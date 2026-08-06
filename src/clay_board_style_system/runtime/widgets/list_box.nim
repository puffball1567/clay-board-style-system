import std/options

import ../../core/node
import ../../input/events
import ../ui_root

type
  ListItem* = object
    label*: string
    value*: string
    disabled*: bool

  ListBoxParams* = object
    items*: seq[ListItem]
    selectedValue*: string
    disabled*: bool

  ListBoxState* = ref object
    items*: seq[ListItem]
    selectedIndex*: int
    disabled*: bool

  ListBoxHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    itemNodes*: seq[NodeHandle]
    state*: ListBoxState

proc selectedIndexFor(params: ListBoxParams): int =
  for index, item in params.items:
    if item.value == params.selectedValue:
      return index
  if params.items.len > 0: 0
  else: -1

proc selectedIndex*(listBox: ListBoxHandle): int =
  listBox.state.selectedIndex

proc selectedValue*(listBox: ListBoxHandle): string =
  if listBox.state.selectedIndex >= 0 and listBox.state.selectedIndex < listBox.state.items.len:
    listBox.state.items[listBox.state.selectedIndex].value
  else:
    ""

proc disabled*(listBox: ListBoxHandle): bool =
  listBox.state.disabled

proc syncVisibleState(listBox: ListBoxHandle) =
  listBox.container.setState(esDisabled, listBox.state.disabled)
  listBox.container.setAccessibleValue(listBox.selectedValue())
  for index, node in listBox.itemNodes:
    node.setState(esSelected, index == listBox.state.selectedIndex)
    node.setState(esDisabled, listBox.state.items[index].disabled)

proc emitValueEvents(listBox: ListBoxHandle) =
  discard listBox.container.emit(inputEvent(listBox.selectedValue()))
  discard listBox.container.emit(changeEvent(listBox.selectedValue()))

proc setSelectedIndex*(listBox: ListBoxHandle; index: int; emitEvents = false) =
  if listBox.state.disabled or index < 0 or index >= listBox.state.items.len:
    return
  if listBox.state.items[index].disabled or listBox.state.selectedIndex == index:
    return
  listBox.state.selectedIndex = index
  listBox.syncVisibleState()
  if emitEvents:
    listBox.emitValueEvents()

proc setSelectedValue*(listBox: ListBoxHandle; value: string; emitEvents = false) =
  for index, item in listBox.state.items:
    if item.value == value:
      listBox.setSelectedIndex(index, emitEvents = emitEvents)
      return

proc setDisabled*(listBox: ListBoxHandle; disabled: bool) =
  listBox.state.disabled = disabled
  listBox.syncVisibleState()

proc nextEnabledIndex(listBox: ListBoxHandle; direction: int): int =
  if listBox.state.items.len == 0:
    return -1
  var index = listBox.state.selectedIndex
  for _ in 0 ..< listBox.state.items.len:
    index += direction
    if index < 0:
      index = listBox.state.items.high
    elif index > listBox.state.items.high:
      index = 0
    if not listBox.state.items[index].disabled:
      return index
  -1

proc selectNext*(listBox: ListBoxHandle; emitEvents = true) =
  let index = listBox.nextEnabledIndex(1)
  if index >= 0:
    listBox.setSelectedIndex(index, emitEvents = emitEvents)

proc selectPrevious*(listBox: ListBoxHandle; emitEvents = true) =
  let index = listBox.nextEnabledIndex(-1)
  if index >= 0:
    listBox.setSelectedIndex(index, emitEvents = emitEvents)

proc `onChange=`*(listBox: ListBoxHandle; handler: EventHandler) =
  listBox.container.onChange = handler

proc `onInput=`*(listBox: ListBoxHandle; handler: EventHandler) =
  listBox.container.onInput = handler

proc itemClickHandler(listBox: ListBoxHandle; itemIndex: int): EventHandler =
  proc(event: DispatchResult): EventOutcome =
    if listBox.state.disabled:
      return true
    listBox.setSelectedIndex(itemIndex, emitEvents = true)
    true

proc listBox*(
    root: UiRoot;
    params: ListBoxParams;
    style = UiStyle();
    itemStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["list-box"]
): ListBoxHandle {.discardable.} =
  result.root = root
  result.state = ListBoxState(
    items: params.items,
    selectedIndex: params.selectedIndexFor(),
    disabled: params.disabled
  )
  if result.state.selectedIndex >= 0 and result.state.items[result.state.selectedIndex].disabled:
    result.state.selectedIndex = -1

  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arListBox)
  for item in result.state.items:
    let itemNode = root.text(result.container, item.label, itemStyle, groups = ["list-item"])
    itemNode.setAccessibleRole(arListItem)
    itemNode.setAccessibleName(item.label)
    itemNode.setAccessibleValue(item.value)
    result.itemNodes.add itemNode

  result.syncVisibleState()
  let listBox = result

  for index, node in listBox.itemNodes:
    root.events.addInternalEventHandler(node.id, iekClick, itemClickHandler(listBox, index))

  root.events.addInternalEventHandler(listBox.container.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if listBox.state.disabled:
      return true
    if event.event.key.isNone:
      return false
    case event.event.key.get
    of "ArrowDown":
      listBox.selectNext()
      return true
    of "ArrowUp":
      listBox.selectPrevious()
      return true
    of "Home":
      for index, item in listBox.state.items:
        if not item.disabled:
          listBox.setSelectedIndex(index, emitEvents = true)
          return true
      return true
    of "End":
      for index in countdown(listBox.state.items.high, 0):
        if not listBox.state.items[index].disabled:
          listBox.setSelectedIndex(index, emitEvents = true)
          return true
      return true
    else:
      discard
    false
  )

proc listBox*(
    root: UiRoot;
    items: openArray[ListItem];
    selectedValue = "";
    disabled = false;
    style = UiStyle();
    itemStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["list-box"]
): ListBoxHandle {.discardable.} =
  root.listBox(
    ListBoxParams(items: @items, selectedValue: selectedValue, disabled: disabled),
    style = style,
    itemStyle = itemStyle,
    id = id,
    groups = groups
  )
