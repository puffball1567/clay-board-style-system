import std/[os, strutils, tempfiles, unittest]

import clay_board_style_system/build/gpu_shader_compiler
import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder,
    gpu_shader_package]

proc argumentValue(arguments: seq[string]; name: string): string =
  for index in 0 ..< arguments.high:
    if arguments[index] == name:
      return arguments[index + 1]

proc runFakeShaderc() =
  let arguments = commandLineParams()
  let outputPath = arguments.argumentValue("-o")
  let sourcePath = arguments.argumentValue("-f")
  let profile = arguments.argumentValue("--profile")
  if outputPath.len == 0 or sourcePath.len == 0 or not fileExists(sourcePath):
    stderr.writeLine("fake shaderc received invalid arguments")
    quit(31)
  if "--varyingdef" in arguments:
    let varyingPath = arguments.argumentValue("--varyingdef")
    if varyingPath.len == 0 or not fileExists(varyingPath):
      stderr.writeLine("fake shaderc received no varying definitions")
      quit(32)

  case profile
  of "fake_fail":
    stderr.writeLine("intentional compiler failure")
    quit(7)
  of "fake_missing":
    quit(0)
  of "fake_empty":
    writeFile(outputPath, "")
  of "fake_loud":
    stdout.write(repeat('x', 128))
    writeFile(outputPath, "BIN")
  else:
    stdout.write("compiled " & profile)
    writeFile(outputPath, "CBSS")
  quit(0)

if "--type" in commandLineParams():
  runFakeShaderc()

proc fragmentSource(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssFragment, "compiler-fragment")
  builder.setColorOutput(builder.vector([0.2'f32, 0.4'f32, 0.6'f32, 1'f32]))
  builder.emitGpuShaderSource()

proc target(profile = "fake_ok"): GpuShaderCompileTarget =
  gpuShaderCompileTarget(gsbtVulkan, gscpLinux, profile)

proc testConfig(
    root: string;
    diagnostics = defaultGpuShaderDiagnosticBytes
): GpuShaderCompilerConfig =
  gpuShaderCompilerConfig(
    getAppFilename(),
    [root],
    workDirectory = root,
    diagnosticByteLimit = diagnostics
  )

suite "build-time GPU shader compiler":
  setup:
    let root = createTempDir("cbss shader compiler ; ", "")
  teardown:
    removeDir(root)

  test "passes structured shaderc arguments without a shell":
    let source = fragmentSource()
    let config = testConfig(root)
    let arguments = source.shadercArguments(
      target(),
      config,
      root / "source ; literal.sc",
      root / "varying & literal.sc",
      root / "output $(literal).bin"
    )
    check arguments.argumentValue("-f") == root / "source ; literal.sc"
    check arguments.argumentValue("-o") == root / "output $(literal).bin"
    check arguments.argumentValue("--varyingdef") == root / "varying & literal.sc"
    check arguments.argumentValue("--platform") == "linux"
    check arguments.argumentValue("--type") == "fragment"
    check arguments.argumentValue("--profile") == "fake_ok"
    check "--Werror" in arguments
    check arguments.argumentValue("-i") == root

    let compute = GpuShaderSource(
      stage: gssCompute,
      label: "manual-compute",
      source: "#include <bgfx_compute.sh>\nvoid main() {}\n"
    )
    let computeArguments = compute.shadercArguments(
      target(),
      config,
      root / "compute.sc",
      "",
      root / "compute.bin"
    )
    check computeArguments.argumentValue("--type") == "compute"
    check "--varyingdef" notin computeArguments

    let warningsAllowed = gpuShaderCompilerConfig(
      getAppFilename(),
      [root],
      workDirectory = root,
      warningsAsErrors = false
    )
    check "--Werror" notin source.shadercArguments(
      target(),
      warningsAllowed,
      root / "source.sc",
      root / "varying.sc",
      root / "output.bin"
    )

  test "compiles into the runtime artifact contract":
    let source = fragmentSource()
    let compiled = source.compileGpuShader(target(), testConfig(root))
    check compiled.artifact.descriptor.stage == gssFragment
    check compiled.artifact.descriptor.label == "compiler-fragment"
    check compiled.artifact.bytecode == @[byte('C'), byte('B'), byte('S'), byte('S')]
    check compiled.artifact.sourceHash == source.gpuShaderSourceHash()
    check compiled.diagnostics == "compiled fake_ok"
    check not compiled.diagnosticsTruncated

  test "adds a compiled variant to a package":
    let source = fragmentSource()
    var package = gpuShaderPackage(source)
    let compiled = package.compileAndAddVariant(
      source,
      target(),
      testConfig(root)
    )
    check compiled.artifact.bytecode.len == 4
    check package.artifactFor(gsbtVulkan).bytecode == compiled.artifact.bytecode

  test "propagates bounded compiler diagnostics":
    let source = fragmentSource()
    let compiled = source.compileGpuShader(
      target("fake_loud"),
      testConfig(root, diagnostics = 8)
    )
    check compiled.diagnostics == "xxxxxxxx"
    check compiled.diagnosticsTruncated

    expect GpuShaderCompilerError:
      discard source.compileGpuShader(
        target("fake_fail"),
        testConfig(root, diagnostics = 12)
      )

  test "rejects missing and empty compiler output":
    let source = fragmentSource()
    expect GpuShaderCompilerError:
      discard source.compileGpuShader(target("fake_missing"), testConfig(root))
    expect GpuShaderCompilerError:
      discard source.compileGpuShader(target("fake_empty"), testConfig(root))

  test "rejects invalid configuration before process launch":
    let source = fragmentSource()
    expect GpuShaderCompilerError:
      discard source.compileGpuShader(
        target("bad/profile"),
        testConfig(root)
      )
    expect GpuShaderCompilerError:
      discard source.compileGpuShader(
        target(),
        gpuShaderCompilerConfig(getAppFilename(), newSeq[string]())
      )
    expect GpuShaderCompilerError:
      discard source.compileGpuShader(
        target(),
        testConfig(root, diagnostics = maxGpuShaderDiagnosticBytes + 1)
      )
    expect GpuShaderCompilerError:
      discard source.compileGpuShader(
        target(),
        gpuShaderCompilerConfig(
          root / "missing-shaderc",
          [root],
          workDirectory = root
        )
      )
