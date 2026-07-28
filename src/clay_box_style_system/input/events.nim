import std/[math, options, tables]
import ../core/[geometry, node]
import ../hit/hit_test
import ../layout/scroll_state

type
  InputEventKind* = enum
    iekAbort,
    iekAnimationEnd,
    iekAnimationIteration,
    iekAnimationStart,
    iekAuxClick,
    iekBeforeInput,
    iekBlur,
    iekCancel,
    iekCanPlay,
    iekCanPlayThrough,
    iekChange,
    iekClose,
    iekPointerMove,
    iekPointerDown,
    iekPointerUp,
    iekPointerCancel,
    iekPointerEnter,
    iekPointerLeave,
    iekPointerOver,
    iekPointerOut,
    iekClick,
    iekContextMenu,
    iekCueChange,
    iekDoubleClick,
    iekCopy,
    iekCut,
    iekPaste,
    iekCompositionEnd,
    iekCompositionStart,
    iekCompositionUpdate,
    iekDrag,
    iekDragEnd,
    iekDragEnter,
    iekDragExit,
    iekDragLeave,
    iekDragOver,
    iekDragStart,
    iekDrop,
    iekDurationChange,
    iekEmptied,
    iekEncrypted,
    iekEnded,
    iekError,
    iekFocus,
    iekFullscreenChange,
    iekFullscreenError,
    iekGotPointerCapture,
    iekInput,
    iekInvalid,
    iekKeyDown,
    iekKeyUp,
    iekLoad,
    iekLoadEnd,
    iekLoadedData,
    iekLoadedMetadata,
    iekLoadStart,
    iekLostPointerCapture,
    iekMouseDown,
    iekMouseEnter,
    iekMouseLeave,
    iekMouseMove,
    iekMouseOut,
    iekMouseOver,
    iekMouseUp,
    iekPause,
    iekPlay,
    iekPlaying,
    iekProgress,
    iekRateChange,
    iekReset,
    iekResize,
    iekScroll,
    iekScrollEnd,
    iekSeeked,
    iekSeeking,
    iekSelect,
    iekShow,
    iekStalled,
    iekSubmit,
    iekSuspend,
    iekTextInput,
    iekTimeUpdate,
    iekToggle,
    iekTouchCancel,
    iekTouchEnd,
    iekTouchMove,
    iekTouchStart,
    iekTransitionEnd,
    iekVolumeChange,
    iekWaiting,
    iekWheel

  EventDispatchMode* = enum
    edmBackendInput,
    edmCoreSynthetic,
    edmComponentDispatch

  InputEvent* = object
    kind*: InputEventKind
    position*: Option[Vec2]
    button*: Option[int]
    key*: Option[string]
    text*: Option[string]
    delta*: Option[Vec2]
    focusOwner*: Option[NodeId]
    focusSerial*: int
    ctrlKey*: bool
    altKey*: bool
    shiftKey*: bool
    metaKey*: bool

  DispatchResult* = object
    target*: Option[NodeId]
    local*: Option[Vec2]
    event*: InputEvent

  InteractionState* = object
    pressedTarget*: Option[NodeId]
    pointerDownPosition*: Option[Vec2]
    focusedTarget*: Option[NodeId]
    focusSerial*: int
    hoveredTarget*: Option[NodeId]
    pointerCaptureTarget*: Option[NodeId]
    lastClickTarget*: Option[NodeId]
    dragTarget*: Option[NodeId]
    dragOverTarget*: Option[NodeId]
    scrollTarget*: Option[NodeId]
    scrollbarPointerTarget*: Option[NodeId]
    scrollbarDragKind*: HitRegionKind
    scrollbarDragTrack*: Rect
    scrollbarDragThumbLength*: float32
    scrollbarDragPointerOffset*: float32
    scrollbarDragging*: bool
    lastClickButton*: int
    clickCount*: int

  EventHandler* = proc(event: DispatchResult): bool {.closure.}

  EventBinding* = object
    node*: NodeId
    kind*: InputEventKind
    handler*: EventHandler
    internal*: bool

  EventRegistry* = object
    bindings*: seq[EventBinding]
    bindingIndex: Table[(int, InputEventKind), seq[int]]

const maxPasteEventBytes* = 8_192
const dragStartThreshold* = 4.0'f32

proc truncateUtf8EventText(text: string; maxBytes: int): string =
  if maxBytes <= 0:
    return ""
  if text.len <= maxBytes:
    return text
  var stop = maxBytes
  while stop > 0 and (ord(text[stop]) and 0b1100_0000) == 0b1000_0000:
    dec stop
  text[0 ..< stop]

