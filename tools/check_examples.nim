import std/[algorithm, os, osproc, sequtils, strutils]

const externallyConfiguredExamples = [
  "examples/bgfx_host_demo.nim"
]

type
  ExampleProfile* = enum
    epBundled,
    epSystem,
    epCustom

proc parseExampleProfile*(value: string): ExampleProfile =
  case value
  of "bundled":
    epBundled
  of "system":
    epSystem
  of "custom":
    epCustom
  else:
    raise newException(ValueError, "unknown example profile: " & value)

proc discoverExamples*(repoRoot: string): seq[string] =
  let examplesRoot = repoRoot / "examples"
  for path in walkDirRec(examplesRoot):
    if path.endsWith(".nim"):
      let relative = path.relativePath(repoRoot).replace('\\', '/')
      if relative notin externallyConfiguredExamples:
        result.add(relative)
  result.sort()

proc profileArguments(profile: ExampleProfile; repoRoot: string): seq[string] =
  case profile
  of epBundled:
    @["-d:cbssSdl3LinkMode=bundled", "-d:cbssRuntimeRoot=" & (repoRoot / "vendor/sdl3")]
  of epSystem:
    @["-d:cbssSdl3LinkMode=system"]
  of epCustom:
    @["-d:cbssSdl3LinkMode=custom", "-d:cbssRuntimeRoot=" & (repoRoot / "vendor/sdl3")]

proc main() {.used.} =
  var memoryModel = "arc"
  var profiles = @[epBundled]
  var profilesSpecified = false

  for argument in commandLineParams():
    if argument.startsWith("--memory:"):
      memoryModel = argument["--memory:".len .. ^1]
      if memoryModel notin ["arc", "orc"]:
        stderr.writeLine("Memory model must be arc or orc.")
        quit(QuitFailure)
    elif argument.startsWith("--profile:"):
      if not profilesSpecified:
        profiles.setLen(0)
        profilesSpecified = true
      try:
        let profile = parseExampleProfile(argument["--profile:".len .. ^1])
        if profile notin profiles:
          profiles.add(profile)
      except ValueError as error:
        stderr.writeLine(error.msg)
        quit(QuitFailure)
    else:
      stderr.writeLine(
        "Usage: check_examples [--memory:arc|--memory:orc] " &
        "[--profile:bundled|--profile:system|--profile:custom]"
      )
      quit(QuitFailure)

  let repoRoot = currentSourcePath().parentDir().parentDir()
  let runRoot = getTempDir() / ("cbss-example-check-" & $getCurrentProcessId())
  createDir(runRoot)
  defer:
    try:
      removeDir(runRoot)
    except OSError:
      discard

  let examples = discoverExamples(repoRoot)
  if examples.len == 0:
    stderr.writeLine("No examples were discovered.")
    quit(QuitFailure)

  for profile in profiles:
    for relative in examples:
      let artifactName = relative.changeFileExt("").replace('/', '_')
      var arguments = @[
        "nim", "check",
        "--hints:off",
        "--verbosity:0",
        "--mm:" & memoryModel,
        "--path:" & (repoRoot / "src"),
        "--nimcache:" & (runRoot / ($profile & "_" & artifactName))
      ]
      arguments.add(profile.profileArguments(repoRoot))
      arguments.add(repoRoot / relative)

      stdout.writeLine("Checking " & relative & " (" & $profile & ", " & memoryModel & ")")
      let execution = execCmdEx(
        arguments.mapIt(it.quoteShell()).join(" "),
        options = {poUsePath, poStdErrToStdOut}
      )
      stdout.write(execution.output)
      if execution.exitCode != 0:
        stderr.writeLine("FAILED: " & relative & " (" & $profile & ")")
        quit(execution.exitCode)

  stdout.writeLine(
    "Checked " & $examples.len & " discovered examples across " &
    $profiles.len & " profile(s) under " & memoryModel & "."
  )

when isMainModule:
  main()
