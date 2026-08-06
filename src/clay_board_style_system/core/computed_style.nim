import std/options
import ./[color, color_conversion, style_value]

type
  DisplayKind* = enum
    dkFlex,
    dkNone

  FlexDirection* = enum
    fdRow,
    fdColumn

  FlexWrap* = enum
    fwNoWrap,
    fwWrap,
    fwWrapReverse

  AlignItems* = enum
    aiStart,
    aiCenter,
    aiEnd,
    aiStretch

  JustifyContent* = enum
    jcStart,
    jcCenter,
    jcEnd,
    jcSpaceBetween

  SelfAlignment* = enum
    saStart,
    saCenter,
    saEnd,
    saStretch

  FontStyle* = enum
    fsNormal,
    fsItalic,
    fsOblique

  FontKerning* = enum
    fkAuto,
    fkNormal,
    fkNone

  FontOpticalSizing* = enum
    fosAuto,
    fosNone

  TextAlign* = enum
    taStart,
    taLeft,
    taCenter,
    taRight,
    taEnd

  WhiteSpace* = enum
    wsNormal,
    wsNoWrap,
    wsPre,
    wsPreWrap,
    wsPreLine,
    wsBreakSpaces

  TextOverflow* = enum
    toClip,
    toEllipsis

  OverflowWrap* = enum
    owNormal,
    owAnywhere,
    owBreakWord

  WordBreak* = enum
    wbNormal,
    wbBreakAll,
    wbKeepAll,
    wbBreakWord

  Hyphens* = enum
    hyManual,
    hyNone,
    hyAuto

  TextDirection* = enum
    tdLtr,
    tdRtl

  UnicodeBidi* = enum
    ubNormal,
    ubEmbed,
    ubIsolate,
    ubBidiOverride,
    ubIsolateOverride,
    ubPlaintext

  WritingMode* = enum
    wmHorizontalTb,
    wmVerticalRl,
    wmVerticalLr

  TextDecorationLine* = enum
    tdlNone,
    tdlUnderline,
    tdlOverline,
    tdlLineThrough

  TextDecorationStyle* = enum
    tdsSolid,
    tdsDouble,
    tdsDotted,
    tdsDashed,
    tdsWavy

  TextTransform* = enum
    ttNone,
    ttUppercase,
    ttLowercase,
    ttCapitalize

  TextWrap* = enum
    twWrap,
    twNoWrap,
    twBalance,
    twPretty,
    twStable

  ObjectFit* = enum
    ofFill,
    ofContain,
    ofCover,
    ofNone,
    ofScaleDown

  ObjectPosition* = object
    x*, y*: float32

  ImageRendering* = enum
    irAuto,
    irSmooth,
    irCrispEdges,
    irPixelated

  BoxSizing* = enum
    bsContentBox,
    bsBorderBox

  OverflowMode* = enum
    omVisible,
    omHidden,
    omClip,
    omAuto,
    omScroll

  ComputedSizingStyle* = object
    ## Non-pixel sizing stays cold. The common fixed-pixel path continues to
    ## use ComputedLayoutStyle's compact Option[float32] fields.
    width*, height*: Option[LengthValue]
    minWidth*, maxWidth*: Option[LengthValue]
    minHeight*, maxHeight*: Option[LengthValue]
    gap*, rowGap*, columnGap*: Option[LengthValue]
    flexBasis*: Option[LengthValue]
    insetTop*, insetRight*, insetBottom*, insetLeft*: Option[LengthValue]
    paddingTop*, paddingRight*, paddingBottom*, paddingLeft*: Option[LengthValue]
    marginTop*, marginRight*, marginBottom*, marginLeft*: Option[LengthValue]

  PointerEvents* = enum
    peAuto,
    peNone

  CursorKind* = enum
    ckAuto,
    ckDefault,
    ckPointer,
    ckText,
    ckMove,
    ckNotAllowed

  UserSelect* = enum
    usAuto,
    usNone,
    usText,
    usAll

  ResizeKind* = enum
    rkNone,
    rkBoth,
    rkHorizontal,
    rkVertical

  BackgroundSizeKind* = enum
    bgSizeAuto,
    bgSizeCover,
    bgSizeContain,
    bgSizeLength

  BackgroundSize* = object
    kind*: BackgroundSizeKind
    width*, height*: Option[float32]

  LinearGradient* = object
    angle*: float32
    interpolationSpace*: ColorInterpolationSpace
    stops*: seq[GradientStop]

  BackgroundRepeat* = enum
    bgRepeat,
    bgNoRepeat,
    bgRepeatX,
    bgRepeatY

  BackgroundBox* = enum
    bgBorderBox,
    bgPaddingBox,
    bgContentBox

  BackgroundAttachment* = enum
    bgScroll,
    bgFixed,
    bgLocal

  BoxDecorationBreak* = enum
    bdbSlice,
    bdbClone

  BlendMode* = enum
    bmNormal,
    bmMultiply,
    bmScreen,
    bmOverlay,
    bmDarken,
    bmLighten

  Isolation* = enum
    isoAuto,
    isoIsolate

  ColorAdjust* = enum
    caAuto,
    caNone

  PrintColorAdjust* = enum
    pcaEconomy,
    pcaExact

  TouchAction* = enum
    taAutoTouch,
    taNoneTouch,
    taManipulation,
    taPanX,
    taPanY,
    taPinchZoom

  ReadingFlow* = enum
    rfNormal,
    rfFlexVisual,
    rfFlexFlow,
    rfGridRows,
    rfGridColumns,
    rfGridOrder

  ScrollbarWidth* = enum
    swAuto,
    swThin,
    swNone

  ScrollbarVisibility* = enum
    ## CBSS extension: `scrolling` paints scrollbars only while their
    ## container is actively being scrolled (overlay indicator behavior).
    svAlways,
    svScrolling

  ScrollBehavior* = enum
    sbAuto,
    sbSmooth

  OverscrollBehavior* = enum
    obAuto,
    obContain,
    obNone

  AnimationDirection* = enum
    adNormal,
    adReverse,
    adAlternate,
    adAlternateReverse

  AnimationFillMode* = enum
    afNone,
    afForwards,
    afBackwards,
    afBoth

  AnimationPlayState* = enum
    apsRunning,
    apsPaused

  AnimationComposition* = enum
    acReplace,
    acAdd,
    acAccumulate

  TransitionBehavior* = enum
    tbNormal,
    tbAllowDiscrete

  TransformOperationKind* = enum
    ctkTranslate,
    ctkScale,
    ctkRotate

  ComputedUnitKind* = enum
    cukPx,
    cukPercent,
    cukEm,
    cukRem,
    cukFill,
    cukContent,
    cukMinContent,
    cukMaxContent,
    cukFitContent,
    cukAuto,
    cukNone,
    cukVw,
    cukVh,
    cukVmin,
    cukVmax,
    cukLh,
    cukRlh,
    cukEx,
    cukCh,
    cukRex,
    cukRch

  ComputedLength* = object
    kind*: ComputedUnitKind
    value*: float32

  TransformOperation* = object
    kind*: TransformOperationKind
    xLength*, yLength*, zLength*: Option[ComputedLength]
    xNumber*, yNumber*, zNumber*: Option[float32]
    angle*: float32

  TransformBox* = enum
    tboxContentBox,
    tboxBorderBox,
    tboxFillBox,
    tboxStrokeBox,
    tboxViewBox

  TransformStyle* = enum
    tsFlat,
    tsPreserve3d

  ComputedTransformStyle* = object
    rawTransform*: Option[string]
    operations*: seq[TransformOperation]
    originX*, originY*: ComputedLength
    originZ*: float32
    transformBox*: TransformBox
    transformStyle*: TransformStyle
    backfaceVisible*: bool
    perspective*: Option[ComputedLength]
    perspectiveOriginX*, perspectiveOriginY*: ComputedLength
    rotate*: Option[float32]
    scaleX*, scaleY*, scaleZ*: Option[float32]
    translateX*, translateY*, translateZ*: Option[ComputedLength]

  ComputedAnimationStyle* = object
    rawAnimation*: Option[string]
    animationName*: Option[string]
    animationDuration*: float32
    animationDelay*: float32
    animationTimingFunction*: Option[string]
    animationIterationCount*: Option[float32]
    animationDirection*: AnimationDirection
    animationFillMode*: AnimationFillMode
    animationPlayState*: AnimationPlayState
    animationComposition*: AnimationComposition
    animationRange*: Option[string]
    animationRangeStart*: Option[string]
    animationRangeEnd*: Option[string]
    animationTimeline*: Option[string]
    animationTrigger*: Option[string]
    timelineTrigger*: Option[string]
    timelineTriggerActivationRange*: Option[string]
    timelineTriggerActivationRangeEnd*: Option[string]
    timelineTriggerActivationRangeStart*: Option[string]
    timelineTriggerActiveRange*: Option[string]
    timelineTriggerActiveRangeEnd*: Option[string]
    timelineTriggerActiveRangeStart*: Option[string]
    timelineTriggerName*: Option[string]
    timelineTriggerSource*: Option[string]
    triggerScope*: Option[string]
    rawTransition*: Option[string]
    transitionProperty*: Option[string]
    transitionDuration*: float32
    transitionDelay*: float32
    transitionTimingFunction*: Option[string]
    transitionBehavior*: TransitionBehavior

  BoxShadow* = object
    offsetX*, offsetY*: float32
    blur*, spread*: float32
    color*: Option[Color]

  PositionKind* = enum
    pkStatic,
    pkRelative,
    pkAbsolute

  EdgeSizes* = object
    top*, right*, bottom*, left*: float32

  EdgeColors* = object
    top*, right*, bottom*, left*: Option[Color]

  EdgeVisibility* = object
    top*, right*, bottom*, left*: bool

  CornerSizes* = object
    topLeft*, topRight*, bottomRight*, bottomLeft*: float32

  Insets* = object
    top*, right*, bottom*, left*: Option[float32]

  ComputedLayoutStyle* = object
    display*: DisplayKind
    direction*: FlexDirection
    flexGrow*: float32
    flexShrink*: float32
    flexBasis*: Option[float32]
    flexWrap*: FlexWrap
    order*: int
    alignTracks*: Option[string]
    alignItems*: AlignItems
    alignSelf*: Option[AlignItems]
    alignContent*: JustifyContent
    justifyContent*: JustifyContent
    justifyTracks*: Option[string]
    justifyItems*: Option[SelfAlignment]
    justifySelf*: Option[SelfAlignment]
    position*: PositionKind
    inset*: Insets
    zIndex*: int
    width*: Option[float32]
    height*: Option[float32]
    minWidth*: Option[float32]
    maxWidth*: Option[float32]
    minHeight*: Option[float32]
    maxHeight*: Option[float32]
    sizing*: ref ComputedSizingStyle
    aspectRatio*: Option[float32]
    boxSizing*: BoxSizing
    gap*: float32
    rowGap*: Option[float32]
    columnGap*: Option[float32]
    overflowX*: OverflowMode
    overflowY*: OverflowMode
    marginTrim*: Option[string]
    legacyBoxAlign*: Option[string]
    legacyBoxDirection*: Option[string]
    legacyBoxFlex*: Option[string]
    legacyBoxFlexGroup*: Option[string]
    legacyBoxLines*: Option[string]
    legacyBoxOrdinalGroup*: Option[string]
    legacyBoxOrient*: Option[string]
    legacyBoxPack*: Option[string]

  ComputedBoxStyle* = object
    padding*: Option[EdgeSizes]
    margin*: Option[EdgeSizes]
    backgroundColor*: Option[Color]
    backgroundImage*: Option[string]
    backgroundGradient*: Option[LinearGradient]
    backgroundSize*: Option[BackgroundSize]
    backgroundPosition*: ObjectPosition
    backgroundRepeat*: BackgroundRepeat
    backgroundClip*: BackgroundBox
    backgroundOrigin*: BackgroundBox
    backgroundAttachment*: BackgroundAttachment
    backgroundBlendMode*: BlendMode
    boxDecorationBreak*: BoxDecorationBreak
    boxShadow*: Option[BoxShadow]
    outlineColor*: Option[Color]
    outlineWidth*: float32
    outlineOffset*: float32
    outlineVisible*: bool
    borderColor*: Option[Color]
    borderColors*: EdgeColors
    borderWidth*: float32
    borderWidths*: EdgeSizes
    borderRadius*: float32
    borderRadii*: CornerSizes
    borderVisible*: bool
    borderSideVisible*: EdgeVisibility
    borderImage*: Option[string]
    borderImageOutset*: Option[string]
    borderImageRepeat*: Option[string]
    borderImageSlice*: Option[string]
    borderImageSource*: Option[string]
    borderImageWidth*: Option[string]
    borderCollapse*: Option[string]
    borderShape*: Option[string]
    borderSpacing*: Option[string]
    cornerShape*: Option[string]
    cornerTopShape*: Option[string]
    cornerRightShape*: Option[string]
    cornerBottomShape*: Option[string]
    cornerLeftShape*: Option[string]
    cornerTopLeftShape*: Option[string]
    cornerTopRightShape*: Option[string]
    cornerBottomRightShape*: Option[string]
    cornerBottomLeftShape*: Option[string]
    cornerBlockStartShape*: Option[string]
    cornerBlockEndShape*: Option[string]
    cornerInlineStartShape*: Option[string]
    cornerInlineEndShape*: Option[string]
    cornerStartStartShape*: Option[string]
    cornerStartEndShape*: Option[string]
    cornerEndStartShape*: Option[string]
    cornerEndEndShape*: Option[string]

  ComputedTextStyle* = object
    color*: Option[Color]
    rawFont*: Option[string]
    fontSize*: Option[float32]
    fontFamily*: Option[string]
    fontFamilies*: seq[string]
    fontStyle*: Option[FontStyle]
    fontWeight*: Option[float32]
    fontStretch*: Option[float32]
    fontFeatureSettings*: Option[string]
    fontVariationSettings*: Option[string]
    fontKerning*: Option[FontKerning]
    fontOpticalSizing*: Option[FontOpticalSizing]
    fontSizeAdjust*: Option[float32]
    fontVariant*: Option[string]
    fontVariantLigatures*: Option[string]
    fontVariantCaps*: Option[string]
    fontVariantNumeric*: Option[string]
    fontVariantEastAsian*: Option[string]
    fontVariantPosition*: Option[string]
    fontVariantAlternates*: Option[string]
    fontVariantEmoji*: Option[string]
    fontLanguageOverride*: Option[string]
    fontPalette*: Option[string]
    fontSynthesis*: Option[string]
    fontSynthesisPosition*: Option[string]
    fontSynthesisSmallCaps*: Option[string]
    fontSynthesisStyle*: Option[string]
    fontSynthesisWeight*: Option[string]
    fontSmooth*: Option[string]
    fontWidth*: Option[float32]
    lineHeight*: Option[float32]
    textAlign*: Option[TextAlign]
    textAlignLast*: Option[TextAlign]
    alignmentBaseline*: Option[string]
    baselineShift*: Option[string]
    baselineSource*: Option[string]
    dominantBaseline*: Option[string]
    whiteSpace*: Option[WhiteSpace]
    maxLines*: Option[string]
    rubyMerge*: Option[string]
    textOverflow*: Option[TextOverflow]
    overflowWrap*: Option[OverflowWrap]
    wordBreak*: Option[WordBreak]
    hyphens*: Option[Hyphens]
    letterSpacing*: Option[float32]
    wordSpacing*: Option[float32]
    textDecorationLine*: Option[TextDecorationLine]
    textDecorationColor*: Option[Color]
    textDecorationStyle*: Option[TextDecorationStyle]
    textDecorationThickness*: Option[float32]
    textDecorationInset*: Option[float32]
    textDecorationSkip*: Option[string]
    textDecorationSkipInk*: Option[string]
    textShadow*: Option[BoxShadow]
    textTransform*: Option[TextTransform]
    textIndent*: Option[float32]
    textWrap*: Option[TextWrap]
    textAnchor*: Option[string]
    textAutospace*: Option[string]
    textBox*: Option[string]
    textBoxEdge*: Option[string]
    textBoxTrim*: Option[string]
    textCombineUpright*: Option[string]
    textEmphasis*: Option[string]
    textEmphasisColor*: Option[Color]
    textEmphasisPosition*: Option[string]
    textEmphasisStyle*: Option[string]
    textJustify*: Option[string]
    textOrientation*: Option[string]
    textRendering*: Option[string]
    textSizeAdjust*: Option[float32]
    textSpacingTrim*: Option[string]
    textUnderlineOffset*: Option[float32]
    textUnderlinePosition*: Option[string]
    direction*: Option[TextDirection]
    unicodeBidi*: Option[UnicodeBidi]
    writingMode*: Option[WritingMode]
    whiteSpaceCollapse*: Option[string]
    verticalAlign*: Option[string]
    tabSize*: Option[float32]
    hangingPunctuation*: Option[string]
    hyphenateCharacter*: Option[string]
    hyphenateLimitChars*: Option[string]
    initialLetter*: Option[string]
    initialLetterAlign*: Option[string]

  ComputedVisualStyle* = object
    visible*: bool
    opacity*: float32
    appearance*: Option[string]
    contentVisibility*: Option[string]
    pointerEvents*: PointerEvents
    cursor*: Option[CursorKind]
    userSelect*: Option[UserSelect]
    caretColor*: Option[Color]
    caret*: Option[string]
    caretAnimation*: Option[string]
    caretShape*: Option[string]
    accentColor*: Option[Color]
    resize*: ResizeKind
    filter*: Option[string]
    backdropFilter*: Option[string]
    mixBlendMode*: BlendMode
    isolation*: Isolation
    colorScheme*: Option[string]
    dynamicRangeLimit*: Option[string]
    fieldSizing*: Option[string]
    interactivity*: Option[string]
    interpolateSize*: Option[string]
    overlay*: Option[string]
    forcedColorAdjust*: ColorAdjust
    printColorAdjust*: PrintColorAdjust
    willChange*: Option[string]
    scrollbarWidth*: ScrollbarWidth
    scrollbarVisibility*: ScrollbarVisibility
    scrollbarThumbColor*: Option[Color]
    scrollbarTrackColor*: Option[Color]
    scrollbarGutter*: Option[string]
    scrollBehavior*: ScrollBehavior
    overscrollBehaviorX*: OverscrollBehavior
    overscrollBehaviorY*: OverscrollBehavior
    overscrollBehaviorBlock*: OverscrollBehavior
    overscrollBehaviorInline*: OverscrollBehavior
    overflowAnchor*: bool
    overflowClipMargin*: Option[float32]
    overflowBlock*: Option[string]
    overflowClipBox*: Option[string]
    overflowInline*: Option[string]
    clipPath*: Option[string]
    clipRule*: Option[string]
    interestDelay*: Option[string]
    interestDelayEnd*: Option[string]
    interestDelayStart*: Option[string]
    scrollInitialTarget*: Option[string]
    scrollMarkerGroup*: Option[string]
    scrollTargetGroup*: Option[string]
    viewTransitionScope*: Option[string]
    zoom*: Option[string]
    touchAction*: TouchAction
    readingFlow*: ReadingFlow
    readingOrder*: int

  ComputedImageStyle* = object
    objectFit*: Option[ObjectFit]
    objectPosition*: Option[ObjectPosition]
    imageRendering*: ImageRendering
    imageOrientation*: Option[string]
    imageResolution*: Option[string]
    objectViewBox*: Option[string]

  ComputedColumnsStyle* = object
    columnCount*: Option[int]
    columnFill*: Option[string]
    columnHeight*: Option[float32]
    columnRule*: Option[string]
    columnRuleColor*: Option[Color]
    columnRuleStyle*: Option[string]
    columnRuleWidth*: Option[float32]
    columnSpan*: Option[string]
    columnWidth*: Option[float32]
    columnWrap*: Option[string]
    columns*: Option[string]

  ComputedMaskStyle* = object
    mask*: Option[string]
    maskBorder*: Option[string]
    maskBorderMode*: Option[string]
    maskBorderOutset*: Option[string]
    maskBorderRepeat*: Option[string]
    maskBorderSlice*: Option[string]
    maskBorderSource*: Option[string]
    maskBorderWidth*: Option[string]
    maskClip*: Option[string]
    maskComposite*: Option[string]
    maskImage*: Option[string]
    maskMode*: Option[string]
    maskOrigin*: Option[string]
    maskPosition*: Option[string]
    maskRepeat*: Option[string]
    maskSize*: Option[string]
    maskType*: Option[string]

  ComputedVectorStyle* = object
    colorInterpolationFilters*: Option[string]
    fill*: Option[string]
    fillColor*: Option[Color]
    fillOpacity*: Option[float32]
    fillRule*: Option[string]
    floodColor*: Option[Color]
    floodOpacity*: Option[float32]
    lightingColor*: Option[Color]
    marker*: Option[string]
    paintOrder*: Option[string]
    stopColor*: Option[Color]
    stopOpacity*: Option[float32]
    stroke*: Option[string]
    strokeColor*: Option[Color]
    strokeDasharray*: Option[string]
    strokeDashoffset*: Option[float32]
    strokeLinecap*: Option[string]
    strokeLinejoin*: Option[string]
    strokeMiterlimit*: Option[float32]
    strokeOpacity*: Option[float32]
    strokeWidth*: Option[float32]
    vectorEffect*: Option[string]
    x*: Option[float32]
    y*: Option[float32]
    cx*: Option[float32]
    cy*: Option[float32]
    d*: Option[string]
    r*: Option[float32]
    rx*: Option[float32]
    ry*: Option[float32]

  ComputedStyle* = object
    layout*: ComputedLayoutStyle
    box*: ComputedBoxStyle
    text*: ComputedTextStyle
    visual*: ComputedVisualStyle
    image*: ComputedImageStyle
    columns*: ref ComputedColumnsStyle
    mask*: ref ComputedMaskStyle
    vector*: ref ComputedVectorStyle
    animationCold: ref ComputedAnimationStyle
    transformCold: ref ComputedTransformStyle

