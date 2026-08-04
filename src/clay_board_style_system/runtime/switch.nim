import std/[math, options, times]

import ../core/[color, declaration, node, style_value]
import ../input/events
import ./[animation_clock, invalidation, ui_root]

type
  SwitchParams* = object
    label*: string
    checked*: bool
    disabled*: bool

  SwitchState* = ref object
    label*: string
    checked*: bool
    disabled*: bool
    visualProgress*: float64
    transitionDurationSeconds*: float64
    transitionTiming*: TimingFunction
    thumbTravel*: float32
    animation*: Option[AnimationId]
    animationStartedAt*: float64

  SwitchHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    trackNode*: NodeHandle
    activeTrackNode*: NodeHandle
    thumbNode*: NodeHandle
    labelNode*: NodeHandle
    state*: SwitchState

proc defaultSwitchStyle(): UiStyle =
  uiStyle([
    decl("min-height", px(30)),
    decl("gap", px(10)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("cursor", keyword("pointer"))
  ])

proc defaultTrackStyle(): UiStyle =
  uiStyle([
    decl("width", px(46)),
    decl("height", px(26)),
    decl("min-width", px(46)),
    decl("min-height", px(26)),
    decl("max-width", px(46)),
    decl("max-height", px(26)),
    decl("position", keyword("relative")),
    decl("background-color", colorValue(rgb(0.24, 0.27, 0.31))),
    decl("border-color", colorValue(rgb(0.13, 0.15, 0.18))),
    decl("border-width", px(1)),
    decl("border-radius", px(13)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(1),
      blur = some(px(2)),
      spread = some(px(0)),
      shadowColor = some(rgba(0, 0, 0, 0.30))
    )),
    decl("pointer-events", keyword("none"))
  ])

proc defaultThumbStyle(): UiStyle =
  uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(2)),
    decl("top", px(3)),
    decl("width", px(20)),
    decl("height", px(20)),
    decl("min-width", px(20)),
    decl("min-height", px(20)),
    decl("max-width", px(20)),
    decl("max-height", px(20)),
    decl("background-color", colorValue(rgb(0.985, 0.99, 1.0))),
    decl("border-color", colorValue(rgba(0.78, 0.82, 0.87, 0.84))),
    decl("border-width", px(1)),
    decl("border-radius", px(10)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(2),
      blur = some(px(4)),
      spread = some(px(0)),
      shadowColor = some(rgba(0, 0, 0, 0.30))
    )),
    decl("pointer-events", keyword("none"))
  ])

proc defaultLabelStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(13)),
    decl("line-height", number(1.25)),
    decl("color", colorValue(rgb(0.86, 0.88, 0.92))),
    decl("pointer-events", keyword("none"))
  ])

proc defaultCheckedTrackStyle(): UiStyle =
  uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(0)),
    decl("width", px(46)),
    decl("height", px(26)),
    decl("min-width", px(46)),
    decl("min-height", px(26)),
    decl("max-width", px(46)),
    decl("max-height", px(26)),
    decl("background-color", colorValue(rgb(0.13, 0.62, 0.48))),
    decl("border-radius", px(12)),
    decl("pointer-events", keyword("none")),
    decl("opacity", number(0))
  ])

proc applyVisualProgress(control: SwitchHandle; progress: float64) =
  if not control.container.valid():
    return
  let value = clamp(progress, 0.0, 1.0)
  control.state.visualProgress = value
  control.root.setNodeStyle(
    control.activeTrackNode.id,
    uiStyle([decl("opacity", number(value.float32))]),
    priority = 200
  )
  control.root.setNodeStyle(
    control.thumbNode.id,
    uiStyle([decl(
      "transform",
      transformValue(translate(px(control.state.thumbTravel * value.float32), px(0)))
    )]),
    priority = 200
  )

proc finishVisuals(control: SwitchHandle; checked: bool) =
  if control.state.animation.isSome:
    discard control.root.cancelOwnedAnimation(control.state.animation.get)
    control.state.animation = none(AnimationId)
  control.applyVisualProgress(if checked: 1.0 else: 0.0)

