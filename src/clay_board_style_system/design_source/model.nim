import std/[algorithm, options, strutils]

import ../core/[color, declaration, node, rule, selector, style_value]

type
  DesignNodeKind* = enum
    dnkFrame,
    dnkText,
    dnkImage,
    dnkComponent,
    dnkInstance

  DesignLayoutDirection* = enum
    dldNone,
    dldRow,
    dldColumn

  DesignAlign* = enum
    daNone,
    daStart,
    daCenter,
    daEnd,
    daStretch,
    daSpaceBetween

  DesignEdges* = object
    top*, right*, bottom*, left*: float32

  DesignStroke* = object
    width*: float32
    color*: Color

  DesignTextStyle* = object
    fontFamilies*: seq[string]
    fontSize*: Option[float32]
    fontWeight*: Option[float32]
    fontStyle*: Option[string]
    lineHeight*: Option[float32]
    letterSpacing*: Option[float32]
    textAlign*: Option[string]
    color*: Option[Color]

  DesignStyle* = object
    width*, height*: Option[float32]
    minWidth*, maxWidth*: Option[float32]
    minHeight*, maxHeight*: Option[float32]
    padding*: Option[DesignEdges]
    gap*: Option[float32]
    layoutDirection*: DesignLayoutDirection
    alignItems*: DesignAlign
    justifyContent*: DesignAlign
    backgroundColor*: Option[Color]
    stroke*: Option[DesignStroke]
    radius*: Option[float32]
    opacity*: Option[float32]
    text*: DesignTextStyle

  DesignSourceNode* = object
    sourceId*: string
    name*: string
    kind*: DesignNodeKind
    id*: string
    groups*: seq[string]
    text*: string
    style*: DesignStyle
    children*: seq[DesignSourceNode]

  DesignSourcePage* = object
    sourceId*: string
    name*: string
    nodes*: seq[DesignSourceNode]

  DesignSourceDocument* = object
    sourceId*: string
    name*: string
    pages*: seq[DesignSourcePage]

  DesignBuildOptions* = object
    includeLocalGroups*: bool
    emitLocalStyleRules*: bool
    localStylePrefix*: string

  DesignBuildResult* = object
    tree*: Tree
    sheet*: StyleSheet

  StyleInjectionPlacement* = enum
    sipBeforeGenerated,
    sipAfterGenerated

  ViewportCondition* = object
    minWidth*, maxWidth*: Option[float32]
    minHeight*, maxHeight*: Option[float32]

  StyleInjection* = object
    name*: string
    sheet*: StyleSheet
    placement*: StyleInjectionPlacement
    priority*: int
    condition*: Option[ViewportCondition]

proc designEdges*(value: SomeNumber): DesignEdges =
  DesignEdges(
    top: value.float32,
    right: value.float32,
    bottom: value.float32,
    left: value.float32
  )

proc designEdges*(top, right, bottom, left: SomeNumber): DesignEdges =
  DesignEdges(
    top: top.float32,
    right: right.float32,
    bottom: bottom.float32,
    left: left.float32
  )

proc designStroke*(width: SomeNumber; color: Color): DesignStroke =
  DesignStroke(width: width.float32, color: color)

proc designFrame*(
    sourceId, name: string;
    id = "";
    groups: openArray[string] = []
): DesignSourceNode =
  result = DesignSourceNode(sourceId: sourceId, name: name, kind: dnkFrame, id: id)
  for group in groups:
    result.groups.add group

proc designText*(
    sourceId, name, text: string;
    id = "";
    groups: openArray[string] = []
): DesignSourceNode =
  result = DesignSourceNode(sourceId: sourceId, name: name, kind: dnkText, id: id, text: text)
  for group in groups:
    result.groups.add group

proc designImage*(
    sourceId, name: string;
    id = "";
    groups: openArray[string] = []
): DesignSourceNode =
  result = DesignSourceNode(sourceId: sourceId, name: name, kind: dnkImage, id: id)
  for group in groups:
    result.groups.add group

proc addChild*(node: var DesignSourceNode; child: DesignSourceNode) =
  node.children.add child

proc designPage*(sourceId, name: string; nodes: openArray[DesignSourceNode]): DesignSourcePage =
  result = DesignSourcePage(sourceId: sourceId, name: name)
  for node in nodes:
    result.nodes.add node

proc designDocument*(sourceId, name: string; pages: openArray[DesignSourcePage]): DesignSourceDocument =
  result = DesignSourceDocument(sourceId: sourceId, name: name)
  for page in pages:
    result.pages.add page

proc defaultDesignBuildOptions*(): DesignBuildOptions =
  DesignBuildOptions(includeLocalGroups: true, emitLocalStyleRules: true, localStylePrefix: "ds")

