import ./[computed_style, declaration, style_value]

template defineLengthProperty(name: untyped; propertyName: static[string]) =
  proc name*(value: StyleValue; sourceOrder = 0): Declaration {.inline.} =
    decl(propertyName, value, sourceOrder)

  proc name*(value: SomeInteger; sourceOrder = 0): Declaration {.inline.} =
    decl(propertyName, px(value), sourceOrder)

  proc name*(value: SomeFloat; sourceOrder = 0): Declaration {.inline.} =
    decl(propertyName, px(value), sourceOrder)

template defineNumberProperty(name: untyped; propertyName: static[string]) =
  proc name*(value: SomeNumber; sourceOrder = 0): Declaration {.inline.} =
    decl(propertyName, number(value), sourceOrder)

template defineIntegerProperty(name: untyped; propertyName: static[string]) =
  proc name*(value: SomeInteger; sourceOrder = 0): Declaration {.inline.} =
    decl(propertyName, number(value), sourceOrder)

# Dimensions and constraints.
defineLengthProperty(width, "width")
defineLengthProperty(height, "height")
defineLengthProperty(inlineSize, "inline-size")
defineLengthProperty(blockSize, "block-size")
defineLengthProperty(minWidth, "min-width")
defineLengthProperty(maxWidth, "max-width")
defineLengthProperty(minHeight, "min-height")
defineLengthProperty(maxHeight, "max-height")
defineLengthProperty(minInlineSize, "min-inline-size")
defineLengthProperty(maxInlineSize, "max-inline-size")
defineLengthProperty(minBlockSize, "min-block-size")
defineLengthProperty(maxBlockSize, "max-block-size")

# Positioned offsets.
defineLengthProperty(inset, "inset")
defineLengthProperty(insetBlock, "inset-block")
defineLengthProperty(insetBlockStart, "inset-block-start")
defineLengthProperty(insetBlockEnd, "inset-block-end")
defineLengthProperty(insetInline, "inset-inline")
defineLengthProperty(insetInlineStart, "inset-inline-start")
defineLengthProperty(insetInlineEnd, "inset-inline-end")
defineLengthProperty(top, "top")
defineLengthProperty(right, "right")
defineLengthProperty(bottom, "bottom")
defineLengthProperty(left, "left")

# Margin, padding, and Flex spacing.
defineLengthProperty(margin, "margin")
defineLengthProperty(marginTop, "margin-top")
defineLengthProperty(marginRight, "margin-right")
defineLengthProperty(marginBottom, "margin-bottom")
defineLengthProperty(marginLeft, "margin-left")
defineLengthProperty(marginInline, "margin-inline")
defineLengthProperty(marginInlineStart, "margin-inline-start")
defineLengthProperty(marginInlineEnd, "margin-inline-end")
defineLengthProperty(marginBlock, "margin-block")
defineLengthProperty(marginBlockStart, "margin-block-start")
defineLengthProperty(marginBlockEnd, "margin-block-end")
defineLengthProperty(padding, "padding")
defineLengthProperty(paddingTop, "padding-top")
defineLengthProperty(paddingRight, "padding-right")
defineLengthProperty(paddingBottom, "padding-bottom")
defineLengthProperty(paddingLeft, "padding-left")
defineLengthProperty(paddingInline, "padding-inline")
defineLengthProperty(paddingInlineStart, "padding-inline-start")
defineLengthProperty(paddingInlineEnd, "padding-inline-end")
defineLengthProperty(paddingBlock, "padding-block")
defineLengthProperty(paddingBlockStart, "padding-block-start")
defineLengthProperty(paddingBlockEnd, "padding-block-end")
defineLengthProperty(gap, "gap")
defineLengthProperty(rowGap, "row-gap")
defineLengthProperty(columnGap, "column-gap")
defineLengthProperty(flexBasis, "flex-basis")

# Border dimensions.
defineLengthProperty(borderWidth, "border-width")
defineLengthProperty(borderTopWidth, "border-top-width")
defineLengthProperty(borderRightWidth, "border-right-width")
defineLengthProperty(borderBottomWidth, "border-bottom-width")
defineLengthProperty(borderLeftWidth, "border-left-width")
defineLengthProperty(borderInlineWidth, "border-inline-width")
defineLengthProperty(borderInlineStartWidth, "border-inline-start-width")
defineLengthProperty(borderInlineEndWidth, "border-inline-end-width")
defineLengthProperty(borderBlockWidth, "border-block-width")
defineLengthProperty(borderBlockStartWidth, "border-block-start-width")
defineLengthProperty(borderBlockEndWidth, "border-block-end-width")
defineLengthProperty(borderRadius, "border-radius")
defineLengthProperty(borderTopLeftRadius, "border-top-left-radius")
defineLengthProperty(borderTopRightRadius, "border-top-right-radius")
defineLengthProperty(borderBottomRightRadius, "border-bottom-right-radius")
defineLengthProperty(borderBottomLeftRadius, "border-bottom-left-radius")
defineLengthProperty(borderStartStartRadius, "border-start-start-radius")
defineLengthProperty(borderStartEndRadius, "border-start-end-radius")
defineLengthProperty(borderEndStartRadius, "border-end-start-radius")
defineLengthProperty(borderEndEndRadius, "border-end-end-radius")

# Text lengths and property-specific unitless values.
defineLengthProperty(fontSize, "font-size")

proc lineHeight*(value: StyleValue; sourceOrder = 0): Declaration {.inline.} =
  decl("line-height", value, sourceOrder)

