import std/[colors, math, options, sequtils, strutils]

import ./color_value

type
  ColorParseErrorKind* = enum
    cpekEmpty,
    cpekInvalidHex,
    cpekUnknownColor,
    cpekUnknownFunction,
    cpekUnexpectedToken,
    cpekInvalidNumber,
    cpekInvalidUnit,
    cpekInvalidArity,
    cpekMixedLegacyUnits,
    cpekUnsupportedColorSpace,
    cpekTrailingInput

  ColorParseError* = object
    kind*: ColorParseErrorKind
    offset*: int
    message*: string

  ColorParseResult* = object
    value*: Option[ColorValue]
    error*: Option[ColorParseError]

  NumberUnit = enum
    nuNumber,
    nuPercent,
    nuDegrees,
    nuGradians,
    nuRadians,
    nuTurns

  TokenKind = enum
    tkNumber,
    tkIdentifier,
    tkComma,
    tkSlash

  Token = object
    kind: TokenKind
    offset: int
    separated: bool
    text: string
    number: float64
    unit: NumberUnit

const componentSlots = [ccFirst, ccSecond, ccThird]

proc isOk*(parsed: ColorParseResult): bool {.inline.} =
  parsed.value.isSome

proc setError(
    error: var Option[ColorParseError];
    kind: ColorParseErrorKind;
    offset: int;
    message: string
) =
  if error.isNone:
    error = some(ColorParseError(kind: kind, offset: offset, message: message))

proc isAsciiWhitespace(value: char): bool {.inline.} =
  value in {' ', '\t', '\r', '\n', '\f'}

proc isAsciiDigit(value: char): bool {.inline.} =
  value in {'0' .. '9'}

proc isIdentifierChar(value: char): bool {.inline.} =
  value in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-', '_'}

proc parseUnit(
    suffix: string;
    offset: int;
    unit: var NumberUnit;
    error: var Option[ColorParseError]
): bool =
  case suffix.toLowerAscii()
  of "": unit = nuNumber
  of "%": unit = nuPercent
  of "deg": unit = nuDegrees
  of "grad": unit = nuGradians
  of "rad": unit = nuRadians
  of "turn": unit = nuTurns
  else:
    error.setError(cpekInvalidUnit, offset, "unsupported numeric unit '" &
        suffix & "'")
    return false
  true

proc lexBody(
    body: string;
    baseOffset: int;
    tokens: var seq[Token];
    error: var Option[ColorParseError]
): bool =
  var index = 0
  while index < body.len:
    var separated = false
    while index < body.len and body[index].isAsciiWhitespace:
      separated = true
      inc index
    if index >= body.len:
      break

    let tokenOffset = baseOffset + index
    case body[index]
    of ',':
      tokens.add Token(kind: tkComma, offset: tokenOffset, separated: separated)
      inc index
    of '/':
      tokens.add Token(kind: tkSlash, offset: tokenOffset, separated: separated)
      inc index
    else:
      let start = index
      if body[index] in {'+', '-'}:
        inc index

      var digits = 0
      while index < body.len and body[index].isAsciiDigit:
        inc digits
        inc index
      if index < body.len and body[index] == '.':
        inc index
        while index < body.len and body[index].isAsciiDigit:
          inc digits
          inc index

      if digits > 0:
        if index < body.len and body[index] in {'e', 'E'}:
          let exponentStart = index
          inc index
          if index < body.len and body[index] in {'+', '-'}:
            inc index
          let exponentDigitsStart = index
          while index < body.len and body[index].isAsciiDigit:
            inc index
          if exponentDigitsStart == index:
            error.setError(
              cpekInvalidNumber,
              baseOffset + exponentStart,
              "numeric exponent requires at least one digit"
            )
            return false

        let numberEnd = index
        if index < body.len and body[index] == '%':
          inc index
        else:
          while index < body.len and body[index] in {'a' .. 'z', 'A' .. 'Z'}:
            inc index
        let suffix = body[numberEnd ..< index]
        var unit: NumberUnit
        if not parseUnit(suffix, baseOffset + numberEnd, unit, error):
          return false
        var number: float64
        try:
          number = parseFloat(body[start ..< numberEnd])
        except ValueError:
          error.setError(cpekInvalidNumber, tokenOffset, "invalid numeric color component")
          return false
        if number.classify in {fcNan, fcInf, fcNegInf}:
          error.setError(cpekInvalidNumber, tokenOffset, "color components must be finite")
          return false
        tokens.add Token(
          kind: tkNumber,
          offset: tokenOffset,
          separated: separated,
          text: body[start ..< index],
          number: number,
          unit: unit
        )
      elif body[start].isIdentifierChar:
        index = start
        while index < body.len and body[index].isIdentifierChar:
          inc index
        tokens.add Token(
          kind: tkIdentifier,
          offset: tokenOffset,
          separated: separated,
          text: body[start ..< index].toLowerAscii()
        )
      else:
        error.setError(
          cpekUnexpectedToken,
          tokenOffset,
          "unexpected character '" & $body[index] & "' in color function"
        )
        return false
  true

