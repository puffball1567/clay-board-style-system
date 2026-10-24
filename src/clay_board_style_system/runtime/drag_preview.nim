import std/[math, options]

import ../core/[geometry, node]
import ../input/events
import ../paint/paint_command

type
  DragPreview* = object
    source: NodeId
    paintBounds: Rect
    grabPoint: Vec2
    opacity: float32

proc finite(value: float32): bool {.inline.} =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc initDragPreview*(
    source: NodeId;
    paintBounds: Rect;
    grabPoint: Vec2;
    opacity = 0.72'f32
): DragPreview =
  ## Capture geometry once at drag start. Source commands remain caller-owned.
  if not paintBounds.x.finite or not paintBounds.y.finite or
      not paintBounds.w.finite or not paintBounds.h.finite or
      paintBounds.w <= 0 or paintBounds.h <= 0 or
      not grabPoint.x.finite or not grabPoint.y.finite or
      not opacity.finite or opacity < 0 or opacity > 1:
    raise newException(ValueError, "invalid drag preview geometry or opacity")
  DragPreview(
    source: source,
    paintBounds: paintBounds,
    grabPoint: grabPoint,
    opacity: opacity
  )

proc dragPreviewBounds*(
    preview: DragPreview;
    state: InteractionState;
    pointer: Vec2
): Option[Rect] =
  ## No preview is returned after release, cancellation, or source disposal.
  if state.keyboardDragging or state.dragTarget != some(preview.source) or
      not pointer.x.finite or not pointer.y.finite:
    return none(Rect)
  let offset = vec2(
    pointer.x - preview.grabPoint.x,
    pointer.y - preview.grabPoint.y
  )
  if not offset.x.finite or not offset.y.finite:
    return none(Rect)
  let bounds = preview.paintBounds.translated(offset)
  if not bounds.x.finite or not bounds.y.finite:
    return none(Rect)
  some(bounds)

proc dragPreviewCommands*(
    preview: DragPreview;
    state: InteractionState;
    pointer: Vec2;
    sourceCommands: openArray[PaintCommand]
): seq[PaintCommand] =
  ## Append this stream after normal UI paint commands. It adds no layout box
  ## or hit region, and the source command stream is never modified.
  if sourceCommands.len == 0 or
      preview.dragPreviewBounds(state, pointer).isNone:
    return
  let offset = vec2(
    pointer.x - preview.grabPoint.x,
    pointer.y - preview.grabPoint.y
  )
  result = newSeqOfCap[PaintCommand](sourceCommands.len + 4)
  result.add pushTransform(translationAffine2D(offset.x, offset.y))
  result.add pushLayer(preview.paintBounds, opacity = preview.opacity)
  for command in sourceCommands:
    result.add command
  result.add popLayer()
  result.add popTransform()
  result.resolveTransformBounds()