defineNumberProperty(lineHeight, "line-height")
defineNumberProperty(opacity, "opacity")
defineNumberProperty(flexGrow, "flex-grow")
defineNumberProperty(flexShrink, "flex-shrink")
defineNumberProperty(fontWeight, "font-weight")
defineIntegerProperty(order, "order")
defineIntegerProperty(zIndex, "z-index")

proc display*(value: DisplayKind; sourceOrder = 0): Declaration =
  let authored = case value
    of dkFlex: "flex"
    of dkNone: "none"
  decl("display", keyword(authored), sourceOrder)

proc flexDirection*(value: FlexDirection; sourceOrder = 0): Declaration =
  let authored = case value
    of fdRow: "row"
    of fdColumn: "column"
  decl("flex-direction", keyword(authored), sourceOrder)

proc flexWrap*(value: FlexWrap; sourceOrder = 0): Declaration =
  let authored = case value
    of fwNoWrap: "nowrap"
    of fwWrap: "wrap"
    of fwWrapReverse: "wrap-reverse"
  decl("flex-wrap", keyword(authored), sourceOrder)

proc alignItems*(value: AlignItems; sourceOrder = 0): Declaration =
  let authored = case value
    of aiStart: "start"
    of aiCenter: "center"
    of aiEnd: "end"
    of aiStretch: "stretch"
  decl("align-items", keyword(authored), sourceOrder)

proc alignSelf*(value: AlignItems; sourceOrder = 0): Declaration =
  let authored = case value
    of aiStart: "start"
    of aiCenter: "center"
    of aiEnd: "end"
    of aiStretch: "stretch"
  decl("align-self", keyword(authored), sourceOrder)

proc contentAlignmentKeyword(value: JustifyContent): string =
  case value
  of jcStart: "start"
  of jcCenter: "center"
  of jcEnd: "end"
  of jcSpaceBetween: "space-between"

proc alignContent*(value: JustifyContent; sourceOrder = 0): Declaration =
  decl("align-content", keyword(value.contentAlignmentKeyword), sourceOrder)

proc justifyContent*(value: JustifyContent; sourceOrder = 0): Declaration =
  decl("justify-content", keyword(value.contentAlignmentKeyword), sourceOrder)

proc selfAlignmentKeyword(value: SelfAlignment): string =
  case value
  of saStart: "start"
  of saCenter: "center"
  of saEnd: "end"
  of saStretch: "stretch"

proc justifyItems*(value: SelfAlignment; sourceOrder = 0): Declaration =
  decl("justify-items", keyword(value.selfAlignmentKeyword), sourceOrder)

proc justifySelf*(value: SelfAlignment; sourceOrder = 0): Declaration =
  decl("justify-self", keyword(value.selfAlignmentKeyword), sourceOrder)

proc position*(value: PositionKind; sourceOrder = 0): Declaration =
  let authored = case value
    of pkStatic: "static"
    of pkRelative: "relative"
    of pkAbsolute: "absolute"
  decl("position", keyword(authored), sourceOrder)

proc boxSizing*(value: BoxSizing; sourceOrder = 0): Declaration =
  let authored = case value
    of bsContentBox: "content-box"
    of bsBorderBox: "border-box"
  decl("box-sizing", keyword(authored), sourceOrder)

proc overflowKeyword(value: OverflowMode): string =
  case value
  of omVisible: "visible"
  of omHidden: "hidden"
  of omClip: "clip"
  of omAuto: "auto"
  of omScroll: "scroll"

proc overflow*(value: OverflowMode; sourceOrder = 0): Declaration =
  decl("overflow", keyword(value.overflowKeyword), sourceOrder)

proc overflowX*(value: OverflowMode; sourceOrder = 0): Declaration =
  decl("overflow-x", keyword(value.overflowKeyword), sourceOrder)

proc overflowY*(value: OverflowMode; sourceOrder = 0): Declaration =
  decl("overflow-y", keyword(value.overflowKeyword), sourceOrder)

proc pointerEvents*(value: PointerEvents; sourceOrder = 0): Declaration =
  let authored = case value
    of peAuto: "auto"
    of peNone: "none"
  decl("pointer-events", keyword(authored), sourceOrder)

proc cursor*(value: CursorKind; sourceOrder = 0): Declaration =
  let authored = case value
    of ckAuto: "auto"
    of ckDefault: "default"
    of ckPointer: "pointer"
    of ckText: "text"
    of ckMove: "move"
    of ckNotAllowed: "not-allowed"
  decl("cursor", keyword(authored), sourceOrder)

proc userSelect*(value: UserSelect; sourceOrder = 0): Declaration =
  let authored = case value
    of usAuto: "auto"
    of usNone: "none"
    of usText: "text"
    of usAll: "all"
  decl("user-select", keyword(authored), sourceOrder)

proc resize*(value: ResizeKind; sourceOrder = 0): Declaration =
  let authored = case value
    of rkNone: "none"
    of rkBoth: "both"
    of rkHorizontal: "horizontal"
    of rkVertical: "vertical"
  decl("resize", keyword(authored), sourceOrder)

proc fontStyle*(value: FontStyle; sourceOrder = 0): Declaration =
  let authored = case value
    of fsNormal: "normal"
    of fsItalic: "italic"
    of fsOblique: "oblique"
  decl("font-style", keyword(authored), sourceOrder)

proc textAlign*(value: TextAlign; sourceOrder = 0): Declaration =
  let authored = case value
    of taStart: "start"
    of taLeft: "left"
    of taCenter: "center"
    of taRight: "right"
    of taEnd: "end"
  decl("text-align", keyword(authored), sourceOrder)
