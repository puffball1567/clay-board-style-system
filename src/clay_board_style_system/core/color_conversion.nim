import std/math

import ./[color, color_value]

type
  ColorGamutMap* = enum
    cgmClip,
    cgmOklchChromaReduction

  ColorInterpolationSpace* = enum
    cisSrgb,
    cisSrgbLinear,
    cisOklab

  Vec3 = array[3, float64]
  Matrix3 = array[3, array[3, float64]]

const
  D50ToD65: Matrix3 = [
    [0.955473421488075, -0.023098454948765, 0.0632592432005707],
    [-0.0283697093338637, 1.0099953980813, 0.0210414411919173],
    [0.0123140148644819, -0.0205076492988989, 1.33036592624212]
  ]
  XyzD65ToSrgb: Matrix3 = [
    [12831.0 / 3959.0, -329.0 / 214.0, -1974.0 / 3959.0],
    [-851781.0 / 878810.0, 1648619.0 / 878810.0, 36519.0 / 878810.0],
    [705.0 / 12673.0, -2585.0 / 12673.0, 705.0 / 667.0]
  ]
  DisplayP3ToXyzD65: Matrix3 = [
    [608311.0 / 1250200.0, 189793.0 / 714400.0, 198249.0 / 1000160.0],
    [35783.0 / 156275.0, 247089.0 / 357200.0, 198249.0 / 2500400.0],
    [0.0, 32229.0 / 714400.0, 5220557.0 / 5000800.0]
  ]
  A98ToXyzD65: Matrix3 = [
    [573536.0 / 994567.0, 263643.0 / 1420810.0, 187206.0 / 994567.0],
    [591459.0 / 1989134.0, 6239551.0 / 9945670.0, 374412.0 / 4972835.0],
    [53769.0 / 1989134.0, 351524.0 / 4972835.0, 4929758.0 / 4972835.0]
  ]
  ProPhotoToXyzD50: Matrix3 = [
    [0.7977666449006423, 0.13518129740053308, 0.0313477341283922],
    [0.2880748288194013, 0.711835234241873, 0.00008993693872564],
    [0.0, 0.0, 0.8251046025104601]
  ]
  Rec2020ToXyzD65: Matrix3 = [
    [63426534.0 / 99577255.0, 20160776.0 / 139408157.0, 47086771.0 /
        278816314.0],
    [26158966.0 / 99577255.0, 472592308.0 / 697040785.0, 8267143.0 /
        139408157.0],
    [0.0, 19567812.0 / 697040785.0, 295819943.0 / 278816314.0]
  ]

proc clamp01(value: float64): float64 {.inline.} =
  max(0.0, min(1.0, value))

proc multiply(matrix: Matrix3; value: Vec3): Vec3 =
  for row in 0 .. 2:
    result[row] =
      matrix[row][0] * value[0] +
      matrix[row][1] * value[1] +
      matrix[row][2] * value[2]

proc signedPow(value, exponent: float64): float64 =
  if value < 0: -pow(-value, exponent) else: pow(value, exponent)

proc linearizeSrgb(value: float64): float64 =
  let magnitude = abs(value)
  if magnitude <= 0.04045:
    value / 12.92
  else:
    copySign(pow((magnitude + 0.055) / 1.055, 2.4), value)

proc encodeSrgb(value: float64): float64 =
  let magnitude = abs(value)
  if magnitude > 0.0031308:
    copySign(1.055 * pow(magnitude, 1.0 / 2.4) - 0.055, value)
  else:
    12.92 * value

proc hslToSrgb(components: Vec3): Vec3 =
  var hue = components[0] mod 360.0
  if hue < 0:
    hue += 360.0
  let saturation = max(0.0, components[1] / 100.0)
  let lightness = components[2] / 100.0
  let a = saturation * min(lightness, 1.0 - lightness)

  proc channel(offset: float64): float64 =
    let k = (offset + hue / 30.0) mod 12.0
    lightness - a * max(-1.0, min(k - 3.0, min(9.0 - k, 1.0)))

  [channel(0), channel(8), channel(4)]

proc hwbToSrgb(components: Vec3): Vec3 =
  var white = max(0.0, components[1] / 100.0)
  var black = max(0.0, components[2] / 100.0)
  if white + black >= 1.0:
    let gray = white / (white + black)
    return [gray, gray, gray]
  let pure = hslToSrgb([components[0], 100.0, 50.0])
  let factor = 1.0 - white - black
  for index in 0 .. 2:
    result[index] = pure[index] * factor + white

proc lchToLab(components: Vec3): Vec3 =
  let angle = components[2] * PI / 180.0
  [components[0], components[1] * cos(angle), components[1] * sin(angle)]

proc oklchToOklab(components: Vec3): Vec3 =
  let angle = components[2] * PI / 180.0
  [components[0], components[1] * cos(angle), components[1] * sin(angle)]

