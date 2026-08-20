import std/unittest

import clay_board_style_system/generated/craft_driver_contract

suite "Craft Driver contract metadata":
  test "publishes one ordered identity for every capability":
    check CbssAbiVersion == 0x0001_0015'u32
    check CbssDriverContractVersion == 0x0001_0000'u32
    check CbssCapabilities.len == 15

    var previousId = 0'u32
    for capability in CbssCapabilities:
      check capability.id > previousId
      check capability.version > 0
      check capability.sinceAbi <= CbssAbiVersion
      check capability.name.len > 0
      previousId = capability.id

  test "keeps generated constants aligned with the table":
    check CbssCapabilities[0].id == CbssCapabilityRetainedTree
    check CbssCapabilities[^1].id == CbssCapabilityStream
    check CbssCapabilities[0].name == "tree.retained"
    check CbssCapabilities[^1].name == "data.stream"
