import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc resolveUi(ui: UiRoot): tuple[styles: ResolvedTree, layout: LayoutResult] =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
  )
  check not diagnostics.hasErrors
  result.layout = computeLayout(ui.tree, result.styles, size(320, 200))

suite "standard canvas surface":
  test "canvas is a normal styled box backed by a registered surface":
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(320)),
      decl("height", px(200))
    ]))
    let drawing = newCanvas2D()
    let canvas = ui.canvas(
      drawing,
      uiStyle([
        decl("width", px(160)),
        decl("height", px(90)),
        decl("background-color", rgb(0.1, 0.1, 0.1)),
        decl("border-radius", px(8))
      ]),
      parent = some(app),
      code = "chart-surface"
    )

    check canvas.valid
    check canvas.node.valid
    check ui.tree.nodes[canvas.node.id.nodeIndex].kind == nkBox
    check ui.tree.nodes[canvas.node.id.nodeIndex].renderSurfaceId ==
      some(canvas.surface.renderSurfaceIdValue)
    check ui.tree.nodes[canvas.node.id.nodeIndex].code == "chart-surface"
    check ui.surfaces.surfaceState(canvas.surface) == rssUnmounted

  test "retained local commands are translated and clipped in paint order":
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(320)),
      decl("height", px(200)),
      decl("padding", px(12))
    ]))
    let drawing = newCanvas2D()
    drawing.fillRect(rect(4, 5, 50, 20), rgba(1, 0, 0, 0.8), radius = 3)
    drawing.strokeRect(rect(2, 3, 60, 30), rgb(0, 1, 0), width = 2)
    let canvas = ui.canvas(
      drawing,
      uiStyle([
        decl("width", px(160)),
        decl("height", px(90)),
        decl("opacity", number(0.5))
      ]),
      parent = some(app)
    )
    let frame = resolveUi(ui)
    ui.syncRenderSurfaces(frame.styles, frame.layout, pixelScale = 2)
    let commands = buildPaintCommands(
      ui.tree, frame.styles, frame.layout, ui.scroll, ui.canvasPaintProvider()
    )

    check ui.surfaces.surfaceState(canvas.surface) == rssMounted
    var canvasBounds = none(Rect)
    for item in frame.layout.boxes:
      if item.node == canvas.node.id:
        canvasBounds = some(item.rect)
    check canvasBounds.isSome

    var sawFill = false
    var sawStroke = false
    var surfaceClipDepth = 0
    for command in commands:
      case command.kind
      of pcPushClip:
        inc surfaceClipDepth
      of pcPopClip:
        dec surfaceClipDepth
      of pcFillRect:
        if command.owner == some(canvas.node.id) and command.color.r == 1:
          sawFill = true
          check surfaceClipDepth > 0
          check command.rect.x == canvasBounds.get.x + 4
          check command.rect.y == canvasBounds.get.y + 5
          check abs(command.color.a - 0.4) < 0.0001
      of pcStrokeRect:
        if command.owner == some(canvas.node.id):
          sawStroke = true
          check surfaceClipDepth > 0
          check command.strokeRect.x == canvasBounds.get.x + 2
          check command.strokeRect.y == canvasBounds.get.y + 3
          check abs(command.strokeColor.a - 0.5) < 0.0001
      else:
        discard
    check sawFill
    check sawStroke
    check surfaceClipDepth == 0

  test "nested canvas clips are balanced even when authored commands are not":
    let drawing = newCanvas2D()
    drawing.pushClip(rect(0, 0, 20, 20))
    drawing.fillRect(rect(0, 0, 40, 40), rgb(1, 1, 1))
    let commands = drawing.paintCommands(NodeId(1), rect(10, 20, 40, 40))
    check commands.len == 3
    check commands[0].kind == pcPushClip
    check commands[0].clipRect == rect(10, 20, 20, 20)
    check commands[1].kind == pcFillRect
    check commands[2].kind == pcPopClip

  test "canvas transforms use local coordinates and nested save restore scopes":
    let drawing = newCanvas2D()
    drawing.save()
    drawing.translate(10, 5)
    drawing.fillRect(rect(1, 2, 8, 6), rgb(1, 0, 0))
    drawing.save()
    drawing.scale(2, 3)
    drawing.fillRect(rect(4, 5, 2, 2), rgb(0, 1, 0))
    drawing.restore()
    drawing.restore()

    let commands = drawing.paintCommands(NodeId(9), rect(20, 30, 100, 80))
    check commands.len == 6
    check commands[0].kind == pcPushTransform
    check commands[1].kind == pcFillRect
    check commands[2].kind == pcPushTransform
    check commands[3].kind == pcFillRect
    check commands[4].kind == pcPopTransform
    check commands[5].kind == pcPopTransform
    check commands[1].rect == rect(21, 32, 8, 6)
    check commands[3].rect == rect(24, 35, 2, 2)
    check commands[0].transform.transformPoint(vec2(21, 32)) == vec2(31, 37)
    let nested = commands[0].transform * commands[2].transform
    check nested.transformPoint(vec2(24, 35)) == vec2(38, 50)
    check not commands[0].transformBounds.isEmpty
    check not commands[2].transformBounds.isEmpty

  test "UI paint pipeline resolves Canvas transform bounds at the final boundary":
    let ui = initUiRoot()
    let root = ui.box(uiStyle([
      decl("width", px(120)), decl("height", px(80))
    ]))
    let drawing = newCanvas2D()
    drawing.translate(7, 9)
    drawing.fillRect(rect(2, 3, 20, 10), rgb(1, 0, 0))
    let canvas = ui.canvas(
      drawing,
      uiStyle([decl("width", px(100)), decl("height", px(60))]),
      parent = some(root)
    )
    let frame = resolveUi(ui)
    let commands = buildPaintCommands(
      ui.tree, frame.styles, frame.layout, ui.scroll, ui.canvasPaintProvider()
    )

    var sawTransform = false
    var sawCanvasFill = false
    for command in commands:
      case command.kind
      of pcPushTransform:
        if not command.transformBounds.isEmpty:
          sawTransform = true
      of pcFillRect:
        if command.owner == some(canvas.node.id):
          sawCanvasFill = true
      else:
        discard
    check sawTransform
    check sawCanvasFill

  test "save restore closes transformed clips in strict LIFO order":
    let drawing = newCanvas2D()
    drawing.save()
    drawing.translate(3, 4)
    drawing.pushClip(rect(0, 0, 20, 20))
    drawing.fillRect(rect(0, 0, 30, 30), rgb(1, 1, 1))
    drawing.restore()
    drawing.fillRect(rect(1, 1, 2, 2), rgb(1, 0, 0))

    let commands = drawing.paintCommands(NodeId(2), rect(10, 20, 40, 40))
    check commands.len == 6
    check commands[0].kind == pcPushTransform
    check commands[1].kind == pcPushClip
    check commands[2].kind == pcFillRect
    check commands[3].kind == pcPopClip
    check commands[4].kind == pcPopTransform
    check commands[5].kind == pcFillRect

  test "bounded layers compose and restore in strict LIFO order":
    let drawing = newCanvas2D()
    drawing.save()
    drawing.beginLayer(
      rect(2, 3, 30, 20), opacity = 0.6, compositeMode = lcmAdditive
    )
    drawing.fillRect(rect(4, 5, 10, 8), rgb(1, 0, 0))
    drawing.translate(3, 4)
    drawing.fillRect(rect(1, 1, 2, 2), rgb(0, 1, 0))
    drawing.restore()

    let commands = drawing.paintCommands(NodeId(4), rect(10, 20, 80, 60))
    check commands.len == 6
    check commands[0].kind == pcPushLayer
    check commands[0].layerBounds == rect(12, 23, 30, 20)
    check abs(commands[0].layerOpacity - 0.6) < 0.0001
    check commands[0].layerCompositeMode == lcmAdditive
    check commands[1].kind == pcFillRect
    check commands[2].kind == pcPushTransform
    check commands[3].kind == pcFillRect
    check commands[4].kind == pcPopTransform
    check commands[5].kind == pcPopLayer

  test "invalid layers are ignored and dangling layers close safely":
    let drawing = newCanvas2D()
    let initialRevision = drawing.revision
    drawing.beginLayer(rect(0, 0, 0, 20))
    drawing.beginLayer(rect(NaN.float32, 0, 20, 20))
    check drawing.revision == initialRevision

    drawing.endLayer()
    drawing.saveLayer(rect(1, 2, 10, 8), opacity = 3)
    drawing.fillRect(rect(1, 2, 3, 4), rgb(1, 1, 1))
    let commands = drawing.paintCommands(NodeId(5), rect(7, 9, 20, 20))
    check commands.len == 3
    check commands[0].kind == pcPushLayer
    check commands[0].layerOpacity == 1
    check commands[1].kind == pcFillRect
    check commands[2].kind == pcPopLayer

  test "canvas safely balances dangling scopes and rejects invalid transforms":
    let drawing = newCanvas2D()
    let initialRevision = drawing.revision
    drawing.transform(Affine2D(m11: NaN.float32, m22: 1))
    drawing.restore()
    check drawing.revision == initialRevision + 1
    drawing.translate(4, 0)
    drawing.pushClip(rect(0, 0, 10, 10))
    drawing.fillRect(rect(0, 0, 20, 20), rgb(1, 1, 1))

    let commands = drawing.paintCommands(NodeId(3), rect(5, 6, 20, 20))
    check commands.len == 5
    check commands[0].kind == pcPushTransform
    check commands[1].kind == pcPushClip
    check commands[2].kind == pcFillRect
    check commands[3].kind == pcPopClip
    check commands[4].kind == pcPopTransform

  test "retained paths preserve local geometry ownership and opacity":
    let drawing = newCanvas2D()
    let initialRevision = drawing.revision
    drawing.strokeLine(vec2(1, 2), vec2(8, 9), rgba(1, 0, 0, 0.8), width = 3)
    drawing.strokePath(
      [vec2(2, 3), vec2(12, 3), vec2(12, 13)],
      rgb(0, 1, 0),
      width = 2,
      closed = true
    )
    drawing.strokePath([vec2(7, 7)], rgb(0, 0, 1), width = 2)

    check drawing.revision == initialRevision + 3
    let owner = NodeId(17)
    let commands = drawing.paintCommands(owner, rect(20, 30, 100, 80), 0.5)
    check commands.len == 2
    check commands[0].kind == pcStrokePath
    check commands[0].owner == some(owner)
    check commands[0].path.segments.len == 2
    check commands[0].path.segments[0].endpoint == vec2(21, 32)
    check commands[0].path.segments[1].endpoint == vec2(28, 39)
    check commands[0].pathWidth == 3
    check commands[0].pathLineCap == slcButt
    check commands[0].pathLineJoin == sljMiter
    check abs(commands[0].pathColor.a - 0.4) < 0.0001
    check commands[1].kind == pcStrokePath
    check commands[1].path.segments.len == 4
    check commands[1].path.segments[^1].kind == pskClose

  test "non-positive path widths are retained safely but do not paint":
    let drawing = newCanvas2D()
    drawing.strokePath([vec2(0, 0), vec2(10, 10)], rgb(1, 0, 0), width = -4)
    check drawing.commands.len == 1
    check drawing.commands[0].pathWidth == 0
    check drawing.paintCommands(NodeId(1), rect(0, 0, 20, 20)).len == 0

  test "curved paths retain cap join and miter state":
    var path = initPath2D()
    path.moveTo(vec2(0, 10))
    path.quadraticCurveTo(vec2(10, 0), vec2(20, 10))
    path.bezierCurveTo(vec2(25, 15), vec2(30, 5), vec2(40, 10))
    let drawing = newCanvas2D()
    drawing.strokePath(
      path,
      rgb(1, 0, 1),
      width = 4,
      lineCap = slcRound,
      lineJoin = sljBevel,
      miterLimit = 3
    )
    let commands = drawing.paintCommands(NodeId(5), rect(7, 8, 80, 40))

    check commands.len == 1
    check commands[0].path.segments.len == 3
    check commands[0].path.segments[0].endpoint == vec2(7, 18)
    check commands[0].path.segments[1].control1 == vec2(17, 8)
    check commands[0].path.segments[2].control2 == vec2(37, 13)
    check commands[0].pathLineCap == slcRound
    check commands[0].pathLineJoin == sljBevel
    check commands[0].pathMiterLimit == 3

  test "surface events preserve local coordinates and consumption":
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(320)),
      decl("height", px(200)),
      decl("padding", px(10))
    ]))
    let drawing = newCanvas2D()
    var received: seq[RenderSurfaceInput]
    drawing.onInput = proc(canvas: Canvas2D; event: RenderSurfaceInput): bool =
      received.add event
      true
    let canvas = ui.canvas(
      drawing,
      uiStyle([decl("width", px(100)), decl("height", px(60))]),
      parent = some(app)
    )
    let frame = resolveUi(ui)
    ui.syncRenderSurfaces(frame.styles, frame.layout)
    let presentation = presentationForNode(
      ui.tree, frame.layout, frame.styles, canvas.node.id, ui.scroll
    ).get
    let point = vec2(presentation.bounds.x + 17, presentation.bounds.y + 11)

    let pen = PointerData(
      device: pdkPenDirect,
      deviceId: 33,
      axes: {paPressure, paTiltY},
      pressure: 0.5,
      tiltY: 24,
      contact: true,
      inProximity: true
    )
    check ui.events.emit(
      ui.tree, canvas.node.id, pointerDownEvent(point, pointer = some(pen))
    )
    check received.len == 1
    check received[0].localPosition == some(vec2(17, 11))
    check received[0].inside
    check received[0].event.pointer == some(pen)

    check ui.events.emit(
      ui.tree, canvas.node.id, penProximityEvent(true, pen)
    )
    check received.len == 2
    check received[1].localPosition.isNone
    check received[1].event.kind == iekPenProximityIn
    check received[1].event.pointer == some(pen)

  test "transformed canvas input resolves back to content-local coordinates":
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(320)), decl("height", px(220))
    ]))
    let drawing = newCanvas2D()
    var received: seq[RenderSurfaceInput]
    drawing.onInput = proc(canvas: Canvas2D; event: RenderSurfaceInput): bool =
      received.add event
      true
    let canvas = ui.canvas(
      drawing,
      uiStyle([
        decl("width", px(100)),
        decl("height", px(60)),
        decl("padding", px(5)),
        decl("transform", transformValue(
          translate(px(80), px(50)), rotate(30)
        ))
      ]),
      parent = some(app)
    )
    let frame = resolveUi(ui)
    ui.syncRenderSurfaces(frame.styles, frame.layout)
    let presentation = presentationForNode(
      ui.tree, frame.layout, frame.styles, canvas.node.id, ui.scroll
    ).get
    let sourceContent = presentation.sourceContentBounds(
      frame.styles.styles[canvas.node.id.nodeIndex]
    )
    let hostPoint = presentation.transform.transformPoint(
      vec2(sourceContent.x + 12, sourceContent.y + 9)
    )

    check ui.events.emit(
      ui.tree, canvas.node.id, pointerDownEvent(hostPoint)
    )
    check received.len == 1
    check abs(received[0].localPosition.get.x - 12) < 0.001
    check abs(received[0].localPosition.get.y - 9) < 0.001

  test "canvas content excludes its own padding and border":
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(320)), decl("height", px(200))
    ]))
    let drawing = newCanvas2D()
    drawing.fillRect(rect(0, 0, 20, 10), rgb(1, 0, 0))
    var received: seq[RenderSurfaceInput]
    drawing.onInput = proc(canvas: Canvas2D; event: RenderSurfaceInput): bool =
      received.add event
      true
    let canvas = ui.canvas(
      drawing,
      uiStyle([
        decl("width", px(100)),
        decl("height", px(60)),
        decl("box-sizing", keyword("border-box")),
        decl("padding", px(7)),
        decl("border-width", px(2)),
        decl("border-color", rgb(1, 1, 1))
      ]),
      parent = some(app)
    )
    let frame = resolveUi(ui)
    ui.syncRenderSurfaces(frame.styles, frame.layout)
    let presentation = presentationForNode(
      ui.tree, frame.layout, frame.styles, canvas.node.id, ui.scroll
    ).get
    let content = presentation.contentBounds(
      frame.styles.styles[canvas.node.id.nodeIndex]
    )
    check content == rect(
      presentation.bounds.x + 9, presentation.bounds.y + 9, 82, 42
    )

    let commands = buildPaintCommands(
      ui.tree, frame.styles, frame.layout, ui.scroll, ui.canvasPaintProvider()
    )
    var surfaceFill = none(Rect)
    for command in commands:
      if command.kind == pcFillRect and command.owner == some(canvas.node.id) and
          command.color.r == 1 and command.color.g == 0:
        surfaceFill = some(command.rect)
    check surfaceFill == some(rect(content.x, content.y, 20, 10))

    check not ui.events.emit(
      ui.tree, canvas.node.id,
      pointerDownEvent(vec2(presentation.bounds.x + 3, presentation.bounds.y + 3))
    )
    check received.len == 0
    check ui.events.emit(
      ui.tree, canvas.node.id,
      pointerDownEvent(vec2(content.x + 4, content.y + 5))
    )
    check received.len == 1
    check received[0].localPosition == some(vec2(4, 5))

  test "frame callbacks update retained commands without rebuilding the UI tree":
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(320)),
      decl("height", px(200))
    ]))
    let drawing = newCanvas2D()
    drawing.onFrame = proc(
        canvas: Canvas2D;
        frame: RenderSurfaceFrame
    ): RenderSurfaceFrameResult =
      canvas.clear()
      canvas.fillRect(rect(0, 0, frame.frameNumber.float32 * 10, 10), rgb(0, 1, 1))
      if frame.frameNumber < 2: rsfRequestNext else: rsfIdle
    let canvas = ui.canvas(
      drawing,
      uiStyle([decl("width", px(100)), decl("height", px(60))]),
      parent = some(app)
    )
    let nodeCount = ui.tree.activeNodeCount
    let frame = resolveUi(ui)
    ui.syncRenderSurfaces(frame.styles, frame.layout)

    check ui.surfaces.needsSurfaceFrame
    check ui.runRenderSurfaceFrames(1.0) == 1
    check ui.surfaces.needsSurfaceFrame
    check ui.runRenderSurfaceFrames(1.016) == 1
    check not ui.surfaces.needsSurfaceFrame
    check ui.tree.activeNodeCount == nodeCount
    check drawing.commands.len == 1
    if drawing.commands.len == 1:
      check drawing.commands[0].fillRect.w == 20
    check ui.surfaces.surfaceState(canvas.surface) == rssMounted

  test "disposing a canvas unmounts and unregisters its surface":
    let ui = initUiRoot()
    let app = ui.box()
    let drawing = newCanvas2D()
    let canvas = ui.canvas(drawing, parent = some(app))
    let frame = resolveUi(ui)
    ui.syncRenderSurfaces(frame.styles, frame.layout)
    var interaction = initInteractionState()

    check ui.disposeSubtree(canvas.node, interaction)
    check not canvas.valid
    check not ui.surfaces.hasSurface(canvas.surface)

  test "surface scheduler requests frames only while canvas remains active":
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(100)), decl("height", px(100))
    ]))
    let drawing = newCanvas2D()
    drawing.onFrame = proc(
        canvas: Canvas2D;
        frame: RenderSurfaceFrame
    ): RenderSurfaceFrameResult =
      if frame.frameNumber < 2: rsfRequestNext else: rsfIdle
    discard ui.canvas(
      drawing,
      uiStyle([decl("width", px(50)), decl("height", px(50))]),
      parent = some(app)
    )
    let frame = resolveUi(ui)
    ui.syncRenderSurfaces(frame.styles, frame.layout)
    var scheduler = initFrameScheduler()

    ui.scheduleRenderSurfaceFrames(scheduler, 1.0)
    check scheduler.waitTimeoutMs(1.0) == 0
    discard scheduler.consumeDirty()
    scheduler.clearDeadline()
    check ui.runRenderSurfaceFrames(scheduler, 1.0) == 1
    check scheduler.consumeDirty() == {ddPaint}
    check scheduler.nextDeadline.isSome
    scheduler.clearDeadline()
    check ui.runRenderSurfaceFrames(scheduler, 1.016) == 1
    check scheduler.consumeDirty() == {ddPaint}
    check scheduler.nextDeadline.isNone

  test "surface scheduler rejects invalid frame rates":
    let ui = initUiRoot()
    var scheduler = initFrameScheduler()
    expect ValueError:
      discard ui.runRenderSurfaceFrames(scheduler, 1.0, 0)
    expect ValueError:
      discard ui.runRenderSurfaceFrames(scheduler, 1.0, Inf)
    expect ValueError:
      discard ui.runRenderSurfaceFrames(scheduler, 1.0, NaN)
