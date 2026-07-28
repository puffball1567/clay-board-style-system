import std/options
import ../core/computed_style

type
  FontSourceKind* = enum
    fskSystem,
    fskFile,
    fskMemory

  FontSource* = object
    kind*: FontSourceKind
    path*: Option[string]
    bytes*: seq[uint8]

  FontFace* = object
    family*: string
    source*: FontSource
    weight*: Option[float32]
    style*: Option[FontStyle]

  FontRegistry* = object
    useSystemFonts*: bool
    faces*: seq[FontFace]
    fallbackFamilies*: seq[string]

proc initFontRegistry*(useSystemFonts = true): FontRegistry =
  result.useSystemFonts = useSystemFonts
  result.fallbackFamilies = @["sans-serif"]

proc systemFontSource*(): FontSource =
  FontSource(kind: fskSystem)

proc fileFontSource*(path: string): FontSource =
  FontSource(kind: fskFile, path: some(path))

proc memoryFontSource*(bytes: openArray[uint8]): FontSource =
  FontSource(kind: fskMemory, bytes: @bytes)

proc addSystemFonts*(registry: var FontRegistry) =
  registry.useSystemFonts = true

proc addFallbackFamily*(registry: var FontRegistry; family: string) =
  if family.len > 0:
    registry.fallbackFamilies.add family

proc addFontFile*(
    registry: var FontRegistry;
    family: string;
    path: string;
    weight: Option[float32] = none(float32);
    style: Option[FontStyle] = none(FontStyle)
) =
  registry.faces.add FontFace(
    family: family,
    source: fileFontSource(path),
    weight: weight,
    style: style
  )

proc addMemoryFont*(
    registry: var FontRegistry;
    family: string;
    bytes: openArray[uint8];
    weight: Option[float32] = none(float32);
    style: Option[FontStyle] = none(FontStyle)
) =
  registry.faces.add FontFace(
    family: family,
    source: memoryFontSource(bytes),
    weight: weight,
    style: style
  )

proc addUnique(target: var seq[string]; family: string) =
  if family.len == 0:
    return
  for existing in target:
    if existing == family:
      return
  target.add family

proc effectiveFontFamilies*(style: ComputedTextStyle; registry: FontRegistry): seq[string] =
  for family in style.fontFamilies:
    result.addUnique(family)
  if result.len == 0 and style.fontFamily.isSome:
    result.addUnique(style.fontFamily.get)
  for family in registry.fallbackFamilies:
    result.addUnique(family)
