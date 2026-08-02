## Compiled color conversion probe. This is intentionally outside
## `nimble test`: it records the cost of common and wide-gamut paths.
import std/[monotimes, options, strformat, times]

import clay_board_style_system

proc elapsedNs(started: MonoTime): float =
  (getMonoTime() - started).inNanoseconds.float

proc benchmarkSrgb(iterations: int): tuple[nsPerColor: float,
    checksum: float32] =
  var checksum = 0.0'f32
  let started = getMonoTime()
  for index in 0 ..< iterations:
    let channel = (index mod 997).float64 / 996.0
    let resolved = srgb(channel, 0.35, 1.0 - channel).resolveColor
    checksum += resolved.r + resolved.g + resolved.b
  (elapsedNs(started) / iterations.float, checksum)

proc benchmarkWideGamut(
    iterations: int
): tuple[nsPerColor: float, checksum: float32] =
  var checksum = 0.0'f32
  let started = getMonoTime()
  for index in 0 ..< iterations:
    let channel = (index mod 991).float64 / 990.0
    let resolved = displayP3(1.1, channel - 0.1, 0.65).resolveColor
    checksum += resolved.r + resolved.g + resolved.b
  (elapsedNs(started) / iterations.float, checksum)

proc benchmarkInterpolation(
    iterations: int
): tuple[nsPerColor: float, checksum: float32] =
  let first = displayP3(0.9, 0.2, 0.1)
  let second = oklch(0.72, 0.14, 230)
  var checksum = 0.0'f32
  let started = getMonoTime()
  for index in 0 ..< iterations:
    let progress = (index mod 1001).float64 / 1000.0
    let resolved = interpolateColor(first, second, progress, cisOklab)
    checksum += resolved.r + resolved.g + resolved.b
  (elapsedNs(started) / iterations.float, checksum)

proc benchmarkParsing(
    iterations: int
): tuple[nsPerColor: float, checksum: float64] =
  const sources = [
    "#1f80ffcc",
    "rgb(12 60% 240 / 75%)",
    "oklch(62% 0.18 250deg / 90%)",
    "color(display-p3 1.05 0.3 0.12 / 0.8)"
  ]
  var checksum = 0.0
  let started = getMonoTime()
  for index in 0 ..< iterations:
    let parsed = parseColor(sources[index mod sources.len])
    doAssert parsed.value.isSome
    let value = parsed.value.get
    checksum += value.components[0] + value.alpha
  (elapsedNs(started) / iterations.float, checksum)

proc main() =
  const iterations = 100_000
  discard benchmarkSrgb(1_000)
  discard benchmarkWideGamut(1_000)
  discard benchmarkInterpolation(1_000)
  discard benchmarkParsing(1_000)

  let srgbTiming = benchmarkSrgb(iterations)
  let wideTiming = benchmarkWideGamut(iterations)
  let interpolationTiming = benchmarkInterpolation(iterations)
  let parsingTiming = benchmarkParsing(iterations)
  doAssert srgbTiming.checksum > 0
  doAssert wideTiming.checksum > 0
  doAssert interpolationTiming.checksum > 0
  doAssert parsingTiming.checksum > 0

  echo "CBSS color conversion benchmark (release, ARC)"
  echo &"sRGB resolve\t{srgbTiming.nsPerColor:.1f} ns/color"
  echo &"wide-gamut resolve\t{wideTiming.nsPerColor:.1f} ns/color"
  echo &"Oklab interpolation\t{interpolationTiming.nsPerColor:.1f} ns/color"
  echo &"serialized parsing\t{parsingTiming.nsPerColor:.1f} ns/color"

when isMainModule:
  main()
