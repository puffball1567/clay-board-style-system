import std/[options, sequtils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc authoredValue(declaration: Declaration): StyleValue =
  check declaration.operation.mode == mmOverwrite
  check declaration.operation.value.isSome
  declaration.operation.value.get

proc authoredKeyword(declaration: Declaration): string =
  let value = declaration.authoredValue
  check value.kind == svKeyword
  value.keyword

suite "typed property authoring":
  test "every dimensional helper maps to its documented property":
    let declarations = [
      width(1), height(1), inlineSize(1), blockSize(1),
      minWidth(1), maxWidth(1), minHeight(1), maxHeight(1),
      minInlineSize(1), maxInlineSize(1), minBlockSize(1), maxBlockSize(1),
      inset(1), insetBlock(1), insetBlockStart(1), insetBlockEnd(1),
      insetInline(1), insetInlineStart(1), insetInlineEnd(1),
      top(1), right(1), bottom(1), left(1),
      margin(1), marginTop(1), marginRight(1), marginBottom(1), marginLeft(1),
      marginInline(1), marginInlineStart(1), marginInlineEnd(1),
      marginBlock(1), marginBlockStart(1), marginBlockEnd(1),
      padding(1), paddingTop(1), paddingRight(1), paddingBottom(1),
      paddingLeft(1), paddingInline(1), paddingInlineStart(1),
      paddingInlineEnd(1), paddingBlock(1), paddingBlockStart(1),
      paddingBlockEnd(1), gap(1), rowGap(1), columnGap(1), flexBasis(1),
      borderWidth(1), borderTopWidth(1), borderRightWidth(1),
      borderBottomWidth(1), borderLeftWidth(1), borderInlineWidth(1),
      borderInlineStartWidth(1), borderInlineEndWidth(1), borderBlockWidth(1),
      borderBlockStartWidth(1), borderBlockEndWidth(1), borderRadius(1),
      borderTopLeftRadius(1), borderTopRightRadius(1),
      borderBottomRightRadius(1), borderBottomLeftRadius(1),
      borderStartStartRadius(1), borderStartEndRadius(1),
      borderEndStartRadius(1), borderEndEndRadius(1), fontSize(1)
    ]
    let expected = [
      "width", "height", "inline-size", "block-size",
      "min-width", "max-width", "min-height", "max-height",
      "min-inline-size", "max-inline-size", "min-block-size", "max-block-size",
      "inset", "inset-block", "inset-block-start", "inset-block-end",
      "inset-inline", "inset-inline-start", "inset-inline-end",
      "top", "right", "bottom", "left",
      "margin", "margin-top", "margin-right", "margin-bottom", "margin-left",
      "margin-inline", "margin-inline-start", "margin-inline-end",
      "margin-block", "margin-block-start", "margin-block-end",
      "padding", "padding-top", "padding-right", "padding-bottom",
      "padding-left", "padding-inline", "padding-inline-start",
      "padding-inline-end", "padding-block", "padding-block-start",
      "padding-block-end", "gap", "row-gap", "column-gap", "flex-basis",
      "border-width", "border-top-width", "border-right-width",
      "border-bottom-width", "border-left-width", "border-inline-width",
      "border-inline-start-width", "border-inline-end-width",
      "border-block-width", "border-block-start-width", "border-block-end-width",
      "border-radius", "border-top-left-radius", "border-top-right-radius",
      "border-bottom-right-radius", "border-bottom-left-radius",
      "border-start-start-radius", "border-start-end-radius",
      "border-end-start-radius", "border-end-end-radius", "font-size"
    ]

    check declarations.mapIt(it.property) == expected
    for declaration in declarations:
      check declaration.authoredValue.length ==
        LengthValue(kind: ukPx, value: 1)

  test "dimensional numbers expand to explicit pixel values":
    let declarations = [
      width(320),
      height(180.5),
      padding(12),
      marginInline(-4),
      left(8),
      gap(6),
      borderRadius(5),
      borderTopWidth(2),
      fontSize(14.5)
    ]

    check declarations.mapIt(it.property) == [
      "width", "height", "padding", "margin-inline", "left", "gap",
      "border-radius", "border-top-width", "font-size"
    ]
    for declaration in declarations:
      let value = declaration.authoredValue
      check value.kind == svLength
      check value.length.kind == ukPx
    check declarations[0].authoredValue.length.value == 320
    check declarations[1].authoredValue.length.value == 180.5'f32
    check declarations[3].authoredValue.length.value == -4

  test "explicit units remain typed and source order is retained":
    let declarations = [
      width(percent(75), sourceOrder = 4),
      padding(em(1.25)),
      minHeight(vh(30)),
      fontSize(rem(1))
    ]

    check declarations[0].sourceOrder == 4
    check declarations[0].authoredValue.length ==
      LengthValue(kind: ukPercent, value: 75)
    check declarations[1].authoredValue.length ==
      LengthValue(kind: ukEm, value: 1.25)
    check declarations[2].authoredValue.length ==
      LengthValue(kind: ukVh, value: 30)
    check declarations[3].authoredValue.length ==
      LengthValue(kind: ukRem, value: 1)

  test "unitless properties retain number semantics":
    let declarations = [
      lineHeight(1.4),
      opacity(0.8),
      flexGrow(1),
      flexShrink(0.5),
      fontWeight(650),
      order(-2),
      zIndex(10)
    ]

    for declaration in declarations:
      check declaration.authoredValue.kind == svNumber
    check declarations[0].authoredValue.number == 1.4'f32
    check declarations[3].authoredValue.number == 0.5'f32
    check declarations[5].authoredValue.number == -2

  test "line height also accepts an explicit length":
    let declaration = lineHeight(px(24))

    check declaration.authoredValue.length ==
      LengthValue(kind: ukPx, value: 24)

  test "typed declarations resolve through the normal property registry":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([rule(target(root), [
      width(320),
      height(180),
      padding(12),
      marginLeft(percent(10)),
      fontSize(20),
      lineHeight(1.4),
      opacity(0.8),
      flexGrow(2),
      order(3),
      zIndex(7)
    ])])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics
    )
    let style = resolved.styles[root.nodeIndex]

    check not diagnostics.hasErrors
    check style.layout.width == some(320.0'f32)
    check style.layout.height == some(180.0'f32)
    check style.box.padding == some(edges(12))
    check not style.layout.sizing.isNil
    check style.layout.sizing.marginLeft ==
      some(LengthValue(kind: ukPercent, value: 10))
    check style.text.fontSize == some(20.0'f32)
    check style.text.lineHeight == some(28.0'f32)
    check style.visual.opacity == 0.8'f32
    check style.layout.flexGrow == 2.0'f32
    check style.layout.order == 3
    check style.layout.zIndex == 7

  test "unsupported shorthand input is rejected at compile time":
    static:
      doAssert compiles(width(12))
      doAssert compiles(width(percent(50)))
      doAssert compiles(lineHeight(px(20)))
      doAssert not compiles(width("12px"))
      doAssert not compiles(zIndex(1.5))

  test "closed value helpers map enums to validated keywords":
    let declarations = [
      display(dkNone),
      flexDirection(fdRow),
      flexWrap(fwWrapReverse),
      alignItems(aiCenter),
      alignSelf(aiEnd),
      alignContent(jcSpaceBetween),
      justifyContent(jcEnd),
      justifyItems(saStretch),
      justifySelf(saStart),
      position(pkAbsolute),
      boxSizing(bsBorderBox),
      overflow(omHidden),
      overflowX(omAuto),
      overflowY(omScroll),
      pointerEvents(peNone),
      cursor(ckNotAllowed),
      userSelect(usAll),
      resize(rkVertical),
      fontStyle(fsOblique),
      textAlign(taRight)
    ]

    check declarations.mapIt(it.property) == [
      "display", "flex-direction", "flex-wrap", "align-items", "align-self",
      "align-content", "justify-content", "justify-items", "justify-self",
      "position", "box-sizing", "overflow", "overflow-x", "overflow-y",
      "pointer-events", "cursor", "user-select", "resize", "font-style",
      "text-align"
    ]
    check declarations.mapIt(it.authoredKeyword) == [
      "none", "row", "wrap-reverse", "center", "end", "space-between",
      "end", "stretch", "start", "absolute", "border-box", "hidden",
      "auto", "scroll", "none", "not-allowed", "all", "vertical",
      "oblique", "right"
    ]

  test "typed closed values resolve through their property implementations":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([rule(target(root), [
      display(dkFlex),
      flexDirection(fdRow),
      flexWrap(fwWrapReverse),
      alignItems(aiCenter),
      alignSelf(aiEnd),
      alignContent(jcSpaceBetween),
      justifyContent(jcEnd),
      justifyItems(saStretch),
      justifySelf(saCenter),
      position(pkAbsolute),
      boxSizing(bsBorderBox),
      overflowX(omAuto),
      overflowY(omScroll),
      pointerEvents(peNone),
      cursor(ckPointer),
      userSelect(usAll),
      resize(rkVertical),
      fontStyle(fsItalic),
      textAlign(taRight)
    ])])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )
    let style = resolved.styles[root.nodeIndex]

    check not diagnostics.hasErrors
    check style.layout.display == dkFlex
    check style.layout.direction == fdRow
    check style.layout.flexWrap == fwWrapReverse
    check style.layout.alignItems == aiCenter
    check style.layout.alignSelf == some(aiEnd)
    check style.layout.alignContent == jcSpaceBetween
    check style.layout.justifyContent == jcEnd
    check style.layout.justifyItems == some(saStretch)
    check style.layout.justifySelf == some(saCenter)
    check style.layout.position == pkAbsolute
    check style.layout.boxSizing == bsBorderBox
    check style.layout.overflowX == omAuto
    check style.layout.overflowY == omScroll
    check style.visual.pointerEvents == peNone
    check style.visual.cursor == some(ckPointer)
    check style.visual.userSelect == some(usAll)
    check style.visual.resize == rkVertical
    check style.text.fontStyle == some(fsItalic)
    check style.text.textAlign == some(taRight)

  test "closed value helpers reject strings and unrelated enums":
    static:
      doAssert compiles(flexDirection(fdRow))
      doAssert compiles(overflow(omAuto))
      doAssert not compiles(flexDirection("row"))
      doAssert not compiles(flexDirection(omAuto))
