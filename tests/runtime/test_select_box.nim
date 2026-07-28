import std/[options, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

proc options(): seq[SelectOption] =
  @[
    SelectOption(label: "Small", value: "small"),
    SelectOption(label: "Medium", value: "medium"),
    SelectOption(label: "Large", value: "large")
  ]

suite "select box component":
  test "select box initializes from selected value":
    let ui = initUiRoot()
    let size = ui.selectBox(options(), selectedValue = "medium", placeholder = "Size")

    check size.selectedIndex() == 1
    check size.selectedValue() == "medium"
    check ui.tree.nodes[size.valueNode.nodeId.nodeIndex].text == "Medium"
    check esSelected in ui.tree.nodes[size.optionNodes[1].nodeId.nodeIndex].states

  test "option click selects value and emits input/change":
    let ui = initUiRoot()
    let size = ui.selectBox(options(), placeholder = "Size")
    var inputValue = ""
    var changeValue = ""

    size.onInput = proc(event: DispatchResult): bool =
      inputValue = size.selectedValue()
      false

    size.onChange = proc(event: DispatchResult): bool =
      changeValue = size.selectedValue()
      false

    discard size.optionNodes[2].emit(InputEvent(kind: iekClick))

    check size.selectedIndex() == 2
    check size.selectedValue() == "large"
    check inputValue == "large"
    check changeValue == "large"
    check ui.tree.nodes[size.valueNode.nodeId.nodeIndex].text == "Large"

  test "option pointer down selects and closes":
    let ui = initUiRoot()
    let size = ui.selectBox(options(), selectedValue = "small")

    size.setOpen(true)
    discard size.optionNodes[2].emit(InputEvent(kind: iekPointerDown))

    check size.selectedValue() == "large"
    check not size.isOpen()

  test "click toggles open state and emits toggle":
    let ui = initUiRoot()
    let size = ui.selectBox(options())
    var toggled = 0

    size.onToggle = proc(event: DispatchResult): bool =
      inc toggled
      false

    discard size.container.emit(InputEvent(kind: iekClick))
    check size.isOpen()
    check esOpen in ui.tree.nodes[size.container.nodeId.nodeIndex].states

    discard size.container.emit(InputEvent(kind: iekClick))
    check not size.isOpen()
    check toggled == 2

  test "real pointer down opens without synthetic click closing it":
    let ui = initUiRoot()
    let size = ui.selectBox(options())

    discard size.container.emit(pointerDownEvent(vec2(4, 4)), local = some(vec2(4, 4)))
    check size.isOpen()

    discard size.container.emit(clickEvent(vec2(4, 4)), local = some(vec2(4, 4)))
    check size.isOpen()

  test "blur closes an open select":
    let ui = initUiRoot()
    let size = ui.selectBox(options())

    size.setOpen(true)
    discard size.container.emit(iekBlur)

    check not size.isOpen()

  test "pointer input flow opens and selects an option":
    let ui = initUiRoot()
    let select = ui.selectBox(
      options(),
      selectedValue = "small",
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(24))
      ]),
      optionStyle = uiStyle([
        decl("width", px(120)),
        decl("height", px(20))
      ])
    )
    var input = initInteractionState()

    var diagnostics: Diagnostics
    var styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    var layout = computeLayout(ui.tree, styles, size(180, 140))
    var regions = buildHitRegions(ui.tree, layout, styles)

    discard ui.events.handle(ui.tree, input.processInput(ui.tree, regions, pointerDownEvent(vec2(8, 8))))
    check select.isOpen()
    check esOpen in ui.tree.nodes[select.container.nodeId.nodeIndex].states

    discard ui.events.handle(ui.tree, input.processInput(ui.tree, regions, pointerUpEvent(vec2(8, 8))))
    check select.isOpen()
    check esOpen in ui.tree.nodes[select.container.nodeId.nodeIndex].states

    diagnostics = Diagnostics()
    styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    layout = computeLayout(ui.tree, styles, size(180, 140))
    regions = buildHitRegions(ui.tree, layout, styles)

    discard ui.events.handle(ui.tree, input.processInput(ui.tree, regions, pointerDownEvent(vec2(8, 58))))
    check select.selectedValue() == "medium"
    check not select.isOpen()

    diagnostics = Diagnostics()
    styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    layout = computeLayout(ui.tree, styles, size(180, 140))
    regions = buildHitRegions(ui.tree, layout, styles)

    discard ui.events.handle(ui.tree, input.processInput(ui.tree, regions, pointerDownEvent(vec2(8, 8))))
    check select.isOpen()

    diagnostics = Diagnostics()
    styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    layout = computeLayout(ui.tree, styles, size(180, 140))
    regions = buildHitRegions(ui.tree, layout, styles)

    discard ui.events.handle(ui.tree, input.processInput(ui.tree, regions, pointerDownEvent(vec2(8, 38))))
    check select.selectedValue() == "small"
    check not select.isOpen()

  test "closed options do not participate in layout or hit testing":
    let ui = initUiRoot()
    let select = ui.selectBox(
      options(),
      selectedValue = "small",
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(24))
      ]),
      optionStyle = uiStyle([
        decl("width", px(120)),
        decl("height", px(20))
      ])
    )

    var diagnostics: Diagnostics
    var styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    var layout = computeLayout(ui.tree, styles, size(160, 120))
    var regions = buildHitRegions(ui.tree, layout, styles)
    var optionHit = hitTest(regions, vec2(8, 34))

    check optionHit.isNone

    select.setOpen(true)
    diagnostics = Diagnostics()
    styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    layout = computeLayout(ui.tree, styles, size(160, 120))
    regions = buildHitRegions(ui.tree, layout, styles)
    optionHit = hitTest(regions, vec2(8, 34))

    check optionHit.isSome
    check optionHit.get.node == select.optionNodes[0].nodeId

  test "closed options do not emit paint commands":
    let ui = initUiRoot()
    discard ui.selectBox(
      options(),
      selectedValue = "small",
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(24))
      ]),
      optionStyle = uiStyle([
        decl("width", px(120)),
        decl("height", px(20))
      ])
    )

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(160, 120))
    let commands = buildPaintCommands(ui.tree, styles, layout)

    for command in commands:
      if command.kind == pcDrawText:
        check command.text != "Medium"
        check command.text != "Large"

  test "open options can paint one shared styled background panel":
    let ui = initUiRoot()
    let select = ui.selectBox(
      options(),
      selectedValue = "small",
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(24))
      ]),
      panelStyle = uiStyle([
        decl("width", px(120)),
        decl("background-color", colorValue(rgb(0.1, 0.2, 0.3)))
      ]),
      optionStyle = uiStyle([
        decl("width", px(112)),
        decl("height", px(20))
      ])
    )
    select.setOpen(true)

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(160, 120))
    let commands = buildPaintCommands(ui.tree, styles, layout)

    var panels = 0
    for command in commands:
      if command.kind == pcFillRect and command.color == rgb(0.1, 0.2, 0.3):
        inc panels
    check panels == 1

  test "open panel paints and hits above following overlapping content":
    let ui = initUiRoot()
    let root = ui.box(uiStyle([
      decl("width", px(140)),
      decl("height", px(140))
    ]))
    ui.pushParent(root)
    let select = ui.selectBox(
      options(),
      selectedValue = "small",
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(24))
      ]),
      panelStyle = uiStyle([
        decl("width", px(120)),
        decl("background-color", colorValue(rgb(0.1, 0.2, 0.3)))
      ]),
      optionStyle = uiStyle([
        decl("width", px(112)),
        decl("height", px(20))
      ])
    )
    discard ui.box(uiStyle([
      decl("width", px(140)),
      decl("height", px(90)),
      decl("background-color", colorValue(rgb(0, 0, 1)))
    ]))
    ui.popParent()
    select.setOpen(true)

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(180, 160))
    let regions = buildHitRegions(ui.tree, layout, styles)
    let hit = hitTest(regions, vec2(8, 38))
    let commands = buildPaintCommands(ui.tree, styles, layout)

    check hit.isSome
    check hit.get.node == select.optionNodes[0].nodeId

    var laterIndex = -1
    var panelIndex = -1
    for index, command in commands:
      if command.kind == pcFillRect and command.color == rgb(0, 0, 1):
        laterIndex = index
      if command.kind == pcFillRect and command.color == rgb(0.1, 0.2, 0.3):
        panelIndex = index
    check laterIndex >= 0
    check panelIndex > laterIndex

  test "open option selection does not click through overlapping following content":
    let ui = initUiRoot()
    let root = ui.box(uiStyle([
      decl("width", px(140)),
      decl("height", px(140))
    ]))
    ui.pushParent(root)
    let select = ui.selectBox(
      options(),
      selectedValue = "medium",
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(24))
      ]),
      panelStyle = uiStyle([
        decl("width", px(120))
      ]),
      optionStyle = uiStyle([
        decl("width", px(112)),
        decl("height", px(20))
      ])
    )
    let under = ui.box(uiStyle([
      decl("width", px(140)),
      decl("height", px(90))
    ]))
    ui.popParent()
    var underClicked = false
    under.onPointerDown = proc(event: DispatchResult): bool =
      underClicked = true
      false
    select.setOpen(true)

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(180, 160))
    let regions = buildHitRegions(ui.tree, layout, styles)
    var input = initInteractionState()

    discard ui.events.handle(ui.tree, input.processInput(ui.tree, regions, pointerDownEvent(vec2(8, 38))))

    check select.selectedValue() == "small"
    check not select.isOpen()
    check not underClicked

  test "keyboard navigation selects next and previous enabled option":
    let ui = initUiRoot()
    let size = ui.selectBox(options(), selectedValue = "medium")
    var changes: seq[string] = @[]

    size.onChange = proc(event: DispatchResult): bool =
      changes.add size.selectedValue()
      false

    discard size.container.emit(keyDownEvent("ArrowDown"))
    discard size.container.emit(keyDownEvent("ArrowUp"))

    check changes == @["large", "medium"]
    check size.selectedValue() == "medium"

  test "disabled select suppresses click and keyboard changes":
    let ui = initUiRoot()
    let size = ui.selectBox(options(), selectedValue = "small", disabled = true)
    var changed = false
    var clicked = false

    size.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    size.onClick = proc(event: DispatchResult): bool =
      clicked = true
      false

    discard size.container.emit(InputEvent(kind: iekClick))
    discard size.container.emit(keyDownEvent("ArrowDown"))

    check size.selectedValue() == "small"
    check not size.isOpen()
    check not changed
    check not clicked
    check esDisabled in ui.tree.nodes[size.container.nodeId.nodeIndex].states

  test "disabled options cannot be selected":
    let ui = initUiRoot()
    let size = ui.selectBox(@[
      SelectOption(label: "Small", value: "small"),
      SelectOption(label: "Medium", value: "medium", disabled: true),
      SelectOption(label: "Large", value: "large")
    ], selectedValue = "small")
    var changed = false

    size.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    discard size.optionNodes[1].emit(InputEvent(kind: iekClick))

    check size.selectedValue() == "small"
    check not changed
    check esDisabled in ui.tree.nodes[size.optionNodes[1].nodeId.nodeIndex].states

  test "setSelectedValue updates without emitting by default":
    let ui = initUiRoot()
    let size = ui.selectBox(options())
    var changed = false

    size.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    size.setSelectedValue("large")

    check size.selectedValue() == "large"
    check not changed

  test "registered popup closer ignores clicks inside the select":
    let ui = initUiRoot()
    let size = ui.selectBox(options(), selectedValue = "small")
    var toggled = false

    size.onToggle = proc(event: DispatchResult): bool =
      toggled = true
      false

    size.setOpen(true)

    check not ui.closeOpenPopups(some(size.container.nodeId))
    check size.isOpen()

    check not ui.closeOpenPopups(some(size.optionNodes[1].nodeId))
    check size.isOpen()
    check not toggled

  test "registered popup closer closes select on outside target":
    let ui = initUiRoot()
    let size = ui.selectBox(options(), selectedValue = "small")
    let outside = ui.box()
    var toggles = 0

    size.onToggle = proc(event: DispatchResult): bool =
      inc toggles
      false

    size.setOpen(true)

    check ui.closeOpenPopups(some(outside.nodeId))
    check not size.isOpen()
    check toggles == 1

  test "registered popup closer closes multiple open selects":
    let ui = initUiRoot()
    let first = ui.selectBox(options(), selectedValue = "small")
    let second = ui.selectBox(options(), selectedValue = "large")

    first.setOpen(true)
    second.setOpen(true)

    check ui.closeOpenPopups(none(NodeId))
    check not first.isOpen()
    check not second.isOpen()
