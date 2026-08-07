import std/options

import ../core/[declaration, node, style_value]
import ../input/events
import ./ui_root

type
  ButtonParams* = object
    label*: string
    disabled*: bool

  ButtonState* = ref object
    label*: string
    disabled*: bool

  ButtonHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    labelNode*: NodeHandle
    state*: ButtonState

proc setLabel*(button: ButtonHandle; label: string) =
  if not button.container.valid():
    return
  button.state.label = label
  button.root.tree.nodes[button.labelNode.id.nodeIndex].text = label
  button.container.setAccessibleName(label)

proc setDisabled*(button: ButtonHandle; disabled: bool) =
  if not button.container.valid():
    return
  button.state.disabled = disabled
  button.container.setState(esDisabled, disabled)

proc disabled*(button: ButtonHandle): bool =
  button.state.disabled

proc `onClick=`*(button: ButtonHandle; handler: EventHandler) =
  button.container.onClick = handler

proc button*(
    root: UiRoot;
    params: ButtonParams;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["button"]
): ButtonHandle {.discardable.} =
  result.root = root
  result.state = ButtonState(label: params.label, disabled: params.disabled)
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arButton)
  result.container.setAccessibleName(params.label)
  result.labelNode = root.text(result.container, params.label, textStyle, groups = ["button-label"])
  root.applyStyle(result.labelNode, uiStyle([decl("pointer-events", keyword("none"))]))
  result.setDisabled(params.disabled)

  let button = result

  root.events.addInternalEventHandler(button.container.id, iekClick, proc(event: DispatchResult): EventOutcome =
    if button.state.disabled: stoppedEvent() else: ignoredEvent()
  )
  root.events.addInternalEventHandler(button.container.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if button.state.disabled:
      return stoppedEvent()
    if event.event.key.isSome:
      case event.event.key.get
      of "Enter", " ":
        discard button.container.emit(InputEvent(kind: iekClick))
        return stoppedEvent()
      else:
        discard
    ignoredEvent()
  )

proc button*(
    root: UiRoot;
    label: string;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["button"]
): ButtonHandle {.discardable.} =
  root.button(ButtonParams(label: label), style = style, textStyle = textStyle, id = id, groups = groups)
