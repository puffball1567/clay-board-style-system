import std/[options, strutils]
import ../core/[computed_style, geometry, property]
import ./[font_registry, text_engine]

const cosmicTextBridgeLib* = "libcbss_cosmic_text_bridge.so"

type
  CosmicTextEngine* = object
    handle*: pointer

  TextMeasureCacheEntry = object
    key: string
    value: Size

  TextCaretCacheEntry = object
    key: string
    value: TextCaretResult

  TextFontMetricsCacheEntry = object
    key: string
    value: FontUnitMetrics

  TextBaselineMetricsCacheEntry = object
    key: string
    value: TextBaselineMetrics

  CosmicTextMeasureInput {.bycopy.} = object
    text: cstring
    familyCsv: cstring
    fontFeatures: cstring
    fontVariations: cstring
    fontSize: cfloat
    lineHeight: cfloat
    maxWidth: cfloat
    hasMaxWidth: uint8
    fontWeight: cfloat
    fontStyle: uint32
    fontStretch: cfloat
    letterSpacing: cfloat
    wordSpacing: cfloat
    wrap: uint32

  CosmicTextMeasureResult {.bycopy.} = object
    width: cfloat
    height: cfloat
    ok: uint8

  CosmicTextFontMetricsResult {.bycopy.} = object
    xHeight: cfloat
    zeroAdvance: cfloat
    ok: uint8

  CosmicTextBaselineMetricsResult {.bycopy.} = object
    ascent: cfloat
    descent: cfloat
    ok: uint8

  CosmicTextBitmapResult {.bycopy.} = object
    width*: uint32
    height*: uint32
    offsetX*: int32
    offsetY*: int32
    len*: csize_t
    pixels*: ptr UncheckedArray[uint8]
    ok*: uint8

  CosmicTextCaretQuery {.bycopy.} = object
    byteIndex: csize_t

  CosmicTextPointQuery {.bycopy.} = object
    x: cfloat
    y: cfloat

  CosmicTextCaretResult {.bycopy.} = object
    x: cfloat
    y: cfloat
    height: cfloat
    byteIndex: csize_t
    ok: uint8

  CosmicTextCaretSample {.bycopy.} = object
    x: cfloat
    y: cfloat
    height: cfloat
    byteIndex: csize_t

  CosmicTextCaretLayoutResult {.bycopy.} = object
    len: csize_t
    samples: ptr UncheckedArray[CosmicTextCaretSample]
    ok: uint8

  CosmicTextBitmap* = object
    width*, height*: int
    offsetX*, offsetY*: int
    pixels*: seq[uint8]

