import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc close(actual, expected: float32; tolerance = 0.0005'f32): bool =
  abs(actual - expected) <= tolerance

template checkColor(actualExpression: Color; red, green, blue: float32;
    alpha = 1.0'f32; tolerance = 0.0005'f32) =
  block:
    let actual = actualExpression
    check actual.r.close(red, tolerance)
    check actual.g.close(green, tolerance)
    check actual.b.close(blue, tolerance)
    check actual.a.close(alpha, tolerance)

proc parsed(input: string): ColorMixValue =
  let parsedResult = parseColorMix(input)
  require parsedResult.isOk
  require parsedResult.error.isNone
  parsedResult.value.get

proc rejected(input: string;
    kind: ColorMixParseErrorKind): ColorMixParseError =
  let parsedResult = parseColorMix(input)
  require not parsedResult.isOk
  require parsedResult.value.isNone
  require parsedResult.error.isSome
  check parsedResult.error.get.kind == kind
  parsedResult.error.get

suite "typed CSS-inspired color mixing":
  test "omitted percentages produce an equal mix":
    let mix = colorMix(srgb(1, 0, 0), srgb(0, 0, 1), cisSrgb)

    check mix.firstWeight == 0.5
    check mix.secondWeight == 0.5
    check mix.alphaMultiplier == 1.0
    mix.resolveColor.checkColor(0.5, 0, 0.5)

  test "resolved and authored endpoints can be mixed without wrappers":
    colorMix(rgb(1, 0, 0), rgb(0, 0, 1), cisSrgb).resolveColor.checkColor(
        0.5, 0, 0.5)
    colorMix(rgb(1, 0, 0), srgb(0, 0, 1), cisSrgb).resolveColor.checkColor(
        0.5, 0, 0.5)
    colorMix(srgb(1, 0, 0), rgb(0, 0, 1), cisSrgb).resolveColor.checkColor(
        0.5, 0, 0.5)

  test "one percentage uses the complement for the other color":
    let mix = colorMix(srgb(1, 0, 0), 25, srgb(0, 0, 1), cisSrgb)

    check mix.firstWeight == 0.25
    check mix.secondWeight == 0.75
    mix.resolveColor.checkColor(0.25, 0, 0.75)

  test "percentages over one hundred normalize without increasing alpha":
    let mix = colorMix(srgb(1, 0, 0), 80, srgb(0, 0, 1), 80, cisSrgb)

    check mix.firstWeight == 0.5
    check mix.secondWeight == 0.5
    check mix.alphaMultiplier == 1.0
    mix.resolveColor.checkColor(0.5, 0, 0.5)

  test "percentages below one hundred apply the specified alpha multiplier":
    let mix = colorMix(srgb(1, 0, 0), 20, srgb(0, 0, 1), 20, cisSrgb)

    check mix.firstWeight == 0.5
    check mix.secondWeight == 0.5
    check mix.alphaMultiplier == 0.4
    mix.resolveColor.checkColor(0.5, 0, 0.5, 0.4)

  test "mixing continues to premultiply endpoint alpha":
    let mix = colorMix(srgb(1, 0, 0, 0), srgb(0, 0, 1), cisSrgb)

    mix.resolveColor.checkColor(0, 0, 1, 0.5)

  test "currentColor remains unresolved until the mix is consumed":
    let mix = colorMix(currentColor(), srgb(0, 0, 0), cisSrgb)

    mix.resolveColor(rgb(0.4, 0.8, 0.2)).checkColor(0.2, 0.4, 0.1)

  test "invalid typed percentages fail before style resolution":
    expect ValueError:
      discard colorMix(srgb(1, 0, 0), -1, srgb(0, 0, 1), 50)
    expect ValueError:
      discard colorMix(srgb(1, 0, 0), 101, srgb(0, 0, 1), 50)
    expect ValueError:
      discard normalizedColorMix(srgb(1, 0, 0), srgb(0, 0, 1),
          some(0.0), some(0.0))
    expect ValueError:
      discard colorMix(srgb(1, 0, 0), NaN, srgb(0, 0, 1), 50)

suite "serialized CSS-inspired color mixing":
  test "the parser accepts default and explicit interpolation spaces":
    let defaultMix = parsed("color-mix(red, blue)")
    check defaultMix.space == cisOklab
    check defaultMix.firstWeight == 0.5
    check defaultMix.secondWeight == 0.5

    let linear = parsed(
      " color-mix(in srgb-linear, rgb(255 0 0) 25%, #0000ff 75%) "
    )
    check linear.space == cisSrgbLinear
    check linear.firstWeight == 0.25
    check linear.secondWeight == 0.75

    check parsed("color-mix(in\tsrgb, red, blue)").space == cisSrgb

  test "serialized percentages follow complement and alpha rules":
    let complement = parsed("color-mix(in srgb, red 20%, blue)")
    check complement.firstWeight == 0.2
    check complement.secondWeight == 0.8
    complement.resolveColor.checkColor(0.2, 0, 0.8)

    let translucent = parsed("color-mix(in srgb, red 20%, blue 20%)")
    translucent.resolveColor.checkColor(0.5, 0, 0.5, 0.4)

  test "nested color functions do not split their internal separators":
    let mix = parsed(
      "color-mix(in srgb, rgba(255, 0, 0, .5) 40%, hsl(240 100% 50%))"
    )
    check mix.firstWeight == 0.4
    check mix.secondWeight == 0.6
    mix.resolveColor.checkColor(0.25, 0, 0.75, 0.8)

  test "currentColor remains contextual after serialized parsing":
    let mix = parsed("color-mix(in srgb, currentColor 75%, black)")

    mix.resolveColor(rgb(0.8, 0.4, 0.2)).checkColor(0.6, 0.3, 0.15)

  test "serialized none components carry through color mixing":
    let mix = parsed("color-mix(in srgb, rgb(none 20% 40%), rgb(80% 60% 20%))")

    mix.resolveColor.checkColor(0.8, 0.4, 0.3)

  test "diagnostics reject malformed functions and percentages":
    check rejected("", cmpekEmpty).offset == 0
    check rejected("rgb(1 2 3)", cmpekUnknownFunction).offset == 0
    discard rejected("color-mix(in lab, red, blue)",
        cmpekInvalidInterpolationSpace)
    discard rejected("color-mix(in srgb, red)", cmpekInvalidArity)
    discard rejected("color-mix(in srgb, red -1%, blue)",
        cmpekInvalidPercentage)
    discard rejected("color-mix(in srgb, red 101%, blue)",
        cmpekInvalidPercentage)
    discard rejected("color-mix(in srgb, red 0%, blue 0%)",
        cmpekInvalidPercentage)
    discard rejected("color-mix(in srgb, unknown, blue)", cmpekInvalidColor)
    discard rejected("color-mix(in srgb, rgb(1 2 3), blue",
        cmpekUnbalancedFunction)

  test "raising parser is explicit for trusted constants":
    check parseColorMixOrRaise("color-mix(red, blue)").space == cisOklab
    expect ValueError:
      discard parseColorMixOrRaise("color-mix(red)")

suite "color mixing in style declarations":
  test "direct declarations resolve mixes through the computed style boundary":
    let mix = colorMix(currentColor(), srgb(0, 0, 0), cisSrgb)
    let context = styleContext([
      decl("background-color", mix),
      decl("color", rgb(0.8, 0.4, 0.2))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    require not diagnostics.hasErrors
    require style.box.backgroundColor.isSome
    style.box.backgroundColor.get.checkColor(0.4, 0.2, 0.1)

  test "structured border and shadow colors accept delayed mixes":
    let mix = colorMix(currentColor(), srgb(0, 0, 0), cisSrgb)
    let context = styleContext([
      decl("border", borderValue(px(2), "solid", mix)),
      decl("box-shadow", shadowValue(px(1), px(2), mix)),
      decl("color", rgb(0.6, 0.2, 0.8))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    require not diagnostics.hasErrors
    style.box.borderColors.top.get.checkColor(0.3, 0.1, 0.4)
    require style.box.boxShadow.isSome
    style.box.boxShadow.get.color.get.checkColor(0.3, 0.1, 0.4)
