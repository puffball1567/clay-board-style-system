## Bounded separable GPU dilation and erosion of premultiplied RGBA.
import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder]

const MaxGpuMorphologyRadius* = 8

type
  GpuMorphologyMode* = enum
    gmmDilate,
    gmmErode

  GpuMorphologyVertex = object
    x, y, z: float32
    u, v: float32

  GpuMorphologyMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    paramsUniform, uvUniform, sampler: GpuResourceHandle

proc gpuMorphologyVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuMorphologyFragmentSource*(): GpuShaderSource =
  var source = """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssMorphSource, 0);
uniform vec4 u_cbssMorphParams;
uniform vec4 u_cbssMorphUv;
vec4 cbssMorphSample(vec2 uv)
{
  vec4 sampled = texture2D(s_cbssMorphSource, uv);
  if (u_cbssMorphParams.z > 1.5) {
    return vec4(sampled.rgb, 1.0);
  }
  if (u_cbssMorphParams.z < 0.5) sampled.rgb *= sampled.a;
  return sampled;
}
vec4 cbssMorphCombine(vec4 a, vec4 b)
{
  if (u_cbssMorphParams.w < 0.0) return min(a, b);
  return max(a, b);
}
void main()
{
  vec2 uv = mix(u_cbssMorphUv.xy, u_cbssMorphUv.zw, v_texcoord0);
  vec2 stepUv = u_cbssMorphParams.xy;
  float radius = abs(u_cbssMorphParams.w);
  vec4 filtered = cbssMorphSample(uv);
"""
  for offset in 1 .. MaxGpuMorphologyRadius:
    source.add "  if (radius >= " & $offset & ".0) {\n"
    source.add "    filtered = cbssMorphCombine(filtered, " &
      "cbssMorphSample(uv + stepUv * " & $offset & ".0));\n"
    source.add "    filtered = cbssMorphCombine(filtered, " &
      "cbssMorphSample(uv - stepUv * " & $offset & ".0));\n"
    source.add "  }\n"
  source.add "  gl_FragColor = filtered;\n}\n"
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-morphology-fragment",
    source: source,
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuMorphologyMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuMorphologyMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuMorphologyMaterial) =
  ## Release after the final submitted frame while the host is still open.
  if material.isClosed:
    return
  for handle in [material.sampler, material.uvUniform,
      material.paramsUniform, material.vertexBuffer, material.pipeline,
      material.fragmentShader, material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuMorphologyMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuMorphologyMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError,
      "GPU morphology material requires a ready host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuMorphologyVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuMorphologyFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError,
      "GPU morphology shader artifacts do not match the built-in shaders")
  result = GpuMorphologyMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuMorphologyVertex(x: -1, y: -1, u: 0, v: 1),
    GpuMorphologyVertex(x: -1, y: 1, u: 0, v: 0),
    GpuMorphologyVertex(x: 1, y: -1, u: 1, v: 1),
    GpuMorphologyVertex(x: 1, y: 1, u: 1, v: 0)
  ]
  var vertexBytes = newSeq[byte](sizeof(vertices))
  copyMem(addr vertexBytes[0], unsafeAddr vertices[0], vertexBytes.len)
  try:
    result.vertexShader = host.createGpuShader(namespace, vertexArtifact)
    result.fragmentShader = host.createGpuShader(namespace, fragmentArtifact)
    result.pipeline = host.createGpuGraphicsPipeline(namespace,
      GpuGraphicsPipelineDescriptor(
        vertexShader: result.vertexShader,
        fragmentShader: result.fragmentShader,
        vertexLayout: layout,
        colorFormat: gtfRgba8,
        topology: gptTriangleStrip,
        cullMode: gcmNone,
        blend: opaqueGpuBlendState(),
        label: "gpu-morphology-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-morphology-quad"), vertexBytes)
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssMorphParams",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-morphology-params"))
    result.uvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssMorphUv",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-morphology-uv"))
    result.sampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssMorphSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-morphology-sampler"))
  except CatchableError:
    result.release()
    raise

proc submitPass(
    material: GpuMorphologyMaterial;
    source, target: GpuResourceHandle;
    sourceInfo: GpuPresentableResourceInfo;
    stepX, stepY: float32;
    alphaMode: GpuAlphaMode;
    mode: GpuMorphologyMode;
    radius: int
) =
  let uv =
    if sourceInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
  let signedRadius =
    if mode == gmmErode: -float32(radius)
    else: float32(radius)
  material.host.submitGpuDraw(material.namespace,
    GpuGraphicsPassDescriptor(
      viewport: GpuViewport(width: sourceInfo.width, height: sourceInfo.height),
      renderTarget: target,
      clearColorEnabled: true,
      clearColor: GpuClearColor()),
    GpuDrawCommand(
      pipeline: material.pipeline,
      vertexBuffer: material.vertexBuffer,
      vertexCount: 4,
      bindings: GpuBindingSet(
        uniforms: @[
          GpuUniformBinding(uniform: material.paramsUniform,
            values: @[stepX, stepY, float32(ord(alphaMode)), signedRadius]),
          GpuUniformBinding(uniform: material.uvUniform, values: uv)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.sampler,
            texture: source)
        ]
      )
    ))

proc submit*(
    material: GpuMorphologyMaterial;
    source, scratch, destination: GpuResourceHandle;
    sourceAlphaMode = gcamStraight;
    mode = gmmDilate;
    radius = 1
): bool =
  ## Two passes apply a square radius 0..8 kernel to premultiplied RGBA.
  if material.isClosed:
    raise newException(ValueError, "GPU morphology material is closed")
  if radius < 0 or radius > MaxGpuMorphologyRadius:
    raise newException(ValueError,
      "GPU morphology radius must be between 0 and 8")
  if source == scratch or source == destination or scratch == destination or
      source.namespace != material.namespace or
      scratch.namespace != material.namespace or
      destination.namespace != material.namespace:
    raise newException(ValueError,
      "GPU morphology resources must be distinct and in one namespace")
  let host = material.host
  let sourceInfo = host.gpuPresentableResourceInfo(source)
  let scratchInfo = host.gpuPresentableResourceInfo(scratch)
  let targetInfo = host.gpuPresentableResourceInfo(destination)
  if sourceInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin sourceInfo.usage or
      sourceInfo.format notin {gtfRgba8, gtfBgra8} or
      scratchInfo.kind != grkRenderTarget or
      gtuSampled notin scratchInfo.usage or
      gtuRenderTarget notin scratchInfo.usage or
      scratchInfo.format != gtfRgba8 or
      targetInfo.kind != grkRenderTarget or
      gtuRenderTarget notin targetInfo.usage or
      targetInfo.format != gtfRgba8 or
      sourceInfo.width != scratchInfo.width or
      sourceInfo.height != scratchInfo.height or
      sourceInfo.width != targetInfo.width or
      sourceInfo.height != targetInfo.height:
    raise newException(ValueError,
      "GPU morphology source, scratch, and target are incompatible")
  for target in [scratch, destination]:
    if host.isGpuResourcePresentationRetained(target):
      raise newException(GpuHostError,
        "GPU morphology cannot overwrite a presentation-retained target")
  host.validateGpuFrameWork(material.namespace, workUnits = 2)
  host.validateGpuViewCapacity(2)
  material.submitPass(source, scratch, sourceInfo,
    1'f32 / float32(sourceInfo.width), 0'f32, sourceAlphaMode,
    mode, radius)
  material.submitPass(scratch, destination, scratchInfo,
    0'f32, 1'f32 / float32(sourceInfo.height), gcamPremultiplied,
    mode, radius)
  true
