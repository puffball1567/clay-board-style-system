import std/[strutils, unittest]

import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder,
    gpu_shader_package]

proc fragmentSource(label = "package-fragment"): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssFragment, label)
  builder.setColorOutput(builder.vector([0.1'f32, 0.2'f32, 0.3'f32, 1'f32]))
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
    check decoded.sourceHash == first.sourceHash
    check decoded.artifactFor(gsbtMetal).bytecode == @[4'u8, 5]
    check decoded.artifactFor(gsbtVulkan).bytecode == @[1'u8, 2, 3]
    check first.encodeGpuShaderPackageData().decodeGpuShaderPackage()
      .artifactFor(gsbtVulkan).bytecode == @[1'u8, 2, 3]

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
    wrongVersion[8] = 2
    expect GpuShaderPackageError:
      discard wrongVersion.decodeGpuShaderPackage()

    var reservedHeader = valid
    reservedHeader[11] = 1
    expect GpuShaderPackageError:
      discard reservedHeader.decodeGpuShaderPackage()

    let variantOffset = 24 + source.label.len
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

  test "rejects malformed in-memory package construction":
    let source = fragmentSource()
    var empty = gpuShaderPackage(source)
    expect GpuShaderPackageError:
      discard empty.encodeGpuShaderPackage()

    var oversizedLabel = empty
    oversizedLabel.descriptor.label = repeat('x', maxGpuResourceLabelBytes + 1)
    expect GpuShaderPackageError:
      discard oversizedLabel.encodeGpuShaderPackage()

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
