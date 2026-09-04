import std/[math, strutils, tables]

import clay_board_style_system/runtime/gpu_host

const
  maxGpuShaderNodes* = 4096
  maxGpuShaderOutputs* = 32
  maxGpuShaderSourceBytes* = 1024 * 1024
  maxGpuComputeThreadsPerGroup* = 1024'u32
  maxGpuComputeWorkGroupX* = 1024'u32
  maxGpuComputeWorkGroupY* = 1024'u32
  maxGpuComputeWorkGroupZ* = 64'u32

type
  GpuShaderBuildError* = object of CatchableError

  GpuShaderValueType* = enum
    gsvtBool,
    gsvtFloat,
    gsvtVec2,
    gsvtVec3,
    gsvtVec4,
    gsvtMat3,
    gsvtMat4,
    gsvtInt,
    gsvtUint,
    gsvtIVec2,
    gsvtIVec3,
    gsvtIVec4,
    gsvtUVec2,
    gsvtUVec3,
    gsvtUVec4

  GpuShaderComputeBuiltin* = enum
    gscbGlobalInvocationId,
    gscbLocalInvocationId,
    gscbWorkGroupId,
    gscbLocalInvocationIndex,
    gscbWorkGroupCount

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
    gsnTernary,
    gsnComputeBuiltin,
    gsnStorageLoad,
    gsnStorageStore

  GpuShaderNode = object
    kind: GpuShaderNodeKind
    valueType: GpuShaderValueType
    name: string
    slot: GpuShaderInterfaceSlot
    values: array[4, float32]
    signedValues: array[4, int32]
    unsignedValues: array[4, uint32]
    operands: array[4, int]
    operandCount: uint8
    storageBufferIndex: int
    swizzle: string
    unary: GpuShaderUnaryOperation
    binary: GpuShaderBinaryOperation
    ternary: GpuShaderTernaryOperation
    computeBuiltin: GpuShaderComputeBuiltin

  GpuShaderVaryingOutput = object
    slot: GpuShaderInterfaceSlot
    expression: int

  GpuShaderStorageEntry* = object
    name*: string
    stage*: uint8
    format*: GpuStorageBufferFormat
    access*: GpuStorageAccess

  GpuShaderBuilder* = ref object
    stageValue: GpuShaderStage
    labelValue: string
    nodes: seq[GpuShaderNode]
    positionOutput: int
    colorOutputs: array[4, int]
    varyingOutputs: seq[GpuShaderVaryingOutput]
    storageBuffers: seq[GpuShaderStorageEntry]
    computeWorkGroupSize: array[3, uint32]
    hasComputeWorkGroupSize: bool
    sealed: bool

  GpuShaderExpression* = object
    owner: GpuShaderBuilder
    nodeIndex: int

  GpuShaderStorageBuffer* = object
    owner: GpuShaderBuilder
    storageIndex: int

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
    storageBuffers*: seq[GpuShaderStorageEntry]
    computeWorkGroupSize*: array[3, uint32]

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
  of gsvtInt: "int"
  of gsvtUint: "uint"
  of gsvtIVec2: "ivec2"
  of gsvtIVec3: "ivec3"
  of gsvtIVec4: "ivec4"
  of gsvtUVec2: "uvec2"
  of gsvtUVec3: "uvec3"
  of gsvtUVec4: "uvec4"

proc componentCount(value: GpuShaderValueType): int =
  case value
  of gsvtBool, gsvtFloat, gsvtInt, gsvtUint: 1
  of gsvtVec2, gsvtIVec2, gsvtUVec2: 2
  of gsvtVec3, gsvtIVec3, gsvtUVec3: 3
  of gsvtVec4, gsvtIVec4, gsvtUVec4: 4
  of gsvtMat3: 9
  of gsvtMat4: 16

proc isNumeric(value: GpuShaderValueType): bool {.inline.} =
  value != gsvtBool

