import std/[math, options]

import ../core/[color, geometry, node]
import ../input/events
import ../paint/paint_command

type
  DropInsertionAxis* = enum
    diaVertical,
    diaHorizontal

  DropInsertionSide* = enum
    disBefore,
    disAfter

  DropInsertionIndicator* = object
    target: NodeId
    bounds: Rect
    axis: DropInsertionAxis
    reversed: bool
    color: Color
    thickness: float32
    inset: float32

proc finite(value: float32): bool {.inline.} =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc initDropInsertionIndicator*(
    target: NodeId;
    bounds: Rect;
    color: Color;
    axis = diaVertical;
    reversed = false;
    thickness = 2.0'f32;
    inset = 0.0'f32
): DropInsertionIndicator =
  ## Bounds and axis come from the current target layout. The indicator adds
  ## no layout box or hit region and can be recreated after layout changes.
  let span = if axis == diaVertical: bounds.w else: bounds.h
  if not bounds.x.finite or not bounds.y.finite or
      not bounds.w.finite or not bounds.h.finite or
      bounds.w <= 0 or bounds.h <= 0 or
      not thickness.finite or thickness <= 0 or
      not inset.finite or inset < 0 or inset * 2 >= span:
    raise newException(ValueError, "invalid drop indicator geometry")
  DropInsertionIndicator(
    target: target,
    bounds: bounds,
    axis: axis,
    reversed: reversed,
    color: color,
    thickness: thickness,
    inset: inset
  )

proc dropInsertionSide*(
    indicator: DropInsertionIndicator;
    pointer: Vec2
): Option[DropInsertionSide] =
  ## Pure geometry: also usable in an onDrop handler after InteractionState
  ## has released its acceptance for the completed drag.
  if not pointer.x.finite or not pointer.y.finite:
    return none(DropInsertionSide)
  let physicalBefore =
    if indicator.axis == diaVertical:
      pointer.y < indicator.bounds.y + indicator.bounds.h * 0.5'f32
    else:
      pointer.x < indicator.bounds.x + indicator.bounds.w * 0.5'f32
  let before = if indicator.reversed: not physicalBefore else: physicalBefore
  some(if before: disBefore else: disAfter)

proc dropInsertionCommands*(
    indicator: DropInsertionIndicator;
    state: InteractionState;
    side: DropInsertionSide
): seq[PaintCommand] =
  ## Append after normal UI commands only while this target is accepted.
  if state.dragTarget.isNone or
      state.dragOverTarget != some(indicator.target) or
      state.dropOperation.isNone:
    return
  let half = indicator.thickness * 0.5'f32
  let physicalBefore = (side == disBefore) != indicator.reversed
  let marker =
    if indicator.axis == diaVertical:
      rect(
        indicator.bounds.x + indicator.inset,
        (if physicalBefore: indicator.bounds.y
         else: indicator.bounds.y + indicator.bounds.h) - half,
        indicator.bounds.w - indicator.inset * 2,
        indicator.thickness
      )
    else:
      rect(
        (if physicalBefore: indicator.bounds.x
         else: indicator.bounds.x + indicator.bounds.w) - half,
        indicator.bounds.y + indicator.inset,
        indicator.thickness,
        indicator.bounds.h - indicator.inset * 2
      )
  @[fillRect(marker, indicator.color, owner = some(indicator.target))]
