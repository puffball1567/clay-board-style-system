import std/[options, strutils]
import ./color

type
  UnitKind* = enum
    ukPx,
    ukPercent,
    ukEm,
    ukRem,
    ukFill,
    ukContent,
    ukMinContent,
    ukMaxContent,
    ukFitContent,
    ukAuto,
    ukNone

  LengthValue* = object
    kind*: UnitKind
    value*: float32

  StyleValueKind* = enum
    svLength,
    svColor,
    svColorPair,
    svKeyword,
    svNumber,
    svBorder,
    svShadow,
    svLinearGradient,
    svTransform,
    svTransformOperation,
    svFunction

  TransformOperationKind* = enum
    tokTranslate,
    tokScale,
    tokRotate

  TransformOperationValue* = object
    kind*: TransformOperationKind
    xLength*, yLength*, zLength*: Option[LengthValue]
    xNumber*, yNumber*, zNumber*: Option[float32]
    angle*: float32

  StyleValueProc* = proc(): StyleValue {.closure.}

  StyleValue* = object
    case kind*: StyleValueKind
    of svLength:
      length*: LengthValue
    of svColor:
      color*: Color
    of svColorPair:
      firstColor*, secondColor*: Color
    of svKeyword:
      keyword*: string
    of svNumber:
      number*: float32
    of svBorder:
      borderWidth*: Option[LengthValue]
      borderStyle*: Option[string]
      borderColor*: Option[Color]
    of svShadow:
      shadowOffsetX*, shadowOffsetY*: LengthValue
      shadowBlur*: Option[LengthValue]
      shadowSpread*: Option[LengthValue]
      shadowColor*: Option[Color]
    of svLinearGradient:
      gradientAngle*: float32
      gradientStops*: seq[GradientStop]
    of svTransform:
      transformOperations*: seq[TransformOperationValue]
    of svTransformOperation:
      transformOperation*: TransformOperationValue
    of svFunction:
      valueProc*: StyleValueProc

  MergeMode* = enum
    mmOverwrite,
    mmInherit,
    mmInitial,
    mmUnset,
    mmRelative

  StyleOperation* = object
    mode*: MergeMode
    value*: Option[StyleValue]

proc px*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukPx, value: value.float32))

proc percent*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukPercent, value: value.float32))

proc em*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukEm, value: value.float32))

proc rem*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukRem, value: value.float32))

proc fill*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukFill, value: 1.0'f32))

proc content*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukContent, value: 0.0'f32))

proc minContent*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukMinContent, value: 0.0'f32))

proc maxContent*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukMaxContent, value: 0.0'f32))

proc fitContent*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukFitContent, value: 0.0'f32))

proc auto*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukAuto, value: 0.0'f32))

