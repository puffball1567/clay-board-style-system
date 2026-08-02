import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc close(actual, expected: float32; tolerance = 1e-5'f32): bool =
  abs(actual - expected) <= tolerance

proc checkColor(actual: Option[Color]; expected: Color) =
  require actual.isSome
  check actual.get.r.close(expected.r)
  check actual.get.g.close(expected.g)
  check actual.get.b.close(expected.b)
  check actual.get.a.close(expected.a)

proc resolved(context: StyleContext; env = ResolveEnv()): ComputedStyle =
  var diagnostics: Diagnostics
  result = resolveStyles(context, defaultProperties(), env, diagnostics)
  require not diagnostics.hasErrors

suite "authored colors in style declarations":
  test "context construction keeps foreground declarations first and stable":
    let context = styleContext([
      decl("background-color", colorValue(currentColor()), sourceOrder = 1),
      decl("color", colorValue(rgb(1, 0, 0)), sourceOrder = 2),
      decl("border-color", colorValue(currentColor()), sourceOrder = 3),
      decl("color", colorValue(rgb(0, 1, 0)), sourceOrder = 4)
    ])

    check context.declarations.len == 4
    check context.declarations[0].property == "color"
    check context.declarations[0].sourceOrder == 2
    check context.declarations[1].property == "color"
    check context.declarations[1].sourceOrder == 4
    check context.declarations[2].property == "background-color"
    check context.declarations[3].property == "border-color"

  test "wide-gamut authored colors resolve once into compact computed colors":
    let authored = displayP3(0.8, 0.25, 0.1, 0.7)
    let expected = authored.resolveColor()
    let style = styleContext([
      decl("color", colorValue(authored)),
      decl("background-color", colorValue(authored)),
      decl("border-color", colorValue(authored)),
      decl("outline-color", colorValue(authored)),
      decl("caret-color", colorValue(authored)),
      decl("accent-color", colorValue(authored)),
      decl("column-rule-color", colorValue(authored)),
      decl("text-decoration-color", colorValue(authored)),
      decl("text-emphasis-color", colorValue(authored)),
      decl("fill", colorValue(authored)),
      decl("flood-color", colorValue(authored)),
      decl("lighting-color", colorValue(authored)),
      decl("stop-color", colorValue(authored)),
      decl("stroke", colorValue(authored)),
      decl("stroke-color", colorValue(authored))
    ]).resolved()

    style.text.color.checkColor(expected)
    style.box.backgroundColor.checkColor(expected)
    style.box.borderColor.checkColor(expected)
    style.box.borderColors.top.checkColor(expected)
    style.box.outlineColor.checkColor(expected)
    style.visual.caretColor.checkColor(expected)
    style.visual.accentColor.checkColor(expected)
    style.columns.columnRuleColor.checkColor(expected)
    style.text.textDecorationColor.checkColor(expected)
    style.text.textEmphasisColor.checkColor(expected)
    style.vector.fillColor.checkColor(expected)
    style.vector.floodColor.checkColor(expected)
    style.vector.lightingColor.checkColor(expected)
    style.vector.stopColor.checkColor(expected)
    style.vector.strokeColor.checkColor(expected)

  test "plain resolved and authored colors have direct declaration overloads":
    let foreground = rgb(0.2, 0.4, 0.6)
    let background = lab(55, 20, -30)
    let style = styleContext([
      decl("color", foreground),
      decl("background-color", background)
    ]).resolved()

    style.text.color.checkColor(foreground)
    style.box.backgroundColor.checkColor(background.resolveColor())

  test "currentColor consumers observe the final foreground regardless of order":
    let foreground = oklch(0.72, 0.15, 230)
    let expected = foreground.resolveColor()
    let style = styleContext([
      decl("background-color", colorValue(currentColor())),
      decl("border-left-color", colorValue(currentColor())),
      decl("outline-color", colorValue(currentColor())),
      decl("text-decoration-color", colorValue(currentColor())),
      decl("fill", colorValue(currentColor())),
      decl("color", colorValue(foreground))
    ]).resolved()

    style.text.color.checkColor(expected)
    style.box.backgroundColor.checkColor(expected)
    style.box.borderColors.left.checkColor(expected)
    style.box.outlineColor.checkColor(expected)
    style.text.textDecorationColor.checkColor(expected)
    style.vector.fillColor.checkColor(expected)

  test "merged styles retain final foreground semantics":
    let foreground = rgb(0.45, 0.3, 0.8)
    let context = mergeStyles(
      styleContext([
        decl("background-color", currentColor())
      ]),
      styleContext([
        decl("color", foreground)
      ])
    )
    let style = context.resolved()

    style.text.color.checkColor(foreground)
    style.box.backgroundColor.checkColor(foreground)

  test "copied authored values retain their color payload under ARC":
    let authored = colorValue(oklch(0.64, 0.18, 275))
    let copied = authored
    let expected = oklch(0.64, 0.18, 275).resolveColor()

    copied.resolveStyleColor(rgb(0, 0, 0)).checkColor(expected)

  test "currentColor on color itself uses the inherited foreground":
    var parent = initialComputedStyle()
    parent.text.color = some(rgb(0.2, 0.45, 0.7))
    let env = ResolveEnv(parent: computedStyleRef(parent))
    let style = styleContext([
      decl("background-color", colorValue(currentColor())),
      decl("color", colorValue(currentColor()))
    ]).resolved(env)

    style.text.color.checkColor(parent.text.color.get)
    style.box.backgroundColor.checkColor(parent.text.color.get)

  test "root currentColor falls back to the CSS initial foreground":
    let style = styleContext([
      decl("background-color", colorValue(currentColor()))
    ]).resolved()

    style.box.backgroundColor.checkColor(rgb(0, 0, 0))

  test "structured borders and outlines retain authored currentColor":
    let foreground = rgb(0.15, 0.65, 0.35)
    let style = styleContext([
      decl("outline", borderValue(px(2), "solid", currentColor())),
      decl("border", borderValue(px(3), "solid", currentColor())),
      decl("color", colorValue(foreground))
    ]).resolved()

    style.box.outlineColor.checkColor(foreground)
    style.box.borderColors.top.checkColor(foreground)
    style.box.borderColors.right.checkColor(foreground)
    style.box.borderColors.bottom.checkColor(foreground)
    style.box.borderColors.left.checkColor(foreground)

  test "scrollbar pairs resolve each authored endpoint independently":
    let foreground = rgb(0.7, 0.2, 0.4)
    let track = rec2020(0.1, 0.2, 0.3)
    let style = styleContext([
      decl("scrollbar-color", colorPairValue(currentColor(), track)),
      decl("color", colorValue(foreground))
    ]).resolved()

    style.visual.scrollbarThumbColor.checkColor(foreground)
    style.visual.scrollbarTrackColor.checkColor(track.resolveColor())

  test "box and text shadows resolve authored colors after foreground":
    let foreground = rgb(0.3, 0.6, 0.9)
    let style = styleContext([
      decl("box-shadow", shadowValue(px(1), px(2), currentColor(),
        blur = some(px(3)))),
      decl("text-shadow", shadowValue(px(2), px(1), currentColor())),
      decl("color", colorValue(foreground))
    ]).resolved()

    require style.box.boxShadow.isSome
    require style.text.textShadow.isSome
    style.box.boxShadow.get.color.checkColor(foreground)
    style.text.textShadow.get.color.checkColor(foreground)

  test "trusted function foregrounds are resolved before currentColor consumers":
    let foreground = rgb(0.8, 0.35, 0.1)
    let context = styleContext([
      decl("background-color", colorValue(currentColor())),
      decl("color", functionValue(proc(): StyleValue =
      colorValue(foreground)
    ))
    ])
    var diagnostics: Diagnostics
    let style = resolveTrustedStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    require not diagnostics.hasErrors
    style.text.color.checkColor(foreground)
    style.box.backgroundColor.checkColor(foreground)

  test "non-color values still produce property diagnostics":
    let context = styleContext([
      decl("background-color", px(2)),
      decl("color", keyword("red"))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    check diagnostics.hasErrors
    check style.text.color.isNone
    check style.box.backgroundColor.isNone
