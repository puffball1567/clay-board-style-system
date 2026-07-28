import std/options
import ../core/[geometry, node]
import ../hit/hit_test

proc updateHover*(tree: var Tree; regions: openArray[HitRegion]; point: Vec2): Option[NodeId] =
  tree.clearState(esHover)
  let hit = hitTest(regions, point)
  if hit.isSome:
    tree.addState(hit.get.node, esHover)
    return some(hit.get.node)
  none(NodeId)
