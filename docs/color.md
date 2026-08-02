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
- `displayP3(...)`, `displayP3Linear(...)`, `a98Rgb(...)`,
  `proPhotoRgb(...)`, and `rec2020(...)`
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

## Serialized Authoring

`parseColor` is the boundary for design tokens, generated assets, external
styles, and web-to-native migration. It returns a `ColorParseResult`; invalid
input carries a typed error kind, a zero-based byte offset, and a diagnostic
message instead of raising an exception. `parseColorOrRaise` is available for
trusted authored constants where startup failure is preferable to recovery.

```nim
import std/options
import clay_board_style_system

let parsed = parseColor("oklch(62% 0.18 250deg / 90%)")
if parsed.isOk:
  let paintColor = parsed.value.get.resolveColor()
else:
  echo parsed.error.get.message
```

The Version 0.3 parser supports:

- strict `#RGB`, `#RGBA`, `#RRGGBB`, and `#RRGGBBAA` hexadecimal forms;
- all CSS named colors, `transparent`, and case-insensitive `currentColor`;
- modern and legacy `rgb()`/`rgba()` and `hsl()`/`hsla()` forms;
- modern `hwb()`, `lab()`, `lch()`, `oklab()`, and `oklch()` forms;
- `deg`, `grad`, `rad`, and `turn` hue units;
- `color()` with `srgb`, `srgb-linear`, `display-p3`,
  `display-p3-linear`, `a98-rgb`, `prophoto-rgb`, `rec2020`, `xyz`,
  `xyz-d65`, and `xyz-d50`; and
- the modern `none` keyword for missing components.

Missing components are stored separately from their numerical placeholder.
This preserves authored intent for future cross-space interpolation. Version
0.3 does not yet implement the CSS carry-forward rules for missing components
during interpolation.

The parser deliberately does not accept deprecated system colors, relative
color syntax, `color-mix()`, `calc()`, `var()`, or CSS comments. CBSS Nim
values and constants remain the theme/value-indirection mechanism; the parser
does not introduce a browser cascade or a CSS custom-property runtime. These
boundaries produce explicit errors rather than silently degrading to another
color.

## Resolution And Interpolation

`resolveColor` converts an authored value to the current SDR sRGB paint
boundary. The default gamut policy reduces Oklch chroma while preserving
lightness and hue. `cgmClip` is available where explicit channel clipping is
required.

`interpolateColor` supports sRGB, linear-light sRGB, and Oklab interpolation.
Alpha is premultiplied before component interpolation. The endpoints return
the independently resolved endpoint colors without an avoidable conversion
round trip.

The numerical model and serialized parser are independent from style-property
integration. Browser comparison fixtures, C ABI input handles, missing-value
interpolation, `color-mix()`, and optional Pixie output remain separate
implementation units built on this contract.

## Conformance Source

The transfer functions, color-space matrices, D50/D65 adaptation, and
interpolation rules follow the W3C
[CSS Color Module Level 4](https://www.w3.org/TR/css-color-4/). Tests use
published reference primaries and white points rather than backend-specific
color behavior.
