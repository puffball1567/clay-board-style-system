import std/options

import ../core/[computed_style, geometry, node, style_resolver]
import ./[layout, overflow_geometry, scroll_state]
import ./transform_geometry

type
  PresentedAncestor* = object
    node*: NodeId
    bounds*: Rect
    sourceBounds*: Rect
    transform*: Affine2D

  PresentationContext* = object
    translation*: Vec2
    clip*: Option[Rect]
    opacity*: float32
    visible*: bool
    ancestors*: seq[PresentedAncestor]
    transform*: Affine2D
    clipShapes*: seq[TransformedRect]

  NodePresentation* = object
    node*: NodeId
    bounds*: Rect
    clip*: Rect
    opacity*: float32
    visible*: bool
    sourceBounds*: Rect
    transform*: Affine2D

proc presentedContentBounds*(bounds: Rect; style: ComputedStyle): Rect =
  ## Returns the pixels owned by replaced/custom content. CBSS retains
  ## ownership of the border and padding around this rectangle.
  let padding =
    if style.box.padding.isSome: style.box.padding.get
    else: edges(0)
  let border = style.box.borderWidths
  let left = padding.left +
    (if style.box.borderSideVisible.left: border.left else: 0.0'f32)
  let right = padding.right +
    (if style.box.borderSideVisible.right: border.right else: 0.0'f32)
  let top = padding.top +
    (if style.box.borderSideVisible.top: border.top else: 0.0'f32)
  let bottom = padding.bottom +
    (if style.box.borderSideVisible.bottom: border.bottom else: 0.0'f32)
  rect(
    bounds.x + left,
    bounds.y + top,
    max(0.0'f32, bounds.w - left - right),
    max(0.0'f32, bounds.h - top - bottom)
  )

proc contentBounds*(presentation: NodePresentation; style: ComputedStyle): Rect =
  presentation.transform.transformedBounds(
    presentedContentBounds(presentation.sourceBounds, style)
  )

proc sourceContentBounds*(presentation: NodePresentation; style: ComputedStyle): Rect =
  presentedContentBounds(presentation.sourceBounds, style)

proc contentClip*(presentation: NodePresentation; style: ComputedStyle): Rect =
  presentation.contentBounds(style).intersection(presentation.clip)

proc hidesPresentedContents(style: ComputedStyle): bool =
  style.visual.contentVisibility.isSome and
    style.visual.contentVisibility.get == "hidden"

proc ancestorPresentationContext*(
    tree: Tree;
    layout: LayoutResult;
    boxIndices: openArray[int];
    styles: ResolvedTree;
    scroll: ScrollState;
    root: NodeId
): PresentationContext =
  result.visible = true
  result.opacity = 1.0'f32
  result.transform = identityAffine2D()
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
        style.hidesPresentedContents:
      result.visible = false
      return

    let sourceBounds = layout.boxes[boxIndex].rect.translated(result.translation)
    let ownTransform = resolvedTransform(style, sourceBounds)
    let worldTransform = result.transform * ownTransform
    let bounds = worldTransform.transformedBounds(sourceBounds)
    result.ancestors.add PresentedAncestor(
      node: ancestor,
      bounds: bounds,
      sourceBounds: sourceBounds,
      transform: worldTransform
    )
    if tree.nodes[ancestor.nodeIndex].kind == nkBox and style.clipsOverflow():
      let ownClipShape = transformedRect(
        overflowClipRect(sourceBounds, style), worldTransform
      )
      let ownClip = ownClipShape.bounds
      result.clipShapes.add ownClipShape
      result.clip =
        if result.clip.isSome:
          some(result.clip.get.intersection(ownClip))
        else:
          some(ownClip)
      if result.clip.get.isEmpty:
        result.visible = false
        return

    result.opacity *= style.visual.opacity
    result.transform = worldTransform
    let offset = scroll.scrollOffset(ancestor)
    result.translation.x -= offset.x
    result.translation.y -= offset.y

proc presentationForNode*(
    tree: Tree;
    layout: LayoutResult;
    styles: ResolvedTree;
    id: NodeId;
    scroll: ScrollState
): Option[NodePresentation] =
  if not tree.isValid(id):
    return none(NodePresentation)
  let boxIndices = layout.layoutBoxIndices(tree.nodes.len)
  let boxIndex = boxIndices.boxIndexFor(id)
  if boxIndex < 0:
    return none(NodePresentation)
  let context = ancestorPresentationContext(
    tree, layout, boxIndices, styles, scroll, id
  )
  if not context.visible:
    return none(NodePresentation)
  let style {.cursor.} = styles.styles[id.nodeIndex]
  if not style.visual.visible or style.layout.display == dkNone or
      style.hidesPresentedContents:
    return none(NodePresentation)
  let sourceBounds = layout.boxes[boxIndex].rect.translated(context.translation)
  let transform = context.transform * resolvedTransform(style, sourceBounds)
  let bounds = transform.transformedBounds(sourceBounds)
  let clip =
    if context.clip.isSome: bounds.intersection(context.clip.get)
    else: bounds
  let opacity = context.opacity * style.visual.opacity
  some(NodePresentation(
    node: id,
    bounds: bounds,
    clip: clip,
    opacity: opacity,
    visible: not clip.isEmpty and opacity > 0,
    sourceBounds: sourceBounds,
    transform: transform
  ))

proc presentationForNode*(
    tree: Tree;
    layout: LayoutResult;
    styles: ResolvedTree;
    id: NodeId
): Option[NodePresentation] =
  presentationForNode(tree, layout, styles, id, initScrollState())
