import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "slider component":
  test "slider clamps and snaps initial value":
    let ui = initUiRoot()
    let volume = ui.slider(SliderParams(min: 0, max: 10, step: 2, value: 9, trackWidth: 100))

    check volume.value() == 10
    check ui.tree.nodes[volume.fillNode.nodeId.nodeIndex].kind == nkBox
    check ui.tree.nodes[volume.valueNode.nodeId.nodeIndex].text == "10.0"
    check ui.tree.nodes[volume.thumbNode.nodeId.nodeIndex].text == "100%"

  test "setValue emits input and change when requested":
    let ui = initUiRoot()
    let volume = ui.slider(value = 0, min = 0, max = 10, step = 1)
    var seen: seq[string] = @[]

    volume.onInput = proc(event: DispatchResult): EventOutcome =
      seen.add $volume.value()
      false

    volume.onChange = proc(event: DispatchResult): EventOutcome =
      seen.add $volume.value()
      false

    volume.setValue(4, emitEvents = true)

    check volume.value() == 4
    check seen == @["4.0", "4.0"]

  test "click local position updates value":
    let ui = initUiRoot()
    let volume = ui.slider(value = 0, min = 0, max = 100, step = 10, trackWidth = 200)

    discard volume.container.emit(clickEvent(vec2(50, 0)), local = some(vec2(50, 0)))

    check volume.value() == 30
    check ui.tree.nodes[volume.thumbNode.nodeId.nodeIndex].text == "30%"

  test "slider fill width tracks the snapped value":
    let ui = initUiRoot()
    let volume = ui.slider(value = 0, min = 0, max = 100, step = 10, trackWidth = 200)

    volume.setValue(50)
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(260, 80))

    var fillWidth = -1.0'f32
    for item in layout.boxes:
      if item.node == volume.fillNode.nodeId:
        fillWidth = item.rect.w

    check fillWidth == 100.0'f32

  test "dragging updates value until pointer up":
    let ui = initUiRoot()
    let volume = ui.slider(value = 0, min = 0, max = 100, step = 1, trackWidth = 100)

    discard volume.container.emit(pointerDownEvent(vec2(10, 0)), local = some(vec2(10, 0)))
    check volume.value() == 10
    check esActive in ui.tree.nodes[volume.container.nodeId.nodeIndex].states

    discard volume.container.emit(pointerMoveEvent(vec2(80, 0)), local = some(vec2(80, 0)))
    check volume.value() == 80

    discard volume.container.emit(pointerUpEvent(vec2(80, 0)), local = some(vec2(80, 0)))
    check esActive notin ui.tree.nodes[volume.container.nodeId.nodeIndex].states

  test "keyboard changes value":
    let ui = initUiRoot()
    let volume = ui.slider(value = 4, min = 0, max = 10, step = 2)

    discard volume.container.emit(keyDownEvent("ArrowRight"))
    check volume.value() == 6

    discard volume.container.emit(keyDownEvent("Home"))
    check volume.value() == 0

    discard volume.container.emit(keyDownEvent("End"))
    check volume.value() == 10

  test "disabled slider suppresses value changes and user pointer handlers":
    let ui = initUiRoot()
    let volume = ui.slider(value = 5, min = 0, max = 10, step = 1, disabled = true)
    var pointerDown = false
    var changed = false

    volume.onPointerDown = proc(event: DispatchResult): EventOutcome =
      pointerDown = true
      false

    volume.onChange = proc(event: DispatchResult): EventOutcome =
      changed = true
      false

    discard volume.container.emit(pointerDownEvent(vec2(100, 0)), local = some(vec2(100, 0)))
    discard volume.container.emit(keyDownEvent("ArrowRight"))
    volume.setValue(10, emitEvents = true)

    check volume.value() == 5
    check not pointerDown
    check not changed
    check esDisabled in ui.tree.nodes[volume.container.nodeId.nodeIndex].states
