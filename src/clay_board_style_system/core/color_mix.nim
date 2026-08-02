import std/[math, options]

import ./[color, color_conversion, color_value]

type
  ColorMixInput* = Color | ColorValue

  ColorMixValue* = object
    ## A resolved-at-use color mix. Keeping the authored endpoints allows
    ## currentColor to remain contextual until style resolution.
    first*, second*: ColorValue
    space*: ColorInterpolationSpace
    firstWeight*, secondWeight*: float64
    alphaMultiplier*: float64

proc validatePercentage(value: float64; name: string) =
  if value.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, name & " must be finite")
  if value < 0.0 or value > 100.0:
    raise newException(ValueError, name & " must be between 0 and 100")

proc normalizedColorMix*(
    first, second: ColorValue;
    firstPercent, secondPercent: Option[float64];
    space = cisOklab
): ColorMixValue =
  ## Applies CSS Color 5 percentage defaulting and normalization.
  var left = firstPercent
  var right = secondPercent
  if left.isNone and right.isNone:
    left = some(50.0)
    right = some(50.0)
  elif left.isNone:
    right.get.validatePercentage("second color percentage")
    left = some(100.0 - right.get)
  elif right.isNone:
    left.get.validatePercentage("first color percentage")
    right = some(100.0 - left.get)

  left.get.validatePercentage("first color percentage")
  right.get.validatePercentage("second color percentage")
  let total = left.get + right.get
  if total <= 0.0:
    raise newException(ValueError, "color mix percentages must not sum to zero")

  result = ColorMixValue(
    first: first,
    second: second,
    space: space,
    firstWeight: left.get / total,
    secondWeight: right.get / total,
    alphaMultiplier: min(total, 100.0) / 100.0
  )

proc authored(value: Color): ColorValue {.inline.} =
  authoredColor(value)

proc authored(value: ColorValue): ColorValue {.inline.} =
  value

proc colorMix*[First: ColorMixInput; Second: ColorMixInput](
    first: First; second: Second;
    space = cisOklab): ColorMixValue =
  normalizedColorMix(first.authored, second.authored, none(float64),
      none(float64), space)

proc colorMix*[First: ColorMixInput; Second: ColorMixInput](
    first: First; firstPercent: SomeNumber;
    second: Second; space = cisOklab): ColorMixValue =
  normalizedColorMix(first.authored, second.authored,
      some(firstPercent.float64), none(float64), space)

proc colorMix*[First: ColorMixInput; Second: ColorMixInput](
    first: First; firstPercent: SomeNumber;
    second: Second; secondPercent: SomeNumber;
    space = cisOklab): ColorMixValue =
  normalizedColorMix(first.authored, second.authored,
      some(firstPercent.float64),
      some(secondPercent.float64), space)

proc resolveColor*(mix: ColorMixValue;
    current: Color = rgb(0, 0, 0)): Color =
  result = interpolateColor(
    mix.first,
    mix.second,
    mix.secondWeight,
    mix.space,
    current
  )
  result.a = (result.a.float64 * mix.alphaMultiplier).float32
