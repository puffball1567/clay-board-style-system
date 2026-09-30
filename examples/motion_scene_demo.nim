## Headless CPU scene example: nim c -r --path:src examples/motion_scene_demo.nim output.ppm
import std/[math, os]

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/runtime/motion_scene

proc frame(phase: float32): MotionSceneSnapshot =
  var objects: seq[MotionObject]
  for row in 0 ..< 12:
    for column in 0 ..< 20:
      let id = MotionObjectId(uint64(row * 20 + column + 1))
      let wave = sin(phase + column.float32 * 0.3'f32 + row.float32 * 0.2'f32)
      objects.add motionRect(id, rect(0, 0, 14, 14),
        rgb(0.2'f32 + 0.5'f32 * (wave + 1) * 0.5'f32,
          0.45'f32, 0.8'f32),
        transform = translationAffine2D(12 + column.float32 * 22,
          12 + row.float32 * 22) * rotationAffine2D(wave * 0.3'f32),
        radius = 4)
  motionSceneSnapshot(size(460, 284), objects)

let scene = newMotionScene(frame(0))
let cancelled = scene.beginUpdate()
discard cancelled.cancel()
assert cancelled.complete(frame(1)) == msuStale
let update = scene.beginUpdate()
assert update.complete(frame(0.75)) == msuApplied
let commands = scene.canvas.paintCommands(NodeId(0), rect(0, 0, 460, 284))
let output = if paramCount() > 0: paramStr(1) else: "motion-scene.ppm"
render(commands, 460, 284, rgb(0.04, 0.06, 0.1)).writePpm(output)
echo "Rendered ", scene.snapshot.objectCount, " objects to ", output
