import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc measureOnlyEngine(measure: TextMeasureProc): TextEngine =
  TextEngine(
    measureText: measure,
    caretPosition: debugCaretPosition,
    hitTestText: debugHitText
  )

suite "layout alignment":
  test "margin and center alignment affect child placement":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(80)),
        decl("padding", px(10)),
        decl("align-items", keyword("center")),
        decl("justify-content", keyword("center"))
      ]),
      rule(id("child"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("margin", px(4))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 80))
    var childRect: Option[Rect]
    for box in layout.boxes:
      if box.node == child:
        childRect = some(box.rect)

    check childRect.isSome
    check childRect.get.x == 40
    check childRect.get.y == 30
    check childRect.get.w == 40
    check childRect.get.h == 20

  test "space-between distributes row children":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(40)),
        decl("flex-direction", keyword("row")),
        decl("justify-content", keyword("space-between"))
      ]),
      rule(group("item"), [
        decl("width", px(20)),
        decl("height", px(20))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 40))
    var firstRect: Option[Rect]
    var secondRect: Option[Rect]
    for box in layout.boxes:
      if box.node == first:
        firstRect = some(box.rect)
      if box.node == second:
        secondRect = some(box.rect)

    check firstRect.isSome
    check secondRect.isSome
    check firstRect.get.x == 0
    check secondRect.get.x == 100

  test "button text can be centered by box alignment":
    var tree = initTree()
    let button = tree.addBox(id = "button")
    let label = tree.addText(button, "OK")

    let sheet = styleSheet([
      rule(id("button"), [
        decl("width", px(80)),
        decl("height", px(36)),
        decl("align-items", keyword("center")),
        decl("justify-content", keyword("center")),
        decl("font-size", px(10))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(80, 36))
    var labelRect: Option[Rect]
    for box in layout.boxes:
      if box.node == label:
        labelRect = some(box.rect)

    check labelRect.isSome
    check labelRect.get.x == 32
    check labelRect.get.y == 14

  test "line-height affects text box height":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "Label", id = "label")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(80))
      ]),
      rule(id("label"), [
        decl("line-height", px(24))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 80))
    var labelRect: Option[Rect]
    for box in layout.boxes:
      if box.node == label:
        labelRect = some(box.rect)

    check labelRect.isSome
    check labelRect.get.h == 24

  test "aspect-ratio derives missing box height":
    var tree = initTree()
    discard tree.addBox(id = "card")

    let sheet = styleSheet([
      rule(id("card"), [
        decl("width", px(120)),
        decl("aspect-ratio", number(2))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(200, 200))
    check layout.boxes.len == 1
    check layout.boxes[0].rect.w == 120
    check layout.boxes[0].rect.h == 60

  test "min and max size constraints clamp natural box size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "wide")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("max-width", px(80)),
        decl("min-height", px(40))
      ]),
      rule(id("wide"), [
        decl("width", px(120)),
        decl("height", px(10))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(200, 100))
    var rootRect: Option[Rect]
    for box in layout.boxes:
      if box.node == root:
        rootRect = some(box.rect)

    check rootRect.isSome
    check rootRect.get.w == 80
    check rootRect.get.h == 40

  test "image intrinsic size contributes to parent natural size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let image = tree.addImage(root, "avatar.png", width = 64, height = 32, id = "image")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("padding", px(4))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(200, 100))
    var rootRect: Option[Rect]
    var imageRect: Option[Rect]
    for box in layout.boxes:
      if box.node == root:
        rootRect = some(box.rect)
      if box.node == image:
        imageRect = some(box.rect)

    check rootRect.isSome
    check imageRect.isSome
    check imageRect.get == rect(4, 4, 64, 32)
    check rootRect.get == rect(0, 0, 72, 40)

  test "image max constraints clamp intrinsic size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let image = tree.addImage(root, "hero.png", width = 200, height = 100, id = "image")

    let sheet = styleSheet([
      rule(id("image"), [
        decl("max-width", px(120)),
        decl("max-height", px(48))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(300, 200))
    var imageRect: Option[Rect]
    for box in layout.boxes:
      if box.node == image:
        imageRect = some(box.rect)

    check imageRect.isSome
    check imageRect.get.w == 120
    check imageRect.get.h == 48

  test "letter-spacing affects text box width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "ABCD", id = "label")

    let sheet = styleSheet([
      rule(id("label"), [
        decl("letter-spacing", px(2))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 80))
    var labelRect: Option[Rect]
    for box in layout.boxes:
      if box.node == label:
        labelRect = some(box.rect)

    check labelRect.isSome
    check labelRect.get.w == 38

  test "custom text engine controls text measurement":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "ABCD", id = "label")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(80))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let textEngine = measureOnlyEngine(proc(input: TextMeasureInput): Size =
      size(input.text.len.float32 * 12.0'f32, 18.0'f32)
    )
    let layout = computeLayout(tree, styles, size(120, 80), textEngine)
    var labelRect: Option[Rect]
    for box in layout.boxes:
      if box.node == label:
        labelRect = some(box.rect)

    check labelRect.isSome
    check labelRect.get.w == 48
    check labelRect.get.h == 18

  test "max-lines limits text measurement input":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "One\nTwo\nThree", id = "label")

    let sheet = styleSheet([
      rule(id("label"), [
        decl("max-lines", keyword("2"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    var measuredText = ""
    let textEngine = measureOnlyEngine(proc(input: TextMeasureInput): Size =
      measuredText = input.text
      size(input.text.len.float32, 20)
    )
    let layout = computeLayout(tree, styles, size(120, 80), textEngine)
    var labelRect: Option[Rect]
    for box in layout.boxes:
      if box.node == label:
        labelRect = some(box.rect)

    check measuredText == "One\nTwo"
    check labelRect.isSome
    check labelRect.get.w == 7

  test "zoom scales child layout and parent natural size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "AB", id = "label")

    let sheet = styleSheet([
      rule(id("label"), [
        decl("zoom", number(2))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let textEngine = measureOnlyEngine(proc(input: TextMeasureInput): Size =
      size(10, 5)
    )
    let layout = computeLayout(tree, styles, size(120, 80), textEngine)
    var rootRect: Option[Rect]
    var labelRect: Option[Rect]
    for box in layout.boxes:
      if box.node == root:
        rootRect = some(box.rect)
      if box.node == label:
        labelRect = some(box.rect)

    check rootRect.isSome
    check labelRect.isSome
    check labelRect.get.w == 20
    check labelRect.get.h == 10
    check rootRect.get.w == 20
    check rootRect.get.h == 10

  test "font registry is passed to text measurement":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addText(root, "ABCD", id = "label")

    let sheet = styleSheet([
      rule(id("label"), [
        decl("font-family", fontFamilyValue("Inter", genericSansSerif()))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    var fonts = initFontRegistry(useSystemFonts = false)
    fonts.addFontFile("Inter", "assets/fonts/Inter-Regular.ttf")
    fonts.addFallbackFamily("Noto Sans JP")

    let textEngine = measureOnlyEngine(proc(input: TextMeasureInput): Size =
      check input.style.fontFamilies == @["Inter", "sans-serif"]
      check not input.fonts.useSystemFonts
      check input.fonts.faces.len == 1
      check input.fonts.faces[0].family == "Inter"
      check input.fonts.fallbackFamilies == @["sans-serif", "Noto Sans JP"]
      check effectiveFontFamilies(input.style, input.fonts) == @["Inter", "sans-serif", "Noto Sans JP"]
      size(10, 10)
    )
    discard computeLayout(tree, styles, size(120, 80), textEngine, fonts)
