import std/[algorithm, options, strutils, unicode]
import ../core/[computed_style, geometry, node, style_resolver, style_value]
import ../text/font_registry
import ../text/text_engine
import ./overflow_geometry

type
  LayoutBox* = object
    node*: NodeId
    rect*: Rect
    zIndex*: int

  LayoutOverflowMetrics* = object
    node*: NodeId
    viewportSize*: Size
    contentSize*: Size

  LayoutResult* = object
    boxes*: seq[LayoutBox]
    overflowMetrics*: seq[LayoutOverflowMetrics]
    boxIndices: seq[int]

  ChildPlacement = object
    node: NodeId
    size: Size
    minMain: float32
    margin: EdgeSizes
    firstBox: int
    boxCount: int

  OrderedChild = object
    node: NodeId
    order: int

  IntrinsicSizes = object
    minSize: Size
    maxSize: Size

proc layoutBoxIndices*(layout: LayoutResult; nodeCount: int): seq[int] =
  ## Layout owns this index. Paint and hit stages borrow its shared sequence
  ## instead of rebuilding an O(tree) map for every presentation update.
  if layout.boxIndices.len == nodeCount:
    return layout.boxIndices
  result = newSeq[int](nodeCount)
  for index in 0 ..< result.len:
    result[index] = -1
  for index, item in layout.boxes:
    if item.node.nodeIndex >= 0 and item.node.nodeIndex < result.len:
      result[item.node.nodeIndex] = index

proc rebuildBoxIndices(layout: var LayoutResult; nodeCount: int) =
  layout.boxIndices.setLen(nodeCount)
  for index in 0 ..< layout.boxIndices.len:
    layout.boxIndices[index] = -1
  for index, item in layout.boxes:
    if item.node.nodeIndex >= 0 and item.node.nodeIndex < layout.boxIndices.len:
      layout.boxIndices[item.node.nodeIndex] = index

proc boxIndexFor*(indices: openArray[int]; id: NodeId): int =
  if id.nodeIndex < 0 or id.nodeIndex >= indices.len:
    return -1
  indices[id.nodeIndex]

proc compareOrderedChild(a, b: OrderedChild): int {.nimcall.} =
  result = cmp(a.order, b.order)
  if result == 0:
    result = cmp(a.node.nodeIndex, b.node.nodeIndex)

proc childrenInLayoutOrder(node: Node; styles: ResolvedTree): seq[NodeId] =
  ## Avoid capturing ResolvedTree in a sort closure: under ARC that can copy it.
  var needsSort = false
  var previousNodeIndex = -1
  for child in node.children:
    if styles.styles[child.nodeIndex].layout.order != 0:
      needsSort = true
      break
    if child.nodeIndex < previousNodeIndex:
      needsSort = true
      break
    previousNodeIndex = child.nodeIndex
  if not needsSort:
    return node.children

  var ordered = newSeqOfCap[OrderedChild](node.children.len)
  for child in node.children:
    ordered.add OrderedChild(
      node: child,
      order: styles.styles[child.nodeIndex].layout.order
    )
  ordered.sort(compareOrderedChild)
  result = newSeqOfCap[NodeId](ordered.len)
  for child in ordered:
    result.add child.node

proc isAbsolute(style: ComputedStyle): bool =
  style.layout.position == pkAbsolute

proc paddingOf(style: ComputedStyle): EdgeSizes =
  result =
    if style.box.padding.isSome: style.box.padding.get
    else: edges(0)
  let gutter = style.scrollbarGutterInsets()
  result.top += gutter.top
  result.right += gutter.right
  result.bottom += gutter.bottom
  result.left += gutter.left

proc marginOf(style: ComputedStyle): EdgeSizes =
  if style.box.margin.isSome:
    style.box.margin.get
  else:
    edges(0)

proc shiftBoxes(output: var LayoutResult; firstBox, boxCount: int; dx, dy: float32) =
  for index in firstBox ..< firstBox + boxCount:
    output.boxes[index].rect.x += dx
    output.boxes[index].rect.y += dy

proc scaleBoxes(output: var LayoutResult; firstBox, boxCount: int; originX, originY, factor: float32) =
  for index in firstBox ..< firstBox + boxCount:
    output.boxes[index].rect.x = originX + (output.boxes[index].rect.x - originX) * factor
    output.boxes[index].rect.y = originY + (output.boxes[index].rect.y - originY) * factor
    output.boxes[index].rect.w *= factor
    output.boxes[index].rect.h *= factor

proc stretchOwnBox(output: var LayoutResult; firstBox, boxCount: int; node: NodeId; width, height: Option[float32]) =
  for index in firstBox ..< firstBox + boxCount:
    if output.boxes[index].node == node:
      if width.isSome:
        output.boxes[index].rect.w = width.get
      if height.isSome:
        output.boxes[index].rect.h = height.get
      return

proc setMainSize(
    output: var LayoutResult;
    firstBox, boxCount: int;
    node: NodeId;
    direction: FlexDirection;
    size: float32
) =
  if direction == fdRow:
    output.stretchOwnBox(firstBox, boxCount, node, some(size), none(float32))
  else:
    output.stretchOwnBox(firstBox, boxCount, node, none(float32), some(size))

