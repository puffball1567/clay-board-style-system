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

proc isPrintableTextKey*(event: Sdl3Event): bool =
  event.kind == sekKeyDown and
    not event.ctrl and not event.alt and not event.meta and
    event.key.len == 1 and event.key[0] >= ' ' and event.key[0] <= '~'

proc isStaleTextControlEvent*(event: Sdl3Event; focusChangedAt: uint64): bool =
  focusChangedAt > 0'u64 and event.timestamp > 0'u64 and
    event.timestamp <= focusChangedAt and event.isQueuedTextControlEvent