proc initialComputedAnimationStyle*(): ComputedAnimationStyle =
  result.animationDuration = 0
  result.animationDelay = 0
  result.animationTimingFunction = some("ease")
  result.animationIterationCount = some(1.0'f32)
  result.animationDirection = adNormal
  result.animationFillMode = afNone
  result.animationPlayState = apsRunning
  result.animationComposition = acReplace
  result.transitionProperty = some("all")
  result.transitionDuration = 0
  result.transitionDelay = 0
  result.transitionTimingFunction = some("ease")
  result.transitionBehavior = tbNormal

proc initialComputedTransformStyle*(): ComputedTransformStyle =
  result.originX = ComputedLength(kind: cukPercent, value: 50)
  result.originY = ComputedLength(kind: cukPercent, value: 50)
  result.originZ = 0
  result.transformBox = tboxBorderBox
  result.transformStyle = tsFlat
  result.backfaceVisible = true
  result.perspectiveOriginX = ComputedLength(kind: cukPercent, value: 50)
  result.perspectiveOriginY = ComputedLength(kind: cukPercent, value: 50)

proc animation*(style: ComputedStyle): ComputedAnimationStyle =
  ## Animation metadata is absent on ordinary nodes. Returning its initial
  ## value preserves the public computed-style view without retaining 376
  ## bytes per node.
  if style.animationCold.isNil:
    initialComputedAnimationStyle()
  else:
    style.animationCold[]

proc animation*(style: var ComputedStyle): var ComputedAnimationStyle =
  if style.animationCold.isNil:
    new(style.animationCold)
    style.animationCold[] = initialComputedAnimationStyle()
  style.animationCold[]

proc transform*(style: ComputedStyle): ComputedTransformStyle =
  if style.transformCold.isNil:
    initialComputedTransformStyle()
  else:
    style.transformCold[]

proc transform*(style: var ComputedStyle): var ComputedTransformStyle =
  if style.transformCold.isNil:
    new(style.transformCold)
    style.transformCold[] = initialComputedTransformStyle()
  style.transformCold[]

proc hasAnimationStyle*(style: ComputedStyle): bool =
  not style.animationCold.isNil

proc hasTransformStyle*(style: ComputedStyle): bool =
  not style.transformCold.isNil

proc ensureSizing*(style: var ComputedStyle) =
  if style.layout.sizing.isNil:
    new(style.layout.sizing)

proc ensureColumns*(style: var ComputedStyle) =
  if style.columns.isNil:
    new(style.columns)

proc ensureMask*(style: var ComputedStyle) =
  if style.mask.isNil:
    new(style.mask)

proc ensureVector*(style: var ComputedStyle) =
  if style.vector.isNil:
    new(style.vector)

proc initialComputedStyle*(): ComputedStyle =
  result.layout.display = dkFlex
  result.layout.direction = fdColumn
  result.layout.flexGrow = 0
  result.layout.flexShrink = 1
  result.layout.flexWrap = fwNoWrap
  result.layout.order = 0
  result.layout.alignItems = aiStart
  result.layout.alignContent = jcStart
  result.layout.justifyContent = jcStart
  result.layout.position = pkStatic
  result.layout.boxSizing = bsContentBox
  result.layout.gap = 0
  result.layout.overflowX = omVisible
  result.layout.overflowY = omVisible
  result.box.backgroundPosition = ObjectPosition(x: 0, y: 0)
  result.box.backgroundRepeat = bgRepeat
  result.box.backgroundClip = bgBorderBox
  result.box.backgroundOrigin = bgPaddingBox
  result.box.backgroundAttachment = bgScroll
  result.box.backgroundBlendMode = bmNormal
  result.box.boxDecorationBreak = bdbSlice
  result.box.outlineVisible = true
  result.box.borderWidth = 0
  result.box.borderWidths = EdgeSizes()
  result.box.borderRadius = 0
  result.box.borderRadii = CornerSizes()
  result.box.borderVisible = true
  result.box.borderSideVisible = EdgeVisibility(top: true, right: true, bottom: true, left: true)
  result.visual.visible = true
  result.visual.opacity = 1.0'f32
  result.visual.pointerEvents = peAuto
  result.visual.resize = rkNone
  result.visual.mixBlendMode = bmNormal
  result.visual.isolation = isoAuto
  result.visual.forcedColorAdjust = caAuto
  result.visual.printColorAdjust = pcaEconomy
  result.visual.scrollbarWidth = swAuto
  result.visual.scrollbarVisibility = svAlways
  result.visual.scrollBehavior = sbAuto
  result.visual.overscrollBehaviorX = obAuto
  result.visual.overscrollBehaviorY = obAuto
  result.visual.overscrollBehaviorBlock = obAuto
  result.visual.overscrollBehaviorInline = obAuto
  result.visual.overflowAnchor = true
  result.visual.touchAction = taAutoTouch
  result.visual.readingFlow = rfNormal
  result.visual.readingOrder = 0
  result.image.imageRendering = irAuto

proc edges*(all: float32): EdgeSizes =
  EdgeSizes(top: all, right: all, bottom: all, left: all)

proc edges*(vertical, horizontal: float32): EdgeSizes =
  EdgeSizes(top: vertical, right: horizontal, bottom: vertical, left: horizontal)

proc edges*(top, right, bottom, left: float32): EdgeSizes =
  EdgeSizes(top: top, right: right, bottom: bottom, left: left)

proc edgeColors*(color: Option[Color]): EdgeColors =
  EdgeColors(top: color, right: color, bottom: color, left: color)

proc edgeVisibility*(visible: bool): EdgeVisibility =
  EdgeVisibility(top: visible, right: visible, bottom: visible, left: visible)

proc corners*(all: float32): CornerSizes =
  CornerSizes(topLeft: all, topRight: all, bottomRight: all, bottomLeft: all)
