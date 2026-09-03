import std/algorithm

import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder]

const
  gpuShaderPackageVersion* = 1'u16
  maxGpuShaderPackageVariants* = 16
  maxGpuShaderBinaryBytes* = 16 * 1024 * 1024
  maxGpuShaderPackageBytes* = 128 * 1024 * 1024
  gpuShaderPackageMagic = "CBSSGSPK"

type
  GpuShaderPackageError* = object of CatchableError

  GpuShaderBinaryTarget* = enum
    gsbtDirect3D11,
    gsbtDirect3D12,
    gsbtMetal,
    gsbtOpenGL,
    gsbtOpenGLES,
    gsbtVulkan,
    gsbtWebGPU,
    gsbtAgc,
    gsbtGnm,
    gsbtNvn

  GpuShaderBinaryVariant* = object
    target*: GpuShaderBinaryTarget
    bytecode*: seq[byte]
    bytecodeHash*: uint64

  GpuShaderPackage* = object
    descriptor*: GpuShaderDescriptor
    sourceHash*: uint64
    variants*: seq[GpuShaderBinaryVariant]

proc hashGpuShaderBytes*(bytes: openArray[byte]): uint64 =
  result = 14_695_981_039_346_656_037'u64
  for value in bytes:
    result = (result xor uint64(value)) * 1_099_511_628_211'u64

proc gpuShaderPackage*(source: GpuShaderSource): GpuShaderPackage =
  if source.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuShaderPackageError, "GPU shader label is too long")
  GpuShaderPackage(
    descriptor: GpuShaderDescriptor(stage: source.stage, label: source.label),
    sourceHash: source.gpuShaderSourceHash()
  )

proc addVariant*(
    package: var GpuShaderPackage;
    target: GpuShaderBinaryTarget;
    artifact: sink GpuShaderArtifact
) =
  if artifact.descriptor != package.descriptor:
    raise newException(GpuShaderPackageError, "GPU shader descriptors do not match")
  if artifact.sourceHash != package.sourceHash:
    raise newException(GpuShaderPackageError, "GPU shader source hashes do not match")
  if artifact.bytecode.len == 0:
    raise newException(GpuShaderPackageError, "GPU shader bytecode cannot be empty")
  if artifact.bytecode.len > maxGpuShaderBinaryBytes:
    raise newException(GpuShaderPackageError, "GPU shader bytecode limit exceeded")
  if package.variants.len >= maxGpuShaderPackageVariants:
    raise newException(GpuShaderPackageError, "GPU shader variant limit exceeded")
  for variant in package.variants:
    if variant.target == target:
      raise newException(GpuShaderPackageError, "duplicate GPU shader target")
  package.variants.add GpuShaderBinaryVariant(
    target: target,
    bytecodeHash: artifact.bytecode.hashGpuShaderBytes(),
    bytecode: artifact.bytecode
  )

proc artifactFor*(
    package: GpuShaderPackage;
    target: GpuShaderBinaryTarget
): GpuShaderArtifact =
  for variant in package.variants:
    if variant.target == target:
      if variant.bytecode.len == 0 or
          variant.bytecode.len > maxGpuShaderBinaryBytes or
          variant.bytecode.hashGpuShaderBytes() != variant.bytecodeHash:
        raise newException(GpuShaderPackageError, "GPU shader variant is corrupted")
      return GpuShaderArtifact(
        descriptor: package.descriptor,
        bytecode: variant.bytecode,
        sourceHash: package.sourceHash
      )
  raise newException(GpuShaderPackageError, "GPU shader target is not packaged")

