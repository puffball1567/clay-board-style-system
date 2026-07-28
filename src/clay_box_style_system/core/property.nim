import std/options
import ./[
  computed_style,
  declaration,
  diagnostics
]

type
  ComputedStyleRef* = object
    value: ptr ComputedStyle

  ResolveEnv* = object
    parent*: ComputedStyleRef
    rootFontSize*: Option[float32]
    currentFontSize*: Option[float32]

  PropertyApplyProc* = proc(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
  ) {.nimcall.}

  PropertyImpl* = object
    name*: string
    apply*: PropertyApplyProc

proc computedStyleRef*(style: var ComputedStyle): ComputedStyleRef =
  ComputedStyleRef(value: addr style)

proc isSome*(style: ComputedStyleRef): bool =
  style.value != nil

proc isNone*(style: ComputedStyleRef): bool =
  style.value == nil

proc get*(style: ComputedStyleRef): lent ComputedStyle =
  assert style.value != nil
  style.value[]
