import std/[math, options]

import ../core/[declaration, node, style_value]
import ./ui_root

type
  ProgressParams* = object
    value*: float32
    max*: float32
    indeterminate*: bool
    trackWidth*: float32

  ProgressState* = ref object
    value*: float32
    max*: float32
    indeterminate*: bool
    trackWidth*: float32

  ProgressHandle* = object
    root*: UiRoot
    container*: NodeHandle
    trackNode*: NodeHandle
    fillNode*: NodeHandle
    valueNode*: NodeHandle
    state*: ProgressState

proc normalizedMax(value: float32): float32 =
  if value <= 0: 1
  else: value

proc clampedValue(state: ProgressState; value: float32): float32 =
  max(0'f32, min(state.max, value))

proc percent*(progress: ProgressHandle): float32 =
  if progress.state.indeterminate:
    return -1
  if progress.state.max <= 0:
    return 0
  progress.state.value / progress.state.max

proc value*(progress: ProgressHandle): float32 =
  progress.state.value

proc maxValue*(progress: ProgressHandle): float32 =
  progress.state.max

proc indeterminate*(progress: ProgressHandle): bool =
  progress.state.indeterminate

proc syncVisibleState(progress: ProgressHandle) =
  let label =
    if progress.state.indeterminate:
      "indeterminate"
    else:
      $int(round(progress.percent() * 100)) & "%"
  progress.root.tree.nodes[progress.valueNode.id.nodeIndex].text = label
  let fillWidth =
    if progress.state.indeterminate:
      progress.state.trackWidth
    else:
      max(0'f32, progress.state.trackWidth * progress.percent())
  progress.fillNode.applyStyle(uiStyle([
    decl("width", px(fillWidth))
  ]))
  progress.container.setState(esActive, progress.state.indeterminate)
  progress.container.setAccessibleValue(label)
  progress.container.setAccessibleRange(
    if progress.state.indeterminate: none(float32) else: some(progress.state.value),
    some(0.0'f32),
    some(progress.state.max)
  )

proc setValue*(progress: ProgressHandle; value: float32) =
  if progress.state.indeterminate:
    progress.state.indeterminate = false
  progress.state.value = progress.state.clampedValue(value)
  progress.syncVisibleState()

proc setMax*(progress: ProgressHandle; maxValue: float32) =
  progress.state.max = normalizedMax(maxValue)
  progress.state.value = progress.state.clampedValue(progress.state.value)
  progress.syncVisibleState()

proc setIndeterminate*(progress: ProgressHandle; indeterminate: bool) =
  progress.state.indeterminate = indeterminate
  progress.syncVisibleState()

proc progress*(
    root: UiRoot;
    params: ProgressParams;
    style = UiStyle();
    trackStyle = UiStyle();
    fillStyle = UiStyle();
    valueStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["progress"]
): ProgressHandle {.discardable.} =
  result.root = root
  result.state = ProgressState(
    max: normalizedMax(params.max),
    indeterminate: params.indeterminate,
    trackWidth: max(0'f32, params.trackWidth)
  )
  result.state.value = result.state.clampedValue(params.value)
  result.container = root.box(style, id = id, groups = groups)
  result.container.setAccessibleRole(arProgressBar)
  result.trackNode = root.box(trackStyle, parent = some(result.container), groups = ["progress-track"])
  result.fillNode = root.box(fillStyle, parent = some(result.trackNode), groups = ["progress-fill"])
  result.valueNode = root.text(result.container, "", valueStyle, groups = ["progress-value"])
  result.syncVisibleState()

proc progress*(
    root: UiRoot;
    value = 0'f32;
    max = 1'f32;
    indeterminate = false;
    trackWidth = 100'f32;
    style = UiStyle();
    trackStyle = UiStyle();
    fillStyle = UiStyle();
    valueStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["progress"]
): ProgressHandle {.discardable.} =
  root.progress(
    ProgressParams(value: value, max: max, indeterminate: indeterminate, trackWidth: trackWidth),
    style = style,
    trackStyle = trackStyle,
    fillStyle = fillStyle,
    valueStyle = valueStyle,
    id = id,
    groups = groups
  )
