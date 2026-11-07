## Same-host source-over composition of two sampled GPU surfaces.
## The output is premultiplied RGBA8.
import std/math

import ../paint/gpu_host_compositor
import ./[gpu_host, gpu_shader_builder]

type
  GpuCompositeBlendMode* = enum
    gcbmNormal,
    gcbmMultiply,
    gcbmScreen,
    gcbmOverlay,
    gcbmDarken,
    gcbmLighten,
    gcbmDifference,
    gcbmExclusion,
    gcbmColorDodge,
    gcbmColorBurn,
    gcbmHardLight,
    gcbmSoftLight,
    gcbmHue,
    gcbmSaturation,
    gcbmColor,
    gcbmLuminosity

  GpuCompositePlacement* = object
    enabled: bool
    x, y: int32
    width, height: uint32

  GpuCompositeVertex = object
    x, y, z: float32
    u, v: float32

  GpuCompositeMaterial* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    vertexShader, fragmentShader: GpuResourceHandle
    pipeline, vertexBuffer: GpuResourceHandle
    paramsUniform, backdropUvUniform, foregroundUvUniform: GpuResourceHandle
    foregroundPlacementUniform: GpuResourceHandle
    backdropSampler, foregroundSampler: GpuResourceHandle

proc gpuCompositePlacement*(
    x, y: int32; width, height: uint32
): GpuCompositePlacement =
  ## Pixel bounds in the destination, measured from its top-left corner.
  if width == 0 or height == 0:
    raise newException(ValueError,
      "GPU composite foreground placement must have positive dimensions")
  GpuCompositePlacement(enabled: true, x: x, y: y,
    width: width, height: height)

proc isPlaced*(placement: GpuCompositePlacement): bool =
  placement.enabled

proc gpuCompositeVertexSource*(): GpuShaderSource =
  gpuHostDirectCompositeVertexSource()