proc animateVisuals(control: SwitchHandle; checked: bool; nowSeconds: float64) =
  if not control.container.valid():
    return
  if control.state.animation.isSome:
    discard control.root.cancelOwnedAnimation(control.state.animation.get)
    control.state.animation = none(AnimationId)

  let target = if checked: 1.0 else: 0.0
  let start = control.state.visualProgress
  let distance = abs(target - start)
  if distance <= 0.000001 or control.state.transitionDurationSeconds <= 0:
    control.applyVisualProgress(target)
    return

  control.state.animationStartedAt = nowSeconds
  let animation = control.root.startOwnedAnimation(
    control.container,
    animationSpec(
      durationSeconds = control.state.transitionDurationSeconds * distance,
      timing = control.state.transitionTiming,
      dirtyDomains = {ddPaint},
      onSample = proc(sample: AnimationSample) =
        control.applyVisualProgress(start + (target - start) * sample.progress),
      onEnd = proc(id: AnimationId) =
        control.applyVisualProgress(target)
        if control.state.animation == some(id):
          control.state.animation = none(AnimationId)
    ),
    nowSeconds
  )
  control.state.animation = some(animation)

proc updateVisuals(control: SwitchHandle) =
  if not control.container.valid():
    return
  control.trackNode.setState(esChecked, control.state.checked)
  control.thumbNode.setState(esChecked, control.state.checked)
  control.root.tree.setAttribute(
    control.container.id,
    "checked",
    if control.state.checked: "true" else: "false"
  )
  control.root.tree.setAttribute(
    control.container.id,
    "value",
    if control.state.checked: "true" else: "false"
  )
  control.container.setAccessibleValue(
    if control.state.checked: "true" else: "false"
  )

proc emitValueEvents(control: SwitchHandle) =
  let value =
    if control.state.checked: "true"
    else: "false"
  discard control.container.emit(inputEvent(value))
  discard control.container.emit(changeEvent(value))

proc setLabel*(control: SwitchHandle; label: string) =
  if not control.container.valid():
    return
  control.state.label = label
  control.root.tree.nodes[control.labelNode.id.nodeIndex].text = label
  control.root.tree.setAttribute(control.container.id, "label", label)
  control.container.setAccessibleName(label)

proc setChecked*(
    control: SwitchHandle;
    checked: bool;
    emitEvents = false;
    animate = true
) =
  if not control.container.valid() or control.state.checked == checked:
    return
  control.state.checked = checked
  control.container.setState(esChecked, checked)
  control.updateVisuals()
  if animate:
    control.animateVisuals(checked, epochTime())
  else:
    control.finishVisuals(checked)
  if emitEvents:
    control.emitValueEvents()

proc toggle*(control: SwitchHandle; emitEvents = true) =
  if not control.container.valid() or control.state.disabled:
    return
  control.setChecked(
    not control.state.checked,
    emitEvents = emitEvents,
    animate = true
  )

proc setDisabled*(control: SwitchHandle; disabled: bool) =
  if not control.container.valid():
    return
  control.state.disabled = disabled
  control.container.setState(esDisabled, disabled)

proc checked*(control: SwitchHandle): bool =
  control.state.checked

proc disabled*(control: SwitchHandle): bool =
  control.state.disabled

proc transitioning*(control: SwitchHandle): bool =
  control.state.animation.isSome

proc `onChange=`*(control: SwitchHandle; handler: EventHandler) =
  control.container.onChange = handler

proc `onInput=`*(control: SwitchHandle; handler: EventHandler) =
  control.container.onInput = handler

proc `onClick=`*(control: SwitchHandle; handler: EventHandler) =
  control.container.onClick = handler

