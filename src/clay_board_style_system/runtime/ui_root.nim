import std/[algorithm, hashes, math, options, sets, tables]

import ../core/[color, declaration, geometry, node, rule, selector, style_value]
import ../core/style_resolver
import ../input/events
import ../layout/layout
import ../layout/presentation
import ../layout/scroll_state
import ../paint/paint
import ../paint/paint_command
import ../text/[font_registry, text_engine]
import ./animation_clock
import ./canvas
import ./declarative_keyframes
import ./declarative_transition
import ./frame_scheduler
import ./invalidation
import ./render_surface

type
  DisabledSetter* = proc(disabled: bool) {.closure.}
  FieldsetRegister* = proc(setter: DisabledSetter) {.closure.}
  ClipboardTextProvider* = proc(): string {.closure.}
  ClipboardTextWriter* = proc(text: string) {.closure.}
  PopupCloser* = proc(target: Option[NodeId]): bool {.closure.}
  ComponentRetention* = ref RootObj
  ComponentUnmountCallback* = proc(component: ComponentRetention) {.nimcall.}

  PopupCloserBinding = object
    owner: NodeId
    callback: PopupCloser

  MountedComponentBinding = object
    owner: NodeId
    component: ComponentRetention
    callback: ComponentUnmountCallback

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

  UiInvalidation* = object
    domains*: set[DirtyDomain]
    roots*: seq[NodeId]

  AppliedStyleKey = object
    node: NodeId
    states: set[ElementState]
    priority: int

  UiRoot* = ref object
    tree*: Tree
    events*: EventRegistry
    componentStyles*: seq[StyleSheet]
    appliedStyleIndices: Table[AppliedStyleKey, int]
    freeComponentStyleIndices: seq[int]
    textEngine*: TextEngine
    fonts*: FontRegistry
    scroll*: ScrollState
    surfaces*: RenderSurfaceRegistry
    canvases*: Table[RenderSurfaceId, Canvas2D]
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
    popupClosers*: seq[PopupCloserBinding]
    mountedComponents: seq[MountedComponentBinding]
    animations: AnimationClock
    keyframes: DeclarativeKeyframeRuntime
    transitions: DeclarativeTransitionRuntime
    animationOwners: Table[AnimationId, NodeId]
    pendingInvalidation: InvalidationState
    pendingInvalidationRoots: seq[NodeId]
    eventActionPool: seq[EventActionQueue]
    focusRequestPending*: bool
    focusRequestTarget*: Option[NodeId]
    pointerRequestPending: bool
    pointerRequestAction: EventPointerCaptureAction
    pointerRequestTarget: Option[NodeId]
    frameRequestPending: bool
    parentStack: seq[NodeId]
    fieldsetStack: seq[FieldsetRegister]

  NodeHandle* = object
    ## Non-owning: UiRoot owns the event registry, whose closures may capture
    ## handles. ARC must not retain the root through that back-reference.
    root* {.cursor.}: UiRoot
    id*: NodeId

  CanvasHandle* = object
    node*: NodeHandle
    surface*: RenderSurfaceId
    canvas*: Canvas2D

proc initUiRoot*(): UiRoot =
  UiRoot(
    tree: initTree(),
    events: initEventRegistry(),
    componentStyles: @[],
    appliedStyleIndices: initTable[AppliedStyleKey, int](),
    freeComponentStyleIndices: @[],
    textEngine: debugTextEngine(),
    fonts: initFontRegistry(),
    scroll: initScrollState(),
    surfaces: initRenderSurfaceRegistry(),
    canvases: initTable[RenderSurfaceId, Canvas2D](),
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
    mountedComponents: @[],
    animations: initAnimationClock(),
    keyframes: initDeclarativeKeyframeRuntime(),
    transitions: initDeclarativeTransitionRuntime(),
    animationOwners: initTable[AnimationId, NodeId](),
    pendingInvalidation: initInvalidationState(),
    pendingInvalidationRoots: @[],
    eventActionPool: @[],
    focusRequestPending: false,
    focusRequestTarget: none(NodeId),
    pointerRequestPending: false,
    pointerRequestAction: epcaNone,
    pointerRequestTarget: none(NodeId),
    frameRequestPending: false,
    parentStack: @[],
    fieldsetStack: @[]
  )

