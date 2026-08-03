import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

type
  SaveButton = ref object of CBSSComponent
    label: string
    clicks: ref int

  Panel = ref object of CBSSComponent
    title: string
    child: SaveButton

  EmptyComponent = ref object of CBSSComponent

  OtherRootComponent = ref object of CBSSComponent
    otherRoot: UiRoot
    nested: SaveButton

  LifecycleComponent = ref object of CBSSComponent
    mounts: ref int
    unmounts: ref int

  OrderedComponent = ref object of CBSSComponent
    name: string
    order: ref seq[string]
    child: OrderedComponent

  FailingRenderComponent = ref object of CBSSComponent
    child: LifecycleComponent

  FailingMountComponent = ref object of CBSSComponent
    unmounts: ref int

  DoubleRootComponent = ref object of CBSSComponent

  EventComponent = ref object of CBSSComponent
    changes: ref int
    keyDowns: ref int

  RecoveringComponent = ref object of CBSSComponent
    otherRoot: UiRoot
    failingChild: FailingRenderComponent

  HookContextComponent = ref object of CBSSComponent
    mountContextRejected: ref bool
    unmountContextRejected: ref bool

  HookContextHost = ref object of CBSSComponent
    child: HookContextComponent

proc saveButtonStyle(): UiStyle =
  uiStyle([
    decl("width", px(96)),
    decl("background-color", colorValue(rgb(0.10, 0.35, 0.60)))
  ])

proc render(self: SaveButton) =
  proc onSave(event: DispatchResult): bool =
    inc self.clicks[]
    return true

  ui.box(self, ownedStyle = saveButtonStyle()):
    ui.text(self.label)

  self.onClick = onSave

proc render(self: Panel) =
  ui.box(self):
    ui.text(self.title)
    ui.mount(self.child)

proc render(self: EmptyComponent) =
  discard self

proc render(self: OtherRootComponent) =
  ui.box(self):
    self.otherRoot.mount(self.nested)
    ui.text("first root")

proc render(self: LifecycleComponent) =
  ui.box(self):
    ui.text("lifecycle")

method onMount(self: LifecycleComponent) =
  inc self.mounts[]

method onUnmount(self: LifecycleComponent) =
  inc self.unmounts[]

proc render(self: OrderedComponent) =
  ui.box(self):
    ui.text(self.name)
    if not self.child.isNil:
      ui.mount(self.child)

method onUnmount(self: OrderedComponent) =
  self.order[].add self.name

proc render(self: FailingRenderComponent) =
  ui.box(self):
    ui.mount(self.child)
    raise newException(ValueError, "render failed")

proc render(self: FailingMountComponent) =
  ui.box(self):
    ui.text("mount failure")

method onMount(self: FailingMountComponent) =
  raise newException(ValueError, "mount hook failed")

method onUnmount(self: FailingMountComponent) =
  inc self.unmounts[]

proc render(self: DoubleRootComponent) =
  ui.box(self):
    ui.text("first")
  ui.box(self):
    ui.text("second")

proc render(self: EventComponent) =
  proc handleChange(event: DispatchResult): bool =
    inc self.changes[]
    return true

  proc handleKeyDown(event: DispatchResult): bool =
    inc self.keyDowns[]
    return true

  ui.box(self):
    ui.text("events")

  self.onChange = handleChange
  self.onKeyDown = handleKeyDown

proc render(self: RecoveringComponent) =
  ui.box(self):
    try:
      self.otherRoot.mount(self.failingChild)
    except ValueError:
      discard
    ui.text("recovered on the original root")

proc render(self: HookContextComponent) =
  ui.box(self):
    ui.text("hook context")

method onMount(self: HookContextComponent) =
  try:
    discard ui.box()
  except ComponentContextError:
    self.mountContextRejected[] = true

method onUnmount(self: HookContextComponent) =
  try:
    discard ui.box()
  except ComponentContextError:
    self.unmountContextRejected[] = true

proc render(self: HookContextHost) =
  ui.box(self):
    ui.mount(self.child)

