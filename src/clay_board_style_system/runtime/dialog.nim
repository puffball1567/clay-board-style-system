import std/options

import ../core/node
import ../input/events
import ./[focus, ui_root]

type
  DialogParams* = object
    title*: string
    body*: string
    open*: bool
    modal*: bool

  DialogState* = ref object
    title*: string
    body*: string
    open*: bool
    modal*: bool
    closeCount*: int
    cancelCount*: int
    showCount*: int
    focusScopeActive*: bool
    previousFocusScope*: Option[NodeId]
    restoreFocus*: Option[NodeId]
    restoreFocusPending*: bool

  DialogHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    titleNode*: NodeHandle
    bodyNode*: NodeHandle
    state*: DialogState

proc syncVisibleState(dialog: DialogHandle) =
  if not dialog.container.valid():
    return
  dialog.container.setState(esActive, dialog.state.open)
  dialog.container.setState(esDisabled, not dialog.state.open)
  dialog.root.tree.nodes[dialog.titleNode.id.nodeIndex].text = dialog.state.title
  dialog.root.tree.nodes[dialog.bodyNode.id.nodeIndex].text = dialog.state.body
  dialog.container.setAccessibleName(dialog.state.title)
  dialog.container.setAccessibleDescription(dialog.state.body)
  dialog.container.setAccessibleHidden(not dialog.state.open)

proc isOpen*(dialog: DialogHandle): bool =
  dialog.state.open

proc modal*(dialog: DialogHandle): bool =
  dialog.state.modal

proc closeCount*(dialog: DialogHandle): int =
  dialog.state.closeCount

proc cancelCount*(dialog: DialogHandle): int =
  dialog.state.cancelCount

proc showCount*(dialog: DialogHandle): int =
  dialog.state.showCount

proc activateFocusScope(dialog: DialogHandle) =
  if not dialog.state.modal or dialog.state.focusScopeActive:
    return
  dialog.state.previousFocusScope = dialog.root.tree.focusScopeRoot
  dialog.root.tree.setFocusScope(some(dialog.container.id))
  dialog.state.focusScopeActive = true

proc deactivateFocusScope(dialog: DialogHandle) =
  if not dialog.state.focusScopeActive:
    return
  if dialog.root.tree.focusScopeRoot == some(dialog.container.id):
    dialog.root.tree.setFocusScope(dialog.state.previousFocusScope)
  dialog.state.previousFocusScope = none(NodeId)
  dialog.state.focusScopeActive = false

proc initialFocusTarget(
    dialog: DialogHandle;
    requested: Option[NodeId]
): Option[NodeId] =
  if requested.isSome and
      dialog.root.tree.isDescendantOrSelf(requested.get, dialog.container.id) and
      dialog.root.tree.isFocusable(requested.get):
    return requested
  for target in dialog.root.focusTargets():
    if dialog.root.tree.isDescendantOrSelf(target, dialog.container.id):
      return some(target)
  if dialog.root.tree.isFocusable(dialog.container.id):
    return some(dialog.container.id)
  none(NodeId)

proc show*(dialog: DialogHandle): bool =
  if not dialog.container.valid() or dialog.state.open:
    return false
  dialog.state.open = true
  inc dialog.state.showCount
  dialog.syncVisibleState()
  dialog.activateFocusScope()
  discard dialog.container.emit(iekShow)
  true

proc show*(
    dialog: DialogHandle;
    interaction: var InteractionState;
    initialFocus = none(NodeId)
): bool =
  if dialog.state.open:
    return false
  dialog.state.restoreFocus = interaction.focusedTarget
  dialog.state.restoreFocusPending = true
  if not dialog.show():
    return false
  discard dialog.root.setFocus(
    interaction,
    dialog.initialFocusTarget(initialFocus),
    focusVisible = true
  )
  true

proc close*(dialog: DialogHandle): bool =
  if not dialog.container.valid() or not dialog.state.open:
    return false
  dialog.state.open = false
  inc dialog.state.closeCount
  dialog.syncVisibleState()
  dialog.deactivateFocusScope()
  if dialog.state.restoreFocusPending:
    let restore = dialog.state.restoreFocus
    let target =
      if restore.isSome and dialog.root.tree.isFocusable(restore.get): restore
      else: none(NodeId)
    dialog.root.requestFocus(target)
    dialog.state.restoreFocus = none(NodeId)
    dialog.state.restoreFocusPending = false
  discard dialog.container.emit(iekClose)
  true

proc close*(dialog: DialogHandle; interaction: var InteractionState): bool =
  if not dialog.close():
    return false
  discard dialog.root.reconcileFocus(interaction)
  true

proc cancel*(dialog: DialogHandle): bool =
  if not dialog.container.valid() or not dialog.state.open:
    return false
  inc dialog.state.cancelCount
  discard dialog.container.emit(iekCancel)
  discard dialog.close()
  true

proc cancel*(dialog: DialogHandle; interaction: var InteractionState): bool =
  if not dialog.container.valid() or not dialog.state.open:
    return false
  inc dialog.state.cancelCount
  discard dialog.container.emit(iekCancel)
  dialog.close(interaction)

proc setTitle*(dialog: DialogHandle; title: string) =
  if not dialog.container.valid():
    return
  dialog.state.title = title
  dialog.syncVisibleState()

proc setBody*(dialog: DialogHandle; body: string) =
  if not dialog.container.valid():
    return
  dialog.state.body = body
  dialog.syncVisibleState()

proc setModal*(dialog: DialogHandle; modal: bool) =
  if not dialog.container.valid() or dialog.state.modal == modal:
    return
  dialog.state.modal = modal
  if dialog.state.open and modal:
    dialog.activateFocusScope()
  elif not modal:
    dialog.deactivateFocusScope()

proc `onShow=`*(dialog: DialogHandle; handler: EventHandler) =
  dialog.container.onShow = handler

proc `onClose=`*(dialog: DialogHandle; handler: EventHandler) =
  dialog.container.onClose = handler

proc `onCancel=`*(dialog: DialogHandle; handler: EventHandler) =
  dialog.container.onCancel = handler

proc dialog*(
    root: UiRoot;
    params: DialogParams;
    style = UiStyle();
    titleStyle = UiStyle();
    bodyStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["dialog"]
): DialogHandle {.discardable.} =
  result.root = root
  result.state = DialogState(
    title: params.title,
    body: params.body,
    open: params.open,
    modal: params.modal,
    previousFocusScope: none(NodeId),
    restoreFocus: none(NodeId)
  )
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable(tabIndex = -1)
  result.container.setAccessibleRole(arDialog)
  result.titleNode = root.text(result.container, params.title, titleStyle, groups = ["dialog-title"])
  result.bodyNode = root.text(result.container, params.body, bodyStyle, groups = ["dialog-body"])
  result.syncVisibleState()
  if params.open:
    result.activateFocusScope()

  let dialog = result

  root.events.addInternalEventHandler(dialog.container.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if not dialog.state.open:
      return stoppedEvent()
    if event.event.key.isSome and event.event.key.get == "Escape":
      discard dialog.cancel()
      return stoppedEvent()
    ignoredEvent()
  )

proc dialog*(
    root: UiRoot;
    title = "";
    body = "";
    open = false;
    modal = false;
    style = UiStyle();
    titleStyle = UiStyle();
    bodyStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["dialog"]
): DialogHandle {.discardable.} =
  root.dialog(
    DialogParams(title: title, body: body, open: open, modal: modal),
    style = style,
    titleStyle = titleStyle,
    bodyStyle = bodyStyle,
    id = id,
    groups = groups
  )
