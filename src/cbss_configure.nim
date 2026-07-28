import std/[os, strutils]

const
  bundledMode = "bundled"
  systemMode = "system"
  customMode = "custom"

proc usage() =
  stderr.writeLine(
    "usage: cbss_configure system [project-dir]\n" &
    "       cbss_configure <bundled|custom> <runtime-root> [project-dir]"
  )

proc projectDirFor(mode: string): string =
  if mode in [bundledMode, customMode]:
    if paramCount() >= 3:
      paramStr(3)
    else:
      getCurrentDir()
  elif paramCount() >= 2:
    paramStr(2)
  else:
    getCurrentDir()

proc writeSetup(mode, runtimeRoot, projectDir: string) =
  let setupDir = projectDir.absolutePath() / ".cbss"
  createDir(setupDir)
  writeFile(setupDir / "link-mode", mode & "\n")

  let rootFile = setupDir / "runtime-root"
  if mode in [bundledMode, customMode]:
    writeFile(rootFile, runtimeRoot.absolutePath() & "\n")
  elif fileExists(rootFile):
    removeFile(rootFile)

  stdout.writeLine("CBSS link mode: " & mode)
  stdout.writeLine("Project: " & projectDir.absolutePath())
  if mode in [bundledMode, customMode]:
    stdout.writeLine("Runtime root: " & runtimeRoot.absolutePath())

when isMainModule:
  if paramCount() < 1:
    usage()
    quit(QuitFailure)

  let mode = paramStr(1).strip().toLowerAscii()
  if mode notin [bundledMode, systemMode, customMode]:
    usage()
    quit(QuitFailure)

  if mode in [bundledMode, customMode] and paramCount() < 2:
    usage()
    quit(QuitFailure)

  let runtimeRoot =
    if mode in [bundledMode, customMode]:
      paramStr(2)
    else:
      ""
  if runtimeRoot.len > 0 and not dirExists(runtimeRoot):
    stderr.writeLine("runtime root does not exist: " & runtimeRoot)
    quit(QuitFailure)
  writeSetup(mode, runtimeRoot, projectDirFor(mode))
