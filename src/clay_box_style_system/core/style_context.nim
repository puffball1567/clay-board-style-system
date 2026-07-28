import std/options

import ./[
  computed_style,
  declaration,
  diagnostics,
  property,
  registry,
  style_value
]

type
  StyleContext* = object
    declarations*: seq[Declaration]

  ResolveOptions* = object
    allowFunctionValues*: bool

proc initStyleContext*(): StyleContext =
  StyleContext(declarations: @[])

proc styleContext*(declarations: openArray[Declaration]): StyleContext =
  result = initStyleContext()
  for declaration in declarations:
    result.declarations.add declaration

proc mergeStyles*(contexts: varargs[StyleContext]): StyleContext =
  result = initStyleContext()
  for context in contexts:
    for declaration in context.declarations:
      result.declarations.add declaration

proc resolveStyles*(
    context: StyleContext;
    registry: PropertyRegistry;
    env: ResolveEnv;
    diagnostics: var Diagnostics;
    options = ResolveOptions()
): ComputedStyle =
  result = initialComputedStyle()
  for declaration in context.declarations:
    if not registry.hasProperty(declaration.property):
      diagnostics.addError(declaration.property, "unknown style property")
      continue
    let property = registry.getProperty(declaration.property)
    var resolved = declaration
    if resolved.operation.value.isSome and resolved.operation.value.get.kind == svFunction:
      if not options.allowFunctionValues:
        diagnostics.addError(resolved.property, "function style values require trusted style resolution")
        continue
      resolved.operation.value = some(resolved.operation.value.get.valueProc())
      if resolved.operation.value.isSome and resolved.operation.value.get.kind == svFunction:
        diagnostics.addError(resolved.property, "style value function returned another function")
        continue
    property.apply(result, resolved, env, diagnostics)

proc resolveTrustedStyles*(
    context: StyleContext;
    registry: PropertyRegistry;
    env: ResolveEnv;
    diagnostics: var Diagnostics
): ComputedStyle =
  resolveStyles(context, registry, env, diagnostics, ResolveOptions(allowFunctionValues: true))
