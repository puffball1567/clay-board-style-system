import std/[options, strformat]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc `$`(color: Color): string =
  &"rgba({color.r:.2f}, {color.g:.2f}, {color.b:.2f}, {color.a:.2f})"

proc main() =
  var tree = initTree()
  let root = tree.addBox(id = "toolbar")
  let save = tree.addBox(parent = some(root), id = "save-button", groups = ["button", "primary"])
  discard tree.addText(save, "Save")
  let cancel = tree.addBox(parent = some(root), id = "cancel-button", groups = ["button"])
  discard tree.addText(cancel, "Cancel")
  tree.addState(save, esHover)

  var hoverButton = group("button")
  hoverButton.requiredStates.incl esHover

  let sheet = styleSheet([
    rule(id("toolbar"), [
      decl("width", px(300)),
      decl("padding", px(8)),
      decl("gap", px(8)),
      decl("flex-direction", keyword("row")),
      decl("background-color", colorValue(rgb(0.12, 0.14, 0.16)))
    ]),
    rule(group("button"), [
      decl("padding", px(6)),
      decl("background-color", colorValue(rgb(0.22, 0.25, 0.29))),
      decl("border-color", colorValue(rgb(0.42, 0.47, 0.54))),
      decl("border-width", px(1)),
      decl("border-radius", px(4)),
      decl("color", colorValue(rgb(0.95, 0.95, 0.95))),
      decl("font-size", px(14))
    ]),
    rule(hoverButton, [
      decl("background-color", colorValue(rgb(0.30, 0.35, 0.42)))
    ])
  ])

  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(
    tree,
    [sheet],
    defaultProperties(),
    diagnostics,
    viewportSize = some(size(300, 80))
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    quit 1

  let layout = computeLayout(tree, styles, size(300, 80))
  let commands = buildPaintCommands(tree, styles, layout)

  echo "Layout boxes:"
  for item in layout.boxes:
    echo &"  node={item.node.nodeIndex} rect=({item.rect.x:.1f}, {item.rect.y:.1f}, {item.rect.w:.1f}, {item.rect.h:.1f})"

  echo "Paint commands:"
  for command in commands:
    case command.kind
    of pcPushTransform:
      let transform = command.transform
      echo &"  PushTransform matrix=({transform.m11:.2f}, {transform.m12:.2f}, {transform.m21:.2f}, {transform.m22:.2f}, {transform.tx:.1f}, {transform.ty:.1f})"
    of pcPopTransform:
      echo "  PopTransform"
    of pcPushLayer:
      echo &"  PushLayer bounds=({command.layerBounds.x:.1f}, {command.layerBounds.y:.1f}, {command.layerBounds.w:.1f}, {command.layerBounds.h:.1f}) opacity={command.layerOpacity:.2f} composite={command.layerCompositeMode}"
    of pcPopLayer:
      echo "  PopLayer"
    of pcBoxShadow:
      echo &"  BoxShadow rect=({command.shadowRect.x:.1f}, {command.shadowRect.y:.1f}, {command.shadowRect.w:.1f}, {command.shadowRect.h:.1f}) offset=({command.shadowOffsetX:.1f}, {command.shadowOffsetY:.1f}) blur={command.shadowBlur:.1f} spread={command.shadowSpread:.1f} radius={command.shadowRadius:.1f} color={command.shadowColor}"
    of pcFillRect:
      echo &"  FillRect rect=({command.rect.x:.1f}, {command.rect.y:.1f}, {command.rect.w:.1f}, {command.rect.h:.1f}) radius={command.radius:.1f} color={command.color}"
    of pcFillLinearGradient:
      echo &"  FillLinearGradient rect=({command.gradientRect.x:.1f}, {command.gradientRect.y:.1f}, {command.gradientRect.w:.1f}, {command.gradientRect.h:.1f}) angle={command.gradient.angle:.1f} stops={command.gradient.stops.len}"
    of pcStrokeRect:
      echo &"  StrokeRect rect=({command.strokeRect.x:.1f}, {command.strokeRect.y:.1f}, {command.strokeRect.w:.1f}, {command.strokeRect.h:.1f}) width={command.strokeWidth:.1f} radius={command.strokeRadius:.1f} color={command.strokeColor}"
    of pcStrokePath:
      echo &"  StrokePath segments={command.path.segments.len} width={command.pathWidth:.1f} color={command.pathColor}"
    of pcDrawText:
      echo &"  DrawText node={command.node.nodeIndex} text=\"{command.text}\" pos=({command.position.x:.1f}, {command.position.y:.1f}) color={command.textColor}"
    of pcDrawImage:
      echo &"  DrawImage node={command.imageNode.nodeIndex} source=\"{command.imageSource}\" rect=({command.imageRect.x:.1f}, {command.imageRect.y:.1f}, {command.imageRect.w:.1f}, {command.imageRect.h:.1f}) opacity={command.imageOpacity:.2f}"
    of pcPushClip:
      echo &"  PushClip rect=({command.clipRect.x:.1f}, {command.clipRect.y:.1f}, {command.clipRect.w:.1f}, {command.clipRect.h:.1f})"
    of pcPopClip:
      echo "  PopClip"

when isMainModule:
  main()
