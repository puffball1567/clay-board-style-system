## Ordered same-host postprocess for GPU-owned surfaces.
## The caller owns materials and four reusable RGBA8 render targets.
import std/math

import ../core/color
import ../paint/layer_color_filter
import ./[gpu_alpha_mask, gpu_channel_matrix, gpu_color_matrix,
  gpu_composite, gpu_gaussian_blur,
  gpu_displacement, gpu_drop_shadow, gpu_host, gpu_surface_crop,
  gpu_morphology, gpu_surface_placement]

const MaxGpuFilterStages* = 8

type
  GpuFilterStageKind* = enum
    gfskColorMatrix,
    gfskGaussianBlur,
    gfskDropShadow,
    gfskOpacity,
    gfskAlphaMask,
    gfskComposite,
    gfskDisplacement,
    gfskMorphology,
    gfskChannelMatrix

  GpuFilterStage* = object
    kindValue: GpuFilterStageKind
    matrixValue: LayerColorFilter
    opacityValue: float32
    offsetXValue, offsetYValue: float32
    colorValue: Color
    blurRadiusValue: int
    sampledInputValue: GpuResourceHandle
    invertMaskValue: bool
    maskStrengthValue: float32
    maskPlacementValue: GpuAlphaMaskPlacement
    maskCropValue: GpuAlphaMaskCrop
    maskModeValue: GpuMaskMode
    maskAlphaModeValue: GpuAlphaMode
    foregroundAlphaModeValue: GpuAlphaMode
    blendModeValue: GpuCompositeBlendMode
    foregroundOpacityValue: float32
    foregroundPlacementValue: GpuCompositePlacement
    foregroundCropValue: GpuCompositeCrop
    displacementScaleXValue, displacementScaleYValue: float32
    morphologyModeValue: GpuMorphologyMode
    morphologyRadiusValue: int
    channelMatrixValue: GpuChannelMatrix

  GpuFilterChain* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    stages: seq[GpuFilterStage]
    colorMatrix: GpuColorMatrixMaterial
    gaussianBlur: GpuGaussianBlurMaterial
    dropShadow: GpuDropShadowMaterial
    alphaMask: GpuAlphaMaskMaterial
    composite: GpuCompositeMaterial
    displacement: GpuDisplacementMaterial
    morphology: GpuMorphologyMaterial
    channelMatrix: GpuChannelMatrixMaterial

proc colorMatrixStage*(filter: LayerColorFilter): GpuFilterStage =
  GpuFilterStage(kindValue: gfskColorMatrix, matrixValue: filter)

proc channelMatrixStage*(matrix: GpuChannelMatrix): GpuFilterStage =
  GpuFilterStage(kindValue: gfskChannelMatrix,
    channelMatrixValue: matrix)

proc opacityStage*(opacity: float32): GpuFilterStage =
  if opacity.classify in {fcNan, fcInf, fcNegInf} or
      opacity < 0 or opacity > 1:
    raise newException(ValueError, "GPU filter opacity must be finite and normalized")
  GpuFilterStage(kindValue: gfskOpacity, opacityValue: opacity)

proc alphaMaskStage*(
    mask: GpuResourceHandle; invertMask = false; maskStrength = 1'f32;
    maskPlacement = GpuAlphaMaskPlacement();
    maskCrop = GpuAlphaMaskCrop();
    maskMode = gmmAlpha;
    maskAlphaMode = gcamStraight
): GpuFilterStage =
  ## Use the sampled mask's alpha; its RGB does not affect the source.
  if maskStrength.classify in {fcNan, fcInf, fcNegInf} or
      maskStrength < 0 or maskStrength > 1:
    raise newException(ValueError,
      "GPU alpha mask strength must be finite and normalized")
  GpuFilterStage(kindValue: gfskAlphaMask, sampledInputValue: mask,
    invertMaskValue: invertMask, maskStrengthValue: maskStrength,
    maskPlacementValue: maskPlacement, maskCropValue: maskCrop,
    maskModeValue: maskMode, maskAlphaModeValue: maskAlphaMode)