proc resolvedStyles(root: UiRoot): ResolvedTree =
  var diagnostics: Diagnostics
  result = resolveTreeStyles(
    root.tree,
    root.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors

proc aliveNodeCount(tree: Tree): int =
  for node in tree.nodes:
    if node.alive:
      inc result

suite "typed component authoring":
  test "component types mount with ordinary Nim syntax":
    let root = initUiRoot()
    let clicks = new int
    let button = root.mount(
      SaveButton(
        label: "Save",
        clicks: clicks,
        style: uiStyle([
          decl("width", px(160)),
          decl("height", px(44))
        ])
      )
    )

    check button.mounted
    check button.state == cmsMounted
    check button.node.valid
    check root.tree.root == some(button.node.id)
    check root.tree.nodes[button.node.id.nodeIndex].children.len == 1
    let label = root.tree.nodes[button.node.id.nodeIndex].children[0]
    check root.tree.nodes[label.nodeIndex].text == "Save"

    let styles = root.resolvedStyles()
    let computed = styles.styles[button.node.id.nodeIndex]
    check computed.layout.width == some(96.0'f32)
    check computed.layout.height == some(44.0'f32)

    check root.events.emit(root.tree, button.node.id, iekClick)
    check clicks[] == 1

  test "nested mounts use the current component parent":
    let root = initUiRoot()
    let child = SaveButton(label: "Nested", clicks: new int)
    let panel = root.mount(Panel(title: "Toolbar", child: child))

    check panel.mounted
    check child.mounted
    check root.tree.nodes[panel.node.id.nodeIndex].children.len == 2
    check root.tree.nodes[panel.node.id.nodeIndex].children[1] == child.node.id

  test "nested mounts on another root restore the previous ui context":
    let firstRoot = initUiRoot()
    let secondRoot = initUiRoot()
    let nested = SaveButton(label: "Second", clicks: new int)
    let outer = firstRoot.mount(
      OtherRootComponent(otherRoot: secondRoot, nested: nested)
    )

    check outer.node.root == firstRoot
    check nested.node.root == secondRoot
    check firstRoot.tree.nodes[outer.node.id.nodeIndex].children.len == 1
    check secondRoot.tree.root == some(nested.node.id)

  test "ui outside render reports an authoring error":
    expect ComponentContextError:
      discard ui.box()

  test "render must create one component root":
    let root = initUiRoot()
    let component = EmptyComponent()

    expect ComponentContextError:
      root.mount(component)
    check component.state == cmsCreated
    check not component.mounted

    expect ComponentContextError:
      discard ui.box()

  test "the same component instance cannot be mounted twice":
    let root = initUiRoot()
    let component = SaveButton(label: "Once", clicks: new int)
    discard root.mount(component)

    expect ComponentContextError:
      root.mount(component)

  test "mount and subtree disposal run lifecycle hooks once":
    let root = initUiRoot()
    let mounts = new int
    let unmounts = new int
    let component = root.mount(
      LifecycleComponent(mounts: mounts, unmounts: unmounts)
    )
    check mounts[] == 1
    check unmounts[] == 0

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check unmounts[] == 1
    check component.state == cmsUnmounted
    check not component.mounted
    expect ComponentContextError:
      discard component.node

  test "disposing a parent unmounts child components before their parent":
    let root = initUiRoot()
    let order = new seq[string]
    let child = OrderedComponent(name: "child", order: order)
    let parent = root.mount(
      OrderedComponent(name: "parent", order: order, child: child)
    )

    var interaction = initInteractionState()
    check root.disposeSubtree(parent.node, interaction)
    check order[] == @["child", "parent"]

  test "render failure rolls back its root and mounted children":
    let root = initUiRoot()
    let childUnmounts = new int
    let child = LifecycleComponent(
      mounts: new int,
      unmounts: childUnmounts
    )
    let component = FailingRenderComponent(child: child)

    expect ValueError:
      root.mount(component)

    check component.state == cmsCreated
    check child.state == cmsUnmounted
    check childUnmounts[] == 1
    check root.tree.root.isNone
    check root.tree.aliveNodeCount == 0

  test "mount hook failure rolls back and runs unmount cleanup":
    let root = initUiRoot()
    let unmounts = new int
    let component = FailingMountComponent(unmounts: unmounts)

    expect ValueError:
      root.mount(component)

    check component.state == cmsUnmounted
    check unmounts[] == 1
    check root.tree.root.isNone
    check root.tree.aliveNodeCount == 0

  test "a component cannot declare two root boxes":
    let root = initUiRoot()
    let component = DoubleRootComponent()

    expect ComponentContextError:
      root.mount(component)

    check component.state == cmsCreated
    check root.tree.root.isNone
    check root.tree.aliveNodeCount == 0

  test "the UiRoot retains a mounted component without a caller variable":
    let root = initUiRoot()
    let mounts = new int
    let unmounts = new int
    discard root.mount(
      LifecycleComponent(mounts: mounts, unmounts: unmounts)
    )

    check mounts[] == 1
    check root.tree.root.isSome
    let mountedRoot = NodeHandle(root: root, id: root.tree.root.get)
    var interaction = initInteractionState()
    check root.disposeSubtree(mountedRoot, interaction)
    check unmounts[] == 1

  test "component event properties target the component root":
    let root = initUiRoot()
    let changes = new int
    let keyDowns = new int
    let component = root.mount(
      EventComponent(changes: changes, keyDowns: keyDowns)
    )

    check root.events.emit(root.tree, component.node.id, iekChange)
    check root.events.emit(root.tree, component.node.id, iekKeyDown)
    check changes[] == 1
    check keyDowns[] == 1

  test "a failed nested mount restores the previous render root":
    let firstRoot = initUiRoot()
    let secondRoot = initUiRoot()
    let failingChild = FailingRenderComponent(
      child: LifecycleComponent(mounts: new int, unmounts: new int)
    )
    let outer = firstRoot.mount(
      RecoveringComponent(
        otherRoot: secondRoot,
        failingChild: failingChild
      )
    )

    check outer.mounted
    check firstRoot.tree.nodes[outer.node.id.nodeIndex].children.len == 1
    check secondRoot.tree.root.isNone
    check secondRoot.tree.aliveNodeCount == 0

  test "nil roots and component instances fail before mutating a tree":
    let root = initUiRoot()
    let nilRoot: UiRoot = nil
    let nilComponent: SaveButton = nil

    expect ComponentContextError:
      nilRoot.mount(SaveButton(label: "Invalid", clicks: new int))
    expect ComponentContextError:
      root.mount(nilComponent)
    check root.tree.root.isNone

  test "lifecycle hooks cannot mutate a nested render context through ui":
    let root = initUiRoot()
    let mountContextRejected = new bool
    let unmountContextRejected = new bool
    let child = HookContextComponent(
      mountContextRejected: mountContextRejected,
      unmountContextRejected: unmountContextRejected
    )
    let host = root.mount(HookContextHost(child: child))

    check mountContextRejected[]
    check root.tree.nodes[host.node.id.nodeIndex].children == @[child.node.id]

    var interaction = initInteractionState()
    check root.disposeSubtree(host.node, interaction)
    check unmountContextRejected[]
