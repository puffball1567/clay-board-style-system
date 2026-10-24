import std/[math, options, sets, tables]
import ../core/[computed_style, dirty_domain, geometry, node]
import ../data/form_data
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
    iekWheel,
    iekPenProximityIn,
    iekPenProximityOut,
    iekPenButtonDown,
    iekPenButtonUp,
    # Append-only: event ABI codes are enum ordinals.
    iekAnimationCancel,
    iekTransitionRun,
    iekTransitionStart,
    iekTransitionCancel

  PointerDeviceKind* = enum
    pdkMouse,
    pdkTouch,
    pdkPenUnknown,
    pdkPenDirect,
    pdkPenIndirect

  PointerAxis* = enum
    paPressure,
    paTangentialPressure,
    paTiltX,
    paTiltY,
    paRotation,
    paDistance,
    paSlider

  PointerData* = object
    ## Device IDs are stable only for the current process. `axes` separates an
    ## unsupported value from a supported axis whose current value is zero.
    device*: PointerDeviceKind
    deviceId*: uint64
    axes*: set[PointerAxis]
    pressure*: float32
    tangentialPressure*: float32
    tiltX*, tiltY*: float32
    rotation*: float32
    distance*: float32
    slider*: float32
    buttons*: uint32
    contact*: bool
    primary*: bool
    eraser*: bool
    inProximity*: bool

  EventDispatchMode* = enum
    edmBackendInput,
    edmCoreSynthetic,
    edmComponentDispatch

  EventPayloadField* = enum
    epfPosition,
    epfDelta,
    epfButton,
    epfKey,
    epfText,
    epfPointer,
    epfFocusOwnership,
    epfFormData,
    epfMotion,
    epfDragData,
    epfDragOperations,
    epfDropOperation,
    epfDropDataEntry,
    epfDragInputMethod

  DragOperation* = enum
    dgoCopy,
    dgoMove,
    dgoLink

  DragFeedback* = enum
    dgfNone,
    dgfNoDrop,
    dgfCopy,
    dgfMove,
    dgfLink

  DragInputMethod* = enum
    dimPointer,
    dimKeyboard

  EventDefinition* = object
    producer*: EventDispatchMode
    payload*: set[EventPayloadField]
    bubbles*: bool
    cancelable*: bool
    aliases*: array[2, InputEventKind]
    aliasCount*: uint8
    publicNames*: array[2, string]
    publicNameCount*: uint8
    abiCode*: uint32

  EventPhase* = enum
    epNone,
    epTarget,
    epBubble,
    epDefaultAction

  EventOutcome* = object
    ## Event effects are independent. Handling an event does not implicitly
    ## prevent its default action, and preventing a default does not stop it
    ## from reaching an ancestor.
    handled*: bool
    stopPropagation*: bool
    preventDefault*: bool

  EventPointerCaptureAction* = enum
    epcaNone,
    epcaCapture,
    epcaRelease

  EventInvalidationRequest* = object
    target*: Option[NodeId]
    domains*: set[DirtyDomain]

  EventActionSnapshot* = object
    focusPending*: bool
    focusTarget*: Option[NodeId]
    pointerAction*: EventPointerCaptureAction
    pointerTarget*: Option[NodeId]
    invalidations*: seq[EventInvalidationRequest]
    frameRequested*: bool

  EventActionQueue* = ref object
    generation: uint64
    active: bool
    focusPending: bool
    focusTarget: Option[NodeId]
    pointerAction: EventPointerCaptureAction
    pointerTarget: Option[NodeId]
    invalidations: seq[EventInvalidationRequest]
    frameRequested: bool

  InputEventPayload = ref object
    ## Uncommon managed payloads stay behind one pointer so pointer, keyboard,
    ## and animation events remain compact on the dispatch hot path.
    formData: FormData
    dragData: FormData
    hasDragData: bool
    dragOperations: Option[set[DragOperation]]
    dropOperation: Option[DragOperation]
    dropDataEntry: Option[FormDataEntry]
    dragInputMethod: DragInputMethod
    motionName: string
    motionElapsedSeconds: float64
    motionIteration: uint64

  InputEvent* = object
    kind*: InputEventKind
    timestamp*: uint64
    position*: Option[Vec2]
    button*: Option[int]
    key*: Option[string]
    text*: Option[string]
    delta*: Option[Vec2]
    pointer*: Option[PointerData]
    focusOwner*: Option[NodeId]
    focusSerial*: int
    ctrlKey*: bool
    altKey*: bool
    shiftKey*: bool
    metaKey*: bool
    payload: InputEventPayload

  DispatchResult* = object
    ## `target` is the original hit/focus target for the complete dispatch.
    ## `currentTarget` changes while the event traverses its ancestor chain.
    target*: Option[NodeId]
    currentTarget*: Option[NodeId]
    local*: Option[Vec2]
    phase*: EventPhase
    event*: InputEvent
    actions: EventActionQueue
    actionGeneration: uint64

  InteractionState* = object
    pressedTarget*: Option[NodeId]
    pointerDownPosition*: Option[Vec2]
    pressedButton*: Option[int]
    dragThreshold: float32
    dragAutoScrollMargin: float32
    dragAutoScrollStep: float32
    dragAutoScrollTarget*: Option[NodeId]
    keyboardDragActive: bool
    dragPayload: InputEventPayload
    acceptedDropOperation: Option[DragOperation]
    acceptedDropDataEntry: Option[FormDataEntry]
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

  EventHandler* = proc(event: DispatchResult): EventOutcome {.closure.}

  EventSubscription* = object
    id*: uint64
    node*: NodeId
    kind*: InputEventKind

  EventBindingRole = enum
    ebrPublicHandler,
    ebrObserver,
    ebrDefaultAction

  EventBinding* = object
    id*: uint64
    node*: NodeId
    kind*: InputEventKind
    handler*: EventHandler
    role: EventBindingRole
    active: bool

  EventRegistry* = object
    bindings*: seq[EventBinding]
    bindingIndex: Table[(NodeId, InputEventKind), seq[int]]
    nextBindingId: uint64
    dispatchDepth: int
    inactiveBindingCount: int

const maxPasteEventBytes* = 8_192
const dragStartThreshold* = 4.0'f32
const dragAutoScrollMargin* = 24.0'f32
const dragAutoScrollStep* = 12.0'f32

proc ignoredEvent*(): EventOutcome =
  EventOutcome()

proc handledEvent*(
    stopPropagation = false;
    preventDefault = false
): EventOutcome =
  EventOutcome(
    handled: true,
    stopPropagation: stopPropagation,
    preventDefault: preventDefault
  )

proc stoppedEvent*(preventDefault = false): EventOutcome =
  EventOutcome(
    handled: true,
    stopPropagation: true,
    preventDefault: preventDefault
  )

proc preventedEvent*(handled = true): EventOutcome =
  EventOutcome(handled: handled, preventDefault: true)

when not defined(cbssStrictEventOutcomes):
  converter boolToEventOutcome*(value: bool): EventOutcome =
    ## Source-compatible migration path for pre-0.4 handlers. New code should
    ## return an explicit EventOutcome whenever propagation or defaults matter.
    if value:
      stoppedEvent()
    else:
      ignoredEvent()

proc mergeOutcome*(result: var EventOutcome; value: EventOutcome) =
  result.handled = result.handled or value.handled
  result.stopPropagation = result.stopPropagation or value.stopPropagation
  result.preventDefault = result.preventDefault or value.preventDefault

