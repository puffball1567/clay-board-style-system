import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc fixedStyle(width, height: float32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(height))
  ])

proc layoutFor(ui: UiRoot): LayoutResult =
  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors
  computeLayout(ui.tree, styles, size(640, 480))

proc hasChange(
    changes: openArray[AtspiChange];
    kind: AtspiChangeKind;
    path: string
): bool =
  for change in changes:
    if change.kind == kind and change.objectPath == path:
      return true
  false

suite "AT-SPI platform-neutral adapter":
  test "snapshot uses stable official root and exposes roles, relations, and geometry":
    let ui = initUiRoot()
    let app = ui.box(fixedStyle(400, 240), id = "app")
    ui.pushParent(app)
    let save = ui.button("Save", style = fixedStyle(120, 32))
    save.container.setCode("save-action")
    let name = ui.textInput(
      TextInputParams(value: "Ada"),
      style = fixedStyle(180, 32)
    )
    discard ui.label("Account name", target = some(name.container))
    let volume = ui.slider(
      value = 25,
      min = 0,
      max = 100,
      style = fixedStyle(180, 32)
    )
    ui.popParent()

    let snapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "CBSS test", "0.1-test")
    let root = snapshot.nodeAt(atspiRootPath)
    let saveNode = snapshot.nodeAt(objectPathFor(save.container.nodeId))
    let nameNode = snapshot.nodeAt(objectPathFor(name.container.nodeId))
    let volumeNode = snapshot.nodeAt(objectPathFor(volume.container.nodeId))

    check root.isSome
    check root.get.parentPath == atspiNullPath
    check root.get.role == atrApplication
    check atiApplication in root.get.interfaces
    check objectPathFor(save.container.nodeId) in root.get.childPaths

    check saveNode.isSome
    check saveNode.get.role == atrPushButton
    check saveNode.get.name == "Save"
    check saveNode.get.accessibleId == "save-action"
    check saveNode.get.parentPath == atspiRootPath
    check saveNode.get.bounds.isSome
    check atiAction in saveNode.get.interfaces
    check atiComponent in saveNode.get.interfaces
    check saveNode.get.actions == @["activate"]

    check nameNode.get.role == atrEntry
    check nameNode.get.name == "Account name"
    check nameNode.get.value == "Ada"
    check atiText notin nameNode.get.interfaces
    check atiEditableText notin nameNode.get.interfaces

    check volumeNode.get.role == atrSlider
    check volumeNode.get.valueNow == some(25.0'f32)
    check volumeNode.get.valueMin == some(0.0'f32)
    check volumeNode.get.valueMax == some(100.0'f32)
    check atiValue notin volumeNode.get.interfaces

  test "only advertised enabled actions dispatch into the existing UI event path":
    let ui = initUiRoot()
    let app = ui.box(fixedStyle(300, 100))
    ui.pushParent(app)
    let save = ui.button("Save", style = fixedStyle(120, 32))
    let disabled = ui.button(
      ButtonParams(label: "Delete", disabled: true),
      style = fixedStyle(120, 32)
    )
    ui.popParent()
    var saves = 0
    save.onClick = proc(event: DispatchResult): EventOutcome =
      inc saves
      true

    let snapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Actions")
    check ui.performAtspiAction(snapshot, objectPathFor(save.container.nodeId))
    check saves == 1
    check not ui.performAtspiAction(snapshot, objectPathFor(save.container.nodeId), "delete")
    check not ui.performAtspiAction(snapshot, objectPathFor(disabled.container.nodeId))
    check saves == 1

  test "switch maps to a toggle button with checked state and activation":
    let ui = initUiRoot()
    let app = ui.box(fixedStyle(300, 100))
    ui.pushParent(app)
    let live = ui.switch("Live updates", style = fixedStyle(140, 32))
    ui.popParent()

    var snapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Switch")
    let path = objectPathFor(live.container.nodeId)
    let before = snapshot.nodeAt(path).get
    check before.role == atrToggleButton
    check before.actions == @["activate"]
    check atsChecked notin before.states

    check ui.performAtspiAction(snapshot, path)
    check live.checked()
    snapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Switch")
    check atsChecked in snapshot.nodeAt(path).get.states
    check snapshot.nodeAt(path).get.value == "true"

  test "hidden and inert controls cannot be activated through stale snapshots":
    let ui = initUiRoot()
    let app = ui.box(fixedStyle(300, 100))
    ui.pushParent(app)
    let action = ui.button("Action", style = fixedStyle(120, 32))
    ui.popParent()
    var activations = 0
    action.onClick = proc(event: DispatchResult): EventOutcome =
      inc activations
      true

    app.setInert()
    let hiddenSnapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Actions")
    let path = objectPathFor(action.container.nodeId)
    let hiddenNode = hiddenSnapshot.nodeAt(path).get
    check atsShowing notin hiddenNode.states
    check atsVisible notin hiddenNode.states
    check not ui.performAtspiAction(hiddenSnapshot, path)
    check activations == 0

    app.setInert(false)
    let visibleSnapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Actions")
    check ui.performAtspiAction(visibleSnapshot, path)
    check activations == 1

  test "hidden semantic subtrees keep geometry without advertising visibility":
    let ui = initUiRoot()
    let dialog = ui.dialog(
      title = "Confirm",
      body = "Continue?",
      style = fixedStyle(240, 100)
    )
    ui.pushParent(dialog.container)
    let accept = ui.button("Accept", style = fixedStyle(120, 32))
    ui.popParent()

    var snapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Visibility")
    let dialogPath = objectPathFor(dialog.container.nodeId)
    let acceptPath = objectPathFor(accept.container.nodeId)
    check snapshot.nodeAt(dialogPath).get.bounds.isSome
    check atsShowing notin snapshot.nodeAt(dialogPath).get.states
    check atsVisible notin snapshot.nodeAt(acceptPath).get.states

    check dialog.show()
    snapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Visibility")
    check atsShowing in snapshot.nodeAt(dialogPath).get.states
    check atsVisible in snapshot.nodeAt(acceptPath).get.states

  test "snapshot diff reports semantic, state, geometry, and removal changes":
    let ui = initUiRoot()
    let app = ui.box(fixedStyle(300, 100))
    ui.pushParent(app)
    let checkbox = ui.checkbox("Remember", style = fixedStyle(140, 32))
    ui.popParent()
    let before = ui.buildAtspiSnapshot(ui.layoutFor(), "Diff")
    let path = objectPathFor(checkbox.container.nodeId)

    checkbox.setLabel("Keep signed in")
    checkbox.setChecked(true)
    let after = ui.buildAtspiSnapshot(ui.layoutFor(), "Diff")
    let changed = diffAtspiSnapshots(before, after)

    check changed.hasChange(ackName, path)
    check changed.hasChange(ackValue, path)
    check changed.hasChange(ackState, path)

    var removed = after
    removed.nodes.setLen(removed.nodes.len - 1)
    check diffAtspiSnapshots(after, removed).hasChange(
      ackRemoved,
      after.nodes[^1].objectPath
    )

  test "transport commits snapshots atomically and retains the last successful state":
    let ui = initUiRoot()
    let app = ui.box(fixedStyle(300, 100))
    ui.pushParent(app)
    let checkbox = ui.checkbox("Remember", style = fixedStyle(140, 32))
    ui.popParent()
    let layout = ui.layoutFor()
    var publications = 0
    var lastChanges: seq[AtspiChange]
    var allowPublish = true
    let adapter = initAtspiAdapter(AtspiTransport(
      publish: proc(snapshot: AtspiSnapshot; changes: seq[AtspiChange]): bool =
        inc publications
        lastChanges = changes
        allowPublish
    ))

    check adapter.refresh(ui, layout, "Transport")
    check adapter.published
    check publications == 1
    check lastChanges.len == adapter.snapshot.nodes.len

    checkbox.setChecked(true)
    check adapter.refresh(ui, layout, "Transport")
    check publications == 2
    check lastChanges.hasChange(ackState, objectPathFor(checkbox.container.nodeId))
    let committedValue = adapter.snapshot.nodeAt(
      objectPathFor(checkbox.container.nodeId)
    ).get.value

    allowPublish = false
    checkbox.setChecked(false)
    check not adapter.refresh(ui, layout, "Transport")
    check publications == 3
    check adapter.snapshot.nodeAt(
      objectPathFor(checkbox.container.nodeId)
    ).get.value == committedValue

  test "invalid semantic state maps to AT-SPI":
    let ui = initUiRoot()
    let app = ui.box(fixedStyle(300, 100))
    ui.pushParent(app)
    let input = ui.textInput(
      "",
      validationRules[string]().required(),
      reportOn = ValidationReport.onSubmit,
      style = fixedStyle(180, 32)
    )
    ui.popParent()
    let snapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Validation")
    let node = snapshot.nodeAt(objectPathFor(input.container.nodeId))

    check node.isSome
    check atsInvalid in node.get.states

    input.setDisabled(true)
    let disabledSnapshot = ui.buildAtspiSnapshot(ui.layoutFor(), "Validation")
    let disabledNode = disabledSnapshot.nodeAt(
      objectPathFor(input.container.nodeId)
    )
    check disabledNode.isSome
    check atsEnabled notin disabledNode.get.states
    check atsSensitive notin disabledNode.get.states
    check atsInvalid notin disabledNode.get.states
