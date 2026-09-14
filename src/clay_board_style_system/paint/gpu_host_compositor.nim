import std/[math, options]

import ../core/geometry
import ../runtime/gpu_host
import ../runtime/gpu_shader_builder
import ./gpu_direct_compositor

const
  gpuHostDirectCompositeVaryingDefinitions* = """
vec2 v_texcoord0 : TEXCOORD0 = vec2(0.0, 0.0);

vec3 a_position  : POSITION;
vec2 a_texcoord0 : TEXCOORD0;
"""

  gpuHostDirectCompositeVertexShader* = """$input a_position, a_texcoord0
$output v_texcoord0

#include "bgfx_shader.sh"

void main()
{
  gl_Position = vec4(a_position, 1.0);
  v_texcoord0 = a_texcoord0;
}
"""

type
  GpuHostDirectCompositeMaterial* = object
    ## Resources are retained by their owner and must outlive the compositor.
    ## The shaders consume a full-viewport position/UV vertex stream,
    ## u_cbssComposite = (opacity, alphaMode, 0, 0), and
    ## u_cbssUvRect = (u0, v0, u1, v1).
    namespace*: GpuNamespaceId
    pipelines*: array[GpuAlphaMode, GpuResourceHandle]
    vertexBuffer*: GpuResourceHandle
    compositeUniform*: GpuResourceHandle
    uvRectUniform*: GpuResourceHandle
    sampler*: GpuResourceHandle
    textureStage*: uint8
    vertexCount*: uint32

proc gpuHostDirectCompositeVertexSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssVertex,
    label: "cbss-direct-composite-vertex",
    source: gpuHostDirectCompositeVertexShader,
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisPosition, valueType: gsvtVec3),
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ],
    outputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc gpuHostDirectCompositeFragmentSource*(
    textureStage = 0'u8
): GpuShaderSource =
  if textureStage >= uint8(maxGpuTextureBindings):
    raise newException(ValueError, "GPU compositor texture stage is invalid")
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-direct-composite-fragment-" & $textureStage,
    source: "$input v_texcoord0\n\n" &
      "#include \"bgfx_shader.sh\"\n\n" &
      "SAMPLER2D(s_cbssSurface, " & $textureStage & ");\n" &
      "uniform vec4 u_cbssComposite;\n" &
      "uniform vec4 u_cbssUvRect;\n\n" &
      "void main()\n" &
      "{\n" &
      "  vec2 uv = mix(u_cbssUvRect.xy, u_cbssUvRect.zw, v_texcoord0);\n" &
      "  vec4 color = texture2D(s_cbssSurface, uv);\n" &
      "  float opacity = clamp(u_cbssComposite.x, 0.0, 1.0);\n" &
      "  float alphaMode = u_cbssComposite.y;\n" &
      "  if (alphaMode < 0.5)\n" &
      "  {\n" &
      "    color.a *= opacity;\n" &
      "  }\n" &
      "  else if (alphaMode < 1.5)\n" &
      "  {\n" &
      "    color *= opacity;\n" &
      "  }\n" &
      "  else\n" &
      "  {\n" &
      "    color.a = opacity;\n" &
      "  }\n" &
      "  gl_FragColor = color;\n" &
      "}\n",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc finite(value: float32): bool {.inline.} =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc validRect(value: Rect): bool {.inline.} =
  value.x.finite and value.y.finite and value.w.finite and value.h.finite and
    value.w > 0 and value.h > 0

proc handlePresent(handle: GpuResourceHandle): bool {.inline.} =
  handle.resource.resourceIdValue() != 0

proc validateMaterial(
    host: GpuHost;
    material: GpuHostDirectCompositeMaterial;
    alphaModes: set[GpuAlphaMode]
) =
  if material.vertexCount == 0:
    raise newException(ValueError, "GPU compositor vertex count must be positive")
  if material.textureStage >= uint8(maxGpuTextureBindings):
    raise newException(ValueError, "GPU compositor texture stage is invalid")
  for handle in [
    material.vertexBuffer,
    material.compositeUniform,
    material.uvRectUniform,
    material.sampler
  ]:
    if handle.namespace != material.namespace or
        not host.isGpuResourceLive(handle):
      raise newException(
        ValueError, "GPU compositor resources must be live in one namespace"
      )
  if material.vertexBuffer.kind != grkBuffer or
      material.compositeUniform.kind != grkUniform or
      material.uvRectUniform.kind != grkUniform or
      material.sampler.kind != grkSampler:
    raise newException(ValueError, "GPU compositor resource kinds are invalid")
  if not host.gpuUniformMatches(
      material.compositeUniform, "u_cbssComposite", gutVec4
    ) or not host.gpuUniformMatches(
      material.uvRectUniform, "u_cbssUvRect", gutVec4
    ) or not host.gpuSamplerMatches(material.sampler, "s_cbssSurface"):
    raise newException(
      ValueError, "GPU compositor bindings do not match the standard shader interface"
    )
  for alphaMode in alphaModes:
    let pipeline = material.pipelines[alphaMode]
    if not pipeline.handlePresent or pipeline.namespace != material.namespace or
        pipeline.kind != grkPipeline or not host.isGpuResourceLive(pipeline):
      raise newException(
        ValueError, "GPU compositor is missing a live pipeline for an alpha mode"
      )

