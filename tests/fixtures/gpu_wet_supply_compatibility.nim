import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder,
    gpu_shader_records]

proc buildWetSupplyCompatibilityShader*(): GpuShaderSource =
  let cellLayout = gpuPackedRecordLayout([
    gpuPackedFieldAt("liquidVolume", gsvtFloat, 0),
    gpuPackedFieldAt("mobilePigmentMass", gsvtFloat, 1),
    gpuPackedFieldAt("pigmentMass", gsvtFloat, 2),
    gpuPackedFieldAt("settledPigmentMass", gsvtFloat, 3),
    gpuPackedFieldAt("binderMass", gsvtFloat, 4),
    gpuPackedFieldAt("intrinsicViscosity", gsvtFloat, 5),
    gpuPackedFieldAt("intrinsicYieldStress", gsvtFloat, 6),
    gpuPackedFieldAt("microHeight", gsvtFloat, 7),
    gpuPackedFieldAt("roughness", gsvtFloat, 8),
    gpuPackedFieldAt("sizing", gsvtFloat, 9),
    gpuPackedFieldAt("absorbedLiquid", gsvtFloat, 10),
    gpuPackedFieldAt("liquidCapacity", gsvtFloat, 11),
    gpuPackedFieldAt("advancingAngleDegrees", gsvtFloat, 12),
    gpuPackedFieldAt("recedingAngleDegrees", gsvtFloat, 13),
    gpuPackedFieldAt("meanPoreRadiusMicrometers", gsvtFloat, 14),
    gpuPackedFieldAt("mobileParticleRadiusMicrometers", gsvtFloat, 15),
    gpuPackedFieldAt("mobileParticleSizeSpread", gsvtFloat, 16),
    gpuPackedFieldAt("domainId", gsvtUint, 17)
  ], wordStride = 18)
  let edgeLayout = gpuPackedRecordLayout([
    gpuPackedFieldAt("requestedLiquid", gsvtFloat, 0),
    gpuPackedFieldAt("transferredLiquid", gsvtFloat, 1),
    gpuPackedFieldAt("transferredPigmentMass", gsvtFloat, 2),
    gpuPackedFieldAt("transferredBinderMass", gsvtFloat, 3),
    gpuPackedFieldAt("source", gsvtUint, 4),
    gpuPackedFieldAt("destination", gsvtUint, 5),
    gpuPackedFieldAt("pinned", gsvtUint, 6),
    gpuPackedFieldAt("padding", gsvtUint, 7)
  ], wordStride = 8)
  let packedEdgeLayout = gpuPackedRecordLayout([
    gpuPackedFieldAt("transferredLiquid", gsvtFloat, 0),
    gpuPackedFieldAt("transferredPigmentMass", gsvtFloat, 1),
    gpuPackedFieldAt("transferredBinderMass", gsvtFloat, 2),
    gpuPackedFieldAt("metadata", gsvtUint, 3)
  ], wordStride = 4)
  let parameterLayout = gpuPackedRecordLayout([
    gpuPackedFieldAt("width", gsvtUint, 0),
    gpuPackedFieldAt("height", gsvtUint, 1),
    gpuPackedFieldAt("cellCount", gsvtUint, 2),
    gpuPackedFieldAt("padding", gsvtUint, 3),
    gpuPackedFieldAt("liquidFlowRate", gsvtFloat, 4),
    gpuPackedFieldAt("hydraulicPressureScale", gsvtFloat, 5),
    gpuPackedFieldAt("solventViscosity", gsvtFloat, 6),
    gpuPackedFieldAt("surfaceTension", gsvtFloat, 7),
    gpuPackedFieldAt("deltaTime", gsvtFloat, 8),
    gpuPackedFieldAt("pigmentMobility", gsvtFloat, 9),
    gpuPackedFieldAt("binderMobility", gsvtFloat, 10),
    gpuPackedFieldAt("packOutput", gsvtUint, 11)
  ], wordStride = 12)

  let builder = newGpuShaderBuilder(gssCompute, "wet-supply-compatibility")
  builder.setComputeWorkGroupSize(64, 1, 1)
  let cells = builder.packedRecordBuffer("b_cells", 0, cellLayout, gsaRead)
  let edges = builder.packedRecordBuffer("b_edges", 1, edgeLayout, gsaReadWrite)
  let parameters = builder.packedRecordBuffer(
    "b_parameters", 2, parameterLayout, gsaRead
  )
  let packedEdges = builder.packedRecordBuffer(
    "b_packed_edges", 3, packedEdgeLayout, gsaWrite
  )

  let zeroIndex = builder.unsignedInteger(0)
  let zeroUint = builder.unsignedInteger(0)
  let oneUint = builder.unsignedInteger(1)
  let twoUint = builder.unsignedInteger(2)
  let threeUint = builder.unsignedInteger(3)
  let fourUint = builder.unsignedInteger(4)
  let source = builder.swizzle(builder.globalInvocationId(), "x")
  let width = parameters.loadPackedField(zeroIndex, "width")
  let height = parameters.loadPackedField(zeroIndex, "height")
  let cellCount = parameters.loadPackedField(zeroIndex, "cellCount")
  let pigmentMobility = parameters.loadPackedField(zeroIndex, "pigmentMobility")
  let binderMobility = parameters.loadPackedField(zeroIndex, "binderMobility")
  let packOutput = parameters.loadPackedField(zeroIndex, "packOutput")

  builder.beginIf(greaterThanOrEqual(source, cellCount))
  builder.returnFromCompute()
  builder.endIf()

  let x = builder.binary(gsbModulo, source, width)
  let y = source / width
  let sentinel = cellCount * fourUint
  let candidates = builder.localArray(sentinel, 8)

  builder.beginIf(lessThan(x + oneUint, width))
  candidates.storeLocalArray(zeroUint, source * fourUint)
  builder.endIf()

  builder.beginIf(lessThan(y + oneUint, height))
  candidates.storeLocalArray(oneUint, source * fourUint + oneUint)
  builder.endIf()

  builder.beginIf(logicalAnd(
    lessThan(x + oneUint, width),
    lessThan(y + oneUint, height)
  ))
  candidates.storeLocalArray(twoUint, source * fourUint + twoUint)
  builder.endIf()

  builder.beginIf(logicalAnd(
    greaterThan(x, zeroUint),
    lessThan(y + oneUint, height)
  ))
  candidates.storeLocalArray(threeUint, source * fourUint + threeUint)
  builder.endIf()

  builder.beginIf(greaterThan(x, zeroUint))
  candidates.storeLocalArray(
    builder.unsignedInteger(4),
    (source - oneUint) * fourUint
  )
  builder.endIf()

  builder.beginIf(greaterThan(y, zeroUint))
  candidates.storeLocalArray(
    builder.unsignedInteger(5),
    (source - width) * fourUint + oneUint
  )
  builder.endIf()

  builder.beginIf(logicalAnd(
    greaterThan(x, zeroUint),
    greaterThan(y, zeroUint)
  ))
  candidates.storeLocalArray(
    builder.unsignedInteger(6),
    (source - width - oneUint) * fourUint + twoUint
  )
  builder.endIf()

  builder.beginIf(logicalAnd(
    lessThan(x + oneUint, width),
    greaterThan(y, zeroUint)
  ))
  candidates.storeLocalArray(
    builder.unsignedInteger(7),
    (source - width + oneUint) * fourUint + threeUint
  )
  builder.endIf()

  let outgoing = builder.localValue(builder.scalar(0))
  let outgoingCandidate = builder.beginForRange(0'u32, 8'u32, 1'u32)
  let outgoingSlot = candidates.loadLocalArray(outgoingCandidate.loadLocal())
  builder.beginIf(logicalAnd(
    lessThan(outgoingSlot, sentinel),
    equalTo(edges.loadPackedField(outgoingSlot, "source"), source)
  ))
  outgoing.storeLocal(
    outgoing.loadLocal() + edges.loadPackedField(outgoingSlot, "requestedLiquid")
  )
  builder.endIf()
  builder.endForRange()

  let scale = builder.localValue(builder.scalar(1))
  builder.beginIf(greaterThan(outgoing.loadLocal(), builder.scalar(0)))
  scale.storeLocal(minimum(
    cells.loadPackedField(source, "liquidVolume") / outgoing.loadLocal(),
    builder.scalar(1)
  ))
  builder.endIf()

  let transferCandidate = builder.beginForRange(0'u32, 8'u32, 1'u32)
  let slot = candidates.loadLocalArray(transferCandidate.loadLocal())
  builder.beginIf(logicalAnd(
    lessThan(slot, sentinel),
    equalTo(edges.loadPackedField(slot, "source"), source)
  ))
  let transferredLiquid = edges.loadPackedField(slot, "requestedLiquid") *
    scale.loadLocal()
  edges.storePackedField(slot, "transferredLiquid", transferredLiquid)

  let liquidVolume = cells.loadPackedField(source, "liquidVolume")
  builder.beginIf(logicalAnd(
    greaterThan(transferredLiquid, builder.scalar(0)),
    greaterThan(liquidVolume, builder.scalar(0))
  ))
  let liquidFraction = clamp(
    transferredLiquid / liquidVolume,
    builder.scalar(0),
    builder.scalar(1)
  )
  let radius = cells.loadPackedField(source, "mobileParticleRadiusMicrometers")
  let particleAdvection = builder.localValue(builder.scalar(1))
  builder.beginIf(greaterThan(radius, builder.scalar(1.1920929e-7'f32)))
  let radiusSquared = radius * radius
  let stokesFraction = radiusSquared / (radiusSquared + builder.scalar(2.25))
  let spread = cells.loadPackedField(source, "mobileParticleSizeSpread")
  particleAdvection.storeLocal(clamp(
    builder.scalar(1) - stokesFraction *
      (builder.scalar(0.52) + builder.scalar(0.18) * spread),
    builder.scalar(0.25),
    builder.scalar(1)
  ))
  builder.endIf()
  edges.storePackedField(
    slot,
    "transferredPigmentMass",
    cells.loadPackedField(source, "mobilePigmentMass") * liquidFraction *
      pigmentMobility * particleAdvection.loadLocal()
  )
  edges.storePackedField(
    slot,
    "transferredBinderMass",
    cells.loadPackedField(source, "binderMass") * liquidFraction * binderMobility
  )
  builder.endIf()

  builder.beginIf(notEqualTo(packOutput, zeroUint))
  let metadata = builder.localValue(zeroUint)
  builder.beginIf(greaterThan(
    transferredLiquid,
    builder.scalar(1.1920929e-7'f32)
  ))
  metadata.storeLocal(metadata.loadLocal().bitwiseOr(oneUint))
  builder.endIf()
  builder.beginIf(notEqualTo(edges.loadPackedField(slot, "pinned"), zeroUint))
  metadata.storeLocal(metadata.loadLocal().bitwiseOr(twoUint))
  builder.endIf()
  builder.beginIf(notEqualTo(
    edges.loadPackedField(slot, "source"),
    slot / fourUint
  ))
  metadata.storeLocal(metadata.loadLocal().bitwiseOr(fourUint))
  builder.endIf()
  packedEdges.storePackedField(
    slot,
    "transferredLiquid",
    edges.loadPackedField(slot, "transferredLiquid")
  )
  packedEdges.storePackedField(
    slot,
    "transferredPigmentMass",
    edges.loadPackedField(slot, "transferredPigmentMass")
  )
  packedEdges.storePackedField(
    slot,
    "transferredBinderMass",
    edges.loadPackedField(slot, "transferredBinderMass")
  )
  packedEdges.storePackedField(slot, "metadata", metadata.loadLocal())
  builder.endIf()
  builder.endIf()
  builder.endForRange()

  builder.emitGpuShaderSource()