proc beginEventActions*(reuse: EventActionQueue = nil): tuple[
    actions: EventActionQueue,
    generation: uint64
] =
  result.actions = reuse
  if result.actions.isNil:
    result.actions = EventActionQueue()
  inc result.actions.generation
  if result.actions.generation == 0:
    result.actions.generation = 1
  result.actions.active = true
  result.actions.focusPending = false
  result.actions.focusTarget = none(NodeId)
  result.actions.pointerAction = epcaNone
  result.actions.pointerTarget = none(NodeId)
  result.actions.invalidations.setLen(0)
  result.actions.frameRequested = false
  result.generation = result.actions.generation

proc withEventActions*(
    dispatch: DispatchResult;
    actions: EventActionQueue;
    generation: uint64
): DispatchResult =
  result = dispatch
  result.actions = actions
  result.actionGeneration = generation

proc finishEventActions*(
    actions: EventActionQueue;
    generation: uint64
): EventActionSnapshot =
  if actions.isNil or not actions.active or actions.generation != generation:
    return
  result = EventActionSnapshot(
    focusPending: actions.focusPending,
    focusTarget: actions.focusTarget,
    pointerAction: actions.pointerAction,
    pointerTarget: actions.pointerTarget,
    invalidations: move(actions.invalidations),
    frameRequested: actions.frameRequested
  )
  actions.active = false

proc hasActiveEventActions(dispatch: DispatchResult): bool {.inline.} =
  not dispatch.actions.isNil and dispatch.actions.active and
    dispatch.actions.generation == dispatch.actionGeneration

proc requestFocus*(
    dispatch: DispatchResult;
    target: Option[NodeId]
): bool {.discardable.} =
  if not dispatch.hasActiveEventActions:
    return false
  dispatch.actions.focusPending = true
  dispatch.actions.focusTarget = target
  true

proc requestFocus*(dispatch: DispatchResult): bool {.discardable.} =
  if dispatch.currentTarget.isNone:
    return false
  dispatch.requestFocus(dispatch.currentTarget)

proc capturePointer*(
    dispatch: DispatchResult;
    target: NodeId
): bool {.discardable.} =
  if not dispatch.hasActiveEventActions:
    return false
  dispatch.actions.pointerAction = epcaCapture
  dispatch.actions.pointerTarget = some(target)
  true

proc capturePointer*(dispatch: DispatchResult): bool {.discardable.} =
  if dispatch.currentTarget.isNone:
    return false
  dispatch.capturePointer(dispatch.currentTarget.get)

proc releasePointer*(dispatch: DispatchResult): bool {.discardable.} =
  if not dispatch.hasActiveEventActions:
    return false
  dispatch.actions.pointerAction = epcaRelease
  dispatch.actions.pointerTarget = none(NodeId)
  true

proc addInvalidation(
    actions: EventActionQueue;
    target: Option[NodeId];
    domains: set[DirtyDomain]
) =
  if domains == {}:
    return
  for request in actions.invalidations.mitems:
    if request.target == target:
      request.domains = request.domains + domains
      return
  actions.invalidations.add EventInvalidationRequest(
    target: target,
    domains: domains
  )

proc invalidate*(
    dispatch: DispatchResult;
    target: NodeId;
    domains: set[DirtyDomain]
): bool {.discardable.} =
  if not dispatch.hasActiveEventActions or domains == {}:
    return false
  dispatch.actions.addInvalidation(some(target), domains)
  true

proc invalidate*(
    dispatch: DispatchResult;
    domains: set[DirtyDomain]
): bool {.discardable.} =
  if dispatch.currentTarget.isNone:
    return false
  dispatch.invalidate(dispatch.currentTarget.get, domains)

proc invalidateRoot*(
    dispatch: DispatchResult;
    domains: set[DirtyDomain]
): bool {.discardable.} =
  if not dispatch.hasActiveEventActions or domains == {}:
    return false
  dispatch.actions.addInvalidation(none(NodeId), domains)
  true

proc requestFrame*(dispatch: DispatchResult): bool {.discardable.} =
  if not dispatch.hasActiveEventActions:
    return false
  dispatch.actions.frameRequested = true
  true

func buildEventDefinitions(): array[InputEventKind, EventDefinition] =
  for kind in InputEventKind:
    let enumName = $kind
    result[kind] = EventDefinition(
      producer: edmComponentDispatch,
      bubbles: true,
      cancelable: true,
      publicNames: ["on" & enumName[3 .. ^1], ""],
      publicNameCount: 1,
      abiCode: uint32(ord(kind))
    )

  result[iekDoubleClick].publicNames = ["onDoubleClick", "onDblClick"]
  result[iekDoubleClick].publicNameCount = 2

  for kind in {
    iekPointerMove, iekPointerDown, iekPointerUp,
    iekKeyDown, iekKeyUp, iekTextInput, iekWheel,
    iekResize,
    iekPenProximityIn, iekPenProximityOut,
    iekPenButtonDown, iekPenButtonUp,
    iekTouchCancel, iekTouchEnd, iekTouchMove, iekTouchStart
  }:
    result[kind].producer = edmBackendInput

  for kind in {
    iekClick, iekAuxClick, iekContextMenu, iekDoubleClick,
    iekBlur, iekFocus,
    iekPointerCancel, iekPointerEnter, iekPointerLeave,
    iekPointerOver, iekPointerOut,
    iekGotPointerCapture, iekLostPointerCapture,
    iekMouseMove, iekMouseDown, iekMouseUp,
    iekMouseEnter, iekMouseLeave, iekMouseOver, iekMouseOut,
    iekScroll, iekScrollEnd,
    iekDrag, iekDragStart, iekDragEnd, iekDragEnter, iekDragOver,
    iekDragLeave, iekDragExit, iekDrop
  }:
    result[kind].producer = edmCoreSynthetic

  for kind in {
    iekBlur, iekFocus, iekLoad,
    iekMouseEnter, iekMouseLeave,
    iekPointerEnter, iekPointerLeave,
    iekScroll
  }:
    result[kind].bubbles = false

  for kind in {
    iekAnimationEnd, iekAnimationIteration, iekAnimationStart,
    iekBlur, iekFocus, iekGotPointerCapture, iekLostPointerCapture,
    iekLoad, iekLoadEnd, iekLoadedData, iekLoadedMetadata, iekLoadStart,
    iekProgress, iekResize, iekScroll, iekScrollEnd,
    iekTransitionEnd
  }:
    result[kind].cancelable = false

  for kind in {
    iekAnimationCancel, iekTransitionRun, iekTransitionStart,
    iekTransitionCancel
  }:
    result[kind].producer = edmCoreSynthetic
    result[kind].cancelable = false
    result[kind].payload = {epfMotion}
  for kind in {
    iekAnimationEnd, iekAnimationIteration, iekAnimationStart,
    iekTransitionEnd
  }:
    result[kind].producer = edmCoreSynthetic
    result[kind].payload = {epfMotion}

  for kind in {
    iekAuxClick, iekClick, iekContextMenu, iekDoubleClick,
    iekDrag, iekDragEnd, iekDragEnter, iekDragExit, iekDragLeave,
    iekDragOver, iekDragStart, iekDrop,
    iekMouseDown, iekMouseEnter, iekMouseLeave, iekMouseMove,
    iekMouseOut, iekMouseOver, iekMouseUp,
    iekPointerCancel, iekPointerDown, iekPointerEnter, iekPointerLeave,
    iekPointerMove, iekPointerOut, iekPointerOver, iekPointerUp,
    iekPenButtonDown, iekPenButtonUp, iekPenProximityIn, iekPenProximityOut,
    iekTouchCancel, iekTouchEnd, iekTouchMove, iekTouchStart
  }:
    result[kind].payload = {epfPosition, epfButton, epfPointer}
  result[iekWheel].payload = {epfPosition, epfDelta, epfPointer}
  for kind in {iekKeyDown, iekKeyUp}:
    result[kind].payload = {epfKey, epfFocusOwnership}
  for kind in {
    iekBeforeInput, iekChange, iekCompositionEnd, iekCompositionStart,
    iekCompositionUpdate, iekCopy, iekCut, iekInput, iekPaste, iekTextInput
  }:
    result[kind].payload = {epfText, epfFocusOwnership}
  result[iekSubmit].payload = {epfFormData}
  for kind in {
    iekDrag, iekDragEnd, iekDragEnter, iekDragExit, iekDragLeave,
    iekDragOver, iekDragStart, iekDrop
  }:
    result[kind].payload.incl epfDragData
    result[kind].payload.incl epfDragOperations
    result[kind].payload.incl epfDragInputMethod
  for kind in {iekDrop, iekDragEnd}:
    result[kind].payload.incl epfDropOperation
    result[kind].payload.incl epfDropDataEntry

  template aliases(kind: InputEventKind; first, second: InputEventKind) =
    result[kind].aliases = [first, second]
    result[kind].aliasCount = 2

  aliases(iekPointerMove, iekMouseMove, iekPointerMove)
  aliases(iekPointerDown, iekMouseDown, iekPointerDown)
  aliases(iekPointerUp, iekMouseUp, iekPointerUp)
  aliases(iekPointerEnter, iekMouseEnter, iekPointerEnter)
  aliases(iekPointerLeave, iekMouseLeave, iekPointerLeave)
  aliases(iekPointerOver, iekMouseOver, iekPointerOver)
  aliases(iekPointerOut, iekMouseOut, iekPointerOut)
  aliases(iekTextInput, iekBeforeInput, iekTextInput)
  aliases(iekTouchStart, iekPointerDown, iekTouchStart)
  aliases(iekTouchMove, iekPointerMove, iekTouchMove)
  aliases(iekTouchEnd, iekPointerUp, iekTouchEnd)
  aliases(iekTouchCancel, iekPointerCancel, iekTouchCancel)

