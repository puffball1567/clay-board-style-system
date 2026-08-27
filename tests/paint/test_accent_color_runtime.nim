import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc fillFor(
    commands: openArray[PaintCommand];
    owner: NodeId
): Option[PaintCommand] =
  for command in commands:
    if command.kind == pcFillRect and command.owner == some(owner):
      return some(command)
  none(PaintCommand)

proc textFor(
    commands: openArray[PaintCommand];
    owner: NodeId
): Option[PaintCommand] =
  for command in commands:
    if command.kind == pcDrawText and command.owner == some(owner):
      return some(command)
  none(PaintCommand)

suite "accent color runtime":
  test "generated control accent parts use typed metadata":
    let ui = initUiRoot()
    let checkbox = ui.checkbox(CheckboxParams(label: "Check"))
    let radio = ui.radio(
      RadioParams(label: "Radio", value: "radio"),
      initRadioSet()
    )
    let switchControl = ui.switch(SwitchParams(label: "Switch"))
    let slider = ui.slider(SliderParams(min: 0, max: 100, value: 50))

    check ui.tree.nodes[checkbox.indicatorNode.id.nodeIndex].generatedPart == gpkAccent
    check ui.tree.nodes[radio.state.indicatorNode.id.nodeIndex].generatedPart == gpkAccent
    check ui.tree.nodes[switchControl.activeTrackNode.id.nodeIndex].generatedPart == gpkAccent
    check ui.tree.nodes[slider.fillNode.id.nodeIndex].generatedPart == gpkAccent

  test "all generated controls consume their authored accent color":
    let ui = initUiRoot()
    let accent = rgb(0.82, 0.16, 0.46)
    let host = ui.box(uiStyle([
      decl("width", px(360)),
      decl("height", px(180))
    ]))
    ui.pushParent(host)
    let controlStyle = uiStyle([
      decl("accent-color", colorValue(accent)),
      decl("height", px(32))
    ])
    let checkbox = ui.checkbox(
      CheckboxParams(label: "Check", checked: true),
      style = controlStyle,
      markerStyle = uiStyle([decl("width", px(18)), decl("height", px(18))])
    )
    let radio = ui.radio(
      RadioParams(label: "Radio", value: "radio", checked: true),
      initRadioSet(),
      style = controlStyle,
      markerStyle = uiStyle([decl("width", px(18)), decl("height", px(18))])
    )
    let switchControl = ui.switch(
      SwitchParams(label: "Switch", checked: true),
      style = controlStyle
    )
    let slider = ui.slider(
      SliderParams(min: 0, max: 100, value: 50, trackWidth: 100),
      style = controlStyle,
      trackStyle = uiStyle([
        decl("width", px(100)),
        decl("height", px(8)),
        decl("position", keyword("relative"))
      ]),
      fillStyle = uiStyle([decl("height", px(8))])
    )
    ui.popParent()

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree,
      ui.styleSheets(),
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(360, 180))
    let commands = buildPaintCommands(ui.tree, styles, layout)

    let checkboxPaint = commands.textFor(checkbox.indicatorNode.id)
    let radioPaint = commands.fillFor(radio.state.indicatorNode.id)
    let switchPaint = commands.fillFor(switchControl.activeTrackNode.id)
    let sliderPaint = commands.fillFor(slider.fillNode.id)
    require checkboxPaint.isSome
    check checkboxPaint.get.textColor == accent
    require radioPaint.isSome
    check radioPaint.get.color == accent
    require switchPaint.isSome
    check switchPaint.get.color == accent
    require sliderPaint.isSome
    check sliderPaint.get.color == accent

  test "accent color inherits into generated box and text paint":
    var tree = initTree()
    let owner = tree.addBox(id = "owner")
    let accentBox = tree.addBox(parent = some(owner), id = "accent-box")
    let accentText = tree.addText(owner, "x", id = "accent-text")
    tree.setGeneratedPart(accentBox, gpkAccent)
    tree.setGeneratedPart(accentText, gpkAccent)

    let accent = rgb(0.86, 0.18, 0.42)
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("owner"), [
          decl("width", px(80)),
          decl("height", px(40)),
          decl("accent-color", colorValue(accent))
        ]),
        rule(id("accent-box"), [
          decl("width", px(12)),
          decl("height", px(12)),
          decl("background-color", colorValue(rgb(0.1, 0.2, 0.3)))
        ]),
        rule(id("accent-text"), [
          decl("color", colorValue(rgb(0.3, 0.2, 0.1)))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors
    check styles.styles[accentBox.nodeIndex].visual.accentColor == some(accent)
    check styles.styles[accentText.nodeIndex].visual.accentColor == some(accent)

    let layout = computeLayout(tree, styles, size(80, 40))
    let commands = buildPaintCommands(tree, styles, layout)
    let boxCommand = commands.fillFor(accentBox)
    let textCommand = commands.textFor(accentText)

    check boxCommand.isSome
    check boxCommand.get.color == accent
    check textCommand.isSome
    check textCommand.get.textColor == accent

  test "auto stops inherited accent color and preserves component fallbacks":
    var tree = initTree()
    let owner = tree.addBox(id = "owner")
    let automatic = tree.addBox(parent = some(owner), id = "automatic")
    tree.setGeneratedPart(automatic, gpkAccent)

    let fallback = rgb(0.2, 0.7, 0.4)
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("owner"), [
          decl("width", px(40)),
          decl("height", px(20)),
          decl("accent-color", colorValue(rgb(0.8, 0.1, 0.2)))
        ]),
        rule(id("automatic"), [
          decl("width", px(12)),
          decl("height", px(12)),
          decl("accent-color", keyword("auto")),
          decl("background-color", colorValue(fallback))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors
    check styles.styles[automatic.nodeIndex].visual.accentColor.isNone
    check styles.styles[automatic.nodeIndex].visual.accentColorSpecified

    let layout = computeLayout(tree, styles, size(40, 20))
    let command = buildPaintCommands(tree, styles, layout).fillFor(automatic)

    check command.isSome
    check command.get.color == fallback

  test "ordinary descendants keep authored paint while inheriting accent metadata":
    var tree = initTree()
    let owner = tree.addBox(id = "owner")
    let ordinary = tree.addBox(parent = some(owner), id = "ordinary")

    let accent = rgb(0.9, 0.2, 0.1)
    let authored = rgb(0.1, 0.3, 0.8)
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("owner"), [
          decl("width", px(40)),
          decl("height", px(20)),
          decl("accent-color", colorValue(accent))
        ]),
        rule(id("ordinary"), [
          decl("width", px(12)),
          decl("height", px(12)),
          decl("background-color", colorValue(authored))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors
    check styles.styles[ordinary.nodeIndex].visual.accentColor == some(accent)

    let layout = computeLayout(tree, styles, size(40, 20))
    let command = buildPaintCommands(tree, styles, layout).fillFor(ordinary)

    check command.isSome
    check command.get.color == authored

  test "initial resets accent while unset follows inherited-property semantics":
    var tree = initTree()
    let owner = tree.addBox(id = "owner")
    let initialChild = tree.addBox(parent = some(owner), id = "initial")
    let unsetChild = tree.addBox(parent = some(owner), id = "unset")
    let accent = rgb(0.7, 0.25, 0.55)

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("owner"), [decl("accent-color", colorValue(accent))]),
        rule(id("initial"), [decl("accent-color", initial())]),
        rule(id("unset"), [decl("accent-color", unset())])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    check styles.styles[initialChild.nodeIndex].visual.accentColor.isNone
    check styles.styles[initialChild.nodeIndex].visual.accentColorSpecified
    check styles.styles[unsetChild.nodeIndex].visual.accentColor == some(accent)
    check styles.styles[unsetChild.nodeIndex].visual.accentColorSpecified
