import std/[math, options]

import ../core/[declaration, geometry, node, style_value]
import ../input/events
import ./ui_root

type
  SliderParams* = object
    min*: float32
    max*: float32
    step*: float32
    value*: float32
    disabled*: bool
    trackWidth*: float32

  SliderState* = ref object
    min*: float32
    max*: float32
    step*: float32
    value*: float32
    disabled*: bool
    dragging*: bool
    trackWidth*: float32

  SliderHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    trackNode*: NodeHandle
    fillNode*: NodeHandle
    thumbNode*: NodeHandle
    valueNode*: NodeHandle
    state*: SliderState

proc normalizedParams(params: SliderParams): SliderParams =
  result = params
  if result.max <= result.min:
    result.max = result.min + 1
  if result.step < 0:
    result.step = 0
  if result.trackWidth <= 0:
    result.trackWidth = 100

proc clampValue(state: SliderState; value: float32): float32 =
  result = max(state.min, min(state.max, value))
  if state.step > 0:
    let steps = round((result - state.min) / state.step)
    result = state.min + steps.float32 * state.step
    result = max(state.min, min(state.max, result))

proc percent(state: SliderState): float32 =
  if state.max <= state.min:
    return 0
  (state.value - state.min) / (state.max - state.min)

proc syncVisibleState(slider: SliderHandle) =
  if not slider.container.valid():
    return
  slider.container.setState(esDisabled, slider.state.disabled)
  slider.container.setState(esActive, slider.state.dragging)
  slider.root.tree.setAttribute(slider.container.id, "value", $slider.state.value)
  slider.root.tree.setAttribute(slider.container.id, "percent", $slider.state.percent())
  slider.root.tree.nodes[slider.valueNode.id.nodeIndex].text = $slider.state.value
  slider.root.tree.nodes[slider.thumbNode.id.nodeIndex].text = $int(round(slider.state.percent() * 100)) & "%"
  slider.container.setAccessibleValue($slider.state.value)
  slider.container.setAccessibleRange(
    some(slider.state.value),
    some(slider.state.min),
    some(slider.state.max)
  )
  slider.fillNode.applyStyle(uiStyle([
    decl("width", px(slider.state.trackWidth * slider.state.percent()))
  ]))

proc emitValueEvents(slider: SliderHandle) =
  let value = $slider.state.value
  discard slider.container.emit(inputEvent(value))
  discard slider.container.emit(changeEvent(value))

proc value*(slider: SliderHandle): float32 =
  slider.state.value

proc disabled*(slider: SliderHandle): bool =
  slider.state.disabled

proc setValue*(slider: SliderHandle; value: float32; emitEvents = false) =
  if not slider.container.valid() or slider.state.disabled:
    return
  let next = slider.state.clampValue(value)
  if next == slider.state.value:
    return
  slider.state.value = next
  slider.syncVisibleState()
  if emitEvents:
    slider.emitValueEvents()

proc setDisabled*(slider: SliderHandle; disabled: bool) =
  if not slider.container.valid():
    return
  slider.state.disabled = disabled
  if disabled:
    slider.state.dragging = false
  slider.syncVisibleState()

proc setValueFromLocal(slider: SliderHandle; local: Option[Vec2]; emitEvents = true) =
  if slider.state.disabled or local.isNone:
    return
  let ratio = max(0'f32, min(1'f32, local.get.x / slider.state.trackWidth))
  slider.setValue(slider.state.min + (slider.state.max - slider.state.min) * ratio, emitEvents = emitEvents)

proc stepBy(slider: SliderHandle; direction: float32) =
  let delta =
    if slider.state.step > 0: slider.state.step
    else: (slider.state.max - slider.state.min) / 100
  slider.setValue(slider.state.value + delta * direction, emitEvents = true)

proc `onChange=`*(slider: SliderHandle; handler: EventHandler) =
  slider.container.onChange = handler

