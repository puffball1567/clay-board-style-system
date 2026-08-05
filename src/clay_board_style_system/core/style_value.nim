import std/[options, strutils]
import ./[color, color_conversion, color_mix, color_value]

type
  AuthoredColorKind = enum
    ackValue,
    ackMix

  AuthoredColorRef = ref object
    case kind: AuthoredColorKind
    of ackValue:
      value: ColorValue
    of ackMix:
      mix: ColorMixValue

  GradientValueStop* = object
    ## Declaration-time gradient stop. Resolved colors remain compact while
    ## authored colors retain their color space until style resolution.
    color*: Color
    offset*: float32
    authoredColor: AuthoredColorRef

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
    ukNone,
    ## Keep new public units appended: UnitKind ordinals are part of the C ABI.
    ukVw,
    ukVh,
    ukVmin,
    ukVmax,
    ukLh,
    ukRlh,
    ukEx,
    ukCh,
    ukRex,
    ukRch

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
      authoredColor: AuthoredColorRef
    of svColorPair:
      firstColor*, secondColor*: Color
      firstAuthoredColor, secondAuthoredColor: AuthoredColorRef
    of svKeyword:
      keyword*: string
    of svNumber:
      number*: float32
    of svBorder:
      borderWidth*: Option[LengthValue]
      borderStyle*: Option[string]
      borderColor*: Option[Color]
      borderAuthoredColor: AuthoredColorRef
    of svShadow:
      shadowOffsetX*, shadowOffsetY*: LengthValue
      shadowBlur*: Option[LengthValue]
      shadowSpread*: Option[LengthValue]
      shadowColor*: Option[Color]
      shadowAuthoredColor: AuthoredColorRef
    of svLinearGradient:
      gradientAngle*: float32
      gradientInterpolationSpace*: ColorInterpolationSpace
      gradientStops*: seq[GradientValueStop]
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
  StyleValue(kind: svLength, length: LengthValue(kind: ukPx,
      value: value.float32))

proc percent*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukPercent,
      value: value.float32))

proc em*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukEm,
      value: value.float32))

proc rem*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukRem,
      value: value.float32))

proc vw*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukVw,
      value: value.float32))

proc vh*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukVh,
      value: value.float32))

proc vmin*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukVmin,
      value: value.float32))

proc vmax*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukVmax,
      value: value.float32))

proc lh*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukLh,
      value: value.float32))

proc rlh*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukRlh,
      value: value.float32))

proc ex*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukEx,
      value: value.float32))

proc ch*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukCh,
      value: value.float32))

proc rex*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukRex,
      value: value.float32))

proc rch*(value: SomeNumber): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukRch,
      value: value.float32))

proc fill*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukFill, value: 1.0'f32))

proc content*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukContent,
      value: 0.0'f32))

proc minContent*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukMinContent,
      value: 0.0'f32))

proc maxContent*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukMaxContent,
      value: 0.0'f32))

proc fitContent*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukFitContent,
      value: 0.0'f32))

proc auto*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukAuto, value: 0.0'f32))

