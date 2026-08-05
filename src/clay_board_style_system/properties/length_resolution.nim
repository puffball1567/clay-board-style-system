import std/options
import ../core/[diagnostics, property, style_value]

proc unitName(kind: UnitKind): string =
  case kind
  of ukPx: "px"
  of ukPercent: "%"
  of ukEm: "em"
  of ukRem: "rem"
  of ukFill: "fill"
  of ukContent: "content"
  of ukMinContent: "min-content"
  of ukMaxContent: "max-content"
  of ukFitContent: "fit-content"
  of ukAuto: "auto"
  of ukNone: "none"
  of ukVw: "vw"
  of ukVh: "vh"
  of ukVmin: "vmin"
  of ukVmax: "vmax"
  of ukLh: "lh"
  of ukRlh: "rlh"

proc resolveContextualLength(
    length: LengthValue;
    env: ResolveEnv;
    property: string;
    diagnostics: var Diagnostics
): Option[float32] =
  case length.kind
  of ukPx:
    some(length.value)
  of ukEm:
    if env.currentFontSize.isNone:
      diagnostics.addError(property, "em requires a current font-size")
      return none(float32)
    some(env.currentFontSize.get * length.value)
  of ukRem:
    if env.rootFontSize.isNone:
      diagnostics.addError(property, "rem requires a root font-size")
      return none(float32)
    some(env.rootFontSize.get * length.value)
  of ukLh:
    if env.currentLineHeight.isNone:
      diagnostics.addError(property, "lh requires a current line-height")
      return none(float32)
    some(env.currentLineHeight.get * length.value)
  of ukRlh:
    if env.rootLineHeight.isNone:
      diagnostics.addError(property, "rlh requires a root line-height")
      return none(float32)
    some(env.rootLineHeight.get * length.value)
  of ukVw, ukVh, ukVmin, ukVmax:
    if env.viewportSize.isNone:
      diagnostics.addError(property, length.kind.unitName &
        " requires an explicit viewport size")
      return none(float32)
    let viewport = env.viewportSize.get
    if viewport.w < 0 or viewport.h < 0:
      diagnostics.addError(property, "viewport dimensions must be non-negative")
      return none(float32)
    let reference =
      case length.kind
      of ukVw: viewport.w
      of ukVh: viewport.h
      of ukVmin: min(viewport.w, viewport.h)
      of ukVmax: max(viewport.w, viewport.h)
      else: 0.0'f32
    some(reference * length.value / 100.0'f32)
  else:
    none(float32)

proc normalizeLength*(
    value: StyleValue;
    env: ResolveEnv;
    property: string;
    preserved: set[UnitKind];
    diagnostics: var Diagnostics
): Option[LengthValue] =
  ## Resolve context-dependent absolute units to pixels and retain only units
  ## whose meaning belongs to a later layout phase, such as percentages.
  if value.kind != svLength:
    diagnostics.addError(property, property & " requires a length value")
    return none(LengthValue)
  if value.length.kind in preserved:
    return some(value.length)
  let resolved = resolveContextualLength(
    value.length, env, property, diagnostics
  )
  if resolved.isSome:
    return some(LengthValue(kind: ukPx, value: resolved.get))
  if value.length.kind notin {
      ukEm, ukRem, ukVw, ukVh, ukVmin, ukVmax, ukLh, ukRlh
  }:
    diagnostics.addError(property, property & " does not support " &
      value.length.kind.unitName)
  none(LengthValue)

proc resolveAbsoluteLength*(
    length: LengthValue;
    env: ResolveEnv;
    property: string;
    diagnostics: var Diagnostics
): Option[float32] =
  let resolved = resolveContextualLength(length, env, property, diagnostics)
  if resolved.isSome:
    return resolved
  if length.kind notin {
      ukEm, ukRem, ukVw, ukVh, ukVmin, ukVmax, ukLh, ukRlh
  }:
    diagnostics.addError(property, property & " does not support " &
      length.kind.unitName)
  none(float32)

proc resolveAbsoluteLength*(
    value: StyleValue;
    env: ResolveEnv;
    property: string;
    diagnostics: var Diagnostics
): Option[float32] =
  let normalized = normalizeLength(
    value, env, property, {}, diagnostics
  )
  if normalized.isSome:
    some(normalized.get.value)
  else:
    none(float32)
