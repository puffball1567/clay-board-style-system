import std/[math, options]
import ./[
  computed_style,
  declaration,
  diagnostics,
  geometry
]

type
  FontUnitMetrics* = object
    ## Versioned text-engine result used by font-relative length resolution.
    version*: uint32
    xHeight*: float32
    zeroAdvance*: float32

  FontUnitMetricsResolver* = proc(
    style: ComputedTextStyle
  ): FontUnitMetrics {.closure.}

  ComputedStyleRef* = object
    value: ptr ComputedStyle

  ResolveEnv* = object
    parent*: ComputedStyleRef
    rootFontSize*: Option[float32]
    currentFontSize*: Option[float32]
    rootLineHeight*: Option[float32]
    currentLineHeight*: Option[float32]
    rootXHeight*: Option[float32]
    currentXHeight*: Option[float32]
    rootZeroAdvance*: Option[float32]
    currentZeroAdvance*: Option[float32]
    viewportSize*: Option[Size]

  PropertyApplyProc* = proc(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
  ) {.nimcall.}

  PropertyImpl* = object
    name*: string
    apply*: PropertyApplyProc

const fontUnitMetricsContractVersion* = 1'u32

proc fallbackFontUnitMetrics*(fontSize: float32): FontUnitMetrics =
  let resolvedFontSize =
    if fontSize.classify in {fcNan, fcInf, fcNegInf} or fontSize < 0:
      16.0'f32
    else:
      fontSize
  let halfEm = resolvedFontSize * 0.5'f32
  FontUnitMetrics(
    version: fontUnitMetricsContractVersion,
    xHeight: halfEm,
    zeroAdvance: halfEm
  )

proc resolveFontUnitMetrics*(
    resolver: FontUnitMetricsResolver;
    style: ComputedTextStyle
): FontUnitMetrics =
  let fallback = fallbackFontUnitMetrics(style.fontSize.get(16.0'f32))
  if resolver.isNil:
    return fallback
  result = resolver(style)
  if result.version != fontUnitMetricsContractVersion:
    return fallback
  if result.xHeight.classify in {fcNan, fcInf, fcNegInf} or
      result.xHeight <= 0.0'f32:
    result.xHeight = fallback.xHeight
  if result.zeroAdvance.classify in {fcNan, fcInf, fcNegInf} or
      result.zeroAdvance <= 0.0'f32:
    result.zeroAdvance = fallback.zeroAdvance

proc computedStyleRef*(style: var ComputedStyle): ComputedStyleRef =
  ComputedStyleRef(value: addr style)

proc isSome*(style: ComputedStyleRef): bool =
  style.value != nil

proc isNone*(style: ComputedStyleRef): bool =
  style.value == nil

proc get*(style: ComputedStyleRef): lent ComputedStyle =
  assert style.value != nil
  style.value[]
