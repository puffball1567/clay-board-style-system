import std/options

import ../core/[color, declaration, node, style_value]
import ../input/events
import ./ui_root

type
  CheckboxParams* = object
    label*: string
    checked*: bool
    disabled*: bool

  CheckboxState* = ref object
    label*: string
    checked*: bool
    disabled*: bool

  CheckboxHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    markerNode*: NodeHandle
    indicatorNode*: NodeHandle
    labelNode*: NodeHandle
    state*: CheckboxState

proc updateMarker(checkbox: CheckboxHandle) =
  if not checkbox.container.valid():
    return
  checkbox.markerNode.setState(esChecked, checkbox.state.checked)
  checkbox.indicatorNode.setState(esChecked, checkbox.state.checked)
  checkbox.root.tree.setAttribute(
    checkbox.container.id,
    "checked",
    if checkbox.state.checked: "true" else: "false"
  )
  checkbox.container.setAccessibleValue(if checkbox.state.checked: "true" else: "false")
  checkbox.root.tree.setAttribute(
    checkbox.container.id,
    "value",
    if checkbox.state.checked: "true" else: "false"
  )

proc emitValueEvents(checkbox: CheckboxHandle) =
  let value =
    if checkbox.state.checked: "true"
    else: "false"
  discard checkbox.container.emit(inputEvent(value))
  discard checkbox.container.emit(changeEvent(value))

proc setLabel*(checkbox: CheckboxHandle; label: string) =
  if not checkbox.container.valid():
    return
  checkbox.state.label = label
  checkbox.root.tree.nodes[checkbox.labelNode.id.nodeIndex].text = label
  checkbox.container.setAccessibleName(label)

proc setChecked*(checkbox: CheckboxHandle; checked: bool; emitEvents = false) =
  if not checkbox.container.valid() or checkbox.state.checked == checked:
    return
  checkbox.state.checked = checked
  checkbox.container.setState(esChecked, checked)
  checkbox.updateMarker()
  if emitEvents:
    checkbox.emitValueEvents()

proc toggle*(checkbox: CheckboxHandle; emitEvents = true) =
  if not checkbox.container.valid() or checkbox.state.disabled:
    return
  checkbox.setChecked(not checkbox.state.checked, emitEvents = emitEvents)

proc setDisabled*(checkbox: CheckboxHandle; disabled: bool) =
  if not checkbox.container.valid():
    return
  checkbox.state.disabled = disabled
  checkbox.container.setState(esDisabled, disabled)

proc checked*(checkbox: CheckboxHandle): bool =
  checkbox.state.checked

proc disabled*(checkbox: CheckboxHandle): bool =
  checkbox.state.disabled

proc `onChange=`*(checkbox: CheckboxHandle; handler: EventHandler) =
  checkbox.container.onChange = handler

proc `onInput=`*(checkbox: CheckboxHandle; handler: EventHandler) =
  checkbox.container.onInput = handler

proc `onClick=`*(checkbox: CheckboxHandle; handler: EventHandler) =
  checkbox.container.onClick = handler

proc checkbox*(
    root: UiRoot;
    params: CheckboxParams;
    style = UiStyle();
    markerStyle = UiStyle();
    labelStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["checkbox"]
): CheckboxHandle {.discardable.} =
  result.root = root
  result.state = CheckboxState(
    label: params.label,
    checked: params.checked,
    disabled: params.disabled
  )
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arCheckBox)
  result.container.setAccessibleName(params.label)
  result.markerNode = root.box(
    markerStyle,
    parent = some(result.container),
    groups = ["checkbox-marker"]
  )
  result.markerNode.applyStyle(uiStyle([
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center"))
  ]))
  result.indicatorNode = root.text(
    result.markerNode,
    "✓",
    uiStyle([
      decl("display", keyword("none")),
      decl("font-size", px(13)),
      decl("line-height", number(1)),
      decl("font-weight", keyword("bold")),
      decl("color", colorValue(rgb(0.30, 0.92, 0.74))),
      decl("pointer-events", keyword("none"))
    ]),
    groups = ["checkbox-indicator"]
  )
  result.indicatorNode.applyStateStyle({esChecked}, uiStyle([
    decl("display", keyword("flex"))
  ]), priority = 100)
  result.labelNode = root.text(
    result.container,
    params.label,
    labelStyle,
    groups = ["checkbox-label"]
  )
  result.container.setState(esChecked, params.checked)
  result.markerNode.setState(esChecked, params.checked)
  result.indicatorNode.setState(esChecked, params.checked)
  result.container.setState(esDisabled, params.disabled)
  result.root.tree.setAttribute(result.container.id, "checked", if params.checked: "true" else: "false")
  result.root.tree.setAttribute(result.container.id, "value", if params.checked: "true" else: "false")
  result.root.tree.setAttribute(result.container.id, "label", params.label)

  let checkbox = result
  let ownDisabled = params.disabled
  root.registerFieldsetTarget(proc(disabled: bool) =
    checkbox.setDisabled(ownDisabled or disabled)
  )

  root.events.addInternalEventHandler(checkbox.container.id, iekClick, proc(event: DispatchResult): bool =
    if checkbox.state.disabled:
      return true
    checkbox.toggle()
    false
  )
  root.events.addInternalEventHandler(checkbox.container.id, iekKeyDown, proc(event: DispatchResult): bool =
    if checkbox.state.disabled:
      return true
    if event.event.key.isSome:
      case event.event.key.get
      of "Enter", " ":
        discard checkbox.container.emit(InputEvent(kind: iekClick))
        return true
      else:
        discard
    false
  )

proc checkbox*(
    root: UiRoot;
    label: string;
    checked = false;
    style = UiStyle();
    markerStyle = UiStyle();
    labelStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["checkbox"]
): CheckboxHandle {.discardable.} =
  root.checkbox(
    CheckboxParams(label: label, checked: checked),
    style = style,
    markerStyle = markerStyle,
    labelStyle = labelStyle,
    id = id,
    groups = groups
  )
