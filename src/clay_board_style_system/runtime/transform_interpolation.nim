import std/options

import ../core/computed_style

type MotionTransformProperty* = enum
  mtpTransform,
  mtpTranslate,
  mtpScale,
  mtpRotate,
  mtpAll

proc interpolateNumber(
    startValue, endValue: Option[float32];
    identity, amount: float32
): Option[float32] =
  if startValue.isNone and endValue.isNone:
    return none(float32)
  let start = startValue.get(identity)
  let finish = endValue.get(identity)
  some(start + (finish - start) * amount)

proc interpolateLength(
    startValue, endValue: Option[ComputedLength];
    amount: float32
): Option[Option[ComputedLength]] =
  if startValue.isNone and endValue.isNone:
    return some(none(ComputedLength))
  let unit =
    if startValue.isSome: startValue.get.kind
    else: endValue.get.kind
  if startValue.isSome and endValue.isSome and
      startValue.get.kind != endValue.get.kind:
    return none(Option[ComputedLength])
  let start = startValue.get(ComputedLength(kind: unit, value: 0))
  let finish = endValue.get(ComputedLength(kind: unit, value: 0))
  some(some(ComputedLength(
    kind: unit,
    value: start.value + (finish.value - start.value) * amount
  )))

proc identityLike(operation: TransformOperation): TransformOperation =
  result.kind = operation.kind
  case operation.kind
  of ctkTranslate:
    if operation.xLength.isSome:
      result.xLength = some(ComputedLength(
        kind: operation.xLength.get.kind, value: 0
      ))
    if operation.yLength.isSome:
      result.yLength = some(ComputedLength(
        kind: operation.yLength.get.kind, value: 0
      ))
    if operation.zLength.isSome:
      result.zLength = some(ComputedLength(
        kind: operation.zLength.get.kind, value: 0
      ))
  of ctkScale:
    result.xNumber = some(1.0'f32)
    if operation.yNumber.isSome:
      result.yNumber = some(1.0'f32)
    if operation.zNumber.isSome:
      result.zNumber = some(1.0'f32)
  of ctkRotate:
    result.angle = 0

proc interpolateOperation(
    startOperation, endOperation: TransformOperation;
    amount: float32
): Option[TransformOperation] =
  if startOperation.kind != endOperation.kind:
    return none(TransformOperation)
  result = some(TransformOperation(kind: startOperation.kind))
  case startOperation.kind
  of ctkTranslate:
    let x = interpolateLength(
      startOperation.xLength, endOperation.xLength, amount
    )
    let y = interpolateLength(
      startOperation.yLength, endOperation.yLength, amount
    )
    let z = interpolateLength(
      startOperation.zLength, endOperation.zLength, amount
    )
    if x.isNone or y.isNone or z.isNone:
      return none(TransformOperation)
    result.get.xLength = x.get
    result.get.yLength = y.get
    result.get.zLength = z.get
  of ctkScale:
    result.get.xNumber = interpolateNumber(
      startOperation.xNumber, endOperation.xNumber, 1, amount
    )
    result.get.yNumber = interpolateNumber(
      startOperation.yNumber, endOperation.yNumber, 1, amount
    )
    result.get.zNumber = interpolateNumber(
      startOperation.zNumber, endOperation.zNumber, 1, amount
    )
  of ctkRotate:
    result.get.angle = startOperation.angle +
      (endOperation.angle - startOperation.angle) * amount

proc interpolateOperations(
    startOperations, endOperations: seq[TransformOperation];
    amount: float32
): Option[seq[TransformOperation]] =
  var start = startOperations
  var finish = endOperations
  if start.len == 0 and finish.len > 0:
    for operation in finish:
      start.add operation.identityLike()
  elif finish.len == 0 and start.len > 0:
    for operation in start:
      finish.add operation.identityLike()
  if start.len != finish.len:
    return none(seq[TransformOperation])
  var interpolated: seq[TransformOperation]
  for index in 0 ..< start.len:
    let operation = interpolateOperation(start[index], finish[index], amount)
    if operation.isNone:
      return none(seq[TransformOperation])
    interpolated.add operation.get
  some(interpolated)

proc interpolateTransformStyle*(
    startValue, endValue: ComputedTransformStyle;
    property: MotionTransformProperty;
    amount: float32
): Option[ComputedTransformStyle] =
  let progress = max(0.0'f32, min(1.0'f32, amount))
  result = some(startValue)
  if property in {mtpTransform, mtpAll}:
    if startValue.rawTransform != endValue.rawTransform and
        (startValue.rawTransform.isSome or endValue.rawTransform.isSome):
      return none(ComputedTransformStyle)
    let operations = interpolateOperations(
      startValue.operations, endValue.operations, progress
    )
    if operations.isNone:
      return none(ComputedTransformStyle)
    result.get.rawTransform = endValue.rawTransform
    result.get.operations = operations.get
  if property in {mtpTranslate, mtpAll}:
    let x = interpolateLength(
      startValue.translateX, endValue.translateX, progress
    )
    let y = interpolateLength(
      startValue.translateY, endValue.translateY, progress
    )
    let z = interpolateLength(
      startValue.translateZ, endValue.translateZ, progress
    )
    if x.isNone or y.isNone or z.isNone:
      return none(ComputedTransformStyle)
    result.get.translateX = x.get
    result.get.translateY = y.get
    result.get.translateZ = z.get
  if property in {mtpScale, mtpAll}:
    result.get.scaleX = interpolateNumber(
      startValue.scaleX, endValue.scaleX, 1, progress
    )
    result.get.scaleY = interpolateNumber(
      startValue.scaleY, endValue.scaleY, 1, progress
    )
    result.get.scaleZ = interpolateNumber(
      startValue.scaleZ, endValue.scaleZ, 1, progress
    )
  if property in {mtpRotate, mtpAll}:
    result.get.rotate = interpolateNumber(
      startValue.rotate, endValue.rotate, 0, progress
    )

proc canInterpolateTransformStyle*(
    startValue, endValue: ComputedTransformStyle;
    property: MotionTransformProperty
): bool =
  interpolateTransformStyle(startValue, endValue, property, 0.5).isSome

proc sameTransformProperty*(
    left, right: ComputedTransformStyle;
    property: MotionTransformProperty
): bool =
  case property
  of mtpTransform:
    left.rawTransform == right.rawTransform and
      left.operations == right.operations
  of mtpTranslate:
    left.translateX == right.translateX and
      left.translateY == right.translateY and
      left.translateZ == right.translateZ
  of mtpScale:
    left.scaleX == right.scaleX and left.scaleY == right.scaleY and
      left.scaleZ == right.scaleZ
  of mtpRotate:
    left.rotate == right.rotate
  of mtpAll:
    left == right
