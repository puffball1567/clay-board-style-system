import std/[math, strutils, tables]

import clay_board_style_system/runtime/gpu_host

const
  maxGpuShaderNodes* = 4096
  maxGpuShaderOutputs* = 32
  maxGpuShaderSourceBytes* = 1024 * 1024

type
  GpuShaderBuildError* = object of CatchableError

  GpuShaderValueType* = enum
    gsvtBool,
    gsvtFloat,
    gsvtVec2,
    gsvtVec3,
    gsvtVec4,
    gsvtMat3,
    gsvtMat4

  GpuShaderInterfaceSlot* = enum
    gsisPosition,
    gsisNormal,
    gsisTangent,
    gsisBitangent,
    gsisColor0,
    gsisColor1,
    gsisColor2,
    gsisColor3,
    gsisTexCoord0,
    gsisTexCoord1,
    gsisTexCoord2,
    gsisTexCoord3,
    gsisTexCoord4,
    gsisTexCoord5,
    gsisTexCoord6,
    gsisTexCoord7

  GpuShaderUnaryOperation* = enum
    gsuNegate,
    gsuSine,
    gsuCosine,
    gsuAbsolute,
    gsuFloor,
    gsuCeil,
    gsuNormalize

  GpuShaderBinaryOperation* = enum
    gsbAdd,
    gsbSubtract,
    gsbMultiply,
    gsbDivide,
    gsbMinimum,
    gsbMaximum,
    gsbDot,
    gsbPower

  GpuShaderTernaryOperation* = enum
    gstMix,
    gstClamp,
    gstSmoothstep

  GpuShaderNodeKind = enum
    gsnLiteral,
    gsnVertexInput,
    gsnVaryingInput,
    gsnUniform,
    gsnConstruct,
    gsnSwizzle,
    gsnUnary,
    gsnBinary,
    gsnTernary

  GpuShaderNode = object
    kind: GpuShaderNodeKind
    valueType: GpuShaderValueType
    name: string
    slot: GpuShaderInterfaceSlot
    values: array[4, float32]
    operands: array[4, int]
    operandCount: uint8
    swizzle: string
    unary: GpuShaderUnaryOperation
    binary: GpuShaderBinaryOperation
    ternary: GpuShaderTernaryOperation

  GpuShaderVaryingOutput = object
    slot: GpuShaderInterfaceSlot
    expression: int

  GpuShaderBuilder* = ref object
    stageValue: GpuShaderStage
    labelValue: string
    nodes: seq[GpuShaderNode]
    positionOutput: int
    colorOutputs: array[4, int]
    varyingOutputs: seq[GpuShaderVaryingOutput]
    sealed: bool

  GpuShaderExpression* = object
    owner: GpuShaderBuilder
    nodeIndex: int

  GpuShaderInterfaceEntry* = object
    slot*: GpuShaderInterfaceSlot
    valueType*: GpuShaderValueType

  GpuShaderSource* = object
    stage*: GpuShaderStage
    label*: string
    source*: string
    varyingDefinitions*: string
    inputs*: seq[GpuShaderInterfaceEntry]
    outputs*: seq[GpuShaderInterfaceEntry]

  GpuShaderArtifact* = object
    descriptor*: GpuShaderDescriptor
    bytecode*: seq[byte]
    sourceHash*: uint64

proc valueTypeName*(value: GpuShaderValueType): string =
  case value
  of gsvtBool: "bool"
  of gsvtFloat: "float"
  of gsvtVec2: "vec2"
  of gsvtVec3: "vec3"
  of gsvtVec4: "vec4"
  of gsvtMat3: "mat3"
  of gsvtMat4: "mat4"

proc componentCount(value: GpuShaderValueType): int =
  case value
  of gsvtBool, gsvtFloat: 1
  of gsvtVec2: 2
  of gsvtVec3: 3
  of gsvtVec4: 4
  of gsvtMat3: 9
  of gsvtMat4: 16

proc isNumeric(value: GpuShaderValueType): bool {.inline.} =
  value != gsvtBool

proc isScalarOrVector(value: GpuShaderValueType): bool {.inline.} =
  value in {gsvtFloat, gsvtVec2, gsvtVec3, gsvtVec4}

