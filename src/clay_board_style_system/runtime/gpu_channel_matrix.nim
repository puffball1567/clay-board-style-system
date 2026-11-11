## GPU-only 4x5 RGBA color matrix with premultiplied output.
import std/math

import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder]

const MaxGpuChannelMatrixCoefficient* = 16'f32

type
  GpuChannelMatrix* = object
    coefficients: array[20, float32]

  GpuChannelMatrixVertex = object
    x, y, z: float32
    u, v: float32

  GpuChannelMatrixMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    rowsUniform, offsetsUniform, paramsUniform, uvUniform: GpuResourceHandle
    sampler: GpuResourceHandle

proc gpuChannelMatrix*(coefficients: array[20, float32]): GpuChannelMatrix =
  ## Four rows of [R, G, B, A, offset] in encoded source RGB.
  for value in coefficients:
    if value.classify in {fcNan, fcInf, fcNegInf} or
        abs(value) > MaxGpuChannelMatrixCoefficient:
      raise newException(ValueError,
        "GPU channel matrix coefficients must be finite and within -16..16")
  GpuChannelMatrix(coefficients: coefficients)

proc identityGpuChannelMatrix*(): GpuChannelMatrix =
  gpuChannelMatrix([
    1'f32, 0, 0, 0, 0,
    0'f32, 1, 0, 0, 0,
    0'f32, 0, 1, 0, 0,
    0'f32, 0, 0, 1, 0
  ])

proc gpuChannelMatrixVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuChannelMatrixFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-channel-matrix-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssChannelSource, 0);
uniform vec4 u_cbssChannelRows[4];
uniform vec4 u_cbssChannelOffsets;
uniform vec4 u_cbssChannelParams;
uniform vec4 u_cbssChannelUv;
void main()
{
  vec2 uv = mix(u_cbssChannelUv.xy, u_cbssChannelUv.zw, v_texcoord0);
  vec4 sampled = texture2D(s_cbssChannelSource, uv);
  float alpha = sampled.a;
  vec3 straight = sampled.rgb;
  if (u_cbssChannelParams.x > 1.5) {
    alpha = 1.0;
  } else if (u_cbssChannelParams.x > 0.5) {
    straight = alpha > 0.0 ? sampled.rgb / alpha : vec3(0.0);
  }
  vec4 channels = vec4(straight, alpha);
  vec4 transformed = clamp(vec4(
    dot(u_cbssChannelRows[0], channels),
    dot(u_cbssChannelRows[1], channels),
    dot(u_cbssChannelRows[2], channels),
    dot(u_cbssChannelRows[3], channels)) +
    u_cbssChannelOffsets, vec4(0.0), vec4(1.0));
  gl_FragColor = vec4(transformed.rgb * transformed.a, transformed.a);
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuChannelMatrixMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuChannelMatrixMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuChannelMatrixMaterial) =
  ## Release after the final submitted frame while the host is still open.
  if material.isClosed:
    return
  for handle in [material.sampler, material.uvUniform,
      material.paramsUniform, material.offsetsUniform, material.rowsUniform,
      material.vertexBuffer, material.pipeline, material.fragmentShader,
      material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuChannelMatrixMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuChannelMatrixMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError,
      "GPU channel matrix material requires a ready host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuChannelMatrixVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuChannelMatrixFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError,
      "GPU channel matrix shader artifacts do not match the built-in shaders")
  result = GpuChannelMatrixMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuChannelMatrixVertex(x: -1, y: -1, u: 0, v: 1),
    GpuChannelMatrixVertex(x: -1, y: 1, u: 0, v: 0),
    GpuChannelMatrixVertex(x: 1, y: -1, u: 1, v: 1),
    GpuChannelMatrixVertex(x: 1, y: 1, u: 1, v: 0)
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
        label: "gpu-channel-matrix-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-channel-matrix-quad"), vertexBytes)
    result.rowsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssChannelRows",
        uniformType: gutVec4, arrayLength: 4,
        label: "gpu-channel-matrix-rows"))
    result.offsetsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssChannelOffsets",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-channel-matrix-offsets"))
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssChannelParams",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-channel-matrix-params"))
    result.uvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssChannelUv",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-channel-matrix-uv"))
    result.sampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssChannelSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-channel-matrix-sampler"))
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuChannelMatrixMaterial;
    source, destination: GpuResourceHandle;
    matrix: GpuChannelMatrix;
    sourceAlphaMode = gcamStraight
): bool =
  ## A full RGBA matrix on straight channels; output is premultiplied RGBA8.
  if material.isClosed:
    raise newException(ValueError, "GPU channel matrix material is closed")
  let host = material.host
  if source.namespace != material.namespace or
      destination.namespace != material.namespace or source == destination:
    raise newException(ValueError,
      "GPU channel matrix resources must be distinct and in one namespace")
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
      "GPU channel matrix source and target are incompatible")
  if host.isGpuResourcePresentationRetained(destination):
    raise newException(GpuHostError,
      "GPU channel matrix cannot overwrite a presentation-retained target")
  var rows = newSeq[float32](16)
  var offsets = newSeq[float32](4)
  for row in 0 .. 3:
    for channel in 0 .. 3:
      rows[row * 4 + channel] = matrix.coefficients[row * 5 + channel]
    offsets[row] = matrix.coefficients[row * 5 + 4]
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
          GpuUniformBinding(uniform: material.offsetsUniform,
            values: offsets),
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
