import std/[compilesettings, os, strutils]

const
  cbssBundledLinkMode* = "bundled"
  cbssSystemLinkMode* = "system"
  cbssCustomLinkMode* = "custom"

proc findLinkSetup(startPath: string): string {.compileTime.} =
  var current = if dirExists(startPath): startPath else: startPath.parentDir()
  while current.len > 0:
    let candidate = current / ".cbss" / "link-mode"
    if fileExists(candidate):
      return candidate
    let parent = current.parentDir()
    if parent == current:
      break
    current = parent

proc setupValue(path, fallback: string): string {.compileTime.} =
  if path.len == 0 or not fileExists(path):
    return fallback
  readFile(path).strip()

proc runtimeIncludeDir(root: string): string {.compileTime.} =
  if fileExists(root / "include" / "SDL3" / "SDL.h"):
    root / "include"
  else:
    root / "include" / "SDL3"

proc runtimeLibraryDir(root: string): string {.compileTime.} =
  if dirExists(root / "lib"):
    root / "lib"
  else:
    root / "linux-x86_64"

const
  cbssProjectPath = querySetting(projectPath)
  cbssLinkSetupFile* = findLinkSetup(cbssProjectPath)
  cbssConfiguredLinkMode = setupValue(cbssLinkSetupFile, cbssSystemLinkMode)
  cbssConfiguredRootFile =
    if cbssLinkSetupFile.len > 0:
      cbssLinkSetupFile.parentDir() / "runtime-root"
    else:
      ""
  cbssConfiguredRuntimeRoot = setupValue(cbssConfiguredRootFile, "")

  ## Normally selected once per application with `cbss_configure`.
  ## The repository also provides `nimble setupBundled` and
  ## `nimble setupSystem` as development conveniences.
  ## The strdefine remains available to CI and advanced build systems.
  cbssSdl3LinkMode* {.strdefine.} = cbssConfiguredLinkMode
  cbssRuntimeRoot* {.strdefine.} = cbssConfiguredRuntimeRoot

const
  sdl3PreferWaylandOnWaylandSession* = true

when defined(linux) and defined(amd64):
  when cbssSdl3LinkMode == cbssSystemLinkMode:
    const
      sdl3IncludeDir* = ""
      sdl3LibDir* = ""
      sdl3CompileFlags* = ""
      sdl3LinkFlags* = "-lSDL3"
      sdl3ImageBridgeLinkFlags* = "-lcbss_image_bridge"
  elif cbssSdl3LinkMode == cbssBundledLinkMode or
      cbssSdl3LinkMode == cbssCustomLinkMode:
    when cbssRuntimeRoot.len == 0:
      {.error: "CBSS bundled/custom linking requires a runtime root. Run cbss_configure with a path or define -d:cbssRuntimeRoot=/path.".}
    const
      sdl3IncludeDir* = runtimeIncludeDir(cbssRuntimeRoot)
      sdl3LibDir* = runtimeLibraryDir(cbssRuntimeRoot)
      sdl3CompileFlags* = "-I" & sdl3IncludeDir
      sdl3ImageBridgeLinkFlags* =
        "-L" & sdl3LibDir &
        " -Wl,-rpath,'$ORIGIN/cbss-libs'" &
        " -Wl,-rpath," & sdl3LibDir &
        " -lcbss_image_bridge"
      sdl3LinkFlags* =
        when cbssSdl3LinkMode == cbssBundledLinkMode:
          sdl3LibDir / "libSDL3.a" &
            " -Wl,-rpath,'$ORIGIN/cbss-libs'" &
            " -Wl,-rpath," & sdl3LibDir &
            " -ldl -lpthread -lm"
        else:
          "-L" & sdl3LibDir &
            " -Wl,-rpath,'$ORIGIN/cbss-libs'" &
            " -Wl,-rpath," & sdl3LibDir &
            " -lSDL3"
    when not fileExists(sdl3IncludeDir / "SDL3" / "SDL.h") or
        not fileExists(sdl3LibDir / "libcbss_image_bridge.so"):
      {.error: "Configured CBSS runtime is incomplete or has an unsupported layout.".}
    when cbssSdl3LinkMode == cbssBundledLinkMode and
        not fileExists(sdl3LibDir / "libSDL3.a"):
      {.error: "CBSS bundled linking requires libSDL3.a in the configured runtime root.".}
    when cbssSdl3LinkMode == cbssCustomLinkMode and
        not fileExists(sdl3LibDir / "libSDL3.so"):
      {.error: "CBSS custom dynamic linking requires libSDL3.so in the configured runtime root.".}
  else:
    {.error: "Unknown CBSS SDL3 link mode. Expected bundled, system, or custom.".}
elif defined(windows) and defined(amd64):
  {.error: "SDL3 Windows x86_64 vendor paths are not configured yet. Add vendor/sdl3/windows-x86_64 and update backends/sdl3/config.nim.".}
elif defined(macosx):
  {.error: "SDL3 macOS vendor paths are not configured yet. Add vendor/sdl3/macos-* and update backends/sdl3/config.nim.".}
else:
  {.error: "This SDL3 backend is currently configured for Linux x86_64 only.".}