proc autoSize*(): StyleValue =
  ## Unambiguous Nim authoring alias; `auto` is also a system type keyword.
  StyleValue(kind: svLength, length: LengthValue(kind: ukAuto, value: 0.0'f32))

proc none*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukNone, value: 0.0'f32))

proc colorValue*(color: Color): StyleValue =
  StyleValue(kind: svColor, color: color)

proc colorPairValue*(first, second: Color): StyleValue =
  StyleValue(kind: svColorPair, firstColor: first, secondColor: second)

proc keyword*(value: string): StyleValue =
  StyleValue(kind: svKeyword, keyword: value)

proc fontFamilyValue*(families: varargs[string]): StyleValue =
  StyleValue(kind: svKeyword, keyword: families.join(","))

proc genericSerif*(): string = "serif"
proc genericSansSerif*(): string = "sans-serif"
proc genericMonospace*(): string = "monospace"
proc genericCursive*(): string = "cursive"
proc genericFantasy*(): string = "fantasy"
proc genericSystemUi*(): string = "system-ui"

proc number*(value: SomeNumber): StyleValue =
  StyleValue(kind: svNumber, number: value.float32)

proc computedValue*(valueProc: StyleValueProc): StyleValue =
  StyleValue(kind: svFunction, valueProc: valueProc)

proc functionValue*(valueProc: StyleValueProc): StyleValue =
  computedValue(valueProc)

proc borderValue*(
    width: Option[StyleValue] = none(StyleValue);
    style: Option[StyleValue] = none(StyleValue);
    color: Option[StyleValue] = none(StyleValue)
): StyleValue =
  result = StyleValue(kind: svBorder)
  if width.isSome:
    let value = width.get
    if value.kind == svLength:
      result.borderWidth = some(value.length)
  if style.isSome:
    let value = style.get
    if value.kind == svKeyword:
      result.borderStyle = some(value.keyword)
  if color.isSome:
    let value = color.get
    if value.kind == svColor:
      result.borderColor = some(value.color)

proc borderValue*(width: StyleValue; style: StyleValue; color: StyleValue): StyleValue =
  borderValue(some(width), some(style), some(color))

proc borderValue*(width: StyleValue; color: StyleValue): StyleValue =
  borderValue(some(width), none(StyleValue), some(color))

proc borderValue*(lineWeight: StyleValue; lineStyle: string; lineColor: Color): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderStyle = some(lineStyle)
  result.borderColor = some(lineColor)

proc borderValue*(lineWeight: StyleValue; lineColor: Color): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderColor = some(lineColor)

proc shadowValue*(
    offsetX: StyleValue;
    offsetY: StyleValue;
    blur: Option[StyleValue] = none(StyleValue);
    spread: Option[StyleValue] = none(StyleValue);
    shadowColor: Option[Color] = none(Color)
): StyleValue =
  result = StyleValue(kind: svShadow)
  if offsetX.kind == svLength:
    result.shadowOffsetX = offsetX.length
  if offsetY.kind == svLength:
    result.shadowOffsetY = offsetY.length
  if blur.isSome and blur.get.kind == svLength:
    result.shadowBlur = some(blur.get.length)
  if spread.isSome and spread.get.kind == svLength:
    result.shadowSpread = some(spread.get.length)
  result.shadowColor = shadowColor

proc linearGradient*(angle: SomeNumber; stops: varargs[GradientStop]): StyleValue =
  StyleValue(kind: svLinearGradient, gradientAngle: angle.float32, gradientStops: @stops)

proc translate*(x, y: StyleValue; z: Option[StyleValue] = none(StyleValue)): StyleValue =
  result = StyleValue(kind: svTransformOperation)
  result.transformOperation.kind = tokTranslate
  if x.kind == svLength:
    result.transformOperation.xLength = some(x.length)
  if y.kind == svLength:
    result.transformOperation.yLength = some(y.length)
  if z.isSome and z.get.kind == svLength:
    result.transformOperation.zLength = some(z.get.length)

proc scale*(x: SomeNumber; y: Option[float32] = none(float32); z: Option[float32] = none(float32)): StyleValue =
  result = StyleValue(kind: svTransformOperation)
  result.transformOperation.kind = tokScale
  result.transformOperation.xNumber = some(x.float32)
  result.transformOperation.yNumber = y
  result.transformOperation.zNumber = z

proc rotate*(angle: SomeNumber): StyleValue =
  result = StyleValue(kind: svTransformOperation)
  result.transformOperation.kind = tokRotate
  result.transformOperation.angle = angle.float32

proc transformValue*(operations: varargs[StyleValue]): StyleValue =
  result = StyleValue(kind: svTransform)
  for operation in operations:
    if operation.kind == svTransformOperation:
      result.transformOperations.add(operation.transformOperation)

proc overwrite*(value: StyleValue): StyleOperation =
  StyleOperation(mode: mmOverwrite, value: some(value))

proc inherit*(): StyleOperation =
  StyleOperation(mode: mmInherit, value: none(StyleValue))

proc initial*(): StyleOperation =
  StyleOperation(mode: mmInitial, value: none(StyleValue))

proc unset*(): StyleOperation =
  StyleOperation(mode: mmUnset, value: none(StyleValue))

proc relative*(value: StyleValue): StyleOperation =
  StyleOperation(mode: mmRelative, value: some(value))
