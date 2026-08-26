import std/[math, options, strutils]

import ../../core/[color, geometry]
import ../../paint/paint_command
import ../../vendor/sdl3

proc toByte(value: float32): uint8 =
  uint8(max(0, min(255, int(value * 255.0'f32 + 0.5'f32))))

proc setTextColor(renderer: pointer; color: Color) =
  discard SDL3.setRenderDrawColor(
    renderer,
    color.r.toByte,
    color.g.toByte,
    color.b.toByte,
    color.a.toByte
  )

proc drawDebugText*(renderer: pointer; command: PaintCommand) =
  let lineAdvance =
    if command.textStyle.lineHeight.isSome:
      max(1.0'f32, command.textStyle.lineHeight.get)
    else:
      8.0'f32
  var lines = command.text.splitLines()
  if lines.len == 0:
    lines = @[""]
  let authoredIndent = command.textStyle.textIndent.get(0.0'f32)
  let textIndent =
    if authoredIndent.classify in {fcNan, fcInf, fcNegInf}: 0.0'f32
    else: authoredIndent
  if command.textStyle.textShadow.isSome:
    let shadow = command.textStyle.textShadow.get
    let color =
      if shadow.color.isSome: shadow.color.get
      else: rgba(0, 0, 0, 0.45)
    renderer.setTextColor(color)
    for index, line in lines:
      let lineIndent = if index == 0: textIndent else: 0.0'f32
      discard SDL3.renderDebugText(
        renderer,
        cfloat(command.position.x + shadow.offsetX + lineIndent),
        cfloat(command.position.y + shadow.offsetY + index.float32 * lineAdvance),
        line.cstring
      )
  renderer.setTextColor(command.textColor)
  for index, line in lines:
    let lineIndent = if index == 0: textIndent else: 0.0'f32
    discard SDL3.renderDebugText(
      renderer,
      cfloat(command.position.x + lineIndent),
      cfloat(command.position.y + index.float32 * lineAdvance),
      line.cstring
    )