proc dispatchMode*(kind: InputEventKind): EventDispatchMode =
  case kind
  of iekPointerMove, iekPointerDown, iekPointerUp,
     iekKeyDown, iekKeyUp, iekTextInput, iekWheel,
     iekResize,
     iekTouchCancel, iekTouchEnd, iekTouchMove, iekTouchStart:
    edmBackendInput
  of iekClick,
     iekAuxClick, iekContextMenu, iekDoubleClick,
     iekBlur, iekFocus,
     iekPointerCancel, iekPointerEnter, iekPointerLeave,
     iekPointerOver, iekPointerOut,
     iekGotPointerCapture, iekLostPointerCapture,
     iekMouseMove, iekMouseDown, iekMouseUp,
     iekMouseEnter, iekMouseLeave, iekMouseOver, iekMouseOut,
     iekScroll, iekScrollEnd,
     iekDrag, iekDragStart, iekDragEnd, iekDragEnter, iekDragOver,
     iekDragLeave, iekDragExit, iekDrop:
    edmCoreSynthetic
  of iekBeforeInput, iekInput, iekChange,
     iekSubmit, iekReset, iekSelect, iekInvalid, iekToggle,
     iekCopy, iekCut, iekPaste,
     iekCompositionStart, iekCompositionUpdate, iekCompositionEnd,
     iekLoad, iekLoadStart, iekLoadEnd, iekLoadedData, iekLoadedMetadata,
     iekCanPlay, iekCanPlayThrough, iekDurationChange, iekEmptied,
     iekEncrypted, iekEnded, iekError, iekPause, iekPlay, iekPlaying, iekProgress,
     iekRateChange, iekSeeked, iekSeeking, iekStalled, iekSuspend,
     iekTimeUpdate, iekVolumeChange, iekWaiting, iekAbort,
     iekAnimationStart, iekAnimationIteration, iekAnimationEnd,
     iekCancel, iekClose, iekCueChange,
     iekFullscreenChange, iekFullscreenError,
     iekShow,
     iekTransitionEnd:
    edmComponentDispatch

proc needsComponentDispatch*(kind: InputEventKind): bool =
  kind.dispatchMode == edmComponentDispatch

proc event*(kind: InputEventKind): InputEvent =
  InputEvent(kind: kind)

proc textEvent*(kind: InputEventKind; text: string): InputEvent =
  InputEvent(kind: kind, text: some(text))

proc positionedEvent*(kind: InputEventKind; position: Vec2; button = 0): InputEvent =
  InputEvent(kind: kind, position: some(position), button: some(button))

proc pointerMoveEvent*(position: Vec2): InputEvent =
  InputEvent(kind: iekPointerMove, position: some(position))

proc pointerDownEvent*(position: Vec2; button = 0): InputEvent =
  InputEvent(kind: iekPointerDown, position: some(position), button: some(button))

proc pointerUpEvent*(position: Vec2; button = 0): InputEvent =
  InputEvent(kind: iekPointerUp, position: some(position), button: some(button))

proc clickEvent*(position: Vec2; button = 0): InputEvent =
  InputEvent(kind: iekClick, position: some(position), button: some(button))

proc auxClickEvent*(position: Vec2; button = 0): InputEvent =
  positionedEvent(iekAuxClick, position, button)

proc contextMenuEvent*(position: Vec2; button = 0): InputEvent =
  positionedEvent(iekContextMenu, position, button)

proc doubleClickEvent*(position: Vec2; button = 0): InputEvent =
  positionedEvent(iekDoubleClick, position, button)

proc mouseDownEvent*(position: Vec2; button = 0): InputEvent =
  positionedEvent(iekMouseDown, position, button)

proc mouseMoveEvent*(position: Vec2): InputEvent =
  InputEvent(kind: iekMouseMove, position: some(position))

proc mouseUpEvent*(position: Vec2; button = 0): InputEvent =
  positionedEvent(iekMouseUp, position, button)

proc wheelEvent*(position: Vec2; delta = vec2(0, 0)): InputEvent =
  InputEvent(kind: iekWheel, position: some(position), delta: some(delta))

proc touchStartEvent*(position: Vec2): InputEvent =
  InputEvent(kind: iekTouchStart, position: some(position))

proc touchMoveEvent*(position: Vec2; delta = vec2(0, 0)): InputEvent =
  InputEvent(kind: iekTouchMove, position: some(position), delta: some(delta))

proc touchEndEvent*(position: Vec2): InputEvent =
  InputEvent(kind: iekTouchEnd, position: some(position))

proc touchCancelEvent*(position: Vec2): InputEvent =
  InputEvent(kind: iekTouchCancel, position: some(position))

proc pointerEventForTouch(event: InputEvent): InputEvent =
  case event.kind
  of iekTouchStart:
    InputEvent(kind: iekPointerDown, position: event.position, button: some(0), delta: event.delta)
  of iekTouchMove:
    InputEvent(kind: iekPointerMove, position: event.position, delta: event.delta)
  of iekTouchEnd:
    InputEvent(kind: iekPointerUp, position: event.position, button: some(0), delta: event.delta)
  of iekTouchCancel:
    InputEvent(kind: iekPointerCancel, position: event.position, delta: event.delta)
  else:
    event

proc keyEvent(
    kind: InputEventKind;
    key: string;
    ctrlKey = false;
    altKey = false;
    shiftKey = false;
    metaKey = false
): InputEvent =
  InputEvent(
    kind: kind,
    key: some(key),
    ctrlKey: ctrlKey,
    altKey: altKey,
    shiftKey: shiftKey,
    metaKey: metaKey
  )

proc keyDownEvent*(
    key: string;
    ctrlKey = false;
    altKey = false;
    shiftKey = false;
    metaKey = false
): InputEvent =
  keyEvent(iekKeyDown, key, ctrlKey, altKey, shiftKey, metaKey)

proc keyUpEvent*(
    key: string;
    ctrlKey = false;
    altKey = false;
    shiftKey = false;
    metaKey = false
): InputEvent =
  keyEvent(iekKeyUp, key, ctrlKey, altKey, shiftKey, metaKey)

proc beforeInputEvent*(text = ""): InputEvent =
  textEvent(iekBeforeInput, text)

