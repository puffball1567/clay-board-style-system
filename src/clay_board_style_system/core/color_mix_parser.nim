import std/[math, options, strutils]

import ./[color_conversion, color_mix, color_parser, color_value]

type
  ColorMixParseErrorKind* = enum
    cmpekEmpty,
    cmpekUnknownFunction,
    cmpekUnbalancedFunction,
    cmpekInvalidArity,
    cmpekInvalidInterpolationSpace,
    cmpekInvalidPercentage,
    cmpekInvalidColor

  ColorMixParseError* = object
    kind*: ColorMixParseErrorKind
    offset*: int
    message*: string

  ColorMixParseResult* = object
    value*: Option[ColorMixValue]
    error*: Option[ColorMixParseError]

  SourcePart = object
    text: string
    offset: int

proc isOk*(parsed: ColorMixParseResult): bool {.inline.} =
  parsed.value.isSome

proc trimPart(source: string; offset: int): SourcePart =
  var first = 0
  while first < source.len and source[first].isSpaceAscii:
    inc first
  var last = source.high
  while last >= first and source[last].isSpaceAscii:
    dec last
  if first > last:
    SourcePart(text: "", offset: offset + first)
  else:
    SourcePart(text: source[first .. last], offset: offset + first)

proc splitTopLevel(body: string; baseOffset: int;
    parts: var seq[SourcePart]; error: var Option[ColorMixParseError]): bool =
  var depth = 0
  var start = 0
  for index, character in body:
    case character
    of '(':
      inc depth
    of ')':
      dec depth
      if depth < 0:
        error = some(ColorMixParseError(kind: cmpekUnbalancedFunction,
            offset: baseOffset + index, message: "unexpected closing parenthesis"))
        return false
    of ',':
      if depth == 0:
        parts.add trimPart(body[start ..< index], baseOffset + start)
        start = index + 1
    else:
      discard
  if depth != 0:
    error = some(ColorMixParseError(kind: cmpekUnbalancedFunction,
        offset: baseOffset + body.len, message: "unclosed color function"))
    return false
  parts.add trimPart(body[start ..< body.len], baseOffset + start)
  true

proc interpolationSpace(part: SourcePart;
    error: var Option[ColorMixParseError]): Option[ColorInterpolationSpace] =
  let words = part.text.toLowerAscii.splitWhitespace
  if words.len != 2 or words[0] != "in":
    error = some(ColorMixParseError(kind: cmpekInvalidInterpolationSpace,
        offset: part.offset, message: "expected 'in <color-space>'"))
    return none(ColorInterpolationSpace)
  case words[1]
  of "srgb": some(cisSrgb)
  of "srgb-linear": some(cisSrgbLinear)
  of "oklab": some(cisOklab)
  else:
    error = some(ColorMixParseError(kind: cmpekInvalidInterpolationSpace,
        offset: part.offset + part.text.rfind(words[1]),
        message: "unsupported color-mix interpolation space '" & words[1] & "'"))
    none(ColorInterpolationSpace)

proc parsePercentage(source: string; offset: int;
    percentage: var Option[float64]; error: var Option[
        ColorMixParseError]): bool =
  if source.len < 2 or source[^1] != '%':
    return false
  var value: float64
  try:
    value = parseFloat(source[0 ..< source.high])
  except ValueError:
    error = some(ColorMixParseError(kind: cmpekInvalidPercentage,
        offset: offset, message: "invalid color-mix percentage"))
    return false
  if value.classify in {fcNan, fcInf, fcNegInf} or value < 0 or value > 100:
    error = some(ColorMixParseError(kind: cmpekInvalidPercentage,
        offset: offset, message: "color-mix percentage must be between 0% and 100%"))
    return false
  percentage = some(value)
  true

