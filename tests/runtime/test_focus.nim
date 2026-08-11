import std/[options, unittest]

import clay_board_style_system

suite "general focus runtime":
  test "decorative nodes are skipped and child hits resolve to a focusable ancestor":
    let ui = initUiRoot()
    let decorative = ui.box()
    let control = ui.box()
    control.setFocusable()
    let label = ui.text(control, "Control")

    check not decorative.focusable
    check control.focusable
    check ui.tree.focusTargetForHit(some(label.nodeId)) == some(control.nodeId)
    check ui.tree.focusTargetForHit(some(decorative.nodeId)).isNone

  test "label hits delegate focus to the associated control":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: ""))
    let caption = ui.label("Name", target = some(input.container))
    var state = initInteractionState()

    check ui.normalizeFocus(state, some(caption.textNode.nodeId))
    check state.focusedTarget == some(input.container.nodeId)
    check input.state.focused

    caption.clearTarget()
    check ui.normalizeFocus(state, some(caption.textNode.nodeId))
    check state.focusedTarget.isNone

  test "tab order uses positive indexes before zero and skips excluded nodes":
    let ui = initUiRoot()
    let zeroFirst = ui.box()
    zeroFirst.setFocusable(tabIndex = 0)
    let positiveTwo = ui.box()
    positiveTwo.setFocusable(tabIndex = 2)
    let pointerOnly = ui.box()
    pointerOnly.setFocusable(tabIndex = -1)
    let positiveOne = ui.box()
    positiveOne.setFocusable(tabIndex = 1)
    let disabled = ui.box()
    disabled.setFocusable(tabIndex = 1)
    disabled.setState(esDisabled, true)
    let zeroSecond = ui.box()
    zeroSecond.setFocusable(tabIndex = 0)

    check ui.focusTargets() == @[
      positiveOne.nodeId,
      positiveTwo.nodeId,
      zeroFirst.nodeId,
      zeroSecond.nodeId
    ]
    check ui.tree.isFocusable(pointerOnly.nodeId)
    check not ui.tree.isFocusable(pointerOnly.nodeId, forTraversal = true)

  test "subtree focus order ignores unrelated and inert nodes":
    let ui = initUiRoot()
    let app = ui.box()
    let screen = ui.box(parent = some(app))
    let outside = ui.box(parent = some(app))
    let zero = ui.box(parent = some(screen))
    zero.setFocusable(tabIndex = 0)
    let positive = ui.box(parent = some(screen))
    positive.setFocusable(tabIndex = 1)
    let inactive = ui.box(parent = some(screen))
    inactive.setFocusable(tabIndex = 2)
    inactive.setInert()
    outside.setFocusable(tabIndex = 1)

    check ui.focusTargets(screen.nodeId) == @[
      positive.nodeId,
      zero.nodeId
    ]

  test "focus movement emits blur and focus and marks keyboard focus visible":
    let ui = initUiRoot()
    let first = ui.box()
    first.setFocusable()
    let second = ui.box()
    second.setFocusable()
    var state = initInteractionState()
    var firstFocused = 0
    var firstBlurred = 0
    var secondFocused = 0

    first.onFocus = proc(event: DispatchResult): EventOutcome =
      inc firstFocused
      false
    first.onBlur = proc(event: DispatchResult): EventOutcome =
      inc firstBlurred
      false
    second.onFocus = proc(event: DispatchResult): EventOutcome =
      inc secondFocused
      false

    check ui.moveFocus(state, 1)
    check state.focusedTarget == some(first.nodeId)
    check esFocus in ui.tree.nodes[first.nodeId.nodeIndex].states
    check esFocusVisible in ui.tree.nodes[first.nodeId.nodeIndex].states
    check firstFocused == 1

    check ui.moveFocus(state, 1)
    check state.focusedTarget == some(second.nodeId)
    check esFocus notin ui.tree.nodes[first.nodeId.nodeIndex].states
    check esFocusVisible notin ui.tree.nodes[first.nodeId.nodeIndex].states
    check esFocusVisible in ui.tree.nodes[second.nodeId.nodeIndex].states
    check firstBlurred == 1
    check secondFocused == 1

    check ui.moveFocus(state, -1)
    check state.focusedTarget == some(first.nodeId)

  test "pointer focus keeps focus without keyboard focus-visible state":
    let ui = initUiRoot()
    let control = ui.box()
    control.setFocusable()
    var state = initInteractionState()

    check ui.setFocus(state, some(control.nodeId), focusVisible = true)
    check esFocusVisible in ui.tree.nodes[control.nodeId.nodeIndex].states
    check not ui.normalizeFocus(state, some(control.nodeId))
    check esFocus in ui.tree.nodes[control.nodeId.nodeIndex].states
    check esFocusVisible notin ui.tree.nodes[control.nodeId.nodeIndex].states

  test "standard controls opt into the common focus mechanism":
    let ui = initUiRoot()
    let button = ui.button("Save")
    let checkbox = ui.checkbox("Remember")
    let slider = ui.slider(value = 0, min = 0, max = 10)
    let input = ui.textInput(TextInputParams(value: ""))

    check button.container.focusable
    check checkbox.container.focusable
    check slider.container.focusable
    check input.container.focusable
    check ui.focusTargets() == @[
      button.container.nodeId,
      checkbox.container.nodeId,
      slider.container.nodeId,
      input.container.nodeId
    ]
