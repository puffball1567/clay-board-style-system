## Ordered same-host postprocess for GPU-owned surfaces.
## The caller owns materials and four reusable RGBA8 render targets.
import std/math

import ../core/color
import ../paint/layer_color_filter
import ./[gpu_color_matrix, gpu_gaussian_blur, gpu_drop_shadow, gpu_host]

const MaxGpuFilterStages* = 8

type
  GpuFilterStageKind* = enum
    gfskColorMatrix,
    gfskGaussianBlur,
    gfskDropShadow

  GpuFilterStage* = object
    kindValue: GpuFilterStageKind
    matrixValue: LayerColorFilter
    offsetXValue, offsetYValue: float32
    colorValue: Color
    blurRadiusValue: int

  GpuFilterChain* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    stages: seq[GpuFilterStage]
    colorMatrix: GpuColorMatrixMaterial
    gaussianBlur: GpuGaussianBlurMaterial
    dropShadow: GpuDropShadowMaterial

proc colorMatrixStage*(filter: LayerColorFilter): GpuFilterStage =
  GpuFilterStage(kindValue: gfskColorMatrix, matrixValue: filter)

proc gaussianBlurStage*(radius = 2): GpuFilterStage =
  if radius < 0 or radius > MaxGpuBlurRadius:
    raise newException(ValueError, "GPU filter blur radius must be between 0 and 4")
  GpuFilterStage(kindValue: gfskGaussianBlur, blurRadiusValue: radius)

proc dropShadowStage*(
    offsetX, offsetY: float32; color: Color; blurRadius = 2
): GpuFilterStage =
  if blurRadius < 0 or blurRadius > MaxGpuBlurRadius:
    raise newException(ValueError,
      "GPU filter shadow blur radius must be between 0 and 4")
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
    dropShadow: GpuDropShadowMaterial = nil
): GpuFilterChain =
  if host.isNil or not host.isReady() or not host.hasGpuNamespace(namespace):
    raise newException(ValueError, "GPU filter chain requires a ready host namespace")
  if stages.len == 0 or stages.len > MaxGpuFilterStages:
    raise newException(ValueError, "GPU filter chain stage count is invalid")
  for stage in stages:
    case stage.kindValue
    of gfskColorMatrix:
      if not colorMatrix.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain color matrix material belongs to another host")
    of gfskGaussianBlur:
      if not gaussianBlur.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain blur material belongs to another host")
    of gfskDropShadow:
      if not dropShadow.belongsTo(host, namespace):
        raise newException(ValueError,
          "GPU filter chain shadow material belongs to another host")
  GpuFilterChain(host: host, namespace: namespace, stages: @stages,
    colorMatrix: colorMatrix, gaussianBlur: gaussianBlur,
    dropShadow: dropShadow)

proc stageCount*(chain: GpuFilterChain): int =
  if chain.isNil: 0 else: chain.stages.len

proc belongsTo*(
    chain: GpuFilterChain; host: GpuHost; namespace: GpuNamespaceId
): bool =
  if chain.isNil or chain.host != host or chain.namespace != namespace or
      host.isNil or not host.isReady():
    return false
  for stage in chain.stages:
    case stage.kindValue
    of gfskColorMatrix:
      if not chain.colorMatrix.belongsTo(host, namespace): return false
    of gfskGaussianBlur:
      if not chain.gaussianBlur.belongsTo(host, namespace): return false
    of gfskDropShadow:
      if not chain.dropShadow.belongsTo(host, namespace): return false
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
    of gfskColorMatrix:
      if not chain.colorMatrix.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain color matrix material is closed")
    of gfskGaussianBlur:
      if not chain.gaussianBlur.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain blur material is closed")
    of gfskDropShadow:
      if not chain.dropShadow.belongsTo(chain.host, chain.namespace):
        raise newException(ValueError, "GPU filter chain shadow material is closed")
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
    current = output
    alphaMode = gcamPremultiplied
  true
