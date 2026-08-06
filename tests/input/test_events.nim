import std/[options, sequtils, strutils, unittest]

import clay_board_style_system

suite "input events":
  test "dispatchInput targets the hit node with local coordinates":
    let root = NodeId(0)
    let button = NodeId(1)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]

    let dispatch = dispatchInput(regions, clickEvent(vec2(14, 13)))

    check dispatch.target == some(button)
    check dispatch.local == some(vec2(4, 5))
    check dispatch.event.kind == iekClick

  test "onClick can mutate local state captured by a handler":
    let button = NodeId(1)
    var clicks = 0
    var registry = initEventRegistry()
    registry.onClick(button, proc(event: DispatchResult): EventOutcome =
      inc clicks
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(button),
      local: some(vec2(0, 0)),
      event: clickEvent(vec2(10, 10))
    ))

    check handled
    check clicks == 1

  test "setEventHandler replaces existing user handler for the same slot":
    let button = NodeId(1)
    var calls: seq[string] = @[]
    var registry = initEventRegistry()

    registry.setEventHandler(button, iekClick, proc(event: DispatchResult): EventOutcome =
      calls.add "first"
      true
    )
    registry.setEventHandler(button, iekClick, proc(event: DispatchResult): EventOutcome =
      calls.add "second"
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(button),
      local: some(vec2(0, 0)),
      event: clickEvent(vec2(10, 10))
    ))

    check handled
    check calls == @["second"]
    check registry.bindings.len == 1

  test "setEventHandler preserves internal handlers":
    let button = NodeId(1)
    var calls: seq[string] = @[]
    var registry = initEventRegistry()

    registry.addInternalEventHandler(button, iekClick, proc(event: DispatchResult): EventOutcome =
      calls.add "internal"
      false
    )
    registry.setEventHandler(button, iekClick, proc(event: DispatchResult): EventOutcome =
      calls.add "user"
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(button),
      local: some(vec2(0, 0)),
      event: clickEvent(vec2(10, 10))
    ))

    check handled
    check calls == @["user", "internal"]
    check registry.bindings.len == 2

  test "public slot replacement preserves additive observers":
    let button = NodeId(1)
    var calls: seq[string] = @[]
    var registry = initEventRegistry()

    discard registry.subscribe(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "observer"
        ignoredEvent()
    )
    registry.setEventHandler(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "first-public"
        ignoredEvent()
    )
    registry.setEventHandler(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "second-public"
        handledEvent()
    )

    check registry.handle(DispatchResult(
      target: some(button),
      event: clickEvent(vec2(0, 0))
    ))
    check calls == @["second-public", "observer"]
    check registry.bindings.len == 2

  test "registry slot procs remain additive listeners":
    let button = NodeId(1)
    var calls: seq[string] = @[]
    var registry = initEventRegistry()

    registry.onClick(button, proc(event: DispatchResult): EventOutcome =
      calls.add "first"
      false
    )
    registry.onClick(button, proc(event: DispatchResult): EventOutcome =
      calls.add "second"
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(button),
      local: some(vec2(0, 0)),
      event: clickEvent(vec2(10, 10))
    ))

    check handled
    check calls == @["first", "second"]
    check registry.bindings.len == 2

  test "onClick can dispatch to an external store":
    type
      ActionKind = enum
        akSaveClicked

      Action = object
        kind: ActionKind
        node: NodeId

      Store = object
        actions: seq[Action]

    proc dispatch(store: var Store; action: Action) =
      store.actions.add action

    let button = NodeId(2)
    var store = Store(actions: @[])
    var registry = initEventRegistry()
    registry.onClick(button, proc(event: DispatchResult): EventOutcome =
      store.dispatch(Action(kind: akSaveClicked, node: event.target.get))
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(button),
      local: some(vec2(0, 0)),
      event: clickEvent(vec2(10, 10))
    ))

    check handled
    check store.actions.len == 1
    check store.actions[0].kind == akSaveClicked
    check store.actions[0].node == button

  test "tree-aware handling bubbles from child to parent":
    var tree = initTree()
    let button = tree.addBox(id = "button")
    let label = tree.addText(button, "Run")
    var registry = initEventRegistry()
    var clicked = false

    registry.onClick(button, proc(event: DispatchResult): EventOutcome =
      clicked = true
      check event.target == some(label)
      check event.currentTarget == some(button)
      check event.phase == epBubble
      check event.local.isNone
      true
    )

    let handled = registry.handle(tree, DispatchResult(
      target: some(label),
      local: some(vec2(4, 2)),
      event: clickEvent(vec2(12, 10))
    ))

    check handled
    check clicked

  test "preventDefault suppresses intrinsic action without stopping bubbling":
    var tree = initTree()
    let parent = tree.addBox(id = "parent")
    let control = tree.addBox(parent = some(parent), id = "control")
    var registry = initEventRegistry()
    var calls: seq[string] = @[]

    registry.onClick(control, proc(event: DispatchResult): EventOutcome =
      calls.add "user"
      preventedEvent()
    )
    registry.onClick(parent, proc(event: DispatchResult): EventOutcome =
      calls.add "parent"
      ignoredEvent()
    )
    registry.addInternalEventHandler(control, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "default"
        handledEvent()
    )
    registry.addInternalEventHandler(parent, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "parent-default"
        handledEvent()
    )

    let outcome = registry.dispatchEvent(tree, DispatchResult(
      target: some(control),
      local: some(vec2(2, 3)),
      event: clickEvent(vec2(12, 13))
    ))

    check outcome.handled
    check outcome.preventDefault
    check not outcome.stopPropagation
    check calls == @["user", "parent"]

  test "stopPropagation retains the target default action":
    var tree = initTree()
    let parent = tree.addBox(id = "parent")
    let control = tree.addBox(parent = some(parent), id = "control")
    var registry = initEventRegistry()
    var calls: seq[string] = @[]

    registry.onClick(control, proc(event: DispatchResult): EventOutcome =
      calls.add "user"
      stoppedEvent()
    )
    registry.onClick(parent, proc(event: DispatchResult): EventOutcome =
      calls.add "parent"
      ignoredEvent()
    )
    registry.addInternalEventHandler(control, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "default"
        handledEvent()
    )

    let outcome = registry.dispatchEvent(tree, DispatchResult(
      target: some(control),
      event: clickEvent(vec2(1, 1))
    ))

    check outcome.handled
    check outcome.stopPropagation
    check not outcome.preventDefault
    check calls == @["user", "default"]

  test "non-bubbling events remain on the original target":
    var tree = initTree()
    let parent = tree.addBox(id = "parent")
    let child = tree.addBox(parent = some(parent), id = "child")
    var registry = initEventRegistry()
    var calls: seq[string] = @[]

    registry.onFocus(child, proc(event: DispatchResult): EventOutcome =
      calls.add "child"
      check event.target == some(child)
      check event.currentTarget == some(child)
      check event.phase == epTarget
      handledEvent()
    )
    registry.onFocus(parent, proc(event: DispatchResult): EventOutcome =
      calls.add "parent"
      handledEvent()
    )

    check registry.handle(tree, DispatchResult(
      target: some(child),
      event: event(iekFocus)
    ))
    check calls == @["child"]

  test "subscriptions can be removed without disturbing other listeners":
    let button = NodeId(1)
    var registry = initEventRegistry()
    var calls: seq[string] = @[]
    let removed = registry.subscribe(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "removed"
        handledEvent()
    )
    discard registry.subscribe(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "kept"
        handledEvent()
    )

    check registry.removeEventHandler(removed)
    check not registry.removeEventHandler(removed)
    check registry.handle(DispatchResult(
      target: some(button),
      event: clickEvent(vec2(0, 0))
    ))
    check calls == @["kept"]

  test "removal during dispatch does not shift or invoke stale bindings":
    let button = NodeId(1)
    var registry = initEventRegistry()
    let registryPtr = addr registry
    var removed: EventSubscription
    var calls: seq[string] = @[]

    discard registry.subscribe(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "first"
        check registryPtr[].removeEventHandler(removed)
        ignoredEvent()
    )
    removed = registry.subscribe(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "removed"
        handledEvent()
    )
    discard registry.subscribe(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        calls.add "last"
        handledEvent()
    )

    check registry.handle(DispatchResult(
      target: some(button),
      event: clickEvent(vec2(0, 0))
    ))
    check calls == @["first", "last"]
    check registry.bindings.len == 2

  test "repeated dispatch-time subscription removal remains bounded":
    let button = NodeId(1)
    var registry = initEventRegistry()
    let registryPtr = addr registry
    var stableCalls = 0

    discard registry.subscribe(button, iekClick,
      proc(event: DispatchResult): EventOutcome =
        inc stableCalls
        ignoredEvent()
    )

    for iteration in 0 ..< 1_000:
      var transient: EventSubscription
      transient = registry.subscribe(button, iekClick,
        proc(event: DispatchResult): EventOutcome =
          check registryPtr[].removeEventHandler(transient)
          handledEvent()
      )

      check registry.handle(DispatchResult(
        target: some(button),
        event: clickEvent(vec2(float32(iteration mod 10), 0))
      ))
      check registry.bindings.len == 1

    check stableCalls == 1_000

  test "unhandled event returns false":
    var registry = initEventRegistry()
    let handled = registry.handle(DispatchResult(
      target: some(NodeId(1)),
      local: none(Vec2),
      event: keyDownEvent("Enter")
    ))

    check not handled

  test "keyboard events expose modifier keys":
    var registry = initEventRegistry()
    var sawShortcut = false

    registry.onKeyDown(NodeId(1), proc(event: DispatchResult): EventOutcome =
      check event.event.kind == iekKeyDown
      check event.event.key == some("s")
      check event.event.ctrlKey
      check not event.event.altKey
      check event.event.shiftKey
      check not event.event.metaKey
      sawShortcut = true
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(NodeId(1)),
      local: none(Vec2),
      event: keyDownEvent("s", ctrlKey = true, shiftKey = true)
    ))

    check handled
    check sawShortcut

  test "onChange dispatches standard change events":
    var registry = initEventRegistry()
    var changed = ""
    registry.onChange(NodeId(1), proc(event: DispatchResult): EventOutcome =
      if event.event.text.isSome:
        changed = event.event.text.get
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(NodeId(1)),
      local: none(Vec2),
      event: changeEvent("ready")
    ))

    check handled
    check changed == "ready"

  test "onInput dispatches standard input events":
    var registry = initEventRegistry()
    var value = ""
    registry.onInput(NodeId(1), proc(event: DispatchResult): EventOutcome =
      if event.event.text.isSome:
        value = event.event.text.get
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(NodeId(1)),
      local: none(Vec2),
      event: inputEvent("typing")
    ))

    check handled
    check value == "typing"

  test "raw text input drives only pre-mutation handlers":
    var registry = initEventRegistry()
    let node = NodeId(1)
    var seen: seq[InputEventKind] = @[]
    let handler = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false

    registry.onBeforeInput(node, handler)
    registry.onTextInput(node, handler)
    registry.onInput(node, handler)
    registry.onChange(node, handler)

    discard registry.handle(DispatchResult(
      target: some(node),
      local: none(Vec2),
      event: textInputEvent("a")
    ))
    check seen == @[iekBeforeInput, iekTextInput]

  test "mouse slots are synthesized from pointer events":
    var registry = initEventRegistry()
    var received = 0
    registry.onMouseDown(NodeId(1), proc(event: DispatchResult): EventOutcome =
      check event.event.kind == iekMouseDown
      inc received
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(NodeId(1)),
      local: some(vec2(2, 4)),
      event: pointerDownEvent(vec2(2, 4), 1)
    ))

    check handled
    check received == 1

  test "wheel input does not report scroll without retained movement":
    var registry = initEventRegistry()
    var wheeled = false
    var scrolled = false
    registry.onWheel(NodeId(1), proc(event: DispatchResult): EventOutcome =
      check event.event.kind == iekWheel
      wheeled = true
      false
    )
    registry.onScroll(NodeId(1), proc(event: DispatchResult): EventOutcome =
      scrolled = true
      true
    )

    let handled = registry.handle(DispatchResult(
      target: some(NodeId(1)),
      local: some(vec2(8, 12)),
      event: wheelEvent(vec2(8, 12), vec2(0, -1))
    ))

    check not handled
    check wheeled
    check not scrolled

  test "finishScroll emits scroll end for the latest scrolled target":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let panel = tree.addBox(parent = some(root), id = "panel")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 120, 80), zIndex: 0),
      HitRegion(node: panel, rect: rect(10, 8, 80, 40), zIndex: 1)
    ]
    var state = initInteractionState()
    var scroll = initScrollState()
    scroll.entries = newSeq[ScrollMetrics](tree.nodes.len)
    scroll.entries[panel.nodeIndex] = ScrollMetrics(
      active: true,
      node: some(panel),
      viewport: size(80, 40),
      content: size(80, 100),
      enabledY: true
    )
    var registry = initEventRegistry()
    var ended = false

    registry.onScrollEnd(panel, proc(event: DispatchResult): EventOutcome =
      check event.event.kind == iekScrollEnd
      ended = true
      true
    )

    discard state.processInput(
      tree, regions, wheelEvent(vec2(20, 20), vec2(0, 10)), scroll
    )
    let endDispatches = state.finishScroll(scroll)

    check endDispatches.len == 1
    check endDispatches[0].target == some(panel)
    check registry.handle(endDispatches)
    check ended
    check state.finishScroll(scroll).len == 0

  test "component events can be emitted explicitly":
    var registry = initEventRegistry()
    var submitted = false
    registry.onSubmit(NodeId(1), proc(event: DispatchResult): EventOutcome =
      check event.event.kind == iekSubmit
      submitted = true
      true
    )

    check registry.emit(NodeId(1), iekSubmit)
    check submitted

  test "focused clipboard and composition events can be emitted":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let input = tree.addBox(parent = some(root), id = "input")
    tree.setFocusable(input)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: input, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var seen: seq[InputEventKind] = @[]
    var pasted = ""
    var composition = ""

    let collect = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      if event.event.kind == iekPaste and event.event.text.isSome:
        pasted = event.event.text.get
      if event.event.kind == iekCompositionUpdate and event.event.text.isSome:
        composition = event.event.text.get
      false

    registry.onCopy(input, collect)
    registry.onCut(input, collect)
    registry.onPaste(input, collect)
    registry.onCompositionStart(input, collect)
    registry.onCompositionUpdate(input, collect)
    registry.onCompositionEnd(input, collect)

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    discard registry.emitFocused(state, copyEvent())
    discard registry.emitFocused(state, cutEvent())
    discard registry.emitFocused(state, pasteEvent("hello"))
    discard registry.emitFocused(state, compositionStartEvent())
    discard registry.emitFocused(state, compositionUpdateEvent("かな"))
    discard registry.emitFocused(state, compositionEndEvent("仮名"))

    check seen == @[
      iekCopy,
      iekCut,
      iekPaste,
      iekCompositionStart,
      iekCompositionUpdate,
      iekCompositionEnd
    ]
    check pasted == "hello"
    check composition == "かな"

  test "focus owned events are rejected after focus changes":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")
    tree.setFocusable(first)
    tree.setFocusable(second)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 160, 40), zIndex: 0),
      HitRegion(node: first, rect: rect(10, 8, 40, 20), zIndex: 1),
      HitRegion(node: second, rect: rect(70, 8, 40, 20), zIndex: 1)
    ]
    var state = initInteractionState()

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    check state.focusedTarget == some(first)
    let firstSerial = state.focusSerial
    let owned = textInputEvent("a").markFocusOwned(state)

    discard state.processInput(tree, regions, pointerDownEvent(vec2(72, 10)))
    check state.focusedTarget == some(second)
    check state.focusSerial > firstSerial
    check not state.acceptsFocusOwnedEvent(owned)
    check state.acceptsFocusOwnedEvent(textInputEvent("b").markFocusOwned(state))

  test "registry rejects focus owned events dispatched to another node":
    var registry = initEventRegistry()
    let owner = NodeId(1)
    let other = NodeId(2)
    var seen = false

    registry.onTextInput(other, proc(event: DispatchResult): EventOutcome =
      seen = true
      false
    )

    let event = textInputEvent("x").markFocusOwned(owner, 1)
    check not registry.handle(DispatchResult(
      target: some(other),
      local: none(Vec2),
      event: event
    ))
    check not seen

  test "event dispatch modes expose non-backend event requirements":
    var registry = initEventRegistry()
    let node = NodeId(1)
    let handler = proc(event: DispatchResult): EventOutcome = stoppedEvent()

    registry.onClick(node, handler)
    registry.onSubmit(node, handler)
    registry.onResize(node, handler)

    check dispatchMode(iekPointerDown) == edmBackendInput
    check dispatchMode(iekClick) == edmCoreSynthetic
    check dispatchMode(iekSubmit) == edmComponentDispatch
    check dispatchMode(iekResize) == edmBackendInput
    check registry.bindingsNeedingComponentDispatch().len == 1
    check registry.bindingsNeedingComponentDispatch()[0].kind == iekSubmit

  test "event definitions are complete and expose stable ABI metadata":
    var abiCodes: seq[uint32]
    for kind in InputEventKind:
      let definition = kind.eventDefinition
      check definition.abiCode == uint32(ord(kind))
      check definition.abiCode notin abiCodes
      check definition.aliasCount <= uint8(definition.aliases.len)
      abiCodes.add definition.abiCode

    check iekPointerDown.eventDefinition.producer == edmBackendInput
    check iekClick.eventDefinition.producer == edmCoreSynthetic
    check iekSubmit.eventDefinition.producer == edmComponentDispatch
    check not iekPointerEnter.eventDefinition.bubbles
    check not iekResize.eventDefinition.cancelable
    check iekPointerMove.eventDefinition.payload ==
      {epfPosition, epfButton, epfPointer}
    check iekWheel.eventDefinition.payload ==
      {epfPosition, epfDelta, epfPointer}
    check iekTextInput.eventDefinition.payload ==
      {epfText, epfFocusOwnership}
    check iekPointerDown.eventDefinition.aliasCount == 2
    check iekPointerDown.eventDefinition.aliases ==
      [iekMouseDown, iekPointerDown]
    check iekSubmit.eventDefinition.aliasCount == 0

  test "processInput synthesizes enter leave and focus events":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    tree.setFocusable(button)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var entered = false
    var focused = false

    registry.onMouseEnter(button, proc(event: DispatchResult): EventOutcome =
      check event.event.kind == iekMouseEnter
      entered = true
      true
    )
    registry.onFocus(button, proc(event: DispatchResult): EventOutcome =
      focused = true
      true
    )

    let move = state.processInput(tree, regions, pointerMoveEvent(vec2(12, 10)))
    check move.len == 3
    check move[0].event.kind == iekPointerOver
    check move[1].event.kind == iekPointerEnter
    check move[2].event.kind == iekPointerMove
    check registry.handle(move)
    check entered

    let down = state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    check down.len == 2
    check down[0].event.kind == iekFocus
    check down[1].event.kind == iekPointerDown
    check registry.handle(down)
    check focused

  test "processInput blurs previous focus before focusing a new target":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")
    tree.setFocusable(first)
    tree.setFocusable(second)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 160, 40), zIndex: 0),
      HitRegion(node: first, rect: rect(10, 8, 40, 20), zIndex: 1),
      HitRegion(node: second, rect: rect(70, 8, 40, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var seen: seq[InputEventKind] = @[]

    registry.onFocus(first, proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false
    )
    registry.onBlur(first, proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false
    )
    registry.onFocus(second, proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false
    )

    discard registry.handle(state.processInput(tree, regions, pointerDownEvent(vec2(12, 10))))
    discard registry.handle(state.processInput(tree, regions, pointerUpEvent(vec2(12, 10))))
    discard registry.handle(state.processInput(tree, regions, pointerDownEvent(vec2(72, 10))))

    check seen == @[iekFocus, iekBlur, iekFocus]
    check esFocus notin tree.nodes[first.nodeIndex].states
    check esFocus in tree.nodes[second.nodeIndex].states

  test "processInput synthesizes context and double click events":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    tree.setFocusable(button)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var contextMenu = false
    var doubleClicked = false

    registry.onContextMenu(button, proc(event: DispatchResult): EventOutcome =
      contextMenu = true
      true
    )
    registry.onDoubleClick(button, proc(event: DispatchResult): EventOutcome =
      doubleClicked = true
      true
    )

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10), 3))
    let rightUp = state.processInput(tree, regions, pointerUpEvent(vec2(12, 10), 3))
    check registry.handle(rightUp)
    check contextMenu

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10), 1))
    discard state.processInput(tree, regions, pointerUpEvent(vec2(12, 10), 1))
    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10), 1))
    let secondUp = state.processInput(tree, regions, pointerUpEvent(vec2(12, 10), 1))
    check registry.handle(secondUp)
    check doubleClicked

  test "processInput synthesizes drag and drop events":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let source = tree.addBox(parent = some(root), id = "source")
    let target = tree.addBox(parent = some(root), id = "target")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 140, 40), zIndex: 0),
      HitRegion(node: source, rect: rect(10, 8, 40, 20), zIndex: 1),
      HitRegion(node: target, rect: rect(70, 8, 40, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var seen: seq[InputEventKind] = @[]
    var dragLocal = none(Vec2)

    let collect = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false

    registry.onDragStart(source, collect)
    registry.onDrag(source, proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      dragLocal = event.local
      false
    )
    registry.onDragEnter(target, collect)
    registry.onDragOver(target, collect)
    registry.onDrop(target, collect)
    registry.onDragEnd(source, collect)
    registry.onClick(source, collect)

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10), 1))
    let move = state.processInput(tree, regions, pointerMoveEvent(vec2(75, 10)))
    discard registry.handle(move)
    let up = state.processInput(tree, regions, pointerUpEvent(vec2(75, 10), 1))
    discard registry.handle(up)

    check seen == @[
      iekDragStart,
      iekDrag,
      iekDragEnter,
      iekDragOver,
      iekDrop,
      iekDragEnd
    ]
    check dragLocal.isSome
    check dragLocal.get.x == 65
    check dragLocal.get.y == 2

  test "small pointer jitter keeps a click and does not start dragging":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    let move = state.processInput(tree, regions, pointerMoveEvent(vec2(14, 11)))
    let up = state.processInput(tree, regions, pointerUpEvent(vec2(14, 11)))

    check move.allIt(it.event.kind notin {iekDragStart, iekDrag})
    check up.anyIt(it.event.kind == iekClick)

  test "pointer cancel releases pressed drag and capture state":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let source = tree.addBox(parent = some(root), id = "source")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: source, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    discard state.capturePointer(source)
    discard state.processInput(tree, regions, pointerMoveEvent(vec2(30, 10)))
    let cancelled = state.processInput(tree, regions, positionedEvent(iekPointerCancel, vec2(30, 10)))

    check state.pressedTarget.isNone
    check state.dragTarget.isNone
    check state.dragOverTarget.isNone
    check state.pointerCaptureTarget.isNone
    check cancelled.anyIt(it.event.kind == iekLostPointerCapture)

  test "pointer capture routes pointer events to captured target":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let captured = tree.addBox(parent = some(root), id = "captured")
    let other = tree.addBox(parent = some(root), id = "other")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 140, 40), zIndex: 0),
      HitRegion(node: captured, rect: rect(10, 8, 40, 20), zIndex: 1),
      HitRegion(node: other, rect: rect(70, 8, 40, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var seen: seq[InputEventKind] = @[]

    registry.onGotPointerCapture(captured, proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      true
    )
    registry.onPointerMove(captured, proc(event: DispatchResult): EventOutcome =
      check event.target == some(captured)
      seen.add event.event.kind
      true
    )
    registry.onLostPointerCapture(captured, proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      true
    )

    check registry.handle(state.capturePointer(captured))
    let move = state.processInput(tree, regions, pointerMoveEvent(vec2(75, 10)))
    check move[^1].target == some(captured)
    check registry.handle(move)
    let released = state.releasePointer()
    check released.isSome
    check registry.handle(released.get)
    let afterRelease = state.processInput(tree, regions, pointerMoveEvent(vec2(75, 10)))
    check afterRelease[^1].target == some(other)

    check seen == @[iekGotPointerCapture, iekPointerMove, iekLostPointerCapture]

  test "touch input drives pointer compatible handlers":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var seen: seq[InputEventKind] = @[]

    let collect = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false

    registry.onPointerDown(button, collect)
    registry.onTouchStart(button, collect)
    registry.onPointerUp(button, collect)
    registry.onTouchEnd(button, collect)
    registry.onClick(button, collect)

    let down = state.processInput(tree, regions, touchStartEvent(vec2(12, 10)))
    discard registry.handle(down)
    let up = state.processInput(tree, regions, touchEndEvent(vec2(12, 10)))
    discard registry.handle(up)

    check seen == @[iekPointerDown, iekTouchStart, iekPointerUp, iekTouchEnd, iekClick]

  test "touch pointer metadata survives pointer-compatible dispatch":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let target = tree.addBox(parent = some(root), id = "target")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: target, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var pointerSamples: seq[PointerData]
    var touchSamples: seq[PointerData]

    registry.onPointerMove(target, proc(event: DispatchResult): EventOutcome =
      check event.event.pointer.isSome
      pointerSamples.add event.event.pointer.get
      false
    )
    registry.onTouchMove(target, proc(event: DispatchResult): EventOutcome =
      check event.event.pointer.isSome
      touchSamples.add event.event.pointer.get
      false
    )

    let dispatches = state.processInput(
      tree,
      regions,
      touchMoveEvent(
        vec2(12, 10), vec2(2, 1), pressure = 0.375, deviceId = 42
      )
    )
    discard registry.handle(dispatches)

    check pointerSamples.len == 1
    check touchSamples.len == 1
    for sample in [pointerSamples[0], touchSamples[0]]:
      check sample.device == pdkTouch
      check sample.deviceId == 42
      check paPressure in sample.axes
      check abs(sample.pressure - 0.375) < 0.0001
      check sample.contact
      check sample.inProximity

  test "touch release retains a supported zero pressure value":
    let released = touchEndEvent(vec2(2, 3), deviceId = 9)
    check released.pointer.isSome
    check released.pointer.get.device == pdkTouch
    check released.pointer.get.deviceId == 9
    check paPressure in released.pointer.get.axes
    check released.pointer.get.pressure == 0
    check not released.pointer.get.contact

  test "js and ts style event slots can be registered":
    var registry = initEventRegistry()
    let node = NodeId(1)
    let handler = proc(event: DispatchResult): EventOutcome = stoppedEvent()

    template attach(registrar: untyped) =
      registry.registrar(node, handler)

    attach(onAbort)
    attach(onAnimationEnd)
    attach(onAnimationIteration)
    attach(onAnimationStart)
    attach(onAuxClick)
    attach(onBeforeInput)
    attach(onBlur)
    attach(onCancel)
    attach(onCanPlay)
    attach(onCanPlayThrough)
    attach(onChange)
    attach(onClick)
    attach(onClose)
    attach(onContextMenu)
    attach(onCopy)
    attach(onCueChange)
    attach(onCut)
    attach(onDblClick)
    attach(onDoubleClick)
    attach(onCompositionEnd)
    attach(onCompositionStart)
    attach(onCompositionUpdate)
    attach(onDrag)
    attach(onDragEnd)
    attach(onDragEnter)
    attach(onDragExit)
    attach(onDragLeave)
    attach(onDragOver)
    attach(onDragStart)
    attach(onDrop)
    attach(onDurationChange)
    attach(onEmptied)
    attach(onEncrypted)
    attach(onEnded)
    attach(onError)
    attach(onFocus)
    attach(onFullscreenChange)
    attach(onFullscreenError)
    attach(onGotPointerCapture)
    attach(onInput)
    attach(onInvalid)
    attach(onKeyDown)
    attach(onKeyUp)
    attach(onLoad)
    attach(onLoadEnd)
    attach(onLoadedData)
    attach(onLoadedMetadata)
    attach(onLoadStart)
    attach(onLostPointerCapture)
    attach(onMouseDown)
    attach(onMouseEnter)
    attach(onMouseLeave)
    attach(onMouseMove)
    attach(onMouseOut)
    attach(onMouseOver)
    attach(onMouseUp)
    attach(onPaste)
    attach(onPause)
    attach(onPlay)
    attach(onPlaying)
    attach(onPointerCancel)
    attach(onPointerDown)
    attach(onPointerEnter)
    attach(onPointerLeave)
    attach(onPointerMove)
    attach(onPointerOut)
    attach(onPointerOver)
    attach(onPointerUp)
    attach(onProgress)
    attach(onRateChange)
    attach(onReset)
    attach(onResize)
    attach(onScroll)
    attach(onScrollEnd)
    attach(onSeeked)
    attach(onSeeking)
    attach(onSelect)
    attach(onShow)
    attach(onStalled)
    attach(onSubmit)
    attach(onSuspend)
    attach(onTextInput)
    attach(onTimeUpdate)
    attach(onToggle)
    attach(onTouchCancel)
    attach(onTouchEnd)
    attach(onTouchMove)
    attach(onTouchStart)
    attach(onTransitionEnd)
    attach(onVolumeChange)
    attach(onWaiting)
    attach(onWheel)

    check registry.bindings.len == 92
    check registry.handle(DispatchResult(target: some(node), local: none(Vec2), event: event(iekSubmit)))
    check registry.handle(DispatchResult(target: some(node), local: none(Vec2), event: event(iekDoubleClick)))

  test "processInput updates hover and synthesizes click":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    tree.setFocusable(button)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 60, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var clicks = 0
    var registry = initEventRegistry()
    registry.onClick(button, proc(event: DispatchResult): EventOutcome =
      inc clicks
      true
    )

    discard state.processInput(tree, regions, pointerMoveEvent(vec2(12, 10)))
    check esHover in tree.nodes[button.nodeIndex].states

    let down = state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    check down.len == 2
    check down[0].event.kind == iekFocus
    check down[1].event.kind == iekPointerDown
    check esActive in tree.nodes[button.nodeIndex].states

    let up = state.processInput(tree, regions, pointerUpEvent(vec2(12, 10)))
    check up.len == 2
    check up[0].event.kind == iekPointerUp
    check up[1].event.kind == iekClick
    check esActive notin tree.nodes[button.nodeIndex].states

    check registry.handle(up)
    check clicks == 1

  test "processInput does not focus activate or click disabled targets":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    tree.setFocusable(button)
    tree.setState(button, esDisabled, true)
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 20, 20), zIndex: 1)
    ]
    var state = initInteractionState()
    var registry = initEventRegistry()
    var clicks = 0
    registry.onClick(button, proc(event: DispatchResult): EventOutcome =
      inc clicks
      true
    )

    let down = state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    check down.len == 1
    check down[0].event.kind == iekPointerDown
    check esActive notin tree.nodes[button.nodeIndex].states
    check esFocus notin tree.nodes[button.nodeIndex].states
    check state.focusedTarget.isNone

    let up = state.processInput(tree, regions, pointerUpEvent(vec2(12, 10)))
    check up.len == 1
    check up[0].event.kind == iekPointerUp
    discard registry.handle(up)
    check clicks == 0

  test "processInput does not synthesize click when pointer up targets another node":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 100, 40), zIndex: 0),
      HitRegion(node: button, rect: rect(10, 8, 20, 20), zIndex: 1)
    ]
    var state = initInteractionState()

    discard state.processInput(tree, regions, pointerDownEvent(vec2(12, 10)))
    let up = state.processInput(tree, regions, pointerUpEvent(vec2(80, 10)))

    check up.len == 1
    check up[0].event.kind == iekPointerUp

  test "paste events cap oversized text payloads":
    let event = pasteEvent("x".repeat(maxPasteEventBytes + 4096))

    check event.kind == iekPaste
    check event.text.isSome
    check event.text.get.len == maxPasteEventBytes