proc noneToken(token: Token): bool {.inline.} =
  token.kind == tkIdentifier and token.text == "none"

proc ensureModernShape(
    tokens: openArray[Token];
    componentCount: int;
    error: var Option[ColorParseError]
): bool =
  let expectedWithAlpha = componentCount + 2
  if tokens.len notin [componentCount, expectedWithAlpha]:
    let offset = if tokens.len > 0: tokens[0].offset else: 0
    error.setError(
      cpekInvalidArity,
      offset,
      "expected " & $componentCount & " components and optional slash alpha"
    )
    return false
  for index in 1 ..< componentCount:
    if not tokens[index].separated:
      error.setError(
        cpekUnexpectedToken,
        tokens[index].offset,
        "modern color components must be separated by whitespace"
      )
      return false
  if tokens.len == expectedWithAlpha:
    if tokens[componentCount].kind != tkSlash:
      error.setError(
        cpekUnexpectedToken,
        tokens[componentCount].offset,
        "modern color alpha must follow '/'"
      )
      return false
  for index, token in tokens:
    if index != componentCount and token.kind in {tkComma, tkSlash}:
      error.setError(
        cpekUnexpectedToken,
        token.offset,
        "unexpected separator in modern color syntax"
      )
      return false
  true

proc legacyValues(
    tokens: openArray[Token];
    values: var seq[Token];
    error: var Option[ColorParseError]
): bool =
  if tokens.len notin [5, 7]:
    let offset = if tokens.len > 0: tokens[0].offset else: 0
    error.setError(cpekInvalidArity, offset, "legacy color syntax expects 3 or 4 values")
    return false
  for index, token in tokens:
    if index mod 2 == 0:
      if token.kind in {tkComma, tkSlash}:
        error.setError(cpekUnexpectedToken, token.offset, "expected a color component")
        return false
      values.add token
    elif token.kind != tkComma:
      error.setError(cpekUnexpectedToken, token.offset, "legacy values must be comma-separated")
      return false
  true

proc scalarComponent(
    token: Token;
    percentReference: float64;
    label: string;
    value: var float64;
    missing: var bool;
    error: var Option[ColorParseError]
): bool =
  if token.noneToken:
    value = 0
    missing = true
    return true
  if token.kind != tkNumber:
    error.setError(cpekUnexpectedToken, token.offset, label & " must be a number, percentage, or none")
    return false
  case token.unit
  of nuNumber:
    value = token.number
  of nuPercent:
    value = token.number * percentReference / 100.0
  else:
    error.setError(cpekInvalidUnit, token.offset, label & " does not accept an angle unit")
    return false
  true

