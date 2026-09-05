import std/[algorithm, math, options, strutils]
import ../core/[color, computed_style, custom_paint, geometry, node,
    style_resolver]
import ../layout/layout
import ../layout/overflow_geometry
import ../layout/presentation
import ../layout/scroll_state
import ../layout/scrollbar_geometry
import ../layout/transform_geometry
import ../text/display_text
import ./background_geometry
import ./custom_paint_registry
import ./paint_command

type
  SurfacePaintProvider* = proc(
    surfaceId: uint64;
    owner: NodeId;
    bounds: Rect;
    opacity: float32
  ): seq[PaintCommand] {.closure.}

  PaintOrderNode = object
    node: NodeId
    zIndex: int

proc comparePaintOrderNode(a, b: PaintOrderNode): int {.nimcall.} =
  result = cmp(a.zIndex, b.zIndex)
  if result != 0:
    return
  result = cmp(a.node.nodeIndex, b.node.nodeIndex)

proc childrenInPaintOrder(node: Node; styles: ResolvedTree): seq[NodeId] =
  ## Extract compact keys before sorting so ResolvedTree is never captured.
  var needsSort = false
  var previousNodeIndex = -1
  for child in node.children:
    if styles.styles[child.nodeIndex].layout.zIndex != 0:
      needsSort = true
      break
    if child.nodeIndex < previousNodeIndex:
      needsSort = true
      break
    previousNodeIndex = child.nodeIndex
  if not needsSort:
    return node.children

  var ordered = newSeqOfCap[PaintOrderNode](node.children.len)
  for child in node.children:
    ordered.add PaintOrderNode(
      node: child,
      zIndex: styles.styles[child.nodeIndex].layout.zIndex
    )
  ordered.sort(comparePaintOrderNode)
  result = newSeqOfCap[NodeId](ordered.len)
  for child in ordered:
    result.add child.node

proc overlayRootsInPaintOrder(overlays: seq[NodeId]; styles: ResolvedTree): seq[NodeId] =
  var ordered = newSeqOfCap[PaintOrderNode](overlays.len)
  for overlay in overlays:
    ordered.add PaintOrderNode(
      node: overlay,
      zIndex: styles.styles[overlay.nodeIndex].layout.zIndex
    )
  ordered.sort(comparePaintOrderNode)
  result = newSeqOfCap[NodeId](ordered.len)
  for overlay in ordered:
    result.add overlay.node

proc withOpacity(color: Color; opacity: float32): Color =
  rgba(color.r, color.g, color.b, color.a * opacity)

proc withOpacity(gradient: LinearGradient; opacity: float32): LinearGradient =
  result = gradient
  result.stops.setLen(0)
  for stop in gradient.stops:
    result.stops.add GradientStop(color: stop.color.withOpacity(opacity), offset: stop.offset)

proc hasAnyBorder(style: ComputedStyle): bool =
  (style.box.borderSideVisible.top and style.box.borderWidths.top > 0) or
    (style.box.borderSideVisible.right and style.box.borderWidths.right > 0) or
    (style.box.borderSideVisible.bottom and style.box.borderWidths.bottom > 0) or
    (style.box.borderSideVisible.left and style.box.borderWidths.left > 0)

proc uniformBorder(style: ComputedStyle): bool =
  style.box.borderWidths.top == style.box.borderWidths.right and
    style.box.borderWidths.top == style.box.borderWidths.bottom and
    style.box.borderWidths.top == style.box.borderWidths.left and
    style.box.borderColors.top == style.box.borderColors.right and
    style.box.borderColors.top == style.box.borderColors.bottom and
    style.box.borderColors.top == style.box.borderColors.left and
    style.box.borderSideVisible.top == style.box.borderSideVisible.right and
    style.box.borderSideVisible.top == style.box.borderSideVisible.bottom and
    style.box.borderSideVisible.top == style.box.borderSideVisible.left

proc addBorderSide(
    output: var seq[PaintCommand];
    rect: Rect;
    width: float32;
    color: Option[Color];
    opacity: float32;
    side: string;
    owner: NodeId
) =
  if width <= 0 or color.isNone:
    return
  let sideRect =
    case side
    of "top":
      Rect(x: rect.x, y: rect.y, w: rect.w, h: width)
    of "right":
      Rect(x: rect.x + rect.w - width, y: rect.y, w: width, h: rect.h)
    of "bottom":
      Rect(x: rect.x, y: rect.y + rect.h - width, w: rect.w, h: width)
    else:
      Rect(x: rect.x, y: rect.y, w: width, h: rect.h)
  output.add fillRect(sideRect, color.get.withOpacity(opacity), owner = some(owner))

