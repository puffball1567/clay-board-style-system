## Same-host displacement of a sampled GPU surface by another surface's RG.
## The output is premultiplied RGBA8.
import std/math

import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder]

const MaxGpuDisplacementPixels* = 4096'f32

type
  GpuDisplacementVertex = object
    x, y, z: float32
    u, v: float32

  GpuDisplacementMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    paramsUniform, sourceUvUniform, mapUvUniform: GpuResourceHandle
    sourceSampler, mapSampler: GpuResourceHandle

proc validGpuDisplacementScale*(scale: float32): bool =
  scale.classify notin {fcNan, fcInf, fcNegInf} and
    abs(scale) <= MaxGpuDisplacementPixels

proc gpuDisplacementVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuDisplacementFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-displacement-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssDisplaceSource, 0);
SAMPLER2D(s_cbssDisplaceMap, 1);
uniform vec4 u_cbssDisplaceParams;
uniform vec4 u_cbssDisplaceSourceUv;
uniform vec4 u_cbssDisplaceMapUv;
void main()
{
  vec2 mapUv = mix(u_cbssDisplaceMapUv.xy,
    u_cbssDisplaceMapUv.zw, v_texcoord0);
  vec2 offset = (texture2D(s_cbssDisplaceMap, mapUv).rg * 2.0 -
    vec2(1.0)) * u_cbssDisplaceParams.xy;
  vec2 sourceUv = mix(u_cbssDisplaceSourceUv.xy,
    u_cbssDisplaceSourceUv.zw, v_texcoord0);
  sourceUv += offset * vec2(1.0,
    u_cbssDisplaceSourceUv.w - u_cbssDisplaceSourceUv.y);
  vec4 sampled = texture2D(s_cbssDisplaceSource, sourceUv);
  if (u_cbssDisplaceParams.z > 1.5) {
    sampled.a = 1.0;
  } else if (u_cbssDisplaceParams.z < 0.5) {
    sampled.rgb *= sampled.a;
  }
  gl_FragColor = sampled;
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuDisplacementMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuDisplacementMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuDisplacementMaterial) =
  ## Release after the final submitted frame while the host is still open.
  if material.isClosed:
    return
  for handle in [material.mapSampler, material.sourceSampler,
      material.mapUvUniform, material.sourceUvUniform,
      material.paramsUniform, material.vertexBuffer, material.pipeline,
      material.fragmentShader, material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuDisplacementMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact;
    sourceFilter = gsfNearest;
    mapFilter = gsfNearest
): GpuDisplacementMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError,
      "GPU displacement material requires a ready host")
  if sourceFilter notin {gsfNearest, gsfLinear} or
      mapFilter notin {gsfNearest, gsfLinear}:
    raise newException(ValueError,
      "GPU displacement sampling must be nearest or linear")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuDisplacementVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuDisplacementFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError,
      "GPU displacement shader artifacts do not match the built-in shaders")
  result = GpuDisplacementMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuDisplacementVertex(x: -1, y: -1, u: 0, v: 1),
    GpuDisplacementVertex(x: -1, y: 1, u: 0, v: 0),
    GpuDisplacementVertex(x: 1, y: -1, u: 1, v: 1),
    GpuDisplacementVertex(x: 1, y: 1, u: 1, v: 0)
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
        label: "gpu-displacement-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-displacement-quad"), vertexBytes)
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssDisplaceParams",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-displacement-params"))
    result.sourceUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssDisplaceSourceUv",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-displacement-source-uv"))
    result.mapUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssDisplaceMapUv",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-displacement-map-uv"))
    result.sourceSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssDisplaceSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: sourceFilter, magFilter: sourceFilter,
        mipFilter: gsfNearest, label: "gpu-displacement-source-sampler"))
    result.mapSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssDisplaceMap",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: mapFilter, magFilter: mapFilter,
        mipFilter: gsfNearest, label: "gpu-displacement-map-sampler"))
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuDisplacementMaterial;
    source, displacementMap, destination: GpuResourceHandle;
    scaleX, scaleY: float32;
    sourceAlphaMode = gcamStraight
): bool =
  ## Map RG values move source sampling by -scale..+scale destination pixels.
  if material.isClosed:
    raise newException(ValueError, "GPU displacement material is closed")
  if not scaleX.validGpuDisplacementScale or
      not scaleY.validGpuDisplacementScale:
    raise newException(ValueError,
      "GPU displacement scale must be finite and within 4096 pixels")
  let host = material.host
  if not host.hasActiveGpuFrame():
    raise newException(GpuHostError,
      "GPU displacement requires an active frame")
  if source.namespace != material.namespace or
      displacementMap.namespace != material.namespace or
      destination.namespace != material.namespace or
      source == destination or displacementMap == destination:
    raise newException(ValueError,
      "GPU displacement resources must be in one namespace without target feedback")
  let sourceInfo = host.gpuPresentableResourceInfo(source)
  let mapInfo = host.gpuPresentableResourceInfo(displacementMap)
  let targetInfo = host.gpuPresentableResourceInfo(destination)
  if sourceInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin sourceInfo.usage or
      sourceInfo.format notin {gtfRgba8, gtfBgra8} or
      mapInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin mapInfo.usage or
      mapInfo.format notin {gtfRgba8, gtfBgra8} or
      targetInfo.kind != grkRenderTarget or
      gtuRenderTarget notin targetInfo.usage or
      targetInfo.format != gtfRgba8 or
      sourceInfo.width != targetInfo.width or
      sourceInfo.height != targetInfo.height or
      mapInfo.width != targetInfo.width or
      mapInfo.height != targetInfo.height:
    raise newException(ValueError,
      "GPU displacement resource shapes are incompatible")
  if host.isGpuResourcePresentationRetained(destination):
    raise newException(GpuHostError,
      "GPU displacement cannot overwrite a presentation-retained target")
  let sourceUv =
    if sourceInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
  let mapUv =
    if mapInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
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
          GpuUniformBinding(uniform: material.paramsUniform,
            values: @[scaleX / float32(sourceInfo.width),
              scaleY / float32(sourceInfo.height),
              float32(ord(sourceAlphaMode)), 0'f32]),
          GpuUniformBinding(uniform: material.sourceUvUniform,
            values: sourceUv),
          GpuUniformBinding(uniform: material.mapUvUniform,
            values: mapUv)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.sourceSampler,
            texture: source),
          GpuTextureBinding(stage: 1, sampler: material.mapSampler,
            texture: displacementMap)
        ]
      )
    ))
  true
