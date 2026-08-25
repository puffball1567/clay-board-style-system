import std/[algorithm, options, strutils, unicode]
import ../core/[computed_style, geometry, node, style_resolver, style_value]
import ../text/font_registry
import ../text/text_engine
import ./overflow_geometry

type
  LayoutBox* = object
    node*: NodeId
    rect*: Rect
    padding*: EdgeSizes
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
    firstBaseline: float32
    laidOutMain: float32
    minMain: float32
    maxMain: float32
    margin: EdgeSizes
    firstBox: int
    boxCount: int
    firstOverflowMetric: int
    overflowMetricCount: int

  FlexLine = object
    firstChild: int
    pastChild: int
    mainSize: float32
    crossSize: float32
    firstBaseline: float32

  OrderedChild = object
    node: NodeId
    order: int

  IntrinsicSizes = object
    minSize: Size
    maxSize: Size

  LayoutMetrics = object
    size: Size
    firstBaseline: float32

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

template withLayoutBoxIndices*(
    layout: LayoutResult;
    nodeCount: int;
    indices: untyped;
    body: untyped
): untyped =
  ## Borrows the retained index on the hot path. `layoutBoxIndices` remains the
  ## owning compatibility API for callers that need to keep or mutate a copy.
  block:
    if layout.boxIndices.len == nodeCount:
      let indices {.cursor.} = layout.boxIndices
      body
    else:
      let indices = layout.layoutBoxIndices(nodeCount)
      body

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

