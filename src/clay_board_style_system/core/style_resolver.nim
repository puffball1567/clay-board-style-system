import std/[algorithm, options, strutils, tables]
import ./[
  computed_style,
  declaration,
  diagnostics,
  geometry,
  node,
  property,
  registry,
  rule,
  selector,
  style_context
]

type
  ResolvedTree* = object
    styles*: seq[ComputedStyle]
    viewportSize*: Option[Size]

  IndexedRule = object
    sheetIndex: int
    ruleIndex: int
    sourceOrder: int

  RuleIndex = object
    targeted: seq[seq[IndexedRule]]
    kinds: array[NodeKind, seq[IndexedRule]]
    ids: Table[string, seq[IndexedRule]]
    codes: Table[string, seq[IndexedRule]]
    groups: Table[string, seq[IndexedRule]]
    general: seq[IndexedRule]

  MatchedDeclaration = object
    declaration: Declaration
    cascadeLayer: int
    priority: int
    specificity: int
    sourceOrder: int

proc compareMatched(a, b: MatchedDeclaration): int =
  result = cmp(a.cascadeLayer, b.cascadeLayer)
  if result != 0:
    return
  result = cmp(a.priority, b.priority)
  if result != 0:
    return
  result = cmp(a.specificity, b.specificity)
  if result != 0:
    return
  result = cmp(a.sourceOrder, b.sourceOrder)

proc buildRuleIndex(tree: Tree; sheets: openArray[StyleSheet]): RuleIndex =
  ## Each rule is registered under one required selector condition. A matching
  ## node must satisfy that condition, so this narrows candidates without
  ## changing selector semantics or cascade order.
  result.targeted = newSeq[seq[IndexedRule]](tree.nodes.len)
  result.ids = initTable[string, seq[IndexedRule]]()
  result.codes = initTable[string, seq[IndexedRule]]()
  result.groups = initTable[string, seq[IndexedRule]]()
  var sourceOrder = 0
  for sheetIndex, sheet in sheets:
    for ruleIndex, rule in sheet.rules:
      let indexed = IndexedRule(
        sheetIndex: sheetIndex,
        ruleIndex: ruleIndex,
        sourceOrder: sourceOrder
      )
      if rule.selector.nodeId.isSome:
        let nodeIndex = rule.selector.nodeId.get.nodeIndex
        if nodeIndex >= 0 and nodeIndex < result.targeted.len:
          result.targeted[nodeIndex].add indexed
      elif rule.selector.id.isSome:
        result.ids.mgetOrPut(rule.selector.id.get, @[]).add indexed
      elif rule.selector.code.isSome:
        result.codes.mgetOrPut(rule.selector.code.get, @[]).add indexed
      elif rule.selector.groups.len > 0:
        result.groups.mgetOrPut(rule.selector.groups[0], @[]).add indexed
      elif rule.selector.elementKind.isSome:
        result.kinds[rule.selector.elementKind.get].add indexed
      else:
        result.general.add indexed
      sourceOrder += max(1, rule.declarations.len)

proc addMatchingDeclarations(
    indexedRules: openArray[IndexedRule];
    id: NodeId;
    node: Node;
    sheets: openArray[StyleSheet];
    matched: var seq[MatchedDeclaration]
) =
  for indexed in indexedRules:
    let rule = sheets[indexed.sheetIndex].rules[indexed.ruleIndex]
    if rule.selector.matches(node, some(id)):
      for declarationIndex, declaration in rule.declarations:
        matched.add MatchedDeclaration(
          declaration: declaration,
          cascadeLayer: rule.cascadeLayer,
          priority: rule.priority,
          specificity: rule.selector.specificity,
          sourceOrder:
            if rule.sourceOrder != 0: rule.sourceOrder
            else: indexed.sourceOrder + declarationIndex
        )

proc matchingContext(
    id: NodeId;
    node: Node;
    sheets: openArray[StyleSheet];
    index: RuleIndex
): StyleContext =
  var matched: seq[MatchedDeclaration]
  addMatchingDeclarations(index.general, id, node, sheets, matched)
  if id.nodeIndex >= 0 and id.nodeIndex < index.targeted.len:
    addMatchingDeclarations(index.targeted[id.nodeIndex], id, node, sheets, matched)
  if node.id.len > 0 and node.id in index.ids:
    addMatchingDeclarations(index.ids[node.id], id, node, sheets, matched)
  if node.code.len > 0 and node.code in index.codes:
    addMatchingDeclarations(index.codes[node.code], id, node, sheets, matched)
  for group in node.groups:
    if group in index.groups:
      addMatchingDeclarations(index.groups[group], id, node, sheets, matched)
  addMatchingDeclarations(index.kinds[node.kind], id, node, sheets, matched)

  matched.sort(compareMatched)
  result = initStyleContext()
  for item in matched:
    result.addDeclaration item.declaration