proc viewportCondition*(
    minWidth: Option[float32] = none(float32);
    maxWidth: Option[float32] = none(float32);
    minHeight: Option[float32] = none(float32);
    maxHeight: Option[float32] = none(float32)
): ViewportCondition =
  ViewportCondition(
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight
  )

proc minViewportWidth*(value: SomeNumber): ViewportCondition =
  viewportCondition(minWidth = some(value.float32))

proc maxViewportWidth*(value: SomeNumber): ViewportCondition =
  viewportCondition(maxWidth = some(value.float32))

proc matches*(condition: ViewportCondition; viewportWidth, viewportHeight: float32): bool =
  if condition.minWidth.isSome and viewportWidth < condition.minWidth.get:
    return false
  if condition.maxWidth.isSome and viewportWidth > condition.maxWidth.get:
    return false
  if condition.minHeight.isSome and viewportHeight < condition.minHeight.get:
    return false
  if condition.maxHeight.isSome and viewportHeight > condition.maxHeight.get:
    return false
  true

proc styleInjection*(
    name: string;
    sheet: StyleSheet;
    placement = sipAfterGenerated;
    priority = 0;
    condition = none(ViewportCondition)
): StyleInjection =
  StyleInjection(
    name: name,
    sheet: sheet,
    placement: placement,
    priority: priority,
    condition: condition
  )

proc fallbackRole(kind: DesignNodeKind): string =
  case kind
  of dnkFrame: "frame"
  of dnkText: "text"
  of dnkImage: "image"
  of dnkComponent: "component"
  of dnkInstance: "instance"

proc sanitizeTagPart(value: string): string =
  for ch in value:
    if ch.isAlphaNumeric:
      result.add ch.toLowerAscii
    elif ch in {'-', '_'}:
      result.add ch
    else:
      if result.len == 0 or result[^1] != '-':
        result.add '-'
  result = result.strip(chars = {'-'})
  if result.len == 0:
    result = "node"

proc localGroup(options: DesignBuildOptions; node: DesignSourceNode; path: string): string =
  let source =
    if node.sourceId.len > 0: node.sourceId
    elif node.name.len > 0: node.name
    else: path
  options.localStylePrefix & "-" & sanitizeTagPart(source)

proc alignKeyword(value: DesignAlign; property: string): Option[string] =
  case value
  of daNone:
    none(string)
  of daStart:
    some("start")
  of daCenter:
    some("center")
  of daEnd:
    some("end")
  of daStretch:
    if property == "justify-content": some("start") else: some("stretch")
  of daSpaceBetween:
    if property == "justify-content": some("space-between") else: some("start")

proc addLengthDecl(result: var seq[Declaration]; property: string; value: Option[float32]) =
  if value.isSome:
    result.add decl(property, px(value.get))

proc addTextDecls(result: var seq[Declaration]; text: DesignTextStyle) =
  if text.fontFamilies.len > 0:
    result.add decl("font-family", keyword(text.fontFamilies.join(",")))
  if text.fontSize.isSome:
    result.add decl("font-size", px(text.fontSize.get))
  if text.fontWeight.isSome:
    result.add decl("font-weight", number(text.fontWeight.get))
  if text.fontStyle.isSome:
    result.add decl("font-style", keyword(text.fontStyle.get))
  if text.lineHeight.isSome:
    result.add decl("line-height", number(text.lineHeight.get))
  if text.letterSpacing.isSome:
    result.add decl("letter-spacing", px(text.letterSpacing.get))
  if text.textAlign.isSome:
    result.add decl("text-align", keyword(text.textAlign.get))
  if text.color.isSome:
    result.add decl("color", colorValue(text.color.get))

