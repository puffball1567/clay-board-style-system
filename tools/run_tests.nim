import std/[algorithm, os, osproc, sequtils, strutils]

const excludedTests = [
  "tests/integration/test_sdl3_large_paste.nim",
  "tests/integration/test_sdl3_wayland_smoke.nim",
  "tests/perf/dirty_subtree_benchmark.nim",
  "tests/perf/pipeline_benchmark.nim",
  "tests/text/test_cosmic_text_engine.nim"
]

proc normalizedRelative(path, root: string): string =
  path.relativePath(root).replace('\\', '/')

proc artifactName(path: string): string =
  result = path.changeFileExt("")
  for index in 0 ..< result.len:
    if not result[index].isAlphaNumeric():
      result[index] = '_'

proc main() =
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
      if relative notin excludedTests:
        tests.add(relative)
  tests.sort()

  if tests.len == 0:
    stderr.writeLine("No CBSS tests were discovered.")
    quit(QuitFailure)

  for relative in tests:
    let name = relative.artifactName()
    let command = @[
      "nim", "c", "-r",
      "--mm:arc",
      "--path:" & (repoRoot / "src"),
      "-d:cbssSdl3LinkMode=bundled",
      "-d:cbssRuntimeRoot=" & (repoRoot / "vendor/sdl3"),
      "--nimcache:" & (runRoot / ("cache_" & name)),
      "--out:" & (runRoot / name),
      repoRoot / relative
    ].mapIt(it.quoteShell()).join(" ")

    stdout.writeLine("\n==> " & relative)
    let execution = execCmdEx(command, options = {poUsePath, poStdErrToStdOut})
    stdout.write(execution.output)
    if execution.exitCode != 0:
      stderr.writeLine("FAILED: " & relative)
      quit(execution.exitCode)

  stdout.writeLine("\nPassed " & $tests.len & " discovered test files.")

when isMainModule:
  main()
