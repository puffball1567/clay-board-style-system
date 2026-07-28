import std/[os, unittest]

import clay_box_style_system/assets/asset_resolver

suite "asset resolver":
  test "keeps empty absolute and uri sources unchanged":
    let resolver = initAssetResolver(["assets"])

    check resolver.resolveAssetPath("") == ""
    check resolver.resolveAssetPath("/tmp/cbss-image.png") == "/tmp/cbss-image.png"
    check resolver.resolveAssetPath("https://example.test/image.png") == "https://example.test/image.png"

  test "finds relative files from configured roots":
    let root = getTempDir() / "cbss_asset_resolver_test"
    createDir(root / "images")
    writeFile(root / "images" / "logo.txt", "asset")
    defer:
      removeFile(root / "images" / "logo.txt")
      removeDir(root / "images")
      removeDir(root)

    let resolver = initAssetResolver([root])

    check resolver.resolveAssetPath("images/logo.txt") == root / "images" / "logo.txt"

  test "returns unresolved relative source when no root matches":
    let resolver = initAssetResolver(["/tmp/cbss_missing_assets"])

    check resolver.resolveAssetPath("missing.png") == "missing.png"

  test "can add roots without mutating the original resolver":
    let base = initAssetResolver()
    let next = base.withRoot("assets")

    check base.roots.len == 0
    check next.roots.len == 1