proc labToXyzD50(lab: Vec3): Vec3 =
  const
    kappa = 24389.0 / 27.0
    epsilon = 216.0 / 24389.0
    d50: Vec3 = [0.3457 / 0.3585, 1.0, (1.0 - 0.3457 - 0.3585) / 0.3585]
  let fy = (lab[0] + 16.0) / 116.0
  let f: Vec3 = [lab[1] / 500.0 + fy, fy, fy - lab[2] / 200.0]
  let x = if pow(f[0], 3) > epsilon: pow(f[0], 3) else: (116.0 * f[0] - 16.0) / kappa
  let y = if lab[0] > kappa * epsilon: pow((lab[0] + 16.0) / 116.0,
      3) else: lab[0] / kappa
  let z = if pow(f[2], 3) > epsilon: pow(f[2], 3) else: (116.0 * f[2] - 16.0) / kappa
  [x * d50[0], y * d50[1], z * d50[2]]

proc oklabToLinearSrgb(oklab: Vec3): Vec3 =
  let l = pow(oklab[0] + 0.3963377773761749 * oklab[1] + 0.2158037573099136 *
      oklab[2], 3)
  let m = pow(oklab[0] - 0.1055613458156586 * oklab[1] - 0.0638541728258133 *
      oklab[2], 3)
  let s = pow(oklab[0] - 0.0894841775298119 * oklab[1] - 1.2914855480194092 *
      oklab[2], 3)
  [
    4.076741661347994 * l - 3.3077115913 * m + 0.230969929981 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
  ]

proc linearSrgbToOklab(rgb: Vec3): Vec3 =
  let l = 0.4122214708 * rgb[0] + 0.5363325363 * rgb[1] + 0.0514459929 * rgb[2]
  let m = 0.2119034982 * rgb[0] + 0.6806995451 * rgb[1] + 0.1073969566 * rgb[2]
  let s = 0.0883024619 * rgb[0] + 0.2817188376 * rgb[1] + 0.6299787005 * rgb[2]
  let lRoot = cbrt(l)
  let mRoot = cbrt(m)
  let sRoot = cbrt(s)
  [
    0.2104542553 * lRoot + 0.793617785 * mRoot - 0.0040720468 * sRoot,
    1.9779984951 * lRoot - 2.428592205 * mRoot + 0.4505937099 * sRoot,
    0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.808675766 * sRoot
  ]

proc linearizeA98(value: float64): float64 =
  signedPow(value, 563.0 / 256.0)

proc linearizeProPhoto(value: float64): float64 =
  let magnitude = abs(value)
  if magnitude <= 16.0 / 512.0:
    value / 16.0
  else:
    signedPow(value, 1.8)

proc linearizeRec2020(value: float64): float64 =
  signedPow(value, 2.4)

proc colorToSrgbComponents(color: Color): Vec3 =
  [color.r.float64, color.g.float64, color.b.float64]

proc rawLinearSrgb(value: ColorValue; current: Color): Vec3 =
  if value.kind == cvCurrentColor:
    let components = colorToSrgbComponents(current)
    return [
      linearizeSrgb(components[0]),
      linearizeSrgb(components[1]),
      linearizeSrgb(components[2])
    ]

  let components = value.components
  case value.space
  of csSrgb:
    result = [linearizeSrgb(components[0]), linearizeSrgb(components[1]),
        linearizeSrgb(components[2])]
  of csSrgbLinear:
    result = components
  of csDisplayP3:
    let linear = [linearizeSrgb(components[0]), linearizeSrgb(components[1]),
        linearizeSrgb(components[2])]
    result = multiply(XyzD65ToSrgb, multiply(DisplayP3ToXyzD65, linear))
  of csA98Rgb:
    let linear = [linearizeA98(components[0]), linearizeA98(components[1]),
        linearizeA98(components[2])]
    result = multiply(XyzD65ToSrgb, multiply(A98ToXyzD65, linear))
  of csProPhotoRgb:
    let linear = [linearizeProPhoto(components[0]), linearizeProPhoto(
        components[1]), linearizeProPhoto(components[2])]
    result = multiply(XyzD65ToSrgb, multiply(D50ToD65, multiply(
        ProPhotoToXyzD50, linear)))
  of csRec2020:
    let linear = [linearizeRec2020(components[0]), linearizeRec2020(components[
        1]), linearizeRec2020(components[2])]
    result = multiply(XyzD65ToSrgb, multiply(Rec2020ToXyzD65, linear))
  of csXyzD50:
    result = multiply(XyzD65ToSrgb, multiply(D50ToD65, components))
  of csXyzD65:
    result = multiply(XyzD65ToSrgb, components)
  of csHsl:
    let srgbComponents = hslToSrgb(components)
    result = [linearizeSrgb(srgbComponents[0]), linearizeSrgb(srgbComponents[
        1]), linearizeSrgb(srgbComponents[2])]
  of csHwb:
    let srgbComponents = hwbToSrgb(components)
    result = [linearizeSrgb(srgbComponents[0]), linearizeSrgb(srgbComponents[
        1]), linearizeSrgb(srgbComponents[2])]
  of csLab:
    result = multiply(XyzD65ToSrgb, multiply(D50ToD65, labToXyzD50(components)))
  of csLch:
    result = multiply(XyzD65ToSrgb, multiply(D50ToD65, labToXyzD50(lchToLab(components))))
  of csOklab:
    result = oklabToLinearSrgb(components)
  of csOklch:
    result = oklabToLinearSrgb(oklchToOklab(components))

