## Same-host GPU drop shadow for sampled RGBA8 surfaces.
## Blurs source alpha, offsets and tints it, then composites the original.
import std/math

import ../core/color
import ../paint/gpu_host_compositor
import ./[gpu_gaussian_blur, gpu_host, gpu_shader_builder]

type
  GpuShadowVertex = object
    x, y, z: float32
    u, v: float32

  GpuDropShadowMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    blur: GpuGaussianBlurMaterial
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    paramsUniform, colorUniform, sourceUvUniform, blurUvUniform: GpuResourceHandle
    sourceSampler, blurSampler: GpuResourceHandle

proc gpuDropShadowVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuDropShadowFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-drop-shadow-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssShadowSource, 0);
SAMPLER2D(s_cbssShadowBlurred, 1);
uniform vec4 u_cbssShadowParams;
uniform vec4 u_cbssShadowColor;
uniform vec4 u_cbssShadowSourceUv;
uniform vec4 u_cbssShadowBlurUv;
void main()
{
  vec2 sourceUv = mix(u_cbssShadowSourceUv.xy,
    u_cbssShadowSourceUv.zw, v_texcoord0);
  vec4 original = texture2D(s_cbssShadowSource, sourceUv);
  if (u_cbssShadowParams.z > 1.5) {
    original.a = 1.0;
  } else if (u_cbssShadowParams.z < 0.5) {
    original.rgb *= original.a;
  }
  vec2 shadowPoint = v_texcoord0 - u_cbssShadowParams.xy;
  float shadowAlpha = 0.0;
  if (shadowPoint.x >= 0.0 && shadowPoint.x <= 1.0 &&
      shadowPoint.y >= 0.0 && shadowPoint.y <= 1.0) {
    vec2 blurUv = mix(u_cbssShadowBlurUv.xy,
      u_cbssShadowBlurUv.zw, shadowPoint);
    shadowAlpha = texture2D(s_cbssShadowBlurred, blurUv).a *
      u_cbssShadowColor.a;
  }
  vec4 shadow = vec4(u_cbssShadowColor.rgb * shadowAlpha, shadowAlpha);
  gl_FragColor = original + shadow * (1.0 - original.a);
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuDropShadowMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuDropShadowMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuDropShadowMaterial) =
  ## Release after the last submitted frame while the host is open.
  if material.isClosed:
    return
  for handle in [material.blurSampler, material.sourceSampler,
      material.blurUvUniform, material.sourceUvUniform,
      material.colorUniform, material.paramsUniform,
      material.vertexBuffer, material.pipeline, material.fragmentShader,
      material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.blur.release()
  material.host = nil

proc newGpuDropShadowMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    blurVertexArtifact, blurFragmentArtifact,
    shadowVertexArtifact, shadowFragmentArtifact: GpuShaderArtifact
): GpuDropShadowMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError, "GPU drop shadow material requires a ready host")
  if shadowVertexArtifact.descriptor.stage != gssVertex or
      shadowVertexArtifact.sourceHash != gpuDropShadowVertexSource().gpuShaderSourceHash() or
      shadowFragmentArtifact.descriptor.stage != gssFragment or
      shadowFragmentArtifact.sourceHash != gpuDropShadowFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError, "GPU drop shadow shader artifacts do not match the built-in shaders")
  result = GpuDropShadowMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuShadowVertex(x: -1, y: -1, u: 0, v: 1),
    GpuShadowVertex(x: -1, y: 1, u: 0, v: 0),
    GpuShadowVertex(x: 1, y: -1, u: 1, v: 1),
    GpuShadowVertex(x: 1, y: 1, u: 1, v: 0)
  ]
  var vertexBytes = newSeq[byte](sizeof(vertices))
  copyMem(addr vertexBytes[0], unsafeAddr vertices[0], vertexBytes.len)
  try:
    result.blur = host.newGpuGaussianBlurMaterial(namespace,
      blurVertexArtifact, blurFragmentArtifact)
    result.vertexShader = host.createGpuShader(namespace, shadowVertexArtifact)
    result.fragmentShader = host.createGpuShader(namespace, shadowFragmentArtifact)
    result.pipeline = host.createGpuGraphicsPipeline(namespace,
      GpuGraphicsPipelineDescriptor(
        vertexShader: result.vertexShader,
        fragmentShader: result.fragmentShader,
        vertexLayout: layout,
        colorFormat: gtfRgba8,
        topology: gptTriangleStrip,
        cullMode: gcmNone,
        blend: opaqueGpuBlendState(),
        label: "gpu-drop-shadow-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-drop-shadow-quad"), vertexBytes)
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssShadowParams", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-drop-shadow-params"))
    result.colorUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssShadowColor", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-drop-shadow-color"))
    result.sourceUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssShadowSourceUv", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-drop-shadow-source-uv"))
    result.blurUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssShadowBlurUv", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-drop-shadow-blur-uv"))
    result.sourceSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssShadowSource",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-drop-shadow-source-sampler"))
    result.blurSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssShadowBlurred",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-drop-shadow-blur-sampler"))
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuDropShadowMaterial;
    source, scratch, blurred, destination: GpuResourceHandle;
    offsetX, offsetY: float32;
    color: Color;
    sourceAlphaMode = gcamStraight;
    blurRadius = 2
): bool =
  ## Offset is in destination pixels. The shadow is clipped to destination
  ## bounds; callers can supply padding in the source to show the full shadow.
  if material.isClosed:
    raise newException(ValueError, "GPU drop shadow material is closed")
  if blurRadius < 0 or blurRadius > MaxGpuBlurRadius:
    raise newException(ValueError,
      "GPU drop shadow blur radius must be between 0 and 4")
  if offsetX.classify in {fcNan, fcInf, fcNegInf} or
      offsetY.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "GPU drop shadow offset must be finite")
  for channel in [color.r, color.g, color.b, color.a]:
    if channel.classify in {fcNan, fcInf, fcNegInf} or
        channel < 0 or channel > 1:
      raise newException(ValueError, "GPU drop shadow color must be finite and normalized")
  if source == scratch or source == blurred or source == destination or
      scratch == blurred or scratch == destination or blurred == destination or
      source.namespace != material.namespace or
      scratch.namespace != material.namespace or
      blurred.namespace != material.namespace or
      destination.namespace != material.namespace:
    raise newException(ValueError, "GPU drop shadow resources must be distinct and in one namespace")
  let sourceInfo = material.host.gpuPresentableResourceInfo(source)
  let scratchInfo = material.host.gpuPresentableResourceInfo(scratch)
  let blurredInfo = material.host.gpuPresentableResourceInfo(blurred)
  let targetInfo = material.host.gpuPresentableResourceInfo(destination)
  if sourceInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin sourceInfo.usage or
      sourceInfo.format notin {gtfRgba8, gtfBgra8} or
      scratchInfo.kind != grkRenderTarget or
      gtuSampled notin scratchInfo.usage or
      gtuRenderTarget notin scratchInfo.usage or
      scratchInfo.format != gtfRgba8 or
      blurredInfo.kind != grkRenderTarget or
      gtuSampled notin blurredInfo.usage or
      gtuRenderTarget notin blurredInfo.usage or
      blurredInfo.format != gtfRgba8 or
      targetInfo.kind != grkRenderTarget or
      gtuRenderTarget notin targetInfo.usage or
      targetInfo.format != gtfRgba8 or
      sourceInfo.width != scratchInfo.width or
      sourceInfo.height != scratchInfo.height or
      sourceInfo.width != blurredInfo.width or
      sourceInfo.height != blurredInfo.height or
      sourceInfo.width != targetInfo.width or
      sourceInfo.height != targetInfo.height:
    raise newException(ValueError, "GPU drop shadow resource shapes are incompatible")
  if not material.host.hasActiveGpuFrame():
    raise newException(GpuHostError, "GPU drop shadow requires an active frame")
  for target in [scratch, blurred, destination]:
    if material.host.isGpuResourcePresentationRetained(target):
      raise newException(GpuHostError,
        "GPU drop shadow cannot overwrite a presentation-retained target")
  discard material.blur.submit(source, scratch, blurred,
    sourceAlphaMode, blurRadius)
  let sourceUv =
    if sourceInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
  let blurUv =
    if blurredInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
  material.host.submitGpuDraw(material.namespace,
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
            values: @[offsetX / float32(targetInfo.width),
              offsetY / float32(targetInfo.height),
              float32(ord(sourceAlphaMode)), 0'f32]),
          GpuUniformBinding(uniform: material.colorUniform,
            values: @[color.r, color.g, color.b, color.a]),
          GpuUniformBinding(uniform: material.sourceUvUniform, values: sourceUv),
          GpuUniformBinding(uniform: material.blurUvUniform, values: blurUv)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.sourceSampler,
            texture: source),
          GpuTextureBinding(stage: 1, sampler: material.blurSampler,
            texture: blurred)
        ]
      )
    ))
  true
