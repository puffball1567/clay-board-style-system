import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "button component":
  test "button invokes user onClick handler":
    let ui = initUiRoot()
    let run = ui.button("Run")
    var clicked = false

    run.onClick = proc(event: DispatchResult): EventOutcome =
      clicked = true
      true

    discard run.container.emit(InputEvent(kind: iekClick))

    check clicked

  test "disabled button suppresses click handlers and has disabled state":
    let ui = initUiRoot()
    let run = ui.button(ButtonParams(label: "Run", disabled: true))
    var clicked = false

    run.onClick = proc(event: DispatchResult): EventOutcome =
      clicked = true
      true

    discard run.container.emit(InputEvent(kind: iekClick))

    check run.disabled()
    check not clicked
    check esDisabled in ui.tree.nodes[run.container.nodeId.nodeIndex].states

  test "setDisabled toggles disabled state":
    let ui = initUiRoot()
    let run = ui.button("Run")

    run.setDisabled(true)
    check run.disabled()
    check esDisabled in ui.tree.nodes[run.container.nodeId.nodeIndex].states

    run.setDisabled(false)
    check not run.disabled()
    check esDisabled notin ui.tree.nodes[run.container.nodeId.nodeIndex].states

  test "keyboard activation dispatches click":
    let ui = initUiRoot()
    let run = ui.button("Run")
    var clicked = 0

    run.onClick = proc(event: DispatchResult): EventOutcome =
      inc clicked
      true

    discard run.container.emit(keyDownEvent("Enter"))
    discard run.container.emit(keyDownEvent(" "))

    check clicked == 2

  test "disabled button suppresses keyboard activation":
    let ui = initUiRoot()
    let run = ui.button(ButtonParams(label: "Run", disabled: true))
    var clicked = false
    var keySeen = false

    run.onClick = proc(event: DispatchResult): EventOutcome =
      clicked = true
      true

    run.container.onKeyDown = proc(event: DispatchResult): EventOutcome =
      keySeen = true
      true

    discard run.container.emit(keyDownEvent("Enter"))

    check not clicked
    check not keySeen

  test "setLabel updates visible text":
    let ui = initUiRoot()
    let run = ui.button("Run")

    run.setLabel("Save")

    check ui.tree.nodes[run.labelNode.nodeId.nodeIndex].text == "Save"

  test "button label does not intercept pointer hits":
    let ui = initUiRoot()
    let run = ui.button(
      "Run",
      style = uiStyle([
        decl("width", px(80)),
        decl("height", px(32)),
        decl("align-items", keyword("center")),
        decl("justify-content", keyword("center"))
      ])
    )

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    let layout = computeLayout(ui.tree, styles, size(120, 60))
    let regions = buildHitRegions(layout, styles)
    let hit = hitTest(regions, vec2(40, 16))

    check not diagnostics.hasErrors
    check styles.styles[run.labelNode.nodeId.nodeIndex].visual.pointerEvents == peNone
    check hit.isSome
    check hit.get.node == run.container.nodeId
