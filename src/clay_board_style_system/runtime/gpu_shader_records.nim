import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder]

const
  maxGpuPackedRecordFields* = 64
  maxGpuPackedRecordWords* = 1024'u32
  automaticGpuPackedWordOffset* = high(uint32)

type
  GpuPackedRecordFieldSpec* = object
    name*: string
    valueType*: GpuShaderValueType
    wordOffset*: uint32

  GpuPackedRecordField* = object
    name*: string
    valueType*: GpuShaderValueType
    wordOffset*: uint32
    wordCount*: uint32

  GpuPackedRecordLayout* = object
    fields*: seq[GpuPackedRecordField]
    wordStride*: uint32

  GpuPackedStorageBuffer* = object
    builder: GpuShaderBuilder
    storage: GpuShaderStorageBuffer
    layoutValue: GpuPackedRecordLayout

proc packedWordCount(valueType: GpuShaderValueType): uint32 =
  case valueType
  of gsvtFloat, gsvtUint: 1
  of gsvtVec2, gsvtUVec2: 2
  of gsvtVec3, gsvtUVec3: 3
  of gsvtVec4, gsvtUVec4: 4
  else:
    raise newException(
      GpuShaderBuildError,
      "packed GPU records support float and uint scalar or vector fields"
    )

proc validatePackedFieldName(value: string) =
  if value.len == 0 or value.len > maxGpuResourceLabelBytes:
    raise newException(GpuShaderBuildError, "packed GPU field name is invalid")
  for index, character in value:
    if not (character == '_' or character in {'a' .. 'z'} or
        character in {'A' .. 'Z'} or
        (index > 0 and character in {'0' .. '9'})):
      raise newException(
        GpuShaderBuildError,
        "packed GPU field name must be a portable identifier"
      )

proc gpuPackedField*(
    name: string;
    valueType: GpuShaderValueType
): GpuPackedRecordFieldSpec =
  GpuPackedRecordFieldSpec(
    name: name,
    valueType: valueType,
    wordOffset: automaticGpuPackedWordOffset
  )

proc gpuPackedFieldAt*(
    name: string;
    valueType: GpuShaderValueType;
    wordOffset: uint32
): GpuPackedRecordFieldSpec =
  GpuPackedRecordFieldSpec(
    name: name,
    valueType: valueType,
    wordOffset: wordOffset
  )

proc gpuPackedRecordLayout*(
    specifications: openArray[GpuPackedRecordFieldSpec];
    wordStride = 0'u32
): GpuPackedRecordLayout =
  if specifications.len == 0 or specifications.len > maxGpuPackedRecordFields:
    raise newException(GpuShaderBuildError, "packed GPU field count is invalid")

  var occupied = newSeq[bool](int(maxGpuPackedRecordWords))
  var cursor = 0'u32
  var requiredWords = 0'u32
  result.fields = newSeqOfCap[GpuPackedRecordField](specifications.len)

  for specification in specifications:
    specification.name.validatePackedFieldName()
    for field in result.fields:
      if field.name == specification.name:
        raise newException(GpuShaderBuildError, "packed GPU field name is duplicated")

    let count = specification.valueType.packedWordCount()
    let offset = if specification.wordOffset == automaticGpuPackedWordOffset:
      cursor
    else:
      specification.wordOffset
    if offset >= maxGpuPackedRecordWords or
        count > maxGpuPackedRecordWords - offset:
      raise newException(GpuShaderBuildError, "packed GPU field exceeds record limits")
    for word in offset ..< offset + count:
      if occupied[int(word)]:
        raise newException(GpuShaderBuildError, "packed GPU fields overlap")
      occupied[int(word)] = true
    requiredWords = max(requiredWords, offset + count)
    cursor = max(cursor, offset + count)
    result.fields.add GpuPackedRecordField(
      name: specification.name,
      valueType: specification.valueType,
      wordOffset: offset,
      wordCount: count
    )

  result.wordStride = if wordStride == 0: requiredWords else: wordStride
  if result.wordStride < requiredWords or result.wordStride > maxGpuPackedRecordWords:
    raise newException(GpuShaderBuildError, "packed GPU record stride is invalid")

proc recordStrideBytes*(layout: GpuPackedRecordLayout): uint64 =
  uint64(layout.wordStride) * 4'u64

proc packedRecordBufferBytes*(
    layout: GpuPackedRecordLayout;
    recordCount: uint32
): uint64 =
  if layout.wordStride == 0 or recordCount == 0:
    raise newException(GpuShaderBuildError, "packed GPU buffer dimensions are invalid")
  result = uint64(layout.wordStride) * uint64(recordCount) * 4'u64
  if result > uint64(high(uint32)):
    raise newException(GpuShaderBuildError, "packed GPU buffer exceeds host limits")

proc fieldOffsetBytes*(field: GpuPackedRecordField): uint64 =
  uint64(field.wordOffset) * 4'u64

