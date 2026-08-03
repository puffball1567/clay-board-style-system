import std/[math, unittest]

import clay_board_style_system

proc close(actual, expected: float32; tolerance = 0.002'f32): bool =
  abs(actual - expected) <= tolerance

template checkColor(actualExpression: Color; red, green, blue: float32;
    alpha = 1.0'f32; tolerance = 0.002'f32) =
  block:
    let actual = actualExpression
    check actual.r.close(red, tolerance)
    check actual.g.close(green, tolerance)
    check actual.b.close(blue, tolerance)
    check actual.a.close(alpha, tolerance)

suite "linear gradient color-space sampling":
  test "empty and single-stop gradients have stable boundary behavior":
    let empty = LinearGradient(angle: 90, interpolationSpace: cisSrgb)
    empty.gradientColorAt(0.5).checkColor(0, 0, 0, 0)

    let single = LinearGradient(
      angle: 90,
      interpolationSpace: cisOklab,
      stops: @[colorStop(rgb(0.2, 0.3, 0.4), 50)]
    )
    single.gradientColorAt(-10).checkColor(0.2, 0.3, 0.4)
    single.gradientColorAt(10).checkColor(0.2, 0.3, 0.4)

  test "sampling clamps outside the authored stop interval":
    let gradient = LinearGradient(
      angle: 90,
      interpolationSpace: cisSrgb,
      stops: @[
        colorStop(rgb(1, 0, 0), 25),
        colorStop(rgb(0, 0, 1), 75)
      ]
    )
    gradient.gradientColorAt(0).checkColor(1, 0, 0)
    gradient.gradientColorAt(1).checkColor(0, 0, 1)

  test "sRGB and linear-sRGB produce distinct midpoints":
    let stops = @[
      colorStop(rgb(1, 0, 0), 0),
      colorStop(rgb(0, 0, 1), 100)
    ]
    let encoded = LinearGradient(
      angle: 90, interpolationSpace: cisSrgb, stops: stops)
    let linear = LinearGradient(
      angle: 90, interpolationSpace: cisSrgbLinear, stops: stops)

    encoded.gradientColorAt(0.5).checkColor(0.5, 0, 0.5)
    let linearMidpoint = linear.gradientColorAt(0.5)
    check linearMidpoint.r > 0.73
    check linearMidpoint.b > 0.73
    check linearMidpoint.g < 0.01

  test "gradient alpha is premultiplied before interpolation":
    let gradient = LinearGradient(
      angle: 90,
      interpolationSpace: cisSrgb,
      stops: @[
        colorStop(rgba(1, 0, 0, 1), 0),
        colorStop(rgba(0, 0, 1, 0), 100)
      ]
    )

    gradient.gradientColorAt(0.5).checkColor(1, 0, 0, 0.5)

  test "duplicate stop offsets preserve the authored boundary color":
    let gradient = LinearGradient(
      angle: 90,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(rgb(1, 0, 0), 50),
        colorStop(rgb(0, 1, 0), 50),
        colorStop(rgb(0, 0, 1), 100)
      ]
    )

    gradient.gradientColorAt(0.5).checkColor(1, 0, 0)

  test "typed gradient helper preserves its interpolation space":
    let value = linearGradientIn(
      cisOklab,
      135,
      colorStop(rgb(1, 0, 0), 0),
      colorStop(rgb(0, 0, 1), 100)
    )

    check value.kind == svLinearGradient
    check value.gradientAngle == 135
    check value.gradientInterpolationSpace == cisOklab

  test "prepared lookup preserves endpoints and bounds its resolution":
    let gradient = LinearGradient(
      angle: 90,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(rgb(1, 0, 0), 0),
        colorStop(rgb(0, 0, 1), 100)
      ]
    )
    let sampler = gradient.prepareGradientSampler
    let lookup = sampler.buildGradientLookup(
      gradientLookupSampleCount(100_000)
    )

    check lookup.colors.len == 2_048
    lookup.gradientColorAt(-1).checkColor(1, 0, 0)
    lookup.gradientColorAt(2).checkColor(0, 0, 1)

  test "lookup sizing samples twice per projected pixel within its cap":
    check gradientLookupSampleCount(-1) == 2
    check gradientLookupSampleCount(0) == 2
    check gradientLookupSampleCount(10) == 21
    check gradientLookupSampleCount(10_000) == 2_048

  test "lookup stays within RGBA8-oriented error of direct sampling":
    for space in ColorInterpolationSpace:
      let gradient = LinearGradient(
        angle: 37,
        interpolationSpace: space,
        stops: @[
          colorStop(rgba(0.95, 0.12, 0.08, 0.85), 0),
          colorStop(rgba(0.20, 0.88, 0.35, 0.45), 42),
          colorStop(rgba(0.10, 0.34, 0.96, 0.65), 100)
        ]
      )
      let sampler = gradient.prepareGradientSampler
      let lookup = sampler.buildGradientLookup(2_048)
      for index in 0 .. 1_000:
        let progress = index.float32 / 1_000.0'f32
        let direct = sampler.gradientColorAt(progress)
        let sampled = lookup.gradientColorAt(progress)
        check abs(direct.r - sampled.r) <= 1.0'f32 / 255.0'f32
        check abs(direct.g - sampled.g) <= 1.0'f32 / 255.0'f32
        check abs(direct.b - sampled.b) <= 1.0'f32 / 255.0'f32
        check abs(direct.a - sampled.a) <= 1.0'f32 / 255.0'f32
