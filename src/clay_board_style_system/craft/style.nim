import std/[algorithm, json, math, options, sets, strutils]

import ../core/[
  color_conversion,
  color_mix_parser,
  color_parser,
  declaration,
  node,
  registry,
  rule,
  selector,
  style_value
]
import ../generated/default_properties

const
  craftStyleFormat* = "cbss-craft-style"
  craftStyleFormatVersion* = 1
  maxCraftStyleSourceBytes* = 8 * 1024 * 1024
  maxCraftStyleJsonDepth* = 32
  maxCraftStyleRules* = 10_000
  maxCraftStyleDeclarationsPerRule* = 4_096
  maxCraftStyleSelectorItems* = 1_024
  maxCraftStyleGradientStops* = 4_096
  maxCraftStyleTransformOperations* = 4_096

type
  CraftStyleDiagnosticCode* = enum
    csdcInvalidJson,
    csdcInvalidDocument,
    csdcUnsupportedVersion,
    csdcMissingField,
    csdcUnknownField,
    csdcInvalidType,
    csdcInvalidValue,
    csdcUnknownProperty,
    csdcDuplicateField,
    csdcLimitExceeded

  CraftStyleDiagnostic* = object
    code*: CraftStyleDiagnosticCode
    path*: string
    message*: string

  CraftStyle* = object
    name*: string
    sheet*: StyleSheet
    normalizedJson*: string

  CraftStyleParseResult* = object
    value*: Option[CraftStyle]
    diagnostics*: seq[CraftStyleDiagnostic]

proc isOk*(parsed: CraftStyleParseResult): bool {.inline.} =
  parsed.value.isSome and parsed.diagnostics.len == 0

proc addDiagnostic(
    parsed: var CraftStyleParseResult;
    code: CraftStyleDiagnosticCode;
    path, message: string
)

proc sourceWithinLimits(
    source: string;
    parsed: var CraftStyleParseResult
): bool =
  if source.len > maxCraftStyleSourceBytes:
    parsed.addDiagnostic(
      csdcLimitExceeded,
      "$",
      "Craft Style source exceeds the byte limit"
    )
    return false

  var depth = 0
  var inString = false
  var escaped = false
  for character in source:
    if inString:
      if escaped:
        escaped = false
      elif character == '\\':
        escaped = true
      elif character == '"':
        inString = false
    else:
      case character
      of '"':
        inString = true
      of '{', '[':
        inc depth
        if depth > maxCraftStyleJsonDepth:
          parsed.addDiagnostic(
            csdcLimitExceeded,
            "$",
            "Craft Style JSON exceeds the nesting-depth limit"
          )
          return false
      of '}', ']':
        dec depth
      else:
        discard

  type SourceContainer = object
    kind: char
    fields: HashSet[string]

  var containers: seq[SourceContainer]
  var index = 0
  while index < source.len:
    case source[index]
    of '{':
      containers.add SourceContainer(kind: '{', fields: initHashSet[string]())
    of '[':
      containers.add SourceContainer(kind: '[')
    of '}', ']':
      if containers.len > 0:
        discard containers.pop()
    of '"':
      let start = index
      inc index
      var escaped = false
      while index < source.len:
        if escaped:
          escaped = false
        elif source[index] == '\\':
          escaped = true
        elif source[index] == '"':
          break
        inc index
      if index < source.len and containers.len > 0 and
          containers[^1].kind == '{':
        var following = index + 1
        while following < source.len and source[following] in Whitespace:
          inc following
        if following < source.len and source[following] == ':':
          try:
            let field = parseJson(source[start .. index]).getStr
            if field in containers[^1].fields:
              parsed.addDiagnostic(
                csdcDuplicateField,
                "$",
                "duplicate field '" & field & "'"
              )
              return false
            containers[^1].fields.incl field
          except JsonParsingError:
            discard
    else:
      discard
    inc index
  true

proc canonicalJson(node: JsonNode): string =
  case node.kind
  of JObject:
    var keys: seq[string]
    for key in node.keys:
      keys.add key
    keys.sort()
    result.add '{'
    for index, key in keys:
      if index > 0:
        result.add ','
      result.add $newJString(key)
      result.add ':'
      result.add canonicalJson(node[key])
    result.add '}'
  of JArray:
    result.add '['
    for index in 0 ..< node.len:
      if index > 0:
        result.add ','
      result.add canonicalJson(node[index])
    result.add ']'
  else:
    result = $node