proc fixedLength(value: Option[float32]): Option[LengthValue] =
  if value.isSome:
    return some(LengthValue(kind: ukPx, value: value.get))
  none(LengthValue)

proc widthSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.width.isSome:
    return style.layout.sizing.width
  fixedLength(style.layout.width)

proc heightSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.height.isSome:
    return style.layout.sizing.height
  fixedLength(style.layout.height)

proc minWidthSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.minWidth.isSome:
    return style.layout.sizing.minWidth
  fixedLength(style.layout.minWidth)

proc maxWidthSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.maxWidth.isSome:
    return style.layout.sizing.maxWidth
  fixedLength(style.layout.maxWidth)

proc minHeightSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.minHeight.isSome:
    return style.layout.sizing.minHeight
  fixedLength(style.layout.minHeight)

proc maxHeightSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.maxHeight.isSome:
    return style.layout.sizing.maxHeight
  fixedLength(style.layout.maxHeight)

proc flexBasisSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.flexBasis.isSome:
    return style.layout.sizing.flexBasis
  fixedLength(style.layout.flexBasis)

proc gapSpec(style: ComputedStyle; axisGap: Option[LengthValue]): Option[LengthValue] =
  if axisGap.isSome:
    return axisGap
  if not style.layout.sizing.isNil and style.layout.sizing.gap.isSome:
    return style.layout.sizing.gap
  some(LengthValue(kind: ukPx, value: style.layout.gap))

proc mainGapSpec(style: ComputedStyle): Option[LengthValue] =
  if style.layout.direction == fdRow:
    if not style.layout.sizing.isNil and style.layout.sizing.columnGap.isSome:
      return style.layout.sizing.columnGap
    return style.gapSpec(fixedLength(style.layout.columnGap))
  if not style.layout.sizing.isNil and style.layout.sizing.rowGap.isSome:
    return style.layout.sizing.rowGap
  style.gapSpec(fixedLength(style.layout.rowGap))

