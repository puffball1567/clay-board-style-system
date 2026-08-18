import std/options

import ../core/node
import ../input/events
import ./invalidation
import ./ui_root

type
  ComponentContextError* = object of ValueError

  ComponentResourceReleaseProc* = proc(
    resource: ComponentOwnedResource
  ) {.nimcall, raises: [].}

  ComponentOwnedResource* = ref object of RootObj
    disposedValue: bool
    releaseCallback: ComponentResourceReleaseProc

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
    ownedResources: seq[ComponentOwnedResource]

proc disposed*(resource: ComponentOwnedResource): bool {.inline.} =
  resource.isNil or resource.disposedValue

proc setReleaseCallback*(
    resource: ComponentOwnedResource;
    callback: ComponentResourceReleaseProc
) =
  if resource.isNil:
    raise newException(ComponentContextError, "owned resource cannot be nil")
  if resource.disposedValue:
    raise newException(ComponentContextError, "owned resource is already disposed")
  if callback.isNil:
    raise newException(ComponentContextError, "resource release callback cannot be nil")
  if resource.releaseCallback != nil:
    raise newException(ComponentContextError, "resource release callback is already set")
  resource.releaseCallback = callback

proc dispose*(resource: ComponentOwnedResource): bool {.discardable.} =
  if resource.isNil or resource.disposedValue:
    return false
  resource.disposedValue = true
  let callback = resource.releaseCallback
  resource.releaseCallback = nil
  if callback != nil:
    callback(resource)
  true

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

proc own*[T: ComponentOwnedResource](self: CBSSComponent; resource: T): T =
  if self.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  if resource.isNil:
    raise newException(ComponentContextError, "owned resource cannot be nil")
  if resource.disposed:
    raise newException(ComponentContextError, "owned resource is already disposed")
  if self.mountState notin {cmsRendering, cmsMounted}:
    raise newException(
      ComponentContextError,
      "resources can only be owned while a component is rendering or mounted"
    )
  for existing in self.ownedResources:
    if existing == resource:
      return resource
  self.ownedResources.add resource
  resource

proc disposeOwnedResources(self: CBSSComponent) =
  if self.isNil:
    return
  for index in countdown(self.ownedResources.high, 0):
    discard self.ownedResources[index].dispose()
  self.ownedResources.setLen(0)

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

proc invalidate*(
    self: CBSSComponent;
    domains: set[DirtyDomain];
    target = none(NodeHandle)
) =
  if self.isNil or self.mountState != cmsMounted or self.ownerRoot.isNil or
      domains == {}:
    return
  let handle = if target.isSome: target.get else: self.rootNode
  if handle.root != self.ownerRoot:
    raise newException(
      ComponentContextError,
      "component invalidation target belongs to another UiRoot"
    )
  if handle.valid:
    self.ownerRoot.invalidate(handle.id, domains)

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
    self.disposeOwnedResources()

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
        self.disposeOwnedResources()
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
