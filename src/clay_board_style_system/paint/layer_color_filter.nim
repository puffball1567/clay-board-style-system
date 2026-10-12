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
