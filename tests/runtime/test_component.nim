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

  ConditionalPanel = ref object of CBSSComponent
    renders: ref int
    clicks: ref int

  ConditionalFlowHost = ref object of CBSSComponent
    panel: ConditionalPanel
    before: NodeHandle
    after: NodeHandle

  TestOwnedResource = ref object of ComponentOwnedResource
    name: string
    releases: ref seq[string]

  ResourceComponent = ref object of CBSSComponent
    releases: ref seq[string]
    first: TestOwnedResource
    second: TestOwnedResource

  FailingResourceComponent = ref object of CBSSComponent
    resource: TestOwnedResource

proc releaseTestResource(resource: ComponentOwnedResource) {.raises: [].} =
  let owned = TestOwnedResource(resource)
  owned.releases[].add owned.name

proc testOwnedResource(
    name: string;
    releases: ref seq[string]
): TestOwnedResource =
  result = TestOwnedResource(name: name, releases: releases)
  result.setReleaseCallback(releaseTestResource)

proc saveButtonStyle(): UiStyle =
  uiStyle([
    decl("width", px(96)),
    decl("background-color", colorValue(rgb(0.10, 0.35, 0.60)))
  ])

proc render(self: SaveButton) =
  proc onSave(event: DispatchResult): EventOutcome =
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
  proc handleChange(event: DispatchResult): EventOutcome =
    inc self.changes[]
    return true

  proc handleKeyDown(event: DispatchResult): EventOutcome =
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

proc render(self: ConditionalPanel) =
  inc self.renders[]
  ui.box(self, ownedStyle = uiStyle([
    decl("height", px(30)),
    decl("background-color", rgb(0.2, 0.4, 0.7))
  ])):
    ui.text("Conditional content")

  self.node.setFocusable()
  self.node.setAccessibleRole(arGroup)
  self.node.setAccessibleName("Conditional panel")
  self.onClick = proc(event: DispatchResult): EventOutcome =
    inc self.clicks[]
    true

proc render(self: ConditionalFlowHost) =
  ui.box(self, ownedStyle = uiStyle([
    decl("width", px(100)),
    decl("flex-direction", keyword("column")),
    decl("gap", px(8))
  ])):
    ui.box(self.before, uiStyle([decl("height", px(10))])):
      discard
    ui.mount(self.panel)
    ui.box(self.after, uiStyle([decl("height", px(10))])):
      discard

proc render(self: ResourceComponent) =
  self.first = self.own(testOwnedResource("first", self.releases))
  self.second = self.own(testOwnedResource("second", self.releases))
  ui.box(self):
    ui.text("resources")

method onUnmount(self: ResourceComponent) =
  self.releases[].add "unmount"

proc render(self: FailingResourceComponent) =
  self.resource = self.own(testOwnedResource("failed", new seq[string]))
  ui.box(self):
    raise newException(ValueError, "resource render failed")

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

proc rectFor(layout: LayoutResult; node: NodeId): Option[Rect] =
  for box in layout.boxes:
    if box.node == node:
      return some(box.rect)
  none(Rect)

proc componentFrame(root: UiRoot): tuple[styles: ResolvedTree, layout: LayoutResult] =
  result.styles = root.resolvedStyles()
  result.layout = computeLayout(root.tree, result.styles, size(100, 120))

proc applyInvalidation(
    root: UiRoot;
    invalidation: UiInvalidation;
    frame: var tuple[styles: ResolvedTree, layout: LayoutResult]
) =
  var diagnostics: Diagnostics
  for dirtyRoot in invalidation.roots:
    check resolveSubtreeStyles(
      root.tree,
      dirtyRoot,
      root.styleSheets(),
      defaultProperties(),
      diagnostics,
      frame.styles
    )
    check relayoutSubtree(
      root.tree,
      frame.styles,
      dirtyRoot,
      frame.layout,
      root.textEngine,
      root.fonts
    )
  check not diagnostics.hasErrors

