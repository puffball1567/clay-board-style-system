import std/math
import ../../core/[color, computed_style, geometry]
import ../../paint/paint_command

type
  RasterImage* = object
    width*, height*: int
    pixels*: seq[uint8]

proc clampByte(value: float32): uint8 =
  uint8(clamp(round(value * 255.0'f32).int, 0, 255))

proc initRasterImage*(width, height: int; background = rgb(1, 1, 1)): RasterImage =
  result.width = width
  result.height = height
  result.pixels = newSeq[uint8](width * height * 3)
  for y in 0 ..< height:
    for x in 0 ..< width:
      let index = (y * width + x) * 3
      result.pixels[index] = clampByte(background.r)
      result.pixels[index + 1] = clampByte(background.g)
      result.pixels[index + 2] = clampByte(background.b)

proc putPixel(image: var RasterImage; x, y: int; color: Color) =
  if x < 0 or y < 0 or x >= image.width or y >= image.height:
    return
  let index = (y * image.width + x) * 3
  image.pixels[index] = clampByte(color.r)
  image.pixels[index + 1] = clampByte(color.g)
  image.pixels[index + 2] = clampByte(color.b)

proc intBounds(rect: Rect; width, height: int): tuple[x0, y0, x1, y1: int] =
  result.x0 = clamp(floor(rect.x).int, 0, width)
  result.y0 = clamp(floor(rect.y).int, 0, height)
  result.x1 = clamp(ceil(rect.x + rect.w).int, 0, width)
  result.y1 = clamp(ceil(rect.y + rect.h).int, 0, height)

proc intersect(a, b: Rect): Rect =
  let x0 = max(a.x, b.x)
  let y0 = max(a.y, b.y)
  let x1 = min(a.x + a.w, b.x + b.w)
  let y1 = min(a.y + a.h, b.y + b.h)
  rect(x0, y0, max(0.0'f32, x1 - x0), max(0.0'f32, y1 - y0))

proc fillRect(image: var RasterImage; rect: Rect; color: Color; clip: Rect) =
  let bounds = intBounds(intersect(rect, clip), image.width, image.height)
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      image.putPixel(x, y, color)

proc strokeRect(image: var RasterImage; rect: Rect; color: Color; width: float32; clip: Rect) =
  let stroke = max(1, round(width).int)
  let bounds = intBounds(intersect(rect, clip), image.width, image.height)
  let original = intBounds(rect, image.width, image.height)
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let left = x < original.x0 + stroke
      let right = x >= original.x1 - stroke
      let top = y < original.y0 + stroke
      let bottom = y >= original.y1 - stroke
      if left or right or top or bottom:
        image.putPixel(x, y, color)

proc mixColor(a, b: Color; t: float32): Color =
  let amount = max(0.0'f32, min(1.0'f32, t))
  rgba(
    a.r + (b.r - a.r) * amount,
    a.g + (b.g - a.g) * amount,
    a.b + (b.b - a.b) * amount,
    a.a + (b.a - a.a) * amount
  )

proc gradientColorAt(gradient: LinearGradient; t: float32): Color =
  if gradient.stops.len == 0:
    return rgba(0, 0, 0, 0)
  if gradient.stops.len == 1:
    return gradient.stops[0].color
  let position = max(0.0'f32, min(100.0'f32, t * 100.0'f32))
  var previous = gradient.stops[0]
  for index in 1 ..< gradient.stops.len:
    let current = gradient.stops[index]
    if position <= current.offset:
      let span = max(0.001'f32, current.offset - previous.offset)
      return mixColor(previous.color, current.color, (position - previous.offset) / span)
    previous = current
  gradient.stops[^1].color

proc fillLinearGradient(image: var RasterImage; rect: Rect; gradient: LinearGradient; clip: Rect) =
  if gradient.stops.len == 0:
    return
  let bounds = intBounds(intersect(rect, clip), image.width, image.height)
  let radians = (gradient.angle - 90.0'f32) * PI / 180.0'f32
  let dx = cos(radians)
  let dy = sin(radians)
  let corners = [
    vec2(rect.x, rect.y),
    vec2(rect.x + rect.w, rect.y),
    vec2(rect.x, rect.y + rect.h),
    vec2(rect.x + rect.w, rect.y + rect.h)
  ]
  var minProjection = corners[0].x * dx + corners[0].y * dy
  var maxProjection = minProjection
  for corner in corners:
    let projection = corner.x * dx + corner.y * dy
    minProjection = min(minProjection, projection)
    maxProjection = max(maxProjection, projection)
  let span = max(0.001'f32, maxProjection - minProjection)
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let projection = (x.float32 + 0.5'f32) * dx + (y.float32 + 0.5'f32) * dy
      image.putPixel(x, y, gradient.gradientColorAt((projection - minProjection) / span))

proc render*(commands: openArray[PaintCommand]; width, height: int; background = rgb(1, 1, 1)): RasterImage =
  result = initRasterImage(width, height, background)
  var clipStack = @[rect(0, 0, width.float32, height.float32)]
  for command in commands:
    case command.kind
    of pcPushClip:
      clipStack.add intersect(clipStack[^1], command.clipRect)
    of pcPopClip:
      if clipStack.len > 1:
        discard clipStack.pop()
    of pcBoxShadow:
      let grow = max(0.0'f32, command.shadowSpread + command.shadowBlur)
      let shadowRect = rect(
        command.shadowRect.x + command.shadowOffsetX - grow,
        command.shadowRect.y + command.shadowOffsetY - grow,
        command.shadowRect.w + grow * 2.0'f32,
        command.shadowRect.h + grow * 2.0'f32
      )
      result.fillRect(shadowRect, command.shadowColor, clipStack[^1])
    of pcFillRect:
      result.fillRect(command.rect, command.color, clipStack[^1])
    of pcFillLinearGradient:
      result.fillLinearGradient(command.gradientRect, command.gradient, clipStack[^1])
    of pcStrokeRect:
      result.strokeRect(command.strokeRect, command.strokeColor, command.strokeWidth, clipStack[^1])
    of pcDrawText:
      discard
    of pcDrawImage:
      discard

proc writePpm*(image: RasterImage; path: string) =
  var content = "P6\n" & $image.width & " " & $image.height & "\n255\n"
  var bytes = newStringOfCap(content.len + image.pixels.len)
  bytes.add content
  for pixel in image.pixels:
    bytes.add char(pixel)
  writeFile(path, bytes)