proc textInputEvent*(text: string): InputEvent =
  InputEvent(kind: iekTextInput, text: some(text))

proc inputEvent*(text = ""): InputEvent =
  InputEvent(
    kind: iekInput,
    text:
      if text.len > 0: some(text)
      else: none(string)
  )

proc changeEvent*(text = ""): InputEvent =
  InputEvent(
    kind: iekChange,
    text:
      if text.len > 0: some(text)
      else: none(string)
  )

proc copyEvent*(): InputEvent =
  InputEvent(kind: iekCopy)

proc cutEvent*(): InputEvent =
  InputEvent(kind: iekCut)

proc pasteEvent*(text = ""): InputEvent =
  let bounded = text.truncateUtf8EventText(maxPasteEventBytes)
  InputEvent(
    kind: iekPaste,
    text:
      if bounded.len > 0: some(bounded)
      else: none(string)
  )

proc compositionStartEvent*(text = ""): InputEvent =
  textEvent(iekCompositionStart, text)

proc compositionUpdateEvent*(text = ""): InputEvent =
  textEvent(iekCompositionUpdate, text)

proc compositionEndEvent*(text = ""): InputEvent =
  textEvent(iekCompositionEnd, text)

proc focusEvent*(target: NodeId): DispatchResult =
  DispatchResult(target: some(target), local: none(Vec2), event: InputEvent(kind: iekFocus))

proc blurEvent*(target: NodeId): DispatchResult =
  DispatchResult(target: some(target), local: none(Vec2), event: InputEvent(kind: iekBlur))

proc gotPointerCaptureEvent*(target: NodeId): DispatchResult =
  DispatchResult(target: some(target), local: none(Vec2), event: InputEvent(kind: iekGotPointerCapture))

proc lostPointerCaptureEvent*(target: NodeId): DispatchResult =
  DispatchResult(target: some(target), local: none(Vec2), event: InputEvent(kind: iekLostPointerCapture))

proc initInteractionState*(): InteractionState =
  InteractionState(
    pressedTarget: none(NodeId),
    focusedTarget: none(NodeId),
    focusSerial: 0,
    hoveredTarget: none(NodeId),
    pointerCaptureTarget: none(NodeId),
    lastClickTarget: none(NodeId),
    dragTarget: none(NodeId),
    dragOverTarget: none(NodeId),
    scrollTarget: none(NodeId),
    scrollbarPointerTarget: none(NodeId),
    scrollbarDragKind: hrContent,
    scrollbarDragging: false,
    lastClickButton: 0,
    clickCount: 0
  )

proc setFocusedTarget*(state: var InteractionState; target: Option[NodeId]): bool =
  if state.focusedTarget == target:
    return false
  state.focusedTarget = target
  inc state.focusSerial
  true

proc markFocusOwned*(event: InputEvent; state: InteractionState): InputEvent =
  result = event
  result.focusOwner = state.focusedTarget
  result.focusSerial = state.focusSerial

proc markFocusOwned*(event: InputEvent; target: NodeId; serial: int): InputEvent =
  result = event
  result.focusOwner = some(target)
  result.focusSerial = serial

proc acceptsFocusOwnedEvent*(state: InteractionState; event: InputEvent): bool =
  if event.focusOwner.isNone:
    return true
  state.focusedTarget.isSome and
    state.focusedTarget.get == event.focusOwner.get and
    state.focusSerial == event.focusSerial

proc dispatchInput*(hit: Option[HitTestResult]; event: InputEvent): DispatchResult =
  result.event = event
  if hit.isSome:
    result.target = some(hit.get.node)
    result.local = some(hit.get.local)

proc dispatchInput*(regions: openArray[HitRegion]; event: InputEvent): DispatchResult =
  let hit =
    if event.position.isSome: hitTest(regions, event.position.get)
    else: none(HitTestResult)
  dispatchInput(hit, event)

proc initEventRegistry*(): EventRegistry =
  EventRegistry(
    bindings: @[],
    bindingIndex: initTable[(int, InputEventKind), seq[int]]()
  )

proc indexBinding(registry: var EventRegistry; bindingIndex: int) =
  let binding = registry.bindings[bindingIndex]
  let key = (binding.node.nodeIndex, binding.kind)
  registry.bindingIndex.mgetOrPut(key, @[]).add bindingIndex

proc addEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
) =
  registry.bindings.add EventBinding(node: node, kind: kind, handler: handler)
  registry.indexBinding(registry.bindings.high)

proc setEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
) =
  for index in countdown(registry.bindings.high, 0):
    if not registry.bindings[index].internal and
        registry.bindings[index].node == node and
        registry.bindings[index].kind == kind:
      registry.bindings[index].handler = handler
      return
  registry.addEventHandler(node, kind, handler)

proc addInternalEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
) =
  registry.bindings.add EventBinding(node: node, kind: kind, handler: handler, internal: true)
  registry.indexBinding(registry.bindings.high)

proc bindingsNeedingComponentDispatch*(registry: EventRegistry): seq[EventBinding] =
  for binding in registry.bindings:
    if binding.kind.needsComponentDispatch:
      result.add binding

template registerEventSlot(name: untyped; kindValue: InputEventKind) =
  proc name*(registry: var EventRegistry; node: NodeId; handler: EventHandler) =
    registry.addEventHandler(node, kindValue, handler)

