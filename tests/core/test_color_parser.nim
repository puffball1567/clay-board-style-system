import std/[math, options, strutils, unittest]

import clay_board_style_system/core/[color_conversion, color_parser, color_value]

proc close(actual, expected: float64; tolerance = 1e-9): bool =
  abs(actual - expected) <= tolerance

proc parsed(input: string): ColorValue =
  let parsedResult = parseColor(input)
  require parsedResult.isOk
  require parsedResult.error.isNone
  parsedResult.value.get

proc rejected(input: string; kind: ColorParseErrorKind): ColorParseError =
  let parsedResult = parseColor(input)
  require not parsedResult.isOk
  require parsedResult.value.isNone
  require parsedResult.error.isSome
  check parsedResult.error.get.kind == kind
  parsedResult.error.get

suite "serialized CSS-inspired colors":
  test "strict hexadecimal forms expand RGB and alpha components":
    let shortRgb = parsed("#0f8")
    check shortRgb.space == csSrgb
    check shortRgb.components[0].close(0)
    check shortRgb.components[1].close(1)
    check shortRgb.components[2].close(136.0 / 255.0)
    check shortRgb.alpha.close(1)

    let shortRgba = parsed("#0f8c")
    check shortRgba.alpha.close(204.0 / 255.0)

    let longRgb = parsed(" #1020Ff ")
    check longRgb.components[0].close(16.0 / 255.0)
    check longRgb.components[1].close(32.0 / 255.0)
    check longRgb.components[2].close(1)

    let longRgba = parsed("#1020ff80")
    check longRgba.alpha.close(128.0 / 255.0)

  test "malformed hexadecimal values report the failing byte":
    check rejected("#12", cpekInvalidHex).offset == 0
    check rejected("  #12xz56", cpekInvalidHex).offset == 5
    check rejected("#12345", cpekInvalidHex).kind == cpekInvalidHex

  test "all standard named colors are accepted case-insensitively":
    let names = """
      aliceblue antiquewhite aqua aquamarine azure beige bisque black
      blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse
      chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan
      darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta
      darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen
      darkslateblue darkslategray darkslategrey darkturquoise darkviolet
      deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite
      forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green
      greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender
      lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan
      lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon
      lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue
      lightyellow lime limegreen linen magenta maroon mediumaquamarine
      mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue
      mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream
      mistyrose moccasin navajowhite navy oldlace olive olivedrab orange
      orangered orchid palegoldenrod palegreen paleturquoise palevioletred
      papayawhip peachpuff peru pink plum powderblue purple rebeccapurple red
      rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna
      silver skyblue slateblue slategray slategrey snow springgreen steelblue
      tan teal thistle tomato turquoise violet wheat white whitesmoke yellow
      yellowgreen
    """.splitWhitespace()
    check names.len == 148
    for name in names:
      check parseColor(name).isOk
    check parseColor("RebeccaPurple").isOk
    let rebecca = parsed("rebeccapurple")
    check rebecca.components == [102.0 / 255.0, 51.0 / 255.0, 153.0 / 255.0]

  test "transparent and currentColor retain their distinct semantics":
    let transparent = parsed("TrAnSpArEnT")
    check transparent.kind == cvComponents
    check transparent.components == [0.0, 0.0, 0.0]
    check transparent.alpha == 0
    check parsed("CURRENTCOLOR").kind == cvCurrentColor
    discard rejected("canvastext", cpekUnknownColor)

  test "modern rgb accepts mixed numeric forms and slash alpha":
    let value = parsed("rgb(255 50% 0 / 25%)")
    check value.space == csSrgb
    check value.components == [1.0, 0.5, 0.0]
    check value.alpha == 0.25

    let alias = parsed("RGBA(300 -20 127.5 / 2)")
    check alias.components == [1.0, 0.0, 0.5]
    check alias.alpha == 1

  test "modern rgb preserves explicitly missing components":
    let value = parsed("rgb(none 20% none / none)")
    check value.components == [0.0, 0.2, 0.0]
    check value.alpha == 0
    check value.missing == {ccFirst, ccThird, ccAlpha}

  test "legacy rgb accepts one component unit family only":
    check parsed("rgb(255, 0, 127)").components[2].close(127.0 / 255.0)
    check parsed("rgba(100%, 0%, 50%, .5)").alpha == 0.5
    discard rejected("rgb(255, 0%, 0)", cpekMixedLegacyUnits)
    discard rejected("rgb(none, 0, 0)", cpekUnexpectedToken)
    discard rejected("rgba(0, 0, 0, none)", cpekUnexpectedToken)
    discard rejected("rgb(1, 2, 3 / .5)", cpekUnexpectedToken)

  test "rgb separator and arity errors are deterministic":
    discard rejected("rgb(1 2)", cpekInvalidArity)
    discard rejected("rgb(1 2 3 4)", cpekInvalidArity)
    discard rejected("rgb(1 2 3, .5)", cpekUnexpectedToken)
    discard rejected("rgb(1-2 3)", cpekUnexpectedToken)

  test "rgb clamps alpha and accepts finite exponent notation":
    check parsed("rgb(1e2 2.55e2 0 / -1)").components == [100.0 / 255.0,
        1.0, 0.0]
    check parsed("rgb(0 0 0 / 200%)").alpha == 1
    discard rejected("rgb(1e999 0 0)", cpekInvalidNumber)
    discard rejected("rgb(+ 0 0)", cpekUnexpectedToken)

  test "hsl supports modern and legacy syntax plus angle units":
    let modern = parsed("hsl(.5turn 100 50% / 75%)")
    check modern.space == csHsl
    check modern.components == [180.0, 100.0, 50.0]
    check modern.alpha == 0.75

    let radians = parsed("hsl(3.141592653589793rad 100% 50%)")
    check radians.components[0].close(180)
    check parsed("hsl(-100grad 100% 50%)").components[0].close(270)
    check parsed("hsla(120, 100%, 50%, .2)").alpha == 0.2

  test "hsl clamps parsed saturation and lightness and rejects bad legacy units":
    let clamped = parsed("hsl(20 -10 120)")
    check clamped.components == [20.0, 0.0, 100.0]
    discard rejected("hsl(20, 10, 20%)", cpekInvalidUnit)
    discard rejected("hsla(20, 10%, 20%, none)", cpekUnexpectedToken)
    discard rejected("hsl(20%, 10% 20%)", cpekInvalidArity)

  test "hwb uses modern syntax and retains normalization inputs":
    let value = parsed("hwb(90deg 120% 40 / .4)")
    check value.space == csHwb
    check value.components == [90.0, 120.0, 40.0]
    check value.alpha == 0.4
    check parsed("hwb(none none 20%)").missing == {ccFirst, ccSecond}
    discard rejected("hwb(0, 0%, 0%)", cpekUnexpectedToken)
    discard rejected("hwb(0deg 10px 20%)", cpekInvalidUnit)
    discard rejected("hwb(20% 10% 20%)", cpekInvalidUnit)

  test "Lab and LCH map percentages to their reference ranges":
    let labValue = parsed("lab(120% 40% -20% / 50%)")
    check labValue.space == csLab
    check labValue.components == [100.0, 50.0, -25.0]
    check labValue.alpha == 0.5

    let lchValue = parsed("lch(-10 50% 1.5turn)")
    check lchValue.space == csLch
    check lchValue.components == [0.0, 75.0, 180.0]
    discard rejected("lab(50%, 0, 0)", cpekUnexpectedToken)

  test "Oklab and Oklch use their CSS percentage reference ranges":
    let labValue = parsed("oklab(50% 25% -50%)")
    check labValue.space == csOklab
    check labValue.components == [0.5, 0.1, -0.2]

    let lchValue = parsed("oklch(120% -2 450deg / none)")
    check lchValue.space == csOklch
    check lchValue.components == [1.0, 0.0, 90.0]
    check lchValue.missing == {ccAlpha}

  test "missing Lab-family components remain identifiable":
    let value = parsed("oklch(none none none / none)")
    check value.components == [0.0, 0.0, 0.0]
    check value.missing == {ccFirst, ccSecond, ccThird, ccAlpha}
    discard rejected("lab(50% 0deg 0)", cpekInvalidUnit)
    discard rejected("lch(50% 20 10%)", cpekInvalidUnit)

  test "color() supports every represented predefined color space":
    let cases = [
      ("srgb", csSrgb),
      ("srgb-linear", csSrgbLinear),
      ("display-p3", csDisplayP3),
      ("display-p3-linear", csDisplayP3Linear),
      ("a98-rgb", csA98Rgb),
      ("prophoto-rgb", csProPhotoRgb),
      ("rec2020", csRec2020),
      ("xyz", csXyzD65),
      ("xyz-d65", csXyzD65),
      ("xyz-d50", csXyzD50)
    ]
    for item in cases:
      let value = parsed("color(" & item[0] & " 1.2 -0.1 50% / 60%)")
      check value.space == item[1]
      check value.components == [1.2, -0.1, 0.5]
      check value.alpha == 0.6

  test "color() preserves missing values and rejects unknown spaces":
    let value = parsed("color(display-p3 none .2 none / none)")
    check value.missing == {ccFirst, ccThird, ccAlpha}
    discard rejected("color(acme-rgb 0 0 0)", cpekUnsupportedColorSpace)
    discard rejected("color(srgb, 0, 0, 0)", cpekUnexpectedToken)
    discard rejected("color(none 0 0 0)", cpekUnsupportedColorSpace)
    discard rejected("color(srgb 0 0)", cpekInvalidArity)
    discard rejected("color(srgb 0deg 0 0)", cpekInvalidUnit)

  test "parsed values resolve through the numerical color foundation":
    let red = parsed("hsl(0 100% 50%)").resolveColor()
    check red.r.close(1, 1e-6)
    check red.g.close(0, 1e-6)
    check red.b.close(0, 1e-6)
    let linearP3 = parsed("color(display-p3-linear 1 1 1)").resolveColor()
    check linearP3.r.close(1, 1e-6)
    check linearP3.g.close(1, 1e-6)
    check linearP3.b.close(1, 1e-6)

  test "diagnostics distinguish empty unknown malformed and trailing input":
    check rejected("  ", cpekEmpty).offset == 2
    check rejected("not-a-color", cpekUnknownColor).offset == 0
    check rejected("paint(1 2 3)", cpekUnknownFunction).offset == 0
    check rejected("rgb(1e 2 3)", cpekInvalidNumber).offset == 5
    check rejected("rgb(1px 2 3)", cpekInvalidUnit).offset == 5
    check rejected("rgb()", cpekInvalidArity).offset == 4
    discard rejected("rgb(1 2 3) extra", cpekTrailingInput)
    discard rejected("rgb((1 2 3))", cpekTrailingInput)
    discard rejected("rgb(1 2 3))", cpekTrailingInput)
    discard rejected("rgb (1 2 3)", cpekUnknownFunction)

  test "the raising helper is reserved for trusted authored constants":
    check parseColorOrRaise("#ff0000").components == [1.0, 0.0, 0.0]
    expect ValueError:
      discard parseColorOrRaise("rgb(1 2)")
