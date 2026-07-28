import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/runtime/text_focus

suite "text focus runtime":
  test "normalizing focus blurs the previous text control":
    let ui = initUiRoot()
    let first = ui.textInput(TextInputParams(value: "first"))
    let second = ui.textInput(TextInputParams(value: "second"))
    var state = initInteractionState()

    ui.normalizeTextControlFocus(state, some(first.container.nodeId))

    check state.focusedTarget == some(first.container.nodeId)
    check first.state.focused
    check esFocus in ui.tree.nodes[first.container.nodeId.nodeIndex].states

    ui.normalizeTextControlFocus(state, some(second.container.nodeId))

    check state.focusedTarget == some(second.container.nodeId)
    check not first.state.focused
    check second.state.focused
    check esFocus notin ui.tree.nodes[first.container.nodeId.nodeIndex].states
    check esFocus in ui.tree.nodes[second.container.nodeId.nodeIndex].states

  test "normalizing an outside hit clears text control focus":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abc"))
    let outside = ui.box()
    var state = initInteractionState()

    ui.normalizeTextControlFocus(state, some(input.container.nodeId))
    ui.normalizeTextControlFocus(state, some(outside.nodeId))

    check state.focusedTarget.isNone
    check not input.state.focused
    check esFocus notin ui.tree.nodes[input.container.nodeId.nodeIndex].states

  test "normalizing a disabled text control hit does not focus it":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "disabled", disabled: true))
    var state = initInteractionState()

    ui.normalizeTextControlFocus(state, some(input.container.nodeId))
    check state.focusedTarget.isNone
    check not input.state.focused
    check esFocus notin ui.tree.nodes[input.container.nodeId.nodeIndex].states
    check ui.inputTargetForHit(some(input.textNode.nodeId)).isNone

  test "hit normalization retargets text overlay nodes to the owning input":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abc"))
    var dispatches = @[
      DispatchResult(
        target: some(input.textNode.nodeId),
        local: some(vec2(6, 6)),
        event: pointerDownEvent(vec2(16, 16))
      )
    ]
    let regions = @[
      HitRegion(node: input.container.nodeId, rect: rect(10, 10, 180, 32), zIndex: 0),
      HitRegion(node: input.textNode.nodeId, rect: rect(16, 16, 80, 18), zIndex: 1)
    ]

    ui.normalizeTextControlDispatches(regions, dispatches)

    check dispatches[0].target == some(input.container.nodeId)
    check dispatches[0].local == some(vec2(6, 6))

  test "caret blink style reuses one style slot and can be forced visible":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abc"))
    var state = initInteractionState()
    var blinkSheetIndex = none(int)

    ui.normalizeTextControlFocus(state, some(input.container.nodeId))
    check ui.setCaretBlinkVisible(state, blinkSheetIndex, false)
    check blinkSheetIndex.isSome
    let index = blinkSheetIndex.get
    check ui.componentStyles[index].rules[0].declarations[0].operation.value.get.number == 0.0'f32

    check ui.setCaretBlinkVisible(state, blinkSheetIndex, true)
    check blinkSheetIndex == some(index)
    check ui.componentStyles[index].rules[0].declarations[0].operation.value.get.number == 1.0'f32

  test "tab focus movement cycles through text controls":
    let ui = initUiRoot()
    let first = ui.textInput(TextInputParams(value: "first"))
    let second = ui.textArea(TextAreaParams(value: "second"))
    var state = initInteractionState()

    check ui.moveTextControlFocus(state, 1)
    check state.focusedTarget == some(first.container.nodeId)
    check first.state.focused

    check ui.moveTextControlFocus(state, 1)
    check state.focusedTarget == some(second.container.nodeId)
    check not first.state.focused
    check second.state.focused

    check ui.moveTextControlFocus(state, -1)
    check state.focusedTarget == some(first.container.nodeId)
    check first.state.focused
    check not second.state.focused