registerEventSlot(onAbort, iekAbort)
registerEventSlot(onAnimationEnd, iekAnimationEnd)
registerEventSlot(onAnimationIteration, iekAnimationIteration)
registerEventSlot(onAnimationStart, iekAnimationStart)
registerEventSlot(onAuxClick, iekAuxClick)
registerEventSlot(onBeforeInput, iekBeforeInput)
registerEventSlot(onBlur, iekBlur)
registerEventSlot(onCancel, iekCancel)
registerEventSlot(onCanPlay, iekCanPlay)
registerEventSlot(onCanPlayThrough, iekCanPlayThrough)
registerEventSlot(onChange, iekChange)
registerEventSlot(onClick, iekClick)
registerEventSlot(onClose, iekClose)
registerEventSlot(onContextMenu, iekContextMenu)
registerEventSlot(onCopy, iekCopy)
registerEventSlot(onCueChange, iekCueChange)
registerEventSlot(onCut, iekCut)
registerEventSlot(onDblClick, iekDoubleClick)
registerEventSlot(onDoubleClick, iekDoubleClick)
registerEventSlot(onCompositionEnd, iekCompositionEnd)
registerEventSlot(onCompositionStart, iekCompositionStart)
registerEventSlot(onCompositionUpdate, iekCompositionUpdate)
registerEventSlot(onDrag, iekDrag)
registerEventSlot(onDragEnd, iekDragEnd)
registerEventSlot(onDragEnter, iekDragEnter)
registerEventSlot(onDragExit, iekDragExit)
registerEventSlot(onDragLeave, iekDragLeave)
registerEventSlot(onDragOver, iekDragOver)
registerEventSlot(onDragStart, iekDragStart)
registerEventSlot(onDrop, iekDrop)
registerEventSlot(onDurationChange, iekDurationChange)
registerEventSlot(onEmptied, iekEmptied)
registerEventSlot(onEncrypted, iekEncrypted)
registerEventSlot(onEnded, iekEnded)
registerEventSlot(onError, iekError)
registerEventSlot(onFocus, iekFocus)
registerEventSlot(onFullscreenChange, iekFullscreenChange)
registerEventSlot(onFullscreenError, iekFullscreenError)
registerEventSlot(onGotPointerCapture, iekGotPointerCapture)
registerEventSlot(onInput, iekInput)
registerEventSlot(onInvalid, iekInvalid)
registerEventSlot(onKeyDown, iekKeyDown)
registerEventSlot(onKeyUp, iekKeyUp)
registerEventSlot(onLoad, iekLoad)
registerEventSlot(onLoadEnd, iekLoadEnd)
registerEventSlot(onLoadedData, iekLoadedData)
registerEventSlot(onLoadedMetadata, iekLoadedMetadata)
registerEventSlot(onLoadStart, iekLoadStart)
registerEventSlot(onLostPointerCapture, iekLostPointerCapture)
registerEventSlot(onMouseDown, iekMouseDown)
registerEventSlot(onMouseEnter, iekMouseEnter)
registerEventSlot(onMouseLeave, iekMouseLeave)
registerEventSlot(onMouseMove, iekMouseMove)
registerEventSlot(onMouseOut, iekMouseOut)
registerEventSlot(onMouseOver, iekMouseOver)
registerEventSlot(onMouseUp, iekMouseUp)
registerEventSlot(onPause, iekPause)
registerEventSlot(onPaste, iekPaste)
registerEventSlot(onPlay, iekPlay)
registerEventSlot(onPlaying, iekPlaying)
registerEventSlot(onPointerCancel, iekPointerCancel)
registerEventSlot(onPointerDown, iekPointerDown)
registerEventSlot(onPointerEnter, iekPointerEnter)
registerEventSlot(onPointerLeave, iekPointerLeave)
registerEventSlot(onPointerMove, iekPointerMove)
registerEventSlot(onPointerOut, iekPointerOut)
registerEventSlot(onPointerOver, iekPointerOver)
registerEventSlot(onPointerUp, iekPointerUp)
registerEventSlot(onProgress, iekProgress)
registerEventSlot(onRateChange, iekRateChange)
registerEventSlot(onReset, iekReset)
registerEventSlot(onResize, iekResize)
registerEventSlot(onScroll, iekScroll)
registerEventSlot(onScrollEnd, iekScrollEnd)
registerEventSlot(onSeeked, iekSeeked)
registerEventSlot(onSeeking, iekSeeking)
registerEventSlot(onSelect, iekSelect)
registerEventSlot(onShow, iekShow)
registerEventSlot(onStalled, iekStalled)
registerEventSlot(onSubmit, iekSubmit)
registerEventSlot(onSuspend, iekSuspend)
registerEventSlot(onTextInput, iekTextInput)
registerEventSlot(onTimeUpdate, iekTimeUpdate)
registerEventSlot(onToggle, iekToggle)
registerEventSlot(onTouchCancel, iekTouchCancel)
registerEventSlot(onTouchEnd, iekTouchEnd)
registerEventSlot(onTouchMove, iekTouchMove)
registerEventSlot(onTouchStart, iekTouchStart)
registerEventSlot(onTransitionEnd, iekTransitionEnd)
registerEventSlot(onVolumeChange, iekVolumeChange)
registerEventSlot(onWaiting, iekWaiting)
registerEventSlot(onWheel, iekWheel)

