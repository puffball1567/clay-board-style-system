# Color Model

CBSS separates authored colors from resolved paint colors.

- `ColorValue` retains the declared color space, three components, and alpha.
- `Color` remains the compact 16-byte RGBA value consumed by current paint
  backends and the existing C ABI.
- Conversion happens when a color is resolved for an output backend. An
  authored wide-gamut value is not silently reinterpreted as sRGB.

## Typed Authoring

The initial typed surface includes:

- `srgb(...)` and `srgbLinear(...)`
- `displayP3(...)`, `a98Rgb(...)`, `proPhotoRgb(...)`, and `rec2020(...)`
- `xyzD50(...)` and `xyzD65(...)`
- `hsl(...)` and `hwb(...)`
- `lab(...)`, `lch(...)`, `oklab(...)`, and `oklch(...)`
- `currentColor()` for late foreground-color resolution

RGB and XYZ component values use the ranges defined by their color spaces.
HSL and HWB saturation, lightness, whiteness, and blackness are expressed as
percent values. CIE Lab lightness uses the 0 to 100 scale. Oklab lightness uses
the 0 to 1 scale. Hue arguments are degrees and may be outside one turn.

Finite out-of-range components are retained because color conversion and
interpolation can legitimately produce colors outside the destination gamut.
`NaN` and infinite components are rejected by typed constructors.

## Resolution And Interpolation

`resolveColor` converts an authored value to the current SDR sRGB paint
boundary. The default gamut policy reduces Oklch chroma while preserving
lightness and hue. `cgmClip` is available where explicit channel clipping is
required.

`interpolateColor` supports sRGB, linear-light sRGB, and Oklab interpolation.
Alpha is premultiplied before component interpolation. The endpoints return
the independently resolved endpoint colors without an avoidable conversion
round trip.

This module is the numerical foundation. Serialized CSS color parsing, named
colors, style-property integration, browser comparison fixtures, C ABI input
handles, and optional Pixie output are separate implementation units built on
this contract.

## Conformance Source

The transfer functions, color-space matrices, D50/D65 adaptation, and
interpolation rules follow the W3C
[CSS Color Module Level 4](https://www.w3.org/TR/css-color-4/). Tests use
published reference primaries and white points rather than backend-specific
color behavior.
