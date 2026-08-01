import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

type
  LinkScreen = enum
    lsHome,
    lsSettings,
    lsDetails

suite "link primitive":
  test "click pushes the typed destination and still invokes user onClick":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(navigator, lsSettings, "Settings")
    var clicked = false
    settings.onClick = proc(event: DispatchResult): bool =
      clicked = true
      true

    discard settings.container.emit(InputEvent(kind: iekClick))

    check clicked
    check navigator.currentDestination() == some(lsSettings)
    check navigator.canGoBack()

  test "navigation completes before the user click handler runs":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(navigator, lsSettings, "Settings")
    var destinationSeenByHandler = lsHome
    settings.onClick = proc(event: DispatchResult): bool =
      destinationSeenByHandler = navigator.currentDestination().get
      false

    check not settings.container.emit(InputEvent(kind: iekClick))
    check destinationSeenByHandler == lsSettings

  test "assigning onClick replaces only the public handler":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(navigator, lsSettings, "Settings")
    var firstCalls = 0
    var secondCalls = 0
    settings.onClick = proc(event: DispatchResult): bool =
      inc firstCalls
      true
    settings.onClick = proc(event: DispatchResult): bool =
      inc secondCalls
      true

    check settings.container.emit(InputEvent(kind: iekClick))
    check firstCalls == 0
    check secondCalls == 1
    check navigator.currentDestination() == some(lsSettings)

  test "Enter activates a link while Space keeps its ordinary key behavior":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(navigator, lsSettings, "Settings")

    check settings.container.emit(keyDownEvent("Enter"))
    check navigator.currentDestination() == some(lsSettings)
    check not settings.container.emit(keyDownEvent(" "))
    check not settings.container.emit(keyDownEvent("Escape"))
    check not settings.container.emit(keyUpEvent("Enter"))
    check navigator.snapshot().entries.len == 2

  test "disabled links suppress pointer keyboard and user handlers":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(
      navigator,
      lsSettings,
      "Settings",
      disabled = true
    )
    var clicked = false
    settings.onClick = proc(event: DispatchResult): bool =
      clicked = true
      true

    check settings.container.emit(InputEvent(kind: iekClick))
    check settings.container.emit(keyDownEvent("Enter"))

    check not clicked
    check navigator.currentDestination() == some(lsHome)
    check settings.disabled()
    check esDisabled in ui.tree.nodes[settings.container.nodeId.nodeIndex].states

  test "re-enabled links recover pointer keyboard and direct activation":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(
      navigator,
      lsSettings,
      "Settings",
      disabled = true
    )

    check not settings.activate()
    settings.setDisabled(false)
    check not settings.disabled()
    check esDisabled notin ui.tree.nodes[settings.container.nodeId.nodeIndex].states
    check settings.container.emit(keyDownEvent("Enter"))
    check navigator.currentDestination() == some(lsSettings)

  test "label destination and disabled state can be updated":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let destination = ui.link(navigator, lsSettings, "Settings")

    destination.setLabel("Details")
    destination.setDestination(lsDetails)
    destination.setDisabled(true)

    check destination.label() == "Details"
    check destination.destination() == lsDetails
    check ui.tree.nodes[destination.labelNode.nodeId.nodeIndex].text == "Details"
    check ui.tree.semanticInfo(destination.container.nodeId).name == "Details"
    check not destination.activate()

    destination.setDisabled(false)
    check destination.activate()
    check navigator.currentDestination() == some(lsDetails)

  test "empty and UTF-8 labels remain synchronized with semantics":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let destination = ui.link(navigator, lsSettings, "Initial")

    destination.setLabel("")
    check destination.label() == ""
    check ui.tree.nodes[destination.labelNode.nodeId.nodeIndex].text == ""
    check ui.tree.semanticInfo(destination.container.nodeId).name == ""

    destination.setLabel("設定へ移動")
    check destination.label() == "設定へ移動"
    check ui.tree.nodes[destination.labelNode.nodeId.nodeIndex].text == "設定へ移動"
    check ui.tree.semanticInfo(destination.container.nodeId).name == "設定へ移動"

  test "links expose focus and accessibility semantics":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(navigator, lsSettings, "Settings")
    var interaction = initInteractionState()

    check settings.container.focusable()
    check ui.setFocus(
      interaction,
      some(settings.container.nodeId),
      focusVisible = true
    )
    let semantic = ui.tree.semanticInfo(settings.container.nodeId)
    check semantic.role == arLink
    check semantic.name == "Settings"
    check esFocus in ui.tree.nodes[settings.container.nodeId.nodeIndex].states
    check esFocusVisible in ui.tree.nodes[settings.container.nodeId.nodeIndex].states

  test "link text does not intercept pointer hits":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let settings = ui.link(
      navigator,
      lsSettings,
      "Settings",
      style = uiStyle([
        decl("width", px(100)),
        decl("height", px(32))
      ])
    )

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree,
      ui.styleSheets(),
      defaultProperties(),
      diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(120, 60))
    let regions = buildHitRegions(layout, styles)
    let hit = hitTest(regions, vec2(20, 16))

    check not diagnostics.hasErrors
    check styles.styles[settings.labelNode.nodeId.nodeIndex].visual.pointerEvents == peNone
    check hit.isSome
    check hit.get.node == settings.container.nodeId

  test "AT-SPI exposes and activates links":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let root = ui.box(
      uiStyle([
        decl("width", px(180)),
        decl("height", px(60))
      ])
    )
    ui.pushParent(root)
    let settings = ui.link(
      navigator,
      lsSettings,
      "Settings",
      style = uiStyle([
        decl("width", px(100)),
        decl("height", px(32))
      ])
    )
    ui.popParent()

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree,
      ui.styleSheets(),
      defaultProperties(),
      diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(180, 60))
    let snapshot = ui.buildAtspiSnapshot(layout, "Navigation")
    let path = objectPathFor(settings.container.nodeId)
    let accessible = snapshot.nodeAt(path)

    check accessible.isSome
    check accessible.get.role == atrLink
    check accessible.get.actions == @["activate"]
    check ui.performAtspiAction(snapshot, path)
    check navigator.currentDestination() == some(lsSettings)

  test "AT-SPI rejects disabled links and unsupported actions":
    let navigator = initStackNavigator(lsHome)
    let ui = initUiRoot()
    let root = ui.box(
      uiStyle([decl("width", px(180)), decl("height", px(60))])
    )
    ui.pushParent(root)
    let settings = ui.link(
      navigator,
      lsSettings,
      "Settings",
      disabled = true,
      style = uiStyle([decl("width", px(100)), decl("height", px(32))])
    )
    ui.popParent()

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree,
      ui.styleSheets(),
      defaultProperties(),
      diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(180, 60))
    let snapshot = ui.buildAtspiSnapshot(layout, "Navigation")
    let path = objectPathFor(settings.container.nodeId)

    check not ui.performAtspiAction(snapshot, path)
    check not ui.performAtspiAction(snapshot, path, action = "open")
    check not ui.performAtspiAction(snapshot, "/missing")
    check navigator.currentDestination() == some(lsHome)

  test "activate reports a custom driver that declines navigation":
    proc currentSnapshot(): NavigationSnapshot[LinkScreen] =
      NavigationSnapshot[LinkScreen](
        entries: @[
          NavigationEntry[LinkScreen](
            id: NavigationEntryId(1),
            destination: lsHome
          )
        ],
        currentIndex: 0,
        revision: 0
      )
    proc noDestination(
        destination: LinkScreen
    ): Option[NavigationChange[LinkScreen]] =
      none(NavigationChange[LinkScreen])
    proc noStep(): Option[NavigationChange[LinkScreen]] =
      none(NavigationChange[LinkScreen])

    let navigator = initNavigator(NavigationDriver[LinkScreen](
      snapshot: currentSnapshot,
      push: noDestination,
      replace: noDestination,
      back: noStep,
      forward: noStep
    ))
    let ui = initUiRoot()
    let link = ui.link(navigator, lsSettings, "Settings")

    check not link.activate()
    check navigator.currentDestination() == some(lsHome)

  test "a nil navigator is rejected":
    let ui = initUiRoot()
    expect ValueError:
      discard ui.link(Navigator[LinkScreen](nil), lsSettings, "Settings")
