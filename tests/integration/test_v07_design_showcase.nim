import std/[options, sequtils, sets, unittest]

import clay_board_style_system
import ../../examples/showcase/v07_design_scenes

proc geometrySignature(canvas: Canvas2D): seq[float32] =
  for command in canvas.commands:
    case command.kind
    of cckPushTransform:
      result.add [command.transform.tx, command.transform.ty,
          command.transform.m11]
    of cckFillRect:
      result.add [command.fillRect.x, command.fillRect.y, command.fillRect.w,
          command.fillRect.h]
    of cckFillPath:
      for segment in command.fillPathValue.segments:
        result.add [segment.endpoint.x, segment.endpoint.y]
    of cckStrokePath:
      for segment in command.path.segments:
        result.add [segment.endpoint.x, segment.endpoint.y]
    else:
      discard

suite "Version 0.7 design showcase":
  test "navigation maps each visible tab and rejects surrounding space":
    for scene in DesignScene:
      let x = 330.0'f32 + scene.ord.float32 * 178.0'f32
      check sceneAtNavigationPoint(vec2(x, 30)) == some(scene)
      check sceneAtNavigationPoint(vec2(x + 146, 50)) == some(scene)

    check sceneAtNavigationPoint(vec2(316, 30)).isNone
    check sceneAtNavigationPoint(vec2(500, 14)).isNone
    check sceneAtNavigationPoint(vec2(500, 52)).isNone

  test "scene traversal wraps in both directions":
    check dsHeartParade.nextScene(-1) == dsNeonDream
    check dsHeartParade.nextScene(1) == dsCandyRadio
    check dsNeonDream.nextScene(1) == dsHeartParade
    check dsStickerStudio.nextScene(5) == dsStickerStudio

  test "every scene produces a substantial and distinct retained display list":
    var commandCounts: seq[int]
    var textCounts: seq[int]
    var pathCounts: seq[int]
    for scene in DesignScene:
      let canvas = newCanvas2D()
      canvas.drawDesignScene(scene, 12.5)
      commandCounts.add canvas.commands.len
      textCounts.add canvas.commands.countIt(it.kind == cckDrawText)
      pathCounts.add canvas.commands.countIt(
        it.kind in {cckFillPath, cckStrokePath}
      )
      check canvas.commands.len >= 35
      check textCounts[^1] >= 10
      check canvas.commands.anyIt(it.kind == cckFillRect)

    check commandCounts.toHashSet().len >= 4
    check pathCounts.countIt(it > 0) >= 4

  test "animated scenes change geometry without growing retained commands":
    for scene in DesignScene:
      let first = newCanvas2D()
      let second = newCanvas2D()
      first.drawDesignScene(scene, 1.0)
      second.drawDesignScene(scene, 2.0)
      check first.commands.len == second.commands.len
      check first.geometrySignature() != second.geometrySignature()

  test "scene labels remain stable public navigation text":
    check sceneLabels.len == designSceneCount
    check sceneLabels.allIt(it.len > 3)
    check sceneLabels.toSeq().toHashSet().len == designSceneCount