proc autoSize*(): StyleValue =
  ## Unambiguous Nim authoring alias; `auto` is also a system type keyword.
  StyleValue(kind: svLength, length: LengthValue(kind: ukAuto, value: 0.0'f32))

proc none*(): StyleValue =
  StyleValue(kind: svLength, length: LengthValue(kind: ukNone, value: 0.0'f32))

proc colorValue*(color: Color): StyleValue =
  StyleValue(kind: svColor, color: color)

proc authoredColorRef(color: ColorValue): AuthoredColorRef =
  AuthoredColorRef(kind: ackValue, value: color)

proc authoredColorRef(mix: ColorMixValue): AuthoredColorRef =
  AuthoredColorRef(kind: ackMix, mix: mix)

proc resolveColor(color: AuthoredColorRef; current: Color): Color =
  case color.kind
  of ackValue: color.value.resolveColor(current)
  of ackMix: color.mix.resolveColor(current)

converter gradientValueStop*(stop: GradientStop): GradientValueStop =
  GradientValueStop(color: stop.color, offset: stop.offset)

proc gradientValueStop*(stop: GradientValueStop): GradientValueStop {.inline.} =
  stop

proc colorStop*(color: ColorValue; offset: SomeNumber): GradientValueStop =
  GradientValueStop(
    offset: offset.float32,
    authoredColor: authoredColorRef(color)
  )

proc colorStop*(color: ColorMixValue; offset: SomeNumber): GradientValueStop =
  GradientValueStop(
    offset: offset.float32,
    authoredColor: authoredColorRef(color)
  )

proc resolveGradientStops*(value: StyleValue; current: Color): seq[GradientStop] =
  if value.kind != svLinearGradient:
    return
  result = newSeqOfCap[GradientStop](value.gradientStops.len)
  for stop in value.gradientStops:
    let color =
      if stop.authoredColor.isNil:
        stop.color
      else:
        stop.authoredColor.resolveColor(current)
    result.add GradientStop(color: color, offset: stop.offset)

proc colorValue*(color: ColorValue): StyleValue =
  StyleValue(
    kind: svColor,
    color: Color(),
    authoredColor: authoredColorRef(color)
  )

proc colorValue*(mix: ColorMixValue): StyleValue =
  StyleValue(
    kind: svColor,
    color: Color(),
    authoredColor: authoredColorRef(mix)
  )

proc colorPairValue*(first, second: Color): StyleValue =
  StyleValue(kind: svColorPair, firstColor: first, secondColor: second)

proc colorPairValue*(first, second: ColorValue): StyleValue =
  StyleValue(
    kind: svColorPair,
    firstColor: Color(),
    secondColor: Color(),
    firstAuthoredColor: authoredColorRef(first),
    secondAuthoredColor: authoredColorRef(second)
  )

proc colorPairValue*(first: ColorValue; second: Color): StyleValue =
  StyleValue(
    kind: svColorPair,
    firstColor: Color(),
    secondColor: second,
    firstAuthoredColor: authoredColorRef(first)
  )

proc colorPairValue*(first: Color; second: ColorValue): StyleValue =
  StyleValue(
    kind: svColorPair,
    firstColor: first,
    secondColor: Color(),
    secondAuthoredColor: authoredColorRef(second)
  )

proc resolveStyleColor*(value: StyleValue; current: Color): Option[Color] =
  if value.kind != svColor:
    return none(Color)
  if not value.authoredColor.isNil:
    return some(value.authoredColor.resolveColor(current))
  some(value.color)

proc resolveColorPair*(value: StyleValue; current: Color): Option[tuple[
    first, second: Color]] =
  if value.kind != svColorPair:
    return none(tuple[first, second: Color])
  let first =
    if not value.firstAuthoredColor.isNil:
      value.firstAuthoredColor.resolveColor(current)
    else:
      value.firstColor
  let second =
    if not value.secondAuthoredColor.isNil:
      value.secondAuthoredColor.resolveColor(current)
    else:
      value.secondColor
  some((first: first, second: second))

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
      result.borderAuthoredColor = value.authoredColor

proc borderValue*(width: StyleValue; style: StyleValue;
    color: StyleValue): StyleValue =
  borderValue(some(width), some(style), some(color))

proc borderValue*(width: StyleValue; color: StyleValue): StyleValue =
  borderValue(some(width), none(StyleValue), some(color))

proc borderValue*(lineWeight: StyleValue; lineStyle: string;
    lineColor: Color): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderStyle = some(lineStyle)
  result.borderColor = some(lineColor)

proc borderValue*(lineWeight: StyleValue; lineStyle: string;
    lineColor: ColorValue): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderStyle = some(lineStyle)
  result.borderAuthoredColor = authoredColorRef(lineColor)

proc borderValue*(lineWeight: StyleValue; lineColor: Color): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderColor = some(lineColor)

proc borderValue*(lineWeight: StyleValue; lineColor: ColorValue): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderAuthoredColor = authoredColorRef(lineColor)

proc borderValue*(lineWeight: StyleValue; lineStyle: string;
    lineColor: ColorMixValue): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderStyle = some(lineStyle)
  result.borderAuthoredColor = authoredColorRef(lineColor)

proc borderValue*(lineWeight: StyleValue;
    lineColor: ColorMixValue): StyleValue =
  result = StyleValue(kind: svBorder)
  if lineWeight.kind == svLength:
    result.borderWidth = some(lineWeight.length)
  result.borderAuthoredColor = authoredColorRef(lineColor)

proc resolveBorderColor*(value: StyleValue; current: Color): Option[Color] =
  if value.kind != svBorder:
    return none(Color)
  if not value.borderAuthoredColor.isNil:
    return some(value.borderAuthoredColor.resolveColor(current))
  value.borderColor

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

proc shadowValue*(
    offsetX: StyleValue;
    offsetY: StyleValue;
    shadowColor: ColorValue;
    blur: Option[StyleValue] = none(StyleValue);
    spread: Option[StyleValue] = none(StyleValue)
): StyleValue =
  result = shadowValue(offsetX, offsetY, blur, spread)
  result.shadowAuthoredColor = authoredColorRef(shadowColor)

proc shadowValue*(
    offsetX: StyleValue;
    offsetY: StyleValue;
    shadowColor: ColorMixValue;
    blur: Option[StyleValue] = none(StyleValue);
    spread: Option[StyleValue] = none(StyleValue)
): StyleValue =
  result = shadowValue(offsetX, offsetY, blur, spread)
  result.shadowAuthoredColor = authoredColorRef(shadowColor)

proc resolveShadowColor*(value: StyleValue; current: Color): Option[Color] =
  if value.kind != svShadow:
    return none(Color)
  if not value.shadowAuthoredColor.isNil:
    return some(value.shadowAuthoredColor.resolveColor(current))
  value.shadowColor

proc linearGradient*(angle: SomeNumber;
    stops: varargs[GradientValueStop, gradientValueStop]): StyleValue =
  StyleValue(kind: svLinearGradient, gradientAngle: angle.float32,
      gradientInterpolationSpace: cisSrgb, gradientStops: @stops)

proc linearGradientIn*(
    interpolationSpace: ColorInterpolationSpace;
    angle: SomeNumber;
    stops: varargs[GradientValueStop, gradientValueStop]
): StyleValue =
  StyleValue(
    kind: svLinearGradient,
    gradientAngle: angle.float32,
    gradientInterpolationSpace: interpolationSpace,
    gradientStops: @stops
  )

proc translate*(x, y: StyleValue; z: Option[StyleValue] = none(
    StyleValue)): StyleValue =
  result = StyleValue(kind: svTransformOperation)
  result.transformOperation.kind = tokTranslate
  if x.kind == svLength:
    result.transformOperation.xLength = some(x.length)
  if y.kind == svLength:
    result.transformOperation.yLength = some(y.length)
  if z.isSome and z.get.kind == svLength:
    result.transformOperation.zLength = some(z.get.length)

proc scale*(x: SomeNumber; y: Option[float32] = none(float32); z: Option[
    float32] = none(float32)): StyleValue =
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