proc hueComponent(
    token: Token;
    value: var float64;
    missing: var bool;
    error: var Option[ColorParseError]
): bool =
  if token.noneToken:
    value = 0
    missing = true
    return true
  if token.kind != tkNumber:
    error.setError(cpekUnexpectedToken, token.offset, "hue must be an angle, number, or none")
    return false
  case token.unit
  of nuNumber, nuDegrees: value = token.number
  of nuGradians: value = token.number * 0.9
  of nuRadians: value = token.number * 180.0 / PI
  of nuTurns: value = token.number * 360.0
  of nuPercent:
    error.setError(cpekInvalidUnit, token.offset, "hue does not accept percentages")
    return false
  value = value mod 360.0
  if value < 0:
    value += 360.0
  true

proc alphaComponent(
    token: Token;
    alpha: var float64;
    missing: var set[ColorComponent];
    error: var Option[ColorParseError]
): bool =
  var isMissing = false
  if not token.scalarComponent(1.0, "alpha", alpha, isMissing, error):
    return false
  alpha = max(0.0, min(1.0, alpha))
  if isMissing:
    missing.incl ccAlpha
  true

proc parsedComponents(
    space: ColorSpace;
    components: array[3, float64];
    alpha: float64;
    missing: set[ColorComponent]
): Option[ColorValue] =
  some(ColorValue(
    kind: cvComponents,
    space: space,
    components: components,
    alpha: alpha,
    missing: missing
  ))

proc parseRgb(
    tokens: openArray[Token];
    error: var Option[ColorParseError]
): Option[ColorValue] =
  let legacy = tokens.anyIt(it.kind == tkComma)
  var values: seq[Token]
  if legacy:
    if not tokens.legacyValues(values, error):
      return none(ColorValue)
    if values[0].noneToken or values[1].noneToken or values[2].noneToken:
      error.setError(cpekUnexpectedToken, values[0].offset, "legacy rgb does not accept none")
      return none(ColorValue)
    if values.len == 4 and values[3].noneToken:
      error.setError(
        cpekUnexpectedToken,
        values[3].offset,
        "legacy rgb alpha does not accept none"
      )
      return none(ColorValue)
    let firstUnit = values[0].unit
    if firstUnit notin {nuNumber, nuPercent}:
      error.setError(cpekInvalidUnit, values[0].offset, "rgb components require numbers or percentages")
      return none(ColorValue)
    for index in 1 .. 2:
      if values[index].kind != tkNumber or values[index].unit != firstUnit:
        error.setError(
          cpekMixedLegacyUnits,
          values[index].offset,
          "legacy rgb components must be all numbers or all percentages"
        )
        return none(ColorValue)
  else:
    if not tokens.ensureModernShape(3, error):
      return none(ColorValue)
    values = @[tokens[0], tokens[1], tokens[2]]
    if tokens.len == 5:
      values.add tokens[4]

  var components: array[3, float64]
  var missing: set[ColorComponent]
  for index in 0 .. 2:
    let token = values[index]
    if token.noneToken and not legacy:
      missing.incl componentSlots[index]
      components[index] = 0
    elif token.kind != tkNumber or token.unit notin {nuNumber, nuPercent}:
      error.setError(cpekInvalidUnit, token.offset, "rgb components require numbers, percentages, or none")
      return none(ColorValue)
    elif token.unit == nuPercent:
      components[index] = max(0.0, min(1.0, token.number / 100.0))
    else:
      components[index] = max(0.0, min(1.0, token.number / 255.0))

  var alpha = 1.0
  if values.len == 4 and not values[3].alphaComponent(alpha, missing, error):
    return none(ColorValue)
  parsedComponents(csSrgb, components, alpha, missing)

