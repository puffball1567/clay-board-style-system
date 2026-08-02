import std/options
import ../core/[color, computed_style, declaration, diagnostics, property,
    style_color, style_value]

proc setColumnKeyword(style: var ComputedStyle; property: string; value: Option[string]) =
  style.ensureColumns()
  case property
  of "column-fill":
    style.columns.columnFill = value
  of "column-rule":
    style.columns.columnRule = value
  of "column-rule-style":
    style.columns.columnRuleStyle = value
  of "column-span":
    style.columns.columnSpan = value
  of "column-wrap":
    style.columns.columnWrap = value
  of "columns":
    style.columns.columns = value
  else:
    discard

proc columnKeyword(style: ComputedStyle; property: string): Option[string] =
  if style.columns.isNil:
    return none(string)
  case property
  of "column-fill":
    style.columns.columnFill
  of "column-rule":
    style.columns.columnRule
  of "column-rule-style":
    style.columns.columnRuleStyle
  of "column-span":
    style.columns.columnSpan
  of "column-wrap":
    style.columns.columnWrap
  of "columns":
    style.columns.columns
  else:
    none(string)

proc applyColumnKeyword(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, declaration.property & " requires a keyword metadata value")
      return
    let value = declaration.operation.value.get.keyword
    if value == "normal" or value == "auto":
      style.setColumnKeyword(declaration.property, none(string))
    else:
      style.setColumnKeyword(declaration.property, some(value))
  of mmInitial, mmUnset:
    style.setColumnKeyword(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setColumnKeyword(declaration.property, env.parent.get.columnKeyword(
          declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc setColumnLength(style: var ComputedStyle; property: string; value: Option[float32]) =
  style.ensureColumns()
  case property
  of "column-height":
    style.columns.columnHeight = value
  of "column-rule-width":
    style.columns.columnRuleWidth = value
  of "column-width":
    style.columns.columnWidth = value
  else:
    discard

proc columnLength(style: ComputedStyle; property: string): Option[float32] =
  if style.columns.isNil:
    return none(float32)
  case property
  of "column-height":
    style.columns.columnHeight
  of "column-rule-width":
    style.columns.columnRuleWidth
  of "column-width":
    style.columns.columnWidth
  else:
    none(float32)

proc applyColumnLength(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svLength:
      diagnostics.addError(declaration.property, declaration.property & " requires a px length value")
      return
    let length = declaration.operation.value.get.length
    if length.kind != ukPx:
      diagnostics.addError(declaration.property, declaration.property & " only supports px lengths")
      return
    style.setColumnLength(declaration.property, some(length.value))
  of mmInitial, mmUnset:
    style.setColumnLength(declaration.property, none(float32))
  of mmInherit:
    if env.parent.isSome:
      style.setColumnLength(declaration.property, env.parent.get.columnLength(
          declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyColumnCount(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  style.ensureColumns()
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "column-count requires auto or a positive number")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      if value.keyword == "auto":
        style.columns.columnCount = none(int)
      else:
        diagnostics.addError(declaration.property, "unsupported column-count keyword")
    of svNumber:
      if value.number < 1:
        diagnostics.addError(declaration.property, "column-count requires a positive number")
      else:
        style.columns.columnCount = some(value.number.int)
    else:
      diagnostics.addError(declaration.property, "column-count requires auto or a positive number")
  of mmInitial, mmUnset:
    style.columns.columnCount = none(int)
  of mmInherit:
    if env.parent.isSome:
      style.columns.columnCount = env.parent.get.columns.columnCount
    else:
      diagnostics.addError(declaration.property, "cannot inherit column-count without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "column-count does not support relative merge")

proc applyColumnRuleColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  style.ensureColumns()
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svColor:
      diagnostics.addError(declaration.property, "column-rule-color requires a color value")
      return
    style.columns.columnRuleColor = declaration.operation.value.get.resolveStyleColor(
        style, env)
  of mmInitial, mmUnset:
    style.columns.columnRuleColor = none(Color)
  of mmInherit:
    if env.parent.isSome:
      style.columns.columnRuleColor = env.parent.get.columns.columnRuleColor
    else:
      diagnostics.addError(declaration.property, "cannot inherit column-rule-color without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "column-rule-color does not support relative merge")

let columnCountProperty* = PropertyImpl(name: "column-count",
    apply: applyColumnCount)
let columnFillProperty* = PropertyImpl(name: "column-fill",
    apply: applyColumnKeyword)
let columnHeightProperty* = PropertyImpl(name: "column-height",
    apply: applyColumnLength)
let columnRuleProperty* = PropertyImpl(name: "column-rule",
    apply: applyColumnKeyword)
let columnRuleColorProperty* = PropertyImpl(name: "column-rule-color",
    apply: applyColumnRuleColor)
let columnRuleStyleProperty* = PropertyImpl(name: "column-rule-style",
    apply: applyColumnKeyword)
let columnRuleWidthProperty* = PropertyImpl(name: "column-rule-width",
    apply: applyColumnLength)
let columnSpanProperty* = PropertyImpl(name: "column-span",
    apply: applyColumnKeyword)
let columnWidthProperty* = PropertyImpl(name: "column-width",
    apply: applyColumnLength)
let columnWrapProperty* = PropertyImpl(name: "column-wrap",
    apply: applyColumnKeyword)
let columnsProperty* = PropertyImpl(name: "columns", apply: applyColumnKeyword)