proc isScalarOrVector(value: GpuShaderValueType): bool {.inline.} =
  value in {
    gsvtFloat, gsvtVec2, gsvtVec3, gsvtVec4,
    gsvtInt, gsvtIVec2, gsvtIVec3, gsvtIVec4,
    gsvtUint, gsvtUVec2, gsvtUVec3, gsvtUVec4
  }

proc isVector(value: GpuShaderValueType): bool {.inline.} =
  value in {
    gsvtVec2, gsvtVec3, gsvtVec4,
    gsvtIVec2, gsvtIVec3, gsvtIVec4,
    gsvtUVec2, gsvtUVec3, gsvtUVec4
  }

proc isFloating(value: GpuShaderValueType): bool {.inline.} =
  value in {gsvtFloat, gsvtVec2, gsvtVec3, gsvtVec4}

proc isSigned(value: GpuShaderValueType): bool {.inline.} =
  value in {gsvtInt, gsvtIVec2, gsvtIVec3, gsvtIVec4}

proc isUnsigned(value: GpuShaderValueType): bool {.inline.} =
  value in {gsvtUint, gsvtUVec2, gsvtUVec3, gsvtUVec4}

proc scalarType(value: GpuShaderValueType): GpuShaderValueType =
  if value.isFloating: gsvtFloat
  elif value.isSigned: gsvtInt
  elif value.isUnsigned: gsvtUint
  else:
    raise newException(GpuShaderBuildError, "GPU value has no scalar type")

proc vectorType(
    scalar: GpuShaderValueType;
    components: int
): GpuShaderValueType =
  if components < 2 or components > 4:
    raise newException(GpuShaderBuildError, "GPU vector needs 2 to 4 components")
  case scalar
  of gsvtFloat: GpuShaderValueType(ord(gsvtVec2) + components - 2)
  of gsvtInt: GpuShaderValueType(ord(gsvtIVec2) + components - 2)
  of gsvtUint: GpuShaderValueType(ord(gsvtUVec2) + components - 2)
  else:
    raise newException(GpuShaderBuildError, "GPU vector scalar type is invalid")

proc storageValueType(format: GpuStorageBufferFormat): GpuShaderValueType =
  case format
  of gsbfInt32: gsvtInt
  of gsbfUint32: gsvtUint
  of gsbfFloat32: gsvtFloat
  of gsbfInt32x2: gsvtIVec2
  of gsbfUint32x2: gsvtUVec2
  of gsbfFloat32x2: gsvtVec2
  of gsbfInt32x4: gsvtIVec4
  of gsbfUint32x4: gsvtUVec4
  of gsbfFloat32x4: gsvtVec4

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

proc addStatement(builder: GpuShaderBuilder; node: sink GpuShaderNode) =
  builder.requireMutable()
  builder.nodes.add(node)

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

proc requireStorageBuffer(
    builder: GpuShaderBuilder;
    storage: GpuShaderStorageBuffer
): GpuShaderStorageEntry =
  if storage.owner != builder or storage.storageIndex < 0 or
      storage.storageIndex >= builder.storageBuffers.len:
    raise newException(
      GpuShaderBuildError,
      "GPU shader storage buffer belongs to another builder or is invalid"
    )
  builder.storageBuffers[storage.storageIndex]

proc storageBufferAt*(
    builder: GpuShaderBuilder;
    id: uint32
): GpuShaderStorageBuffer =
  if builder.isNil or id == 0 or uint64(id) > uint64(builder.storageBuffers.len):
    raise newException(GpuShaderBuildError, "GPU shader storage buffer id is invalid")
  GpuShaderStorageBuffer(owner: builder, storageIndex: int(id) - 1)

proc storageBufferId*(storage: GpuShaderStorageBuffer): uint32 =
  if storage.owner.isNil or storage.storageIndex < 0 or
      storage.storageIndex >= storage.owner.storageBuffers.len:
    raise newException(GpuShaderBuildError, "GPU shader storage buffer is invalid")
  uint32(storage.storageIndex + 1)

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
    valueType: vectorType(gsvtFloat, values.len),
    values: stored
  ))