proc parseMixItem(part: SourcePart; color: var ColorValue;
    percentage: var Option[float64]; error: var Option[
        ColorMixParseError]): bool =
  if part.text.len == 0:
    error = some(ColorMixParseError(kind: cmpekInvalidColor,
        offset: part.offset, message: "color-mix item is empty"))
    return false

  let direct = parseColor(part.text)
  if direct.isOk:
    color = direct.value.get
    return true

  var depth = 0
  var split = -1
  var index = part.text.high
  while index >= 0:
    case part.text[index]
    of ')': inc depth
    of '(': dec depth
    else:
      if depth == 0 and part.text[index].isSpaceAscii:
        split = index
        break
    dec index
  if split < 0:
    let diagnostic = direct.error.get
    error = some(ColorMixParseError(kind: cmpekInvalidColor,
        offset: part.offset + diagnostic.offset, message: diagnostic.message))
    return false

  let colorPart = trimPart(part.text[0 ..< split], part.offset)
  let percentPart = trimPart(part.text[split + 1 ..< part.text.len],
      part.offset + split + 1)
  if not parsePercentage(percentPart.text, percentPart.offset, percentage, error):
    if error.isNone:
      error = some(ColorMixParseError(kind: cmpekInvalidPercentage,
          offset: percentPart.offset, message: "expected a trailing percentage"))
    return false
  let parsedColor = parseColor(colorPart.text)
  if not parsedColor.isOk:
    let diagnostic = parsedColor.error.get
    error = some(ColorMixParseError(kind: cmpekInvalidColor,
        offset: colorPart.offset + diagnostic.offset,
        message: diagnostic.message))
    return false
  color = parsedColor.value.get
  true

proc parseColorMix*(input: string): ColorMixParseResult =
  let source = trimPart(input, 0)
  if source.text.len == 0:
    result.error = some(ColorMixParseError(kind: cmpekEmpty,
        offset: source.offset, message: "color mix is empty"))
    return

  let openParen = source.text.find('(')
  if openParen < 0 or source.text[0 ..< openParen].toLowerAscii != "color-mix":
    result.error = some(ColorMixParseError(kind: cmpekUnknownFunction,
        offset: source.offset, message: "expected color-mix()"))
    return
  if source.text[^1] != ')':
    result.error = some(ColorMixParseError(kind: cmpekUnbalancedFunction,
        offset: source.offset + source.text.len,
        message: "color-mix() must end with ')'"))
    return

  let bodyOffset = source.offset + openParen + 1
  let body = source.text[openParen + 1 ..< source.text.high]
  var parts: seq[SourcePart]
  var error: Option[ColorMixParseError]
  if not splitTopLevel(body, bodyOffset, parts, error):
    result.error = error
    return

  var space = cisOklab
  var itemStart = 0
  let firstWords = if parts.len > 0:
      parts[0].text.toLowerAscii.splitWhitespace else: @[]
  if firstWords.len > 0 and firstWords[0] == "in":
    let parsedSpace = interpolationSpace(parts[0], error)
    if parsedSpace.isNone:
      result.error = error
      return
    space = parsedSpace.get
    itemStart = 1
  if parts.len - itemStart != 2:
    result.error = some(ColorMixParseError(kind: cmpekInvalidArity,
        offset: bodyOffset, message: "color-mix() requires exactly two colors"))
    return

  var first, second: ColorValue
  var firstPercent, secondPercent: Option[float64]
  if not parseMixItem(parts[itemStart], first, firstPercent, error) or
      not parseMixItem(parts[itemStart + 1], second, secondPercent, error):
    result.error = error
    return
  try:
    result.value = some(normalizedColorMix(first, second, firstPercent,
        secondPercent, space))
  except ValueError as exception:
    result.error = some(ColorMixParseError(kind: cmpekInvalidPercentage,
        offset: parts[itemStart].offset, message: exception.msg))

proc parseColorMixOrRaise*(input: string): ColorMixValue =
  let parsed = parseColorMix(input)
  if parsed.isOk:
    return parsed.value.get
  let diagnostic = parsed.error.get
  raise newException(ValueError,
      diagnostic.message & " at byte offset " & $diagnostic.offset)