proc cbss_cosmic_text_engine_new(useSystemFonts: uint8): pointer
  {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_engine_free(handle: pointer)
  {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_add_font_file(handle: pointer; path: cstring): uint8
  {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_add_font_data(handle: pointer; data: ptr UncheckedArray[uint8]; len: csize_t): uint8
  {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_measure(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    output: ptr CosmicTextMeasureResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_font_unit_metrics(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    output: ptr CosmicTextFontMetricsResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_baseline_metrics(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    output: ptr CosmicTextBaselineMetricsResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_render_bitmap(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    output: ptr CosmicTextBitmapResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_render_bitmap_region(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    regionTop, regionHeight: cfloat;
    output: ptr CosmicTextBitmapResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_caret_position(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    query: ptr CosmicTextCaretQuery;
    output: ptr CosmicTextCaretResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_hit_test(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    query: ptr CosmicTextPointQuery;
    output: ptr CosmicTextCaretResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_caret_layout(
    handle: pointer;
    input: ptr CosmicTextMeasureInput;
    output: ptr CosmicTextCaretLayoutResult
): uint8 {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_caret_layout_free(samples: ptr UncheckedArray[CosmicTextCaretSample]; len: csize_t)
  {.cdecl, importc, dynlib: cosmicTextBridgeLib.}
proc cbss_cosmic_text_bitmap_free(pixels: ptr UncheckedArray[uint8]; len: csize_t)
  {.cdecl, importc, dynlib: cosmicTextBridgeLib.}

proc initCosmicTextEngine*(fonts = initFontRegistry()): CosmicTextEngine =
  result.handle = cbss_cosmic_text_engine_new(if fonts.useSystemFonts: 1'u8 else: 0'u8)
  for face in fonts.faces:
    if face.source.kind == fskFile and face.source.path.isSome:
      discard cbss_cosmic_text_add_font_file(result.handle, face.source.path.get.cstring)
    elif face.source.kind == fskMemory and face.source.bytes.len > 0:
      discard cbss_cosmic_text_add_font_data(
        result.handle,
        cast[ptr UncheckedArray[uint8]](unsafeAddr face.source.bytes[0]),
        csize_t(face.source.bytes.len)
      )

proc close*(engine: var CosmicTextEngine) =
  if not engine.handle.isNil:
    cbss_cosmic_text_engine_free(engine.handle)
    engine.handle = nil

proc fontStyleCode(style: Option[FontStyle]): uint32 =
  if style.isNone:
    return 0
  case style.get
  of fsNormal:
    0'u32
  of fsItalic:
    1'u32
  of fsOblique:
    2'u32

proc wrapCode(style: ComputedTextStyle): uint32 =
  if style.whiteSpace.isSome and style.whiteSpace.get in {wsNoWrap, wsPre}:
    return 1
  if style.textWrap.isSome and style.textWrap.get == twNoWrap:
    return 1
  if style.overflowWrap.isSome and style.overflowWrap.get in {owAnywhere, owBreakWord}:
    return 2
  if style.wordBreak.isSome and style.wordBreak.get in {wbBreakAll, wbBreakWord}:
    return 2
  0

proc addFeature(features: var seq[string]; tag: string; enabled = true) =
  features.add(tag & " " & (if enabled: "1" else: "0"))

proc appendLigatureFeatures(features: var seq[string]; value: string) =
  for item in value.splitWhitespace:
    case item
    of "none":
      features.addFeature("liga", false)
      features.addFeature("clig", false)
      features.addFeature("dlig", false)
      features.addFeature("hlig", false)
    of "common-ligatures":
      features.addFeature("liga")
      features.addFeature("clig")
    of "no-common-ligatures":
      features.addFeature("liga", false)
      features.addFeature("clig", false)
    of "discretionary-ligatures":
      features.addFeature("dlig")
    of "no-discretionary-ligatures":
      features.addFeature("dlig", false)
    of "historical-ligatures":
      features.addFeature("hlig")
    of "no-historical-ligatures":
      features.addFeature("hlig", false)
    of "contextual":
      features.addFeature("calt")
    of "no-contextual":
      features.addFeature("calt", false)
    else:
      discard

proc appendCapsFeatures(features: var seq[string]; value: string) =
  case value
  of "small-caps":
    features.addFeature("smcp")
  of "all-small-caps":
    features.addFeature("smcp")
    features.addFeature("c2sc")
  of "petite-caps":
    features.addFeature("pcap")
  of "all-petite-caps":
    features.addFeature("pcap")
    features.addFeature("c2pc")
  of "unicase":
    features.addFeature("unic")
  of "titling-caps":
    features.addFeature("titl")
  else:
    discard

proc appendNumericFeatures(features: var seq[string]; value: string) =
  for item in value.splitWhitespace:
    case item
    of "lining-nums": features.addFeature("lnum")
    of "oldstyle-nums": features.addFeature("onum")
    of "proportional-nums": features.addFeature("pnum")
    of "tabular-nums": features.addFeature("tnum")
    of "diagonal-fractions": features.addFeature("frac")
    of "stacked-fractions": features.addFeature("afrc")
    of "ordinal": features.addFeature("ordn")
    of "slashed-zero": features.addFeature("zero")
    else: discard

proc appendEastAsianFeatures(features: var seq[string]; value: string) =
  for item in value.splitWhitespace:
    case item
    of "jis78": features.addFeature("jp78")
    of "jis83": features.addFeature("jp83")
    of "jis90": features.addFeature("jp90")
    of "jis04": features.addFeature("jp04")
    of "simplified": features.addFeature("smpl")
    of "traditional": features.addFeature("trad")
    of "full-width": features.addFeature("fwid")
    of "proportional-width": features.addFeature("pwid")
    of "ruby": features.addFeature("ruby")
    else: discard

proc appendPositionFeatures(features: var seq[string]; value: string) =
  case value
  of "sub":
    features.addFeature("subs")
  of "super":
    features.addFeature("sups")
  else:
    discard

proc appendAlternateFeatures(features: var seq[string]; value: string) =
  for item in value.splitWhitespace:
    case item
    of "historical-forms": features.addFeature("hist")
    else: discard

proc computedFontFeatures(style: ComputedTextStyle): string =
  var features: seq[string]
  if style.fontKerning.isSome:
    case style.fontKerning.get
    of fkNormal:
      features.addFeature("kern")
    of fkNone:
      features.addFeature("kern", false)
    of fkAuto:
      discard
  if style.fontVariant.isSome:
    appendLigatureFeatures(features, style.fontVariant.get)
    appendCapsFeatures(features, style.fontVariant.get)
    appendNumericFeatures(features, style.fontVariant.get)
    appendEastAsianFeatures(features, style.fontVariant.get)
    appendPositionFeatures(features, style.fontVariant.get)
    appendAlternateFeatures(features, style.fontVariant.get)
  if style.fontVariantLigatures.isSome:
    appendLigatureFeatures(features, style.fontVariantLigatures.get)
  if style.fontVariantCaps.isSome:
    appendCapsFeatures(features, style.fontVariantCaps.get)
  if style.fontVariantNumeric.isSome:
    appendNumericFeatures(features, style.fontVariantNumeric.get)
  if style.fontVariantEastAsian.isSome:
    appendEastAsianFeatures(features, style.fontVariantEastAsian.get)
  if style.fontVariantPosition.isSome:
    appendPositionFeatures(features, style.fontVariantPosition.get)
  if style.fontVariantAlternates.isSome:
    appendAlternateFeatures(features, style.fontVariantAlternates.get)
  if style.fontFeatureSettings.isSome and style.fontFeatureSettings.get.len > 0:
    features.add style.fontFeatureSettings.get
  features.join(",")

proc measureCosmicText*(engine: CosmicTextEngine; input: TextMeasureInput): Size =
  if engine.handle.isNil:
    return debugMeasureText(input)

  let families = effectiveFontFamilies(input.style, input.fonts).join(",")
  let features = input.style.computedFontFeatures()
  let variations =
    if input.style.fontVariationSettings.isSome: input.style.fontVariationSettings.get
    else: ""
  let fontSize =
    if input.style.fontSize.isSome: input.style.fontSize.get
    else: 16.0'f32
  let adjustedFontSize =
    if input.style.fontSizeAdjust.isSome: fontSize * max(0.1'f32, input.style.fontSizeAdjust.get)
    else: fontSize
  let lineHeight =
    if input.style.lineHeight.isSome: input.style.lineHeight.get
    else: adjustedFontSize * 1.2'f32
  var request = CosmicTextMeasureInput(
    text: input.text.cstring,
    familyCsv: families.cstring,
    fontFeatures: features.cstring,
    fontVariations: variations.cstring,
    fontSize: cfloat(adjustedFontSize),
    lineHeight: cfloat(lineHeight),
    maxWidth: if input.maxWidth.isSome: cfloat(input.maxWidth.get) else: cfloat(0),
    hasMaxWidth: if input.maxWidth.isSome: 1'u8 else: 0'u8,
    fontWeight: cfloat(if input.style.fontWeight.isSome: input.style.fontWeight.get else: 400.0'f32),
    fontStyle: input.style.fontStyle.fontStyleCode,
    fontStretch: cfloat(if input.style.fontStretch.isSome: input.style.fontStretch.get else: 100.0'f32),
    letterSpacing: cfloat(if input.style.letterSpacing.isSome: input.style.letterSpacing.get else: 0.0'f32),
    wordSpacing: cfloat(if input.style.wordSpacing.isSome: input.style.wordSpacing.get else: 0.0'f32),
    wrap: input.style.wrapCode
  )
  var output: CosmicTextMeasureResult
  if cbss_cosmic_text_measure(engine.handle, addr request, addr output) == 0 or output.ok == 0:
    return debugMeasureText(input)
  size(output.width.float32, output.height.float32)

proc toCosmicRequest(input: TextMeasureInput): CosmicTextMeasureInput =
  let families = effectiveFontFamilies(input.style, input.fonts).join(",")
  let features = input.style.computedFontFeatures()
  let variations =
    if input.style.fontVariationSettings.isSome: input.style.fontVariationSettings.get
    else: ""
  let fontSize =
    if input.style.fontSize.isSome: input.style.fontSize.get
    else: 16.0'f32
  let adjustedFontSize =
    if input.style.fontSizeAdjust.isSome: fontSize * max(0.1'f32, input.style.fontSizeAdjust.get)
    else: fontSize
  let lineHeight =
    if input.style.lineHeight.isSome: input.style.lineHeight.get
    else: adjustedFontSize * 1.2'f32
  CosmicTextMeasureInput(
    text: input.text.cstring,
    familyCsv: families.cstring,
    fontFeatures: features.cstring,
    fontVariations: variations.cstring,
    fontSize: cfloat(adjustedFontSize),
    lineHeight: cfloat(lineHeight),
    maxWidth: if input.maxWidth.isSome: cfloat(input.maxWidth.get) else: cfloat(0),
    hasMaxWidth: if input.maxWidth.isSome: 1'u8 else: 0'u8,
    fontWeight: cfloat(if input.style.fontWeight.isSome: input.style.fontWeight.get else: 400.0'f32),
    fontStyle: input.style.fontStyle.fontStyleCode,
    fontStretch: cfloat(if input.style.fontStretch.isSome: input.style.fontStretch.get else: 100.0'f32),
    letterSpacing: cfloat(if input.style.letterSpacing.isSome: input.style.letterSpacing.get else: 0.0'f32),
    wordSpacing: cfloat(if input.style.wordSpacing.isSome: input.style.wordSpacing.get else: 0.0'f32),
    wrap: input.style.wrapCode
  )

proc measureCosmicFontUnits*(
    engine: CosmicTextEngine;
    input: TextFontMetricsInput
): FontUnitMetrics =
  let fontSize = input.style.fontSize.get(16.0'f32)
  result = fallbackFontUnitMetrics(fontSize)
  if engine.handle.isNil:
    return
  var request = TextMeasureInput(
    text: "0",
    style: input.style,
    maxWidth: none(float32),
    fonts: input.fonts
  ).toCosmicRequest()
  var output: CosmicTextFontMetricsResult
  if cbss_cosmic_text_font_unit_metrics(
      engine.handle, addr request, addr output
  ) == 0 or output.ok == 0:
    return
  result = FontUnitMetrics(
    version: fontUnitMetricsVersion,
    xHeight: output.xHeight.float32,
    zeroAdvance: output.zeroAdvance.float32
  )

proc measureCosmicBaselineMetrics*(
    engine: CosmicTextEngine;
    input: TextFontMetricsInput
): TextBaselineMetrics =
  result = fallbackTextBaselineMetrics(input.style)
  if engine.handle.isNil:
    return
  var request = TextMeasureInput(
    text: "0",
    style: input.style,
    maxWidth: none(float32),
    fonts: input.fonts
  ).toCosmicRequest()
  var output: CosmicTextBaselineMetricsResult
  if cbss_cosmic_text_baseline_metrics(
      engine.handle, addr request, addr output
  ) == 0 or output.ok == 0:
    return
  result = TextBaselineMetrics(
    ascent: output.ascent.float32,
    descent: output.descent.float32
  )

proc addKeyPart(parts: var seq[string]; value: string) =
  parts.add($value.len & ":" & value)

proc addKeyPart(parts: var seq[string]; value: float32) =
  parts.add($value)

proc addKeyPart(parts: var seq[string]; value: uint32) =
  parts.add($value)

proc cosmicTextRasterKey*(input: TextMeasureInput): string =
  let families = effectiveFontFamilies(input.style, input.fonts).join(",")
  let features = input.style.computedFontFeatures()
  let variations =
    if input.style.fontVariationSettings.isSome: input.style.fontVariationSettings.get
    else: ""
  let fontSize =
    if input.style.fontSize.isSome: input.style.fontSize.get
    else: 16.0'f32
  let adjustedFontSize =
    if input.style.fontSizeAdjust.isSome: fontSize * max(0.1'f32, input.style.fontSizeAdjust.get)
    else: fontSize
  let lineHeight =
    if input.style.lineHeight.isSome: input.style.lineHeight.get
    else: adjustedFontSize * 1.2'f32
  var parts: seq[string]
  parts.addKeyPart(input.text)
  parts.addKeyPart(families)
  parts.addKeyPart(features)
  parts.addKeyPart(variations)
  parts.addKeyPart(adjustedFontSize)
  parts.addKeyPart(lineHeight)
  parts.addKeyPart(if input.maxWidth.isSome: input.maxWidth.get else: 0.0'f32)
  parts.addKeyPart(if input.maxWidth.isSome: 1'u32 else: 0'u32)
  parts.addKeyPart(if input.style.fontWeight.isSome: input.style.fontWeight.get else: 400.0'f32)
  parts.addKeyPart(input.style.fontStyle.fontStyleCode)
  parts.addKeyPart(if input.style.fontStretch.isSome: input.style.fontStretch.get else: 100.0'f32)
  parts.addKeyPart(if input.style.letterSpacing.isSome: input.style.letterSpacing.get else: 0.0'f32)
  parts.addKeyPart(if input.style.wordSpacing.isSome: input.style.wordSpacing.get else: 0.0'f32)
  parts.addKeyPart(input.style.wrapCode)
  parts.join("|")

const maxCosmicBitmapBytes = 64 * 1024 * 1024

proc takeCosmicBitmap(output: CosmicTextBitmapResult): Option[CosmicTextBitmap] =
  if output.ok == 0:
    return none(CosmicTextBitmap)
  let width = int(output.width)
  let height = int(output.height)
  let expected = width.int64 * height.int64 * 4'i64
  if expected < 0 or expected > maxCosmicBitmapBytes.int64 or
      output.len.int64 != expected:
    if output.len > 0 and not output.pixels.isNil:
      cbss_cosmic_text_bitmap_free(output.pixels, output.len)
    return none(CosmicTextBitmap)
  var bitmap = CosmicTextBitmap(
    width: width,
    height: height,
    offsetX: int(output.offsetX),
    offsetY: int(output.offsetY),
    pixels: newSeq[uint8](int(output.len))
  )
  if output.len > 0 and not output.pixels.isNil:
    copyMem(addr bitmap.pixels[0], output.pixels, int(output.len))
    cbss_cosmic_text_bitmap_free(output.pixels, output.len)
  some(bitmap)

proc renderCosmicTextBitmap*(engine: CosmicTextEngine; input: TextMeasureInput): Option[CosmicTextBitmap] =
  if engine.handle.isNil:
    return none(CosmicTextBitmap)
  var request = input.toCosmicRequest()
  var output: CosmicTextBitmapResult
  if cbss_cosmic_text_render_bitmap(engine.handle, addr request, addr output) == 0:
    return none(CosmicTextBitmap)
  output.takeCosmicBitmap()

proc renderCosmicTextBitmapRegion*(
    engine: CosmicTextEngine;
    input: TextMeasureInput;
    regionTop, regionHeight: float32
): Option[CosmicTextBitmap] =
  if engine.handle.isNil or regionHeight <= 0:
    return none(CosmicTextBitmap)
  var request = input.toCosmicRequest()
  var output: CosmicTextBitmapResult
  if cbss_cosmic_text_render_bitmap_region(
      engine.handle,
      addr request,
      cfloat(regionTop),
      cfloat(regionHeight),
      addr output
  ) == 0:
    return none(CosmicTextBitmap)
  output.takeCosmicBitmap()

proc caretCosmicText*(engine: CosmicTextEngine; input: TextCaretInput): TextCaretResult =
  if engine.handle.isNil:
    return debugCaretPosition(input)
  var request = TextMeasureInput(
    text: input.text,
    style: input.style,
    maxWidth: input.maxWidth,
    fonts: input.fonts
  ).toCosmicRequest()
  var query = CosmicTextCaretQuery(byteIndex: csize_t(max(0, input.byteIndex)))
  var output: CosmicTextCaretResult
  if cbss_cosmic_text_caret_position(engine.handle, addr request, addr query, addr output) == 0 or output.ok == 0:
    return debugCaretPosition(input)
  TextCaretResult(
    position: vec2(output.x.float32, output.y.float32),
    height: output.height.float32,
    byteIndex: int(output.byteIndex)
  )

proc hitCosmicText*(engine: CosmicTextEngine; input: TextHitInput): TextCaretResult =
  if engine.handle.isNil:
    return debugHitText(input)
  var request = TextMeasureInput(
    text: input.text,
    style: input.style,
    maxWidth: input.maxWidth,
    fonts: input.fonts
  ).toCosmicRequest()
  var query = CosmicTextPointQuery(x: cfloat(input.point.x), y: cfloat(input.point.y))
  var output: CosmicTextCaretResult
  if cbss_cosmic_text_hit_test(engine.handle, addr request, addr query, addr output) == 0 or output.ok == 0:
    return debugHitText(input)
  TextCaretResult(
    position: vec2(output.x.float32, output.y.float32),
    height: output.height.float32,
    byteIndex: int(output.byteIndex)
  )

proc caretLayoutCosmicText*(engine: CosmicTextEngine; input: TextMeasureInput): seq[TextCaretSample] =
  if engine.handle.isNil:
    return debugTextEngine().carets(input)
  var request = input.toCosmicRequest()
  var output: CosmicTextCaretLayoutResult
  if cbss_cosmic_text_caret_layout(engine.handle, addr request, addr output) == 0 or output.ok == 0:
    return debugTextEngine().carets(input)
  if output.len > 0 and not output.samples.isNil:
    for index in 0 ..< int(output.len):
      let sample = output.samples[index]
      result.add TextCaretSample(
        byteIndex: int(sample.byteIndex),
        position: vec2(sample.x.float32, sample.y.float32),
        height: sample.height.float32
      )
    cbss_cosmic_text_caret_layout_free(output.samples, output.len)

proc textEngine*(engine: CosmicTextEngine): TextEngine =
  let handle = engine.handle
  var measureCache: seq[TextMeasureCacheEntry] = @[]
  var caretCache: seq[TextCaretCacheEntry] = @[]
  var fontMetricsCache: seq[TextFontMetricsCacheEntry] = @[]
  var baselineMetricsCache: seq[TextBaselineMetricsCacheEntry] = @[]

  proc trimMeasureCache() =
    const limit = 512
    while measureCache.len > limit:
      measureCache.delete(0)

  proc trimCaretCache() =
    const limit = 512
    while caretCache.len > limit:
      caretCache.delete(0)

  proc trimFontMetricsCache() =
    const limit = 128
    while fontMetricsCache.len > limit:
      fontMetricsCache.delete(0)

  proc trimBaselineMetricsCache() =
    const limit = 128
    while baselineMetricsCache.len > limit:
      baselineMetricsCache.delete(0)

  proc cachedMeasure(input: TextMeasureInput): Size =
    let key = input.cosmicTextRasterKey()
    if input.text.len > 256 or key.len > 2048:
      return measureCosmicText(CosmicTextEngine(handle: handle), input)
    for entry in measureCache:
      if entry.key == key:
        return entry.value
    result = measureCosmicText(CosmicTextEngine(handle: handle), input)
    measureCache.add TextMeasureCacheEntry(key: key, value: result)
    trimMeasureCache()

  proc cachedCaret(input: TextCaretInput): TextCaretResult =
    let measureInput = TextMeasureInput(
      text: input.text,
      style: input.style,
      maxWidth: input.maxWidth,
      fonts: input.fonts
    )
    let key = measureInput.cosmicTextRasterKey() & "|caret:" & $input.byteIndex
    if input.text.len > 256 or key.len > 2048:
      return caretCosmicText(CosmicTextEngine(handle: handle), input)
    for entry in caretCache:
      if entry.key == key:
        return entry.value
    result = caretCosmicText(CosmicTextEngine(handle: handle), input)
    caretCache.add TextCaretCacheEntry(key: key, value: result)
    trimCaretCache()

  proc cachedHit(input: TextHitInput): TextCaretResult =
    let measureInput = TextMeasureInput(
      text: input.text,
      style: input.style,
      maxWidth: input.maxWidth,
      fonts: input.fonts
    )
    let key = measureInput.cosmicTextRasterKey() &
      "|hit:" & $input.point.x & "," & $input.point.y
    if input.text.len > 256 or key.len > 2048:
      return hitCosmicText(CosmicTextEngine(handle: handle), input)
    for entry in caretCache:
      if entry.key == key:
        return entry.value
    result = hitCosmicText(CosmicTextEngine(handle: handle), input)
    caretCache.add TextCaretCacheEntry(key: key, value: result)
    trimCaretCache()

  proc cachedCaretLayout(input: TextMeasureInput): seq[TextCaretSample] =
    caretLayoutCosmicText(CosmicTextEngine(handle: handle), input)

  proc cachedFontMetrics(input: TextFontMetricsInput): FontUnitMetrics =
    let measureInput = TextMeasureInput(
      text: "0",
      style: input.style,
      maxWidth: none(float32),
      fonts: input.fonts
    )
    let key = measureInput.cosmicTextRasterKey()
    for entry in fontMetricsCache:
      if entry.key == key:
        return entry.value
    result = measureCosmicFontUnits(CosmicTextEngine(handle: handle), input)
    fontMetricsCache.add TextFontMetricsCacheEntry(key: key, value: result)
    trimFontMetricsCache()

  proc cachedBaselineMetrics(input: TextFontMetricsInput): TextBaselineMetrics =
    let measureInput = TextMeasureInput(
      text: "0",
      style: input.style,
      maxWidth: none(float32),
      fonts: input.fonts
    )
    let key = measureInput.cosmicTextRasterKey()
    for entry in baselineMetricsCache:
      if entry.key == key:
        return entry.value
    result = measureCosmicBaselineMetrics(CosmicTextEngine(handle: handle), input)
    baselineMetricsCache.add TextBaselineMetricsCacheEntry(key: key, value: result)
    trimBaselineMetricsCache()

  TextEngine(
    measureText: proc(input: TextMeasureInput): Size =
      cachedMeasure(input),
    caretPosition: proc(input: TextCaretInput): TextCaretResult =
      cachedCaret(input),
    hitTestText: proc(input: TextHitInput): TextCaretResult =
      cachedHit(input),
    fontUnitMetrics: proc(input: TextFontMetricsInput): FontUnitMetrics =
      cachedFontMetrics(input),
    baselineMetrics: proc(input: TextFontMetricsInput): TextBaselineMetrics =
      cachedBaselineMetrics(input),
    layoutCarets: proc(input: TextMeasureInput): seq[TextCaretSample] =
      cachedCaretLayout(input)
  )
