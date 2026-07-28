import std/[options, unittest]

import clay_board_style_system

suite "runtime frame scheduler":
  test "idle scheduler waits indefinitely without dirty work or deadlines":
    let scheduler = initFrameScheduler()

    check scheduler.waitTimeoutMs(10.0) == -1
    check not scheduler.deadlineDue(10.0)

  test "dirty work prevents the event loop from blocking":
    var scheduler = initFrameScheduler()
    scheduler.markDirty({ddPaint, ddText})

    check scheduler.waitTimeoutMs(10.0) == 0
    check scheduler.consumeDirty() == {ddPaint, ddText}
    check scheduler.waitTimeoutMs(10.0) == -1

  test "earliest deadline wins and timeout rounds up":
    var scheduler = initFrameScheduler()
    scheduler.requestDeadline(10.2504)
    scheduler.requestDeadline(10.5)
    scheduler.requestDeadline(10.1251)

    check scheduler.nextDeadline == some(10.1251)
    check scheduler.waitTimeoutMs(10.0) == 126
    check not scheduler.deadlineDue(10.1250)
    check scheduler.deadlineDue(10.1251)

  test "deadline can be cleared when timed work becomes inactive":
    var scheduler = initFrameScheduler()
    scheduler.requestDeadline(20.0)
    scheduler.clearDeadline()

    check scheduler.nextDeadline.isNone
    check scheduler.waitTimeoutMs(10.0) == -1
