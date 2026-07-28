type
  Color* = object
    r*, g*, b*, a*: float32

  GradientStop* = object
    color*: Color
    offset*: float32

proc rgba*(r, g, b: float32; a: float32 = 1.0'f32): Color =
  Color(r: r, g: g, b: b, a: a)

proc rgb*(r, g, b: float32): Color =
  rgba(r, g, b, 1.0'f32)

proc colorStop*(color: Color; offset: SomeNumber): GradientStop =
  GradientStop(color: color, offset: offset.float32)
