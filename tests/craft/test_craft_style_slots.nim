import std/[options, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

type SlotButton = ref object of CBSSComponent
  clicks: ref int
  labelNode: NodeHandle

proc render(self: SlotButton) =
  ui.box(self, ownedStyle = uiStyle([
    decl("width", px(96))
  ])):
    self.publicStyleSlot("root")
    self.labelNode = ui.text("Save")
    self.publicStyleSlot("label", some(self.labelNode))

  self.node.setFocusable()
  self.onClick = proc(event: DispatchResult): EventOutcome =
    inc self.clicks[]
    true

proc themeSource(name, background, labelColor: string): string =
  """{
    "format": "cbss-craft-style",
    "version": 1,
    "name": "$1",
    "rules": [
      {
        "selector": {"component": "slot-button", "slot": "root"},
        "priority": 500,
        "declarations": [
          {"property": "width", "value": {"type": "length", "unit": "px", "value": 240}},
          {"property": "background-color", "value": {"type": "color", "value": "$2"}}
        ]
      },
      {
        "selector": {"component": "slot-button", "slot": "label"},
        "priority": 20,
        "declarations": [
          {"property": "color", "value": {"type": "color", "value": "$3"}}
        ]
      }
    ]
  }""" % [name, background, labelColor]

proc missingSlotSource(name: string): string =
  """{
    "format": "cbss-craft-style",
    "version": 1,
    "name": "$1",
    "rules": [
      {
        "selector": {"component": "slot-button", "slot": "missing"},
        "declarations": [
          {"property": "opacity", "value": {"type": "number", "value": 0.5}}
        ]
      }
    ]
  }""" % [name]

proc resolvedStyles(root: UiRoot): ResolvedTree =
  var diagnostics: Diagnostics
  result = resolveTreeStyles(
    root.tree,
    root.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors

suite "Craft Style public slots":
  test "component and slot selectors are retained as a paired contract":
    let parsed = parseCraftStyle(themeSource("paired", "#cc2244", "#ffffff"))
    require parsed.isOk
    check parsed.value.get.targets.len == 2
    check parsed.value.get.targets[0].component == some("slot-button")
    check parsed.value.get.targets[0].slot == some("root")
    check parsed.value.get.targets[1].slot == some("label")

    let incomplete = parseCraftStyle("""{
      "format": "cbss-craft-style",
      "version": 1,
      "name": "incomplete",
      "rules": [{
        "selector": {"component": "slot-button"},
        "declarations": [{
          "property": "opacity",
          "value": {"type": "number", "value": 1}
        }]
      }]
    }""")
    check not incomplete.isOk
    check incomplete.diagnostics[^1].code == csdcInvalidValue
    check incomplete.diagnostics[^1].path == "$.rules[0].selector"

  test "replacement is atomic and component-owned invariants win":
    let root = initUiRoot()
    let clicks = new int
    let component = root.mount(SlotButton(
      craftName: "slot-button",
      clicks: clicks
    ))
    let componentNode = component.node.id
    let labelNode = component.labelNode.id
    discard root.consumeInvalidation()

    let first = root.replaceCraftStyle(
      themeSource("application-theme", "#cc2244", "#f7f7f7")
    )
    require first.applied
    check first.parseDiagnostics.len == 0
    check first.replacementDiagnostics.len == 0
    check root.activeCraftStyleNames() == @["application-theme"]
    check root.publicStyleSlots().len == 2

    let firstInvalidation = root.consumeInvalidation()
    check firstInvalidation.domains == {
      ddStyle, ddLayout, ddPaint, ddHit, ddText
    }
    check firstInvalidation.roots == @[componentNode]

    var styles = root.resolvedStyles()
    check styles.styles[componentNode.nodeIndex].layout.width == some(96.0'f32)
    check styles.styles[componentNode.nodeIndex].box.backgroundColor ==
      some(rgb(0.8, 0.13333334, 0.26666668))
    check styles.styles[labelNode.nodeIndex].text.color ==
      some(rgb(0.96862745, 0.96862745, 0.96862745))

    var interaction = initInteractionState()
    check root.setFocus(interaction, some(componentNode), focusVisible = true)
    check root.events.emit(root.tree, componentNode, iekClick)
    check clicks[] == 1

    let rejected = root.replaceCraftStyle(missingSlotSource("application-theme"))
    check not rejected.applied
    check rejected.parseDiagnostics.len == 0
    check rejected.replacementDiagnostics.len == 1
    check rejected.replacementDiagnostics[0].code == csrUndeclaredStyleSlot
    check not root.hasPendingInvalidation
    check root.activeCraftStyleNames() == @["application-theme"]
    styles = root.resolvedStyles()
    check styles.styles[componentNode.nodeIndex].box.backgroundColor ==
      some(rgb(0.8, 0.13333334, 0.26666668))

    let malformed = root.replaceCraftStyle("{not-json")
    check not malformed.applied
    check malformed.parseDiagnostics.len == 1
    check malformed.replacementDiagnostics.len == 0
    check not root.hasPendingInvalidation

    let second = root.replaceCraftStyle(
      themeSource("application-theme", "#2255cc", "#111111")
    )
    require second.applied
    check root.activeCraftStyleNames() == @["application-theme"]
    check component.node.id == componentNode
    check interaction.focusedTarget == some(componentNode)
    check root.events.emit(root.tree, componentNode, iekClick)
    check clicks[] == 2
    styles = root.resolvedStyles()
    check styles.styles[componentNode.nodeIndex].layout.width == some(96.0'f32)
    check styles.styles[componentNode.nodeIndex].box.backgroundColor ==
      some(rgb(0.13333334, 0.33333334, 0.8))

    var disposeInteraction = interaction
    check root.disposeSubtree(component.node, disposeInteraction)
    check root.publicStyleSlots().len == 0
    check root.activeCraftStyleNames() == @["application-theme"]
    check root.styleSheets().len == 2
    check root.styleSheets()[0].rules.len == 0
    check root.removeCraftStyle("application-theme")
    check root.activeCraftStyleNames().len == 0
    check not root.removeCraftStyle("application-theme")

  test "slot registration rejects foreign, stale, and empty contracts":
    let root = initUiRoot()
    let other = initUiRoot()
    let owner = root.box()
    let child = root.box(parent = some(owner))
    let sibling = root.box()
    let foreign = other.box()

    expect ValueError:
      discard root.exposePublicStyleSlot(owner, child, "", "root")
    expect ValueError:
      discard root.exposePublicStyleSlot(owner, child, "panel", "")
    expect ValueError:
      discard root.exposePublicStyleSlot(owner, foreign, "panel", "root")
    expect ValueError:
      discard root.exposePublicStyleSlot(owner, sibling, "panel", "root")
    check root.exposePublicStyleSlot(owner, child, "panel", "body")
    check not root.exposePublicStyleSlot(owner, child, "panel", "body")
    expect ValueError:
      discard root.exposePublicStyleSlot(owner, owner, "other-panel", "root")

  test "active styles expand to later component instances and remove cleanly":
    let root = initUiRoot()
    let app = root.box()
    root.pushParent(app)
    let first = root.mount(SlotButton(
      craftName: "slot-button",
      clicks: new int
    ))
    root.popParent()
    discard root.consumeInvalidation()
    require root.replaceCraftStyle(
      themeSource("shared-theme", "#2255cc", "#ffffff")
    ).applied
    discard root.consumeInvalidation()

    root.pushParent(app)
    let second = root.mount(SlotButton(
      craftName: "slot-button",
      clicks: new int
    ))
    root.popParent()
    let mountedInvalidation = root.consumeInvalidation()
    check second.node.id in mountedInvalidation.roots
    check root.publicStyleSlots().len == 4
    check root.styleSheets()[0].rules.len == 4
    var styles = root.resolvedStyles()
    check styles.styles[first.node.id.nodeIndex].box.backgroundColor ==
      some(rgb(0.13333334, 0.33333334, 0.8))
    check styles.styles[second.node.id.nodeIndex].box.backgroundColor ==
      some(rgb(0.13333334, 0.33333334, 0.8))

    check root.removeCraftStyle("shared-theme")
    let removal = root.consumeInvalidation()
    check removal.domains == {ddStyle, ddLayout, ddPaint, ddHit, ddText}
    check removal.roots == @[first.node.id, second.node.id]
    styles = root.resolvedStyles()
    check styles.styles[first.node.id.nodeIndex].box.backgroundColor.isNone
    check styles.styles[second.node.id.nodeIndex].box.backgroundColor.isNone

  test "unscoped and structurally inconsistent candidates never replace active Style":
    let root = initUiRoot()
    root.mount(SlotButton(craftName: "slot-button", clicks: new int))
    discard root.consumeInvalidation()
    require root.replaceCraftStyle(
      themeSource("guarded-theme", "#2255cc", "#ffffff")
    ).applied
    discard root.consumeInvalidation()

    let unscoped = parseCraftStyle("""{
      "format": "cbss-craft-style",
      "version": 1,
      "name": "guarded-theme",
      "rules": [{
        "selector": {"element": "box"},
        "declarations": [{
          "property": "opacity",
          "value": {"type": "number", "value": 0.5}
        }]
      }]
    }""")
    require unscoped.isOk
    let rejectedUnscoped = root.replaceCraftStyle(unscoped.value.get)
    check not rejectedUnscoped.applied
    check rejectedUnscoped.diagnostics.len == 1
    check rejectedUnscoped.diagnostics[0].code == csrUnsupportedRuleTarget

    var inconsistent = parseCraftStyle(
      themeSource("guarded-theme", "#cc2244", "#111111")
    ).value.get
    inconsistent.targets.setLen(1)
    let rejectedInconsistent = root.replaceCraftStyle(inconsistent)
    check not rejectedInconsistent.applied
    check rejectedInconsistent.diagnostics.len == 1
    check rejectedInconsistent.diagnostics[0].code == csrInvalidCraftStyle
    check root.activeCraftStyleNames() == @["guarded-theme"]
    check not root.hasPendingInvalidation
