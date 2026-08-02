import std/options

import ../core/[color, computed_style, geometry, node]
import ../paint/[paint_command, path_geometry]
import ./render_surface

type
  CanvasCommandKind* = enum
    cckPushClip,
    cckPopClip,
    cckFillRect,
    cckFillLinearGradient,
    cckStrokeRect,
    cckStrokePath,
    cckDrawText,
    cckDrawImage

  CanvasCommand* = object
    case kind*: CanvasCommandKind
    of cckPushClip:
      clipRect*: Rect
      clipRadius*: float32
    of cckPopClip:
      discard
    of cckFillRect:
      fillRect*: Rect
      fillColor*: Color
      fillRadius*: float32
    of cckFillLinearGradient:
      gradientRect*: Rect
      gradient*: LinearGradient
      gradientRadius*: float32
    of cckStrokeRect:
      strokeRect*: Rect
      strokeColor*: Color
      strokeWidth*: float32
      strokeRadius*: float32
    of cckStrokePath:
      path*: Path2D
      pathColor*: Color
      pathWidth*: float32
      pathLineCap*: StrokeLineCap
      pathLineJoin*: StrokeLineJoin
      pathMiterLimit*: float32
    of cckDrawText:
      text*: string
      textPosition*: Vec2
      textMaxWidth*: Option[float32]
      textColor*: Color
      textStyle*: ComputedTextStyle
    of cckDrawImage:
      imageSource*: string
      imageRect*: Rect
      imageOpacity*: float32
      imageStyle*: ComputedImageStyle

  Canvas2D* = ref object
    commands*: seq[CanvasCommand]
    revision*: uint64
    onInput*: proc(canvas: Canvas2D; event: RenderSurfaceInput): bool {.closure.}
    onFrame*: proc(canvas: Canvas2D; frame: RenderSurfaceFrame): RenderSurfaceFrameResult {.closure.}

proc newCanvas2D*(): Canvas2D =
  Canvas2D(commands: @[], revision: 1)

proc touch(canvas: Canvas2D) =
  if canvas.revision == high(uint64):
    canvas.revision = 1
  else:
    inc canvas.revision

proc clear*(canvas: Canvas2D) =
  canvas.commands.setLen(0)
  canvas.touch()

