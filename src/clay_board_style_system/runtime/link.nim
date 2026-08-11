import std/options

import ../core/[declaration, node, style_value]
import ../input/events
import ./[navigation, ui_root]

type
  LinkState*[Destination] = ref object
    ## A navigator is application-owned and must outlive every link that uses it.
    navigator* {.cursor.}: Navigator[Destination]
    destination*: Destination
    label*: string
    disabled*: bool

  LinkHandle*[Destination] = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    labelNode*: NodeHandle
    state*: LinkState[Destination]

proc label*[Destination](link: LinkHandle[Destination]): string =
  link.state.label

proc destination*[Destination](link: LinkHandle[Destination]): Destination =
  link.state.destination

proc disabled*[Destination](link: LinkHandle[Destination]): bool =
  link.state.disabled

proc setLabel*[Destination](link: LinkHandle[Destination]; label: string) =
  link.state.label = label
  link.root.tree.nodes[link.labelNode.id.nodeIndex].text = label
  link.container.setAccessibleName(label)

proc setDestination*[Destination](
    link: LinkHandle[Destination];
    destination: Destination
) =
  link.state.destination = destination

proc setDisabled*[Destination](link: LinkHandle[Destination]; disabled: bool) =
  link.state.disabled = disabled
  link.container.setState(esDisabled, disabled)

proc activate*[Destination](link: LinkHandle[Destination]): bool {.discardable.} =
  if link.state.disabled:
    return false
  link.state.navigator.push(link.state.destination)

proc `onClick=`*[Destination](
    link: LinkHandle[Destination];
    handler: EventHandler
) =
  link.container.onClick = handler

proc link*[Destination](
    root: UiRoot;
    navigator: Navigator[Destination];
    destination: Destination;
    label: string;
    disabled = false;
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["link"]
): LinkHandle[Destination] {.discardable.} =
  if navigator.isNil:
    raise newException(ValueError, "link requires a navigator")

  result.root = root
  result.state = LinkState[Destination](
    navigator: navigator,
    destination: destination,
    label: label,
    disabled: disabled
  )
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arLink)
  result.container.setAccessibleName(label)
  result.labelNode = root.text(
    result.container,
    label,
    textStyle,
    groups = ["link-label"]
  )
  root.applyStyle(
    result.labelNode,
    uiStyle([decl("pointer-events", keyword("none"))])
  )
  result.setDisabled(disabled)

  let link = result
  root.events.addInternalEventHandler(
    link.container.id,
    iekClick,
    proc(event: DispatchResult): EventOutcome =
      if link.state.disabled:
        return ignoredEvent()
      if link.activate():
        return stoppedEvent()
      ignoredEvent()
  )
  root.events.addInternalEventHandler(
    link.container.id,
    iekKeyDown,
    proc(event: DispatchResult): EventOutcome =
      if link.state.disabled:
        return ignoredEvent()
      if event.event.key.isSome and event.event.key.get == "Enter":
        discard link.container.emit(InputEvent(kind: iekClick))
        return stoppedEvent()
      ignoredEvent()
  )
