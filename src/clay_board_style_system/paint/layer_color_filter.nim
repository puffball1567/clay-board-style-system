import std/math

import ../core/color

type LayerColorFilter* = ref object
  ## Immutable RGB matrix in encoded sRGB. Alpha and geometric coverage are
  ## preserved; nil is the identity filter. Each row is [R, G, B, offset].
  coefficients: array[12, float32]

const identityColorMatrix* = [
  1.0'f32, 0, 0, 0,
  0.0'f32, 1, 0, 0,
  0.0'f32, 0, 1, 0
]

proc colorMatrixFilter*(coefficients: array[12, float32]): LayerColorFilter =
  for value in coefficients:
    if value.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "layer color matrix must be finite")
  if coefficients != identityColorMatrix:
    result = LayerColorFilter(coefficients: coefficients)

proc validateColorFilterAmount(amount, maximum: float32; name: string) =
  if amount.classify in {fcNan, fcInf, fcNegInf} or
      amount < 0 or amount > maximum:
    raise newException(ValueError,
      name & " filter amount must be finite and between 0 and " & $maximum)

proc brightnessColorFilter*(amount: float32): LayerColorFilter =
  ## Encoded-sRGB brightness multiplier, bounded to 0..4.
  validateColorFilterAmount(amount, 4, "brightness")
  colorMatrixFilter([
    amount, 0'f32, 0, 0,
    0'f32, amount, 0, 0,
    0'f32, 0, amount, 0
  ])

proc contrastColorFilter*(amount: float32): LayerColorFilter =
  ## Encoded-sRGB contrast about the midpoint, bounded to 0..4.
  validateColorFilterAmount(amount, 4, "contrast")
  let offset = (1'f32 - amount) * 0.5'f32
  colorMatrixFilter([
    amount, 0'f32, 0, offset,
    0'f32, amount, 0, offset,
    0'f32, 0, amount, offset
  ])

proc saturationColorFilter*(amount: float32): LayerColorFilter =
  ## Encoded-sRGB saturation around Rec. 709 luma, bounded to 0..4.
  validateColorFilterAmount(amount, 4, "saturation")
  const lumaR = 0.2126'f32
  const lumaG = 0.7152'f32
  const lumaB = 0.0722'f32
  let gray = 1'f32 - amount
  colorMatrixFilter([
    gray * lumaR + amount, gray * lumaG, gray * lumaB, 0'f32,
    gray * lumaR, gray * lumaG + amount, gray * lumaB, 0'f32,
    gray * lumaR, gray * lumaG, gray * lumaB + amount, 0'f32
  ])

proc grayscaleColorFilter*(amount: float32): LayerColorFilter =
  ## Blend toward Rec. 709 luma in encoded sRGB, bounded to 0..1.
  validateColorFilterAmount(amount, 1, "grayscale")
  saturationColorFilter(1'f32 - amount)

proc invertColorFilter*(amount: float32): LayerColorFilter =
  ## Blend with encoded-sRGB channel inversion, bounded to 0..1.
  validateColorFilterAmount(amount, 1, "invert")
  let scale = 1'f32 - 2'f32 * amount
  colorMatrixFilter([
    scale, 0'f32, 0, amount,
    0'f32, scale, 0, amount,
    0'f32, 0, scale, amount
  ])

proc sameLayerColorFilter*(first, second: LayerColorFilter): bool =
  if first == second:
    return true
  if first.isNil or second.isNil:
    return false
  first.coefficients == second.coefficients

proc colorMatrixCoefficients*(filter: LayerColorFilter): array[12, float32] =
  ## Returns a value copy, so inspection cannot mutate retained commands.
  if filter.isNil: identityColorMatrix
  else: filter.coefficients

proc applyLayerColorFilter*(filter: LayerColorFilter; color: Color): Color =
  ## Input and output RGB are straight (not premultiplied). Clamp only after
  ## evaluating each row; float64 intermediates keep finite float32 matrices
  ## from overflowing during cancellation. Opacity is applied by composition.
  if filter.isNil:
    return color
  if color.a <= 0:
    return rgba(0, 0, 0, 0)
  var channels: array[3, float32]
  for row in 0 .. 2:
    let offset = row * 4
    channels[row] = float32(clamp(
      filter.coefficients[offset].float64 * color.r.float64 +
      filter.coefficients[offset + 1].float64 * color.g.float64 +
      filter.coefficients[offset + 2].float64 * color.b.float64 +
      filter.coefficients[offset + 3].float64,
      0.0, 1.0
    ))
  rgba(channels[0], channels[1], channels[2], color.a)