proc expandedEventKinds(kind: InputEventKind): seq[InputEventKind] =
  case kind
  of iekPointerMove:
    @[iekMouseMove, iekPointerMove]
  of iekPointerDown:
    @[iekMouseDown, iekPointerDown]
  of iekPointerUp:
    @[iekMouseUp, iekPointerUp]
  of iekPointerEnter:
    @[iekMouseEnter, iekPointerEnter]
  of iekPointerLeave:
    @[iekMouseLeave, iekPointerLeave]
  of iekPointerOver:
    @[iekMouseOver, iekPointerOver]
  of iekPointerOut:
    @[iekMouseOut, iekPointerOut]
  of iekTextInput:
    @[iekBeforeInput, iekTextInput, iekInput, iekChange]
  of iekWheel:
    @[iekWheel]
  of iekTouchStart:
    @[iekPointerDown, iekTouchStart]
  of iekTouchMove:
    @[iekPointerMove, iekTouchMove]
  of iekTouchEnd:
    @[iekPointerUp, iekTouchEnd]
  of iekTouchCancel:
    @[iekPointerCancel, iekTouchCancel]
  else:
    @[kind]

proc appendTouchDispatches(
    result: var seq[DispatchResult];
    originalEvent: InputEvent;
    pointerDispatches: openArray[DispatchResult]
) =
  for dispatch in pointerDispatches:
    case originalEvent.kind
    of iekTouchStart:
      if dispatch.event.kind == iekPointerDown:
        var touchDispatch = dispatch
        touchDispatch.event = originalEvent
        result.add touchDispatch
      else:
        result.add dispatch
    of iekTouchMove:
      if dispatch.event.kind == iekPointerMove:
        var touchDispatch = dispatch
        touchDispatch.event = originalEvent
        result.add touchDispatch
      else:
        result.add dispatch
    of iekTouchEnd:
      if dispatch.event.kind == iekPointerUp:
        var touchDispatch = dispatch
        touchDispatch.event = originalEvent
        result.add touchDispatch
      else:
        result.add dispatch
    of iekTouchCancel:
      if dispatch.event.kind == iekPointerCancel:
        var touchDispatch = dispatch
        touchDispatch.event = originalEvent
        result.add touchDispatch
      else:
        result.add dispatch
    else:
      result.add dispatch

proc handle*(registry: EventRegistry; dispatch: DispatchResult): bool =
  if dispatch.target.isNone:
    return false
  if dispatch.event.focusOwner.isSome and dispatch.event.focusOwner.get != dispatch.target.get:
    return false
  for effectiveKind in dispatch.event.kind.expandedEventKinds:
    let key = (dispatch.target.get.nodeIndex, effectiveKind)
    if key notin registry.bindingIndex:
      continue
    let indices = registry.bindingIndex[key]
    for bindingIndex in indices:
      let binding = registry.bindings[bindingIndex]
      if binding.internal and binding.node == dispatch.target.get and binding.kind == effectiveKind:
        var effectiveDispatch = dispatch
        effectiveDispatch.event.kind = binding.kind
        if binding.handler(effectiveDispatch):
          return true
    for index in countdown(indices.high, 0):
      let binding = registry.bindings[indices[index]]
      if not binding.internal and binding.node == dispatch.target.get and binding.kind == effectiveKind:
        var effectiveDispatch = dispatch
        effectiveDispatch.event.kind = binding.kind
        if binding.handler(effectiveDispatch):
          return true
  false

proc dispatchToNode(dispatch: DispatchResult; node: NodeId; clearLocal: bool): DispatchResult =
  result = dispatch
  result.target = some(node)
  if clearLocal:
    result.local = none(Vec2)

proc handle*(registry: EventRegistry; tree: Tree; dispatch: DispatchResult): bool =
  if dispatch.target.isNone:
    return false

  let originalTarget = dispatch.target.get
  var current = some(originalTarget)
  while current.isSome:
    let node = current.get
    if registry.handle(dispatch.dispatchToNode(node, clearLocal = node != originalTarget)):
      return true
    current = tree.nodes[node.nodeIndex].parent
  false

proc handle*(registry: EventRegistry; dispatches: openArray[DispatchResult]): bool =
  for dispatch in dispatches:
    if registry.handle(dispatch):
      result = true

proc handle*(registry: EventRegistry; tree: Tree; dispatches: openArray[DispatchResult]): bool =
  for dispatch in dispatches:
    if registry.handle(tree, dispatch):
      result = true

proc emit*(
    registry: EventRegistry;
    target: NodeId;
    event: InputEvent;
    local = none(Vec2)
): bool =
  registry.handle(DispatchResult(target: some(target), local: local, event: event))

proc emit*(
    registry: EventRegistry;
    tree: Tree;
    target: NodeId;
    event: InputEvent;
    local = none(Vec2)
): bool =
  registry.handle(tree, DispatchResult(target: some(target), local: local, event: event))

proc emit*(
    registry: EventRegistry;
    target: NodeId;
    kind: InputEventKind;
    local = none(Vec2)
): bool =
  registry.emit(target, event(kind), local)

proc emit*(
    registry: EventRegistry;
    tree: Tree;
    target: NodeId;
    kind: InputEventKind;
    local = none(Vec2)
): bool =
  registry.emit(tree, target, event(kind), local)

proc emitFocused*(
    registry: EventRegistry;
    state: InteractionState;
    event: InputEvent
): bool =
  if state.focusedTarget.isNone:
    return false
  registry.emit(state.focusedTarget.get, event.markFocusOwned(state))

proc emitFocused*(
    registry: EventRegistry;
    state: InteractionState;
    kind: InputEventKind
): bool =
  registry.emitFocused(state, event(kind))

