import std/options
import ../core/[color, computed_style, geometry, node]

type
  PaintCommandKind* = enum
    pcPushClip,
    pcPopClip,
    pcBoxShadow,
    pcFillRect,
    pcFillLinearGradient,
    pcStrokeRect,
    pcDrawText,
    pcDrawImage

  PaintCommand* = object
    owner*: Option[NodeId]
    case kind*: PaintCommandKind
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
      gradient*: LinearGradient
      gradientRadius*: float32
    of pcStrokeRect:
      strokeRect*: Rect
      strokeColor*: Color
      strokeWidth*: float32
      strokeRadius*: float32
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

proc fillRect*(rect: Rect; color: Color; radius: float32 = 0; owner = none(NodeId)): PaintCommand =
  PaintCommand(kind: pcFillRect, owner: owner, rect: rect, color: color, radius: radius)

proc fillLinearGradient*(rect: Rect; gradient: LinearGradient; radius: float32 = 0; owner = none(NodeId)): PaintCommand =
  PaintCommand(kind: pcFillLinearGradient, owner: owner, gradientRect: rect, gradient: gradient, gradientRadius: radius)

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

proc drawText*(node: NodeId; text: string; position: Vec2; color: Color; style: ComputedTextStyle; maxWidth = none(float32)): PaintCommand =
  PaintCommand(kind: pcDrawText, owner: some(node), node: node, text: text, position: position, textMaxWidth: maxWidth, textColor: color, textStyle: style)

proc drawImage*(node: NodeId; source: string; rect: Rect; opacity: float32; style: ComputedImageStyle): PaintCommand =
  PaintCommand(kind: pcDrawImage, owner: some(node), imageNode: node, imageSource: source, imageRect: rect, imageOpacity: opacity, imageStyle: style)
