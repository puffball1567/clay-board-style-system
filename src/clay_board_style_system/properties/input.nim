import std/options
import ../core/[color, computed_style, declaration, diagnostics, property,
    style_color, style_value]

proc keywordValue(declaration: Declaration;
    diagnostics: var Diagnostics): Option[string] =
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
    return none(string)
  some(declaration.operation.value.get.keyword)

proc applyPointerEvents(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "pointer-events only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.pointerEvents = peAuto
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  case value.get
  of "auto":
    style.visual.pointerEvents = peAuto
  of "none":
    style.visual.pointerEvents = peNone
  else:
    diagnostics.addError(declaration.property, "unsupported pointer-events keyword")

proc applyCursor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = keywordValue(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "auto":
      style.visual.cursor = some(ckAuto)
    of "default":
      style.visual.cursor = some(ckDefault)
    of "pointer":
      style.visual.cursor = some(ckPointer)
    of "text":
      style.visual.cursor = some(ckText)
    of "move":
      style.visual.cursor = some(ckMove)
    of "not-allowed":
      style.visual.cursor = some(ckNotAllowed)
    else:
      diagnostics.addError(declaration.property, "unsupported cursor keyword")
  of mmInitial, mmUnset:
    style.visual.cursor = some(ckAuto)
  of mmInherit:
    if env.parent.isSome:
      style.visual.cursor = env.parent.get.visual.cursor
    else:
      diagnostics.addError(declaration.property, "cannot inherit cursor without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "cursor does not support relative merge")

proc applyUserSelect(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = keywordValue(declaration, diagnostics)
    if value.isNone:
      return
    case value.get
    of "auto":
      style.visual.userSelect = some(usAuto)
    of "none":
      style.visual.userSelect = some(usNone)
    of "text":
      style.visual.userSelect = some(usText)
    of "all":
      style.visual.userSelect = some(usAll)
    else:
      diagnostics.addError(declaration.property, "unsupported user-select keyword")
  of mmInitial, mmUnset:
    style.visual.userSelect = some(usAuto)
  of mmInherit:
    if env.parent.isSome:
      style.visual.userSelect = env.parent.get.visual.userSelect
    else:
      diagnostics.addError(declaration.property, "cannot inherit user-select without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "user-select does not support relative merge")

proc applyInputColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a color value or auto")
      return
    let value = declaration.operation.value.get
    if value.kind == svKeyword and value.keyword == "auto":
      if declaration.property == "caret-color":
        style.visual.caretColor = none(Color)
        style.visual.caretColorSpecified = true
      else:
        style.visual.accentColor = none(Color)
        style.visual.accentColorSpecified = true
      return
    if value.kind != svColor:
      diagnostics.addError(declaration.property, declaration.property & " requires a color value or auto")
      return
    if declaration.property == "caret-color":
      style.visual.caretColor = value.resolveStyleColor(style, env)
      style.visual.caretColorSpecified = true
    else:
      style.visual.accentColor = value.resolveStyleColor(style, env)
      style.visual.accentColorSpecified = true
  of mmInitial:
    if declaration.property == "caret-color":
      style.visual.caretColor = none(Color)
      style.visual.caretColorSpecified = true
    else:
      style.visual.accentColor = none(Color)
      style.visual.accentColorSpecified = true
  of mmUnset, mmInherit:
    if env.parent.isNone:
      if declaration.operation.mode == mmInherit:
        diagnostics.addError(declaration.property, "cannot inherit " &
            declaration.property & " without parent")
        return
      if declaration.property == "caret-color":
        style.visual.caretColor = none(Color)
        style.visual.caretColorSpecified = true
      else:
        style.visual.accentColor = none(Color)
        style.visual.accentColorSpecified = true
      return
    if declaration.property == "caret-color":
      style.visual.caretColor = env.parent.get.visual.caretColor
      style.visual.caretColorSpecified = true
    else:
      style.visual.accentColor = env.parent.get.visual.accentColor
      style.visual.accentColorSpecified = true
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyResize(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "resize only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.resize = rkNone
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  case value.get
  of "none":
    style.visual.resize = rkNone
  of "both":
    style.visual.resize = rkBoth
  of "horizontal":
    style.visual.resize = rkHorizontal
  of "vertical":
    style.visual.resize = rkVertical
  else:
    diagnostics.addError(declaration.property, "unsupported resize keyword")

let pointerEventsProperty* = PropertyImpl(name: "pointer-events",
    apply: applyPointerEvents)
let cursorProperty* = PropertyImpl(name: "cursor", apply: applyCursor)
let userSelectProperty* = PropertyImpl(name: "user-select",
    apply: applyUserSelect)
let caretColorProperty* = PropertyImpl(name: "caret-color",
    apply: applyInputColor)
let accentColorProperty* = PropertyImpl(name: "accent-color",
    apply: applyInputColor)
let resizeProperty* = PropertyImpl(name: "resize", apply: applyResize)
