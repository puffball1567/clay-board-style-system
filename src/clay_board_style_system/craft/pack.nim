import std/[algorithm, json, options, sets, strutils]

import ../generated/craft_driver_contract

const
  craftPackFormat* = "cbss-craft-pack"
  craftPackFormatVersion* = 1
  maxCraftPackSourceBytes* = 4 * 1024 * 1024
  maxCraftPackJsonDepth* = 24
  maxCraftPackComponents* = 4_096
  maxCraftPackSlotsPerComponent* = 1_024
  maxCraftPackStyles* = 4_096
  maxCraftPackAssets* = 65_536
  maxCraftPackCapabilities* = 1_024
  maxCraftPackProfiles* = 1_024
  maxCraftPackPlatforms* = 1_024
  maxCraftPackStringBytes* = 65_536

type
  CraftPackDiagnosticCode* = enum
    cpdcInvalidJson,
    cpdcInvalidDocument,
    cpdcUnsupportedVersion,
    cpdcMissingField,
    cpdcUnknownField,
    cpdcInvalidType,
    cpdcInvalidValue,
    cpdcDuplicateField,
    cpdcDuplicateValue,
    cpdcLimitExceeded,
    cpdcIncompatibleAbi,
    cpdcIncompatibleDriverContract,
    cpdcMissingCapability

  CraftPackDiagnostic* = object
    code*: CraftPackDiagnosticCode
    path*: string
    message*: string

  CraftPackCapabilityRequirement* = object
    id*: uint32
    minimumVersion*: uint32

  CraftPackCompatibility* = object
    minimumAbi*: uint32
    maximumAbi*: Option[uint32]
    minimumDriverContract*: uint32
    maximumDriverContract*: Option[uint32]
    capabilities*: seq[CraftPackCapabilityRequirement]

  CraftPackComponent* = object
    name*: string
    slots*: seq[string]

  CraftPackStyleAsset* = object
    name*: string
    path*: string
    sha256*: string

  CraftPackAssetKind* = enum
    cpakFont,
    cpakImage,
    cpakShader,
    cpakBinary

  CraftPackAsset* = object
    id*: string
    kind*: CraftPackAssetKind
    path*: string
    mimeType*: Option[string]
    sha256*: string
    required*: bool

  CraftPackFeatureProfile* = object
    name*: string
    capabilities*: seq[CraftPackCapabilityRequirement]

  CraftPack* = object
    id*: string
    version*: string
    compatibility*: CraftPackCompatibility
    components*: seq[CraftPackComponent]
    styles*: seq[CraftPackStyleAsset]
    assets*: seq[CraftPackAsset]
    profiles*: seq[CraftPackFeatureProfile]
    platforms*: seq[string]
    normalizedJson*: string

  CraftPackParseResult* = object
    value*: Option[CraftPack]
    diagnostics*: seq[CraftPackDiagnostic]

  CraftPackLoadResult* = object
    loaded*: bool
    diagnostics*: seq[CraftPackDiagnostic]

  CraftPackRegistry* = object
    packs: seq[CraftPack]

proc isOk*(parsed: CraftPackParseResult): bool {.inline.} =
  parsed.value.isSome and parsed.diagnostics.len == 0

proc initCraftPackRegistry*(): CraftPackRegistry =
  CraftPackRegistry(packs: @[])

proc addDiagnostic(
    parsed: var CraftPackParseResult;
    code: CraftPackDiagnosticCode;
    path, message: string
) =
  parsed.diagnostics.add CraftPackDiagnostic(
    code: code,
    path: path,
    message: message
  )

