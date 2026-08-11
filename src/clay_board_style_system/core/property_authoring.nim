import std/strutils
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

template defineClosedKeywordProperty(
    name: untyped;
    valueType: typedesc;
    propertyName: static[string]
) =
  proc name*(value: valueType; sourceOrder = 0): Declaration {.inline.} =
    decl(propertyName, keyword(closedKeyword(value)), sourceOrder)

proc closedKeyword(value: FontKerning): string =
  case value
  of fkAuto: "auto"
  of fkNormal: "normal"
  of fkNone: "none"

proc closedKeyword(value: FontOpticalSizing): string =
  case value
  of fosAuto: "auto"
  of fosNone: "none"

proc closedKeyword(value: TextAlign): string =
  case value
  of taStart: "start"
  of taLeft: "left"
  of taCenter: "center"
  of taRight: "right"
  of taEnd: "end"

proc closedKeyword(value: WhiteSpace): string =
  case value
  of wsNormal: "normal"
  of wsNoWrap: "nowrap"
  of wsPre: "pre"
  of wsPreWrap: "pre-wrap"
  of wsPreLine: "pre-line"
  of wsBreakSpaces: "break-spaces"

proc closedKeyword(value: TextOverflow): string =
  case value
  of toClip: "clip"
  of toEllipsis: "ellipsis"

proc closedKeyword(value: OverflowWrap): string =
  case value
  of owNormal: "normal"
  of owAnywhere: "anywhere"
  of owBreakWord: "break-word"

proc closedKeyword(value: WordBreak): string =
  case value
  of wbNormal: "normal"
  of wbBreakAll: "break-all"
  of wbKeepAll: "keep-all"
  of wbBreakWord: "break-word"

proc closedKeyword(value: Hyphens): string =
  case value
  of hyManual: "manual"
  of hyNone: "none"
  of hyAuto: "auto"

proc closedKeyword(value: TextDirection): string =
  case value
  of tdLtr: "ltr"
  of tdRtl: "rtl"

proc closedKeyword(value: UnicodeBidi): string =
  case value
  of ubNormal: "normal"
  of ubEmbed: "embed"
  of ubIsolate: "isolate"
  of ubBidiOverride: "bidi-override"
  of ubIsolateOverride: "isolate-override"
  of ubPlaintext: "plaintext"

proc closedKeyword(value: WritingMode): string =
  case value
  of wmHorizontalTb: "horizontal-tb"
  of wmVerticalRl: "vertical-rl"
  of wmVerticalLr: "vertical-lr"

proc closedKeyword(value: TextDecorationLine): string =
  case value
  of tdlNone: "none"
  of tdlUnderline: "underline"
  of tdlOverline: "overline"
  of tdlLineThrough: "line-through"

proc closedKeyword(value: TextDecorationStyle): string =
  case value
  of tdsSolid: "solid"
  of tdsDouble: "double"
  of tdsDotted: "dotted"
  of tdsDashed: "dashed"
  of tdsWavy: "wavy"

proc closedKeyword(value: TextTransform): string =
  case value
  of ttNone: "none"
  of ttUppercase: "uppercase"
  of ttLowercase: "lowercase"
  of ttCapitalize: "capitalize"

proc closedKeyword(value: TextWrap): string =
  case value
  of twWrap: "wrap"
  of twNoWrap: "nowrap"
  of twBalance: "balance"
  of twPretty: "pretty"
  of twStable: "stable"

proc closedKeyword(value: ObjectFit): string =
  case value
  of ofFill: "fill"
  of ofContain: "contain"
  of ofCover: "cover"
  of ofNone: "none"
  of ofScaleDown: "scale-down"

proc closedKeyword(value: ImageRendering): string =
  case value
  of irAuto: "auto"
  of irSmooth: "smooth"
  of irCrispEdges: "crisp-edges"
  of irPixelated: "pixelated"

proc closedKeyword(value: BackgroundRepeat): string =
  case value
  of bgRepeat: "repeat"
  of bgNoRepeat: "no-repeat"
  of bgRepeatX: "repeat-x"
  of bgRepeatY: "repeat-y"

proc closedKeyword(value: BackgroundBox): string =
  case value
  of bgBorderBox: "border-box"
  of bgPaddingBox: "padding-box"
  of bgContentBox: "content-box"

proc closedKeyword(value: BackgroundAttachment): string =
  case value
  of bgScroll: "scroll"
  of bgFixed: "fixed"
  of bgLocal: "local"

proc closedKeyword(value: BoxDecorationBreak): string =
  case value
  of bdbSlice: "slice"
  of bdbClone: "clone"