proc addDiagnostic(
    parsed: var CraftStyleParseResult;
    code: CraftStyleDiagnosticCode;
    path, message: string
) =
  parsed.diagnostics.add CraftStyleDiagnostic(
    code: code,
    path: path,
    message: message
  )

proc checkFields(
    node: JsonNode;
    path: string;
    allowed: openArray[string];
    parsed: var CraftStyleParseResult
) =
  if node.kind != JObject:
    return
  let allowedSet = allowed.toHashSet
  for key in node.keys:
    if key notin allowedSet:
      parsed.addDiagnostic(
        csdcUnknownField,
        path & "." & key,
        "unknown field"
      )

proc requiredField(
    node: JsonNode;
    name, path: string;
    parsed: var CraftStyleParseResult
): JsonNode =
  if node.kind != JObject or not node.hasKey(name):
    parsed.addDiagnostic(
      csdcMissingField,
      path & "." & name,
      "required field is missing"
    )
    return nil
  node[name]

proc parseString(
    node: JsonNode;
    path: string;
    parsed: var CraftStyleParseResult
): Option[string] =
  if node.isNil or node.kind != JString:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a string")
    return none(string)
  some(node.getStr)

proc parseNumber(
    node: JsonNode;
    path: string;
    parsed: var CraftStyleParseResult
): Option[float32] =
  if node.isNil or node.kind notin {JInt, JFloat}:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a finite number")
    return none(float32)
  let value = node.getFloat
  if value.classify in {fcNan, fcInf, fcNegInf}:
    parsed.addDiagnostic(csdcInvalidValue, path, "number must be finite")
    return none(float32)
  some(value.float32)

proc parseInteger(
    node: JsonNode;
    path: string;
    parsed: var CraftStyleParseResult
): Option[int] =
  if node.isNil or node.kind != JInt:
    parsed.addDiagnostic(csdcInvalidType, path, "expected an integer")
    return none(int)
  let value = node.getBiggestInt
  if value < BiggestInt(low(int32)) or value > BiggestInt(high(int32)):
    parsed.addDiagnostic(csdcInvalidValue, path, "integer is outside the supported range")
    return none(int)
  some(int(value))

proc parseUnit(
    value, path: string;
    parsed: var CraftStyleParseResult
): Option[UnitKind] =
  let unit = case value
  of "px": some(ukPx)
  of "percent": some(ukPercent)
  of "em": some(ukEm)
  of "rem": some(ukRem)
  of "fill": some(ukFill)
  of "content": some(ukContent)
  of "min-content": some(ukMinContent)
  of "max-content": some(ukMaxContent)
  of "fit-content": some(ukFitContent)
  of "auto": some(ukAuto)
  of "none": some(ukNone)
  of "vw": some(ukVw)
  of "vh": some(ukVh)
  of "vmin": some(ukVmin)
  of "vmax": some(ukVmax)
  of "lh": some(ukLh)
  of "rlh": some(ukRlh)
  of "ex": some(ukEx)
  of "ch": some(ukCh)
  of "rex": some(ukRex)
  of "rch": some(ukRch)
  else: none(UnitKind)
  if unit.isNone:
    parsed.addDiagnostic(csdcInvalidValue, path, "unknown length unit '" &
        value & "'")
  unit

proc lengthValue(kind: UnitKind; value: float32): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: kind, value: value))

