import std/[options, times, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc resolvedStyles(ui: UiRoot): ResolvedTree =
  var diagnostics: Diagnostics
  result = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors

suite "switch component":
  test "click toggles state and emits input before change":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")
    var seen: seq[tuple[kind: InputEventKind, value: string]] = @[]

    live.onInput = proc(event: DispatchResult): EventOutcome =
      seen.add (event.event.kind, event.event.text.get(""))
      false
    live.onChange = proc(event: DispatchResult): EventOutcome =
      seen.add (event.event.kind, event.event.text.get(""))
      false

    discard live.container.emit(InputEvent(kind: iekClick))

    check live.checked()
    check seen == @[(iekInput, "true"), (iekChange, "true")]
    check esChecked in ui.tree.nodes[live.container.nodeId.nodeIndex].states
    check esChecked in ui.tree.nodes[live.trackNode.nodeId.nodeIndex].states
    check esChecked in ui.tree.nodes[live.thumbNode.nodeId.nodeIndex].states
    check ui.tree.nodes[live.container.nodeId.nodeIndex].attrValue("checked").get == "true"
    check ui.tree.nodes[live.container.nodeId.nodeIndex].attrValue("value").get == "true"

  test "setChecked is silent by default and can emit value events":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")
    var changes = 0

    live.onChange = proc(event: DispatchResult): EventOutcome =
      inc changes
      false

    live.setChecked(true)
    check live.checked()
    check changes == 0

    live.setChecked(false, emitEvents = true)
    check not live.checked()
    check changes == 1

    live.setChecked(false, emitEvents = true)
    check changes == 1

  test "Space and Enter activate through the click event path":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")
    var clicks = 0

    live.onClick = proc(event: DispatchResult): EventOutcome =
      inc clicks
      false

    discard live.container.emit(keyDownEvent(" "))
    check live.checked()
    discard live.container.emit(keyDownEvent("Enter"))

    check not live.checked()
    check clicks == 2

  test "unrelated keys do not change the switch":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")

    discard live.container.emit(keyDownEvent("ArrowRight"))
    discard live.container.emit(keyDownEvent("a"))

    check not live.checked()

  test "disabled switch suppresses pointer keyboard and user handlers":
    let ui = initUiRoot()
    let live = ui.switch(SwitchParams(
      label: "Live updates",
      checked: true,
      disabled: true
    ))
    var clicked = false
    var changed = false

    live.onClick = proc(event: DispatchResult): EventOutcome =
      clicked = true
      false
    live.onChange = proc(event: DispatchResult): EventOutcome =
      changed = true
      false

    discard live.container.emit(InputEvent(kind: iekClick))
    discard live.container.emit(keyDownEvent(" "))

    check live.checked()
    check live.disabled()
    check not clicked
    check not changed
    check esDisabled in ui.tree.nodes[live.container.nodeId.nodeIndex].states

  test "setDisabled restores interaction when enabled again":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")

    live.setDisabled(true)
    discard live.container.emit(InputEvent(kind: iekClick))
    check not live.checked()

    live.setDisabled(false)
    discard live.container.emit(InputEvent(kind: iekClick))
    check live.checked()
    check esDisabled notin ui.tree.nodes[live.container.nodeId.nodeIndex].states

  test "fieldset disabled state applies without losing an owned disabled state":
    let ui = initUiRoot()
    var inherited, owned: SwitchHandle

    let group = ui.fieldset("Features"):
      inherited = ui.switch("Live updates")
      owned = ui.switch(SwitchParams(label: "Locked", disabled: true))

    group.setDisabled(true)
    check inherited.disabled()
    check owned.disabled()

    group.setDisabled(false)
    check not inherited.disabled()
    check owned.disabled()

  test "setLabel updates visible and semantic names":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")

    live.setLabel("Automatic updates")

    check ui.tree.nodes[live.labelNode.nodeId.nodeIndex].text == "Automatic updates"
    check ui.tree.nodes[live.container.nodeId.nodeIndex].attrValue("label").get == "Automatic updates"
    check ui.tree.resolvedAccessibleName(live.container.nodeId) == "Automatic updates"

  test "external label activation focuses and toggles the switch":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")
    let caption = ui.label("Enable live updates", live)

    discard caption.container.emit(InputEvent(kind: iekClick))

    check live.checked()
    check ui.tree.semanticInfo(live.container.nodeId).labelledBy ==
      some(caption.container.nodeId)

  test "keyboard focus ring follows the rounded track instead of the label container":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")
    let next = ui.button("Next")
    var interaction = initInteractionState()

    check ui.setFocus(
      interaction,
      some(live.container.nodeId),
      focusVisible = true
    )
    check esFocusVisible in
      ui.tree.nodes[live.trackNode.nodeId.nodeIndex].states

    check ui.setFocus(
      interaction,
      some(next.container.nodeId),
      focusVisible = true
    )
    check esFocusVisible notin
      ui.tree.nodes[live.trackNode.nodeId.nodeIndex].states

  test "checked state moves the thumb with a paint transform":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")

    var styles = ui.resolvedStyles()
    check styles.styles[live.thumbNode.nodeId.nodeIndex].transform.operations.len == 1
    check styles.styles[live.thumbNode.nodeId.nodeIndex].transform.operations[0].xLength.get.value == 0

    live.setChecked(true, animate = false)
    styles = ui.resolvedStyles()
    let thumb = styles.styles[live.thumbNode.nodeId.nodeIndex]
    check thumb.transform.operations.len == 1
    check thumb.transform.operations[0].kind == ctkTranslate
    check thumb.transform.operations[0].xLength.get.value == 22.0'f32
    check thumb.transform.operations[0].yLength.get.value == 0.0'f32

  test "default rounded surfaces use uniform borders":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")
    let styles = ui.resolvedStyles()
    let track = styles.styles[live.trackNode.nodeId.nodeIndex]
    let thumb = styles.styles[live.thumbNode.nodeId.nodeIndex]

    check track.box.borderColors.top == track.box.borderColors.right
    check track.box.borderColors.top == track.box.borderColors.bottom
    check track.box.borderColors.top == track.box.borderColors.left
    check thumb.box.borderColors.top == thumb.box.borderColors.right
    check thumb.box.borderColors.top == thumb.box.borderColors.bottom
    check thumb.box.borderColors.top == thumb.box.borderColors.left

  test "default thumb travel leaves equal visual gaps at both endpoints":
    let ui = initUiRoot()
    let live = ui.switch("Live updates")
    var styles = ui.resolvedStyles()
    var layout = computeLayout(ui.tree, styles, size(300, 80))
    let offTrack = presentationForNode(
      ui.tree, layout, styles, live.trackNode.nodeId
    ).get
    let offThumb = presentationForNode(
      ui.tree, layout, styles, live.thumbNode.nodeId
    ).get
    let offGap = offThumb.bounds.x - offTrack.bounds.x
    let topGap = offThumb.bounds.y - offTrack.bounds.y
    let bottomGap = offTrack.bounds.y + offTrack.bounds.h -
      offThumb.bounds.y - offThumb.bounds.h

    live.setChecked(true, animate = false)
    styles = ui.resolvedStyles()
    layout = computeLayout(ui.tree, styles, size(300, 80))
    let onTrack = presentationForNode(
      ui.tree, layout, styles, live.trackNode.nodeId
    ).get
    let onThumb = presentationForNode(
      ui.tree, layout, styles, live.thumbNode.nodeId
    ).get
    let onGap = onTrack.bounds.x + onTrack.bounds.w -
      onThumb.bounds.x - onThumb.bounds.w

    check offGap == 2.0'f32
    check onGap == offGap
    check topGap == 3.0'f32
    check bottomGap == topGap

  test "caller styles override defaults in base and checked states":
    let ui = initUiRoot()
    let live = ui.switch(
      "Live updates",
      checked = true,
      trackStyle = uiStyle([
        decl("width", px(52)),
        decl("background-color", colorValue(rgb(0.10, 0.20, 0.30)))
      ]),
      checkedTrackStyle = uiStyle([
        decl("background-color", colorValue(rgb(0.75, 0.25, 0.40)))
      ]),
      checkedThumbStyle = uiStyle([
        decl("background-color", colorValue(rgb(0.95, 0.90, 0.82)))
      ]),
      thumbTravel = 28
    )

    let styles = ui.resolvedStyles()
    let track = styles.styles[live.activeTrackNode.nodeId.nodeIndex]
    let thumb = styles.styles[live.thumbNode.nodeId.nodeIndex]
    check styles.styles[live.trackNode.nodeId.nodeIndex].layout.width == some(52.0'f32)
    check track.box.backgroundColor == some(rgb(0.75, 0.25, 0.40))
    check thumb.transform.operations[0].xLength.get.value == 28.0'f32
    check thumb.box.backgroundColor == some(rgb(0.95, 0.90, 0.82))

  test "ease transition interpolates thumb and checked overlay without layout changes":
    let ui = initUiRoot()
    let live = ui.switch("Live updates", transitionDurationSeconds = 0.2)
    var scheduler = initFrameScheduler()
    let styleSlots = ui.componentStyles.len

    discard live.container.emit(InputEvent(kind: iekClick))
    let startedAt = live.state.animationStartedAt
    check live.transitioning()
    check ui.activeAnimationOwners() == @[live.container.nodeId]

    check ui.tickOwnedAnimations(scheduler, startedAt) == 1
    var styles = ui.resolvedStyles()
    let startThumb = styles.styles[live.thumbNode.nodeId.nodeIndex]
    let startOverlay = styles.styles[live.activeTrackNode.nodeId.nodeIndex]
    check startThumb.transform.operations[0].xLength.get.value == 0
    check startOverlay.visual.opacity == 0

    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check ui.tickOwnedAnimations(scheduler, startedAt + 0.1) == 1
    styles = ui.resolvedStyles()
    let middleX = styles.styles[live.thumbNode.nodeId.nodeIndex]
      .transform.operations[0].xLength.get.value
    let middleOpacity = styles.styles[live.activeTrackNode.nodeId.nodeIndex]
      .visual.opacity
    check middleX > 0 and middleX < 22
    check middleOpacity > 0 and middleOpacity < 1

    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check ui.tickOwnedAnimations(scheduler, startedAt + 0.2) == 1
    styles = ui.resolvedStyles()
    check styles.styles[live.thumbNode.nodeId.nodeIndex]
      .transform.operations[0].xLength.get.value == 22
    check styles.styles[live.activeTrackNode.nodeId.nodeIndex].visual.opacity == 1
    check not live.transitioning()
    check ui.activeAnimationOwners().len == 0
    check ui.componentStyles.len == styleSlots

  test "rapid reversal continues from the sampled visual position":
    let ui = initUiRoot()
    let live = ui.switch("Live updates", transitionDurationSeconds = 0.2)
    var scheduler = initFrameScheduler()

    discard live.container.emit(InputEvent(kind: iekClick))
    let firstStart = live.state.animationStartedAt
    discard ui.tickOwnedAnimations(scheduler, firstStart + 0.1)
    let sampled = live.state.visualProgress
    check sampled > 0 and sampled < 1

    live.toggle()
    check live.state.visualProgress == sampled
    let reverseStart = live.state.animationStartedAt
    discard ui.tickOwnedAnimations(scheduler, reverseStart + 0.2 * sampled + 0.001)

    check not live.checked()
    check abs(live.state.visualProgress) < 0.000001
    check not live.transitioning()

  test "invalid animation values are rejected":
    let ui = initUiRoot()
    expect ValueError:
      discard ui.switch("Invalid", transitionDurationSeconds = -0.1)
    expect ValueError:
      discard ui.switch("Invalid", thumbTravel = -1)

  test "reduced motion completes on the first animation tick":
    let ui = initUiRoot()
    ui.setReducedMotion(true)
    let live = ui.switch("Live updates")
    var scheduler = initFrameScheduler()

    discard live.container.emit(InputEvent(kind: iekClick))
    check ui.tickOwnedAnimations(scheduler, live.state.animationStartedAt) == 1

    check live.state.visualProgress == 1
    check not live.transitioning()

  test "disposed handles cannot mutate reused nodes":
    let ui = initUiRoot()
    let app = ui.box()
    let live = ui.switch("Live updates", id = "live", groups = [])
    var interaction = initInteractionState()
    var scheduler = initFrameScheduler()

    live.toggle()
    check live.transitioning()
    check ui.disposeSubtree(live.container, interaction)
    let replacement = ui.box(parent = some(app))
    live.setChecked(true)
    live.setLabel("Stale")
    live.setDisabled(true)

    check replacement.valid()
    check not live.container.valid()
    check ui.tickOwnedAnimations(scheduler, epochTime() + 1) == 0
