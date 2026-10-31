## GPU postprocess for the same encoded-sRGB RGB matrix used by Canvas layers.
## Import explicitly; the ordinary UI and CPU filter path remains GPU-free.
import ../paint/[gpu_host_compositor, layer_color_filter]
import ./[gpu_host, gpu_shader_builder]

type
  GpuColorMatrixVertex = object
    x, y, z: float32
    u, v: float32

  GpuColorMatrixMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    rowsUniform, paramsUniform, uvUniform: GpuResourceHandle
    sampler: GpuResourceHandle

proc gpuColorMatrixVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuColorMatrixFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-color-matrix-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssFilterSource, 0);
uniform vec4 u_cbssColorRows[3];
uniform vec4 u_cbssFilterParams;
uniform vec4 u_cbssUvRect;
void main()
{
  vec2 uv = mix(u_cbssUvRect.xy, u_cbssUvRect.zw, v_texcoord0);
  vec4 sampled = texture2D(s_cbssFilterSource, uv);
  float alpha = sampled.a;
  vec3 straight = sampled.rgb;
  if (u_cbssFilterParams.x > 1.5) {
    alpha = 1.0;
  } else if (u_cbssFilterParams.x > 0.5) {
    straight = alpha > 0.0 ? sampled.rgb / alpha : vec3(0.0);
  }
  vec4 channels = vec4(straight, 1.0);
  vec3 filtered = clamp(vec3(
    dot(u_cbssColorRows[0], channels),
    dot(u_cbssColorRows[1], channels),
    dot(u_cbssColorRows[2], channels)), 0.0, 1.0);
  gl_FragColor = vec4(filtered * alpha, alpha);
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuColorMatrixMaterial): bool =
  material.isNil or material.host.isNil

proc release*(material: GpuColorMatrixMaterial) =
  ## Release after the final submitted frame while the host is still open.
  if material.isClosed:
    return
  for handle in [material.sampler, material.uvUniform,
      material.paramsUniform, material.rowsUniform, material.vertexBuffer,
      material.pipeline, material.fragmentShader, material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuColorMatrixMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuColorMatrixMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError, "GPU color matrix material requires a ready host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuColorMatrixVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuColorMatrixFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError, "GPU color matrix shader artifacts do not match the built-in shaders")
  result = GpuColorMatrixMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuColorMatrixVertex(x: -1, y: -1, u: 0, v: 1),
    GpuColorMatrixVertex(x: -1, y: 1, u: 0, v: 0),
    GpuColorMatrixVertex(x: 1, y: -1, u: 1, v: 1),
    GpuColorMatrixVertex(x: 1, y: 1, u: 1, v: 0)
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
        label: "gpu-color-matrix-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-color-matrix-quad"), vertexBytes)
    result.rowsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssColorRows", uniformType: gutVec4,
        arrayLength: 3, label: "gpu-color-matrix-rows"))
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssFilterParams", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-color-matrix-params"))
    result.uvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssUvRect", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-color-matrix-uv"))
    result.sampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssFilterSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-color-matrix-sampler"))
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuColorMatrixMaterial;
    source, destination: GpuResourceHandle;
    filter: LayerColorFilter;
    sourceAlphaMode = gcamStraight
): bool =
  ## Filters one sampled RGBA8/BGRA8 source into a same-size RGBA8 target.
  ## Output pixels are premultiplied; use gcamPremultiplied for presentation.
  if material.isClosed:
    raise newException(ValueError, "GPU color matrix material is closed")
  let host = material.host
  if source.namespace != material.namespace or
      destination.namespace != material.namespace or source == destination:
    raise newException(ValueError, "GPU color matrix resources must be distinct and in one namespace")
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
    raise newException(ValueError, "GPU color matrix source and target are incompatible")
  let coefficients = filter.colorMatrixCoefficients()
  var rows = newSeq[float32](coefficients.len)
  for index, value in coefficients:
    rows[index] = value
  let uv =
    if sourceInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
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
            values: @[float32(ord(sourceAlphaMode)), 0'f32, 0, 0]),
          GpuUniformBinding(uniform: material.uvUniform, values: uv)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.sampler,
            texture: source)
        ]
      )
    ))
  true
