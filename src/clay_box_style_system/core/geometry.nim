type
  Vec2* = object
    x*, y*: float32

  Size* = object
    w*, h*: float32

  Rect* = object
    x*, y*, w*, h*: float32

proc vec2*(x, y: float32): Vec2 =
  Vec2(x: x, y: y)

proc size*(w, h: float32): Size =
  Size(w: w, h: h)

proc rect*(x, y, w, h: float32): Rect =
  Rect(x: x, y: y, w: w, h: h)

proc contains*(rect: Rect; point: Vec2): bool =
  point.x >= rect.x and point.y >= rect.y and
    point.x < rect.x + rect.w and point.y < rect.y + rect.h

proc translated*(rect: Rect; offset: Vec2): Rect =
  Rect(x: rect.x + offset.x, y: rect.y + offset.y, w: rect.w, h: rect.h)

proc intersection*(a, b: Rect): Rect =
  let left = max(a.x, b.x)
  let top = max(a.y, b.y)
  let right = min(a.x + a.w, b.x + b.w)
  let bottom = min(a.y + a.h, b.y + b.h)
  Rect(
    x: left,
    y: top,
    w: max(0.0'f32, right - left),
    h: max(0.0'f32, bottom - top)
  )

proc isEmpty*(rect: Rect): bool =
  rect.w <= 0 or rect.h <= 0
