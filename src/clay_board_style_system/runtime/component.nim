import ../input/events
import ./ui_root

type
  ComponentContextError* = object of ValueError

  ComponentMountState* = enum
    cmsCreated,
    cmsRendering,
    cmsMounted,
    cmsUnmounted

  CBSSComponent* = ref object of RootObj
    style*: UiStyle
    rootNode: NodeHandle
    ownerRoot {.cursor.}: UiRoot
    mountState: ComponentMountState

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

componentEventSlot(`onAbort=`, iekAbort)
componentEventSlot(`onAnimationEnd=`, iekAnimationEnd)
componentEventSlot(`onAnimationIteration=`, iekAnimationIteration)
componentEventSlot(`onAnimationStart=`, iekAnimationStart)
componentEventSlot(`onAuxClick=`, iekAuxClick)
componentEventSlot(`onBeforeInput=`, iekBeforeInput)
componentEventSlot(`onBlur=`, iekBlur)
componentEventSlot(`onCancel=`, iekCancel)
componentEventSlot(`onCanPlay=`, iekCanPlay)
componentEventSlot(`onCanPlayThrough=`, iekCanPlayThrough)
componentEventSlot(`onChange=`, iekChange)
componentEventSlot(`onClick=`, iekClick)
componentEventSlot(`onClose=`, iekClose)
componentEventSlot(`onContextMenu=`, iekContextMenu)
componentEventSlot(`onCopy=`, iekCopy)
componentEventSlot(`onCueChange=`, iekCueChange)
componentEventSlot(`onCut=`, iekCut)
componentEventSlot(`onDblClick=`, iekDoubleClick)
componentEventSlot(`onDoubleClick=`, iekDoubleClick)
componentEventSlot(`onCompositionEnd=`, iekCompositionEnd)
componentEventSlot(`onCompositionStart=`, iekCompositionStart)
componentEventSlot(`onCompositionUpdate=`, iekCompositionUpdate)
componentEventSlot(`onDrag=`, iekDrag)
componentEventSlot(`onDragEnd=`, iekDragEnd)
componentEventSlot(`onDragEnter=`, iekDragEnter)
componentEventSlot(`onDragExit=`, iekDragExit)
componentEventSlot(`onDragLeave=`, iekDragLeave)
componentEventSlot(`onDragOver=`, iekDragOver)
componentEventSlot(`onDragStart=`, iekDragStart)
componentEventSlot(`onDrop=`, iekDrop)
componentEventSlot(`onDurationChange=`, iekDurationChange)
componentEventSlot(`onEmptied=`, iekEmptied)
componentEventSlot(`onEncrypted=`, iekEncrypted)
componentEventSlot(`onEnded=`, iekEnded)
componentEventSlot(`onError=`, iekError)
componentEventSlot(`onFocus=`, iekFocus)
componentEventSlot(`onFullscreenChange=`, iekFullscreenChange)
componentEventSlot(`onFullscreenError=`, iekFullscreenError)
componentEventSlot(`onGotPointerCapture=`, iekGotPointerCapture)
componentEventSlot(`onInput=`, iekInput)
componentEventSlot(`onInvalid=`, iekInvalid)
componentEventSlot(`onKeyDown=`, iekKeyDown)
componentEventSlot(`onKeyUp=`, iekKeyUp)
componentEventSlot(`onLoad=`, iekLoad)
componentEventSlot(`onLoadEnd=`, iekLoadEnd)
componentEventSlot(`onLoadedData=`, iekLoadedData)
componentEventSlot(`onLoadedMetadata=`, iekLoadedMetadata)
componentEventSlot(`onLoadStart=`, iekLoadStart)
componentEventSlot(`onLostPointerCapture=`, iekLostPointerCapture)
componentEventSlot(`onMouseDown=`, iekMouseDown)
componentEventSlot(`onMouseEnter=`, iekMouseEnter)
componentEventSlot(`onMouseLeave=`, iekMouseLeave)
componentEventSlot(`onMouseMove=`, iekMouseMove)
componentEventSlot(`onMouseOut=`, iekMouseOut)
componentEventSlot(`onMouseOver=`, iekMouseOver)
componentEventSlot(`onMouseUp=`, iekMouseUp)
componentEventSlot(`onPause=`, iekPause)
componentEventSlot(`onPaste=`, iekPaste)
componentEventSlot(`onPenButtonDown=`, iekPenButtonDown)
componentEventSlot(`onPenButtonUp=`, iekPenButtonUp)
componentEventSlot(`onPenProximityIn=`, iekPenProximityIn)
componentEventSlot(`onPenProximityOut=`, iekPenProximityOut)
componentEventSlot(`onPlay=`, iekPlay)
componentEventSlot(`onPlaying=`, iekPlaying)
componentEventSlot(`onPointerCancel=`, iekPointerCancel)
componentEventSlot(`onPointerDown=`, iekPointerDown)
componentEventSlot(`onPointerEnter=`, iekPointerEnter)
componentEventSlot(`onPointerLeave=`, iekPointerLeave)
componentEventSlot(`onPointerMove=`, iekPointerMove)
componentEventSlot(`onPointerOut=`, iekPointerOut)
componentEventSlot(`onPointerOver=`, iekPointerOver)
componentEventSlot(`onPointerUp=`, iekPointerUp)
componentEventSlot(`onProgress=`, iekProgress)
componentEventSlot(`onRateChange=`, iekRateChange)
componentEventSlot(`onReset=`, iekReset)
componentEventSlot(`onResize=`, iekResize)
componentEventSlot(`onScroll=`, iekScroll)
componentEventSlot(`onScrollEnd=`, iekScrollEnd)
componentEventSlot(`onSeeked=`, iekSeeked)
componentEventSlot(`onSeeking=`, iekSeeking)
componentEventSlot(`onSelect=`, iekSelect)
componentEventSlot(`onShow=`, iekShow)
componentEventSlot(`onStalled=`, iekStalled)
componentEventSlot(`onSubmit=`, iekSubmit)
componentEventSlot(`onSuspend=`, iekSuspend)
componentEventSlot(`onTextInput=`, iekTextInput)
componentEventSlot(`onTimeUpdate=`, iekTimeUpdate)
componentEventSlot(`onToggle=`, iekToggle)
componentEventSlot(`onTouchCancel=`, iekTouchCancel)
componentEventSlot(`onTouchEnd=`, iekTouchEnd)
componentEventSlot(`onTouchMove=`, iekTouchMove)
componentEventSlot(`onTouchStart=`, iekTouchStart)
componentEventSlot(`onTransitionEnd=`, iekTransitionEnd)
componentEventSlot(`onVolumeChange=`, iekVolumeChange)
componentEventSlot(`onWaiting=`, iekWaiting)
componentEventSlot(`onWheel=`, iekWheel)
