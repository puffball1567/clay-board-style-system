import std/[strutils, unittest]

import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder,
    gpu_shader_package]

proc fragmentSource(label = "package-fragment"): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssFragment, label)
  builder.setColorOutput(builder.vector([0.1'f32, 0.2'f32, 0.3'f32, 1'f32]))
  builder.emitGpuShaderSource()

proc computeSource(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssCompute, "package-compute")
  builder.setComputeWorkGroupSize(8, 8, 1)
  let buffer = builder.storageBuffer(
    "b_cells", 1, gsbfFloat32x4, gsaReadWrite
  )
  let image = builder.storageImage("i_output", 3, gtfRgba32F, gsaWrite)
  discard builder.uniform("u_material", gsvtVec4)
  discard builder.uniform("u_timing", gsvtMat4)
  let index = builder.unsignedInteger(0)
  builder.storeStorage(buffer, index, builder.loadStorage(buffer, index))
  builder.storeStorageImage(
    image,
    builder.signedVector([0'i32, 0'i32]),
    builder.vector([0'f32, 0'f32, 0'f32, 1'f32])
  )
  builder.emitGpuShaderSource()

suite "GPU shader packages":
  test "round trips variants in a deterministic target order":
    let source = fragmentSource()
    var first = gpuShaderPackage(source)
    first.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8, 2, 3]))
    first.addVariant(gsbtMetal, gpuShaderArtifact(source, @[4'u8, 5]))

    var second = gpuShaderPackage(source)
    second.addVariant(gsbtMetal, gpuShaderArtifact(source, @[4'u8, 5]))
    second.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8, 2, 3]))

    let encoded = first.encodeGpuShaderPackage()
    check encoded == second.encodeGpuShaderPackage()
    let decoded = encoded.decodeGpuShaderPackage()
    check decoded.descriptor == first.descriptor
    check decoded.bindingLayout == GpuShaderBindingLayout(known: true)
    check decoded.sourceHash == first.sourceHash
    check decoded.artifactFor(gsbtMetal).bytecode == @[4'u8, 5]
    check decoded.artifactFor(gsbtVulkan).bytecode == @[1'u8, 2, 3]
    check first.encodeGpuShaderPackageData().decodeGpuShaderPackage()
      .artifactFor(gsbtVulkan).bytecode == @[1'u8, 2, 3]

  test "round trips typed compute binding layouts":
    let source = computeSource()
    var package = gpuShaderPackage(source)
    package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8, 2, 3]))
    let decoded = package.encodeGpuShaderPackage().decodeGpuShaderPackage()
    check decoded.bindingLayout == GpuShaderBindingLayout(
      known: true,
      uniforms: @[
        GpuShaderUniformLayout(
          nameId: gpuBindingNameId("u_material"),
          uniformType: gutVec4,
          arrayLength: 1
        ),
        GpuShaderUniformLayout(
          nameId: gpuBindingNameId("u_timing"),
          uniformType: gutMat4,
          arrayLength: 1
        )
      ],
      storageBuffers: @[
        GpuShaderStorageBufferLayout(
          stage: 1, format: gsbfFloat32x4, access: gsaReadWrite
        )
      ],
      storageImages: @[
        GpuShaderStorageImageLayout(
          stage: 3, format: gtfRgba32F, access: gsaWrite
        )
      ]
    )
    check decoded.artifactFor(gsbtVulkan).bindingLayout == decoded.bindingLayout

  test "rejects duplicate targets and mismatched source metadata":
    let source = fragmentSource()
    var package = gpuShaderPackage(source)
    package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8]))
    expect GpuShaderPackageError:
      package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[2'u8]))

    let otherSource = fragmentSource("other-fragment")
    expect GpuShaderPackageError:
      package.addVariant(gsbtMetal, gpuShaderArtifact(otherSource, @[3'u8]))

    var wrongStage = gpuShaderArtifact(source, @[4'u8])
    wrongStage.descriptor.stage = gssVertex
    expect GpuShaderPackageError:
      package.addVariant(gsbtOpenGL, wrongStage)

    var wrongLayout = gpuShaderArtifact(source, @[5'u8])
    wrongLayout.bindingLayout.known = false
    expect GpuShaderPackageError:
      package.addVariant(gsbtOpenGL, wrongLayout)

  test "rejects absent and mutated variants":
    let source = fragmentSource()
    var package = gpuShaderPackage(source)
    package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8, 2, 3]))
    expect GpuShaderPackageError:
      discard package.artifactFor(gsbtMetal)

    package.variants[0].bytecode[1] = 9
    expect GpuShaderPackageError:
      discard package.artifactFor(gsbtVulkan)
    expect GpuShaderPackageError:
      discard package.encodeGpuShaderPackage()

  test "rejects malformed serialized packages":
    let source = fragmentSource()
    var package = gpuShaderPackage(source)
    package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8, 2, 3]))
    let valid = package.encodeGpuShaderPackage()

    var wrongMagic = valid
    wrongMagic[0] = byte('X')
    expect GpuShaderPackageError:
      discard wrongMagic.decodeGpuShaderPackage()

    var wrongVersion = valid
    wrongVersion[8] = 4
    expect GpuShaderPackageError:
      discard wrongVersion.decodeGpuShaderPackage()

    var reservedHeader = valid
    reservedHeader[11] = 1
    expect GpuShaderPackageError:
      discard reservedHeader.decodeGpuShaderPackage()

    let layoutOffset = 24 + source.label.len
    var invalidLayoutFlags = valid
    invalidLayoutFlags[layoutOffset] = 2
    expect GpuShaderPackageError:
      discard invalidLayoutFlags.decodeGpuShaderPackage()

    var invalidUniformCount = valid
    invalidUniformCount[layoutOffset + 3] = 255
    expect GpuShaderPackageError:
      discard invalidUniformCount.decodeGpuShaderPackage()

    let variantOffset = layoutOffset + 4
    var unknownTarget = valid
    unknownTarget[variantOffset] = 255
    expect GpuShaderPackageError:
      discard unknownTarget.decodeGpuShaderPackage()

    var reservedVariant = valid
    reservedVariant[variantOffset + 1] = 1
    expect GpuShaderPackageError:
      discard reservedVariant.decodeGpuShaderPackage()

    var corruptPayload = valid
    corruptPayload[^1] = corruptPayload[^1] xor 0xff'u8
    expect GpuShaderPackageError:
      discard corruptPayload.decodeGpuShaderPackage()

    expect GpuShaderPackageError:
      discard valid[0 ..< valid.high].decodeGpuShaderPackage()

    var trailing = valid
    trailing.add 0'u8
    expect GpuShaderPackageError:
      discard trailing.decodeGpuShaderPackage()

  test "decodes version one packages with an unknown binding layout":
    let source = fragmentSource()
    var package = gpuShaderPackage(source)
    package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8, 2, 3]))
    let current = package.encodeGpuShaderPackage()
    let layoutOffset = 24 + source.label.len
    var legacy = current[0 ..< layoutOffset]
    legacy.add current[layoutOffset + 4 .. current.high]
    legacy[8] = 1
    legacy[9] = 0
    let decoded = legacy.decodeGpuShaderPackage()
    check decoded.bindingLayout == GpuShaderBindingLayout()
    check decoded.artifactFor(gsbtVulkan).bytecode == @[1'u8, 2, 3]

  test "decodes version two packages without uniform metadata":
    let source = fragmentSource()
    var package = gpuShaderPackage(source)
    package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8, 2, 3]))
    var legacy = package.encodeGpuShaderPackage()
    legacy[8] = 2
    legacy[9] = 0
    let decoded = legacy.decodeGpuShaderPackage()
    check decoded.bindingLayout == GpuShaderBindingLayout(known: true)
    check decoded.artifactFor(gsbtVulkan).bytecode == @[1'u8, 2, 3]

  test "rejects malformed serialized binding layout entries":
    let source = computeSource()
    var package = gpuShaderPackage(source)
    package.addVariant(gsbtVulkan, gpuShaderArtifact(source, @[1'u8]))
    let valid = package.encodeGpuShaderPackage()
    let layoutOffset = 24 + source.label.len
    let bufferOffset = layoutOffset + 4
    let imageOffset = bufferOffset + 4
    let uniformOffset = imageOffset + 4

    var invalidBufferFormat = valid
    invalidBufferFormat[bufferOffset + 1] = 255
    expect GpuShaderPackageError:
      discard invalidBufferFormat.decodeGpuShaderPackage()

    var invalidImageAccess = valid
    invalidImageAccess[imageOffset + 2] = 255
    expect GpuShaderPackageError:
      discard invalidImageAccess.decodeGpuShaderPackage()

    var reservedEntry = valid
    reservedEntry[imageOffset + 3] = 1
    expect GpuShaderPackageError:
      discard reservedEntry.decodeGpuShaderPackage()

    var sharedStage = valid
    sharedStage[imageOffset] = sharedStage[bufferOffset]
    expect GpuShaderPackageError:
      discard sharedStage.decodeGpuShaderPackage()

    var invalidUniformType = valid
    invalidUniformType[uniformOffset + 8] = 255
    expect GpuShaderPackageError:
      discard invalidUniformType.decodeGpuShaderPackage()

    var reservedUniform = valid
    reservedUniform[uniformOffset + 9] = 1
    expect GpuShaderPackageError:
      discard reservedUniform.decodeGpuShaderPackage()

    var zeroUniformLength = valid
    zeroUniformLength[uniformOffset + 10] = 0
    zeroUniformLength[uniformOffset + 11] = 0
    expect GpuShaderPackageError:
      discard zeroUniformLength.decodeGpuShaderPackage()

    var duplicateUniformName = valid
    let secondUniformOffset = uniformOffset + 12
    for index in 0 ..< 8:
      duplicateUniformName[secondUniformOffset + index] =
        duplicateUniformName[uniformOffset + index]
    expect GpuShaderPackageError:
      discard duplicateUniformName.decodeGpuShaderPackage()

  test "rejects malformed in-memory package construction":
    let source = fragmentSource()
    var empty = gpuShaderPackage(source)
    expect GpuShaderPackageError:
      discard empty.encodeGpuShaderPackage()

    var oversizedLabel = empty
    oversizedLabel.descriptor.label = repeat('x', maxGpuResourceLabelBytes + 1)
    expect GpuShaderPackageError:
      discard oversizedLabel.encodeGpuShaderPackage()

    var unknownWithEntries = empty
    unknownWithEntries.bindingLayout = GpuShaderBindingLayout(
      storageBuffers: @[
        GpuShaderStorageBufferLayout(
          stage: 0, format: gsbfFloat32, access: gsaRead
        )
      ]
    )
    expect GpuShaderPackageError:
      discard unknownWithEntries.encodeGpuShaderPackage()

    var duplicateUniforms = empty
    duplicateUniforms.bindingLayout = GpuShaderBindingLayout(
      known: true,
      uniforms: @[
        GpuShaderUniformLayout(
          nameId: gpuBindingNameId("u_first"),
          uniformType: gutVec4,
          arrayLength: 1
        ),
        GpuShaderUniformLayout(
          nameId: gpuBindingNameId("u_first"),
          uniformType: gutMat4,
          arrayLength: 1
        )
      ]
    )
    expect GpuShaderPackageError:
      discard duplicateUniforms.encodeGpuShaderPackage()

    var zeroUniformLength = empty
    zeroUniformLength.bindingLayout = GpuShaderBindingLayout(
      known: true,
      uniforms: @[
        GpuShaderUniformLayout(
          nameId: gpuBindingNameId("u_invalid"),
          uniformType: gutVec4
        )
      ]
    )
    expect GpuShaderPackageError:
      discard zeroUniformLength.encodeGpuShaderPackage()

    let artifact = gpuShaderArtifact(source, @[1'u8])
    var duplicate = gpuShaderPackage(source)
    duplicate.variants = @[
      GpuShaderBinaryVariant(
        target: gsbtVulkan,
        bytecode: artifact.bytecode,
        bytecodeHash: artifact.bytecode.hashGpuShaderBytes()
      ),
      GpuShaderBinaryVariant(
        target: gsbtVulkan,
        bytecode: artifact.bytecode,
        bytecodeHash: artifact.bytecode.hashGpuShaderBytes()
      )
    ]
    expect GpuShaderPackageError:
      discard duplicate.encodeGpuShaderPackage()
