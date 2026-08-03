import std/[math, unittest]

import clay_board_style_system

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

suite "CSS color-space conversion foundation":
  test "resolved Color remains a compact 16-byte backend interchange value":
    check sizeof(Color) == 16

  test "authored values preserve their declared color space and channels":
    let value = displayP3(0.9, 0.2, 0.1, 0.75)

    check value.kind == cvComponents
    check value.space == csDisplayP3
    check value.components == [0.9, 0.2, 0.1]
    check value.alpha == 0.75
    check value.missing == {}

  test "linear Display P3 stays distinct from gamma-encoded Display P3":
    let linear = displayP3Linear(0.25, 0.5, 0.75, 0.8)

    check linear.space == csDisplayP3Linear
    check linear.components == [0.25, 0.5, 0.75]
    check linear.alpha == 0.8
    check linear.missing == {}
    displayP3Linear(1, 1, 1).resolveColor.checkColor(1, 1, 1,
        tolerance = 0.001)
    let linearGray = displayP3Linear(0.25, 0.25, 0.25).resolveColor
    let encodedGray = displayP3(0.25, 0.25, 0.25).resolveColor
    check linearGray.r > encodedGray.r + 0.2

  test "typed constructors accept float32 authoring values":
    let value = srgb(0.1'f32, 0.2'f32, 0.3'f32, 0.4'f32)

    check value.components == [0.1'f32.float64, 0.2'f32.float64,
        0.3'f32.float64]
    check value.alpha == 0.4'f32.float64

  test "non-finite authoring components fail before paint resolution":
    expect ValueError:
      discard colorIn(csSrgb, Inf, 0, 0)
    expect ValueError:
      discard colorIn(csLab, 50, NaN, 0)
    expect ValueError:
      discard colorIn(csOklab, 0.5, 0, 0, NegInf)

  test "explicit missing metadata survives typed color construction":
    let value = colorIn(csOklch, 0.5, 0.0, 0.0, 0.0,
        {ccSecond, ccThird, ccAlpha})

    check value.missing == {ccSecond, ccThird, ccAlpha}

  test "HSL primary colors resolve to sRGB":
    hsl(0, 100, 50).resolveColor.checkColor(1, 0, 0)
    hsl(120, 100, 50).resolveColor.checkColor(0, 1, 0)
    hsl(240, 100, 50).resolveColor.checkColor(0, 0, 1)
    hsl(-120, 100, 50).resolveColor.checkColor(0, 0, 1)

  test "HWB primary colors and gray normalization resolve to sRGB":
    hwb(120, 0, 0).resolveColor.checkColor(0, 1, 0)
    hwb(40, 60, 60).resolveColor.checkColor(0.5, 0.5, 0.5)

  test "Lab and LCH D50 reference red resolve to sRGB":
    lab(54.2917, 80.8125, 69.8851).resolveColor.checkColor(1, 0, 0,
        tolerance = 0.002)
    lch(54.2917, 106.839, 40.8526).resolveColor.checkColor(1, 0, 0,
        tolerance = 0.002)

  test "Oklab and Oklch reference red resolve to sRGB":
    oklab(0.627955, 0.224863, 0.125846).resolveColor.checkColor(1, 0, 0,
        tolerance = 0.001)
    oklch(0.627955, 0.257683, 29.2339).resolveColor.checkColor(1, 0, 0,
        tolerance = 0.001)

  test "predefined RGB and XYZ spaces preserve their reference white":
    checkpoint "Display P3"
    displayP3(1, 1, 1).resolveColor.checkColor(1, 1, 1, tolerance = 0.001)
    checkpoint "A98 RGB"
    a98Rgb(1, 1, 1).resolveColor.checkColor(1, 1, 1, tolerance = 0.001)
    checkpoint "ProPhoto RGB"
    proPhotoRgb(1, 1, 1).resolveColor.checkColor(1, 1, 1, tolerance = 0.001)
    checkpoint "Rec. 2020"
    rec2020(1, 1, 1).resolveColor.checkColor(1, 1, 1, tolerance = 0.001)
    checkpoint "XYZ D65"
    xyzD65(0.9504559, 1.0, 1.0890578).resolveColor.checkColor(1, 1, 1,
        tolerance = 0.001)

  test "currentColor resolves late against the computed foreground color":
    let foreground = rgba(0.2, 0.4, 0.6, 0.75)
    currentColor().resolveColor(foreground).checkColor(0.2, 0.4, 0.6, 0.75)

  test "output alpha and channels are clamped at the paint boundary":
    srgb(1.4, -0.2, 0.5, 2).resolveColor(gamutMap = cgmClip).checkColor(1, 0,
        0.5, 1)

  test "finite out-of-gamut components stay authored until resolution":
    let value = displayP3(1.4, -0.2, 0.5)

    check value.components == [1.4, -0.2, 0.5]
    let resolved = value.resolveColor
    check resolved.r >= 0 and resolved.r <= 1
    check resolved.g >= 0 and resolved.g <= 1
    check resolved.b >= 0 and resolved.b <= 1

  test "interpolation premultiplies alpha before mixing channels":
    let transparentRed = srgb(1, 0, 0, 0)
    let opaqueBlue = srgb(0, 0, 1, 1)
    let mixed = interpolateColor(transparentRed, opaqueBlue, 0.5, cisSrgb)

    mixed.checkColor(0, 0, 1, 0.5)

  test "Oklab interpolation is deterministic at endpoints":
    let first = displayP3(0.8, 0.2, 0.1)
    let second = oklch(0.7, 0.12, 220)

    check interpolateColor(first, second, 0, cisOklab) == first.resolveColor
    check interpolateColor(first, second, 1, cisOklab) == second.resolveColor

suite "CSS missing-component interpolation":
  test "an analogous missing RGB channel uses the other endpoint channel":
    let first = colorIn(csSrgb, 0, 0.2, 0.4, missing = {ccFirst})
    let second = srgb(0.8, 0.6, 0.2)

    interpolateColor(first, second, 0, cisSrgb).checkColor(0.8, 0.2, 0.4)
    interpolateColor(first, second, 0.5, cisSrgb).checkColor(0.8, 0.4, 0.3)

  test "XYZ channels are analogous to their corresponding RGB channels":
    let first = colorIn(csXyzD65, 0, 0.1, 0.1, missing = {ccFirst})
    let second = srgb(0.8, 0.3, 0.2)
    let mixed = interpolateColor(first, second, 0, cisSrgb)

    check mixed.r.close(0.8)

  test "a fully missing non-analogous set carries into Oklab":
    let first = colorIn(csSrgb, 0, 0, 0,
        missing = {ccFirst, ccSecond, ccThird})
    let second = oklab(0.7, 0.1, 0.05)

    interpolateColor(first, second, 0.35, cisOklab).checkColor(
        second.resolveColor.r,
        second.resolveColor.g,
        second.resolveColor.b,
        tolerance = 0.001
    )

  test "the remaining polar components carry as one analogous set":
    let first = colorIn(csOklch, 0.5, 0, 0,
        missing = {ccSecond, ccThird})
    let second = oklab(0.7, 0.1, 0.05)
    let expected = oklab(0.6, 0.1, 0.05).resolveColor

    interpolateColor(first, second, 0.5, cisOklab).checkColor(
        expected.r, expected.g, expected.b, tolerance = 0.001)

  test "a partly missing remainder is converted numerically instead of carried":
    let first = colorIn(csOklch, 0.5, 0, 0, missing = {ccSecond})
    let second = oklab(0.7, 0.1, 0.05)
    let expected = oklab(0.6, 0.05, 0.025).resolveColor

    interpolateColor(first, second, 0.5, cisOklab).checkColor(
        expected.r, expected.g, expected.b, tolerance = 0.001)

  test "missing alpha carries before premultiplication":
    let first = colorIn(csSrgb, 1, 0, 0, 0, {ccAlpha})
    let second = srgb(0, 0, 1, 0.6)

    interpolateColor(first, second, 0.5, cisSrgb).checkColor(
        0.5, 0, 0.5, 0.6)

  test "two missing alpha components resolve to transparent black":
    let first = colorIn(csSrgb, 1, 0, 0, 0, {ccAlpha})
    let second = colorIn(csSrgb, 0, 0, 1, 0, {ccAlpha})

    interpolateColor(first, second, 0.5, cisSrgb).checkColor(0, 0, 0, 0)
