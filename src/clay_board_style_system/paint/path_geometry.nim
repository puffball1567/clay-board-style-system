import std/[algorithm, math, options]

import ../core/geometry

type
  PathFillRule* = enum
    pfrNonZero,
    pfrEvenOdd

  StrokeLineCap* = enum
    slcButt,
    slcRound,
    slcSquare

  StrokeLineJoin* = enum
    sljMiter,
    sljRound,
    sljBevel

  PathSegmentKind* = enum
    pskMoveTo,
    pskLineTo,
    pskQuadraticTo,
    pskCubicTo,
    pskClose

  PathSegment* = object
    kind*: PathSegmentKind
    control1*, control2*, endpoint*: Vec2

  Path2D* = object
    segments*: seq[PathSegment]
    currentPoint: Option[Vec2]
    subpathStart: Option[Vec2]

  FlattenedPathContour* = object
    points*: seq[Vec2]
    closed*: bool

const
  maxStrokeDashPatternEntries* = 4_096
  maxStrokeDashPieces* = 65_536

proc initPath2D*(): Path2D =
  Path2D(segments: @[])

proc finite(value: float32): bool =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc finite(point: Vec2): bool =
  point.x.finite and point.y.finite

proc clear*(path: var Path2D) =
  path.segments.setLen(0)
  path.currentPoint = none(Vec2)
  path.subpathStart = none(Vec2)

proc moveTo*(path: var Path2D; point: Vec2) =
  if not point.finite:
    return
  path.segments.add PathSegment(kind: pskMoveTo, endpoint: point)
  path.currentPoint = some(point)
  path.subpathStart = some(point)

proc lineTo*(path: var Path2D; point: Vec2) =
  if not point.finite:
    return
  if path.currentPoint.isNone:
    path.moveTo(point)
    return
  path.segments.add PathSegment(kind: pskLineTo, endpoint: point)
  path.currentPoint = some(point)

proc quadraticCurveTo*(path: var Path2D; control, endpoint: Vec2) =
  if not control.finite or not endpoint.finite:
    return
  if path.currentPoint.isNone:
    path.moveTo(endpoint)
    return
  path.segments.add PathSegment(
    kind: pskQuadraticTo,
    control1: control,
    endpoint: endpoint
  )
  path.currentPoint = some(endpoint)

proc bezierCurveTo*(
    path: var Path2D;
    control1, control2, endpoint: Vec2
) =
  if not control1.finite or not control2.finite or not endpoint.finite:
    return
  if path.currentPoint.isNone:
    path.moveTo(endpoint)
    return
  path.segments.add PathSegment(
    kind: pskCubicTo,
    control1: control1,
    control2: control2,
    endpoint: endpoint
  )
  path.currentPoint = some(endpoint)