proc parseHsl(
    tokens: openArray[Token];
    error: var Option[ColorParseError]
): Option[ColorValue] =
  let legacy = tokens.anyIt(it.kind == tkComma)
  var values: seq[Token]
  if legacy:
    if not tokens.legacyValues(values, error):
      return none(ColorValue)
    if values[0].noneToken or values[1].noneToken or values[2].noneToken:
      error.setError(cpekUnexpectedToken, values[0].offset, "legacy hsl does not accept none")
      return none(ColorValue)
    if values.len == 4 and values[3].noneToken:
      error.setError(
        cpekUnexpectedToken,
        values[3].offset,
        "legacy hsl alpha does not accept none"
      )
      return none(ColorValue)
    for index in 1 .. 2:
      if values[index].kind != tkNumber or values[index].unit != nuPercent:
        error.setError(cpekInvalidUnit, values[index].offset, "legacy hsl saturation and lightness require percentages")
        return none(ColorValue)
  else:
    if not tokens.ensureModernShape(3, error):
      return none(ColorValue)
    values = @[tokens[0], tokens[1], tokens[2]]
    if tokens.len == 5:
      values.add tokens[4]

  var components: array[3, float64]
  var missing: set[ColorComponent]
  var componentMissing = false
  if not values[0].hueComponent(components[0], componentMissing, error):
    return none(ColorValue)
  if componentMissing:
    missing.incl ccFirst
  for index in 1 .. 2:
    componentMissing = false
    if not values[index].scalarComponent(100.0, "hsl component", components[
        index], componentMissing, error):
      return none(ColorValue)
    components[index] = max(0.0, min(100.0, components[index]))
    if componentMissing:
      missing.incl componentSlots[index]
  var alpha = 1.0
  if values.len == 4 and not values[3].alphaComponent(alpha, missing, error):
    return none(ColorValue)
  parsedComponents(csHsl, components, alpha, missing)

proc parseHwb(
    tokens: openArray[Token];
    error: var Option[ColorParseError]
): Option[ColorValue] =
  if tokens.anyIt(it.kind == tkComma):
    error.setError(cpekUnexpectedToken, tokens[0].offset, "hwb does not support legacy comma syntax")
    return none(ColorValue)
  if not tokens.ensureModernShape(3, error):
    return none(ColorValue)
  var components: array[3, float64]
  var missing: set[ColorComponent]
  var componentMissing = false
  if not tokens[0].hueComponent(components[0], componentMissing, error):
    return none(ColorValue)
  if componentMissing:
    missing.incl ccFirst
  for index in 1 .. 2:
    componentMissing = false
    if not tokens[index].scalarComponent(100.0, "hwb component", components[
        index], componentMissing, error):
      return none(ColorValue)
    components[index] = max(0.0, components[index])
    if componentMissing:
      missing.incl componentSlots[index]
  var alpha = 1.0
  if tokens.len == 5 and not tokens[4].alphaComponent(alpha, missing, error):
    return none(ColorValue)
  parsedComponents(csHwb, components, alpha, missing)

proc parseLabLike(
    functionName: string;
    tokens: openArray[Token];
    error: var Option[ColorParseError]
): Option[ColorValue] =
  if tokens.anyIt(it.kind == tkComma):
    error.setError(cpekUnexpectedToken, tokens[0].offset, functionName & " does not support comma syntax")
    return none(ColorValue)
  if not tokens.ensureModernShape(3, error):
    return none(ColorValue)

  let space = case functionName
    of "lab": csLab
    of "lch": csLch
    of "oklab": csOklab
    else: csOklch
  let polar = space in {csLch, csOklch}
  let oklike = space in {csOklab, csOklch}
  var components: array[3, float64]
  var missing: set[ColorComponent]
  var componentMissing = false

  let lightnessReference = if oklike: 1.0 else: 100.0
  if not tokens[0].scalarComponent(lightnessReference, "lightness", components[
      0], componentMissing, error):
    return none(ColorValue)
  components[0] = max(0.0, min(lightnessReference, components[0]))
  if componentMissing:
    missing.incl ccFirst

  componentMissing = false
  let secondReference =
    if space == csLab: 125.0
    elif space == csLch: 150.0
    else: 0.4
  if not tokens[1].scalarComponent(secondReference, "color component",
      components[1], componentMissing, error):
    return none(ColorValue)
  if polar:
    components[1] = max(0.0, components[1])
  if componentMissing:
    missing.incl ccSecond

  componentMissing = false
  if polar:
    if not tokens[2].hueComponent(components[2], componentMissing, error):
      return none(ColorValue)
  else:
    let thirdReference = if oklike: 0.4 else: 125.0
    if not tokens[2].scalarComponent(thirdReference, "color component",
        components[2], componentMissing, error):
      return none(ColorValue)
  if componentMissing:
    missing.incl ccThird

  var alpha = 1.0
  if tokens.len == 5 and not tokens[4].alphaComponent(alpha, missing, error):
    return none(ColorValue)
  parsedComponents(space, components, alpha, missing)