proc invalidate*(root: UiRoot; domain: DirtyDomain) =
  if not root.isNil:
    root.pendingInvalidation.markDirty(domain)

proc invalidate*(root: UiRoot; domains: set[DirtyDomain]) =
  if not root.isNil:
    root.pendingInvalidation.markDirty(domains)

proc invalidate*(root: UiRoot; target: NodeId; domains: set[DirtyDomain]) =
  if root.isNil or not root.tree.isValid(target):
    return
  root.pendingInvalidation.markDirty(domains)
  var index = 0
  while index < root.pendingInvalidationRoots.len:
    let existing = root.pendingInvalidationRoots[index]
    if root.tree.isDescendantOrSelf(target, existing):
      return
    if root.tree.isDescendantOrSelf(existing, target):
      root.pendingInvalidationRoots.delete(index)
      continue
    inc index
  root.pendingInvalidationRoots.add target

proc hasPendingInvalidation*(root: UiRoot): bool =
  not root.isNil and root.pendingInvalidation.dirty()

proc consumeInvalidation*(root: UiRoot): UiInvalidation =
  if root.isNil:
    return UiInvalidation()
  result = UiInvalidation(
    domains: root.pendingInvalidation.consumeDirty(),
    roots: root.pendingInvalidationRoots
  )
  root.pendingInvalidationRoots = @[]

proc requestFocus*(root: UiRoot; target: Option[NodeId])

proc acquireEventActions(root: UiRoot): tuple[
    actions: EventActionQueue,
    generation: uint64
] =
  let reuse =
    if root.eventActionPool.len > 0: root.eventActionPool.pop()
    else: nil
  beginEventActions(reuse)

proc applyEventActions(root: UiRoot; snapshot: EventActionSnapshot) =
  if snapshot.focusPending and
      (snapshot.focusTarget.isNone or
       root.tree.isValid(snapshot.focusTarget.get)):
    root.requestFocus(snapshot.focusTarget)

  if snapshot.pointerAction != epcaNone:
    let validTarget = snapshot.pointerTarget.isSome and
      root.tree.isValid(snapshot.pointerTarget.get)
    if snapshot.pointerAction == epcaRelease or validTarget:
      root.pointerRequestPending = true
      root.pointerRequestAction = snapshot.pointerAction
      root.pointerRequestTarget = snapshot.pointerTarget

  for request in snapshot.invalidations:
    if request.target.isSome:
      if root.tree.isValid(request.target.get):
        root.invalidate(request.target.get, request.domains)
    else:
      root.invalidate(request.domains)

  if snapshot.frameRequested:
    root.frameRequestPending = true
    root.invalidate(ddAnimation)

proc dispatchEvent*(
    root: UiRoot;
    dispatch: DispatchResult
): EventOutcome =
  if root.isNil:
    return ignoredEvent()
  let scope = root.acquireEventActions()
  let scopedDispatch = dispatch.withEventActions(
    scope.actions,
    scope.generation
  )
  var snapshot: EventActionSnapshot
  try:
    result = root.events.dispatchEvent(root.tree, scopedDispatch)
    snapshot = finishEventActions(scope.actions, scope.generation)
  except:
    discard finishEventActions(scope.actions, scope.generation)
    root.eventActionPool.add scope.actions
    raise
  root.eventActionPool.add scope.actions
  root.applyEventActions(snapshot)

proc dispatchEvents*(
    root: UiRoot;
    dispatches: openArray[DispatchResult]
): EventOutcome =
  for dispatch in dispatches:
    result.mergeOutcome(root.dispatchEvent(dispatch))

proc handleEvent*(root: UiRoot; dispatch: DispatchResult): bool =
  root.dispatchEvent(dispatch).handled

proc handleEvents*(
    root: UiRoot;
    dispatches: openArray[DispatchResult]
): bool =
  root.dispatchEvents(dispatches).handled

proc takeFrameRequest*(root: UiRoot): bool =
  if root.isNil:
    return false
  result = root.frameRequestPending
  root.frameRequestPending = false

