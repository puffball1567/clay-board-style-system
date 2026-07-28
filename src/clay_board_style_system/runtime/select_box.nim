import std/options

import ../core/[declaration, node, style_value]
import ../input/events
import ./ui_root

type
  SelectOption* = object
    label*: string
    value*: string
    disabled*: bool

  SelectParams* = object
    options*: seq[SelectOption]
    selectedValue*: string
    placeholder*: string
    disabled*: bool

  SelectState* = ref object
    options*: seq[SelectOption]
    selectedIndex*: int
    placeholder*: string
    disabled*: bool
    open*: bool

  SelectHandle* = object
    root*: UiRoot
    container*: NodeHandle
    valueNode*: NodeHandle
    panelNode*: NodeHandle
    optionNodes*: seq[NodeHandle]
    state*: SelectState

proc selectedLabel(select: SelectHandle): string =
  if select.state.selectedIndex >= 0 and select.state.selectedIndex < select.state.options.len:
    select.state.options[select.state.selectedIndex].label
  else:
    select.state.placeholder

proc selectedValue*(select: SelectHandle): string =
  if select.state.selectedIndex >= 0 and select.state.selectedIndex < select.state.options.len:
    select.state.options[select.state.selectedIndex].value
  else:
    ""

proc selectedIndex*(select: SelectHandle): int =
  select.state.selectedIndex

proc isOpen*(select: SelectHandle): bool =
  select.state.open

proc disabled*(select: SelectHandle): bool =
  select.state.disabled

proc syncVisibleState(select: SelectHandle) =
  select.root.tree.setAttribute(select.container.id, "value", select.selectedValue())
  select.root.tree.setAttribute(select.container.id, "placeholder", select.state.placeholder)
  select.root.tree.nodes[select.valueNode.id.nodeIndex].text = select.selectedLabel()
  select.container.setAccessibleValue(select.selectedLabel())
  select.container.setState(esOpen, select.state.open)
  select.container.setState(esDisabled, select.state.disabled)
  for index, node in select.optionNodes:
    node.setAccessibleHidden(not select.state.open)
    node.setState(esOpen, select.state.open)
    node.setState(esSelected, index == select.state.selectedIndex)
    node.setState(esDisabled, select.state.options[index].disabled)
  select.panelNode.setState(esOpen, select.state.open)

proc emitValueEvents(select: SelectHandle) =
  discard select.container.emit(inputEvent(select.selectedValue()))
  discard select.container.emit(changeEvent(select.selectedValue()))

proc setOpen*(select: SelectHandle; open: bool; emitToggle = false) =
  if select.state.disabled or select.state.open == open:
    return
  select.state.open = open
  select.syncVisibleState()
  if emitToggle:
    discard select.container.emit(iekToggle)

proc toggleOpen*(select: SelectHandle; emitToggle = true) =
  select.setOpen(not select.state.open, emitToggle = emitToggle)

proc setDisabled*(select: SelectHandle; disabled: bool) =
  select.state.disabled = disabled
  select.syncVisibleState()

proc setSelectedIndex*(select: SelectHandle; index: int; emitEvents = false) =
  if select.state.disabled or index < 0 or index >= select.state.options.len:
    return
  if select.state.options[index].disabled or select.state.selectedIndex == index:
    return
  select.state.selectedIndex = index
  select.syncVisibleState()
  if emitEvents:
    select.emitValueEvents()

proc setSelectedValue*(select: SelectHandle; value: string; emitEvents = false) =
  for index, option in select.state.options:
    if option.value == value:
      select.setSelectedIndex(index, emitEvents = emitEvents)
      return

proc nextEnabledIndex(select: SelectHandle; direction: int): int =
  if select.state.options.len == 0:
    return -1
  var index = select.state.selectedIndex
  for _ in 0 ..< select.state.options.len:
    index += direction
    if index < 0:
      index = select.state.options.high
    elif index > select.state.options.high:
      index = 0
    if not select.state.options[index].disabled:
      return index
  -1

proc selectNext*(select: SelectHandle; emitEvents = true) =
  let index = select.nextEnabledIndex(1)
  if index >= 0:
    select.setSelectedIndex(index, emitEvents = emitEvents)

proc selectPrevious*(select: SelectHandle; emitEvents = true) =
  let index = select.nextEnabledIndex(-1)
  if index >= 0:
    select.setSelectedIndex(index, emitEvents = emitEvents)

proc `onChange=`*(select: SelectHandle; handler: EventHandler) =
  select.container.onChange = handler

proc `onInput=`*(select: SelectHandle; handler: EventHandler) =
  select.container.onInput = handler

proc `onClick=`*(select: SelectHandle; handler: EventHandler) =
  select.container.onClick = handler

proc `onToggle=`*(select: SelectHandle; handler: EventHandler) =
  select.container.onToggle = handler

proc selectedIndexFor(params: SelectParams): int =
  for index, option in params.options:
    if option.value == params.selectedValue:
      return index
  -1