proc closedKeyword(value: BlendMode): string =
  case value
  of bmNormal: "normal"
  of bmMultiply: "multiply"
  of bmScreen: "screen"
  of bmOverlay: "overlay"
  of bmDarken: "darken"
  of bmLighten: "lighten"

proc closedKeyword(value: Isolation): string =
  case value
  of isoAuto: "auto"
  of isoIsolate: "isolate"

proc closedKeyword(value: ColorAdjust): string =
  case value
  of caAuto: "auto"
  of caNone: "none"

proc closedKeyword(value: PrintColorAdjust): string =
  case value
  of pcaEconomy: "economy"
  of pcaExact: "exact"

proc closedKeyword(value: TouchAction): string =
  case value
  of taAutoTouch: "auto"
  of taNoneTouch: "none"
  of taManipulation: "manipulation"
  of taPanX: "pan-x"
  of taPanY: "pan-y"
  of taPinchZoom: "pinch-zoom"

proc closedKeyword(value: ReadingFlow): string =
  case value
  of rfNormal: "normal"
  of rfFlexVisual: "flex-visual"
  of rfFlexFlow: "flex-flow"
  of rfGridRows: "grid-rows"
  of rfGridColumns: "grid-columns"
  of rfGridOrder: "grid-order"

proc closedKeyword(value: ScrollbarWidth): string =
  case value
  of swAuto: "auto"
  of swThin: "thin"
  of swNone: "none"

proc closedKeyword(value: ScrollbarVisibility): string =
  case value
  of svAlways: "always"
  of svScrolling: "scrolling"

proc closedKeyword(value: ScrollBehavior): string =
  case value
  of sbAuto: "auto"
  of sbSmooth: "smooth"

proc closedKeyword(value: OverscrollBehavior): string =
  case value
  of obAuto: "auto"
  of obContain: "contain"
  of obNone: "none"

proc closedKeyword(value: AnimationDirection): string =
  case value
  of adNormal: "normal"
  of adReverse: "reverse"
  of adAlternate: "alternate"
  of adAlternateReverse: "alternate-reverse"

proc closedKeyword(value: AnimationFillMode): string =
  case value
  of afNone: "none"
  of afForwards: "forwards"
  of afBackwards: "backwards"
  of afBoth: "both"

proc closedKeyword(value: AnimationPlayState): string =
  case value
  of apsRunning: "running"
  of apsPaused: "paused"

proc closedKeyword(value: AnimationComposition): string =
  case value
  of acReplace: "replace"
  of acAdd: "add"
  of acAccumulate: "accumulate"

proc closedKeyword(value: TransitionBehavior): string =
  case value
  of tbNormal: "normal"
  of tbAllowDiscrete: "allow-discrete"

proc closedKeyword(value: TransformBox): string =
  case value
  of tboxContentBox: "content-box"
  of tboxBorderBox: "border-box"
  of tboxFillBox: "fill-box"
  of tboxStrokeBox: "stroke-box"
  of tboxViewBox: "view-box"

proc closedKeyword(value: TransformStyle): string =
  case value
  of tsFlat: "flat"
  of tsPreserve3d: "preserve-3d"