proc colorSpace(
    token: Token;
    space: var ColorSpace;
    error: var Option[ColorParseError]
): bool =
  if token.kind != tkIdentifier:
    error.setError(cpekUnexpectedToken, token.offset, "color() requires a predefined color-space name")
    return false
  case token.text
  of "srgb": space = csSrgb
  of "srgb-linear": space = csSrgbLinear
  of "display-p3": space = csDisplayP3
  of "display-p3-linear": space = csDisplayP3Linear
  of "a98-rgb": space = csA98Rgb
  of "prophoto-rgb": space = csProPhotoRgb
  of "rec2020": space = csRec2020
  of "xyz", "xyz-d65": space = csXyzD65
  of "xyz-d50": space = csXyzD50
  else:
    error.setError(cpekUnsupportedColorSpace, token.offset,
        "unsupported color space '" & token.text & "'")
    return false
  true

proc parseColorFunction(
    tokens: openArray[Token];
    error: var Option[ColorParseError]
): Option[ColorValue] =
  if tokens.anyIt(it.kind == tkComma):
    error.setError(cpekUnexpectedToken, tokens[0].offset, "color() does not support comma syntax")
    return none(ColorValue)
  if not tokens.ensureModernShape(4, error):
    return none(ColorValue)
  var space: ColorSpace
  if not tokens[0].colorSpace(space, error):
    return none(ColorValue)
  var components: array[3, float64]
  var missing: set[ColorComponent]
  for index in 0 .. 2:
    var componentMissing = false
    if not tokens[index + 1].scalarComponent(1.0, "color() component",
        components[index], componentMissing, error):
      return none(ColorValue)
    if componentMissing:
      missing.incl componentSlots[index]
  var alpha = 1.0
  if tokens.len == 6 and not tokens[5].alphaComponent(alpha, missing, error):
    return none(ColorValue)
  parsedComponents(space, components, alpha, missing)

proc hexDigit(value: char): int =
  case value
  of '0' .. '9': ord(value) - ord('0')
  of 'a' .. 'f': ord(value) - ord('a') + 10
  of 'A' .. 'F': ord(value) - ord('A') + 10
  else: -1

proc parseHexColor(
    source: string;
    baseOffset: int;
    error: var Option[ColorParseError]
): Option[ColorValue] =
  if source.len notin [4, 5, 7, 9]:
    error.setError(
      cpekInvalidHex,
      baseOffset,
      "hex colors require 3, 4, 6, or 8 hexadecimal digits"
    )
    return none(ColorValue)
  for index in 1 ..< source.len:
    if source[index].hexDigit < 0:
      error.setError(cpekInvalidHex, baseOffset + index, "invalid hexadecimal color digit")
      return none(ColorValue)

  var channels: array[4, int]
  channels[3] = 255
  if source.len in [4, 5]:
    for index in 0 ..< source.len - 1:
      let digit = source[index + 1].hexDigit
      channels[index] = digit * 17
  else:
    for index in 0 ..< (source.len - 1) div 2:
      channels[index] = source[index * 2 + 1].hexDigit * 16 + source[index * 2 + 2].hexDigit
  parsedComponents(
    csSrgb,
    [channels[0].float64 / 255.0, channels[1].float64 / 255.0,
      channels[2].float64 / 255.0],
    channels[3].float64 / 255.0,
    {}
  )