proc compositeStage*(
    foreground: GpuResourceHandle;
    foregroundAlphaMode = gcamStraight;
    blendMode = gcbmNormal;
    foregroundOpacity = 1'f32;
    foregroundPlacement = GpuCompositePlacement();
    foregroundCrop = GpuCompositeCrop()
): GpuFilterStage =
  ## Place a sampled foreground above the current chain result.
  if foregroundOpacity.classify in {fcNan, fcInf, fcNegInf} or
      foregroundOpacity < 0 or foregroundOpacity > 1:
    raise newException(ValueError,
      "GPU composite foreground opacity must be finite and normalized")
  GpuFilterStage(kindValue: gfskComposite, sampledInputValue: foreground,
    foregroundAlphaModeValue: foregroundAlphaMode,
    blendModeValue: blendMode, foregroundOpacityValue: foregroundOpacity,
    foregroundPlacementValue: foregroundPlacement,
    foregroundCropValue: foregroundCrop)

proc displacementStage*(
    displacementMap: GpuResourceHandle; scaleX, scaleY: float32
): GpuFilterStage =
  ## Map R and G displace the current result in destination pixels.
  if not scaleX.validGpuDisplacementScale or
      not scaleY.validGpuDisplacementScale:
    raise newException(ValueError,
      "GPU displacement scale must be finite and within 4096 pixels")
  GpuFilterStage(kindValue: gfskDisplacement,
    sampledInputValue: displacementMap,
    displacementScaleXValue: scaleX,
    displacementScaleYValue: scaleY)

proc morphologyStage*(
    mode: GpuMorphologyMode; radius = 1
): GpuFilterStage =
  if radius < 0 or radius > MaxGpuMorphologyRadius:
    raise newException(ValueError,
      "GPU morphology radius must be between 0 and 8")
  GpuFilterStage(kindValue: gfskMorphology,
    morphologyModeValue: mode, morphologyRadiusValue: radius)

proc gaussianBlurStage*(radius = 2): GpuFilterStage =
  if radius < 0 or radius > MaxGpuBlurRadius:
    raise newException(ValueError, "GPU filter blur radius must be between 0 and 16")
  GpuFilterStage(kindValue: gfskGaussianBlur, blurRadiusValue: radius)

proc dropShadowStage*(
    offsetX, offsetY: float32; color: Color; blurRadius = 2
): GpuFilterStage =
  if blurRadius < 0 or blurRadius > MaxGpuBlurRadius:
    raise newException(ValueError,
      "GPU filter shadow blur radius must be between 0 and 16")
  for value in [offsetX, offsetY]:
    if value.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "GPU filter shadow offset must be finite")
  for value in [color.r, color.g, color.b, color.a]:
    if value.classify in {fcNan, fcInf, fcNegInf} or
        value < 0 or value > 1:
      raise newException(ValueError,
        "GPU filter shadow color must be finite and normalized")
  GpuFilterStage(kindValue: gfskDropShadow,
    offsetXValue: offsetX, offsetYValue: offsetY,
    colorValue: color, blurRadiusValue: blurRadius)

