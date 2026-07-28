import std/unittest

import clay_box_style_system/backends/sdl3/renderer
import clay_box_style_system/backends/sdl3/text_event_guard

suite "sdl3 text event guard":
  test "IME UI modes map to SDL implemented UI hints":
    check siuNative.imeImplementedUiHint() == "none"
    check siuComposition.imeImplementedUiHint() == "composition"
    check siuCompositionAndCandidates.imeImplementedUiHint() == "composition,candidates"

  test "text control events are recognized for focus-change queue pruning":
    check Sdl3Event(kind: sekKeyDown, timestamp: 1, key: "a", repeat: false).isQueuedTextControlEvent
    check Sdl3Event(kind: sekKeyUp, timestamp: 1, key: "a", repeat: false).isQueuedTextControlEvent
    check Sdl3Event(kind: sekTextInput, timestamp: 1, text: "a").isQueuedTextControlEvent
    check Sdl3Event(kind: sekCompositionStart, timestamp: 1, text: "あ").isQueuedTextControlEvent
    check Sdl3Event(kind: sekCompositionUpdate, timestamp: 1, text: "あ").isQueuedTextControlEvent
    check Sdl3Event(kind: sekCompositionEnd, timestamp: 1, text: "あ").isQueuedTextControlEvent

    check not Sdl3Event(kind: sekPointerDown, timestamp: 1, button: 1, buttonX: 4, buttonY: 8).isQueuedTextControlEvent
    check not Sdl3Event(kind: sekWheel, timestamp: 1, wheelX: 0, wheelY: -1, wheelMouseX: 4, wheelMouseY: 8).isQueuedTextControlEvent

  test "old text control events are stale after focus changes":
    let focusChangedAt = 20'u64

    check Sdl3Event(kind: sekTextInput, timestamp: 19, text: "a").isStaleTextControlEvent(focusChangedAt)
    check Sdl3Event(kind: sekTextInput, timestamp: 20, text: "a").isStaleTextControlEvent(focusChangedAt)
    check not Sdl3Event(kind: sekTextInput, timestamp: 21, text: "a").isStaleTextControlEvent(focusChangedAt)
    check not Sdl3Event(kind: sekTextInput, timestamp: 0, text: "a").isStaleTextControlEvent(focusChangedAt)
    check not Sdl3Event(kind: sekTextInput, timestamp: 19, text: "a").isStaleTextControlEvent(0)
    check not Sdl3Event(kind: sekPointerDown, timestamp: 19, button: 1, buttonX: 4, buttonY: 8).isStaleTextControlEvent(focusChangedAt)

  test "printable key detection does not assume a US keyboard layout":
    check Sdl3Event(kind: sekKeyDown, key: ";", shift: true).isPrintableTextKey
    check Sdl3Event(kind: sekKeyDown, key: "+", shift: true).isPrintableTextKey
    check not Sdl3Event(kind: sekKeyDown, key: "Backspace").isPrintableTextKey
    check not Sdl3Event(kind: sekKeyDown, key: "v", ctrl: true).isPrintableTextKey
