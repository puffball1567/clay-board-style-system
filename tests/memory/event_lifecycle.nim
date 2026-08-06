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

      doAssert ui.disposeSubtree(host, interaction)
      doAssert ui.events.bindings.len == 0

exerciseEventLifecycle()
