import std/[hashes, math, options, tables]

import ../core/[color, declaration, geometry, node, rule, selector, style_value]
import ../input/events
import ../layout/scroll_state
import ../text/[font_registry, text_engine]

type
  DisabledSetter* = proc(disabled: bool) {.closure.}
  FieldsetRegister* = proc(setter: DisabledSetter) {.closure.}
  ClipboardTextProvider* = proc(): string {.closure.}
  ClipboardTextWriter* = proc(text: string) {.closure.}
  PopupCloser* = proc(target: Option[NodeId]): bool {.closure.}

  ContextMenuAction* = enum
    cmaCut,
    cmaCopy,
    cmaPaste,
    cmaDelete,
    cmaSelectAll

  ContextMenuItem* = object
    label*: string
    action*: ContextMenuAction
    disabled*: bool

  UiStyle* = object
    declarations*: seq[Declaration]

  AppliedStyleKey = object
    nodeIndex: int
    states: set[ElementState]
    priority: int

  UiRoot* = ref object
    tree*: Tree
    events*: EventRegistry
    componentStyles*: seq[StyleSheet]
    appliedStyleIndices: Table[AppliedStyleKey, int]
    textEngine*: TextEngine
    fonts*: FontRegistry
    scroll*: ScrollState
    defaultContextMenuOpen*: bool
    defaultContextMenuPosition*: Vec2
    defaultContextMenuTarget*: Option[NodeId]
    defaultContextMenuNode*: Option[NodeId]
    defaultContextMenuItems*: seq[ContextMenuItem]
    defaultContextMenuItemNodes*: seq[NodeId]
    defaultContextMenuStyleIndex*: Option[int]
    clipboardTextProvider*: ClipboardTextProvider
    clipboardTextWriter*: ClipboardTextWriter
    clipboardTextCache: string
    clipboardTextCached: bool
    popupClosers*: seq[PopupCloser]
    focusRequestPending*: bool
    focusRequestTarget*: Option[NodeId]
    parentStack: seq[NodeId]
    fieldsetStack: seq[FieldsetRegister]

  NodeHandle* = object
    ## Non-owning: UiRoot owns the event registry, whose closures may capture
    ## handles. ARC must not retain the root through that back-reference.
    root* {.cursor.}: UiRoot
    id*: NodeId

proc initUiRoot*(): UiRoot =
  UiRoot(
    tree: initTree(),
    events: initEventRegistry(),
    componentStyles: @[],
    appliedStyleIndices: initTable[AppliedStyleKey, int](),
    textEngine: debugTextEngine(),
    fonts: initFontRegistry(),
    scroll: initScrollState(),
    defaultContextMenuPosition: vec2(0, 0),
    defaultContextMenuTarget: none(NodeId),
    defaultContextMenuNode: none(NodeId),
    defaultContextMenuItems: @[],
    defaultContextMenuItemNodes: @[],
    defaultContextMenuStyleIndex: none(int),
    clipboardTextProvider: proc(): string = "",
    clipboardTextWriter: proc(text: string) = discard,
    clipboardTextCache: "",
    clipboardTextCached: false,
    popupClosers: @[],
    focusRequestPending: false,
    focusRequestTarget: none(NodeId),
    parentStack: @[],
    fieldsetStack: @[]
  )

proc requestFocus*(root: UiRoot; target: Option[NodeId]) =
  ## Event handlers do not own InteractionState. Queue one deterministic focus
  ## transfer for the host to reconcile after the current event batch.
  root.focusRequestPending = true
  root.focusRequestTarget = target

proc takeFocusRequest*(root: UiRoot): tuple[pending: bool, target: Option[NodeId]] =
  result = (root.focusRequestPending, root.focusRequestTarget)
  root.focusRequestPending = false
  root.focusRequestTarget = none(NodeId)

proc configureTextLayout*(root: UiRoot; engine: TextEngine; fonts: FontRegistry) =
  root.textEngine = engine
  root.fonts = fonts

proc configureClipboardTextProvider*(root: UiRoot; provider: ClipboardTextProvider) =
  root.clipboardTextProvider = provider
  root.clipboardTextCache = ""
  root.clipboardTextCached = false

