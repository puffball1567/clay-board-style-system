## Verifies that retained screen activation depends on the registered screens
## and active screen subtree, not on unrelated retained nodes.
import std/[monotimes, options, strformat, times]

import clay_board_style_system

type BenchScreen = enum
  bsHome,
  bsSettings

proc elapsedUs(started: MonoTime): float =
  (getMonoTime() - started).inNanoseconds.float / 1_000.0

proc benchmarkScreenHost(nodeCount: int): float =
  let navigator = initStackNavigator(bsHome)
  let ui = initUiRoot()
  let app = ui.box()
  let homeRoot = ui.box(parent = some(app))
  ui.pushParent(homeRoot)
  discard ui.button("Home")
  ui.popParent()
  let settingsRoot = ui.box(parent = some(app))
  ui.pushParent(settingsRoot)
  discard ui.button("Settings")
  ui.popParent()
  for _ in ui.tree.nodes.len ..< nodeCount:
    discard ui.box(parent = some(app))

  let host = initNavigationScreenHost(ui, navigator)
  host.registerScreen(bsHome, homeRoot)
  host.registerScreen(bsSettings, settingsRoot)
  var interaction = initInteractionState()
  doAssert host.sync(interaction)
  let retainedNodes = ui.tree.nodes.len
  let retainedStyles = ui.componentStyles.len

  const warmupTransitions = 100
  for index in 0 ..< warmupTransitions:
    navigator.replace(if index mod 2 == 0: bsSettings else: bsHome)
    doAssert host.sync(interaction)

  const measuredTransitions = 4_000
  let started = getMonoTime()
  for index in 0 ..< measuredTransitions:
    navigator.replace(if index mod 2 == 0: bsSettings else: bsHome)
    doAssert host.sync(interaction)
  result = elapsedUs(started) / measuredTransitions.float

  doAssert ui.tree.nodes.len == retainedNodes
  doAssert ui.componentStyles.len == retainedStyles

proc main() =
  echo "CBSS retained navigation screen-host benchmark (release, ARC)"
  echo "Mean of 4,000 replace+sync transitions"
  echo "tree nodes\ttransition us"
  let large = benchmarkScreenHost(10_000)
  let small = benchmarkScreenHost(500)
  echo &"500\t{small:.3f}"
  echo &"10000\t{large:.3f}"
  doAssert large <= small * 2.0 + 1.0,
    "screen activation scaled with unrelated retained nodes"

when isMainModule:
  main()
