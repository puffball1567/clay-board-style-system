import std/[os, osproc, streams, strutils, tempfiles]

import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder,
    gpu_shader_package]

const
  defaultGpuShaderDiagnosticBytes* = 64 * 1024
  maxGpuShaderDiagnosticBytes* = 1024 * 1024
  maxGpuShaderCompilerIncludes* = 32

type
  GpuShaderCompilerError* = object of CatchableError

  GpuShaderCompilerPlatform* = enum
    gscpAndroid,
    gscpAsmJs,
    gscpIos,
    gscpLinux,
    gscpMacOs,
    gscpOrbis,
    gscpWindows

  GpuShaderCompileTarget* = object
    binaryTarget*: GpuShaderBinaryTarget
    platform*: GpuShaderCompilerPlatform
    profile*: string

  GpuShaderCompilerConfig* = object
    executable*: string
    includeDirectories*: seq[string]
    workDirectory*: string
    diagnosticByteLimit*: int
    warningsAsErrors*: bool

  GpuShaderCompileResult* = object
    artifact*: GpuShaderArtifact
    diagnostics*: string
    diagnosticsTruncated*: bool

proc gpuShaderCompileTarget*(
    binaryTarget: GpuShaderBinaryTarget;
    platform: GpuShaderCompilerPlatform;
    profile: string
): GpuShaderCompileTarget =
  GpuShaderCompileTarget(
    binaryTarget: binaryTarget,
    platform: platform,
    profile: profile
  )

proc gpuShaderCompilerConfig*(
    executable: string;
    includeDirectories: openArray[string];
    workDirectory = "";
    diagnosticByteLimit = defaultGpuShaderDiagnosticBytes;
    warningsAsErrors = true
): GpuShaderCompilerConfig =
  GpuShaderCompilerConfig(
    executable: executable,
    includeDirectories: @includeDirectories,
    workDirectory: workDirectory,
    diagnosticByteLimit: diagnosticByteLimit,
    warningsAsErrors: warningsAsErrors
  )

proc platformArgument(value: GpuShaderCompilerPlatform): string =
  case value
  of gscpAndroid: "android"
  of gscpAsmJs: "asm.js"
  of gscpIos: "ios"
  of gscpLinux: "linux"
  of gscpMacOs: "osx"
  of gscpOrbis: "orbis"
  of gscpWindows: "windows"

proc stageArgument(value: GpuShaderStage): string =
  case value
  of gssVertex: "vertex"
  of gssFragment: "fragment"
  of gssCompute: "compute"

proc validateToken(value, description: string) =
  if value.len == 0 or value.len > 64:
    raise newException(
      GpuShaderCompilerError,
      description & " must contain 1 to 64 bytes"
    )
  for character in value:
    if not (character.isAlphaNumeric or character in {'_', '-', '.'}):
      raise newException(
        GpuShaderCompilerError,
        description & " contains an unsupported character"
      )

proc validateCompilerConfig(config: GpuShaderCompilerConfig) =
  if config.executable.len == 0:
    raise newException(GpuShaderCompilerError, "shaderc executable is required")
  if config.includeDirectories.len == 0 or
      config.includeDirectories.len > maxGpuShaderCompilerIncludes:
    raise newException(
      GpuShaderCompilerError,
      "shaderc include directory count is invalid"
    )
  for path in config.includeDirectories:
    if path.len == 0 or not dirExists(path):
      raise newException(
        GpuShaderCompilerError,
        "shaderc include directory does not exist: " & path
      )
  if config.workDirectory.len > 0 and not dirExists(config.workDirectory):
    raise newException(
      GpuShaderCompilerError,
      "shaderc work directory does not exist"
    )
  if config.diagnosticByteLimit < 0 or
      config.diagnosticByteLimit > maxGpuShaderDiagnosticBytes:
    raise newException(
      GpuShaderCompilerError,
      "shaderc diagnostic byte limit is invalid"
    )