proc configureClipboardTextWriter*(root: UiRoot; writer: ClipboardTextWriter) =
  root.clipboardTextWriter = writer

proc invalidateClipboardText*(root: UiRoot) =
  ## Call this when the host knows an external clipboard owner may have changed.
  root.clipboardTextCache = ""
  root.clipboardTextCached = false

proc clipboardText*(root: UiRoot): string =
  ## Clipboard reads may synchronously contact an external Wayland/X11 owner.
  ## Cache one bounded snapshot until the host invalidates it, so repeated paste
  ## requests never turn into repeated platform round trips.
  if not root.clipboardTextCached:
    let event = pasteEvent(root.clipboardTextProvider())
    root.clipboardTextCache =
      if event.text.isSome: event.text.get
      else: ""
    root.clipboardTextCached = true
  root.clipboardTextCache

proc writeClipboardText*(root: UiRoot; text: string) =
  ## Keep the in-process snapshot coherent before delegating to the host. Hosts
  ## may defer the actual platform write without changing copy/paste semantics.
  let event = pasteEvent(text)
  root.clipboardTextCache =
    if event.text.isSome: event.text.get
    else: ""
  root.clipboardTextCached = true
  if root.clipboardTextCache.len > 0:
    root.clipboardTextWriter(root.clipboardTextCache)

proc registerPopupCloser*(root: UiRoot; closer: PopupCloser) =
  root.popupClosers.add closer

proc closeOpenPopups*(root: UiRoot; target: Option[NodeId]): bool =
  for closer in root.popupClosers:
    if closer(target):
      result = true

proc uiStyle*(declarations: openArray[Declaration]): UiStyle =
  UiStyle(declarations: @declarations)

proc `+`*(a, b: UiStyle): UiStyle =
  UiStyle(declarations: a.declarations & b.declarations)

proc hash(key: AppliedStyleKey): Hash =
  result = hash(key.nodeIndex)
  result = result !& hash(key.priority)
  result = result !& hash(cast[uint8](key.states))
  result = !$result

proc mergeStyleDeclarations(existing, updates: openArray[Declaration]): seq[Declaration] =
  ## `applyStyle` is incremental authoring API. Keep earlier declarations for
  ## other properties while replacing the last declaration for each update.
  result = @existing
  for update in updates:
    var replacementIndex = -1
    if result.len > 0:
      for index in countdown(result.high, 0):
        if result[index].property == update.property:
          replacementIndex = index
          break
    if replacementIndex >= 0:
      result[replacementIndex] = update
    else:
      result.add update

proc nodeId*(handle: NodeHandle): NodeId =
  handle.id

proc setCode*(handle: NodeHandle; code: string) =
  handle.root.tree.nodes[handle.id.nodeIndex].code = code

proc addStyle*(root: UiRoot; sheet: StyleSheet) =
  root.componentStyles.add sheet

proc addStyles*(root: UiRoot; sheets: openArray[StyleSheet]) =
  for sheet in sheets:
    root.addStyle(sheet)

proc setNodeStyle*(
    root: UiRoot;
    node: NodeId;
    style: UiStyle;
    states: set[ElementState] = {};
    priority = 0
) =
  ## Replaces a prior style for the same node/state slot instead of retaining
  ## stale sheets after interactive updates.
  let key = AppliedStyleKey(
    nodeIndex: node.nodeIndex,
    states: states,
    priority: priority
  )
  var selector = target(node)
  selector.requiredStates = selector.requiredStates + states
  if key in root.appliedStyleIndices:
    let index = root.appliedStyleIndices[key]
    if index >= 0 and index < root.componentStyles.len:
      let declarations = mergeStyleDeclarations(
        root.componentStyles[index].rules[0].declarations,
        style.declarations
      )
      root.componentStyles[index] = styleSheet([rule(selector, declarations, priority = priority)])
      return
  let sheet = styleSheet([rule(selector, style.declarations, priority = priority)])
  root.componentStyles.add sheet
  root.appliedStyleIndices[key] = root.componentStyles.len - 1

proc applyStyle*(root: UiRoot; handle: NodeHandle; style: UiStyle) =
  if style.declarations.len > 0:
    root.setNodeStyle(handle.id, style)

