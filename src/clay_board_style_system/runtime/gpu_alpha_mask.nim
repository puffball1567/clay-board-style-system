## Same-host GPU alpha mask for sampled surfaces.
## Source and mask are sampled independently; output is premultiplied RGBA8.
import std/math

import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder]

type
  GpuAlphaMaskVertex = object
    x, y, z: float32
    u, v: float32

  GpuAlphaMaskMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    paramsUniform, sourceUvUniform, maskUvUniform: GpuResourceHandle
    sourceSampler, maskSampler: GpuResourceHandle

proc gpuAlphaMaskVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuAlphaMaskFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-alpha-mask-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssMaskSource, 0);
SAMPLER2D(s_cbssMaskCoverage, 1);
uniform vec4 u_cbssMaskParams;
uniform vec4 u_cbssMaskSourceUv;
uniform vec4 u_cbssMaskCoverageUv;
void main()
{
  vec2 sourceUv = mix(u_cbssMaskSourceUv.xy,
    u_cbssMaskSourceUv.zw, v_texcoord0);
  vec2 maskUv = mix(u_cbssMaskCoverageUv.xy,
    u_cbssMaskCoverageUv.zw, v_texcoord0);
  vec4 source = texture2D(s_cbssMaskSource, sourceUv);
  if (u_cbssMaskParams.x > 1.5) {
    source.a = 1.0;
  } else if (u_cbssMaskParams.x < 0.5) {
    source.rgb *= source.a;
  }
  float coverage = texture2D(s_cbssMaskCoverage, maskUv).a;
  if (u_cbssMaskParams.y > 0.5) coverage = 1.0 - coverage;
  coverage = mix(1.0, coverage, u_cbssMaskParams.z);
  gl_FragColor = source * coverage;
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuAlphaMaskMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuAlphaMaskMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuAlphaMaskMaterial) =
  ## Release after the final submitted frame while the host is still open.
  if material.isClosed:
    return
  for handle in [material.maskSampler, material.sourceSampler,
      material.maskUvUniform, material.sourceUvUniform,
      material.paramsUniform, material.vertexBuffer, material.pipeline,
      material.fragmentShader, material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuAlphaMaskMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuAlphaMaskMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError, "GPU alpha mask material requires a ready host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuAlphaMaskVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuAlphaMaskFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError, "GPU alpha mask shader artifacts do not match the built-in shaders")
  result = GpuAlphaMaskMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuAlphaMaskVertex(x: -1, y: -1, u: 0, v: 1),
    GpuAlphaMaskVertex(x: -1, y: 1, u: 0, v: 0),
    GpuAlphaMaskVertex(x: 1, y: -1, u: 1, v: 1),
    GpuAlphaMaskVertex(x: 1, y: 1, u: 1, v: 0)
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
        label: "gpu-alpha-mask-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-alpha-mask-quad"), vertexBytes)
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssMaskParams", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-alpha-mask-params"))
    result.sourceUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssMaskSourceUv", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-alpha-mask-source-uv"))
    result.maskUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssMaskCoverageUv", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-alpha-mask-coverage-uv"))
    result.sourceSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssMaskSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-alpha-mask-source-sampler"))
    result.maskSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssMaskCoverage",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-alpha-mask-coverage-sampler"))
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuAlphaMaskMaterial;
    source, mask, destination: GpuResourceHandle;
    sourceAlphaMode = gcamStraight;
    invertMask = false;
    maskStrength = 1'f32
): bool =
  ## Mask strength blends between an unmasked source and mask coverage.
  ## Source and mask may be the same sampled resource. Output is premultiplied.
  if material.isClosed:
    raise newException(ValueError, "GPU alpha mask material is closed")
  if maskStrength.classify in {fcNan, fcInf, fcNegInf} or
      maskStrength < 0 or maskStrength > 1:
    raise newException(ValueError,
      "GPU alpha mask strength must be finite and normalized")
  let host = material.host
  if not host.hasActiveGpuFrame():
    raise newException(GpuHostError, "GPU alpha mask requires an active frame")
  if source.namespace != material.namespace or
      mask.namespace != material.namespace or
      destination.namespace != material.namespace or
      source == destination or mask == destination:
    raise newException(ValueError,
      "GPU alpha mask resources must be in one namespace without target feedback")
  let sourceInfo = host.gpuPresentableResourceInfo(source)
  let maskInfo = host.gpuPresentableResourceInfo(mask)
  let targetInfo = host.gpuPresentableResourceInfo(destination)
  if sourceInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin sourceInfo.usage or
      sourceInfo.format notin {gtfRgba8, gtfBgra8} or
      maskInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin maskInfo.usage or
      maskInfo.format notin {gtfRgba8, gtfBgra8} or
      targetInfo.kind != grkRenderTarget or
      gtuRenderTarget notin targetInfo.usage or
      targetInfo.format != gtfRgba8 or
      sourceInfo.width != targetInfo.width or
      sourceInfo.height != targetInfo.height or
      maskInfo.width != targetInfo.width or
      maskInfo.height != targetInfo.height:
    raise newException(ValueError, "GPU alpha mask resource shapes are incompatible")
  if host.isGpuResourcePresentationRetained(destination):
    raise newException(GpuHostError,
      "GPU alpha mask cannot overwrite a presentation-retained target")
  let sourceUv =
    if sourceInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
  let maskUv =
    if maskInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
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
            values: @[float32(ord(sourceAlphaMode)),
              (if invertMask: 1'f32 else: 0'f32), maskStrength, 0'f32]),
          GpuUniformBinding(uniform: material.sourceUvUniform,
            values: sourceUv),
          GpuUniformBinding(uniform: material.maskUvUniform,
            values: maskUv)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.sourceSampler,
            texture: source),
          GpuTextureBinding(stage: 1, sampler: material.maskSampler,
            texture: mask)
        ]
      )
    ))
  true