proc switch*(
    root: UiRoot;
    params: SwitchParams;
    style = UiStyle();
    trackStyle = UiStyle();
    thumbStyle = UiStyle();
    labelStyle = UiStyle();
    checkedTrackStyle = UiStyle();
    checkedThumbStyle = UiStyle();
    transitionDurationSeconds = 0.18;
    transitionTiming = easeTiming();
    thumbTravel = 22.0'f32;
    id = "";
    groups: openArray[string] = ["switch"]
): SwitchHandle {.discardable.} =
  if transitionDurationSeconds.classify in {fcNan, fcInf, fcNegInf} or
      transitionDurationSeconds < 0:
    raise newException(
      ValueError,
      "switch transition duration must be finite and non-negative"
    )
  if thumbTravel.classify in {fcNan, fcInf, fcNegInf} or thumbTravel < 0:
    raise newException(ValueError, "switch thumb travel must be finite and non-negative")
  result.root = root
  result.state = SwitchState(
    label: params.label,
    checked: params.checked,
    disabled: params.disabled,
    visualProgress: if params.checked: 1.0 else: 0.0,
    transitionDurationSeconds: transitionDurationSeconds,
    transitionTiming: transitionTiming,
    thumbTravel: thumbTravel,
    animation: none(AnimationId)
  )
  result.container = root.box(defaultSwitchStyle() + style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arSwitch)
  result.container.setAccessibleName(params.label)
  result.trackNode = root.box(
    defaultTrackStyle() + trackStyle,
    parent = some(result.container),
    groups = ["switch-track"]
  )
  result.activeTrackNode = root.box(
    defaultCheckedTrackStyle() + checkedTrackStyle,
    parent = some(result.trackNode),
    groups = ["switch-track-active"]
  )
  result.thumbNode = root.box(
    defaultThumbStyle() + thumbStyle,
    parent = some(result.trackNode),
    groups = ["switch-thumb"]
  )
  result.thumbNode.applyStateStyle({esChecked}, checkedThumbStyle, priority = 100)
  result.labelNode = root.text(
    result.container,
    params.label,
    defaultLabelStyle() + labelStyle,
    groups = ["switch-label"]
  )
  result.container.applyStateStyle({esDisabled}, uiStyle([
    decl("opacity", number(0.48)),
    decl("cursor", keyword("default"))
  ]), priority = 100)
  result.trackNode.applyStateStyle({esFocusVisible}, uiStyle([
    decl("outline-color", colorValue(rgba(0.35, 0.76, 1.0, 0.92))),
    decl("outline-style", keyword("solid")),
    decl("outline-width", px(2)),
    decl("outline-offset", px(2))
  ]), priority = 100)
  result.container.setState(esChecked, params.checked)
  result.trackNode.setState(esChecked, params.checked)
  result.thumbNode.setState(esChecked, params.checked)
  result.container.setState(esDisabled, params.disabled)
  result.root.tree.setAttribute(
    result.container.id,
    "checked",
    if params.checked: "true" else: "false"
  )
  result.root.tree.setAttribute(
    result.container.id,
    "value",
    if params.checked: "true" else: "false"
  )
  result.root.tree.setAttribute(result.container.id, "label", params.label)
  result.container.setAccessibleValue(if params.checked: "true" else: "false")
  result.applyVisualProgress(if params.checked: 1.0 else: 0.0)

  let control = result
  let ownDisabled = params.disabled
  root.registerFieldsetTarget(proc(disabled: bool) =
    control.setDisabled(ownDisabled or disabled)
  )

  root.events.addInternalEventHandler(
    control.container.id,
    iekFocus,
    proc(event: DispatchResult): bool =
      let focusVisible =
        esFocusVisible in control.root.tree.nodes[control.container.id.nodeIndex].states
      control.trackNode.setState(esFocusVisible, focusVisible)
      false
  )
  root.events.addInternalEventHandler(
    control.container.id,
    iekBlur,
    proc(event: DispatchResult): bool =
      control.trackNode.setState(esFocusVisible, false)
      false
  )
  root.events.addInternalEventHandler(
    control.container.id,
    iekClick,
    proc(event: DispatchResult): bool =
      if control.state.disabled:
        return true
      control.toggle()
      false
  )
  root.events.addInternalEventHandler(
    control.container.id,
    iekKeyDown,
    proc(event: DispatchResult): bool =
      if control.state.disabled:
        return true
      if event.event.key.isSome and event.event.key.get in ["Enter", " "]:
        discard control.container.emit(InputEvent(kind: iekClick))
        return true
      false
  )

proc switch*(
    root: UiRoot;
    label: string;
    checked = false;
    style = UiStyle();
    trackStyle = UiStyle();
    thumbStyle = UiStyle();
    labelStyle = UiStyle();
    checkedTrackStyle = UiStyle();
    checkedThumbStyle = UiStyle();
    transitionDurationSeconds = 0.18;
    transitionTiming = easeTiming();
    thumbTravel = 22.0'f32;
    id = "";
    groups: openArray[string] = ["switch"]
): SwitchHandle {.discardable.} =
  root.switch(
    SwitchParams(label: label, checked: checked),
    style = style,
    trackStyle = trackStyle,
    thumbStyle = thumbStyle,
    labelStyle = labelStyle,
    checkedTrackStyle = checkedTrackStyle,
    checkedThumbStyle = checkedThumbStyle,
    transitionDurationSeconds = transitionDurationSeconds,
    transitionTiming = transitionTiming,
    thumbTravel = thumbTravel,
    id = id,
    groups = groups
  )
