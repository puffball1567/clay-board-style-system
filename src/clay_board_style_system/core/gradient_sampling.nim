import std/math

import ./[color, color_conversion, computed_style]

type
  PreparedGradientStop* = object
    color*: Color
    interpolation*: PreparedColorInterpolation
    offset*: float32

  PreparedGradientSampler* = object
    stops*: seq[PreparedGradientStop]

  GradientLookupTable* = object
    colors*: seq[Color]

proc prepareGradientSampler*(gradient: LinearGradient): PreparedGradientSampler =
  result.stops = newSeqOfCap[PreparedGradientStop](gradient.stops.len)
  for stop in gradient.stops:
    result.stops.add PreparedGradientStop(
      color: stop.color,
      interpolation: stop.color.prepareColorInterpolation(
        gradient.interpolationSpace),
      offset: stop.offset
    )

proc gradientColorAt*(
    sampler: PreparedGradientSampler;
    progress: SomeNumber
): Color =
  if sampler.stops.len == 0:
    return rgba(0, 0, 0, 0)
  if sampler.stops.len == 1:
    return sampler.stops[0].color

  let position = clamp(progress.float32, 0.0'f32, 1.0'f32) * 100.0'f32
  var previous = sampler.stops[0]
  if position <= previous.offset:
    return previous.color

  for index in 1 ..< sampler.stops.len:
    let current = sampler.stops[index]
    if position <= current.offset:
      let span = current.offset - previous.offset
      if span <= 0.0'f32:
        return current.color
      return interpolateColor(
        previous.interpolation,
        current.interpolation,
        (position - previous.offset) / span
      )
    previous = current
  sampler.stops[^1].color

proc gradientColorAt*(gradient: LinearGradient; progress: SomeNumber): Color =
  gradient.prepareGradientSampler.gradientColorAt(progress)

proc buildGradientLookup*(
    sampler: PreparedGradientSampler;
    sampleCount: int
): GradientLookupTable =
  let count = max(2, sampleCount)
  result.colors = newSeq[Color](count)
  for index in 0 ..< count:
    result.colors[index] = sampler.gradientColorAt(
      index.float32 / (count - 1).float32
    )

proc gradientLookupSampleCount*(spanPixels: SomeNumber): int =
  clamp(int(ceil(max(0.0, spanPixels.float64) * 2.0)) + 1, 2, 2_048)

proc gradientColorAt*(table: GradientLookupTable; progress: SomeNumber): Color =
  if table.colors.len == 0:
    return rgba(0, 0, 0, 0)
  if table.colors.len == 1:
    return table.colors[0]
  let index = round(
    clamp(progress.float32, 0.0'f32, 1.0'f32) *
      (table.colors.len - 1).float32
  ).int
  table.colors[index]