proc gpuCompositeFragmentSource*(): GpuShaderSource =
  GpuShaderSource(
    stage: gssFragment,
    label: "cbss-gpu-composite-fragment",
    source: """$input v_texcoord0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssBackdrop, 0);
SAMPLER2D(s_cbssForeground, 1);
uniform vec4 u_cbssCompositeParams;
uniform vec4 u_cbssBackdropUv;
uniform vec4 u_cbssForegroundUv;
uniform vec4 u_cbssForegroundPlacement;
float cbssColorDodge(float backdrop, float foreground)
{
  if (backdrop <= 0.0) return 0.0;
  if (foreground >= 1.0) return 1.0;
  return min(1.0, backdrop / (1.0 - foreground));
}
float cbssColorBurn(float backdrop, float foreground)
{
  if (backdrop >= 1.0) return 1.0;
  if (foreground <= 0.0) return 0.0;
  return 1.0 - min(1.0, (1.0 - backdrop) / foreground);
}
float cbssHardLight(float backdrop, float foreground)
{
  if (foreground <= 0.5) return 2.0 * backdrop * foreground;
  return 1.0 - 2.0 * (1.0 - backdrop) * (1.0 - foreground);
}
float cbssSoftLight(float backdrop, float foreground)
{
  if (foreground <= 0.5) {
    return backdrop - (1.0 - 2.0 * foreground) *
      backdrop * (1.0 - backdrop);
  }
  float d = backdrop <= 0.25 ?
    ((16.0 * backdrop - 12.0) * backdrop + 4.0) * backdrop :
    sqrt(backdrop);
  return backdrop + (2.0 * foreground - 1.0) * (d - backdrop);
}
float cbssLum(vec3 color)
{
  return dot(color, vec3(0.3, 0.59, 0.11));
}
float cbssSat(vec3 color)
{
  return max(color.r, max(color.g, color.b)) -
    min(color.r, min(color.g, color.b));
}
vec3 cbssClipColor(vec3 color)
{
  float lum = cbssLum(color);
  float low = min(color.r, min(color.g, color.b));
  float high = max(color.r, max(color.g, color.b));
  if (low < 0.0) {
    color = vec3(lum) + (color - vec3(lum)) *
      (lum / (lum - low));
  }
  if (high > 1.0) {
    color = vec3(lum) + (color - vec3(lum)) *
      ((1.0 - lum) / (high - lum));
  }
  return clamp(color, vec3(0.0), vec3(1.0));
}
vec3 cbssSetLum(vec3 color, float lum)
{
  return cbssClipColor(color + vec3(lum - cbssLum(color)));
}
vec3 cbssSetSat(vec3 color, float sat)
{
  float low = min(color.r, min(color.g, color.b));
  float high = max(color.r, max(color.g, color.b));
  if (high <= low) return vec3(0.0);
  return (color - vec3(low)) * (sat / (high - low));
}
void main()
{
  vec2 backdropUv = mix(u_cbssBackdropUv.xy,
    u_cbssBackdropUv.zw, v_texcoord0);
  vec4 backdrop = texture2D(s_cbssBackdrop, backdropUv);
  vec2 localForeground = (v_texcoord0 - u_cbssForegroundPlacement.xy) /
    u_cbssForegroundPlacement.zw;
  vec4 foreground = vec4(0.0);
  float foregroundCoverage = 0.0;
  if (localForeground.x >= 0.0 && localForeground.y >= 0.0 &&
      localForeground.x < 1.0 && localForeground.y < 1.0) {
    vec2 foregroundUv = mix(u_cbssForegroundUv.xy,
      u_cbssForegroundUv.zw, localForeground);
    foreground = texture2D(s_cbssForeground, foregroundUv);
    foregroundCoverage = 1.0;
  }
  if (u_cbssCompositeParams.x > 1.5) {
    backdrop.a = 1.0;
  } else if (u_cbssCompositeParams.x < 0.5) {
    backdrop.rgb *= backdrop.a;
  }
  if (u_cbssCompositeParams.y > 1.5) {
    foreground.a = 1.0;
  } else if (u_cbssCompositeParams.y < 0.5) {
    foreground.rgb *= foreground.a;
  }
  foreground *= foregroundCoverage * u_cbssCompositeParams.w;
  vec3 rgb;
  if (u_cbssCompositeParams.z > 7.5) {
    vec3 backdropColor = vec3(0.0);
    vec3 foregroundColor = vec3(0.0);
    if (backdrop.a > 0.0) backdropColor = backdrop.rgb / backdrop.a;
    if (foreground.a > 0.0) foregroundColor = foreground.rgb / foreground.a;
    vec3 blended;
    if (u_cbssCompositeParams.z > 14.5) {
      blended = cbssSetLum(backdropColor, cbssLum(foregroundColor));
    } else if (u_cbssCompositeParams.z > 13.5) {
      blended = cbssSetLum(foregroundColor, cbssLum(backdropColor));
    } else if (u_cbssCompositeParams.z > 12.5) {
      blended = cbssSetLum(
        cbssSetSat(backdropColor, cbssSat(foregroundColor)),
        cbssLum(backdropColor));
    } else if (u_cbssCompositeParams.z > 11.5) {
      blended = cbssSetLum(
        cbssSetSat(foregroundColor, cbssSat(backdropColor)),
        cbssLum(backdropColor));
    } else if (u_cbssCompositeParams.z > 10.5) {
      blended = vec3(
        cbssSoftLight(backdropColor.r, foregroundColor.r),
        cbssSoftLight(backdropColor.g, foregroundColor.g),
        cbssSoftLight(backdropColor.b, foregroundColor.b));
    } else if (u_cbssCompositeParams.z > 9.5) {
      blended = vec3(
        cbssHardLight(backdropColor.r, foregroundColor.r),
        cbssHardLight(backdropColor.g, foregroundColor.g),
        cbssHardLight(backdropColor.b, foregroundColor.b));
    } else if (u_cbssCompositeParams.z > 8.5) {
      blended = vec3(
        cbssColorBurn(backdropColor.r, foregroundColor.r),
        cbssColorBurn(backdropColor.g, foregroundColor.g),
        cbssColorBurn(backdropColor.b, foregroundColor.b));
    } else {
      blended = vec3(
        cbssColorDodge(backdropColor.r, foregroundColor.r),
        cbssColorDodge(backdropColor.g, foregroundColor.g),
        cbssColorDodge(backdropColor.b, foregroundColor.b));
    }
    rgb = foreground.rgb * (1.0 - backdrop.a) +
      backdrop.rgb * (1.0 - foreground.a) +
      blended * (backdrop.a * foreground.a);
  } else if (u_cbssCompositeParams.z > 6.5) {
    rgb = foreground.rgb + backdrop.rgb -
      2.0 * foreground.rgb * backdrop.rgb;
  } else if (u_cbssCompositeParams.z > 5.5) {
    rgb = foreground.rgb * (1.0 - backdrop.a) +
      backdrop.rgb * (1.0 - foreground.a) +
      abs(backdrop.rgb * foreground.a - foreground.rgb * backdrop.a);
  } else if (u_cbssCompositeParams.z > 4.5) {
    rgb = foreground.rgb * (1.0 - backdrop.a) +
      backdrop.rgb * (1.0 - foreground.a) +
      max(backdrop.rgb * foreground.a, foreground.rgb * backdrop.a);
  } else if (u_cbssCompositeParams.z > 3.5) {
    rgb = foreground.rgb * (1.0 - backdrop.a) +
      backdrop.rgb * (1.0 - foreground.a) +
      min(backdrop.rgb * foreground.a, foreground.rgb * backdrop.a);
  } else if (u_cbssCompositeParams.z > 2.5) {
    vec3 low = 2.0 * backdrop.rgb * foreground.rgb;
    vec3 high = vec3(backdrop.a * foreground.a) -
      2.0 * (vec3(backdrop.a) - backdrop.rgb) *
      (vec3(foreground.a) - foreground.rgb);
    vec3 overlap = mix(low, high,
      step(vec3(backdrop.a * 0.5), backdrop.rgb));
    rgb = foreground.rgb * (1.0 - backdrop.a) +
      backdrop.rgb * (1.0 - foreground.a) + overlap;
  } else if (u_cbssCompositeParams.z > 1.5) {
    rgb = foreground.rgb + backdrop.rgb -
      foreground.rgb * backdrop.rgb;
  } else if (u_cbssCompositeParams.z > 0.5) {
    rgb = foreground.rgb * (1.0 - backdrop.a) +
      backdrop.rgb * (1.0 - foreground.a) +
      foreground.rgb * backdrop.rgb;
  } else {
    rgb = foreground.rgb + backdrop.rgb * (1.0 - foreground.a);
  }
  float alpha = foreground.a + backdrop.a * (1.0 - foreground.a);
  gl_FragColor = vec4(rgb, alpha);
}
""",
    varyingDefinitions: gpuHostDirectCompositeVaryingDefinitions,
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2)
    ]
  )

