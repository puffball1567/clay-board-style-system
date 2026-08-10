import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties
import clay_board_style_system/testing/test_driver

proc resolved(
    tree: Tree;
    node: NodeId;
    declarations: openArray[Declaration]
): ResolvedTree =
  var diagnostics: Diagnostics
  result = resolveTreeStyles(
    tree,
    [styleSheet([rule(target(node), declarations)])],
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors

proc transitionMetadata(
    property: string;
    duration: float32;
    delay = 0.0'f32;
    timing = "linear"
): seq[Declaration] =
  @[
    decl("transition-property", keyword(property)),
    decl("transition-duration", number(duration)),
    decl("transition-delay", number(delay)),
    decl("transition-timing-function", keyword(timing))
  ]

suite "declarative style transitions":
  test "opacity samples active tracks without resolving the tree again":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    var displayed = tree.resolved(root, [decl("opacity", number(0))])
    let targetStyles = transitionMetadata("opacity", 1)
    let target = tree.resolved(root, targetStyles & @[decl("opacity", number(1))])
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()

    runtime.reconcileTransitions(tree, displayed, target, 10)
    check runtime.activeTransitionCount == 1
    displayed = target
    check runtime.applyTransitions(tree, displayed, scheduler, 10) == 1
    check displayed.styles[root.nodeIndex].visual.opacity == 0
    check scheduler.consumeDirty() == {ddPaint, ddAnimation}

    scheduler.clearDeadline()
    check runtime.applyTransitions(tree, displayed, scheduler, 10.5) == 1
    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.5) < 0.0001
    check scheduler.nextDeadline.isSome

    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check runtime.applyTransitions(tree, displayed, scheduler, 11) == 1
    check displayed.styles[root.nodeIndex].visual.opacity == 1
    check runtime.activeTransitionCount == 0

  test "delay schedules its boundary without requesting intermediate frames":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [decl("opacity", number(0))])
    let target = tree.resolved(
      root,
      transitionMetadata("opacity", 1, delay = 2) &
        @[decl("opacity", number(1))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 5)
    displayed = target

    discard runtime.applyTransitions(tree, displayed, scheduler, 5.5)
    check displayed.styles[root.nodeIndex].visual.opacity == 0
    check scheduler.nextDeadline == some(7.0)

  test "named and cubic timing functions are parsed strictly":
    check parseTimingFunction(" ease-in-out ").isSome
    check parseTimingFunction("STEP-END").isSome
    let cubic = parseTimingFunction("cubic-bezier(0.2, 0.8, 0.4, 1)")
    check cubic.isSome
    check cubic.get.kind == tfCubicBezier
    check parseTimingFunction("cubic-bezier(-0.1, 0, 1, 1)").isNone
    check parseTimingFunction("steps(4, end)").isNone
    check parseTimingFunction("unknown").isNone

  test "reconciling the same target does not restart an active track":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [decl("opacity", number(0))])
    let target = tree.resolved(
      root,
      transitionMetadata("opacity", 1) & @[decl("opacity", number(1))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 0)
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.4)
    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.4) < 0.0001

    runtime.reconcileTransitions(tree, displayed, target, 0.4)
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.6)
    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.6) < 0.0001

  test "a changed target reverses from the currently displayed value":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [decl("opacity", number(0))])
    let visible = tree.resolved(
      root,
      transitionMetadata("opacity", 1) & @[decl("opacity", number(1))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, visible, 0)
    displayed = visible
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.4)

    let hidden = tree.resolved(
      root,
      transitionMetadata("opacity", 1) & @[decl("opacity", number(0))]
    )
    runtime.reconcileTransitions(tree, displayed, hidden, 0.4)
    displayed = hidden
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.4)
    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.4) < 0.0001
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.9)
    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.2) < 0.0001

  test "text and background colors interpolate in Oklab":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [
      decl("color", colorValue(rgb(1, 0, 0))),
      decl("background-color", colorValue(rgb(0, 0, 0)))
    ])
    let target = tree.resolved(root,
      transitionMetadata("color, background-color", 1) & @[
        decl("color", colorValue(rgb(0, 0, 1))),
        decl("background-color", colorValue(rgb(1, 1, 1)))
      ]
    )
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 0)
    check runtime.activeTransitionCount == 2
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.5)

    let foreground = displayed.styles[root.nodeIndex].text.color.get
    let background = displayed.styles[root.nodeIndex].box.backgroundColor.get
    check foreground.r > 0.4
    check foreground.b > 0.4
    check background.r > 0.3 and background.r < 0.8

  test "transition lists cycle values and preserve unknown property positions":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [
      decl("opacity", number(0)),
      decl("background-color", colorValue(rgba(0, 0, 0, 0)))
    ])
    let target = tree.resolved(root, [
      transitionProperties(
        "future-property", "opacity", "background-color"
      ),
      transitionDurations(8.0'f32, 2.0'f32),
      transitionDelays(0.0'f32, 0.5'f32),
      transitionTimingFunctions("linear"),
      decl("opacity", number(1)),
      decl("background-color", colorValue(rgba(1, 1, 1, 1)))
    ])
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 0)
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 1)

    # opacity uses index 1: duration 2, delay 0.5. Background uses index 2,
    # cycling back to duration 8 and delay 0.
    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.25) < 0.0001
    let background = displayed.styles[root.nodeIndex].box.backgroundColor.get
    check abs(background.a - 0.125) < 0.001

  test "the last matching transition-property entry supplies parameters":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [decl("opacity", number(0))])
    let target = tree.resolved(root, [
      transitionProperties("opacity", "all", "opacity"),
      transitionDurations(8.0'f32, 4.0'f32, 1.0'f32),
      transitionTimingFunctions("linear"),
      decl("opacity", number(1))
    ])
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 0)
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.5)

    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.5) < 0.0001

  test "background none transitions through transparent target color":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [])
    let target = tree.resolved(
      root,
      transitionMetadata("background-color", 1) &
        @[decl("background-color", colorValue(rgb(0.2, 0.6, 0.9)))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 0)
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 0)
    check displayed.styles[root.nodeIndex].box.backgroundColor.get.a == 0
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.5)
    check abs(displayed.styles[root.nodeIndex].box.backgroundColor.get.a - 0.5) < 0.001

  test "reduced motion and zero duration apply targets immediately":
    var tree = initTree()
    let root = tree.addBox()
    let displayed = tree.resolved(root, [decl("opacity", number(0))])
    let target = tree.resolved(
      root,
      transitionMetadata("all", 1) & @[decl("opacity", number(1))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    runtime.reducedMotion = true
    runtime.reconcileTransitions(tree, displayed, target, 0)
    check not runtime.hasActiveTransitions

    runtime.reducedMotion = false
    let immediate = tree.resolved(
      root,
      transitionMetadata("all", 0) & @[decl("opacity", number(1))]
    )
    runtime.reconcileTransitions(tree, displayed, immediate, 0)
    check not runtime.hasActiveTransitions

  test "enabling reduced motion completes an active track immediately":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [decl("opacity", number(0))])
    let target = tree.resolved(
      root,
      transitionMetadata("opacity", 10) & @[decl("opacity", number(1))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 0)
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 1)
    check displayed.styles[root.nodeIndex].visual.opacity < 1

    runtime.reducedMotion = true
    discard runtime.applyTransitions(tree, displayed, scheduler, 1)
    check displayed.styles[root.nodeIndex].visual.opacity == 1
    check not runtime.hasActiveTransitions

  test "negative delay begins within the active interval":
    var tree = initTree()
    let root = tree.addBox()
    var displayed = tree.resolved(root, [decl("opacity", number(0))])
    let target = tree.resolved(
      root,
      transitionMetadata("opacity", 1, delay = -0.25) &
        @[decl("opacity", number(1))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    var scheduler = initFrameScheduler()
    runtime.reconcileTransitions(tree, displayed, target, 5)
    displayed = target
    discard runtime.applyTransitions(tree, displayed, scheduler, 5)
    check abs(displayed.styles[root.nodeIndex].visual.opacity - 0.25) < 0.0001

  test "disposed node tracks are removed without touching recycled nodes":
    var tree = initTree()
    let root = tree.addBox()
    let child = tree.addBox(parent = some(root))
    var displayed = tree.resolved(child, [decl("opacity", number(0))])
    let target = tree.resolved(
      child,
      transitionMetadata("opacity", 1) & @[decl("opacity", number(1))]
    )
    var runtime = initDeclarativeTransitionRuntime()
    runtime.reconcileTransitions(tree, displayed, target, 0)
    check runtime.activeTransitionCount == 1
    discard tree.disposeSubtree(child)
    var scheduler = initFrameScheduler()
    discard runtime.applyTransitions(tree, displayed, scheduler, 0.5)
    check runtime.activeTransitionCount == 0

  test "invalid frame rate and non-finite times fail early":
    expect ValueError:
      discard initDeclarativeTransitionRuntime(0)
    var tree = initTree()
    let root = tree.addBox()
    let styles = tree.resolved(root, [])
    var runtime = initDeclarativeTransitionRuntime()
    expect ValueError:
      runtime.reconcileTransitions(tree, styles, styles, NaN)
    var mutableStyles = styles
    var scheduler = initFrameScheduler()
    expect ValueError:
      discard runtime.applyTransitions(tree, mutableStyles, scheduler, Inf)

  test "UiRoot disposal cancels owned declarative tracks":
    let ui = initUiRoot()
    let root = ui.box(id = "root")
    let child = ui.box(parent = some(root), id = "child")
    var initialDiagnostics: Diagnostics
    let displayed = resolveTreeStyles(
      ui.tree,
      [styleSheet([rule(target(child.id), [decl("opacity", number(0))])])],
      defaultProperties(),
      initialDiagnostics
    )
    check not initialDiagnostics.hasErrors
    var diagnostics: Diagnostics
    let targetStyles = resolveTreeStyles(
      ui.tree,
      [styleSheet([rule(target(child.id),
        transitionMetadata("opacity", 1) & @[decl("opacity", number(1))]
      )])],
      defaultProperties(),
      diagnostics
    )
    ui.reconcileStyleTransitions(displayed, targetStyles, 0)
    check ui.activeStyleTransitionCount == 1
    var interaction = initInteractionState()
    check ui.disposeSubtree(child, interaction)
    check ui.activeStyleTransitionCount == 0

  test "headless driver advances paint-only transitions without relayout":
    let ui = initUiRoot()
    let panel = ui.box(
      uiStyle(transitionMetadata("opacity", 1) & @[
        decl("width", px(120)),
        decl("height", px(40)),
        decl("opacity", number(0))
      ]),
      id = "panel"
    )
    let driver = initCbssTestDriver(ui, size(320, 180))
    let initialRect = driver.rectFor(panel.id)
    check initialRect.isSome

    panel.applyStyle(uiStyle([decl("opacity", number(1))]))
    driver.refresh()
    check ui.activeStyleTransitionCount == 1
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 0

    driver.advanceTime(0.5)
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.5) < 0.0001
    check driver.rectFor(panel.id) == initialRect
    check driver.scheduler.consumeDirty() == {ddPaint, ddAnimation}

    driver.advanceTime(0.5)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1
    check ui.activeStyleTransitionCount == 0

  test "headless driver rejects invalid elapsed time":
    let driver = initCbssTestDriver(initUiRoot(), size(100, 100))
    expect ValueError:
      driver.advanceTime(-0.1)
    expect ValueError:
      driver.advanceTime(NaN)