proc alphaOf(value: ColorValue; current: Color): float64 =
  if value.kind == cvCurrentColor: current.a.float64 else: value.alpha

proc inSrgbGamut(linear: Vec3): bool =
  for channel in linear:
    if channel < -1e-7 or channel > 1.0 + 1e-7:
      return false
  true

proc clipLinear(linear: Vec3): Vec3 =
  [clamp01(linear[0]), clamp01(linear[1]), clamp01(linear[2])]

proc mapOklchChroma(linear: Vec3): Vec3 =
  if linear.inSrgbGamut:
    return linear
  var oklabValue = linearSrgbToOklab(linear)
  if oklabValue[0] >= 1.0:
    return [1.0, 1.0, 1.0]
  if oklabValue[0] <= 0.0:
    return [0.0, 0.0, 0.0]
  let originalChroma = hypot(oklabValue[1], oklabValue[2])
  if originalChroma <= 1e-9:
    return clipLinear(linear)
  let hue = arctan2(oklabValue[2], oklabValue[1])
  var low = 0.0
  var high = originalChroma
  var best = oklabToLinearSrgb([oklabValue[0], 0.0, 0.0])
  for _ in 0 ..< 24:
    let chroma = (low + high) * 0.5
    let candidate = oklabToLinearSrgb([
      oklabValue[0], chroma * cos(hue), chroma * sin(hue)
    ])
    if candidate.inSrgbGamut:
      low = chroma
      best = candidate
    else:
      high = chroma
  clipLinear(best)

proc toLinearSrgb*(
    value: ColorValue;
    current: Color = rgb(0, 0, 0);
    gamutMap = cgmOklchChromaReduction
): array[3, float64] =
  let linear = rawLinearSrgb(value, current)
  case gamutMap
  of cgmClip: clipLinear(linear)
  of cgmOklchChromaReduction: mapOklchChroma(linear)

proc resolveColor*(
    value: ColorValue;
    current: Color = rgb(0, 0, 0);
    gamutMap = cgmOklchChromaReduction
): Color =
  let linear = value.toLinearSrgb(current, gamutMap)
  rgba(
    clamp01(encodeSrgb(linear[0])).float32,
    clamp01(encodeSrgb(linear[1])).float32,
    clamp01(encodeSrgb(linear[2])).float32,
    clamp01(value.alphaOf(current)).float32
  )

proc toOklab*(value: ColorValue; current: Color = rgb(0, 0, 0)): array[3, float64] =
  linearSrgbToOklab(rawLinearSrgb(value, current))

proc interpolateColor*(
    first, second: ColorValue;
    progress: SomeNumber;
    space = cisOklab;
    current: Color = rgb(0, 0, 0)
): Color =
  let t = clamp01(progress.float64)
  if t <= 0.0:
    return first.resolveColor(current)
  if t >= 1.0:
    return second.resolveColor(current)
  let firstAlpha = clamp01(first.alphaOf(current))
  let secondAlpha = clamp01(second.alphaOf(current))
  let alpha = firstAlpha * (1.0 - t) + secondAlpha * t

  var left, right: Vec3
  case space
  of cisSrgb:
    let leftLinear = rawLinearSrgb(first, current)
    let rightLinear = rawLinearSrgb(second, current)
    left = [encodeSrgb(leftLinear[0]), encodeSrgb(leftLinear[1]), encodeSrgb(
        leftLinear[2])]
    right = [encodeSrgb(rightLinear[0]), encodeSrgb(rightLinear[1]), encodeSrgb(
        rightLinear[2])]
  of cisSrgbLinear:
    left = rawLinearSrgb(first, current)
    right = rawLinearSrgb(second, current)
  of cisOklab:
    left = first.toOklab(current)
    right = second.toOklab(current)

  var mixed: Vec3
  if alpha > 1e-12:
    for index in 0 .. 2:
      mixed[index] =
        (left[index] * firstAlpha * (1.0 - t) + right[index] * secondAlpha *
            t) / alpha

  var linear: Vec3
  case space
  of cisSrgb:
    linear = [linearizeSrgb(mixed[0]), linearizeSrgb(mixed[1]), linearizeSrgb(
        mixed[2])]
  of cisSrgbLinear:
    linear = mixed
  of cisOklab:
    linear = oklabToLinearSrgb(mixed)
  linear = mapOklchChroma(linear)
  rgba(
    clamp01(encodeSrgb(linear[0])).float32,
    clamp01(encodeSrgb(linear[1])).float32,
    clamp01(encodeSrgb(linear[2])).float32,
    alpha.float32
  )