defineClosedKeywordProperty(fontKerning, FontKerning, "font-kerning")
defineClosedKeywordProperty(
  fontOpticalSizing, FontOpticalSizing, "font-optical-sizing"
)
defineClosedKeywordProperty(textAlignLast, TextAlign, "text-align-last")
defineClosedKeywordProperty(whiteSpace, WhiteSpace, "white-space")
defineClosedKeywordProperty(textOverflow, TextOverflow, "text-overflow")
defineClosedKeywordProperty(overflowWrap, OverflowWrap, "overflow-wrap")
defineClosedKeywordProperty(wordWrap, OverflowWrap, "word-wrap")
defineClosedKeywordProperty(wordBreak, WordBreak, "word-break")
defineClosedKeywordProperty(hyphens, Hyphens, "hyphens")
defineClosedKeywordProperty(direction, TextDirection, "direction")
defineClosedKeywordProperty(unicodeBidi, UnicodeBidi, "unicode-bidi")
defineClosedKeywordProperty(writingMode, WritingMode, "writing-mode")
defineClosedKeywordProperty(
  textDecorationLine, TextDecorationLine, "text-decoration-line"
)
defineClosedKeywordProperty(
  textDecorationStyle, TextDecorationStyle, "text-decoration-style"
)
defineClosedKeywordProperty(textTransform, TextTransform, "text-transform")
defineClosedKeywordProperty(textWrap, TextWrap, "text-wrap")
defineClosedKeywordProperty(objectFit, ObjectFit, "object-fit")
defineClosedKeywordProperty(imageRendering, ImageRendering, "image-rendering")
defineClosedKeywordProperty(
  backgroundRepeat, BackgroundRepeat, "background-repeat"
)
defineClosedKeywordProperty(
  backgroundOrigin, BackgroundBox, "background-origin"
)
defineClosedKeywordProperty(backgroundClip, BackgroundBox, "background-clip")
defineClosedKeywordProperty(
  backgroundAttachment, BackgroundAttachment, "background-attachment"
)
defineClosedKeywordProperty(
  backgroundBlendMode, BlendMode, "background-blend-mode"
)
defineClosedKeywordProperty(
  boxDecorationBreak, BoxDecorationBreak, "box-decoration-break"
)
defineClosedKeywordProperty(mixBlendMode, BlendMode, "mix-blend-mode")
defineClosedKeywordProperty(isolation, Isolation, "isolation")
defineClosedKeywordProperty(
  forcedColorAdjust, ColorAdjust, "forced-color-adjust"
)
defineClosedKeywordProperty(
  printColorAdjust, PrintColorAdjust, "print-color-adjust"
)
defineClosedKeywordProperty(touchAction, TouchAction, "touch-action")
defineClosedKeywordProperty(readingFlow, ReadingFlow, "reading-flow")
defineClosedKeywordProperty(scrollbarWidth, ScrollbarWidth, "scrollbar-width")
defineClosedKeywordProperty(
  scrollbarVisibility, ScrollbarVisibility, "scrollbar-visibility"
)
defineClosedKeywordProperty(scrollBehavior, ScrollBehavior, "scroll-behavior")
defineClosedKeywordProperty(
  overscrollBehavior, OverscrollBehavior, "overscroll-behavior"
)
defineClosedKeywordProperty(
  overscrollBehaviorX, OverscrollBehavior, "overscroll-behavior-x"
)
defineClosedKeywordProperty(
  overscrollBehaviorY, OverscrollBehavior, "overscroll-behavior-y"
)
defineClosedKeywordProperty(
  overscrollBehaviorBlock, OverscrollBehavior, "overscroll-behavior-block"
)
defineClosedKeywordProperty(
  overscrollBehaviorInline, OverscrollBehavior, "overscroll-behavior-inline"
)
defineClosedKeywordProperty(
  animationDirection, AnimationDirection, "animation-direction"
)
defineClosedKeywordProperty(
  animationFillMode, AnimationFillMode, "animation-fill-mode"
)
defineClosedKeywordProperty(
  animationPlayState, AnimationPlayState, "animation-play-state"
)
defineClosedKeywordProperty(
  animationComposition, AnimationComposition, "animation-composition"
)
defineClosedKeywordProperty(
  transitionBehavior, TransitionBehavior, "transition-behavior"
)

proc animationNames*(values: varargs[string]): Declaration =
  decl("animation-name", keyword((@values).join(", ")))

proc animationDurations*(values: varargs[float32]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add $value
  decl("animation-duration", keyword(authored.join(", ")))

proc animationDelays*(values: varargs[float32]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add $value
  decl("animation-delay", keyword(authored.join(", ")))

proc animationTimingFunctions*(values: varargs[string]): Declaration =
  decl("animation-timing-function", keyword((@values).join(", ")))

proc animationIterationCounts*(values: varargs[float32]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add $value
  decl("animation-iteration-count", keyword(authored.join(", ")))

proc animationDirections*(values: varargs[AnimationDirection]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add closedKeyword(value)
  decl("animation-direction", keyword(authored.join(", ")))

proc animationFillModes*(values: varargs[AnimationFillMode]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add closedKeyword(value)
  decl("animation-fill-mode", keyword(authored.join(", ")))

proc animationPlayStates*(values: varargs[AnimationPlayState]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add closedKeyword(value)
  decl("animation-play-state", keyword(authored.join(", ")))

proc animationCompositions*(values: varargs[AnimationComposition]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add closedKeyword(value)
  decl("animation-composition", keyword(authored.join(", ")))

proc transitionProperties*(values: varargs[string]): Declaration =
  decl("transition-property", keyword((@values).join(", ")))

proc transitionDurations*(values: varargs[float32]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add $value
  decl("transition-duration", keyword(authored.join(", ")))

proc transitionDelays*(values: varargs[float32]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add $value
  decl("transition-delay", keyword(authored.join(", ")))

proc transitionTimingFunctions*(values: varargs[string]): Declaration =
  decl("transition-timing-function", keyword((@values).join(", ")))

proc transitionBehaviors*(values: varargs[TransitionBehavior]): Declaration =
  var authored: seq[string]
  for value in values:
    authored.add closedKeyword(value)
  decl("transition-behavior", keyword(authored.join(", ")))

defineClosedKeywordProperty(transformBox, TransformBox, "transform-box")
defineClosedKeywordProperty(transformStyle, TransformStyle, "transform-style")
