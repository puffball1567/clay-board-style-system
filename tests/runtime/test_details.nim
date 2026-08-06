import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "details component":
  test "details initializes summary body and open state":
    let ui = initUiRoot()
    let panel = ui.details("More", "Hidden body", open = true)

    check panel.isOpen()
    check panel.summary() == "More"
    check panel.body() == "Hidden body"
    check ui.tree.nodes[panel.summaryTextNode.nodeId.nodeIndex].text == "More"
    check ui.tree.nodes[panel.bodyNode.nodeId.nodeIndex].text == "Hidden body"
    check ui.tree.nodes[panel.markerNode.nodeId.nodeIndex].text == "v"
    check esOpen in ui.tree.nodes[panel.container.nodeId.nodeIndex].states
    check esOpen in ui.tree.nodes[panel.bodyNode.nodeId.nodeIndex].states

  test "summary click toggles details and emits toggle":
    let ui = initUiRoot()
    let panel = ui.details("More", "Body")
    var toggles = 0

    panel.onToggle = proc(event: DispatchResult): EventOutcome =
      inc toggles
      false

    discard panel.summaryNode.emit(InputEvent(kind: iekClick))
    check panel.isOpen()
    check ui.tree.nodes[panel.markerNode.nodeId.nodeIndex].text == "v"

    discard panel.summaryNode.emit(InputEvent(kind: iekClick))
    check not panel.isOpen()
    check ui.tree.nodes[panel.markerNode.nodeId.nodeIndex].text == ">"
    check toggles == 2

  test "keyboard activation toggles details":
    let ui = initUiRoot()
    let panel = ui.details("More", "Body")

    discard panel.summaryNode.emit(keyDownEvent("Enter"))
    check panel.isOpen()

    discard panel.summaryNode.emit(keyDownEvent(" "))
    check not panel.isOpen()

  test "direction keys expose disclosure behavior without application logic":
    let ui = initUiRoot()
    let panel = ui.details("More", "Body")
    var toggles = 0

    panel.onToggle = proc(event: DispatchResult): EventOutcome =
      inc toggles
      false

    discard panel.summaryNode.emit(keyDownEvent("ArrowRight"))
    check panel.isOpen()
    discard panel.summaryNode.emit(keyDownEvent("ArrowRight"))
    check panel.isOpen()

    discard panel.summaryNode.emit(keyDownEvent("ArrowLeft"))
    check not panel.isOpen()
    discard panel.summaryNode.emit(keyDownEvent("ArrowLeft"))
    check not panel.isOpen()
    check toggles == 2

  test "closed details body does not paint or hit test":
    let ui = initUiRoot()
    let panel = ui.details(
      "More",
      "Hidden body",
      style = uiStyle([
        decl("width", px(160))
      ]),
      summaryStyle = uiStyle([
        decl("width", px(160)),
        decl("height", px(24))
      ]),
      bodyStyle = uiStyle([
        decl("width", px(160)),
        decl("height", px(24)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    )

    var diagnostics: Diagnostics
    var styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    var layout = computeLayout(ui.tree, styles, size(180, 80))
    var regions = buildHitRegions(ui.tree, layout, styles)
    var commands = buildPaintCommands(ui.tree, styles, layout)

    check hitTest(regions, vec2(8, 34)).isNone
    for command in commands:
      if command.kind == pcDrawText:
        check command.text != "Hidden body"
      if command.kind == pcFillRect:
        check command.color != rgb(1, 0, 0)

    panel.setOpen(true)
    diagnostics = Diagnostics()
    styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    layout = computeLayout(ui.tree, styles, size(180, 80))
    regions = buildHitRegions(ui.tree, layout, styles)
    commands = buildPaintCommands(ui.tree, styles, layout)

    let hit = hitTest(regions, vec2(8, 34))
    check hit.isSome

    var paintedBody = false
    for command in commands:
      if command.kind == pcDrawText and command.text == "Hidden body":
        paintedBody = true
    check paintedBody

  test "disabled details suppresses user toggles":
    let ui = initUiRoot()
    let panel = ui.details("More", "Body", disabled = true)
    var toggled = false

    panel.onToggle = proc(event: DispatchResult): EventOutcome =
      toggled = true
      false

    discard panel.summaryNode.emit(InputEvent(kind: iekClick))
    discard panel.summaryNode.emit(keyDownEvent("Enter"))

    check not panel.isOpen()
    check not toggled
    check esDisabled in ui.tree.nodes[panel.container.nodeId.nodeIndex].states

  test "setters update visible content without emitting toggle":
    let ui = initUiRoot()
    let panel = ui.details("More", "Body")
    var toggled = false

    panel.onToggle = proc(event: DispatchResult): EventOutcome =
      toggled = true
      false

    panel.setSummary("Advanced")
    panel.setBody("Updated")
    panel.setOpen(true)

    check panel.summary() == "Advanced"
    check panel.body() == "Updated"
    check panel.isOpen()
    check not toggled
    check ui.tree.nodes[panel.summaryTextNode.nodeId.nodeIndex].text == "Advanced"
    check ui.tree.nodes[panel.bodyNode.nodeId.nodeIndex].text == "Updated"