proc isVector(value: GpuShaderValueType): bool {.inline.} =
  value in {gsvtVec2, gsvtVec3, gsvtVec4}

proc validateIdentifier(value, description: string) =
  if value.len == 0 or value.len > maxGpuResourceLabelBytes:
    raise newException(
      GpuShaderBuildError,
      description & " must contain 1 to " & $maxGpuResourceLabelBytes & " bytes"
    )
  for index, character in value:
    if not (character == '_' or character in {'a' .. 'z'} or
        character in {'A' .. 'Z'} or
        (index > 0 and character in {'0' .. '9'})):
      raise newException(
        GpuShaderBuildError,
        description & " must be a portable identifier"
      )

proc newGpuShaderBuilder*(
    stage: GpuShaderStage;
    label = ""
): GpuShaderBuilder =
  if label.len > maxGpuResourceLabelBytes:
    raise newException(GpuShaderBuildError, "GPU shader label is too long")
  GpuShaderBuilder(
    stageValue: stage,
    labelValue: label,
    positionOutput: -1,
    colorOutputs: [-1, -1, -1, -1]
  )

proc stage*(builder: GpuShaderBuilder): GpuShaderStage =
  if builder.isNil:
    raise newException(GpuShaderBuildError, "GPU shader builder cannot be nil")
  builder.stageValue

proc label*(builder: GpuShaderBuilder): string =
  if builder.isNil: "" else: builder.labelValue

proc requireOpen(builder: GpuShaderBuilder) =
  if builder.isNil:
    raise newException(GpuShaderBuildError, "GPU shader builder cannot be nil")
  if builder.sealed:
    raise newException(GpuShaderBuildError, "GPU shader builder is already sealed")

proc requireMutable(builder: GpuShaderBuilder) =
  builder.requireOpen()
  if builder.nodes.len >= maxGpuShaderNodes:
    raise newException(GpuShaderBuildError, "GPU shader node limit exceeded")

proc addNode(
    builder: GpuShaderBuilder;
    node: sink GpuShaderNode
): GpuShaderExpression =
  builder.requireMutable()
  builder.nodes.add(node)
  GpuShaderExpression(owner: builder, nodeIndex: builder.nodes.high)

proc requireExpression(
    builder: GpuShaderBuilder;
    expression: GpuShaderExpression
): GpuShaderNode =
  if expression.owner != builder or expression.nodeIndex < 0 or
      expression.nodeIndex >= builder.nodes.len:
    raise newException(
      GpuShaderBuildError,
      "GPU shader expression belongs to another builder or is invalid"
    )
  builder.nodes[expression.nodeIndex]

proc valueType*(expression: GpuShaderExpression): GpuShaderValueType =
  if expression.owner.isNil or expression.nodeIndex < 0 or
      expression.nodeIndex >= expression.owner.nodes.len:
    raise newException(GpuShaderBuildError, "GPU shader expression is invalid")
  expression.owner.nodes[expression.nodeIndex].valueType

proc expressionAt*(
    builder: GpuShaderBuilder;
    id: uint32
): GpuShaderExpression =
  if builder.isNil or id == 0 or uint64(id) > uint64(builder.nodes.len):
    raise newException(GpuShaderBuildError, "GPU shader expression id is invalid")
  GpuShaderExpression(owner: builder, nodeIndex: int(id) - 1)

proc expressionId*(expression: GpuShaderExpression): uint32 =
  if expression.owner.isNil or expression.nodeIndex < 0 or
      expression.nodeIndex >= expression.owner.nodes.len:
    raise newException(GpuShaderBuildError, "GPU shader expression is invalid")
  uint32(expression.nodeIndex + 1)

