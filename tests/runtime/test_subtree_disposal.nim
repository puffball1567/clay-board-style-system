import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc resolvedStyles(ui: UiRoot): ResolvedTree =
  var diagnostics: Diagnostics
  result = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors

suite "dynamic subtree disposal":
  test "tree slots are reused without reviving stale node ids":
    var tree = initTree()
    let app = tree.addBox()
    let oldParent = tree.addBox(parent = some(app))
    let oldChild = tree.addText(oldParent, "old")
    let oldParentIndex = oldParent.nodeIndex
    let oldChildIndex = oldChild.nodeIndex

    let removed = tree.disposeSubtree(oldParent)

    check removed.len == 2
    check not tree.isValid(oldParent)
    check not tree.isValid(oldChild)
    check tree.activeNodeCount() == 1
    check tree.nodes[app.nodeIndex].children.len == 0
    check tree.disposeSubtree(oldParent).len == 0

    let replacementParent = tree.addBox(parent = some(app))
    let replacementChild = tree.addText(replacementParent, "new")
    check replacementParent.nodeIndex in [oldParentIndex, oldChildIndex]
    check replacementChild.nodeIndex in [oldParentIndex, oldChildIndex]
    check replacementParent != oldParent
    check replacementChild != oldChild
    check tree.isValid(replacementParent)
    check tree.isValid(replacementChild)
    expect ValueError:
      discard tree.addBox(parent = some(oldParent))

  test "disposing a subtree clears runtime references before reuse":
    let ui = initUiRoot()
    let app = ui.box()
    let outside = ui.box(parent = some(app))
    let panel = ui.box(
      uiStyle([decl("width", px(111))]),
      parent = some(app)
    )
    ui.pushParent(panel)
    let action = ui.button("Remove")
    ui.popParent()
    outside.setFocusDelegate(some(action.container))
    outside.setAccessibleLabelledBy(some(action.labelNode))
    outside.setAccessibleDescribedBy(some(action.labelNode))

    var clicks = 0
    var blurs = 0
    var observedClicks = 0
    action.onClick = proc(event: DispatchResult): EventOutcome =
      inc clicks
      true
    let observation = action.container.subscribe(
      iekClick,
      proc(event: DispatchResult): EventOutcome =
        inc observedClicks
        ignoredEvent()
    )
    action.container.onBlur = proc(event: DispatchResult): EventOutcome =
      inc blurs
      true

    var popupCalls = 0
    ui.registerPopupCloser(panel.id, proc(target: Option[NodeId]): bool =
      inc popupCalls
      true
    )
    ui.scroll.entries.setLen(ui.tree.nodes.len)
    ui.scroll.entries[action.container.id.nodeIndex] = ScrollMetrics(
      active: true,
      node: some(action.container.id),
      scrolling: true,
      viewport: size(10, 10),
      content: size(10, 20),
      enabledY: true
    )

    var interaction = initInteractionState()
    discard ui.setFocus(
      interaction,
      some(action.container.id),
      focusVisible = true
    )
    interaction.pressedTarget = some(action.container.id)
    interaction.pointerDownPosition = some(vec2(4, 5))
    interaction.hoveredTarget = some(action.container.id)
    interaction.pointerCaptureTarget = some(action.container.id)
    interaction.lastClickTarget = some(action.container.id)
    interaction.dragTarget = some(action.container.id)
    interaction.dragOverTarget = some(action.container.id)
    interaction.scrollTarget = some(action.container.id)
    interaction.scrollbarPointerTarget = some(action.container.id)
    interaction.scrollbarDragging = true
    interaction.clickCount = 2
    ui.requestFocus(some(action.container.id))

    let oldPanel = panel.id
    let oldAction = action.container.id
    let oldLabel = action.labelNode.id
    let oldStyleCount = ui.componentStyles.len
    check ui.disposeSubtree(panel, interaction)

    check not panel.valid()
    check not action.container.valid()
    check not ui.disposeSubtree(panel, interaction)
    check blurs == 1
    check interaction.focusedTarget.isNone
    check interaction.pressedTarget.isNone
    check interaction.pointerDownPosition.isNone
    check interaction.hoveredTarget.isNone
    check interaction.pointerCaptureTarget.isNone
    check interaction.lastClickTarget.isNone
    check interaction.dragTarget.isNone
    check interaction.dragOverTarget.isNone
    check interaction.scrollTarget.isNone
    check interaction.scrollbarPointerTarget.isNone
    check not interaction.scrollbarDragging
    check interaction.clickCount == 0
    check ui.scroll.metricsFor(oldAction).isNone
    check not ui.closeOpenPopups(none(NodeId))
    check popupCalls == 0
    check ui.tree.nodes[outside.id.nodeIndex].focusDelegate.isNone
    check ui.tree.semanticInfo(outside.id).labelledBy.isNone
    check ui.tree.semanticInfo(outside.id).describedBy.isNone
    let request = ui.takeFocusRequest()
    check not request.pending
    check request.target.isNone

    let replacement = ui.box(parent = some(app))
    replacement.applyStyle(uiStyle([decl("height", px(44))]))
    var replacementClicks = 0
    replacement.onClick = proc(event: DispatchResult): EventOutcome =
      inc replacementClicks
      true

    check replacement.id.nodeIndex == oldPanel.nodeIndex or
      replacement.id.nodeIndex == oldAction.nodeIndex or
      replacement.id.nodeIndex == oldLabel.nodeIndex
    check replacement.id != oldPanel
    check replacement.id != oldAction
    check not ui.events.emit(ui.tree, oldAction, iekClick)
    check clicks == 0
    check observedClicks == 0
    check not ui.events.removeEventHandler(observation)
    check replacement.emit(iekClick)
    check replacementClicks == 1
    check ui.componentStyles.len <= oldStyleCount + 1

    let styles = ui.resolvedStyles()
    check styles.styles[replacement.id.nodeIndex].layout.width.isNone
    check styles.styles[replacement.id.nodeIndex].layout.height == some(44.0'f32)

  test "disposed declarative parents cannot capture later nodes":
    let ui = initUiRoot()
    let app = ui.box()
    let panel = ui.box(parent = some(app))
    ui.pushParent(panel)
    var interaction = initInteractionState()

    check ui.disposeSubtree(panel, interaction)
    let independent = ui.box()

    check independent.valid()
    check ui.tree.nodes[independent.id.nodeIndex].parent.isNone

  test "foreign handles and foreign semantic relations are rejected":
    let ui = initUiRoot()
    let foreignUi = initUiRoot()
    let local = ui.box()
    let foreign = foreignUi.box()
    var interaction = initInteractionState()

    expect ValueError:
      discard ui.disposeSubtree(foreign, interaction)
    expect ValueError:
      local.setFocusDelegate(some(foreign))
    expect ValueError:
      local.setAccessibleLabelledBy(some(foreign))
    expect ValueError:
      local.setAccessibleDescribedBy(some(foreign))
    check local.valid()
    check foreign.valid()

  test "reused accessibility slots receive a new object path":
    let ui = initUiRoot()
    let app = ui.box()
    ui.pushParent(app)
    let old = ui.button("Old")
    ui.popParent()
    let oldId = old.container.id
    let oldPath = objectPathFor(oldId)
    var interaction = initInteractionState()

    check ui.disposeSubtree(old.container, interaction)
    ui.pushParent(app)
    let replacement = ui.button("New")
    ui.popParent()

    check replacement.container.id.nodeIndex == oldId.nodeIndex or
      replacement.labelNode.id.nodeIndex == oldId.nodeIndex
    check objectPathFor(replacement.container.id) != oldPath

  test "stale component handles cannot mutate reused component slots":
    let ui = initUiRoot()
    let app = ui.box()
    ui.pushParent(app)
    let old = ui.button("Old")
    ui.popParent()
    var interaction = initInteractionState()
    check ui.disposeSubtree(old.container, interaction)

    ui.pushParent(app)
    let replacement = ui.button("Replacement")
    ui.popParent()
    old.setLabel("stale mutation")
    old.setDisabled(true)

    check ui.tree.nodes[replacement.labelNode.id.nodeIndex].text == "Replacement"
    check esDisabled notin ui.tree.nodes[replacement.container.id.nodeIndex].states

  test "repeated create and dispose keeps node and style capacity bounded":
    let ui = initUiRoot()
    let app = ui.box()
    var interaction = initInteractionState()
    var maximumNodes = ui.tree.nodes.len
    var maximumStyles = ui.componentStyles.len

    for iteration in 0 ..< 200:
      let panel = ui.box(
        uiStyle([decl("width", px(float32(20 + iteration mod 5)))]),
        parent = some(app)
      )
      ui.pushParent(panel)
      let action = ui.button("Action")
      ui.popParent()
      action.container.applyHoverStyle(
        uiStyle([decl("height", px(30))]),
        priority = 2
      )
      action.onClick = proc(event: DispatchResult): EventOutcome = stoppedEvent()
      maximumNodes = max(maximumNodes, ui.tree.nodes.len)
      maximumStyles = max(maximumStyles, ui.componentStyles.len)
      check ui.disposeSubtree(panel, interaction)
      check ui.tree.activeNodeCount() == 1

    check maximumNodes <= 4
    check maximumStyles <= 3
    check ui.tree.nodes.len <= 4
    check ui.componentStyles.len <= 3
    check ui.events.bindings.len == 0