proc partitionFontContexts(
    context: StyleContext;
    collectDescriptor: bool
): tuple[
    fontSize, lineHeight, descriptor, remaining: StyleContext] =
  result.fontSize = initStyleContext()
  result.lineHeight = initStyleContext()
  result.descriptor = initStyleContext()
  result.remaining = initStyleContext()
  for declaration in context.declarations:
    case declaration.property
    of "font-size":
      result.fontSize.addDeclaration declaration
    of "line-height":
      result.lineHeight.addDeclaration declaration
    else:
      if collectDescriptor and declaration.property.startsWith("font-"):
        result.descriptor.addDeclaration declaration
      result.remaining.addDeclaration declaration

proc metricTextStyle(
    parent: ComputedStyleRef;
    fontSize, lineHeight: float32;
    descriptorContext: StyleContext;
    resolvedDescriptor: ComputedTextStyle
): ComputedTextStyle =
  ## Build only the font-selection state needed by a metrics provider. Keeping
  ## this separate avoids coupling the core resolver to a concrete text engine.
  if parent.isSome:
    result = parent.get.text
  result.fontSize = some(fontSize)
  result.lineHeight = some(lineHeight)
  for declaration in descriptorContext.declarations:
    case declaration.property
    of "font-family":
      result.fontFamily = resolvedDescriptor.fontFamily
      result.fontFamilies = resolvedDescriptor.fontFamilies
    of "font-style":
      result.fontStyle = resolvedDescriptor.fontStyle
    of "font-weight":
      result.fontWeight = resolvedDescriptor.fontWeight
    of "font-stretch", "font-width":
      result.fontStretch = resolvedDescriptor.fontStretch
      result.fontWidth = resolvedDescriptor.fontWidth
    of "font-feature-settings":
      result.fontFeatureSettings = resolvedDescriptor.fontFeatureSettings
    of "font-variation-settings":
      result.fontVariationSettings = resolvedDescriptor.fontVariationSettings
    of "font-kerning":
      result.fontKerning = resolvedDescriptor.fontKerning
    of "font-optical-sizing":
      result.fontOpticalSizing = resolvedDescriptor.fontOpticalSizing
    of "font-size-adjust":
      result.fontSizeAdjust = resolvedDescriptor.fontSizeAdjust
    of "font-variant":
      result.fontVariant = resolvedDescriptor.fontVariant
    of "font-variant-ligatures":
      result.fontVariantLigatures = resolvedDescriptor.fontVariantLigatures
    of "font-variant-caps":
      result.fontVariantCaps = resolvedDescriptor.fontVariantCaps
    of "font-variant-numeric":
      result.fontVariantNumeric = resolvedDescriptor.fontVariantNumeric
    of "font-variant-east-asian":
      result.fontVariantEastAsian = resolvedDescriptor.fontVariantEastAsian
    of "font-variant-position":
      result.fontVariantPosition = resolvedDescriptor.fontVariantPosition
    of "font-variant-alternates":
      result.fontVariantAlternates = resolvedDescriptor.fontVariantAlternates
    of "font-variant-emoji":
      result.fontVariantEmoji = resolvedDescriptor.fontVariantEmoji
    else:
      discard

