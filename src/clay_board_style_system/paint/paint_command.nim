import std/[math, options, strutils, unicode]
import ../core/[color, computed_style, geometry, node, raster_surface]
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
    pcStrokePath,
    pcDrawText,
    pcDrawImage,
    pcDrawRasterSurface

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
    of pcStrokePath:
      path*: Path2D
      pathColor*: Color
      pathWidth*: float32
      pathLineCap*: StrokeLineCap
      pathLineJoin*: StrokeLineJoin
      pathMiterLimit*: float32
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

proc visualBounds(command: PaintCommand): Option[Rect] =
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
  of pcStrokePath:
    some(command.path.bounds().expanded(max(0.0'f32, command.pathWidth) * 0.5'f32))
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
  of pcPushLayer:
    some(command.layerBounds)
  of pcPushTransform, pcPopTransform, pcPopLayer, pcPushClip, pcPopClip:
    none(Rect)

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
    owner = none(NodeId)
): PaintCommand =
  PaintCommand(
    kind: pcStrokePath,
    owner: owner,
    path: path,
    pathColor: color,
    pathWidth: max(0.0'f32, width),
    pathLineCap: lineCap,
    pathLineJoin: lineJoin,
    pathMiterLimit: max(1.0'f32, miterLimit)
  )

proc strokePath*(
    points: openArray[Vec2];
    color: Color;
    width = 1.0'f32;
    closed = false;
    lineCap = slcButt;
    lineJoin = sljMiter;
    miterLimit = 10.0'f32;
    owner = none(NodeId)
): PaintCommand =
  strokePath(
    path2D(points, closed), color, width, lineCap, lineJoin, miterLimit, owner
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
