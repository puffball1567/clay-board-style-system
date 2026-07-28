import std/options
import ../core/[computed_style, declaration, diagnostics, property, style_value]

proc toComputedLength(value: LengthValue): ComputedLength =
  case value.kind
  of ukPx:
    ComputedLength(kind: cukPx, value: value.value)
  of ukPercent:
    ComputedLength(kind: cukPercent, value: value.value)
  of ukEm:
    ComputedLength(kind: cukEm, value: value.value)
  of ukRem:
    ComputedLength(kind: cukRem, value: value.value)
  of ukFill:
    ComputedLength(kind: cukFill, value: value.value)
  of ukContent:
    ComputedLength(kind: cukContent, value: value.value)
  of ukMinContent:
    ComputedLength(kind: cukMinContent, value: value.value)
  of ukMaxContent:
    ComputedLength(kind: cukMaxContent, value: value.value)
  of ukFitContent:
    ComputedLength(kind: cukFitContent, value: value.value)
  of ukAuto:
    ComputedLength(kind: cukAuto, value: value.value)
  of ukNone:
    ComputedLength(kind: cukNone, value: value.value)

proc toComputedLength(value: Option[LengthValue]): Option[ComputedLength] =
  if value.isSome: some(value.get.toComputedLength()) else: none(ComputedLength)

proc toComputed(operation: style_value.TransformOperationValue): computed_style.TransformOperation =
  case operation.kind
  of tokTranslate:
    result.kind = ctkTranslate
  of tokScale:
    result.kind = ctkScale
  of tokRotate:
    result.kind = ctkRotate
  result.xLength = operation.xLength.toComputedLength()
  result.yLength = operation.yLength.toComputedLength()
  result.zLength = operation.zLength.toComputedLength()
  result.xNumber = operation.xNumber
  result.yNumber = operation.yNumber
  result.zNumber = operation.zNumber
  result.angle = operation.angle

proc resetTransform(style: var ComputedStyle) =
  style.transform.rawTransform = none(string)
  style.transform.operations = @[]

