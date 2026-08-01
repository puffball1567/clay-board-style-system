import std/math

import ./color

type
  ColorSpace* = enum
    csSrgb,
    csSrgbLinear,
    csDisplayP3,
    csA98Rgb,
    csProPhotoRgb,
    csRec2020,
    csXyzD50,
    csXyzD65,
    csHsl,
    csHwb,
    csLab,
    csLch,
    csOklab,
    csOklch

  ColorValueKind* = enum
    cvComponents,
    cvCurrentColor

  ColorValue* = object
    ## Author-facing color value. Components remain in their declared color
    ## space until a paint backend requests a resolved output color.
    case kind*: ColorValueKind
    of cvComponents:
      space*: ColorSpace
      components*: array[3, float64]
      alpha*: float64
    of cvCurrentColor:
      discard

proc colorIn*[First, Second, Third: SomeNumber](
    space: ColorSpace;
    first: First;
    second: Second;
    third: Third;
    alpha: float64 = 1.0
): ColorValue =
  for component in [first.float64, second.float64, third.float64, alpha]:
    if component.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "color components must be finite")
  ColorValue(
    kind: cvComponents,
    space: space,
    components: [first.float64, second.float64, third.float64],
    alpha: alpha.float64
  )

proc srgb*[Red, Green, Blue: SomeNumber](red: Red; green: Green; blue: Blue;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csSrgb, red, green, blue, alpha)

proc srgbLinear*[Red, Green, Blue: SomeNumber](red: Red; green: Green;
    blue: Blue; alpha: float64 = 1.0): ColorValue =
  colorIn(csSrgbLinear, red, green, blue, alpha)

proc displayP3*[Red, Green, Blue: SomeNumber](red: Red; green: Green;
    blue: Blue; alpha: float64 = 1.0): ColorValue =
  colorIn(csDisplayP3, red, green, blue, alpha)

proc a98Rgb*[Red, Green, Blue: SomeNumber](red: Red; green: Green; blue: Blue;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csA98Rgb, red, green, blue, alpha)

proc proPhotoRgb*[Red, Green, Blue: SomeNumber](red: Red; green: Green;
    blue: Blue; alpha: float64 = 1.0): ColorValue =
  colorIn(csProPhotoRgb, red, green, blue, alpha)

proc rec2020*[Red, Green, Blue: SomeNumber](red: Red; green: Green; blue: Blue;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csRec2020, red, green, blue, alpha)

proc xyzD50*[X, Y, Z: SomeNumber](x: X; y: Y; z: Z;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csXyzD50, x, y, z, alpha)

proc xyzD65*[X, Y, Z: SomeNumber](x: X; y: Y; z: Z;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csXyzD65, x, y, z, alpha)

proc hsl*[Hue, Saturation, Lightness: SomeNumber](hueDegrees: Hue;
    saturationPercent: Saturation; lightnessPercent: Lightness;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csHsl, hueDegrees, saturationPercent, lightnessPercent, alpha)

proc hwb*[Hue, Whiteness, Blackness: SomeNumber](hueDegrees: Hue;
    whitenessPercent: Whiteness; blacknessPercent: Blackness;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csHwb, hueDegrees, whitenessPercent, blacknessPercent, alpha)

proc lab*[Lightness, A, B: SomeNumber](lightness: Lightness; a: A; b: B;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csLab, lightness, a, b, alpha)

proc lch*[Lightness, Chroma, Hue: SomeNumber](lightness: Lightness;
    chroma: Chroma; hueDegrees: Hue; alpha: float64 = 1.0): ColorValue =
  colorIn(csLch, lightness, chroma, hueDegrees, alpha)

proc oklab*[Lightness, A, B: SomeNumber](lightness: Lightness; a: A; b: B;
    alpha: float64 = 1.0): ColorValue =
  colorIn(csOklab, lightness, a, b, alpha)

proc oklch*[Lightness, Chroma, Hue: SomeNumber](lightness: Lightness;
    chroma: Chroma; hueDegrees: Hue; alpha: float64 = 1.0): ColorValue =
  colorIn(csOklch, lightness, chroma, hueDegrees, alpha)

proc currentColor*(): ColorValue =
  ColorValue(kind: cvCurrentColor)

proc authoredColor*(color: Color): ColorValue =
  srgb(color.r, color.g, color.b, color.a)