proc appendU16(bytes: var seq[byte]; value: uint16) =
  bytes.add byte(value and 0xff'u16)
  bytes.add byte(value shr 8)

proc appendU32(bytes: var seq[byte]; value: uint32) =
  for shift in countup(0, 24, 8):
    bytes.add byte((value shr shift) and 0xff'u32)

proc appendU64(bytes: var seq[byte]; value: uint64) =
  for shift in countup(0, 56, 8):
    bytes.add byte((value shr shift) and 0xff'u64)

proc readU8(bytes: openArray[byte]; offset: var int): uint8 =
  if offset >= bytes.len:
    raise newException(GpuShaderPackageError, "truncated GPU shader package")
  result = bytes[offset]
  inc offset

proc readU16(bytes: openArray[byte]; offset: var int): uint16 =
  result = uint16(bytes.readU8(offset))
  result = result or (uint16(bytes.readU8(offset)) shl 8)

proc readU32(bytes: openArray[byte]; offset: var int): uint32 =
  for shift in countup(0, 24, 8):
    result = result or (uint32(bytes.readU8(offset)) shl shift)

proc readU64(bytes: openArray[byte]; offset: var int): uint64 =
  for shift in countup(0, 56, 8):
    result = result or (uint64(bytes.readU8(offset)) shl shift)

proc encodeGpuShaderPackage*(package: GpuShaderPackage): seq[byte] =
  if package.descriptor.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuShaderPackageError, "GPU shader label is too long")
  if package.variants.len == 0 or
      package.variants.len > maxGpuShaderPackageVariants:
    raise newException(GpuShaderPackageError, "GPU shader package variant count is invalid")

  var variants = package.variants
  variants.sort(proc(left, right: GpuShaderBinaryVariant): int =
    cmp(ord(left.target), ord(right.target))
  )
  var previousTarget = -1
  var encodedSize = gpuShaderPackageMagic.len + 16 + package.descriptor.label.len
  for variant in variants:
    if ord(variant.target) == previousTarget:
      raise newException(GpuShaderPackageError, "duplicate GPU shader target")
    previousTarget = ord(variant.target)
    if variant.bytecode.len == 0 or variant.bytecode.len > maxGpuShaderBinaryBytes:
      raise newException(GpuShaderPackageError, "GPU shader bytecode size is invalid")
    if variant.bytecode.hashGpuShaderBytes() != variant.bytecodeHash:
      raise newException(GpuShaderPackageError, "GPU shader variant is corrupted")
    if encodedSize > maxGpuShaderPackageBytes - 16 - variant.bytecode.len:
      raise newException(GpuShaderPackageError, "GPU shader package limit exceeded")
    encodedSize += 16 + variant.bytecode.len

  result = newSeqOfCap[byte](encodedSize)
  for value in gpuShaderPackageMagic:
    result.add byte(value)
  result.appendU16(gpuShaderPackageVersion)
  result.add byte(ord(package.descriptor.stage))
  result.add 0'u8
  result.appendU16(uint16(package.descriptor.label.len))
  result.appendU16(uint16(variants.len))
  result.appendU64(package.sourceHash)
  for value in package.descriptor.label:
    result.add byte(value)
  for variant in variants:
    result.add byte(ord(variant.target))
    result.add [0'u8, 0'u8, 0'u8]
    result.appendU32(uint32(variant.bytecode.len))
    result.appendU64(variant.bytecodeHash)
    result.add variant.bytecode

proc encodeGpuShaderPackageData*(package: GpuShaderPackage): string =
  let encoded = package.encodeGpuShaderPackage()
  result = newString(encoded.len)
  for index, value in encoded:
    result[index] = char(value)

proc decodeGpuShaderPackage*(bytes: openArray[byte]): GpuShaderPackage =
  if bytes.len > maxGpuShaderPackageBytes:
    raise newException(GpuShaderPackageError, "GPU shader package limit exceeded")
  if bytes.len < gpuShaderPackageMagic.len + 16:
    raise newException(GpuShaderPackageError, "truncated GPU shader package")
  var offset = 0
  for expected in gpuShaderPackageMagic:
    if bytes.readU8(offset) != uint8(expected):
      raise newException(GpuShaderPackageError, "invalid GPU shader package magic")
  if bytes.readU16(offset) != gpuShaderPackageVersion:
    raise newException(GpuShaderPackageError, "unsupported GPU shader package version")
  let rawStage = bytes.readU8(offset)
  if bytes.readU8(offset) != 0:
    raise newException(GpuShaderPackageError, "invalid GPU shader package header")
  if rawStage > uint8(ord(high(GpuShaderStage))):
    raise newException(GpuShaderPackageError, "invalid GPU shader stage")
  let labelLength = int(bytes.readU16(offset))
  let variantCount = int(bytes.readU16(offset))
  let sourceHash = bytes.readU64(offset)
  if labelLength > maxGpuResourceLabelBytes or variantCount == 0 or
      variantCount > maxGpuShaderPackageVariants or
      labelLength > bytes.len - offset:
    raise newException(GpuShaderPackageError, "invalid GPU shader package header")

  var label = newString(labelLength)
  for index in 0 ..< labelLength:
    label[index] = char(bytes.readU8(offset))
  result = GpuShaderPackage(
    descriptor: GpuShaderDescriptor(stage: GpuShaderStage(rawStage), label: label),
    sourceHash: sourceHash
  )

  var seenTargets: set[GpuShaderBinaryTarget]
  for _ in 0 ..< variantCount:
    let rawTarget = bytes.readU8(offset)
    for _ in 0 ..< 3:
      if bytes.readU8(offset) != 0:
        raise newException(GpuShaderPackageError, "invalid GPU shader variant header")
    let rawBytecodeLength = bytes.readU32(offset)
    let expectedHash = bytes.readU64(offset)
    if rawTarget > uint8(ord(high(GpuShaderBinaryTarget))):
      raise newException(GpuShaderPackageError, "invalid GPU shader target")
    let target = GpuShaderBinaryTarget(rawTarget)
    if target in seenTargets:
      raise newException(GpuShaderPackageError, "duplicate GPU shader target")
    seenTargets.incl(target)
    if rawBytecodeLength == 0 or
        rawBytecodeLength > uint32(maxGpuShaderBinaryBytes):
      raise newException(GpuShaderPackageError, "invalid GPU shader bytecode size")
    let bytecodeLength = int(rawBytecodeLength)
    if bytecodeLength > bytes.len - offset:
      raise newException(GpuShaderPackageError, "invalid GPU shader bytecode size")
    var bytecode = newSeq[byte](bytecodeLength)
    for index in 0 ..< bytecodeLength:
      bytecode[index] = bytes.readU8(offset)
    if bytecode.hashGpuShaderBytes() != expectedHash:
      raise newException(GpuShaderPackageError, "GPU shader bytecode checksum failed")
    result.variants.add GpuShaderBinaryVariant(
      target: target,
      bytecode: bytecode,
      bytecodeHash: expectedHash
    )
  if offset != bytes.len:
    raise newException(GpuShaderPackageError, "GPU shader package has trailing data")

proc decodeGpuShaderPackage*(data: string): GpuShaderPackage =
  var bytes = newSeq[byte](data.len)
  for index, value in data:
    bytes[index] = byte(value)
  bytes.decodeGpuShaderPackage()

proc createGpuShader*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    package: GpuShaderPackage;
    target: GpuShaderBinaryTarget
): GpuResourceHandle =
  host.createGpuShader(namespace, package.artifactFor(target))