proc scalar*(builder: GpuShaderBuilder; value: float32): GpuShaderExpression =
  if value.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(GpuShaderBuildError, "GPU shader literal must be finite")
  builder.addNode(GpuShaderNode(
    kind: gsnLiteral,
    valueType: gsvtFloat,
    values: [value, 0'f32, 0'f32, 0'f32]
  ))

proc vector*(
    builder: GpuShaderBuilder;
    values: openArray[float32]
): GpuShaderExpression =
  if values.len < 2 or values.len > 4:
    raise newException(GpuShaderBuildError, "GPU vector needs 2 to 4 components")
  var stored: array[4, float32]
  for index, value in values:
    if value.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(GpuShaderBuildError, "GPU shader literal must be finite")
    stored[index] = value
  builder.addNode(GpuShaderNode(
    kind: gsnLiteral,
    valueType: GpuShaderValueType(ord(gsvtVec2) + values.len - 2),
    values: stored
  ))

proc interfaceName(
    slot: GpuShaderInterfaceSlot;
    varying: bool
): string =
  let prefix = if varying: "v_" else: "a_"
  case slot
  of gsisPosition: prefix & "position"
  of gsisNormal: prefix & "normal"
  of gsisTangent: prefix & "tangent"
  of gsisBitangent: prefix & "bitangent"
  of gsisColor0 .. gsisColor3:
    prefix & "color" & $(ord(slot) - ord(gsisColor0))
  of gsisTexCoord0 .. gsisTexCoord7:
    prefix & "texcoord" & $(ord(slot) - ord(gsisTexCoord0))

proc interfaceSemantic(slot: GpuShaderInterfaceSlot): string =
  case slot
  of gsisPosition: "POSITION"
  of gsisNormal: "NORMAL"
  of gsisTangent: "TANGENT"
  of gsisBitangent: "BITANGENT"
  of gsisColor0 .. gsisColor3:
    "COLOR" & $(ord(slot) - ord(gsisColor0))
  of gsisTexCoord0 .. gsisTexCoord7:
    "TEXCOORD" & $(ord(slot) - ord(gsisTexCoord0))

proc vertexInput*(
    builder: GpuShaderBuilder;
    slot: GpuShaderInterfaceSlot;
    valueType: GpuShaderValueType
): GpuShaderExpression =
  builder.requireOpen()
  if builder.stageValue != gssVertex:
    raise newException(GpuShaderBuildError, "vertex inputs require a vertex shader")
  if not valueType.isScalarOrVector:
    raise newException(GpuShaderBuildError, "vertex input type is not portable")
  builder.addNode(GpuShaderNode(
    kind: gsnVertexInput,
    valueType: valueType,
    slot: slot,
    name: slot.interfaceName(false)
  ))

proc varyingInput*(
    builder: GpuShaderBuilder;
    slot: GpuShaderInterfaceSlot;
    valueType: GpuShaderValueType
): GpuShaderExpression =
  builder.requireOpen()
  if builder.stageValue != gssFragment:
    raise newException(GpuShaderBuildError, "varying inputs require a fragment shader")
  if not valueType.isScalarOrVector:
    raise newException(GpuShaderBuildError, "varying input type is not portable")
  builder.addNode(GpuShaderNode(
    kind: gsnVaryingInput,
    valueType: valueType,
    slot: slot,
    name: slot.interfaceName(true)
  ))

proc uniform*(
    builder: GpuShaderBuilder;
    name: string;
    valueType: GpuShaderValueType
): GpuShaderExpression =
  builder.requireOpen()
  name.validateIdentifier("GPU shader uniform name")
  if not name.startsWith("u_") or name in ["u_viewRect", "u_viewTexel",
      "u_view", "u_invView", "u_proj", "u_invProj", "u_viewProj",
      "u_invViewProj", "u_model", "u_modelView", "u_modelViewProj",
      "u_alphaRef"]:
    raise newException(
      GpuShaderBuildError,
      "portable GPU uniform names must use a non-reserved u_ prefix"
    )
  if valueType notin {gsvtVec4, gsvtMat3, gsvtMat4}:
    raise newException(
      GpuShaderBuildError,
      "portable GPU uniforms must be vec4, mat3, or mat4"
    )
  for node in builder.nodes:
    if node.kind == gsnUniform and node.name == name:
      if node.valueType != valueType:
        raise newException(
          GpuShaderBuildError,
          "GPU shader uniform is declared with conflicting types"
        )
  builder.addNode(GpuShaderNode(
    kind: gsnUniform,
    valueType: valueType,
    name: name
  ))

proc construct*(
    builder: GpuShaderBuilder;
    valueType: GpuShaderValueType;
    components: openArray[GpuShaderExpression]
): GpuShaderExpression =
  if valueType notin {gsvtVec2, gsvtVec3, gsvtVec4} or
      components.len != valueType.componentCount:
    raise newException(GpuShaderBuildError, "GPU vector constructor arity is invalid")
  var operands: array[4, int]
  for index, component in components:
    if builder.requireExpression(component).valueType != gsvtFloat:
      raise newException(
        GpuShaderBuildError,
        "GPU vector constructor components must be floats"
      )
    operands[index] = component.nodeIndex
  builder.addNode(GpuShaderNode(
    kind: gsnConstruct,
    valueType: valueType,
    operands: operands,
    operandCount: uint8(components.len)
  ))

proc swizzleType(value: string): GpuShaderValueType =
  case value.len
  of 1: gsvtFloat
  of 2: gsvtVec2
  of 3: gsvtVec3
  of 4: gsvtVec4
  else:
    raise newException(GpuShaderBuildError, "GPU swizzle needs 1 to 4 components")

proc swizzle*(
    builder: GpuShaderBuilder;
    value: GpuShaderExpression;
    components: string
): GpuShaderExpression =
  let node = builder.requireExpression(value)
  if not node.valueType.isVector:
    raise newException(GpuShaderBuildError, "GPU swizzle requires a vector")
  let available = node.valueType.componentCount
  var componentSet = -1
  for component in components:
    let currentSet = if component in {'x', 'y', 'z', 'w'}: 0 else: 1
    let index = case component
      of 'x', 'r': 0
      of 'y', 'g': 1
      of 'z', 'b': 2
      of 'w', 'a': 3
      else: -1
    if index < 0 or index >= available:
      raise newException(GpuShaderBuildError, "GPU swizzle component is invalid")
    if componentSet >= 0 and currentSet != componentSet:
      raise newException(GpuShaderBuildError, "GPU swizzle component sets cannot mix")
    componentSet = currentSet
  builder.addNode(GpuShaderNode(
    kind: gsnSwizzle,
    valueType: components.swizzleType,
    operands: [value.nodeIndex, 0, 0, 0],
    operandCount: 1,
    swizzle: components
  ))

proc unary*(
    builder: GpuShaderBuilder;
    operation: GpuShaderUnaryOperation;
    value: GpuShaderExpression
): GpuShaderExpression =
  let node = builder.requireExpression(value)
  if not node.valueType.isScalarOrVector:
    raise newException(GpuShaderBuildError, "GPU unary operation type is invalid")
  if operation == gsuNormalize and not node.valueType.isVector:
    raise newException(GpuShaderBuildError, "normalize requires a vector")
  builder.addNode(GpuShaderNode(
    kind: gsnUnary,
    valueType: node.valueType,
    operands: [value.nodeIndex, 0, 0, 0],
    operandCount: 1,
    unary: operation
  ))

proc binaryResultType(
    operation: GpuShaderBinaryOperation;
    left, right: GpuShaderValueType
): GpuShaderValueType =
  if not left.isNumeric or not right.isNumeric:
    raise newException(GpuShaderBuildError, "GPU binary operation requires numbers")
  case operation
  of gsbDot:
    if left != right or not left.isVector:
      raise newException(GpuShaderBuildError, "dot requires equal vector types")
    gsvtFloat
  of gsbPower:
    if left != right or not left.isScalarOrVector:
      raise newException(GpuShaderBuildError, "pow requires equal scalar or vector types")
    left
  of gsbMinimum, gsbMaximum:
    if left != right or not left.isScalarOrVector:
      raise newException(
        GpuShaderBuildError,
        "min and max require equal scalar or vector types"
      )
    left
  of gsbMultiply:
    if left == gsvtMat3 and right == gsvtVec3:
      gsvtVec3
    elif left == gsvtMat4 and right == gsvtVec4:
      gsvtVec4
    elif left == right and left.isNumeric:
      left
    elif left == gsvtFloat and right.isScalarOrVector:
      right
    elif right == gsvtFloat and left.isScalarOrVector:
      left
    else:
      raise newException(GpuShaderBuildError, "GPU multiply operand types differ")
  of gsbDivide:
    if left == right and left.isScalarOrVector:
      left
    elif right == gsvtFloat and left.isScalarOrVector:
      left
    else:
      raise newException(GpuShaderBuildError, "GPU divide operand types differ")
  of gsbAdd, gsbSubtract:
    if left == right:
      left
    else:
      raise newException(GpuShaderBuildError, "GPU binary operand types differ")

proc binary*(
    builder: GpuShaderBuilder;
    operation: GpuShaderBinaryOperation;
    left, right: GpuShaderExpression
): GpuShaderExpression =
  let leftNode = builder.requireExpression(left)
  let rightNode = builder.requireExpression(right)
  builder.addNode(GpuShaderNode(
    kind: gsnBinary,
    valueType: operation.binaryResultType(leftNode.valueType, rightNode.valueType),
    operands: [left.nodeIndex, right.nodeIndex, 0, 0],
    operandCount: 2,
    binary: operation
  ))

proc ternary*(
    builder: GpuShaderBuilder;
    operation: GpuShaderTernaryOperation;
    first, second, third: GpuShaderExpression
): GpuShaderExpression =
  let firstType = builder.requireExpression(first).valueType
  let secondType = builder.requireExpression(second).valueType
  let thirdType = builder.requireExpression(third).valueType
  var resultType = firstType
  case operation
  of gstMix:
    if firstType != secondType or not firstType.isScalarOrVector or
        thirdType notin {gsvtFloat, firstType}:
      raise newException(GpuShaderBuildError, "mix operand types are invalid")
  of gstClamp:
    if not firstType.isScalarOrVector or
        secondType notin {gsvtFloat, firstType} or
        thirdType notin {gsvtFloat, firstType}:
      raise newException(GpuShaderBuildError, "clamp operand types are invalid")
  of gstSmoothstep:
    if secondType != firstType or thirdType != firstType or
        not firstType.isScalarOrVector:
      raise newException(GpuShaderBuildError, "smoothstep operand types are invalid")
    resultType = thirdType
  builder.addNode(GpuShaderNode(
    kind: gsnTernary,
    valueType: resultType,
    operands: [first.nodeIndex, second.nodeIndex, third.nodeIndex, 0],
    operandCount: 3,
    ternary: operation
  ))

proc expressionBuilder(value: GpuShaderExpression): GpuShaderBuilder =
  discard value.valueType
  value.owner

proc `+`*(left, right: GpuShaderExpression): GpuShaderExpression =
  left.expressionBuilder.binary(gsbAdd, left, right)

proc `-`*(left, right: GpuShaderExpression): GpuShaderExpression =
  left.expressionBuilder.binary(gsbSubtract, left, right)

proc `*`*(left, right: GpuShaderExpression): GpuShaderExpression =
  left.expressionBuilder.binary(gsbMultiply, left, right)

proc `/`*(left, right: GpuShaderExpression): GpuShaderExpression =
  left.expressionBuilder.binary(gsbDivide, left, right)

proc `-`*(value: GpuShaderExpression): GpuShaderExpression =
  value.expressionBuilder.unary(gsuNegate, value)

proc `*`*(
    value: GpuShaderExpression;
    scalar: float32
): GpuShaderExpression =
  let builder = value.expressionBuilder
  builder.binary(gsbMultiply, value, builder.scalar(scalar))

proc `*`*(
    scalar: float32;
    value: GpuShaderExpression
): GpuShaderExpression =
  value * scalar

proc `/`*(
    value: GpuShaderExpression;
    scalar: float32
): GpuShaderExpression =
  let builder = value.expressionBuilder
  builder.binary(gsbDivide, value, builder.scalar(scalar))

proc sine*(value: GpuShaderExpression): GpuShaderExpression =
  value.expressionBuilder.unary(gsuSine, value)

proc cosine*(value: GpuShaderExpression): GpuShaderExpression =
  value.expressionBuilder.unary(gsuCosine, value)

proc absolute*(value: GpuShaderExpression): GpuShaderExpression =
  value.expressionBuilder.unary(gsuAbsolute, value)

proc normalize*(value: GpuShaderExpression): GpuShaderExpression =
  value.expressionBuilder.unary(gsuNormalize, value)

proc dot*(
    left, right: GpuShaderExpression
): GpuShaderExpression =
  left.expressionBuilder.binary(gsbDot, left, right)

proc minimum*(
    left, right: GpuShaderExpression
): GpuShaderExpression =
  left.expressionBuilder.binary(gsbMinimum, left, right)

proc maximum*(
    left, right: GpuShaderExpression
): GpuShaderExpression =
  left.expressionBuilder.binary(gsbMaximum, left, right)

proc power*(
    left, right: GpuShaderExpression
): GpuShaderExpression =
  left.expressionBuilder.binary(gsbPower, left, right)

proc mix*(
    first, second, factor: GpuShaderExpression
): GpuShaderExpression =
  first.expressionBuilder.ternary(gstMix, first, second, factor)

proc clamp*(
    value, minimum, maximum: GpuShaderExpression
): GpuShaderExpression =
  value.expressionBuilder.ternary(gstClamp, value, minimum, maximum)

proc smoothstep*(
    edge0, edge1, value: GpuShaderExpression
): GpuShaderExpression =
  edge0.expressionBuilder.ternary(gstSmoothstep, edge0, edge1, value)

proc setPositionOutput*(
    builder: GpuShaderBuilder;
    value: GpuShaderExpression
) =
  builder.requireOpen()
  if builder.stageValue != gssVertex:
    raise newException(GpuShaderBuildError, "position output requires a vertex shader")
  if builder.requireExpression(value).valueType != gsvtVec4:
    raise newException(GpuShaderBuildError, "position output must be vec4")
  builder.positionOutput = value.nodeIndex

proc setColorOutput*(
    builder: GpuShaderBuilder;
    value: GpuShaderExpression;
    index = 0
) =
  builder.requireOpen()
  if builder.stageValue != gssFragment:
    raise newException(GpuShaderBuildError, "color output requires a fragment shader")
  if index < 0 or index >= builder.colorOutputs.len:
    raise newException(GpuShaderBuildError, "color output index is invalid")
  if builder.requireExpression(value).valueType != gsvtVec4:
    raise newException(GpuShaderBuildError, "color output must be vec4")
  builder.colorOutputs[index] = value.nodeIndex

proc setVaryingOutput*(
    builder: GpuShaderBuilder;
    slot: GpuShaderInterfaceSlot;
    value: GpuShaderExpression
) =
  builder.requireOpen()
  if builder.stageValue != gssVertex:
    raise newException(GpuShaderBuildError, "varying output requires a vertex shader")
  let node = builder.requireExpression(value)
  if not node.valueType.isScalarOrVector:
    raise newException(GpuShaderBuildError, "varying output type is not portable")
  for item in builder.varyingOutputs.mitems:
    if item.slot == slot:
      item.expression = value.nodeIndex
      return
  if builder.varyingOutputs.len >= maxGpuShaderOutputs:
    raise newException(GpuShaderBuildError, "GPU shader output limit exceeded")
  builder.varyingOutputs.add GpuShaderVaryingOutput(
    slot: slot,
    expression: value.nodeIndex
  )

proc formatFloat(value: float32): string =
  result = $value
  if '.' notin result and 'e' notin result and 'E' notin result:
    result.add(".0")

proc nodeReference(builder: GpuShaderBuilder; index: int): string =
  let node = builder.nodes[index]
  case node.kind
  of gsnLiteral:
    if node.valueType == gsvtFloat:
      result = node.values[0].formatFloat
    else:
      var values: seq[string]
      for component in 0 ..< node.valueType.componentCount:
        values.add node.values[component].formatFloat
      result = node.valueType.valueTypeName & "(" & values.join(", ") & ")"
  of gsnVertexInput, gsnVaryingInput, gsnUniform:
    result = node.name
  else:
    result = "cbss_n" & $index

proc nodeExpression(builder: GpuShaderBuilder; index: int): string =
  let node = builder.nodes[index]
  case node.kind
  of gsnLiteral, gsnVertexInput, gsnVaryingInput, gsnUniform:
    result = builder.nodeReference(index)
  of gsnConstruct:
    var values: seq[string]
    for operand in 0 ..< int(node.operandCount):
      values.add builder.nodeReference(node.operands[operand])
    result = node.valueType.valueTypeName & "(" & values.join(", ") & ")"
  of gsnSwizzle:
    result = "(" & builder.nodeReference(node.operands[0]) & ")." &
      node.swizzle
  of gsnUnary:
    let value = builder.nodeReference(node.operands[0])
    case node.unary
    of gsuNegate: result = "(-(" & value & "))"
    of gsuSine: result = "sin(" & value & ")"
    of gsuCosine: result = "cos(" & value & ")"
    of gsuAbsolute: result = "abs(" & value & ")"
    of gsuFloor: result = "floor(" & value & ")"
    of gsuCeil: result = "ceil(" & value & ")"
    of gsuNormalize: result = "normalize(" & value & ")"
  of gsnBinary:
    let left = builder.nodeReference(node.operands[0])
    let right = builder.nodeReference(node.operands[1])
    case node.binary
    of gsbAdd: result = "((" & left & ") + (" & right & "))"
    of gsbSubtract: result = "((" & left & ") - (" & right & "))"
    of gsbMultiply: result = "((" & left & ") * (" & right & "))"
    of gsbDivide: result = "((" & left & ") / (" & right & "))"
    of gsbMinimum: result = "min(" & left & ", " & right & ")"
    of gsbMaximum: result = "max(" & left & ", " & right & ")"
    of gsbDot: result = "dot(" & left & ", " & right & ")"
    of gsbPower: result = "pow(" & left & ", " & right & ")"
  of gsnTernary:
    let first = builder.nodeReference(node.operands[0])
    let second = builder.nodeReference(node.operands[1])
    let third = builder.nodeReference(node.operands[2])
    let name = case node.ternary
      of gstMix: "mix"
      of gstClamp: "clamp"
      of gstSmoothstep: "smoothstep"
    result = name & "(" & first & ", " & second & ", " & third & ")"

proc addUnique(
    values: var seq[GpuShaderInterfaceEntry];
    entry: GpuShaderInterfaceEntry
) =
  for value in values:
    if value.slot == entry.slot:
      if value.valueType != entry.valueType:
        raise newException(
          GpuShaderBuildError,
          "GPU shader interface slot has conflicting types"
        )
      return
  values.add entry

proc emitGpuShaderSource*(builder: GpuShaderBuilder): GpuShaderSource =
  if builder.isNil:
    raise newException(GpuShaderBuildError, "GPU shader builder cannot be nil")
  if builder.stageValue == gssCompute:
    raise newException(
      GpuShaderBuildError,
      "typed compute storage operations are not implemented"
    )
  if builder.stageValue == gssVertex and builder.positionOutput < 0:
    raise newException(GpuShaderBuildError, "vertex shader has no position output")
  if builder.stageValue == gssFragment and builder.colorOutputs[0] < 0:
    raise newException(GpuShaderBuildError, "fragment shader has no color output")

  result.stage = builder.stageValue
  result.label = builder.labelValue
  var uniforms = initOrderedTable[string, GpuShaderValueType]()
  var inputNames: seq[string]
  var outputNames: seq[string]
  for node in builder.nodes:
    case node.kind
    of gsnVertexInput:
      result.inputs.addUnique GpuShaderInterfaceEntry(
        slot: node.slot, valueType: node.valueType
      )
      if node.name notin inputNames:
        inputNames.add node.name
    of gsnVaryingInput:
      result.inputs.addUnique GpuShaderInterfaceEntry(
        slot: node.slot, valueType: node.valueType
      )
      if node.name notin inputNames:
        inputNames.add node.name
    of gsnUniform:
      if node.name in uniforms and uniforms[node.name] != node.valueType:
        raise newException(
          GpuShaderBuildError,
          "GPU shader uniform has conflicting declarations"
        )
      uniforms[node.name] = node.valueType
    else:
      discard

  if builder.stageValue == gssVertex:
    for item in builder.varyingOutputs:
      let node = builder.nodes[item.expression]
      result.outputs.addUnique GpuShaderInterfaceEntry(
        slot: item.slot, valueType: node.valueType
      )
      outputNames.add item.slot.interfaceName(true)

  if inputNames.len > 0:
    result.source.add "$input " & inputNames.join(", ") & "\n"
  if outputNames.len > 0:
    result.source.add "$output " & outputNames.join(", ") & "\n"
  result.source.add "#include <bgfx_shader.sh>\n\n"
  for name, valueType in uniforms.pairs:
    result.source.add "uniform " & valueType.valueTypeName & " " & name & ";\n"
  if uniforms.len > 0:
    result.source.add "\n"
  result.source.add "void main()\n{\n"
  for index, node in builder.nodes:
    if node.kind notin {gsnLiteral, gsnVertexInput, gsnVaryingInput, gsnUniform}:
      result.source.add "  " & node.valueType.valueTypeName & " cbss_n" &
        $index & " = " & builder.nodeExpression(index) & ";\n"
  if builder.stageValue == gssVertex:
    for item in builder.varyingOutputs:
      result.source.add "  " & item.slot.interfaceName(true) & " = " &
        builder.nodeReference(item.expression) & ";\n"
    result.source.add "  gl_Position = " &
      builder.nodeReference(builder.positionOutput) & ";\n"
  else:
    for index, expression in builder.colorOutputs:
      if expression >= 0:
        let output = if index == 0: "gl_FragColor" else: "gl_FragData[" & $index & "]"
        result.source.add "  " & output & " = " &
          builder.nodeReference(expression) & ";\n"
  result.source.add "}\n"

  var definitions = initOrderedTable[string, string]()
  for node in builder.nodes:
    if node.kind in {gsnVertexInput, gsnVaryingInput}:
      let definition = node.valueType.valueTypeName & " " & node.name & " : " &
        node.slot.interfaceSemantic & ";\n"
      if node.name in definitions and definitions[node.name] != definition:
        raise newException(
          GpuShaderBuildError,
          "GPU shader interface name has conflicting types"
        )
      definitions[node.name] = definition
  for item in builder.varyingOutputs:
    let node = builder.nodes[item.expression]
    let name = item.slot.interfaceName(true)
    let definition = node.valueType.valueTypeName & " " & name & " : " &
      item.slot.interfaceSemantic & ";\n"
    if name in definitions and definitions[name] != definition:
      raise newException(
        GpuShaderBuildError,
        "GPU shader interface name has conflicting types"
      )
    definitions[name] = definition
  for definition in definitions.values:
    result.varyingDefinitions.add definition

  if result.source.len > maxGpuShaderSourceBytes or
      result.varyingDefinitions.len > maxGpuShaderSourceBytes:
    raise newException(GpuShaderBuildError, "GPU shader source limit exceeded")
  builder.sealed = true

proc validateGpuShaderInterface*(
    vertex, fragment: GpuShaderSource
) =
  if vertex.stage != gssVertex or fragment.stage != gssFragment:
    raise newException(
      GpuShaderBuildError,
      "GPU shader interface requires vertex and fragment sources"
    )
  for input in fragment.inputs:
    var matched = false
    for output in vertex.outputs:
      if output.slot == input.slot:
        matched = true
        if output.valueType != input.valueType:
          raise newException(
            GpuShaderBuildError,
            "GPU shader varying types do not match"
          )
        break
    if not matched:
      raise newException(
        GpuShaderBuildError,
        "fragment shader input has no matching vertex output"
      )

proc gpuShaderSourceHash*(source: GpuShaderSource): uint64 =
  var sourceHash = 14_695_981_039_346_656_037'u64
  for value in source.source & "\n" & source.varyingDefinitions:
    sourceHash = (sourceHash xor uint64(uint8(value))) * 1_099_511_628_211'u64
  sourceHash

proc gpuShaderArtifact*(
    source: GpuShaderSource;
    bytecode: sink seq[byte]
): GpuShaderArtifact =
  if bytecode.len == 0:
    raise newException(GpuShaderBuildError, "GPU shader bytecode cannot be empty")
  GpuShaderArtifact(
    descriptor: GpuShaderDescriptor(stage: source.stage, label: source.label),
    bytecode: bytecode,
    sourceHash: source.gpuShaderSourceHash()
  )

proc createGpuShader*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    artifact: GpuShaderArtifact
): GpuResourceHandle =
  host.createGpuShader(namespace, artifact.descriptor, artifact.bytecode)