proc resolveSpacing(spec: Option[LengthValue]; fallback, reference: float32;
    nonNegative: bool): float32 =
  result = fallback
  if spec.isSome:
    case spec.get.kind
    of ukPx:
      result = spec.get.value
    of ukPercent:
      result = reference * spec.get.value / 100.0'f32
    else:
      discard
  if nonNegative:
    result = max(0.0'f32, result)

proc paddingOf(style: ComputedStyle; containingInlineSize = 0.0'f32): EdgeSizes =
  result =
    if style.box.padding.isSome: style.box.padding.get
    else: edges(0)
  if not style.layout.sizing.isNil:
    result.top = resolveSpacing(style.layout.sizing.paddingTop, result.top,
        containingInlineSize, true)
    result.right = resolveSpacing(style.layout.sizing.paddingRight, result.right,
        containingInlineSize, true)
    result.bottom = resolveSpacing(style.layout.sizing.paddingBottom, result.bottom,
        containingInlineSize, true)
    result.left = resolveSpacing(style.layout.sizing.paddingLeft, result.left,
        containingInlineSize, true)
  let gutter = style.scrollbarGutterInsets()
  result.top += gutter.top
  result.right += gutter.right
  result.bottom += gutter.bottom
  result.left += gutter.left

proc borderOf(style: ComputedStyle): EdgeSizes =
  let widths = style.box.borderWidths
  result.top =
    if style.box.borderSideVisible.top: max(0.0'f32, widths.top)
    else: 0.0'f32
  result.right =
    if style.box.borderSideVisible.right: max(0.0'f32, widths.right)
    else: 0.0'f32
  result.bottom =
    if style.box.borderSideVisible.bottom: max(0.0'f32, widths.bottom)
    else: 0.0'f32
  result.left =
    if style.box.borderSideVisible.left: max(0.0'f32, widths.left)
    else: 0.0'f32

proc combinedEdges(first, second: EdgeSizes): EdgeSizes {.inline.} =
  EdgeSizes(
    top: first.top + second.top,
    right: first.right + second.right,
    bottom: first.bottom + second.bottom,
    left: first.left + second.left
  )

proc horizontal(edges: EdgeSizes): float32 {.inline.} =
  edges.left + edges.right

proc vertical(edges: EdgeSizes): float32 {.inline.} =
  edges.top + edges.bottom

proc isRow(direction: FlexDirection): bool {.inline.} =
  direction in {fdRow, fdRowReverse}

proc isMainReverse(direction: FlexDirection): bool {.inline.} =
  direction in {fdRowReverse, fdColumnReverse}

proc mainSize(value: Size; direction: FlexDirection): float32 {.inline.} =
  if direction.isRow: value.w else: value.h

proc crossSize(value: Size; direction: FlexDirection): float32 {.inline.} =
  if direction.isRow: value.h else: value.w

proc setMainSize(value: var Size; direction: FlexDirection; next: float32) {.inline.} =
  if direction.isRow:
    value.w = next
  else:
    value.h = next

proc mainMargin(value: EdgeSizes; direction: FlexDirection): float32 {.inline.} =
  if direction.isRow:
    value.left + value.right
  else:
    value.top + value.bottom

proc crossMargin(value: EdgeSizes; direction: FlexDirection): float32 {.inline.} =
  if direction.isRow:
    value.top + value.bottom
  else:
    value.left + value.right

proc outerMain(child: ChildPlacement; direction: FlexDirection): float32 {.inline.} =
  child.size.mainSize(direction) + child.margin.mainMargin(direction)

proc outerCross(child: ChildPlacement; direction: FlexDirection): float32 {.inline.} =
  child.size.crossSize(direction) + child.margin.crossMargin(direction)

proc effectiveAlignment(
    alignSelf: Option[AlignItems];
    alignItems: AlignItems
): AlignItems {.inline.} =
  if alignSelf.isSome:
    alignSelf.get
  else:
    alignItems

proc toBorderBox(
    value: float32;
    extra: float32;
    boxSizing: BoxSizing
): float32 {.inline.} =
  case boxSizing
  of bsContentBox:
    max(0.0'f32, value) + extra
  of bsBorderBox:
    max(extra, value)

proc usesSelectedSizingBox(value: Option[LengthValue]): bool {.inline.} =
  value.isSome and value.get.kind in {ukPx, ukPercent, ukFill}

proc marginOf(style: ComputedStyle; containingInlineSize = 0.0'f32): EdgeSizes =
  result =
    if style.box.margin.isSome: style.box.margin.get
    else: edges(0)
  if not style.layout.sizing.isNil:
    result.top = resolveSpacing(style.layout.sizing.marginTop, result.top,
        containingInlineSize, false)
    result.right = resolveSpacing(style.layout.sizing.marginRight, result.right,
        containingInlineSize, false)
    result.bottom = resolveSpacing(style.layout.sizing.marginBottom, result.bottom,
        containingInlineSize, false)
    result.left = resolveSpacing(style.layout.sizing.marginLeft, result.left,
        containingInlineSize, false)

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
    output.boxes[index].padding.top *= factor
    output.boxes[index].padding.right *= factor
    output.boxes[index].padding.bottom *= factor
    output.boxes[index].padding.left *= factor

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
  if direction.isRow:
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
  if style.layout.direction.isRow:
    if not style.layout.sizing.isNil and style.layout.sizing.columnGap.isSome:
      return style.layout.sizing.columnGap
    return style.gapSpec(fixedLength(style.layout.columnGap))
  if not style.layout.sizing.isNil and style.layout.sizing.rowGap.isSome:
    return style.layout.sizing.rowGap
  style.gapSpec(fixedLength(style.layout.rowGap))

proc crossGapSpec(style: ComputedStyle): Option[LengthValue] =
  if style.layout.direction.isRow:
    if not style.layout.sizing.isNil and style.layout.sizing.rowGap.isSome:
      return style.layout.sizing.rowGap
    return style.gapSpec(fixedLength(style.layout.rowGap))
  if not style.layout.sizing.isNil and style.layout.sizing.columnGap.isSome:
    return style.layout.sizing.columnGap
  style.gapSpec(fixedLength(style.layout.columnGap))

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
  of ukEm, ukRem, ukVw, ukVh, ukVmin, ukVmax, ukLh, ukRlh,
      ukEx, ukCh, ukRex, ukRch:
    none(float32)

proc resolveSizingLength(
    value: Option[LengthValue];
    reference, intrinsicMin, intrinsicMax, extra: float32;
    boxSizing: BoxSizing
): Option[float32] =
  result = resolveLength(value, reference, intrinsicMin, intrinsicMax)
  if result.isSome and value.usesSelectedSizingBox:
    result = some(toBorderBox(result.get, extra, boxSizing))

proc flexMinimumMain(
    style: ComputedStyle;
    direction: FlexDirection;
    constraints: Size;
    intrinsic: IntrinsicSizes;
    boxEdges: EdgeSizes
): float32 =
  let reference = if direction.isRow: constraints.w else: constraints.h
  let intrinsicMin = if direction.isRow: intrinsic.minSize.w else: intrinsic.minSize.h
  let intrinsicMax = if direction.isRow: intrinsic.maxSize.w else: intrinsic.maxSize.h
  let minimumSpec = if direction.isRow: style.minWidthSpec() else: style.minHeightSpec()
  let extra = if direction.isRow: boxEdges.horizontal else: boxEdges.vertical
  if minimumSpec.isSome and minimumSpec.get.kind != ukAuto:
    let resolved = resolveSizingLength(
      minimumSpec, reference, intrinsicMin, intrinsicMax,
      extra, style.layout.boxSizing
    )
    return if resolved.isSome: resolved.get else: 0.0'f32

  let overflow = if direction.isRow: style.layout.overflowX else: style.layout.overflowY
  if overflow in {omAuto, omScroll}:
    return 0.0'f32

  # CSS automatic minimum size is content based for non-scrollable flex
  # items, capped by a definite preferred size when one exists.
  result = max(0.0'f32, intrinsicMin)
  let preferredSpec = if direction.isRow: style.widthSpec() else: style.heightSpec()
  let preferred = resolveSizingLength(
    preferredSpec, reference, intrinsicMin, intrinsicMax,
    extra, style.layout.boxSizing
  )
  if preferred.isSome:
    result = min(result, preferred.get)

proc flexMaximumMain(
    style: ComputedStyle;
    direction: FlexDirection;
    constraints: Size;
    intrinsic: IntrinsicSizes;
    boxEdges: EdgeSizes
): float32 =
  let reference = constraints.mainSize(direction)
  let intrinsicMin = intrinsic.minSize.mainSize(direction)
  let intrinsicMax = intrinsic.maxSize.mainSize(direction)
  let maximumSpec =
    if direction.isRow: style.maxWidthSpec()
    else: style.maxHeightSpec()
  let extra =
    if direction.isRow: boxEdges.horizontal
    else: boxEdges.vertical
  let maximum = resolveSizingLength(
    maximumSpec,
    reference,
    intrinsicMin,
    intrinsicMax,
    extra,
    style.layout.boxSizing
  )
  if maximum.isSome: maximum.get else: high(float32)

proc mainGapOf(style: ComputedStyle; contentSize: Size): float32 =
  let reference =
    if style.layout.direction.isRow: contentSize.w
    else: contentSize.h
  let resolved = resolveLength(style.mainGapSpec(), reference, 0, 0)
  if resolved.isSome: resolved.get else: 0.0'f32

proc crossGapOf(style: ComputedStyle; contentSize: Size): float32 =
  let reference =
    if style.layout.direction.isRow: contentSize.h
    else: contentSize.w
  let resolved = resolveLength(style.crossGapSpec(), reference, 0, 0)
  if resolved.isSome: resolved.get else: 0.0'f32

proc refreshLineMetrics(
    line: var FlexLine;
    children: openArray[ChildPlacement];
    direction: FlexDirection;
    gap: float32
) =
  line.mainSize = 0
  line.crossSize = 0
  line.firstBaseline = -1
  for index in line.firstChild ..< line.pastChild:
    if index > line.firstChild:
      line.mainSize += gap
    line.mainSize += children[index].outerMain(direction)
    line.crossSize = max(line.crossSize, children[index].outerCross(direction))

proc collectFlexLines(
    children: openArray[ChildPlacement];
    direction: FlexDirection;
    wrapping: FlexWrap;
    mainIsDefinite: bool;
    availableMain, gap: float32
): seq[FlexLine] =
  if children.len == 0:
    return

  let canWrap = wrapping != fwNoWrap and mainIsDefinite
  var line = FlexLine(firstChild: 0, pastChild: 0, firstBaseline: -1)
  for index, child in children:
    let itemMain = child.outerMain(direction)
    let nextMain =
      if line.pastChild == line.firstChild: itemMain
      else: line.mainSize + gap + itemMain
    if canWrap and line.pastChild > line.firstChild and
        nextMain > availableMain + 0.001'f32:
      result.add line
      line = FlexLine(
        firstChild: index,
        pastChild: index + 1,
        mainSize: itemMain,
        crossSize: child.outerCross(direction),
        firstBaseline: -1
      )
    else:
      if line.pastChild > line.firstChild:
        line.mainSize += gap
      line.mainSize += itemMain
      line.crossSize = max(line.crossSize, child.outerCross(direction))
      line.pastChild = index + 1
  result.add line

proc resolveLineBaselines(
    lines: var seq[FlexLine];
    children: openArray[ChildPlacement];
    styles: ResolvedTree;
    parentAlign: AlignItems;
    direction: FlexDirection;
    hasBaselineAlignment: bool
) =
  if not direction.isRow or not hasBaselineAlignment:
    return
  for line in lines.mitems:
    var baseline = -1.0'f32
    var belowBaseline = 0.0'f32
    for index in line.firstChild ..< line.pastChild:
      let child = children[index]
      let childStyle {.cursor.} = styles.styles[child.node.nodeIndex]
      if effectiveAlignment(childStyle.layout.alignSelf, parentAlign) != aiBaseline:
        continue
      let childBaseline = max(0.0'f32, child.firstBaseline)
      baseline = max(baseline, child.margin.top + childBaseline)
      belowBaseline = max(
        belowBaseline,
        child.margin.bottom + max(0.0'f32, child.size.h - childBaseline)
      )
    line.firstBaseline = baseline
    if baseline >= 0:
      line.crossSize = max(line.crossSize, baseline + belowBaseline)

proc resolveFlexibleLine(
    line: var FlexLine;
    children: var seq[ChildPlacement];
    styles: ResolvedTree;
    direction: FlexDirection;
    availableMain, gap: float32;
    output: var LayoutResult
) =
  let childCount = line.pastChild - line.firstChild
  if childCount <= 0:
    return

  let freeMain = max(0.0'f32, availableMain - line.mainSize)
  let deficitMain = max(0.0'f32, line.mainSize - availableMain)
  if freeMain > 0:
    var frozen = newSeq[bool](childCount)
    var remainingFree = freeMain
    for _ in 0 .. childCount:
      if remainingFree <= 0.001'f32:
        break
      var totalGrow = 0.0'f32
      for localIndex in 0 ..< childCount:
        if frozen[localIndex]:
          continue
        let index = line.firstChild + localIndex
        let grow = styles.styles[children[index].node.nodeIndex].layout.flexGrow
        let current = children[index].size.mainSize(direction)
        if grow <= 0 or current >= children[index].maxMain - 0.001'f32:
          frozen[localIndex] = true
          continue
        totalGrow += grow
      if totalGrow <= 0:
        break

      var addedThisPass = 0.0'f32
      for localIndex in 0 ..< childCount:
        if frozen[localIndex]:
          continue
        let index = line.firstChild + localIndex
        let grow = styles.styles[children[index].node.nodeIndex].layout.flexGrow
        let current = children[index].size.mainSize(direction)
        let requested = remainingFree * (grow / totalGrow)
        let capacity = max(0.0'f32, children[index].maxMain - current)
        let added = min(requested, capacity)
        let next = current + added
        children[index].size.setMainSize(direction, next)
        output.setMainSize(
          children[index].firstBox,
          children[index].boxCount,
          children[index].node,
          direction,
          next
        )
        addedThisPass += added
        if capacity <= requested + 0.001'f32:
          frozen[localIndex] = true
      if addedThisPass <= 0.001'f32:
        break
      remainingFree = max(0.0'f32, remainingFree - addedThisPass)
  elif deficitMain > 0:
    var frozen = newSeq[bool](childCount)
    var remainingDeficit = deficitMain
    for _ in 0 .. childCount:
      if remainingDeficit <= 0.001'f32:
        break
      var totalShrink = 0.0'f32
      for localIndex in 0 ..< childCount:
        if frozen[localIndex]:
          continue
        let index = line.firstChild + localIndex
        let childStyle {.cursor.} = styles.styles[children[index].node.nodeIndex]
        let current = children[index].size.mainSize(direction)
        if current <= children[index].minMain + 0.001'f32 or
            childStyle.layout.flexShrink <= 0:
          frozen[localIndex] = true
          continue
        totalShrink += childStyle.layout.flexShrink * current
      if totalShrink <= 0:
        break

      var removedThisPass = 0.0'f32
      for localIndex in 0 ..< childCount:
        if frozen[localIndex]:
          continue
        let index = line.firstChild + localIndex
        let childStyle {.cursor.} = styles.styles[children[index].node.nodeIndex]
        let current = children[index].size.mainSize(direction)
        let requested = remainingDeficit *
          ((childStyle.layout.flexShrink * current) / totalShrink)
        let capacity = max(0.0'f32, current - children[index].minMain)
        let removed = min(requested, capacity)
        let next = current - removed
        children[index].size.setMainSize(direction, next)
        output.setMainSize(
          children[index].firstBox,
          children[index].boxCount,
          children[index].node,
          direction,
          next
        )
        removedThisPass += removed
        if capacity <= requested + 0.001'f32:
          frozen[localIndex] = true
      if removedThisPass <= 0.001'f32:
        break
      remainingDeficit = max(0.0'f32, remainingDeficit - removedThisPass)

  line.refreshLineMetrics(children, direction, gap)

proc distribution(
    alignment: JustifyContent;
    freeSpace: float32;
    itemCount: int
): tuple[offset, extraGap: float32] =
  case alignment
  of jcStart:
    discard
  of jcCenter:
    result.offset = freeSpace / 2.0'f32
  of jcEnd:
    result.offset = freeSpace
  of jcSpaceBetween:
    if itemCount > 1:
      result.extraGap = freeSpace / (itemCount - 1).float32
  of jcSpaceAround:
    if itemCount > 0:
      result.extraGap = freeSpace / itemCount.float32
      result.offset = result.extraGap / 2.0'f32
  of jcSpaceEvenly:
    if itemCount > 0:
      result.extraGap = freeSpace / (itemCount + 1).float32
      result.offset = result.extraGap
  of jcStretch:
    discard

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
  of ukEm, ukRem, ukFill, ukContent, ukMinContent, ukMaxContent,
      ukFitContent, ukAuto, ukNone, ukVw, ukVh, ukVmin, ukVmax, ukLh,
      ukRlh, ukEx, ukCh, ukRex, ukRch:
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
    intrinsic: IntrinsicSizes;
    boxEdges = EdgeSizes()
): Size =
  result = size(w, h)
  let minWidth = resolveSizingLength(
    style.minWidthSpec(), constraints.w,
    intrinsic.minSize.w, intrinsic.maxSize.w,
    boxEdges.horizontal, style.layout.boxSizing
  )
  let maxWidth = resolveSizingLength(
    style.maxWidthSpec(), constraints.w,
    intrinsic.minSize.w, intrinsic.maxSize.w,
    boxEdges.horizontal, style.layout.boxSizing
  )
  let minHeight = resolveSizingLength(
    style.minHeightSpec(), constraints.h,
    intrinsic.minSize.h, intrinsic.maxSize.h,
    boxEdges.vertical, style.layout.boxSizing
  )
  let maxHeight = resolveSizingLength(
    style.maxHeightSpec(), constraints.h,
    intrinsic.minSize.h, intrinsic.maxSize.h,
    boxEdges.vertical, style.layout.boxSizing
  )
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

  let measuredEdges =
    if node.kind == nkBox:
      combinedEdges(paddingOf(style), borderOf(style))
    else:
      EdgeSizes()

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
      if style.layout.direction.isRow:
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
      if style.layout.direction.isRow:
        result.minSize.w += gaps
        result.maxSize.w += gaps
      else:
        result.minSize.h += gaps
        result.maxSize.h += gaps
    result.minSize.w += measuredEdges.horizontal
    result.maxSize.w += measuredEdges.horizontal
    result.minSize.h += measuredEdges.vertical
    result.maxSize.h += measuredEdges.vertical

  # Cache raw content measurements. The value returned to the parent below may
  # include this node's explicit size, but `content` and flex-basis content
  # must still be able to read the unmodified intrinsic dimensions.
  output[id.nodeIndex] = result

  let widthSpec = style.widthSpec()
  let heightSpec = style.heightSpec()
  let width =
    if widthSpec.isSome and widthSpec.get.kind in {ukPx, ukContent, ukMinContent, ukMaxContent}:
      resolveLength(
        widthSpec, result.maxSize.w, result.minSize.w, result.maxSize.w
      )
    else:
      none(float32)
  let height =
    if heightSpec.isSome and heightSpec.get.kind in {ukPx, ukContent, ukMinContent, ukMaxContent}:
      resolveLength(
        heightSpec, result.maxSize.h, result.minSize.h, result.maxSize.h
      )
    else:
      none(float32)
  if width.isSome:
    let outerWidth =
      if widthSpec.usesSelectedSizingBox:
        toBorderBox(width.get, measuredEdges.horizontal, style.layout.boxSizing)
      else:
        width.get
    result.minSize.w = outerWidth
    result.maxSize.w = outerWidth
  if height.isSome:
    let outerHeight =
      if heightSpec.usesSelectedSizingBox:
        toBorderBox(height.get, measuredEdges.vertical, style.layout.boxSizing)
      else:
        height.get
    result.minSize.h = outerHeight
    result.maxSize.h = outerHeight

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

proc flexContainerSize(
    style: ComputedStyle;
    constraints: Size;
    intrinsic: IntrinsicSizes;
    boxEdges: EdgeSizes;
    specifiedWidth, specifiedHeight: Option[float32];
    contentMain, contentCross: float32
): Size =
  let widthSpec = style.widthSpec()
  let heightSpec = style.heightSpec()
  let naturalW =
    if style.layout.direction.isRow:
      contentMain + boxEdges.horizontal
    else:
      contentCross + boxEdges.horizontal
  let naturalH =
    if style.layout.direction.isRow:
      contentCross + boxEdges.vertical
    else:
      contentMain + boxEdges.vertical
  let rawW = if specifiedWidth.isSome: specifiedWidth.get else: naturalW
  let rawH = if specifiedHeight.isSome: specifiedHeight.get else: naturalH
  var aspect = size(rawW, rawH)
  if style.layout.aspectRatio.isSome and style.layout.aspectRatio.get > 0:
    let ratio = style.layout.aspectRatio.get
    if specifiedWidth.isSome and specifiedHeight.isNone:
      if widthSpec.usesSelectedSizingBox and style.layout.boxSizing == bsContentBox:
        let contentWidth = max(0.0'f32, specifiedWidth.get - boxEdges.horizontal)
        aspect.h = contentWidth / ratio + boxEdges.vertical
      else:
        aspect.h = max(boxEdges.vertical, specifiedWidth.get / ratio)
    elif specifiedHeight.isSome and specifiedWidth.isNone:
      if heightSpec.usesSelectedSizingBox and style.layout.boxSizing == bsContentBox:
        let contentHeight = max(0.0'f32, specifiedHeight.get - boxEdges.vertical)
        aspect.w = contentHeight * ratio + boxEdges.horizontal
      else:
        aspect.w = max(boxEdges.horizontal, specifiedHeight.get * ratio)
  clampSize(
    aspect.w, aspect.h, style, constraints, intrinsic, boxEdges
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
    output: var LayoutResult;
    forcedWidth = none(float32);
    forcedHeight = none(float32)
): LayoutMetrics =
  let node = tree.nodes[id.nodeIndex]
  let style {.cursor.} = styles.styles[id.nodeIndex]
  let intrinsic = intrinsics[id.nodeIndex]
  let initialPadding =
    if node.kind == nkBox: paddingOf(style, constraints.w)
    else: EdgeSizes()
  let initialBoxEdges =
    if node.kind == nkBox:
      combinedEdges(initialPadding, borderOf(style))
    else:
      EdgeSizes()
  let widthSpec = style.widthSpec()
  let heightSpec = style.heightSpec()
  let specifiedWidth =
    if forcedWidth.isSome:
      forcedWidth
    else:
      resolveSizingLength(
        widthSpec, constraints.w,
        intrinsic.minSize.w, intrinsic.maxSize.w,
        initialBoxEdges.horizontal, style.layout.boxSizing
      )
  let specifiedHeight =
    if forcedHeight.isSome:
      forcedHeight
    else:
      resolveSizingLength(
        heightSpec, constraints.h,
        intrinsic.minSize.h, intrinsic.maxSize.h,
        initialBoxEdges.vertical, style.layout.boxSizing
      )
  let firstBox = output.boxes.len

  if style.layout.display == dkNone:
    output.boxes.add LayoutBox(
      node: id,
      rect: rect(x, y, 0, 0),
      zIndex: style.layout.zIndex
    )
    return LayoutMetrics(size: size(0, 0), firstBaseline: 0)

  if node.kind == nkText:
    let measuredText = textLimitedByMaxLines(node.text, style.text)
    let measured = textEngine.measure(TextMeasureInput(
      text: measuredText,
      style: style.text,
      maxWidth: some(if specifiedWidth.isSome: specifiedWidth.get else: constraints.w),
      fonts: fontRegistry
    ))
    let w = if specifiedWidth.isSome: specifiedWidth.get else: measured.w
    let h = if specifiedHeight.isSome: specifiedHeight.get else: measured.h
    let aspect = applyAspect(w, h, style, specifiedWidth.isSome, specifiedHeight.isSome)
    let clamped = clampSize(aspect.w, aspect.h, style, constraints, intrinsic)
    output.boxes.add LayoutBox(
      node: id,
      rect: rect(x, y, clamped.w, clamped.h),
      zIndex: style.layout.zIndex
    )
    let zoom = parsedZoom(style)
    let baseline = textEngine.firstLineBaseline(TextFontMetricsInput(
      style: style.text,
      fonts: fontRegistry
    ))
    if zoom != 1.0'f32:
      output.scaleBoxes(firstBox, output.boxes.len - firstBox, x, y, zoom)
      return LayoutMetrics(
        size: size(clamped.w * zoom, clamped.h * zoom),
        firstBaseline: baseline * zoom
      )
    return LayoutMetrics(size: clamped, firstBaseline: baseline)

  if node.kind == nkImage:
    let intrinsicW = max(0.0'f32, node.imageWidth)
    let intrinsicH = max(0.0'f32, node.imageHeight)
    let w =
      if specifiedWidth.isSome: specifiedWidth.get
      elif intrinsicW > 0: intrinsicW
      else: 0.0'f32
    let h =
      if specifiedHeight.isSome: specifiedHeight.get
      elif intrinsicH > 0: intrinsicH
      else: 0.0'f32
    let aspect = applyAspect(w, h, style, specifiedWidth.isSome, specifiedHeight.isSome)
    let clamped = clampSize(aspect.w, aspect.h, style, constraints, intrinsic)
    output.boxes.add LayoutBox(
      node: id,
      rect: rect(x, y, clamped.w, clamped.h),
      zIndex: style.layout.zIndex
    )
    let zoom = parsedZoom(style)
    if zoom != 1.0'f32:
      output.scaleBoxes(firstBox, output.boxes.len - firstBox, x, y, zoom)
      return LayoutMetrics(
        size: size(clamped.w * zoom, clamped.h * zoom),
        firstBaseline: clamped.h * zoom
      )
    return LayoutMetrics(size: clamped, firstBaseline: clamped.h)

  let pad = initialPadding
  let boxEdges = initialBoxEdges
  let resolvedWidth = specifiedWidth
  let resolvedHeight = specifiedHeight
  let childConstraints = size(
    max(
      0.0'f32,
      (if resolvedWidth.isSome: resolvedWidth.get else: constraints.w) -
        boxEdges.horizontal
    ),
    max(
      0.0'f32,
      (if resolvedHeight.isSome: resolvedHeight.get else: constraints.h) -
        boxEdges.vertical
    )
  )
  let mainAxisResolved =
    if style.layout.direction.isRow: resolvedWidth.isSome
    else: resolvedHeight.isSome
  let crossAxisResolved =
    if style.layout.direction.isRow: resolvedHeight.isSome
    else: resolvedWidth.isSome
  var wrapMainIsDefinite = mainAxisResolved
  var tentativeAvailableMain = childConstraints.mainSize(style.layout.direction)
  if style.layout.flexWrap != fwNoWrap and not wrapMainIsDefinite:
    let maximumSpec =
      if style.layout.direction.isRow: style.maxWidthSpec()
      else: style.maxHeightSpec()
    let intrinsicMin = intrinsic.minSize.mainSize(style.layout.direction)
    let intrinsicMax = intrinsic.maxSize.mainSize(style.layout.direction)
    let reference = constraints.mainSize(style.layout.direction)
    let extra =
      if style.layout.direction.isRow: boxEdges.horizontal
      else: boxEdges.vertical
    let maximum = resolveSizingLength(
      maximumSpec,
      reference,
      intrinsicMin,
      intrinsicMax,
      extra,
      style.layout.boxSizing
    )
    if maximum.isSome:
      tentativeAvailableMain = max(0.0'f32, maximum.get - extra)
      wrapMainIsDefinite = true
  var tentativeContentSize = childConstraints
  tentativeContentSize.setMainSize(
    style.layout.direction, tentativeAvailableMain
  )
  let measuredMainGap =
    if wrapMainIsDefinite: style.mainGapOf(tentativeContentSize)
    else: style.mainGapOf(size(0, 0))
  let measuredCrossGap =
    if crossAxisResolved: style.crossGapOf(childConstraints)
    else: style.crossGapOf(size(0, 0))

  var children: seq[ChildPlacement]
  var absoluteChildren: seq[ChildPlacement]
  var hasBaselineAlignment = false
  var hasStretchAlignment = false
  let orderedChildren = node.childrenInLayoutOrder(styles)
  for child in orderedChildren:
    let childStyle {.cursor.} = styles.styles[child.nodeIndex]
    if childStyle.layout.display == dkNone:
      continue
    if childStyle.isAbsolute:
      let firstBox = output.boxes.len
      let firstOverflowMetric = output.overflowMetrics.len
      let childMetrics = layoutNode(
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
        size: childMetrics.size,
        firstBaseline: childMetrics.firstBaseline,
        laidOutMain: childMetrics.size.mainSize(style.layout.direction),
        minMain: 0,
        margin: marginOf(childStyle, childConstraints.w),
        firstBox: firstBox,
        boxCount: output.boxes.len - firstBox,
        firstOverflowMetric: firstOverflowMetric,
        overflowMetricCount: output.overflowMetrics.len - firstOverflowMetric
      )
      continue

    let childAlignment = effectiveAlignment(
      childStyle.layout.alignSelf, style.layout.alignItems
    )
    if style.layout.direction.isRow and childAlignment == aiBaseline:
      hasBaselineAlignment = true
    if childAlignment == aiStretch:
      hasStretchAlignment = true

    let firstBox = output.boxes.len
    let firstOverflowMetric = output.overflowMetrics.len
    let childMetrics = layoutNode(
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
    var childSize = childMetrics.size
    let basisSpec = childStyle.flexBasisSpec()
    let childIntrinsic = intrinsics[child.nodeIndex]
    let childBoxEdges = combinedEdges(
      paddingOf(childStyle, childConstraints.w),
      borderOf(childStyle)
    )
    let childMinMain = childStyle.flexMinimumMain(
      style.layout.direction, childConstraints, childIntrinsic, childBoxEdges
    )
    let childMaxMain = childStyle.flexMaximumMain(
      style.layout.direction, childConstraints, childIntrinsic, childBoxEdges
    )
    let specifiedBasis =
      if basisSpec.isSome and basisSpec.get.kind == ukPercent and not mainAxisResolved:
        none(float32)
      elif style.layout.direction.isRow:
        resolveSizingLength(
          basisSpec, childConstraints.w,
          childIntrinsic.minSize.w, childIntrinsic.maxSize.w,
          childBoxEdges.horizontal, childStyle.layout.boxSizing
        )
      else:
        resolveSizingLength(
          basisSpec, childConstraints.h,
          childIntrinsic.minSize.h, childIntrinsic.maxSize.h,
          childBoxEdges.vertical, childStyle.layout.boxSizing
        )
    let basis = specifiedBasis
    if basis.isSome:
      let basisSize = max(childMinMain, min(basis.get, childMaxMain))
      childSize.setMainSize(style.layout.direction, basisSize)
      output.setMainSize(
        firstBox, output.boxes.len - firstBox,
        child, style.layout.direction, basisSize
      )
    let margin = marginOf(childStyle, childConstraints.w)
    children.add ChildPlacement(
      node: child,
      size: childSize,
      firstBaseline: childMetrics.firstBaseline,
      laidOutMain: childMetrics.size.mainSize(style.layout.direction),
      minMain: childMinMain,
      maxMain: childMaxMain,
      margin: margin,
      firstBox: firstBox,
      boxCount: output.boxes.len - firstBox,
      firstOverflowMetric: firstOverflowMetric,
      overflowMetricCount: output.overflowMetrics.len - firstOverflowMetric
    )

  var lines = collectFlexLines(
    children,
    style.layout.direction,
    style.layout.flexWrap,
    wrapMainIsDefinite,
    tentativeAvailableMain,
    measuredMainGap
  )
  lines.resolveLineBaselines(
    children, styles, style.layout.alignItems, style.layout.direction,
    hasBaselineAlignment
  )
  var contentMain = 0.0'f32
  var contentCross = 0.0'f32
  for index, line in lines:
    contentMain = max(contentMain, line.mainSize)
    if index > 0:
      contentCross += measuredCrossGap
    contentCross += line.crossSize

  var clamped = flexContainerSize(
    style, constraints, intrinsic, boxEdges, resolvedWidth, resolvedHeight,
    contentMain, contentCross
  )

  let availableMain =
    if style.layout.direction.isRow:
      max(0.0'f32, clamped.w - boxEdges.horizontal)
    else:
      max(0.0'f32, clamped.h - boxEdges.vertical)
  var availableCross =
    if style.layout.direction.isRow:
      max(0.0'f32, clamped.h - boxEdges.vertical)
    else:
      max(0.0'f32, clamped.w - boxEdges.horizontal)
  var containingContentSize = size(
    max(0.0'f32, clamped.w - boxEdges.horizontal),
    max(0.0'f32, clamped.h - boxEdges.vertical)
  )
  var mainGap = style.mainGapOf(containingContentSize)
  var crossGap = style.crossGapOf(containingContentSize)
  lines = collectFlexLines(
    children,
    style.layout.direction,
    style.layout.flexWrap,
    wrapMainIsDefinite,
    availableMain,
    mainGap
  )
  for line in lines.mitems:
    line.resolveFlexibleLine(
      children, styles, style.layout.direction, availableMain, mainGap, output
    )

  var reflowBuffer = LayoutResult(boxes: @[], overflowMetrics: @[])
  template relayoutChild(
      childIndex: int;
      targetWidth, targetHeight: Option[float32]
  ) =
    block:
      let reflowStyle {.cursor.} = styles.styles[
        children[childIndex].node.nodeIndex
      ]
      let reflowZoom = parsedZoom(reflowStyle)
      let forcedChildWidth =
        if targetWidth.isSome: some(targetWidth.get / reflowZoom)
        else: none(float32)
      let forcedChildHeight =
        if targetHeight.isSome: some(targetHeight.get / reflowZoom)
        else: none(float32)
      reflowBuffer.boxes.setLen(0)
      reflowBuffer.overflowMetrics.setLen(0)
      let childMetrics = layoutNode(
        tree, styles, children[childIndex].node, 0, 0,
        containingContentSize, textEngine, fontRegistry, intrinsics,
        reflowBuffer,
        forcedWidth = forcedChildWidth,
        forcedHeight = forcedChildHeight
      )
      if reflowBuffer.boxes.len != children[childIndex].boxCount or
          reflowBuffer.overflowMetrics.len !=
            children[childIndex].overflowMetricCount:
        raise newException(
          ValueError,
          "flex item relayout changed the retained subtree shape"
        )
      for localIndex, box in reflowBuffer.boxes:
        output.boxes[children[childIndex].firstBox + localIndex] = box
      for localIndex, metrics in reflowBuffer.overflowMetrics:
        output.overflowMetrics[
          children[childIndex].firstOverflowMetric + localIndex
        ] = metrics
      children[childIndex].size = childMetrics.size
      children[childIndex].firstBaseline = childMetrics.firstBaseline
      children[childIndex].laidOutMain = childMetrics.size.mainSize(
        style.layout.direction
      )

  var mainRelayoutOccurred = false
  for childIndex in 0 ..< children.len:
    let targetMain = children[childIndex].size.mainSize(style.layout.direction)
    if abs(targetMain - children[childIndex].laidOutMain) <= 0.001'f32:
      continue
    mainRelayoutOccurred = true
    if style.layout.direction.isRow:
      relayoutChild(childIndex, some(targetMain), none(float32))
    else:
      relayoutChild(childIndex, none(float32), some(targetMain))

  if mainRelayoutOccurred:
    for line in lines.mitems:
      line.refreshLineMetrics(children, style.layout.direction, mainGap)

  lines.resolveLineBaselines(
    children, styles, style.layout.alignItems, style.layout.direction,
    hasBaselineAlignment
  )

  if mainRelayoutOccurred:
    contentMain = 0
    contentCross = 0
    for index, line in lines:
      contentMain = max(contentMain, line.mainSize)
      if index > 0:
        contentCross += crossGap
      contentCross += line.crossSize

    let reflowedContainerSize = flexContainerSize(
      style, constraints, intrinsic, boxEdges, resolvedWidth, resolvedHeight,
      contentMain, contentCross
    )
    if style.layout.direction.isRow:
      clamped.h = reflowedContainerSize.h
    else:
      clamped.w = reflowedContainerSize.w
    availableCross =
      if style.layout.direction.isRow:
        max(0.0'f32, clamped.h - boxEdges.vertical)
      else:
        max(0.0'f32, clamped.w - boxEdges.horizontal)
    containingContentSize = size(
      max(0.0'f32, clamped.w - boxEdges.horizontal),
      max(0.0'f32, clamped.h - boxEdges.vertical)
    )
    mainGap = style.mainGapOf(containingContentSize)
    crossGap = style.crossGapOf(containingContentSize)
    for line in lines.mitems:
      line.refreshLineMetrics(children, style.layout.direction, mainGap)

  if lines.len == 1:
    lines[0].crossSize = availableCross
  let freeCross =
    if lines.len > 1: max(0.0'f32, availableCross - contentCross)
    else: 0.0'f32
  if style.layout.alignContent == jcStretch and lines.len > 1:
    let extraCross = freeCross / lines.len.float32
    for line in lines.mitems:
      line.crossSize += extraCross

  if hasStretchAlignment:
    for line in lines:
      for childIndex in line.firstChild ..< line.pastChild:
        let childStyle {.cursor.} = styles.styles[
          children[childIndex].node.nodeIndex
        ]
        if effectiveAlignment(
            childStyle.layout.alignSelf, style.layout.alignItems
        ) != aiStretch:
          continue
        let targetCross = max(
          0.0'f32,
          line.crossSize - children[childIndex].margin.crossMargin(
            style.layout.direction
          )
        )
        if abs(
            targetCross - children[childIndex].size.crossSize(
              style.layout.direction
            )
        ) <= 0.001'f32:
          continue
        let targetMain = children[childIndex].size.mainSize(
          style.layout.direction
        )
        if style.layout.direction.isRow:
          relayoutChild(childIndex, some(targetMain), some(targetCross))
        else:
          relayoutChild(childIndex, some(targetCross), some(targetMain))
  let lineDistribution = distribution(
    style.layout.alignContent, freeCross, lines.len
  )
  var cursorCross = lineDistribution.offset
  var containerFirstBaseline = clamped.h

  for lineIndex in 0 ..< lines.len:
    let line = lines[lineIndex]
    let physicalCross =
      if style.layout.flexWrap == fwWrapReverse:
        availableCross - cursorCross - line.crossSize
      else:
        cursorCross
    if lineIndex == 0 and style.layout.direction.isRow and line.firstBaseline >= 0:
      containerFirstBaseline = boxEdges.top + physicalCross + line.firstBaseline
    let freeMain = max(0.0'f32, availableMain - line.mainSize)
    let mainDistribution = distribution(
      style.layout.justifyContent,
      freeMain,
      line.pastChild - line.firstChild
    )
    var cursorMain = mainDistribution.offset

    for childIndex in line.firstChild ..< line.pastChild:
      let child = children[childIndex]
      let childStyle {.cursor.} = styles.styles[child.node.nodeIndex]
      let childOuterMain = child.outerMain(style.layout.direction)
      let childOuterCross = child.outerCross(style.layout.direction)
      let physicalMain =
        if style.layout.direction.isMainReverse:
          availableMain - cursorMain - childOuterMain
        else:
          cursorMain
      let effectiveAlign = effectiveAlignment(
        childStyle.layout.alignSelf, style.layout.alignItems
      )
      let crossOffset =
        case effectiveAlign
        of aiStart, aiStretch:
          0.0'f32
        of aiCenter:
          max(0.0'f32, (line.crossSize - childOuterCross) / 2.0'f32)
        of aiEnd:
          max(0.0'f32, line.crossSize - childOuterCross)
        of aiBaseline:
          if style.layout.direction.isRow and line.firstBaseline >= 0:
            max(0.0'f32,
              line.firstBaseline - child.margin.top - child.firstBaseline)
          else:
            0.0'f32

      if style.layout.direction.isRow:
        let targetX = x + boxEdges.left + physicalMain + child.margin.left
        let targetY = y + boxEdges.top + physicalCross +
          crossOffset + child.margin.top
        let offset = childStyle.relativeOffset(containingContentSize)
        if lineIndex == 0 and childIndex == line.firstChild and
            line.firstBaseline < 0:
          containerFirstBaseline = boxEdges.top + physicalCross +
            crossOffset + child.margin.top + child.firstBaseline
        output.shiftBoxes(
          child.firstBox, child.boxCount, targetX + offset.x, targetY + offset.y
        )
      else:
        let targetX = x + boxEdges.left + physicalCross +
          crossOffset + child.margin.left
        let targetY = y + boxEdges.top + physicalMain + child.margin.top
        let offset = childStyle.relativeOffset(containingContentSize)
        output.shiftBoxes(
          child.firstBox, child.boxCount, targetX + offset.x, targetY + offset.y
        )
      cursorMain += childOuterMain
      if childIndex + 1 < line.pastChild:
        cursorMain += mainGap + mainDistribution.extraGap

    cursorCross += line.crossSize
    if lineIndex < lines.high:
      cursorCross += crossGap + lineDistribution.extraGap

  for child in absoluteChildren:
    let childStyle {.cursor.} = styles.styles[child.node.nodeIndex]
    let contentX = x + boxEdges.left
    let contentY = y + boxEdges.top
    let contentW = max(0.0'f32, clamped.w - boxEdges.horizontal)
    let contentH = max(0.0'f32, clamped.h - boxEdges.vertical)
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
    padding: pad,
    zIndex: style.layout.zIndex
  )
  let zoom = parsedZoom(style)
  if style.layout.overflowX in {omAuto, omScroll} or
      style.layout.overflowY in {omAuto, omScroll}:
    let contentSize =
      if style.layout.direction.isRow:
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
    return LayoutMetrics(
      size: size(clamped.w * zoom, clamped.h * zoom),
      firstBaseline: containerFirstBaseline * zoom
    )
  LayoutMetrics(size: clamped, firstBaseline: containerFirstBaseline)

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
