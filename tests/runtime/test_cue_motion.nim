import std/unittest

import clay_board_style_system
import clay_board_style_system/frontend_runtime
import clay_board_style_system/testing/test_driver

proc transitionStyle(opacity: float32): UiStyle =
  uiStyle([
    decl("transition-property", keyword("opacity")),
    decl("transition-duration", number(1)),
    decl("transition-timing-function", keyword("linear")),
    decl("opacity", number(opacity))
  ])

proc animationStyle(name: string; duration = 1.0'f32): UiStyle =
  uiStyle([
    decl("animation-name", keyword(name)),
    decl("animation-duration", number(duration)),
    decl("animation-timing-function", keyword("linear")),
    decl("animation-fill-mode", keyword("forwards"))
  ])

suite "Cue motion adapters":
  test "transition action waits for the matching lifecycle end":
    let ui = initUiRoot()
    let panel = ui.box(transitionStyle(0))
    let driver = initCbssTestDriver(ui, size(200, 100))
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var continued = false
    let graph = cue(cueTransition(
      "fade-in",
      panel,
      dtpOpacity,
      proc() = panel.applyStyle(transitionStyle(1))
    )).then(cueAction("continued", proc() = continued = true))

    let session = runtime.start(graph)
    check session.status == cssRunning
    driver.refresh()
    check session.status == cssRunning
    driver.advanceTime(1)
    check session.status == cssSucceeded
    check continued

  when not defined(release) or defined(cbssFrontendTrace):
    test "transition trace includes motion lifecycle and dirty domains":
      let ui = initUiRoot()
      let panel = ui.box(transitionStyle(0))
      let driver = initCbssTestDriver(ui, size(200, 100))
      let runtime = initCueRuntime()
      let trace = runtime.enableTrace()
      defer:
        check runtime.dispose()
      let session = runtime.start(cue(cueTransition(
        "fade",
        panel,
        dtpOpacity,
        proc() = panel.applyStyle(transitionStyle(1))
      )))

      driver.refresh()
      driver.advanceTime(1)
      let events = trace.snapshot
      var started = false
      var succeeded = false
      var dirtied = false
      for event in events:
        if event.kind == ftkMotionStarted and event.name == "opacity":
          started = true
        elif event.kind == ftkMotionSucceeded and event.name == "opacity":
          succeeded = true
        elif event.kind == ftkDirtyDomains and
            event.domains == {ddPaint, ddAnimation}:
          dirtied = true
      check session.status == cssSucceeded
      check started
      check succeeded
      check dirtied

  test "animation action waits for one named animation only":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("fade", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box()
    let driver = initCbssTestDriver(ui, size(200, 100))
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    let session = runtime.start(cue(cueAnimation(
      "animate",
      panel,
      "fade",
      proc() = panel.applyStyle(animationStyle("fade"))
    )))

    driver.refresh()
    check session.status == cssRunning
    discard panel.emit(motionEvent(iekAnimationEnd, "other", 1))
    check session.status == cssRunning
    driver.advanceTime(1)
    check session.status == cssSucceeded

  test "public motion handlers coexist with Cue observers":
    let ui = initUiRoot()
    let panel = ui.box(transitionStyle(0))
    let driver = initCbssTestDriver(ui, size(200, 100))
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var publicEnds = 0
    panel.onTransitionEnd = proc(event: DispatchResult): EventOutcome =
      if event.motionName == "opacity":
        inc publicEnds
      handledEvent()
    let session = runtime.start(cue(cueTransition(
      "fade",
      panel,
      dtpOpacity,
      proc() = panel.applyStyle(transitionStyle(1))
    )))

    driver.refresh()
    driver.advanceTime(1)
    check session.status == cssSucceeded
    check publicEnds == 1

  test "external cancellation fails the waiting action":
    let ui = initUiRoot()
    let panel = ui.box(transitionStyle(0))
    let driver = initCbssTestDriver(ui, size(200, 100))
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    let session = runtime.start(cue(cueTransition(
      "fade",
      panel,
      dtpOpacity,
      proc() = panel.applyStyle(transitionStyle(1)),
      cancelledMessage = "Fade interrupted"
    )))

    driver.refresh()
    check ui.disposeSubtree(panel, driver.input)
    check session.status == cssFailed
    check session.failure == "Fade interrupted"

  test "Cue cancellation detaches observers and invokes motion cleanup once":
    let ui = initUiRoot()
    let panel = ui.box(transitionStyle(0))
    let driver = initCbssTestDriver(ui, size(200, 100))
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var cleanups = 0
    let session = runtime.start(cue(cueTransition(
      "fade",
      panel,
      dtpOpacity,
      proc() = panel.applyStyle(transitionStyle(1)),
      cancelMotion = proc() {.raises: [].} = inc cleanups
    )))

    driver.refresh()
    check runtime.cancel(session)
    check session.status == cssCancelled
    check cleanups == 1
    driver.advanceTime(1)
    check session.status == cssCancelled
    check cleanups == 1

  test "start failures fail deterministically and remove observers":
    let ui = initUiRoot()
    let panel = ui.box()
    let runtime = initCueRuntime()
    when not defined(release) or defined(cbssFrontendTrace):
      let trace = runtime.enableTrace()
    defer:
      check runtime.dispose()
    let session = runtime.start(cue(cueAnimation(
      "broken",
      panel,
      "fade",
      proc() = raise newException(ValueError, "bad animation")
    )))

    check session.status == cssFailed
    check session.failure == "Motion could not start: bad animation"
    when not defined(release) or defined(cbssFrontendTrace):
      var startFailure = false
      for event in trace.snapshot:
        if event.kind == ftkMotionFailed and event.name == "fade" and
            event.detail == "Motion could not start: bad animation":
          startFailure = true
      check startFailure
    discard panel.emit(motionEvent(iekAnimationEnd, "fade", 1))
    check session.status == cssFailed

  test "reusable actions install fresh subscriptions per session":
    let ui = initUiRoot()
    let panel = ui.box()
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var starts = 0
    let action = cueAnimation(
      "repeat",
      panel,
      "pulse",
      proc() = inc starts
    )
    let graph = cue(action)

    let first = runtime.start(graph, cspParallel)
    let second = runtime.start(graph, cspParallel)
    check starts == 2
    discard panel.emit(motionEvent(iekAnimationEnd, "pulse", 1))
    check first.status == cssSucceeded
    check second.status == cssSucceeded

  test "invalid motion adapter arguments fail before execution":
    let ui = initUiRoot()
    let panel = ui.box()
    expect ValueError:
      discard cueTransition(
        "invalid",
        NodeHandle(),
        dtpOpacity,
        proc() = discard
      )
    expect ValueError:
      discard cueAnimation(
        "invalid",
        panel,
        "  ",
        proc() = discard
      )
    expect ValueError:
      discard cueAnimation(
        "invalid",
        panel,
        "fade",
        MotionStartProc(nil)
      )
    expect ValueError:
      discard cueTransition(
        "invalid",
        panel,
        dtpOpacity,
        proc() = discard,
        cancelledMessage = ""
      )
