import ./[declaration, style_value]

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
