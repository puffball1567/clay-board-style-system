import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/generated/default_properties
import clay_board_style_system/paint/background_geometry

proc edges(value: float32): EdgeSizes =
  EdgeSizes(top: value, right: value, bottom: value, left: value)

proc gradient(): LinearGradient =
  LinearGradient(
    angle: 90,
    interpolationSpace: cisSrgb,
    stops: @[
      GradientStop(color: rgb(1, 0, 0), offset: 0),
      GradientStop(color: rgb(0, 0, 1), offset: 100)
    ]
  )

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b: uint8] =
  let index = (y * image.width + x) * 3
  (image.pixels[index], image.pixels[index + 1], image.pixels[index + 2])

suite "background geometry runtime":
  test "origin clip size and mixed-unit position share one geometry":
    var style = initialComputedStyle().box
    style.borderWidths = edges(4)
    style.borderRadius = 12
    style.backgroundOrigin = bgContentBox
    style.backgroundClip = bgPaddingBox
    style.backgroundRepeat = bgNoRepeat
    style.backgroundSize = some(BackgroundSize(
      kind: bgSizeLength,
      width: some(50.0'f32),
      height: none(float32),
      widthValue: some(LengthValue(kind: ukPercent, value: 50)),
      heightValue: none(LengthValue)
    ))
    style.backgroundPositionValue = BackgroundPosition(
      x: LengthValue(kind: ukPercent, value: 100),
      y: LengthValue(kind: ukPx, value: 5)
    )

    let geometry = backgroundPaintGeometry(
      rect(0, 0, 100, 80), style, edges(6)
    )

    check geometry.originRect == rect(10, 10, 80, 60)
    check geometry.clipRect == rect(4, 4, 92, 72)
    check geometry.clipRadius == 8
    check geometry.tileRect == rect(50, 15, 40, 60)
    check geometry.paintRect == geometry.tileRect

  test "repeat axes expand only their own paint dimension":
    var style = initialComputedStyle().box
    style.backgroundSize = some(BackgroundSize(
      kind: bgSizeLength,
      width: some(20.0'f32),
      height: some(10.0'f32),
      widthValue: some(LengthValue(kind: ukPx, value: 20)),
      heightValue: some(LengthValue(kind: ukPx, value: 10))
    ))
    style.backgroundPositionValue = BackgroundPosition(
      x: LengthValue(kind: ukPx, value: 5),
      y: LengthValue(kind: ukPx, value: 7)
    )

    style.backgroundRepeat = bgRepeatX
    let horizontal = backgroundPaintGeometry(
      rect(0, 0, 100, 60), style, EdgeSizes()
    )
    check horizontal.tileRect == rect(5, 7, 20, 10)
    check horizontal.paintRect == rect(0, 7, 100, 10)

    style.backgroundRepeat = bgRepeatY
    let vertical = backgroundPaintGeometry(
      rect(0, 0, 100, 60), style, EdgeSizes()
    )
    check vertical.paintRect == rect(5, 0, 20, 60)

    style.backgroundRepeat = bgRepeat
    let both = backgroundPaintGeometry(
      rect(0, 0, 100, 60), style, EdgeSizes()
    )
    check both.paintRect == rect(0, 0, 100, 60)

  test "property resolution preserves percentage and absolute intent":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([rule(target(root), [
        decl("background-size", percent(25)),
        decl("background-position-x", px(7)),
        decl("background-position-y", percent(75))
      ])])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let style = styles.styles[root.nodeIndex].box
    check style.backgroundSize.get.widthValue ==
      some(LengthValue(kind: ukPercent, value: 25))
    check style.backgroundPositionValue.x ==
      LengthValue(kind: ukPx, value: 7)
    check style.backgroundPositionValue.y ==
      LengthValue(kind: ukPercent, value: 75)

  test "contextual units resolve once while percentages remain deferred":
    var diagnostics: Diagnostics
    let style = resolveStyles(
      styleContext([
        decl("background-size", em(2)),
        decl("background-position-x", vw(10)),
        decl("background-position-y", percent(25))
      ]),
      defaultProperties(),
      ResolveEnv(
        currentFontSize: some(20.0'f32),
        viewportSize: some(size(800, 600))
      ),
      diagnostics
    )

    check not diagnostics.hasErrors
    check style.box.backgroundSize.get.widthValue ==
      some(LengthValue(kind: ukPx, value: 40))
    check style.box.backgroundPositionValue.x ==
      LengthValue(kind: ukPx, value: 80)
    check style.box.backgroundPositionValue.y ==
      LengthValue(kind: ukPercent, value: 25)

  test "single background-position keywords preserve the other centered axis":
    let cases: array[3, tuple[
      keywordValue: string,
      expected: BackgroundPosition
    ]] = [
      ("left", BackgroundPosition(
        x: LengthValue(kind: ukPercent, value: 0),
        y: LengthValue(kind: ukPercent, value: 50)
      )),
      ("top", BackgroundPosition(
        x: LengthValue(kind: ukPercent, value: 50),
        y: LengthValue(kind: ukPercent, value: 0)
      )),
      ("center", BackgroundPosition(
        x: LengthValue(kind: ukPercent, value: 50),
        y: LengthValue(kind: ukPercent, value: 50)
      ))
    ]
    for testCase in cases:
      var tree = initTree()
      let root = tree.addBox()
      var diagnostics: Diagnostics
      let styles = resolveTreeStyles(
        tree,
        [styleSheet([rule(target(root), [
          decl("background-position", keyword(testCase.keywordValue))
        ])])],
        defaultProperties(),
        diagnostics
      )
      check not diagnostics.hasErrors
      check styles.styles[root.nodeIndex].box.backgroundPositionValue ==
        testCase.expected

  test "invalid negative size and unitless position fail deterministically":
    var tree = initTree()
    let root = tree.addBox()
    var diagnostics: Diagnostics
    discard resolveTreeStyles(
      tree,
      [styleSheet([rule(target(root), [
        decl("background-size", px(-1)),
        decl("background-position-x", number(2))
      ])])],
      defaultProperties(),
      diagnostics
    )

    check diagnostics.hasErrors
    check diagnostics.items.len == 2

  test "oversized insets and a zero-sized tile stay empty and non-negative":
    var style = initialComputedStyle().box
    style.borderWidths = EdgeSizes(
      top: 80, right: 80, bottom: 80, left: 80
    )
    style.backgroundOrigin = bgContentBox
    style.backgroundClip = bgContentBox
    style.backgroundSize = some(BackgroundSize(
      kind: bgSizeLength,
      width: some(0.0'f32),
      height: none(float32),
      widthValue: some(LengthValue(kind: ukPx, value: 0)),
      heightValue: none(LengthValue)
    ))

    let geometry = backgroundPaintGeometry(
      rect(0, 0, 100, 50), style, edges(30)
    )
    check geometry.originRect.w == 0
    check geometry.originRect.h == 0
    check geometry.clipRect.w == 0
    check geometry.clipRect.h == 0
    check geometry.tileRect.w == 0
    check geometry.paintRect.isEmpty

  test "paint emits clipped color and one bounded repeated gradient command":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    var diagnostics: Diagnostics
    var styles = resolveTreeStyles(
      tree,
      [styleSheet([rule(target(root), [
        decl("width", px(100)),
        decl("height", px(60)),
        decl("box-sizing", keyword("border-box")),
        decl("padding", px(6)),
        decl("border", borderValue(px(4), "solid", rgb(0, 0, 0))),
        decl("background-color", colorValue(rgb(0.1, 0.2, 0.3))),
        decl("background-image", linearGradient(
          90,
          colorStop(rgb(1, 0, 0), 0),
          colorStop(rgb(0, 0, 1), 100)
        )),
        decl("background-origin", keyword("content-box")),
        decl("background-clip", keyword("padding-box")),
        decl("background-size", px(0.01)),
        decl("background-repeat", keyword("repeat"))
      ])])],
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 80))
    let commands = buildPaintCommands(tree, styles, layout)
    var fills = 0
    var gradients = 0
    for command in commands:
      case command.kind
      of pcFillRect:
        inc fills
        check command.rect == rect(4, 4, 92, 52)
      of pcFillLinearGradient:
        inc gradients
        check command.gradientRect == rect(10, 10, 0.01, 40)
        check command.gradientPaintRect == rect(4, 4, 92, 52)
        check command.gradientClipRect == rect(4, 4, 92, 52)
        check command.gradientRepeat == bgRepeat
      else:
        discard
    check fills == 1
    check gradients == 1

suite "repeated gradient raster":
  test "paint command defaults preserve the non-repeating canvas contract":
    let command = fillLinearGradient(rect(2, 3, 4, 5), gradient())
    check command.gradientPaintRect == command.gradientRect
    check command.gradientClipRect == command.gradientRect
    check command.gradientRepeat == bgNoRepeat

  test "repeat reuses one tile on both axes":
    let image = render([
      fillLinearGradient(
        rect(0, 0, 4, 2), gradient(),
        paintRect = some(rect(0, 0, 12, 4)),
        repeat = bgRepeat
      )
    ], 12, 4)

    check image.pixel(0, 0) == image.pixel(4, 0)
    check image.pixel(3, 1) == image.pixel(7, 3)

  test "no-repeat leaves pixels outside the positioned tile untouched":
    let image = render([
      fillLinearGradient(
        rect(2, 1, 4, 2), gradient(),
        paintRect = some(rect(0, 0, 10, 4)),
        repeat = bgNoRepeat
      )
    ], 10, 4)

    check image.pixel(0, 0) == (255'u8, 255'u8, 255'u8)
    check image.pixel(2, 1) != (255'u8, 255'u8, 255'u8)
    check image.pixel(7, 1) == (255'u8, 255'u8, 255'u8)

  test "repeat-x does not repeat outside the tile block axis":
    let image = render([
      fillLinearGradient(
        rect(0, 1, 4, 2), gradient(),
        paintRect = some(rect(0, 0, 12, 4)),
        repeat = bgRepeatX
      )
    ], 12, 4)

    check image.pixel(0, 1) == image.pixel(4, 1)
    check image.pixel(0, 0) == (255'u8, 255'u8, 255'u8)
    check image.pixel(0, 3) == (255'u8, 255'u8, 255'u8)

  test "repeat-y does not repeat outside the tile inline axis":
    let image = render([
      fillLinearGradient(
        rect(2, 0, 4, 2), gradient(),
        paintRect = some(rect(0, 0, 10, 6)),
        repeat = bgRepeatY
      )
    ], 10, 6)

    check image.pixel(2, 0) == image.pixel(2, 2)
    check image.pixel(1, 0) == (255'u8, 255'u8, 255'u8)
    check image.pixel(6, 0) == (255'u8, 255'u8, 255'u8)

  test "repeat phase follows transformed source coordinates":
    let image = render([
      pushTransform(translationAffine2D(3, 2) * scaleAffine2D(2, 2)),
      fillLinearGradient(
        rect(0, 0, 2, 2), gradient(),
        paintRect = some(rect(0, 0, 6, 2)),
        repeat = bgRepeatX
      ),
      popTransform()
    ], 16, 8)

    check image.pixel(3, 2) == image.pixel(7, 2)
    check image.pixel(2, 2) == (255'u8, 255'u8, 255'u8)
    check image.pixel(3, 6) == (255'u8, 255'u8, 255'u8)
