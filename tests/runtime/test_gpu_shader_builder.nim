import std/[math, strutils, unittest]

import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder]

proc buildVertexShader(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssVertex, "basic-vertex")
  let position = builder.vertexInput(gsisPosition, gsvtVec3)
  let texCoord = builder.vertexInput(gsisTexCoord0, gsvtVec2)
  let x = builder.swizzle(position, "x")
  let y = builder.swizzle(position, "y")
  let z = builder.swizzle(position, "z")
  let one = builder.scalar(1'f32)
  let clipPosition = builder.construct(gsvtVec4, [x, y, z, one])
  builder.setPositionOutput(clipPosition)
  builder.setVaryingOutput(gsisTexCoord0, texCoord)
  builder.emitGpuShaderSource()

proc buildFragmentShader(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssFragment, "accent-fragment")
  let texCoord = builder.varyingInput(gsisTexCoord0, gsvtVec2)
  let factor = builder.swizzle(texCoord, "x")
  let base = builder.vector([0.1'f32, 0.2'f32, 0.3'f32, 1'f32])
  let accent = builder.uniform("u_accent", gsvtVec4)
  let color = builder.ternary(gstMix, base, accent, factor)
  builder.setColorOutput(color)
  builder.emitGpuShaderSource()

proc buildComputeShader(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssCompute, "copy-compute")
  builder.setComputeWorkGroupSize(64, 1, 1)
  let source = builder.storageBuffer(
    "b_source", 0, gsbfFloat32x4, gsaRead
  )
  let destination = builder.storageBuffer(
    "b_destination", 1, gsbfFloat32x4, gsaReadWrite
  )
  let index = builder.swizzle(builder.globalInvocationId(), "x")
  let value = builder.loadStorage(source, index)
  builder.storeStorage(destination, index, value)
  builder.emitGpuShaderSource()

suite "typed GPU shader authoring":
  test "emits deterministic vertex and fragment source":
    let vertex = buildVertexShader()
    let fragment = buildFragmentShader()

    check vertex.stage == gssVertex
    check vertex.label == "basic-vertex"
    check vertex.source.startsWith("$input a_position, a_texcoord0\n")
    check "$output v_texcoord0" in vertex.source
    check "vec4 cbss_n" in vertex.source
    check "gl_Position = cbss_n" in vertex.source
    check "vec3 a_position : POSITION;" in vertex.varyingDefinitions
    check "vec2 a_texcoord0 : TEXCOORD0;" in vertex.varyingDefinitions
    check "vec2 v_texcoord0 : TEXCOORD0;" in vertex.varyingDefinitions

    check fragment.stage == gssFragment
    check fragment.source.startsWith("$input v_texcoord0\n")
    check "uniform vec4 u_accent;" in fragment.source
    check " = mix(" in fragment.source
    check "gl_FragColor = cbss_n" in fragment.source
    check "vec2 v_texcoord0 : TEXCOORD0;" in fragment.varyingDefinitions
    check buildFragmentShader().source == fragment.source

  test "validates a linked graphics interface":
    validateGpuShaderInterface(buildVertexShader(), buildFragmentShader())

    let incompatible = newGpuShaderBuilder(gssFragment)
    let normal = incompatible.varyingInput(gsisNormal, gsvtVec3)
    let alpha = incompatible.scalar(1'f32)
    let x = incompatible.swizzle(normal, "x")
    let color = incompatible.construct(gsvtVec4, [x, x, x, alpha])
    incompatible.setColorOutput(color)
    let fragment = incompatible.emitGpuShaderSource()
    expect GpuShaderBuildError:
      validateGpuShaderInterface(buildVertexShader(), fragment)

  test "rejects expressions from another builder":
    let first = newGpuShaderBuilder(gssFragment)
    let second = newGpuShaderBuilder(gssFragment)
    let foreign = first.scalar(1'f32)
    let local = second.scalar(2'f32)
    expect GpuShaderBuildError:
      discard second.binary(gsbAdd, foreign, local)

  test "rejects invalid operation types before source generation":
    let builder = newGpuShaderBuilder(gssFragment)
    let scalar = builder.scalar(0.5'f32)
    let vector = builder.vector([1'f32, 2'f32, 3'f32])
    expect GpuShaderBuildError:
      discard builder.binary(gsbAdd, scalar, vector)
    expect GpuShaderBuildError:
      discard builder.binary(gsbDot, scalar, scalar)
    expect GpuShaderBuildError:
      builder.setColorOutput(vector)
    expect GpuShaderBuildError:
      discard builder.swizzle(vector, "w")

  test "requires stage-correct mandatory outputs":
    let vertex = newGpuShaderBuilder(gssVertex)
    discard vertex.vertexInput(gsisPosition, gsvtVec3)
    expect GpuShaderBuildError:
      discard vertex.emitGpuShaderSource()

    let fragment = newGpuShaderBuilder(gssFragment)
    discard fragment.vector([0'f32, 0'f32, 0'f32, 1'f32])
    expect GpuShaderBuildError:
      discard fragment.emitGpuShaderSource()

    let compute = newGpuShaderBuilder(gssCompute)
    expect GpuShaderBuildError:
      discard compute.emitGpuShaderSource()

  test "uses portable uniform types and identifiers":
    let builder = newGpuShaderBuilder(gssFragment)
    expect GpuShaderBuildError:
      discard builder.uniform("time", gsvtFloat)
    expect GpuShaderBuildError:
      discard builder.uniform("bad-name", gsvtVec4)
    expect GpuShaderBuildError:
      discard builder.uniform("accent", gsvtVec4)
    expect GpuShaderBuildError:
      discard builder.uniform("u_view", gsvtMat4)
    discard builder.uniform("u_time", gsvtVec4)
    expect GpuShaderBuildError:
      discard builder.uniform("u_time", gsvtMat4)

  test "rejects non-finite constants":
    let builder = newGpuShaderBuilder(gssFragment)
    expect GpuShaderBuildError:
      discard builder.scalar(NaN.float32)
    expect GpuShaderBuildError:
      discard builder.vector([0'f32, Inf.float32])

  test "maps ergonomic Nim operators to the same typed graph":
    let vertex = newGpuShaderBuilder(gssVertex)
    let position = vertex.vertexInput(gsisPosition, gsvtVec4)
    let transform = vertex.uniform("u_transform", gsvtMat4)
    let transformed = transform * position
    vertex.setPositionOutput(transformed)
    let source = vertex.emitGpuShaderSource()
    check " = ((u_transform) * (a_position));" in source.source
    check "gl_Position = cbss_n" in source.source

    let fragment = newGpuShaderBuilder(gssFragment)
    let base = fragment.vector([0'f32, 0'f32, 0'f32, 1'f32])
    let accent = fragment.uniform("u_accent", gsvtVec4)
    let factor = fragment.scalar(0.5'f32)
    fragment.setColorOutput(mix(base, accent, factor))
    let fragmentSource = fragment.emitGpuShaderSource().source
    check " = mix(" in fragmentSource
    check "gl_FragColor = cbss_n" in fragmentSource

  test "emits shared expression graphs in linear space":
    let fragment = newGpuShaderBuilder(gssFragment)
    var value = fragment.vector([0.1'f32, 0.2'f32, 0.3'f32, 1'f32])
    for _ in 0 ..< 256:
      value = value + value
    fragment.setColorOutput(value)
    let source = fragment.emitGpuShaderSource().source
    check source.len < 64 * 1024
    check source.count("vec4 cbss_n") == 256

  test "seals the graph after successful emission":
    let builder = newGpuShaderBuilder(gssFragment)
    let color = builder.vector([1'f32, 0'f32, 0'f32, 1'f32])
    builder.setColorOutput(color)
    let first = builder.emitGpuShaderSource()
    check builder.emitGpuShaderSource().source == first.source
    expect GpuShaderBuildError:
      discard builder.scalar(1'f32)
    expect GpuShaderBuildError:
      builder.setColorOutput(color)

  test "rejects unsafe public API inputs":
    let nilBuilder: GpuShaderBuilder = nil
    expect GpuShaderBuildError:
      discard nilBuilder.vertexInput(gsisPosition, gsvtVec3)

    let builder = newGpuShaderBuilder(gssFragment)
    let color = builder.vector([1'f32, 0'f32, 0'f32, 1'f32])
    expect GpuShaderBuildError:
      discard builder.swizzle(color, "xr")

  test "wraps compiled bytes for the existing GPU host contract":
    let source = buildFragmentShader()
    let first = gpuShaderArtifact(source, @[1'u8, 2'u8, 3'u8])
    let second = gpuShaderArtifact(source, @[9'u8])
    check first.descriptor.stage == gssFragment
    check first.descriptor.label == "accent-fragment"
    check first.bytecode == @[1'u8, 2'u8, 3'u8]
    check first.sourceHash == second.sourceHash
    expect GpuShaderBuildError:
      discard gpuShaderArtifact(source, @[])

  test "enforces the bounded graph size":
    let builder = newGpuShaderBuilder(gssFragment)
    for index in 0 ..< maxGpuShaderNodes:
      discard builder.scalar(float32(index))
    expect GpuShaderBuildError:
      discard builder.scalar(0'f32)

suite "typed GPU compute shader authoring":
  test "emits deterministic compute source with ordered storage operations":
    let source = buildComputeShader()
    check source.stage == gssCompute
    check source.label == "copy-compute"
    check source.computeWorkGroupSize == [64'u32, 1'u32, 1'u32]
    check source.storageBuffers == @[
      GpuShaderStorageEntry(
        name: "b_source", stage: 0, format: gsbfFloat32x4, access: gsaRead
      ),
      GpuShaderStorageEntry(
        name: "b_destination", stage: 1, format: gsbfFloat32x4,
        access: gsaReadWrite
      )
    ]
    check source.varyingDefinitions.len == 0
    check source.source.startsWith("#include <bgfx_compute.sh>\n\n")
    check "BUFFER_RO(b_source, vec4, 0);" in source.source
    check "BUFFER_RW(b_destination, vec4, 1);" in source.source
    check "NUM_THREADS(64, 1, 1)" in source.source
    check "uint cbss_n1 = (gl_GlobalInvocationID).x;" in source.source
    check "vec4 cbss_n2 = b_source[cbss_n1];" in source.source
    check "b_destination[cbss_n1] = cbss_n2;" in source.source
    check buildComputeShader().source == source.source

  test "maps every storage format to an exact shader value type":
    let formats = [
      (gsbfInt32, gsvtInt, "int"),
      (gsbfUint32, gsvtUint, "uint"),
      (gsbfFloat32, gsvtFloat, "float"),
      (gsbfInt32x2, gsvtIVec2, "ivec2"),
      (gsbfUint32x2, gsvtUVec2, "uvec2"),
      (gsbfFloat32x2, gsvtVec2, "vec2"),
      (gsbfInt32x4, gsvtIVec4, "ivec4"),
      (gsbfUint32x4, gsvtUVec4, "uvec4"),
      (gsbfFloat32x4, gsvtVec4, "vec4")
    ]
    for index, item in formats:
      let builder = newGpuShaderBuilder(gssCompute)
      builder.setComputeWorkGroupSize(1, 1, 1)
      let input = builder.storageBuffer(
        "b_input", 0, item[0], gsaRead
      )
      let output = builder.storageBuffer(
        "b_output", 1, item[0], gsaWrite
      )
      let element = builder.loadStorage(input, builder.unsignedInteger(uint32(index)))
      check element.valueType == item[1]
      builder.storeStorage(output, builder.unsignedInteger(uint32(index)), element)
      let source = builder.emitGpuShaderSource().source
      check "BUFFER_RO(b_input, " & item[2] & ", 0);" in source
      check "BUFFER_WO(b_output, " & item[2] & ", 1);" in source

  test "exposes all portable compute invocation builtins":
    let builder = newGpuShaderBuilder(gssCompute)
    check builder.globalInvocationId().valueType == gsvtUVec3
    check builder.localInvocationId().valueType == gsvtUVec3
    check builder.workGroupId().valueType == gsvtUVec3
    check builder.localInvocationIndex().valueType == gsvtUint
    check builder.workGroupCount().valueType == gsvtUVec3

  test "supports typed integer literals vectors swizzles and arithmetic":
    let builder = newGpuShaderBuilder(gssCompute)
    let signed = builder.signedVector([-2'i32, 4'i32])
    let unsigned = builder.unsignedVector([2'u32, 4'u32, 8'u32])
    check signed.valueType == gsvtIVec2
    check builder.swizzle(signed, "y").valueType == gsvtInt
    check unsigned.valueType == gsvtUVec3
    check builder.swizzle(unsigned, "xy").valueType == gsvtUVec2
    check (builder.unsignedInteger(4) + builder.unsignedInteger(2)).valueType ==
      gsvtUint
    expect GpuShaderBuildError:
      discard -builder.unsignedInteger(1)
    expect GpuShaderBuildError:
      discard sine(builder.signedInteger(1))

  test "rejects missing and unsafe work-group sizes":
    let missing = newGpuShaderBuilder(gssCompute)
    let missingOutput = missing.storageBuffer(
      "b_output", 0, gsbfUint32, gsaWrite
    )
    let zero = missing.unsignedInteger(0)
    missing.storeStorage(missingOutput, zero, zero)
    expect GpuShaderBuildError:
      discard missing.emitGpuShaderSource()

    let invalid = newGpuShaderBuilder(gssCompute)
    for dimensions in [
      (0'u32, 1'u32, 1'u32),
      (1025'u32, 1'u32, 1'u32),
      (1'u32, 1025'u32, 1'u32),
      (1'u32, 1'u32, 65'u32),
      (33'u32, 33'u32, 1'u32)
    ]:
      expect GpuShaderBuildError:
        invalid.setComputeWorkGroupSize(dimensions[0], dimensions[1], dimensions[2])

  test "enforces compute-only storage names stages access and outputs":
    let fragment = newGpuShaderBuilder(gssFragment)
    expect GpuShaderBuildError:
      fragment.setComputeWorkGroupSize(1, 1, 1)
    expect GpuShaderBuildError:
      discard fragment.storageBuffer("b_data", 0, gsbfFloat32, gsaRead)

    let builder = newGpuShaderBuilder(gssCompute)
    builder.setComputeWorkGroupSize(1, 1, 1)
    expect GpuShaderBuildError:
      discard builder.storageBuffer("data", 0, gsbfFloat32, gsaRead)
    let readOnly = builder.storageBuffer("b_read", 0, gsbfFloat32, gsaRead)
    let writeOnly = builder.storageBuffer("b_write", 1, gsbfFloat32, gsaWrite)
    expect GpuShaderBuildError:
      discard builder.storageBuffer("b_read", 2, gsbfFloat32, gsaRead)
    expect GpuShaderBuildError:
      discard builder.storageBuffer("b_other", 1, gsbfFloat32, gsaRead)
    expect GpuShaderBuildError:
      discard builder.storageBuffer(
        "b_out_of_range", uint8(maxGpuStorageBufferBindings),
        gsbfFloat32, gsaRead
      )
    let index = builder.unsignedInteger(0)
    let value = builder.scalar(1)
    expect GpuShaderBuildError:
      discard builder.loadStorage(writeOnly, index)
    expect GpuShaderBuildError:
      builder.storeStorage(readOnly, index, value)
    expect GpuShaderBuildError:
      discard builder.loadStorage(readOnly, builder.signedInteger(0))
    expect GpuShaderBuildError:
      builder.storeStorage(writeOnly, index, builder.unsignedInteger(1))
    expect GpuShaderBuildError:
      discard builder.emitGpuShaderSource()

  test "rejects storage handles and expressions from another builder":
    let first = newGpuShaderBuilder(gssCompute)
    let second = newGpuShaderBuilder(gssCompute)
    let foreignStorage = first.storageBuffer(
      "b_first", 0, gsbfUint32, gsaReadWrite
    )
    let localIndex = second.unsignedInteger(0)
    let foreignValue = first.unsignedInteger(1)
    expect GpuShaderBuildError:
      discard second.loadStorage(foreignStorage, localIndex)
    let localStorage = second.storageBuffer(
      "b_second", 0, gsbfUint32, gsaReadWrite
    )
    expect GpuShaderBuildError:
      second.storeStorage(localStorage, localIndex, foreignValue)

  test "seals compute declarations and statements after emission":
    let builder = newGpuShaderBuilder(gssCompute)
    builder.setComputeWorkGroupSize(1, 1, 1)
    let output = builder.storageBuffer("b_output", 0, gsbfUint32, gsaWrite)
    let index = builder.unsignedInteger(0)
    builder.storeStorage(output, index, builder.unsignedInteger(1))
    let first = builder.emitGpuShaderSource()
    check builder.emitGpuShaderSource().source == first.source
    expect GpuShaderBuildError:
      discard builder.computeBuiltin(gscbGlobalInvocationId)
    expect GpuShaderBuildError:
      builder.setComputeWorkGroupSize(2, 1, 1)