proc reconcilePointerCapture*(
    root: UiRoot;
    interaction: var InteractionState
): EventOutcome =
  if root.isNil or not root.pointerRequestPending:
    return ignoredEvent()
  let action = root.pointerRequestAction
  let target = root.pointerRequestTarget
  root.pointerRequestPending = false
  root.pointerRequestAction = epcaNone
  root.pointerRequestTarget = none(NodeId)

  case action
  of epcaCapture:
    if target.isNone or not root.tree.isValid(target.get) or
        interaction.pointerCaptureTarget == target:
      return ignoredEvent()
    let released = interaction.releasePointer()
    if released.isSome:
      result.mergeOutcome(root.dispatchEvent(released.get))
    result.mergeOutcome(root.dispatchEvent(
      interaction.capturePointer(target.get)
    ))
  of epcaRelease:
    let released = interaction.releasePointer()
    if released.isSome:
      result.mergeOutcome(root.dispatchEvent(released.get))
  of epcaNone:
    discard

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

proc startOwnedAnimation*(
    root: UiRoot;
    owner: NodeHandle;
    spec: AnimationSpec;
    nowSeconds: float64
): AnimationId =
  if owner.root != root or not root.tree.isValid(owner.id):
    raise newException(ValueError, "animation owner is not active in this UiRoot")
  result = root.animations.startAnimation(spec, nowSeconds)
  root.animationOwners[result] = owner.id

proc cancelOwnedAnimation*(root: UiRoot; id: AnimationId): bool {.discardable.} =
  root.animationOwners.del(id)
  root.animations.cancelAnimation(id)

proc tickOwnedAnimations*(
    root: UiRoot;
    scheduler: var FrameScheduler;
    nowSeconds: float64
): int {.discardable.} =
  var stale: seq[AnimationId]
  for id, owner in root.animationOwners.pairs:
    if not root.tree.isValid(owner):
      stale.add id
  for id in stale:
    discard root.cancelOwnedAnimation(id)

  result = root.animations.tickAnimations(scheduler, nowSeconds)
  var completed: seq[AnimationId]
  for id in root.animationOwners.keys:
    if not root.animations.hasAnimation(id):
      completed.add id
  for id in completed:
    root.animationOwners.del(id)

proc scheduleOwnedAnimations*(
    root: UiRoot;
    scheduler: var FrameScheduler;
    nowSeconds: float64
) =
  if root.animations.hasActiveAnimations():
    scheduler.requestDeadline(nowSeconds + root.animations.targetFrameInterval)

proc activeAnimationOwners*(root: UiRoot): seq[NodeId] =
  for id, owner in root.animationOwners.pairs:
    if root.animations.hasAnimation(id) and root.tree.isValid(owner):
      result.add owner
  result.sort(proc(a, b: NodeId): int =
    cmp(a.nodeRawValue(), b.nodeRawValue())
  )

proc setReducedMotion*(root: UiRoot; enabled: bool) =
  root.animations.reducedMotion = enabled
  root.keyframes.setReducedMotion(enabled)
  root.transitions.reducedMotion = enabled
  if enabled and (root.transitions.hasActiveTransitions or
      root.keyframes.activeAnimationCount > 0):
    root.invalidate({ddPaint, ddAnimation})

proc registerStyleKeyframes*(root: UiRoot; definition: StyleKeyframes) =
  if root.isNil:
    raise newException(ValueError, "cannot register keyframes on a nil UiRoot")
  root.keyframes.registerStyleKeyframes(definition)

proc unregisterStyleKeyframes*(root: UiRoot; name: string): bool {.discardable.} =
  not root.isNil and root.keyframes.unregisterStyleKeyframes(name)

proc hasStyleKeyframes*(root: UiRoot; name: string): bool =
  not root.isNil and root.keyframes.hasStyleKeyframes(name)

proc reconcileStyleAnimations*(
    root: UiRoot;
    target: var ResolvedTree;
    nowSeconds: float64
) =
  if not root.isNil:
    root.keyframes.reconcileAnimations(root.tree, target, nowSeconds)

proc applyStyleAnimations*(
    root: UiRoot;
    styles: var ResolvedTree;
    scheduler: var FrameScheduler;
    nowSeconds: float64
): int {.discardable.} =
  if root.isNil:
    return 0
  root.keyframes.applyAnimations(root.tree, styles, scheduler, nowSeconds)

proc activeStyleAnimationCount*(root: UiRoot): int =
  if root.isNil: 0
  else: root.keyframes.activeAnimationCount

