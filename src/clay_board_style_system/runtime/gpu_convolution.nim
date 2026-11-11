## Bounded 3x3 GPU convolution over premultiplied RGBA8 surfaces.
import std/math

import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder]

const MaxGpuConvolutionWeight* = 16'f32

type
  GpuConvolutionKernel* = object
    weights: array[9, float32]

  GpuConvolutionVertex = object
    x, y, z: float32
    u, v: float32

  GpuConvolutionMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    rowsUniform, paramsUniform, uvUniform, sampler: GpuResourceHandle

proc gpuConvolutionKernel*(weights: array[9, float32]): GpuConvolutionKernel =
  ## Row-major weights run left-to-right and top-to-bottom in image space.
  for weight in weights:
    if weight.classify in {fcNan, fcInf, fcNegInf} or
        abs(weight) > MaxGpuConvolutionWeight:
      raise newException(ValueError,
        "GPU convolution weights must be finite and within -16..16")
  GpuConvolutionKernel(weights: weights)

proc identityGpuConvolutionKernel*(): GpuConvolutionKernel =
  gpuConvolutionKernel([0'f32, 0, 0, 0, 1, 0, 0, 0, 0])

proc gpuConvolutionVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuConvolutionFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-convolution-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssConvolveSource, 0);
uniform vec4 u_cbssConvolveRows[3];
uniform vec4 u_cbssConvolveParams;
uniform vec4 u_cbssConvolveUv;
vec4 cbssConvolveSample(vec2 uv)
{
  vec4 sampled = texture2D(s_cbssConvolveSource, uv);
  if (u_cbssConvolveParams.z > 1.5) {
    sampled.a = 1.0;
  } else if (u_cbssConvolveParams.z < 0.5) {
    sampled.rgb *= sampled.a;
  }
  return sampled;
}
void main()
{
  vec2 uv = mix(u_cbssConvolveUv.xy, u_cbssConvolveUv.zw, v_texcoord0);
  vec2 stepUv = u_cbssConvolveParams.xy;
  vec4 center = cbssConvolveSample(uv);
  vec4 filtered =
    cbssConvolveSample(uv + stepUv * vec2(-1.0, -1.0)) * u_cbssConvolveRows[0].x +
    cbssConvolveSample(uv + stepUv * vec2( 0.0, -1.0)) * u_cbssConvolveRows[0].y +
    cbssConvolveSample(uv + stepUv * vec2( 1.0, -1.0)) * u_cbssConvolveRows[0].z +
    cbssConvolveSample(uv + stepUv * vec2(-1.0,  0.0)) * u_cbssConvolveRows[1].x +
    center * u_cbssConvolveRows[1].y +
    cbssConvolveSample(uv + stepUv * vec2( 1.0,  0.0)) * u_cbssConvolveRows[1].z +
    cbssConvolveSample(uv + stepUv * vec2(-1.0,  1.0)) * u_cbssConvolveRows[2].x +
    cbssConvolveSample(uv + stepUv * vec2( 0.0,  1.0)) * u_cbssConvolveRows[2].y +
    cbssConvolveSample(uv + stepUv * vec2( 1.0,  1.0)) * u_cbssConvolveRows[2].z;
  float alpha = u_cbssConvolveParams.w > 0.5 ? center.a :
    clamp(filtered.a, 0.0, 1.0);
  gl_FragColor = vec4(clamp(filtered.rgb, vec3(0.0), vec3(alpha)), alpha);
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuConvolutionMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuConvolutionMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuConvolutionMaterial) =
  ## Release after the final submitted frame while the host is still open.
  if material.isClosed:
    return
  for handle in [material.sampler, material.uvUniform,
      material.paramsUniform, material.rowsUniform, material.vertexBuffer,
      material.pipeline, material.fragmentShader, material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuConvolutionMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuConvolutionMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError,
      "GPU convolution material requires a ready host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuConvolutionVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuConvolutionFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError,
      "GPU convolution shader artifacts do not match the built-in shaders")
  result = GpuConvolutionMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuConvolutionVertex(x: -1, y: -1, u: 0, v: 1),
    GpuConvolutionVertex(x: -1, y: 1, u: 0, v: 0),
    GpuConvolutionVertex(x: 1, y: -1, u: 1, v: 1),
    GpuConvolutionVertex(x: 1, y: 1, u: 1, v: 0)
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
        label: "gpu-convolution-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-convolution-quad"), vertexBytes)
    result.rowsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssConvolveRows",
        uniformType: gutVec4, arrayLength: 3,
        label: "gpu-convolution-rows"))
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssConvolveParams",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-convolution-params"))
    result.uvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssConvolveUv",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-convolution-uv"))
    result.sampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssConvolveSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-convolution-sampler"))
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuConvolutionMaterial;
    source, destination: GpuResourceHandle;
    kernel: GpuConvolutionKernel;
    sourceAlphaMode = gcamStraight;
    preserveAlpha = true
): bool =
  ## Apply a clamped-edge 3x3 kernel and write premultiplied RGBA8.
  if material.isClosed:
    raise newException(ValueError, "GPU convolution material is closed")
  let host = material.host
  if not host.hasActiveGpuFrame():
    raise newException(GpuHostError, "GPU convolution requires an active frame")
  if source.namespace != material.namespace or
      destination.namespace != material.namespace or source == destination:
    raise newException(ValueError,
      "GPU convolution resources must be distinct and in one namespace")
  let sourceInfo = host.gpuPresentableResourceInfo(source)
  let targetInfo = host.gpuPresentableResourceInfo(destination)
  if sourceInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin sourceInfo.usage or
      sourceInfo.format notin {gtfRgba8, gtfBgra8} or
      targetInfo.kind != grkRenderTarget or
      gtuRenderTarget notin targetInfo.usage or
      targetInfo.format != gtfRgba8 or
      sourceInfo.width != targetInfo.width or
      sourceInfo.height != targetInfo.height:
    raise newException(ValueError,
      "GPU convolution source and target are incompatible")
  if host.isGpuResourcePresentationRetained(destination):
    raise newException(GpuHostError,
      "GPU convolution cannot overwrite a presentation-retained target")
  var rows = newSeq[float32](12)
  for row in 0 .. 2:
    for column in 0 .. 2:
      rows[row * 4 + column] = kernel.weights[row * 3 + column]
  let uv =
    if sourceInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0'f32, 1, 1]
  host.submitGpuDraw(material.namespace,
    GpuGraphicsPassDescriptor(
      viewport: GpuViewport(width: targetInfo.width, height: targetInfo.height),
      renderTarget: destination,
      clearColorEnabled: true,
      clearColor: GpuClearColor()),
    GpuDrawCommand(
      pipeline: material.pipeline,
      vertexBuffer: material.vertexBuffer,
      vertexCount: 4,
      bindings: GpuBindingSet(
        uniforms: @[
          GpuUniformBinding(uniform: material.rowsUniform, values: rows),
          GpuUniformBinding(uniform: material.paramsUniform,
            values: @[1'f32 / float32(sourceInfo.width),
              (uv[3] - uv[1]) / float32(sourceInfo.height),
              float32(ord(sourceAlphaMode)),
              (if preserveAlpha: 1'f32 else: 0'f32)]),
          GpuUniformBinding(uniform: material.uvUniform, values: uv)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.sampler,
            texture: source)
        ]
      )
    ))
  true