proc parseInsetToken(token: string): Option[float32] =
  var value = token.strip()
  if value.endsWith("px"):
    value = value[0 ..< value.len - 2].strip()
  try:
    some(parseFloat(value).float32)
  except ValueError:
    none(float32)

proc insetClipRect(base: Rect; clipPath: Option[string]): Option[Rect] =
  if clipPath.isNone:
    return none(Rect)
  let value = clipPath.get.strip()
  if not value.startsWith("inset(") or not value.endsWith(")"):
    return none(Rect)

  let body = value["inset(".len ..< value.len - 1].strip()
  if body.len == 0:
    return none(Rect)

  let parts = body.splitWhitespace()
  if parts.len < 1 or parts.len > 4:
    return none(Rect)

  var lengths: seq[float32]
  for part in parts:
    let parsed = parseInsetToken(part)
    if parsed.isNone:
      return none(Rect)
    lengths.add parsed.get

  let top = lengths[0]
  let right = if lengths.len >= 2: lengths[1] else: top
  let bottom = if lengths.len >= 3: lengths[2] else: top
  let left = if lengths.len >= 4: lengths[3] else: right
  let width = max(0.0'f32, base.w - left - right)
  let height = max(0.0'f32, base.h - top - bottom)
  some(Rect(x: base.x + left, y: base.y + top, w: width, h: height))

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
    return displayTextTransform(text, style).text
  if maxLines.get == 0:
    return ""
  let lines = text.splitLines()
  if lines.len <= maxLines.get:
    return displayTextTransform(text, style).text
  displayTextTransform(lines[0 ..< maxLines.get].join("\n"), style).text

proc decorationThickness(style: ComputedTextStyle): float32 =
  if style.textDecorationThickness.isSome:
    return max(1.0'f32, style.textDecorationThickness.get)
  if style.fontSize.isSome:
    return max(1.0'f32, round(style.fontSize.get / 12.0'f32))
  1.0'f32

proc decorationLineY(rect: Rect; style: ComputedTextStyle; line: TextDecorationLine): float32 =
  let fontSize =
    if style.fontSize.isSome: style.fontSize.get
    else: min(rect.h, 14.0'f32)
  let lineHeight =
    if style.lineHeight.isSome: style.lineHeight.get
    else: max(rect.h, fontSize)
  case line
  of tdlOverline:
    rect.y + max(0.0'f32, (lineHeight - fontSize) * 0.5'f32)
  of tdlLineThrough:
    rect.y + lineHeight * 0.52'f32
  else:
    rect.y + lineHeight * 0.86'f32

proc addDecorationSegment(
    output: var seq[PaintCommand];
    x, y, width, thickness: float32;
    color: Color;
    owner: NodeId
) =
  if width > 0:
    output.add fillRect(Rect(x: x, y: y, w: width, h: thickness), color, owner = some(owner))

proc addTextDecoration(
    output: var seq[PaintCommand];
    rect: Rect;
    style: ComputedTextStyle;
    color: Color;
    opacity: float32;
    owner: NodeId
) =
  if style.textDecorationLine.isNone:
    return
  let line = style.textDecorationLine.get
  if line == tdlNone:
    return

  let thickness = style.decorationThickness()
  let inset =
    if style.textDecorationInset.isSome: max(0.0'f32, style.textDecorationInset.get)
    else: 0.0'f32
  let x = rect.x + inset
  let width = max(0.0'f32, rect.w - inset * 2.0'f32)
  if width <= 0:
    return

  let decorationColor =
    if style.textDecorationColor.isSome: style.textDecorationColor.get
    else: color
  var y = decorationLineY(rect, style, line)
  if line == tdlUnderline and style.textUnderlineOffset.isSome:
    y += style.textUnderlineOffset.get
  let finalColor = decorationColor.withOpacity(opacity)
  let decorationStyle =
    if style.textDecorationStyle.isSome: style.textDecorationStyle.get
    else: tdsSolid

  case decorationStyle
  of tdsDouble:
    let gap = max(1.0'f32, thickness)
    output.addDecorationSegment(x, y, width, thickness, finalColor, owner)
    output.addDecorationSegment(x, y + thickness + gap, width, thickness, finalColor, owner)
  of tdsDashed:
    let dash = max(4.0'f32, thickness * 4.0'f32)
    let gap = max(2.0'f32, thickness * 2.0'f32)
    var cursor = 0.0'f32
    while cursor < width:
      let segment = min(dash, width - cursor)
      output.addDecorationSegment(x + cursor, y, segment, thickness, finalColor, owner)
      cursor += dash + gap
  of tdsDotted:
    let dot = max(1.0'f32, thickness)
    let gap = max(2.0'f32, thickness * 2.0'f32)
    var cursor = 0.0'f32
    while cursor < width:
      output.addDecorationSegment(x + cursor, y, min(dot, width - cursor), thickness, finalColor, owner)
      cursor += dot + gap
  else:
    output.addDecorationSegment(x, y, width, thickness, finalColor, owner)

proc hidesContents(style: ComputedStyle): bool =
  style.visual.contentVisibility.isSome and style.visual.contentVisibility.get == "hidden"

proc addCustomPaint(
    output: var seq[PaintCommand];
    provider: CustomPaintProvider;
    style: ComputedStyle;
    stage: CustomPaintStage;
    owner: NodeId;
    bounds: Rect;
    opacity: float32
) =
  let material = style.customPaintMaterial(stage)
  if material.isNone or provider.isNil:
    return
  let resolved = provider(CustomPaintRequest(
    material: material.get,
    stage: stage,
    owner: owner,
    bounds: bounds,
    opacity: opacity
  ))
  if resolved.status != cprsResolved or resolved.commands.len == 0:
    return
  output.add pushClip(bounds, style.box.borderRadius)
  for command in resolved.commands:
    output.add command
  output.add popClip()

proc addScrollbars(
    output: var seq[PaintCommand];
    nodeRect: Rect;
    style: ComputedStyle;
    padding: EdgeSizes;
    metrics: ScrollMetrics;
    opacity: float32;
    owner: NodeId
) =
  let geometry = scrollbarGeometry(nodeRect, style, padding, metrics)
  if geometry.horizontal.isNone and geometry.vertical.isNone:
    return
  let thickness = style.scrollbarThickness()
  let trackColor =
    if style.visual.scrollbarTrackColor.isSome:
      style.visual.scrollbarTrackColor.get.withOpacity(opacity)
    else:
      rgba(0.04, 0.05, 0.06, 0.30 * opacity)
  let thumbColor =
    if style.visual.scrollbarThumbColor.isSome:
      style.visual.scrollbarThumbColor.get.withOpacity(opacity)
    else:
      rgba(0.55, 0.60, 0.66, 0.82 * opacity)
  let radius = thickness * 0.5'f32

  if geometry.vertical.isSome:
    let vertical = geometry.vertical.get
    output.add fillRect(vertical.track, trackColor, radius, some(owner))
    output.add fillRect(vertical.thumb, thumbColor, radius, some(owner))

  if geometry.horizontal.isSome:
    let horizontal = geometry.horizontal.get
    output.add fillRect(horizontal.track, trackColor, radius, some(owner))
    output.add fillRect(horizontal.thumb, thumbColor, radius, some(owner))

proc paintNode(
    tree: Tree;
    styles: ResolvedTree;
    layout: LayoutResult;
    boxIndices: openArray[int];
    id: NodeId;
    inheritedOpacity: float32;
    output: var seq[PaintCommand];
    hasTransform: var bool;
    scroll: ScrollState;
    translation: Vec2;
    surfaceProvider: SurfacePaintProvider;
    customPaintProvider: CustomPaintProvider;
    overlayPass = false
) =
  let node = tree.nodes[id.nodeIndex]
  let boxIndex = boxIndices.boxIndexFor(id)
  if boxIndex < 0:
    return
  let item = layout.boxes[boxIndex]
  let nodeRect = item.rect.translated(translation)

  let style {.cursor.} = styles.styles[id.nodeIndex]
  if not overlayPass and node.parent.isSome and style.layout.zIndex > 0:
    return
  if style.layout.display == dkNone:
    return
  if nodeRect.w <= 0 or nodeRect.h <= 0:
    return
  if not style.visual.visible:
    return
  let opacity = inheritedOpacity * style.visual.opacity
  if opacity <= 0.0'f32:
    return

  let ownTransform = resolvedTransform(style, nodeRect, item.padding)
  let transformed = not ownTransform.isIdentity
  if transformed:
    output.add pushTransform(ownTransform)
    hasTransform = true

  let visualClip = insetClipRect(nodeRect, style.visual.clipPath)
  if visualClip.isSome:
    output.add pushClip(visualClip.get, style.box.borderRadius)

  let needsClip = node.kind == nkBox and style.clipsOverflow()

  if node.kind == nkBox and style.box.boxShadow.isSome:
    let shadow = style.box.boxShadow.get
    let color =
      if shadow.color.isSome: shadow.color.get
      else: rgba(0, 0, 0, 0.25)
    output.add drawBoxShadow(
      nodeRect,
      color.withOpacity(opacity),
      shadow.offsetX,
      shadow.offsetY,
      shadow.blur,
      shadow.spread,
      style.box.borderRadius,
      owner = some(id)
    )
  if node.kind == nkBox and (
      style.box.backgroundColor.isSome or style.box.backgroundGradient.isSome or
      (node.generatedPart == gpkAccent and style.visual.accentColor.isSome)
  ):
    let background = backgroundPaintGeometry(nodeRect, style.box, item.padding)
    var backgroundColor = style.box.backgroundColor
    if node.generatedPart == gpkCaret and node.parent.isSome:
      let ownerStyle {.cursor.} = styles.styles[node.parent.get.nodeIndex]
      if ownerStyle.visual.caretColor.isSome:
        backgroundColor = ownerStyle.visual.caretColor
    elif node.generatedPart == gpkAccent and style.visual.accentColor.isSome:
      backgroundColor = style.visual.accentColor
    if backgroundColor.isSome and not background.clipRect.isEmpty:
      output.add fillRect(
        background.clipRect,
        backgroundColor.get.withOpacity(opacity),
        background.clipRadius,
        some(id)
      )
    if style.box.backgroundGradient.isSome and
        not background.paintRect.isEmpty:
      output.add fillLinearGradient(
        background.tileRect,
        style.box.backgroundGradient.get.withOpacity(opacity),
        radius = background.clipRadius,
        owner = some(id),
        paintRect = some(background.paintRect),
        clipRect = some(background.clipRect),
        repeat = background.repeat
      )
  if node.kind == nkBox and style.box.borderVisible and style.hasAnyBorder:
    if style.uniformBorder and style.box.borderColors.top.isSome:
      output.add strokeRect(nodeRect, style.box.borderColors.top.get.withOpacity(opacity), style.box.borderWidths.top, style.box.borderRadius, some(id))
    else:
      if style.box.borderSideVisible.top:
        output.addBorderSide(nodeRect, style.box.borderWidths.top, style.box.borderColors.top, opacity, "top", id)
      if style.box.borderSideVisible.right:
        output.addBorderSide(nodeRect, style.box.borderWidths.right, style.box.borderColors.right, opacity, "right", id)
      if style.box.borderSideVisible.bottom:
        output.addBorderSide(nodeRect, style.box.borderWidths.bottom, style.box.borderColors.bottom, opacity, "bottom", id)
      if style.box.borderSideVisible.left:
        output.addBorderSide(nodeRect, style.box.borderWidths.left, style.box.borderColors.left, opacity, "left", id)
  if node.kind == nkBox and style.box.outlineVisible and style.box.outlineWidth > 0 and style.box.outlineColor.isSome:
    let offset = style.box.outlineOffset
    let outlineRect = Rect(
      x: nodeRect.x - offset,
      y: nodeRect.y - offset,
      w: nodeRect.w + offset * 2.0'f32,
      h: nodeRect.h + offset * 2.0'f32
    )
    output.add strokeRect(outlineRect, style.box.outlineColor.get.withOpacity(opacity), style.box.outlineWidth, style.box.borderRadius, some(id))
  if node.kind == nkText:
    let textColor =
      if node.generatedPart == gpkAccent and style.visual.accentColor.isSome:
        style.visual.accentColor.get
      elif style.text.color.isSome: style.text.color.get
      else: rgb(0, 0, 0)
    let paintText = layout.paintTextFor(item)
    let sourceText =
      if paintText.isSome: paintText.get
      else: node.text
    let text = textLimitedByMaxLines(sourceText, style.text)
    let textRect = Rect(
      x: nodeRect.x + node.renderOffset.x,
      y: nodeRect.y + node.renderOffset.y,
      w:
        if node.textRenderWidth.isSome: node.textRenderWidth.get
        else: nodeRect.w,
      h: nodeRect.h
    )
    let textMaxWidth =
      if node.textRenderWidth.isSome: node.textRenderWidth
      else: some(nodeRect.w)
    if style.text.textShadow.isSome:
      let shadow = style.text.textShadow.get
      let shadowColor =
        if shadow.color.isSome: shadow.color.get
        else: rgba(0, 0, 0, 0.35)
      output.add drawText(
        id,
        text,
        vec2(textRect.x + shadow.offsetX, textRect.y + shadow.offsetY),
        shadowColor.withOpacity(opacity),
        style.text,
        textMaxWidth
      )
    output.add drawText(id, text, vec2(textRect.x, textRect.y), textColor.withOpacity(opacity), style.text, textMaxWidth)
    output.addTextDecoration(textRect, style.text, textColor, opacity, id)
  if node.kind == nkImage:
    output.add drawImage(id, node.imageSource, nodeRect, opacity, style.image)

  if needsClip:
    output.add pushClip(
      overflowClipRect(nodeRect, style, item.padding), style.box.borderRadius
    )

  if node.kind == nkBox:
    output.addCustomPaint(
      customPaintProvider, style, cpsUnderlay, id, nodeRect, opacity
    )
    output.addCustomPaint(
      customPaintProvider, style, cpsMask, id, nodeRect, opacity
    )
    output.addCustomPaint(
      customPaintProvider, style, cpsFilter, id, nodeRect, opacity
    )

  if node.renderSurfaceId.isSome and not surfaceProvider.isNil:
    let contentRect = presentedContentBounds(nodeRect, style, item.padding)
    output.add pushClip(contentRect, style.box.borderRadius)
    for command in surfaceProvider(
        node.renderSurfaceId.get, id, contentRect, opacity):
      output.add command
      if command.kind == pcPushTransform:
        hasTransform = true
    output.add popClip()

  if not style.hidesContents:
    let ownOffset = scroll.scrollOffset(id)
    let childTranslation = vec2(translation.x - ownOffset.x, translation.y - ownOffset.y)
    let children = node.childrenInPaintOrder(styles)
    for child in children:
      paintNode(
        tree, styles, layout, boxIndices, child, opacity, output, hasTransform,
        scroll, childTranslation,
        surfaceProvider,
        customPaintProvider,
        overlayPass = overlayPass
      )

  if node.kind == nkBox:
    output.addCustomPaint(
      customPaintProvider, style, cpsOverlay, id, nodeRect, opacity
    )

  let scrollMetrics = scroll.metricsFor(id)
  if node.kind == nkBox and scrollMetrics.isSome:
    output.addScrollbars(
      nodeRect, style, item.padding, scrollMetrics.get, opacity, id
    )

  if needsClip:
    output.add popClip()

  if visualClip.isSome:
    output.add popClip()

  if transformed:
    output.add popTransform()

proc collectOverlayRoots(
    tree: Tree;
    styles: ResolvedTree;
    id: NodeId;
    output: var seq[NodeId]
) =
  let node = tree.nodes[id.nodeIndex]
  if node.parent.isSome and styles.styles[id.nodeIndex].layout.zIndex > 0:
    output.add id
    return
  for child in node.children:
    collectOverlayRoots(tree, styles, child, output)

type
  AncestorPaintScope = object
    clipCount: int
    transformed: bool

  AncestorPaintContext = object
    opacity: float32
    translation: Vec2
    scopes: seq[AncestorPaintScope]

proc pushAncestorPaintContext(
    tree: Tree;
    styles: ResolvedTree;
    layout: LayoutResult;
    boxIndices: openArray[int];
    scroll: ScrollState;
    id: NodeId;
    output: var seq[PaintCommand];
    hasTransform: var bool
): AncestorPaintContext =
  let presentation = ancestorPresentationContext(
    tree, layout, boxIndices, styles, scroll, id
  )
  result.opacity = presentation.opacity
  result.translation = presentation.translation
  for ancestor in presentation.ancestors:
    let style {.cursor.} = styles.styles[ancestor.node.nodeIndex]
    var scope: AncestorPaintScope
    if not ancestor.ownTransform.isIdentity:
      output.add pushTransform(ancestor.ownTransform)
      scope.transformed = true
      hasTransform = true
    let visualClip = insetClipRect(ancestor.sourceBounds, style.visual.clipPath)
    if visualClip.isSome:
      output.add pushClip(visualClip.get, style.box.borderRadius)
      inc scope.clipCount
    if tree.nodes[ancestor.node.nodeIndex].kind == nkBox and
        style.clipsOverflow():
      output.add pushClip(
        overflowClipRect(ancestor.sourceBounds, style, ancestor.padding),
        style.box.borderRadius
      )
      inc scope.clipCount
    result.scopes.add scope

proc popAncestorPaintContext(
    context: AncestorPaintContext;
    output: var seq[PaintCommand]
) =
  for index in countdown(context.scopes.high, 0):
    for _ in 0 ..< context.scopes[index].clipCount:
      output.add popClip()
    if context.scopes[index].transformed:
      output.add popTransform()

proc buildPaintCommands*(
    tree: Tree;
    styles: ResolvedTree;
    layout: LayoutResult;
    scroll: ScrollState;
    surfaceProvider: SurfacePaintProvider = nil;
    customPaintProvider: CustomPaintProvider = nil
): seq[PaintCommand] =
  var hasTransform = false
  if tree.root.isSome:
    withLayoutBoxIndices(layout, tree.nodes.len, boxIndices):
      paintNode(
        tree, styles, layout, boxIndices, tree.root.get, 1.0'f32, result,
        hasTransform, scroll, vec2(0, 0), surfaceProvider, customPaintProvider
      )
      var overlays: seq[NodeId]
      collectOverlayRoots(tree, styles, tree.root.get, overlays)
      for overlay in overlays.overlayRootsInPaintOrder(styles):
        let context = pushAncestorPaintContext(
          tree, styles, layout, boxIndices, scroll, overlay, result, hasTransform
        )
        paintNode(
          tree, styles, layout, boxIndices, overlay, context.opacity, result,
          hasTransform, scroll, context.translation, surfaceProvider,
          customPaintProvider,
          overlayPass = true
        )
        popAncestorPaintContext(context, result)
      if hasTransform:
        result.resolveTransformBounds()

proc buildPaintCommands*(tree: Tree; styles: ResolvedTree; layout: LayoutResult): seq[PaintCommand] =
  buildPaintCommands(tree, styles, layout, initScrollState())

proc buildPaintCommandsForSubtree*(
    tree: Tree;
    styles: ResolvedTree;
    layout: LayoutResult;
    root: NodeId;
    scroll: ScrollState;
    surfaceProvider: SurfacePaintProvider = nil;
    customPaintProvider: CustomPaintProvider = nil
): seq[PaintCommand] =
  var hasTransform = false
  if root.nodeIndex < 0 or root.nodeIndex >= tree.nodes.len:
    return
  let overlayPass =
    tree.nodes[root.nodeIndex].parent.isSome and
      styles.styles[root.nodeIndex].layout.zIndex > 0
  withLayoutBoxIndices(layout, tree.nodes.len, boxIndices):
    let context = pushAncestorPaintContext(
      tree, styles, layout, boxIndices, scroll, root, result, hasTransform
    )
    paintNode(
      tree,
      styles,
      layout,
      boxIndices,
      root,
      context.opacity,
      result,
      hasTransform,
      scroll,
      context.translation,
      surfaceProvider,
      customPaintProvider,
      overlayPass = overlayPass
    )
    popAncestorPaintContext(context, result)

    # The normal pass deliberately skips positive z-index descendants. A
    # retained subtree repaint must replay those overlays just like a full-tree
    # paint or focused controls lose popups, carets, and scrollbar children.
    var overlays: seq[NodeId]
    for child in tree.nodes[root.nodeIndex].children:
      collectOverlayRoots(tree, styles, child, overlays)
    for overlay in overlays.overlayRootsInPaintOrder(styles):
      let overlayContext = pushAncestorPaintContext(
        tree, styles, layout, boxIndices, scroll, overlay, result, hasTransform
      )
      paintNode(
        tree, styles, layout, boxIndices, overlay, overlayContext.opacity,
        result, hasTransform, scroll, overlayContext.translation, surfaceProvider,
        customPaintProvider,
        overlayPass = true
      )
      popAncestorPaintContext(overlayContext, result)
    if hasTransform:
      result.resolveTransformBounds()

proc buildPaintCommandsForSubtree*(
    tree: Tree;
    styles: ResolvedTree;
    layout: LayoutResult;
    root: NodeId
): seq[PaintCommand] =
  buildPaintCommandsForSubtree(tree, styles, layout, root, initScrollState())
