## Compiled performance probe. This is intentionally outside `nimble test`:
## benchmarks report numbers, while unit tests assert behavior.
import std/[algorithm, monotimes, options, strformat, times]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

type PipelineTiming = object
  styleMs: float
  layoutMs: float
  scrollMs: float
  paintMs: float
  hitMs: float
  commandCount: int

proc elapsedMs(started: MonoTime): float =
  (getMonoTime() - started).inNanoseconds.float / 1_000_000.0

proc benchmarkPipeline(nodeCount: int): PipelineTiming =
  var tree = initTree()
  let root = tree.addBox(id = "root")
  const itemsPerRow = 20
  var remaining = nodeCount
  while remaining > 0:
    let row = tree.addBox(parent = some(root), groups = ["row"])
    let itemsInRow = min(itemsPerRow, remaining)
    for index in 0 ..< itemsInRow:
      discard tree.addBox(parent = some(row), groups = ["item"])
    remaining -= itemsInRow

  let sheet = styleSheet([
    rule(id("root"), [
      decl("width", px(1200)),
      decl("height", px(900)),
      decl("flex-direction", keyword("column")),
      decl("gap", px(2)),
      decl("overflow-y", keyword("auto"))
    ]),
    rule(group("row"), [
      decl("width", px(1200)),
      decl("height", px(20)),
      decl("flex-direction", keyword("row")),
      decl("gap", px(2))
    ]),
    rule(group("item"), [
      decl("width", px(24)),
      decl("height", px(20)),
      decl("background-color", colorValue(rgb(0.2, 0.4, 0.7)))
    ])
  ])

  var diagnostics: Diagnostics
  let styleStarted = getMonoTime()
  let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
  result.styleMs = elapsedMs(styleStarted)
  doAssert not diagnostics.hasErrors

  let layoutStarted = getMonoTime()
  let layout = computeLayout(tree, styles, size(1200, 900))
  result.layoutMs = elapsedMs(layoutStarted)

  var scroll = initScrollState()
  let scrollStarted = getMonoTime()
  scroll.syncScrollState(tree, styles, layout)
  result.scrollMs = elapsedMs(scrollStarted)

  let paintStarted = getMonoTime()
  let commands = buildPaintCommands(tree, styles, layout, scroll)
  result.paintMs = elapsedMs(paintStarted)
  result.commandCount = commands.len

  let hitStarted = getMonoTime()
  discard buildHitRegions(tree, layout, styles, scroll)
  result.hitMs = elapsedMs(hitStarted)

proc median(values: var seq[float]): float =
  values.sort()
  values[values.len div 2]

proc stableBenchmark(nodeCount: int): PipelineTiming =
  const measuredRuns = 5
  discard benchmarkPipeline(nodeCount)
  var styleSamples = newSeqOfCap[float](measuredRuns)
  var layoutSamples = newSeqOfCap[float](measuredRuns)
  var scrollSamples = newSeqOfCap[float](measuredRuns)
  var paintSamples = newSeqOfCap[float](measuredRuns)
  var hitSamples = newSeqOfCap[float](measuredRuns)
  for _ in 0 ..< measuredRuns:
    let sample = benchmarkPipeline(nodeCount)
    styleSamples.add sample.styleMs
    layoutSamples.add sample.layoutMs
    scrollSamples.add sample.scrollMs
    paintSamples.add sample.paintMs
    hitSamples.add sample.hitMs
    result.commandCount = sample.commandCount
  result.styleMs = median(styleSamples)
  result.layoutMs = median(layoutSamples)
  result.scrollMs = median(scrollSamples)
  result.paintMs = median(paintSamples)
  result.hitMs = median(hitSamples)

proc main() =
  echo "CBSS pipeline benchmark (release, ARC)"
  echo "Median of 5 measured runs after one warmup"
  echo "nodes\tstyle ms\tlayout ms\tscroll ms\tpaint ms\thit ms\tcommands"
  for nodeCount in [500, 1000, 4000]:
    let timing = stableBenchmark(nodeCount)
    echo &"{nodeCount}\t{timing.styleMs:.3f}\t{timing.layoutMs:.3f}\t" &
      &"{timing.scrollMs:.3f}\t{timing.paintMs:.3f}\t{timing.hitMs:.3f}\t" &
      $timing.commandCount

when isMainModule:
  main()
