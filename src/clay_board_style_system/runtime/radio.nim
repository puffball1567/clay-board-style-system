import std/options

import ../core/[color, declaration, node, style_value]
import ../input/events
import ./form
import ./ui_root

type
  RadioState* = ref object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    markerNode*: NodeHandle
    indicatorNode*: NodeHandle
    labelNode*: NodeHandle
    label*: string
    value*: string
    checked*: bool
    disabled*: bool

  RadioSet* = ref object
    selectedValue*: string
    items*: seq[RadioState]

  RadioParams* = object
    label*: string
    value*: string
    checked*: bool
    disabled*: bool

  RadioHandle* = object
    state*: RadioState
    radioSet*: RadioSet

proc register*(form: FormHandle; name: string; radio: RadioHandle) =
  form.registerField(radio.state.container, name, ffCheckable)

proc initRadioSet*(selectedValue = ""): RadioSet =
  RadioSet(selectedValue: selectedValue, items: @[])

proc container*(radio: RadioHandle): NodeHandle =
  radio.state.container

proc markerNode*(radio: RadioHandle): NodeHandle =
  radio.state.markerNode

proc labelNode*(radio: RadioHandle): NodeHandle =
  radio.state.labelNode

proc value*(radio: RadioHandle): string =
  radio.state.value

proc checked*(radio: RadioHandle): bool =
  radio.state.checked

proc disabled*(radio: RadioHandle): bool =
  radio.state.disabled

proc updateMarker(state: RadioState) =
  if not state.container.valid():
    return
  state.markerNode.setState(esChecked, state.checked)
  state.indicatorNode.setState(esChecked, state.checked)

proc syncChecked(state: RadioState; checked: bool) =
  if not state.container.valid():
    return
  state.checked = checked
  state.container.setState(esChecked, checked)
  state.root.tree.setAttribute(state.container.id, "checked", if checked: "true" else: "false")
  state.updateMarker()

proc emitValueEvents(radio: RadioHandle) =
  discard radio.container.emit(inputEvent(radio.state.value))
  discard radio.container.emit(changeEvent(radio.state.value))

proc select*(radio: RadioHandle; emitEvents = true) =
  if not radio.container.valid() or radio.state.disabled or radio.state.checked:
    return
  radio.radioSet.selectedValue = radio.state.value
  for item in radio.radioSet.items:
    item.syncChecked(item == radio.state)
  if emitEvents:
    radio.emitValueEvents()

proc setDisabled*(radio: RadioHandle; disabled: bool) =
  if not radio.container.valid():
    return
  radio.state.disabled = disabled
  radio.container.setState(esDisabled, disabled)

proc setLabel*(radio: RadioHandle; label: string) =
  if not radio.container.valid():
    return
  radio.state.label = label
  radio.state.root.tree.nodes[radio.state.labelNode.id.nodeIndex].text = label
  radio.container.setAccessibleName(label)

proc `onChange=`*(radio: RadioHandle; handler: EventHandler) =
  radio.container.onChange = handler

proc `onInput=`*(radio: RadioHandle; handler: EventHandler) =
  radio.container.onInput = handler

proc `onClick=`*(radio: RadioHandle; handler: EventHandler) =
  radio.container.onClick = handler

proc radio*(
    root: UiRoot;
    params: RadioParams;
    radioSet: RadioSet;
    style = UiStyle();
    markerStyle = UiStyle();
    labelStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["radio"]
): RadioHandle {.discardable.} =
  let initiallyChecked =
    if params.checked: true
    elif radioSet.selectedValue.len > 0: radioSet.selectedValue == params.value
    else: false

  let container = root.box(style, id = id, groups = groups)
  container.setFocusable()
  container.setAccessibleRole(arRadio)
  container.setAccessibleName(params.label)
  container.setAccessibleValue(params.value)
  let marker = root.box(
    markerStyle,
    parent = some(container),
    groups = ["radio-marker"]
  )
  marker.applyStyle(uiStyle([
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center"))
  ]))
  let indicator = root.box(
    uiStyle([
      decl("width", px(8)),
      decl("height", px(8)),
      decl("display", keyword("none")),
      decl("background-color", colorValue(rgb(0.34, 0.70, 0.96))),
      decl("border-radius", px(4)),
      decl("pointer-events", keyword("none"))
    ]),
    parent = some(marker),
    groups = ["radio-indicator"]
  )
  indicator.applyStateStyle({esChecked}, uiStyle([
    decl("display", keyword("flex"))
  ]), priority = 100)
  let label = root.text(
    container,
    params.label,
    labelStyle,
    groups = ["radio-label"]
  )
  container.setState(esChecked, initiallyChecked)
  marker.setState(esChecked, initiallyChecked)
  indicator.setState(esChecked, initiallyChecked)
  container.setState(esDisabled, params.disabled)
  root.tree.setAttribute(container.id, "checked", if initiallyChecked: "true" else: "false")
  root.tree.setAttribute(container.id, "value", params.value)
  root.tree.setAttribute(container.id, "label", params.label)

  let state = RadioState(
    root: root,
    container: container,
    markerNode: marker,
    indicatorNode: indicator,
    labelNode: label,
    label: params.label,
    value: params.value,
    checked: initiallyChecked,
    disabled: params.disabled
  )
  radioSet.items.add state
  if initiallyChecked:
    radioSet.selectedValue = params.value
    for item in radioSet.items:
      item.syncChecked(item == state)

  result = RadioHandle(state: state, radioSet: radioSet)
  let radio = result
  let ownDisabled = params.disabled
  root.registerFieldsetTarget(proc(disabled: bool) =
    radio.setDisabled(ownDisabled or disabled)
  )

  root.events.addInternalEventHandler(radio.container.id, iekClick, proc(event: DispatchResult): EventOutcome =
    if radio.state.disabled:
      return stoppedEvent()
    radio.select()
    ignoredEvent()
  )
  root.events.addInternalEventHandler(radio.container.id, iekPointerDown, proc(event: DispatchResult): EventOutcome =
    if radio.state.disabled:
      return stoppedEvent()
    radio.select()
    stoppedEvent()
  )
  root.events.addInternalEventHandler(radio.container.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if radio.state.disabled:
      return stoppedEvent()
    if event.event.key.isSome:
      case event.event.key.get
      of "Enter", " ":
        discard radio.container.emit(InputEvent(kind: iekClick))
        return stoppedEvent()
      else:
        discard
    ignoredEvent()
  )

proc radio*(
    root: UiRoot;
    radioSet: RadioSet;
    label: string;
    value: string;
    checked = false;
    style = UiStyle();
    markerStyle = UiStyle();
    labelStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["radio"]
): RadioHandle {.discardable.} =
  root.radio(
    RadioParams(label: label, value: value, checked: checked),
    radioSet,
    style = style,
    markerStyle = markerStyle,
    labelStyle = labelStyle,
    id = id,
    groups = groups
  )
