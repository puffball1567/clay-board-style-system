import std/[math, options, strutils, unicode]
import ../core/[color, computed_style, geometry, node, raster_surface]
import ../runtime/gpu_direct_surface
import ./path_geometry

type
  LayerCompositeMode* = enum
    lcmSourceOver,
    lcmCopy,
    lcmAdditive

  PaintCommandKind* = enum
    pcPushTransform,
    pcPopTransform,
    pcPushLayer,
    pcPopLayer,
    pcPushClip,
    pcPopClip,
    pcBoxShadow,
    pcFillRect,
    pcFillLinearGradient,
    pcStrokeRect,
    pcFillPath,
    pcStrokePath,
    pcDrawText,
    pcDrawImage,
    pcDrawRasterSurface,
    pcDrawGpuDirectSurface

  PaintCommand* = object
    owner*: Option[NodeId]
    case kind*: PaintCommandKind
    of pcPushTransform:
      transform*: Affine2D
      transformBounds*: Rect
    of pcPopTransform:
      discard
    of pcPushLayer:
      layerBounds*: Rect
      layerOpacity*: float32
      layerCompositeMode*: LayerCompositeMode
    of pcPopLayer:
      discard
    of pcPushClip:
      clipRect*: Rect
      clipRadius*: float32
    of pcPopClip:
      discard
    of pcBoxShadow:
      shadowRect*: Rect
      shadowColor*: Color
      shadowOffsetX*, shadowOffsetY*: float32
      shadowBlur*, shadowSpread*: float32
      shadowRadius*: float32
    of pcFillRect:
      rect*: Rect
      color*: Color
      radius*: float32
    of pcFillLinearGradient:
      gradientRect*: Rect
      gradientPaintRect*: Rect
      gradientClipRect*: Rect
      gradient*: LinearGradient
      gradientRadius*: float32
      gradientRepeat*: BackgroundRepeat
    of pcStrokeRect:
      strokeRect*: Rect
      strokeColor*: Color
      strokeWidth*: float32
      strokeRadius*: float32
    of pcFillPath:
      fillPathValue*: Path2D
      fillPathColor*: Color
      fillPathRule*: PathFillRule
    of pcStrokePath:
      path*: Path2D
      pathOutline*: Path2D
      pathColor*: Color
      pathWidth*: float32
      pathLineCap*: StrokeLineCap
      pathLineJoin*: StrokeLineJoin
      pathMiterLimit*: float32
      pathDashPattern*: seq[float32]
      pathDashOffset*: float32
    of pcDrawText:
      node*: NodeId
      text*: string
      position*: Vec2
      textMaxWidth*: Option[float32]
      textColor*: Color
      textStyle*: ComputedTextStyle
    of pcDrawImage:
      imageNode*: NodeId
      imageSource*: string
      imageRect*: Rect
      imageOpacity*: float32
      imageStyle*: ComputedImageStyle
    of pcDrawRasterSurface:
      rasterSurface*: RasterSurface
      rasterRect*: Rect
      rasterOpacity*: float32
    of pcDrawGpuDirectSurface:
      gpuDirectSurface*: GpuDirectSurface
      gpuSurfaceRect*: Rect
      gpuSurfaceOpacity*: float32

proc fillRect*(rect: Rect; color: Color; radius: float32 = 0; owner = none(NodeId)): PaintCommand =
  PaintCommand(kind: pcFillRect, owner: owner, rect: rect, color: color, radius: radius)

proc pushTransform*(transform: Affine2D; bounds = rect(0, 0, 0, 0)): PaintCommand =
  PaintCommand(kind: pcPushTransform, transform: transform, transformBounds: bounds)

proc popTransform*(): PaintCommand =
  PaintCommand(kind: pcPopTransform)

proc pushLayer*(
    bounds: Rect;
    opacity = 1.0'f32;
    compositeMode = lcmSourceOver
): PaintCommand =
  PaintCommand(
    kind: pcPushLayer,
    layerBounds: bounds,
    layerOpacity: clamp(opacity, 0.0'f32, 1.0'f32),
    layerCompositeMode: compositeMode
  )

proc popLayer*(): PaintCommand =
  PaintCommand(kind: pcPopLayer)

type TransformBoundsFrame = object
  commandIndex: int
  bounds: Option[Rect]