proc reconcileStyleTransitions*(
    root: UiRoot;
    displayed, target: ResolvedTree;
    nowSeconds: float64
) =
  if root.isNil:
    return
  root.transitions.reconcileTransitions(
    root.tree, displayed, target, nowSeconds
  )

proc applyStyleTransitions*(
    root: UiRoot;
    styles: var ResolvedTree;
    scheduler: var FrameScheduler;
    nowSeconds: float64
): int {.discardable.} =
  if root.isNil:
    return 0
  root.transitions.applyTransitions(
    root.tree, styles, scheduler, nowSeconds
  )

proc activeStyleTransitionCount*(root: UiRoot): int =
  if root.isNil: 0
  else: root.transitions.activeTransitionCount()

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

proc registerPopupCloser*(
    root: UiRoot;
    owner: NodeId;
    closer: PopupCloser
) =
  if not root.tree.isValid(owner):
    raise newException(ValueError, "popup closer owner is not active")
  root.popupClosers.add PopupCloserBinding(owner: owner, callback: closer)

proc closeOpenPopups*(root: UiRoot; target: Option[NodeId]): bool =
  for binding in root.popupClosers:
    if binding.callback(target):
      result = true

proc retainMountedComponent*(
    root: UiRoot;
    owner: NodeHandle;
    component: ComponentRetention;
    callback: ComponentUnmountCallback
) =
  if owner.root != root or not root.tree.isValid(owner.id):
    raise newException(ValueError, "component root does not belong to this UiRoot")
  if callback.isNil:
    raise newException(ValueError, "component unmount callback cannot be nil")
  if component.isNil:
    raise newException(ValueError, "mounted component cannot be nil")
  for binding in root.mountedComponents:
    if binding.owner == owner.id:
      raise newException(ValueError, "component root is already retained")
  root.mountedComponents.add MountedComponentBinding(
    owner: owner.id,
    component: component,
    callback: callback
  )

proc takeComponentUnmountCallbacks(
    root: UiRoot;
    removed: HashSet[NodeId]
): seq[MountedComponentBinding] =
  var retained = newSeqOfCap[MountedComponentBinding](root.mountedComponents.len)
  for binding in root.mountedComponents:
    if binding.owner in removed:
      result.add binding
    else:
      retained.add binding
  root.mountedComponents = retained

proc uiStyle*(declarations: openArray[Declaration]): UiStyle =
  UiStyle(declarations: @declarations)

proc `+`*(a, b: UiStyle): UiStyle =
  UiStyle(declarations: a.declarations & b.declarations)

proc hash(key: AppliedStyleKey): Hash =
  result = hash(key.node)
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
  if not handle.root.isNil and handle.root.tree.isValid(handle.id):
    handle.root.tree.nodes[handle.id.nodeIndex].code = code

proc valid*(handle: NodeHandle): bool =
  not handle.root.isNil and handle.root.tree.isValid(handle.id)

proc valid*(handle: CanvasHandle): bool =
  handle.node.valid and handle.node.root.surfaces.hasSurface(handle.surface)

proc nodeHandle*(handle: CanvasHandle): NodeHandle =
  handle.node

proc requestFrame*(handle: CanvasHandle): bool {.discardable.} =
  if not handle.valid:
    return false
  handle.node.root.surfaces.requestSurfaceFrame(handle.surface)

proc storeComponentStyle(root: UiRoot; sheet: StyleSheet): int =
  if root.freeComponentStyleIndices.len > 0:
    result = root.freeComponentStyleIndices.pop()
    root.componentStyles[result] = sheet
  else:
    root.componentStyles.add sheet
    result = root.componentStyles.high

