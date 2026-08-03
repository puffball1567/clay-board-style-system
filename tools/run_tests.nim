import std/[algorithm, os, osproc, sequtils, strutils]

const excludedTests = [
  "tests/integration/test_sdl3_large_paste.nim",
  "tests/integration/test_sdl3_wayland_smoke.nim",
  "tests/perf/color_conversion_benchmark.nim",
  "tests/perf/dirty_subtree_benchmark.nim",
  "tests/perf/navigation_screen_host_benchmark.nim",
  "tests/perf/pipeline_benchmark.nim",
  "tests/text/test_cosmic_text_engine.nim"
]

const portableExcludedTests = [
  "tests/backends/test_sdl3_image_loader.nim",
  "tests/backends/test_sdl3_pen_input.nim",
  "tests/backends/test_sdl3_text_event_guard.nim",
  "tests/integration/test_demo_layout.nim",
  "tests/integration/test_sdl3_navigation.nim",
  "tests/integration/test_sdl3_transform_render.nim",
  "tests/testing/test_sdl3_wayland_driver.nim"
]

proc normalizedRelative(path, root: string): string =
  path.relativePath(root).replace('\\', '/')

proc artifactName(path: string): string =
  result = path.changeFileExt("")
  for index in 0 ..< result.len:
    if not result[index].isAlphaNumeric():
      result[index] = '_'

proc main() =
  let portable = paramCount() == 1 and paramStr(1) == "--portable"
  if paramCount() > 1 or (paramCount() == 1 and not portable):
    stderr.writeLine("Usage: run_tests [--portable]")
    quit(QuitFailure)

  let repoRoot = currentSourcePath().parentDir().parentDir()
  let testsRoot = repoRoot / "tests"
  let runRoot = getTempDir() / ("cbss-tests-" & $getCurrentProcessId())
  var tests: seq[string]

  createDir(runRoot)
  defer:
    try:
      removeDir(runRoot)
    except OSError:
      discard

  for path in walkDirRec(testsRoot):
    if path.endsWith(".nim"):
      let relative = path.normalizedRelative(repoRoot)
      if relative notin excludedTests and
          (not portable or relative notin portableExcludedTests):
        tests.add(relative)
  tests.sort()

  if tests.len == 0:
    stderr.writeLine("No CBSS tests were discovered.")
    quit(QuitFailure)

  for relative in tests:
    let name = relative.artifactName()
    var arguments = @[
      "nim", "c", "-r",
      "--mm:arc",
      "--path:" & (repoRoot / "src"),
    ]
    if relative.startsWith("tests/perf/"):
      arguments.add("-d:release")
    if not portable:
      arguments.add("-d:cbssSdl3LinkMode=bundled")
      arguments.add("-d:cbssRuntimeRoot=" & (repoRoot / "vendor/sdl3"))
    arguments.add("--nimcache:" & (runRoot / ("cache_" & name)))
    arguments.add("--out:" & (runRoot / name))
    arguments.add(repoRoot / relative)
    var command = arguments.mapIt(it.quoteShell()).join(" ")
    when defined(linux):
      if not portable:
        let bridgeLibraryPath = [
          repoRoot / "native" / "cosmic_text_bridge" / "target" / "release",
          repoRoot / "native" / "image_bridge" / "target" / "release"
        ].join(":")
        command = "env LD_LIBRARY_PATH=" & bridgeLibraryPath.quoteShell & " " & command

    stdout.writeLine("\n==> " & relative)
    let execution = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    stdout.write(execution.output)
    if execution.exitCode != 0:
      stderr.writeLine("FAILED: " & relative)
      quit(execution.exitCode)

  let profile = if portable: "portable" else: "full"
  stdout.writeLine(
    "\nPassed " & $tests.len & " discovered test files (" & profile & " profile)."
  )

when isMainModule:
  main()