proc samePoint(a, b: Vec2; tolerance = 0.0001'f32): bool =
  abs(a.x - b.x) <= tolerance and abs(a.y - b.y) <= tolerance

proc ellipsePoint(
    center: Vec2;
    radiusX, radiusY, rotation, angle: float32
): Vec2 =
  let cosine = cos(angle)
  let sine = sin(angle)
  let rotationCosine = cos(rotation)
  let rotationSine = sin(rotation)
  vec2(
    center.x + rotationCosine * radiusX * cosine -
      rotationSine * radiusY * sine,
    center.y + rotationSine * radiusX * cosine +
      rotationCosine * radiusY * sine
  )

proc ellipseDerivative(
    radiusX, radiusY, rotation, angle: float32
): Vec2 =
  let cosine = cos(angle)
  let sine = sin(angle)
  let rotationCosine = cos(rotation)
  let rotationSine = sin(rotation)
  vec2(
    -rotationCosine * radiusX * sine - rotationSine * radiusY * cosine,
    -rotationSine * radiusX * sine + rotationCosine * radiusY * cosine
  )

proc ellipse*(
    path: var Path2D;
    center: Vec2;
    radiusX, radiusY: float32;
    rotation, startAngle, endAngle: float32;
    counterClockwise = false
) =
  ## Appends an elliptical arc in radians using bounded cubic segments. Invalid
  ## or negative radii leave the retained path unchanged.
  if not center.finite or not radiusX.finite or not radiusY.finite or
      not rotation.finite or not startAngle.finite or not endAngle.finite or
      radiusX < 0 or radiusY < 0:
    return

  const fullTurn = PI.float32 * 2.0'f32
  var sweep = endAngle - startAngle
  if abs(sweep) >= fullTurn:
    sweep = if counterClockwise: -fullTurn else: fullTurn
  elif counterClockwise:
    while sweep > 0:
      sweep -= fullTurn
  else:
    while sweep < 0:
      sweep += fullTurn

  let first = ellipsePoint(center, radiusX, radiusY, rotation, startAngle)
  if path.currentPoint.isNone:
    path.moveTo(first)
  elif not path.currentPoint.get.samePoint(first):
    path.lineTo(first)
  if abs(sweep) <= 0.000001'f32 or radiusX == 0 or radiusY == 0:
    return

  let segmentCount = max(1, int(ceil(abs(sweep) / (PI.float32 * 0.5'f32))))
  let segmentSweep = sweep / segmentCount.float32
  var segmentStart = startAngle
  var segmentStartPoint = first
  for _ in 0 ..< segmentCount:
    let segmentEnd = segmentStart + segmentSweep
    let segmentEndPoint = ellipsePoint(
      center, radiusX, radiusY, rotation, segmentEnd
    )
    let tangentScale = 4.0'f32 / 3.0'f32 * tan(segmentSweep * 0.25'f32)
    let startDerivative = ellipseDerivative(
      radiusX, radiusY, rotation, segmentStart
    )
    let endDerivative = ellipseDerivative(
      radiusX, radiusY, rotation, segmentEnd
    )
    path.bezierCurveTo(
      vec2(
        segmentStartPoint.x + startDerivative.x * tangentScale,
        segmentStartPoint.y + startDerivative.y * tangentScale
      ),
      vec2(
        segmentEndPoint.x - endDerivative.x * tangentScale,
        segmentEndPoint.y - endDerivative.y * tangentScale
      ),
      segmentEndPoint
    )
    segmentStart = segmentEnd
    segmentStartPoint = segmentEndPoint

proc arc*(
    path: var Path2D;
    center: Vec2;
    radius, startAngle, endAngle: float32;
    counterClockwise = false
) =
  path.ellipse(
    center, radius, radius, 0.0'f32,
    startAngle, endAngle, counterClockwise
  )

proc closePath*(path: var Path2D) =
  if path.currentPoint.isNone or path.subpathStart.isNone:
    return
  if path.segments.len > 0 and path.segments[^1].kind == pskClose:
    return
  path.segments.add PathSegment(kind: pskClose)
  path.currentPoint = path.subpathStart

proc path2D*(points: openArray[Vec2]; closed = false): Path2D =
  result = initPath2D()
  for index, point in points:
    if index == 0:
      result.moveTo(point)
    else:
      result.lineTo(point)
  if closed:
    result.closePath()

proc drawable*(path: Path2D): bool =
  for segment in path.segments:
    if segment.kind in {pskLineTo, pskQuadraticTo, pskCubicTo}:
      return true
  false

proc translated*(path: Path2D; offset: Vec2): Path2D =
  result = path
  for segment in result.segments.mitems:
    case segment.kind
    of pskMoveTo, pskLineTo:
      segment.endpoint = segment.endpoint.translated(offset)
    of pskQuadraticTo:
      segment.control1 = segment.control1.translated(offset)
      segment.endpoint = segment.endpoint.translated(offset)
    of pskCubicTo:
      segment.control1 = segment.control1.translated(offset)
      segment.control2 = segment.control2.translated(offset)
      segment.endpoint = segment.endpoint.translated(offset)
    of pskClose:
      discard
  if result.currentPoint.isSome:
    result.currentPoint = some(result.currentPoint.get.translated(offset))
  if result.subpathStart.isSome:
    result.subpathStart = some(result.subpathStart.get.translated(offset))

proc transformed*(path: Path2D; transform: Affine2D): Path2D =
  result = path
  for segment in result.segments.mitems:
    case segment.kind
    of pskMoveTo, pskLineTo:
      segment.endpoint = transform.transformPoint(segment.endpoint)
    of pskQuadraticTo:
      segment.control1 = transform.transformPoint(segment.control1)
      segment.endpoint = transform.transformPoint(segment.endpoint)
    of pskCubicTo:
      segment.control1 = transform.transformPoint(segment.control1)
      segment.control2 = transform.transformPoint(segment.control2)
      segment.endpoint = transform.transformPoint(segment.endpoint)
    of pskClose:
      discard
  if result.currentPoint.isSome:
    result.currentPoint = some(transform.transformPoint(result.currentPoint.get))
  if result.subpathStart.isSome:
    result.subpathStart = some(transform.transformPoint(result.subpathStart.get))

proc midpoint(a, b: Vec2): Vec2 =
  vec2((a.x + b.x) * 0.5'f32, (a.y + b.y) * 0.5'f32)

proc pointLineDistance(point, first, last: Vec2): float32 =
  let dx = last.x - first.x
  let dy = last.y - first.y
  let lengthSquared = dx * dx + dy * dy
  if lengthSquared <= 0.000001'f32:
    let px = point.x - first.x
    let py = point.y - first.y
    return sqrt(px * px + py * py)
  abs(dy * point.x - dx * point.y + last.x * first.y - last.y * first.x) /
    sqrt(lengthSquared)

proc flattenQuadratic(
    first, control, last: Vec2;
    tolerance: float32;
    depth: int;
    output: var seq[Vec2]
) =
  if depth >= 12 or control.pointLineDistance(first, last) <= tolerance:
    output.add last
    return
  let firstControl = midpoint(first, control)
  let controlLast = midpoint(control, last)
  let split = midpoint(firstControl, controlLast)
  flattenQuadratic(first, firstControl, split, tolerance, depth + 1, output)
  flattenQuadratic(split, controlLast, last, tolerance, depth + 1, output)

proc flattenCubic(
    first, control1, control2, last: Vec2;
    tolerance: float32;
    depth: int;
    output: var seq[Vec2]
) =
  let flatness = max(
    control1.pointLineDistance(first, last),
    control2.pointLineDistance(first, last)
  )
  if depth >= 12 or flatness <= tolerance:
    output.add last
    return
  let firstControl = midpoint(first, control1)
  let controls = midpoint(control1, control2)
  let controlLast = midpoint(control2, last)
  let leftControl = midpoint(firstControl, controls)
  let rightControl = midpoint(controls, controlLast)
  let split = midpoint(leftControl, rightControl)
  flattenCubic(
    first, firstControl, leftControl, split, tolerance, depth + 1, output
  )
  flattenCubic(
    split, rightControl, controlLast, last, tolerance, depth + 1, output
  )

proc flattened*(
    path: Path2D;
    tolerance = 0.25'f32
): seq[FlattenedPathContour] =
  let safeTolerance = max(0.01'f32, tolerance)
  var points: seq[Vec2]
  var current = none(Vec2)
  var start = none(Vec2)

  template flush(closedValue: bool) =
    if points.len >= 2:
      result.add FlattenedPathContour(points: points, closed: closedValue)
    points = @[]

  for segment in path.segments:
    case segment.kind
    of pskMoveTo:
      flush(false)
      points = @[segment.endpoint]
      current = some(segment.endpoint)
      start = some(segment.endpoint)
    of pskLineTo:
      if current.isNone:
        points = @[segment.endpoint]
        start = some(segment.endpoint)
      else:
        points.add segment.endpoint
      current = some(segment.endpoint)
    of pskQuadraticTo:
      if current.isSome:
        flattenQuadratic(
          current.get, segment.control1, segment.endpoint,
          safeTolerance, 0, points
        )
      else:
        points = @[segment.endpoint]
        start = some(segment.endpoint)
      current = some(segment.endpoint)
    of pskCubicTo:
      if current.isSome:
        flattenCubic(
          current.get, segment.control1, segment.control2, segment.endpoint,
          safeTolerance, 0, points
        )
      else:
        points = @[segment.endpoint]
        start = some(segment.endpoint)
      current = some(segment.endpoint)
    of pskClose:
      if start.isSome:
        flush(true)
        points = @[start.get]
        current = start
      else:
        current = none(Vec2)
  flush(false)

proc appendClosedPolygon(path: var Path2D; source: openArray[Vec2]) =
  if source.len < 3:
    return
  var points = @source
  var twiceArea = 0.0'f32
  for index in 0 ..< points.len:
    let current = points[index]
    let following = points[(index + 1) mod points.len]
    twiceArea += current.x * following.y - following.x * current.y
  if twiceArea < 0:
    points.reverse()
  path.moveTo(points[0])
  for index in 1 ..< points.len:
    path.lineTo(points[index])
  path.closePath()

proc appendCircle(path: var Path2D; center: Vec2; radius: float32) =
  if radius <= 0:
    return
  path.moveTo(vec2(center.x + radius, center.y))
  path.arc(center, radius, 0.0'f32, PI.float32 * 2.0'f32)
  path.closePath()

proc appendStrokeJoin(
    outline: var Path2D;
    previous, point, following: Vec2;
    radius: float32;
    lineJoin: StrokeLineJoin;
    miterLimit: float32
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
  if lineJoin == sljRound:
    outline.appendCircle(point, radius)
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
    outline.appendClosedPolygon([previousOuter, point, followingOuter])
    return

  let normalSum = vec2(
    previousNormal.x + followingNormal.x,
    previousNormal.y + followingNormal.y
  )
  let normalSumLength = sqrt(
    normalSum.x * normalSum.x + normalSum.y * normalSum.y
  )
  if normalSumLength <= 0.0001'f32:
    outline.appendClosedPolygon([previousOuter, point, followingOuter])
    return
  let miterDirection = vec2(
    normalSum.x / normalSumLength, normalSum.y / normalSumLength
  )
  let denominator = miterDirection.x * followingNormal.x +
    miterDirection.y * followingNormal.y
  if abs(denominator) <= 0.0001'f32:
    outline.appendClosedPolygon([previousOuter, point, followingOuter])
    return
  let miterLength = radius / denominator
  if abs(miterLength) > radius * max(1.0'f32, miterLimit):
    outline.appendClosedPolygon([previousOuter, point, followingOuter])
    return
  outline.appendClosedPolygon([
    previousOuter,
    vec2(
      point.x + miterDirection.x * miterLength,
      point.y + miterDirection.y * miterLength
    ),
    followingOuter
  ])

proc normalizeDashPattern*(source: openArray[float32]): seq[float32] =
  ## Normalizes a CSS-like alternating dash/gap list. Invalid and all-zero
  ## patterns resolve to a solid stroke. Odd lists repeat once.
  if source.len > maxStrokeDashPatternEntries:
    return @[]
  var total = 0.0'f32
  result = newSeqOfCap[float32](source.len * (if source.len mod 2 == 0: 1 else: 2))
  for value in source:
    if not value.finite or value < 0:
      return @[]
    result.add value
    total += value
  if result.len == 0 or not total.finite or total <= 0.000001'f32:
    return @[]
  if result.len mod 2 != 0:
    for value in source:
      result.add value

proc contourLength(contour: FlattenedPathContour): float32 =
  let segmentCount = contour.points.len - 1 + ord(contour.closed)
  for index in 0 ..< segmentCount:
    let first = contour.points[index mod contour.points.len]
    let second = contour.points[(index + 1) mod contour.points.len]
    let dx = second.x - first.x
    let dy = second.y - first.y
    result += sqrt(dx * dx + dy * dy)

proc dashedContours(
    source: openArray[FlattenedPathContour];
    pattern: openArray[float32];
    offset: float32
): tuple[contours: seq[FlattenedPathContour], overflowed: bool] =
  var patternLength = 0.0'f32
  for value in pattern:
    patternLength += value
  var estimatedPieces = 0.0'f32
  for contour in source:
    estimatedPieces += contour.contourLength / patternLength *
      max(1, pattern.len div 2).float32 + 1.0'f32
  if not estimatedPieces.finite or estimatedPieces > maxStrokeDashPieces.float32:
    return (@[], true)

  var normalizedOffset =
    if offset.finite: offset mod patternLength
    else: 0.0'f32
  if normalizedOffset < 0:
    normalizedOffset += patternLength

  for contour in source:
    if contour.points.len < 2:
      continue
    var patternIndex = 0
    var patternRemaining = pattern[0]
    var phase = normalizedOffset
    while phase > 0.000001'f32:
      if patternRemaining <= 0.000001'f32:
        patternIndex = (patternIndex + 1) mod pattern.len
        patternRemaining = pattern[patternIndex]
      elif phase >= patternRemaining:
        phase -= patternRemaining
        patternIndex = (patternIndex + 1) mod pattern.len
        patternRemaining = pattern[patternIndex]
      else:
        patternRemaining -= phase
        phase = 0

    var fragments: seq[FlattenedPathContour]
    var activePoints: seq[Vec2]
    var hadGap = false
    let segmentCount = contour.points.len - 1 + ord(contour.closed)
    for segmentIndex in 0 ..< segmentCount:
      let first = contour.points[segmentIndex mod contour.points.len]
      let second = contour.points[(segmentIndex + 1) mod contour.points.len]
      let dx = second.x - first.x
      let dy = second.y - first.y
      let segmentLength = sqrt(dx * dx + dy * dy)
      if segmentLength <= 0.000001'f32:
        continue
      var consumed = 0.0'f32
      while consumed < segmentLength - 0.000001'f32:
        while patternRemaining <= 0.000001'f32:
          let wasDash = patternIndex mod 2 == 0
          patternIndex = (patternIndex + 1) mod pattern.len
          patternRemaining = pattern[patternIndex]
          if wasDash and patternIndex mod 2 != 0 and activePoints.len >= 2:
            fragments.add FlattenedPathContour(points: activePoints)
            activePoints = @[]
        let step = min(segmentLength - consumed, patternRemaining)
        let startRatio = consumed / segmentLength
        let endRatio = (consumed + step) / segmentLength
        let startPoint = vec2(first.x + dx * startRatio, first.y + dy * startRatio)
        let endPoint = vec2(first.x + dx * endRatio, first.y + dy * endRatio)
        if patternIndex mod 2 == 0:
          if activePoints.len == 0:
            activePoints.add startPoint
          if not activePoints[^1].samePoint(endPoint):
            activePoints.add endPoint
        elif step > 0.000001'f32:
          hadGap = true
        consumed += step
        patternRemaining -= step

    if activePoints.len >= 2:
      fragments.add FlattenedPathContour(points: activePoints)

    if contour.closed and not hadGap:
      result.contours.add contour
      continue
    if contour.closed and fragments.len >= 2 and
        fragments[0].points.len >= 2 and fragments[^1].points.len >= 2 and
        fragments[0].points[0].samePoint(contour.points[0]) and
        fragments[^1].points[^1].samePoint(contour.points[0]):
      var merged = fragments[^1].points
      for index in 1 ..< fragments[0].points.len:
        merged.add fragments[0].points[index]
      fragments[0] = FlattenedPathContour(points: merged)
      fragments.setLen(fragments.len - 1)
    result.contours.add fragments

proc strokeOutline*(
    path: Path2D;
    width = 1.0'f32;
    lineCap = slcButt;
    lineJoin = sljMiter;
    miterLimit = 10.0'f32;
    tolerance = 0.25'f32;
    dashPattern: openArray[float32] = [];
    dashOffset = 0.0'f32
): Path2D =
  ## Converts a retained centerline into fillable contours. Both CPU backends
  ## consume this geometry so caps, joins and coverage cannot drift apart.
  result = initPath2D()
  if width <= 0 or not width.finite:
    return
  let flattenTolerance =
    if tolerance.finite and tolerance > 0: tolerance
    else: 0.25'f32
  let radius = width * 0.5'f32
  let solidContours = path.flattened(flattenTolerance)
  let normalizedPattern = normalizeDashPattern(dashPattern)
  let dashed =
    if normalizedPattern.len == 0:
      (contours: solidContours, overflowed: false)
    else:
      dashedContours(solidContours, normalizedPattern, dashOffset)
  let contours = if dashed.overflowed: solidContours else: dashed.contours
  for contour in contours:
    var points = newSeqOfCap[Vec2](contour.points.len)
    for point in contour.points:
      if points.len == 0 or not points[^1].samePoint(point):
        points.add point
    if contour.closed and points.len > 1 and points[0].samePoint(points[^1]):
      points.setLen(points.len - 1)
    if points.len < 2:
      continue

    let segmentCount = points.len - 1 + ord(contour.closed)
    for index in 0 ..< segmentCount:
      var first = points[index mod points.len]
      var second = points[(index + 1) mod points.len]
      let delta = vec2(second.x - first.x, second.y - first.y)
      let length = sqrt(delta.x * delta.x + delta.y * delta.y)
      if length <= 0.0001'f32:
        continue
      let direction = vec2(delta.x / length, delta.y / length)
      if not contour.closed and lineCap == slcSquare:
        if index == 0:
          first = vec2(
            first.x - direction.x * radius,
            first.y - direction.y * radius
          )
        if index == segmentCount - 1:
          second = vec2(
            second.x + direction.x * radius,
            second.y + direction.y * radius
          )
      let normal = vec2(-direction.y * radius, direction.x * radius)
      result.appendClosedPolygon([
        vec2(first.x + normal.x, first.y + normal.y),
        vec2(second.x + normal.x, second.y + normal.y),
        vec2(second.x - normal.x, second.y - normal.y),
        vec2(first.x - normal.x, first.y - normal.y)
      ])

    if contour.closed:
      for index in 0 ..< points.len:
        result.appendStrokeJoin(
          points[(index - 1 + points.len) mod points.len],
          points[index],
          points[(index + 1) mod points.len],
          radius, lineJoin, miterLimit
        )
    else:
      for index in 1 ..< points.len - 1:
        result.appendStrokeJoin(
          points[index - 1], points[index], points[index + 1],
          radius, lineJoin, miterLimit
        )
      if lineCap == slcRound:
        result.appendCircle(points[0], radius)
        result.appendCircle(points[^1], radius)

proc fillable*(path: Path2D): bool =
  for contour in path.flattened():
    if contour.points.len >= 3:
      return true
  false

proc contains*(
    contours: openArray[FlattenedPathContour];
    point: Vec2;
    fillRule = pfrNonZero
): bool =
  ## Tests the implicitly closed fill area. Boundary ownership follows the
  ## half-open scanline rule so adjacent contours do not double-count edges.
  var winding = 0
  var crossings = 0
  for contour in contours:
    if contour.points.len < 3:
      continue
    for index in 0 ..< contour.points.len:
      let first = contour.points[index]
      let second = contour.points[(index + 1) mod contour.points.len]
      if (first.y > point.y) == (second.y > point.y):
        continue
      let edgeX = first.x +
        (point.y - first.y) * (second.x - first.x) / (second.y - first.y)
      if edgeX <= point.x:
        continue
      if fillRule == pfrEvenOdd:
        inc crossings
      elif second.y > first.y:
        inc winding
      else:
        dec winding
  if fillRule == pfrEvenOdd:
    crossings mod 2 == 1
  else:
    winding != 0

type
  PathScanIntersection = object
    x: float32
    winding: int8

  PathFillScratch* = object
    intersections: seq[PathScanIntersection]

proc fillPathCoverageRow*(
    contours: openArray[FlattenedPathContour];
    y, xStart, xEnd: int;
    fillRule: PathFillRule;
    coverage: var seq[uint8];
    scratch: var PathFillScratch
) =
  ## Produces four-sample antialias coverage in linear scanline time. The
  ## output stores one bit per sample for every pixel in `[xStart, xEnd)`.
  let width = max(0, xEnd - xStart)
  coverage.setLen(width)
  for index in 0 ..< coverage.len:
    coverage[index] = 0
  if width == 0:
    return

  const offsets = [0.25'f32, 0.75'f32]
  for offsetYIndex, offsetY in offsets:
    scratch.intersections.setLen(0)
    let sampleY = y.float32 + offsetY
    for contour in contours:
      if contour.points.len < 3:
        continue
      for index in 0 ..< contour.points.len:
        let first = contour.points[index]
        let second = contour.points[(index + 1) mod contour.points.len]
        if (first.y > sampleY) == (second.y > sampleY):
          continue
        scratch.intersections.add PathScanIntersection(
          x: first.x +
            (sampleY - first.y) * (second.x - first.x) /
              (second.y - first.y),
          winding: (if second.y > first.y: 1'i8 else: -1'i8)
        )
    scratch.intersections.sort(
      proc(a, b: PathScanIntersection): int = cmp(a.x, b.x)
    )

    for offsetXIndex, offsetX in offsets:
      var nextIntersection = 0
      var winding = 0
      var crossings = 0
      for localX in 0 ..< width:
        let sampleX = (xStart + localX).float32 + offsetX
        while nextIntersection < scratch.intersections.len and
            scratch.intersections[nextIntersection].x <= sampleX:
          if fillRule == pfrEvenOdd:
            inc crossings
          else:
            winding += scratch.intersections[nextIntersection].winding.int
          inc nextIntersection
        if (fillRule == pfrEvenOdd and crossings mod 2 == 1) or
            (fillRule == pfrNonZero and winding != 0):
          coverage[localX] = coverage[localX] or
            (1'u8 shl (offsetYIndex * offsets.len + offsetXIndex))

proc fillPathCoverageRow*(
    contours: openArray[FlattenedPathContour];
    y, xStart, xEnd: int;
    fillRule: PathFillRule;
    coverage: var seq[uint8]
) =
  ## Convenience overload for callers that render only one scanline.
  var scratch: PathFillScratch
  contours.fillPathCoverageRow(
    y, xStart, xEnd, fillRule, coverage, scratch
  )

proc pathCoverageCount*(coverageMask: uint8): int {.inline.} =
  ## Counts the four antialias samples encoded by `fillPathCoverageRow`.
  const sampleCounts = [
    0'u8, 1, 1, 2,
    1, 2, 2, 3,
    1, 2, 2, 3,
    2, 3, 3, 4
  ]
  sampleCounts[int(coverageMask and 0x0F'u8)].int

proc bounds*(path: Path2D; tolerance = 0.25'f32): Rect =
  var initialized = false
  var left, top, right, bottom: float32
  for contour in path.flattened(tolerance):
    for point in contour.points:
      if not initialized:
        left = point.x
        right = point.x
        top = point.y
        bottom = point.y
        initialized = true
      else:
        left = min(left, point.x)
        right = max(right, point.x)
        top = min(top, point.y)
        bottom = max(bottom, point.y)
  if initialized:
    rect(left, top, right - left, bottom - top)
  else:
    rect(0, 0, 0, 0)
