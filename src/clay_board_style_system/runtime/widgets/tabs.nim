import std/options

import ../../core/node
import ../../input/events
import ../ui_root

type
  TabItem* = object
    label*: string
    value*: string
    disabled*: bool

  TabsParams* = object
    items*: seq[TabItem]
    selectedValue*: string
    disabled*: bool

  TabsState* = ref object
    items*: seq[TabItem]
    selectedIndex*: int
    disabled*: bool

  TabsHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    tabNodes*: seq[NodeHandle]
    state*: TabsState

proc selectedIndexFor(params: TabsParams): int =
  for index, item in params.items:
    if item.value == params.selectedValue:
      return index
  if params.items.len > 0: 0
  else: -1

proc selectedIndex*(tabs: TabsHandle): int =
  tabs.state.selectedIndex

proc selectedValue*(tabs: TabsHandle): string =
  if tabs.state.selectedIndex >= 0 and tabs.state.selectedIndex < tabs.state.items.len:
    tabs.state.items[tabs.state.selectedIndex].value
  else:
    ""

proc disabled*(tabs: TabsHandle): bool =
  tabs.state.disabled

proc syncVisibleState(tabs: TabsHandle) =
  tabs.container.setState(esDisabled, tabs.state.disabled)
  tabs.container.setAccessibleValue(tabs.selectedValue())
  for index, node in tabs.tabNodes:
    node.setState(esSelected, index == tabs.state.selectedIndex)
    node.setState(esDisabled, tabs.state.items[index].disabled)

proc emitValueEvents(tabs: TabsHandle) =
  discard tabs.container.emit(inputEvent(tabs.selectedValue()))
  discard tabs.container.emit(changeEvent(tabs.selectedValue()))

proc setSelectedIndex*(tabs: TabsHandle; index: int; emitEvents = false) =
  if tabs.state.disabled or index < 0 or index >= tabs.state.items.len:
    return
  if tabs.state.items[index].disabled or tabs.state.selectedIndex == index:
    return
  tabs.state.selectedIndex = index
  tabs.syncVisibleState()
  if emitEvents:
    tabs.emitValueEvents()

proc setSelectedValue*(tabs: TabsHandle; value: string; emitEvents = false) =
  for index, item in tabs.state.items:
    if item.value == value:
      tabs.setSelectedIndex(index, emitEvents = emitEvents)
      return

proc setDisabled*(tabs: TabsHandle; disabled: bool) =
  tabs.state.disabled = disabled
  tabs.syncVisibleState()

proc nextEnabledIndex(tabs: TabsHandle; direction: int): int =
  if tabs.state.items.len == 0:
    return -1
  var index = tabs.state.selectedIndex
  for _ in 0 ..< tabs.state.items.len:
    index += direction
    if index < 0:
      index = tabs.state.items.high
    elif index > tabs.state.items.high:
      index = 0
    if not tabs.state.items[index].disabled:
      return index
  -1

proc selectNext*(tabs: TabsHandle; emitEvents = true) =
  let index = tabs.nextEnabledIndex(1)
  if index >= 0:
    tabs.setSelectedIndex(index, emitEvents = emitEvents)

proc selectPrevious*(tabs: TabsHandle; emitEvents = true) =
  let index = tabs.nextEnabledIndex(-1)
  if index >= 0:
    tabs.setSelectedIndex(index, emitEvents = emitEvents)

proc `onChange=`*(tabs: TabsHandle; handler: EventHandler) =
  tabs.container.onChange = handler

proc `onInput=`*(tabs: TabsHandle; handler: EventHandler) =
  tabs.container.onInput = handler

proc tabClickHandler(tabs: TabsHandle; tabIndex: int): EventHandler =
  proc(event: DispatchResult): EventOutcome =
    if tabs.state.disabled:
      return stoppedEvent()
    tabs.setSelectedIndex(tabIndex, emitEvents = true)
    stoppedEvent()

proc tabs*(
    root: UiRoot;
    params: TabsParams;
    style = UiStyle();
    tabStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["tabs"];
    tabGroups: openArray[string] = ["tab"]
): TabsHandle {.discardable.} =
  result.root = root
  result.state = TabsState(
    items: params.items,
    selectedIndex: params.selectedIndexFor(),
    disabled: params.disabled
  )
  if result.state.selectedIndex >= 0 and result.state.items[result.state.selectedIndex].disabled:
    result.state.selectedIndex = -1

  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arTabList)
  for item in result.state.items:
    let tabNode = root.text(result.container, item.label, tabStyle, groups = tabGroups)
    tabNode.setAccessibleRole(arTab)
    tabNode.setAccessibleName(item.label)
    tabNode.setAccessibleValue(item.value)
    result.tabNodes.add tabNode

  result.syncVisibleState()
  let tabs = result

  for index, node in tabs.tabNodes:
    root.events.addInternalEventHandler(node.id, iekClick, tabClickHandler(tabs, index))

  root.events.addInternalEventHandler(tabs.container.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if tabs.state.disabled:
      return stoppedEvent()
    if event.event.key.isNone:
      return ignoredEvent()
    case event.event.key.get
    of "ArrowRight", "ArrowDown":
      tabs.selectNext()
      return stoppedEvent()
    of "ArrowLeft", "ArrowUp":
      tabs.selectPrevious()
      return stoppedEvent()
    else:
      discard
    ignoredEvent()
  )

proc tabs*(
    root: UiRoot;
    items: openArray[TabItem];
    selectedValue = "";
    disabled = false;
    style = UiStyle();
    tabStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["tabs"];
    tabGroups: openArray[string] = ["tab"]
): TabsHandle {.discardable.} =
  root.tabs(
    TabsParams(items: @items, selectedValue: selectedValue, disabled: disabled),
    style = style,
    tabStyle = tabStyle,
    id = id,
    groups = groups,
    tabGroups = tabGroups
  )
