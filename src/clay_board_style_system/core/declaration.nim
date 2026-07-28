import ./style_value

type
  Declaration* = object
    property*: string
    operation*: StyleOperation
    sourceOrder*: int

proc decl*(property: string; value: StyleValue; sourceOrder = 0): Declaration =
  Declaration(property: property, operation: overwrite(value), sourceOrder: sourceOrder)

proc decl*(property: string; operation: StyleOperation; sourceOrder = 0): Declaration =
  Declaration(property: property, operation: operation, sourceOrder: sourceOrder)
