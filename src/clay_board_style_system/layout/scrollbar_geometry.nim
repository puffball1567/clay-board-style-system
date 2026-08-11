import std/[math, options]

import ../core/[computed_style, geometry]
import ./overflow_geometry
import ./scroll_state

type
  ScrollbarAxisGeometry* = object
    track*: Rect
    thumb*: Rect

  ScrollbarGeometry* = object
    horizontal*: Option[ScrollbarAxisGeometry]
    vertical*: Option[ScrollbarAxisGeometry]

proc scrollbarGeometry*(
    nodeRect: Rect;
    style: ComputedStyle;
    padding: EdgeSizes;
    metrics: ScrollMetrics
): ScrollbarGeometry =
  let thickness = style.scrollbarThickness()
  if thickness <= 0:
    return
  if style.visual.scrollbarVisibility == svScrolling and not metrics.scrolling:
    return

  let maximum = metrics.maxOffset()
  let showX = metrics.enabledX and
    (maximum.x > 0 or style.layout.overflowX == omScroll)
  let showY = metrics.enabledY and
    (maximum.y > 0 or style.layout.overflowY == omScroll)
  if not showX and not showY:
    return

  let content = overflowContentRect(nodeRect, style, padding)
  if showY:
    let trackHeight = max(
      0.0'f32, content.h - (if showX: thickness else: 0.0'f32)
    )
    if trackHeight > 0:
      let track = rect(
        content.x + content.w - thickness, content.y, thickness, trackHeight
      )
      let ratio =
        if metrics.content.h > 0:
          min(1.0'f32, metrics.viewport.h / metrics.content.h)
        else:
          1.0'f32
      let thumbHeight = min(
        trackHeight, max(thickness * 2.0'f32, trackHeight * ratio)
      )
      let travel = max(0.0'f32, trackHeight - thumbHeight)
      let progress =
        if maximum.y > 0: metrics.offset.y / maximum.y
        else: 0.0'f32
      result.vertical = some(ScrollbarAxisGeometry(
        track: track,
        thumb: rect(
          track.x, track.y + travel * progress, thickness, thumbHeight
        )
      ))

  if showX:
    let trackWidth = max(
      0.0'f32, content.w - (if showY: thickness else: 0.0'f32)
    )
    if trackWidth > 0:
      let track = rect(
        content.x, content.y + content.h - thickness, trackWidth, thickness
      )
      let ratio =
        if metrics.content.w > 0:
          min(1.0'f32, metrics.viewport.w / metrics.content.w)
        else:
          1.0'f32
      let thumbWidth = min(
        trackWidth, max(thickness * 2.0'f32, trackWidth * ratio)
      )
      let travel = max(0.0'f32, trackWidth - thumbWidth)
      let progress =
        if maximum.x > 0: metrics.offset.x / maximum.x
        else: 0.0'f32
      result.horizontal = some(ScrollbarAxisGeometry(
        track: track,
        thumb: rect(
          track.x + travel * progress, track.y, thumbWidth, thickness
        )
      ))

proc scrollbarGeometry*(
    nodeRect: Rect;
    style: ComputedStyle;
    metrics: ScrollMetrics
): ScrollbarGeometry =
  let padding =
    if style.box.padding.isSome: style.box.padding.get
    else: edges(0)
  scrollbarGeometry(nodeRect, style, padding, metrics)
