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
