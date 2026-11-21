## A packaged fragment shader that samples and replaces a premultiplied layer.
import std/[options, strutils]
import ../core/custom_paint_parameter
import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder, gpu_shader_package]

type
  GpuLayerShaderInput* = object
    ## An application-owned texture retained read-only by the material.
    slot*: uint8
    texture*: GpuResourceHandle

  GpuLayerShaderInputBinding = object
    slot: uint8
    texture, sampler, uvUniform: GpuResourceHandle
    rowsBottomUp: bool

  GpuLayerShaderParameter = object
    defaultValue: CustomPaintParameter
    uniform: GpuResourceHandle

  GpuLayerShaderMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader, pipeline, vertexBuffer: GpuResourceHandle
    orientationUniform, sourceUvUniform, sampler: GpuResourceHandle
    parameters: seq[GpuLayerShaderParameter]
    inputs: seq[GpuLayerShaderInputBinding]

const layerTargetOrientationUniform = "u_cbssComposite"

proc gpuLayerShaderVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc belongsTo*(
    material: GpuLayerShaderMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isNil and not host.isNil and material.host == host and
    material.namespace == namespace

proc release*(material: GpuLayerShaderMaterial) =
  if material.isNil or material.host.isNil:
    return
  let host = material.host
  for parameter in material.parameters:
    if host.isGpuResourceLive(parameter.uniform):
      discard host.releaseGpuResource(parameter.uniform)
  for input in material.inputs:
    for handle in [input.uvUniform, input.sampler]:
      if host.isGpuResourceLive(handle):
        discard host.releaseGpuResource(handle)
    discard host.releaseGpuResourceFromPresentation(input.texture)
  for handle in [material.sampler, material.sourceUvUniform, material.orientationUniform,
      material.vertexBuffer, material.pipeline, material.fragmentShader, material.vertexShader]:
    if host.isGpuResourceLive(handle):
      discard host.releaseGpuResource(handle)
  material.host = nil

proc pack(parameter: CustomPaintParameter; value: var array[4, float32]): bool =
  value = default(array[4, float32])
  case parameter.kind
  of cppkFloat:
    value[0] = parameter.floatValue
  of cppkInteger:
    # Every integer in the supported range is exactly representable as float32.
    if parameter.integerValue notin -16_777_216'i64 .. 16_777_216'i64:
      return false
    value[0] = parameter.integerValue.float32
  of cppkBoolean:
    value[0] = ord(parameter.booleanValue).float32
  of cppkVec2:
    value[0] = parameter.vec2Value[0]
    value[1] = parameter.vec2Value[1]
  of cppkVec4:
    value = parameter.vec4Value
  of cppkColor:
    let color = parameter.colorValue
    value = [color.r, color.g, color.b, color.a]
  true

proc hasVec4Uniform(layout: GpuShaderBindingLayout; name: string): bool =
  GpuShaderUniformLayout(nameId: name.gpuBindingNameId(),
    uniformType: gutVec4, arrayLength: 1) in layout.uniforms

proc validateLayerShaderUniforms(
    layout: GpuShaderBindingLayout;
    defaults: CustomPaintParameters;
    suppliedSlots: set[GpuLayerShaderInputSlot]
) =
  # The vertex orientation uniform occupies one additional binding.
  let expectedUniforms = defaults.len + card(suppliedSlots) + 1
  if not layout.known or layout.storageBuffers.len != 0 or layout.storageImages.len != 0 or
      layout.uniforms.len != expectedUniforms or expectedUniforms >= maxGpuUniformBindings:
    raise newException(ValueError, "GPU layer shader requires a source sampler and matching vec4 parameters")
  if not layout.hasVec4Uniform(gpuLayerSourceUvUniform):
    raise newException(ValueError, "GPU layer shader must sample the layer")
  # Each fixed sampler slot has a matching UV uniform in the package.
  for slot in low(GpuLayerShaderInputSlot) .. high(GpuLayerShaderInputSlot):
    if layout.hasVec4Uniform(gpuLayerInputUvUniform(slot)) != (slot in suppliedSlots):
      raise newException(ValueError, "GPU layer shader inputs do not match the packaged slots")
  for parameter in defaults:
    let name = parameter.name
    if not name.startsWith("u_") or name == layerTargetOrientationUniform or
        name == gpuLayerSourceUvUniform or name.startsWith(gpuLayerInputUvPrefix):
      raise newException(ValueError, "invalid GPU layer shader parameter name")
    if not layout.hasVec4Uniform(name):
      raise newException(ValueError, "GPU layer shader parameter has no matching uniform")
    var value: array[4, float32]
    if not parameter.pack(value):
      raise newException(ValueError, "GPU layer shader default integer is not exactly representable")

proc newGpuLayerShaderMaterial*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    vertex, fragment: GpuShaderPackage;
    target: GpuShaderBinaryTarget;
    defaults: CustomPaintParameters = nil;
    inputs: openArray[GpuLayerShaderInput] = []
): GpuLayerShaderMaterial =
  ## The fragment uses sampleLayer() and returns premultiplied RGBA.
  ## Extra inputs stay retained and read-only until release().
  if not host.isReady():
    raise newException(ValueError, "GPU layer shader material requires a ready host")
  let vertexArtifact = vertex.artifactFor(target)
  let fragmentArtifact = fragment.artifactFor(target)
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuLayerShaderVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment:
    raise newException(ValueError, "GPU layer shader packages do not match the layer pipeline")
  var suppliedSlots: set[GpuLayerShaderInputSlot]
  var inputOrientation: array[GpuLayerShaderInputSlot, bool]
  for input in inputs:
    if input.slot notin 1'u8 .. uint8(MaxGpuLayerShaderInputs):
      raise newException(ValueError, "GPU layer shader input slot is out of range")
    let slot = GpuLayerShaderInputSlot(input.slot)
    if slot in suppliedSlots:
      raise newException(ValueError, "duplicate GPU layer shader input slot")
    if input.texture.namespace != namespace or
        input.texture.kind notin {grkTexture, grkRenderTarget} or
        not host.isGpuResourceLive(input.texture):
      raise newException(ValueError, "GPU layer shader input must be live in the material namespace")
    let info = host.gpuPresentableResourceInfo(input.texture)
    if gtuSampled notin info.usage or info.format notin {gtfRgba8, gtfBgra8}:
      raise newException(ValueError, "GPU layer shader input requires sampled RGBA8 or BGRA8")
    suppliedSlots.incl slot
    inputOrientation[slot] = info.rowsBottomUp
  fragmentArtifact.bindingLayout.validateLayerShaderUniforms(defaults, suppliedSlots)

  result = GpuLayerShaderMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3, componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2, componentType: gvctFloat)
  ]
  let vertices = [
    [-1'f32, -1, 0, 0, 1], [-1'f32, 1, 0, 0, 0],
    [1'f32, -1, 0, 1, 1], [1'f32, 1, 0, 1, 0]
  ]
  var vertexBytes = newSeq[byte](sizeof(vertices))
  copyMem(addr vertexBytes[0], unsafeAddr vertices[0], vertexBytes.len)
  proc createVec4(name: string): GpuResourceHandle =
    host.createGpuUniform(namespace, GpuUniformDescriptor(
      name: name, uniformType: gutVec4, arrayLength: 1))
  proc createSampler(name: string): GpuResourceHandle =
    host.createGpuSampler(namespace, GpuSamplerDescriptor(
      name: name, addressU: gsamClamp, addressV: gsamClamp,
      minFilter: gsfLinear, magFilter: gsfLinear, mipFilter: gsfNearest))
  try:
    result.vertexShader = host.createGpuShader(namespace, vertexArtifact)
    result.fragmentShader = host.createGpuShader(namespace, fragmentArtifact)
    result.pipeline = host.createGpuGraphicsPipeline(namespace, GpuGraphicsPipelineDescriptor(
      vertexShader: result.vertexShader, fragmentShader: result.fragmentShader,
      vertexLayout: layout, colorFormat: gtfRgba8, topology: gptTriangleStrip,
      cullMode: gcmNone, blend: opaqueGpuBlendState(), label: "UI layer shader"))
    result.vertexBuffer = host.createGpuBuffer(namespace, GpuBufferDescriptor(
      byteSize: uint64(vertexBytes.len), role: gbrVertex, access: gbaStatic,
      vertexLayout: layout), move(vertexBytes))
    result.orientationUniform = createVec4(layerTargetOrientationUniform)
    result.sourceUvUniform = createVec4(gpuLayerSourceUvUniform)
    result.sampler = createSampler(gpuLayerSourceSampler)
    for parameter in defaults:
      result.parameters.add GpuLayerShaderParameter(
        defaultValue: parameter, uniform: createVec4(parameter.name))
    for input in inputs:
      let slot = GpuLayerShaderInputSlot(input.slot)
      result.inputs.add GpuLayerShaderInputBinding(slot: input.slot,
        rowsBottomUp: inputOrientation[slot])
      result.inputs[^1].sampler = createSampler(gpuLayerInputSampler(slot))
      result.inputs[^1].uvUniform = createVec4(gpuLayerInputUvUniform(slot))
      host.retainGpuResourceForPresentation(input.texture)
      result.inputs[^1].texture = input.texture
  except CatchableError:
    result.release()
    raise

