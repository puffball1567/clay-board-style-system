import std/[os, strutils, unittest]

proc repoRoot(): string =
  currentSourcePath().parentDir().parentDir().parentDir()

proc normalizeNewlines(value: string): string =
  value.replace("\r\n", "\n").replace('\r', '\n')

suite "CI workflow policy":
  let workflow = readFile(repoRoot() / ".github/workflows/ci.yml").normalizeNewlines()

  test "workflow inspection is independent of checkout line endings":
    check normalizeNewlines("first\r\nsecond\rthird") ==
      "first\nsecond\nthird"

  test "expensive jobs wait for the deterministic preflight":
    check "  preflight:\n" in workflow
    for job in [
      "nim", "nim-orc", "bgfx-contract", "linux-atspi", "portable",
      "linux-valgrind", "motion-address-sanitizer",
      "undefined-behavior-sanitizer", "leak-sanitizer",
      "thread-sanitizer", "rust-bridge", "release-hygiene"
    ]:
      check ("  " & job & ":\n") in workflow
      let jobStart = workflow.find("  " & job & ":\n")
      require jobStart >= 0
      let jobEnd = min(workflow.high, jobStart + 400)
      let jobText = workflow[jobStart .. jobEnd]
      check "needs: preflight" in jobText

    let gateStart = workflow.find("  required-gate:\n")
    require gateStart >= 0
    check "      - preflight\n" in workflow[gateStart .. ^1]

  test "workflow cancels obsolete runs and avoids mutable action tags":
    check "cancel-in-progress: true" in workflow
    for line in workflow.splitLines():
      let stripped = line.strip()
      if stripped.startsWith("uses:") or stripped.startsWith("- uses:"):
        let atIndex = stripped.find('@')
        require atIndex >= 0
        let values = stripped[atIndex + 1 .. ^1].splitWhitespace()
        require values.len > 0
        let suffix = values[0]
        check suffix.len == 40
        check suffix.allCharsInSet(HexDigits)

  test "Nim installation does not execute a downloaded shell script":
    check "curl https://nim-lang.org/choosenim/init.sh" notin workflow
    check "jiro4989/setup-nim-action@" in workflow

  test "network retries and deterministic shader compiler caching stay enabled":
    check "CARGO_NET_RETRY: 5" in workflow
    check "CARGO_HTTP_TIMEOUT: 120" in workflow
    check "id: shaderc-cache" in workflow
    check "steps.shaderc-cache.outputs.cache-hit != 'true'" in workflow