proc applyStateStyle*(
    root: UiRoot;
    handle: NodeHandle;
    states: set[ElementState];
    style: UiStyle;
    priority = 0
) =
  if style.declarations.len > 0:
    root.setNodeStyle(handle.id, style, states, priority)

proc applyHoverStyle*(root: UiRoot; handle: NodeHandle; style: UiStyle; priority = 0) =
  root.applyStateStyle(handle, {esHover}, style, priority = priority)

proc applyActiveStyle*(root: UiRoot; handle: NodeHandle; style: UiStyle; priority = 0) =
  root.applyStateStyle(handle, {esActive}, style, priority = priority)

proc applyFocusStyle*(root: UiRoot; handle: NodeHandle; style: UiStyle; priority = 0) =
  root.applyStateStyle(handle, {esFocus}, style, priority = priority)

proc applyFocusVisibleStyle*(root: UiRoot; handle: NodeHandle; style: UiStyle; priority = 0) =
  root.applyStateStyle(handle, {esFocusVisible}, style, priority = priority)

proc defaultContextMenuItems*(): seq[ContextMenuItem] =
  @[
    ContextMenuItem(label: "Cut", action: cmaCut),
    ContextMenuItem(label: "Copy", action: cmaCopy),
    ContextMenuItem(label: "Paste", action: cmaPaste),
    ContextMenuItem(label: "Delete", action: cmaDelete),
    ContextMenuItem(label: "Select All", action: cmaSelectAll)
  ]

const
  defaultContextMenuWidth = 156.0'f32
  defaultContextMenuPadding = 5.0'f32
  defaultContextMenuItemHeight = 26.0'f32
  defaultContextMenuItemGap = 2.0'f32

proc defaultContextMenuPanelStyle(root: UiRoot): UiStyle =
  uiStyle([
    decl("display", keyword(if root.defaultContextMenuOpen: "flex" else: "none")),
    decl("position", keyword("absolute")),
    decl("left", px(root.defaultContextMenuPosition.x)),
    decl("top", px(root.defaultContextMenuPosition.y)),
    decl("width", px(defaultContextMenuWidth)),
    decl("padding", px(5)),
    decl("gap", px(2)),
    decl("background-color", colorValue(rgb(0.11, 0.12, 0.14))),
    decl("border-color", colorValue(rgb(0.31, 0.36, 0.43))),
    decl("border-width", px(1)),
    decl("border-radius", px(5)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(10),
      blur = some(px(20)),
      spread = some(px(-4)),
      shadowColor = some(rgba(0, 0, 0, 0.42))
    )),
    decl("z-index", number(5000))
  ])

proc syncDefaultContextMenuStyle*(root: UiRoot) =
  if root.defaultContextMenuNode.isNone:
    return
  let sheet = styleSheet([
    rule(target(root.defaultContextMenuNode.get), root.defaultContextMenuPanelStyle().declarations, priority = 5000)
  ])
  if root.defaultContextMenuStyleIndex.isSome and root.defaultContextMenuStyleIndex.get < root.componentStyles.len:
    root.componentStyles[root.defaultContextMenuStyleIndex.get] = sheet
  else:
    root.componentStyles.add sheet
    root.defaultContextMenuStyleIndex = some(root.componentStyles.len - 1)

proc closeDefaultContextMenu*(root: UiRoot): bool =
  if not root.defaultContextMenuOpen:
    return false
  root.defaultContextMenuOpen = false
  root.defaultContextMenuTarget = none(NodeId)
  root.syncDefaultContextMenuStyle()
  true

proc showDefaultContextMenu*(root: UiRoot; target: Option[NodeId]; position: Vec2): bool =
  if root.defaultContextMenuNode.isNone or target.isNone:
    return false
  root.defaultContextMenuOpen = true
  root.defaultContextMenuTarget = target
  root.defaultContextMenuPosition = position
  root.syncDefaultContextMenuStyle()
  true

proc styleSheets*(root: UiRoot; externalStyles: openArray[StyleSheet] = []): seq[StyleSheet] =
  for sheet in externalStyles:
    result.add sheet
  for sheet in root.componentStyles:
    result.add sheet