proc styleDeclarations*(style: DesignStyle): seq[Declaration] =
  result.addLengthDecl("width", style.width)
  result.addLengthDecl("height", style.height)
  result.addLengthDecl("min-width", style.minWidth)
  result.addLengthDecl("max-width", style.maxWidth)
  result.addLengthDecl("min-height", style.minHeight)
  result.addLengthDecl("max-height", style.maxHeight)

  if style.padding.isSome:
    let padding = style.padding.get
    if padding.top == padding.right and padding.top == padding.bottom and padding.top == padding.left:
      result.add decl("padding", px(padding.top))
    else:
      result.add decl("padding-top", px(padding.top))
      result.add decl("padding-right", px(padding.right))
      result.add decl("padding-bottom", px(padding.bottom))
      result.add decl("padding-left", px(padding.left))

  if style.gap.isSome:
    result.add decl("gap", px(style.gap.get))

  case style.layoutDirection
  of dldNone:
    discard
  of dldRow:
    result.add decl("display", keyword("flex"))
    result.add decl("flex-direction", keyword("row"))
  of dldColumn:
    result.add decl("display", keyword("flex"))
    result.add decl("flex-direction", keyword("column"))

  let alignItems = alignKeyword(style.alignItems, "align-items")
  if alignItems.isSome:
    result.add decl("align-items", keyword(alignItems.get))
  let justifyContent = alignKeyword(style.justifyContent, "justify-content")
  if justifyContent.isSome:
    result.add decl("justify-content", keyword(justifyContent.get))

  if style.backgroundColor.isSome:
    result.add decl("background-color", colorValue(style.backgroundColor.get))
  if style.stroke.isSome:
    result.add decl("border-width", px(style.stroke.get.width))
    result.add decl("border-style", keyword("solid"))
    result.add decl("border-color", colorValue(style.stroke.get.color))
  if style.radius.isSome:
    result.add decl("border-radius", px(style.radius.get))
  if style.opacity.isSome:
    result.add decl("opacity", number(style.opacity.get))

  result.addTextDecls(style.text)

proc appendDesignNode(
    tree: var Tree;
    rules: var seq[StyleRule];
    node: DesignSourceNode;
    parent: Option[NodeId];
    options: DesignBuildOptions;
    path: string
): NodeId =
  let generatedGroup = localGroup(options, node, path)
  var groups = node.groups
  if options.includeLocalGroups or options.emitLocalStyleRules:
    groups.add generatedGroup

  let nodeId =
    if node.id.len > 0: node.id
    else: fallbackRole(node.kind)

  case node.kind
  of dnkText:
    if parent.isSome:
      result = tree.addText(parent.get, node.text, id = nodeId, groups = groups)
    else:
      result = tree.addBox(id = nodeId, groups = groups)
      tree.nodes[result.nodeIndex].text = node.text
  else:
    result = tree.addBox(parent = parent, id = nodeId, groups = groups)

  tree.addAttribute(result, "data-design-source-id", node.sourceId)
  tree.addAttribute(result, "data-design-name", node.name)

  let declarations = node.style.styleDeclarations()
  if options.emitLocalStyleRules and declarations.len > 0:
    rules.add rule(group(generatedGroup), declarations)

  for index, child in node.children:
    discard tree.appendDesignNode(
      rules,
      child,
      some(result),
      options,
      path & "-" & $index
    )

proc buildCbss*(page: DesignSourcePage; options = defaultDesignBuildOptions()): DesignBuildResult =
  result.tree = initTree()
  var rules: seq[StyleRule] = @[]
  for index, node in page.nodes:
    discard result.tree.appendDesignNode(rules, node, none(NodeId), options, $index)
  result.sheet = StyleSheet(rules: rules)

proc buildCbss*(document: DesignSourceDocument; pageIndex = 0; options = defaultDesignBuildOptions()): DesignBuildResult =
  if pageIndex < 0 or pageIndex >= document.pages.len:
    return DesignBuildResult(tree: initTree(), sheet: styleSheet([]))
  document.pages[pageIndex].buildCbss(options)

proc injectionApplies(
    injection: StyleInjection;
    viewportWidth, viewportHeight: Option[float32]
): bool =
  if injection.condition.isNone:
    return true
  if viewportWidth.isNone or viewportHeight.isNone:
    return false
  injection.condition.get.matches(viewportWidth.get, viewportHeight.get)

proc compareInjections(a, b: StyleInjection): int =
  result = cmp(a.priority, b.priority)
  if result != 0:
    return
  result = cmp(a.name, b.name)

proc injectedStyleSheets*(
    built: DesignBuildResult;
    injections: openArray[StyleInjection];
    viewportWidth = none(float32);
    viewportHeight = none(float32)
): seq[StyleSheet] =
  var before: seq[StyleInjection]
  var after: seq[StyleInjection]
  for injection in injections:
    if not injection.injectionApplies(viewportWidth, viewportHeight):
      continue
    case injection.placement
    of sipBeforeGenerated:
      before.add injection
    of sipAfterGenerated:
      after.add injection

  before.sort(compareInjections)
  after.sort(compareInjections)

  for injection in before:
    result.add injection.sheet
  result.add built.sheet
  for injection in after:
    result.add injection.sheet

proc styleSheets*(
    built: DesignBuildResult;
    externalSheets: openArray[StyleSheet] = [];
    externalOverrides = true
): seq[StyleSheet] =
  if externalOverrides:
    result.add built.sheet
    for sheet in externalSheets:
      result.add sheet
  else:
    for sheet in externalSheets:
      result.add sheet
    result.add built.sheet