proc isClosed*(material: GpuCompositeMaterial): bool =
  material.isNil or material.host.isNil

proc belongsTo*(
    material: GpuCompositeMaterial; host: GpuHost; namespace: GpuNamespaceId
): bool =
  not material.isClosed and material.host == host and
    material.namespace == namespace

proc release*(material: GpuCompositeMaterial) =
  ## Release after the final submitted frame while the host is still open.
  if material.isClosed:
    return
  for handle in [material.foregroundSampler, material.backdropSampler,
      material.foregroundPlacementUniform, material.foregroundUvUniform,
      material.backdropUvUniform,
      material.paramsUniform, material.vertexBuffer, material.pipeline,
      material.fragmentShader, material.vertexShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuCompositeMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuCompositeMaterial =
  if host.isNil or not host.isReady():
    raise newException(ValueError, "GPU composite material requires a ready host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuCompositeVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuCompositeFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError,
      "GPU composite shader artifacts do not match the built-in shaders")
  result = GpuCompositeMaterial(host: host, namespace: namespace)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3,
      componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2,
      componentType: gvctFloat)
  ]
  let vertices = [
    GpuCompositeVertex(x: -1, y: -1, u: 0, v: 1),
    GpuCompositeVertex(x: -1, y: 1, u: 0, v: 0),
    GpuCompositeVertex(x: 1, y: -1, u: 1, v: 1),
    GpuCompositeVertex(x: 1, y: 1, u: 1, v: 0)
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
        label: "gpu-composite-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(vertexBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "gpu-composite-quad"), vertexBytes)
    result.paramsUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssCompositeParams", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-composite-params"))
    result.backdropUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssBackdropUv", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-composite-backdrop-uv"))
    result.foregroundUvUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssForegroundUv", uniformType: gutVec4,
        arrayLength: 1, label: "gpu-composite-foreground-uv"))
    result.foregroundPlacementUniform = host.createGpuUniform(namespace,
      GpuUniformDescriptor(name: "u_cbssForegroundPlacement",
        uniformType: gutVec4, arrayLength: 1,
        label: "gpu-composite-foreground-placement"))
    result.backdropSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssBackdrop",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-composite-backdrop-sampler"))
    result.foregroundSampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssForeground",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "gpu-composite-foreground-sampler"))
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuCompositeMaterial;
    backdrop, foreground, destination: GpuResourceHandle;
    backdropAlphaMode = gcamStraight;
    foregroundAlphaMode = gcamStraight;
    blendMode = gcbmNormal;
    foregroundOpacity = 1'f32;
    foregroundPlacement = GpuCompositePlacement()
): bool =
  ## Foreground is placed over backdrop. Both inputs may share one resource.
  if material.isClosed:
    raise newException(ValueError, "GPU composite material is closed")
  if foregroundOpacity.classify in {fcNan, fcInf, fcNegInf} or
      foregroundOpacity < 0 or foregroundOpacity > 1:
    raise newException(ValueError,
      "GPU composite foreground opacity must be finite and normalized")
  let host = material.host
  if not host.hasActiveGpuFrame():
    raise newException(GpuHostError, "GPU composite requires an active frame")
  if backdrop.namespace != material.namespace or
      foreground.namespace != material.namespace or
      destination.namespace != material.namespace or
      backdrop == destination or foreground == destination:
    raise newException(ValueError,
      "GPU composite resources must be in one namespace without target feedback")
  let backdropInfo = host.gpuPresentableResourceInfo(backdrop)
  let foregroundInfo = host.gpuPresentableResourceInfo(foreground)
  let targetInfo = host.gpuPresentableResourceInfo(destination)
  if backdropInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin backdropInfo.usage or
      backdropInfo.format notin {gtfRgba8, gtfBgra8} or
      foregroundInfo.kind notin {grkTexture, grkRenderTarget} or
      gtuSampled notin foregroundInfo.usage or
      foregroundInfo.format notin {gtfRgba8, gtfBgra8} or
      targetInfo.kind != grkRenderTarget or
      gtuRenderTarget notin targetInfo.usage or
      targetInfo.format != gtfRgba8 or
      backdropInfo.width != targetInfo.width or
      backdropInfo.height != targetInfo.height or
      (not foregroundPlacement.isPlaced and
        (foregroundInfo.width != targetInfo.width or
          foregroundInfo.height != targetInfo.height)):
    raise newException(ValueError, "GPU composite resource shapes are incompatible")
  if host.isGpuResourcePresentationRetained(destination):
    raise newException(GpuHostError,
      "GPU composite cannot overwrite a presentation-retained target")
  let backdropUv =
    if backdropInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
  let foregroundUv =
    if foregroundInfo.rowsBottomUp: @[0'f32, 1, 1, 0]
    else: @[0'f32, 0, 1, 1]
  let placement =
    if foregroundPlacement.isPlaced:
      @[float32(foregroundPlacement.x) / float32(targetInfo.width),
        float32(foregroundPlacement.y) / float32(targetInfo.height),
        float32(foregroundPlacement.width) / float32(targetInfo.width),
        float32(foregroundPlacement.height) / float32(targetInfo.height)]
    else:
      @[0'f32, 0, 1, 1]
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
            values: @[float32(ord(backdropAlphaMode)),
              float32(ord(foregroundAlphaMode)),
              float32(ord(blendMode)), foregroundOpacity]),
          GpuUniformBinding(uniform: material.backdropUvUniform,
            values: backdropUv),
          GpuUniformBinding(uniform: material.foregroundUvUniform,
            values: foregroundUv),
          GpuUniformBinding(uniform: material.foregroundPlacementUniform,
            values: placement)
        ],
        textures: @[
          GpuTextureBinding(stage: 0, sampler: material.backdropSampler,
            texture: backdrop),
          GpuTextureBinding(stage: 1, sampler: material.foregroundSampler,
            texture: foreground)
        ]
      )
    ))
  true
