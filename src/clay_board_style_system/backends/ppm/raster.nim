import std/math
import ../../core/[color, computed_style, geometry, gradient_sampling]
import ../../paint/[paint_command, path_geometry]

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

proc fillCircle(
    image: var RasterImage;
    center: Vec2;
    radius: float32;
    color: Color;
    clip: Rect
) =
  let radiusSquared = radius * radius
  let bounds = intBounds(
    rect(center.x - radius, center.y - radius, radius * 2, radius * 2),
    image.width,
    image.height
  )
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let sample = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
      let dx = sample.x - center.x
      let dy = sample.y - center.y
      if clip.contains(sample) and dx * dx + dy * dy <= radiusSquared:
        image.putPixel(x, y, color)

proc edge(first, second, point: Vec2): float32 =
  (point.x - first.x) * (second.y - first.y) -
    (point.y - first.y) * (second.x - first.x)

proc fillTriangle(
    image: var RasterImage;
    first, second, third: Vec2;
    color: Color;
    clip: Rect
) =
  let bounds = intBounds(
    rect(
      min(first.x, min(second.x, third.x)),
      min(first.y, min(second.y, third.y)),
      max(first.x, max(second.x, third.x)) - min(first.x, min(second.x, third.x)),
      max(first.y, max(second.y, third.y)) - min(first.y, min(second.y, third.y))
    ),
    image.width,
    image.height
  )
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let sample = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
      if not clip.contains(sample):
        continue
      let a = edge(first, second, sample)
      let b = edge(second, third, sample)
      let c = edge(third, first, sample)
      if (a >= 0 and b >= 0 and c >= 0) or
          (a <= 0 and b <= 0 and c <= 0):
        image.putPixel(x, y, color)

