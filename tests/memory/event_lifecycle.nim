import std/options

import clay_board_style_system

const lifecycleIterations = 500

proc exerciseEventLifecycle() =
  for iteration in 0 ..< lifecycleIterations:
    block:
      let ui = initUiRoot()
      let host = ui.box()
      let target = ui.box(parent = some(host))
      var interaction = initInteractionState()
      var publicCalls = 0
      var observerCalls = 0
      var observation: EventSubscription

      target.onClick = proc(event: DispatchResult): EventOutcome =
        inc publicCalls
        doAssert event.requestFocus()
        doAssert event.invalidate({ddStyle, ddLayout, ddPaint, ddHit})
        doAssert event.requestFrame()
        handledEvent()

      observation = target.subscribe(
        iekClick,
        proc(event: DispatchResult): EventOutcome =
          inc observerCalls
          doAssert target.unsubscribe(observation)
          ignoredEvent()
      )

      let outcome = ui.dispatchEvent(DispatchResult(
        target: some(target.id),
        event: clickEvent(vec2(float32(iteration mod 10), 1))
      ))
      doAssert outcome.handled
      doAssert publicCalls == 1
      doAssert observerCalls == 1
      doAssert ui.events.bindings.len == 1

      let focus = ui.takeFocusRequest()
      doAssert focus.pending and focus.target == some(target.id)
      let invalidation = ui.consumeInvalidation()
      doAssert invalidation.domains ==
        {ddStyle, ddLayout, ddPaint, ddHit, ddAnimation}
      doAssert ui.takeFrameRequest()

      let regions = @[HitRegion(
        node: target.id, rect: rect(0, 0, 40, 20), zIndex: 0
      )]
      var dragBuilder = initFormDataBuilder()
      dragBuilder.addBlob("application/octet-stream", newBlob([byte 1, 2, 3]))
      discard interaction.processInput(
        ui.tree, regions, pointerDownEvent(vec2(2, 2))
      )
      doAssert interaction.setDragData(target.id, dragBuilder.finish())
      doAssert interaction.setDragOperations(target.id, {dgoCopy})
      ui.scroll.entries.setLen(ui.tree.nodes.len)
      ui.scroll.entries[target.id.nodeIndex] = ScrollMetrics(
        active: true, node: some(target.id),
        viewport: size(40, 20), content: size(40, 80),
        enabledY: true, overscrollY: obAuto
      )
      let dragDispatches = interaction.processInput(
        ui.tree, regions, pointerMoveEvent(vec2(12, 18)), ui.scroll
      )
      doAssert dragDispatches.len > 0
      doAssert interaction.dragData.isSome
      doAssert interaction.dragAutoScrollTarget == some(target.id)
      doAssert interaction.acceptDropDataEntry(
        target.id, dgoCopy, "application/octet-stream", fdvBlob
      )
      doAssert interaction.dropDataEntry.isSome

      doAssert ui.disposeSubtree(host, interaction)
      doAssert interaction.dragData.isNone
      doAssert interaction.dragOperations.isNone
      doAssert interaction.dropOperation.isNone
      doAssert interaction.dropDataEntry.isNone
      doAssert interaction.dragAutoScrollTarget.isNone
      doAssert ui.events.bindings.len == 0

    if iteration mod 5 == 0:
      let ui = initUiRoot()
      let host = ui.box()
      let source = ui.box(parent = some(host))
      let target = ui.box(parent = some(host))
      var interaction = initInteractionState()
      var dragBuilder = initFormDataBuilder()
      dragBuilder.addBlob("application/octet-stream", newBlob([byte 4, 5, 6]))
      discard interaction.setFocusedTarget(some(source.id))
      doAssert interaction.startKeyboardDrag(
        ui.tree, source.id, {dgoCopy}, some(dragBuilder.finish())
      ).isSome
      discard interaction.setFocusedTarget(some(target.id))
      doAssert interaction.advanceKeyboardDrag(ui.tree).len > 0
      doAssert interaction.acceptDropDataEntry(
        target.id, dgoCopy, "application/octet-stream", fdvBlob
      )
      doAssert ui.disposeSubtree(source, interaction)
      doAssert not interaction.keyboardDragging
      doAssert interaction.dragData.isNone
      doAssert interaction.dragOperations.isNone
      doAssert interaction.dropDataEntry.isNone

exerciseEventLifecycle()
