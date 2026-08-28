import ./[declaration, selector]

type
  StyleRule* = object
    selector*: SelectorCondition
    declarations*: seq[Declaration]
    cascadeLayer*: int
    priority*: int
    sourceOrder*: int

  StyleSheet* = object
    rules*: seq[StyleRule]

proc rule*(
    selector: SelectorCondition;
    declarations: openArray[Declaration];
    priority = 0;
    sourceOrder = 0;
    cascadeLayer = 0
): StyleRule =
  StyleRule(
    selector: selector,
    declarations: @declarations,
    cascadeLayer: cascadeLayer,
    priority: priority,
    sourceOrder: sourceOrder
  )

proc styleSheet*(rules: openArray[StyleRule]): StyleSheet =
  StyleSheet(rules: @rules)