proc signedInteger*(
    builder: GpuShaderBuilder;
    value: int32
): GpuShaderExpression =
  builder.addNode(GpuShaderNode(
    kind: gsnLiteral,
    valueType: gsvtInt,
    signedValues: [value, 0'i32, 0'i32, 0'i32]
  ))

proc unsignedInteger*(
    builder: GpuShaderBuilder;
    value: uint32
): GpuShaderExpression =
  builder.addNode(GpuShaderNode(
    kind: gsnLiteral,
    valueType: gsvtUint,
    unsignedValues: [value, 0'u32, 0'u32, 0'u32]
  ))

proc signedVector*(
    builder: GpuShaderBuilder;
    values: openArray[int32]
): GpuShaderExpression =
  if values.len < 2 or values.len > 4:
    raise newException(GpuShaderBuildError, "GPU vector needs 2 to 4 components")
  var stored: array[4, int32]
  for index, value in values:
    stored[index] = value
  builder.addNode(GpuShaderNode(
    kind: gsnLiteral,
    valueType: vectorType(gsvtInt, values.len),
    signedValues: stored
  ))

proc unsignedVector*(
    builder: GpuShaderBuilder;
    values: openArray[uint32]
): GpuShaderExpression =
  if values.len < 2 or values.len > 4:
    raise newException(GpuShaderBuildError, "GPU vector needs 2 to 4 components")
  var stored: array[4, uint32]
  for index, value in values:
    stored[index] = value
  builder.addNode(GpuShaderNode(
    kind: gsnLiteral,
    valueType: vectorType(gsvtUint, values.len),
    unsignedValues: stored
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

proc setComputeWorkGroupSize*(
    builder: GpuShaderBuilder;
    x, y, z: uint32
) =
  builder.requireOpen()
  if builder.stageValue != gssCompute:
    raise newException(GpuShaderBuildError, "work-group size requires a compute shader")
  if x == 0 or y == 0 or z == 0 or x > maxGpuComputeWorkGroupX or
      y > maxGpuComputeWorkGroupY or z > maxGpuComputeWorkGroupZ or
      uint64(x) * uint64(y) * uint64(z) > uint64(maxGpuComputeThreadsPerGroup):
    raise newException(GpuShaderBuildError, "GPU compute work-group size is invalid")
  builder.computeWorkGroupSize = [x, y, z]
  builder.hasComputeWorkGroupSize = true

proc storageBuffer*(
    builder: GpuShaderBuilder;
    name: string;
    stage: uint8;
    format: GpuStorageBufferFormat;
    access: GpuStorageAccess
): GpuShaderStorageBuffer =
  builder.requireOpen()
  if builder.stageValue != gssCompute:
    raise newException(GpuShaderBuildError, "storage buffers require a compute shader")
  name.validateIdentifier("GPU shader storage buffer name")
  if not name.startsWith("b_"):
    raise newException(
      GpuShaderBuildError,
      "portable GPU storage buffer names must use a b_ prefix"
    )
  if stage >= uint8(maxGpuStorageBufferBindings):
    raise newException(GpuShaderBuildError, "GPU storage buffer stage is invalid")
  if builder.storageBuffers.len >= maxGpuStorageBufferBindings:
    raise newException(GpuShaderBuildError, "GPU storage buffer limit exceeded")
  for storage in builder.storageBuffers:
    if storage.name == name:
      raise newException(GpuShaderBuildError, "GPU storage buffer name is duplicated")
    if storage.stage == stage:
      raise newException(GpuShaderBuildError, "GPU storage buffer stage is duplicated")
  builder.storageBuffers.add GpuShaderStorageEntry(
    name: name,
    stage: stage,
    format: format,
    access: access
  )
  GpuShaderStorageBuffer(
    owner: builder,
    storageIndex: builder.storageBuffers.high
  )

proc computeBuiltin*(
    builder: GpuShaderBuilder;
    builtin: GpuShaderComputeBuiltin
): GpuShaderExpression =
  builder.requireOpen()
  if builder.stageValue != gssCompute:
    raise newException(GpuShaderBuildError, "compute builtins require a compute shader")
  let valueType = case builtin
    of gscbLocalInvocationIndex: gsvtUint
    else: gsvtUVec3
  builder.addNode(GpuShaderNode(
    kind: gsnComputeBuiltin,
    valueType: valueType,
    computeBuiltin: builtin
  ))

proc globalInvocationId*(builder: GpuShaderBuilder): GpuShaderExpression =
  builder.computeBuiltin(gscbGlobalInvocationId)

proc localInvocationId*(builder: GpuShaderBuilder): GpuShaderExpression =
  builder.computeBuiltin(gscbLocalInvocationId)

proc workGroupId*(builder: GpuShaderBuilder): GpuShaderExpression =
  builder.computeBuiltin(gscbWorkGroupId)

proc localInvocationIndex*(builder: GpuShaderBuilder): GpuShaderExpression =
  builder.computeBuiltin(gscbLocalInvocationIndex)

proc workGroupCount*(builder: GpuShaderBuilder): GpuShaderExpression =
  builder.computeBuiltin(gscbWorkGroupCount)

proc loadStorage*(
    builder: GpuShaderBuilder;
    storage: GpuShaderStorageBuffer;
    index: GpuShaderExpression
): GpuShaderExpression =
  builder.requireOpen()
  let declaration = builder.requireStorageBuffer(storage)
  if declaration.access == gsaWrite:
    raise newException(GpuShaderBuildError, "write-only GPU storage cannot be read")
  if builder.requireExpression(index).valueType != gsvtUint:
    raise newException(GpuShaderBuildError, "GPU storage index must be uint")
  builder.addNode(GpuShaderNode(
    kind: gsnStorageLoad,
    valueType: declaration.format.storageValueType,
    operands: [index.nodeIndex, 0, 0, 0],
    operandCount: 1,
    storageBufferIndex: storage.storageIndex
  ))

proc storeStorage*(
    builder: GpuShaderBuilder;
    storage: GpuShaderStorageBuffer;
    index, value: GpuShaderExpression
) =
  builder.requireOpen()
  let declaration = builder.requireStorageBuffer(storage)
  if declaration.access == gsaRead:
    raise newException(GpuShaderBuildError, "read-only GPU storage cannot be written")
  if builder.requireExpression(index).valueType != gsvtUint:
    raise newException(GpuShaderBuildError, "GPU storage index must be uint")
  if builder.requireExpression(value).valueType != declaration.format.storageValueType:
    raise newException(GpuShaderBuildError, "GPU storage value type does not match")
  builder.addStatement(GpuShaderNode(
    kind: gsnStorageStore,
    operands: [index.nodeIndex, value.nodeIndex, 0, 0],
    operandCount: 2,
    storageBufferIndex: storage.storageIndex
  ))

proc construct*(
    builder: GpuShaderBuilder;
    valueType: GpuShaderValueType;
    components: openArray[GpuShaderExpression]
): GpuShaderExpression =
  if not valueType.isVector or components.len != valueType.componentCount:
    raise newException(GpuShaderBuildError, "GPU vector constructor arity is invalid")
  let expectedScalar = valueType.scalarType
  var operands: array[4, int]
  for index, component in components:
    if builder.requireExpression(component).valueType != expectedScalar:
      raise newException(
        GpuShaderBuildError,
        "GPU vector constructor component type is invalid"
      )
    operands[index] = component.nodeIndex
  builder.addNode(GpuShaderNode(
    kind: gsnConstruct,
    valueType: valueType,
    operands: operands,
    operandCount: uint8(components.len)
  ))

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
    valueType: if components.len == 1:
      node.valueType.scalarType
    else:
      vectorType(node.valueType.scalarType, components.len),
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
  case operation
  of gsuNegate:
    if node.valueType.isUnsigned:
      raise newException(GpuShaderBuildError, "unsigned values cannot be negated")
  of gsuSine, gsuCosine, gsuFloor, gsuCeil:
    if not node.valueType.isFloating:
      raise newException(GpuShaderBuildError, "GPU operation requires floating values")
  of gsuAbsolute:
    if node.valueType.isUnsigned:
      raise newException(GpuShaderBuildError, "unsigned values do not need absolute")
  of gsuNormalize:
    if not node.valueType.isFloating or not node.valueType.isVector:
      raise newException(GpuShaderBuildError, "normalize requires a floating vector")
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
    if left != right or not left.isFloating or not left.isVector:
      raise newException(GpuShaderBuildError, "dot requires equal floating vectors")
    gsvtFloat
  of gsbPower:
    if left != right or not left.isFloating:
      raise newException(GpuShaderBuildError, "pow requires equal floating values")
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
    elif left == right and left.isScalarOrVector:
      left
    elif left in {gsvtFloat, gsvtInt, gsvtUint} and
        right.isScalarOrVector and left == right.scalarType:
      right
    elif right in {gsvtFloat, gsvtInt, gsvtUint} and
        left.isScalarOrVector and right == left.scalarType:
      left
    else:
      raise newException(GpuShaderBuildError, "GPU multiply operand types differ")
  of gsbDivide:
    if left == right and left.isScalarOrVector:
      left
    elif right in {gsvtFloat, gsvtInt, gsvtUint} and
        left.isScalarOrVector and right == left.scalarType:
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
    if firstType != secondType or not firstType.isFloating or
        thirdType notin {gsvtFloat, firstType}:
      raise newException(GpuShaderBuildError, "mix operand types are invalid")
  of gstClamp:
    if not firstType.isScalarOrVector or
        (secondType != firstType.scalarType and secondType != firstType) or
        (thirdType != firstType.scalarType and thirdType != firstType):
      raise newException(GpuShaderBuildError, "clamp operand types are invalid")
  of gstSmoothstep:
    if secondType != firstType or thirdType != firstType or
        not firstType.isFloating:
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

proc formatUnsigned(value: uint32): string =
  $value & "u"

proc computeBuiltinName(value: GpuShaderComputeBuiltin): string =
  case value
  of gscbGlobalInvocationId: "gl_GlobalInvocationID"
  of gscbLocalInvocationId: "gl_LocalInvocationID"
  of gscbWorkGroupId: "gl_WorkGroupID"
  of gscbLocalInvocationIndex: "gl_LocalInvocationIndex"
  of gscbWorkGroupCount: "gl_NumWorkGroups"

proc storageMacro(value: GpuStorageAccess): string =
  case value
  of gsaRead: "BUFFER_RO"
  of gsaWrite: "BUFFER_WO"
  of gsaReadWrite: "BUFFER_RW"

proc nodeReference(builder: GpuShaderBuilder; index: int): string =
  let node = builder.nodes[index]
  case node.kind
  of gsnLiteral:
    if node.valueType == gsvtFloat:
      result = node.values[0].formatFloat
    elif node.valueType == gsvtInt:
      result = $node.signedValues[0]
    elif node.valueType == gsvtUint:
      result = node.unsignedValues[0].formatUnsigned
    else:
      var values: seq[string]
      for component in 0 ..< node.valueType.componentCount:
        if node.valueType.isFloating:
          values.add node.values[component].formatFloat
        elif node.valueType.isSigned:
          values.add $node.signedValues[component]
        elif node.valueType.isUnsigned:
          values.add node.unsignedValues[component].formatUnsigned
      result = node.valueType.valueTypeName & "(" & values.join(", ") & ")"
  of gsnVertexInput, gsnVaryingInput, gsnUniform:
    result = node.name
  of gsnComputeBuiltin:
    result = node.computeBuiltin.computeBuiltinName
  else:
    result = "cbss_n" & $index

proc nodeExpression(builder: GpuShaderBuilder; index: int): string =
  let node = builder.nodes[index]
  case node.kind
  of gsnLiteral, gsnVertexInput, gsnVaryingInput, gsnUniform, gsnComputeBuiltin:
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
  of gsnStorageLoad:
    let storage = builder.storageBuffers[node.storageBufferIndex]
    result = storage.name & "[" & builder.nodeReference(node.operands[0]) & "]"
  of gsnStorageStore:
    result = ""

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
  if builder.stageValue == gssVertex and builder.positionOutput < 0:
    raise newException(GpuShaderBuildError, "vertex shader has no position output")
  if builder.stageValue == gssFragment and builder.colorOutputs[0] < 0:
    raise newException(GpuShaderBuildError, "fragment shader has no color output")
  if builder.stageValue == gssCompute:
    if not builder.hasComputeWorkGroupSize:
      raise newException(GpuShaderBuildError, "compute shader has no work-group size")
    var hasStore = false
    for node in builder.nodes:
      if node.kind == gsnStorageStore:
        hasStore = true
        break
    if not hasStore:
      raise newException(GpuShaderBuildError, "compute shader has no storage output")

  result.stage = builder.stageValue
  result.label = builder.labelValue
  result.storageBuffers = builder.storageBuffers
  result.computeWorkGroupSize = builder.computeWorkGroupSize
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
  if builder.stageValue == gssCompute:
    result.source.add "#include <bgfx_compute.sh>\n\n"
    for storage in builder.storageBuffers:
      result.source.add storage.access.storageMacro & "(" & storage.name & ", " &
        storage.format.storageValueType.valueTypeName & ", " & $storage.stage & ");\n"
    if builder.storageBuffers.len > 0:
      result.source.add "\n"
  else:
    result.source.add "#include <bgfx_shader.sh>\n\n"
  for name, valueType in uniforms.pairs:
    result.source.add "uniform " & valueType.valueTypeName & " " & name & ";\n"
  if uniforms.len > 0:
    result.source.add "\n"
  if builder.stageValue == gssCompute:
    result.source.add "NUM_THREADS(" & $builder.computeWorkGroupSize[0] & ", " &
      $builder.computeWorkGroupSize[1] & ", " &
      $builder.computeWorkGroupSize[2] & ")\n"
  result.source.add "void main()\n{\n"
  for index, node in builder.nodes:
    if node.kind == gsnStorageStore:
      let storage = builder.storageBuffers[node.storageBufferIndex]
      result.source.add "  " & storage.name & "[" &
        builder.nodeReference(node.operands[0]) & "] = " &
        builder.nodeReference(node.operands[1]) & ";\n"
    elif node.kind notin {
        gsnLiteral, gsnVertexInput, gsnVaryingInput, gsnUniform,
        gsnComputeBuiltin
    }:
      result.source.add "  " & node.valueType.valueTypeName & " cbss_n" &
        $index & " = " & builder.nodeExpression(index) & ";\n"
  case builder.stageValue
  of gssVertex:
    for item in builder.varyingOutputs:
      result.source.add "  " & item.slot.interfaceName(true) & " = " &
        builder.nodeReference(item.expression) & ";\n"
    result.source.add "  gl_Position = " &
      builder.nodeReference(builder.positionOutput) & ";\n"
  of gssFragment:
    for index, expression in builder.colorOutputs:
      if expression >= 0:
        let output = if index == 0: "gl_FragColor" else: "gl_FragData[" & $index & "]"
        result.source.add "  " & output & " = " &
          builder.nodeReference(expression) & ";\n"
  of gssCompute:
    discard
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
