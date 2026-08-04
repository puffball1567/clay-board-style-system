import std/[options, strutils]
import ../core/[color, computed_style, declaration, diagnostics, property,
    style_color, style_value]
import ./length_resolution

proc requireKeyword(declaration: Declaration;
    diagnostics: var Diagnostics): Option[string] =
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
    return none(string)
  some(declaration.operation.value.get.keyword)

proc parseFontFamilies(value: string): seq[string] =
  for family in value.split(','):
    let trimmed = family.strip()
    if trimmed.len > 0:
      result.add trimmed

proc applyFontFamily(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isSome:
      let families = parseFontFamilies(value.get)
      if families.len == 0:
        diagnostics.addError(declaration.property, "font-family requires at least one family")
        return
      style.text.fontFamily = some(families[0])
      style.text.fontFamilies = families
  of mmInitial, mmUnset:
    style.text.fontFamily = none(string)
    style.text.fontFamilies.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.text.fontFamily = env.parent.get.text.fontFamily
      style.text.fontFamilies = env.parent.get.text.fontFamilies
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-family without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-family does not support relative merge")

proc applyFontStyle(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "normal":
      style.text.fontStyle = some(fsNormal)
    of "italic":
      style.text.fontStyle = some(fsItalic)
    of "oblique":
      style.text.fontStyle = some(fsOblique)
    else:
      diagnostics.addError(declaration.property, "unsupported font-style keyword")
  of mmInitial, mmUnset:
    style.text.fontStyle = some(fsNormal)
  of mmInherit:
    if env.parent.isSome:
      style.text.fontStyle = env.parent.get.text.fontStyle
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-style without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-style does not support relative merge")

proc applyFontWeight(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "font-weight requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      style.text.fontWeight = some(max(1.0'f32, value.number))
    of svKeyword:
      case value.keyword
      of "normal":
        style.text.fontWeight = some(400.0'f32)
      of "bold":
        style.text.fontWeight = some(700.0'f32)
      else:
        diagnostics.addError(declaration.property, "unsupported font-weight keyword")
    else:
      diagnostics.addError(declaration.property, "font-weight requires a number or keyword value")
  of mmInitial, mmUnset:
    style.text.fontWeight = some(400.0'f32)
  of mmInherit:
    if env.parent.isSome:
      style.text.fontWeight = env.parent.get.text.fontWeight
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-weight without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-weight relative merge is not implemented yet")

proc applyFontStretch(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "font-stretch requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svLength:
      if value.length.kind != ukPercent:
        diagnostics.addError(declaration.property, "font-stretch requires a percent value or keyword")
        return
      style.text.fontStretch = some(max(1.0'f32, value.length.value))
    of svKeyword:
      case value.keyword
      of "ultra-condensed":
        style.text.fontStretch = some(50.0'f32)
      of "extra-condensed":
        style.text.fontStretch = some(62.5'f32)
      of "condensed":
        style.text.fontStretch = some(75.0'f32)
      of "semi-condensed":
        style.text.fontStretch = some(87.5'f32)
      of "normal":
        style.text.fontStretch = some(100.0'f32)
      of "semi-expanded":
        style.text.fontStretch = some(112.5'f32)
      of "expanded":
        style.text.fontStretch = some(125.0'f32)
      of "extra-expanded":
        style.text.fontStretch = some(150.0'f32)
      of "ultra-expanded":
        style.text.fontStretch = some(200.0'f32)
      else:
        diagnostics.addError(declaration.property, "unsupported font-stretch keyword")
    else:
      diagnostics.addError(declaration.property, "font-stretch requires a percent value or keyword")
  of mmInitial, mmUnset:
    style.text.fontStretch = some(100.0'f32)
  of mmInherit:
    if env.parent.isSome:
      style.text.fontStretch = env.parent.get.text.fontStretch
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-stretch without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-stretch relative merge is not implemented yet")

proc applyFontSettings(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    if value.get == "normal":
      if declaration.property == "font-feature-settings":
        style.text.fontFeatureSettings = none(string)
      else:
        style.text.fontVariationSettings = none(string)
    else:
      if declaration.property == "font-feature-settings":
        style.text.fontFeatureSettings = value
      else:
        style.text.fontVariationSettings = value
  of mmInitial, mmUnset:
    if declaration.property == "font-feature-settings":
      style.text.fontFeatureSettings = none(string)
    else:
      style.text.fontVariationSettings = none(string)
  of mmInherit:
    if env.parent.isSome:
      if declaration.property == "font-feature-settings":
        style.text.fontFeatureSettings = env.parent.get.text.fontFeatureSettings
      else:
        style.text.fontVariationSettings = env.parent.get.text.fontVariationSettings
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyFontKerning(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "auto":
      style.text.fontKerning = some(fkAuto)
    of "normal":
      style.text.fontKerning = some(fkNormal)
    of "none":
      style.text.fontKerning = some(fkNone)
    else:
      diagnostics.addError(declaration.property, "unsupported font-kerning keyword")
  of mmInitial, mmUnset:
    style.text.fontKerning = some(fkAuto)
  of mmInherit:
    if env.parent.isSome:
      style.text.fontKerning = env.parent.get.text.fontKerning
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-kerning without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-kerning does not support relative merge")

proc applyFontOpticalSizing(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "auto":
      style.text.fontOpticalSizing = some(fosAuto)
    of "none":
      style.text.fontOpticalSizing = some(fosNone)
    else:
      diagnostics.addError(declaration.property, "unsupported font-optical-sizing keyword")
  of mmInitial, mmUnset:
    style.text.fontOpticalSizing = some(fosAuto)
  of mmInherit:
    if env.parent.isSome:
      style.text.fontOpticalSizing = env.parent.get.text.fontOpticalSizing
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-optical-sizing without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-optical-sizing does not support relative merge")

proc applyFontSizeAdjust(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "font-size-adjust requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      if value.keyword == "none":
        style.text.fontSizeAdjust = none(float32)
      else:
        diagnostics.addError(declaration.property, "unsupported font-size-adjust keyword")
    of svNumber:
      style.text.fontSizeAdjust = some(max(0.0'f32, value.number))
    else:
      diagnostics.addError(declaration.property, "font-size-adjust requires none or number")
  of mmInitial, mmUnset:
    style.text.fontSizeAdjust = none(float32)
  of mmInherit:
    if env.parent.isSome:
      style.text.fontSizeAdjust = env.parent.get.text.fontSizeAdjust
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-size-adjust without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-size-adjust relative merge is not implemented yet")

proc applyFontVariantKeyword(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    if value.get == "normal":
      case declaration.property
      of "font-variant": style.text.fontVariant = none(string)
      of "font-variant-ligatures": style.text.fontVariantLigatures = none(string)
      of "font-variant-caps": style.text.fontVariantCaps = none(string)
      else: style.text.fontVariantNumeric = none(string)
    else:
      case declaration.property
      of "font-variant": style.text.fontVariant = value
      of "font-variant-ligatures": style.text.fontVariantLigatures = value
      of "font-variant-caps": style.text.fontVariantCaps = value
      else: style.text.fontVariantNumeric = value
  of mmInitial, mmUnset:
    case declaration.property
    of "font-variant": style.text.fontVariant = none(string)
    of "font-variant-ligatures": style.text.fontVariantLigatures = none(string)
    of "font-variant-caps": style.text.fontVariantCaps = none(string)
    else: style.text.fontVariantNumeric = none(string)
  of mmInherit:
    if env.parent.isNone:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
      return
    case declaration.property
    of "font-variant": style.text.fontVariant = env.parent.get.text.fontVariant
    of "font-variant-ligatures": style.text.fontVariantLigatures = env.parent.get.text.fontVariantLigatures
    of "font-variant-caps": style.text.fontVariantCaps = env.parent.get.text.fontVariantCaps
    else: style.text.fontVariantNumeric = env.parent.get.text.fontVariantNumeric
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc setFontKeywordField(style: var ComputedStyle; property, value: string) =
  let normalized = if value in ["normal", "none"]: none(string) else: some(value)
  case property
  of "font-variant-east-asian": style.text.fontVariantEastAsian = normalized
  of "font-variant-position": style.text.fontVariantPosition = normalized
  of "font-variant-alternates": style.text.fontVariantAlternates = normalized
  of "font-variant-emoji": style.text.fontVariantEmoji = normalized
  of "font-language-override": style.text.fontLanguageOverride = normalized
  of "font-palette": style.text.fontPalette = normalized
  of "font-synthesis": style.text.fontSynthesis = normalized
  of "font-synthesis-position": style.text.fontSynthesisPosition = normalized
  of "font-synthesis-small-caps": style.text.fontSynthesisSmallCaps = normalized
  of "font-synthesis-style": style.text.fontSynthesisStyle = normalized
  else: style.text.fontSynthesisWeight = normalized

proc inheritFontKeywordField(style: var ComputedStyle; property: string;
    parent: ComputedStyle) =
  case property
  of "font-variant-east-asian": style.text.fontVariantEastAsian = parent.text.fontVariantEastAsian
  of "font-variant-position": style.text.fontVariantPosition = parent.text.fontVariantPosition
  of "font-variant-alternates": style.text.fontVariantAlternates = parent.text.fontVariantAlternates
  of "font-variant-emoji": style.text.fontVariantEmoji = parent.text.fontVariantEmoji
  of "font-language-override": style.text.fontLanguageOverride = parent.text.fontLanguageOverride
  of "font-palette": style.text.fontPalette = parent.text.fontPalette
  of "font-synthesis": style.text.fontSynthesis = parent.text.fontSynthesis
  of "font-synthesis-position": style.text.fontSynthesisPosition = parent.text.fontSynthesisPosition
  of "font-synthesis-small-caps": style.text.fontSynthesisSmallCaps = parent.text.fontSynthesisSmallCaps
  of "font-synthesis-style": style.text.fontSynthesisStyle = parent.text.fontSynthesisStyle
  else: style.text.fontSynthesisWeight = parent.text.fontSynthesisWeight

proc applyFontKeywordPassthrough(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isSome:
      style.setFontKeywordField(declaration.property, value.get)
  of mmInitial, mmUnset:
    style.setFontKeywordField(declaration.property, "normal")
  of mmInherit:
    if env.parent.isSome:
      style.inheritFontKeywordField(declaration.property, env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc baseFontSize(style: ComputedStyle; env: ResolveEnv): Option[float32] =
  if style.text.fontSize.isSome:
    return style.text.fontSize
  if env.currentFontSize.isSome:
    return env.currentFontSize
  if env.parent.isSome:
    return env.parent.get.text.fontSize
  none(float32)

proc applyLineHeight(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "line-height requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svLength:
      let resolved = resolveAbsoluteLength(value, env, declaration.property,
          diagnostics)
      if resolved.isSome:
        style.text.lineHeight = resolved
    of svNumber:
      let base = style.baseFontSize(env)
      if base.isNone:
        diagnostics.addError(declaration.property, "number line-height requires font-size")
        return
      style.text.lineHeight = some(base.get * value.number)
    of svKeyword:
      if value.keyword == "normal":
        style.text.lineHeight = none(float32)
      else:
        diagnostics.addError(declaration.property, "unsupported line-height keyword")
    else:
      diagnostics.addError(declaration.property, "line-height requires a length, number, or normal")
  of mmInitial, mmUnset:
    style.text.lineHeight = none(float32)
  of mmInherit:
    if env.parent.isSome:
      style.text.lineHeight = env.parent.get.text.lineHeight
    else:
      diagnostics.addError(declaration.property, "cannot inherit line-height without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "line-height relative merge is not implemented yet")

proc applyTextAlign(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "start":
      style.text.textAlign = some(taStart)
    of "left":
      style.text.textAlign = some(taLeft)
    of "center":
      style.text.textAlign = some(taCenter)
    of "right":
      style.text.textAlign = some(taRight)
    of "end":
      style.text.textAlign = some(taEnd)
    else:
      diagnostics.addError(declaration.property, "unsupported text-align keyword")
  of mmInitial, mmUnset:
    style.text.textAlign = some(taStart)
  of mmInherit:
    if env.parent.isSome:
      style.text.textAlign = env.parent.get.text.textAlign
    else:
      diagnostics.addError(declaration.property, "cannot inherit text-align without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-align does not support relative merge")

proc applyTextAlignLast(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "auto":
      style.text.textAlignLast = none(TextAlign)
    of "start":
      style.text.textAlignLast = some(taStart)
    of "left":
      style.text.textAlignLast = some(taLeft)
    of "center":
      style.text.textAlignLast = some(taCenter)
    of "right":
      style.text.textAlignLast = some(taRight)
    of "end":
      style.text.textAlignLast = some(taEnd)
    else:
      diagnostics.addError(declaration.property, "unsupported text-align-last keyword")
  of mmInitial, mmUnset:
    style.text.textAlignLast = none(TextAlign)
  of mmInherit:
    if env.parent.isSome:
      style.text.textAlignLast = env.parent.get.text.textAlignLast
    else:
      diagnostics.addError(declaration.property, "cannot inherit text-align-last without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-align-last does not support relative merge")

proc applyWhiteSpace(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "normal":
      style.text.whiteSpace = some(wsNormal)
    of "nowrap":
      style.text.whiteSpace = some(wsNoWrap)
    of "pre":
      style.text.whiteSpace = some(wsPre)
    of "pre-wrap":
      style.text.whiteSpace = some(wsPreWrap)
    of "pre-line":
      style.text.whiteSpace = some(wsPreLine)
    of "break-spaces":
      style.text.whiteSpace = some(wsBreakSpaces)
    else:
      diagnostics.addError(declaration.property, "unsupported white-space keyword")
  of mmInitial, mmUnset:
    style.text.whiteSpace = some(wsNormal)
  of mmInherit:
    if env.parent.isSome:
      style.text.whiteSpace = env.parent.get.text.whiteSpace
    else:
      diagnostics.addError(declaration.property, "cannot inherit white-space without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "white-space does not support relative merge")

proc applyTextOverflow(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "clip": style.text.textOverflow = some(toClip)
    of "ellipsis": style.text.textOverflow = some(toEllipsis)
    else: diagnostics.addError(declaration.property, "unsupported text-overflow keyword")
  of mmInitial, mmUnset:
    style.text.textOverflow = some(toClip)
  of mmInherit:
    if env.parent.isSome: style.text.textOverflow = env.parent.get.text.textOverflow
    else: diagnostics.addError(declaration.property, "cannot inherit text-overflow without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-overflow does not support relative merge")

proc applyOverflowWrap(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "normal": style.text.overflowWrap = some(owNormal)
    of "anywhere": style.text.overflowWrap = some(owAnywhere)
    of "break-word": style.text.overflowWrap = some(owBreakWord)
    else: diagnostics.addError(declaration.property, "unsupported " &
        declaration.property & " keyword")
  of mmInitial, mmUnset:
    style.text.overflowWrap = some(owNormal)
  of mmInherit:
    if env.parent.isSome: style.text.overflowWrap = env.parent.get.text.overflowWrap
    else: diagnostics.addError(declaration.property, "cannot inherit " &
        declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyWordBreak(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "normal": style.text.wordBreak = some(wbNormal)
    of "break-all": style.text.wordBreak = some(wbBreakAll)
    of "keep-all": style.text.wordBreak = some(wbKeepAll)
    of "break-word": style.text.wordBreak = some(wbBreakWord)
    else: diagnostics.addError(declaration.property, "unsupported word-break keyword")
  of mmInitial, mmUnset:
    style.text.wordBreak = some(wbNormal)
  of mmInherit:
    if env.parent.isSome: style.text.wordBreak = env.parent.get.text.wordBreak
    else: diagnostics.addError(declaration.property, "cannot inherit word-break without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "word-break does not support relative merge")

proc applyHyphens(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "manual": style.text.hyphens = some(hyManual)
    of "none": style.text.hyphens = some(hyNone)
    of "auto": style.text.hyphens = some(hyAuto)
    else: diagnostics.addError(declaration.property, "unsupported hyphens keyword")
  of mmInitial, mmUnset:
    style.text.hyphens = some(hyManual)
  of mmInherit:
    if env.parent.isSome: style.text.hyphens = env.parent.get.text.hyphens
    else: diagnostics.addError(declaration.property, "cannot inherit hyphens without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "hyphens does not support relative merge")

proc applyTextSpacing(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a value")
      return
    let value = declaration.operation.value.get
    if value.kind == svKeyword and value.keyword == "normal":
      if declaration.property == "letter-spacing": style.text.letterSpacing = some(0.0'f32)
      else: style.text.wordSpacing = some(0.0'f32)
      return
    let resolved = resolveAbsoluteLength(value, env, declaration.property,
        diagnostics)
    if resolved.isSome:
      if declaration.property == "letter-spacing": style.text.letterSpacing = resolved
      else: style.text.wordSpacing = resolved
  of mmInitial, mmUnset:
    if declaration.property == "letter-spacing": style.text.letterSpacing = some(0.0'f32)
    else: style.text.wordSpacing = some(0.0'f32)
  of mmInherit:
    if env.parent.isNone:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
      return
    if declaration.property == "letter-spacing": style.text.letterSpacing = env.parent.get.text.letterSpacing
    else: style.text.wordSpacing = env.parent.get.text.wordSpacing
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " relative merge is not implemented yet")

proc applyTextDecorationLine(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "none": style.text.textDecorationLine = some(tdlNone)
    of "underline": style.text.textDecorationLine = some(tdlUnderline)
    of "overline": style.text.textDecorationLine = some(tdlOverline)
    of "line-through": style.text.textDecorationLine = some(tdlLineThrough)
    else: diagnostics.addError(declaration.property, "unsupported text-decoration-line keyword")
  of mmInitial, mmUnset:
    style.text.textDecorationLine = some(tdlNone)
  of mmInherit:
    if env.parent.isSome: style.text.textDecorationLine = env.parent.get.text.textDecorationLine
    else: diagnostics.addError(declaration.property, "cannot inherit text-decoration-line without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-decoration-line does not support relative merge")

proc applyTextDecorationColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svColor:
      diagnostics.addError(declaration.property, "text-decoration-color requires a color value")
      return
    style.text.textDecorationColor = declaration.operation.value.get.resolveStyleColor(
        style, env)
  of mmInitial, mmUnset:
    style.text.textDecorationColor = none(Color)
  of mmInherit:
    if env.parent.isSome: style.text.textDecorationColor = env.parent.get.text.textDecorationColor
    else: diagnostics.addError(declaration.property, "cannot inherit text-decoration-color without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-decoration-color does not support relative merge")

proc applyTextDecorationStyle(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "solid": style.text.textDecorationStyle = some(tdsSolid)
    of "double": style.text.textDecorationStyle = some(tdsDouble)
    of "dotted": style.text.textDecorationStyle = some(tdsDotted)
    of "dashed": style.text.textDecorationStyle = some(tdsDashed)
    of "wavy": style.text.textDecorationStyle = some(tdsWavy)
    else: diagnostics.addError(declaration.property, "unsupported text-decoration-style keyword")
  of mmInitial, mmUnset:
    style.text.textDecorationStyle = some(tdsSolid)
  of mmInherit:
    if env.parent.isSome: style.text.textDecorationStyle = env.parent.get.text.textDecorationStyle
    else: diagnostics.addError(declaration.property, "cannot inherit text-decoration-style without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-decoration-style does not support relative merge")

proc applyTextDecorationThickness(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "text-decoration-thickness requires a value")
      return
    let value = declaration.operation.value.get
    if value.kind == svKeyword and value.keyword == "auto":
      style.text.textDecorationThickness = none(float32)
      return
    style.text.textDecorationThickness = resolveAbsoluteLength(value, env,
        declaration.property, diagnostics)
  of mmInitial, mmUnset:
    style.text.textDecorationThickness = none(float32)
  of mmInherit:
    if env.parent.isSome: style.text.textDecorationThickness = env.parent.get.text.textDecorationThickness
    else: diagnostics.addError(declaration.property, "cannot inherit text-decoration-thickness without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-decoration-thickness relative merge is not implemented yet")

proc applyTextDecoration(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "text-decoration requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      let lineDecl = Declaration(property: "text-decoration-line",
          operation: declaration.operation,
          sourceOrder: declaration.sourceOrder)
      style.applyTextDecorationLine(lineDecl, env, diagnostics)
    of svColor:
      style.text.textDecorationColor = value.resolveStyleColor(style, env)
    of svLength:
      style.text.textDecorationThickness = resolveAbsoluteLength(value, env,
          declaration.property, diagnostics)
    else:
      diagnostics.addError(declaration.property, "text-decoration supports line keywords, color, or thickness initially")
  of mmInitial, mmUnset:
    style.text.textDecorationLine = some(tdlNone)
    style.text.textDecorationColor = none(Color)
    style.text.textDecorationStyle = some(tdsSolid)
    style.text.textDecorationThickness = none(float32)
  of mmInherit:
    if env.parent.isSome:
      style.text.textDecorationLine = env.parent.get.text.textDecorationLine
      style.text.textDecorationColor = env.parent.get.text.textDecorationColor
      style.text.textDecorationStyle = env.parent.get.text.textDecorationStyle
      style.text.textDecorationThickness = env.parent.get.text.textDecorationThickness
    else:
      diagnostics.addError(declaration.property, "cannot inherit text-decoration without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-decoration does not support relative merge")

proc applyTextShadow(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "text-shadow requires a value")
      return
    let value = declaration.operation.value.get
    if value.kind == svKeyword and value.keyword == "none":
      style.text.textShadow = none(BoxShadow)
      return
    if value.kind != svShadow:
      diagnostics.addError(declaration.property, "text-shadow requires a structured shadow value or none")
      return
    let offsetX = resolveAbsoluteLength(value.shadowOffsetX, env,
        declaration.property, diagnostics)
    let offsetY = resolveAbsoluteLength(value.shadowOffsetY, env,
        declaration.property, diagnostics)
    if offsetX.isNone or offsetY.isNone:
      return
    var blur = 0.0'f32
    var spread = 0.0'f32
    if value.shadowBlur.isSome:
      let resolved = resolveAbsoluteLength(value.shadowBlur.get, env,
          declaration.property, diagnostics)
      if resolved.isNone:
        return
      blur = resolved.get
    if value.shadowSpread.isSome:
      let resolved = resolveAbsoluteLength(value.shadowSpread.get, env,
          declaration.property, diagnostics)
      if resolved.isNone:
        return
      spread = resolved.get
    style.text.textShadow = some(BoxShadow(
      offsetX: offsetX.get,
      offsetY: offsetY.get,
      blur: blur,
      spread: spread,
      color: value.resolveShadowColor(style, env)
    ))
  of mmInitial, mmUnset:
    style.text.textShadow = none(BoxShadow)
  of mmInherit:
    if env.parent.isSome: style.text.textShadow = env.parent.get.text.textShadow
    else: diagnostics.addError(declaration.property, "cannot inherit text-shadow without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-shadow does not support relative merge")

proc applyTextTransform(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "none": style.text.textTransform = some(ttNone)
    of "uppercase": style.text.textTransform = some(ttUppercase)
    of "lowercase": style.text.textTransform = some(ttLowercase)
    of "capitalize": style.text.textTransform = some(ttCapitalize)
    else: diagnostics.addError(declaration.property, "unsupported text-transform keyword")
  of mmInitial, mmUnset:
    style.text.textTransform = some(ttNone)
  of mmInherit:
    if env.parent.isSome: style.text.textTransform = env.parent.get.text.textTransform
    else: diagnostics.addError(declaration.property, "cannot inherit text-transform without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-transform does not support relative merge")

proc applyTextIndent(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "text-indent requires a value")
      return
    style.text.textIndent = resolveAbsoluteLength(
        declaration.operation.value.get, env, declaration.property,
        diagnostics)
  of mmInitial, mmUnset:
    style.text.textIndent = some(0.0'f32)
  of mmInherit:
    if env.parent.isSome: style.text.textIndent = env.parent.get.text.textIndent
    else: diagnostics.addError(declaration.property, "cannot inherit text-indent without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-indent relative merge is not implemented yet")

proc applyTextWrap(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "wrap": style.text.textWrap = some(twWrap)
    of "nowrap": style.text.textWrap = some(twNoWrap)
    of "balance": style.text.textWrap = some(twBalance)
    of "pretty": style.text.textWrap = some(twPretty)
    of "stable": style.text.textWrap = some(twStable)
    else: diagnostics.addError(declaration.property, "unsupported " &
        declaration.property & " keyword")
  of mmInitial, mmUnset:
    style.text.textWrap = some(twWrap)
  of mmInherit:
    if env.parent.isSome: style.text.textWrap = env.parent.get.text.textWrap
    else: diagnostics.addError(declaration.property, "cannot inherit " &
        declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyDirection(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "ltr": style.text.direction = some(tdLtr)
    of "rtl": style.text.direction = some(tdRtl)
    else: diagnostics.addError(declaration.property, "unsupported direction keyword")
  of mmInitial, mmUnset:
    style.text.direction = some(tdLtr)
  of mmInherit:
    if env.parent.isSome: style.text.direction = env.parent.get.text.direction
    else: diagnostics.addError(declaration.property, "cannot inherit direction without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "direction does not support relative merge")

proc applyUnicodeBidi(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "normal": style.text.unicodeBidi = some(ubNormal)
    of "embed": style.text.unicodeBidi = some(ubEmbed)
    of "isolate": style.text.unicodeBidi = some(ubIsolate)
    of "bidi-override": style.text.unicodeBidi = some(ubBidiOverride)
    of "isolate-override": style.text.unicodeBidi = some(ubIsolateOverride)
    of "plaintext": style.text.unicodeBidi = some(ubPlaintext)
    else: diagnostics.addError(declaration.property, "unsupported unicode-bidi keyword")
  of mmInitial, mmUnset:
    style.text.unicodeBidi = some(ubNormal)
  of mmInherit:
    if env.parent.isSome: style.text.unicodeBidi = env.parent.get.text.unicodeBidi
    else: diagnostics.addError(declaration.property, "cannot inherit unicode-bidi without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "unicode-bidi does not support relative merge")

proc applyWritingMode(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone: return
    case value.get
    of "horizontal-tb": style.text.writingMode = some(wmHorizontalTb)
    of "vertical-rl": style.text.writingMode = some(wmVerticalRl)
    of "vertical-lr": style.text.writingMode = some(wmVerticalLr)
    else: diagnostics.addError(declaration.property, "unsupported writing-mode keyword")
  of mmInitial, mmUnset:
    style.text.writingMode = some(wmHorizontalTb)
  of mmInherit:
    if env.parent.isSome: style.text.writingMode = env.parent.get.text.writingMode
    else: diagnostics.addError(declaration.property, "cannot inherit writing-mode without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "writing-mode does not support relative merge")

proc applyTabSize(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "tab-size requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      style.text.tabSize = some(max(0.0'f32, value.number))
    of svLength:
      let resolved = resolveAbsoluteLength(value, env, declaration.property,
          diagnostics)
      if resolved.isSome:
        style.text.tabSize = some(max(0.0'f32, resolved.get))
    else:
      diagnostics.addError(declaration.property, "tab-size requires a number or length")
  of mmInitial, mmUnset:
    style.text.tabSize = some(8.0'f32)
  of mmInherit:
    if env.parent.isSome: style.text.tabSize = env.parent.get.text.tabSize
    else: diagnostics.addError(declaration.property, "cannot inherit tab-size without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "tab-size relative merge is not implemented yet")

proc setTextMetadata(style: var ComputedStyle; property, value: string) =
  case property
  of "font":
    style.text.rawFont = some(value)
  of "font-smooth":
    style.text.fontSmooth = some(value)
  of "alignment-baseline":
    style.text.alignmentBaseline = some(value)
  of "baseline-shift":
    style.text.baselineShift = some(value)
  of "baseline-source":
    style.text.baselineSource = some(value)
  of "dominant-baseline":
    style.text.dominantBaseline = some(value)
  of "hanging-punctuation":
    style.text.hangingPunctuation = some(value)
  of "hyphenate-character":
    style.text.hyphenateCharacter = some(value)
  of "hyphenate-limit-chars":
    style.text.hyphenateLimitChars = some(value)
  of "initial-letter":
    style.text.initialLetter = some(value)
  of "initial-letter-align":
    style.text.initialLetterAlign = some(value)
  of "max-lines":
    style.text.maxLines = some(value)
  of "ruby-merge":
    style.text.rubyMerge = some(value)
  of "text-anchor":
    style.text.textAnchor = some(value)
  of "text-autospace":
    style.text.textAutospace = some(value)
  of "text-box":
    style.text.textBox = some(value)
  of "text-box-edge":
    style.text.textBoxEdge = some(value)
  of "text-box-trim":
    style.text.textBoxTrim = some(value)
  of "text-combine-upright":
    style.text.textCombineUpright = some(value)
  of "text-decoration-skip":
    style.text.textDecorationSkip = some(value)
  of "text-decoration-skip-ink":
    style.text.textDecorationSkipInk = some(value)
  of "text-emphasis":
    style.text.textEmphasis = some(value)
  of "text-emphasis-position":
    style.text.textEmphasisPosition = some(value)
  of "text-emphasis-style":
    style.text.textEmphasisStyle = some(value)
  of "text-justify":
    style.text.textJustify = some(value)
  of "text-orientation":
    style.text.textOrientation = some(value)
  of "text-rendering":
    style.text.textRendering = some(value)
  of "text-spacing-trim":
    style.text.textSpacingTrim = some(value)
  of "text-underline-position":
    style.text.textUnderlinePosition = some(value)
  of "white-space-collapse":
    style.text.whiteSpaceCollapse = some(value)
  of "vertical-align":
    style.text.verticalAlign = some(value)
  else:
    discard

proc clearTextMetadata(style: var ComputedStyle; property: string) =
  case property
  of "font":
    style.text.rawFont = none(string)
  of "font-smooth":
    style.text.fontSmooth = none(string)
  of "alignment-baseline":
    style.text.alignmentBaseline = none(string)
  of "baseline-shift":
    style.text.baselineShift = none(string)
  of "baseline-source":
    style.text.baselineSource = none(string)
  of "dominant-baseline":
    style.text.dominantBaseline = none(string)
  of "hanging-punctuation":
    style.text.hangingPunctuation = none(string)
  of "hyphenate-character":
    style.text.hyphenateCharacter = none(string)
  of "hyphenate-limit-chars":
    style.text.hyphenateLimitChars = none(string)
  of "initial-letter":
    style.text.initialLetter = none(string)
  of "initial-letter-align":
    style.text.initialLetterAlign = none(string)
  of "max-lines":
    style.text.maxLines = none(string)
  of "ruby-merge":
    style.text.rubyMerge = none(string)
  of "text-anchor":
    style.text.textAnchor = none(string)
  of "text-autospace":
    style.text.textAutospace = none(string)
  of "text-box":
    style.text.textBox = none(string)
  of "text-box-edge":
    style.text.textBoxEdge = none(string)
  of "text-box-trim":
    style.text.textBoxTrim = none(string)
  of "text-combine-upright":
    style.text.textCombineUpright = none(string)
  of "text-decoration-skip":
    style.text.textDecorationSkip = none(string)
  of "text-decoration-skip-ink":
    style.text.textDecorationSkipInk = none(string)
  of "text-emphasis":
    style.text.textEmphasis = none(string)
  of "text-emphasis-position":
    style.text.textEmphasisPosition = none(string)
  of "text-emphasis-style":
    style.text.textEmphasisStyle = none(string)
  of "text-justify":
    style.text.textJustify = none(string)
  of "text-orientation":
    style.text.textOrientation = none(string)
  of "text-rendering":
    style.text.textRendering = none(string)
  of "text-spacing-trim":
    style.text.textSpacingTrim = none(string)
  of "text-underline-position":
    style.text.textUnderlinePosition = none(string)
  of "white-space-collapse":
    style.text.whiteSpaceCollapse = none(string)
  of "vertical-align":
    style.text.verticalAlign = none(string)
  else:
    discard

proc getTextMetadata(style: ComputedStyle; property: string): Option[string] =
  case property
  of "font":
    style.text.rawFont
  of "font-smooth":
    style.text.fontSmooth
  of "alignment-baseline":
    style.text.alignmentBaseline
  of "baseline-shift":
    style.text.baselineShift
  of "baseline-source":
    style.text.baselineSource
  of "dominant-baseline":
    style.text.dominantBaseline
  of "hanging-punctuation":
    style.text.hangingPunctuation
  of "hyphenate-character":
    style.text.hyphenateCharacter
  of "hyphenate-limit-chars":
    style.text.hyphenateLimitChars
  of "initial-letter":
    style.text.initialLetter
  of "initial-letter-align":
    style.text.initialLetterAlign
  of "max-lines":
    style.text.maxLines
  of "ruby-merge":
    style.text.rubyMerge
  of "text-anchor":
    style.text.textAnchor
  of "text-autospace":
    style.text.textAutospace
  of "text-box":
    style.text.textBox
  of "text-box-edge":
    style.text.textBoxEdge
  of "text-box-trim":
    style.text.textBoxTrim
  of "text-combine-upright":
    style.text.textCombineUpright
  of "text-decoration-skip":
    style.text.textDecorationSkip
  of "text-decoration-skip-ink":
    style.text.textDecorationSkipInk
  of "text-emphasis":
    style.text.textEmphasis
  of "text-emphasis-position":
    style.text.textEmphasisPosition
  of "text-emphasis-style":
    style.text.textEmphasisStyle
  of "text-justify":
    style.text.textJustify
  of "text-orientation":
    style.text.textOrientation
  of "text-rendering":
    style.text.textRendering
  of "text-spacing-trim":
    style.text.textSpacingTrim
  of "text-underline-position":
    style.text.textUnderlinePosition
  of "white-space-collapse":
    style.text.whiteSpaceCollapse
  of "vertical-align":
    style.text.verticalAlign
  else:
    none(string)

proc applyTextMetadata(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isSome:
      style.setTextMetadata(declaration.property, value.get)
  of mmInitial, mmUnset:
    style.clearTextMetadata(declaration.property)
  of mmInherit:
    if env.parent.isSome:
      let value = env.parent.get.getTextMetadata(declaration.property)
      if value.isSome: style.setTextMetadata(declaration.property, value.get)
      else: style.clearTextMetadata(declaration.property)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc setTextLengthMetadata(style: var ComputedStyle; property: string;
    value: Option[float32]) =
  case property
  of "text-decoration-inset":
    style.text.textDecorationInset = value
  of "text-size-adjust":
    style.text.textSizeAdjust = value
  of "text-underline-offset":
    style.text.textUnderlineOffset = value
  else:
    discard

proc getTextLengthMetadata(style: ComputedStyle; property: string): Option[float32] =
  case property
  of "text-decoration-inset":
    style.text.textDecorationInset
  of "text-size-adjust":
    style.text.textSizeAdjust
  of "text-underline-offset":
    style.text.textUnderlineOffset
  else:
    none(float32)

proc applyTextLengthMetadata(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svLength:
      let resolved = normalizeLength(value, env, declaration.property,
          {ukPercent}, diagnostics)
      if resolved.isSome:
        style.setTextLengthMetadata(declaration.property, some(
            resolved.get.value))
    of svNumber:
      style.setTextLengthMetadata(declaration.property, some(value.number))
    of svKeyword:
      if value.keyword == "auto" or value.keyword == "none":
        style.setTextLengthMetadata(declaration.property, none(float32))
      else:
        diagnostics.addError(declaration.property, "unsupported " &
            declaration.property & " keyword")
    else:
      diagnostics.addError(declaration.property, declaration.property & " requires a length, number, auto, or none")
  of mmInitial, mmUnset:
    style.setTextLengthMetadata(declaration.property, none(float32))
  of mmInherit:
    if env.parent.isSome:
      style.setTextLengthMetadata(declaration.property,
          env.parent.get.getTextLengthMetadata(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyFontWidth(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "font-width requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svLength:
      if value.length.kind == ukPercent:
        style.text.fontWidth = some(max(1.0'f32, value.length.value))
      else:
        diagnostics.addError(declaration.property, "font-width requires a percent value or keyword")
    of svKeyword:
      case value.keyword
      of "ultra-condensed": style.text.fontWidth = some(50.0'f32)
      of "extra-condensed": style.text.fontWidth = some(62.5'f32)
      of "condensed": style.text.fontWidth = some(75.0'f32)
      of "semi-condensed": style.text.fontWidth = some(87.5'f32)
      of "normal": style.text.fontWidth = some(100.0'f32)
      of "semi-expanded": style.text.fontWidth = some(112.5'f32)
      of "expanded": style.text.fontWidth = some(125.0'f32)
      of "extra-expanded": style.text.fontWidth = some(150.0'f32)
      of "ultra-expanded": style.text.fontWidth = some(200.0'f32)
      else: diagnostics.addError(declaration.property, "unsupported font-width keyword")
    else:
      diagnostics.addError(declaration.property, "font-width requires a percent value or keyword")
  of mmInitial, mmUnset:
    style.text.fontWidth = some(100.0'f32)
  of mmInherit:
    if env.parent.isSome: style.text.fontWidth = env.parent.get.text.fontWidth
    else: diagnostics.addError(declaration.property, "cannot inherit font-width without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "font-width does not support relative merge")

proc applyTextEmphasisColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svColor:
      diagnostics.addError(declaration.property, "text-emphasis-color requires a color value")
      return
    style.text.textEmphasisColor = declaration.operation.value.get.resolveStyleColor(
        style, env)
  of mmInitial, mmUnset:
    style.text.textEmphasisColor = none(Color)
  of mmInherit:
    if env.parent.isSome: style.text.textEmphasisColor = env.parent.get.text.textEmphasisColor
    else: diagnostics.addError(declaration.property, "cannot inherit text-emphasis-color without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "text-emphasis-color does not support relative merge")

let fontFamilyProperty* = PropertyImpl(name: "font-family",
    apply: applyFontFamily)
let fontProperty* = PropertyImpl(name: "font", apply: applyTextMetadata)
let fontStyleProperty* = PropertyImpl(name: "font-style", apply: applyFontStyle)
let fontWeightProperty* = PropertyImpl(name: "font-weight",
    apply: applyFontWeight)
let fontStretchProperty* = PropertyImpl(name: "font-stretch",
    apply: applyFontStretch)
let fontWidthProperty* = PropertyImpl(name: "font-width", apply: applyFontWidth)
let fontSmoothProperty* = PropertyImpl(name: "font-smooth",
    apply: applyTextMetadata)
let alignmentBaselineProperty* = PropertyImpl(name: "alignment-baseline",
    apply: applyTextMetadata)
let baselineShiftProperty* = PropertyImpl(name: "baseline-shift",
    apply: applyTextMetadata)
let baselineSourceProperty* = PropertyImpl(name: "baseline-source",
    apply: applyTextMetadata)
let dominantBaselineProperty* = PropertyImpl(name: "dominant-baseline",
    apply: applyTextMetadata)
let fontFeatureSettingsProperty* = PropertyImpl(name: "font-feature-settings",
    apply: applyFontSettings)
let fontVariationSettingsProperty* = PropertyImpl(
    name: "font-variation-settings", apply: applyFontSettings)
let fontKerningProperty* = PropertyImpl(name: "font-kerning",
    apply: applyFontKerning)
let fontOpticalSizingProperty* = PropertyImpl(name: "font-optical-sizing",
    apply: applyFontOpticalSizing)
let fontSizeAdjustProperty* = PropertyImpl(name: "font-size-adjust",
    apply: applyFontSizeAdjust)
let fontVariantProperty* = PropertyImpl(name: "font-variant",
    apply: applyFontVariantKeyword)
let fontVariantLigaturesProperty* = PropertyImpl(name: "font-variant-ligatures",
    apply: applyFontVariantKeyword)
let fontVariantCapsProperty* = PropertyImpl(name: "font-variant-caps",
    apply: applyFontVariantKeyword)
let fontVariantNumericProperty* = PropertyImpl(name: "font-variant-numeric",
    apply: applyFontVariantKeyword)
let fontVariantEastAsianProperty* = PropertyImpl(
    name: "font-variant-east-asian", apply: applyFontKeywordPassthrough)
let fontVariantPositionProperty* = PropertyImpl(name: "font-variant-position",
    apply: applyFontKeywordPassthrough)
let fontVariantAlternatesProperty* = PropertyImpl(
    name: "font-variant-alternates", apply: applyFontKeywordPassthrough)
let fontVariantEmojiProperty* = PropertyImpl(name: "font-variant-emoji",
    apply: applyFontKeywordPassthrough)
let fontLanguageOverrideProperty* = PropertyImpl(name: "font-language-override",
    apply: applyFontKeywordPassthrough)
let fontPaletteProperty* = PropertyImpl(name: "font-palette",
    apply: applyFontKeywordPassthrough)
let fontSynthesisProperty* = PropertyImpl(name: "font-synthesis",
    apply: applyFontKeywordPassthrough)
let fontSynthesisPositionProperty* = PropertyImpl(
    name: "font-synthesis-position", apply: applyFontKeywordPassthrough)
let fontSynthesisSmallCapsProperty* = PropertyImpl(
    name: "font-synthesis-small-caps", apply: applyFontKeywordPassthrough)
let fontSynthesisStyleProperty* = PropertyImpl(name: "font-synthesis-style",
    apply: applyFontKeywordPassthrough)
let fontSynthesisWeightProperty* = PropertyImpl(name: "font-synthesis-weight",
    apply: applyFontKeywordPassthrough)
let lineHeightProperty* = PropertyImpl(name: "line-height",
    apply: applyLineHeight)
let textAlignProperty* = PropertyImpl(name: "text-align", apply: applyTextAlign)
let textAlignLastProperty* = PropertyImpl(name: "text-align-last",
    apply: applyTextAlignLast)
let whiteSpaceProperty* = PropertyImpl(name: "white-space",
    apply: applyWhiteSpace)
let textOverflowProperty* = PropertyImpl(name: "text-overflow",
    apply: applyTextOverflow)
let overflowWrapProperty* = PropertyImpl(name: "overflow-wrap",
    apply: applyOverflowWrap)
let wordWrapProperty* = PropertyImpl(name: "word-wrap",
    apply: applyOverflowWrap)
let wordBreakProperty* = PropertyImpl(name: "word-break", apply: applyWordBreak)
let hyphensProperty* = PropertyImpl(name: "hyphens", apply: applyHyphens)
let letterSpacingProperty* = PropertyImpl(name: "letter-spacing",
    apply: applyTextSpacing)
let wordSpacingProperty* = PropertyImpl(name: "word-spacing",
    apply: applyTextSpacing)
let textDecorationProperty* = PropertyImpl(name: "text-decoration",
    apply: applyTextDecoration)
let textDecorationLineProperty* = PropertyImpl(name: "text-decoration-line",
    apply: applyTextDecorationLine)
let textDecorationColorProperty* = PropertyImpl(name: "text-decoration-color",
    apply: applyTextDecorationColor)
let textDecorationStyleProperty* = PropertyImpl(name: "text-decoration-style",
    apply: applyTextDecorationStyle)
let textDecorationThicknessProperty* = PropertyImpl(
    name: "text-decoration-thickness", apply: applyTextDecorationThickness)
let textDecorationInsetProperty* = PropertyImpl(name: "text-decoration-inset",
    apply: applyTextLengthMetadata)
let textDecorationSkipProperty* = PropertyImpl(name: "text-decoration-skip",
    apply: applyTextMetadata)
let textDecorationSkipInkProperty* = PropertyImpl(
    name: "text-decoration-skip-ink", apply: applyTextMetadata)
let textShadowProperty* = PropertyImpl(name: "text-shadow",
    apply: applyTextShadow)
let textTransformProperty* = PropertyImpl(name: "text-transform",
    apply: applyTextTransform)
let textIndentProperty* = PropertyImpl(name: "text-indent",
    apply: applyTextIndent)
let textWrapProperty* = PropertyImpl(name: "text-wrap", apply: applyTextWrap)
let textWrapModeProperty* = PropertyImpl(name: "text-wrap-mode",
    apply: applyTextWrap)
let textWrapStyleProperty* = PropertyImpl(name: "text-wrap-style",
    apply: applyTextWrap)
let textAnchorProperty* = PropertyImpl(name: "text-anchor",
    apply: applyTextMetadata)
let textAutospaceProperty* = PropertyImpl(name: "text-autospace",
    apply: applyTextMetadata)
let textBoxProperty* = PropertyImpl(name: "text-box", apply: applyTextMetadata)
let textBoxEdgeProperty* = PropertyImpl(name: "text-box-edge",
    apply: applyTextMetadata)
let textBoxTrimProperty* = PropertyImpl(name: "text-box-trim",
    apply: applyTextMetadata)
let textCombineUprightProperty* = PropertyImpl(name: "text-combine-upright",
    apply: applyTextMetadata)
let textEmphasisProperty* = PropertyImpl(name: "text-emphasis",
    apply: applyTextMetadata)
let textEmphasisColorProperty* = PropertyImpl(name: "text-emphasis-color",
    apply: applyTextEmphasisColor)
let textEmphasisPositionProperty* = PropertyImpl(name: "text-emphasis-position",
    apply: applyTextMetadata)
let textEmphasisStyleProperty* = PropertyImpl(name: "text-emphasis-style",
    apply: applyTextMetadata)
let textJustifyProperty* = PropertyImpl(name: "text-justify",
    apply: applyTextMetadata)
let textOrientationProperty* = PropertyImpl(name: "text-orientation",
    apply: applyTextMetadata)
let textRenderingProperty* = PropertyImpl(name: "text-rendering",
    apply: applyTextMetadata)
let textSizeAdjustProperty* = PropertyImpl(name: "text-size-adjust",
    apply: applyTextLengthMetadata)
let textSpacingTrimProperty* = PropertyImpl(name: "text-spacing-trim",
    apply: applyTextMetadata)
let textUnderlineOffsetProperty* = PropertyImpl(name: "text-underline-offset",
    apply: applyTextLengthMetadata)
let textUnderlinePositionProperty* = PropertyImpl(
    name: "text-underline-position", apply: applyTextMetadata)
let directionProperty* = PropertyImpl(name: "direction", apply: applyDirection)
let unicodeBidiProperty* = PropertyImpl(name: "unicode-bidi",
    apply: applyUnicodeBidi)
let writingModeProperty* = PropertyImpl(name: "writing-mode",
    apply: applyWritingMode)
let whiteSpaceCollapseProperty* = PropertyImpl(name: "white-space-collapse",
    apply: applyTextMetadata)
let verticalAlignProperty* = PropertyImpl(name: "vertical-align",
    apply: applyTextMetadata)
let tabSizeProperty* = PropertyImpl(name: "tab-size", apply: applyTabSize)
let hangingPunctuationProperty* = PropertyImpl(name: "hanging-punctuation",
    apply: applyTextMetadata)
let hyphenateCharacterProperty* = PropertyImpl(name: "hyphenate-character",
    apply: applyTextMetadata)
let hyphenateLimitCharsProperty* = PropertyImpl(name: "hyphenate-limit-chars",
    apply: applyTextMetadata)
let initialLetterProperty* = PropertyImpl(name: "initial-letter",
    apply: applyTextMetadata)
let initialLetterAlignProperty* = PropertyImpl(name: "initial-letter-align",
    apply: applyTextMetadata)
let maxLinesProperty* = PropertyImpl(name: "max-lines",
    apply: applyTextMetadata)
let rubyMergeProperty* = PropertyImpl(name: "ruby-merge",
    apply: applyTextMetadata)
