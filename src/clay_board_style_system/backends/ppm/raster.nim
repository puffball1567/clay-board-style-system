import std/[math, options, sequtils]
import ../../core/[color, computed_style, geometry, gradient_sampling]
import ../../paint/[paint_command, path_geometry]

type
  RasterImage* = object
    width*, height*: int
    pixels*: seq[uint8]
    alpha*: seq[uint8]

  PpmClip = object
    bounds: Rect
    shapes: seq[TransformedRect]

  PpmLinearGradientSampler = object
    dx, dy: float32
    minProjection, span: float32
    lookup: GradientLookupTable

  PpmLayer = object
    bounds: Rect
    opacity: float32
    compositeMode: LayerCompositeMode
    clipDepth: int

proc clampByte(value: float32): uint8 =
  uint8(clamp(round(value * 255.0'f32).int, 0, 255))

proc initRasterImage*(width, height: int; background = rgb(1, 1, 1)): RasterImage =
  result.width = width
  result.height = height
  result.pixels = newSeq[uint8](width * height * 3)
  result.alpha = newSeq[uint8](width * height)
  for y in 0 ..< height:
    for x in 0 ..< width:
      let index = (y * width + x) * 3
      let alphaIndex = y * width + x
      result.pixels[index] = clampByte(background.r)
      result.pixels[index + 1] = clampByte(background.g)
      result.pixels[index + 2] = clampByte(background.b)
      result.alpha[alphaIndex] = clampByte(background.a)

proc pixelColor(image: RasterImage; x, y: int): Color =
  let index = (y * image.width + x) * 3
  let alphaIndex = y * image.width + x
  rgba(
    image.pixels[index].float32 / 255.0'f32,
    image.pixels[index + 1].float32 / 255.0'f32,
    image.pixels[index + 2].float32 / 255.0'f32,
    image.alpha[alphaIndex].float32 / 255.0'f32
  )

proc storePixel(image: var RasterImage; x, y: int; color: Color) =
  let index = (y * image.width + x) * 3
  let alphaIndex = y * image.width + x
  image.pixels[index] = clampByte(color.r)
  image.pixels[index + 1] = clampByte(color.g)
  image.pixels[index + 2] = clampByte(color.b)
  image.alpha[alphaIndex] = clampByte(color.a)

proc sourceOver(source, destination: Color): Color =
  let sourceAlpha = clamp(source.a, 0.0'f32, 1.0'f32)
  let destinationAlpha = clamp(destination.a, 0.0'f32, 1.0'f32)
  let outputAlpha = sourceAlpha + destinationAlpha * (1.0'f32 - sourceAlpha)
  if outputAlpha <= 0.000001'f32:
    return rgba(0, 0, 0, 0)
  rgba(
    (source.r * sourceAlpha +
      destination.r * destinationAlpha * (1.0'f32 - sourceAlpha)) / outputAlpha,
    (source.g * sourceAlpha +
      destination.g * destinationAlpha * (1.0'f32 - sourceAlpha)) / outputAlpha,
    (source.b * sourceAlpha +
      destination.b * destinationAlpha * (1.0'f32 - sourceAlpha)) / outputAlpha,
    outputAlpha
  )

proc putPixel(image: var RasterImage; x, y: int; color: Color) =
  if x < 0 or y < 0 or x >= image.width or y >= image.height:
    return
  image.storePixel(x, y, color.sourceOver(image.pixelColor(x, y)))

proc compositePixel(
    destination: var RasterImage;
    source: RasterImage;
    x, y: int;
    opacity: float32;
    compositeMode: LayerCompositeMode
) =
  var sourceColor = source.pixelColor(x, y)
  sourceColor.a *= opacity
  let destinationColor = destination.pixelColor(x, y)
  case compositeMode
  of lcmSourceOver:
    destination.storePixel(x, y, sourceColor.sourceOver(destinationColor))
  of lcmCopy:
    destination.storePixel(x, y, sourceColor)
  of lcmAdditive:
    let sourceAlpha = clamp(sourceColor.a, 0.0'f32, 1.0'f32)
    destination.storePixel(x, y, rgba(
      min(1.0'f32, destinationColor.r + sourceColor.r * sourceAlpha),
      min(1.0'f32, destinationColor.g + sourceColor.g * sourceAlpha),
      min(1.0'f32, destinationColor.b + sourceColor.b * sourceAlpha),
      destinationColor.a
    ))

proc intBounds(rect: Rect; width, height: int): tuple[x0, y0, x1, y1: int]
proc intersect(a, b: Rect): Rect
proc contains(clip: PpmClip; point: Vec2): bool

proc compositeLayer(
    destination: var RasterImage;
    source: RasterImage;
    layer: PpmLayer;
    clip: PpmClip
) =
  let bounds = intBounds(
    intersect(layer.bounds, clip.bounds), destination.width, destination.height
  )
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let sample = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
      if clip.contains(sample):
        destination.compositePixel(
          source, x, y, layer.opacity, layer.compositeMode
        )

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

proc contains(clip: PpmClip; point: Vec2): bool =
  if not clip.bounds.contains(point):
    return false
  for shape in clip.shapes:
    if not shape.contains(point):
      return false
  true

proc withShape(clip: PpmClip; shape: TransformedRect): PpmClip =
  result.bounds = intersect(clip.bounds, shape.bounds)
  result.shapes = newSeqOfCap[TransformedRect](clip.shapes.len + 1)
  for existing in clip.shapes:
    result.shapes.add existing
  result.shapes.add shape

proc fillCircle(
    image: var RasterImage;
    center: Vec2;
    radius: float32;
    color: Color;
    clip: PpmClip
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
    clip: PpmClip
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

proc fillTransformedRect(
    image: var RasterImage;
    source: Rect;
    transform: Affine2D;
    color: Color;
    clip: PpmClip
) =
  let shape = transformedRect(source, transform)
  if shape.inverseTransform.isNone:
    return
  let bounds = intBounds(
    intersect(shape.bounds, clip.bounds), image.width, image.height
  )
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let sample = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
      if clip.contains(sample) and shape.contains(sample):
        image.putPixel(x, y, color)

proc strokeScale(transform: Affine2D): float32 =
  let xScale = sqrt(transform.m11 * transform.m11 + transform.m12 * transform.m12)
  let yScale = sqrt(transform.m21 * transform.m21 + transform.m22 * transform.m22)
  max(0.0001'f32, (xScale + yScale) * 0.5'f32)

proc strokeJoin(
    image: var RasterImage;
    previous, point, following: Vec2;
    radius: float32;
    color: Color;
    lineJoin: StrokeLineJoin;
    miterLimit: float32;
    clip: PpmClip
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
    clip: PpmClip
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
    clip: PpmClip
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

proc prepareLinearGradient(rect: Rect; gradient: LinearGradient): PpmLinearGradientSampler =
  let radians = (gradient.angle - 90.0'f32) * PI / 180.0'f32
  result.dx = cos(radians)
  result.dy = sin(radians)
  let corners = [
    vec2(rect.x, rect.y),
    vec2(rect.x + rect.w, rect.y),
    vec2(rect.x, rect.y + rect.h),
    vec2(rect.x + rect.w, rect.y + rect.h)
  ]
  result.minProjection = corners[0].x * result.dx + corners[0].y * result.dy
  var maxProjection = result.minProjection
  for corner in corners:
    let projection = corner.x * result.dx + corner.y * result.dy
    result.minProjection = min(result.minProjection, projection)
    maxProjection = max(maxProjection, projection)
  result.span = max(0.001'f32, maxProjection - result.minProjection)
  result.lookup = gradient.prepareGradientSampler.buildGradientLookup(
    result.span.gradientLookupSampleCount
  )

proc colorAt(sampler: PpmLinearGradientSampler; point: Vec2): Color =
  let projection = point.x * sampler.dx + point.y * sampler.dy
  sampler.lookup.gradientColorAt(
    (projection - sampler.minProjection) / sampler.span
  )

proc fillLinearGradient(
    image: var RasterImage;
    sourceRect: Rect;
    gradient: LinearGradient;
    transform: Affine2D;
    clip: PpmClip
) =
  if gradient.stops.len == 0:
    return
  let shape = transformedRect(sourceRect, transform)
  if shape.inverseTransform.isNone:
    return
  let bounds = intBounds(
    intersect(shape.bounds, clip.bounds), image.width, image.height
  )
  let sampler = prepareLinearGradient(sourceRect, gradient)
  for y in bounds.y0 ..< bounds.y1:
    for x in bounds.x0 ..< bounds.x1:
      let destination = vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
      if not clip.contains(destination):
        continue
      let source = shape.inverseTransform.get.transformPoint(destination)
      if sourceRect.contains(source):
        image.putPixel(x, y, sampler.colorAt(source))

proc render*(commands: openArray[PaintCommand]; width, height: int; background = rgb(1, 1, 1)): RasterImage =
  var targets = @[initRasterImage(width, height, background)]
  var layers: seq[PpmLayer]
  var clipStack = @[
    PpmClip(bounds: rect(0, 0, width.float32, height.float32))
  ]
  var transformStack = @[identityAffine2D()]
  for command in commands:
    case command.kind
    of pcPushTransform:
      transformStack.add(transformStack[^1] * command.transform)
    of pcPopTransform:
      if transformStack.len > 1:
        discard transformStack.pop()
    of pcPushLayer:
      let layerBounds = transformStack[^1].transformedBounds(command.layerBounds)
      layers.add PpmLayer(
        bounds: layerBounds,
        opacity: command.layerOpacity,
        compositeMode: command.layerCompositeMode,
        clipDepth: clipStack.len
      )
      targets.add initRasterImage(width, height, rgba(0, 0, 0, 0))
      clipStack.add clipStack[^1].withShape(
        transformedRect(command.layerBounds, transformStack[^1])
      )
    of pcPopLayer:
      if layers.len > 0 and targets.len > 1:
        let source = targets.pop()
        let layer = layers.pop()
        clipStack.setLen(max(1, layer.clipDepth))
        targets[^1].compositeLayer(source, layer, clipStack[^1])
    of pcPushClip:
      clipStack.add clipStack[^1].withShape(
        transformedRect(command.clipRect, transformStack[^1])
      )
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
      targets[^1].fillTransformedRect(
        shadowRect, transformStack[^1], command.shadowColor, clipStack[^1]
      )
    of pcFillRect:
      targets[^1].fillTransformedRect(
        command.rect, transformStack[^1], command.color, clipStack[^1]
      )
    of pcFillLinearGradient:
      targets[^1].fillLinearGradient(
        command.gradientRect, command.gradient, transformStack[^1], clipStack[^1]
      )
    of pcStrokeRect:
      let corners = [
        vec2(command.strokeRect.x, command.strokeRect.y),
        vec2(command.strokeRect.x + command.strokeRect.w, command.strokeRect.y),
        vec2(command.strokeRect.x + command.strokeRect.w, command.strokeRect.y + command.strokeRect.h),
        vec2(command.strokeRect.x, command.strokeRect.y + command.strokeRect.h)
      ]
      targets[^1].strokePolyline(
        corners.mapIt(transformStack[^1].transformPoint(it)),
        command.strokeColor,
        command.strokeWidth * transformStack[^1].strokeScale,
        true, slcButt, sljMiter, 10, clipStack[^1]
      )
    of pcStrokePath:
      var transformedCommand = command
      transformedCommand.path = command.path.transformed(transformStack[^1])
      transformedCommand.pathWidth = command.pathWidth * transformStack[^1].strokeScale
      targets[^1].strokePath(transformedCommand, clipStack[^1])
    of pcDrawText:
      discard
    of pcDrawImage:
      discard

  while layers.len > 0 and targets.len > 1:
    let source = targets.pop()
    let layer = layers.pop()
    clipStack.setLen(max(1, layer.clipDepth))
    targets[^1].compositeLayer(source, layer, clipStack[^1])
  result = targets[0]

proc writePpm*(image: RasterImage; path: string) =
  var content = "P6\n" & $image.width & " " & $image.height & "\n255\n"
  var bytes = newStringOfCap(content.len + image.pixels.len)
  bytes.add content
  for pixel in image.pixels:
    bytes.add char(pixel)
  writeFile(path, bytes)