proc expanded(bounds: Rect; amount: float32): Rect =
  rect(
    bounds.x - amount,
    bounds.y - amount,
    max(0.0'f32, bounds.w + amount * 2.0'f32),
    max(0.0'f32, bounds.h + amount * 2.0'f32)
  )

proc includeBounds(bounds: var Option[Rect]; value: Rect) =
  if value.isEmpty:
    return
  if bounds.isNone:
    bounds = some(value)
    return
  let current = bounds.get
  let left = min(current.x, value.x)
  let top = min(current.y, value.y)
  let right = max(current.x + current.w, value.x + value.w)
  let bottom = max(current.y + current.h, value.y + value.h)
  bounds = some(rect(left, top, right - left, bottom - top))

proc visualBounds*(command: PaintCommand): Option[Rect] =
  case command.kind
  of pcBoxShadow:
    let blur = max(0.0'f32, command.shadowBlur)
    let grow = command.shadowSpread + blur
    some(rect(
      command.shadowRect.x + command.shadowOffsetX - grow,
      command.shadowRect.y + command.shadowOffsetY - grow,
      max(0.0'f32, command.shadowRect.w + grow * 2.0'f32),
      max(0.0'f32, command.shadowRect.h + grow * 2.0'f32)
    ))
  of pcFillRect:
    some(command.rect)
  of pcFillLinearGradient:
    some(command.gradientPaintRect)
  of pcStrokeRect:
    some(command.strokeRect.expanded(max(0.0'f32, command.strokeWidth) * 0.5'f32))
  of pcFillPath:
    some(command.fillPathValue.bounds())
  of pcStrokePath:
    some(command.pathOutline.bounds())
  of pcDrawText:
    let fontSize =
      if command.textStyle.fontSize.isSome: command.textStyle.fontSize.get
      else: 14.0'f32
    let lineHeight =
      if command.textStyle.lineHeight.isSome: command.textStyle.lineHeight.get
      else: fontSize * 1.25'f32
    let lineCount = max(1, command.text.count('\n') + 1)
    let width =
      if command.textMaxWidth.isSome: command.textMaxWidth.get
      else: max(fontSize, command.text.runeLen.float32 * fontSize * 0.7'f32)
    let authoredIndent = command.textStyle.textIndent.get(0.0'f32)
    let indent =
      if authoredIndent.classify in {fcNan, fcInf, fcNegInf}: 0.0'f32
      else: authoredIndent
    let leftOffset = min(0.0'f32, indent)
    let rightOffset =
      if command.textMaxWidth.isSome: 0.0'f32
      else: max(0.0'f32, indent)
    some(rect(
      command.position.x + leftOffset,
      command.position.y,
      width - leftOffset + rightOffset,
      lineHeight * lineCount.float32
    ))
  of pcDrawImage:
    some(command.imageRect)
  of pcDrawRasterSurface:
    some(command.rasterRect)
  of pcDrawGpuDirectSurface:
    some(command.gpuSurfaceRect)
  of pcPushLayer:
    some(command.layerBounds)
  of pcPushTransform, pcPopTransform, pcPopLayer, pcPushClip, pcPopClip:
    none(Rect)

proc isPaintScopeCommand*(command: PaintCommand): bool {.inline.} =
  command.kind in {
    pcPushTransform, pcPopTransform, pcPushLayer, pcPopLayer,
    pcPushClip, pcPopClip
  }

proc hasConservativeDamageBounds*(command: PaintCommand): bool {.inline.} =
  ## Text metrics and shadows are backend-shaped, so text changes must fall
  ## back to full damage until the canonical text raster bounds are retained.
  command.kind notin {
    pcPushTransform, pcPopTransform, pcPushLayer, pcPopLayer,
    pcPushClip, pcPopClip, pcDrawText
  }

proc samePaintCommand*(first, second: PaintCommand): bool =
  ## Case-object equality is not generated by Nim. Keep this exact comparison
  ## next to the command definition so retained backends share one contract.
  if first.kind != second.kind or first.owner != second.owner:
    return false
  case first.kind
  of pcPushTransform:
    first.transform == second.transform and
      first.transformBounds == second.transformBounds
  of pcPopTransform, pcPopLayer, pcPopClip:
    true
  of pcPushLayer:
    first.layerBounds == second.layerBounds and
      first.layerOpacity == second.layerOpacity and
      first.layerCompositeMode == second.layerCompositeMode
  of pcPushClip:
    first.clipRect == second.clipRect and first.clipRadius == second.clipRadius
  of pcBoxShadow:
    first.shadowRect == second.shadowRect and
      first.shadowColor == second.shadowColor and
      first.shadowOffsetX == second.shadowOffsetX and
      first.shadowOffsetY == second.shadowOffsetY and
      first.shadowBlur == second.shadowBlur and
      first.shadowSpread == second.shadowSpread and
      first.shadowRadius == second.shadowRadius
  of pcFillRect:
    first.rect == second.rect and first.color == second.color and
      first.radius == second.radius
  of pcFillLinearGradient:
    first.gradientRect == second.gradientRect and
      first.gradientPaintRect == second.gradientPaintRect and
      first.gradientClipRect == second.gradientClipRect and
      first.gradient == second.gradient and
      first.gradientRadius == second.gradientRadius and
      first.gradientRepeat == second.gradientRepeat
  of pcStrokeRect:
    first.strokeRect == second.strokeRect and
      first.strokeColor == second.strokeColor and
      first.strokeWidth == second.strokeWidth and
      first.strokeRadius == second.strokeRadius
  of pcFillPath:
    first.fillPathValue == second.fillPathValue and
      first.fillPathColor == second.fillPathColor and
      first.fillPathRule == second.fillPathRule
  of pcStrokePath:
    first.path == second.path and first.pathOutline == second.pathOutline and
      first.pathColor == second.pathColor and
      first.pathWidth == second.pathWidth and
      first.pathLineCap == second.pathLineCap and
      first.pathLineJoin == second.pathLineJoin and
      first.pathMiterLimit == second.pathMiterLimit and
      first.pathDashPattern == second.pathDashPattern and
      first.pathDashOffset == second.pathDashOffset
  of pcDrawText:
    first.node == second.node and first.text == second.text and
      first.position == second.position and
      first.textMaxWidth == second.textMaxWidth and
      first.textColor == second.textColor and
      first.textStyle == second.textStyle
  of pcDrawImage:
    first.imageNode == second.imageNode and
      first.imageSource == second.imageSource and
      first.imageRect == second.imageRect and
      first.imageOpacity == second.imageOpacity and
      first.imageStyle == second.imageStyle
  of pcDrawRasterSurface:
    first.rasterSurface == second.rasterSurface and
      first.rasterRect == second.rasterRect and
      first.rasterOpacity == second.rasterOpacity
  of pcDrawGpuDirectSurface:
    first.gpuDirectSurface == second.gpuDirectSurface and
      first.gpuSurfaceRect == second.gpuSurfaceRect and
      first.gpuSurfaceOpacity == second.gpuSurfaceOpacity

proc resolvedVisualBounds*(commands: openArray[PaintCommand]): seq[Option[Rect]] =
  ## Resolves conservative destination-space bounds while replaying retained
  ## transform and rectangular clip scopes. The result is index-aligned with
  ## the input command stream.
  result = newSeq[Option[Rect]](commands.len)
  var transforms = @[identityAffine2D()]
  var clips: seq[Rect]
  var layerClipDepths: seq[int]
  for index, command in commands:
    case command.kind
    of pcPushTransform:
      transforms.add transforms[^1] * command.transform
    of pcPopTransform:
      if transforms.len > 1:
        discard transforms.pop()
    of pcPushClip:
      var transformed = transforms[^1].transformedBounds(command.clipRect)
      if clips.len > 0:
        transformed = transformed.intersection(clips[^1])
      clips.add transformed
    of pcPopClip:
      if clips.len > 0:
        discard clips.pop()
    of pcPushLayer:
      layerClipDepths.add clips.len
      var transformed = transforms[^1].transformedBounds(command.layerBounds)
      if clips.len > 0:
        transformed = transformed.intersection(clips[^1])
      clips.add transformed
    of pcPopLayer:
      if layerClipDepths.len > 0:
        clips.setLen(layerClipDepths.pop())
    else:
      let local = command.visualBounds()
      if local.isSome:
        var bounds = transforms[^1].transformedBounds(local.get)
        if clips.len > 0:
          bounds = bounds.intersection(clips[^1])
        if not bounds.isEmpty:
          result[index] = some(bounds)

proc resolvedVisualBoundsFor*(
    commands: openArray[PaintCommand];
    commandIndex: int;
    localBounds: Rect
): Option[Rect] =
  ## Resolves a subregion of one command through the scopes active at that
  ## command. Retained resources use this to map source dirty rectangles into
  ## destination-space tiles without invalidating the whole resource bounds.
  if commandIndex < 0 or commandIndex >= commands.len or localBounds.isEmpty:
    return none(Rect)
  var transforms = @[identityAffine2D()]
  var clips: seq[Rect]
  var layerClipDepths: seq[int]
  for index in 0 .. commandIndex:
    let command = commands[index]
    if index == commandIndex:
      var bounds = transforms[^1].transformedBounds(localBounds)
      if clips.len > 0:
        bounds = bounds.intersection(clips[^1])
      if not bounds.isEmpty:
        return some(bounds)
      return none(Rect)
    case command.kind
    of pcPushTransform:
      transforms.add transforms[^1] * command.transform
    of pcPopTransform:
      if transforms.len > 1:
        discard transforms.pop()
    of pcPushClip:
      var transformed = transforms[^1].transformedBounds(command.clipRect)
      if clips.len > 0:
        transformed = transformed.intersection(clips[^1])
      clips.add transformed
    of pcPopClip:
      if clips.len > 0:
        discard clips.pop()
    of pcPushLayer:
      layerClipDepths.add clips.len
      var transformed = transforms[^1].transformedBounds(command.layerBounds)
      if clips.len > 0:
        transformed = transformed.intersection(clips[^1])
      clips.add transformed
    of pcPopLayer:
      if layerClipDepths.len > 0:
        clips.setLen(layerClipDepths.pop())
    else:
      discard

proc resolveTransformBounds*(commands: var seq[PaintCommand]) =
  ## Annotates generated transform scopes with their source-space visual bounds.
  ## Render backends can therefore allocate compact intermediate surfaces.
  var stack: seq[TransformBoundsFrame]
  for index in 0 ..< commands.len:
    case commands[index].kind
    of pcPushTransform:
      stack.add TransformBoundsFrame(commandIndex: index)
    of pcPopTransform:
      if stack.len == 0:
        continue
      let frame = stack.pop()
      if frame.bounds.isSome:
        commands[frame.commandIndex].transformBounds = frame.bounds.get
        if stack.len > 0:
          stack[^1].bounds.includeBounds(
            commands[frame.commandIndex].transform.transformedBounds(frame.bounds.get)
          )
    else:
      if stack.len > 0:
        let bounds = commands[index].visualBounds()
        if bounds.isSome:
          stack[^1].bounds.includeBounds(bounds.get)

proc fillLinearGradient*(
    rect: Rect;
    gradient: LinearGradient;
    radius: float32 = 0;
    owner = none(NodeId);
    paintRect = none(Rect);
    clipRect = none(Rect);
    repeat = bgNoRepeat
): PaintCommand =
  let resolvedPaintRect = paintRect.get(rect)
  PaintCommand(
    kind: pcFillLinearGradient,
    owner: owner,
    gradientRect: rect,
    gradientPaintRect: resolvedPaintRect,
    gradientClipRect: clipRect.get(resolvedPaintRect),
    gradient: gradient,
    gradientRadius: radius,
    gradientRepeat: repeat
  )

proc pushClip*(rect: Rect; radius: float32 = 0): PaintCommand =
  PaintCommand(kind: pcPushClip, clipRect: rect, clipRadius: radius)

proc popClip*(): PaintCommand =
  PaintCommand(kind: pcPopClip)

proc drawBoxShadow*(
    rect: Rect;
    color: Color;
    offsetX, offsetY, blur, spread: float32;
    radius: float32 = 0;
    owner = none(NodeId)
): PaintCommand =
  PaintCommand(
    kind: pcBoxShadow,
    owner: owner,
    shadowRect: rect,
    shadowColor: color,
    shadowOffsetX: offsetX,
    shadowOffsetY: offsetY,
    shadowBlur: blur,
    shadowSpread: spread,
    shadowRadius: radius
  )

proc strokeRect*(rect: Rect; color: Color; width: float32; radius: float32 = 0; owner = none(NodeId)): PaintCommand =
  PaintCommand(kind: pcStrokeRect, owner: owner, strokeRect: rect, strokeColor: color, strokeWidth: width, strokeRadius: radius)

proc strokePath*(
    path: Path2D;
    color: Color;
    width = 1.0'f32;
    lineCap = slcButt;
    lineJoin = sljMiter;
    miterLimit = 10.0'f32;
    owner = none(NodeId);
    dashPattern: openArray[float32] = [];
    dashOffset = 0.0'f32
): PaintCommand =
  let normalizedWidth =
    if width.classify in {fcNan, fcInf, fcNegInf}: 0.0'f32
    else: max(0.0'f32, width)
  let normalizedMiterLimit =
    if miterLimit.classify in {fcNan, fcInf, fcNegInf}: 1.0'f32
    else: max(1.0'f32, miterLimit)
  let normalizedDashPattern = normalizeDashPattern(dashPattern)
  let normalizedDashOffset =
    if dashOffset.classify in {fcNan, fcInf, fcNegInf}: 0.0'f32
    else: dashOffset
  PaintCommand(
    kind: pcStrokePath,
    owner: owner,
    path: path,
    pathOutline: path.strokeOutline(
      normalizedWidth, lineCap, lineJoin, normalizedMiterLimit,
      dashPattern = normalizedDashPattern,
      dashOffset = normalizedDashOffset
    ),
    pathColor: color,
    pathWidth: normalizedWidth,
    pathLineCap: lineCap,
    pathLineJoin: lineJoin,
    pathMiterLimit: normalizedMiterLimit,
    pathDashPattern: normalizedDashPattern,
    pathDashOffset: normalizedDashOffset
  )

proc fillPath*(
    path: Path2D;
    color: Color;
    fillRule = pfrNonZero;
    owner = none(NodeId)
): PaintCommand =
  PaintCommand(
    kind: pcFillPath,
    owner: owner,
    fillPathValue: path,
    fillPathColor: color,
    fillPathRule: fillRule
  )

proc strokePath*(
    points: openArray[Vec2];
    color: Color;
    width = 1.0'f32;
    closed = false;
    lineCap = slcButt;
    lineJoin = sljMiter;
    miterLimit = 10.0'f32;
    owner = none(NodeId);
    dashPattern: openArray[float32] = [];
    dashOffset = 0.0'f32
): PaintCommand =
  strokePath(
    path2D(points, closed), color, width, lineCap, lineJoin, miterLimit,
    owner, dashPattern, dashOffset
  )

proc drawText*(node: NodeId; text: string; position: Vec2; color: Color; style: ComputedTextStyle; maxWidth = none(float32)): PaintCommand =
  PaintCommand(kind: pcDrawText, owner: some(node), node: node, text: text, position: position, textMaxWidth: maxWidth, textColor: color, textStyle: style)

proc drawImage*(node: NodeId; source: string; rect: Rect; opacity: float32; style: ComputedImageStyle): PaintCommand =
  PaintCommand(kind: pcDrawImage, owner: some(node), imageNode: node, imageSource: source, imageRect: rect, imageOpacity: opacity, imageStyle: style)

proc drawRasterSurface*(
    node: NodeId;
    surface: RasterSurface;
    bounds: Rect;
    opacity = 1.0'f32
): PaintCommand =
  if surface.isNil:
    raise newException(ValueError, "raster surface cannot be nil")
  PaintCommand(
    kind: pcDrawRasterSurface,
    owner: some(node),
    rasterSurface: surface,
    rasterRect: bounds,
    rasterOpacity: clamp(opacity, 0.0'f32, 1.0'f32)
  )

proc drawGpuDirectSurface*(
    node: NodeId;
    surface: GpuDirectSurface;
    bounds: Rect;
    opacity = 1.0'f32
): PaintCommand =
  if surface.isNil or surface.isClosed:
    raise newException(ValueError, "GPU direct surface cannot be nil or closed")
  PaintCommand(
    kind: pcDrawGpuDirectSurface,
    owner: some(node),
    gpuDirectSurface: surface,
    gpuSurfaceRect: bounds,
    gpuSurfaceOpacity: clamp(opacity, 0.0'f32, 1.0'f32)
  )
