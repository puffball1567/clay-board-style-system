## Fixed five-tap separable Gaussian blur for same-host GPU surfaces.
## The two-pass result is premultiplied RGBA8; import explicitly.
import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder]

type
  GpuBlurVertex = object
    x, y, z: float32
    u, v: float32

  GpuGaussianBlurMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    paramsUniform, uvUniform, sampler: GpuResourceHandle

proc gpuGaussianBlurVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuGaussianBlurFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-gaussian-blur-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssBlurSource, 0);
uniform vec4 u_cbssBlurParams;
uniform vec4 u_cbssUvRect;
vec4 premultipliedSample(vec2 uv)
{
  vec4 sampled = texture2D(s_cbssBlurSource, uv);
  if (u_cbssBlurParams.z > 1.5) {
    return vec4(sampled.rgb, 1.0);
  }
  if (u_cbssBlurParams.z < 0.5) {
    sampled.rgb *= sampled.a;
  }
  return sampled;
}
void main()
{
  vec2 uv = mix(u_cbssUvRect.xy, u_cbssUvRect.zw, v_texcoord0);
  vec2 stepUv = u_cbssBlurParams.xy;
  vec4 blurred = premultipliedSample(uv) * 6.0;
  blurred += premultipliedSample(uv + stepUv) * 4.0;
  blurred += premultipliedSample(uv - stepUv) * 4.0;
  blurred += premultipliedSample(uv + stepUv * 2.0);
  blurred += premultipliedSample(uv - stepUv * 2.0);
  gl_FragColor = blurred * (1.0 / 16.0);
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuGaussianBlurMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuGaussianBlurMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuGaussianBlurMaterial) =
  ## Release after the last submitted frame while the host is open.
  if material.isClosed:
    return
  for handle in [material.sampler, material.uvUniform, material.paramsUniform,
      material.vertexBuffer, material.pipeline, material.fragmentShader,
      material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuGaussianBlurMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuGaussianBlurMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError, "GPU blur material requires a ready host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuGaussianBlurVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuGaussianBlurFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError, "GPU blur shader artifacts do not match the built-in shaders")
  result = GpuGaussianBlurMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuBlurVertex(x: -1, y: -1, u: 0, v: 1),
    GpuBlurVertex(x: -1, y: 1, u: 0, v: 0),
    GpuBlurVertex(x: 1, y: -1, u: 1, v: 1),
    GpuBlurVertex(x: 1, y: 1, u: 1, v: 0)
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
        label: "gpu-gaussian-blur-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-gaussian-blur-quad"), vertexBytes)
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssBlurParams", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-gaussian-blur-params"))
    result.uvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssUvRect", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-gaussian-blur-uv"))
    result.sampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssBlurSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-gaussian-blur-sampler"))
  except CatchableError:
    result.release()
    raise

proc submitPass(
    material: GpuGaussianBlurMaterial;
    source, target: GpuResourceHandle;
    sourceInfo: GpuPresentableResourceInfo;
    stepX, stepY: float32;
    alphaMode: GpuAlphaMode
) =
  let uv =
    if sourceInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
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
            values: @[stepX, stepY, float32(ord(alphaMode)), 0'f32]),
          GpuUniformBinding(uniform: material.uvUniform, values: uv)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.sampler,
            texture: source)
        ]
      )
    ))

proc submit*(
    material: GpuGaussianBlurMaterial;
    source, scratch, destination: GpuResourceHandle;
    sourceAlphaMode = gcamStraight
): bool =
  ## A fixed radius-two Gaussian blur, horizontal then vertical. Edge pixels
  ## are clamped. All resources must have equal dimensions in one namespace.
  if material.isClosed:
    raise newException(ValueError, "GPU blur material is closed")
  if source == scratch or source == destination or scratch == destination or
      source.namespace != material.namespace or
      scratch.namespace != material.namespace or
      destination.namespace != material.namespace:
    raise newException(ValueError, "GPU blur resources must be distinct and in one namespace")
  let sourceInfo = material.host.gpuPresentableResourceInfo(source)
  let scratchInfo = material.host.gpuPresentableResourceInfo(scratch)
  let targetInfo = material.host.gpuPresentableResourceInfo(destination)
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
    raise newException(ValueError, "GPU blur source, scratch, and target are incompatible")
  material.submitPass(source, scratch, sourceInfo,
    1'f32 / float32(sourceInfo.width), 0'f32, sourceAlphaMode)
  material.submitPass(scratch, destination, scratchInfo,
    0'f32, 1'f32 / float32(sourceInfo.height), gcamPremultiplied)
  true