proc physicalBounds(
    logical: Rect;
    target: Rect;
    scale: float32;
    width, height: uint32
): tuple[viewport: GpuViewport, empty: bool] =
  let left = floor((logical.x - target.x) * scale).int64
  let top = floor((logical.y - target.y) * scale).int64
  let right = ceil((logical.x + logical.w - target.x) * scale).int64
  let bottom = ceil((logical.y + logical.h - target.y) * scale).int64
  let clippedLeft = clamp(left, 0'i64, int64(width))
  let clippedTop = clamp(top, 0'i64, int64(height))
  let clippedRight = clamp(right, 0'i64, int64(width))
  let clippedBottom = clamp(bottom, 0'i64, int64(height))
  if clippedRight <= clippedLeft or clippedBottom <= clippedTop:
    return (GpuViewport(), true)
  (
    GpuViewport(
      x: uint32(clippedLeft),
      y: uint32(clippedTop),
      width: uint32(clippedRight - clippedLeft),
      height: uint32(clippedBottom - clippedTop)
    ),
    false
  )

proc uvRect(
    destination: Rect;
    visible: Rect
): array[4, float32] =
  let inverseWidth = 1.0'f32 / destination.w
  let inverseHeight = 1.0'f32 / destination.h
  [
    clamp((visible.x - destination.x) * inverseWidth, 0.0'f32, 1.0'f32),
    clamp((visible.y - destination.y) * inverseHeight, 0.0'f32, 1.0'f32),
    clamp(
      (visible.x + visible.w - destination.x) * inverseWidth,
      0.0'f32,
      1.0'f32
    ),
    clamp(
      (visible.y + visible.h - destination.y) * inverseHeight,
      0.0'f32,
      1.0'f32
    )
  ]

proc newGpuHostDirectCompositor*(
    host: GpuHost;
    material: GpuHostDirectCompositeMaterial;
    clipBoundsSupported = true
): GpuDirectCompositor =
  ## Creates the standard same-host Texture/RenderTarget compositor. The caller
  ## begins and ends exactly one GpuHost frame around the surrounding paint
  ## stream; this callback never presents independently.
  if host.isNil or not host.isReady():
    raise newException(ValueError, "GPU compositor requires a ready host")
  let config = host.config()
  if not config.presentation:
    raise newException(ValueError, "GPU compositor requires a presentation host")
  let info = host.backendInfo()
  var sourceKinds: set[GpuResourceKind]
  if info.directTexturePresentationSupported:
    sourceKinds.incl grkTexture
  if info.directRenderTargetPresentationSupported:
    sourceKinds.incl grkRenderTarget
  if sourceKinds == {} or info.directPresentationFormats == {} or
      info.directPresentationAlphaModes == {}:
    raise newException(
      ValueError, "GPU host has no qualified direct presentation profile"
    )
  host.validateMaterial(material, info.directPresentationAlphaModes)

  let capabilities = gpuDirectCompositeCapabilities(
    {gdctWindow},
    clipBoundsSupported = clipBoundsSupported,
    clipMaskSupported = false,
    sourceProviders = {host.provider()},
    sourceKinds = sourceKinds,
    sourceFormats = info.directPresentationFormats,
    alphaModes = info.directPresentationAlphaModes,
    maxSourceWidth = info.maxDirectPresentationWidth,
    maxSourceHeight = info.maxDirectPresentationHeight
  )

  newGpuDirectCompositor(
    capabilities,
    proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
      if not host.isReady():
        return gdcsFailed
      if not host.hasActiveGpuFrame():
        return gdcsRetry
      if request.context.targetKind != gdctWindow or
          request.context.requiresClipMask:
        return gdcsUnsupported
      if not request.destination.validRect or
          not request.context.targetBounds.validRect or
          not request.opacity.finite or request.opacity < 0 or
          request.opacity > 1:
        return gdcsFailed
      if request.frame.alphaMode notin info.directPresentationAlphaModes:
        return gdcsUnsupported

      var visible = request.destination.intersection(request.context.targetBounds)
      if request.context.clipBounds.isSome:
        visible = visible.intersection(request.context.clipBounds.get)
      if visible.isEmpty:
        return gdcsPresented
      let bounds = physicalBounds(
        visible,
        request.context.targetBounds,
        request.context.pixelScale,
        config.width,
        config.height
      )
      if bounds.empty:
        return gdcsPresented

      let pipeline = material.pipelines[request.frame.alphaMode]
      try:
        host.submitGpuPresentationDraw(
          material.namespace,
          GpuGraphicsPassDescriptor(viewport: bounds.viewport),
          GpuDrawCommand(
            pipeline: pipeline,
            vertexBuffer: material.vertexBuffer,
            vertexCount: material.vertexCount,
            bindings: GpuBindingSet(
              uniforms: @[
                GpuUniformBinding(
                  uniform: material.compositeUniform,
                  values: @[
                    request.opacity,
                    float32(ord(request.frame.alphaMode)),
                    0.0'f32,
                    0.0'f32
                  ]
                ),
                GpuUniformBinding(
                  uniform: material.uvRectUniform,
                  values: @(request.destination.uvRect(visible))
                )
              ]
            )
          ),
          GpuPresentationTextureBinding(
            stage: material.textureStage,
            sampler: material.sampler,
            texture: request.frame.resource
          )
        )
        gdcsPresented
      except GpuHostError:
        gdcsFailed
  )