const eventDefinitions* = buildEventDefinitions()

func eventDefinition*(kind: InputEventKind): EventDefinition {.inline.} =
  eventDefinitions[kind]

func primaryEventName*(kind: InputEventKind): string {.inline.} =
  kind.eventDefinition.publicNames[0]

iterator publicEventNames*(kind: InputEventKind): string =
  let definition = kind.eventDefinition
  for index in 0 ..< int(definition.publicNameCount):
    yield definition.publicNames[index]

proc bubbles*(kind: InputEventKind): bool {.inline.} =
  kind.eventDefinition.bubbles

proc cancelable*(kind: InputEventKind): bool {.inline.} =
  kind.eventDefinition.cancelable

proc truncateUtf8EventText(text: string; maxBytes: int): string =
  if maxBytes <= 0:
    return ""
  if text.len <= maxBytes:
    return text
  var stop = maxBytes
  while stop > 0 and (ord(text[stop]) and 0b1100_0000) == 0b1000_0000:
    dec stop
  text[0 ..< stop]

proc dispatchMode*(kind: InputEventKind): EventDispatchMode {.inline.} =
  kind.eventDefinition.producer

proc needsComponentDispatch*(kind: InputEventKind): bool =
  kind.dispatchMode == edmComponentDispatch

proc event*(kind: InputEventKind): InputEvent =
  InputEvent(kind: kind)

proc submitEvent*(data: FormData): InputEvent =
  ## Constructs a submit event carrying an immutable form snapshot. A payload
  ## object is allocated only for events that actually transport FormData.
  InputEvent(
    kind: iekSubmit,
    payload: InputEventPayload(formData: data)
  )

proc formData*(event: InputEvent): Option[FormData] =
  ## Returns `some` even for an intentionally empty submitted form. Synthetic
  ## submit events built only from `iekSubmit` retain their legacy no-payload
  ## behavior and return `none`.
  if event.kind != iekSubmit or event.payload.isNil:
    none(FormData)
  else:
    some(event.payload.formData)

proc formData*(dispatch: DispatchResult): Option[FormData] {.inline.} =
  ## Convenience access for `onSubmit` and additive submit listeners.
  dispatch.event.formData()

proc dragData*(event: InputEvent): Option[FormData] =
  ## Text and Blob entries supplied by the pressed drag source. An empty
  ## FormData is still a present payload; ordinary drags return `none`.
  if event.kind notin {
      iekDrag, iekDragEnd, iekDragEnter, iekDragExit, iekDragLeave,
      iekDragOver, iekDragStart, iekDrop
  } or event.payload.isNil or not event.payload.hasDragData:
    return none(FormData)
  some(event.payload.dragData)

proc dragData*(dispatch: DispatchResult): Option[FormData] {.inline.} =
  dispatch.event.dragData()

proc dragOperations*(event: InputEvent): Option[set[DragOperation]] =
  ## `none` means the legacy unconditional drop lifecycle. `some({})`
  ## explicitly offers no acceptable operation.
  if event.kind notin {
      iekDrag, iekDragEnd, iekDragEnter, iekDragExit, iekDragLeave,
      iekDragOver, iekDragStart, iekDrop
  } or event.payload.isNil:
    return none(set[DragOperation])
  event.payload.dragOperations

proc dragOperations*(dispatch: DispatchResult): Option[set[DragOperation]] {.inline.} =
  dispatch.event.dragOperations()

proc dragInputMethod*(event: InputEvent): Option[DragInputMethod] =
  if event.kind notin {
      iekDrag, iekDragEnd, iekDragEnter, iekDragExit, iekDragLeave,
      iekDragOver, iekDragStart, iekDrop
  }:
    return none(DragInputMethod)
  some(if event.payload.isNil: dimPointer else: event.payload.dragInputMethod)

proc dragInputMethod*(dispatch: DispatchResult): Option[DragInputMethod] {.inline.} =
  dispatch.event.dragInputMethod()

proc dropOperation*(event: InputEvent): Option[DragOperation] =
  ## The negotiated operation of a completed drop. A canceled or rejected
  ## drag end, and a legacy drop without negotiation, return `none`.
  if event.kind notin {iekDrop, iekDragEnd} or event.payload.isNil:
    return none(DragOperation)
  event.payload.dropOperation

proc dropOperation*(dispatch: DispatchResult): Option[DragOperation] {.inline.} =
  dispatch.event.dropOperation()

proc dropDataEntry*(event: InputEvent): Option[FormDataEntry] =
  ## The entry selected by a data-aware drop target, if one completed the drop.
  if event.kind notin {iekDrop, iekDragEnd} or event.payload.isNil:
    return none(FormDataEntry)
  event.payload.dropDataEntry

proc dropDataEntry*(dispatch: DispatchResult): Option[FormDataEntry] {.inline.} =
  dispatch.event.dropDataEntry()

proc motionEvent*(
    kind: InputEventKind;
    name: string;
    elapsedSeconds: float64;
    iteration = 0'u64
): InputEvent =
  if kind notin {
      iekAnimationStart, iekAnimationIteration, iekAnimationEnd,
      iekAnimationCancel, iekTransitionRun, iekTransitionStart,
      iekTransitionEnd, iekTransitionCancel
  }:
    raise newException(ValueError, "motionEvent requires a motion event kind")
  InputEvent(
    kind: kind,
    payload: InputEventPayload(
      motionName: name,
      motionElapsedSeconds: elapsedSeconds,
      motionIteration: iteration
    )
  )

proc motionName*(event: InputEvent): string =
  if event.payload.isNil: "" else: event.payload.motionName

proc motionElapsedSeconds*(event: InputEvent): float64 =
  if event.payload.isNil: 0 else: event.payload.motionElapsedSeconds

proc motionIteration*(event: InputEvent): uint64 =
  if event.payload.isNil: 0 else: event.payload.motionIteration

