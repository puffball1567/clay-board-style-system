import std/[options, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

suite "node to paint command pipeline":
  test "resolves styles, computes layout, and emits paint commands":
    var tree = initTree()
    let root = tree.addBox(groups = ["toolbar"])
    let save = tree.addBox(parent = some(root), groups = ["button", "primary"])
    discard tree.addText(save, "Save")
    let cancel = tree.addBox(parent = some(root), groups = ["button"])
    discard tree.addText(cancel, "Cancel")
    tree.addState(save, esHover)

    var hoverButton = target(save)
    hoverButton.requiredStates.incl esHover

    let sheet = styleSheet([
      rule(group("toolbar"), [
        decl("width", px(300)),
        decl("padding", px(8)),
        decl("gap", px(8)),
        decl("flex-direction", keyword("row")),
        decl("background-color", colorValue(rgb(0.12, 0.14, 0.16)))
      ]),
      rule(group("button"), [
        decl("min-width", px(44)),
        decl("padding", px(6)),
        decl("overflow", keyword("hidden")),
        decl("background-color", colorValue(rgb(0.22, 0.25, 0.29))),
        decl("border-color", colorValue(rgb(0.42, 0.47, 0.54))),
        decl("border-width", px(1)),
        decl("border-radius", px(4)),
        decl("color", colorValue(rgb(0.95, 0.95, 0.95))),
        decl("font-size", px(14))
      ]),
      rule(hoverButton, [
        decl("background-color", colorValue(rgb(0.30, 0.35, 0.42)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(300, 80))
    let commands = buildPaintCommands(tree, styles, layout)

    check layout.boxes.len == tree.nodes.len
    check commands.len == 11
    check commands[0].kind == pcFillRect
    var sawClip = false
    var sawText = false
    for command in commands:
      case command.kind
      of pcPushClip:
        sawClip = true
      of pcDrawText:
        sawText = true
        check command.textColor == rgb(0.95, 0.95, 0.95)
      else:
        discard
    check sawClip
    check sawText
