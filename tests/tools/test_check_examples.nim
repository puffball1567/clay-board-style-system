import std/[os, unittest]

import ../../tools/check_examples

suite "example contract discovery":
  test "profiles reject unknown names":
    expect ValueError:
      discard parseExampleProfile("portable")

  test "profiles parse every supported link mode":
    check parseExampleProfile("bundled") == epBundled
    check parseExampleProfile("system") == epSystem
    check parseExampleProfile("custom") == epCustom

  test "discovery includes ordinary examples and excludes externally configured ones":
    let repoRoot = currentSourcePath().parentDir().parentDir().parentDir()
    let examples = discoverExamples(repoRoot)
    check "examples/paint_demo.nim" in examples
    check "examples/sdl3_demo.nim" in examples
    check "examples/bgfx_host_demo.nim" notin examples