proc `onInput=`*(slider: SliderHandle; handler: EventHandler) =
  slider.container.onInput = handler

proc `onPointerDown=`*(slider: SliderHandle; handler: EventHandler) =
  slider.container.onPointerDown = handler

proc `onPointerMove=`*(slider: SliderHandle; handler: EventHandler) =
  slider.container.onPointerMove = handler

proc `onPointerUp=`*(slider: SliderHandle; handler: EventHandler) =
  slider.container.onPointerUp = handler

proc slider*(
    root: UiRoot;
    params: SliderParams;
    style = UiStyle();
    trackStyle = UiStyle();
    fillStyle = UiStyle();
    thumbStyle = UiStyle();
    valueStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["slider"]
): SliderHandle {.discardable.} =
  let normalized = params.normalizedParams()
  result.root = root
  result.state = SliderState(
    min: normalized.min,
    max: normalized.max,
    step: normalized.step,
    disabled: normalized.disabled,
    trackWidth: normalized.trackWidth
  )
  result.state.value = result.state.clampValue(normalized.value)
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arSlider)
  result.trackNode = root.box(trackStyle, parent = some(result.container), groups = ["slider-track"])
  result.fillNode = root.box(fillStyle + uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(0)),
    decl("pointer-events", keyword("none"))
  ]), parent = some(result.trackNode), groups = ["slider-fill"])
  result.thumbNode = root.text(result.trackNode, "", thumbStyle, groups = ["slider-thumb"])
  result.valueNode = root.text(result.container, "", valueStyle, groups = ["slider-value"])
  result.syncVisibleState()

  let slider = result

  root.events.addInternalEventHandler(slider.container.id, iekClick, proc(event: DispatchResult): bool =
    if slider.state.disabled:
      return true
    slider.setValueFromLocal(event.local)
    false
  )
  root.events.addInternalEventHandler(slider.container.id, iekPointerDown, proc(event: DispatchResult): bool =
    if slider.state.disabled:
      return true
    slider.state.dragging = true
    slider.setValueFromLocal(event.local)
    slider.syncVisibleState()
    false
  )
  root.events.addInternalEventHandler(slider.container.id, iekPointerMove, proc(event: DispatchResult): bool =
    if slider.state.disabled:
      return true
    if slider.state.dragging:
      slider.setValueFromLocal(event.local)
      return false
    false
  )
  root.events.addInternalEventHandler(slider.container.id, iekPointerUp, proc(event: DispatchResult): bool =
    if slider.state.disabled:
      return true
    slider.state.dragging = false
    slider.syncVisibleState()
    false
  )
  root.events.addInternalEventHandler(slider.container.id, iekKeyDown, proc(event: DispatchResult): bool =
    if slider.state.disabled:
      return true
    if event.event.key.isNone:
      return false
    case event.event.key.get
    of "ArrowRight", "ArrowUp":
      slider.stepBy(1)
      return true
    of "ArrowLeft", "ArrowDown":
      slider.stepBy(-1)
      return true
    of "Home":
      slider.setValue(slider.state.min, emitEvents = true)
      return true
    of "End":
      slider.setValue(slider.state.max, emitEvents = true)
      return true
    else:
      discard
    false
  )

proc slider*(
    root: UiRoot;
    value = 0'f32;
    min = 0'f32;
    max = 100'f32;
    step = 1'f32;
    disabled = false;
    trackWidth = 100'f32;
    style = UiStyle();
    trackStyle = UiStyle();
    fillStyle = UiStyle();
    thumbStyle = UiStyle();
    valueStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["slider"]
): SliderHandle {.discardable.} =
  root.slider(
    SliderParams(
      min: min,
      max: max,
      step: step,
      value: value,
      disabled: disabled,
      trackWidth: trackWidth
    ),
    style = style,
    trackStyle = trackStyle,
    fillStyle = fillStyle,
    thumbStyle = thumbStyle,
    valueStyle = valueStyle,
    id = id,
    groups = groups
  )
