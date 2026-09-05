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
    check "  classify_flow:\n" in workflow
    check "  preflight:\n" in workflow
    let preflightStart = workflow.find("  preflight:\n")
    require preflightStart >= 0
    let preflightEnd = min(workflow.high, preflightStart + 300)
    let preflightText = workflow[preflightStart .. preflightEnd]
    check "needs: classify_flow" in preflightText
    check "needs.classify_flow.outputs.mode == 'full'" in preflightText
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
    check "      - classify_flow\n" in workflow[gateStart .. ^1]
    check "      - preflight\n" in workflow[gateStart .. ^1]

  test "protected branch flows avoid duplicate release CI":
    let pushStart = workflow.find("  push:\n")
    let pullRequestStart = workflow.find("  pull_request:\n")
    require pushStart >= 0
    require pullRequestStart > pushStart
    let pushTriggers = workflow[pushStart ..< pullRequestStart]
    check "      - devel\n" in pushTriggers
    check "      - main\n" notin pushTriggers
    check "  pull_request:\n    branches:\n      - main\n      - devel\n" in workflow
    check "CBSS_FLOW_MODE: ${{ needs.classify_flow.outputs.mode }}" in workflow
    check "sh tools/ci/branch_flow.sh verify-promotion" in workflow
    check "This branch flow is not allowed" in workflow
    check "actions: read" in workflow

    let branchFlow = readFile(repoRoot() / "tools/ci/branch_flow.sh").normalizeNewlines()
    check "assert_mode promotion pull_request main devel" in branchFlow
    check "assert_mode full pull_request main hotfix/urgent" in branchFlow
    check "assert_mode full pull_request devel main" in branchFlow
    check "assert_mode invalid pull_request main feature/example" in branchFlow
    check "head_sha == $sha" in branchFlow
    check ".head_branch == \"devel\"" in branchFlow
    check ".event == \"push\"" in branchFlow
    check ".conclusion == \"success\"" in branchFlow

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
