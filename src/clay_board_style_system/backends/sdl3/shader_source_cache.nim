# SPDX-License-Identifier: Apache-2.0

## Snapshots of the paint inside an SDL shader layer, before filtering.
import ../../core/[geometry, raster_surface]
import ../../paint/paint_command

const maxShaderSourceCommands = 512

type
  RasterInput = tuple[id, revision: uint64]

  Sdl3ShaderSourceSnapshot* = ref object
    bounds: Rect
    pixelScale: float32
    imageGeneration*: uint64
    usesImages*: bool
    commands*: seq[PaintCommand]
    rasters*: seq[RasterInput]

proc shaderSourceEnd*(commands: openArray[PaintCommand]; first: int): int =
  ## Find a complete, bounded scope with replayable inputs. Live GPU producers
  ## and nested filters need their own fresh backend decisions on each draw.
  var closing: seq[PaintCommandKind]
  var usesImages, hasRoundedClip: bool
  for index in first ..< min(commands.len, first + maxShaderSourceCommands + 1):
    let command = commands[index]
    case command.kind
    of pcPushLayer:
      if command.layerShaderFilter.material.len != 0 or
          command.layerBlurRadius != 0 or not command.layerColorFilter.isNil:
        return -1
      closing.add pcPopLayer
    of pcPushTransform:
      closing.add pcPopTransform
    of pcPushClip:
      closing.add pcPopClip
      hasRoundedClip = hasRoundedClip or command.clipRadius > 0.001'f32
    of pcPopLayer, pcPopTransform, pcPopClip:
      if closing.len == 0:
        return (if command.kind == pcPopLayer and index > first: index else: -1)
      if closing.pop() != command.kind:
        return -1
    of pcDrawGpuDirectSurface:
      return -1
    of pcDrawImage:
      usesImages = true
    else:
      discard
    # A rounded file image may need a temporary SDL target of its own.
    if usesImages and hasRoundedClip:
      return -1
  -1

proc rasterInput(command: PaintCommand): RasterInput =
  if command.kind == pcDrawRasterSurface and not command.rasterSurface.isNil:
    (command.rasterSurface.id, command.rasterSurface.revision)
  else: (0'u64, 0'u64)

proc shaderSourceSnapshot*(
    commands: openArray[PaintCommand]; bounds: Rect; scale: float32; imageGeneration: uint64
): Sdl3ShaderSourceSnapshot =
  result = Sdl3ShaderSourceSnapshot(bounds: bounds, pixelScale: scale,
    imageGeneration: imageGeneration, commands: @commands,
    rasters: newSeq[RasterInput](commands.len))
  for index, command in commands:
    case command.kind
    of pcDrawRasterSurface:
      result.rasters[index] = command.rasterInput
      # The cached texture owns the pixels. Avoid retaining CPU raster buffers.
      result.commands[index].rasterSurface = nil
    of pcDrawImage:
      result.usesImages = true
    else:
      discard

proc matches*(
    snapshot: Sdl3ShaderSourceSnapshot;
    commands: openArray[PaintCommand];
    bounds: Rect;
    scale: float32;
    imageGeneration: uint64
): bool =
  if snapshot.isNil or snapshot.bounds != bounds or snapshot.pixelScale != scale or
      snapshot.commands.len != commands.len or
      (snapshot.usesImages and snapshot.imageGeneration != imageGeneration):
    return false
  for index, command in commands:
    var comparable = command
    if comparable.kind == pcDrawRasterSurface:
      if command.rasterInput != snapshot.rasters[index]:
        return false
      comparable.rasterSurface = nil
    if not samePaintCommand(comparable, snapshot.commands[index]):
      return false
  true
