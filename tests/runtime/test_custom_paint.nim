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
