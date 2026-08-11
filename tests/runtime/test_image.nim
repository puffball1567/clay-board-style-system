import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "image element":
  test "image handle creates an image node with intrinsic size":
    let ui = initUiRoot()
    let root = ui.box(groups = ["root"])

    let logo = ui.image(root, "logo.png", width = 64, height = 32)

    check ui.tree.nodes[logo.container.id.nodeIndex].kind == nkImage
    check logo.source() == "logo.png"
    check ui.tree.nodes[logo.container.id.nodeIndex].imageWidth == 64
    check ui.tree.nodes[logo.container.id.nodeIndex].imageHeight == 32

    logo.setSource("logo-dark.png")
    logo.setIntrinsicSize(128, 48)

    check logo.source() == "logo-dark.png"
    check ui.tree.nodes[logo.container.id.nodeIndex].imageWidth == 128
    check ui.tree.nodes[logo.container.id.nodeIndex].imageHeight == 48

  test "image participates in layout and paint commands":
    var tree = initTree()
    let root = tree.addBox(groups = ["root"])
    let logo = tree.addImage(root, "logo.png", width = 64, height = 32, groups = ["logo"])

    let sheet = styleSheet([
      rule(group("root"), [
        decl("width", px(200)),
        decl("height", px(100))
      ]),
      rule(group("logo"), [
        decl("object-fit", keyword("contain")),
        decl("object-position", keyword("bottom"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(200, 100))
    let commands = buildPaintCommands(tree, styles, layout)

    check layout.boxes.len == tree.nodes.len
    var logoRect = none(Rect)
    for item in layout.boxes:
      if item.node == logo:
        logoRect = some(item.rect)
    check logoRect.isSome
    check logoRect.get.w == 64
    check logoRect.get.h == 32

    var sawImage = false
    for command in commands:
      case command.kind
      of pcDrawImage:
        sawImage = true
        check command.imageNode == logo
        check command.imageSource == "logo.png"
        check command.imageRect.w == 64
        check command.imageRect.h == 32
        check command.imageStyle.objectFit == some(ofContain)
        check command.imageStyle.objectPosition.isSome
        check command.imageStyle.objectPosition.get.y == 100
      else:
        discard
    check sawImage

  test "image supports standard event assignment":
    let ui = initUiRoot()
    let root = ui.box(groups = ["root"])
    let logo = ui.image(root, ImageParams(source: "logo.png"))
    var loaded = false
    var clicked = false

    logo.onLoad = proc(event: DispatchResult): EventOutcome =
      loaded = true
      true
    logo.onClick = proc(event: DispatchResult): EventOutcome =
      clicked = true
      true

    discard logo.container.emit(iekLoad)
    discard logo.container.emit(iekClick)

    check loaded
    check clicked
