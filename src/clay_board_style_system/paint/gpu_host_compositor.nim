import std/[math, options]

import ../core/geometry
import ../runtime/gpu_host
import ../runtime/gpu_shader_builder
import ./gpu_direct_compositor

const
  gpuHostDirectCompositeClipUniformArrayLength* =
    uint16(1 + maxGpuDirectClipMasks * 2)

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
    ## u_cbssUvRect = (u0, v0, u1, v1). Masked pipelines additionally consume
    ## the fixed-size u_cbssClipMasks array.
    namespace*: GpuNamespaceId
    pipelines*: array[GpuAlphaMode, GpuResourceHandle]
    maskedPipelines*: array[GpuAlphaMode, GpuResourceHandle]
    vertexBuffer*: GpuResourceHandle
    compositeUniform*: GpuResourceHandle
    uvRectUniform*: GpuResourceHandle
    clipMasksUniform*: GpuResourceHandle
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

proc gpuHostDirectCompositeMaskedFragmentSource*(
    textureStage = 0'u8
): GpuShaderSource =
  ## Emits the bounded rounded-clip variant. Element zero stores
  ## (maskCount, visibleWidth, visibleHeight, pixelScale); each mask occupies two
  ## vec4 values: local bounds and (radius, 0, 0, 0). Header w stores the
  ## physical pixel scale used for one-pixel edge antialiasing.
  if textureStage >= uint8(maxGpuTextureBindings):
    raise newException(ValueError, "GPU compositor texture stage is invalid")
  var source = "$input v_texcoord0\n\n" &
    "#include \"bgfx_shader.sh\"\n\n" &
    "SAMPLER2D(s_cbssSurface, " & $textureStage & ");\n" &
    "uniform vec4 u_cbssComposite;\n" &
    "uniform vec4 u_cbssUvRect;\n" &
    "uniform vec4 u_cbssClipMasks[" &
      $gpuHostDirectCompositeClipUniformArrayLength & "];\n\n" &
    "float cbssRoundedRectDistance(vec2 point, vec4 bounds, float radius)\n" &
    "{\n" &
    "  vec2 halfSize = max((bounds.zw - bounds.xy) * 0.5, vec2(0.0));\n" &
    "  float boundedRadius = clamp(radius, 0.0, min(halfSize.x, halfSize.y));\n" &
    "  vec2 center = (bounds.xy + bounds.zw) * 0.5;\n" &
    "  vec2 delta = abs(point - center) - max(halfSize - vec2(boundedRadius), vec2(0.0));\n" &
    "  return length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0) - boundedRadius;\n" &
    "}\n\n" &
    "void main()\n" &
    "{\n" &
    "  vec2 point = v_texcoord0 * u_cbssClipMasks[0].yz;\n" &
    "  float clipCoverage = 1.0;\n"
  for index in 0 ..< maxGpuDirectClipMasks:
    let boundsIndex = 1 + index * 2
    let radiusIndex = boundsIndex + 1
    source.add "  if (u_cbssClipMasks[0].x > " &
      $(index.float32 + 0.5'f32) &
      ")\n" &
      "  {\n" &
      "    float distanceToMask = cbssRoundedRectDistance(point, u_cbssClipMasks[" &
      $boundsIndex & "], u_cbssClipMasks[" & $radiusIndex & "].x);\n" &
      "    clipCoverage = min(clipCoverage, 1.0 - smoothstep(-0.5, 0.5, " &
      "distanceToMask * u_cbssClipMasks[0].w));\n" &
      "  }\n"
  source.add(
    "  vec2 uv = mix(u_cbssUvRect.xy, u_cbssUvRect.zw, v_texcoord0);\n" &
    "  vec4 color = texture2D(s_cbssSurface, uv);\n" &
    "  float opacity = clamp(u_cbssComposite.x, 0.0, 1.0) * clipCoverage;\n" &
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
    "}\n"
  )
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-direct-composite-masked-fragment-" & $textureStage,
    source: move(source),
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

proc floorToInt64Saturated(value: float64): int64 {.inline.} =
  let rounded = floor(value)
  if rounded <= float64(low(int64)):
    low(int64)
  elif rounded >= float64(high(int64)):
    high(int64)
  else:
    int64(rounded)

proc ceilToInt64Saturated(value: float64): int64 {.inline.} =
  let rounded = ceil(value)
  if rounded <= float64(low(int64)):
    low(int64)
  elif rounded >= float64(high(int64)):
    high(int64)
  else:
    int64(rounded)

proc matchesPhysicalExtent(
    logicalExtent, scale: float32;
    physicalExtent: uint32
): bool {.inline.} =
  let expected = ceil(float64(logicalExtent) * float64(scale))
  expected >= 1.0 and expected <= float64(high(uint32)) and
    uint64(expected) == uint64(physicalExtent)

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
  let hasClipMasksUniform = material.clipMasksUniform.handlePresent
  if hasClipMasksUniform:
    if material.clipMasksUniform.namespace != material.namespace or
        material.clipMasksUniform.kind != grkUniform or
        not host.gpuUniformMatches(
          material.clipMasksUniform,
          "u_cbssClipMasks",
          gutVec4,
          gpuHostDirectCompositeClipUniformArrayLength
        ):
      raise newException(
        ValueError, "GPU compositor clip-mask uniform does not match the standard interface"
      )
    for alphaMode in alphaModes:
      let pipeline = material.maskedPipelines[alphaMode]
      if not pipeline.handlePresent or pipeline.namespace != material.namespace or
          pipeline.kind != grkPipeline or not host.isGpuResourceLive(pipeline):
        raise newException(
          ValueError, "GPU compositor is missing a clip-mask pipeline for an alpha mode"
        )
  else:
    for alphaMode in alphaModes:
      if material.maskedPipelines[alphaMode].handlePresent:
        raise newException(
          ValueError, "GPU compositor clip-mask pipelines require their uniform"
        )

proc physicalBounds(
    logical: Rect;
    target: Rect;
    scale: float32;
    width, height: uint32
): tuple[viewport: GpuViewport, empty: bool] =
  let left = floorToInt64Saturated(
    (float64(logical.x) - float64(target.x)) * float64(scale)
  )
  let top = floorToInt64Saturated(
    (float64(logical.y) - float64(target.y)) * float64(scale)
  )
  let right = ceilToInt64Saturated(
    (float64(logical.x) + float64(logical.w) - float64(target.x)) *
      float64(scale)
  )
  let bottom = ceilToInt64Saturated(
    (float64(logical.y) + float64(logical.h) - float64(target.y)) *
      float64(scale)
  )
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
    visible: Rect;
    rowsBottomUp = false
): array[4, float32] =
  let inverseWidth = 1.0'f32 / destination.w
  let inverseHeight = 1.0'f32 / destination.h
  result = [
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
  if rowsBottomUp:
    swap(result[1], result[3])

proc clipMaskUniformValues(
    context: GpuDirectCompositeContext;
    visible: Rect
): seq[float32] =
  result = newSeq[float32](
    int(gpuHostDirectCompositeClipUniformArrayLength) * 4
  )
  result[0] = float32(context.clipMaskCount)
  result[1] = visible.w
  result[2] = visible.h
  result[3] = context.pixelScale
  for index in 0 ..< int(context.clipMaskCount):
    let mask = context.clipMasks[index]
    let offset = (1 + index * 2) * 4
    result[offset] = mask.bounds.x - visible.x
    result[offset + 1] = mask.bounds.y - visible.y
    result[offset + 2] = mask.bounds.x + mask.bounds.w - visible.x
    result[offset + 3] = mask.bounds.y + mask.bounds.h - visible.y
    result[offset + 4] = mask.radius

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
  let supportsClipMasks = material.clipMasksUniform.handlePresent

  let capabilities = gpuDirectCompositeCapabilities(
    {gdctWindow, gdctOffscreen},
    clipBoundsSupported = clipBoundsSupported,
    clipMaskSupported = supportsClipMasks,
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
      if not capabilities.supports(request.context) or
          not capabilities.supports(request.frame):
        return gdcsUnsupported
      if not host.hasActiveGpuFrame():
        return gdcsRetry
      if not request.destination.validRect or
          not request.context.targetBounds.validRect or
          not request.opacity.finite or request.opacity < 0 or
          request.opacity > 1:
        return gdcsFailed
      if request.frame.alphaMode notin info.directPresentationAlphaModes:
        return gdcsUnsupported

      var sourceInfo: GpuPresentableResourceInfo
      try:
        sourceInfo = host.gpuPresentableResourceInfo(request.frame.resource)
      except GpuHostError:
        return gdcsUnsupported
      if sourceInfo.kind != request.frame.resource.kind or
          sourceInfo.width != request.frame.width or
          sourceInfo.height != request.frame.height or
          sourceInfo.format != request.frame.format:
        return gdcsUnsupported

      var passTarget: GpuResourceHandle
      var targetPixelWidth = config.width
      var targetPixelHeight = config.height
      case request.context.targetKind
      of gdctWindow:
        if not request.context.offscreenTarget.isEmptyGpuHandle():
          return gdcsUnsupported
      of gdctOffscreen:
        passTarget = request.context.offscreenTarget
        if passTarget.isEmptyGpuHandle() or
            passTarget.kind != grkRenderTarget or
            passTarget.namespace != material.namespace or
            passTarget == request.frame.resource or
            not host.isGpuResourceLive(passTarget):
          return gdcsUnsupported
        var targetInfo: GpuPresentableResourceInfo
        try:
          targetInfo = host.gpuPresentableResourceInfo(passTarget)
        except GpuHostError:
          return gdcsUnsupported
        if gtuRenderTarget notin targetInfo.usage:
          return gdcsUnsupported
        targetPixelWidth = targetInfo.width
        targetPixelHeight = targetInfo.height
        if not matchesPhysicalExtent(
              request.context.targetBounds.w,
              request.context.pixelScale,
              targetPixelWidth
            ) or
            not matchesPhysicalExtent(
              request.context.targetBounds.h,
              request.context.pixelScale,
              targetPixelHeight
            ):
          return gdcsUnsupported
      of gdctUnspecified:
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
        targetPixelWidth,
        targetPixelHeight
      )
      if bounds.empty:
        return gdcsPresented

      let pipeline =
        if request.context.requiresClipMask:
          material.maskedPipelines[request.frame.alphaMode]
        else:
          material.pipelines[request.frame.alphaMode]
      var uniforms = @[
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
          values: @(
            request.destination.uvRect(visible, sourceInfo.rowsBottomUp)
          )
        )
      ]
      if request.context.requiresClipMask:
        uniforms.add GpuUniformBinding(
          uniform: material.clipMasksUniform,
          values: request.context.clipMaskUniformValues(visible)
        )
      try:
        host.submitGpuPresentationDraw(
          material.namespace,
          GpuGraphicsPassDescriptor(
            viewport: bounds.viewport,
            renderTarget: passTarget
          ),
          GpuDrawCommand(
            pipeline: pipeline,
            vertexBuffer: material.vertexBuffer,
            vertexCount: material.vertexCount,
            bindings: GpuBindingSet(uniforms: move(uniforms))
          ),
          GpuPresentationTextureBinding(
            stage: material.textureStage,
            sampler: material.sampler,
            texture: request.frame.resource
          )
        )
        gdcsPresented
      except GpuHostError as error:
        when defined(cbssGpuCompositorDiagnostics):
          stderr.writeLine("CBSS GPU compositor: " & error.msg)
        else:
          discard error
        gdcsFailed
  )