proc motionName*(dispatch: DispatchResult): string {.inline.} =
  dispatch.event.motionName

proc motionElapsedSeconds*(dispatch: DispatchResult): float64 {.inline.} =
  dispatch.event.motionElapsedSeconds

proc motionIteration*(dispatch: DispatchResult): uint64 {.inline.} =
  dispatch.event.motionIteration

proc textEvent*(kind: InputEventKind; text: string): InputEvent =
  InputEvent(kind: kind, text: some(text))

proc positionedEvent*(kind: InputEventKind; position: Vec2; button = 0): InputEvent =
  InputEvent(kind: kind, position: some(position), button: some(button))

proc pointerMoveEvent*(
    position: Vec2;
    pointer = none(PointerData);
    timestamp = 0'u64
): InputEvent =
  InputEvent(
    kind: iekPointerMove,
    timestamp: timestamp,
    position: some(position),
    pointer: pointer
  )

proc pointerDownEvent*(
    position: Vec2;
    button = 0;
    pointer = none(PointerData);
    timestamp = 0'u64
): InputEvent =
  InputEvent(
    kind: iekPointerDown,
    timestamp: timestamp,
    position: some(position),
    button: some(button),
    pointer: pointer
  )

proc pointerUpEvent*(
    position: Vec2;
    button = 0;
    pointer = none(PointerData);
    timestamp = 0'u64
): InputEvent =
  InputEvent(
    kind: iekPointerUp,
    timestamp: timestamp,
    position: some(position),
    button: some(button),
    pointer: pointer
  )

proc penProximityEvent*(inside: bool; pointer: PointerData): InputEvent =
  InputEvent(
    kind: if inside: iekPenProximityIn else: iekPenProximityOut,
    pointer: some(pointer)
  )

proc penButtonEvent*(
    down: bool;
    position: Vec2;
    button: int;
    pointer: PointerData
): InputEvent =
  InputEvent(
    kind: if down: iekPenButtonDown else: iekPenButtonUp,
    position: some(position),
    button: some(button),
    pointer: some(pointer)
  )

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

proc touchPointerData*(
    deviceId: uint64;
    pressure: float32;
    contact: bool
): PointerData =
  let boundedPressure =
    if pressure.classify in {fcNan, fcInf, fcNegInf}: 0.0'f32
    else: clamp(pressure, 0.0'f32, 1.0'f32)
  PointerData(
    device: pdkTouch,
    deviceId: deviceId,
    axes: {paPressure},
    pressure: boundedPressure,
    contact: contact,
    primary: true,
    inProximity: contact
  )

proc touchStartEvent*(
    position: Vec2;
    pressure = 1.0'f32;
    deviceId = 0'u64
): InputEvent =
  InputEvent(
    kind: iekTouchStart,
    position: some(position),
    pointer: some(touchPointerData(deviceId, pressure, true))
  )

proc touchMoveEvent*(
    position: Vec2;
    delta = vec2(0, 0);
    pressure = 1.0'f32;
    deviceId = 0'u64
): InputEvent =
  InputEvent(
    kind: iekTouchMove,
    position: some(position),
    delta: some(delta),
    pointer: some(touchPointerData(deviceId, pressure, true))
  )

