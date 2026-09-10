import std/unittest

import clay_board_style_system/generated/craft_driver_contract

suite "Craft Driver contract metadata":
  test "publishes one ordered identity for every capability":
    check CbssAbiVersion == 0x0001_001D'u32
    check CbssDriverContractVersion == 0x0001_0000'u32
    check CbssCapabilities.len == 22

    var previousId = 0'u32
    for capability in CbssCapabilities:
      check capability.id > previousId
      check capability.version > 0
      check capability.sinceAbi <= CbssAbiVersion
      check capability.name.len > 0
      previousId = capability.id

  test "keeps generated constants aligned with the table":
    check CbssCapabilities[0].id == CbssCapabilityRetainedTree
    check CbssCapabilities[14].id == CbssCapabilityStream
    check CbssCapabilities[^7].id == CbssCapabilityCraftStyle
    check CbssCapabilities[^6].id == CbssCapabilityCraftPack
    check CbssCapabilities[^5].id == CbssCapabilitySubtreeLifecycle
    check CbssCapabilities[^4].id == CbssCapabilityValidationPattern
    check CbssCapabilities[^3].id == CbssCapabilityRasterSurface
    check CbssCapabilities[^2].id == CbssCapabilityShaderAuthoring
    check CbssCapabilities[^2].version == 2
    check CbssCapabilities[^1].id == CbssCapabilityCustomPaintProvider
    check CbssCapabilities[^1].version == 1
    check CbssCapabilities[0].name == "tree.retained"
    check CbssCapabilities[^5].name == "tree.subtree-lifecycle"
    check CbssCapabilities[^4].name == "validation.pattern"
    check CbssCapabilities[^3].name == "raster-surface"
    check CbssCapabilities[^2].name == "shader.authoring"
    check CbssCapabilities[^1].name == "custom-paint.provider"