proc strokeJoin(
    image: var RasterImage;
    previous, point, following: Vec2;
    radius: float32;
    color: Color;
    lineJoin: StrokeLineJoin;
    miterLimit: float32;
    clip: Rect
) =
  let previousDelta = vec2(point.x - previous.x, point.y - previous.y)
  let followingDelta = vec2(following.x - point.x, following.y - point.y)
  let previousLength = sqrt(
    previousDelta.x * previousDelta.x + previousDelta.y * previousDelta.y
  )
  let followingLength = sqrt(
    followingDelta.x * followingDelta.x + followingDelta.y * followingDelta.y
  )
  if previousLength <= 0.0001'f32 or followingLength <= 0.0001'f32:
    return
  let previousDirection = vec2(
    previousDelta.x / previousLength, previousDelta.y / previousLength
  )
  let followingDirection = vec2(
    followingDelta.x / followingLength, followingDelta.y / followingLength
  )
  let turn = previousDirection.x * followingDirection.y -
    previousDirection.y * followingDirection.x
  if abs(turn) <= 0.0001'f32:
    return
  if lineJoin == sljRound:
    image.fillCircle(point, radius, color, clip)
    return

  let outerSign = if turn > 0: -1.0'f32 else: 1.0'f32
  let previousNormal = vec2(
    -previousDirection.y * outerSign,
    previousDirection.x * outerSign
  )
  let followingNormal = vec2(
    -followingDirection.y * outerSign,
    followingDirection.x * outerSign
  )
  let previousOuter = vec2(
    point.x + previousNormal.x * radius,
    point.y + previousNormal.y * radius
  )
  let followingOuter = vec2(
    point.x + followingNormal.x * radius,
    point.y + followingNormal.y * radius
  )
  if lineJoin == sljBevel:
    image.fillTriangle(previousOuter, point, followingOuter, color, clip)
    return
  let sum = vec2(
    previousNormal.x + followingNormal.x,
    previousNormal.y + followingNormal.y
  )
  let sumLength = sqrt(sum.x * sum.x + sum.y * sum.y)
  if sumLength <= 0.0001'f32:
    image.fillTriangle(previousOuter, point, followingOuter, color, clip)
    return
  let miterDirection = vec2(sum.x / sumLength, sum.y / sumLength)
  let denominator = miterDirection.x * followingNormal.x +
    miterDirection.y * followingNormal.y
  if abs(denominator) <= 0.0001'f32:
    image.fillTriangle(previousOuter, point, followingOuter, color, clip)
    return
  let miterLength = radius / denominator
  if abs(miterLength) > radius * max(1.0'f32, miterLimit):
    image.fillTriangle(previousOuter, point, followingOuter, color, clip)
    return
  image.fillTriangle(
    previousOuter,
    vec2(
      point.x + miterDirection.x * miterLength,
      point.y + miterDirection.y * miterLength
    ),
    followingOuter,
    color,
    clip
  )

proc samePoint(a, b: Vec2): bool =
  abs(a.x - b.x) <= 0.0001'f32 and abs(a.y - b.y) <= 0.0001'f32

proc strokePolyline(
    image: var RasterImage;
    points: openArray[Vec2];
    color: Color;
    width: float32;
    closed: bool;
    lineCap: StrokeLineCap;
    lineJoin: StrokeLineJoin;
    miterLimit: float32;
    clip: Rect
) =
  if points.len < 2 or width <= 0:
    return
  var normalized = newSeqOfCap[Vec2](points.len)
  for point in points:
    if normalized.len == 0 or not normalized[^1].samePoint(point):
      normalized.add point
  if closed and normalized.len > 1 and normalized[0].samePoint(normalized[^1]):
    normalized.setLen(normalized.len - 1)
  if normalized.len < 2:
    return

  let radius = width * 0.5'f32
  let radiusSquared = radius * radius
  let segmentCount = normalized.len - 1 + ord(closed)
  for index in 0 ..< segmentCount:
    var first = normalized[index mod normalized.len]
    var second = normalized[(index + 1) mod normalized.len]
    let dx = second.x - first.x
    let dy = second.y - first.y
    let lengthSquared = dx * dx + dy * dy
    let length = sqrt(lengthSquared)
    if length <= 0.0001'f32:
      continue
    if not closed and lineCap == slcSquare:
      if index == 0:
        first.x -= dx / length * radius
        first.y -= dy / length * radius
      if index == segmentCount - 1:
        second.x += dx / length * radius
        second.y += dy / length * radius
    let adjustedDx = second.x - first.x
    let adjustedDy = second.y - first.y
    let adjustedLengthSquared = adjustedDx * adjustedDx + adjustedDy * adjustedDy
    let bounds = intBounds(
      rect(
        min(first.x, second.x) - radius,
        min(first.y, second.y) - radius,
        abs(adjustedDx) + radius * 2.0'f32,
        abs(adjustedDy) + radius * 2.0'f32
      ),
      image.width,
      image.height
    )
    for y in bounds.y0 ..< bounds.y1:
      for x in bounds.x0 ..< bounds.x1:
        let sample = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
        if not clip.contains(sample):
          continue
        let t = ((sample.x - first.x) * adjustedDx +
          (sample.y - first.y) * adjustedDy) / adjustedLengthSquared
        if t < 0 or t > 1:
          continue
        let nearest = vec2(
          first.x + adjustedDx * t, first.y + adjustedDy * t
        )
        let distanceX = sample.x - nearest.x
        let distanceY = sample.y - nearest.y
        if distanceX * distanceX + distanceY * distanceY <= radiusSquared:
          image.putPixel(x, y, color)

  if closed:
    for index in 0 ..< normalized.len:
      image.strokeJoin(
        normalized[(index - 1 + normalized.len) mod normalized.len],
        normalized[index],
        normalized[(index + 1) mod normalized.len],
        radius, color, lineJoin, miterLimit, clip
      )
  else:
    for index in 1 ..< normalized.len - 1:
      image.strokeJoin(
        normalized[index - 1], normalized[index], normalized[index + 1],
        radius, color, lineJoin, miterLimit, clip
      )
    if lineCap == slcRound:
      image.fillCircle(normalized[0], radius, color, clip)
      image.fillCircle(normalized[^1], radius, color, clip)

proc strokePath(
    image: var RasterImage;
    command: PaintCommand;
    clip: Rect
) =
  for contour in command.path.flattened():
    image.strokePolyline(
      contour.points,
      command.pathColor,
      command.pathWidth,
      contour.closed,
      command.pathLineCap,
      command.pathLineJoin,
      command.pathMiterLimit,
      clip
    )

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
  let lookup = gradient.prepareGradientSampler.buildGradientLookup(
    span.gradientLookupSampleCount
  )
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let projection = (x.float32 + 0.5'f32) * dx + (y.float32 + 0.5'f32) * dy
      image.putPixel(x, y, lookup.gradientColorAt((projection - minProjection) / span))

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
    of pcStrokePath:
      result.strokePath(command, clipStack[^1])
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
