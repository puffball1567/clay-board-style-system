import std/[math, options]

import ../core/[computed_style, geometry, node, style_resolver]
import ./layout

type
  ScrollMetrics* = object
    active*: bool
    scrolling*: bool
      ## Set while this container is being scrolled and cleared when the host
      ## reports scroll end. Only `scrollbar-visibility: scrolling` reads it.
    offset*: Vec2
    viewport*: Size
    content*: Size
    enabledX*: bool
    enabledY*: bool
    overscrollX*: OverscrollBehavior
    overscrollY*: OverscrollBehavior

  ScrollState* = object
    ## Retained independently from style and layout. Scrolling mutates only
    ## this state; layout is recomputed only when geometry actually changes.
    entries*: seq[ScrollMetrics]
    revision*: uint64

proc initScrollState*(): ScrollState =
  ScrollState(entries: @[], revision: 0)

proc maxOffset*(metrics: ScrollMetrics): Vec2 =
  vec2(
    max(0.0'f32, metrics.content.w - metrics.viewport.w),
    max(0.0'f32, metrics.content.h - metrics.viewport.h)
  )

proc clampOffset(metrics: ScrollMetrics; offset: Vec2): Vec2 =
  let maximum = metrics.maxOffset()
  vec2(
    if metrics.enabledX: clamp(offset.x, 0.0'f32, maximum.x) else: 0.0'f32,
    if metrics.enabledY: clamp(offset.y, 0.0'f32, maximum.y) else: 0.0'f32
  )

proc syncScrollState*(
    state: var ScrollState;
    tree: Tree;
    styles: ResolvedTree;
    layout: LayoutResult
) =
  let previousLength = state.entries.len
  state.entries.setLen(tree.nodes.len)
  for index in 0 ..< tree.nodes.len:
    state.entries[index].active = false
    state.entries[index].enabledX = false
    state.entries[index].enabledY = false
  for item in layout.overflowMetrics:
    let index = item.node.nodeIndex
    if index < 0 or index >= tree.nodes.len:
      continue
    let style {.cursor.} = styles.styles[index]
    let oldOffset = if index < previousLength: state.entries[index].offset else: vec2(0, 0)
    let wasScrolling = index < previousLength and state.entries[index].scrolling
    var metrics = ScrollMetrics(
      active: true,
      scrolling: wasScrolling,
      offset: oldOffset,
      viewport: item.viewportSize,
      content: size(
        max(item.viewportSize.w, item.contentSize.w),
        max(item.viewportSize.h, item.contentSize.h)
      ),
      enabledX: style.layout.overflowX in {omAuto, omScroll},
      enabledY: style.layout.overflowY in {omAuto, omScroll},
      overscrollX: style.visual.overscrollBehaviorX,
      overscrollY: style.visual.overscrollBehaviorY
    )
    metrics.offset = metrics.clampOffset(metrics.offset)
    state.entries[index] = metrics

proc metricsFor*(state: ScrollState; id: NodeId): Option[ScrollMetrics] =
  if id.nodeIndex < 0 or id.nodeIndex >= state.entries.len:
    return none(ScrollMetrics)
  let metrics = state.entries[id.nodeIndex]
  if not metrics.active:
    return none(ScrollMetrics)
  some(metrics)

proc scrollOffset*(state: ScrollState; id: NodeId): Vec2 =
  let metrics = state.metricsFor(id)
  if metrics.isSome: metrics.get.offset else: vec2(0, 0)

proc setScrollOffset*(state: var ScrollState; id: NodeId; offset: Vec2): bool =
  if id.nodeIndex < 0 or id.nodeIndex >= state.entries.len:
    return false
  var metrics = state.entries[id.nodeIndex]
  if not metrics.active:
    return false
  let next = metrics.clampOffset(offset)
  if next == metrics.offset:
    return false
  metrics.offset = next
  metrics.scrolling = true
  state.entries[id.nodeIndex] = metrics
  inc state.revision
  true

proc scrollBy*(state: var ScrollState; id: NodeId; delta: Vec2): bool =
  let current = state.scrollOffset(id)
  state.setScrollOffset(id, vec2(current.x + delta.x, current.y + delta.y))

proc setScrolling*(state: var ScrollState; id: NodeId; scrolling: bool): bool =
  if id.nodeIndex < 0 or id.nodeIndex >= state.entries.len:
    return false
  var metrics = state.entries[id.nodeIndex]
  if not metrics.active or metrics.scrolling == scrolling:
    return false
  metrics.scrolling = scrolling
  state.entries[id.nodeIndex] = metrics
  inc state.revision
  true

proc scrollNearest*(
    state: var ScrollState;
    tree: Tree;
    target: Option[NodeId];
    delta: Vec2
): Option[NodeId] =
  ## Nested scroll containers chain naturally: an axis at its boundary does
  ## not consume the wheel delta, so the nearest scrollable ancestor can.
  var current = target
  while current.isSome:
    let id = current.get
    if state.scrollBy(id, delta):
      return some(id)
    let metrics = state.metricsFor(id)
    if metrics.isSome:
      let item = metrics.get
      let containsX = delta.x != 0 and item.enabledX and item.overscrollX != obAuto
      let containsY = delta.y != 0 and item.enabledY and item.overscrollY != obAuto
      if containsX or containsY:
        return some(id)
    if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
      break
    current = tree.nodes[id.nodeIndex].parent
  none(NodeId)