proc addStyle*(root: UiRoot; sheet: StyleSheet) =
  discard root.storeComponentStyle(sheet)

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
  if not root.tree.isValid(node):
    return
  let key = AppliedStyleKey(
    node: node,
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
  root.appliedStyleIndices[key] = root.storeComponentStyle(sheet)

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

proc releaseComponentStyleSlot(root: UiRoot; index: int) =
  if index < 0 or index >= root.componentStyles.len:
    return
  if root.defaultContextMenuStyleIndex == some(index):
    return
  root.componentStyles[index] = StyleSheet(rules: @[])
  if index notin root.freeComponentStyleIndices:
    root.freeComponentStyleIndices.add index

proc removeSubtreeStyles(root: UiRoot; removed: HashSet[NodeId]) =
  var staleKeys: seq[AppliedStyleKey]
  for key in root.appliedStyleIndices.keys:
    if key.node in removed:
      staleKeys.add key
  for key in staleKeys:
    let index = root.appliedStyleIndices[key]
    root.appliedStyleIndices.del(key)
    root.releaseComponentStyleSlot(index)

  for index in 0 ..< root.componentStyles.len:
    if index in root.freeComponentStyleIndices:
      continue
    let sheet = root.componentStyles[index]
    var retained = newSeqOfCap[StyleRule](sheet.rules.len)
    var changed = false
    for item in sheet.rules:
      if item.selector.nodeId.isSome and item.selector.nodeId.get in removed:
        changed = true
      else:
        retained.add item
    if changed:
      if retained.len == 0:
        root.releaseComponentStyleSlot(index)
      else:
        root.componentStyles[index] = StyleSheet(rules: retained)

proc clearInteractionTargets(
    root: UiRoot;
    interaction: var InteractionState;
    removed: HashSet[NodeId]
) =
  if interaction.focusedTarget.isSome and
      interaction.focusedTarget.get in removed:
    let focused = interaction.focusedTarget.get
    discard root.events.emit(root.tree, focused, iekBlur)
    discard interaction.setFocusedTarget(none(NodeId))

  template clearTarget(field: untyped) =
    if field.isSome and field.get in removed:
      field = none(NodeId)

  if interaction.pressedTarget.isSome and
      interaction.pressedTarget.get in removed:
    interaction.pressedTarget = none(NodeId)
    interaction.pointerDownPosition = none(Vec2)
  clearTarget(interaction.hoveredTarget)
  clearTarget(interaction.pointerCaptureTarget)
  clearTarget(interaction.lastClickTarget)
  clearTarget(interaction.dragTarget)
  clearTarget(interaction.dragOverTarget)
  clearTarget(interaction.scrollTarget)
  clearTarget(interaction.scrollbarPointerTarget)
  if interaction.lastClickTarget.isNone:
    interaction.clickCount = 0
  if interaction.scrollbarPointerTarget.isNone:
    interaction.scrollbarDragging = false

proc disposeSubtree*(
    root: UiRoot;
    subtree: NodeHandle;
    interaction: var InteractionState
): bool {.discardable.} =
  if subtree.root != root:
    raise newException(ValueError, "disposed subtree belongs to another UiRoot")
  if not root.tree.isValid(subtree.id):
    return false

  var removedIds: seq[NodeId]
  var removed = initHashSet[NodeId]()
  var pending = @[subtree.id]
  while pending.len > 0:
    let id = pending.pop()
    if not root.tree.isValid(id) or id in removed:
      continue
    removed.incl id
    removedIds.add id
    for child in root.tree.nodes[id.nodeIndex].children:
      pending.add child

  root.clearInteractionTargets(interaction, removed)
  var removedAnimations: seq[AnimationId]
  for id, owner in root.animationOwners.pairs:
    if owner in removed:
      removedAnimations.add id
  for id in removedAnimations:
    discard root.cancelOwnedAnimation(id)
  discard root.keyframes.cancelAnimations(removedIds)
  discard root.transitions.cancelTransitions(removedIds)
  let componentUnmountCallbacks = root.takeComponentUnmountCallbacks(removed)
  discard root.events.removeEventHandlers(removed)
  root.removeSubtreeStyles(removed)
  root.scroll.clearNodes(removedIds)

  for id in removedIds:
    let surface = root.tree.nodes[id.nodeIndex].renderSurfaceId
    if surface.isSome:
      let surfaceId = RenderSurfaceId(surface.get)
      root.canvases.del(surfaceId)
      discard root.surfaces.unregisterSurface(surfaceId)

  var retainedClosers = newSeqOfCap[PopupCloserBinding](root.popupClosers.len)
  for binding in root.popupClosers:
    if binding.owner notin removed:
      retainedClosers.add binding
  root.popupClosers = retainedClosers

  var retainedParents = newSeqOfCap[NodeId](root.parentStack.len)
  for id in root.parentStack:
    if id notin removed:
      retainedParents.add id
  root.parentStack = retainedParents

  if root.focusRequestTarget.isSome and root.focusRequestTarget.get in removed:
    root.focusRequestPending = false
    root.focusRequestTarget = none(NodeId)
  if root.pointerRequestTarget.isSome and root.pointerRequestTarget.get in removed:
    root.pointerRequestPending = false
    root.pointerRequestAction = epcaNone
    root.pointerRequestTarget = none(NodeId)
  if root.defaultContextMenuTarget.isSome and
      root.defaultContextMenuTarget.get in removed:
    root.defaultContextMenuTarget = none(NodeId)
    root.defaultContextMenuOpen = false
  if root.defaultContextMenuNode.isSome and
      root.defaultContextMenuNode.get in removed:
    if root.defaultContextMenuStyleIndex.isSome:
      let styleIndex = root.defaultContextMenuStyleIndex.get
      root.defaultContextMenuStyleIndex = none(int)
      root.releaseComponentStyleSlot(styleIndex)
    root.defaultContextMenuNode = none(NodeId)
    root.defaultContextMenuItemNodes.setLen(0)
    root.defaultContextMenuItems.setLen(0)
    root.defaultContextMenuOpen = false
  else:
    var retainedItems: seq[NodeId]
    for id in root.defaultContextMenuItemNodes:
      if id notin removed:
        retainedItems.add id
    root.defaultContextMenuItemNodes = retainedItems

  discard root.tree.disposeSubtree(subtree.id)

  var unmountFailure: ref CatchableError
  for binding in componentUnmountCallbacks:
    try:
      binding.callback(binding.component)
    except CatchableError as error:
      if unmountFailure.isNil:
        unmountFailure = error
  if not unmountFailure.isNil:
    raise unmountFailure
  true

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
    root.defaultContextMenuStyleIndex = some(root.storeComponentStyle(sheet))

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
  while root.parentStack.len > 0 and
      not root.tree.isValid(root.parentStack[^1]):
    root.parentStack.setLen(root.parentStack.len - 1)
  if root.parentStack.len == 0: none(NodeId)
  else: some(root.parentStack[^1])

proc pushParent*(root: UiRoot; handle: NodeHandle) =
  if handle.root != root or not root.tree.isValid(handle.id):
    raise newException(ValueError, "parent handle does not belong to this UiRoot")
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
  if parent.isSome and parent.get.root != root:
    raise newException(ValueError, "box parent belongs to another UiRoot")
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

proc bindRenderSurfaceEvents(root: UiRoot; node: NodeHandle; surface: RenderSurfaceId) =
  let target = node
  const surfaceInputEventKinds = {
    iekPointerMove, iekPointerDown, iekPointerUp, iekPointerCancel,
    iekPointerEnter, iekPointerLeave, iekClick, iekAuxClick,
    iekContextMenu, iekDoubleClick, iekWheel,
    iekKeyDown, iekKeyUp, iekTextInput,
    iekFocus, iekBlur,
    iekCompositionStart, iekCompositionUpdate, iekCompositionEnd,
    iekCopy, iekCut, iekPaste,
    iekTouchStart, iekTouchMove, iekTouchEnd, iekTouchCancel,
    iekPenProximityIn, iekPenProximityOut,
    iekPenButtonDown, iekPenButtonUp,
    iekDragStart, iekDrag, iekDragEnd, iekDragEnter, iekDragOver,
    iekDragLeave, iekDrop
  }
  for kind in surfaceInputEventKinds:
    let eventKind = kind
    root.events.addInternalEventHandler(node.id, eventKind, proc(event: DispatchResult): EventOutcome =
      if not target.valid:
        return ignoredEvent()
      let handled = target.root.surfaces.dispatchSurfaceInput(
        surface,
        event.event,
        captured = false
      )
      if handled: stoppedEvent() else: ignoredEvent()
    )

proc canvas*(
    root: UiRoot;
    value: Canvas2D;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): CanvasHandle {.discardable.} =
  if value.isNil:
    raise newException(ValueError, "canvas value must not be nil")
  if parent.isSome and parent.get.root != root:
    raise newException(ValueError, "canvas parent belongs to another UiRoot")
  let parentId =
    if parent.isSome: some(parent.get.id)
    else: root.currentParent()
  let surface = root.surfaces.registerSurface(value.renderSurfaceDescriptor())
  let node = NodeHandle(
    root: root,
    id: root.tree.addRenderSurfaceBox(
      surface.renderSurfaceIdValue,
      parent = parentId,
      id = id,
      code = code,
      groups = groups
    )
  )
  root.canvases[surface] = value
  root.bindRenderSurfaceEvents(node, surface)
  result = CanvasHandle(node: node, surface: surface, canvas: value)

proc canvas*(
    root: UiRoot;
    value: Canvas2D;
    style: UiStyle;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): CanvasHandle {.discardable.} =
  result = root.canvas(value, parent, id, code, groups)
  root.applyStyle(result.node, style)

proc canvasPaintProvider*(root: UiRoot): SurfacePaintProvider =
  let owner = root
  result = proc(
      surfaceId: uint64;
      node: NodeId;
      bounds: Rect;
      opacity: float32
  ): seq[PaintCommand] =
    let id = RenderSurfaceId(surfaceId)
    if id in owner.canvases:
      result = owner.canvases[id].paintCommands(
        node, bounds, opacity, resolveBounds = false
      )

proc syncRenderSurfaces*(
    root: UiRoot;
    styles: ResolvedTree;
    layout: LayoutResult;
    pixelScale = 1.0'f32
) =
  for index, node in root.tree.nodes:
    if not node.alive or node.renderSurfaceId.isNone:
      continue
    let nodeId = root.tree.nodeIdAt(index).get
    let surface = RenderSurfaceId(node.renderSurfaceId.get)
    if not root.surfaces.hasSurface(surface):
      continue
    let presentation = presentationForNode(
      root.tree, layout, styles, nodeId, root.scroll
    )
    let placement =
      if presentation.isSome:
        let sourceContentBounds = presentation.get.sourceContentBounds(
          styles.styles[nodeId.nodeIndex]
        )
        let contentClip = presentation.get.contentClip(
          styles.styles[nodeId.nodeIndex]
        )
        renderSurfacePlacement(
          sourceContentBounds,
          contentClip,
          pixelScale = pixelScale,
          opacity = max(0.0'f32, min(1.0'f32, presentation.get.opacity)),
          transform = presentation.get.transform
        )
      else:
        renderSurfacePlacement(
          rect(0, 0, 0, 0), rect(0, 0, 0, 0), pixelScale = pixelScale,
          opacity = 0
        )
    let visible = presentation.isSome and presentation.get.visible and
      not placement.effectiveClip.isEmpty
    if root.surfaces.surfaceState(surface) == rssUnmounted:
      let revision =
        if surface in root.canvases: root.canvases[surface].revision
        else: 0'u64
      root.surfaces.mountSurface(
        surface, nodeId, placement, visible = visible, revision = revision
      )
      if surface in root.canvases and not root.canvases[surface].onFrame.isNil:
        discard root.surfaces.requestSurfaceFrame(surface)
    else:
      discard root.surfaces.placeSurface(surface, placement)
      discard root.surfaces.setSurfaceVisible(surface, visible)
      if surface in root.canvases:
        discard root.surfaces.updateSurface(
          surface, root.canvases[surface].revision
        )

