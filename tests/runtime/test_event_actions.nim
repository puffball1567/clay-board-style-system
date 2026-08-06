import std/[options, unittest]

import clay_board_style_system

suite "dispatch-scoped event actions":
  test "handlers request focus invalidation and one frame without capturing UiRoot":
    let ui = initUiRoot()
    let button = ui.box()
    var retainedEvent: DispatchResult

    button.onClick = proc(event: DispatchResult): EventOutcome =
      retainedEvent = event
      check event.requestFocus()
      check event.invalidate({ddStyle, ddPaint})
      check event.invalidateRoot({ddResource})
      check event.requestFrame()
      handledEvent()

    let outcome = ui.dispatchEvent(DispatchResult(
      target: some(button.id),
      event: clickEvent(vec2(4, 5))
    ))

    check outcome.handled
    let focus = ui.takeFocusRequest()
    check focus.pending
    check focus.target == some(button.id)
    let invalidation = ui.consumeInvalidation()
    check invalidation.domains == {ddStyle, ddPaint, ddResource, ddAnimation}
    check invalidation.roots == @[button.id]
    check ui.takeFrameRequest()
    check not ui.takeFrameRequest()

    check not retainedEvent.requestFocus()
    check not retainedEvent.capturePointer()
    check not retainedEvent.invalidate({ddLayout})
    check not retainedEvent.requestFrame()

  test "pointer capture requests reconcile with host-owned interaction state":
    let ui = initUiRoot()
    let surface = ui.box()
    var interaction = initInteractionState()
    var captures = 0
    var releases = 0

    surface.onPointerDown = proc(event: DispatchResult): EventOutcome =
      check event.capturePointer()
      handledEvent()
    surface.onPointerUp = proc(event: DispatchResult): EventOutcome =
      check event.releasePointer()
      handledEvent()
    surface.onGotPointerCapture = proc(event: DispatchResult): EventOutcome =
      inc captures
      ignoredEvent()
    surface.onLostPointerCapture = proc(event: DispatchResult): EventOutcome =
      inc releases
      ignoredEvent()

    discard ui.dispatchEvent(DispatchResult(
      target: some(surface.id),
      event: pointerDownEvent(vec2(2, 3))
    ))
    check interaction.pointerCaptureTarget.isNone
    discard ui.reconcilePointerCapture(interaction)
    check interaction.pointerCaptureTarget == some(surface.id)
    check captures == 1

    discard ui.dispatchEvent(DispatchResult(
      target: some(surface.id),
      event: pointerUpEvent(vec2(5, 6))
    ))
    discard ui.reconcilePointerCapture(interaction)
    check interaction.pointerCaptureTarget.isNone
    check releases == 1

  test "a retained event cannot act during a later pooled dispatch":
    let ui = initUiRoot()
    let first = ui.box()
    let second = ui.box()
    var retainedEvent: DispatchResult
    var staleRequestAccepted = true

    first.onClick = proc(event: DispatchResult): EventOutcome =
      retainedEvent = event
      handledEvent()
    second.onClick = proc(event: DispatchResult): EventOutcome =
      staleRequestAccepted = retainedEvent.requestFrame()
      check event.requestFocus()
      handledEvent()

    discard ui.dispatchEvent(DispatchResult(
      target: some(first.id),
      event: clickEvent(vec2(1, 1))
    ))
    discard ui.dispatchEvent(DispatchResult(
      target: some(second.id),
      event: clickEvent(vec2(1, 1))
    ))

    check not staleRequestAccepted
    check not ui.takeFrameRequest()
    let focus = ui.takeFocusRequest()
    check focus.pending
    check focus.target == some(second.id)

  test "direct registry dispatch has no root-scoped action authority":
    let ui = initUiRoot()
    let button = ui.box()
    var accepted = true

    button.onClick = proc(event: DispatchResult): EventOutcome =
      accepted = event.requestFrame()
      handledEvent()

    check ui.events.handle(ui.tree, DispatchResult(
      target: some(button.id),
      event: clickEvent(vec2(0, 0))
    ))
    check not accepted
    check not ui.takeFrameRequest()

  test "disposing a requested pointer target cancels the pending capture":
    let ui = initUiRoot()
    let surface = ui.box()
    var interaction = initInteractionState()

    surface.onPointerDown = proc(event: DispatchResult): EventOutcome =
      check event.capturePointer()
      handledEvent()

    discard ui.dispatchEvent(DispatchResult(
      target: some(surface.id),
      event: pointerDownEvent(vec2(2, 3))
    ))
    check ui.disposeSubtree(surface, interaction)
    let outcome = ui.reconcilePointerCapture(interaction)

    check not outcome.handled
    check interaction.pointerCaptureTarget.isNone
