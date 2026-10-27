import ../core/[dirty_domain, node]
import ./drop_indicator
import ./ui_root

proc moveChildForDrop*(
    root: UiRoot;
    parent, source, target: NodeId;
    side: DropInsertionSide
): bool {.discardable.} =
  ## Move a direct child before or after a sibling without replacing nodes.
  ## Applications call this after deciding what an accepted move drop means.
  if root.isNil:
    return false
  result = root.tree.moveChildRelative(parent, source, target, side == disAfter)
  if result:
    root.invalidate(parent, {ddLayout, ddPaint, ddHit})

proc moveChildByStep*(
    root: UiRoot;
    parent, source: NodeId;
    direction: int
): bool {.discardable.} =
  ## Move a direct child one sibling backward (-1) or forward (+1).
  ## A keyboard handler can map its own shortcuts to these two directions.
  if root.isNil:
    return false
  result = root.tree.moveChildByStep(parent, source, direction)
  if result:
    root.invalidate(parent, {ddLayout, ddPaint, ddHit})