proc packedRecordBufferDescriptor*(
    layout: GpuPackedRecordLayout;
    recordCount: uint32;
    storageAccess: GpuStorageAccess;
    access = gbaDynamic;
    label = ""
): GpuBufferDescriptor =
  GpuBufferDescriptor(
    byteSize: layout.packedRecordBufferBytes(recordCount),
    role: gbrStorage,
    access: access,
    storageFormat: gsbfUint32,
    storageAccess: storageAccess,
    label: label
  )

proc packedRecordBuffer*(
    builder: GpuShaderBuilder;
    name: string;
    stage: uint8;
    layout: GpuPackedRecordLayout;
    access: GpuStorageAccess
): GpuPackedStorageBuffer =
  if layout.wordStride == 0 or layout.fields.len == 0:
    raise newException(GpuShaderBuildError, "packed GPU record layout is empty")
  GpuPackedStorageBuffer(
    builder: builder,
    storage: builder.storageBuffer(name, stage, gsbfUint32, access),
    layoutValue: layout
  )

proc layout*(buffer: GpuPackedStorageBuffer): GpuPackedRecordLayout =
  buffer.layoutValue

proc storageBuffer*(buffer: GpuPackedStorageBuffer): GpuShaderStorageBuffer =
  buffer.storage

proc requireField(
    buffer: GpuPackedStorageBuffer;
    name: string
): GpuPackedRecordField =
  if buffer.builder.isNil:
    raise newException(GpuShaderBuildError, "packed GPU buffer is invalid")
  for field in buffer.layoutValue.fields:
    if field.name == name:
      return field
  raise newException(GpuShaderBuildError, "packed GPU field does not exist")

proc packedWordIndex(
    buffer: GpuPackedStorageBuffer;
    recordIndex: GpuShaderExpression;
    wordOffset: uint32
): GpuShaderExpression =
  let builder = buffer.builder
  if recordIndex.valueType != gsvtUint:
    raise newException(GpuShaderBuildError, "packed GPU record index must be uint")
  let base = builder.binary(
    gsbMultiply,
    recordIndex,
    builder.unsignedInteger(buffer.layoutValue.wordStride)
  )
  builder.binary(gsbAdd, base, builder.unsignedInteger(wordOffset))

proc decodePackedWord(
    builder: GpuShaderBuilder;
    valueType: GpuShaderValueType;
    word: GpuShaderExpression
): GpuShaderExpression =
  case valueType
  of gsvtFloat:
    builder.reinterpretValue(gsvtFloat, word)
  of gsvtUint:
    word
  else:
    raise newException(GpuShaderBuildError, "packed GPU scalar type is invalid")

proc encodePackedWord(
    builder: GpuShaderBuilder;
    value: GpuShaderExpression
): GpuShaderExpression =
  case value.valueType
  of gsvtFloat:
    builder.reinterpretValue(gsvtUint, value)
  of gsvtUint:
    value
  else:
    raise newException(GpuShaderBuildError, "packed GPU scalar type is invalid")

proc scalarType(valueType: GpuShaderValueType): GpuShaderValueType =
  case valueType
  of gsvtFloat, gsvtVec2, gsvtVec3, gsvtVec4: gsvtFloat
  of gsvtUint, gsvtUVec2, gsvtUVec3, gsvtUVec4: gsvtUint
  else:
    raise newException(GpuShaderBuildError, "packed GPU field type is invalid")

proc loadPackedField*(
    buffer: GpuPackedStorageBuffer;
    recordIndex: GpuShaderExpression;
    name: string
): GpuShaderExpression =
  let field = buffer.requireField(name)
  let builder = buffer.builder
  let scalar = field.valueType.scalarType()
  var components = newSeqOfCap[GpuShaderExpression](int(field.wordCount))
  for component in 0'u32 ..< field.wordCount:
    let wordIndex = buffer.packedWordIndex(
      recordIndex,
      field.wordOffset + component
    )
    let word = builder.loadStorage(buffer.storage, wordIndex)
    components.add builder.decodePackedWord(scalar, word)
  if components.len == 1:
    components[0]
  else:
    builder.construct(field.valueType, components)

proc storePackedField*(
    buffer: GpuPackedStorageBuffer;
    recordIndex: GpuShaderExpression;
    name: string;
    value: GpuShaderExpression
) =
  let field = buffer.requireField(name)
  let builder = buffer.builder
  if value.valueType != field.valueType:
    raise newException(GpuShaderBuildError, "packed GPU field value type does not match")
  const components = "xyzw"
  for component in 0'u32 ..< field.wordCount:
    let scalar = if field.wordCount == 1:
      value
    else:
      builder.swizzle(value, $components[int(component)])
    let word = builder.encodePackedWord(scalar)
    let wordIndex = buffer.packedWordIndex(
      recordIndex,
      field.wordOffset + component
    )
    builder.storeStorage(buffer.storage, wordIndex, word)
