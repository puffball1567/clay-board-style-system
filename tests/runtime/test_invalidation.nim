import std/[options, unittest]

import clay_board_style_system

suite "runtime invalidation":
  test "UiRoot invalidation coalesces nested roots and consumes atomically":
    let ui = initUiRoot()
    let outer = ui.box()
    let parent = ui.box(parent = some(outer))
    let child = ui.box(parent = some(parent))

    ui.invalidate(child.id, {ddPaint})
    ui.invalidate(parent.id, {ddStyle, ddLayout})
    ui.invalidate(child.id, {ddHit})

    check ui.hasPendingInvalidation
    let pending = ui.consumeInvalidation()
    check pending.domains == {ddStyle, ddLayout, ddPaint, ddHit}
    check pending.roots == @[parent.id]
    check not ui.hasPendingInvalidation
    check ui.consumeInvalidation().roots.len == 0

  test "dirty domains accumulate and consume as a set":
    var invalidation = initInvalidationState()

    check not invalidation.dirty()
    check not invalidation.needsFrame()

    invalidation.markDirty(ddText)
    invalidation.markDirty({ddPaint, ddHit})
    invalidation.markDirty(ddText)

    check invalidation.dirty()
    check invalidation.needsFrame()
    check invalidation.domains == {ddText, ddPaint, ddHit}
    check invalidation.consumeDirty(ddPaint)
    check not invalidation.consumeDirty(ddPaint)
    check invalidation.domains == {ddText, ddHit}

    let consumed = invalidation.consumeDirty()
    check consumed == {ddText, ddHit}
    check not invalidation.dirty()

  test "dirty domains classify full frame data and paint-only refreshes":
    var invalidation = initInvalidationState({ddText})
    check invalidation.needsPaintOnly()
    check not invalidation.needsFullFrameData()

    invalidation.markDirty(ddAnimation)
    check invalidation.needsPaintOnly()

    invalidation.markDirty(ddLayout)
    check invalidation.needsFullFrameData()
    check not invalidation.needsPaintOnly()

    discard invalidation.consumeDirty(ddLayout)
    check invalidation.needsPaintOnly()

    invalidation.clearDirty()
    check not invalidation.needsFrame()
