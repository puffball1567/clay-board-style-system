import std/[json, options, os, sequtils, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/craft_driver_contract

let fixturePath = currentSourcePath.parentDir / ".." / "fixtures" /
  "craft_pack" / "reference.json"
let schemaPath = currentSourcePath.parentDir / ".." / ".." / "schema" /
  "craft_pack_v1.schema.json"

proc fixtureSource(): string =
  readFile(fixturePath)

suite "Craft Pack manifest":
  test "schema publishes the parser limits and closed document contract":
    let schema = parseJson(readFile(schemaPath))
    check schema["additionalProperties"].getBool == false
    check schema["properties"]["version"]["const"].getInt ==
      craftPackFormatVersion
    check schema["properties"]["components"]["maxItems"].getInt ==
      maxCraftPackComponents
    check schema["properties"]["styles"]["maxItems"].getInt ==
      maxCraftPackStyles
    check schema["properties"]["assets"]["maxItems"].getInt ==
      maxCraftPackAssets
    check schema["$defs"]["relativePath"]["maxLength"].getInt ==
      maxCraftPackStringBytes
    check schema["$defs"]["relativePath"]["x-cbss-maxUtf8Bytes"].getInt ==
      maxCraftPackStringBytes
    check schema["$defs"]["boundedString"]["x-cbss-maxUtf8Bytes"].getInt ==
      maxCraftPackStringBytes

  test "reference manifest parses, normalizes, and exposes typed metadata":
    let parsed = parseCraftPack(fixtureSource())
    require parsed.isOk
    let pack = parsed.value.get
    check pack.id == "org.example.dashboard"
    check pack.version == "1.2.0"
    check pack.compatibility.minimumAbi == CbssAbiVersion
    check pack.compatibility.capabilities.len == 3
    check pack.components == @[
      CraftPackComponent(
        name: "dashboard-card",
        slots: @["root", "title", "body"]
      )
    ]
    check pack.styles[0].path == "styles/dashboard-light.json"
    check pack.assets[0].kind == cpakImage
    check pack.assets[0].mimeType == some("image/png")
    check pack.profiles[0].name == "gpu-effects"
    check pack.platforms.len == 3
    check parseJson(pack.normalizedJson)["id"].getStr == pack.id
    check pack.validateCraftPackCompatibility().len == 0

  test "registry replacement is atomic and keyed by pack identity":
    var registry = initCraftPackRegistry()
    let first = registry.replaceCraftPack(fixtureSource())
    require first.loaded
    check registry.activeCraftPackIds() == @["org.example.dashboard"]
    require registry.craftPackAt(0).isSome
    check registry.craftPackAt(0).get.version == "1.2.0"

    let incompatible = fixtureSource().replace(
      "\"minimumAbi\": 65558",
      "\"minimumAbi\": 4294967295"
    ).replace("\"packVersion\": \"1.2.0\"", "\"packVersion\": \"2.0.0\"")
    let rejected = registry.replaceCraftPack(incompatible)
    check not rejected.loaded
    check rejected.diagnostics.len == 1
    check rejected.diagnostics[0].code == cpdcIncompatibleAbi
    check registry.craftPackAt(0).get.version == "1.2.0"

    let replacement = fixtureSource().replace(
      "\"packVersion\": \"1.2.0\"",
      "\"packVersion\": \"1.3.0\""
    )
    require registry.replaceCraftPack(replacement).loaded
    check registry.craftPackCount() == 1
    check registry.craftPackAt(0).get.version == "1.3.0"
    check registry.removeCraftPack("org.example.dashboard")
    check not registry.removeCraftPack("org.example.dashboard")

    let root = initUiRoot()
    require root.replaceCraftPack(fixtureSource()).loaded
    check root.activeCraftPackIds() == @["org.example.dashboard"]
    check root.craftPackAt(0).get.version == "1.2.0"
    check root.removeCraftPack("org.example.dashboard")

  test "unsafe paths, malformed digests, duplicates, and unknown fields fail":
    for (needle, replacement, expected) in [
      (
        "styles/dashboard-light.json",
        "../dashboard-light.json",
        cpdcInvalidValue
      ),
      (
        repeat("1", 64),
        repeat("G", 64),
        cpdcInvalidValue
      ),
      (
        "\"slots\": [\"root\", \"title\", \"body\"]",
        "\"slots\": [\"root\", \"root\", \"body\"]",
        cpdcDuplicateValue
      )
    ]:
      let parsed = parseCraftPack(fixtureSource().replace(needle, replacement))
      check not parsed.isOk
      check parsed.diagnostics.anyIt(it.code == expected)

    let duplicateField = fixtureSource().replace(
      "\"id\": \"org.example.dashboard\"",
      "\"id\": \"org.example.dashboard\", \"id\": \"duplicate\""
    )
    let duplicateParsed = parseCraftPack(duplicateField)
    check not duplicateParsed.isOk
    check duplicateParsed.diagnostics[0].code == cpdcDuplicateField

    let document = parseJson(fixtureSource())
    document["unexpected"] = newJBool(true)
    let unknownParsed = parseCraftPack($document)
    check not unknownParsed.isOk
    check unknownParsed.diagnostics.anyIt(it.code == cpdcUnknownField)

  test "all non-normalized path families are rejected":
    for invalidPath in [
      "/styles/theme.json",
      "../styles/theme.json",
      "styles/../theme.json",
      "styles/./theme.json",
      "styles/..",
      "styles/.",
      "..",
      ".",
      "styles//theme.json",
      "styles\\theme.json",
      "C:/styles/theme.json",
      "file:styles/theme.json"
    ]:
      let parsed = parseCraftPack(fixtureSource().replace(
        "styles/dashboard-light.json",
        invalidPath
      ))
      checkpoint invalidPath
      check not parsed.isOk
      check parsed.diagnostics.anyIt(
        it.code == cpdcInvalidValue and it.path == "$.styles[0].path"
      )

  test "invalid identities, ranges, kinds, and cross-asset duplicates fail":
    for (needle, replacement, expectedCode, expectedPath) in [
      (
        "\"format\": \"cbss-craft-pack\"",
        "\"format\": \"not-a-craft-pack\"",
        cpdcInvalidValue,
        "$.format"
      ),
      (
        "\"version\": 1",
        "\"version\": 2",
        cpdcUnsupportedVersion,
        "$.version"
      ),
      (
        "\"kind\": \"image\"",
        "\"kind\": \"executable\"",
        cpdcInvalidValue,
        "$.assets[0].kind"
      ),
      (
        "assets/dashboard-logo.png",
        "styles/dashboard-light.json",
        cpdcDuplicateValue,
        "$.assets[0].path"
      )
    ]:
      let parsed = parseCraftPack(fixtureSource().replace(needle, replacement))
      check not parsed.isOk
      check parsed.diagnostics.anyIt(
        it.code == expectedCode and it.path == expectedPath
      )

    let reversedAbiRange = fixtureSource().replace(
      "\"minimumAbi\": 65558,",
      "\"minimumAbi\": 65558, \"maximumAbi\": 65557,"
    )
    let reversedAbiParsed = parseCraftPack(reversedAbiRange)
    check not reversedAbiParsed.isOk
    check reversedAbiParsed.diagnostics.anyIt(
      it.code == cpdcInvalidValue and
        it.path == "$.compatibility.maximumAbi"
    )

    let duplicateComponent = fixtureSource().replace(
      "{\"name\": \"dashboard-card\", \"slots\": [\"root\", \"title\", \"body\"]}",
      "{\"name\": \"dashboard-card\", \"slots\": [\"root\"]}," &
        "{\"name\": \"dashboard-card\", \"slots\": [\"body\"]}"
    )
    let duplicateComponentParsed = parseCraftPack(duplicateComponent)
    check not duplicateComponentParsed.isOk
    check duplicateComponentParsed.diagnostics.anyIt(
      it.code == cpdcDuplicateValue and
        it.path == "$.components[1].name"
    )

    let invalidRequired = fixtureSource().replace(
      "\"mimeType\": \"image/png\",",
      "\"mimeType\": \"image/png\", \"required\": \"yes\","
    )
    let invalidRequiredParsed = parseCraftPack(invalidRequired)
    check not invalidRequiredParsed.isOk
    check invalidRequiredParsed.diagnostics.anyIt(
      it.code == cpdcInvalidType and it.path == "$.assets[0].required"
    )

  test "limits and compatibility failures produce stable diagnostics":
    let oversized = repeat(" ", maxCraftPackSourceBytes + 1)
    let oversizedParsed = parseCraftPack(oversized)
    check not oversizedParsed.isOk
    check oversizedParsed.diagnostics[0].code == cpdcLimitExceeded

    let tooDeep = repeat("[", maxCraftPackJsonDepth + 1) &
      repeat("]", maxCraftPackJsonDepth + 1)
    let deepParsed = parseCraftPack(tooDeep)
    check not deepParsed.isOk
    check deepParsed.diagnostics[0].code == cpdcLimitExceeded

    var pack = parseCraftPack(fixtureSource()).value.get
    pack.compatibility.minimumDriverContract = high(uint32)
    let driverDiagnostics = pack.validateCraftPackCompatibility()
    check driverDiagnostics.anyIt(it.code == cpdcIncompatibleDriverContract)

    pack = parseCraftPack(fixtureSource()).value.get
    pack.compatibility.capabilities.add CraftPackCapabilityRequirement(
      id: high(uint32),
      minimumVersion: 1
    )
    let capabilityDiagnostics = pack.validateCraftPackCompatibility()
    check capabilityDiagnostics.anyIt(it.code == cpdcMissingCapability)
