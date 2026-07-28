import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "ui root handles":
  test "clipboard reads are cached until the host invalidates them":
    let ui = initUiRoot()
    var providerCalls = 0
    var source = "first"
    ui.configureClipboardTextProvider(proc(): string =
      inc providerCalls
      source
    )

    check ui.clipboardText() == "first"
    source = "second"
    check ui.clipboardText() == "first"
    check providerCalls == 1

    ui.invalidateClipboardText()
    check ui.clipboardText() == "second"
    check providerCalls == 2

  test "clipboard writes refresh the cached paste snapshot":
    let ui = initUiRoot()
    var providerCalls = 0
    var written = ""
    ui.configureClipboardTextProvider(proc(): string =
      inc providerCalls
      "platform"
    )
    ui.configureClipboardTextWriter(proc(text: string) =
      written = text
    )

    ui.writeClipboardText("copied")

    check written == "copied"
    check ui.clipboardText() == "copied"
    check providerCalls == 0

  test "node handles can receive onClick by assignment":
    let ui = initUiRoot()
    let toolbar = ui.box(groups = ["toolbar"])
    let saveButton = ui.box(parent = some(toolbar), groups = ["button", "primary"])
    ui.text(saveButton, "Save")

    var clicked = false
    saveButton.onClick = proc(event: DispatchResult): bool =
      clicked = true
      true

    let handled = ui.events.handle(DispatchResult(
      target: some(saveButton.nodeId),
      local: none(Vec2),
      event: InputEvent(kind: iekClick)
    ))

    check handled
    check clicked
    check ui.tree.nodes.len == 3

  test "node event assignment replaces previous handler":
    let ui = initUiRoot()
    let saveButton = ui.box(groups = ["button"])
    var calls: seq[string] = @[]

    saveButton.onClick = proc(event: DispatchResult): bool =
      calls.add "first"
      true

    saveButton.onClick = proc(event: DispatchResult): bool =
      calls.add "second"
      true

    let handled = ui.events.handle(DispatchResult(
      target: some(saveButton.nodeId),
      local: none(Vec2),
      event: InputEvent(kind: iekClick)
    ))

    check handled
    check calls == @["second"]
    check ui.events.bindings.len == 1

  test "node handles expose standard event assignment names":
    let ui = initUiRoot()
    let input = ui.box(groups = ["input"])
    var typing = ""
    var changed = ""
    var submitted = false

    input.onInput = proc(event: DispatchResult): bool =
      if event.event.text.isSome:
        typing = event.event.text.get
      true

    input.onChange = proc(event: DispatchResult): bool =
      if event.event.text.isSome:
        changed = event.event.text.get
      true

    input.onSubmit = proc(event: DispatchResult): bool =
      submitted = true
      true

    let inputHandled = ui.events.handle(DispatchResult(
      target: some(input.nodeId),
      local: none(Vec2),
      event: inputEvent("draft")
    ))
    let changeHandled = ui.events.handle(DispatchResult(
      target: some(input.nodeId),
      local: none(Vec2),
      event: changeEvent("abc")
    ))

    check inputHandled
    check changeHandled
    check typing == "draft"
    check changed == "abc"
    check input.emit(iekSubmit)
    check submitted

  test "node handles can be used as style targets":
    let ui = initUiRoot()
    let panel = ui.box()

    let sheet = styleSheet([
      rule(target(panel), [
        decl("width", px(120))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, [sheet], defaultProperties(), diagnostics)

    check not diagnostics.hasErrors
    check styles.styles[panel.nodeId.nodeIndex].layout.width == some(120.0'f32)

  test "node handles can carry optional cbss codes":
    let ui = initUiRoot()
    let created = ui.box(code = "created-code")
    let assigned = ui.box()

    assigned.setCode("assigned-code")

    check ui.tree.nodes[created.nodeId.nodeIndex].code == "created-code"
    check ui.tree.nodes[assigned.nodeId.nodeIndex].code == "assigned-code"

  test "cbss codes can be used as style selector conditions":
    let ui = initUiRoot()
    let panel = ui.box(code = "settings-panel")

    let sheet = styleSheet([
      rule(code("settings-panel"), [
        decl("height", px(72))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, [sheet], defaultProperties(), diagnostics)

    check not diagnostics.hasErrors
    check styles.styles[panel.nodeId.nodeIndex].layout.height == some(72.0'f32)

  test "state styles can override direct handle styles":
    let ui = initUiRoot()
    let button = ui.box(uiStyle([
      decl("background-color", colorValue(rgb(0.10, 0.20, 0.30)))
    ]))
    button.applyActiveStyle(uiStyle([
      decl("background-color", colorValue(rgb(0.80, 0.20, 0.10)))
    ]))

    button.addState(esActive)

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)

    check not diagnostics.hasErrors
    check styles.styles[button.nodeId.nodeIndex].box.backgroundColor == some(rgb(0.80, 0.20, 0.10))

  test "reapplying a node style replaces its stylesheet slot":
    let ui = initUiRoot()
    let meter = ui.box()

    meter.applyStyle(uiStyle([decl("width", px(12))]))
    let styleCount = ui.componentStyles.len
    meter.applyStyle(uiStyle([decl("width", px(84))]))

    check ui.componentStyles.len == styleCount
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    check styles.styles[meter.nodeId.nodeIndex].layout.width == some(84.0'f32)

  test "state style replacement is scoped by state and priority":
    let ui = initUiRoot()
    let button = ui.box()
    button.applyActiveStyle(uiStyle([decl("width", px(24))]), priority = 10)
    let styleCount = ui.componentStyles.len
    button.applyActiveStyle(uiStyle([decl("width", px(48))]), priority = 10)
    button.applyFocusStyle(uiStyle([decl("height", px(32))]), priority = 10)

    check ui.componentStyles.len == styleCount + 1
    button.addState(esActive)
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    check styles.styles[button.nodeId.nodeIndex].layout.width == some(48.0'f32)

  test "box blocks create declarative parent-child structure":
    let ui = initUiRoot()
    var app, saveButton: NodeHandle

    ui.box(app, "app"):
      ui.box("header"):
        ui.box("toolbar"):
          ui.box(saveButton, "button", "primary"):
            ui.text("Save")
            ui.text("Ctrl+S", groups = ["shortcut"])

    saveButton.onClick = proc(event: DispatchResult): bool =
      true

    check ui.tree.root == some(app.nodeId)
    check ui.tree.nodes[app.nodeId.nodeIndex].children.len == 1
    let header = ui.tree.nodes[app.nodeId.nodeIndex].children[0]
    check ui.tree.nodes[header.nodeIndex].children.len == 1
    let toolbar = ui.tree.nodes[header.nodeIndex].children[0]
    check ui.tree.nodes[toolbar.nodeIndex].children == @[saveButton.nodeId]
    check ui.tree.nodes[saveButton.nodeId.nodeIndex].children.len == 2
    check ui.events.bindings.len == 1

  test "ui can be split into component-like procedures":
    type
      ToolbarParams = object
        title: string

    proc toolbarStyle(): UiStyle =
      uiStyle([
        decl("width", px(240)),
        decl("height", px(48))
      ])

    proc saveButtonStyle(): UiStyle =
      uiStyle([
        decl("width", px(96)),
        decl("background-color", colorValue(rgb(0.10, 0.35, 0.60)))
      ])

    proc wideButtonStyle(): UiStyle =
      saveButtonStyle() + uiStyle([
        decl("width", px(144))
      ])

    proc titleStyle(): UiStyle =
      uiStyle([
        decl("font-size", px(18))
      ])

    proc externalToolbarStyle(): StyleSheet =
      styleSheet([
        rule(group("toolbar"), [
          decl("width", px(120))
        ])
      ])

    proc onSave(event: DispatchResult): bool =
      true

    proc SaveButton(ui: UiRoot; style = saveButtonStyle()): NodeHandle {.discardable.} =
      ui.box(result, style):
        ui.text("Save")
      result.onClick = onSave

    proc Toolbar(
        ui: UiRoot;
        style = toolbarStyle();
        params = ToolbarParams(title: "Editor")
    ): NodeHandle {.discardable.} =
      ui.box(result, style, "toolbar"):
        ui.text(params.title, titleStyle())
        SaveButton(ui, style = wideButtonStyle())

    proc App(ui: UiRoot): NodeHandle {.discardable.} =
      ui.box(result, uiStyle([
        decl("padding", px(16))
      ])):
        Toolbar(ui, params = ToolbarParams(title: "Editor"))
        ui.box(uiStyle([
          decl("padding", px(12))
        ])):
          ui.text("Document body")

    let ui = initUiRoot()
    let app = App(ui)

    check ui.tree.root == some(app.nodeId)
    check ui.tree.nodes[app.nodeId.nodeIndex].children.len == 2
    check ui.events.bindings.len == 1

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets([externalToolbarStyle()]), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let toolbar = ui.tree.nodes[app.nodeId.nodeIndex].children[0]
    check styles.styles[toolbar.nodeIndex].layout.width == some(240.0'f32)
    let saveButton = ui.tree.nodes[toolbar.nodeIndex].children[1]
    check styles.styles[saveButton.nodeIndex].layout.width == some(144.0'f32)