proc touchEndEvent*(position: Vec2; deviceId = 0'u64): InputEvent =
  InputEvent(
    kind: iekTouchEnd,
    position: some(position),
    pointer: some(touchPointerData(deviceId, 0, false))
  )

proc touchCancelEvent*(position: Vec2; deviceId = 0'u64): InputEvent =
  InputEvent(
    kind: iekTouchCancel,
    position: some(position),
    pointer: some(touchPointerData(deviceId, 0, false))
  )

proc pointerEventForTouch(event: InputEvent): InputEvent =
  result = event
  case event.kind
  of iekTouchStart:
    result.kind = iekPointerDown
    result.button = some(0)
  of iekTouchMove:
    result.kind = iekPointerMove
  of iekTouchEnd:
    result.kind = iekPointerUp
    result.button = some(0)
  of iekTouchCancel:
    result.kind = iekPointerCancel
  else:
    discard

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
    pressedButton: none(int),
    dragThreshold: dragStartThreshold,
    dragAutoScrollMargin: dragAutoScrollMargin,
    dragAutoScrollStep: dragAutoScrollStep,
    dragAutoScrollTarget: none(NodeId),
    keyboardDragActive: false,
    dragPayload: nil,
    acceptedDropOperation: none(DragOperation),
    acceptedDropDataEntry: none(FormDataEntry),
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

proc dragStartDistance*(state: InteractionState): float32 {.inline.} =
  ## The minimum Manhattan pointer movement before a drag starts.
  state.dragThreshold

proc setDragStartDistance*(state: var InteractionState; distance: float32) =
  ## Configure the gesture threshold in layout pixels. Existing active drags
  ## continue, while a pending press uses the new distance on its next move.
  if not (distance > 0 and distance < Inf.float32):
    raise newException(ValueError, "drag start distance must be finite and positive")
  state.dragThreshold = distance

proc setDragAutoScroll*(
    state: var InteractionState; margin, step: float32
) =
  ## Set the edge band and scroll distance per drag pointer sample in layout
  ## pixels. Zero for either value disables automatic scrolling.
  if not (margin >= 0 and margin < Inf.float32 and
      step >= 0 and step < Inf.float32):
    raise newException(ValueError, "drag auto-scroll values must be finite and nonnegative")
  state.dragAutoScrollMargin = margin
  state.dragAutoScrollStep = step

proc setDragData*(
    state: var InteractionState; source: NodeId; data: FormData
): bool {.discardable.} =
  ## Arm an immutable text/Blob payload after pointer down and before the
  ## gesture crosses the drag threshold. Only the pressed source may arm it.
  if state.pressedTarget != some(source) or state.dragTarget.isSome:
    return false
  let operations =
    if state.dragPayload.isNil: none(set[DragOperation])
    else: state.dragPayload.dragOperations
  state.dragPayload = InputEventPayload(
    dragData: data,
    hasDragData: true,
    dragOperations: operations
  )
  true

proc clearDragData*(state: var InteractionState) =
  ## Revoke data for subsequent events. Already synthesized events retain it.
  if state.dragPayload.isNil:
    return
  let operations = state.dragPayload.dragOperations
  state.dragPayload =
    if operations.isSome: InputEventPayload(
      dragOperations: operations,
      dragInputMethod: state.dragPayload.dragInputMethod
    )
    else: nil
  state.acceptedDropOperation = none(DragOperation)
  state.acceptedDropDataEntry = none(FormDataEntry)

proc dragData*(state: InteractionState): Option[FormData] =
  if state.dragPayload.isNil or not state.dragPayload.hasDragData:
    none(FormData)
  else:
    some(state.dragPayload.dragData)

proc setDragOperations*(
    state: var InteractionState;
    source: NodeId;
    operations: set[DragOperation]
): bool {.discardable.} =
  ## Opt into negotiated drops. Call after pointer down and before drag start.
  ## An empty offer deliberately prevents any negotiated drop.
  if state.pressedTarget != some(source) or state.dragTarget.isSome:
    return false
  let data = state.dragData()
  state.dragPayload = InputEventPayload(
    dragData: if data.isSome: data.get else: FormData(),
    hasDragData: data.isSome,
    dragOperations: some(operations)
  )
  true

proc clearDragOperations*(
    state: var InteractionState; source: NodeId
): bool {.discardable.} =
  ## Return a pending drag to the legacy drop lifecycle.
  if state.pressedTarget != some(source) or state.dragTarget.isSome:
    return false
  let data = state.dragData()
  state.dragPayload =
    if data.isSome: InputEventPayload(
      dragData: data.get, hasDragData: true
    )
    else: nil
  true

proc dragOperations*(state: InteractionState): Option[set[DragOperation]] =
  if state.dragPayload.isNil:
    none(set[DragOperation])
  else:
    state.dragPayload.dragOperations

proc acceptDropOperation*(
    state: var InteractionState;
    target: NodeId;
    operation: DragOperation
): bool {.discardable.} =
  ## Called by the current drop target after handling `onDragOver`.
  let offered = state.dragOperations()
  if state.dragTarget.isNone or state.dragOverTarget != some(target) or
      offered.isNone or operation notin offered.get:
    return false
  state.acceptedDropOperation = some(operation)
  state.acceptedDropDataEntry = none(FormDataEntry)
  true

proc acceptDropDataEntry*(
    state: var InteractionState;
    target: NodeId;
    operation: DragOperation;
    name: string;
    kind: FormDataValueKind
): bool {.discardable.} =
  ## Accept an offered operation only when the transfer contains a matching
  ## field. The first matching entry is retained as the selected drop value.
  let offered = state.dragOperations()
  let data = state.dragData()
  if state.dragTarget.isNone or state.dragOverTarget != some(target) or
      offered.isNone or operation notin offered.get or data.isNone:
    return false
  for entry in data.get.items:
    if entry.name == name and entry.kind == kind:
      state.acceptedDropOperation = some(operation)
      state.acceptedDropDataEntry = some(entry)
      return true
  false

proc declineDropOperation*(
    state: var InteractionState; target: NodeId
): bool {.discardable.} =
  if state.dragTarget.isNone or state.dragOverTarget != some(target) or
      state.dragOperations().isNone:
    return false
  state.acceptedDropOperation = none(DragOperation)
  state.acceptedDropDataEntry = none(FormDataEntry)
  true

proc dropOperation*(state: InteractionState): Option[DragOperation] {.inline.} =
  state.acceptedDropOperation

proc dragFeedback*(state: InteractionState): DragFeedback =
  ## Read after dispatching drag-over handlers. Legacy drags have no
  ## negotiated operation and leave cursor policy to the host.
  if state.dragTarget.isNone or state.dragOperations().isNone:
    return dgfNone
  if state.dragOverTarget.isNone or state.acceptedDropOperation.isNone:
    return dgfNoDrop
  case state.acceptedDropOperation.get
  of dgoCopy: dgfCopy
  of dgoMove: dgfMove
  of dgoLink: dgfLink

proc dropDataEntry*(state: InteractionState): Option[FormDataEntry] {.inline.} =
  state.acceptedDropDataEntry

proc keyboardDragging*(state: InteractionState): bool {.inline.} =
  state.keyboardDragActive

proc clearDragTransfer*(state: var InteractionState) =
  ## Release data, offered operations, and the current target's acceptance.
  state.dragPayload = nil
  state.acceptedDropOperation = none(DragOperation)
  state.acceptedDropDataEntry = none(FormDataEntry)

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
    bindingIndex: initTable[(NodeId, InputEventKind), seq[int]](),
    nextBindingId: 1,
    dispatchDepth: 0,
    inactiveBindingCount: 0
  )

proc newSubscription(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind
): EventSubscription =
  result = EventSubscription(id: registry.nextBindingId, node: node, kind: kind)
  inc registry.nextBindingId
  if registry.nextBindingId == 0:
    registry.nextBindingId = 1

proc indexBinding(registry: var EventRegistry; bindingIndex: int) =
  let binding = registry.bindings[bindingIndex]
  if not binding.active:
    return
  let key = (binding.node, binding.kind)
  registry.bindingIndex.mgetOrPut(key, @[]).add bindingIndex

proc rebuildBindingIndex(registry: var EventRegistry) =
  registry.bindingIndex.clear()
  for index in 0 ..< registry.bindings.len:
    registry.indexBinding(index)

proc removeEventHandlers*(
    registry: var EventRegistry;
    nodes: HashSet[NodeId]
): int =
  if registry.dispatchDepth > 0:
    for binding in registry.bindings.mitems:
      if binding.active and binding.node in nodes:
        binding.active = false
        binding.handler = nil
        inc result
        inc registry.inactiveBindingCount
    if result > 0:
      registry.rebuildBindingIndex()
    return
  var retained = newSeqOfCap[EventBinding](registry.bindings.len)
  for binding in registry.bindings:
    if binding.active and binding.node in nodes:
      inc result
    elif binding.active:
      retained.add binding
  if result > 0:
    registry.bindings = retained
    registry.rebuildBindingIndex()

proc removeEventHandler*(
    registry: var EventRegistry;
    subscription: EventSubscription
): bool {.discardable.} =
  if subscription.id == 0:
    return false
  for index in 0 ..< registry.bindings.len:
    let binding = registry.bindings[index]
    if binding.active and binding.id == subscription.id and
        binding.node == subscription.node and
        binding.kind == subscription.kind:
      if registry.dispatchDepth > 0:
        registry.bindings[index].active = false
        registry.bindings[index].handler = nil
        inc registry.inactiveBindingCount
      else:
        registry.bindings.delete(index)
      registry.rebuildBindingIndex()
      return true

proc compactBindings(registry: var EventRegistry) =
  if registry.inactiveBindingCount == 0:
    return
  var retained = newSeqOfCap[EventBinding](
    registry.bindings.len - registry.inactiveBindingCount
  )
  for binding in registry.bindings:
    if binding.active:
      retained.add binding
  registry.bindings = retained
  registry.inactiveBindingCount = 0
  registry.rebuildBindingIndex()

proc addBinding(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler;
    role: EventBindingRole
): EventSubscription =
  result = registry.newSubscription(node, kind)
  registry.bindings.add EventBinding(
    id: result.id,
    node: node,
    kind: kind,
    handler: handler,
    role: role,
    active: true
  )
  registry.indexBinding(registry.bindings.high)

proc addEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
) =
  discard registry.addBinding(node, kind, handler, ebrObserver)

proc subscribe*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
): EventSubscription =
  registry.addBinding(node, kind, handler, ebrObserver)

proc setEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
) =
  for index in countdown(registry.bindings.high, 0):
    if registry.bindings[index].active and
        registry.bindings[index].role == ebrPublicHandler and
        registry.bindings[index].node == node and
        registry.bindings[index].kind == kind:
      registry.bindings[index].handler = handler
      return
  discard registry.addBinding(node, kind, handler, ebrPublicHandler)

proc clearEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind
): bool {.discardable.} =
  for index in countdown(registry.bindings.high, 0):
    let binding = registry.bindings[index]
    if binding.active and binding.role == ebrPublicHandler and
        binding.node == node and binding.kind == kind:
      if registry.dispatchDepth > 0:
        registry.bindings[index].active = false
        registry.bindings[index].handler = nil
        inc registry.inactiveBindingCount
      else:
        registry.bindings.delete(index)
      registry.rebuildBindingIndex()
      return true

proc addInternalEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
) =
  discard registry.addBinding(node, kind, handler, ebrDefaultAction)

proc setInternalEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind;
    handler: EventHandler
) =
  for index in countdown(registry.bindings.high, 0):
    if registry.bindings[index].active and
        registry.bindings[index].role == ebrDefaultAction and
        registry.bindings[index].node == node and
        registry.bindings[index].kind == kind:
      registry.bindings[index].handler = handler
      return
  discard registry.addBinding(node, kind, handler, ebrDefaultAction)

