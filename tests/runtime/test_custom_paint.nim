import std/[options, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc resolvedUi(ui: UiRoot): tuple[styles: ResolvedTree, layout: LayoutResult] =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
  )
  check not diagnostics.hasErrors
  result.layout = computeLayout(ui.tree, result.styles, size(240, 120))

proc commandIndex(commands: openArray[PaintCommand]; color: Color): int =
  for index, command in commands:
    if command.kind == pcFillRect and command.color == color:
      return index
  -1

suite "declarative custom paint":
  test "typed material parameters preserve every supported value kind":
    let values = customPaintParameters([
      customPaintFloat("phase", 0.25),
      customPaintInteger("samples", 12),
      customPaintBoolean("enabled", true),
      customPaintVec2("origin", 3, 4),
      customPaintVec4("weights", 1, 2, 3, 4),
      customPaintColor("accent", rgba(0.1, 0.2, 0.3, 0.4))
    ])

    check values.len == 6
    check values[0].kind == cppkFloat
    check values[0].floatValue == 0.25
    check values[1].kind == cppkInteger
    check values[1].integerValue == 12
    check values[2].kind == cppkBoolean
    check values[2].booleanValue
    check values[3].kind == cppkVec2
    check values[3].vec2Value == [3.0'f32, 4.0'f32]
    check values[4].kind == cppkVec4
    check values[4].vec4Value == [1.0'f32, 2.0'f32, 3.0'f32, 4.0'f32]
    check values[5].kind == cppkColor
    check values[5].colorValue == rgba(0.1, 0.2, 0.3, 0.4)

    var names: seq[string]
    for parameter in values:
      names.add parameter.name
    check names == @["phase", "samples", "enabled", "origin", "weights",
      "accent"]
    check values.findCustomPaintParameter("origin").isSome
    check values.findCustomPaintParameter("missing").isNone
    check CustomPaintParameters(nil).len == 0
    check CustomPaintParameters(nil).findCustomPaintParameter("x").isNone

  test "parameter snapshots do not alias caller-owned names or values":
    var callerName = "phase"
    var callerParameter = customPaintFloat(callerName, 0.5)
    let retained = customPaintParameters([callerParameter])

    callerName[0] = 'x'
    callerParameter.floatValue = 1.0
    check retained[0].name == "phase"
    check retained[0].floatValue == 0.5

    let emptyDeclaration = customPaint("plain")
    check emptyDeclaration.customPaintParameters.isNil

  test "typed material parameters reach paint without per-frame parsing":
    let ui = initUiRoot()
    let panel = ui.box(uiStyle([
      decl("width", px(40)),
      decl("height", px(20)),
      customPaint(
        "parameterized",
        parameters = [
          customPaintFloat("phase", 0.75),
          customPaintColor("tint", rgb(0.2, 0.4, 0.6))
        ]
      )
    ]))
    var callbackCount = 0
    var captured: CustomPaintRequest
    check ui.registerCustomPaintMaterial(
      "parameterized",
      proc(request: CustomPaintRequest): seq[PaintCommand] =
        inc callbackCount
        captured = request
        @[]
    )

    let resolved = ui.resolvedUi()
    let retained = resolved.styles.styles[panel.id.nodeIndex]
      .customPaintParameters(cpsOverlay)
    check retained.len == 2
    discard ui.buildPaintCommands(resolved.styles, resolved.layout)
    check callbackCount == 1
    check captured.owner == panel.id
    check captured.parameters.len == 2
    check captured.parameters[0].name == "phase"
    check captured.parameters[0].floatValue == 0.75
    check captured.parameters[1].name == "tint"
    check captured.parameters[1].colorValue == rgb(0.2, 0.4, 0.6)

  test "material parameters remain isolated by stage and clear with none":
    let ui = initUiRoot()
    let panel = ui.box(uiStyle([
      customPaint(
        "base",
        cpsUnderlay,
        parameters = [customPaintFloat("depth", 1)]
      ),
      customPaint(
        "shine",
        cpsOverlay,
        parameters = [customPaintFloat("intensity", 2)]
      ),
      decl(customPaintOverlayProperty, keyword("none"))
    ]))
    let resolved = ui.resolvedUi()
    let style = resolved.styles.styles[panel.id.nodeIndex]

    check style.customPaintParameters(cpsUnderlay).len == 1
    check style.customPaintParameters(cpsUnderlay)[0].name == "depth"
    check style.customPaintMaterial(cpsOverlay).isNone
    check style.customPaintParameters(cpsOverlay).len == 0
    check style.customPaintParameters(cpsMask).len == 0
    check style.customPaintParameters(cpsFilter).len == 0

  test "parameter names are bounded shader-compatible identifiers":
    let valid = ["x", "_phase", "accent2", "CamelCase"]
    for name in valid:
      check name.validCustomPaintParameterName
      check customPaintFloat(name, 1).name == name

    let invalid = ["", "2phase", "has-dash", "has space", "accent.color",
      "\x00bad", repeat('x', maxCustomPaintParameterNameBytes + 1), "色"]
    for name in invalid:
      check not name.validCustomPaintParameterName
      expect ValueError:
        discard customPaintFloat(name, 1)

  test "parameter sets reject duplicate names and excessive cardinality":
    expect ValueError:
      discard customPaintParameters([
        customPaintFloat("same", 1),
        customPaintInteger("same", 2)
      ])

    var maximum: seq[CustomPaintParameter]
    for index in 0 ..< maxCustomPaintParameters:
      maximum.add customPaintInteger("p" & $index, index)
    check customPaintParameters(maximum).len == maxCustomPaintParameters
    maximum.add customPaintFloat("overflow", 1)
    expect ValueError:
      discard customPaintParameters(maximum)

  test "non-finite float vector and color values fail before style storage":
    for value in [NaN.float32, Inf.float32, NegInf.float32]:
      expect ValueError:
        discard customPaintFloat("value", value)
      expect ValueError:
        discard customPaintVec2("value", 0, value)
      expect ValueError:
        discard customPaintVec4("value", 0, 0, value, 0)
      expect ValueError:
        discard customPaintColor("value", rgba(0, value, 0, 1))

  test "integer parameters preserve int64 boundaries and reject overflow":
    check customPaintInteger("low", low(int64)).integerValue == low(int64)
    check customPaintInteger("high", high(int64)).integerValue == high(int64)
    check customPaintInteger("unsigned", uint64(high(int64))).integerValue ==
      high(int64)
    expect ValueError:
      discard customPaintInteger("overflow", high(uint64))

  test "authoring validates names and maps every stage to a private property":
    check customPaint("surface").property == customPaintOverlayProperty
    check customPaint("surface", cpsUnderlay).property ==
      customPaintUnderlayProperty
    check customPaint("surface", cpsMask).property == customPaintMaskProperty
    check customPaint("surface", cpsFilter).property == customPaintFilterProperty

    for invalid in ["", " leading", "trailing ", "bad\x00name", "bad\nname"]:
      expect ValueError:
        discard customPaint(invalid)

  test "computed style retains component-local material references":
    let ui = initUiRoot()
    let panel = ui.box(uiStyle([
      customPaint("base", cpsUnderlay),
      customPaint("shine", cpsOverlay)
    ]))
    let resolved = ui.resolvedUi()
    let style = resolved.styles.styles[panel.id.nodeIndex]

    check style.hasCustomPaintStyle
    check style.customPaintMaterial(cpsUnderlay) == some("base")
    check style.customPaintMaterial(cpsOverlay) == some("shine")
    check style.customPaintMaterial(cpsMask).isNone
    check style.customPaintMaterial(cpsFilter).isNone

  test "none explicitly removes an earlier material in the same style slot":
    let ui = initUiRoot()
    let panel = ui.box(uiStyle([
      customPaint("base", cpsOverlay),
      decl(customPaintOverlayProperty, keyword("none"))
    ]))
    let resolved = ui.resolvedUi()
    check resolved.styles.styles[panel.id.nodeIndex]
      .customPaintMaterial(cpsOverlay).isNone

  test "underlay and overlay surround child paint without adding tree nodes":
    let underlayColor = rgb(0.13, 0.37, 0.71)
    let overlayColor = rgba(0.92, 0.28, 0.16, 0.4)
    let ui = initUiRoot()
    let panel = ui.box(uiStyle([
      decl("width", px(160)),
      decl("height", px(64)),
      decl("overflow", keyword("hidden")),
      customPaint("panel-base", cpsUnderlay),
      customPaint("panel-glow", cpsOverlay)
    ]), code = "panel")
    let label = ui.text(panel, "Custom paint")
    let nodeCount = ui.tree.nodes.len

    check ui.registerCustomPaintMaterial(
      "panel-base",
      proc(request: CustomPaintRequest): seq[PaintCommand] =
        @[fillRect(request.bounds, underlayColor, owner = some(request.owner))],
      {cpsUnderlay}
    )
    check ui.registerCustomPaintMaterial(
      "panel-glow",
      proc(request: CustomPaintRequest): seq[PaintCommand] =
        @[fillRect(request.bounds, overlayColor, owner = some(request.owner))],
      {cpsOverlay}
    )

    let resolved = ui.resolvedUi()
    let commands = ui.buildPaintCommands(resolved.styles, resolved.layout)
    let underlayIndex = commands.commandIndex(underlayColor)
    let overlayIndex = commands.commandIndex(overlayColor)
    var textIndex = -1
    for index, command in commands:
      if command.kind == pcDrawText and command.node == label.id:
        textIndex = index

    check ui.tree.nodes.len == nodeCount
    check underlayIndex >= 0
    check textIndex >= 0
    check overlayIndex >= 0
    check underlayIndex < textIndex
    check textIndex < overlayIndex
    check ui.takeCustomPaintDiagnostics().len == 0

  test "material output is clipped to its owner bounds":
    let ui = initUiRoot()
    discard ui.box(uiStyle([
      decl("width", px(80)),
      decl("height", px(40)),
      decl("border-radius", px(8)),
      customPaint("oversized", cpsOverlay)
    ]))
    check ui.registerCustomPaintMaterial(
      "oversized",
      proc(request: CustomPaintRequest): seq[PaintCommand] =
        @[fillRect(rect(-100, -100, 1000, 1000), rgb(1, 0, 0))]
    )
    let resolved = ui.resolvedUi()
    let commands = ui.buildPaintCommands(resolved.styles, resolved.layout)
    let paintIndex = commands.commandIndex(rgb(1, 0, 0))

    check paintIndex > 0
    check commands[paintIndex - 1].kind == pcPushClip
    check commands[paintIndex + 1].kind == pcPopClip
    check commands[paintIndex - 1].clipRadius == 8

  test "missing materials fail closed and emit one bounded diagnostic":
    let ui = initUiRoot()
    discard ui.box(uiStyle([
      decl("width", px(40)),
      decl("height", px(20)),
      customPaint("missing")
    ]))
    let resolved = ui.resolvedUi()

    discard ui.buildPaintCommands(resolved.styles, resolved.layout)
    discard ui.buildPaintCommands(resolved.styles, resolved.layout)
    let diagnostics = ui.takeCustomPaintDiagnostics()
    check diagnostics.len == 1
    check diagnostics[0].status == cprsMissingMaterial
    check diagnostics[0].material == "missing"
    check ui.takeCustomPaintDiagnostics().len == 0

  test "material lifecycle invalidates only nodes that consumed that name":
    let ui = initUiRoot()
    let first = ui.box(uiStyle([
      decl("width", px(40)),
      decl("height", px(20)),
      customPaint("dynamic")
    ]))
    discard ui.box(uiStyle([
      decl("width", px(40)),
      decl("height", px(20))
    ]))
    let resolved = ui.resolvedUi()
    discard ui.consumeInvalidation()
    discard ui.buildPaintCommands(resolved.styles, resolved.layout)

    let callback = proc(
        request: CustomPaintRequest
    ): seq[PaintCommand] = @[]
    check ui.registerCustomPaintMaterial("dynamic", callback)
    var invalidation = ui.consumeInvalidation()
    check invalidation.domains == {ddPaint}
    check invalidation.roots == @[first.id]

    check ui.invalidateCustomPaintMaterial("dynamic") == 1
    invalidation = ui.consumeInvalidation()
    check invalidation.domains == {ddPaint}
    check invalidation.roots == @[first.id]

    check ui.unregisterCustomPaintMaterial("dynamic")
    invalidation = ui.consumeInvalidation()
    check invalidation.domains == {ddPaint}
    check invalidation.roots == @[first.id]

  test "diagnostics stay bounded under distinct malformed material references":
    let registry = initCustomPaintRegistry()
    for index in 0 .. maxCustomPaintDiagnostics + 31:
      discard registry.resolveCustomPaint(CustomPaintRequest(
        material: "missing-" & $index,
        stage: cpsOverlay,
        owner: NodeId(index),
        bounds: rect(0, 0, 1, 1),
        opacity: 1
      ))
    check registry.takeCustomPaintDiagnostics().len ==
      maxCustomPaintDiagnostics

  test "mask and filter declarations report unsupported composition":
    let ui = initUiRoot()
    discard ui.box(uiStyle([
      decl("width", px(40)),
      decl("height", px(20)),
      customPaint("alpha-mask", cpsMask),
      customPaint("blur-pass", cpsFilter)
    ]))
    let resolved = ui.resolvedUi()
    discard ui.buildPaintCommands(resolved.styles, resolved.layout)
    let diagnostics = ui.takeCustomPaintDiagnostics()

    check diagnostics.len == 2
    for diagnostic in diagnostics:
      check diagnostic.status == cprsUnsupportedStage

  test "unbalanced material commands are rejected before composition":
    let markerColor = rgb(0.2, 0.8, 0.4)
    let ui = initUiRoot()
    discard ui.box(uiStyle([
      decl("width", px(40)),
      decl("height", px(20)),
      customPaint("broken")
    ]))
    check ui.registerCustomPaintMaterial(
      "broken",
      proc(request: CustomPaintRequest): seq[PaintCommand] =
        @[
          pushClip(request.bounds),
          fillRect(request.bounds, markerColor)
        ]
    )
    let resolved = ui.resolvedUi()
    let commands = ui.buildPaintCommands(resolved.styles, resolved.layout)
    let diagnostics = ui.takeCustomPaintDiagnostics()

    check commands.commandIndex(markerColor) == -1
    check diagnostics.len == 1
    check diagnostics[0].status == cprsInvalidCommands

  test "oversized material command streams fail closed":
    let registry = initCustomPaintRegistry()
    check registry.registerCustomPaintMaterial(
      "too-many",
      proc(request: CustomPaintRequest): seq[PaintCommand] =
        newSeq[PaintCommand](maxCustomPaintCommands + 1)
    )
    let resolution = registry.resolveCustomPaint(CustomPaintRequest(
      material: "too-many",
      stage: cpsOverlay,
      owner: NodeId(0),
      bounds: rect(0, 0, 10, 10),
      opacity: 1
    ))

    check resolution.status == cprsInvalidCommands
    check resolution.commands.len == 0
    let diagnostics = registry.takeCustomPaintDiagnostics()
    check diagnostics.len == 1
    check diagnostics[0].message.contains("command limit")

  test "invalid direct requests do not retain attacker-controlled names":
    let registry = initCustomPaintRegistry()
    let resolution = registry.resolveCustomPaint(CustomPaintRequest(
      material: repeat('x', maxCustomPaintMaterialBytes + 1),
      stage: cpsOverlay,
      owner: NodeId(0),
      bounds: rect(0, 0, 10, 10),
      opacity: 1
    ))

    check resolution.status == cprsInvalidRequest
    let diagnostics = registry.takeCustomPaintDiagnostics()
    check diagnostics.len == 1
    check diagnostics[0].material == "<invalid>"

  test "disposing a subtree removes its material consumer entries":
    let ui = initUiRoot()
    var interaction = initInteractionState()
    let panel = ui.box(uiStyle([
      decl("width", px(40)),
      decl("height", px(20)),
      customPaint("temporary")
    ]))
    let resolved = ui.resolvedUi()
    discard ui.buildPaintCommands(resolved.styles, resolved.layout)

    check ui.invalidateCustomPaintMaterial("temporary") == 1
    discard ui.consumeInvalidation()
    check ui.disposeSubtree(panel, interaction)
    check ui.invalidateCustomPaintMaterial("temporary") == 0

  test "registered stage mismatch never invokes the material callback":
    let registry = initCustomPaintRegistry()
    var calls = 0
    let callback = proc(
        request: CustomPaintRequest
    ): seq[PaintCommand] =
      inc calls
      @[]
    check registry.registerCustomPaintMaterial(
      "underlay-only",
      callback,
      {cpsUnderlay}
    )
    let resolution = registry.resolveCustomPaint(CustomPaintRequest(
      material: "underlay-only",
      stage: cpsOverlay,
      owner: NodeId(0),
      bounds: rect(0, 0, 10, 10),
      opacity: 1
    ))

    check resolution.status == cprsUnsupportedStage
    check resolution.commands.len == 0
    check calls == 0

  test "registration is deterministic and explicit replacement is opt-in":
    let registry = initCustomPaintRegistry()
    let first = proc(request: CustomPaintRequest): seq[PaintCommand] = @[]
    let second = proc(request: CustomPaintRequest): seq[PaintCommand] = @[]

    check registry.registerCustomPaintMaterial("material", first)
    check not registry.registerCustomPaintMaterial("material", second)
    check registry.registerCustomPaintMaterial("material", second, replace = true)
    check registry.hasCustomPaintMaterial("material")
    check registry.unregisterCustomPaintMaterial("material")
    check not registry.hasCustomPaintMaterial("material")
    check not registry.unregisterCustomPaintMaterial("material")

  test "tracked registration cannot remove a newer replacement":
    let registry = initCustomPaintRegistry()
    let callback = proc(request: CustomPaintRequest): seq[PaintCommand] = @[]
    let first = registry.registerCustomPaintMaterialTracked(
      "material", callback
    )
    let second = registry.registerCustomPaintMaterialTracked(
      "material", callback, replace = true
    )

    check first.isSome
    check second.isSome
    check not registry.hasCustomPaintRegistration(first.get)
    check registry.hasCustomPaintRegistration(second.get)
    check not registry.unregisterCustomPaintMaterial(first.get)
    check registry.hasCustomPaintRegistration(second.get)
    check registry.unregisterCustomPaintMaterial(second.get)

  test "property type and inheritance errors are diagnosed":
    let ui = initUiRoot()
    discard ui.box(uiStyle([
      decl(customPaintOverlayProperty, number(4)),
      decl(customPaintUnderlayProperty, inherit())
    ]))
    var diagnostics: Diagnostics
    discard resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    check diagnostics.hasErrors

  test "material name length is bounded before registration and authoring":
    let oversized = repeat('x', maxCustomPaintMaterialBytes + 1)
    let registry = initCustomPaintRegistry()
    let callback = proc(request: CustomPaintRequest): seq[PaintCommand] = @[]

    expect ValueError:
      discard customPaint(oversized)
    expect ValueError:
      discard registry.registerCustomPaintMaterial(oversized, callback)
