import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties
import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/runtime/[motion_scene, motion_scene_ui]

proc item(id: uint64; bounds = rect(0, 0, 12, 12);
    color = rgb(1, 0, 0); zIndex = 0'i32): MotionObject =
  motionRect(MotionObjectId(id), bounds, color, zIndex = zIndex)

proc snap(objects: openArray[MotionObject]): MotionSceneSnapshot =
  motionSceneSnapshot(size(32, 24), objects)

proc pixels(scene: MotionScene): RasterImage =
  render(scene.canvas.paintCommands(NodeId(0), rect(0, 0, 32, 24)), 32, 24, rgb(0, 0, 0))

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b: uint8] =
  let offset = (y * image.width + x) * 3
  (image.pixels[offset], image.pixels[offset + 1], image.pixels[offset + 2])

suite "CPU Motion Scene snapshots":
  test "snapshot copies input and returned values while keeping stable IDs":
    var values = @[item(9), item(2, color = rgb(0, 1, 0))]
    let original = snap(values)
    values[0].bounds.w = 1
    var inspected = original.objectById(MotionObjectId(9)).get
    inspected.color = rgb(0, 0, 1)
    check original.objectById(MotionObjectId(9)).get.bounds.w == 12
    check original.objectAt(0).get.color.r == 1
    check original.objectAt(-1).isNone
    check original.objectAt(2).isNone
    check original.objectById(MotionObjectId(7)).isNone
    let replacement = snap([item(2), item(9, rect(12, 0, 8, 8))])
    check replacement.objectById(MotionObjectId(9)).get.bounds.x == 12
    check original.objectById(MotionObjectId(9)).get.bounds.x == 0

  test "paint and hit order use z-index then authoring order":
    let scene = newMotionScene(snap([
      item(1, color = rgb(1, 0, 0), zIndex = 5),
      item(2, color = rgb(0, 0, 1), zIndex = -1),
      item(3, color = rgb(0, 1, 0), zIndex = 5)]))
    check scene.pixels.pixel(3, 3) == (0'u8, 255'u8, 0'u8)
    check scene.hitTest(vec2(3, 3)).get.id == MotionObjectId(3)
    discard scene.replaceSnapshot(snap([item(3, color = rgb(0, 1, 0)), item(1)]))
    check scene.pixels.pixel(3, 3) == (255'u8, 0'u8, 0'u8)
    check scene.hitTest(vec2(3, 3)).get.id == MotionObjectId(1)

  test "rounded transformed rectangles agree with inverse-space hit testing":
    var shape = item(1, rect(0, 0, 10, 10))
    shape.radius = 5
    shape.transform = translationAffine2D(16, 2) * rotationAffine2D(PI.float32 / 2)
    let scene = newMotionScene(snap([shape]))
    check scene.pixels.pixel(11, 7).r == 255
    check scene.pixels.pixel(6, 2).r == 0
    let hit = scene.hitTest(vec2(11, 7))
    require hit.isSome
    check abs(hit.get.localPosition.x - 5) < 0.001
    check abs(hit.get.localPosition.y - 5) < 0.001
    check scene.hitTest(vec2(6.1, 2.1)).isNone

  test "viewport clips drawing and picking while opacity preserves composition":
    var shape = item(1, rect(0, 0, 30, 20))
    shape.opacity = 0.5
    let scene = newMotionScene(motionSceneSnapshot(size(8, 8), [shape]))
    let image = scene.pixels
    check abs(int(image.pixel(2, 2).r) - 128) <= 1
    check image.pixel(9, 2).r == 0
    check scene.hitTest(vec2(2, 2)).isSome
    check scene.hitTest(vec2(8, 2)).isNone
    check scene.hitTest(vec2(NaN.float32, 0)).isNone

  test "hidden transparent empty and singular objects are neither painted nor picked":
    var hidden = item(1)
    hidden.visible = false
    var transparent = item(2)
    transparent.opacity = 0
    var alpha = item(3)
    alpha.color.a = 0
    var empty = item(4, rect(0, 0, 0, 10))
    var singular = item(5)
    singular.transform = scaleAffine2D(0, 1)
    let scene = newMotionScene(snap([hidden, transparent, alpha, empty, singular]))
    check scene.snapshot.objectCount == 5
    check scene.pixels.pixel(2, 2) == (0'u8, 0'u8, 0'u8)
    check scene.hitTest(vec2(2, 2)).isNone
    var visualOnly = item(6)
    visualOnly.hitTestable = false
    discard scene.replaceSnapshot(snap([visualOnly]))
    check scene.pixels.pixel(2, 2).r == 255
    check scene.hitTest(vec2(2, 2)).isNone

  test "equal replacement retains revision and synchronous updates preserve order":
    let scene = newMotionScene(snap([item(1)]))
    let revision = scene.revision
    check not scene.replaceSnapshot(snap([item(1)]))
    check scene.revision == revision
    for color in [rgb(0, 1, 0), rgb(0, 0, 1), rgb(1, 0, 0)]:
      check scene.replaceSnapshot(snap([item(1, color = color)]))
      check scene.snapshot.objectById(MotionObjectId(1)).get.color == color
    check scene.revision == revision + 3

  test "latest request wins and cancelled or completed tokens cannot publish":
    let scene = newMotionScene(snap([item(1)]))
    let first = scene.beginUpdate()
    let second = scene.beginUpdate()
    check not first.isPending
    check first.complete(snap([item(2)])) == msuStale
    check scene.snapshot.objectById(MotionObjectId(1)).isSome
    check second.complete(snap([item(3)])) == msuApplied
    check second.complete(snap([item(4)])) == msuStale
    let revision = scene.revision
    let cancelled = scene.beginUpdate()
    check cancelled.cancel()
    check not cancelled.cancel()
    check cancelled.complete(snap([item(5)])) == msuStale
    check scene.revision == revision
    let equal = scene.beginUpdate()
    check equal.complete(snap([item(3)])) == msuUnchanged
    check not equal.isPending
    let direct = scene.beginUpdate()
    check not scene.replaceSnapshot(scene.snapshot)
    check direct.complete(snap([item(6)])) == msuStale

  test "tokens cannot affect another scene and invalid completion is retryable":
    let first = newMotionScene(snap([item(1)]))
    let second = newMotionScene(snap([item(2)]))
    let token = first.beginUpdate()
    let unrelated = second.beginUpdate()
    expect ValueError: discard token.complete(nil)
    check token.isPending
    check unrelated.isPending
    check token.complete(snap([item(3)])) == msuApplied
    check unrelated.isPending
    check second.snapshot.objectById(MotionObjectId(2)).isSome
    check MotionSceneUpdate().complete(nil) == msuStale

  test "invalid snapshots reject duplicate IDs and unsafe numeric data":
    expect ValueError: discard snap([item(0)])
    expect ValueError: discard snap([item(1), item(1)])
    expect ValueError: discard motionSceneSnapshot(size(0, 10), [])
    expect ValueError: discard motionSceneSnapshot(size(Inf.float32, 10), [])
    for bad in [NaN.float32, Inf.float32, NegInf.float32]:
      var shape = item(1)
      shape.bounds.x = bad
      expect ValueError: discard snap([shape])
      shape = item(1)
      shape.transform.m11 = bad
      expect ValueError: discard snap([shape])
      shape = item(1)
      shape.opacity = bad
      expect ValueError: discard snap([shape])
      shape = item(1)
      shape.radius = bad
      expect ValueError: discard snap([shape])
      shape = item(1)
      shape.color.a = bad
      expect ValueError: discard snap([shape])
    var shape = item(1)
    shape.transform = scaleAffine2D(high(float32), high(float32))
    expect ValueError: discard snap([shape])
    shape = item(1, rect(0, 0, -1, 2))
    expect ValueError: discard snap([shape])
    shape = item(1)
    shape.opacity = 1.1
    expect ValueError: discard snap([shape])
    shape = item(1)
    shape.color.r = -0.1
    expect ValueError: discard snap([shape])
    var oversized = newSeq[MotionObject](maxMotionSceneObjects + 1)
    expect ValueError: discard snap(oversized)

  test "many objects mount as one idle Canvas and publication only dirties paint":
    var values: seq[MotionObject]
    for index in 0 ..< 10_000:
      values.add item(uint64(index + 1), rect(float32(index mod 100), float32(index div 100), 1, 1))
    let scene = newMotionScene(motionSceneSnapshot(size(100, 100), values))
    let ui = initUiRoot()
    let handle = ui.motionScene(scene, uiStyle([decl("width", px(100)), decl("height", px(100))]))
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    let layout = computeLayout(ui.tree, styles, size(100, 100))
    ui.syncRenderSurfaces(styles, layout)
    check not diagnostics.hasErrors
    check layout.boxes.len == 1
    check ui.surfaces.surfaceState(handle.attachment.surface) == rssMounted
    check ui.tree.nodes.len == 1
    check scene.snapshot.objectCount == 10_000
    discard ui.consumeInvalidation()
    check not handle.publish()
    check not ui.surfaces.needsSurfaceFrame
    values[0].color = rgb(0, 1, 0)
    discard scene.replaceSnapshot(motionSceneSnapshot(size(100, 100), values))
    check handle.publish()
    let dirty = ui.consumeInvalidation()
    check dirty.domains == {ddPaint}
    check dirty.roots == @[handle.nodeHandle.id]
    check not handle.publish()
    check not ui.surfaces.needsSurfaceFrame
    check scene.hitTest(vec2(0.5, 0.5)).get.id == MotionObjectId(1)
    var interaction = initInteractionState()
    check ui.disposeSubtree(handle.nodeHandle, interaction)
    check not handle.valid
    check not handle.publish()

  test "shared scene attachments publish independently without a frame loop":
    let scene = newMotionScene(snap([item(1)]))
    let ui = initUiRoot()
    let first = ui.motionScene(scene)
    let second = ui.motionScene(scene)
    discard ui.consumeInvalidation()
    discard scene.replaceSnapshot(snap([item(2)]))
    check first.publish()
    check not first.publish()
    check ui.consumeInvalidation().roots == @[first.nodeHandle.id]
    check second.publish()
    check ui.consumeInvalidation().roots == @[second.nodeHandle.id]
    check not ui.surfaces.needsSurfaceFrame
