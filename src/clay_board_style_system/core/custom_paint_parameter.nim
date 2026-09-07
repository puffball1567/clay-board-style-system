import std/[math, options, sets]

import ./color

const
  maxCustomPaintParameters* = 64
  maxCustomPaintParameterNameBytes* = 64

type
  CustomPaintParameterKind* = enum
    cppkFloat,
    cppkInteger,
    cppkBoolean,
    cppkVec2,
    cppkVec4,
    cppkColor

  CustomPaintParameter* = object
    parameterName: string
    case kind*: CustomPaintParameterKind
    of cppkFloat:
      floatValue*: float32
    of cppkInteger:
      integerValue*: int64
    of cppkBoolean:
      booleanValue*: bool
    of cppkVec2:
      vec2Value*: array[2, float32]
    of cppkVec4:
      vec4Value*: array[4, float32]
    of cppkColor:
      colorValue*: Color

  CustomPaintParameters* = ref object
    values: seq[CustomPaintParameter]

proc finite(value: float32): bool {.inline.} =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc copyParameterName(value: string): string =
  result = newString(value.len)
  if value.len > 0:
    copyMem(addr result[0], unsafeAddr value[0], value.len)

proc validCustomPaintParameterName*(name: string): bool =
  if name.len == 0 or name.len > maxCustomPaintParameterNameBytes:
    return false
  if not (name[0] in {'a' .. 'z', 'A' .. 'Z'} or name[0] == '_'):
    return false
  for character in name:
    if not (character in {'a' .. 'z', 'A' .. 'Z', '0' .. '9'} or
        character == '_'):
      return false
  true

proc validate(parameter: CustomPaintParameter) =
  if not parameter.parameterName.validCustomPaintParameterName:
    raise newException(ValueError, "custom paint parameter name is invalid")
  case parameter.kind
  of cppkFloat:
    if not parameter.floatValue.finite:
      raise newException(ValueError, "custom paint float parameter must be finite")
  of cppkVec2:
    for value in parameter.vec2Value:
      if not value.finite:
        raise newException(ValueError, "custom paint vec2 parameter must be finite")
  of cppkVec4:
    for value in parameter.vec4Value:
      if not value.finite:
        raise newException(ValueError, "custom paint vec4 parameter must be finite")
  of cppkColor:
    for value in [parameter.colorValue.r, parameter.colorValue.g,
        parameter.colorValue.b, parameter.colorValue.a]:
      if not value.finite:
        raise newException(ValueError, "custom paint color parameter must be finite")
  of cppkInteger, cppkBoolean:
    discard

proc customPaintFloat*(name: string; value: SomeNumber): CustomPaintParameter =
  result = CustomPaintParameter(
    parameterName: name.copyParameterName,
    kind: cppkFloat,
    floatValue: value.float32
  )
  result.validate()

proc customPaintInteger*(name: string; value: SomeInteger): CustomPaintParameter =
  when value is SomeUnsignedInt:
    if uint64(value) > uint64(high(int64)):
      raise newException(ValueError, "custom paint integer parameter exceeds int64")
  result = CustomPaintParameter(
    parameterName: name.copyParameterName,
    kind: cppkInteger,
    integerValue: value.int64
  )
  result.validate()

proc customPaintBoolean*(name: string; value: bool): CustomPaintParameter =
  result = CustomPaintParameter(
    parameterName: name.copyParameterName,
    kind: cppkBoolean,
    booleanValue: value
  )
  result.validate()

proc customPaintVec2*[X: SomeNumber, Y: SomeNumber](
    name: string;
    x: X;
    y: Y
): CustomPaintParameter =
  result = CustomPaintParameter(
    parameterName: name.copyParameterName,
    kind: cppkVec2,
    vec2Value: [x.float32, y.float32]
  )
  result.validate()

proc customPaintVec4*[
    X: SomeNumber,
    Y: SomeNumber,
    Z: SomeNumber,
    W: SomeNumber
](
    name: string;
    x: X;
    y: Y;
    z: Z;
    w: W
): CustomPaintParameter =
  result = CustomPaintParameter(
    parameterName: name.copyParameterName,
    kind: cppkVec4,
    vec4Value: [x.float32, y.float32, z.float32, w.float32]
  )
  result.validate()

proc customPaintColor*(name: string; value: Color): CustomPaintParameter =
  result = CustomPaintParameter(
    parameterName: name.copyParameterName,
    kind: cppkColor,
    colorValue: value
  )
  result.validate()

proc customPaintParameters*(
    values: openArray[CustomPaintParameter]
): CustomPaintParameters =
  if values.len == 0:
    return nil
  if values.len > maxCustomPaintParameters:
    raise newException(ValueError, "custom paint parameter limit exceeded")

  var names = initHashSet[string]()
  var snapshot = newSeqOfCap[CustomPaintParameter](values.len)
  for parameter in values:
    parameter.validate()
    if parameter.parameterName in names:
      raise newException(ValueError, "custom paint parameter names must be unique")
    names.incl parameter.parameterName
    var retained = parameter
    retained.parameterName = parameter.parameterName.copyParameterName
    snapshot.add retained
  CustomPaintParameters(values: snapshot)

proc name*(parameter: CustomPaintParameter): lent string {.inline.} =
  parameter.parameterName

proc len*(parameters: CustomPaintParameters): int {.inline.} =
  if parameters.isNil: 0 else: parameters.values.len

proc `[]`*(
    parameters: CustomPaintParameters;
    index: int
): CustomPaintParameter =
  if parameters.isNil:
    raise newException(IndexDefect, "custom paint parameter index is out of bounds")
  parameters.values[index]

iterator items*(parameters: CustomPaintParameters): CustomPaintParameter =
  if not parameters.isNil:
    for parameter in parameters.values:
      yield parameter

proc findCustomPaintParameter*(
    parameters: CustomPaintParameters;
    name: string
): Option[CustomPaintParameter] =
  if parameters.isNil:
    return none(CustomPaintParameter)
  for parameter in parameters.values:
    if parameter.parameterName == name:
      return some(parameter)
  none(CustomPaintParameter)
