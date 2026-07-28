import std/options
import ../core/[computed_style, geometry, node, style_resolver]
import ../layout/layout
import ../layout/overflow_geometry
import ../layout/scroll_state
import ../layout/scrollbar_geometry

type
  HitRegionKind* = enum
    hrContent,
    hrScrollbarTrackX,
    hrScrollbarThumbX,
    hrScrollbarTrackY,
    hrScrollbarThumbY

  HitRegion* = object
    node*: NodeId
    rect*: Rect
    localOrigin*: Option[Vec2]
    zIndex*: int
    cursor*: Option[CursorKind]
    kind*: HitRegionKind
    scrollbarTrack*: Option[Rect]
    scrollbarThumb*: Option[Rect]

  HitTestResult* = object
    node*: NodeId
    local*: Vec2
    cursor*: Option[CursorKind]
    kind*: HitRegionKind
    scrollbarTrack*: Option[Rect]
    scrollbarThumb*: Option[Rect]

proc isScrollbar*(kind: HitRegionKind): bool =
  kind != hrContent

proc isScrollbarThumb*(kind: HitRegionKind): bool =
  kind in {hrScrollbarThumbX, hrScrollbarThumbY}

proc isHorizontalScrollbar*(kind: HitRegionKind): bool =
  kind in {hrScrollbarTrackX, hrScrollbarThumbX}

proc buildHitRegions*(layout: LayoutResult): seq[HitRegion] =
  for index, item in layout.boxes:
    if item.rect.w > 0 and item.rect.h > 0:
      result.add HitRegion(
        node: item.node,
        rect: item.rect,
        localOrigin: some(vec2(item.rect.x, item.rect.y)),
        zIndex: item.zIndex * 100000 + index
      )

proc buildHitRegions*(layout: LayoutResult; styles: ResolvedTree): seq[HitRegion] =
  for index, item in layout.boxes:
    let visual {.cursor.} = styles.styles[item.node.nodeIndex].visual
    if item.rect.w > 0 and item.rect.h > 0 and visual.visible and visual.pointerEvents != peNone:
      result.add HitRegion(
        node: item.node,
        rect: item.rect,
        localOrigin: some(vec2(item.rect.x, item.rect.y)),
        zIndex: item.zIndex * 100000 + index,
        cursor: visual.cursor
      )

proc hidesContents(style: ComputedStyle): bool =
  style.visual.contentVisibility.isSome and style.visual.contentVisibility.get == "hidden"

proc inheritedCursor(tree: Tree; styles: ResolvedTree; id: NodeId): Option[CursorKind] =
  var current = some(id)
  while current.isSome:
    let currentId = current.get
    let cursor {.cursor.} = styles.styles[currentId.nodeIndex].visual.cursor
    if cursor.isSome:
      return cursor
    current = tree.nodes[currentId.nodeIndex].parent
  none(CursorKind)

