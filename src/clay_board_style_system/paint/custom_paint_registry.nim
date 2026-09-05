import std/[algorithm, options, sets, tables]

import ../core/[custom_paint, geometry, node]
import ./paint_command

const
  maxCustomPaintDiagnostics* = 256
  maxCustomPaintCommands* = 4096

type
  CustomPaintResolutionStatus* = enum
    cprsResolved,
    cprsInvalidRequest,
    cprsMissingMaterial,
    cprsUnsupportedStage,
    cprsInvalidCommands

  CustomPaintDiagnostic* = object
    status*: CustomPaintResolutionStatus
    owner*: NodeId
    material*: string
    stage*: CustomPaintStage
    message*: string

  CustomPaintRequest* = object
    material*: string
    stage*: CustomPaintStage
    owner*: NodeId
    bounds*: Rect
    opacity*: float32

  CustomPaintResolution* = object
    status*: CustomPaintResolutionStatus
    commands*: seq[PaintCommand]

  CustomPaintMaterialProc* = proc(
    request: CustomPaintRequest
  ): seq[PaintCommand] {.closure, raises: [].}

  CustomPaintProvider* = proc(
    request: CustomPaintRequest
  ): CustomPaintResolution {.closure, raises: [].}

  CustomPaintMaterialEntry = object
    callback: CustomPaintMaterialProc
    stages: set[CustomPaintStage]
    generation: uint64

  CustomPaintConsumerSet = ref HashSet[NodeId]

  CustomPaintRegistration* = object
    material*: string
    generation*: uint64

  CustomPaintRegistry* = ref object
    materials: Table[string, CustomPaintMaterialEntry]
    consumers: Table[string, CustomPaintConsumerSet]
    nextGeneration: uint64
    diagnostics: seq[CustomPaintDiagnostic]
    diagnosticKeys: HashSet[string]

proc initCustomPaintRegistry*(): CustomPaintRegistry =
  CustomPaintRegistry(
    materials: initTable[string, CustomPaintMaterialEntry](),
    consumers: initTable[string, CustomPaintConsumerSet](),
    nextGeneration: 0,
    diagnostics: @[],
    diagnosticKeys: initHashSet[string]()
  )

proc addDiagnostic(
    registry: CustomPaintRegistry;
    request: CustomPaintRequest;
    status: CustomPaintResolutionStatus;
    message: string
) =
  if registry.isNil or registry.diagnostics.len >= maxCustomPaintDiagnostics:
    return
  let key = $request.owner.nodeRawValue & ":" & $ord(request.stage) & ":" &
    request.material & ":" & $ord(status)
  if key in registry.diagnosticKeys:
    return
  registry.diagnosticKeys.incl key
  registry.diagnostics.add CustomPaintDiagnostic(
    status: status,
    owner: request.owner,
    material: request.material,
    stage: request.stage,
    message: message
  )

proc registerCustomPaintMaterialTracked*(
    registry: CustomPaintRegistry;
    material: string;
    callback: CustomPaintMaterialProc;
    stages: set[CustomPaintStage] = {cpsUnderlay, cpsOverlay};
    replace = false
): Option[CustomPaintRegistration] =
  if registry.isNil:
    raise newException(ValueError, "custom paint registry cannot be nil")
  if not material.validCustomPaintMaterial:
    raise newException(ValueError, "custom paint material name is invalid")
  if callback.isNil:
    raise newException(ValueError, "custom paint material callback cannot be nil")
  if stages == {}:
    raise newException(ValueError, "custom paint material requires a paint stage")
  if cpsMask in stages or cpsFilter in stages:
    raise newException(
      ValueError,
      "mask and filter custom paint stages are not implemented"
    )
  if material in registry.materials and not replace:
    return none(CustomPaintRegistration)
  if registry.nextGeneration == high(uint64):
    raise newException(ValueError, "custom paint registration space exhausted")
  inc registry.nextGeneration
  registry.materials[material] = CustomPaintMaterialEntry(
    callback: callback,
    stages: stages,
    generation: registry.nextGeneration
  )
  some(CustomPaintRegistration(
    material: material,
    generation: registry.nextGeneration
  ))

proc registerCustomPaintMaterial*(
    registry: CustomPaintRegistry;
    material: string;
    callback: CustomPaintMaterialProc;
    stages: set[CustomPaintStage] = {cpsUnderlay, cpsOverlay};
    replace = false
): bool {.discardable.} =
  registry.registerCustomPaintMaterialTracked(
    material, callback, stages, replace
  ).isSome

proc unregisterCustomPaintMaterial*(
    registry: CustomPaintRegistry;
    material: string
): bool {.discardable.} =
  if registry.isNil or material notin registry.materials:
    return false
  registry.materials.del material
  true

proc unregisterCustomPaintMaterial*(
    registry: CustomPaintRegistry;
    registration: CustomPaintRegistration
): bool {.discardable.} =
  if registry.isNil or registration.material notin registry.materials:
    return false
  let entry = registry.materials.getOrDefault(registration.material)
  if entry.generation != registration.generation:
    return false
  registry.materials.del registration.material
  true

