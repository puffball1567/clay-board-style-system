import std/tables
import ./property

type
  PropertyRegistry* = object
    properties*: Table[string, PropertyImpl]

proc initPropertyRegistry*(): PropertyRegistry =
  PropertyRegistry(properties: initTable[string, PropertyImpl]())

proc registerProperty*(registry: var PropertyRegistry; property: PropertyImpl) =
  registry.properties[property.name] = property

proc hasProperty*(registry: PropertyRegistry; name: string): bool =
  registry.properties.hasKey(name)

proc getProperty*(registry: PropertyRegistry; name: string): PropertyImpl =
  registry.properties[name]
