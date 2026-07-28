## Verifies the structural performance claim that a fixed dirty subtree does
## not become more expensive as unrelated retained nodes are added.
import std/[monotimes, options, strformat, times]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

type DirtyTiming = object
  paintUs: float
  hitUs: float
  paintCommands: int
  hitRegions: int

proc elapsedUs(started: MonoTime): float =
  (getMonoTime() - started).inNanoseconds.float / 1_000.0

proc benchmarkDirtySubtree(nodeCount: int): DirtyTiming =
  var tree = initTree()
  let root = tree.addBox(id = "root")
  let scrollBox = tree.addBox(parent = some(root), id = "scroll")
  for _ in 0 ..< 6:
    discard tree.addBox(parent = some(scrollBox), groups = ["scroll-item"])
  for _ in 0 ..< max(0, nodeCount - tree.nodes.len):
    discard tree.addBox(parent = some(root), groups = ["unrelated"])

  let sheet = styleSheet([
    rule(id("root"), [
      decl("width", px(1200)),
      decl("height", px(900)),
      decl("flex-direction", keyword("row")),
      decl("flex-wrap", keyword("wrap"))
    ]),
    rule(id("scroll"), [
      decl("width", px(80)),
      decl("height", px(40)),
      decl("overflow-y", keyword("auto"))
    ]),
    rule(group("scroll-item"), [
      decl("width", px(70)),
      decl("height", px(20)),
      decl("min-height", px(20)),
      decl("background-color", colorValue(rgb(0.2, 0.4, 0.7)))
    ]),
    rule(group("unrelated"), [
      decl("width", px(10)),
      decl("height", px(10))
    ])
  ])

  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(
    tree, [sheet], defaultProperties(), diagnostics
  )
  doAssert not diagnostics.hasErrors
  let layout = computeLayout(tree, styles, size(1200, 900))
  var scroll = initScrollState()
  scroll.syncScrollState(tree, styles, layout)
  discard scroll.scrollBy(scrollBox, vec2(0, 20))

  const measuredRuns = 200
  var paintTotal = 0.0
  var hitTotal = 0.0
  for _ in 0 ..< measuredRuns:
    let paintStarted = getMonoTime()
    let commands = buildPaintCommandsForSubtree(
      tree, styles, layout, scrollBox, scroll
    )
    paintTotal += elapsedUs(paintStarted)
    result.paintCommands = commands.len

    let hitStarted = getMonoTime()
    let regions = buildHitRegionsForSubtree(
      tree, layout, styles, scrollBox, scroll
    )
    hitTotal += elapsedUs(hitStarted)
    result.hitRegions = regions.len

  result.paintUs = paintTotal / measuredRuns.float
  result.hitUs = hitTotal / measuredRuns.float

proc main() =
  echo "CBSS fixed dirty-subtree benchmark (release, ARC)"
  echo "Mean of 200 updates; dirty subtree is always 7 nodes"
  echo "tree nodes\tpaint us\thit us\tcommands\tregions"
  var samples: seq[DirtyTiming]
  for nodeCount in [500, 4000, 10000]:
    let timing = benchmarkDirtySubtree(nodeCount)
    samples.add timing
    echo &"{nodeCount}\t{timing.paintUs:.3f}\t{timing.hitUs:.3f}\t" &
      &"{timing.paintCommands}\t{timing.hitRegions}"

  doAssert samples[^1].paintCommands == samples[0].paintCommands
  doAssert samples[^1].hitRegions == samples[0].hitRegions
  doAssert samples[^1].paintUs <= samples[0].paintUs * 4.0,
    "fixed dirty paint scaled with unrelated tree size"
  doAssert samples[^1].hitUs <= samples[0].hitUs * 4.0,
    "fixed dirty hit build scaled with unrelated tree size"

when isMainModule:
  main()
