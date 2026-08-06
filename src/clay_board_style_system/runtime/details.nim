import std/options

import ../core/[declaration, node, style_value]
import ../input/events
import ./ui_root

type
  DetailsParams* = object
    summary*: string
    body*: string
    open*: bool
    disabled*: bool

  DetailsState* = ref object
    summary*: string
    body*: string
    open*: bool
    disabled*: bool

  DetailsHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    summaryNode*: NodeHandle
    markerNode*: NodeHandle
    summaryTextNode*: NodeHandle
    bodyNode*: NodeHandle
    state*: DetailsState

proc syncVisibleState(details: DetailsHandle) =
  if not details.container.valid():
    return
  details.container.setState(esOpen, details.state.open)
  details.container.setState(esDisabled, details.state.disabled)
  details.summaryNode.setState(esOpen, details.state.open)
  details.summaryNode.setState(esDisabled, details.state.disabled)
  details.markerNode.setState(esOpen, details.state.open)
  details.bodyNode.setState(esOpen, details.state.open)
  details.bodyNode.setState(esDisabled, details.state.disabled)
  details.root.tree.nodes[details.summaryTextNode.id.nodeIndex].text = details.state.summary
  details.root.tree.nodes[details.bodyNode.id.nodeIndex].text = details.state.body
  details.root.tree.nodes[details.markerNode.id.nodeIndex].text =
    if details.state.open: "v"
    else: ">"
  details.summaryNode.setAccessibleName(details.state.summary)
  details.summaryNode.setAccessibleValue(if details.state.open: "expanded" else: "collapsed")

proc isOpen*(details: DetailsHandle): bool =
  details.state.open

proc disabled*(details: DetailsHandle): bool =
  details.state.disabled

proc summary*(details: DetailsHandle): string =
  details.state.summary

proc body*(details: DetailsHandle): string =
  details.state.body

proc setOpen*(details: DetailsHandle; open: bool; emitToggle = false) =
  if not details.container.valid() or details.state.disabled or details.state.open == open:
    return
  details.state.open = open
  details.syncVisibleState()
  if emitToggle:
    discard details.container.emit(iekToggle)

proc toggle*(details: DetailsHandle; emitToggle = true) =
  details.setOpen(not details.state.open, emitToggle = emitToggle)

proc setDisabled*(details: DetailsHandle; disabled: bool) =
  if not details.container.valid():
    return
  details.state.disabled = disabled
  details.syncVisibleState()

proc setSummary*(details: DetailsHandle; summary: string) =
  if not details.container.valid():
    return
  details.state.summary = summary
  details.syncVisibleState()

proc setBody*(details: DetailsHandle; body: string) =
  if not details.container.valid():
    return
  details.state.body = body
  details.syncVisibleState()

proc `onToggle=`*(details: DetailsHandle; handler: EventHandler) =
  details.container.onToggle = handler

proc details*(
    root: UiRoot;
    params: DetailsParams;
    style = UiStyle();
    summaryStyle = UiStyle();
    markerStyle = UiStyle();
    summaryTextStyle = UiStyle();
    bodyStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["details"]
): DetailsHandle {.discardable.} =
  result.root = root
  result.state = DetailsState(
    summary: params.summary,
    body: params.body,
    open: params.open,
    disabled: params.disabled
  )
  result.container = root.box(style, id = id, groups = groups)
  result.summaryNode = root.box(summaryStyle, parent = some(result.container), groups = ["details-summary"])
  result.summaryNode.setFocusable()
  result.summaryNode.setAccessibleRole(arDisclosure)
  result.summaryNode.applyStyle(uiStyle([
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ]))
  result.markerNode = root.text(
    result.summaryNode,
    "",
    markerStyle,
    groups = ["details-marker"]
  )
  result.markerNode.applyStyle(uiStyle([
    decl("pointer-events", keyword("none"))
  ]))
  result.summaryTextNode = root.text(
    result.summaryNode,
    params.summary,
    summaryTextStyle,
    groups = ["details-summary-text"]
  )
  result.summaryTextNode.applyStyle(uiStyle([
    decl("pointer-events", keyword("none"))
  ]))
  result.bodyNode = root.text(result.container, params.body, bodyStyle, groups = ["details-body"])
  result.bodyNode.applyStyle(uiStyle([
    decl("display", keyword("none")),
    decl("pointer-events", keyword("none"))
  ]))
  result.bodyNode.applyStateStyle({esOpen}, uiStyle([
    decl("display", keyword("flex"))
  ]), priority = 100)
  result.syncVisibleState()

  let details = result

  root.events.addInternalEventHandler(details.summaryNode.id, iekClick, proc(event: DispatchResult): EventOutcome =
    if details.state.disabled:
      return true
    details.toggle()
    true
  )
  root.events.addInternalEventHandler(details.summaryNode.id, iekPointerDown, proc(event: DispatchResult): EventOutcome =
    if details.state.disabled:
      return true
    false
  )
  root.events.addInternalEventHandler(details.summaryNode.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if details.state.disabled:
      return true
    if event.event.key.isSome:
      case event.event.key.get
      of "Enter", " ":
        details.toggle()
        return true
      of "ArrowRight":
        details.setOpen(true, emitToggle = true)
        return true
      of "ArrowLeft":
        details.setOpen(false, emitToggle = true)
        return true
      else:
        discard
    false
  )

proc details*(
    root: UiRoot;
    summary: string;
    body = "";
    open = false;
    disabled = false;
    style = UiStyle();
    summaryStyle = UiStyle();
    markerStyle = UiStyle();
    summaryTextStyle = UiStyle();
    bodyStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["details"]
): DetailsHandle {.discardable.} =
  root.details(
    DetailsParams(summary: summary, body: body, open: open, disabled: disabled),
    style = style,
    summaryStyle = summaryStyle,
    markerStyle = markerStyle,
    summaryTextStyle = summaryTextStyle,
    bodyStyle = bodyStyle,
    id = id,
    groups = groups
  )
