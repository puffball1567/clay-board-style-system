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
This preserves authored intent during cross-space interpolation. Version 0.3
classifies analogous components before conversion and carries a numeric
counterpart into a missing component before alpha premultiplication. It also
implements the CSS rule that carries a fully missing remaining component set,
such as Oklch chroma and hue, into the corresponding Oklab `a` and `b` set.

The single-color parser deliberately does not accept deprecated system colors,
relative color syntax, `calc()`, `var()`, or CSS comments. `color-mix()` uses
the separate `parseColorMix` boundary described below because it produces a
deferred color expression rather than one authored color. CBSS Nim values and
constants remain the theme/value-indirection mechanism; neither parser
introduces a browser cascade or a CSS custom-property runtime. These
boundaries produce explicit errors rather than silently degrading to another
color.

## Style Declarations

Typed and parsed `ColorValue` instances can be passed through the existing
`colorValue(...)` declaration helper. Solid color properties resolve the
authored color into the compact 16-byte `Color` stored by `ComputedStyle`:

```nim
let accent = parseColorOrRaise("oklch(68% 0.17 245deg)")
let panelStyle = styleContext([
  decl("color", accent),
  decl("border-color", currentColor()),
  decl("background-color", displayP3(0.12, 0.18, 0.28))
])
```

The direct `decl` overload is preferred when the value is unambiguously a
solid color. `colorValue(...)` remains available for explicit construction and
for composition with helpers that accept a general `StyleValue`.

Foreground `color` declarations are resolved before other properties. This
makes `currentColor` independent of declaration order and lets a child use its
inherited foreground when no local color is declared. The conversion occurs
during style resolution; paint and hit-test passes do not retain or repeatedly
convert the authored value.

The same authored-color path covers solid background, border, outline, input,
text-decoration, text-emphasis, column-rule, vector, scrollbar-pair, and
structured border/shadow values. Gradient-stop interpolation remains a
separate color unit because it requires defined missing-component and
interpolation-space behavior.

## Resolution And Interpolation

`resolveColor` converts an authored value to the current SDR sRGB paint
boundary. The default gamut policy reduces Oklch chroma while preserving
lightness and hue. `cgmClip` is available where explicit channel clipping is
required.

`interpolateColor` supports sRGB, linear-light sRGB, and Oklab interpolation.
Alpha is premultiplied before component interpolation. The endpoints return
the independently resolved endpoint colors without an avoidable conversion
round trip.

The numerical model, serialized parser, and solid style-property integration
remain independent implementation units. Browser comparison fixtures, C ABI
input handles, gradient color spaces, and optional Pixie output remain
separate units built on this contract.

## Color Mixing

`ColorMixValue` retains both authored endpoints, the interpolation space,
normalized weights, and any alpha multiplier. It resolves only when consumed,
so `currentColor` continues to use the foreground from the relevant style
context.

```nim
let accent = colorMix(
  currentColor(), 30,
  displayP3(0.1, 0.45, 0.9), 70,
  cisOklab
)

let panelStyle = styleContext([
  decl("color", rgb(0.9, 0.9, 0.95)),
  decl("background-color", accent)
])
```

The typed API and `parseColorMix` implement the CSS Color 5 percentage rules:

- two omitted percentages become 50% each;
- one omitted percentage is the complement of the specified percentage;
- totals above 100% are normalized without increasing alpha;
- totals below 100% are normalized and multiply the result alpha; and
- negative, non-finite, over-100%, and all-zero inputs are rejected.

The initial interpolation-space surface is `cisSrgb`, `cisSrgbLinear`, and
`cisOklab`. Serialized input accepts the corresponding `srgb`, `srgb-linear`,
and `oklab` names:

```nim
let parsed = parseColorMix(
  "color-mix(in srgb-linear, currentColor 25%, #2677ff 75%)"
)
```

`parseColorMix` intentionally remains separate from `parseColor`: the former
returns `ColorMixValue`, while the latter returns one `ColorValue`. Both can be
passed directly to `decl` after successful parsing. Nested mixes, polar hue
interpolation methods, and additional interpolation spaces remain follow-up
units rather than silently using an incorrect fallback.

## Gradient Interpolation

Linear gradients use the same interpolation contract as `color-mix()`. The
existing `linearGradient(...)` helper retains its sRGB default for source
compatibility. `linearGradientIn(...)` selects a space explicitly:

```nim
let background = linearGradientIn(
  cisOklab,
  135,
  colorStop(rgb(0.95, 0.18, 0.12), 0),
  colorStop(rgb(0.10, 0.32, 0.95), 100)
)
```

The selected space survives style resolution and paint-command generation.
SDL3 and the deterministic PPM backend share one sampler, including
premultiplied-alpha handling, instead of maintaining backend-specific color
math. SDL3 also includes the interpolation space in its baked texture cache
key. Raster backends prepare stop conversions once and use a projected-pixel
lookup capped at 2,048 samples. This avoids doing color-space matrices and
gamut mapping per output pixel while keeping lookup error within one RGBA8
channel step in the conformance tests. Gradient declarations may mix resolved
colors with authored `ColorValue`, `currentColor`, and `ColorMixValue` stops.
Authored stops resolve during style computation, after the foreground color is
known; computed and paint data keep the existing resolved `GradientStop`
representation. Serialized CSS gradient syntax remains a separate follow-up
input unit.

```nim
let background = linearGradientIn(
  cisOklab,
  110,
  colorStop(displayP3(0.94, 0.22, 0.08), 0),
  colorStop(currentColor(), 45),
  colorStop(colorMix(oklch(0.72, 0.16, 42), rec2020(0.1, 0.7, 0.3)), 100)
)
```

C ABI version `0x00010001` adds opaque authored-color handles. Foreign callers
can construct typed color-space values and `currentColor`, parse supported CSS
color and `color-mix()` syntax, resolve a value for inspection, and copy it
into a style declaration. The original 16-byte `CbssColor` and existing RGBA
setter remain unchanged. The additive gradient setter selects an interpolation
space, which is also emitted in renderer-neutral paint commands.
`cbss_style_set_linear_gradient_color_values` accepts opaque authored-color
handles as stops and copies their values into the style, so callers may destroy
the handles immediately after a successful call.

## Conformance Source

The transfer functions, color-space matrices, D50/D65 adaptation, and base
interpolation rules follow the W3C
[CSS Color Module Level 4](https://www.w3.org/TR/css-color-4/). Color-mix
percentage normalization follows
[CSS Color Module Level 5](https://www.w3.org/TR/css-color-5/). Tests use
published reference primaries and white points rather than backend-specific
color behavior.

## Browser Comparison Fixtures

`tests/fixtures/color/browser_reference.html` captures serialized color,
color-mix, alpha-composition, and wide-gamut values through a one-pixel sRGB
Canvas boundary. `browser_visual_reference.html` renders the corresponding
values as ordinary CSS backgrounds so the Canvas result can be checked against
actual browser paint. The pinned Chrome 150 Linux values live in
`chrome_150_linux_srgb.json`; the portable Nim test consumes only that data, so
Chrome is not a runtime or product dependency.

Chrome 150 exposes channel-clipped sRGB at this boundary. The fixture therefore
compares against explicit `cgmClip` conversion while CBSS retains Oklch chroma
reduction as its default perceptual gamut policy. Exact or two-step RGBA8
tolerances cover quantization and premultiplied readback. Rec.2020 is recorded
as a named divergence: Chrome 150's output does not match the current CSS Color
4 BT.1886 2.4 transfer used by CBSS. The fixture stores both results and tests
them independently instead of weakening the tolerance for every color.