proc resolveLength(
    value: Option[LengthValue];
    reference, intrinsicMin, intrinsicMax: float32
): Option[float32] =
  if value.isNone:
    return none(float32)
  let length = value.get
  case length.kind
  of ukPx:
    some(max(0.0'f32, length.value))
  of ukPercent:
    some(max(0.0'f32, reference * length.value / 100.0'f32))
  of ukContent, ukMaxContent:
    some(max(0.0'f32, intrinsicMax))
  of ukMinContent:
    some(max(0.0'f32, intrinsicMin))
  of ukFitContent:
    some(max(intrinsicMin, min(intrinsicMax, reference)))
  of ukAuto, ukNone:
    none(float32)
  of ukFill:
    some(max(0.0'f32, reference))
  of ukEm, ukRem:
    none(float32)

proc flexMinimumMain(
    style: ComputedStyle;
    direction: FlexDirection;
    constraints: Size;
    intrinsic: IntrinsicSizes
): float32 =
  let reference = if direction == fdRow: constraints.w else: constraints.h
  let intrinsicMin = if direction == fdRow: intrinsic.minSize.w else: intrinsic.minSize.h
  let intrinsicMax = if direction == fdRow: intrinsic.maxSize.w else: intrinsic.maxSize.h
  let minimumSpec = if direction == fdRow: style.minWidthSpec() else: style.minHeightSpec()
  if minimumSpec.isSome and minimumSpec.get.kind != ukAuto:
    let resolved = resolveLength(minimumSpec, reference, intrinsicMin, intrinsicMax)
    return if resolved.isSome: resolved.get else: 0.0'f32

  let overflow = if direction == fdRow: style.layout.overflowX else: style.layout.overflowY
  if overflow in {omAuto, omScroll}:
    return 0.0'f32

  # CSS automatic minimum size is content based for non-scrollable flex
  # items, capped by a definite preferred size when one exists.
  result = max(0.0'f32, intrinsicMin)
  let preferredSpec = if direction == fdRow: style.widthSpec() else: style.heightSpec()
  let preferred = resolveLength(preferredSpec, reference, intrinsicMin, intrinsicMax)
  if preferred.isSome:
    result = min(result, preferred.get)

proc mainGapOf(style: ComputedStyle; contentSize: Size): float32 =
  let reference =
    if style.layout.direction == fdRow: contentSize.w
    else: contentSize.h
  let resolved = resolveLength(style.mainGapSpec(), reference, 0, 0)
  if resolved.isSome: resolved.get else: 0.0'f32

proc insetTopSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.insetTop.isSome:
    return style.layout.sizing.insetTop
  fixedLength(style.layout.inset.top)

proc insetRightSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.insetRight.isSome:
    return style.layout.sizing.insetRight
  fixedLength(style.layout.inset.right)

proc insetBottomSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.insetBottom.isSome:
    return style.layout.sizing.insetBottom
  fixedLength(style.layout.inset.bottom)

proc insetLeftSpec(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.insetLeft.isSome:
    return style.layout.sizing.insetLeft
  fixedLength(style.layout.inset.left)

proc resolveInsetLength(value: Option[LengthValue]; reference: float32): Option[float32] =
  if value.isNone:
    return none(float32)
  case value.get.kind
  of ukPx:
    some(value.get.value)
  of ukPercent:
    some(reference * value.get.value / 100.0'f32)
  else:
    none(float32)

proc resolvedInsets(style: ComputedStyle; containingSize: Size): Insets =
  Insets(
    top: resolveInsetLength(style.insetTopSpec(), containingSize.h),
    right: resolveInsetLength(style.insetRightSpec(), containingSize.w),
    bottom: resolveInsetLength(style.insetBottomSpec(), containingSize.h),
    left: resolveInsetLength(style.insetLeftSpec(), containingSize.w)
  )

proc relativeOffset(style: ComputedStyle; containingSize: Size): Vec2 {.inline.} =
  if style.layout.position != pkRelative:
    return vec2(0, 0)
  let inset = style.resolvedInsets(containingSize)
  result.x =
    if inset.left.isSome: inset.left.get
    elif inset.right.isSome: -inset.right.get
    else: 0.0'f32
  result.y =
    if inset.top.isSome: inset.top.get
    elif inset.bottom.isSome: -inset.bottom.get
    else: 0.0'f32

proc clampSize(
    w, h: float32;
    style: ComputedStyle;
    constraints: Size;
    intrinsic: IntrinsicSizes
): Size =
  result = size(w, h)
  let minWidth = resolveLength(style.minWidthSpec(), constraints.w, intrinsic.minSize.w, intrinsic.maxSize.w)
  let maxWidth = resolveLength(style.maxWidthSpec(), constraints.w, intrinsic.minSize.w, intrinsic.maxSize.w)
  let minHeight = resolveLength(style.minHeightSpec(), constraints.h, intrinsic.minSize.h, intrinsic.maxSize.h)
  let maxHeight = resolveLength(style.maxHeightSpec(), constraints.h, intrinsic.minSize.h, intrinsic.maxSize.h)
  if maxWidth.isSome:
    result.w = min(result.w, maxWidth.get)
  if minWidth.isSome:
    result.w = max(result.w, minWidth.get)
  if maxHeight.isSome:
    result.h = min(result.h, maxHeight.get)
  if minHeight.isSome:
    result.h = max(result.h, minHeight.get)

proc applyAspect(
    w, h: float32;
    style: ComputedStyle;
    widthResolved, heightResolved: bool
): Size =
  result = size(w, h)
  if style.layout.aspectRatio.isNone:
    return
  let ratio = style.layout.aspectRatio.get
  if ratio <= 0:
    return
  if widthResolved and not heightResolved:
    result.h = result.w / ratio
  elif heightResolved and not widthResolved:
    result.w = result.h * ratio

proc parsedMaxLines(style: ComputedTextStyle): Option[int] =
  if style.maxLines.isNone:
    return none(int)
  try:
    let value = parseInt(style.maxLines.get.strip())
    some(max(0, value))
  except ValueError:
    none(int)

proc textLimitedByMaxLines(text: string; style: ComputedTextStyle): string =
  let maxLines = style.parsedMaxLines()
  if maxLines.isNone:
    return text
  if maxLines.get == 0:
    return ""
  let lines = text.splitLines()
  if lines.len <= maxLines.get:
    return text
  lines[0 ..< maxLines.get].join("\n")

proc parsedZoom(style: ComputedStyle): float32 =
  if style.visual.zoom.isNone:
    return 1.0'f32
  try:
    let value = parseFloat(style.visual.zoom.get.strip()).float32
    if value > 0.0'f32: value else: 1.0'f32
  except ValueError:
    1.0'f32

proc unwrappedTextSize(
    text: string;
    style: ComputedTextStyle;
    textEngine: TextEngine;
    fontRegistry: FontRegistry
): Size =
  textEngine.measure(TextMeasureInput(
    text: text,
    style: style,
    maxWidth: none(float32),
    fonts: fontRegistry
  ))

proc minContentTextWidth(
    text: string;
    style: ComputedTextStyle;
    textEngine: TextEngine;
    fontRegistry: FontRegistry
): float32 =
  ## Latin words are unbreakable runs. Non-ASCII runes are treated as break
  ## opportunities until the text engine exposes language-aware line breaks.
  var asciiRun = ""
  for rune in text.runes:
    let value = int(rune)
    let isAsciiSpace = value in [9, 10, 13, 32]
    if value <= 127 and not isAsciiSpace:
      asciiRun.add char(value)
      continue
    if asciiRun.len > 0:
      result = max(result, unwrappedTextSize(asciiRun, style, textEngine, fontRegistry).w)
      asciiRun.setLen(0)
    if value > 127:
      result = max(result, unwrappedTextSize($rune, style, textEngine, fontRegistry).w)
  if asciiRun.len > 0:
    result = max(result, unwrappedTextSize(asciiRun, style, textEngine, fontRegistry).w)

proc measureIntrinsicNode(
    tree: Tree;
    styles: ResolvedTree;
    id: NodeId;
    textEngine: TextEngine;
    fontRegistry: FontRegistry;
    measured: var seq[bool];
    output: var seq[IntrinsicSizes]
): IntrinsicSizes =
  if measured[id.nodeIndex]:
    return output[id.nodeIndex]
  measured[id.nodeIndex] = true
  let node = tree.nodes[id.nodeIndex]
  let style {.cursor.} = styles.styles[id.nodeIndex]
  if style.layout.display == dkNone:
    result = IntrinsicSizes(minSize: size(0, 0), maxSize: size(0, 0))
    output[id.nodeIndex] = result
    return

  if node.kind == nkText:
    let measuredText = textLimitedByMaxLines(node.text, style.text)
    let maximum = unwrappedTextSize(measuredText, style.text, textEngine, fontRegistry)
    let minimum = size(
      minContentTextWidth(measuredText, style.text, textEngine, fontRegistry),
      maximum.h
    )
    result = IntrinsicSizes(minSize: minimum, maxSize: maximum)
  elif node.kind == nkImage:
    let imageSize = size(max(0.0'f32, node.imageWidth), max(0.0'f32, node.imageHeight))
    result = IntrinsicSizes(minSize: imageSize, maxSize: imageSize)
  else:
    let pad = paddingOf(style)
    let orderedChildren = node.childrenInLayoutOrder(styles)
    var childCount = 0
    for child in orderedChildren:
      let childStyle {.cursor.} = styles.styles[child.nodeIndex]
      if childStyle.isAbsolute or childStyle.layout.display == dkNone:
        continue
      let childIntrinsic = measureIntrinsicNode(
        tree, styles, child, textEngine, fontRegistry, measured, output
      )
      let margin = marginOf(childStyle)
      let childMin = size(
        childIntrinsic.minSize.w + margin.left + margin.right,
        childIntrinsic.minSize.h + margin.top + margin.bottom
      )
      let childMax = size(
        childIntrinsic.maxSize.w + margin.left + margin.right,
        childIntrinsic.maxSize.h + margin.top + margin.bottom
      )
      if style.layout.direction == fdRow:
        result.minSize.w += childMin.w
        result.maxSize.w += childMax.w
        result.minSize.h = max(result.minSize.h, childMin.h)
        result.maxSize.h = max(result.maxSize.h, childMax.h)
      else:
        result.minSize.w = max(result.minSize.w, childMin.w)
        result.maxSize.w = max(result.maxSize.w, childMax.w)
        result.minSize.h += childMin.h
        result.maxSize.h += childMax.h
      inc childCount
    if childCount > 1:
      let gaps = style.mainGapOf(size(0, 0)) * (childCount - 1).float32
      if style.layout.direction == fdRow:
        result.minSize.w += gaps
        result.maxSize.w += gaps
      else:
        result.minSize.h += gaps
        result.maxSize.h += gaps
    result.minSize.w += pad.left + pad.right
    result.maxSize.w += pad.left + pad.right
    result.minSize.h += pad.top + pad.bottom
    result.maxSize.h += pad.top + pad.bottom

  # Cache raw content measurements. The value returned to the parent below may
  # include this node's explicit size, but `content` and flex-basis content
  # must still be able to read the unmodified intrinsic dimensions.
  output[id.nodeIndex] = result

  let widthSpec = style.widthSpec()
  let heightSpec = style.heightSpec()
  let width =
    if widthSpec.isSome and widthSpec.get.kind in {ukPx, ukContent, ukMinContent, ukMaxContent}:
      resolveLength(widthSpec, result.maxSize.w, result.minSize.w, result.maxSize.w)
    else:
      none(float32)
  let height =
    if heightSpec.isSome and heightSpec.get.kind in {ukPx, ukContent, ukMinContent, ukMaxContent}:
      resolveLength(heightSpec, result.maxSize.h, result.minSize.h, result.maxSize.h)
    else:
      none(float32)
  if width.isSome:
    result.minSize.w = width.get
    result.maxSize.w = width.get
  if height.isSome:
    result.minSize.h = height.get
    result.maxSize.h = height.get

proc computeIntrinsicSizes(
    tree: Tree;
    styles: ResolvedTree;
    root: NodeId;
    textEngine: TextEngine;
    fontRegistry: FontRegistry
): seq[IntrinsicSizes] =
  result = newSeq[IntrinsicSizes](tree.nodes.len)
  var measured = newSeq[bool](tree.nodes.len)
  var required = false
  for index in 0 ..< styles.styles.len:
    let style {.cursor.} = styles.styles[index]
    if style.layout.sizing.isNil:
      continue
    let sizing = style.layout.sizing[]
    for value in [
      sizing.width, sizing.height,
      sizing.minWidth, sizing.maxWidth,
      sizing.minHeight, sizing.maxHeight,
      sizing.flexBasis
    ]:
      if value.isSome and value.get.kind in {
          ukContent, ukMinContent, ukMaxContent, ukFitContent
      }:
        required = true
        break
    if required:
      break
  if required:
    discard measureIntrinsicNode(
      tree, styles, root, textEngine, fontRegistry, measured, result
    )
  else:
    # Scroll containers need the automatic minimum size of shrinkable flex
    # children so overflow is not erased by the flex pass. Measure only those
    # subtrees; one scroll container must not force an intrinsic pass over the
    # entire application.
    for nodeIndex, node in tree.nodes:
      if not node.alive:
        continue
      let parentStyle {.cursor.} = styles.styles[nodeIndex]
      if parentStyle.layout.overflowX notin {omAuto, omScroll} and
          parentStyle.layout.overflowY notin {omAuto, omScroll}:
        continue
      for child in node.children:
        if styles.styles[child.nodeIndex].layout.flexShrink > 0:
          discard measureIntrinsicNode(
            tree, styles, child, textEngine, fontRegistry, measured, result
          )

proc layoutNode(
    tree: Tree;
    styles: ResolvedTree;
    id: NodeId;
    x, y: float32;
    constraints: Size;
    textEngine: TextEngine;
    fontRegistry: FontRegistry;
    intrinsics: seq[IntrinsicSizes];
    output: var LayoutResult
): Size =
  let node = tree.nodes[id.nodeIndex]
  let style {.cursor.} = styles.styles[id.nodeIndex]
  let intrinsic = intrinsics[id.nodeIndex]
  let resolvedWidth = resolveLength(
    style.widthSpec(), constraints.w, intrinsic.minSize.w, intrinsic.maxSize.w
  )
  let resolvedHeight = resolveLength(
    style.heightSpec(), constraints.h, intrinsic.minSize.h, intrinsic.maxSize.h
  )
  let firstBox = output.boxes.len

  if style.layout.display == dkNone:
    output.boxes.add LayoutBox(
      node: id,
      rect: rect(x, y, 0, 0),
      zIndex: style.layout.zIndex
    )
    return size(0, 0)

  if node.kind == nkText:
    let measuredText = textLimitedByMaxLines(node.text, style.text)
    let measured = textEngine.measure(TextMeasureInput(
      text: measuredText,
      style: style.text,
      maxWidth: some(if resolvedWidth.isSome: resolvedWidth.get else: constraints.w),
      fonts: fontRegistry
    ))
    let w = if resolvedWidth.isSome: resolvedWidth.get else: measured.w
    let h = if resolvedHeight.isSome: resolvedHeight.get else: measured.h
    let aspect = applyAspect(w, h, style, resolvedWidth.isSome, resolvedHeight.isSome)
    let clamped = clampSize(aspect.w, aspect.h, style, constraints, intrinsic)
    output.boxes.add LayoutBox(
      node: id,
      rect: rect(x, y, clamped.w, clamped.h),
      zIndex: style.layout.zIndex
    )
    let zoom = parsedZoom(style)
    if zoom != 1.0'f32:
      output.scaleBoxes(firstBox, output.boxes.len - firstBox, x, y, zoom)
      return size(clamped.w * zoom, clamped.h * zoom)
    return clamped

  if node.kind == nkImage:
    let intrinsicW = max(0.0'f32, node.imageWidth)
    let intrinsicH = max(0.0'f32, node.imageHeight)
    let w =
      if resolvedWidth.isSome: resolvedWidth.get
      elif intrinsicW > 0: intrinsicW
      else: 0.0'f32
    let h =
      if resolvedHeight.isSome: resolvedHeight.get
      elif intrinsicH > 0: intrinsicH
      else: 0.0'f32
    let aspect = applyAspect(w, h, style, resolvedWidth.isSome, resolvedHeight.isSome)
    let clamped = clampSize(aspect.w, aspect.h, style, constraints, intrinsic)
    output.boxes.add LayoutBox(
      node: id,
      rect: rect(x, y, clamped.w, clamped.h),
      zIndex: style.layout.zIndex
    )
    let zoom = parsedZoom(style)
    if zoom != 1.0'f32:
      output.scaleBoxes(firstBox, output.boxes.len - firstBox, x, y, zoom)
      return size(clamped.w * zoom, clamped.h * zoom)
    return clamped

  let pad = paddingOf(style)
  let childConstraints = size(
    max(0.0'f32, (if resolvedWidth.isSome: resolvedWidth.get else: constraints.w) - pad.left - pad.right),
    max(0.0'f32, (if resolvedHeight.isSome: resolvedHeight.get else: constraints.h) - pad.top - pad.bottom)
  )
  let mainAxisResolved =
    if style.layout.direction == fdRow: resolvedWidth.isSome
    else: resolvedHeight.isSome
  let measuredMainGap =
    if mainAxisResolved: style.mainGapOf(childConstraints)
    else: style.mainGapOf(size(0, 0))

  var children: seq[ChildPlacement]
  var absoluteChildren: seq[ChildPlacement]
  var contentMain = 0.0'f32
  var contentCross = 0.0'f32
  var first = true
  let orderedChildren = node.childrenInLayoutOrder(styles)
  for child in orderedChildren:
    let childStyle {.cursor.} = styles.styles[child.nodeIndex]
    if childStyle.layout.display == dkNone:
      continue
    if childStyle.isAbsolute:
      let firstBox = output.boxes.len
      let childSize = layoutNode(
        tree,
        styles,
        child,
        0,
        0,
        childConstraints,
        textEngine,
        fontRegistry,
        intrinsics,
        output
      )
      absoluteChildren.add ChildPlacement(
        node: child,
        size: childSize,
        minMain: 0,
        margin: marginOf(childStyle),
        firstBox: firstBox,
        boxCount: output.boxes.len - firstBox
      )
      continue

    if not first:
      contentMain += measuredMainGap
    first = false

    let firstBox = output.boxes.len
    var childSize = layoutNode(
      tree,
      styles,
      child,
      0,
      0,
      childConstraints,
      textEngine,
      fontRegistry,
      intrinsics,
      output
    )
    let basisSpec = childStyle.flexBasisSpec()
    let childIntrinsic = intrinsics[child.nodeIndex]
    let basis =
      if basisSpec.isSome and basisSpec.get.kind == ukPercent and not mainAxisResolved:
        none(float32)
      elif style.layout.direction == fdRow:
        resolveLength(
          basisSpec, childConstraints.w,
          childIntrinsic.minSize.w, childIntrinsic.maxSize.w
        )
      else:
        resolveLength(
          basisSpec, childConstraints.h,
          childIntrinsic.minSize.h, childIntrinsic.maxSize.h
        )
    if basis.isSome:
      if style.layout.direction == fdRow:
        childSize.w = basis.get
      else:
        childSize.h = basis.get
      output.setMainSize(
        firstBox, output.boxes.len - firstBox,
        child, style.layout.direction, basis.get
      )
    let margin = marginOf(childStyle)
    let outerW = childSize.w + margin.left + margin.right
    let outerH = childSize.h + margin.top + margin.bottom
    children.add ChildPlacement(
      node: child,
      size: childSize,
      minMain: childStyle.flexMinimumMain(
        style.layout.direction, childConstraints, childIntrinsic
      ),
      margin: margin,
      firstBox: firstBox,
      boxCount: output.boxes.len - firstBox
    )

    if style.layout.direction == fdRow:
      contentMain += outerW
      contentCross = max(contentCross, outerH)
    else:
      contentMain += outerH
      contentCross = max(contentCross, outerW)

  let naturalW =
    if style.layout.direction == fdRow:
      contentMain + pad.left + pad.right
    else:
      contentCross + pad.left + pad.right
  let naturalH =
    if style.layout.direction == fdRow:
      contentCross + pad.top + pad.bottom
    else:
      contentMain + pad.top + pad.bottom
  let rawW = if resolvedWidth.isSome: resolvedWidth.get else: naturalW
  let rawH = if resolvedHeight.isSome: resolvedHeight.get else: naturalH
  let aspect = applyAspect(rawW, rawH, style, resolvedWidth.isSome, resolvedHeight.isSome)
  let clamped = clampSize(aspect.w, aspect.h, style, constraints, intrinsic)

  let availableMain =
    if style.layout.direction == fdRow:
      max(0.0'f32, clamped.w - pad.left - pad.right)
    else:
      max(0.0'f32, clamped.h - pad.top - pad.bottom)
  let availableCross =
    if style.layout.direction == fdRow:
      max(0.0'f32, clamped.h - pad.top - pad.bottom)
    else:
      max(0.0'f32, clamped.w - pad.left - pad.right)
  let containingContentSize = size(
    max(0.0'f32, clamped.w - pad.left - pad.right),
    max(0.0'f32, clamped.h - pad.top - pad.bottom)
  )
  let mainGap = style.mainGapOf(containingContentSize)
  if children.len > 1 and mainGap != measuredMainGap:
    contentMain += (mainGap - measuredMainGap) * (children.len - 1).float32
  let freeMain = max(0.0'f32, availableMain - contentMain)
  let deficitMain = max(0.0'f32, contentMain - availableMain)
  if freeMain > 0 and children.len > 0:
    var totalGrow = 0.0'f32
    for child in children:
      totalGrow += styles.styles[child.node.nodeIndex].layout.flexGrow
    if totalGrow > 0:
      for child in children.mitems:
        let grow = styles.styles[child.node.nodeIndex].layout.flexGrow
        if grow > 0:
          let delta = freeMain * (grow / totalGrow)
          if style.layout.direction == fdRow:
            child.size.w += delta
            output.setMainSize(child.firstBox, child.boxCount, child.node, style.layout.direction, child.size.w)
          else:
            child.size.h += delta
            output.setMainSize(child.firstBox, child.boxCount, child.node, style.layout.direction, child.size.h)
      contentMain += freeMain
  elif deficitMain > 0 and children.len > 0:
    var frozen = newSeq[bool](children.len)
    var remainingDeficit = deficitMain
    var totalRemoved = 0.0'f32
    for _ in 0 .. children.len:
      if remainingDeficit <= 0.001'f32:
        break
      var totalShrink = 0.0'f32
      for index, child in children:
        if frozen[index]:
          continue
        let childStyle {.cursor.} = styles.styles[child.node.nodeIndex]
        let current = if style.layout.direction == fdRow: child.size.w else: child.size.h
        if current <= child.minMain + 0.001'f32 or childStyle.layout.flexShrink <= 0:
          frozen[index] = true
          continue
        totalShrink += childStyle.layout.flexShrink * current
      if totalShrink <= 0:
        break

      var removedThisPass = 0.0'f32
      for index in 0 ..< children.len:
        if frozen[index]:
          continue
        let childStyle {.cursor.} = styles.styles[children[index].node.nodeIndex]
        let current =
          if style.layout.direction == fdRow: children[index].size.w
          else: children[index].size.h
        let requested = remainingDeficit *
          ((childStyle.layout.flexShrink * current) / totalShrink)
        let capacity = max(0.0'f32, current - children[index].minMain)
        let removed = min(requested, capacity)
        let next = current - removed
        if style.layout.direction == fdRow:
          children[index].size.w = next
        else:
          children[index].size.h = next
        output.setMainSize(
          children[index].firstBox,
          children[index].boxCount,
          children[index].node,
          style.layout.direction,
          next
        )
        removedThisPass += removed
        if capacity <= requested + 0.001'f32:
          frozen[index] = true
      if removedThisPass <= 0.001'f32:
        break
      totalRemoved += removedThisPass
      remainingDeficit = max(0.0'f32, remainingDeficit - removedThisPass)
    contentMain -= totalRemoved

  let freeMainAfterFlex = max(0.0'f32, availableMain - contentMain)
  var cursorMain =
    case style.layout.justifyContent
    of jcStart, jcSpaceBetween:
      0.0'f32
    of jcCenter:
      freeMainAfterFlex / 2.0'f32
    of jcEnd:
      freeMainAfterFlex
  let extraGap =
    if style.layout.justifyContent == jcSpaceBetween and children.len > 1:
      freeMainAfterFlex / (children.len - 1).float32
    else:
      0.0'f32

  for index, child in children:
    let childStyle {.cursor.} = styles.styles[child.node.nodeIndex]
    let outerMain =
      if style.layout.direction == fdRow:
        child.size.w + child.margin.left + child.margin.right
      else:
        child.size.h + child.margin.top + child.margin.bottom
    let outerCross =
      if style.layout.direction == fdRow:
        child.size.h + child.margin.top + child.margin.bottom
      else:
        child.size.w + child.margin.left + child.margin.right
    let effectiveAlign =
      if childStyle.layout.alignSelf.isSome:
        childStyle.layout.alignSelf.get
      else:
        style.layout.alignItems
    let crossOffset =
      case effectiveAlign
      of aiStart, aiStretch:
        0.0'f32
      of aiCenter:
        max(0.0'f32, (availableCross - outerCross) / 2.0'f32)
      of aiEnd:
        max(0.0'f32, availableCross - outerCross)

    if style.layout.direction == fdRow:
      let targetX = x + pad.left + cursorMain + child.margin.left
      let targetY = y + pad.top + crossOffset + child.margin.top
      let offset = childStyle.relativeOffset(containingContentSize)
      output.shiftBoxes(child.firstBox, child.boxCount, targetX + offset.x, targetY + offset.y)
      if effectiveAlign == aiStretch:
        output.stretchOwnBox(
          child.firstBox,
          child.boxCount,
          child.node,
          none(float32),
          some(max(0.0'f32, availableCross - child.margin.top - child.margin.bottom))
        )
    else:
      let targetX = x + pad.left + crossOffset + child.margin.left
      let targetY = y + pad.top + cursorMain + child.margin.top
      let offset = childStyle.relativeOffset(containingContentSize)
      output.shiftBoxes(child.firstBox, child.boxCount, targetX + offset.x, targetY + offset.y)
      if effectiveAlign == aiStretch:
        output.stretchOwnBox(
          child.firstBox,
          child.boxCount,
          child.node,
          some(max(0.0'f32, availableCross - child.margin.left - child.margin.right)),
          none(float32)
        )

    cursorMain += outerMain
    if index < children.high:
      cursorMain += mainGap + extraGap

  for child in absoluteChildren:
    let childStyle {.cursor.} = styles.styles[child.node.nodeIndex]
    let contentX = x + pad.left
    let contentY = y + pad.top
    let contentW = max(0.0'f32, clamped.w - pad.left - pad.right)
    let contentH = max(0.0'f32, clamped.h - pad.top - pad.bottom)
    let inset = childStyle.resolvedInsets(size(contentW, contentH))
    let outerW = child.size.w + child.margin.left + child.margin.right
    let outerH = child.size.h + child.margin.top + child.margin.bottom
    let targetX =
      if inset.left.isSome:
        contentX + inset.left.get + child.margin.left
      elif inset.right.isSome:
        contentX + contentW - inset.right.get - outerW + child.margin.left
      else:
        contentX + child.margin.left
    let targetY =
      if inset.top.isSome:
        contentY + inset.top.get + child.margin.top
      elif inset.bottom.isSome:
        contentY + contentH - inset.bottom.get - outerH + child.margin.top
      else:
        contentY + child.margin.top
    output.shiftBoxes(child.firstBox, child.boxCount, targetX, targetY)

  output.boxes.add LayoutBox(
    node: id,
    rect: rect(x, y, clamped.w, clamped.h),
    zIndex: style.layout.zIndex
  )
  let zoom = parsedZoom(style)
  if style.layout.overflowX in {omAuto, omScroll} or
      style.layout.overflowY in {omAuto, omScroll}:
    let contentSize =
      if style.layout.direction == fdRow:
        size(contentMain, contentCross)
      else:
        size(contentCross, contentMain)
    output.overflowMetrics.add LayoutOverflowMetrics(
      node: id,
      viewportSize: size(
        containingContentSize.w * zoom,
        containingContentSize.h * zoom
      ),
      contentSize: size(contentSize.w * zoom, contentSize.h * zoom)
    )
  if zoom != 1.0'f32:
    output.scaleBoxes(firstBox, output.boxes.len - firstBox, x, y, zoom)
    return size(clamped.w * zoom, clamped.h * zoom)
  clamped

proc computeLayout*(
    tree: Tree;
    styles: ResolvedTree;
    constraints: Size;
    textEngine = debugTextEngine();
    fontRegistry = initFontRegistry()
): LayoutResult =
  result.boxes = @[]
  result.overflowMetrics = @[]
  if tree.root.isSome:
    let intrinsics = computeIntrinsicSizes(tree, styles, tree.root.get, textEngine, fontRegistry)
    discard layoutNode(
      tree, styles, tree.root.get, 0, 0, constraints,
      textEngine, fontRegistry, intrinsics, result
    )
  result.rebuildBoxIndices(tree.nodes.len)

proc relayoutSubtree*(
    tree: Tree;
    styles: ResolvedTree;
    root: NodeId;
    layout: var LayoutResult;
    textEngine = debugTextEngine();
    fontRegistry = initFontRegistry()
): bool =
  if root.nodeIndex < 0 or root.nodeIndex >= tree.nodes.len:
    return false

  let oldBoxIndices = layout.layoutBoxIndices(tree.nodes.len)
  var relayoutRoot = root
  var subtree: LayoutResult

  while true:
    let anchorIndex = oldBoxIndices.boxIndexFor(relayoutRoot)
    if anchorIndex < 0:
      return false
    let anchor = layout.boxes[anchorIndex].rect
    subtree = LayoutResult(boxes: @[], overflowMetrics: @[])
    let intrinsics = computeIntrinsicSizes(
      tree, styles, relayoutRoot, textEngine, fontRegistry
    )
    discard layoutNode(
      tree,
      styles,
      relayoutRoot,
      anchor.x,
      anchor.y,
      size(anchor.w, anchor.h),
      textEngine,
      fontRegistry,
      intrinsics,
      subtree
    )
    subtree.rebuildBoxIndices(tree.nodes.len)

    let newRootIndex = subtree.boxIndices.boxIndexFor(relayoutRoot)
    if newRootIndex < 0:
      return false
    let nextRect = subtree.boxes[newRootIndex].rect
    let sizeChanged =
      abs(nextRect.w - anchor.w) > 0.001'f32 or
      abs(nextRect.h - anchor.h) > 0.001'f32
    let parent = tree.nodes[relayoutRoot.nodeIndex].parent
    if not sizeChanged or parent.isNone:
      break
    relayoutRoot = parent.get

  var replaced = newSeq[bool](tree.nodes.len)
  var pending = @[relayoutRoot]
  while pending.len > 0:
    let id = pending.pop()
    if id.nodeIndex < 0 or id.nodeIndex >= replaced.len or replaced[id.nodeIndex]:
      continue
    replaced[id.nodeIndex] = true
    for child in tree.nodes[id.nodeIndex].children:
      pending.add child

  var nextBoxes = newSeqOfCap[LayoutBox](layout.boxes.len - 1 + subtree.boxes.len)
  for box in layout.boxes:
    if box.node.nodeIndex < 0 or box.node.nodeIndex >= replaced.len or
        not replaced[box.node.nodeIndex]:
      nextBoxes.add box
  nextBoxes.add subtree.boxes
  layout.boxes = nextBoxes

  var nextOverflowMetrics = newSeqOfCap[LayoutOverflowMetrics](
    layout.overflowMetrics.len + subtree.overflowMetrics.len
  )
  for metrics in layout.overflowMetrics:
    if metrics.node.nodeIndex < 0 or metrics.node.nodeIndex >= replaced.len or
        not replaced[metrics.node.nodeIndex]:
      nextOverflowMetrics.add metrics
  nextOverflowMetrics.add subtree.overflowMetrics
  layout.overflowMetrics = nextOverflowMetrics
  layout.rebuildBoxIndices(tree.nodes.len)
  true
