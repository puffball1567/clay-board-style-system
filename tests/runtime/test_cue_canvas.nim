import std/unittest

import clay_board_style_system
import clay_board_style_system/frontend_runtime
import clay_board_style_system/generated/default_properties
import clay_board_style_system/testing/test_driver

proc canvasStyle(): UiStyle =
  uiStyle([
    decl("width", px(120)),
    decl("height", px(80))
  ])

proc resolveUi(ui: UiRoot): tuple[styles: ResolvedTree, layout: LayoutResult] =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
  )
  check not diagnostics.hasErrors
  result.layout = computeLayout(ui.tree, result.styles, size(200, 120))

proc mountCanvas(ui: UiRoot; canvas: CanvasHandle) =
  discard canvas
  let resolved = resolveUi(ui)
  ui.syncRenderSurfaces(resolved.styles, resolved.layout)

suite "Cue Canvas adapter":
  test "Canvas frames advance Cue only after the frame callback completes":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var frames = 0
    var continued = false
    let graph = cue(cueCanvas(
      "draw-intro",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        inc frames
        value.clear()
        value.fillRect(
          rect(0, 0, frame.frameNumber.float32 * 10, 10),
          rgb(0.2, 0.8, 1)
        )
        if frames < 2: ccfdContinue else: ccfdComplete
    )).then(cueAction("continued", proc() = continued = true))

    let session = runtime.start(graph)
    check session.status == cssRunning
    ui.mountCanvas(canvas)
    check ui.surfaces.needsSurfaceFrame
    check ui.runRenderSurfaceFrames(1) == 1
    check session.status == cssRunning
    check ui.runRenderSurfaceFrames(1.016) == 1
    check session.status == cssSucceeded
    check frames == 2
    check continued
    check drawing.commands.len == 1

  test "public Canvas frame callbacks coexist with Cue observers":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    var publicFrames = 0
    drawing.onFrame = proc(
        value: Canvas2D;
        frame: RenderSurfaceFrame
    ): RenderSurfaceFrameResult =
      discard value
      discard frame
      inc publicFrames
      rsfIdle
    let canvas = ui.canvas(drawing, canvasStyle())
    ui.mountCanvas(canvas)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    let session = runtime.start(cue(cueCanvas(
      "overlay",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        ccfdComplete
    )))

    check ui.runRenderSurfaceFrames(1) == 1
    check session.status == cssSucceeded
    check publicFrames == 1

  test "parallel Canvas actions share one frame without replacing each other":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    ui.mountCanvas(canvas)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var firstFrames = 0
    var secondFrames = 0
    let first = cueCanvas(
      "first-layer",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        inc firstFrames
        ccfdComplete
    )
    let second = cueCanvas(
      "second-layer",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        inc secondFrames
        ccfdComplete
    )
    let graph = cue(cueAction("begin", proc() = discard))
      .thenParallel(first, second)
    let session = runtime.start(graph)

    check session.status == cssRunning
    check ui.runRenderSurfaceFrames(1) == 1
    check session.status == cssSucceeded
    check firstFrames == 1
    check secondFrames == 1

  test "large parallel Canvas fan-out settles in one indexed dispatch":
    const branchCount = 1024
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    ui.mountCanvas(canvas)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var calls = 0
    let action = cueCanvas(
      "shared-frame",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        inc calls
        ccfdComplete
    )
    var branches = newSeqOfCap[CueBranch](branchCount)
    for _ in 0 ..< branchCount:
      branches.add branch(action)
    let graph = cue(cueAction("begin", proc() = discard))
    discard graph.thenStage(branches)
    let session = runtime.start(graph)

    check session.status == cssRunning
    check ui.runRenderSurfaceFrames(1) == 1
    check session.status == cssSucceeded
    check calls == branchCount
    check not drawing.hasFrameObservers(canvas.surface)

  test "Cue cancellation detaches Canvas observers and invokes cleanup once":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    ui.mountCanvas(canvas)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var frames = 0
    var cleanups = 0
    let session = runtime.start(cue(cueCanvas(
      "continuous",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        inc frames
        ccfdContinue,
      cancelCanvas = proc() {.raises: [].} = inc cleanups
    )))

    check ui.runRenderSurfaceFrames(1) == 1
    check frames == 1
    check runtime.cancel(session)
    check session.status == cssCancelled
    check cleanups == 1
    check ui.runRenderSurfaceFrames(1.016) == 1
    check frames == 1
    check cleanups == 1

  test "disposing a Canvas fails its waiting Cue action":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    let driver = initCbssTestDriver(ui, size(200, 120))
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    let session = runtime.start(cue(cueCanvas(
      "until-dispose",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        ccfdContinue,
      disposedMessage = "Drawing surface was removed"
    )))

    check ui.disposeSubtree(canvas.node, driver.input)
    check session.status == cssFailed
    check session.failure == "Drawing surface was removed"

  test "shared Canvas display lists keep Cue lifecycle scoped by surface":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let firstCanvas = ui.canvas(drawing, canvasStyle())
    let secondCanvas = ui.canvas(drawing, canvasStyle())
    let driver = initCbssTestDriver(ui, size(240, 120))
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var frames = 0
    let session = runtime.start(cue(cueCanvas(
      "first-surface-only",
      firstCanvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        inc frames
        ccfdComplete
    )))

    ui.mountCanvas(firstCanvas)
    check ui.disposeSubtree(secondCanvas.node, driver.input)
    check session.status == cssRunning
    check ui.runRenderSurfaceFrames(1) == 1
    check session.status == cssSucceeded
    check frames == 1

  test "direct surface unmount fails its waiting Canvas action":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    ui.mountCanvas(canvas)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    let session = runtime.start(cue(cueCanvas(
      "mounted-surface",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        ccfdContinue
    )))

    check ui.surfaces.unmountSurface(canvas.surface)
    check session.status == cssFailed
    check session.failure == "Canvas was disposed"

  test "Canvas frame exceptions fail without leaving an active observer":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    ui.mountCanvas(canvas)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var calls = 0
    let session = runtime.start(cue(cueCanvas(
      "broken-frame",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        inc calls
        raise newException(ValueError, "bad frame")
    )))

    check ui.runRenderSurfaceFrames(1) == 1
    check session.status == cssFailed
    check session.failure == "Canvas frame failed: bad frame"
    discard canvas.requestFrame()
    check ui.runRenderSurfaceFrames(1.016) == 1
    check calls == 1

  test "reusable Canvas actions install fresh observers per session":
    let ui = initUiRoot()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, canvasStyle())
    ui.mountCanvas(canvas)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    var calls = 0
    let action = cueCanvas(
      "reusable",
      canvas,
      proc(
          value: Canvas2D;
          frame: RenderSurfaceFrame
      ): CueCanvasFrameDecision =
        discard value
        discard frame
        inc calls
        ccfdComplete
    )
    let graph = cue(action)

    let first = runtime.start(graph, cspParallel)
    check ui.runRenderSurfaceFrames(1) == 1
    check first.status == cssSucceeded
    let second = runtime.start(graph, cspParallel)
    check ui.runRenderSurfaceFrames(1.016) == 1
    check second.status == cssSucceeded
    check calls == 2

  test "invalid Canvas adapter arguments fail before execution":
    let ui = initUiRoot()
    let canvas = ui.canvas(newCanvas2D(), canvasStyle())
    expect ValueError:
      discard cueCanvas(
        "invalid",
        CanvasHandle(),
        proc(
            value: Canvas2D;
            frame: RenderSurfaceFrame
        ): CueCanvasFrameDecision =
          discard value
          discard frame
          ccfdComplete
      )
    expect ValueError:
      discard cueCanvas(
        "invalid",
        canvas,
        CueCanvasFrameProc(nil)
      )
    expect ValueError:
      discard cueCanvas(
        "invalid",
        canvas,
        proc(
            value: Canvas2D;
            frame: RenderSurfaceFrame
        ): CueCanvasFrameDecision =
          discard value
          discard frame
          ccfdComplete,
        disposedMessage = ""
      )
