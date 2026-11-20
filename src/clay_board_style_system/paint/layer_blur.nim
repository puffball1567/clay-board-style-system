## Shared binomial Gaussian kernel for premultiplied UI layer pixels.
import std/math

const
  MaxLayerBlurRadius* = 16
  MaxFilteredLayerBytes* = 64'u64 * 1024 * 1024

type LayerBlurRadius* = range[0 .. MaxLayerBlurRadius]

proc layerBlurWeights*(radius: LayerBlurRadius): array[MaxLayerBlurRadius + 1, float32] =
  ## The symmetric half of the normalized binomial kernel.
  let n = radius.int * 2
  let divisor = float64(1'u64 shl n)
  var coefficient = 1'u64
  for position in 0 .. n:
    if position >= radius.int:
      result[position - radius.int] = float32(float64(coefficient) / divisor)
    if position < n:
      coefficient = coefficient * uint64(n - position) div uint64(position + 1)

proc blurLayerPass(
    source: openArray[uint8];
    destination: var openArray[uint8];
    width, height, radius: int;
    weights: array[MaxLayerBlurRadius + 1, float32];
    horizontal: bool
) =
  for y in 0 ..< height:
    for x in 0 ..< width:
      let center = (y * width + x) * 4
      var blurred: array[4, float32]
      for channel in 0 ..< 4:
        blurred[channel] = source[center + channel].float32 * weights[0]
      for step in 1 .. radius:
        let left =
          if horizontal: (y * width + max(0, x - step)) * 4
          else: (max(0, y - step) * width + x) * 4
        let right =
          if horizontal: (y * width + min(width - 1, x + step)) * 4
          else: (min(height - 1, y + step) * width + x) * 4
        for channel in 0 ..< 4:
          blurred[channel] += source[right + channel].float32 * weights[step]
          blurred[channel] += source[left + channel].float32 * weights[step]
      for channel in 0 ..< 4:
        destination[center + channel] = uint8(clamp(round(blurred[channel]).int, 0, 255))

proc blurPremultipliedRgba8*(
    pixels: var openArray[uint8];
    width, height: int;
    radius: LayerBlurRadius
) =
  ## Separable, clamped-edge blur over tightly packed premultiplied RGBA8.
  if radius == 0:
    return
  if width <= 0 or height <= 0 or pixels.len mod 4 != 0 or
      width > pixels.len div 4 div height or width * height != pixels.len div 4:
    raise newException(ValueError, "blur requires tightly packed RGBA8 storage")
  let weights = layerBlurWeights(radius)
  var horizontal = newSeq[uint8](pixels.len)
  blurLayerPass(pixels, horizontal, width, height, radius.int, weights, true)
  blurLayerPass(horizontal, pixels, width, height, radius.int, weights, false)