proc resolveNode(
    tree: Tree;
    id: NodeId;
    baseContext: StyleContext;
    sheets: openArray[StyleSheet];
    ruleIndex: RuleIndex;
    registry: PropertyRegistry;
    parent: ComputedStyleRef;
    rootFontSize: float32;
    rootLineHeight: float32;
    rootFontMetrics: FontUnitMetrics;
    parentFontMetrics: FontUnitMetrics;
    fontMetricsResolver: FontUnitMetricsResolver;
    viewportSize: Option[Size];
    diagnostics: var Diagnostics;
    result: var ResolvedTree
) =
  let node = tree.nodes[id.nodeIndex]
  let context = mergeStyles(baseContext, matchingContext(id, node, sheets, ruleIndex))
  let inheritedFontSize =
    if parent.isSome and parent.get.text.fontSize.isSome:
      parent.get.text.fontSize.get
    else:
      rootFontSize
  let inheritsNormalLineHeight =
    parent.isNone or parent.get.text.lineHeight.isNone
  let inheritedLineHeight =
    if parent.isSome and parent.get.text.lineHeight.isSome:
      parent.get.text.lineHeight.get
    elif parent.isSome and parent.get.text.fontSize.isSome:
      parent.get.text.fontSize.get * 1.2'f32
    else:
      rootLineHeight
  let fontContexts = context.partitionFontContexts(
    not fontMetricsResolver.isNil
  )
  let fontEnv = ResolveEnv(
    parent: parent,
    rootFontSize: some(rootFontSize),
    currentFontSize: some(inheritedFontSize),
    rootLineHeight: some(rootLineHeight),
    currentLineHeight: some(inheritedLineHeight),
    rootXHeight: some(rootFontMetrics.xHeight),
    currentXHeight: some(parentFontMetrics.xHeight),
    rootZeroAdvance: some(rootFontMetrics.zeroAdvance),
    currentZeroAdvance: some(parentFontMetrics.zeroAdvance),
    viewportSize: viewportSize
  )
  let resolvedFont = resolveStyles(
    fontContexts.fontSize, registry, fontEnv, diagnostics
  )
  let currentFontSize =
    if resolvedFont.text.fontSize.isSome:
      resolvedFont.text.fontSize.get
    else:
      inheritedFontSize
  let effectiveRootFontSize =
    if parent.isSome: rootFontSize
    else: currentFontSize
  let hasLocalLineHeight = fontContexts.lineHeight.declarations.len > 0
  var currentLineHeight =
    if inheritsNormalLineHeight:
      currentFontSize * 1.2'f32
    else:
      inheritedLineHeight
  var storedLineHeight =
    if parent.isSome: parent.get.text.lineHeight
    else: none(float32)
  let currentFontMetrics =
    if fontMetricsResolver.isNil:
      fallbackFontUnitMetrics(currentFontSize)
    else:
      let descriptorStyle =
        if fontContexts.descriptor.declarations.len > 0:
          var descriptorDiagnostics: Diagnostics
          resolveStyles(
            fontContexts.descriptor, registry, fontEnv, descriptorDiagnostics
          ).text
        else:
          ComputedTextStyle()
      let metricsStyle = metricTextStyle(
        parent,
        currentFontSize,
        currentLineHeight,
        fontContexts.descriptor,
        descriptorStyle
      )
      resolveFontUnitMetrics(fontMetricsResolver, metricsStyle)
  if hasLocalLineHeight:
    let lineHeightEnv = ResolveEnv(
      parent: parent,
      rootFontSize: some(effectiveRootFontSize),
      currentFontSize: some(currentFontSize),
      rootLineHeight: some(rootLineHeight),
      currentLineHeight: some(inheritedLineHeight),
      rootXHeight: some(rootFontMetrics.xHeight),
      currentXHeight: some(currentFontMetrics.xHeight),
      rootZeroAdvance: some(rootFontMetrics.zeroAdvance),
      currentZeroAdvance: some(currentFontMetrics.zeroAdvance),
      viewportSize: viewportSize
    )
    let resolvedLineHeight = resolveStyles(
      fontContexts.lineHeight, registry, lineHeightEnv, diagnostics
    )
    if resolvedLineHeight.text.lineHeight.isSome:
      currentLineHeight = resolvedLineHeight.text.lineHeight.get
    storedLineHeight = resolvedLineHeight.text.lineHeight
  let effectiveRootLineHeight =
    if parent.isSome: rootLineHeight
    else: currentLineHeight
  let effectiveRootFontMetrics =
    if parent.isSome: rootFontMetrics
    else: currentFontMetrics
  let env = ResolveEnv(
    parent: parent,
    rootFontSize: some(effectiveRootFontSize),
    currentFontSize: some(currentFontSize),
    rootLineHeight: some(effectiveRootLineHeight),
    currentLineHeight: some(currentLineHeight),
    rootXHeight: some(effectiveRootFontMetrics.xHeight),
    currentXHeight: some(currentFontMetrics.xHeight),
    rootZeroAdvance: some(effectiveRootFontMetrics.zeroAdvance),
    currentZeroAdvance: some(currentFontMetrics.zeroAdvance),
    viewportSize: viewportSize
  )
  var style = resolveStyles(
    fontContexts.remaining, registry, env, diagnostics
  )
  style.text.fontSize = some(currentFontSize)
  style.text.lineHeight = storedLineHeight
  if parent.isSome:
    if style.text.color.isNone:
      style.text.color = parent.get.text.color
    if style.text.fontSize.isNone:
      style.text.fontSize = parent.get.text.fontSize
    if style.text.fontFamily.isNone:
      style.text.fontFamily = parent.get.text.fontFamily
    if style.text.fontFamilies.len == 0:
      style.text.fontFamilies = parent.get.text.fontFamilies
    if style.text.fontStyle.isNone:
      style.text.fontStyle = parent.get.text.fontStyle
    if style.text.fontWeight.isNone:
      style.text.fontWeight = parent.get.text.fontWeight
    if style.text.fontStretch.isNone:
      style.text.fontStretch = parent.get.text.fontStretch
    if style.text.fontFeatureSettings.isNone:
      style.text.fontFeatureSettings = parent.get.text.fontFeatureSettings
    if style.text.fontVariationSettings.isNone:
      style.text.fontVariationSettings = parent.get.text.fontVariationSettings
    if style.text.fontKerning.isNone:
      style.text.fontKerning = parent.get.text.fontKerning
    if style.text.fontOpticalSizing.isNone:
      style.text.fontOpticalSizing = parent.get.text.fontOpticalSizing
    if style.text.fontSizeAdjust.isNone:
      style.text.fontSizeAdjust = parent.get.text.fontSizeAdjust
    if style.text.fontVariant.isNone:
      style.text.fontVariant = parent.get.text.fontVariant
    if style.text.fontVariantLigatures.isNone:
      style.text.fontVariantLigatures = parent.get.text.fontVariantLigatures
    if style.text.fontVariantCaps.isNone:
      style.text.fontVariantCaps = parent.get.text.fontVariantCaps
    if style.text.fontVariantNumeric.isNone:
      style.text.fontVariantNumeric = parent.get.text.fontVariantNumeric
    if style.text.fontVariantEastAsian.isNone:
      style.text.fontVariantEastAsian = parent.get.text.fontVariantEastAsian
    if style.text.fontVariantPosition.isNone:
      style.text.fontVariantPosition = parent.get.text.fontVariantPosition
    if style.text.fontVariantAlternates.isNone:
      style.text.fontVariantAlternates = parent.get.text.fontVariantAlternates
    if style.text.fontVariantEmoji.isNone:
      style.text.fontVariantEmoji = parent.get.text.fontVariantEmoji
    if style.text.fontLanguageOverride.isNone:
      style.text.fontLanguageOverride = parent.get.text.fontLanguageOverride
    if style.text.fontPalette.isNone:
      style.text.fontPalette = parent.get.text.fontPalette
    if style.text.fontSynthesis.isNone:
      style.text.fontSynthesis = parent.get.text.fontSynthesis
    if style.text.fontSynthesisPosition.isNone:
      style.text.fontSynthesisPosition = parent.get.text.fontSynthesisPosition
    if style.text.fontSynthesisSmallCaps.isNone:
      style.text.fontSynthesisSmallCaps = parent.get.text.fontSynthesisSmallCaps
    if style.text.fontSynthesisStyle.isNone:
      style.text.fontSynthesisStyle = parent.get.text.fontSynthesisStyle
    if style.text.fontSynthesisWeight.isNone:
      style.text.fontSynthesisWeight = parent.get.text.fontSynthesisWeight
    if style.text.lineHeight.isNone:
      style.text.lineHeight = parent.get.text.lineHeight
    if style.text.textAlign.isNone:
      style.text.textAlign = parent.get.text.textAlign
    if style.text.whiteSpace.isNone:
      style.text.whiteSpace = parent.get.text.whiteSpace
    if style.text.direction.isNone:
      style.text.direction = parent.get.text.direction
    if style.text.unicodeBidi.isNone:
      style.text.unicodeBidi = parent.get.text.unicodeBidi
    if style.text.writingMode.isNone:
      style.text.writingMode = parent.get.text.writingMode
    if style.text.tabSize.isNone:
      style.text.tabSize = parent.get.text.tabSize
    if not style.visual.caretColorSpecified:
      style.visual.caretColor = parent.get.visual.caretColor
      style.visual.caretColorSpecified = parent.get.visual.caretColorSpecified
    if not style.visual.accentColorSpecified:
      style.visual.accentColor = parent.get.visual.accentColor
      style.visual.accentColorSpecified = parent.get.visual.accentColorSpecified
    if style.image.objectFit.isNone:
      style.image.objectFit = parent.get.image.objectFit
    if style.image.objectPosition.isNone:
      style.image.objectPosition = parent.get.image.objectPosition
  if node.flowCollapsed:
    style.layout.display = dkNone
  result.styles[id.nodeIndex] = style

  for child in node.children:
    resolveNode(
      tree,
      child,
      baseContext,
      sheets,
      ruleIndex,
      registry,
      computedStyleRef(result.styles[id.nodeIndex]),
      effectiveRootFontSize,
      effectiveRootLineHeight,
      effectiveRootFontMetrics,
      currentFontMetrics,
      fontMetricsResolver,
      viewportSize,
      diagnostics,
      result
    )

