import std/options
import ./node

type
  AttrCondition* = object
    name*: string
    value*: Option[string]

  SelectorCondition* = object
    nodeId*: Option[NodeId]
    elementKind*: Option[NodeKind]
    id*: Option[string]
    code*: Option[string]
    groups*: seq[string]
    attrs*: seq[AttrCondition]
    requiredStates*: set[ElementState]

proc selector*(): SelectorCondition =
  SelectorCondition(groups: @[], attrs: @[])

proc element*(kind: NodeKind): SelectorCondition =
  result = selector()
  result.elementKind = some(kind)

proc target*(nodeId: NodeId): SelectorCondition =
  result = selector()
  result.nodeId = some(nodeId)

proc id*(name: string): SelectorCondition =
  result = selector()
  result.id = some(name)

proc code*(value: string): SelectorCondition =
  result = selector()
  result.code = some(value)

proc group*(name: string): SelectorCondition =
  result = selector()
  result.groups.add name

proc attr*(name, value: string): AttrCondition =
  AttrCondition(name: name, value: some(value))

proc attrExists*(name: string): AttrCondition =
  AttrCondition(name: name, value: none(string))

proc matches*(condition: SelectorCondition; node: Node; nodeId = none(NodeId)): bool =
  if condition.nodeId.isSome:
    if nodeId.isNone or nodeId.get != condition.nodeId.get:
      return false
  if condition.elementKind.isSome and node.kind != condition.elementKind.get:
    return false
  if condition.id.isSome and node.id != condition.id.get:
    return false
  if condition.code.isSome and node.code != condition.code.get:
    return false
  for group in condition.groups:
    if not node.hasGroup(group):
      return false
  for attr in condition.attrs:
    let actual = node.attrValue(attr.name)
    if actual.isNone:
      return false
    if attr.value.isSome and actual.get != attr.value.get:
      return false
  for state in condition.requiredStates:
    if state notin node.states:
      return false
  true

proc specificity*(condition: SelectorCondition): int =
  if condition.nodeId.isSome:
    result += 100
  if condition.elementKind.isSome:
    result += 1
  if condition.id.isSome:
    result += 10
  if condition.code.isSome:
    result += 10
  result += condition.groups.len * 10
  result += condition.attrs.len * 10
  result += card(condition.requiredStates) * 10