proc parseLength(
    node: JsonNode;
    path: string;
    parsed: var CraftStyleParseResult
): Option[StyleValue] =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a length object")
    return none(StyleValue)
  node.checkFields(path, ["type", "unit", "value"], parsed)
  let unitText = parseString(node.requiredField("unit", path, parsed), path &
      ".unit", parsed)
  if unitText.isNone:
    return none(StyleValue)
  let unit = parseUnit(unitText.get, path & ".unit", parsed)
  if unit.isNone:
    return none(StyleValue)
  let valueRequired = unit.get notin {
    ukContent, ukMinContent, ukMaxContent, ukFitContent, ukAuto, ukNone
  }
  if not valueRequired:
    if node.hasKey("value"):
      let value = parseNumber(node["value"], path & ".value", parsed)
      if value.isSome and value.get != 0.0'f32:
        parsed.addDiagnostic(
          csdcInvalidValue,
          path & ".value",
          "keyword length units require zero or an omitted value"
        )
        return none(StyleValue)
    return some(lengthValue(unit.get, 0.0'f32))
  let value = parseNumber(node.requiredField("value", path, parsed), path &
      ".value", parsed)
  if value.isNone:
    return none(StyleValue)
  some(lengthValue(unit.get, value.get))

proc parseColorStyleValue(
    text, path: string;
    parsed: var CraftStyleParseResult
): Option[StyleValue] =
  if text.strip.toLowerAscii.startsWith("color-mix("):
    let mixed = parseColorMix(text)
    if mixed.isOk:
      return some(colorValue(mixed.value.get))
    let message = if mixed.error.isSome: mixed.error.get.message else: "invalid color mix"
    parsed.addDiagnostic(csdcInvalidValue, path, message)
    return none(StyleValue)
  let color = parseColor(text)
  if color.isOk:
    return some(colorValue(color.value.get))
  let message = if color.error.isSome: color.error.get.message else: "invalid color"
  parsed.addDiagnostic(csdcInvalidValue, path, message)
  none(StyleValue)

proc parseRequiredColor(
    node: JsonNode;
    field, path: string;
    parsed: var CraftStyleParseResult
): Option[StyleValue] =
  let text = parseString(node.requiredField(field, path, parsed), path & "." &
      field, parsed)
  if text.isNone:
    return none(StyleValue)
  parseColorStyleValue(text.get, path & "." & field, parsed)

proc parseInterpolationSpace(
    value, path: string;
    parsed: var CraftStyleParseResult
): Option[ColorInterpolationSpace] =
  result = case value
  of "srgb": some(cisSrgb)
  of "srgb-linear": some(cisSrgbLinear)
  of "oklab": some(cisOklab)
  else: none(ColorInterpolationSpace)
  if result.isNone:
    parsed.addDiagnostic(csdcInvalidValue, path,
        "unsupported interpolation space '" & value & "'")

proc parseTransformOperation(
    node: JsonNode;
    path: string;
    parsed: var CraftStyleParseResult
): Option[StyleValue] =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a transform operation object")
    return none(StyleValue)
  let operation = parseString(node.requiredField("type", path, parsed), path &
      ".type", parsed)
  if operation.isNone:
    return none(StyleValue)
  case operation.get
  of "translate":
    node.checkFields(path, ["type", "x", "y", "z"], parsed)
    let x = parseLength(node.requiredField("x", path, parsed), path & ".x", parsed)
    let y = parseLength(node.requiredField("y", path, parsed), path & ".y", parsed)
    if x.isNone or y.isNone:
      return none(StyleValue)
    var z = none(StyleValue)
    if node.hasKey("z"):
      z = parseLength(node["z"], path & ".z", parsed)
      if z.isNone:
        return none(StyleValue)
    some(translate(x.get, y.get, z))
  of "scale":
    node.checkFields(path, ["type", "x", "y", "z"], parsed)
    let x = parseNumber(node.requiredField("x", path, parsed), path & ".x", parsed)
    if x.isNone:
      return none(StyleValue)
    var y = none(float32)
    var z = none(float32)
    if node.hasKey("y"):
      y = parseNumber(node["y"], path & ".y", parsed)
      if y.isNone:
        return none(StyleValue)
    if node.hasKey("z"):
      z = parseNumber(node["z"], path & ".z", parsed)
      if z.isNone:
        return none(StyleValue)
    some(scale(x.get, y, z))
  of "rotate":
    node.checkFields(path, ["type", "angle"], parsed)
    let angle = parseNumber(node.requiredField("angle", path, parsed), path &
        ".angle", parsed)
    if angle.isNone:
      return none(StyleValue)
    some(rotate(angle.get))
  else:
    parsed.addDiagnostic(csdcInvalidValue, path & ".type",
        "unknown transform operation '" & operation.get & "'")
    none(StyleValue)

proc parseStyleValue(
    node: JsonNode;
    path: string;
    parsed: var CraftStyleParseResult
): Option[StyleValue] =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a typed Style value object")
    return none(StyleValue)
  let valueType = parseString(node.requiredField("type", path, parsed), path &
      ".type", parsed)
  if valueType.isNone:
    return none(StyleValue)
  case valueType.get
  of "length":
    parseLength(node, path, parsed)
  of "number":
    node.checkFields(path, ["type", "value"], parsed)
    let value = parseNumber(node.requiredField("value", path, parsed), path &
        ".value", parsed)
    if value.isSome: some(number(value.get)) else: none(StyleValue)
  of "keyword":
    node.checkFields(path, ["type", "value"], parsed)
    let value = parseString(node.requiredField("value", path, parsed), path &
        ".value", parsed)
    if value.isSome: some(keyword(value.get)) else: none(StyleValue)
  of "color":
    node.checkFields(path, ["type", "value"], parsed)
    let value = parseString(node.requiredField("value", path, parsed), path &
        ".value", parsed)
    if value.isSome:
      parseColorStyleValue(value.get, path & ".value", parsed)
    else:
      none(StyleValue)
  of "color-pair":
    node.checkFields(path, ["type", "first", "second"], parsed)
    let firstText = parseString(node.requiredField("first", path, parsed),
        path & ".first", parsed)
    let secondText = parseString(node.requiredField("second", path, parsed),
        path & ".second", parsed)
    if firstText.isNone or secondText.isNone:
      return none(StyleValue)
    let first = parseColor(firstText.get)
    let second = parseColor(secondText.get)
    if not first.isOk:
      parsed.addDiagnostic(csdcInvalidValue, path & ".first",
          first.error.get.message)
    if not second.isOk:
      parsed.addDiagnostic(csdcInvalidValue, path & ".second",
          second.error.get.message)
    if first.isOk and second.isOk:
      some(colorPairValue(first.value.get, second.value.get))
    else:
      none(StyleValue)
  of "border":
    node.checkFields(path, ["type", "width", "style", "color"], parsed)
    var width = none(StyleValue)
    var lineStyle = none(StyleValue)
    var lineColor = none(StyleValue)
    if node.hasKey("width"):
      width = parseLength(node["width"], path & ".width", parsed)
    if node.hasKey("style"):
      let value = parseString(node["style"], path & ".style", parsed)
      if value.isSome:
        lineStyle = some(keyword(value.get))
    if node.hasKey("color"):
      lineColor = parseRequiredColor(node, "color", path, parsed)
    if (node.hasKey("width") and width.isNone) or
        (node.hasKey("style") and lineStyle.isNone) or
        (node.hasKey("color") and lineColor.isNone):
      none(StyleValue)
    else:
      some(borderValue(width, lineStyle, lineColor))
  of "shadow":
    node.checkFields(path, ["type", "offset-x", "offset-y", "blur", "spread",
        "color"], parsed)
    let offsetX = parseLength(node.requiredField("offset-x", path, parsed),
        path & ".offset-x", parsed)
    let offsetY = parseLength(node.requiredField("offset-y", path, parsed),
        path & ".offset-y", parsed)
    if offsetX.isNone or offsetY.isNone:
      return none(StyleValue)
    var blur = none(StyleValue)
    var spread = none(StyleValue)
    if node.hasKey("blur"):
      blur = parseLength(node["blur"], path & ".blur", parsed)
      if blur.isNone:
        return none(StyleValue)
    if node.hasKey("spread"):
      spread = parseLength(node["spread"], path & ".spread", parsed)
      if spread.isNone:
        return none(StyleValue)
    if not node.hasKey("color"):
      return some(shadowValue(offsetX.get, offsetY.get, blur, spread))
    let colorText = parseString(node["color"], path & ".color", parsed)
    if colorText.isNone:
      return none(StyleValue)
    if colorText.get.strip.toLowerAscii.startsWith("color-mix("):
      let mixed = parseColorMix(colorText.get)
      if mixed.isOk:
        return some(shadowValue(offsetX.get, offsetY.get, mixed.value.get, blur, spread))
      parsed.addDiagnostic(csdcInvalidValue, path & ".color",
          mixed.error.get.message)
      return none(StyleValue)
    let color = parseColor(colorText.get)
    if color.isOk:
      some(shadowValue(offsetX.get, offsetY.get, color.value.get, blur, spread))
    else:
      parsed.addDiagnostic(csdcInvalidValue, path & ".color",
          color.error.get.message)
      none(StyleValue)
  of "linear-gradient":
    node.checkFields(path, ["type", "angle", "space", "stops"], parsed)
    let angle = parseNumber(node.requiredField("angle", path, parsed), path &
        ".angle", parsed)
    if angle.isNone:
      return none(StyleValue)
    var space = some(cisSrgb)
    if node.hasKey("space"):
      let text = parseString(node["space"], path & ".space", parsed)
      if text.isNone:
        return none(StyleValue)
      space = parseInterpolationSpace(text.get, path & ".space", parsed)
      if space.isNone:
        return none(StyleValue)
    let stopsNode = node.requiredField("stops", path, parsed)
    if stopsNode.isNil or stopsNode.kind != JArray:
      parsed.addDiagnostic(csdcInvalidType, path & ".stops", "expected an array of gradient stops")
      return none(StyleValue)
    if stopsNode.len < 2:
      parsed.addDiagnostic(csdcInvalidValue, path & ".stops", "a gradient requires at least two stops")
      return none(StyleValue)
    if stopsNode.len > maxCraftStyleGradientStops:
      parsed.addDiagnostic(csdcLimitExceeded, path & ".stops", "too many gradient stops")
      return none(StyleValue)
    var stops: seq[GradientValueStop]
    var valid = true
    for index in 0 ..< stopsNode.len:
      let stopNode = stopsNode[index]
      let stopPath = path & ".stops[" & $index & "]"
      if stopNode.kind != JObject:
        parsed.addDiagnostic(csdcInvalidType, stopPath, "expected a gradient stop object")
        valid = false
        continue
      stopNode.checkFields(stopPath, ["color", "offset"], parsed)
      let colorText = parseString(stopNode.requiredField("color", stopPath,
          parsed), stopPath & ".color", parsed)
      let offset = parseNumber(stopNode.requiredField("offset", stopPath,
          parsed), stopPath & ".offset", parsed)
      if colorText.isNone or offset.isNone:
        valid = false
        continue
      if offset.get < 0.0'f32 or offset.get > 1.0'f32:
        parsed.addDiagnostic(csdcInvalidValue, stopPath & ".offset", "gradient offset must be between zero and one")
        valid = false
        continue
      if colorText.get.strip.toLowerAscii.startsWith("color-mix("):
        let mixed = parseColorMix(colorText.get)
        if mixed.isOk:
          stops.add colorStop(mixed.value.get, offset.get)
        else:
          parsed.addDiagnostic(csdcInvalidValue, stopPath & ".color",
              mixed.error.get.message)
          valid = false
      else:
        let color = parseColor(colorText.get)
        if color.isOk:
          stops.add colorStop(color.value.get, offset.get)
        else:
          parsed.addDiagnostic(csdcInvalidValue, stopPath & ".color",
              color.error.get.message)
          valid = false
    if valid:
      some(StyleValue(
        kind: svLinearGradient,
        gradientAngle: angle.get,
        gradientInterpolationSpace: space.get,
        gradientStops: stops
      ))
    else:
      none(StyleValue)
  of "transform":
    node.checkFields(path, ["type", "operations"], parsed)
    let operationsNode = node.requiredField("operations", path, parsed)
    if operationsNode.isNil or operationsNode.kind != JArray:
      parsed.addDiagnostic(csdcInvalidType, path & ".operations", "expected an array")
      return none(StyleValue)
    if operationsNode.len > maxCraftStyleTransformOperations:
      parsed.addDiagnostic(csdcLimitExceeded, path & ".operations", "too many transform operations")
      return none(StyleValue)
    var operations: seq[StyleValue]
    var valid = true
    for index in 0 ..< operationsNode.len:
      let operationNode = operationsNode[index]
      let operation = parseTransformOperation(
        operationNode,
        path & ".operations[" & $index & "]",
        parsed
      )
      if operation.isSome:
        operations.add operation.get
      else:
        valid = false
    if valid:
      var value = StyleValue(kind: svTransform)
      for operation in operations:
        value.transformOperations.add operation.transformOperation
      some(value)
    else:
      none(StyleValue)
  else:
    parsed.addDiagnostic(csdcInvalidValue, path & ".type",
        "unsupported Style value type '" & valueType.get & "'")
    none(StyleValue)

proc parseState(
    value, path: string;
    parsed: var CraftStyleParseResult
): Option[ElementState] =
  result = case value
  of "hover": some(esHover)
  of "active": some(esActive)
  of "focus": some(esFocus)
  of "focus-visible": some(esFocusVisible)
  of "disabled": some(esDisabled)
  of "checked": some(esChecked)
  of "selected": some(esSelected)
  of "open": some(esOpen)
  of "invalid": some(esInvalid)
  else: none(ElementState)
  if result.isNone:
    parsed.addDiagnostic(csdcInvalidValue, path, "unknown element state '" &
        value & "'")

proc parseSelector(
    node: JsonNode;
    path: string;
    parsed: var CraftStyleParseResult
): Option[SelectorCondition] =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a selector object")
    return none(SelectorCondition)
  node.checkFields(path, ["element", "id", "code", "groups", "attributes",
      "states"], parsed)
  result = some(selector())
  if node.hasKey("element"):
    let value = parseString(node["element"], path & ".element", parsed)
    if value.isNone:
      return none(SelectorCondition)
    result.get.elementKind = case value.get
    of "box": some(nkBox)
    of "text": some(nkText)
    of "image": some(nkImage)
    else:
      parsed.addDiagnostic(csdcInvalidValue, path & ".element",
          "unknown element kind '" & value.get & "'")
      return none(SelectorCondition)
  if node.hasKey("id"):
    let value = parseString(node["id"], path & ".id", parsed)
    if value.isNone:
      return none(SelectorCondition)
    result.get.id = some(value.get)
  if node.hasKey("code"):
    let value = parseString(node["code"], path & ".code", parsed)
    if value.isNone:
      return none(SelectorCondition)
    result.get.code = some(value.get)
  for field in ["groups", "states"]:
    if not node.hasKey(field):
      continue
    if node[field].kind != JArray:
      parsed.addDiagnostic(csdcInvalidType, path & "." & field, "expected an array")
      return none(SelectorCondition)
    if node[field].len > maxCraftStyleSelectorItems:
      parsed.addDiagnostic(csdcLimitExceeded, path & "." & field, "too many selector items")
      return none(SelectorCondition)
    for index in 0 ..< node[field].len:
      let item = node[field][index]
      let itemPath = path & "." & field & "[" & $index & "]"
      let value = parseString(item, itemPath, parsed)
      if value.isNone:
        return none(SelectorCondition)
      if field == "groups":
        result.get.groups.add value.get
      else:
        let state = parseState(value.get, itemPath, parsed)
        if state.isNone:
          return none(SelectorCondition)
        result.get.requiredStates.incl state.get
  if node.hasKey("attributes"):
    if node["attributes"].kind != JObject:
      parsed.addDiagnostic(csdcInvalidType, path & ".attributes", "expected an object")
      return none(SelectorCondition)
    if node["attributes"].len > maxCraftStyleSelectorItems:
      parsed.addDiagnostic(csdcLimitExceeded, path & ".attributes",
          "too many selector items")
      return none(SelectorCondition)
    for name, value in node["attributes"]:
      if value.kind == JNull:
        result.get.attrs.add attrExists(name)
      elif value.kind == JString:
        result.get.attrs.add attr(name, value.getStr)
      else:
        parsed.addDiagnostic(
          csdcInvalidType,
          path & ".attributes." & name,
          "attribute selector values must be strings or null"
        )
        return none(SelectorCondition)

proc parseDeclaration(
    node: JsonNode;
    path: string;
    sourceOrder: int;
    registry: PropertyRegistry;
    parsed: var CraftStyleParseResult
): Option[Declaration] =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a declaration object")
    return none(Declaration)
  node.checkFields(path, ["property", "operation", "value"], parsed)
  let property = parseString(node.requiredField("property", path, parsed),
      path & ".property", parsed)
  if property.isNone:
    return none(Declaration)
  if not registry.hasProperty(property.get):
    parsed.addDiagnostic(csdcUnknownProperty, path & ".property",
        "unknown style property '" & property.get & "'")
    return none(Declaration)
  var operationName = "overwrite"
  if node.hasKey("operation"):
    let value = parseString(node["operation"], path & ".operation", parsed)
    if value.isNone:
      return none(Declaration)
    operationName = value.get
  case operationName
  of "overwrite", "relative":
    let value = parseStyleValue(node.requiredField("value", path, parsed),
        path & ".value", parsed)
    if value.isNone:
      return none(Declaration)
    let operation = if operationName == "relative": relative(
        value.get) else: overwrite(value.get)
    some(decl(property.get, operation, sourceOrder))
  of "inherit", "initial", "unset":
    if node.hasKey("value"):
      parsed.addDiagnostic(csdcInvalidValue, path & ".value", "this operation does not accept a value")
      return none(Declaration)
    let operation = case operationName
    of "inherit": inherit()
    of "initial": initial()
    else: unset()
    some(decl(property.get, operation, sourceOrder))
  else:
    parsed.addDiagnostic(csdcInvalidValue, path & ".operation",
        "unknown Style operation '" & operationName & "'")
    none(Declaration)

proc parseRule(
    node: JsonNode;
    path: string;
    sourceOrder: int;
    registry: PropertyRegistry;
    parsed: var CraftStyleParseResult
): Option[StyleRule] =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(csdcInvalidType, path, "expected a rule object")
    return none(StyleRule)
  node.checkFields(path, ["selector", "priority", "declarations"], parsed)
  let condition = parseSelector(node.requiredField("selector", path, parsed),
      path & ".selector", parsed)
  var priority = 0
  if node.hasKey("priority"):
    let value = parseInteger(node["priority"], path & ".priority", parsed)
    if value.isNone:
      return none(StyleRule)
    priority = value.get
  let declarationsNode = node.requiredField("declarations", path, parsed)
  if declarationsNode.isNil or declarationsNode.kind != JArray:
    parsed.addDiagnostic(csdcInvalidType, path & ".declarations", "expected an array")
    return none(StyleRule)
  if declarationsNode.len == 0:
    parsed.addDiagnostic(csdcInvalidValue, path & ".declarations", "a rule requires at least one declaration")
    return none(StyleRule)
  if declarationsNode.len > maxCraftStyleDeclarationsPerRule:
    parsed.addDiagnostic(csdcLimitExceeded, path & ".declarations", "too many declarations")
    return none(StyleRule)
  var declarations: seq[Declaration]
  var valid = condition.isSome
  for index in 0 ..< declarationsNode.len:
    let declarationNode = declarationsNode[index]
    let declaration = parseDeclaration(
      declarationNode,
      path & ".declarations[" & $index & "]",
      index,
      registry,
      parsed
    )
    if declaration.isSome:
      declarations.add declaration.get
    else:
      valid = false
  if valid:
    some(rule(condition.get, declarations, priority, sourceOrder))
  else:
    none(StyleRule)

proc parseCraftStyle*(source: string): CraftStyleParseResult =
  if not sourceWithinLimits(source, result):
    return
  var document: JsonNode
  try:
    document = parseJson(source)
  except JsonParsingError as error:
    result.addDiagnostic(csdcInvalidJson, "$", error.msg)
    return
  if document.kind != JObject:
    result.addDiagnostic(csdcInvalidDocument, "$", "Craft Style document must be an object")
    return
  document.checkFields("$", ["format", "version", "name", "rules"], result)
  let format = parseString(document.requiredField("format", "$", result),
      "$.format", result)
  if format.isSome and format.get != craftStyleFormat:
    result.addDiagnostic(csdcInvalidValue, "$.format", "unsupported format '" &
        format.get & "'")
  let versionNode = document.requiredField("version", "$", result)
  if not versionNode.isNil:
    if versionNode.kind != JInt:
      result.addDiagnostic(csdcInvalidType, "$.version", "expected an integer")
    elif versionNode.getInt != craftStyleFormatVersion:
      result.addDiagnostic(
        csdcUnsupportedVersion,
        "$.version",
        "unsupported Craft Style version " & $versionNode.getInt
      )
  let name = parseString(document.requiredField("name", "$", result), "$.name", result)
  if name.isSome and name.get.len == 0:
    result.addDiagnostic(csdcInvalidValue, "$.name", "name must not be empty")
  let rulesNode = document.requiredField("rules", "$", result)
  let registry = defaultProperties()
  var rules: seq[StyleRule]
  if not rulesNode.isNil:
    if rulesNode.kind != JArray:
      result.addDiagnostic(csdcInvalidType, "$.rules", "expected an array")
    elif rulesNode.len > maxCraftStyleRules:
      result.addDiagnostic(csdcLimitExceeded, "$.rules", "too many rules")
    else:
      for index in 0 ..< rulesNode.len:
        let ruleNode = rulesNode[index]
        let parsedRule = parseRule(
          ruleNode,
          "$.rules[" & $index & "]",
          index,
          registry,
          result
        )
        if parsedRule.isSome:
          rules.add parsedRule.get
  if result.diagnostics.len == 0 and name.isSome:
    result.value = some(CraftStyle(
      name: name.get,
      sheet: styleSheet(rules),
      normalizedJson: canonicalJson(document)
    ))