proc runRenderSurfaceFrames*(root: UiRoot; nowSeconds: float64): int {.discardable.} =
  result = root.surfaces.runSurfaceFrames(nowSeconds)
  if result == 0:
    return
  for surface, canvas in root.canvases.pairs:
    discard root.surfaces.updateSurface(surface, canvas.revision)

proc scheduleRenderSurfaceFrames*(
    root: UiRoot;
    scheduler: var FrameScheduler;
    nowSeconds: float64
) =
  if root.surfaces.needsSurfaceFrame:
    scheduler.markDirty(ddAnimation)
    scheduler.requestDeadline(nowSeconds)

proc runRenderSurfaceFrames*(
    root: UiRoot;
    scheduler: var FrameScheduler;
    nowSeconds: float64;
    targetFramesPerSecond = 60.0
): int {.discardable.} =
  if targetFramesPerSecond.classify in {fcNan, fcInf, fcNegInf} or
      targetFramesPerSecond <= 0:
    raise newException(
      ValueError, "surface target frame rate must be positive and finite"
    )
  result = root.runRenderSurfaceFrames(nowSeconds)
  if result > 0:
    scheduler.markDirty(ddPaint)
  if root.surfaces.needsSurfaceFrame:
    scheduler.requestDeadline(nowSeconds + 1.0 / targetFramesPerSecond)

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
  if parent.root != root or not root.tree.isValid(parent.id):
    raise newException(ValueError, "text parent does not belong to this UiRoot")
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
  let menu = result
  root.defaultContextMenuNode = some(result.id)
  root.syncDefaultContextMenuStyle()
  for item in items:
    let node = root.text(result, item.label, defaultContextMenuItemStyle(), groups = ["context-menu-item"])
    root.applyHoverStyle(node, defaultContextMenuItemHoverStyle(), priority = 5001)
    root.applyStateStyle(node, {esDisabled}, defaultContextMenuItemDisabledStyle(), priority = 5001)
    root.tree.setState(node.id, esDisabled, item.disabled)
    root.defaultContextMenuItemNodes.add node.id
    let captured = item
    root.events.addInternalEventHandler(node.id, iekPointerDown, proc(event: DispatchResult): EventOutcome =
      if menu.root.dispatchDefaultContextMenuAction(captured):
        handledEvent()
      else:
        ignoredEvent()
    )
    root.events.addInternalEventHandler(node.id, iekClick, proc(event: DispatchResult): EventOutcome =
      handledEvent()
    )

  root.events.addInternalEventHandler(result.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if event.event.key.isSome and event.event.key.get == "Escape":
      discard menu.root.closeDefaultContextMenu()
      return handledEvent()
    ignoredEvent()
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
  if parent.root != root or not root.tree.isValid(parent.id):
    raise newException(ValueError, "image parent does not belong to this UiRoot")
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
  if target.isSome and target.get.root != handle.root:
    raise newException(ValueError, "focus delegate belongs to another UiRoot")
  handle.root.tree.setFocusDelegate(
    handle.id,
    if target.isSome: some(target.get.id) else: none(NodeId)
  )

proc setInert*(handle: NodeHandle; inert = true) =
  handle.root.tree.setInert(handle.id, inert)

proc inert*(handle: NodeHandle): bool =
  handle.root.tree.isInert(handle.id)

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
  if label.isSome and label.get.root != handle.root:
    raise newException(ValueError, "accessible label belongs to another UiRoot")
  handle.root.tree.setAccessibleLabelledBy(
    handle.id,
    if label.isSome: some(label.get.id) else: none(NodeId)
  )

proc setAccessibleDescribedBy*(handle: NodeHandle; description: Option[NodeHandle]) =
  if description.isSome and description.get.root != handle.root:
    raise newException(ValueError, "accessible description belongs to another UiRoot")
  handle.root.tree.setAccessibleDescribedBy(
    handle.id,
    if description.isSome: some(description.get.id) else: none(NodeId)
  )

proc setAccessibleHidden*(handle: NodeHandle; hidden: bool) =
  handle.root.tree.setAccessibleHidden(handle.id, hidden)

proc focusable*(handle: NodeHandle): bool =
  handle.root.tree.isFocusable(handle.id)

proc tabIndex*(handle: NodeHandle): int =
  if handle.valid(): handle.root.tree.nodes[handle.id.nodeIndex].tabIndex
  else: -1

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
  handle.root.dispatchEvent(DispatchResult(
    target: some(handle.id),
    local: local,
    event: event
  )).handled

proc emit*(handle: NodeHandle; kind: InputEventKind; local = none(Vec2)): bool =
  handle.emit(InputEvent(kind: kind), local)

proc subscribe*(
    handle: NodeHandle;
    kind: InputEventKind;
    handler: EventHandler
): EventSubscription =
  if not handle.valid():
    raise newException(ValueError, "cannot subscribe to an inactive node")
  handle.root.events.subscribe(handle.id, kind, handler)

proc unsubscribe*(
    handle: NodeHandle;
    subscription: EventSubscription
): bool {.discardable.} =
  if not handle.valid() or subscription.node != handle.id:
    return false
  handle.root.events.removeEventHandler(subscription)

template handleEventSlot(setterName: untyped; kindValue: InputEventKind) =
  proc setterName*(handle: NodeHandle; handler: EventHandler) =
    handle.root.events.setEventHandler(handle.id, kindValue, handler)

include "../generated/node_event_slots.nim"
