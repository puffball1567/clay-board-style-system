when not defined(linux):
  {.error: "Linux AT-SPI transport tests require Linux.".}

import std/[options, sets, unittest]

import clay_board_style_system/backends/atspi/[adapter, linux_dbus]
import clay_board_style_system/core/geometry

proc sampleSnapshot(): AtspiSnapshot =
  let buttonPath = "/org/a11y/atspi/accessible/node_1"
  AtspiSnapshot(
    applicationName: "Contract test",
    toolkitName: "CBSS",
    nodes: @[
      AtspiNode(
        objectPath: atspiRootPath,
        parentPath: atspiNullPath,
        childPaths: @[buttonPath],
        role: atrApplication,
        interfaces: {atiAccessible, atiApplication}
      ),
      AtspiNode(
        objectPath: buttonPath,
        parentPath: atspiRootPath,
        role: atrPushButton,
        interfaces: {atiAccessible, atiAction, atiComponent},
        actions: @["activate"],
        bounds: some(rect(0, 0, 100, 30))
      )
    ]
  )

suite "Linux AT-SPI D-Bus contract":
  test "object paths accept only generated CBSS accessibility paths":
    check validAtspiObjectPath(atspiRootPath)
    check validAtspiObjectPath("/org/a11y/atspi/accessible/node_0")
    check validAtspiObjectPath("/org/a11y/atspi/accessible/node_123456")
    check not validAtspiObjectPath(atspiNullPath)
    check not validAtspiObjectPath("/org/a11y/atspi/accessible/node_")
    check not validAtspiObjectPath("/org/a11y/atspi/accessible/node_-1")
    check not validAtspiObjectPath("/org/a11y/atspi/accessible/node_1/child")
    check not validAtspiObjectPath("/tmp/node_1")

  test "advertised neutral interfaces map to official D-Bus names":
    let node = AtspiNode(interfaces: {
      atiAccessible,
      atiApplication,
      atiAction,
      atiComponent
    })

    check node.interfaceNames() == @[
      accessibleInterface,
      applicationInterface,
      actionInterface,
      componentInterface
    ]

  test "every neutral role has one stable AT-SPI role code":
    var codes = initHashSet[uint32]()
    for role in AtspiRole:
      let code = role.roleCode()
      check code > 0
      check code notin codes
      check role.roleName().len > 0
      codes.incl code

    check atrApplication.roleCode() == 75
    check atrPushButton.roleCode() == 43
    check atrEntry.roleCode() == 79
    check atrLink.roleCode() == 88
    check atrSlider.roleCode() == 51
    check atrToggleButton.roleCode() == 62

  test "state arrays use official AT-SPI state values in deterministic order":
    check stateCodes({
      atsChecked,
      atsEnabled,
      atsFocusable,
      atsFocused,
      atsVisible,
      atsInvalid
    }) == @[4'u32, 8'u32, 11'u32, 12'u32, 30'u32, 36'u32]

  test "snapshot validation accepts one connected supported tree":
    check sampleSnapshot().validAtspiSnapshot()

  test "snapshot validation rejects unsafe identity and topology":
    var snapshot = sampleSnapshot()
    snapshot.nodes[1].objectPath = "/tmp/untrusted"
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes.add snapshot.nodes[1]
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes[1].parentPath = "/org/a11y/atspi/accessible/node_99"
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes[0].childPaths.setLen(0)
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes[0].childPaths.add snapshot.nodes[1].objectPath
    check not snapshot.validAtspiSnapshot()

  test "snapshot validation rejects disconnected cycles":
    let firstPath = "/org/a11y/atspi/accessible/node_1"
    let secondPath = "/org/a11y/atspi/accessible/node_2"
    var snapshot = sampleSnapshot()
    snapshot.nodes[0].childPaths.setLen(0)
    snapshot.nodes[1].parentPath = secondPath
    snapshot.nodes[1].childPaths = @[secondPath]
    snapshot.nodes.add AtspiNode(
      objectPath: secondPath,
      parentPath: firstPath,
      childPaths: @[firstPath],
      role: atrPanel,
      interfaces: {atiAccessible}
    )
    check not snapshot.validAtspiSnapshot()

  test "snapshot validation rejects unsupported capability combinations":
    var snapshot = sampleSnapshot()
    snapshot.nodes[1].interfaces.incl atiText
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes[1].interfaces.excl atiAction
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes[1].actions = @["delete"]
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes[1].bounds = none(Rect)
    check not snapshot.validAtspiSnapshot()

    snapshot = sampleSnapshot()
    snapshot.nodes[1].interfaces.incl atiApplication
    check not snapshot.validAtspiSnapshot()
