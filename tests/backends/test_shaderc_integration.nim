import std/[os, tempfiles, unittest]

import clay_board_style_system/build/gpu_shader_compiler
import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder,
    gpu_shader_package]

proc vertexSource(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssVertex, "shaderc-vertex")
  let position = builder.vertexInput(gsisPosition, gsvtVec3)
  let texCoord = builder.vertexInput(gsisTexCoord0, gsvtVec2)
  builder.setPositionOutput(builder.construct(gsvtVec4, [
    builder.swizzle(position, "x"),
    builder.swizzle(position, "y"),
    builder.swizzle(position, "z"),
    builder.scalar(1'f32)
  ]))
  builder.setVaryingOutput(gsisTexCoord0, texCoord)
  builder.emitGpuShaderSource()

proc fragmentSource(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssFragment, "shaderc-fragment")
  let texCoord = builder.varyingInput(gsisTexCoord0, gsvtVec2)
  let x = builder.swizzle(texCoord, "x")
  builder.setColorOutput(builder.construct(gsvtVec4, [
    x,
    builder.scalar(0.25'f32),
    builder.scalar(0.75'f32),
    builder.scalar(1'f32)
  ]))
  builder.emitGpuShaderSource()

let shaderc = getEnv("CBSS_SHADERC")
let shaderIncludes = getEnv("CBSS_BGFX_SHADER_INCLUDE")
if shaderc.len == 0 or shaderIncludes.len == 0:
  stderr.writeLine(
    "CBSS_SHADERC and CBSS_BGFX_SHADER_INCLUDE are required for this integration test"
  )
  quit(QuitFailure)

suite "official bgfx shaderc integration":
  test "compiles generated graphics shaders and packages SPIR-V":
    let root = createTempDir("cbss-shaderc-integration-", "")
    defer:
      removeDir(root)

    let vertex = vertexSource()
    let fragment = fragmentSource()
    validateGpuShaderInterface(vertex, fragment)
    let config = gpuShaderCompilerConfig(
      shaderc,
      [shaderIncludes],
      workDirectory = root
    )
    let target = gpuShaderCompileTarget(
      gsbtVulkan,
      gscpLinux,
      "spirv"
    )

    var vertexPackage = gpuShaderPackage(vertex)
    discard vertexPackage.compileAndAddVariant(vertex, target, config)
    var fragmentPackage = gpuShaderPackage(fragment)
    discard fragmentPackage.compileAndAddVariant(fragment, target, config)

    let encodedVertex = vertexPackage.encodeGpuShaderPackage()
    let encodedFragment = fragmentPackage.encodeGpuShaderPackage()
    check encodedVertex.decodeGpuShaderPackage().artifactFor(gsbtVulkan).bytecode.len > 0
    check encodedFragment.decodeGpuShaderPackage().artifactFor(gsbtVulkan).bytecode.len > 0
