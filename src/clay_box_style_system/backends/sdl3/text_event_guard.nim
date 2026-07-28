import ./renderer

proc isQueuedTextControlEvent*(event: Sdl3Event): bool =
  event.kind in {
    sekKeyDown,
    sekKeyUp,
    sekTextInput,
    sekCompositionStart,
    sekCompositionUpdate,
    sekCompositionEnd,
    sekCompositionCandidates
  }

proc isStaleTextControlEvent*(event: Sdl3Event; focusChangedAt: uint64): bool =
  focusChangedAt > 0'u64 and event.timestamp > 0'u64 and
    event.timestamp <= focusChangedAt and event.isQueuedTextControlEvent
