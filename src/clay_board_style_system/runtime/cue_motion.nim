import std/strutils

import ../input/events
import ./[cue, declarative_transition, ui_root]

type
  MotionStartProc* = proc() {.closure.}

proc cueMotion(
    name: string;
    target: NodeHandle;
    motionName: string;
    endKind, cancelKind: InputEventKind;
    start: MotionStartProc;
    cancelMotion: CueCancel;
    cancelledMessage: string
): CueAction =
  if not target.valid:
    raise newException(ValueError, "Cue motion target is not active")
  if motionName.len == 0:
    raise newException(ValueError, "Cue motion name cannot be empty")
  if start.isNil:
    raise newException(ValueError, "Cue motion start callback cannot be nil")
  if cancelledMessage.len == 0:
    raise newException(ValueError, "Cue motion cancellation message cannot be empty")

  cueAction(name, proc(completion: CueCompletion): CueCancel =
    var endSubscription: EventSubscription
    var cancelSubscription: EventSubscription
    var listening = true

    proc detach() {.raises: [].} =
      if not listening:
        return
      listening = false
      try:
        discard target.unsubscribe(endSubscription)
        discard target.unsubscribe(cancelSubscription)
      except Exception:
        discard

    proc settle(event: DispatchResult; succeeded: bool): EventOutcome =
      if not listening or event.motionName != motionName:
        return ignoredEvent()
      detach()
      try:
        if succeeded:
          completion.succeed()
        else:
          completion.fail(cancelledMessage)
      except Exception:
        discard
      ignoredEvent()

    try:
      endSubscription = target.subscribe(
        endKind,
        proc(event: DispatchResult): EventOutcome = settle(event, true)
      )
      cancelSubscription = target.subscribe(
        cancelKind,
        proc(event: DispatchResult): EventOutcome = settle(event, false)
      )
      start()
    except CatchableError as error:
      detach()
      completion.fail("Motion could not start: " & error.msg)

    return proc() {.raises: [].} =
      let wasListening = listening
      detach()
      if wasListening and cancelMotion != nil:
        cancelMotion()
  )

proc cueTransition*(
    name: string;
    target: NodeHandle;
    property: DeclarativeTransitionProperty;
    start: MotionStartProc;
    cancelMotion: CueCancel = nil;
    cancelledMessage = "Transition was cancelled"
): CueAction =
  cueMotion(
    name,
    target,
    property.transitionPropertyName,
    iekTransitionEnd,
    iekTransitionCancel,
    start,
    cancelMotion,
    cancelledMessage
  )

proc cueAnimation*(
    name: string;
    target: NodeHandle;
    animationName: string;
    start: MotionStartProc;
    cancelMotion: CueCancel = nil;
    cancelledMessage = "Animation was cancelled"
): CueAction =
  let normalized = animationName.strip
  if normalized.len == 0:
    raise newException(ValueError, "Cue animation name cannot be empty")
  cueMotion(
    name,
    target,
    normalized,
    iekAnimationEnd,
    iekAnimationCancel,
    start,
    cancelMotion,
    cancelledMessage
  )