proc parseNamedColor(
    source: string;
    baseOffset: int;
    error: var Option[ColorParseError]
): Option[ColorValue] =
  let keyword = source.toLowerAscii()
  if keyword == "transparent":
    return parsedComponents(csSrgb, [0.0, 0.0, 0.0], 0.0, {})
  if keyword == "currentcolor":
    return some(currentColor())
  try:
    let named = colors.parseColor(keyword)
    let packed = uint32(int(named))
    parsedComponents(
      csSrgb,
      [
        float64((packed shr 16) and 0xff'u32) / 255.0,
        float64((packed shr 8) and 0xff'u32) / 255.0,
        float64(packed and 0xff'u32) / 255.0
      ],
      1.0,
      {}
    )
  except ValueError:
    error.setError(cpekUnknownColor, baseOffset, "unknown color '" & source & "'")
    none(ColorValue)

proc parseColor*(input: string): ColorParseResult =
  var first = 0
  while first < input.len and input[first].isAsciiWhitespace:
    inc first
  if first == input.len:
    result.error = some(ColorParseError(
      kind: cpekEmpty,
      offset: first,
      message: "color value is empty"
    ))
    return
  var last = input.high
  while last >= first and input[last].isAsciiWhitespace:
    dec last
  let source = input[first .. last]
  var error: Option[ColorParseError]

  if source[0] == '#':
    result.value = source.parseHexColor(first, error)
    result.error = error
    return

  let openParen = source.find('(')
  if openParen < 0:
    result.value = source.parseNamedColor(first, error)
    result.error = error
    return
  if source[^1] != ')':
    result.error = some(ColorParseError(
      kind: cpekTrailingInput,
      offset: first + openParen,
      message: "color function must end with ')' and contain no trailing input"
    ))
    return
  if source.find(')', openParen + 1) != source.high:
    result.error = some(ColorParseError(
      kind: cpekTrailingInput,
      offset: first + openParen + 1,
      message: "nested or trailing color-function input is not supported"
    ))
    return

  let functionName = source[0 ..< openParen].toLowerAscii()
  if functionName.len == 0 or functionName.anyIt(not it.isIdentifierChar):
    result.error = some(ColorParseError(
      kind: cpekUnknownFunction,
      offset: first,
      message: "invalid color-function name"
    ))
    return
  var tokens: seq[Token]
  let body = source[openParen + 1 ..< source.high]
  if not body.lexBody(first + openParen + 1, tokens, error):
    result.error = error
    return
  if tokens.len == 0:
    result.error = some(ColorParseError(
      kind: cpekInvalidArity,
      offset: first + openParen + 1,
      message: "color function requires components"
    ))
    return

  case functionName
  of "rgb", "rgba": result.value = tokens.parseRgb(error)
  of "hsl", "hsla": result.value = tokens.parseHsl(error)
  of "hwb": result.value = tokens.parseHwb(error)
  of "lab", "lch", "oklab", "oklch":
    result.value = functionName.parseLabLike(tokens, error)
  of "color": result.value = tokens.parseColorFunction(error)
  else:
    error.setError(
      cpekUnknownFunction,
      first,
      "unsupported color function '" & functionName & "'"
    )
  result.error = error

proc parseColorOrRaise*(input: string): ColorValue =
  let parsed = parseColor(input)
  if parsed.value.isSome:
    return parsed.value.get
  let diagnostic = parsed.error.get
  raise newException(
    ValueError,
    diagnostic.message & " at byte offset " & $diagnostic.offset
  )
