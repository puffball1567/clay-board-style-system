import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/design_source/model
import clay_board_style_system/generated/default_properties

suite "design source model":
  test "maps service-neutral baseline alignment into CBSS vocabulary":
    var row = designFrame("frame:row", "Row", id = "row")
    row.style.layoutDirection = dldRow
    row.style.alignItems = daBaseline
    let built = designPage("page:main", "Main", [row]).buildCbss()
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      built.tree, [built.sheet], defaultProperties(), diagnostics
    )

    check not diagnostics.hasErrors
    check styles.styles[0].layout.alignItems == aiBaseline

  test "builds a CBSS tree and stylesheet from service-neutral design nodes":
    var card = designFrame("frame:card", "Card", id = "card", groups = ["surface"])
    card.style.width = some(320.0'f32)
    card.style.height = some(160.0'f32)
    card.style.padding = some(designEdges(16))
    card.style.gap = some(8.0'f32)
    card.style.layoutDirection = dldColumn
    card.style.backgroundColor = some(rgb(0.96, 0.97, 0.98))
    card.style.stroke = some(designStroke(1, rgb(0.72, 0.76, 0.80)))
    card.style.radius = some(6.0'f32)

    var title = designText("text:title", "Title", "Design source", id = "title")
    title.style.text.fontFamilies = @["Inter", "Noto Sans", genericSansSerif()]
    title.style.text.fontSize = some(20.0'f32)
    title.style.text.fontWeight = some(700.0'f32)
    title.style.text.color = some(rgb(0.10, 0.12, 0.14))
    card.addChild(title)

    var body = designText("text:body", "Body", "Shared model keeps service adapters isolated.", id = "body")
    body.style.text.fontSize = some(14.0'f32)
    body.style.text.lineHeight = some(1.4'f32)
    body.style.text.color = some(rgb(0.28, 0.32, 0.36))
    card.addChild(body)

    let page = designPage("page:main", "Main", [card])
    let built = page.buildCbss()

    check built.tree.nodes.len == 3
    check built.tree.nodes[0].id == "card"
    check built.tree.nodes[0].hasGroup("surface")
    check built.tree.nodes[0].hasGroup("ds-frame-card")
    check built.tree.nodes[1].id == "title"
    check built.tree.nodes[1].text == "Design source"
    check built.sheet.rules.len == 3

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(built.tree, [built.sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    check styles.styles[0].layout.width == some(320.0'f32)
    check styles.styles[0].box.padding.get.left == 16.0'f32
    check styles.styles[0].layout.direction == fdColumn
    check styles.styles[1].text.fontFamilies == @["Inter", "Noto Sans", "sans-serif"]
    check styles.styles[1].text.fontWeight == some(700.0'f32)

  test "can resolve styles from an external stylesheet":
    var node = designFrame("frame:plain", "Plain", id = "plain", groups = ["token-card"])
    let page = designPage("page:main", "Main", [node])
    let built = page.buildCbss(DesignBuildOptions(
      includeLocalGroups: false,
      emitLocalStyleRules: false,
      localStylePrefix: "ds"
    ))

    check built.tree.nodes.len == 1
    check built.tree.nodes[0].hasGroup("token-card")
    check not built.tree.nodes[0].hasGroup("ds-frame-plain")
    check built.sheet.rules.len == 0

    let external = styleSheet([
      rule(id("plain"), [
        decl("width", px(100)),
        decl("background-color", colorValue(rgb(0.2, 0.3, 0.4)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(built.tree, built.styleSheets([external]), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    check styles.styles[0].layout.width == some(100.0'f32)
    check styles.styles[0].box.backgroundColor == some(rgb(0.2, 0.3, 0.4))

  test "external stylesheets can override generated design-source styles":
    var node = designFrame("frame:override", "Override", id = "panel")
    node.style.width = some(160.0'f32)
    let built = designPage("page:main", "Main", [node]).buildCbss()
    let external = styleSheet([
      rule(id("panel"), [
        decl("width", px(240))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(built.tree, built.styleSheets([external]), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    check styles.styles[0].layout.width == some(240.0'f32)

  test "style injections support ordered themes and viewport conditions":
    var node = designFrame("frame:responsive", "Responsive", id = "panel")
    node.style.width = some(160.0'f32)
    let built = designPage("page:main", "Main", [node]).buildCbss()

    let baseTheme = styleInjection(
      "base-theme",
      styleSheet([
        rule(id("panel"), [
          decl("background-color", colorValue(rgb(0.1, 0.1, 0.1)))
        ])
      ]),
      placement = sipBeforeGenerated,
      priority = 0
    )
    let desktopOverride = styleInjection(
      "desktop",
      styleSheet([
        rule(id("panel"), [
          decl("width", px(320))
        ])
      ]),
      placement = sipAfterGenerated,
      priority = 10,
      condition = some(minViewportWidth(900))
    )

    var diagnostics: Diagnostics
    let mobileStyles = resolveTreeStyles(
      built.tree,
      built.injectedStyleSheets([baseTheme, desktopOverride], viewportWidth = some(640.0'f32), viewportHeight = some(480.0'f32)),
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors
    check mobileStyles.styles[0].layout.width == some(160.0'f32)
    check mobileStyles.styles[0].box.backgroundColor == some(rgb(0.1, 0.1, 0.1))

    diagnostics = Diagnostics()
    let desktopStyles = resolveTreeStyles(
      built.tree,
      built.injectedStyleSheets([baseTheme, desktopOverride], viewportWidth = some(1280.0'f32), viewportHeight = some(720.0'f32)),
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors
    check desktopStyles.styles[0].layout.width == some(320.0'f32)