proc pushClip*(canvas: Canvas2D; bounds: Rect; radius = 0.0'f32) =
  canvas.commands.add CanvasCommand(
    kind: cckPushClip,
    clipRect: bounds,
    clipRadius: max(0.0'f32, radius)
  )
  canvas.touch()

proc popClip*(canvas: Canvas2D) =
  canvas.commands.add CanvasCommand(kind: cckPopClip)
  canvas.touch()

proc fillRect*(
    canvas: Canvas2D;
    bounds: Rect;
    color: Color;
    radius = 0.0'f32
) =
  canvas.commands.add CanvasCommand(
    kind: cckFillRect,
    fillRect: bounds,
    fillColor: color,
    fillRadius: max(0.0'f32, radius)
  )
  canvas.touch()

proc fillLinearGradient*(
    canvas: Canvas2D;
    bounds: Rect;
    gradient: LinearGradient;
    radius = 0.0'f32
) =
  canvas.commands.add CanvasCommand(
    kind: cckFillLinearGradient,
    gradientRect: bounds,
    gradient: gradient,
    gradientRadius: max(0.0'f32, radius)
  )
  canvas.touch()

proc strokeRect*(
    canvas: Canvas2D;
    bounds: Rect;
    color: Color;
    width = 1.0'f32;
    radius = 0.0'f32
) =
  canvas.commands.add CanvasCommand(
    kind: cckStrokeRect,
    strokeRect: bounds,
    strokeColor: color,
    strokeWidth: max(0.0'f32, width),
    strokeRadius: max(0.0'f32, radius)
  )
  canvas.touch()

proc strokePath*(
    canvas: Canvas2D;
    path: Path2D;
    color: Color;
    width = 1.0'f32;
    lineCap = slcButt;
    lineJoin = sljMiter;
    miterLimit = 10.0'f32
) =
  ## Adds a retained path in Canvas-local coordinates. Empty paths are
  ## retained safely but produce no paint command.
  canvas.commands.add CanvasCommand(
    kind: cckStrokePath,
    path: path,
    pathColor: color,
    pathWidth: max(0.0'f32, width),
    pathLineCap: lineCap,
    pathLineJoin: lineJoin,
    pathMiterLimit: max(1.0'f32, miterLimit)
  )
  canvas.touch()

proc strokePath*(
    canvas: Canvas2D;
    points: openArray[Vec2];
    color: Color;
    width = 1.0'f32;
    closed = false;
    lineCap = slcButt;
    lineJoin = sljMiter;
    miterLimit = 10.0'f32
) =
  canvas.strokePath(
    path2D(points, closed), color, width, lineCap, lineJoin, miterLimit
  )

proc strokeLine*(
    canvas: Canvas2D;
    startPoint, endPoint: Vec2;
    color: Color;
    width = 1.0'f32;
    lineCap = slcButt
) =
  canvas.strokePath(
    [startPoint, endPoint], color, width, lineCap = lineCap
  )

proc drawText*(
    canvas: Canvas2D;
    text: string;
    position: Vec2;
    color: Color;
    style: ComputedTextStyle;
    maxWidth = none(float32)
) =
  canvas.commands.add CanvasCommand(
    kind: cckDrawText,
    text: text,
    textPosition: position,
    textMaxWidth: maxWidth,
    textColor: color,
    textStyle: style
  )
  canvas.touch()

proc drawImage*(
    canvas: Canvas2D;
    source: string;
    bounds: Rect;
    opacity = 1.0'f32;
    style = ComputedImageStyle()
) =
  canvas.commands.add CanvasCommand(
    kind: cckDrawImage,
    imageSource: source,
    imageRect: bounds,
    imageOpacity: max(0.0'f32, min(1.0'f32, opacity)),
    imageStyle: style
  )
  canvas.touch()

proc withOpacity(color: Color; opacity: float32): Color =
  rgba(color.r, color.g, color.b, color.a * opacity)

proc withOpacity(gradient: LinearGradient; opacity: float32): LinearGradient =
  result = gradient
  result.stops.setLen(0)
  for stop in gradient.stops:
    result.stops.add colorStop(stop.color.withOpacity(opacity), stop.offset)

proc paintCommands*(
    canvas: Canvas2D;
    owner: NodeId;
    bounds: Rect;
    opacity = 1.0'f32
): seq[PaintCommand] =
  ## Convert retained local commands at the paint boundary. The display list
  ## remains independent of window placement and can be reused after layout,
  ## scrolling, or DPI changes without being rebuilt.
  let offset = vec2(bounds.x, bounds.y)
  result = newSeqOfCap[PaintCommand](canvas.commands.len + 8)
  var clipDepth = 0
  for command in canvas.commands:
    case command.kind
    of cckPushClip:
      result.add pushClip(command.clipRect.translated(offset), command.clipRadius)
      inc clipDepth
    of cckPopClip:
      if clipDepth > 0:
        result.add popClip()
        dec clipDepth
    of cckFillRect:
      result.add fillRect(
        command.fillRect.translated(offset),
        command.fillColor.withOpacity(opacity),
        command.fillRadius,
        some(owner)
      )
    of cckFillLinearGradient:
      result.add fillLinearGradient(
        command.gradientRect.translated(offset),
        command.gradient.withOpacity(opacity),
        command.gradientRadius,
        some(owner)
      )
    of cckStrokeRect:
      result.add strokeRect(
        command.strokeRect.translated(offset),
        command.strokeColor.withOpacity(opacity),
        command.strokeWidth,
        command.strokeRadius,
        some(owner)
      )
    of cckStrokePath:
      if command.path.drawable and command.pathWidth > 0:
        result.add strokePath(
          command.path.translated(offset),
          command.pathColor.withOpacity(opacity),
          command.pathWidth,
          command.pathLineCap,
          command.pathLineJoin,
          command.pathMiterLimit,
          some(owner)
        )
    of cckDrawText:
      result.add drawText(
        owner,
        command.text,
        command.textPosition.translated(offset),
        command.textColor.withOpacity(opacity),
        command.textStyle,
        command.textMaxWidth
      )
    of cckDrawImage:
      result.add drawImage(
        owner,
        command.imageSource,
        command.imageRect.translated(offset),
        command.imageOpacity * opacity,
        command.imageStyle
      )
  while clipDepth > 0:
    result.add popClip()
    dec clipDepth

proc renderSurfaceDescriptor*(canvas: Canvas2D; name = "canvas-2d"): RenderSurfaceDescriptor =
  RenderSurfaceDescriptor(
    name: name,
    callbacks: RenderSurfaceCallbacks(
      onInput: proc(event: RenderSurfaceInput): bool =
        if canvas.onInput.isNil:
          return false
        canvas.onInput(canvas, event),
      onFrame: proc(frame: RenderSurfaceFrame): RenderSurfaceFrameResult =
        if canvas.onFrame.isNil:
          return rsfIdle
        canvas.onFrame(canvas, frame)
    )
  )
