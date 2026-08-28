import std/[json, options, os, strutils, unittest]

import clay_board_style_system

const fixturePath = currentSourcePath.parentDir.parentDir / "fixtures" /
  "craft_style" / "reference.json"
const schemaPath = currentSourcePath.parentDir.parentDir.parentDir / "schema" /
  "craft_style_v1.schema.json"

proc sourceFor(value: JsonNode; property = "width";
    operation = "overwrite"): string =
  $( %* {
    "format": craftStyleFormat,
    "version": craftStyleFormatVersion,
    "name": "test-style",
    "rules": [{
      "selector": {"element": "box"},
      "declarations": [{
        "property": property,
        "operation": operation,
        "value": value
    }]
  }]
  })

proc documentWith(rule: JsonNode): JsonNode =
  %* {
    "format": craftStyleFormat,
    "version": craftStyleFormatVersion,
    "name": "test-style",
    "rules": [rule]
  }

proc firstDiagnostic(source: string): CraftStyleDiagnostic =
  let parsed = parseCraftStyle(source)
  require not parsed.isOk
  require parsed.value.isNone
  require parsed.diagnostics.len > 0
  parsed.diagnostics[0]

suite "Craft Style exchange format":
  test "machine-readable schema tracks runtime identity and collection limits":
    let schema = parseJson(readFile(schemaPath))

    check schema["properties"]["format"]["const"].getStr == craftStyleFormat
    check schema["properties"]["version"]["const"].getInt == craftStyleFormatVersion
    check schema["properties"]["rules"]["maxItems"].getInt == maxCraftStyleRules
    check schema["$defs"]["rule"]["properties"]["declarations"][
        "maxItems"].getInt ==
      maxCraftStyleDeclarationsPerRule
    check schema["$defs"]["selector"]["properties"]["groups"][
        "maxItems"].getInt ==
      maxCraftStyleSelectorItems
    check schema["$defs"]["selector"]["properties"]["attributes"][
        "maxProperties"].getInt ==
      maxCraftStyleSelectorItems
    check schema["$defs"]["selector"]["properties"]["component"][
        "minLength"].getInt == 1
    check schema["$defs"]["selector"]["properties"]["slot"][
        "minLength"].getInt == 1
    check schema["$defs"]["selector"]["dependentRequired"]["component"][
        0].getStr == "slot"
    check schema["$defs"]["selector"]["dependentRequired"]["slot"][
        0].getStr == "component"

  test "reference fixture preserves typed rules and selector semantics":
    let parsed = parseCraftStyle(readFile(fixturePath))

    require parsed.isOk
    check parsed.diagnostics.len == 0
    let craft = parsed.value.get
    check craft.name == "reference-theme"
    check craft.sheet.rules.len == 2
    check craft.targets.len == 2
    check craft.targets[0].component.isNone
    check craft.targets[0].slot.isNone

    let first = craft.sheet.rules[0]
    check first.priority == 7
    check first.sourceOrder == 0
    check first.selector.elementKind == some(nkBox)
    check first.selector.id == some("dashboard")
    check first.selector.code == some("primary-panel")
    check first.selector.groups == @["surface", "interactive"]
    check first.selector.attrs.len == 2
    check first.selector.requiredStates == {esHover, esFocusVisible, esInvalid}
    check first.declarations.len == 10

    check first.declarations[0].operation.value.get.kind == svLength
    check first.declarations[0].operation.value.get.length.kind == ukPercent
    check first.declarations[1].operation.value.get.length.kind == ukAuto
    check first.declarations[2].operation.value.get.kind == svNumber
    check first.declarations[3].operation.value.get.keyword == "flex"
    check first.declarations[4].operation.value.get.kind == svColor
    check first.declarations[5].operation.value.get.kind == svColor
    check first.declarations[6].operation.value.get.kind == svBorder
    check first.declarations[7].operation.value.get.kind == svShadow
    check first.declarations[8].operation.value.get.kind == svLinearGradient
    check first.declarations[8].operation.value.get.gradientStops.len == 2
    check first.declarations[9].operation.value.get.kind == svTransform
    check first.declarations[9].operation.value.get.transformOperations.len == 3

    let second = craft.sheet.rules[1]
    check second.sourceOrder == 1
    check second.declarations[0].operation.mode == mmInherit
    check second.declarations[1].operation.mode == mmInitial
    check second.declarations[2].operation.mode == mmUnset
    check second.declarations[3].operation.mode == mmRelative

  test "all public length units have a stable serialized spelling":
    let units = [
      ("px", ukPx), ("percent", ukPercent), ("em", ukEm), ("rem", ukRem),
      ("fill", ukFill), ("vw", ukVw), ("vh", ukVh), ("vmin", ukVmin),
      ("vmax", ukVmax), ("lh", ukLh), ("rlh", ukRlh), ("ex", ukEx),
      ("ch", ukCh), ("rex", ukRex), ("rch", ukRch)
    ]
    for (spelling, expected) in units:
      let parsed = parseCraftStyle(sourceFor( %* {
        "type": "length", "unit": spelling, "value": 2.5
      }))
      require parsed.isOk
      check parsed.value.get.sheet.rules[0].declarations[
          0].operation.value.get.length ==
        LengthValue(kind: expected, value: 2.5)

    for (spelling, expected) in [
      ("content", ukContent), ("min-content", ukMinContent),
      ("max-content", ukMaxContent), ("fit-content", ukFitContent),
      ("auto", ukAuto), ("none", ukNone)
    ]:
      let parsed = parseCraftStyle(sourceFor( %* {
        "type": "length", "unit": spelling
      }))
      require parsed.isOk
      check parsed.value.get.sheet.rules[0].declarations[
          0].operation.value.get.length.kind == expected

  test "color pairs and optional structured fields parse without callbacks":
    let pair = parseCraftStyle(sourceFor(
      %* {"type": "color-pair", "first": "red", "second": "#00ff00"},
      "border-color"
    ))
    require pair.isOk
    check pair.value.get.sheet.rules[0].declarations[
        0].operation.value.get.kind == svColorPair

    let border = parseCraftStyle(sourceFor(
      %* {"type": "border", "style": "dashed"}, "border"
    ))
    require border.isOk
    check border.value.get.sheet.rules[0].declarations[
        0].operation.value.get.borderStyle ==
      some("dashed")

  test "empty rule arrays are valid but empty declaration arrays are not":
    let empty = parseCraftStyle($( %* {
      "format": craftStyleFormat,
      "version": craftStyleFormatVersion,
      "name": "empty",
      "rules": []
    }))
    require empty.isOk
    check empty.value.get.sheet.rules.len == 0

    let invalid = documentWith( %* {
      "selector": {"element": "box"},
      "declarations": []
    })
    let diagnostic = firstDiagnostic($invalid)
    check diagnostic.code == csdcInvalidValue
    check diagnostic.path == "$.rules[0].declarations"

  test "normalization is independent of object key order":
    let first = parseCraftStyle("""
      {"format":"cbss-craft-style","version":1,"name":"same","rules":[]}
    """)
    let second = parseCraftStyle("""
      {"rules":[],"name":"same","version":1,"format":"cbss-craft-style"}
    """)

    require first.isOk
    require second.isOk
    check first.value.get.normalizedJson == second.value.get.normalizedJson
    check first.value.get.normalizedJson ==
      "{\"format\":\"cbss-craft-style\",\"name\":\"same\",\"rules\":[],\"version\":1}"

  test "document errors never return a partially usable Craft Style":
    let cases = [
      ("{", csdcInvalidJson, "$"),
      ("[]", csdcInvalidDocument, "$"),
      ($( %* {"format": craftStyleFormat, "version": 1, "rules": []}),
        csdcMissingField, "$.name"),
      ($( %* {"format": craftStyleFormat, "version": 2, "name": "x", "rules": []}),
        csdcUnsupportedVersion, "$.version"),
      ($( %* {"format": "css", "version": 1, "name": "x", "rules": []}),
        csdcInvalidValue, "$.format"),
      ($( %* {"format": craftStyleFormat, "version": 1, "name": "", "rules": []}),
        csdcInvalidValue, "$.name")
    ]
    for (source, code, path) in cases:
      let diagnostic = firstDiagnostic(source)
      check diagnostic.code == code
      check diagnostic.path == path

  test "duplicate object fields are rejected before Driver parsers can diverge":
    let diagnostic = firstDiagnostic("""
      {
        "format":"cbss-craft-style",
        "version":1,
        "name":"first",
        "name":"second",
        "rules":[]
      }
    """)

    check diagnostic.code == csdcDuplicateField
    check diagnostic.path == "$"
    check diagnostic.message == "duplicate field 'name'"

  test "unknown fields are rejected at every structural boundary":
    var cases: seq[tuple[source, path: string]]

    var document = parseJson(sourceFor( %* {"type": "length", "unit": "px", "value": 1}))
    document["extra"] = %true
    cases.add(($document, "$.extra"))

    document = parseJson(sourceFor( %* {"type": "length", "unit": "px", "value": 1}))
    document["rules"][0]["extra"] = %true
    cases.add(($document, "$.rules[0].extra"))

    document = parseJson(sourceFor( %* {"type": "length", "unit": "px", "value": 1}))
    document["rules"][0]["selector"]["extra"] = %true
    cases.add(($document, "$.rules[0].selector.extra"))

    document = parseJson(sourceFor( %* {"type": "length", "unit": "px", "value": 1}))
    document["rules"][0]["declarations"][0]["extra"] = %true
    cases.add(($document, "$.rules[0].declarations[0].extra"))

    document = parseJson(sourceFor( %* {"type": "length", "unit": "px", "value": 1}))
    document["rules"][0]["declarations"][0]["value"]["extra"] = %true
    cases.add(($document, "$.rules[0].declarations[0].value.extra"))

    for item in cases:
      let diagnostic = firstDiagnostic(item.source)
      check diagnostic.code == csdcUnknownField
      check diagnostic.path == item.path

  test "invalid values report deterministic property paths":
    let cases = [
      (sourceFor( %* {"type": "length", "unit": "pixels", "value": 1}),
        csdcInvalidValue, "$.rules[0].declarations[0].value.unit"),
      (sourceFor( %* {"type": "function"}),
        csdcInvalidValue, "$.rules[0].declarations[0].value.type"),
      (sourceFor( %* {"type": "color", "value": "not-a-color"}, "color"),
        csdcInvalidValue, "$.rules[0].declarations[0].value.value"),
      (sourceFor( %* {
        "type": "linear-gradient", "angle": 0,
        "stops": [{"color": "red", "offset": 0}]
      }, "background-image"),
        csdcInvalidValue, "$.rules[0].declarations[0].value.stops"),
      (sourceFor( %* {
        "type": "linear-gradient", "angle": 0,
        "stops": [
          {"color": "red", "offset": -0.1},
          {"color": "blue", "offset": 1}
        ]
      }, "background-image"),
        csdcInvalidValue, "$.rules[0].declarations[0].value.stops[0].offset"),
      (sourceFor( %* {
        "type": "transform", "operations": [{"type": "skew", "angle": 10}]
      }, "transform"),
        csdcInvalidValue, "$.rules[0].declarations[0].value.operations[0].type"),
      (sourceFor( %* {"type": "number", "value": 1}, "unknown-property"),
        csdcUnknownProperty, "$.rules[0].declarations[0].property")
    ]
    for (source, code, path) in cases:
      let diagnostic = firstDiagnostic(source)
      check diagnostic.code == code
      check diagnostic.path == path

  test "selector and operation errors are explicit":
    var document = documentWith( %* {
      "selector": {"element": "canvas"},
      "declarations": [{
        "property": "width",
        "value": {"type": "length", "unit": "px", "value": 1}
      }]
    })
    var diagnostic = firstDiagnostic($document)
    check diagnostic.path == "$.rules[0].selector.element"

    document["rules"][0]["selector"] = %* {"states": ["visited"]}
    diagnostic = firstDiagnostic($document)
    check diagnostic.path == "$.rules[0].selector.states[0]"

    diagnostic = firstDiagnostic(sourceFor(
      %* {"type": "number", "value": 1}, "opacity", "append"
    ))
    check diagnostic.path == "$.rules[0].declarations[0].operation"

    diagnostic = firstDiagnostic(sourceFor(
      %* {"type": "number", "value": 1}, "opacity", "inherit"
    ))
    check diagnostic.path == "$.rules[0].declarations[0].value"

  test "all diagnostics are retained while the document remains unusable":
    let parsed = parseCraftStyle($( %* {
      "format": "wrong",
      "version": 99,
      "name": "",
      "rules": [{
        "selector": {"element": "unknown"},
        "declarations": [{
          "property": "unknown",
          "value": {"type": "function"}
      }]
    }]
    }))

    check parsed.value.isNone
    check parsed.diagnostics.len >= 5

  test "bounded parsing rejects excessive nesting before JSON allocation":
    let source = "[".repeat(maxCraftStyleJsonDepth + 1) &
      "0" & "]".repeat(maxCraftStyleJsonDepth + 1)
    let diagnostic = firstDiagnostic(source)

    check diagnostic.code == csdcLimitExceeded
    check diagnostic.path == "$"

  test "bounded parsing rejects oversized selector collections":
    var groups = newJArray()
    for index in 0 .. maxCraftStyleSelectorItems:
      groups.add %("group-" & $index)
    let document = documentWith( %* {
      "selector": {"groups": groups},
      "declarations": [{
        "property": "opacity",
        "value": {"type": "number", "value": 1}
      }]
    })
    let diagnostic = firstDiagnostic($document)

    check diagnostic.code == csdcLimitExceeded
    check diagnostic.path == "$.rules[0].selector.groups"
