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
