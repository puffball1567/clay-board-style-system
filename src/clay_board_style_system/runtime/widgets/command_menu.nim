import std/options

import ../../core/node
import ../../input/events
import ../ui_root

type
  CommandMenuItem* = object
    label*: string
    value*: string
    disabled*: bool

  CommandMenuParams* = object
    items*: seq[CommandMenuItem]
    open*: bool
    disabled*: bool

  CommandMenuState* = ref object
    items*: seq[CommandMenuItem]
    open*: bool
    disabled*: bool
    activeIndex*: int
    selectedValue*: string

  CommandMenuHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    itemNodes*: seq[NodeHandle]
    state*: CommandMenuState

proc isOpen*(menu: CommandMenuHandle): bool =
  menu.state.open

proc disabled*(menu: CommandMenuHandle): bool =
  menu.state.disabled

proc activeIndex*(menu: CommandMenuHandle): int =
  menu.state.activeIndex

proc selectedValue*(menu: CommandMenuHandle): string =
  menu.state.selectedValue

proc syncVisibleState(menu: CommandMenuHandle) =
  menu.container.setState(esActive, menu.state.open)
  menu.container.setState(esDisabled, menu.state.disabled or not menu.state.open)
  for index, node in menu.itemNodes:
    node.setState(esSelected, index == menu.state.activeIndex)
    node.setState(esDisabled, menu.state.items[index].disabled)

proc show*(menu: CommandMenuHandle): bool =
  if menu.state.disabled or menu.state.open:
    return false
  menu.state.open = true
  menu.syncVisibleState()
  discard menu.container.emit(iekShow)
  true

proc close*(menu: CommandMenuHandle): bool =
  if not menu.state.open:
    return false
  menu.state.open = false
  menu.syncVisibleState()
  discard menu.container.emit(iekClose)
  true

proc setDisabled*(menu: CommandMenuHandle; disabled: bool) =
  menu.state.disabled = disabled
  if disabled:
    menu.state.open = false
  menu.syncVisibleState()

proc setActiveIndex*(menu: CommandMenuHandle; index: int) =
  if menu.state.disabled or index < 0 or index >= menu.state.items.len:
    return
  if menu.state.items[index].disabled:
    return
  menu.state.activeIndex = index
  menu.syncVisibleState()

proc nextEnabledIndex(menu: CommandMenuHandle; direction: int): int =
  if menu.state.items.len == 0:
    return -1
  var index = menu.state.activeIndex
  for _ in 0 ..< menu.state.items.len:
    index += direction
    if index < 0:
      index = menu.state.items.high
    elif index > menu.state.items.high:
      index = 0
    if not menu.state.items[index].disabled:
      return index
  -1

proc activate*(menu: CommandMenuHandle): bool =
  if menu.state.disabled or not menu.state.open:
    return false
  let index = menu.state.activeIndex
  if index < 0 or index >= menu.state.items.len or menu.state.items[index].disabled:
    return false
  menu.state.selectedValue = menu.state.items[index].value
  discard menu.container.emit(inputEvent(menu.state.selectedValue))
  discard menu.container.emit(changeEvent(menu.state.selectedValue))
  discard menu.close()
  true

proc `onShow=`*(menu: CommandMenuHandle; handler: EventHandler) =
  menu.container.onShow = handler

proc `onClose=`*(menu: CommandMenuHandle; handler: EventHandler) =
  menu.container.onClose = handler

proc `onInput=`*(menu: CommandMenuHandle; handler: EventHandler) =
  menu.container.onInput = handler

proc `onChange=`*(menu: CommandMenuHandle; handler: EventHandler) =
  menu.container.onChange = handler

proc commandMenuItemClickHandler(menu: CommandMenuHandle; itemIndex: int): EventHandler =
  proc(event: DispatchResult): EventOutcome =
    if menu.state.disabled or not menu.state.open:
      return stoppedEvent()
    if itemIndex < 0 or itemIndex >= menu.state.items.len:
      return stoppedEvent()
    if menu.state.items[itemIndex].disabled:
      return stoppedEvent()
    menu.setActiveIndex(itemIndex)
    discard menu.activate()
    stoppedEvent()

proc commandMenu*(
    root: UiRoot;
    params: CommandMenuParams;
    style = UiStyle();
    itemStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["command-menu"]
): CommandMenuHandle {.discardable.} =
  result.root = root
  result.state = CommandMenuState(
    items: params.items,
    open: params.open,
    disabled: params.disabled,
    activeIndex: if params.items.len > 0: 0 else: -1
  )
  if result.state.activeIndex >= 0 and result.state.items[result.state.activeIndex].disabled:
    result.state.activeIndex = -1

  result.container = root.box(style, id = id, groups = groups)
  for item in result.state.items:
    result.itemNodes.add root.text(result.container, item.label, itemStyle, groups = ["command-menu-item"])

  result.syncVisibleState()
  let menu = result

  for index, node in menu.itemNodes:
    root.events.addInternalEventHandler(node.id, iekClick, commandMenuItemClickHandler(menu, index))

  root.events.addInternalEventHandler(menu.container.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if menu.state.disabled or not menu.state.open:
      return stoppedEvent()
    if event.event.key.isNone:
      return ignoredEvent()
    case event.event.key.get
    of "ArrowDown":
      menu.setActiveIndex(menu.nextEnabledIndex(1))
      return stoppedEvent()
    of "ArrowUp":
      menu.setActiveIndex(menu.nextEnabledIndex(-1))
      return stoppedEvent()
    of "Enter", " ":
      discard menu.activate()
      return stoppedEvent()
    of "Escape":
      discard menu.close()
      return stoppedEvent()
    else:
      discard
    ignoredEvent()
  )

proc commandMenu*(
    root: UiRoot;
    items: openArray[CommandMenuItem];
    open = false;
    disabled = false;
    style = UiStyle();
    itemStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["command-menu"]
): CommandMenuHandle {.discardable.} =
  root.commandMenu(
    CommandMenuParams(items: @items, open: open, disabled: disabled),
    style = style,
    itemStyle = itemStyle,
    id = id,
    groups = groups
  )
