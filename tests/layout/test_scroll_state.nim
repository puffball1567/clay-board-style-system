import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc scrollFixture(): tuple[
    tree: Tree,
    root: NodeId,
    first: NodeId,
    second: NodeId,
    styles: ResolvedTree,
    layout: LayoutResult,
    diagnostics: Diagnostics
] =
  var tree = initTree()
  let root = tree.addBox(id = "viewport")
  let first = tree.addBox(parent = some(root), id = "first")
  let second = tree.addBox(parent = some(root), id = "second")
  let sheet = styleSheet([
    rule(id("viewport"), [
      decl("width", px(100)),
      decl("height", px(40)),
      decl("flex-direction", keyword("column")),
      decl("overflow-x", keyword("hidden")),
      decl("overflow-y", keyword("auto")),
      decl("scrollbar-width", keyword("thin")),
      decl("scrollbar-color", colorPairValue(
        rgb(0.20, 0.70, 0.60), rgb(0.04, 0.08, 0.07)
      )),
      decl("background-color", colorValue(rgb(0, 0, 0)))
    ]),
    rule(id("first"), [
      decl("width", px(100)),
      decl("height", px(30)),
      decl("min-height", px(30)),
      decl("background-color", colorValue(rgb(1, 0, 0)))
    ]),
    rule(id("second"), [
      decl("width", px(100)),
      decl("height", px(30)),
      decl("min-height", px(30)),
      decl("background-color", colorValue(rgb(0, 1, 0)))
    ])
  ])
  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
  let layout = computeLayout(tree, styles, size(100, 40))
  (tree, root, first, second, styles, layout, diagnostics)