proc updateHoverState(tree: var Tree; target: Option[NodeId]) =
  tree.clearState(esHover)
  if target.isSome:
    tree.addState(target.get, esHover)

proc updateActiveState(tree: var Tree; target: Option[NodeId]) =
  tree.clearState(esActive)
  if target.isSome:
    tree.addState(target.get, esActive)

proc updateFocusState(tree: var Tree; target: Option[NodeId]) =
  tree.clearState(esFocus)
  tree.clearState(esFocusVisible)
  if target.isSome:
    tree.addState(target.get, esFocus)

proc capturePointer*(state: var InteractionState; target: NodeId): DispatchResult =
  state.pointerCaptureTarget = some(target)
  gotPointerCaptureEvent(target)

proc releasePointer*(state: var InteractionState): Option[DispatchResult] =
  if state.pointerCaptureTarget.isNone:
    return none(DispatchResult)
  let target = state.pointerCaptureTarget.get
  state.pointerCaptureTarget = none(NodeId)
  some(lostPointerCaptureEvent(target))

proc localForTarget(
    regions: openArray[HitRegion];
    target: Option[NodeId];
    position: Option[Vec2]
): Option[Vec2] =
  if target.isNone or position.isNone:
    return none(Vec2)
  for region in regions:
    if region.node == target.get:
      let point = position.get
      let origin =
        if region.localOrigin.isSome: region.localOrigin.get
        else: vec2(region.rect.x, region.rect.y)
      return some(vec2(point.x - origin.x, point.y - origin.y))
  none(Vec2)

proc disabledTarget(tree: Tree; target: Option[NodeId]): bool =
  var current = target
  while current.isSome:
    let id = current.get
    if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
      return false
    let node = tree.nodes[id.nodeIndex]
    if esDisabled in node.states:
      return true
    current = node.parent
  false

proc exceededDragThreshold(start, current: Option[Vec2]): bool =
  if start.isNone or current.isNone:
    return false
  let dx = abs(current.get.x - start.get.x)
  let dy = abs(current.get.y - start.get.y)
  dx + dy >= dragStartThreshold

proc finishScroll*(state: var InteractionState): seq[DispatchResult] =
  if state.scrollTarget.isSome:
    result.add DispatchResult(
      target: state.scrollTarget,
      local: none(Vec2),
      event: InputEvent(kind: iekScrollEnd)
    )
    state.scrollTarget = none(NodeId)

proc beginScroll*(state: var InteractionState; target: NodeId) =
  state.scrollTarget = some(target)

proc finishScroll*(
    state: var InteractionState;
    scroll: var ScrollState
): seq[DispatchResult] =
  let target = state.scrollTarget
  result = state.finishScroll()
  if target.isSome:
    discard scroll.setScrolling(target.get, false)

proc scrollDispatch(target: NodeId): DispatchResult =
  DispatchResult(
    target: some(target),
    local: none(Vec2),
    event: InputEvent(kind: iekScroll)
  )