proc clearInternalEventHandler*(
    registry: var EventRegistry;
    node: NodeId;
    kind: InputEventKind
): bool {.discardable.} =
  for index in countdown(registry.bindings.high, 0):
    let binding = registry.bindings[index]
    if binding.active and binding.role == ebrDefaultAction and
        binding.node == node and binding.kind == kind:
      if registry.dispatchDepth > 0:
        registry.bindings[index].active = false
        registry.bindings[index].handler = nil
        inc registry.inactiveBindingCount
      else:
        registry.bindings.delete(index)
      registry.rebuildBindingIndex()
      return true

proc bindingsNeedingComponentDispatch*(registry: EventRegistry): seq[EventBinding] =
  for binding in registry.bindings:
    if binding.active and binding.kind.needsComponentDispatch:
      result.add binding

template registerEventSlot(name: untyped; kindValue: InputEventKind) =
  proc name*(
      registry: var EventRegistry;
      node: NodeId;
      handler: EventHandler
  ) =
    registry.addEventHandler(node, kindValue, handler)

include "../generated/event_registry_slots.nim"

iterator expandedEventKinds(kind: InputEventKind): InputEventKind =
  let definition = kind.eventDefinition
  if definition.aliasCount == 0:
    yield kind
  else:
    for index in 0 ..< int(definition.aliasCount):
      yield definition.aliases[index]

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

proc invokeBindings(
    registry: EventRegistry;
    dispatch: DispatchResult;
    role: EventBindingRole
): EventOutcome =
  if dispatch.target.isNone:
    return ignoredEvent()
  let currentTarget =
    if dispatch.currentTarget.isSome: dispatch.currentTarget.get
    else: dispatch.target.get
  if dispatch.event.focusOwner.isSome and
      dispatch.event.focusOwner.get != dispatch.target.get:
    return ignoredEvent()
  for effectiveKind in dispatch.event.kind.expandedEventKinds:
    let key = (currentTarget, effectiveKind)
    if key notin registry.bindingIndex:
      continue
    let indices = registry.bindingIndex[key]
    for bindingIndex in indices:
      let binding = registry.bindings[bindingIndex]
      if binding.active and binding.role == role and
          binding.node == currentTarget and binding.kind == effectiveKind:
        var effectiveDispatch = dispatch
        effectiveDispatch.event.kind = binding.kind
        result.mergeOutcome(binding.handler(effectiveDispatch))

proc dispatchToNode(
    dispatch: DispatchResult;
    node: NodeId;
    phase: EventPhase;
    clearLocal: bool
): DispatchResult =
  result = dispatch
  result.currentTarget = some(node)
  result.phase = phase
  if clearLocal:
    result.local = none(Vec2)

proc dispatchEvent*(
    registry: var EventRegistry;
    dispatch: DispatchResult
): EventOutcome =
  if dispatch.target.isNone:
    return ignoredEvent()
  inc registry.dispatchDepth
  defer:
    dec registry.dispatchDepth
    if registry.dispatchDepth == 0:
      registry.compactBindings()
  let target = dispatch.target.get
  let targeted = dispatch.dispatchToNode(target, epTarget, clearLocal = false)
  result.mergeOutcome(registry.invokeBindings(targeted, ebrPublicHandler))
  result.mergeOutcome(registry.invokeBindings(targeted, ebrObserver))
  if not (result.preventDefault and dispatch.event.kind.cancelable):
    result.mergeOutcome(registry.invokeBindings(
      targeted.dispatchToNode(target, epDefaultAction, clearLocal = false),
      ebrDefaultAction
    ))

proc disabledBlocksDispatch(kind: InputEventKind): bool =
  kind in {
    iekAuxClick, iekBeforeInput, iekChange, iekClick, iekContextMenu,
    iekDoubleClick, iekDrag, iekDragEnd, iekDragStart, iekDrop,
    iekInput, iekKeyDown, iekKeyUp,
    iekMouseDown, iekMouseUp,
    iekPointerDown, iekPointerUp,
    iekSubmit, iekTextInput, iekToggle,
    iekTouchEnd, iekTouchStart
  }

proc hasDisabledAncestor(tree: Tree; target: NodeId): bool =
  var current = some(target)
  while current.isSome:
    let node = current.get
    if not tree.isValid(node):
      return false
    if esDisabled in tree.nodes[node.nodeIndex].states:
      return true
    current = tree.nodes[node.nodeIndex].parent

proc dispatchEvent*(
    registry: var EventRegistry;
    tree: Tree;
    dispatch: DispatchResult
): EventOutcome =
  if dispatch.target.isNone:
    return ignoredEvent()

  let originalTarget = dispatch.target.get
  if tree.isInert(originalTarget):
    return ignoredEvent()
  if dispatch.event.kind.disabledBlocksDispatch and
      tree.hasDisabledAncestor(originalTarget):
    return ignoredEvent()

  inc registry.dispatchDepth
  defer:
    dec registry.dispatchDepth
    if registry.dispatchDepth == 0:
      registry.compactBindings()

  # User handlers and observers see the event before intrinsic control actions.
  var current = some(originalTarget)
  var propagationBoundary = originalTarget
  while current.isSome:
    let node = current.get
    propagationBoundary = node
    let phase = if node == originalTarget: epTarget else: epBubble
    let currentDispatch = dispatch.dispatchToNode(
      node,
      phase,
      clearLocal = node != originalTarget
    )
    result.mergeOutcome(registry.invokeBindings(
      currentDispatch,
      ebrPublicHandler
    ))
    result.mergeOutcome(registry.invokeBindings(currentDispatch, ebrObserver))
    if result.stopPropagation or not dispatch.event.kind.bubbles:
      break
    current = tree.nodes[node.nodeIndex].parent

  if result.preventDefault and dispatch.event.kind.cancelable:
    return

  # Default actions use a separate pass so preventDefault never needs to race
  # an internal handler. No ancestor route is allocated on the hot path.
  current = some(originalTarget)
  while current.isSome:
    let node = current.get
    let outcome = registry.invokeBindings(
      dispatch.dispatchToNode(
        node,
        epDefaultAction,
        clearLocal = node != originalTarget
      ),
      ebrDefaultAction
    )
    result.mergeOutcome(outcome)
    if outcome.stopPropagation or not dispatch.event.kind.bubbles or
        node == propagationBoundary:
      break
    current = tree.nodes[node.nodeIndex].parent

proc handle*(registry: var EventRegistry; dispatch: DispatchResult): bool =
  registry.dispatchEvent(dispatch).handled

proc handle*(registry: var EventRegistry; tree: Tree; dispatch: DispatchResult): bool =
  registry.dispatchEvent(tree, dispatch).handled

proc handle*(registry: var EventRegistry; dispatches: openArray[DispatchResult]): bool =
  for dispatch in dispatches:
    if registry.handle(dispatch):
      result = true

proc handle*(registry: var EventRegistry; tree: Tree; dispatches: openArray[DispatchResult]): bool =
  for dispatch in dispatches:
    if registry.handle(tree, dispatch):
      result = true

proc emit*(
    registry: var EventRegistry;
    target: NodeId;
    event: InputEvent;
    local = none(Vec2)
): bool =
  registry.handle(DispatchResult(target: some(target), local: local, event: event))

proc emit*(
    registry: var EventRegistry;
    tree: Tree;
    target: NodeId;
    event: InputEvent;
    local = none(Vec2)
): bool =
  registry.handle(tree, DispatchResult(target: some(target), local: local, event: event))

proc emit*(
    registry: var EventRegistry;
    target: NodeId;
    kind: InputEventKind;
    local = none(Vec2)
): bool =
  registry.emit(target, event(kind), local)

proc emit*(
    registry: var EventRegistry;
    tree: Tree;
    target: NodeId;
    kind: InputEventKind;
    local = none(Vec2)
): bool =
  registry.emit(tree, target, event(kind), local)