proc sourceWithinLimits(
    source: string;
    parsed: var CraftPackParseResult
): bool =
  if source.len > maxCraftPackSourceBytes:
    parsed.addDiagnostic(
      cpdcLimitExceeded,
      "$",
      "Craft Pack source exceeds the byte limit"
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
        if depth > maxCraftPackJsonDepth:
          parsed.addDiagnostic(
            cpdcLimitExceeded,
            "$",
            "Craft Pack JSON exceeds the nesting-depth limit"
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
      var quotedEscape = false
      while index < source.len:
        if quotedEscape:
          quotedEscape = false
        elif source[index] == '\\':
          quotedEscape = true
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
                cpdcDuplicateField,
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

proc checkFields(
    node: JsonNode;
    path: string;
    allowed: openArray[string];
    parsed: var CraftPackParseResult
) =
  if node.isNil or node.kind != JObject:
    return
  let allowedSet = allowed.toHashSet
  for key in node.keys:
    if key notin allowedSet:
      parsed.addDiagnostic(cpdcUnknownField, path & "." & key, "unknown field")

proc requiredField(
    node: JsonNode;
    name, path: string;
    parsed: var CraftPackParseResult
): JsonNode =
  if node.isNil or node.kind != JObject or not node.hasKey(name):
    parsed.addDiagnostic(
      cpdcMissingField,
      path & "." & name,
      "required field is missing"
    )
    return nil
  node[name]

proc parseString(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult;
    allowEmpty = false
): Option[string] =
  if node.isNil or node.kind != JString:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected a string")
    return none(string)
  let value = node.getStr
  if value.len > maxCraftPackStringBytes:
    parsed.addDiagnostic(cpdcLimitExceeded, path, "string exceeds the byte limit")
    return none(string)
  if not allowEmpty and value.len == 0:
    parsed.addDiagnostic(cpdcInvalidValue, path, "value cannot be empty")
    return none(string)
  if '\0' in value:
    parsed.addDiagnostic(cpdcInvalidValue, path, "value cannot contain NUL")
    return none(string)
  some(value)

proc parseUint32(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult;
    allowZero = false
): Option[uint32] =
  if node.isNil or node.kind != JInt:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an integer")
    return none(uint32)
  let value = node.getBiggestInt
  if value < 0 or value > BiggestInt(high(uint32)) or
      (not allowZero and value == 0):
    parsed.addDiagnostic(cpdcInvalidValue, path, "integer is outside the supported range")
    return none(uint32)
  some(uint32(value))

proc validRelativePath(value: string): bool =
  if value.len == 0 or value[0] == '/' or '\\' in value or ':' in value:
    return false
  for character in value:
    if ord(character) <= 0x1f or ord(character) == 0x7f:
      return false
  for part in value.split('/'):
    if part.len == 0 or part == "." or part == "..":
      return false
  true

proc validSha256(value: string): bool =
  if value.len != 64:
    return false
  for character in value:
    if character notin {'0' .. '9', 'a' .. 'f'}:
      return false
  true

proc parseCapability(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult
): Option[CraftPackCapabilityRequirement] =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an object")
    return none(CraftPackCapabilityRequirement)
  node.checkFields(path, ["id", "minimumVersion"], parsed)
  let id = parseUint32(node.requiredField("id", path, parsed), path & ".id", parsed)
  let version = parseUint32(
    node.requiredField("minimumVersion", path, parsed),
    path & ".minimumVersion",
    parsed
  )
  if id.isSome and version.isSome:
    some(CraftPackCapabilityRequirement(
      id: id.get,
      minimumVersion: version.get
    ))
  else:
    none(CraftPackCapabilityRequirement)

proc parseCapabilities(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult
): seq[CraftPackCapabilityRequirement] =
  if node.isNil or node.kind != JArray:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an array")
    return
  if node.len > maxCraftPackCapabilities:
    parsed.addDiagnostic(cpdcLimitExceeded, path, "too many capabilities")
    return
  var seen = initHashSet[uint32]()
  for index in 0 ..< node.len:
    let requirement = parseCapability(node[index], path & "[" & $index & "]", parsed)
    if requirement.isNone:
      continue
    if requirement.get.id in seen:
      parsed.addDiagnostic(
        cpdcDuplicateValue,
        path & "[" & $index & "].id",
        "capability id is duplicated"
      )
    else:
      seen.incl requirement.get.id
      result.add requirement.get

proc parseCompatibility(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult
): CraftPackCompatibility =
  if node.isNil or node.kind != JObject:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an object")
    return
  node.checkFields(path, ["minimumAbi", "maximumAbi",
      "minimumDriverContract", "maximumDriverContract", "capabilities"], parsed)
  let minimumAbi = parseUint32(
    node.requiredField("minimumAbi", path, parsed),
    path & ".minimumAbi",
    parsed
  )
  let minimumDriver = parseUint32(
    node.requiredField("minimumDriverContract", path, parsed),
    path & ".minimumDriverContract",
    parsed
  )
  if minimumAbi.isSome:
    result.minimumAbi = minimumAbi.get
  if minimumDriver.isSome:
    result.minimumDriverContract = minimumDriver.get
  if node.hasKey("maximumAbi"):
    result.maximumAbi = parseUint32(node["maximumAbi"], path & ".maximumAbi", parsed)
  if node.hasKey("maximumDriverContract"):
    result.maximumDriverContract = parseUint32(
      node["maximumDriverContract"],
      path & ".maximumDriverContract",
      parsed
    )
  if result.maximumAbi.isSome and minimumAbi.isSome and
      result.maximumAbi.get < minimumAbi.get:
    parsed.addDiagnostic(
      cpdcInvalidValue,
      path & ".maximumAbi",
      "maximumAbi cannot be lower than minimumAbi"
    )
  if result.maximumDriverContract.isSome and minimumDriver.isSome and
      result.maximumDriverContract.get < minimumDriver.get:
    parsed.addDiagnostic(
      cpdcInvalidValue,
      path & ".maximumDriverContract",
      "maximumDriverContract cannot be lower than minimumDriverContract"
    )
  result.capabilities = parseCapabilities(
    node.requiredField("capabilities", path, parsed),
    path & ".capabilities",
    parsed
  )

proc parseStringArray(
    node: JsonNode;
    path: string;
    limit: int;
    parsed: var CraftPackParseResult
): seq[string] =
  if node.isNil or node.kind != JArray:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an array")
    return
  if node.len > limit:
    parsed.addDiagnostic(cpdcLimitExceeded, path, "array exceeds the item limit")
    return
  var seen = initHashSet[string]()
  for index in 0 ..< node.len:
    let value = parseString(node[index], path & "[" & $index & "]", parsed)
    if value.isNone:
      continue
    if value.get in seen:
      parsed.addDiagnostic(
        cpdcDuplicateValue,
        path & "[" & $index & "]",
        "value is duplicated"
      )
    else:
      seen.incl value.get
      result.add value.get

proc parseComponents(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult
): seq[CraftPackComponent] =
  if node.isNil or node.kind != JArray:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an array")
    return
  if node.len > maxCraftPackComponents:
    parsed.addDiagnostic(cpdcLimitExceeded, path, "too many components")
    return
  var seen = initHashSet[string]()
  for index in 0 ..< node.len:
    let itemPath = path & "[" & $index & "]"
    let item = node[index]
    if item.kind != JObject:
      parsed.addDiagnostic(cpdcInvalidType, itemPath, "expected an object")
      continue
    item.checkFields(itemPath, ["name", "slots"], parsed)
    let name = parseString(item.requiredField("name", itemPath, parsed),
        itemPath & ".name", parsed)
    let slots = parseStringArray(
      item.requiredField("slots", itemPath, parsed),
      itemPath & ".slots",
      maxCraftPackSlotsPerComponent,
      parsed
    )
    if name.isSome:
      if name.get in seen:
        parsed.addDiagnostic(
          cpdcDuplicateValue,
          itemPath & ".name",
          "component name is duplicated"
        )
      else:
        seen.incl name.get
        result.add CraftPackComponent(name: name.get, slots: slots)

proc parseStyles(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult
): seq[CraftPackStyleAsset] =
  if node.isNil or node.kind != JArray:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an array")
    return
  if node.len > maxCraftPackStyles:
    parsed.addDiagnostic(cpdcLimitExceeded, path, "too many Style assets")
    return
  var names = initHashSet[string]()
  var paths = initHashSet[string]()
  for index in 0 ..< node.len:
    let itemPath = path & "[" & $index & "]"
    let item = node[index]
    if item.kind != JObject:
      parsed.addDiagnostic(cpdcInvalidType, itemPath, "expected an object")
      continue
    item.checkFields(itemPath, ["name", "path", "sha256"], parsed)
    let name = parseString(item.requiredField("name", itemPath, parsed),
        itemPath & ".name", parsed)
    let assetPath = parseString(item.requiredField("path", itemPath, parsed),
        itemPath & ".path", parsed)
    let sha256 = parseString(item.requiredField("sha256", itemPath, parsed),
        itemPath & ".sha256", parsed)
    var valid = name.isSome and assetPath.isSome and sha256.isSome
    if assetPath.isSome and not validRelativePath(assetPath.get):
      parsed.addDiagnostic(cpdcInvalidValue, itemPath & ".path",
          "path must be a normalized relative path")
      valid = false
    if sha256.isSome and not validSha256(sha256.get):
      parsed.addDiagnostic(cpdcInvalidValue, itemPath & ".sha256",
          "sha256 must be 64 lowercase hexadecimal characters")
      valid = false
    if name.isSome and name.get in names:
      parsed.addDiagnostic(cpdcDuplicateValue, itemPath & ".name",
          "Style name is duplicated")
      valid = false
    if assetPath.isSome and assetPath.get in paths:
      parsed.addDiagnostic(cpdcDuplicateValue, itemPath & ".path",
          "asset path is duplicated")
      valid = false
    if valid:
      names.incl name.get
      paths.incl assetPath.get
      result.add CraftPackStyleAsset(
        name: name.get,
        path: assetPath.get,
        sha256: sha256.get
      )

proc parseAssetKind(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult
): Option[CraftPackAssetKind] =
  let value = parseString(node, path, parsed)
  if value.isNone:
    return none(CraftPackAssetKind)
  case value.get
  of "font": some(cpakFont)
  of "image": some(cpakImage)
  of "shader": some(cpakShader)
  of "binary": some(cpakBinary)
  else:
    parsed.addDiagnostic(cpdcInvalidValue, path, "unknown asset kind '" & value.get & "'")
    none(CraftPackAssetKind)

proc parseAssets(
    node: JsonNode;
    path: string;
    reservedPaths: var HashSet[string];
    parsed: var CraftPackParseResult
): seq[CraftPackAsset] =
  if node.isNil or node.kind != JArray:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an array")
    return
  if node.len > maxCraftPackAssets:
    parsed.addDiagnostic(cpdcLimitExceeded, path, "too many assets")
    return
  var ids = initHashSet[string]()
  for index in 0 ..< node.len:
    let itemPath = path & "[" & $index & "]"
    let item = node[index]
    if item.kind != JObject:
      parsed.addDiagnostic(cpdcInvalidType, itemPath, "expected an object")
      continue
    item.checkFields(itemPath, ["id", "kind", "path", "mimeType", "sha256", "required"], parsed)
    let id = parseString(item.requiredField("id", itemPath, parsed),
        itemPath & ".id", parsed)
    let kind = parseAssetKind(item.requiredField("kind", itemPath, parsed),
        itemPath & ".kind", parsed)
    let assetPath = parseString(item.requiredField("path", itemPath, parsed),
        itemPath & ".path", parsed)
    let sha256 = parseString(item.requiredField("sha256", itemPath, parsed),
        itemPath & ".sha256", parsed)
    var mimeType = none(string)
    if item.hasKey("mimeType"):
      mimeType = parseString(item["mimeType"], itemPath & ".mimeType", parsed)
    var required = true
    if item.hasKey("required"):
      if item["required"].kind != JBool:
        parsed.addDiagnostic(cpdcInvalidType, itemPath & ".required", "expected a boolean")
      else:
        required = item["required"].getBool
    var valid = id.isSome and kind.isSome and assetPath.isSome and sha256.isSome
    if assetPath.isSome and not validRelativePath(assetPath.get):
      parsed.addDiagnostic(cpdcInvalidValue, itemPath & ".path",
          "path must be a normalized relative path")
      valid = false
    if sha256.isSome and not validSha256(sha256.get):
      parsed.addDiagnostic(cpdcInvalidValue, itemPath & ".sha256",
          "sha256 must be 64 lowercase hexadecimal characters")
      valid = false
    if id.isSome and id.get in ids:
      parsed.addDiagnostic(cpdcDuplicateValue, itemPath & ".id", "asset id is duplicated")
      valid = false
    if assetPath.isSome and assetPath.get in reservedPaths:
      parsed.addDiagnostic(cpdcDuplicateValue, itemPath & ".path", "asset path is duplicated")
      valid = false
    if valid:
      ids.incl id.get
      reservedPaths.incl assetPath.get
      result.add CraftPackAsset(
        id: id.get,
        kind: kind.get,
        path: assetPath.get,
        mimeType: mimeType,
        sha256: sha256.get,
        required: required
      )

proc parseProfiles(
    node: JsonNode;
    path: string;
    parsed: var CraftPackParseResult
): seq[CraftPackFeatureProfile] =
  if node.isNil or node.kind != JArray:
    parsed.addDiagnostic(cpdcInvalidType, path, "expected an array")
    return
  if node.len > maxCraftPackProfiles:
    parsed.addDiagnostic(cpdcLimitExceeded, path, "too many feature profiles")
    return
  var names = initHashSet[string]()
  for index in 0 ..< node.len:
    let itemPath = path & "[" & $index & "]"
    let item = node[index]
    if item.kind != JObject:
      parsed.addDiagnostic(cpdcInvalidType, itemPath, "expected an object")
      continue
    item.checkFields(itemPath, ["name", "capabilities"], parsed)
    let name = parseString(item.requiredField("name", itemPath, parsed),
        itemPath & ".name", parsed)
    let capabilities = parseCapabilities(
      item.requiredField("capabilities", itemPath, parsed),
      itemPath & ".capabilities",
      parsed
    )
    if name.isSome:
      if name.get in names:
        parsed.addDiagnostic(cpdcDuplicateValue, itemPath & ".name",
            "feature profile name is duplicated")
      else:
        names.incl name.get
        result.add CraftPackFeatureProfile(
          name: name.get,
          capabilities: capabilities
        )

proc parseCraftPack*(source: string): CraftPackParseResult =
  if not sourceWithinLimits(source, result):
    return

  var document: JsonNode
  try:
    document = parseJson(source)
  except JsonParsingError as error:
    result.addDiagnostic(cpdcInvalidJson, "$", error.msg)
    return
  if document.kind != JObject:
    result.addDiagnostic(cpdcInvalidDocument, "$", "expected a JSON object")
    return

  document.checkFields("$", ["format", "version", "id", "packVersion",
      "compatibility", "components", "styles", "assets", "profiles", "platforms"], result)
  let format = parseString(document.requiredField("format", "$", result), "$.format", result)
  let formatVersion = parseUint32(
    document.requiredField("version", "$", result),
    "$.version",
    result
  )
  let id = parseString(document.requiredField("id", "$", result), "$.id", result)
  let packVersion = parseString(
    document.requiredField("packVersion", "$", result),
    "$.packVersion",
    result
  )
  if format.isSome and format.get != craftPackFormat:
    result.addDiagnostic(cpdcInvalidValue, "$.format", "unsupported Craft Pack format")
  if formatVersion.isSome and formatVersion.get != uint32(craftPackFormatVersion):
    result.addDiagnostic(cpdcUnsupportedVersion, "$.version", "unsupported Craft Pack version")

  let compatibility = parseCompatibility(
    document.requiredField("compatibility", "$", result),
    "$.compatibility",
    result
  )
  let components = parseComponents(
    document.requiredField("components", "$", result),
    "$.components",
    result
  )
  let styles = parseStyles(
    document.requiredField("styles", "$", result),
    "$.styles",
    result
  )
  var reservedPaths = initHashSet[string]()
  for style in styles:
    reservedPaths.incl style.path
  let assets = parseAssets(
    document.requiredField("assets", "$", result),
    "$.assets",
    reservedPaths,
    result
  )
  var profiles: seq[CraftPackFeatureProfile]
  if document.hasKey("profiles"):
    profiles = parseProfiles(document["profiles"], "$.profiles", result)
  var platforms: seq[string]
  if document.hasKey("platforms"):
    platforms = parseStringArray(
      document["platforms"],
      "$.platforms",
      maxCraftPackPlatforms,
      result
    )

  if result.diagnostics.len == 0 and id.isSome and packVersion.isSome:
    result.value = some(CraftPack(
      id: id.get,
      version: packVersion.get,
      compatibility: compatibility,
      components: components,
      styles: styles,
      assets: assets,
      profiles: profiles,
      platforms: platforms,
      normalizedJson: canonicalJson(document)
    ))

proc capabilityVersion(id: uint32): Option[uint32] =
  for capability in CbssCapabilities:
    if capability.id == id:
      return some(capability.version)

proc validateCraftPackCompatibility*(
    pack: CraftPack;
    abiVersion = CbssAbiVersion;
    driverContractVersion = CbssDriverContractVersion
): seq[CraftPackDiagnostic] =
  if abiVersion < pack.compatibility.minimumAbi or
      (pack.compatibility.maximumAbi.isSome and
       abiVersion > pack.compatibility.maximumAbi.get):
    result.add CraftPackDiagnostic(
      code: cpdcIncompatibleAbi,
      path: "$.compatibility",
      message: "Craft Pack is incompatible with CBSS ABI " & $abiVersion
    )
  if driverContractVersion < pack.compatibility.minimumDriverContract or
      (pack.compatibility.maximumDriverContract.isSome and
       driverContractVersion > pack.compatibility.maximumDriverContract.get):
    result.add CraftPackDiagnostic(
      code: cpdcIncompatibleDriverContract,
      path: "$.compatibility",
      message: "Craft Pack is incompatible with Craft Driver contract " &
        $driverContractVersion
    )
  for index, requirement in pack.compatibility.capabilities:
    let available = capabilityVersion(requirement.id)
    if available.isNone or available.get < requirement.minimumVersion:
      result.add CraftPackDiagnostic(
        code: cpdcMissingCapability,
        path: "$.compatibility.capabilities[" & $index & "]",
        message: "required capability " & $requirement.id & " version " &
          $requirement.minimumVersion & " is unavailable"
      )

proc replaceCraftPack(
    registry: var CraftPackRegistry;
    pack: CraftPack
): CraftPackLoadResult =
  result.diagnostics = pack.validateCraftPackCompatibility()
  if result.diagnostics.len > 0:
    return
  for index, active in registry.packs:
    if active.id == pack.id:
      registry.packs[index] = pack
      result.loaded = true
      return
  registry.packs.add pack
  result.loaded = true

proc replaceCraftPack*(
    registry: var CraftPackRegistry;
    source: string
): CraftPackLoadResult =
  let parsed = parseCraftPack(source)
  result.diagnostics = parsed.diagnostics
  if not parsed.isOk:
    return
  registry.replaceCraftPack(parsed.value.get)

proc removeCraftPack*(registry: var CraftPackRegistry; id: string): bool =
  for index, pack in registry.packs:
    if pack.id == id:
      registry.packs.delete(index)
      return true

proc craftPackCount*(registry: CraftPackRegistry): int {.inline.} =
  registry.packs.len

proc craftPackAt*(registry: CraftPackRegistry; index: int): Option[CraftPack] =
  if index >= 0 and index < registry.packs.len:
    some(registry.packs[index])
  else:
    none(CraftPack)

proc activeCraftPackIds*(registry: CraftPackRegistry): seq[string] =
  for pack in registry.packs:
    result.add pack.id
