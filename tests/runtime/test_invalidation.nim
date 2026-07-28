import std/unittest

import clay_board_style_system

suite "runtime invalidation":
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