proc containsTarget(select: SelectHandle; target: Option[NodeId]): bool =
  var current = target
  while current.isSome:
    let id = current.get
    if id == select.container.id or id == select.panelNode.id:
      return true
    for node in select.optionNodes:
      if id == node.id:
        return true
    if id.nodeIndex < 0 or id.nodeIndex >= select.root.tree.nodes.len:
      return false
    current = select.root.tree.nodes[id.nodeIndex].parent
  false

proc optionClickHandler(select: SelectHandle; optionIndex: int): EventHandler =
  proc(event: DispatchResult): bool =
    if select.state.disabled:
      return true
    if optionIndex < 0 or optionIndex >= select.state.options.len:
      return true
    if select.state.options[optionIndex].disabled:
      return true
    select.setSelectedIndex(optionIndex, emitEvents = true)
    select.setOpen(false, emitToggle = true)
    true

proc selectBox*(
    root: UiRoot;
    params: SelectParams;
    style = UiStyle();
    valueStyle = UiStyle();
    panelStyle = UiStyle();
    optionStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["select"]
): SelectHandle {.discardable.} =
  result.root = root
  result.state = SelectState(
    options: params.options,
    selectedIndex: params.selectedIndexFor(),
    placeholder: params.placeholder,
    disabled: params.disabled
  )
  if result.state.selectedIndex >= 0 and result.state.options[result.state.selectedIndex].disabled:
    result.state.selectedIndex = -1

  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arComboBox)
  result.container.applyStateStyle({esOpen}, uiStyle([
    decl("z-index", number(100))
  ]), priority = 100)
  result.valueNode = root.text(result.container, result.selectedLabel(), valueStyle, groups = ["select-value"])
  result.valueNode.applyStyle(uiStyle([
    decl("pointer-events", keyword("none"))
  ]))
  result.panelNode = root.box(panelStyle, parent = some(result.container), groups = ["select-panel"])
  result.panelNode.applyStyle(uiStyle([
    decl("display", keyword("none")),
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(30)),
    decl("z-index", number(101)),
    decl("gap", px(0))
  ]))
  result.panelNode.applyStateStyle({esOpen}, uiStyle([
    decl("display", keyword("flex"))
  ]), priority = 100)
  for index, option in result.state.options:
    let optionNode = root.box(optionStyle, parent = some(result.panelNode), groups = ["select-option"])
    optionNode.setAccessibleRole(arOption)
    optionNode.setAccessibleName(option.label)
    optionNode.setAccessibleValue(option.value)
    optionNode.applyStyle(uiStyle([
      decl("z-index", number(102 + index))
    ]))
    let labelNode = root.text(optionNode, option.label, groups = ["select-option-label"])
    labelNode.applyStyle(uiStyle([
      decl("pointer-events", keyword("none"))
    ]))
    optionNode.setState(esSelected, index == result.state.selectedIndex)
    optionNode.setState(esDisabled, option.disabled)
    result.optionNodes.add optionNode

  result.syncVisibleState()
  let select = result

  root.registerPopupCloser(proc(target: Option[NodeId]): bool =
    if not select.state.open:
      return false
    if select.containsTarget(target):
      return false
    select.setOpen(false, emitToggle = true)
    true
  )

  root.events.addInternalEventHandler(select.container.id, iekClick, proc(event: DispatchResult): bool =
    if select.state.disabled:
      return true
    if event.event.position.isSome:
      return true
    select.toggleOpen()
    false
  )
  root.events.addInternalEventHandler(select.container.id, iekPointerDown, proc(event: DispatchResult): bool =
    if select.state.disabled:
      return true
    select.toggleOpen()
    true
  )
  root.events.addInternalEventHandler(select.container.id, iekBlur, proc(event: DispatchResult): bool =
    select.setOpen(false, emitToggle = true)
    false
  )
  root.events.addInternalEventHandler(select.container.id, iekKeyDown, proc(event: DispatchResult): bool =
    if select.state.disabled:
      return true
    if event.event.key.isNone:
      return false
    case event.event.key.get
    of "ArrowDown":
      select.selectNext()
      return true
    of "ArrowUp":
      select.selectPrevious()
      return true
    of "Enter", " ":
      select.toggleOpen()
      return true
    of "Escape":
      select.setOpen(false, emitToggle = true)
      return true
    else:
      discard
    false
  )

  for index, optionNode in select.optionNodes:
    root.events.addInternalEventHandler(optionNode.id, iekPointerDown, optionClickHandler(select, index))
    root.events.addInternalEventHandler(optionNode.id, iekClick, optionClickHandler(select, index))

proc selectBox*(
    root: UiRoot;
    options: openArray[SelectOption];
    selectedValue = "";
    placeholder = "";
    disabled = false;
    style = UiStyle();
    valueStyle = UiStyle();
    panelStyle = UiStyle();
    optionStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["select"]
): SelectHandle {.discardable.} =
  root.selectBox(
    SelectParams(
      options: @options,
      selectedValue: selectedValue,
      placeholder: placeholder,
      disabled: disabled
    ),
    style = style,
    valueStyle = valueStyle,
    panelStyle = panelStyle,
    optionStyle = optionStyle,
    id = id,
    groups = groups
  )
