import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/core/computed_style
import clay_board_style_system/generated/default_properties

suite "style context merge":
  test "cold animation and transform styles allocate only when used":
    let initial = initialComputedStyle()
    check not initial.hasAnimationStyle
    check not initial.hasTransformStyle
    check initial.animation.transitionProperty == some("all")
    check initial.transform.originX ==
      ComputedLength(kind: cukPercent, value: 50)

    var animated = initialComputedStyle()
    animated.animation.animationName = some("fade")
    check animated.hasAnimationStyle
    check not animated.hasTransformStyle

    var transformed = initialComputedStyle()
    transformed.transform.rotate = some(15.0'f32)
    check not transformed.hasAnimationStyle
    check transformed.hasTransformStyle

  test "copying cold styles keeps value semantics when a child mutates":
    var parent = initialComputedStyle()
    parent.animation.animationName = some("parent")
    parent.transform.rotate = some(10.0'f32)

    var child = initialComputedStyle()
    child.animation = parent.animation
    child.transform = parent.transform
    child.animation.animationName = some("child")
    child.transform.rotate = some(20.0'f32)

    check parent.animation.animationName == some("parent")
    check parent.transform.rotate == some(10.0'f32)
    check child.animation.animationName == some("child")
    check child.transform.rotate == some(20.0'f32)

  test "later declarations overwrite the same property":
    let context = mergeStyles(
      styleContext([
        decl("color", colorValue(rgb(1, 0, 0)))
      ]),
      styleContext([
        decl("color", colorValue(rgb(0, 0, 1)))
      ])
    )

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.text.color.isSome
    check style.text.color.get == rgb(0, 0, 1)

  test "inherit reads from parent computed style":
    var parent: ComputedStyle
    parent.text.color = some(rgb(0.2, 0.3, 0.4))

    let context = styleContext([
      decl("color", inherit())
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(parent: computedStyleRef(parent)), diagnostics
    )

    check not diagnostics.hasErrors
    check style.text.color == parent.text.color

  test "relative padding reads from parent and adds px":
    var parent: ComputedStyle
    parent.box.padding = some(edges(8))

    let context = styleContext([
      decl("padding", relative(px(4)))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(parent: computedStyleRef(parent)), diagnostics
    )

    check not diagnostics.hasErrors
    check style.box.padding.isSome
    check style.box.padding.get == edges(12)

  test "side-specific padding and margin update one edge":
    let context = styleContext([
      decl("padding", px(4)),
      decl("padding-left", px(10)),
      decl("margin", px(2)),
      decl("margin-top", px(8))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.padding.get.top == 4
    check style.box.padding.get.right == 4
    check style.box.padding.get.bottom == 4
    check style.box.padding.get.left == 10
    check style.box.margin.get.top == 8
    check style.box.margin.get.right == 2
    check style.box.margin.get.bottom == 2
    check style.box.margin.get.left == 2

  test "logical sizing padding and margin map to horizontal ltr physical edges":
    let context = styleContext([
      decl("inline-size", px(120)),
      decl("block-size", px(48)),
      decl("min-inline-size", px(80)),
      decl("max-inline-size", px(180)),
      decl("min-block-size", px(32)),
      decl("max-block-size", px(96)),
      decl("padding-inline", px(10)),
      decl("padding-inline-start", px(14)),
      decl("padding-block", px(6)),
      decl("padding-block-end", px(9)),
      decl("margin-inline", px(3)),
      decl("margin-inline-end", px(7)),
      decl("margin-block", px(4)),
      decl("margin-block-start", px(8))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.layout.width == some(120.0'f32)
    check style.layout.height == some(48.0'f32)
    check style.layout.minWidth == some(80.0'f32)
    check style.layout.maxWidth == some(180.0'f32)
    check style.layout.minHeight == some(32.0'f32)
    check style.layout.maxHeight == some(96.0'f32)
    check style.box.padding.get.top == 6
    check style.box.padding.get.right == 10
    check style.box.padding.get.bottom == 9
    check style.box.padding.get.left == 14
    check style.box.margin.get.top == 8
    check style.box.margin.get.right == 7
    check style.box.margin.get.bottom == 4
    check style.box.margin.get.left == 3

  test "side-specific border properties update one edge or corner":
    let context = styleContext([
      decl("border-width", px(2)),
      decl("border-left-width", px(6)),
      decl("border-color", colorValue(rgb(0, 0, 0))),
      decl("border-top-color", colorValue(rgb(1, 0, 0))),
      decl("border-style", keyword("solid")),
      decl("border-right-style", keyword("none")),
      decl("border-radius", px(3)),
      decl("border-bottom-right-radius", px(9))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.borderWidths.top == 2
    check style.box.borderWidths.right == 2
    check style.box.borderWidths.bottom == 2
    check style.box.borderWidths.left == 6
    check style.box.borderColors.top == some(rgb(1, 0, 0))
    check style.box.borderColors.right == some(rgb(0, 0, 0))
    check style.box.borderColors.bottom == some(rgb(0, 0, 0))
    check style.box.borderColors.left == some(rgb(0, 0, 0))
    check style.box.borderVisible
    check style.box.borderSideVisible.top
    check not style.box.borderSideVisible.right
    check style.box.borderSideVisible.bottom
    check style.box.borderSideVisible.left
    check style.box.borderRadii.topLeft == 3
    check style.box.borderRadii.topRight == 3
    check style.box.borderRadii.bottomRight == 9
    check style.box.borderRadii.bottomLeft == 3

  test "border shorthand maps a single value to width or color":
    let context = styleContext([
      decl("border", px(2)),
      decl("border-left", px(7)),
      decl("border", colorValue(rgb(0, 0, 1))),
      decl("border-left", colorValue(rgb(1, 0, 0)))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.borderWidths.top == 2
    check style.box.borderWidths.right == 2
    check style.box.borderWidths.bottom == 2
    check style.box.borderWidths.left == 7
    check style.box.borderColors.top == some(rgb(0, 0, 1))
    check style.box.borderColors.right == some(rgb(0, 0, 1))
    check style.box.borderColors.bottom == some(rgb(0, 0, 1))
    check style.box.borderColors.left == some(rgb(1, 0, 0))

  test "border shorthand accepts structured values":
    let context = styleContext([
      decl("border", borderValue(lineWeight = px(2), lineStyle = "solid", lineColor = rgb(0, 0, 1))),
      decl("border-left", borderValue(lineWeight = px(5), lineStyle = "solid", lineColor = rgb(1, 0, 0)))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.borderVisible
    check style.box.borderWidths.top == 2
    check style.box.borderWidths.right == 2
    check style.box.borderWidths.bottom == 2
    check style.box.borderWidths.left == 5
    check style.box.borderColors.top == some(rgb(0, 0, 1))
    check style.box.borderColors.right == some(rgb(0, 0, 1))
    check style.box.borderColors.bottom == some(rgb(0, 0, 1))
    check style.box.borderColors.left == some(rgb(1, 0, 0))

  test "logical border properties map to horizontal ltr physical edges":
    let context = styleContext([
      decl("border-inline", borderValue(lineWeight = px(2), lineStyle = "solid", lineColor = rgb(0, 0, 1))),
      decl("border-block-width", px(4)),
      decl("border-block-color", colorValue(rgb(0, 1, 0))),
      decl("border-inline-start-width", px(7)),
      decl("border-inline-end-style", keyword("none")),
      decl("border-block-start-color", colorValue(rgb(1, 0, 0))),
      decl("border-start-start-radius", px(3)),
      decl("border-start-end-radius", px(5)),
      decl("border-end-start-radius", px(9)),
      decl("border-end-end-radius", px(11))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.borderWidths.top == 4
    check style.box.borderWidths.right == 2
    check style.box.borderWidths.bottom == 4
    check style.box.borderWidths.left == 7
    check style.box.borderColors.top == some(rgb(1, 0, 0))
    check style.box.borderColors.right == some(rgb(0, 0, 1))
    check style.box.borderColors.bottom == some(rgb(0, 1, 0))
    check style.box.borderColors.left == some(rgb(0, 0, 1))
    check style.box.borderSideVisible.left
    check not style.box.borderSideVisible.right
    check style.box.borderRadii.topLeft == 3
    check style.box.borderRadii.topRight == 5
    check style.box.borderRadii.bottomLeft == 9
    check style.box.borderRadii.bottomRight == 11

  test "text properties resolve to computed text style":
    let context = styleContext([
      decl("font-family", fontFamilyValue("Inter", "Noto Sans JP", genericSansSerif())),
      decl("font-style", keyword("italic")),
      decl("font-weight", keyword("bold")),
      decl("font-stretch", keyword("condensed")),
      decl("font-feature-settings", keyword("kern 1, liga 0")),
      decl("font-variation-settings", keyword("wght 650")),
      decl("font-kerning", keyword("normal")),
      decl("font-optical-sizing", keyword("auto")),
      decl("font-size-adjust", number(0.8)),
      decl("font-variant-ligatures", keyword("common-ligatures contextual")),
      decl("font-variant-caps", keyword("small-caps")),
      decl("font-variant-numeric", keyword("tabular-nums slashed-zero")),
      decl("font-variant-east-asian", keyword("jis04 ruby")),
      decl("font-variant-position", keyword("super")),
      decl("font-variant-alternates", keyword("historical-forms")),
      decl("font-variant-emoji", keyword("emoji")),
      decl("font-language-override", keyword("TRK")),
      decl("font-palette", keyword("light")),
      decl("font-synthesis", keyword("weight style")),
      decl("font-synthesis-position", keyword("none")),
      decl("font-synthesis-small-caps", keyword("auto")),
      decl("font-synthesis-style", keyword("none")),
      decl("font-synthesis-weight", keyword("auto")),
      decl("font-size", px(20)),
      decl("line-height", number(1.4)),
      decl("text-align", keyword("center")),
      decl("text-align-last", keyword("right")),
      decl("white-space", keyword("nowrap")),
      decl("direction", keyword("rtl")),
      decl("unicode-bidi", keyword("isolate")),
      decl("writing-mode", keyword("vertical-rl")),
      decl("tab-size", number(4))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.text.fontFamily == some("Inter")
    check style.text.fontFamilies == @["Inter", "Noto Sans JP", "sans-serif"]
    check style.text.fontStyle == some(fsItalic)
    check style.text.fontWeight == some(700.0'f32)
    check style.text.fontStretch == some(75.0'f32)
    check style.text.fontFeatureSettings == some("kern 1, liga 0")
    check style.text.fontVariationSettings == some("wght 650")
    check style.text.fontKerning == some(fkNormal)
    check style.text.fontOpticalSizing == some(fosAuto)
    check style.text.fontSizeAdjust == some(0.8'f32)
    check style.text.fontVariantLigatures == some("common-ligatures contextual")
    check style.text.fontVariantCaps == some("small-caps")
    check style.text.fontVariantNumeric == some("tabular-nums slashed-zero")
    check style.text.fontVariantEastAsian == some("jis04 ruby")
    check style.text.fontVariantPosition == some("super")
    check style.text.fontVariantAlternates == some("historical-forms")
    check style.text.fontVariantEmoji == some("emoji")
    check style.text.fontLanguageOverride == some("TRK")
    check style.text.fontPalette == some("light")
    check style.text.fontSynthesis == some("weight style")
    check style.text.fontSynthesisPosition.isNone
    check style.text.fontSynthesisSmallCaps == some("auto")
    check style.text.fontSynthesisStyle.isNone
    check style.text.fontSynthesisWeight == some("auto")
    check style.text.lineHeight == some(28.0'f32)
    check style.text.textAlign == some(taCenter)
    check style.text.textAlignLast == some(taRight)
    check style.text.whiteSpace == some(wsNoWrap)
    check style.text.direction == some(tdRtl)
    check style.text.unicodeBidi == some(ubIsolate)
    check style.text.writingMode == some(wmVerticalRl)
    check style.text.tabSize == some(4.0'f32)

  test "image object properties resolve to computed image style":
    let context = styleContext([
      decl("object-fit", keyword("cover")),
      decl("object-position", keyword("bottom")),
      decl("image-rendering", keyword("pixelated"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.image.objectFit == some(ofCover)
    check style.image.objectPosition.isSome
    check style.image.objectPosition.get.x == 50
    check style.image.objectPosition.get.y == 100
    check style.image.imageRendering == irPixelated

  test "p1 layout and input properties resolve to computed style":
    let context = styleContext([
      decl("aspect-ratio", number(1.5)),
      decl("box-sizing", keyword("border-box")),
      decl("inset", px(8)),
      decl("inset-block-start", px(3)),
      decl("inset-inline-end", px(5)),
      decl("pointer-events", keyword("none")),
      decl("cursor", keyword("pointer")),
      decl("user-select", keyword("none"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.layout.aspectRatio == some(1.5'f32)
    check style.layout.boxSizing == bsBorderBox
    check style.layout.inset.top == some(3.0'f32)
    check style.layout.inset.right == some(5.0'f32)
    check style.layout.inset.bottom == some(8.0'f32)
    check style.layout.inset.left == some(8.0'f32)
    check style.visual.pointerEvents == peNone
    check style.visual.cursor == some(ckPointer)
    check style.visual.userSelect == some(usNone)

  test "p1 alignment and input extension properties resolve to computed style":
    let context = styleContext([
      decl("order", number(3)),
      decl("align-content", keyword("center")),
      decl("align-self", keyword("end")),
      decl("justify-items", keyword("center")),
      decl("justify-self", keyword("end")),
      decl("place-content", keyword("space-between")),
      decl("place-items", keyword("stretch")),
      decl("place-self", keyword("center")),
      decl("caret-color", colorValue(rgb(1, 0, 0))),
      decl("accent-color", colorValue(rgb(0, 1, 0))),
      decl("resize", keyword("both")),
      decl("color-scheme", keyword("light dark")),
      decl("forced-color-adjust", keyword("none")),
      decl("print-color-adjust", keyword("exact")),
      decl("will-change", keyword("opacity, transform")),
      decl("scrollbar-width", keyword("thin")),
      decl("scrollbar-color", colorPairValue(rgb(0.2, 0.3, 0.4), rgb(0.05, 0.06, 0.07))),
      decl("scrollbar-gutter", keyword("stable both-edges")),
      decl("scroll-behavior", keyword("smooth")),
      decl("overscroll-behavior", keyword("contain")),
      decl("overscroll-behavior-y", keyword("none")),
      decl("overscroll-behavior-block", keyword("contain")),
      decl("overscroll-behavior-inline", keyword("none")),
      decl("overflow-anchor", keyword("none")),
      decl("overflow-clip-margin", px(12)),
      decl("touch-action", keyword("manipulation")),
      decl("reading-flow", keyword("flex-flow")),
      decl("reading-order", number(4))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.layout.order == 3
    check style.layout.alignContent == jcSpaceBetween
    check style.layout.alignItems == aiStretch
    check style.layout.alignSelf == some(aiCenter)
    check style.layout.justifyContent == jcSpaceBetween
    check style.layout.justifyItems == some(saStretch)
    check style.layout.justifySelf == some(saCenter)
    check style.visual.caretColor == some(rgb(1, 0, 0))
    check style.visual.accentColor == some(rgb(0, 1, 0))
    check style.visual.resize == rkBoth
    check style.visual.colorScheme == some("light dark")
    check style.visual.forcedColorAdjust == caNone
    check style.visual.printColorAdjust == pcaExact
    check style.visual.willChange == some("opacity, transform")
    check style.visual.scrollbarWidth == swThin
    check style.visual.scrollbarThumbColor == some(rgb(0.2, 0.3, 0.4))
    check style.visual.scrollbarTrackColor == some(rgb(0.05, 0.06, 0.07))
    check style.visual.scrollbarGutter == some("stable both-edges")
    check style.visual.scrollBehavior == sbSmooth
    check style.visual.overscrollBehaviorX == obContain
    check style.visual.overscrollBehaviorY == obNone
    check style.visual.overscrollBehaviorBlock == obContain
    check style.visual.overscrollBehaviorInline == obNone
    check not style.visual.overflowAnchor
    check style.visual.overflowClipMargin == some(12.0'f32)
    check style.visual.touchAction == taManipulation
    check style.visual.readingFlow == rfFlexFlow
    check style.visual.readingOrder == 4

  test "flex shorthand and wrapping properties resolve to computed layout style":
    let context = styleContext([
      decl("display", keyword("flex")),
      decl("flex-direction", keyword("row")),
      decl("flex-flow", keyword("column wrap")),
      decl("flex", number(2)),
      decl("flex-wrap", keyword("wrap-reverse")),
      decl("flex-basis", px(120))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.layout.display == dkFlex
    check style.layout.direction == fdColumn
    check style.layout.flexWrap == fwWrapReverse
    check style.layout.flexGrow == 2
    check style.layout.flexShrink == 1
    check style.layout.flexBasis == some(120.0'f32)

  test "animation and transition properties resolve to computed animation style":
    let context = styleContext([
      decl("animation", keyword("fade 0.2s ease")),
      decl("animation-name", keyword("fade")),
      decl("animation-duration", number(0.2)),
      decl("animation-delay", number(0.05)),
      decl("animation-timing-function", keyword("ease-in-out")),
      decl("animation-iteration-count", keyword("infinite")),
      decl("animation-direction", keyword("alternate")),
      decl("animation-fill-mode", keyword("both")),
      decl("animation-play-state", keyword("paused")),
      decl("animation-composition", keyword("add")),
      decl("animation-range", keyword("entry exit")),
      decl("animation-range-start", keyword("entry")),
      decl("animation-range-end", keyword("exit")),
      decl("animation-timeline", keyword("auto")),
      decl("animation-trigger", keyword("click")),
      decl("transition", keyword("opacity 0.2s ease")),
      decl("transition-property", keyword("opacity")),
      decl("transition-duration", number(0.2)),
      decl("transition-delay", number(0.04)),
      decl("transition-timing-function", keyword("linear")),
      decl("transition-behavior", keyword("allow-discrete"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.animation.rawAnimation == some("fade 0.2s ease")
    check style.animation.animationName == some("fade")
    check style.animation.animationDuration == 0.2'f32
    check style.animation.animationDelay == 0.05'f32
    check style.animation.animationTimingFunction == some("ease-in-out")
    check style.animation.animationIterationCount.isNone
    check style.animation.animationDirection == adAlternate
    check style.animation.animationFillMode == afBoth
    check style.animation.animationPlayState == apsPaused
    check style.animation.animationComposition == acAdd
    check style.animation.animationRange == some("entry exit")
    check style.animation.animationRangeStart == some("entry")
    check style.animation.animationRangeEnd == some("exit")
    check style.animation.animationTimeline == some("auto")
    check style.animation.animationTrigger == some("click")
    check style.animation.rawTransition == some("opacity 0.2s ease")
    check style.animation.transitionProperty == some("opacity")
    check style.animation.transitionDuration == 0.2'f32
    check style.animation.transitionDelay == 0.04'f32
    check style.animation.transitionTimingFunction == some("linear")
    check style.animation.transitionBehavior == tbAllowDiscrete

  test "animation delay preserves a negative authored offset":
    let context = styleContext([
      decl("animation-duration", number(-1)),
      decl("animation-delay", number(-0.25))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    check not diagnostics.hasErrors
    check style.animation.animationDuration == 0
    check style.animation.animationDelay == -0.25'f32

  test "background properties resolve to computed box style":
    let context = styleContext([
      decl("background", colorValue(rgb(0.1, 0.2, 0.3))),
      decl("background-image", linearGradient(
        135,
        colorStop(rgb(1, 0, 0), 0),
        colorStop(rgb(0, 0, 1), 100)
      )),
      decl("background-size", keyword("cover")),
      decl("background-position-x", percent(25)),
      decl("background-position-y", keyword("bottom")),
      decl("background-repeat", keyword("no-repeat")),
      decl("background-clip", keyword("padding-box")),
      decl("background-origin", keyword("content-box")),
      decl("background-attachment", keyword("local")),
      decl("background-blend-mode", keyword("multiply"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.backgroundColor == some(rgb(0.1, 0.2, 0.3))
    check style.box.backgroundImage.isNone
    check style.box.backgroundGradient.isSome
    check style.box.backgroundGradient.get.angle == 135
    check style.box.backgroundGradient.get.stops.len == 2
    check style.box.backgroundSize.isSome
    check style.box.backgroundSize.get.kind == bgSizeCover
    check style.box.backgroundPosition.x == 25
    check style.box.backgroundPosition.y == 100
    check style.box.backgroundRepeat == bgNoRepeat
    check style.box.backgroundClip == bgPaddingBox
    check style.box.backgroundOrigin == bgContentBox
    check style.box.backgroundAttachment == bgLocal
    check style.box.backgroundBlendMode == bmMultiply

  test "function values are evaluated before property application":
    let base = 12.0'f32
    let context = styleContext([
      decl("padding-left", computedValue(proc(): StyleValue = px(base + 8))),
      decl("color", functionValue(proc(): StyleValue = colorValue(rgb(0.2, 0.4, 0.6))))
    ])

    var diagnostics: Diagnostics
    let style = resolveTrustedStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.padding.isSome
    check style.box.padding.get.left == 20
    check style.text.color == some(rgb(0.2, 0.4, 0.6))

  test "regular style resolution rejects function values":
    let context = styleContext([
      decl("padding-left", computedValue(proc(): StyleValue = px(20)))
    ])

    var diagnostics: Diagnostics
    discard resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check diagnostics.hasErrors

  test "shadow and outline properties resolve to computed box style":
    let context = styleContext([
      decl("box-shadow", shadowValue(
        offsetX = px(4),
        offsetY = px(6),
        blur = some(px(10)),
        spread = some(px(2)),
        shadowColor = some(rgba(0, 0, 0, 0.35))
      )),
      decl("mix-blend-mode", keyword("multiply")),
      decl("isolation", keyword("isolate")),
      decl("box-decoration-break", keyword("clone")),
      decl("outline", borderValue(lineWeight = px(2), lineStyle = "solid", lineColor = rgb(1, 0, 0))),
      decl("outline-offset", px(3))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.boxShadow.isSome
    check style.box.boxShadow.get.offsetX == 4
    check style.box.boxShadow.get.offsetY == 6
    check style.box.boxShadow.get.blur == 10
    check style.box.boxShadow.get.spread == 2
    check style.box.boxShadow.get.color == some(rgba(0, 0, 0, 0.35))
    check style.visual.mixBlendMode == bmMultiply
    check style.visual.isolation == isoIsolate
    check style.box.boxDecorationBreak == bdbClone
    check style.box.outlineVisible
    check style.box.outlineWidth == 2
    check style.box.outlineColor == some(rgb(1, 0, 0))
    check style.box.outlineOffset == 3

  test "visual effect metadata properties resolve to computed style":
    let context = styleContext([
      decl("filter", keyword("blur(8px) saturate(1.2)")),
      decl("backdrop-filter", keyword("blur(12px)")),
      decl("appearance", keyword("textfield")),
      decl("content-visibility", keyword("auto")),
      decl("caret-animation", keyword("manual")),
      decl("caret-shape", keyword("block")),
      decl("dynamic-range-limit", keyword("constrained")),
      decl("field-sizing", keyword("content")),
      decl("interactivity", keyword("inert")),
      decl("interpolate-size", keyword("allow-keywords")),
      decl("overlay", keyword("manual")),
      decl("backface-visibility", keyword("hidden")),
      decl("perspective", px(640)),
      decl("perspective-origin", percent(25))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.visual.filter == some("blur(8px) saturate(1.2)")
    check style.visual.backdropFilter == some("blur(12px)")
    check style.visual.appearance == some("textfield")
    check style.visual.contentVisibility == some("auto")
    check style.visual.caretAnimation == some("manual")
    check style.visual.caretShape == some("block")
    check style.visual.dynamicRangeLimit == some("constrained")
    check style.visual.fieldSizing == some("content")
    check style.visual.interactivity == some("inert")
    check style.visual.interpolateSize == some("allow-keywords")
    check style.visual.overlay == some("manual")
    check not style.transform.backfaceVisible
    check style.transform.perspective.isSome
    check style.transform.perspective.get.kind == cukPx
    check style.transform.perspective.get.value == 640
    check style.transform.perspectiveOriginX.kind == cukPercent
    check style.transform.perspectiveOriginX.value == 25

  test "mask metadata properties resolve to computed mask style":
    let context = styleContext([
      decl("mask", keyword("url(mask.png) alpha")),
      decl("mask-border", keyword("url(border-mask.png) 30 fill")),
      decl("mask-border-mode", keyword("alpha")),
      decl("mask-border-outset", keyword("4")),
      decl("mask-border-repeat", keyword("round")),
      decl("mask-border-slice", keyword("30 fill")),
      decl("mask-border-source", keyword("url(border-mask.png)")),
      decl("mask-border-width", keyword("12")),
      decl("mask-clip", keyword("padding-box")),
      decl("mask-composite", keyword("add")),
      decl("mask-image", keyword("linear-gradient(black, transparent)")),
      decl("mask-mode", keyword("luminance")),
      decl("mask-origin", keyword("content-box")),
      decl("mask-position", keyword("center")),
      decl("mask-repeat", keyword("no-repeat")),
      decl("mask-size", keyword("cover")),
      decl("mask-type", keyword("alpha"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.mask.mask == some("url(mask.png) alpha")
    check style.mask.maskBorder == some("url(border-mask.png) 30 fill")
    check style.mask.maskBorderMode == some("alpha")
    check style.mask.maskBorderOutset == some("4")
    check style.mask.maskBorderRepeat == some("round")
    check style.mask.maskBorderSlice == some("30 fill")
    check style.mask.maskBorderSource == some("url(border-mask.png)")
    check style.mask.maskBorderWidth == some("12")
    check style.mask.maskClip == some("padding-box")
    check style.mask.maskComposite == some("add")
    check style.mask.maskImage == some("linear-gradient(black, transparent)")
    check style.mask.maskMode == some("luminance")
    check style.mask.maskOrigin == some("content-box")
    check style.mask.maskPosition == some("center")
    check style.mask.maskRepeat == some("no-repeat")
    check style.mask.maskSize == some("cover")
    check style.mask.maskType == some("alpha")

  test "vector metadata properties resolve to computed vector style":
    let context = styleContext([
      decl("color-interpolation-filters", keyword("sRGB")),
      decl("fill", colorValue(rgb(1, 0, 0))),
      decl("fill-opacity", number(0.75)),
      decl("fill-rule", keyword("evenodd")),
      decl("flood-color", colorValue(rgb(0, 1, 0))),
      decl("flood-opacity", number(0.4)),
      decl("lighting-color", colorValue(rgb(1, 1, 0))),
      decl("marker", keyword("url(marker.svg)")),
      decl("paint-order", keyword("stroke fill markers")),
      decl("stop-color", colorValue(rgb(0, 0, 1))),
      decl("stop-opacity", number(0.5)),
      decl("stroke", colorValue(rgb(0.2, 0.3, 0.4))),
      decl("stroke-color", colorValue(rgb(0.4, 0.3, 0.2))),
      decl("stroke-dasharray", keyword("4 2")),
      decl("stroke-dashoffset", px(3)),
      decl("stroke-linecap", keyword("round")),
      decl("stroke-linejoin", keyword("bevel")),
      decl("stroke-miterlimit", number(5)),
      decl("stroke-opacity", number(0.8)),
      decl("stroke-width", px(2)),
      decl("vector-effect", keyword("non-scaling-stroke"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.vector.colorInterpolationFilters == some("sRGB")
    check style.vector.fillColor == some(rgb(1, 0, 0))
    check style.vector.fillOpacity == some(0.75'f32)
    check style.vector.fillRule == some("evenodd")
    check style.vector.floodColor == some(rgb(0, 1, 0))
    check style.vector.floodOpacity == some(0.4'f32)
    check style.vector.lightingColor == some(rgb(1, 1, 0))
    check style.vector.marker == some("url(marker.svg)")
    check style.vector.paintOrder == some("stroke fill markers")
    check style.vector.stopColor == some(rgb(0, 0, 1))
    check style.vector.stopOpacity == some(0.5'f32)
    check style.vector.strokeColor == some(rgb(0.4, 0.3, 0.2))
    check style.vector.strokeDasharray == some("4 2")
    check style.vector.strokeDashoffset == some(3.0'f32)
    check style.vector.strokeLinecap == some("round")
    check style.vector.strokeLinejoin == some("bevel")
    check style.vector.strokeMiterlimit == some(5.0'f32)
    check style.vector.strokeOpacity == some(0.8'f32)
    check style.vector.strokeWidth == some(2.0'f32)
    check style.vector.vectorEffect == some("non-scaling-stroke")

  test "image metadata properties resolve to computed image style":
    let context = styleContext([
      decl("image-orientation", keyword("from-image")),
      decl("image-resolution", keyword("300dpi")),
      decl("object-view-box", keyword("inset(10px 20px)"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.image.imageOrientation == some("from-image")
    check style.image.imageResolution == some("300dpi")
    check style.image.objectViewBox == some("inset(10px 20px)")

  test "column metadata properties resolve to computed columns style":
    let context = styleContext([
      decl("column-count", number(3)),
      decl("column-fill", keyword("balance")),
      decl("column-height", px(240)),
      decl("column-rule", keyword("2px solid currentColor")),
      decl("column-rule-color", colorValue(rgb(0.2, 0.4, 0.8))),
      decl("column-rule-style", keyword("solid")),
      decl("column-rule-width", px(2)),
      decl("column-span", keyword("all")),
      decl("column-width", px(160)),
      decl("column-wrap", keyword("wrap")),
      decl("columns", keyword("160px 3"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.columns.columnCount == some(3)
    check style.columns.columnFill == some("balance")
    check style.columns.columnHeight == some(240.0'f32)
    check style.columns.columnRule == some("2px solid currentColor")
    check style.columns.columnRuleColor == some(rgb(0.2, 0.4, 0.8))
    check style.columns.columnRuleStyle == some("solid")
    check style.columns.columnRuleWidth == some(2.0'f32)
    check style.columns.columnSpan == some("all")
    check style.columns.columnWidth == some(160.0'f32)
    check style.columns.columnWrap == some("wrap")
    check style.columns.columns == some("160px 3")

  test "border image and corner shape metadata resolve to computed box style":
    let context = styleContext([
      decl("border-image", keyword("url(frame.png) 30 fill")),
      decl("border-image-outset", keyword("4")),
      decl("border-image-repeat", keyword("round")),
      decl("border-image-slice", keyword("30 fill")),
      decl("border-image-source", keyword("url(frame.png)")),
      decl("border-image-width", keyword("12")),
      decl("corner-shape", keyword("scoop")),
      decl("corner-top-shape", keyword("round")),
      decl("corner-right-shape", keyword("bevel")),
      decl("corner-bottom-shape", keyword("notch")),
      decl("corner-left-shape", keyword("squircle")),
      decl("corner-top-left-shape", keyword("round")),
      decl("corner-top-right-shape", keyword("bevel")),
      decl("corner-bottom-right-shape", keyword("notch")),
      decl("corner-bottom-left-shape", keyword("scoop")),
      decl("corner-block-start-shape", keyword("round")),
      decl("corner-block-end-shape", keyword("bevel")),
      decl("corner-inline-start-shape", keyword("scoop")),
      decl("corner-inline-end-shape", keyword("notch")),
      decl("corner-start-start-shape", keyword("round")),
      decl("corner-start-end-shape", keyword("bevel")),
      decl("corner-end-start-shape", keyword("scoop")),
      decl("corner-end-end-shape", keyword("notch"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.box.borderImage == some("url(frame.png) 30 fill")
    check style.box.borderImageOutset == some("4")
    check style.box.borderImageRepeat == some("round")
    check style.box.borderImageSlice == some("30 fill")
    check style.box.borderImageSource == some("url(frame.png)")
    check style.box.borderImageWidth == some("12")
    check style.box.cornerShape == some("scoop")
    check style.box.cornerTopShape == some("round")
    check style.box.cornerRightShape == some("bevel")
    check style.box.cornerBottomShape == some("notch")
    check style.box.cornerLeftShape == some("squircle")
    check style.box.cornerTopLeftShape == some("round")
    check style.box.cornerTopRightShape == some("bevel")
    check style.box.cornerBottomRightShape == some("notch")
    check style.box.cornerBottomLeftShape == some("scoop")
    check style.box.cornerBlockStartShape == some("round")
    check style.box.cornerBlockEndShape == some("bevel")
    check style.box.cornerInlineStartShape == some("scoop")
    check style.box.cornerInlineEndShape == some("notch")
    check style.box.cornerStartStartShape == some("round")
    check style.box.cornerStartEndShape == some("bevel")
    check style.box.cornerEndStartShape == some("scoop")
    check style.box.cornerEndEndShape == some("notch")

  test "timeline trigger metadata resolves to computed animation style":
    let context = styleContext([
      decl("timeline-trigger", keyword("panel-open")),
      decl("timeline-trigger-activation-range", keyword("entry 0% exit 100%")),
      decl("timeline-trigger-activation-range-end", keyword("exit 100%")),
      decl("timeline-trigger-activation-range-start", keyword("entry 0%")),
      decl("timeline-trigger-active-range", keyword("cover")),
      decl("timeline-trigger-active-range-end", keyword("cover 100%")),
      decl("timeline-trigger-active-range-start", keyword("cover 0%")),
      decl("timeline-trigger-name", keyword("panelTimeline")),
      decl("timeline-trigger-source", keyword("nearest")),
      decl("trigger-scope", keyword("root"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.animation.timelineTrigger == some("panel-open")
    check style.animation.timelineTriggerActivationRange == some("entry 0% exit 100%")
    check style.animation.timelineTriggerActivationRangeEnd == some("exit 100%")
    check style.animation.timelineTriggerActivationRangeStart == some("entry 0%")
    check style.animation.timelineTriggerActiveRange == some("cover")
    check style.animation.timelineTriggerActiveRangeEnd == some("cover 100%")
    check style.animation.timelineTriggerActiveRangeStart == some("cover 0%")
    check style.animation.timelineTriggerName == some("panelTimeline")
    check style.animation.timelineTriggerSource == some("nearest")
    check style.animation.triggerScope == some("root")

  test "baseline metadata resolves to computed text style":
    let context = styleContext([
      decl("alignment-baseline", keyword("middle")),
      decl("baseline-shift", keyword("sub")),
      decl("baseline-source", keyword("first")),
      decl("dominant-baseline", keyword("central"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.text.alignmentBaseline == some("middle")
    check style.text.baselineShift == some("sub")
    check style.text.baselineSource == some("first")
    check style.text.dominantBaseline == some("central")

  test "svg geometry metadata resolves to computed vector style":
    let context = styleContext([
      decl("x", px(12)),
      decl("y", px(24)),
      decl("cx", number(32)),
      decl("cy", number(48)),
      decl("d", keyword("M0 0 L10 10")),
      decl("r", px(8)),
      decl("rx", px(4)),
      decl("ry", px(6))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.vector.x == some(12.0'f32)
    check style.vector.y == some(24.0'f32)
    check style.vector.cx == some(32.0'f32)
    check style.vector.cy == some(48.0'f32)
    check style.vector.d == some("M0 0 L10 10")
    check style.vector.r == some(8.0'f32)
    check style.vector.rx == some(4.0'f32)
    check style.vector.ry == some(6.0'f32)

  test "overflow axis metadata resolves to computed visual style":
    let context = styleContext([
      decl("overflow-block", keyword("clip")),
      decl("overflow-clip-box", keyword("padding-box")),
      decl("overflow-inline", keyword("auto"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.visual.overflowBlock == some("clip")
    check style.visual.overflowClipBox == some("padding-box")
    check style.visual.overflowInline == some("auto")

  test "remaining planned metadata properties resolve to computed styles":
    let context = styleContext([
      decl("align-tracks", keyword("center")),
      decl("justify-tracks", keyword("space-between")),
      decl("margin-trim", keyword("block")),
      decl("box-align", keyword("center")),
      decl("box-direction", keyword("reverse")),
      decl("box-flex", number(1)),
      decl("box-flex-group", number(2)),
      decl("box-lines", keyword("multiple")),
      decl("box-ordinal-group", number(3)),
      decl("box-orient", keyword("horizontal")),
      decl("box-pack", keyword("justify")),
      decl("border-collapse", keyword("collapse")),
      decl("border-shape", keyword("round")),
      decl("border-spacing", keyword("8px 12px")),
      decl("caret", keyword("auto")),
      decl("clip-path", keyword("inset(4px)")),
      decl("clip-rule", keyword("evenodd")),
      decl("interest-delay", keyword("120ms")),
      decl("interest-delay-end", keyword("80ms")),
      decl("interest-delay-start", keyword("40ms")),
      decl("max-lines", keyword("3")),
      decl("ruby-merge", keyword("merge")),
      decl("scroll-initial-target", keyword("nearest")),
      decl("scroll-marker-group", keyword("after")),
      decl("scroll-target-group", keyword("root")),
      decl("view-transition-scope", keyword("local")),
      decl("zoom", number(1.25))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.layout.alignTracks == some("center")
    check style.layout.justifyTracks == some("space-between")
    check style.layout.marginTrim == some("block")
    check style.layout.legacyBoxAlign == some("center")
    check style.layout.legacyBoxDirection == some("reverse")
    check style.layout.legacyBoxFlex == some("1.0")
    check style.layout.legacyBoxFlexGroup == some("2.0")
    check style.layout.legacyBoxLines == some("multiple")
    check style.layout.legacyBoxOrdinalGroup == some("3.0")
    check style.layout.legacyBoxOrient == some("horizontal")
    check style.layout.legacyBoxPack == some("justify")
    check style.box.borderCollapse == some("collapse")
    check style.box.borderShape == some("round")
    check style.box.borderSpacing == some("8px 12px")
    check style.visual.caret == some("auto")
    check style.visual.clipPath == some("inset(4px)")
    check style.visual.clipRule == some("evenodd")
    check style.visual.interestDelay == some("120ms")
    check style.visual.interestDelayEnd == some("80ms")
    check style.visual.interestDelayStart == some("40ms")
    check style.text.maxLines == some("3")
    check style.text.rubyMerge == some("merge")
    check style.visual.scrollInitialTarget == some("nearest")
    check style.visual.scrollMarkerGroup == some("after")
    check style.visual.scrollTargetGroup == some("root")
    check style.visual.viewTransitionScope == some("local")
    check style.visual.zoom == some("1.25")

  test "zoom accepts percent shorthand":
    let context = styleContext([
      decl("zoom", percent(150))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.visual.zoom == some("1.5")

  test "p1 text control properties resolve to computed text style":
    let context = styleContext([
      decl("text-overflow", keyword("ellipsis")),
      decl("overflow-wrap", keyword("anywhere")),
      decl("word-break", keyword("break-all")),
      decl("word-wrap", keyword("break-word")),
      decl("hyphens", keyword("auto")),
      decl("letter-spacing", px(2)),
      decl("word-spacing", px(4)),
      decl("text-decoration", keyword("underline")),
      decl("text-decoration-color", colorValue(rgb(1, 0, 0))),
      decl("text-decoration-style", keyword("dashed")),
      decl("text-decoration-thickness", px(3)),
      decl("text-shadow", shadowValue(offsetX = px(1), offsetY = px(2), shadowColor = some(rgba(0, 0, 0, 0.5)))),
      decl("text-transform", keyword("uppercase")),
      decl("text-indent", px(12)),
      decl("text-wrap", keyword("balance"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.text.textOverflow == some(toEllipsis)
    check style.text.overflowWrap == some(owBreakWord)
    check style.text.wordBreak == some(wbBreakAll)
    check style.text.hyphens == some(hyAuto)
    check style.text.letterSpacing == some(2.0'f32)
    check style.text.wordSpacing == some(4.0'f32)
    check style.text.textDecorationLine == some(tdlUnderline)
    check style.text.textDecorationColor == some(rgb(1, 0, 0))
    check style.text.textDecorationStyle == some(tdsDashed)
    check style.text.textDecorationThickness == some(3.0'f32)
    check style.text.textShadow.isSome
    check style.text.textShadow.get.offsetX == 1
    check style.text.textShadow.get.offsetY == 2
    check style.text.textTransform == some(ttUppercase)
    check style.text.textIndent == some(12.0'f32)
    check style.text.textWrap == some(twBalance)

  test "advanced text metadata properties resolve to computed text style":
    let context = styleContext([
      decl("font", keyword("italic 700 16px Inter")),
      decl("font-width", keyword("expanded")),
      decl("font-smooth", keyword("always")),
      decl("hanging-punctuation", keyword("first allow-end")),
      decl("hyphenate-character", keyword("-")),
      decl("hyphenate-limit-chars", keyword("6 3 3")),
      decl("initial-letter", keyword("2")),
      decl("initial-letter-align", keyword("alphabetic")),
      decl("text-anchor", keyword("middle")),
      decl("text-autospace", keyword("normal")),
      decl("text-box", keyword("trim-both cap alphabetic")),
      decl("text-box-edge", keyword("cap alphabetic")),
      decl("text-box-trim", keyword("trim-both")),
      decl("text-combine-upright", keyword("all")),
      decl("text-decoration-inset", px(2)),
      decl("text-decoration-skip", keyword("spaces")),
      decl("text-decoration-skip-ink", keyword("auto")),
      decl("text-emphasis", keyword("filled circle")),
      decl("text-emphasis-color", colorValue(rgb(1, 0, 0))),
      decl("text-emphasis-position", keyword("over right")),
      decl("text-emphasis-style", keyword("filled dot")),
      decl("text-justify", keyword("inter-character")),
      decl("text-orientation", keyword("mixed")),
      decl("text-rendering", keyword("optimizeLegibility")),
      decl("text-size-adjust", percent(100)),
      decl("text-spacing-trim", keyword("space-all")),
      decl("text-underline-offset", px(3)),
      decl("text-underline-position", keyword("under")),
      decl("white-space-collapse", keyword("preserve")),
      decl("vertical-align", keyword("middle"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.text.rawFont == some("italic 700 16px Inter")
    check style.text.fontWidth == some(125.0'f32)
    check style.text.fontSmooth == some("always")
    check style.text.hangingPunctuation == some("first allow-end")
    check style.text.hyphenateCharacter == some("-")
    check style.text.hyphenateLimitChars == some("6 3 3")
    check style.text.initialLetter == some("2")
    check style.text.initialLetterAlign == some("alphabetic")
    check style.text.textAnchor == some("middle")
    check style.text.textAutospace == some("normal")
    check style.text.textBox == some("trim-both cap alphabetic")
    check style.text.textBoxEdge == some("cap alphabetic")
    check style.text.textBoxTrim == some("trim-both")
    check style.text.textCombineUpright == some("all")
    check style.text.textDecorationInset == some(2.0'f32)
    check style.text.textDecorationSkip == some("spaces")
    check style.text.textDecorationSkipInk == some("auto")
    check style.text.textEmphasis == some("filled circle")
    check style.text.textEmphasisColor == some(rgb(1, 0, 0))
    check style.text.textEmphasisPosition == some("over right")
    check style.text.textEmphasisStyle == some("filled dot")
    check style.text.textJustify == some("inter-character")
    check style.text.textOrientation == some("mixed")
    check style.text.textRendering == some("optimizeLegibility")
    check style.text.textSizeAdjust == some(100.0'f32)
    check style.text.textSpacingTrim == some("space-all")
    check style.text.textUnderlineOffset == some(3.0'f32)
    check style.text.textUnderlinePosition == some("under")
    check style.text.whiteSpaceCollapse == some("preserve")
    check style.text.verticalAlign == some("middle")

  test "font relative unit reports an error without required font context":
    let context = styleContext([
      decl("font-size", em(1.2))
    ])

    var diagnostics: Diagnostics
    discard resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check diagnostics.hasErrors

  test "transform properties resolve to computed transform style":
    let context = styleContext([
      decl("transform", transformValue(
        translate(px(12), px(4)),
        rotate(8),
        scale(1.2, some(0.9'f32))
      )),
      decl("rotate", number(12)),
      decl("scale", scale(1.5, some(0.75'f32))),
      decl("translate", translate(px(24), px(6))),
      decl("transform-origin", percent(25)),
      decl("transform-box", keyword("content-box")),
      decl("transform-style", keyword("preserve-3d"))
    ])

    var diagnostics: Diagnostics
    let style = resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check not diagnostics.hasErrors
    check style.transform.operations.len == 3
    check style.transform.operations[0].kind == ctkTranslate
    check style.transform.operations[0].xLength.get.value == 12
    check style.transform.operations[1].kind == ctkRotate
    check style.transform.operations[1].angle == 8
    check style.transform.operations[2].kind == ctkScale
    check style.transform.rotate == some(12.0'f32)
    check style.transform.scaleX == some(1.5'f32)
    check style.transform.scaleY == some(0.75'f32)
    check style.transform.translateX.get.value == 24
    check style.transform.translateY.get.value == 6
    check style.transform.originX.kind == cukPercent
    check style.transform.originX.value == 25
    check style.transform.originY.value == 25
    check style.transform.transformBox == tboxContentBox
    check style.transform.transformStyle == tsPreserve3d