proc resolveTreeStyles*(
    tree: Tree;
    sheets: openArray[StyleSheet];
    registry: PropertyRegistry;
    diagnostics: var Diagnostics;
    baseContext = initStyleContext();
    rootFontSize = 16.0'f32;
    viewportSize = none(Size);
    fontMetricsResolver: FontUnitMetricsResolver = nil
): ResolvedTree =
  result.viewportSize = viewportSize
  result.styles = newSeq[ComputedStyle](tree.nodes.len)
  if tree.root.isSome:
    let ruleIndex = buildRuleIndex(tree, sheets)
    let initialMetrics = resolveFontUnitMetrics(
      fontMetricsResolver,
      ComputedTextStyle(fontSize: some(rootFontSize))
    )
    resolveNode(
      tree,
      tree.root.get,
      baseContext,
      sheets,
      ruleIndex,
      registry,
      ComputedStyleRef(),
      rootFontSize,
      rootFontSize * 1.2'f32,
      initialMetrics,
      initialMetrics,
      fontMetricsResolver,
      viewportSize,
      diagnostics,
      result
    )

proc resolveSubtreeStyles*(
    tree: Tree;
    root: NodeId;
    sheets: openArray[StyleSheet];
    registry: PropertyRegistry;
    diagnostics: var Diagnostics;
    resolved: var ResolvedTree;
    baseContext = initStyleContext();
    viewportSize = none(Size);
    fontMetricsResolver: FontUnitMetricsResolver = nil
): bool =
  ## Re-resolve a stable subtree while preserving computed styles elsewhere.
  ## Callers must use full resolution when ancestors or global sheets changed.
  if tree.root.isNone or
      root.nodeIndex < 0 or root.nodeIndex >= tree.nodes.len or
      resolved.styles.len != tree.nodes.len:
    return false
  let parent = tree.nodes[root.nodeIndex].parent
  let parentStyle =
    if parent.isSome: computedStyleRef(resolved.styles[parent.get.nodeIndex])
    else: ComputedStyleRef()
  let rootFontSize =
    if tree.root.isSome and resolved.styles[
        tree.root.get.nodeIndex].text.fontSize.isSome:
      resolved.styles[tree.root.get.nodeIndex].text.fontSize.get
    else:
      16.0'f32
  let rootLineHeight =
    if tree.root.isSome and resolved.styles[
        tree.root.get.nodeIndex].text.lineHeight.isSome:
      resolved.styles[tree.root.get.nodeIndex].text.lineHeight.get
    else:
      rootFontSize * 1.2'f32
  let effectiveViewport =
    if viewportSize.isSome: viewportSize else: resolved.viewportSize
  resolved.viewportSize = effectiveViewport
  let rootMetrics = resolveFontUnitMetrics(
    fontMetricsResolver,
    resolved.styles[tree.root.get.nodeIndex].text
  )
  let parentMetrics =
    if parent.isSome:
      resolveFontUnitMetrics(
        fontMetricsResolver, resolved.styles[parent.get.nodeIndex].text
      )
    else:
      rootMetrics
  let ruleIndex = buildRuleIndex(tree, sheets)
  resolveNode(
    tree,
    root,
    baseContext,
    sheets,
    ruleIndex,
    registry,
    parentStyle,
    rootFontSize,
    rootLineHeight,
    rootMetrics,
    parentMetrics,
    fontMetricsResolver,
    effectiveViewport,
    diagnostics,
    resolved
  )
  true