proc currentParent(root: UiRoot): Option[NodeId] =
  if root.parentStack.len == 0:
    none(NodeId)
  else:
    some(root.parentStack[^1])

proc pushParent*(root: UiRoot; handle: NodeHandle) =
  root.parentStack.add handle.id

proc popParent*(root: UiRoot) =
  if root.parentStack.len > 0:
    root.parentStack.setLen(root.parentStack.len - 1)

proc pushFieldsetContext*(root: UiRoot; register: FieldsetRegister) =
  root.fieldsetStack.add register

proc popFieldsetContext*(root: UiRoot) =
  if root.fieldsetStack.len > 0:
    root.fieldsetStack.setLen(root.fieldsetStack.len - 1)

proc registerFieldsetTarget*(root: UiRoot; setter: DisabledSetter) =
  if root.fieldsetStack.len > 0:
    root.fieldsetStack[^1](setter)

proc box*(
    root: UiRoot;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  let parentId =
    if parent.isSome: some(parent.get.id)
    else: root.currentParent()
  NodeHandle(root: root, id: root.tree.addBox(parent = parentId, id = id, code = code, groups = groups))

proc box*(
    root: UiRoot;
    style: UiStyle;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  result = root.box(parent = parent, id = id, code = code, groups = groups)
  root.applyStyle(result, style)

template box*(root: UiRoot; group: string; body: untyped) =
  block:
    let handle {.gensym.} = root.box(parent = none(NodeHandle), groups = [group])
    root.pushParent(handle)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; style: UiStyle; body: untyped) =
  block:
    let handle {.gensym.} = root.box(style, parent = none(NodeHandle))
    root.pushParent(handle)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; style: UiStyle; group: string; body: untyped) =
  block:
    let handle {.gensym.} = root.box(style, parent = none(NodeHandle), groups = [group])
    root.pushParent(handle)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; groupA, groupB: string; body: untyped) =
  block:
    let handle {.gensym.} = root.box(parent = none(NodeHandle), groups = [groupA, groupB])
    root.pushParent(handle)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; groupA, groupB, groupC: string; body: untyped) =
  block:
    let handle {.gensym.} = root.box(parent = none(NodeHandle), groups = [groupA, groupB, groupC])
    root.pushParent(handle)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; output: var NodeHandle; group: string; body: untyped) =
  block:
    output = root.box(parent = none(NodeHandle), groups = [group])
    root.pushParent(output)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; output: var NodeHandle; style: UiStyle; body: untyped) =
  block:
    output = root.box(style, parent = none(NodeHandle))
    root.pushParent(output)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; output: var NodeHandle; style: UiStyle; group: string; body: untyped) =
  block:
    output = root.box(style, parent = none(NodeHandle), groups = [group])
    root.pushParent(output)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; output: var NodeHandle; groupA, groupB: string; body: untyped) =
  block:
    output = root.box(parent = none(NodeHandle), groups = [groupA, groupB])
    root.pushParent(output)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; output: var NodeHandle; groupA, groupB, groupC: string; body: untyped) =
  block:
    output = root.box(parent = none(NodeHandle), groups = [groupA, groupB, groupC])
    root.pushParent(output)
    try:
      body
    finally:
      root.popParent()