proc updateScrollbarDrag(
    state: InteractionState;
    position: Vec2;
    scroll: var ScrollState
): bool =
  if state.scrollbarPointerTarget.isNone or not state.scrollbarDragging:
    return false
  let target = state.scrollbarPointerTarget.get
  let metrics = scroll.metricsFor(target)
  if metrics.isNone:
    return false

  let horizontal = state.scrollbarDragKind.isHorizontalScrollbar
  let trackStart =
    if horizontal: state.scrollbarDragTrack.x
    else: state.scrollbarDragTrack.y
  let trackLength =
    if horizontal: state.scrollbarDragTrack.w
    else: state.scrollbarDragTrack.h
  let pointer = if horizontal: position.x else: position.y
  let travel = max(0.0'f32, trackLength - state.scrollbarDragThumbLength)
  let progress =
    if travel > 0:
      clamp(
        (pointer - trackStart - state.scrollbarDragPointerOffset) / travel,
        0.0'f32,
        1.0'f32
      )
    else:
      0.0'f32
  let maximum = metrics.get.maxOffset()
  let current = metrics.get.offset
  let next =
    if horizontal: vec2(maximum.x * progress, current.y)
    else: vec2(current.x, maximum.y * progress)
  scroll.setScrollOffset(target, next)

proc processScrollbarPointer(
    state: var InteractionState;
    hit: Option[HitTestResult];
    event: InputEvent;
    scroll: var ScrollState;
    output: var seq[DispatchResult]
): bool =
  case event.kind
  of iekPointerMove:
    if state.scrollbarPointerTarget.isNone:
      return false
    if event.position.isSome and state.updateScrollbarDrag(event.position.get, scroll):
      let target = state.scrollbarPointerTarget.get
      state.scrollTarget = some(target)
      output.add scrollDispatch(target)
    return true
  of iekPointerUp, iekPointerCancel:
    if state.scrollbarPointerTarget.isNone:
      return false
    state.scrollbarPointerTarget = none(NodeId)
    state.scrollbarDragging = false
    state.scrollbarDragKind = hrContent
    return true
  of iekPointerDown:
    let button = if event.button.isSome: event.button.get else: 0
    if button notin [0, 1] or hit.isNone or not hit.get.kind.isScrollbar:
      return false
    let target = hit.get.node
    if hit.get.scrollbarTrack.isNone or hit.get.scrollbarThumb.isNone or
        event.position.isNone:
      return false

    state.scrollbarPointerTarget = some(target)
    state.scrollTarget = some(target)
    state.scrollbarDragKind = hit.get.kind
    state.scrollbarDragTrack = hit.get.scrollbarTrack.get
    let thumb = hit.get.scrollbarThumb.get
    let point = event.position.get
    let horizontal = hit.get.kind.isHorizontalScrollbar
    if hit.get.kind.isScrollbarThumb:
      state.scrollbarDragging = true
      state.scrollbarDragThumbLength = if horizontal: thumb.w else: thumb.h
      state.scrollbarDragPointerOffset =
        if horizontal: point.x - thumb.x
        else: point.y - thumb.y
    else:
      state.scrollbarDragging = false
      let metrics = scroll.metricsFor(target)
      if metrics.isSome:
        let beforeThumb =
          if horizontal: point.x < thumb.x
          else: point.y < thumb.y
        let amount =
          if horizontal: metrics.get.viewport.w
          else: metrics.get.viewport.h
        let delta = if beforeThumb: -amount else: amount
        let changed =
          if horizontal: scroll.scrollBy(target, vec2(delta, 0))
          else: scroll.scrollBy(target, vec2(0, delta))
        if changed:
          output.add scrollDispatch(target)
    return true
  else:
    false

proc restrictToFocusScope(state: var InteractionState; tree: var Tree) =
  if tree.focusScopeRoot.isNone:
    return

  template clearOutsideScope(field: untyped) =
    if field.isSome and not tree.isWithinFocusScope(field.get):
      field = none(NodeId)

  let hadOutsideHover = state.hoveredTarget.isSome and
    not tree.isWithinFocusScope(state.hoveredTarget.get)
  let hadOutsidePress = state.pressedTarget.isSome and
    not tree.isWithinFocusScope(state.pressedTarget.get)
  clearOutsideScope(state.hoveredTarget)
  clearOutsideScope(state.pressedTarget)
  clearOutsideScope(state.pointerCaptureTarget)
  clearOutsideScope(state.lastClickTarget)
  clearOutsideScope(state.dragTarget)
  clearOutsideScope(state.dragOverTarget)
  clearOutsideScope(state.scrollTarget)
  clearOutsideScope(state.scrollbarPointerTarget)
  if state.scrollbarPointerTarget.isNone:
    state.scrollbarDragging = false
  if state.focusedTarget.isSome and
      not tree.isWithinFocusScope(state.focusedTarget.get):
    discard state.setFocusedTarget(none(NodeId))
    tree.updateFocusState(none(NodeId))
  if hadOutsideHover:
    tree.updateHoverState(none(NodeId))
  if hadOutsidePress:
    state.pointerDownPosition = none(Vec2)
    tree.updateActiveState(none(NodeId))

proc processInputImpl(
    state: var InteractionState;
    tree: var Tree;
    regions: openArray[HitRegion];
    event: InputEvent;
    scroll: ptr ScrollState
): seq[DispatchResult] =
  case event.kind
  of iekTouchStart, iekTouchMove, iekTouchEnd, iekTouchCancel:
    let pointerDispatches = processInputImpl(
      state, tree, regions, event.pointerEventForTouch(), scroll
    )
    result.appendTouchDispatches(event, pointerDispatches)
    return
  else:
    discard

  state.restrictToFocusScope(tree)

  var hit =
    if event.position.isSome: hitTest(regions, event.position.get)
    else: none(HitTestResult)
  if hit.isSome and tree.focusScopeRoot.isSome and
      not tree.isWithinFocusScope(hit.get.node):
    hit = none(HitTestResult)
  if scroll != nil and
      state.processScrollbarPointer(hit, event, scroll[], result):
    return

  var dispatch = dispatchInput(hit, event)
  case event.kind
  of iekPointerMove, iekPointerDown, iekPointerUp, iekPointerCancel:
    if state.pointerCaptureTarget.isSome:
      dispatch.target = state.pointerCaptureTarget
      dispatch.local = none(Vec2)
  else:
    discard
  let blockedByFocusScope = tree.focusScopeRoot.isSome and
    (dispatch.target.isNone or not tree.isWithinFocusScope(dispatch.target.get))
  if blockedByFocusScope:
    dispatch.target = none(NodeId)
    dispatch.local = none(Vec2)
  case event.kind
  of iekPointerMove:
    if dispatch.target != state.hoveredTarget:
      if state.hoveredTarget.isSome:
        result.add DispatchResult(
          target: state.hoveredTarget,
          local: none(Vec2),
          event: InputEvent(kind: iekPointerOut)
        )
        result.add DispatchResult(
          target: state.hoveredTarget,
          local: none(Vec2),
          event: InputEvent(kind: iekPointerLeave)
        )
      if dispatch.target.isSome:
        result.add DispatchResult(
          target: dispatch.target,
          local: dispatch.local,
          event: InputEvent(kind: iekPointerOver)
        )
        result.add DispatchResult(
          target: dispatch.target,
          local: dispatch.local,
          event: InputEvent(kind: iekPointerEnter)
        )
      state.hoveredTarget = dispatch.target
    tree.updateHoverState(dispatch.target)
    if state.pressedTarget.isSome:
      if state.dragTarget.isNone and state.pointerDownPosition.exceededDragThreshold(event.position):
        state.dragTarget = state.pressedTarget
        result.add DispatchResult(
          target: state.dragTarget,
          local: localForTarget(regions, state.dragTarget, event.position),
          event: InputEvent(kind: iekDragStart, position: event.position)
        )
      if state.dragTarget.isSome:
        result.add DispatchResult(
          target: state.dragTarget,
          local: localForTarget(regions, state.dragTarget, event.position),
          event: InputEvent(kind: iekDrag, position: event.position)
        )
      if dispatch.target != state.dragOverTarget:
        if state.dragOverTarget.isSome:
          result.add DispatchResult(
            target: state.dragOverTarget,
            local: none(Vec2),
            event: InputEvent(kind: iekDragLeave, position: event.position)
          )
          result.add DispatchResult(
            target: state.dragOverTarget,
            local: none(Vec2),
            event: InputEvent(kind: iekDragExit, position: event.position)
          )
        if dispatch.target.isSome:
          result.add DispatchResult(
            target: dispatch.target,
            local: dispatch.local,
            event: InputEvent(kind: iekDragEnter, position: event.position)
          )
        state.dragOverTarget = dispatch.target
      if state.dragOverTarget.isSome:
        result.add DispatchResult(
          target: state.dragOverTarget,
          local: dispatch.local,
          event: InputEvent(kind: iekDragOver, position: event.position)
        )
    result.add dispatch
  of iekPointerDown:
    let targetDisabled = tree.disabledTarget(dispatch.target)
    let focusTarget =
      if blockedByFocusScope: state.focusedTarget
      elif targetDisabled: none(NodeId)
      else: tree.focusTargetForHit(dispatch.target)
    state.pressedTarget =
      if targetDisabled: none(NodeId)
      else: dispatch.target
    state.pointerDownPosition =
      if targetDisabled: none(Vec2)
      else: event.position
    state.dragTarget = none(NodeId)
    state.dragOverTarget = none(NodeId)
    tree.updateActiveState(if targetDisabled: none(NodeId) else: dispatch.target)
    if focusTarget != state.focusedTarget:
      if state.focusedTarget.isSome:
        result.add blurEvent(state.focusedTarget.get)
      if focusTarget.isSome:
        result.add focusEvent(focusTarget.get)
      discard state.setFocusedTarget(focusTarget)
      tree.updateFocusState(state.focusedTarget)
    result.add dispatch
  of iekPointerUp:
    result.add dispatch
    let pressed = state.pressedTarget
    let dragTarget = state.dragTarget
    let dragOverTarget = state.dragOverTarget
    state.pressedTarget = none(NodeId)
    state.pointerDownPosition = none(Vec2)
    state.dragTarget = none(NodeId)
    state.dragOverTarget = none(NodeId)
    tree.updateActiveState(none(NodeId))
    if dragTarget.isSome:
      if dragOverTarget.isSome:
        result.add DispatchResult(
          target: dragOverTarget,
          local: dispatch.local,
          event: InputEvent(kind: iekDrop, position: event.position)
        )
      result.add DispatchResult(
        target: dragTarget,
        local: localForTarget(regions, dragTarget, event.position),
        event: InputEvent(kind: iekDragEnd, position: event.position)
      )
    if dragTarget.isNone and pressed.isSome and dispatch.target == pressed and event.position.isSome:
      let button = if event.button.isSome: event.button.get else: 0
      result.add DispatchResult(
        target: pressed,
        local: dispatch.local,
        event: clickEvent(event.position.get, button)
      )
      if button != 0 and button != 1:
        result.add DispatchResult(
          target: pressed,
          local: dispatch.local,
          event: auxClickEvent(event.position.get, button)
        )
      if button == 3:
        result.add DispatchResult(
          target: pressed,
          local: dispatch.local,
          event: contextMenuEvent(event.position.get, button)
        )
      if state.lastClickTarget == pressed and state.lastClickButton == button:
        inc state.clickCount
      else:
        state.clickCount = 1
      state.lastClickTarget = pressed
      state.lastClickButton = button
      if state.clickCount == 2:
        result.add DispatchResult(
          target: pressed,
          local: dispatch.local,
          event: doubleClickEvent(event.position.get, button)
        )
        state.clickCount = 0
  of iekPointerCancel:
    let dragTarget = state.dragTarget
    state.pressedTarget = none(NodeId)
    state.pointerDownPosition = none(Vec2)
    state.dragTarget = none(NodeId)
    state.dragOverTarget = none(NodeId)
    tree.updateActiveState(none(NodeId))
    result.add dispatch
    if dragTarget.isSome:
      result.add DispatchResult(
        target: dragTarget,
        local: localForTarget(regions, dragTarget, event.position),
        event: InputEvent(kind: iekDragEnd, position: event.position)
      )
    let released = state.releasePointer()
    if released.isSome:
      result.add released.get
  of iekWheel:
    result.add dispatch
    if scroll != nil and event.delta.isSome:
      let scrolled = scroll[].scrollNearest(tree, dispatch.target, event.delta.get)
      if scrolled.isSome:
        state.scrollTarget = scrolled
        result.add scrollDispatch(scrolled.get)
  else:
    result.add dispatch

proc processInput*(
    state: var InteractionState;
    tree: var Tree;
    regions: openArray[HitRegion];
    event: InputEvent
): seq[DispatchResult] =
  processInputImpl(state, tree, regions, event, nil)

proc processInput*(
    state: var InteractionState;
    tree: var Tree;
    regions: openArray[HitRegion];
    event: InputEvent;
    scroll: var ScrollState
): seq[DispatchResult] =
  processInputImpl(state, tree, regions, event, addr scroll)