proc newGpuFilterChain*(
    host: GpuHost; namespace: GpuNamespaceId;
    stages: openArray[GpuFilterStage];
    colorMatrix: GpuColorMatrixMaterial = nil;
    gaussianBlur: GpuGaussianBlurMaterial = nil;
    dropShadow: GpuDropShadowMaterial = nil;
    alphaMask: GpuAlphaMaskMaterial = nil;
    composite: GpuCompositeMaterial = nil;
    displacement: GpuDisplacementMaterial = nil;
    morphology: GpuMorphologyMaterial = nil;
    channelMatrix: GpuChannelMatrixMaterial = nil
): GpuFilterChain =
  if host.isNil or not host.isReady() or not host.hasGpuNamespace(namespace):
    raise newException(ValueError, "GPU filter chain requires a ready host namespace")
  if stages.len == 0 or stages.len > MaxGpuFilterStages:
    raise newException(ValueError, "GPU filter chain stage count is invalid")
  for stage in stages:
    case stage.kindValue
    of gfskColorMatrix, gfskOpacity:
      if not colorMatrix.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain color matrix material belongs to another host")
    of gfskChannelMatrix:
      if not channelMatrix.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain channel matrix material belongs to another host")
    of gfskGaussianBlur:
      if not gaussianBlur.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain blur material belongs to another host")
    of gfskDropShadow:
      if not dropShadow.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain shadow material belongs to another host")
    of gfskAlphaMask:
      if not alphaMask.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain alpha mask material belongs to another host")
      if stage.sampledInputValue.namespace != namespace or
          not host.isGpuResourceLive(stage.sampledInputValue):
        raise newException(ValueError,
          "GPU filter chain alpha mask resource is unavailable")
      let maskInfo = host.gpuPresentableResourceInfo(stage.sampledInputValue)
      if maskInfo.kind notin {grkTexture, grkRenderTarget} or
          gtuSampled notin maskInfo.usage or
          maskInfo.format notin {gtfRgba8, gtfBgra8}:
        raise newException(ValueError,
          "GPU filter chain alpha mask must be sampled RGBA8 or BGRA8")
    of gfskComposite:
      if not composite.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain composite material belongs to another host")
      if stage.sampledInputValue.namespace != namespace or
          not host.isGpuResourceLive(stage.sampledInputValue):
        raise newException(ValueError,
          "GPU filter chain foreground resource is unavailable")
      let foregroundInfo = host.gpuPresentableResourceInfo(stage.sampledInputValue)
      if foregroundInfo.kind notin {grkTexture, grkRenderTarget} or
          gtuSampled notin foregroundInfo.usage or
          foregroundInfo.format notin {gtfRgba8, gtfBgra8}:
        raise newException(ValueError,
          "GPU filter chain foreground must be sampled RGBA8 or BGRA8")
    of gfskDisplacement:
      if not displacement.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain displacement material belongs to another host")
      if stage.sampledInputValue.namespace != namespace or
          not host.isGpuResourceLive(stage.sampledInputValue):
        raise newException(ValueError,
          "GPU filter chain displacement map is unavailable")
      let mapInfo = host.gpuPresentableResourceInfo(stage.sampledInputValue)
      if mapInfo.kind notin {grkTexture, grkRenderTarget} or
          gtuSampled notin mapInfo.usage or
          mapInfo.format notin {gtfRgba8, gtfBgra8}:
        raise newException(ValueError,
          "GPU filter chain displacement map must be sampled RGBA8 or BGRA8")
    of gfskMorphology:
      if not morphology.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain morphology material belongs to another host")
  GpuFilterChain(host: host, namespace: namespace, stages: @stages,
    colorMatrix: colorMatrix, gaussianBlur: gaussianBlur,
    dropShadow: dropShadow, alphaMask: alphaMask, composite: composite,
    displacement: displacement, morphology: morphology,
    channelMatrix: channelMatrix)

proc stageCount*(chain: GpuFilterChain): int =
  if chain.isNil: 0 else: chain.stages.len

proc requiredWorkUnits*(chain: GpuFilterChain): uint32 =
  ## One view/work unit per graphics pass, including blur and shadow passes.
  if chain.isNil:
    return 0
  for stage in chain.stages:
    case stage.kindValue
    of gfskGaussianBlur, gfskMorphology:
      result += 2
    of gfskDropShadow:
      result += 3
    else:
      inc result

proc belongsTo*(
    chain: GpuFilterChain; host: GpuHost; namespace: GpuNamespaceId
): bool =
  if chain.isNil or chain.host != host or chain.namespace != namespace or
      host.isNil or not host.isReady():
    return false
  for stage in chain.stages:
    case stage.kindValue
    of gfskColorMatrix, gfskOpacity:
      if not chain.colorMatrix.belongsTo(host, namespace): return false
    of gfskChannelMatrix:
      if not chain.channelMatrix.belongsTo(host, namespace): return false
    of gfskGaussianBlur:
      if not chain.gaussianBlur.belongsTo(host, namespace): return false
    of gfskDropShadow:
      if not chain.dropShadow.belongsTo(host, namespace): return false
    of gfskAlphaMask:
      if not chain.alphaMask.belongsTo(host, namespace) or
          not host.isGpuResourceLive(stage.sampledInputValue): return false
    of gfskComposite:
      if not chain.composite.belongsTo(host, namespace) or
          not host.isGpuResourceLive(stage.sampledInputValue): return false
    of gfskDisplacement:
      if not chain.displacement.belongsTo(host, namespace) or
          not host.isGpuResourceLive(stage.sampledInputValue): return false
    of gfskMorphology:
      if not chain.morphology.belongsTo(host, namespace): return false
  true