proc hasCustomPaintMaterial*(
    registry: CustomPaintRegistry;
    material: string
): bool =
  not registry.isNil and material in registry.materials

proc hasCustomPaintRegistration*(
    registry: CustomPaintRegistry;
    registration: CustomPaintRegistration
): bool =
  if registry.isNil or registration.material notin registry.materials:
    return false
  registry.materials.getOrDefault(registration.material).generation ==
    registration.generation

proc noteConsumer(registry: CustomPaintRegistry; material: string; owner: NodeId) =
  if registry.isNil:
    return
  var owners = registry.consumers.getOrDefault(material)
  if owners.isNil:
    new(owners)
    owners[] = initHashSet[NodeId]()
    registry.consumers[material] = owners
  owners[].incl owner

proc customPaintConsumers*(
    registry: CustomPaintRegistry;
    material: string
): seq[NodeId] =
  if registry.isNil or material notin registry.consumers:
    return
  let owners = registry.consumers.getOrDefault(material)
  if owners.isNil:
    return
  for owner in owners[]:
    result.add owner
  result.sort(proc(a, b: NodeId): int =
    cmp(a.nodeRawValue(), b.nodeRawValue())
  )

proc clearCustomPaintConsumers*(registry: CustomPaintRegistry) =
  if not registry.isNil:
    registry.consumers.clear()

proc removeCustomPaintConsumers*(
    registry: CustomPaintRegistry;
    removed: HashSet[NodeId]
) =
  if registry.isNil or removed.len == 0:
    return
  var emptyMaterials: seq[string]
  for material, owners in registry.consumers.mpairs:
    if owners.isNil:
      emptyMaterials.add material
      continue
    for owner in removed:
      owners[].excl owner
    if owners[].len == 0:
      emptyMaterials.add material
  for material in emptyMaterials:
    registry.consumers.del material

proc balanced(commands: openArray[PaintCommand]): bool =
  var transformDepth = 0
  var clipDepth = 0
  var layerDepth = 0
  for command in commands:
    case command.kind
    of pcPushTransform:
      inc transformDepth
    of pcPopTransform:
      dec transformDepth
    of pcPushClip:
      inc clipDepth
    of pcPopClip:
      dec clipDepth
    of pcPushLayer:
      inc layerDepth
    of pcPopLayer:
      dec layerDepth
    else:
      discard
    if transformDepth < 0 or clipDepth < 0 or layerDepth < 0:
      return false
  transformDepth == 0 and clipDepth == 0 and layerDepth == 0

proc resolveCustomPaint*(
    registry: CustomPaintRegistry;
    request: CustomPaintRequest
): CustomPaintResolution {.raises: [].} =
  if not request.material.validCustomPaintMaterial:
    if not registry.isNil:
      var diagnosticRequest = request
      diagnosticRequest.material = "<invalid>"
      registry.addDiagnostic(
        diagnosticRequest,
        cprsInvalidRequest,
        "custom paint material name is invalid"
      )
    return CustomPaintResolution(status: cprsInvalidRequest)
  if not registry.isNil:
    registry.noteConsumer(request.material, request.owner)
  if request.stage in {cpsMask, cpsFilter}:
    if not registry.isNil:
      registry.addDiagnostic(
        request,
        cprsUnsupportedStage,
        "custom paint mask and filter composition is not implemented"
      )
    return CustomPaintResolution(status: cprsUnsupportedStage)

  if registry.isNil or request.material notin registry.materials:
    if not registry.isNil:
      registry.addDiagnostic(
        request,
        cprsMissingMaterial,
        "custom paint material is not registered"
      )
    return CustomPaintResolution(status: cprsMissingMaterial)

  let entry = registry.materials.getOrDefault(request.material)
  if request.stage notin entry.stages:
    registry.addDiagnostic(
      request,
      cprsUnsupportedStage,
      "custom paint material does not support the requested stage"
    )
    return CustomPaintResolution(status: cprsUnsupportedStage)

  let commands = entry.callback(request)
  if commands.len > maxCustomPaintCommands:
    registry.addDiagnostic(
      request,
      cprsInvalidCommands,
      "custom paint material exceeded the command limit"
    )
    return CustomPaintResolution(status: cprsInvalidCommands)
  if not commands.balanced:
    registry.addDiagnostic(
      request,
      cprsInvalidCommands,
      "custom paint material returned an unbalanced command stream"
    )
    return CustomPaintResolution(status: cprsInvalidCommands)
  CustomPaintResolution(status: cprsResolved, commands: commands)

proc provider*(registry: CustomPaintRegistry): CustomPaintProvider =
  let retained = registry
  result = proc(
      request: CustomPaintRequest
  ): CustomPaintResolution {.raises: [].} =
    retained.resolveCustomPaint(request)

proc takeCustomPaintDiagnostics*(
    registry: CustomPaintRegistry
): seq[CustomPaintDiagnostic] =
  if registry.isNil:
    return
  result = registry.diagnostics
  registry.diagnostics = @[]
  registry.diagnosticKeys.clear()

proc clearCustomPaintDiagnostics*(registry: CustomPaintRegistry) =
  if registry.isNil:
    return
  registry.diagnostics = @[]
  registry.diagnosticKeys.clear()