proc shadercArguments*(
    source: GpuShaderSource;
    target: GpuShaderCompileTarget;
    config: GpuShaderCompilerConfig;
    sourcePath, varyingPath, outputPath: string
): seq[string] =
  config.validateCompilerConfig()
  target.profile.validateToken("shaderc profile")
  if source.source.len == 0 or source.source.len > maxGpuShaderSourceBytes or
      source.varyingDefinitions.len > maxGpuShaderSourceBytes:
    raise newException(GpuShaderCompilerError, "GPU shader source size is invalid")
  if sourcePath.len == 0 or outputPath.len == 0:
    raise newException(GpuShaderCompilerError, "shaderc input and output paths are required")

  result = @[
    "-f", sourcePath,
    "-o", outputPath,
    "--platform", target.platform.platformArgument(),
    "--type", source.stage.stageArgument(),
    "--profile", target.profile
  ]
  if source.stage != gssCompute:
    if varyingPath.len == 0:
      raise newException(
        GpuShaderCompilerError,
        "graphics shaders require varying definitions"
      )
    result.add ["--varyingdef", varyingPath]
  if config.warningsAsErrors:
    result.add "--Werror"
  for path in config.includeDirectories:
    result.add ["-i", path]

proc readDiagnostics(
    stream: Stream;
    limit: int
): tuple[text: string, truncated: bool] =
  var buffer = newString(4096)
  while true:
    let count = stream.readData(addr buffer[0], buffer.len)
    if count <= 0:
      break
    let remaining = max(0, limit - result.text.len)
    if remaining > 0:
      result.text.add buffer[0 ..< min(count, remaining)]
    if count > remaining:
      result.truncated = true

proc readBinaryFile(path: string): seq[byte] =
  let size = getFileSize(path)
  if size <= 0 or size > maxGpuShaderBinaryBytes:
    raise newException(
      GpuShaderCompilerError,
      "shaderc output size is invalid"
    )
  let contents = readFile(path)
  if contents.len != int(size):
    raise newException(
      GpuShaderCompilerError,
      "shaderc output changed while being read"
    )
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc compileGpuShader*(
    source: GpuShaderSource;
    target: GpuShaderCompileTarget;
    config: GpuShaderCompilerConfig
): GpuShaderCompileResult =
  config.validateCompilerConfig()
  target.profile.validateToken("shaderc profile")

  let parent = if config.workDirectory.len > 0:
      config.workDirectory
    else:
      getTempDir()
  let work = createTempDir("cbss-shaderc-", "", parent)
  defer:
    try:
      removeDir(work)
    except OSError:
      discard

  let sourcePath = work / "shader.sc"
  let varyingPath = work / "varying.def.sc"
  let outputPath = work / "shader.bin"
  writeFile(sourcePath, source.source)
  if source.stage != gssCompute:
    writeFile(varyingPath, source.varyingDefinitions)
  let arguments = source.shadercArguments(
    target,
    config,
    sourcePath,
    varyingPath,
    outputPath
  )

  var process: Process
  try:
    process = startProcess(
      config.executable,
      args = arguments,
      options = {poStdErrToStdOut, poUsePath}
    )
  except OSError as error:
    raise newException(
      GpuShaderCompilerError,
      "failed to start shaderc: " & error.msg
    )
  defer:
    close(process)

  let diagnostics = process.outputStream.readDiagnostics(
    config.diagnosticByteLimit
  )
  let exitCode = process.waitForExit()
  if exitCode != 0:
    var message = "shaderc failed with exit code " & $exitCode
    if diagnostics.text.len > 0:
      message.add ": " & diagnostics.text
    if diagnostics.truncated:
      message.add " [diagnostics truncated]"
    raise newException(GpuShaderCompilerError, message)
  if not fileExists(outputPath):
    raise newException(GpuShaderCompilerError, "shaderc produced no output")

  result = GpuShaderCompileResult(
    artifact: gpuShaderArtifact(source, outputPath.readBinaryFile()),
    diagnostics: diagnostics.text,
    diagnosticsTruncated: diagnostics.truncated
  )

proc compileAndAddVariant*(
    package: var GpuShaderPackage;
    source: GpuShaderSource;
    target: GpuShaderCompileTarget;
    config: GpuShaderCompilerConfig
): GpuShaderCompileResult =
  result = source.compileGpuShader(target, config)
  package.addVariant(target.binaryTarget, result.artifact)