proc uvRect(rowsBottomUp: bool): seq[float32] =
  if rowsBottomUp: @[0'f32, 1, 1, 0]
  else: @[0'f32, 0, 1, 1]

proc submit*(
    material: GpuLayerShaderMaterial;
    source, destination: GpuResourceHandle;
    parameters: CustomPaintParameters
): bool =
  ## Return false for unsupported parameter values before submitting a draw.
  if material.isNil or not material.host.isReady() or
      parameters.len > material.parameters.len:
    return false
  let host = material.host
  if source == destination or source.namespace != material.namespace or
      destination.namespace != material.namespace:
    return false
  let sourceInfo = host.gpuPresentableResourceInfo(source)
  let targetInfo = host.gpuPresentableResourceInfo(destination)
  if gtuSampled notin sourceInfo.usage or sourceInfo.format != gtfRgba8 or
      targetInfo.kind != grkRenderTarget or gtuRenderTarget notin targetInfo.usage or
      targetInfo.format != gtfRgba8 or sourceInfo.width != targetInfo.width or
      sourceInfo.height != targetInfo.height:
    return false

  let flipTarget = targetInfo.rowsBottomUp != host.backendInfo().originBottomLeft
  var uniforms = @[
    GpuUniformBinding(uniform: material.orientationUniform,
      values: @[0'f32, 0, ord(flipTarget).float32, 0]),
    GpuUniformBinding(uniform: material.sourceUvUniform,
      values: uvRect(sourceInfo.rowsBottomUp))
  ]
  var matched = 0
  for binding in material.parameters:
    let supplied = parameters.findCustomPaintParameter(binding.defaultValue.name)
    let parameter = supplied.get(binding.defaultValue)
    var value: array[4, float32]
    if parameter.kind != binding.defaultValue.kind or not parameter.pack(value):
      return false
    matched += ord(supplied.isSome)
    uniforms.add GpuUniformBinding(uniform: binding.uniform, values: @value)
  if matched != parameters.len:
    return false

  var textures = @[GpuTextureBinding(stage: 0, sampler: material.sampler, texture: source)]
  for input in material.inputs:
    if input.texture == destination or not host.isGpuResourceLive(input.texture):
      return false
    uniforms.add GpuUniformBinding(uniform: input.uvUniform, values: uvRect(input.rowsBottomUp))
    textures.add GpuTextureBinding(stage: input.slot, sampler: input.sampler,
      texture: input.texture)

  host.submitGpuDraw(material.namespace, GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: targetInfo.width, height: targetInfo.height),
    renderTarget: destination, clearColorEnabled: true),
    GpuDrawCommand(pipeline: material.pipeline, vertexBuffer: material.vertexBuffer,
      vertexCount: 4, bindings: GpuBindingSet(uniforms: move(uniforms),
        textures: move(textures))))
  true