proc text*(
    root: UiRoot;
    parent: NodeHandle;
    value: string;
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  NodeHandle(root: root, id: root.tree.addText(parent.id, value, id = id, code = code, groups = groups))

proc text*(
    root: UiRoot;
    parent: NodeHandle;
    value: string;
    style: UiStyle;
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  result = root.text(parent, value, id = id, code = code, groups = groups)
  root.applyStyle(result, style)

proc text*(
    root: UiRoot;
    value: string;
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  let parent = root.currentParent()
  if parent.isNone:
    raise newException(ValueError, "ui.text without an explicit parent requires an active ui.box block")
  NodeHandle(root: root, id: root.tree.addText(parent.get, value, id = id, code = code, groups = groups))

proc text*(
    root: UiRoot;
    value: string;
    style: UiStyle;
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  result = root.text(value, id = id, code = code, groups = groups)
  root.applyStyle(result, style)

proc defaultContextMenuItemStyle(): UiStyle =
  uiStyle([
    decl("height", px(26)),
    decl("padding", px(5)),
    decl("padding-left", px(9)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("flex-start")),
    decl("font-size", px(12)),
    decl("line-height", px(16)),
    decl("color", colorValue(rgb(0.90, 0.93, 0.96))),
    decl("border-radius", px(3)),
    decl("cursor", keyword("pointer"))
  ])

proc defaultContextMenuItemHoverStyle(): UiStyle =
  uiStyle([
    decl("background-color", colorValue(rgb(0.19, 0.34, 0.46))),
    decl("color", colorValue(rgb(1, 1, 1)))
  ])

proc defaultContextMenuItemDisabledStyle(): UiStyle =
  uiStyle([
    decl("color", colorValue(rgba(0.65, 0.70, 0.76, 0.42))),
    decl("cursor", keyword("default"))
  ])

proc dispatchDefaultContextMenuAction(root: UiRoot; item: ContextMenuItem): bool =
  if item.disabled or root.defaultContextMenuTarget.isNone:
    discard root.closeDefaultContextMenu()
    return true
  let target = root.defaultContextMenuTarget.get
  case item.action
  of cmaCut:
    discard root.events.emit(root.tree, target, cutEvent())
  of cmaCopy:
    discard root.events.emit(root.tree, target, copyEvent())
  of cmaPaste:
    discard root.events.emit(root.tree, target, pasteEvent(root.clipboardText()))
  of cmaDelete:
    discard root.events.emit(root.tree, target, keyDownEvent("Delete"))
  of cmaSelectAll:
    discard root.events.emit(root.tree, target, keyDownEvent("a", ctrlKey = true))
  discard root.closeDefaultContextMenu()
  true

proc defaultContextMenuRect*(root: UiRoot): Rect =
  let itemCount = root.defaultContextMenuItems.len.float32
  let height =
    defaultContextMenuPadding * 2.0'f32 +
    itemCount * defaultContextMenuItemHeight +
    max(0.0'f32, itemCount - 1.0'f32) * defaultContextMenuItemGap
  rect(
    root.defaultContextMenuPosition.x,
    root.defaultContextMenuPosition.y,
    defaultContextMenuWidth,
    height
  )

proc defaultContextMenuItemAt*(root: UiRoot; point: Vec2): Option[int] =
  if not root.defaultContextMenuOpen:
    return none(int)
  let menuRect = root.defaultContextMenuRect()
  if not menuRect.contains(point):
    return none(int)
  let localY = point.y - menuRect.y - defaultContextMenuPadding
  if localY < 0:
    return none(int)
  let pitch = defaultContextMenuItemHeight + defaultContextMenuItemGap
  let index = int(floor(localY / pitch))
  if index < 0 or index >= root.defaultContextMenuItems.len:
    return none(int)
  let itemTop = index.float32 * pitch
  if localY < itemTop or localY > itemTop + defaultContextMenuItemHeight:
    return none(int)
  some(index)

proc containsDefaultContextMenuPoint*(root: UiRoot; point: Vec2): bool =
  root.defaultContextMenuOpen and root.defaultContextMenuRect().contains(point)

proc activateDefaultContextMenuAt*(root: UiRoot; point: Vec2): bool =
  let index = root.defaultContextMenuItemAt(point)
  if index.isNone:
    return false
  root.dispatchDefaultContextMenuAction(root.defaultContextMenuItems[index.get])

proc mountDefaultContextMenu*(
    root: UiRoot;
    parent: NodeHandle;
    items: openArray[ContextMenuItem] = defaultContextMenuItems()
): NodeHandle {.discardable.} =
  root.defaultContextMenuItems = @items
  result = root.box(root.defaultContextMenuPanelStyle(), parent = some(parent), groups = ["context-menu", "context-menu-default"])
  root.defaultContextMenuNode = some(result.id)
  root.syncDefaultContextMenuStyle()
  for item in items:
    let node = root.text(result, item.label, defaultContextMenuItemStyle(), groups = ["context-menu-item"])
    root.applyHoverStyle(node, defaultContextMenuItemHoverStyle(), priority = 5001)
    root.applyStateStyle(node, {esDisabled}, defaultContextMenuItemDisabledStyle(), priority = 5001)
    root.tree.setState(node.id, esDisabled, item.disabled)
    root.defaultContextMenuItemNodes.add node.id
    let captured = item
    root.events.addInternalEventHandler(node.id, iekPointerDown, proc(event: DispatchResult): bool =
      root.dispatchDefaultContextMenuAction(captured)
    )
    root.events.addInternalEventHandler(node.id, iekClick, proc(event: DispatchResult): bool =
      true
    )

  root.events.addInternalEventHandler(result.id, iekKeyDown, proc(event: DispatchResult): bool =
    if event.event.key.isSome and event.event.key.get == "Escape":
      discard root.closeDefaultContextMenu()
      return true
    false
  )

proc imageNode*(
    root: UiRoot;
    parent: NodeHandle;
    source: string;
    width = 0.0'f32;
    height = 0.0'f32;
    id = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  NodeHandle(
    root: root,
    id: root.tree.addImage(parent.id, source, width = width, height = height, id = id, groups = groups)
  )

proc imageNode*(
    root: UiRoot;
    parent: NodeHandle;
    source: string;
    style: UiStyle;
    width = 0.0'f32;
    height = 0.0'f32;
    id = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  result = root.imageNode(parent, source, width = width, height = height, id = id, groups = groups)
  root.applyStyle(result, style)

proc imageNode*(
    root: UiRoot;
    source: string;
    width = 0.0'f32;
    height = 0.0'f32;
    id = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  let parent = root.currentParent()
  if parent.isNone:
    raise newException(ValueError, "ui.image without an explicit parent requires an active ui.box block")
  NodeHandle(
    root: root,
    id: root.tree.addImage(parent.get, source, width = width, height = height, id = id, groups = groups)
  )

proc imageNode*(
    root: UiRoot;
    source: string;
    style: UiStyle;
    width = 0.0'f32;
    height = 0.0'f32;
    id = "";
    groups: openArray[string] = []
): NodeHandle {.discardable.} =
  result = root.imageNode(source, width = width, height = height, id = id, groups = groups)
  root.applyStyle(result, style)

proc addState*(handle: NodeHandle; state: ElementState) =
  handle.root.tree.addState(handle.id, state)

proc removeState*(handle: NodeHandle; state: ElementState) =
  handle.root.tree.removeState(handle.id, state)

proc setState*(handle: NodeHandle; state: ElementState; enabled: bool) =
  handle.root.tree.setState(handle.id, state, enabled)

proc setFocusable*(handle: NodeHandle; focusable = true; tabIndex = 0) =
  handle.root.tree.setFocusable(handle.id, focusable, tabIndex)

proc setFocusDelegate*(handle: NodeHandle; target: Option[NodeHandle]) =
  handle.root.tree.setFocusDelegate(
    handle.id,
    if target.isSome: some(target.get.id) else: none(NodeId)
  )

proc setAccessibleRole*(handle: NodeHandle; role: AccessibleRole) =
  handle.root.tree.setAccessibleRole(handle.id, role)

proc setAccessibleName*(handle: NodeHandle; name: string) =
  handle.root.tree.setAccessibleName(handle.id, name)

proc setAccessibleDescription*(handle: NodeHandle; description: string) =
  handle.root.tree.setAccessibleDescription(handle.id, description)

proc setAccessibleValue*(handle: NodeHandle; value: string) =
  handle.root.tree.setAccessibleValue(handle.id, value)

proc setAccessibleRange*(
    handle: NodeHandle;
    valueNow, valueMin, valueMax: Option[float32]
) =
  handle.root.tree.setAccessibleRange(handle.id, valueNow, valueMin, valueMax)

proc setAccessibleLabelledBy*(handle: NodeHandle; label: Option[NodeHandle]) =
  handle.root.tree.setAccessibleLabelledBy(
    handle.id,
    if label.isSome: some(label.get.id) else: none(NodeId)
  )

proc setAccessibleDescribedBy*(handle: NodeHandle; description: Option[NodeHandle]) =
  handle.root.tree.setAccessibleDescribedBy(
    handle.id,
    if description.isSome: some(description.get.id) else: none(NodeId)
  )

proc setAccessibleHidden*(handle: NodeHandle; hidden: bool) =
  handle.root.tree.setAccessibleHidden(handle.id, hidden)

proc focusable*(handle: NodeHandle): bool =
  handle.root.tree.isFocusable(handle.id)

proc tabIndex*(handle: NodeHandle): int =
  handle.root.tree.nodes[handle.id.nodeIndex].tabIndex

proc target*(handle: NodeHandle): SelectorCondition =
  target(handle.id)

proc applyStyle*(handle: NodeHandle; style: UiStyle) =
  handle.root.applyStyle(handle, style)

proc applyStateStyle*(handle: NodeHandle; states: set[ElementState]; style: UiStyle; priority = 0) =
  handle.root.applyStateStyle(handle, states, style, priority = priority)

proc applyHoverStyle*(handle: NodeHandle; style: UiStyle; priority = 0) =
  handle.root.applyHoverStyle(handle, style, priority = priority)

proc applyActiveStyle*(handle: NodeHandle; style: UiStyle; priority = 0) =
  handle.root.applyActiveStyle(handle, style, priority = priority)

proc applyFocusStyle*(handle: NodeHandle; style: UiStyle; priority = 0) =
  handle.root.applyFocusStyle(handle, style, priority = priority)

proc applyFocusVisibleStyle*(handle: NodeHandle; style: UiStyle; priority = 0) =
  handle.root.applyFocusVisibleStyle(handle, style, priority = priority)

proc emit*(handle: NodeHandle; event: InputEvent; local = none(Vec2)): bool =
  handle.root.events.emit(handle.root.tree, handle.id, event, local)

proc emit*(handle: NodeHandle; kind: InputEventKind; local = none(Vec2)): bool =
  handle.root.events.emit(handle.root.tree, handle.id, kind, local)

template handleEventSlot(setterName: untyped; kindValue: InputEventKind) =
  proc setterName*(handle: NodeHandle; handler: EventHandler) =
    handle.root.events.setEventHandler(handle.id, kindValue, handler)

handleEventSlot(`onAbort=`, iekAbort)
handleEventSlot(`onAnimationEnd=`, iekAnimationEnd)
handleEventSlot(`onAnimationIteration=`, iekAnimationIteration)
handleEventSlot(`onAnimationStart=`, iekAnimationStart)
handleEventSlot(`onAuxClick=`, iekAuxClick)
handleEventSlot(`onBeforeInput=`, iekBeforeInput)
handleEventSlot(`onBlur=`, iekBlur)
handleEventSlot(`onCancel=`, iekCancel)
handleEventSlot(`onCanPlay=`, iekCanPlay)
handleEventSlot(`onCanPlayThrough=`, iekCanPlayThrough)
handleEventSlot(`onChange=`, iekChange)
handleEventSlot(`onClick=`, iekClick)
handleEventSlot(`onClose=`, iekClose)
handleEventSlot(`onContextMenu=`, iekContextMenu)
handleEventSlot(`onCopy=`, iekCopy)
handleEventSlot(`onCueChange=`, iekCueChange)
handleEventSlot(`onCut=`, iekCut)
handleEventSlot(`onDblClick=`, iekDoubleClick)
handleEventSlot(`onDoubleClick=`, iekDoubleClick)
handleEventSlot(`onCompositionEnd=`, iekCompositionEnd)
handleEventSlot(`onCompositionStart=`, iekCompositionStart)
handleEventSlot(`onCompositionUpdate=`, iekCompositionUpdate)
handleEventSlot(`onDrag=`, iekDrag)
handleEventSlot(`onDragEnd=`, iekDragEnd)
handleEventSlot(`onDragEnter=`, iekDragEnter)
handleEventSlot(`onDragExit=`, iekDragExit)
handleEventSlot(`onDragLeave=`, iekDragLeave)
handleEventSlot(`onDragOver=`, iekDragOver)
handleEventSlot(`onDragStart=`, iekDragStart)
handleEventSlot(`onDrop=`, iekDrop)
handleEventSlot(`onDurationChange=`, iekDurationChange)
handleEventSlot(`onEmptied=`, iekEmptied)
handleEventSlot(`onEncrypted=`, iekEncrypted)
handleEventSlot(`onEnded=`, iekEnded)
handleEventSlot(`onError=`, iekError)
handleEventSlot(`onFocus=`, iekFocus)
handleEventSlot(`onFullscreenChange=`, iekFullscreenChange)
handleEventSlot(`onFullscreenError=`, iekFullscreenError)
handleEventSlot(`onGotPointerCapture=`, iekGotPointerCapture)
handleEventSlot(`onInput=`, iekInput)
handleEventSlot(`onInvalid=`, iekInvalid)
handleEventSlot(`onKeyDown=`, iekKeyDown)
handleEventSlot(`onKeyUp=`, iekKeyUp)
handleEventSlot(`onLoad=`, iekLoad)
handleEventSlot(`onLoadEnd=`, iekLoadEnd)
handleEventSlot(`onLoadedData=`, iekLoadedData)
handleEventSlot(`onLoadedMetadata=`, iekLoadedMetadata)
handleEventSlot(`onLoadStart=`, iekLoadStart)
handleEventSlot(`onLostPointerCapture=`, iekLostPointerCapture)
handleEventSlot(`onMouseDown=`, iekMouseDown)
handleEventSlot(`onMouseEnter=`, iekMouseEnter)
handleEventSlot(`onMouseLeave=`, iekMouseLeave)
handleEventSlot(`onMouseMove=`, iekMouseMove)
handleEventSlot(`onMouseOut=`, iekMouseOut)
handleEventSlot(`onMouseOver=`, iekMouseOver)
handleEventSlot(`onMouseUp=`, iekMouseUp)
handleEventSlot(`onPause=`, iekPause)
handleEventSlot(`onPaste=`, iekPaste)
handleEventSlot(`onPlay=`, iekPlay)
handleEventSlot(`onPlaying=`, iekPlaying)
handleEventSlot(`onPointerCancel=`, iekPointerCancel)
handleEventSlot(`onPointerDown=`, iekPointerDown)
handleEventSlot(`onPointerEnter=`, iekPointerEnter)
handleEventSlot(`onPointerLeave=`, iekPointerLeave)
handleEventSlot(`onPointerMove=`, iekPointerMove)
handleEventSlot(`onPointerOut=`, iekPointerOut)
handleEventSlot(`onPointerOver=`, iekPointerOver)
handleEventSlot(`onPointerUp=`, iekPointerUp)
handleEventSlot(`onProgress=`, iekProgress)
handleEventSlot(`onRateChange=`, iekRateChange)
handleEventSlot(`onReset=`, iekReset)
handleEventSlot(`onResize=`, iekResize)
handleEventSlot(`onScroll=`, iekScroll)
handleEventSlot(`onScrollEnd=`, iekScrollEnd)
handleEventSlot(`onSeeked=`, iekSeeked)
handleEventSlot(`onSeeking=`, iekSeeking)
handleEventSlot(`onSelect=`, iekSelect)
handleEventSlot(`onShow=`, iekShow)
handleEventSlot(`onStalled=`, iekStalled)
handleEventSlot(`onSubmit=`, iekSubmit)
handleEventSlot(`onSuspend=`, iekSuspend)
handleEventSlot(`onTextInput=`, iekTextInput)
handleEventSlot(`onTimeUpdate=`, iekTimeUpdate)
handleEventSlot(`onToggle=`, iekToggle)
handleEventSlot(`onTouchCancel=`, iekTouchCancel)
handleEventSlot(`onTouchEnd=`, iekTouchEnd)
handleEventSlot(`onTouchMove=`, iekTouchMove)
handleEventSlot(`onTouchStart=`, iekTouchStart)
handleEventSlot(`onTransitionEnd=`, iekTransitionEnd)
handleEventSlot(`onVolumeChange=`, iekVolumeChange)
handleEventSlot(`onWaiting=`, iekWaiting)
handleEventSlot(`onWheel=`, iekWheel)