proc emitFocused*(
    registry: var EventRegistry;
    state: InteractionState;
    event: InputEvent
): bool =
  if state.focusedTarget.isNone:
    return false
  registry.emit(state.focusedTarget.get, event.markFocusOwned(state))

proc emitFocused*(
    registry: var EventRegistry;
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

proc dragEvent(
    kind: InputEventKind;
    position: Option[Vec2];
    payload: InputEventPayload;
    operation = none(DragOperation);
    entry = none(FormDataEntry)
): InputEvent =
  var eventPayload = payload
  if operation.isSome:
    eventPayload = InputEventPayload(
      dragData: if payload.isNil: FormData() else: payload.dragData,
      hasDragData: not payload.isNil and payload.hasDragData,
      dragOperations:
        if payload.isNil: none(set[DragOperation])
        else: payload.dragOperations,
      dropOperation: operation,
      dropDataEntry: entry,
      dragInputMethod:
        if payload.isNil: dimPointer else: payload.dragInputMethod
    )
  InputEvent(kind: kind, position: position, payload: eventPayload)

proc updateDragOver(
    state: var InteractionState;
    target: Option[NodeId];
    targetLocal: Option[Vec2];
    position: Option[Vec2];
    events: var seq[DispatchResult]
) =
  # A target must renew its acceptance for each drag-over sample. A release
  # without a new sample keeps the latest accepted operation.
  state.acceptedDropOperation = none(DragOperation)
  state.acceptedDropDataEntry = none(FormDataEntry)
  if target != state.dragOverTarget:
    if state.dragOverTarget.isSome:
      for kind in [iekDragLeave, iekDragExit]:
        events.add DispatchResult(
          target: state.dragOverTarget,
          local: none(Vec2),
          event: dragEvent(kind, position, state.dragPayload)
        )
    if target.isSome:
      events.add DispatchResult(
        target: target,
        local: targetLocal,
        event: dragEvent(iekDragEnter, position, state.dragPayload)
      )
    state.dragOverTarget = target
  if target.isSome:
    events.add DispatchResult(
      target: target,
      local: targetLocal,
      event: dragEvent(iekDragOver, position, state.dragPayload)
    )

proc disabledTarget(tree: Tree; target: Option[NodeId]): bool =
  var current = target
  while current.isSome:
    let id = current.get
    if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
      return false
    if esDisabled in tree.nodes[id.nodeIndex].states:
      return true
    current = tree.nodes[id.nodeIndex].parent
  false

proc cancelKeyboardDrag*(state: var InteractionState): seq[DispatchResult] =
  ## Cancel an active keyboard drag and retain its immutable payload on the
  ## returned events, even after the interaction releases it.
  if not state.keyboardDragActive:
    return
  let source = state.dragTarget
  let payload = state.dragPayload
  state.updateDragOver(none(NodeId), none(Vec2), none(Vec2), result)
  state.keyboardDragActive = false
  state.dragTarget = none(NodeId)
  state.dragOverTarget = none(NodeId)
  state.clearDragTransfer()
  if source.isSome:
    result.add DispatchResult(
      target: source,
      local: none(Vec2),
      event: dragEvent(iekDragEnd, none(Vec2), payload)
    )

proc startKeyboardDrag*(
    state: var InteractionState;
    tree: Tree;
    source: NodeId;
    operations: set[DragOperation];
    data = none(FormData)
): Option[DispatchResult] =
  ## Begin a drag from the focused source. The host maps its chosen keyboard
  ## command to this API, then dispatches the returned DragStart event.
  if state.keyboardDragActive or state.dragTarget.isSome or
      state.pressedTarget.isSome or state.focusedTarget != some(source) or
      not tree.isValid(source) or not tree.isWithinFocusScope(source) or
      tree.isInert(source) or tree.disabledTarget(some(source)):
    return none(DispatchResult)
  state.dragPayload = InputEventPayload(
    dragData: if data.isSome: data.get else: FormData(),
    hasDragData: data.isSome,
    dragOperations: some(operations),
    dragInputMethod: dimKeyboard
  )
  state.keyboardDragActive = true
  state.dragTarget = some(source)
  state.dragOverTarget = none(NodeId)
  some(DispatchResult(
    target: some(source),
    local: none(Vec2),
    event: dragEvent(iekDragStart, none(Vec2), state.dragPayload)
  ))

proc advanceKeyboardDrag*(
    state: var InteractionState; tree: Tree
): seq[DispatchResult] =
  ## Re-evaluate the focused target after keyboard focus navigation. The
  ## target accepts an operation while handling the returned DragOver event.
  if not state.keyboardDragActive:
    return
  let source = state.dragTarget
  if source.isNone or not tree.isValid(source.get) or
      not tree.isWithinFocusScope(source.get) or tree.isInert(source.get) or
      tree.disabledTarget(source):
    return state.cancelKeyboardDrag()
  var target = state.focusedTarget
  if target.isSome and (not tree.isValid(target.get) or
      not tree.isWithinFocusScope(target.get) or tree.isInert(target.get) or
      tree.disabledTarget(target)):
    target = none(NodeId)
  result.add DispatchResult(
    target: source,
    local: none(Vec2),
    event: dragEvent(iekDrag, none(Vec2), state.dragPayload)
  )
  state.updateDragOver(target, none(Vec2), none(Vec2), result)

proc finishKeyboardDrag*(
    state: var InteractionState; tree: Tree
): seq[DispatchResult] =
  ## Complete only when the current focused target accepted an offered
  ## operation on its latest DragOver event.
  if not state.keyboardDragActive:
    return
  let source = state.dragTarget
  if source.isNone or not tree.isValid(source.get) or
      not tree.isWithinFocusScope(source.get) or tree.isInert(source.get) or
      tree.disabledTarget(source):
    return state.cancelKeyboardDrag()
  let target = state.dragOverTarget
  let operation = state.acceptedDropOperation
  let selectedEntry = state.acceptedDropDataEntry
  let payload = state.dragPayload
  let canDrop = target.isSome and target == state.focusedTarget and
    tree.isValid(target.get) and tree.isWithinFocusScope(target.get) and
    not tree.isInert(target.get) and not tree.disabledTarget(target) and
    operation.isSome
  state.keyboardDragActive = false
  state.dragTarget = none(NodeId)
  state.dragOverTarget = none(NodeId)
  state.clearDragTransfer()
  if canDrop:
    result.add DispatchResult(
      target: target,
      local: none(Vec2),
      event: dragEvent(iekDrop, none(Vec2), payload, operation, selectedEntry)
    )
  result.add DispatchResult(
    target: source,
    local: none(Vec2),
    event: dragEvent(iekDragEnd, none(Vec2), payload,
      if canDrop: operation else: none(DragOperation),
      if canDrop: selectedEntry else: none(FormDataEntry))
  )

proc exceededDragThreshold(
    start, current: Option[Vec2]; threshold: float32
): bool =
  if start.isNone or current.isNone:
    return false
  let dx = abs(current.get.x - start.get.x)
  let dy = abs(current.get.y - start.get.y)
  dx + dy >= threshold

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

proc finishDragAutoScroll*(
    state: var InteractionState; scroll: var ScrollState
): seq[DispatchResult] =
  ## End a drag's scroll session, including when its source is disposed.
  if state.dragAutoScrollTarget.isSome:
    let target = state.dragAutoScrollTarget.get
    state.dragAutoScrollTarget = none(NodeId)
    if scroll.metricsFor(target).isSome:
      discard scroll.setScrolling(target, false)
      result.add DispatchResult(
        target: some(target),
        local: none(Vec2),
        event: InputEvent(kind: iekScrollEnd)
      )

proc dragEdgeDelta(
    point: Vec2; viewport: Rect; margin, step: float32
): Vec2 =
  if margin <= 0 or step <= 0 or viewport.w <= 0 or viewport.h <= 0 or
      point.x < viewport.x or point.x >= viewport.x + viewport.w or
      point.y < viewport.y or point.y >= viewport.y + viewport.h:
    return vec2(0, 0)
  let edgeX = min(margin, viewport.w * 0.5'f32)
  let edgeY = min(margin, viewport.h * 0.5'f32)
  if point.x < viewport.x + edgeX:
    result.x = -step
  elif point.x > viewport.x + viewport.w - edgeX:
    result.x = step
  if point.y < viewport.y + edgeY:
    result.y = -step
  elif point.y > viewport.y + viewport.h - edgeY:
    result.y = step

proc updateDragAutoScroll(
    state: var InteractionState;
    tree: Tree;
    regions: openArray[HitRegion];
    target: Option[NodeId];
    position: Option[Vec2];
    scroll: var ScrollState;
    output: var seq[DispatchResult]
) =
  if state.dragTarget.isSome and target.isSome and position.isSome and
      state.dragAutoScrollMargin > 0 and state.dragAutoScrollStep > 0 and
      tree.isValid(target.get) and not tree.isInert(target.get) and
      not tree.disabledTarget(target):
    var current = target
    while current.isSome:
      let id = current.get
      if not tree.isValid(id):
        break
      let metrics = scroll.metricsFor(id)
      if metrics.isSome:
        for region in regions:
          if region.node != id or region.kind != hrContent:
            continue
          var edgePoint = position.get
          var viewport = region.rect
          if region.shape.isSome and
              not region.shape.get.transform.isIdentity and
              region.shape.get.inverseTransform.isSome:
            edgePoint = region.shape.get.inverseTransform.get.transformPoint(
              edgePoint
            )
            viewport = region.shape.get.source
          let delta = dragEdgeDelta(edgePoint, viewport,
            state.dragAutoScrollMargin, state.dragAutoScrollStep)
          if delta.x == 0 and delta.y == 0:
            break
          if scroll.scrollBy(id, delta):
            if state.dragAutoScrollTarget != some(id):
              output.add state.finishDragAutoScroll(scroll)
            state.dragAutoScrollTarget = some(id)
            output.add scrollDispatch(id)
            return
          let item = metrics.get
          if (delta.x != 0 and item.enabledX and
              item.overscrollX != obAuto) or
              (delta.y != 0 and item.enabledY and
              item.overscrollY != obAuto):
            output.add state.finishDragAutoScroll(scroll)
            return
          break
      current = tree.nodes[id.nodeIndex].parent
  output.add state.finishDragAutoScroll(scroll)

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
    state.pressedButton = none(int)
    state.clearDragTransfer()
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

  if state.keyboardDragActive and
      (event.kind in {iekPointerDown, iekPointerUp, iekPointerCancel} or
      state.dragTarget.isNone or not tree.isValid(state.dragTarget.get) or
      not tree.isWithinFocusScope(state.dragTarget.get) or
      tree.isInert(state.dragTarget.get) or
      tree.disabledTarget(state.dragTarget)):
    result.add state.cancelKeyboardDrag()

  state.restrictToFocusScope(tree)
  if scroll != nil and (state.dragTarget.isNone or
      event.kind in {iekPointerDown, iekPointerUp, iekPointerCancel}):
    result.add state.finishDragAutoScroll(scroll[])

  var hit =
    if event.position.isSome: hitTest(regions, event.position.get)
    else: none(HitTestResult)
  if hit.isSome and tree.focusScopeRoot.isSome and
      not tree.isWithinFocusScope(hit.get.node):
    hit = none(HitTestResult)
  if scroll != nil and
      state.processScrollbarPointer(hit, event, scroll[], result):
    return

  let physicalTarget =
    if hit.isSome: some(hit.get.node)
    else: none(NodeId)
  let physicalLocal =
    if hit.isSome: some(hit.get.local)
    else: none(Vec2)
  var dispatch = dispatchInput(hit, event)
  case event.kind
  of iekPointerMove, iekPointerDown, iekPointerUp, iekPointerCancel:
    if state.pointerCaptureTarget.isSome:
      dispatch.target = state.pointerCaptureTarget
      dispatch.local = localForTarget(
        regions, state.pointerCaptureTarget, event.position
      )
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
      if state.dragTarget.isNone and state.pressedButton.isSome and
          state.pressedButton.get in {0, 1} and
          state.pointerDownPosition.exceededDragThreshold(
            event.position, state.dragThreshold
          ):
        state.dragTarget = state.pressedTarget
        result.add DispatchResult(
          target: state.dragTarget,
          local: localForTarget(regions, state.dragTarget, event.position),
          event: dragEvent(iekDragStart, event.position, state.dragPayload)
        )
      if state.dragTarget.isSome:
        result.add DispatchResult(
          target: state.dragTarget,
          local: localForTarget(regions, state.dragTarget, event.position),
          event: dragEvent(iekDrag, event.position, state.dragPayload)
        )
        state.updateDragOver(physicalTarget, physicalLocal,
          event.position, result)
        if scroll != nil:
          state.updateDragAutoScroll(tree, regions, physicalTarget,
            event.position, scroll[], result)
    result.add dispatch
  of iekPointerDown:
    state.clearDragTransfer()
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
    state.pressedButton =
      if targetDisabled: none(int)
      else: some(if event.button.isSome: event.button.get else: 0)
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
    if dragTarget.isSome and physicalTarget != state.dragOverTarget:
      state.updateDragOver(physicalTarget, physicalLocal,
        event.position, result)
    let dragOverTarget = state.dragOverTarget
    let payload = state.dragPayload
    let offered = state.dragOperations()
    let selected = state.acceptedDropOperation
    let selectedEntry = state.acceptedDropDataEntry
    let canDrop = dragOverTarget.isSome and
      tree.isValid(dragOverTarget.get) and
      not tree.disabledTarget(dragOverTarget) and
      not tree.isInert(dragOverTarget.get) and
      (offered.isNone or selected.isSome)
    state.pressedTarget = none(NodeId)
    state.pointerDownPosition = none(Vec2)
    state.pressedButton = none(int)
    state.dragTarget = none(NodeId)
    state.dragOverTarget = none(NodeId)
    state.clearDragTransfer()
    tree.updateActiveState(none(NodeId))
    if dragTarget.isSome:
      if canDrop:
        result.add DispatchResult(
          target: dragOverTarget,
          local: physicalLocal,
          event: dragEvent(iekDrop, event.position, payload, selected,
            selectedEntry)
        )
      result.add DispatchResult(
        target: dragTarget,
        local: localForTarget(regions, dragTarget, event.position),
        event: dragEvent(iekDragEnd, event.position, payload,
          if canDrop: selected else: none(DragOperation),
          if canDrop: selectedEntry else: none(FormDataEntry))
      )
    if dragTarget.isNone and pressed.isSome and physicalTarget == pressed and
        event.position.isSome:
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
    let released = state.releasePointer()
    if released.isSome:
      result.add released.get
  of iekPointerCancel:
    let dragTarget = state.dragTarget
    let payload = state.dragPayload
    if dragTarget.isSome:
      state.updateDragOver(none(NodeId), none(Vec2), event.position, result)
    state.pressedTarget = none(NodeId)
    state.pointerDownPosition = none(Vec2)
    state.pressedButton = none(int)
    state.dragTarget = none(NodeId)
    state.dragOverTarget = none(NodeId)
    state.clearDragTransfer()
    tree.updateActiveState(none(NodeId))
    result.add dispatch
    if dragTarget.isSome:
      result.add DispatchResult(
        target: dragTarget,
        local: localForTarget(regions, dragTarget, event.position),
        event: dragEvent(iekDragEnd, event.position, payload)
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
