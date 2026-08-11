import std/[options, strformat]

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/generated/default_properties

proc main() =
  var tree = initTree()
  let root = tree.addBox(id = "toolbar")
  let save = tree.addBox(parent = some(root), id = "save-button", groups = ["button", "primary"])
  discard tree.addText(save, "Save")
  let cancel = tree.addBox(parent = some(root), id = "cancel-button", groups = ["button"])
  discard tree.addText(cancel, "Cancel")
  tree.addState(save, esHover)

  var hoverButton = group("button")
  hoverButton.requiredStates.incl esHover

  let sheet = styleSheet([
    rule(id("toolbar"), [
      decl("width", px(300)),
      decl("height", px(64)),
      decl("padding", px(8)),
      decl("gap", px(8)),
      decl("flex-direction", keyword("row")),
      decl("background-color", colorValue(rgb(0.12, 0.14, 0.16)))
    ]),
    rule(group("button"), [
      decl("padding", px(6)),
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
  let styles = resolveTreeStyles(
    tree,
    [sheet],
    defaultProperties(),
    diagnostics,
    viewportSize = some(size(300, 64))
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    quit 1

  let layout = computeLayout(tree, styles, size(300, 64))
  let commands = buildPaintCommands(tree, styles, layout)
  let image = render(commands, 300, 64, rgb(1, 1, 1))
  let path = "/tmp/clay_board_style_system_demo.ppm"
  image.writePpm(path)
  echo &"wrote {path}"

when isMainModule:
  main()