proc addHitRegions(
    tree: Tree;
    layout: LayoutResult;
    boxIndices: openArray[int];
    styles: ResolvedTree;
    scroll: ScrollState;
    id: NodeId;
    translation: Vec2;
    inheritedClip: Option[Rect];
    output: var seq[HitRegion]
) =
  let boxIndex = boxIndices.boxIndexFor(id)
  if boxIndex < 0:
    return
  let item = layout.boxes[boxIndex]
  let style {.cursor.} = styles.styles[id.nodeIndex]
  if not style.visual.visible or style.layout.display == dkNone:
    return

  let nodeRect = item.rect.translated(translation)
  var visibleRect = nodeRect
  if inheritedClip.isSome:
    visibleRect = visibleRect.intersection(inheritedClip.get)

  if not visibleRect.isEmpty and style.visual.pointerEvents != peNone:
    output.add HitRegion(
      node: id,
      rect: visibleRect,
      localOrigin: some(vec2(nodeRect.x, nodeRect.y)),
      zIndex: item.zIndex * 100000 + boxIndex,
      cursor: tree.inheritedCursor(styles, id)
    )

  if style.hidesContents:
    return

  var childClip = inheritedClip
  if tree.nodes[id.nodeIndex].kind == nkBox and style.clipsOverflow():
    let ownClip = overflowClipRect(nodeRect, style)
    childClip =
      if childClip.isSome: some(childClip.get.intersection(ownClip))
      else: some(ownClip)
    if childClip.get.isEmpty:
      return

  let offset = scroll.scrollOffset(id)
  let childTranslation = vec2(translation.x - offset.x, translation.y - offset.y)
  for child in tree.nodes[id.nodeIndex].children:
    addHitRegions(
      tree, layout, boxIndices, styles, scroll, child, childTranslation,
      childClip, output
    )

  if tree.nodes[id.nodeIndex].kind == nkBox and
      style.visual.pointerEvents != peNone:
    let metrics = scroll.metricsFor(id)
    if metrics.isSome:
      let scrollbars = scrollbarGeometry(nodeRect, style, metrics.get)
      template addScrollbarRegions(
          axis: ScrollbarAxisGeometry;
          trackKind, thumbKind: HitRegionKind
      ) =
        var visibleTrack = axis.track
        var visibleThumb = axis.thumb
        if inheritedClip.isSome:
          visibleTrack = visibleTrack.intersection(inheritedClip.get)
          visibleThumb = visibleThumb.intersection(inheritedClip.get)
        if not visibleTrack.isEmpty:
          output.add HitRegion(
            node: id,
            rect: visibleTrack,
            localOrigin: some(vec2(nodeRect.x, nodeRect.y)),
            zIndex: item.zIndex * 100000 + boxIndex,
            kind: trackKind,
            scrollbarTrack: some(axis.track),
            scrollbarThumb: some(axis.thumb)
          )
        if not visibleThumb.isEmpty:
          output.add HitRegion(
            node: id,
            rect: visibleThumb,
            localOrigin: some(vec2(nodeRect.x, nodeRect.y)),
            zIndex: item.zIndex * 100000 + boxIndex,
            kind: thumbKind,
            scrollbarTrack: some(axis.track),
            scrollbarThumb: some(axis.thumb)
          )
      if scrollbars.horizontal.isSome:
        addScrollbarRegions(
          scrollbars.horizontal.get, hrScrollbarTrackX, hrScrollbarThumbX
        )
      if scrollbars.vertical.isSome:
        addScrollbarRegions(
          scrollbars.vertical.get, hrScrollbarTrackY, hrScrollbarThumbY
        )

proc buildHitRegions*(
    tree: Tree;
    layout: LayoutResult;
    styles: ResolvedTree;
    scroll: ScrollState
): seq[HitRegion] =
  if tree.root.isSome:
    let boxIndices = layout.layoutBoxIndices(tree.nodes.len)
    addHitRegions(
      tree, layout, boxIndices, styles, scroll, tree.root.get, vec2(0, 0),
      none(Rect), result
    )

type HitAncestorContext = object
  translation: Vec2
  clip: Option[Rect]
  visible: bool

proc ancestorHitContext(
    tree: Tree;
    layout: LayoutResult;
    boxIndices: openArray[int];
    styles: ResolvedTree;
    scroll: ScrollState;
    root: NodeId
): HitAncestorContext =
  result.visible = true
  var parent = tree.nodes[root.nodeIndex].parent
  var ancestors: seq[NodeId]
  while parent.isSome:
    ancestors.add parent.get
    parent = tree.nodes[parent.get.nodeIndex].parent

  if ancestors.len == 0:
    return

  for index in countdown(ancestors.high, 0):
    let ancestor = ancestors[index]
    let boxIndex = boxIndices.boxIndexFor(ancestor)
    if boxIndex < 0:
      result.visible = false
      return
    let style {.cursor.} = styles.styles[ancestor.nodeIndex]
    if not style.visual.visible or style.layout.display == dkNone or
        style.hidesContents:
      result.visible = false
      return

    let nodeRect = layout.boxes[boxIndex].rect.translated(result.translation)
    if tree.nodes[ancestor.nodeIndex].kind == nkBox and style.clipsOverflow():
      let ownClip = overflowClipRect(nodeRect, style)
      result.clip =
        if result.clip.isSome:
          some(result.clip.get.intersection(ownClip))
        else:
          some(ownClip)
      if result.clip.get.isEmpty:
        result.visible = false
        return

    let offset = scroll.scrollOffset(ancestor)
    result.translation.x -= offset.x
    result.translation.y -= offset.y

