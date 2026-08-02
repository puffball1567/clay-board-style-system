import std/[json, math, os, options, unittest]

import clay_board_style_system

proc compositeOver(source, backdrop: Color): Color =
  let outputAlpha = source.a + backdrop.a * (1.0'f32 - source.a)
  if outputAlpha <= 0:
    return rgba(0, 0, 0, 0)
  result = rgba(
    (source.r * source.a + backdrop.r * backdrop.a *
      (1.0'f32 - source.a)) / outputAlpha,
    (source.g * source.a + backdrop.g * backdrop.a *
      (1.0'f32 - source.a)) / outputAlpha,
    (source.b * source.a + backdrop.b * backdrop.a *
      (1.0'f32 - source.a)) / outputAlpha,
    outputAlpha
  )

proc rgba8(color: Color): array[4, int] =
  [
    int(round(clamp(color.r, 0, 1) * 255)),
    int(round(clamp(color.g, 0, 1) * 255)),
    int(round(clamp(color.b, 0, 1) * 255)),
    int(round(clamp(color.a, 0, 1) * 255))
  ]

proc resolveFixtureColor(kind, input: string): Color =
  if kind == "mix":
    let parsed = parseColorMix(input)
    check parsed.isOk
    if parsed.value.isSome:
      return parsed.value.get.resolveColor()
  else:
    let parsed = parseColor(input)
    check parsed.isOk
    if parsed.value.isSome:
      # Chrome 150 exposes channel-clipped sRGB through this Canvas boundary.
      # CBSS keeps perceptual gamut mapping as its default, so this fixture
      # selects the matching explicit boundary policy for conversion checks.
      return parsed.value.get.resolveColor(gamutMap = cgmClip)
  rgba(0, 0, 0, 0)

suite "pinned browser color comparison":
  test "supported colors stay within the local Chrome RGBA8 boundary":
    let fixturePath = currentSourcePath.parentDir.parentDir /
      "fixtures" / "color" / "chrome_150_linux_srgb.json"
    let fixture = parseFile(fixturePath)

    check fixture["schema"].getInt == 1
    check fixture["pixelBoundary"].getStr ==
      "CanvasRenderingContext2D/getImageData/srgb/rgba8"
    check fixture["cases"].len >= 20

    for fixtureCase in fixture["cases"]:
      let name = fixtureCase["name"].getStr
      var actual = resolveFixtureColor(
        fixtureCase["kind"].getStr,
        fixtureCase["input"].getStr
      )
      if fixtureCase["backdrop"].kind != JNull:
        actual = actual.compositeOver(
          resolveFixtureColor("color", fixtureCase["backdrop"].getStr)
        )

      let actualBytes = actual.rgba8
      let expectedNode =
        if fixtureCase.hasKey("cbssRgba8"):
          fixtureCase["cbssRgba8"]
        else:
          fixtureCase["rgba8"]
      for channel in 0 .. 3:
        let expected = expectedNode[channel].getInt
        checkpoint name & " channel " & $channel & ": got " &
          $actualBytes[channel] & ", expected " & $expected
        check abs(actualBytes[channel] - expected) <= 2

      if fixtureCase.hasKey("cbssRgba8"):
        check fixtureCase["comparison"].getStr == "known-browser-divergence"
        var hasRecordedDifference = false
        for channel in 0 .. 3:
          if abs(fixtureCase["rgba8"][channel].getInt -
              fixtureCase["cbssRgba8"][channel].getInt) > 2:
            hasRecordedDifference = true
        check hasRecordedDifference
