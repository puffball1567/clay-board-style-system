import ./[color, color_mix, color_value, style_value]

type
  Declaration* = object
    property*: string
    operation*: StyleOperation
    sourceOrder*: int

proc decl*(property: string; value: StyleValue; sourceOrder = 0): Declaration =
  Declaration(property: property, operation: overwrite(value),
      sourceOrder: sourceOrder)

proc decl*(property: string; value: Color; sourceOrder = 0): Declaration =
  decl(property, colorValue(value), sourceOrder)

proc decl*(property: string; value: ColorValue; sourceOrder = 0): Declaration =
  decl(property, colorValue(value), sourceOrder)

proc decl*(property: string; value: ColorMixValue;
    sourceOrder = 0): Declaration =
  decl(property, colorValue(value), sourceOrder)

proc decl*(property: string; operation: StyleOperation;
    sourceOrder = 0): Declaration =
  Declaration(property: property, operation: operation,
      sourceOrder: sourceOrder)