proc submit*(
    chain: GpuFilterChain;
    source, destination: GpuResourceHandle;
    scratch: array[3, GpuResourceHandle];
    sourceAlphaMode = gcamStraight
): bool =
  ## Stages are ordered. Output is premultiplied RGBA8. Scratch targets must
  ## be sampled RGBA8 RenderTargets, distinct from source and destination.
  if chain.isNil or chain.host.isNil or not chain.host.isReady():
    raise newException(ValueError, "GPU filter chain host is unavailable")
  if not chain.host.hasActiveGpuFrame():
    raise newException(GpuHostError, "GPU filter chain requires an active frame")
  let resources = [source, destination, scratch[0], scratch[1], scratch[2]]
  for index in 0 ..< resources.len:
    if resources[index].namespace != chain.namespace:
      raise newException(ValueError,
        "GPU filter chain resources must be in one namespace")
    for previous in 0 ..< index:
      if resources[index] == resources[previous]:
        raise newException(ValueError,
          "GPU filter chain resources must be distinct")
  let sourceInfo = chain.host.gpuPresentableResourceInfo(source)
  if sourceInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin sourceInfo.usage or
      sourceInfo.format notin {gtfRgba8, gtfBgra8}:
    raise newException(ValueError,
      "GPU filter chain source must be sampled RGBA8 or BGRA8")
  for target in [destination, scratch[0], scratch[1], scratch[2]]:
    let info = chain.host.gpuPresentableResourceInfo(target)
    if info.kind != grkRenderTarget or
        gtuRenderTarget notin info.usage or
        gtuSampled notin info.usage or
        info.format != gtfRgba8 or
        info.width != sourceInfo.width or
        info.height != sourceInfo.height:
      raise newException(ValueError,
        "GPU filter chain targets must be sampled RGBA8 render targets of source size")
    if chain.host.isGpuResourcePresentationRetained(target):
      raise newException(GpuHostError,
        "GPU filter chain cannot overwrite a presentation-retained target")
  for stage in chain.stages:
    case stage.kindValue
    of gfskColorMatrix, gfskOpacity:
      if not chain.colorMatrix.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain color matrix material is closed")
    of gfskChannelMatrix:
      if not chain.channelMatrix.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError,
          "GPU filter chain channel matrix material is closed")
    of gfskGaussianBlur:
      if not chain.gaussianBlur.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain blur material is closed")
    of gfskDropShadow:
      if not chain.dropShadow.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain shadow material is closed")
    of gfskAlphaMask:
      if not chain.alphaMask.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain alpha mask material is closed")
      if stage.sampledInputValue.namespace != chain.namespace or
          stage.sampledInputValue in [destination, scratch[0], scratch[1], scratch[2]]:
        raise newException(ValueError,
          "GPU filter chain mask must not alias a writable target")
      let maskInfo = chain.host.gpuPresentableResourceInfo(stage.sampledInputValue)
      if maskInfo.kind notin {grkTexture, grkRenderTarget} or
          gtuSampled notin maskInfo.usage or
          maskInfo.format notin {gtfRgba8, gtfBgra8} or
          (not stage.maskPlacementValue.isGpuPlacementActive and
            not stage.maskCropValue.isGpuCropActive and
            (maskInfo.width != sourceInfo.width or
              maskInfo.height != sourceInfo.height)):
        raise newException(ValueError,
          "GPU filter chain mask must be a sampled RGBA8 or BGRA8 source of matching size")
      discard stage.maskCropValue.sampledGpuCropUv(
        maskInfo.width, maskInfo.height, maskInfo.rowsBottomUp)
    of gfskComposite:
      if not chain.composite.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain composite material is closed")
      if stage.sampledInputValue.namespace != chain.namespace or
          stage.sampledInputValue in [destination, scratch[0], scratch[1], scratch[2]]:
        raise newException(ValueError,
          "GPU filter chain foreground must not alias a writable target")
      let foregroundInfo = chain.host.gpuPresentableResourceInfo(stage.sampledInputValue)
      if foregroundInfo.kind notin {grkTexture, grkRenderTarget} or
          gtuSampled notin foregroundInfo.usage or
          foregroundInfo.format notin {gtfRgba8, gtfBgra8} or
          (not stage.foregroundPlacementValue.isPlaced and
            not stage.foregroundCropValue.isGpuCropActive and
            (foregroundInfo.width != sourceInfo.width or
              foregroundInfo.height != sourceInfo.height)):
        raise newException(ValueError,
          "GPU filter chain foreground must be a sampled RGBA8 or BGRA8 source of matching size")
      discard stage.foregroundCropValue.sampledGpuCropUv(
        foregroundInfo.width, foregroundInfo.height,
        foregroundInfo.rowsBottomUp)
    of gfskDisplacement:
      if not chain.displacement.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError,
          "GPU filter chain displacement material is closed")
      if stage.sampledInputValue.namespace != chain.namespace or
          stage.sampledInputValue in [destination, scratch[0], scratch[1], scratch[2]]:
        raise newException(ValueError,
          "GPU filter chain displacement map must not alias a writable target")
      let mapInfo = chain.host.gpuPresentableResourceInfo(stage.sampledInputValue)
      if mapInfo.kind notin {grkTexture, grkRenderTarget} or
          gtuSampled notin mapInfo.usage or
          mapInfo.format notin {gtfRgba8, gtfBgra8} or
          mapInfo.width != sourceInfo.width or
          mapInfo.height != sourceInfo.height:
        raise newException(ValueError,
          "GPU filter chain displacement map must match the source size")
    of gfskMorphology:
      if not chain.morphology.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError,
          "GPU filter chain morphology material is closed")
  let workUnits = chain.requiredWorkUnits()
  chain.host.validateGpuFrameWork(chain.namespace, workUnits = workUnits)
  chain.host.validateGpuViewCapacity(int(workUnits))
  var current = source
  var alphaMode = sourceAlphaMode
  for index, stage in chain.stages:
    let isLast = index == chain.stages.high
    let output =
      if isLast: destination
      elif current == scratch[0]: scratch[1]
      else: scratch[0]
    case stage.kindValue
    of gfskColorMatrix:
      discard chain.colorMatrix.submit(current, output,
        stage.matrixValue, alphaMode)
    of gfskChannelMatrix:
      discard chain.channelMatrix.submit(current, output,
        stage.channelMatrixValue, alphaMode)
    of gfskOpacity:
      discard chain.colorMatrix.submit(current, output,
        nil, alphaMode, stage.opacityValue)
    of gfskGaussianBlur:
      discard chain.gaussianBlur.submit(current, scratch[2],
        output, alphaMode, stage.blurRadiusValue)
    of gfskDropShadow:
      # A non-final shadow uses destination as its blurred-alpha temporary.
      # The final stage uses the ping-pong target it does not read or write.
      let blurred =
        if not isLast: destination
        elif current == scratch[0]: scratch[1]
        else: scratch[0]
      discard chain.dropShadow.submit(current, scratch[2], blurred,
        output, stage.offsetXValue, stage.offsetYValue,
        stage.colorValue, alphaMode, stage.blurRadiusValue)
    of gfskAlphaMask:
      discard chain.alphaMask.submit(current, stage.sampledInputValue,
        output, alphaMode, stage.invertMaskValue, stage.maskStrengthValue,
        stage.maskPlacementValue, stage.maskCropValue,
        stage.maskModeValue, stage.maskAlphaModeValue)
    of gfskComposite:
      discard chain.composite.submit(current, stage.sampledInputValue,
        output, alphaMode, stage.foregroundAlphaModeValue,
        stage.blendModeValue, stage.foregroundOpacityValue,
        stage.foregroundPlacementValue, stage.foregroundCropValue)
    of gfskDisplacement:
      discard chain.displacement.submit(current, stage.sampledInputValue,
        output, stage.displacementScaleXValue,
        stage.displacementScaleYValue, alphaMode)
    of gfskMorphology:
      discard chain.morphology.submit(current, scratch[2], output,
        alphaMode, stage.morphologyModeValue,
        stage.morphologyRadiusValue)
    current = output
    alphaMode = gcamPremultiplied
  true
