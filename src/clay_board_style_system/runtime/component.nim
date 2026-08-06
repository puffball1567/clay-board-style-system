import std/options

import ../core/node
import ../input/events
import ./invalidation
import ./ui_root

type
  ComponentContextError* = object of ValueError

  ComponentMountState* = enum
    cmsCreated,
    cmsRendering,
    cmsMounted,
    cmsUnmounted

  ComponentFlowState* = enum
    cfsMaterialized,
    cfsCollapsed

  CBSSComponent* = ref object of RootObj
    style*: UiStyle
    rootNode: NodeHandle
    ownerRoot {.cursor.}: UiRoot
    mountState: ComponentMountState
    flowState: ComponentFlowState

type RenderContextFrame = object
  root {.cursor.}: UiRoot
  previous: ptr RenderContextFrame

var activeRenderContext {.threadvar.}: ptr RenderContextFrame

proc activeUiRoot(): lent UiRoot =
  if activeRenderContext.isNil:
    raise newException(
      ComponentContextError,
      "ui is only available while CBSS is rendering a mounted component"
    )
  activeRenderContext[].root

template ui*: UiRoot =
  activeUiRoot()

proc state*(self: CBSSComponent): ComponentMountState =
  if self.isNil:
    return cmsUnmounted
  self.mountState

proc mounted*(self: CBSSComponent): bool =
  not self.isNil and self.mountState == cmsMounted and self.rootNode.valid

proc materialized*(self: CBSSComponent): bool =
  not self.isNil and self.flowState == cfsMaterialized

proc setMaterialized*(self: CBSSComponent; materialized: bool): bool {.discardable.} =
  ## Keep the component mounted at a stable sibling position while allowing its
  ## library-owned state to contribute either a normal flow item or no item.
  if self.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  let nextState = if materialized: cfsMaterialized else: cfsCollapsed
  if self.flowState == nextState:
    return false
  self.flowState = nextState
  if self.rootNode.valid:
    self.rootNode.root.tree.setFlowCollapsed(
      self.rootNode.id,
      nextState == cfsCollapsed
    )
  if self.mountState == cmsMounted and not self.ownerRoot.isNil:
    let parent = self.ownerRoot.tree.nodes[self.rootNode.id.nodeIndex].parent
    let layoutRoot = if parent.isSome: parent.get else: self.rootNode.id
    self.ownerRoot.invalidate(
      layoutRoot,
      {ddStyle, ddLayout, ddPaint, ddHit}
    )
  true

proc node*(self: CBSSComponent): lent NodeHandle =
  if self.isNil or not self.rootNode.valid:
    raise newException(ComponentContextError, "component does not have a mounted root node")
  self.rootNode

proc prepareRoot(root: UiRoot; self: CBSSComponent) =
  if self.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  if self.mountState != cmsRendering or self.ownerRoot != root:
    raise newException(
      ComponentContextError,
      "component roots can only be created by their active mount context"
    )
  if self.rootNode.valid:
    raise newException(ComponentContextError, "component already has a root node")

proc beginRoot(root: UiRoot; self: CBSSComponent; handle: NodeHandle) =
  if handle.root != root or not handle.valid:
    raise newException(ComponentContextError, "component root belongs to another UiRoot")
  self.rootNode = handle
  root.tree.setFlowCollapsed(handle.id, self.flowState == cfsCollapsed)

template box*(
    root: UiRoot;
    self: CBSSComponent;
    ownedStyle: UiStyle;
    body: untyped
) =
  block:
    root.prepareRoot(self)
    let componentRoot {.gensym.} = root.box(self.style + ownedStyle)
    root.beginRoot(self, componentRoot)
    root.pushParent(componentRoot)
    try:
      body
    finally:
      root.popParent()

template box*(root: UiRoot; self: CBSSComponent; body: untyped) =
  root.box(self, ownedStyle = UiStyle()):
    body

proc finishUnmount(self: CBSSComponent) =
  self.rootNode = NodeHandle()
  self.ownerRoot = nil
  self.mountState = cmsUnmounted

method onMount*(self: CBSSComponent) {.base.} =
  discard

method onUnmount*(self: CBSSComponent) {.base.} =
  discard

proc unmountComponent(component: ComponentRetention) {.nimcall.} =
  if component.isNil or not (component of CBSSComponent):
    raise newException(ComponentContextError, "invalid component retention binding")
  let self = CBSSComponent(component)
  self.finishUnmount()
  let previousContext = activeRenderContext
  activeRenderContext = nil
  try:
    self.onUnmount()
  finally:
    activeRenderContext = previousContext

proc mount*[T: CBSSComponent](root: UiRoot; self: T): T {.discardable.} =
  mixin render

  if root.isNil:
    raise newException(ComponentContextError, "component mount requires a UiRoot")
  if self.isNil:
    raise newException(ComponentContextError, "component mount requires an instance")
  if self.mountState in {cmsRendering, cmsMounted}:
    raise newException(ComponentContextError, "component instance is already mounted")

  self.rootNode = NodeHandle()
  self.ownerRoot = root
  self.mountState = cmsRendering
  var renderContext = RenderContextFrame(
    root: root,
    previous: activeRenderContext
  )
  activeRenderContext = addr renderContext

  var mountedSuccessfully = false
  try:
    render(self)
    if not self.rootNode.valid or self.rootNode.root != root:
      raise newException(
        ComponentContextError,
        "render(self) must create exactly one root with ui.box(self, ...)"
      )
    self.mountState = cmsMounted
    root.retainMountedComponent(
      self.rootNode,
      ComponentRetention(self),
      unmountComponent
    )
    let previousContext = activeRenderContext
    activeRenderContext = nil
    try:
      self.onMount()
    finally:
      activeRenderContext = previousContext
    mountedSuccessfully = true
  finally:
    activeRenderContext = renderContext.previous
    if not mountedSuccessfully:
      let mountFailure = getCurrentException()
      if self.rootNode.valid:
        var interaction = initInteractionState()
        try:
          discard root.disposeSubtree(self.rootNode, interaction)
        except CatchableError:
          if mountFailure.isNil:
            raise
      if self.mountState != cmsUnmounted:
        self.rootNode = NodeHandle()
        self.ownerRoot = nil
        self.mountState = cmsCreated

  return self

template componentEventSlot(setterName: untyped; kindValue: InputEventKind) =
  proc setterName*(self: CBSSComponent; handler: EventHandler) =
    self.node().root.events.setEventHandler(self.node().id, kindValue, handler)

proc subscribe*(
    self: CBSSComponent;
    kind: InputEventKind;
    handler: EventHandler
): EventSubscription =
  self.node().subscribe(kind, handler)

proc unsubscribe*(
    self: CBSSComponent;
    subscription: EventSubscription
): bool {.discardable.} =
  self.node().unsubscribe(subscription)

include "../generated/component_event_slots.nim"
