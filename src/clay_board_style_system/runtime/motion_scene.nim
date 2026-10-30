## Deterministic CPU scene snapshots. Mutation and publication belong to the UI
## thread; immutable snapshots do not provide a cross-thread transport by themselves.
import std/[algorithm, math, options, tables]

import ../core/[color, geometry]
import ../paint/path_geometry
import ./canvas

const maxMotionSceneObjects* = 65_536

type
  MotionObjectId* = distinct uint64

  MotionShape* = enum
    msRoundedRect, msEllipse, msLine

  MotionLineCap* = enum
    mlcButt, mlcSquare, mlcRound

  MotionObject* = object
    ## A value-type scene shape. IDs are application-owned and nonzero.
    id*: MotionObjectId
    shape*: MotionShape
    bounds*: Rect
    color*: Color
    transform*: Affine2D
    opacity*, radius*: float32
    zIndex*: int32
    visible*, hitTestable*: bool

  MotionSceneEntry = object
    value: MotionObject
    inverse: Option[Affine2D]
    bounds: Rect

  MotionSceneSnapshot* = ref object
    viewport: Size
    entries: seq[MotionSceneEntry]
    order: seq[int]
    byId: Table[uint64, int]

  MotionScene* = ref object
    current: MotionSceneSnapshot
    target: Canvas2D
    generation: uint64
    pending: bool

  MotionSceneUpdate* = object
    ## Opaque latest-request token. Holding it retains the scene, not a UI node.
    scene: MotionScene
    generation: uint64

  MotionSceneUpdateResult* = enum
    msuApplied, msuUnchanged, msuStale

  MotionSceneHit* = object
    id*: MotionObjectId
    localPosition*: Vec2

proc `==`*(a, b: MotionObjectId): bool {.borrow.}
proc `$`*(id: MotionObjectId): string {.borrow.}

proc finite(value: float32): bool =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc finite(value: Affine2D): bool =
  for part in [value.m11, value.m12, value.m21, value.m22, value.tx, value.ty]:
    if not part.finite: return false
  true

proc finite(value: Rect): bool =
  value.x.finite and value.y.finite and value.w.finite and value.h.finite and
    (value.x + value.w).finite and (value.y + value.h).finite

proc motionRect*(
    id: MotionObjectId; bounds: Rect; color: Color;
    transform = identityAffine2D(); opacity = 1.0'f32; radius = 0.0'f32;
    zIndex = 0'i32; visible = true; hitTestable = true
): MotionObject =
  ## Validation happens atomically when a snapshot is constructed.
  MotionObject(id: id, bounds: bounds, color: color, transform: transform,
    shape: msRoundedRect, opacity: opacity, radius: radius, zIndex: zIndex,
    visible: visible, hitTestable: hitTestable)

proc motionEllipse*(
    id: MotionObjectId; bounds: Rect; color: Color;
    transform = identityAffine2D(); opacity = 1.0'f32;
    zIndex = 0'i32; visible = true; hitTestable = true
): MotionObject =
  ## Bounds enclose a filled ellipse in local scene coordinates.
  MotionObject(id: id, shape: msEllipse, bounds: bounds, color: color,
    transform: transform, opacity: opacity, radius: 0.0'f32,
    zIndex: zIndex, visible: visible, hitTestable: hitTestable)