proc buildHitRegionsForSubtree*(
    tree: Tree;
    layout: LayoutResult;
    styles: ResolvedTree;
    root: NodeId;
    scroll: ScrollState
): seq[HitRegion] =
  ## Recomputes presentation coordinates only for `root` and its descendants.
  ## Ancestor scroll translations and overflow clips are retained so the
  ## result is interchangeable with the corresponding span of a full build.
  if root.nodeIndex < 0 or root.nodeIndex >= tree.nodes.len:
    return
  let boxIndices = layout.layoutBoxIndices(tree.nodes.len)
  let context = ancestorHitContext(
    tree, layout, boxIndices, styles, scroll, root
  )
  if context.visible:
    addHitRegions(
      tree, layout, boxIndices, styles, scroll, root, context.translation,
      context.clip, result
    )

proc buildHitRegionsForSubtree*(
    tree: Tree;
    layout: LayoutResult;
    styles: ResolvedTree;
    root: NodeId
): seq[HitRegion] =
  buildHitRegionsForSubtree(
    tree, layout, styles, root, initScrollState()
  )

proc buildHitRegions*(tree: Tree; layout: LayoutResult; styles: ResolvedTree): seq[HitRegion] =
  buildHitRegions(tree, layout, styles, initScrollState())

proc stackingLayer(region: HitRegion): int =
  region.zIndex div 100000

proc isBetterHit(candidate, current: HitRegion): bool =
  let candidateLayer = candidate.stackingLayer()
  let currentLayer = current.stackingLayer()
  if candidateLayer != currentLayer:
    return candidateLayer > currentLayer

  if candidate.kind.isScrollbar != current.kind.isScrollbar:
    return candidate.kind.isScrollbar
  if candidate.kind.isScrollbarThumb != current.kind.isScrollbarThumb:
    return candidate.kind.isScrollbarThumb

  let currentArea = current.rect.w * current.rect.h
  let candidateArea = candidate.rect.w * candidate.rect.h
  candidateArea < currentArea or (candidateArea == currentArea and candidate.zIndex > current.zIndex)

proc hitTest*(regions: openArray[HitRegion]; point: Vec2): Option[HitTestResult] =
  var best: Option[HitRegion]
  for region in regions:
    if region.rect.contains(point):
      if best.isNone:
        best = some(region)
      elif region.isBetterHit(best.get):
        best = some(region)

  if best.isSome:
    let region = best.get
    let origin =
      if region.localOrigin.isSome: region.localOrigin.get
      else: vec2(region.rect.x, region.rect.y)
    return some(HitTestResult(
      node: region.node,
      local: vec2(point.x - origin.x, point.y - origin.y),
      cursor: region.cursor,
      kind: region.kind,
      scrollbarTrack: region.scrollbarTrack,
      scrollbarThumb: region.scrollbarThumb
    ))
  none(HitTestResult)

proc cursorAt*(regions: openArray[HitRegion]; point: Vec2): CursorKind =
  let hit = hitTest(regions, point)
  if hit.isSome and hit.get.cursor.isSome:
    hit.get.cursor.get
  else:
    ckDefault

proc cursorForHit*(hit: Option[HitTestResult]): CursorKind =
  if hit.isSome and hit.get.cursor.isSome:
    hit.get.cursor.get
  else:
    ckDefault