suite "typed component authoring":
  test "conditional components collapse and materialize in stable normal flow":
    let root = initUiRoot()
    let renders = new int
    let clicks = new int
    let panel = ConditionalPanel(renders: renders, clicks: clicks)
    check panel.setMaterialized(false)
    let host = root.mount(ConditionalFlowHost(panel: panel))

    check not panel.materialized
    check renders[] == 1
    check root.tree.nodes[host.node.id.nodeIndex].children == @[
      host.before.id, panel.node.id, host.after.id
    ]

    var frame = root.componentFrame()
    check frame.styles.styles[panel.node.id.nodeIndex].layout.display == dkNone
    check frame.layout.rectFor(panel.node.id).isNone
    check frame.layout.rectFor(host.after.id).get.y == 18
    for region in buildHitRegions(root.tree, frame.layout, frame.styles):
      check region.node != panel.node.id
    for command in buildPaintCommands(root.tree, frame.styles, frame.layout):
      check command.owner != some(panel.node.id)
    check panel.node.id notin root.focusTargets()
    check not root.events.emit(root.tree, panel.node.id, iekClick)
    check clicks[] == 0
    for semantic in root.accessibilityTree():
      check semantic.node != panel.node.id

    check panel.setMaterialized(true)
    let materializedInvalidation = root.consumeInvalidation()
    check materializedInvalidation.domains == {ddStyle, ddLayout, ddPaint, ddHit}
    check materializedInvalidation.roots == @[host.node.id]
    root.applyInvalidation(materializedInvalidation, frame)
    check frame.styles.styles[panel.node.id.nodeIndex].layout.display != dkNone
    check frame.layout.rectFor(panel.node.id).get.y == 18
    check frame.layout.rectFor(host.after.id).get.y == 56
    var panelHit = false
    for region in buildHitRegions(root.tree, frame.layout, frame.styles):
      if region.node == panel.node.id:
        panelHit = true
    check panelHit
    var panelPaint = false
    for command in buildPaintCommands(root.tree, frame.styles, frame.layout):
      if command.owner == some(panel.node.id):
        panelPaint = true
    check panelPaint
    check panel.node.id in root.focusTargets()
    check root.events.emit(root.tree, panel.node.id, iekClick)
    check clicks[] == 1
    var exposed = false
    for semantic in root.accessibilityTree():
      if semantic.node == panel.node.id:
        exposed = true
    check exposed
    check renders[] == 1

    var interaction = initInteractionState()
    check root.setFocus(interaction, some(panel.node.id), focusVisible = true)

    check not panel.setMaterialized(true)
    check not root.hasPendingInvalidation
    check panel.setMaterialized(false)
    let collapsedInvalidation = root.consumeInvalidation()
    check collapsedInvalidation.domains == {ddStyle, ddLayout, ddPaint, ddHit}
    check collapsedInvalidation.roots == @[host.node.id]
    root.applyInvalidation(collapsedInvalidation, frame)
    check frame.layout.rectFor(panel.node.id).isNone
    check frame.layout.rectFor(host.after.id).get.y == 18
    check root.reconcileFocus(interaction)
    check interaction.focusedTarget.isNone
    check renders[] == 1

    for cycle in 0 ..< 4:
      check panel.setMaterialized(true)
      root.applyInvalidation(root.consumeInvalidation(), frame)
      check frame.layout.rectFor(host.after.id).get.y == 56
      check panel.setMaterialized(false)
      root.applyInvalidation(root.consumeInvalidation(), frame)
      check frame.layout.rectFor(host.after.id).get.y == 18
    check renders[] == 1

  test "pre-mount flow state is retained across deterministic unmount and remount":
    let root = initUiRoot()
    let panel = ConditionalPanel(renders: new int, clicks: new int)
    discard panel.setMaterialized(false)
    discard root.mount(panel)
    check root.tree.isFlowCollapsed(panel.node.id)

    var interaction = initInteractionState()
    check root.disposeSubtree(panel.node, interaction)
    check not panel.materialized
    discard root.mount(panel)
    check root.tree.isFlowCollapsed(panel.node.id)
    check panel.renders[] == 2

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

  test "owned resources release once in reverse order after unmount hooks":
    let root = initUiRoot()
    let releases = new seq[string]
    let component = root.mount(ResourceComponent(releases: releases))
    check not component.first.disposed
    check not component.second.disposed
    check component.own(component.first) == component.first
    expect ComponentContextError:
      component.first.setReleaseCallback(releaseTestResource)

    check component.second.dispose()
    check not component.second.dispose()
    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check releases[] == @["second", "unmount", "first"]
    check component.first.disposed
    check component.second.disposed

  test "render failure releases resources registered before rollback":
    let root = initUiRoot()
    let component = FailingResourceComponent()
    expect ValueError:
      root.mount(component)
    check not component.resource.isNil
    check component.resource.disposed
    check component.state == cmsCreated

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