proc motionLine*(
    id: MotionObjectId; startPoint, endPoint: Vec2; width: float32;
    color: Color; cap = mlcRound;
    transform = identityAffine2D(); opacity = 1.0'f32;
    zIndex = 0'i32; visible = true; hitTestable = true
): MotionObject =
  ## A stroked segment represented by the same affine rounded-rectangle
  ## primitive in CPU paint, picking, and GPU instance batches.
  if not startPoint.x.finite or not startPoint.y.finite or
      not endPoint.x.finite or not endPoint.y.finite or
      not width.finite or width <= 0:
    raise newException(ValueError, "motion line endpoints must be finite and width must be positive and finite")
  let dx = endPoint.x.float64 - startPoint.x.float64
  let dy = endPoint.y.float64 - startPoint.y.float64
  let length64 = sqrt(dx * dx + dy * dy)
  if length64 + width.float64 > high(float32).float64:
    raise newException(ValueError, "motion line geometry exceeds float32 range")
  let length = float32(length64)
  let extension = if cap == mlcButt: 0.0'f32 else: width * 0.5'f32
  let basis =
    if length64 == 0.0:
      identityAffine2D()
    else:
      let cosine = float32(dx / length64)
      let sine = float32(dy / length64)
      Affine2D(m11: cosine, m12: sine, m21: -sine, m22: cosine)
  let placement = translationAffine2D(startPoint.x, startPoint.y) * basis
  result = motionRect(
    id, rect(-extension, -width * 0.5'f32,
      length + extension * 2.0'f32, width), color,
    transform = transform * placement, opacity = opacity,
    radius = (if cap == mlcRound: width * 0.5'f32 else: 0.0'f32),
    zIndex = zIndex, visible = visible, hitTestable = hitTestable
  )
  result.shape = msLine

proc motionSceneSnapshot*(
    viewport: Size; objects: openArray[MotionObject]
): MotionSceneSnapshot =
  if not viewport.w.finite or not viewport.h.finite or
      viewport.w <= 0 or viewport.h <= 0:
    raise newException(ValueError, "motion scene viewport must be finite and positive")
  if objects.len > maxMotionSceneObjects:
    raise newException(ValueError, "motion scene object limit exceeded")
  result = MotionSceneSnapshot(viewport: viewport, byId: initTable[uint64, int]())
  for index, authored in objects:
    var value = authored
    if uint64(value.id) == 0 or uint64(value.id) in result.byId:
      raise newException(ValueError, "motion scene IDs must be nonzero and unique")
    if not value.bounds.finite or value.bounds.w < 0 or value.bounds.h < 0 or
        not value.transform.finite or not value.transform.determinant.finite or
        not value.opacity.finite or
        value.opacity < 0 or value.opacity > 1 or not value.radius.finite or
        value.radius < 0:
      raise newException(ValueError, "invalid motion scene geometry or opacity")
    for channel in [value.color.r, value.color.g, value.color.b, value.color.a]:
      if not channel.finite or channel < 0 or channel > 1:
        raise newException(ValueError, "motion scene colors must be in the unit interval")
    # Match Canvas's identity tolerance and rounded clip normalization.
    if value.transform.isIdentity:
      value.transform = identityAffine2D()
    value.radius = min(value.radius, min(value.bounds.w, value.bounds.h) * 0.5'f32)
    if value.shape == msEllipse:
      value.radius = 0.0'f32
    for corner in [vec2(value.bounds.x, value.bounds.y),
        vec2(value.bounds.x + value.bounds.w, value.bounds.y),
        vec2(value.bounds.x, value.bounds.y + value.bounds.h),
        vec2(value.bounds.x + value.bounds.w, value.bounds.y + value.bounds.h)]:
      let mapped = value.transform.transformPoint(corner)
      if not mapped.x.finite or not mapped.y.finite:
        raise newException(ValueError, "motion scene transformed geometry overflow")
    let bounds = value.transform.transformedBounds(value.bounds)
    let inverse = value.transform.inverse
    if not bounds.finite or (inverse.isSome and not inverse.get.finite):
      raise newException(ValueError, "motion scene transformed geometry overflow")
    result.entries.add MotionSceneEntry(value: value, bounds: bounds, inverse: inverse)
    result.order.add index
    result.byId[uint64(value.id)] = index
  let entries = result.entries
  result.order.sort(proc(a, b: int): int =
    result = cmp(entries[a].value.zIndex, entries[b].value.zIndex)
    if result == 0: result = cmp(a, b)
  )

proc objectCount*(snapshot: MotionSceneSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.entries.len

proc viewportSize*(snapshot: MotionSceneSnapshot): Size =
  if snapshot.isNil: size(0, 0) else: snapshot.viewport

proc objectAt*(snapshot: MotionSceneSnapshot; index: int): Option[MotionObject] =
  ## Returns a value copy in authoring order, independent of paint order.
  if snapshot.isNil or index < 0 or index >= snapshot.entries.len:
    return none(MotionObject)
  some(snapshot.entries[index].value)

proc objectById*(snapshot: MotionSceneSnapshot; id: MotionObjectId): Option[MotionObject] =
  if snapshot.isNil or uint64(id) notin snapshot.byId:
    return none(MotionObject)
  snapshot.objectAt(snapshot.byId.getOrDefault(uint64(id)))

proc drawable(entry: MotionSceneEntry): bool =
  entry.value.visible and entry.value.opacity > 0 and entry.value.color.a > 0 and
    entry.value.bounds.w > 0 and entry.value.bounds.h > 0 and entry.inverse.isSome

proc paintObjectAt*(
    snapshot: MotionSceneSnapshot; index: int
): Option[MotionObject] =
  ## Returns a drawable value copy in paint order. Hidden or degenerate objects
  ## occupy their stable position but return none, preserving authoring IDs.
  if snapshot.isNil or index < 0 or index >= snapshot.order.len:
    return none(MotionObject)
  let entry = snapshot.entries[snapshot.order[index]]
  if entry.drawable: some(entry.value) else: none(MotionObject)

proc sameSnapshot(a, b: MotionSceneSnapshot): bool =
  if a == b: return true
  if a.isNil or b.isNil or a.viewport != b.viewport or a.entries.len != b.entries.len:
    return false
  for index in 0 ..< a.entries.len:
    if a.entries[index].value != b.entries[index].value: return false
  true

proc compile(snapshot: MotionSceneSnapshot): seq[CanvasCommand] =
  let target = newCanvas2D()
  target.pushClip(rect(0, 0, snapshot.viewport.w, snapshot.viewport.h))
  for index in snapshot.order:
    let entry = snapshot.entries[index]
    if not entry.drawable: continue
    let value = entry.value
    target.save()
    target.transform(value.transform)
    var color = value.color
    color.a *= value.opacity
    case value.shape
    of msRoundedRect, msLine:
      if value.radius > 0:
        target.pushClip(value.bounds, value.radius)
      target.fillRect(value.bounds, color)
    of msEllipse:
      var path = initPath2D()
      path.ellipse(
        vec2(value.bounds.x + value.bounds.w * 0.5'f32,
          value.bounds.y + value.bounds.h * 0.5'f32),
        value.bounds.w * 0.5'f32, value.bounds.h * 0.5'f32,
        0.0'f32, 0.0'f32, PI.float32 * 2.0'f32)
      path.closePath()
      target.fillPath(path, color)
    target.restore()
  target.popClip()
  target.commands

proc replaceSnapshot*(scene: MotionScene; snapshot: MotionSceneSnapshot): bool {.discardable.} =
  ## Synchronous replacement preserves caller order for deterministic exports.
  ## A direct replacement also cancels any outstanding asynchronous request.
  if scene.isNil or snapshot.isNil:
    raise newException(ValueError, "motion scene and snapshot must not be nil")
  if scene.current.sameSnapshot(snapshot):
    scene.pending = false
    return false
  let commands = snapshot.compile()
  scene.target.clear()
  scene.target.commands = commands
  scene.current = snapshot
  scene.pending = false
  true

proc newMotionScene*(snapshot: MotionSceneSnapshot): MotionScene =
  result = MotionScene(target: newCanvas2D())
  discard result.replaceSnapshot(snapshot)

proc canvas*(scene: MotionScene): Canvas2D =
  ## Borrow for mounting. The scene owns its display list; do not edit commands.
  if scene.isNil: nil else: scene.target

proc snapshot*(scene: MotionScene): MotionSceneSnapshot =
  if scene.isNil: nil else: scene.current

proc revision*(scene: MotionScene): uint64 =
  if scene.isNil: 0'u64 else: scene.target.revision

proc beginUpdate*(scene: MotionScene): MotionSceneUpdate =
  ## Supersedes the preceding request, keeping the last committed image visible.
  if scene.isNil:
    raise newException(ValueError, "motion scene must not be nil")
  if scene.generation == high(uint64):
    raise newException(ValueError, "motion scene update token space exhausted")
  inc scene.generation
  scene.pending = true
  MotionSceneUpdate(scene: scene, generation: scene.generation)

proc isPending*(update: MotionSceneUpdate): bool =
  not update.scene.isNil and update.scene.pending and
    update.generation == update.scene.generation

proc cancel*(update: MotionSceneUpdate): bool {.discardable.} =
  if not update.isPending: return false
  update.scene.pending = false
  true

proc complete*(update: MotionSceneUpdate; snapshot: MotionSceneSnapshot): MotionSceneUpdateResult =
  ## No frame loop or thread transport is created. Call this on the UI thread.
  if not update.isPending: return msuStale
  if update.scene.replaceSnapshot(snapshot): msuApplied else: msuUnchanged

proc hitTest*(snapshot: MotionSceneSnapshot; position: Vec2): Option[MotionSceneHit] =
  if snapshot.isNil or not position.x.finite or not position.y.finite or
      not rect(0, 0, snapshot.viewport.w, snapshot.viewport.h).contains(position):
    return none(MotionSceneHit)
  for offset in countdown(snapshot.order.high, 0):
    let entry = snapshot.entries[snapshot.order[offset]]
    if not entry.drawable or not entry.value.hitTestable or
        not entry.bounds.contains(position): continue
    let point = entry.inverse.get.transformPoint(position)
    let bounds = entry.value.bounds
    if not bounds.contains(point): continue
    case entry.value.shape
    of msRoundedRect, msLine:
      let radius = entry.value.radius
      if radius > 0:
        let x = clamp(point.x, bounds.x + radius, bounds.x + bounds.w - radius)
        let y = clamp(point.y, bounds.y + radius, bounds.y + bounds.h - radius)
        let dx = point.x.float64 - x.float64
        let dy = point.y.float64 - y.float64
        if dx * dx + dy * dy > radius.float64 * radius.float64: continue
    of msEllipse:
      let x = (point.x.float64 - bounds.x.float64) / bounds.w.float64 * 2.0 - 1.0
      let y = (point.y.float64 - bounds.y.float64) / bounds.h.float64 * 2.0 - 1.0
      if x * x + y * y > 1.0: continue
    return some(MotionSceneHit(id: entry.value.id,
      localPosition: vec2(point.x - bounds.x, point.y - bounds.y)))

proc hitTest*(scene: MotionScene; position: Vec2): Option[MotionSceneHit] =
  scene.snapshot.hitTest(position)