suite "retained scroll state":
  test "automatic flex minimum keeps text overflow scrollable":
    var tree = initTree()
    let root = tree.addBox(id = "viewport")
    discard tree.addText(root, "first", id = "first")
    discard tree.addText(root, "second", id = "second")
    let sheet = styleSheet([
      rule(id("viewport"), [
        decl("width", px(100)),
        decl("height", px(40)),
        decl("flex-direction", keyword("column")),
        decl("overflow-y", keyword("auto"))
      ]),
      rule(id("first"), [
        decl("height", px(30)),
        decl("font-size", px(20)),
        decl("line-height", px(30))
      ]),
      rule(id("second"), [
        decl("height", px(30)),
        decl("font-size", px(20)),
        decl("line-height", px(30))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(100, 40))
    var scroll = initScrollState()
    scroll.syncScrollState(tree, styles, layout)

    check not diagnostics.hasErrors
    check scroll.metricsFor(root).get.content.h == 60
    check scroll.metricsFor(root).get.maxOffset().y == 20

  test "overflow resolves independently for each axis":
    let fixture = scrollFixture()

    check not fixture.diagnostics.hasErrors
    check fixture.styles.styles[fixture.root.nodeIndex].layout.overflowX == omHidden
    check fixture.styles.styles[fixture.root.nodeIndex].layout.overflowY == omAuto

  test "sync retains and clamps offset without changing layout":
    let fixture = scrollFixture()
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)
    let originalLayout = fixture.layout

    check scroll.metricsFor(fixture.root).get.viewport == size(100, 40)
    check scroll.metricsFor(fixture.root).get.content == size(100, 60)
    check scroll.revision == 0
    check scroll.setScrollOffset(fixture.root, vec2(20, 200))
    check scroll.scrollOffset(fixture.root) == vec2(0, 20)
    check scroll.revision == 1
    check not scroll.setScrollOffset(fixture.root, vec2(0, 20))
    check scroll.revision == 1
    check fixture.layout == originalLayout

    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)
    check scroll.scrollOffset(fixture.root) == vec2(0, 20)

  test "paint and hit testing share scroll translation and clipping":
    let fixture = scrollFixture()
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)
    check scroll.setScrollOffset(fixture.root, vec2(0, 15))

    let commands = buildPaintCommands(
      fixture.tree, fixture.styles, fixture.layout, scroll
    )
    var firstRect = none(Rect)
    for command in commands:
      if command.kind == pcFillRect and command.owner == some(fixture.first):
        firstRect = some(command.rect)
    check firstRect == some(rect(0, -15, 100, 30))

    let regions = buildHitRegions(
      fixture.tree, fixture.layout, fixture.styles, scroll
    )
    let firstHit = hitTest(regions, vec2(10, 5))
    check firstHit.isSome
    check firstHit.get.node == fixture.first
    check firstHit.get.local == vec2(10, 20)
    check hitTest(regions, vec2(10, 45)).isNone

  test "scrollbar visuals use resolved width colors and retained offset":
    let fixture = scrollFixture()
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)

    proc scrollbarRects(offset: float32): tuple[track, thumb: Option[Rect]] =
      discard scroll.setScrollOffset(fixture.root, vec2(0, offset))
      let commands = buildPaintCommands(
        fixture.tree, fixture.styles, fixture.layout, scroll
      )
      for command in commands:
        if command.kind != pcFillRect or command.owner != some(fixture.root):
          continue
        if command.color == rgb(0.04, 0.08, 0.07):
          result.track = some(command.rect)
        elif command.color == rgb(0.20, 0.70, 0.60):
          result.thumb = some(command.rect)

    let initial = scrollbarRects(0)
    check initial.track == some(rect(94, 0, 6, 40))
    check initial.thumb.isSome
    check abs(initial.thumb.get.x - 94) < 0.001
    check abs(initial.thumb.get.y) < 0.001
    check abs(initial.thumb.get.w - 6) < 0.001
    check abs(initial.thumb.get.h - (40.0 / 60.0 * 40.0)) < 0.001

    let scrolled = scrollbarRects(20)
    check scrolled.thumb.isSome
    check abs(scrolled.thumb.get.y - (40.0 - scrolled.thumb.get.h)) < 0.001

  test "scrollbar-width none suppresses scrollbar paint commands":
    var fixture = scrollFixture()
    fixture.styles.styles[fixture.root.nodeIndex].visual.scrollbarWidth = swNone
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)

    let commands = buildPaintCommands(
      fixture.tree, fixture.styles, fixture.layout, scroll
    )
    for command in commands:
      if command.kind == pcFillRect and command.owner == some(fixture.root):
        check command.color != rgb(0.04, 0.08, 0.07)
        check command.color != rgb(0.20, 0.70, 0.60)

  test "stable scrollbar gutter reserves layout space":
    var fixture = scrollFixture()
    fixture.styles.styles[fixture.root.nodeIndex].visual.scrollbarGutter = some("stable")
    fixture.layout = computeLayout(fixture.tree, fixture.styles, size(100, 40))
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)

    let metrics = scroll.metricsFor(fixture.root).get
    check metrics.viewport == size(94, 40)
    let geometry = scrollbarGeometry(
      rect(0, 0, 100, 40),
      fixture.styles.styles[fixture.root.nodeIndex],
      metrics
    )
    check geometry.vertical.isSome
    check geometry.vertical.get.track == rect(94, 0, 6, 40)

  test "both-edge stable gutter reserves symmetric layout space":
    var fixture = scrollFixture()
    fixture.styles.styles[fixture.root.nodeIndex].visual.scrollbarGutter =
      some("stable both-edges")
    fixture.layout = computeLayout(fixture.tree, fixture.styles, size(100, 40))
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)

    check scroll.metricsFor(fixture.root).get.viewport == size(88, 40)
    var firstRect = rect(0, 0, 0, 0)
    for item in fixture.layout.boxes:
      if item.node == fixture.first:
        firstRect = item.rect
    check firstRect.x == 6

  test "scrolling visibility paints only while retained scrolling is active":
    var fixture = scrollFixture()
    fixture.styles.styles[fixture.root.nodeIndex].visual.scrollbarVisibility = svScrolling
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)

    let idleCommands = buildPaintCommands(
      fixture.tree, fixture.styles, fixture.layout, scroll
    )
    var idleScrollbarCommands = 0
    for command in idleCommands:
      if command.kind == pcFillRect and command.owner == some(fixture.root) and
          command.color in [rgb(0.04, 0.08, 0.07), rgb(0.20, 0.70, 0.60)]:
        inc idleScrollbarCommands
    check idleScrollbarCommands == 0

    check scroll.scrollBy(fixture.root, vec2(0, 10))
    check scroll.metricsFor(fixture.root).get.scrolling
    let activeCommands = buildPaintCommands(
      fixture.tree, fixture.styles, fixture.layout, scroll
    )
    var activeScrollbarCommands = 0
    for command in activeCommands:
      if command.kind == pcFillRect and command.owner == some(fixture.root) and
          command.color in [rgb(0.04, 0.08, 0.07), rgb(0.20, 0.70, 0.60)]:
        inc activeScrollbarCommands
    check activeScrollbarCommands == 2

    var input = initInteractionState()
    input.scrollTarget = some(fixture.root)
    let ended = input.finishScroll(scroll)
    check ended.len == 1
    check not scroll.metricsFor(fixture.root).get.scrolling

  test "scrollbar hit regions stay above scrolled children":
    let fixture = scrollFixture()
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)
    let regions = buildHitRegions(
      fixture.tree, fixture.layout, fixture.styles, scroll
    )

    let thumbHit = hitTest(regions, vec2(97, 5))
    check thumbHit.isSome
    check thumbHit.get.node == fixture.root
    check thumbHit.get.kind == hrScrollbarThumbY

    let trackHit = hitTest(regions, vec2(97, 35))
    check trackHit.isSome
    check trackHit.get.node == fixture.root
    check trackHit.get.kind == hrScrollbarTrackY

  test "scrollbar thumb drag updates retained offset and emits scroll":
    var fixture = scrollFixture()
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)
    let regions = buildHitRegions(
      fixture.tree, fixture.layout, fixture.styles, scroll
    )
    var input = initInteractionState()

    let down = input.processInput(
      fixture.tree, regions, pointerDownEvent(vec2(97, 5), 1), scroll
    )
    check down.len == 0
    check input.scrollbarPointerTarget == some(fixture.root)
    check input.scrollbarDragging

    let moved = input.processInput(
      fixture.tree, regions, pointerMoveEvent(vec2(97, 15)), scroll
    )
    check abs(scroll.scrollOffset(fixture.root).y - 15) < 0.001
    check moved.len == 1
    check moved[0].target == some(fixture.root)
    check moved[0].event.kind == iekScroll

    let released = input.processInput(
      fixture.tree, regions, pointerUpEvent(vec2(97, 15), 1), scroll
    )
    check released.len == 0
    check input.scrollbarPointerTarget.isNone
    check not input.scrollbarDragging

  test "scrollbar track click pages without dispatching to content":
    var fixture = scrollFixture()
    var scroll = initScrollState()
    scroll.syncScrollState(fixture.tree, fixture.styles, fixture.layout)
    let regions = buildHitRegions(
      fixture.tree, fixture.layout, fixture.styles, scroll
    )
    var input = initInteractionState()

    let down = input.processInput(
      fixture.tree, regions, pointerDownEvent(vec2(97, 35), 1), scroll
    )
    check scroll.scrollOffset(fixture.root) == vec2(0, 20)
    check down.len == 1
    check down[0].target == some(fixture.root)
    check down[0].event.kind == iekScroll
    check input.pressedTarget.isNone

    discard input.processInput(
      fixture.tree, regions, pointerUpEvent(vec2(97, 35), 1), scroll
    )

  test "wheel input scrolls the nearest available ancestor":
    var tree = initTree()
    let outer = tree.addBox(id = "outer")
    let inner = tree.addBox(parent = some(outer), id = "inner")
    var scroll = initScrollState()
    scroll.entries = newSeq[ScrollMetrics](2)
    scroll.entries[outer.nodeIndex] = ScrollMetrics(
      active: true, node: some(outer),
      viewport: size(100, 50), content: size(100, 100),
      enabledY: true, overscrollY: obAuto
    )
    scroll.entries[inner.nodeIndex] = ScrollMetrics(
      active: true, node: some(inner),
      viewport: size(100, 30), content: size(100, 40),
      enabledY: true, overscrollY: obAuto
    )
    let regions = @[
      HitRegion(
        node: inner,
        rect: rect(0, 0, 100, 30),
        localOrigin: some(vec2(0, 0)),
        zIndex: 1
      )
    ]
    var input = initInteractionState()
    var registry = initEventRegistry()
    var scrollEvents = 0
    registry.onScroll(inner, proc(event: DispatchResult): bool =
      inc scrollEvents
      true
    )

    let firstWheel = input.processInput(
      tree, regions, wheelEvent(vec2(10, 10), vec2(0, 20)), scroll
    )
    check scroll.scrollOffset(inner) == vec2(0, 10)
    check scroll.scrollOffset(outer) == vec2(0, 0)
    check firstWheel.len == 2
    check firstWheel[0].target == some(inner)
    check firstWheel[0].event.kind == iekWheel
    check firstWheel[1].target == some(inner)
    check firstWheel[1].event.kind == iekScroll
    check registry.handle(firstWheel)
    check scrollEvents == 1

    let secondWheel = input.processInput(
      tree, regions, wheelEvent(vec2(10, 10), vec2(0, 20)), scroll
    )
    check scroll.scrollOffset(inner) == vec2(0, 10)
    check scroll.scrollOffset(outer) == vec2(0, 20)
    check secondWheel.len == 2
    check secondWheel[0].target == some(inner)
    check secondWheel[0].event.kind == iekWheel
    check secondWheel[1].target == some(outer)
    check secondWheel[1].event.kind == iekScroll

  test "overscroll containment stops wheel chaining at a boundary":
    var tree = initTree()
    let outer = tree.addBox(id = "outer")
    let inner = tree.addBox(parent = some(outer), id = "inner")
    var scroll = initScrollState()
    scroll.entries = newSeq[ScrollMetrics](2)
    scroll.entries[outer.nodeIndex] = ScrollMetrics(
      active: true, node: some(outer),
      viewport: size(100, 50), content: size(100, 100),
      enabledY: true, overscrollY: obAuto
    )
    scroll.entries[inner.nodeIndex] = ScrollMetrics(
      active: true, node: some(inner), offset: vec2(0, 10),
      viewport: size(100, 30),
      content: size(100, 40), enabledY: true, overscrollY: obContain
    )
    let regions = @[
      HitRegion(
        node: inner,
        rect: rect(0, 0, 100, 30),
        localOrigin: some(vec2(0, 0)),
        zIndex: 1
      )
    ]
    var input = initInteractionState()

    discard input.processInput(
      tree, regions, wheelEvent(vec2(10, 10), vec2(0, 20)), scroll
    )
    check scroll.scrollOffset(inner) == vec2(0, 10)
    check scroll.scrollOffset(outer) == vec2(0, 0)
    check input.scrollTarget == some(inner)
