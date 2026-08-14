import ./[canvas, cue, render_surface, ui_root]

type
  CueCanvasFrameDecision* = enum
    ccfdContinue,
    ccfdComplete

  CueCanvasFrameProc* = proc(
    canvas: Canvas2D;
    frame: RenderSurfaceFrame
  ): CueCanvasFrameDecision {.closure.}

proc cueCanvas*(
    name: string;
    target: CanvasHandle;
    onFrame: CueCanvasFrameProc;
    cancelCanvas: CueCancel = nil;
    disposedMessage = "Canvas was disposed"
): CueAction =
  if not target.valid:
    raise newException(ValueError, "Cue Canvas target is not active")
  if onFrame.isNil:
    raise newException(ValueError, "Cue Canvas frame callback cannot be nil")
  if disposedMessage.len == 0:
    raise newException(ValueError, "Cue Canvas disposal message cannot be empty")

  cueAction(name, proc(completion: CueCompletion): CueCancel =
    if not target.valid:
      completion.fail(disposedMessage)
      return nil

    var subscription: CanvasFrameSubscription
    var listening = true

    proc detach() {.raises: [].} =
      if not listening:
        return
      listening = false
      try:
        discard target.canvas.unsubscribeFrames(subscription)
      except Exception:
        discard

    subscription = target.canvas.observeFrames(
      target.surface,
      proc(
          canvas: Canvas2D;
          frame: RenderSurfaceFrame
      ): RenderSurfaceFrameResult =
        if not listening:
          return rsfIdle
        try:
          case onFrame(canvas, frame)
          of ccfdContinue:
            return rsfRequestNext
          of ccfdComplete:
            detach()
            completion.succeed()
            return rsfIdle
        except CatchableError as error:
          detach()
          completion.fail("Canvas frame failed: " & error.msg)
          return rsfIdle,
      proc(canvas: Canvas2D) =
        discard canvas
        if listening:
          detach()
          completion.fail(disposedMessage)
    )

    if not target.requestFrame() and not target.valid:
      detach()
      completion.fail(disposedMessage)

    return proc() {.raises: [].} =
      let wasListening = listening
      detach()
      if wasListening and cancelCanvas != nil:
        cancelCanvas()
  )
