import std/options

import ../core/node
import ../input/events
import ./[checkbox, radio, text_input, textarea]
import ./ui_root

type
  LabelParams* = object
    text*: string
    disabled*: bool

  LabelState* = ref object
    text*: string
    disabled*: bool
    target*: Option[NodeHandle]

  LabelHandle* = object
    root*: UiRoot
    container*: NodeHandle
    textNode*: NodeHandle
    state*: LabelState

proc setText*(label: LabelHandle; text: string) =
  label.state.text = text
  label.root.tree.nodes[label.textNode.id.nodeIndex].text = text

proc setDisabled*(label: LabelHandle; disabled: bool) =
  label.state.disabled = disabled
  label.container.setState(esDisabled, disabled)

proc disabled*(label: LabelHandle): bool =
  label.state.disabled

proc text*(label: LabelHandle): string =
  label.state.text

proc target*(label: LabelHandle): Option[NodeHandle] =
  label.state.target

proc setTarget*(label: LabelHandle; target: NodeHandle) =
  if label.state.target.isSome:
    let previous = label.state.target.get
    if label.root.tree.semanticInfo(previous.id).labelledBy ==
        some(label.container.id):
      previous.setAccessibleLabelledBy(none(NodeHandle))
  label.state.target = some(target)
  label.container.setFocusDelegate(some(target))
  target.setAccessibleLabelledBy(some(label.container))

proc clearTarget*(label: LabelHandle) =
  if label.state.target.isSome:
    let target = label.state.target.get
    if label.root.tree.semanticInfo(target.id).labelledBy ==
        some(label.container.id):
      target.setAccessibleLabelledBy(none(NodeHandle))
  label.state.target = none(NodeHandle)
  label.container.setFocusDelegate(none(NodeHandle))

proc activateTarget(label: LabelHandle): bool =
  if label.state.disabled or label.state.target.isNone:
    return label.state.disabled
  let target = label.state.target.get
  discard target.emit(iekFocus)
  discard target.emit(InputEvent(kind: iekClick))
  true

proc `onClick=`*(label: LabelHandle; handler: EventHandler) =
  label.container.onClick = handler

proc label*(
    root: UiRoot;
    params: LabelParams;
    target = none(NodeHandle);
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["label"]
): LabelHandle {.discardable.} =
  result.root = root
  result.state = LabelState(
    text: params.text,
    disabled: params.disabled,
    target: target
  )
  result.container = root.box(style, id = id, groups = groups)
  result.textNode = root.text(result.container, params.text, textStyle, groups = ["label-text"])
  if target.isSome:
    result.setTarget(target.get)
  result.setDisabled(params.disabled)

  let label = result

  root.events.addInternalEventHandler(label.container.id, iekClick, proc(event: DispatchResult): bool =
    label.activateTarget()
  )
  root.events.addInternalEventHandler(label.container.id, iekKeyDown, proc(event: DispatchResult): bool =
    if label.state.disabled:
      return true
    if event.event.key.isSome:
      case event.event.key.get
      of "Enter", " ":
        discard label.container.emit(InputEvent(kind: iekClick))
        return true
      else:
        discard
    false
  )

proc label*(
    root: UiRoot;
    text: string;
    target = none(NodeHandle);
    disabled = false;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["label"]
): LabelHandle {.discardable.} =
  root.label(
    LabelParams(text: text, disabled: disabled),
    target = target,
    style = style,
    textStyle = textStyle,
    id = id,
    groups = groups
  )

proc label*(
    root: UiRoot;
    text: string;
    target: CheckboxHandle;
    disabled = false;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["label"]
): LabelHandle {.discardable.} =
  root.label(text, target = some(target.container), disabled = disabled, style = style, textStyle = textStyle, id = id, groups = groups)

proc label*(
    root: UiRoot;
    text: string;
    target: RadioHandle;
    disabled = false;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["label"]
): LabelHandle {.discardable.} =
  root.label(text, target = some(target.container()), disabled = disabled, style = style, textStyle = textStyle, id = id, groups = groups)

proc label*(
    root: UiRoot;
    text: string;
    target: TextInputHandle;
    disabled = false;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["label"]
): LabelHandle {.discardable.} =
  root.label(text, target = some(target.container), disabled = disabled, style = style, textStyle = textStyle, id = id, groups = groups)

proc label*(
    root: UiRoot;
    text: string;
    target: TextAreaHandle;
    disabled = false;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["label"]
): LabelHandle {.discardable.} =
  root.label(text, target = some(target.container), disabled = disabled, style = style, textStyle = textStyle, id = id, groups = groups)