proc applyTransform(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "transform requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      if value.keyword == "none":
        style.resetTransform()
      else:
        style.transform.rawTransform = some(value.keyword)
        style.transform.operations = @[]
    of svTransform:
      style.transform.rawTransform = none(string)
      style.transform.operations = @[]
      for operation in value.transformOperations:
        style.transform.operations.add(operation.toComputed())
    else:
      diagnostics.addError(declaration.property, "transform requires none, a raw keyword, or transformValue")
  of mmInitial, mmUnset:
    style.resetTransform()
  of mmInherit:
    if env.parent.isSome:
      style.transform.rawTransform = env.parent.get.transform.rawTransform
      style.transform.operations = env.parent.get.transform.operations
    else:
      diagnostics.addError(declaration.property, "cannot inherit transform without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "transform does not support relative merge")

proc applyRotate(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "rotate requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      style.transform.rotate = some(value.number)
    of svTransformOperation:
      if value.transformOperation.kind == tokRotate:
        style.transform.rotate = some(value.transformOperation.angle)
      else:
        diagnostics.addError(declaration.property, "rotate requires rotate(...)")
    of svKeyword:
      if value.keyword == "none":
        style.transform.rotate = none(float32)
      else:
        diagnostics.addError(declaration.property, "unsupported rotate keyword")
    else:
      diagnostics.addError(declaration.property, "rotate requires a number of degrees, none, or rotate(...)")
  of mmInitial, mmUnset:
    style.transform.rotate = none(float32)
  of mmInherit:
    if env.parent.isSome:
      style.transform.rotate = env.parent.get.transform.rotate
    else:
      diagnostics.addError(declaration.property, "cannot inherit rotate without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "rotate does not support relative merge")

proc applyScale(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "scale requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      style.transform.scaleX = some(value.number)
      style.transform.scaleY = some(value.number)
      style.transform.scaleZ = none(float32)
    of svTransformOperation:
      if value.transformOperation.kind != tokScale:
        diagnostics.addError(declaration.property, "scale requires scale(...)")
        return
      style.transform.scaleX = value.transformOperation.xNumber
      style.transform.scaleY =
        if value.transformOperation.yNumber.isSome: value.transformOperation.yNumber
        else: value.transformOperation.xNumber
      style.transform.scaleZ = value.transformOperation.zNumber
    of svKeyword:
      if value.keyword == "none":
        style.transform.scaleX = none(float32)
        style.transform.scaleY = none(float32)
        style.transform.scaleZ = none(float32)
      else:
        diagnostics.addError(declaration.property, "unsupported scale keyword")
    else:
      diagnostics.addError(declaration.property, "scale requires a number, none, or scale(...)")
  of mmInitial, mmUnset:
    style.transform.scaleX = none(float32)
    style.transform.scaleY = none(float32)
    style.transform.scaleZ = none(float32)
  of mmInherit:
    if env.parent.isSome:
      style.transform.scaleX = env.parent.get.transform.scaleX
      style.transform.scaleY = env.parent.get.transform.scaleY
      style.transform.scaleZ = env.parent.get.transform.scaleZ
    else:
      diagnostics.addError(declaration.property, "cannot inherit scale without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "scale does not support relative merge")

proc applyTranslate(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "translate requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svTransformOperation:
      if value.transformOperation.kind != tokTranslate:
        diagnostics.addError(declaration.property, "translate requires translate(...)")
        return
      style.transform.translateX = value.transformOperation.xLength.toComputedLength()
      style.transform.translateY = value.transformOperation.yLength.toComputedLength()
      style.transform.translateZ = value.transformOperation.zLength.toComputedLength()
    of svKeyword:
      if value.keyword == "none":
        style.transform.translateX = none(ComputedLength)
        style.transform.translateY = none(ComputedLength)
        style.transform.translateZ = none(ComputedLength)
      else:
        diagnostics.addError(declaration.property, "unsupported translate keyword")
    else:
      diagnostics.addError(declaration.property, "translate requires none or translate(...)")
  of mmInitial, mmUnset:
    style.transform.translateX = none(ComputedLength)
    style.transform.translateY = none(ComputedLength)
    style.transform.translateZ = none(ComputedLength)
  of mmInherit:
    if env.parent.isSome:
      style.transform.translateX = env.parent.get.transform.translateX
      style.transform.translateY = env.parent.get.transform.translateY
      style.transform.translateZ = env.parent.get.transform.translateZ
    else:
      diagnostics.addError(declaration.property, "cannot inherit translate without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "translate does not support relative merge")

proc resolveOriginValue(value: StyleValue; property: string; diagnostics: var Diagnostics): Option[ComputedLength] =
  case value.kind
  of svLength:
    some(value.length.toComputedLength())
  of svKeyword:
    case value.keyword
    of "left", "top":
      some(ComputedLength(kind: cukPercent, value: 0))
    of "center":
      some(ComputedLength(kind: cukPercent, value: 50))
    of "right", "bottom":
      some(ComputedLength(kind: cukPercent, value: 100))
    else:
      diagnostics.addError(property, "unsupported transform-origin keyword")
      none(ComputedLength)
  else:
    diagnostics.addError(property, property & " requires a length, percent, or origin keyword")
    none(ComputedLength)

proc applyTransformOrigin(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "transform-origin requires a value")
      return
    let value = resolveOriginValue(declaration.operation.value.get, declaration.property, diagnostics)
    if value.isNone:
      return
    style.transform.originX = value.get
    style.transform.originY = value.get
  of mmInitial, mmUnset:
    style.transform.originX = ComputedLength(kind: cukPercent, value: 50)
    style.transform.originY = ComputedLength(kind: cukPercent, value: 50)
    style.transform.originZ = 0
  of mmInherit:
    if env.parent.isSome:
      style.transform.originX = env.parent.get.transform.originX
      style.transform.originY = env.parent.get.transform.originY
      style.transform.originZ = env.parent.get.transform.originZ
    else:
      diagnostics.addError(declaration.property, "cannot inherit transform-origin without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "transform-origin does not support relative merge")

proc applyTransformBox(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "transform-box only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.transform.transformBox = tboxBorderBox
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "transform-box requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "content-box":
    style.transform.transformBox = tboxContentBox
  of "border-box":
    style.transform.transformBox = tboxBorderBox
  of "fill-box":
    style.transform.transformBox = tboxFillBox
  of "stroke-box":
    style.transform.transformBox = tboxStrokeBox
  of "view-box":
    style.transform.transformBox = tboxViewBox
  else:
    diagnostics.addError(declaration.property, "unsupported transform-box keyword")

proc applyTransformStyle(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "transform-style only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.transform.transformStyle = tsFlat
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "transform-style requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "flat":
    style.transform.transformStyle = tsFlat
  of "preserve-3d":
    style.transform.transformStyle = tsPreserve3d
  else:
    diagnostics.addError(declaration.property, "unsupported transform-style keyword")

proc applyBackfaceVisibility(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "backface-visibility only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.transform.backfaceVisible = true
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "backface-visibility requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "visible":
    style.transform.backfaceVisible = true
  of "hidden":
    style.transform.backfaceVisible = false
  else:
    diagnostics.addError(declaration.property, "unsupported backface-visibility keyword")

proc applyPerspective(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "perspective requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svLength:
      style.transform.perspective = some(value.length.toComputedLength())
    of svKeyword:
      if value.keyword == "none":
        style.transform.perspective = none(ComputedLength)
      else:
        diagnostics.addError(declaration.property, "unsupported perspective keyword")
    else:
      diagnostics.addError(declaration.property, "perspective requires a length value or none")
  of mmInitial, mmUnset:
    style.transform.perspective = none(ComputedLength)
  of mmInherit:
    if env.parent.isSome:
      style.transform.perspective = env.parent.get.transform.perspective
    else:
      diagnostics.addError(declaration.property, "cannot inherit perspective without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "perspective does not support relative merge")

proc applyPerspectiveOrigin(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "perspective-origin requires a value")
      return
    let value = resolveOriginValue(declaration.operation.value.get, declaration.property, diagnostics)
    if value.isNone:
      return
    style.transform.perspectiveOriginX = value.get
    style.transform.perspectiveOriginY = value.get
  of mmInitial, mmUnset:
    style.transform.perspectiveOriginX = ComputedLength(kind: cukPercent, value: 50)
    style.transform.perspectiveOriginY = ComputedLength(kind: cukPercent, value: 50)
  of mmInherit:
    if env.parent.isSome:
      style.transform.perspectiveOriginX = env.parent.get.transform.perspectiveOriginX
      style.transform.perspectiveOriginY = env.parent.get.transform.perspectiveOriginY
    else:
      diagnostics.addError(declaration.property, "cannot inherit perspective-origin without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "perspective-origin does not support relative merge")

let transformProperty* = PropertyImpl(name: "transform", apply: applyTransform)
let rotateProperty* = PropertyImpl(name: "rotate", apply: applyRotate)
let scaleProperty* = PropertyImpl(name: "scale", apply: applyScale)
let translateProperty* = PropertyImpl(name: "translate", apply: applyTranslate)
let transformOriginProperty* = PropertyImpl(name: "transform-origin", apply: applyTransformOrigin)
let transformBoxProperty* = PropertyImpl(name: "transform-box", apply: applyTransformBox)
let transformStyleProperty* = PropertyImpl(name: "transform-style", apply: applyTransformStyle)
let backfaceVisibilityProperty* = PropertyImpl(name: "backface-visibility", apply: applyBackfaceVisibility)
let perspectiveProperty* = PropertyImpl(name: "perspective", apply: applyPerspective)
let perspectiveOriginProperty* = PropertyImpl(name: "perspective-origin", apply: applyPerspectiveOrigin)
