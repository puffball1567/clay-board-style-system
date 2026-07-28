import std/[os, strutils]

type
  AssetResolver* = object
    roots*: seq[string]

proc initAssetResolver*(roots: openArray[string] = []): AssetResolver =
  for root in roots:
    if root.len > 0:
      result.roots.add root.normalizedPath()

proc isUri*(source: string): bool =
  let marker = source.find("://")
  marker > 0

proc resolveAssetPath*(resolver: AssetResolver; source: string): string =
  if source.len == 0 or source.isUri() or source.isAbsolute():
    return source

  if fileExists(source):
    return source

  for root in resolver.roots:
    let candidate = root / source
    if fileExists(candidate):
      return candidate

  source

proc withRoot*(resolver: AssetResolver; root: string): AssetResolver =
  result = resolver
  if root.len > 0:
    result.roots.add root.normalizedPath()
