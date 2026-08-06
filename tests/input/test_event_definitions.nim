import std/[sets, strutils, unittest]

import clay_board_style_system/input/events

suite "event definition source":
  test "every event owns stable public names and an ABI code":
    var names = initHashSet[string]()
    var abiCodes = initHashSet[uint32]()

    for kind in InputEventKind:
      let definition = kind.eventDefinition
      check definition.publicNameCount in 1'u8 .. 2'u8
      check definition.abiCode == uint32(ord(kind))
      check definition.abiCode notin abiCodes
      abiCodes.incl(definition.abiCode)

      var observed = 0
      for publicName in kind.publicEventNames:
        check publicName.startsWith("on")
        check publicName.len > 2
        check publicName notin names
        names.incl(publicName)
        inc observed
      check observed == int(definition.publicNameCount)
      check kind.primaryEventName == definition.publicNames[0]

  test "double click keeps its documented compatibility alias":
    check iekDoubleClick.primaryEventName == "onDoubleClick"
    check iekDoubleClick.eventDefinition.publicNameCount == 2
    check iekDoubleClick.eventDefinition.publicNames[1] == "onDblClick"

  test "unused public name slots remain empty":
    for kind in InputEventKind:
      let definition = kind.eventDefinition
      for index in int(definition.publicNameCount) ..< definition.publicNames.len:
        check definition.publicNames[index].len == 0
