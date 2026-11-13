## Bounded GPU instance encoding for the CPU Motion Scene reference snapshot.
## Import explicitly; ordinary UI and headless Motion Scene builds stay CPU-only.
import std/[math, options]

import ../core/geometry
import ./[gpu_host, gpu_shader_builder, motion_scene]

const gpuMotionRectVec4Count* = 5'u8

type GpuMotionRectRecord* = array[5, array[4, float32]]

type GpuMotionDrawRun = object
  first, count: uint32
  image: MotionImageAsset

type GpuMotionRectBatch* = ref object
  ## Owns one dynamic instance buffer and the last successfully uploaded frame.
  host: GpuHost
  namespace: GpuNamespaceId
  scene: MotionScene
  revision: uint64
  buffer: GpuResourceHandle
  capacity: int
  records: seq[GpuMotionRectRecord]
  runs: seq[GpuMotionDrawRun]
  imageAssets: seq[MotionImageAsset]
  imageTextures: seq[GpuResourceHandle]

type GpuMotionRectMaterial* = ref object
  ## Owns the built-in shape shaders, instanced pipeline, and unit quad.
  host: GpuHost
  namespace: GpuNamespaceId
  vertexShader, fragmentShader: GpuResourceHandle
  pipeline, vertexBuffer: GpuResourceHandle

type GpuMotionImageMaterial* = ref object
  host: GpuHost
  namespace: GpuNamespaceId
  vertexShader, fragmentShader: GpuResourceHandle
  pipeline, vertexBuffer, sampler: GpuResourceHandle

static:
  doAssert sizeof(GpuMotionRectRecord) == 80

proc gpuMotionRectRecords*(snapshot: MotionSceneSnapshot): seq[GpuMotionRectRecord] =
  ## Packs drawable shapes in CPU paint order. The five vec4 rows
  ## match gpuMotionRectVertexSource and one host instanced draw.
  if snapshot.isNil:
    raise newException(ValueError, "motion scene snapshot must not be nil")
  let viewport = snapshot.viewportSize()
  let inverseWidth = 1'f32 / viewport.w
  let inverseHeight = 1'f32 / viewport.h
  if inverseWidth.classify in {fcNan, fcInf, fcNegInf} or
      inverseHeight.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "motion scene GPU viewport scale is not finite")
  for index in 0 ..< snapshot.objectCount():
    let candidate = snapshot.paintObjectAt(index)
    if candidate.isNone:
      continue
    let item = candidate.get
    let origin = item.transform.transformPoint(
      vec2(item.bounds.x, item.bounds.y)
    )
    result.add [
      [item.transform.m11, item.transform.m21, origin.x, item.sweepAngle],
      [item.transform.m12, item.transform.m22, origin.y,
        (if item.shape == msAnnularSector: item.radius else: 0'f32)],
      [item.bounds.w, item.bounds.h,
        (if item.shape in {msSector, msAnnularSector}:
          item.startAngle else: item.radius),
        (if item.shape == msEllipse: 1'f32
         elif item.shape == msTriangle: 2'f32
         elif item.shape == msRing: 3'f32
         elif item.shape == msSector: 4'f32
         elif item.shape == msAnnularSector: 5'f32
         elif item.shape == msImage: 6'f32
         else: 0'f32)],
      [item.color.r, item.color.g, item.color.b,
        item.color.a * item.opacity],
      [inverseWidth, inverseHeight, 0'f32, 0'f32]
    ]

proc gpuMotionRectBytes*(records: openArray[GpuMotionRectRecord]): seq[byte] =
  ## Native float32 bytes for a static or dynamic GpuHost instance buffer.
  if records.len > maxMotionSceneObjects:
    raise newException(ValueError, "motion scene GPU instance limit exceeded")
  result = newSeq[byte](records.len * sizeof(GpuMotionRectRecord))
  if result.len > 0:
    copyMem(addr result[0], unsafeAddr records[0], result.len)

proc newGpuMotionRectBatch*(): GpuMotionRectBatch =
  GpuMotionRectBatch()

proc instanceBinding*(batch: GpuMotionRectBatch): GpuInstanceBinding =
  ## Submit only when instanceCount is nonzero.
  if batch.isNil:
    raise newException(ValueError, "motion scene GPU batch must not be nil")
  GpuInstanceBinding(buffer: batch.buffer,
    instanceCount: uint32(batch.records.len))

proc release*(batch: GpuMotionRectBatch) =
  ## Release before discarding a batch or moving it to another host/namespace.
  if batch.isNil:
    return
  if not batch.host.isNil and batch.capacity > 0 and
      batch.host.isGpuResourceLive(batch.buffer):
    discard batch.host.releaseGpuResource(batch.buffer)
  if not batch.host.isNil:
    for texture in batch.imageTextures:
      if batch.host.isGpuResourceLive(texture):
        discard batch.host.releaseGpuResource(texture)
  batch.host = nil
  batch.namespace = GpuNamespaceId(0)
  batch.scene = nil
  batch.revision = 0
  batch.buffer = GpuResourceHandle()
  batch.capacity = 0
  batch.records.setLen(0)
  batch.runs.setLen(0)
  batch.imageAssets.setLen(0)
  batch.imageTextures.setLen(0)

proc sync*(
    batch: GpuMotionRectBatch; host: GpuHost;
    namespace: GpuNamespaceId; scene: MotionScene
): bool =
  ## Upload before beginning a GPU frame. Returns true when drawable records
  ## or their count changed.
  ## A failed update leaves the prior CPU record cache intact for a retry.
  if batch.isNil or host.isNil or scene.isNil:
    raise newException(ValueError, "motion scene GPU sync requires a batch, host, and scene")
  if not batch.host.isNil and
      (batch.host != host or batch.namespace != namespace):
    raise newException(ValueError,
      "release the motion scene GPU batch before changing host or namespace")
  let live = batch.capacity > 0 and host.isGpuResourceLive(batch.buffer)
  var texturesLive = true
  for texture in batch.imageTextures:
    if not host.isGpuResourceLive(texture):
      texturesLive = false
  if live and texturesLive and batch.scene == scene and batch.revision == scene.revision:
    return false
  let next = gpuMotionRectRecords(scene.snapshot)
  var nextRuns: seq[GpuMotionDrawRun]
  var nextAssets: seq[MotionImageAsset]
  var nextTextures: seq[GpuResourceHandle]
  var recordIndex = 0'u32
  for index in 0 ..< scene.snapshot.objectCount():
    let candidate = scene.snapshot.paintObjectAt(index)
    if candidate.isNone:
      continue
    let item = candidate.get
    let image = if item.shape == msImage: item.image else: nil
    if image != nil and image notin nextAssets:
      if nextAssets.len >= 64:
        raise newException(ValueError, "motion scene GPU image asset limit exceeded")
      nextAssets.add image
    if nextRuns.len > 0 and nextRuns[^1].image == image:
      inc nextRuns[^1].count
    else:
      nextRuns.add GpuMotionDrawRun(first: recordIndex,
        count: 1, image: image)
    inc recordIndex
  var created: seq[GpuResourceHandle]
  try:
    for asset in nextAssets:
      var reused = false
      for index, previous in batch.imageAssets:
        if previous == asset and host.isGpuResourceLive(batch.imageTextures[index]):
          nextTextures.add batch.imageTextures[index]
          reused = true
          break
      if not reused:
        let texture = host.createGpuTexture(namespace,
          GpuTextureDescriptor(width: uint32(asset.width),
            height: uint32(asset.height), format: gtfRgba8,
            usage: {gtuSampled}, access: gtaStatic,
            label: "motion-scene-image"), asset.imagePixels())
        nextTextures.add texture
        created.add texture
  except CatchableError:
    for texture in created:
      discard host.releaseGpuResource(texture)
    raise
  result = next.len != batch.records.len or
    nextAssets != batch.imageAssets or not texturesLive
  try:
    if next.len > batch.capacity or (next.len > 0 and not live):
      let replacement = host.createGpuBuffer(namespace,
      gpuInstanceBufferDescriptor(gpuMotionRectVec4Count,
        uint32(next.len), gbaDynamic, "motion-scene-rects"),
      gpuMotionRectBytes(next))
      if live:
        try:
          discard host.releaseGpuResource(batch.buffer)
        except:
          discard host.releaseGpuResource(replacement)
          raise
      batch.buffer = replacement
      batch.capacity = next.len
      result = true
    elif live:
      var index = 0
      while index < next.len:
        if index < batch.records.len and next[index] == batch.records[index]:
          inc index
          continue
        let first = index
        while index < next.len and
            (index >= batch.records.len or next[index] != batch.records[index]):
          inc index
        host.updateGpuBuffer(batch.buffer,
          uint64(first * sizeof(GpuMotionRectRecord)),
          gpuMotionRectBytes(next.toOpenArray(first, index - 1)))
        result = true
  except CatchableError:
    for texture in created:
      discard host.releaseGpuResource(texture)
    raise
  for texture in batch.imageTextures:
    if texture notin nextTextures and host.isGpuResourceLive(texture):
      discard host.releaseGpuResource(texture)
  batch.host = host
  batch.namespace = namespace
  batch.scene = scene
  batch.revision = scene.revision
  batch.records = next
  batch.runs = nextRuns
  batch.imageAssets = nextAssets
  batch.imageTextures = nextTextures

proc gpuMotionRectVertexSource*(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssVertex, "motion-scene-rect-vertex")
  let corner = builder.vertexInput(gsisPosition, gsvtVec2)
  let rowX = builder.vertexInput(gsisInstance0, gsvtVec4)
  let rowY = builder.vertexInput(gsisInstance1, gsvtVec4)
  let shape = builder.vertexInput(gsisInstance2, gsvtVec4)
  let color = builder.vertexInput(gsisInstance3, gsvtVec4)
  let viewport = builder.vertexInput(gsisInstance4, gsvtVec4)
  let point = corner * builder.swizzle(shape, "xy")
  let local = builder.construct(gsvtVec4, [
    builder.swizzle(point, "x"), builder.swizzle(point, "y"),
    builder.scalar(1), builder.scalar(0)
  ])
  let x = builder.binary(gsbDot, rowX, local) *
    builder.swizzle(viewport, "x") * builder.scalar(2) - builder.scalar(1)
  let y = builder.scalar(1) - builder.binary(gsbDot, rowY, local) *
    builder.swizzle(viewport, "y") * builder.scalar(2)
  builder.setPositionOutput(builder.construct(gsvtVec4, [
    x, y, builder.scalar(0), builder.scalar(1)
  ]))
  builder.setVaryingOutput(gsisTexCoord0, point)
  builder.setVaryingOutput(gsisTexCoord1, shape)
  builder.setVaryingOutput(gsisTexCoord2, builder.construct(gsvtVec2, [
    builder.swizzle(rowX, "w"), builder.swizzle(rowY, "w")
  ]))
  builder.setVaryingOutput(gsisColor0, color)
  builder.emitGpuShaderSource()

proc gpuMotionRectFragmentSource*(): GpuShaderSource =
  GpuShaderSource(stage: gssFragment, label: "motion-scene-rect-fragment",
    source: """$input v_texcoord0, v_texcoord1, v_texcoord2, v_color0
#include "bgfx_shader.sh"
void main()
{
  vec2 halfSize = v_texcoord1.xy * 0.5;
  if (v_texcoord1.w > 3.5) {
    vec2 normalized = (v_texcoord0 - halfSize) / halfSize;
    float distanceSquared = dot(normalized, normalized);
    if (distanceSquared > 1.0 ||
        (v_texcoord1.w > 4.5 &&
         distanceSquared < v_texcoord2.y * v_texcoord2.y)) { discard; }
    if (distanceSquared > 0.0 && v_texcoord2.x < 6.2831855) {
      float delta = atan(normalized.y, normalized.x) - v_texcoord1.z;
      float relative = delta - floor(delta / 6.2831855) * 6.2831855;
      if (relative > v_texcoord2.x) { discard; }
    }
  } else if (v_texcoord1.w > 2.5) {
    vec2 normalized = (v_texcoord0 - halfSize) / halfSize;
    float distanceSquared = dot(normalized, normalized);
    if (distanceSquared > 1.0 ||
        distanceSquared < v_texcoord1.z * v_texcoord1.z) { discard; }
  } else if (v_texcoord1.w > 1.5) {
    vec2 normalized = v_texcoord0 / v_texcoord1.xy;
    if (normalized.x + normalized.y > 1.0) { discard; }
  } else if (v_texcoord1.w > 0.5) {
    vec2 normalized = (v_texcoord0 - halfSize) / halfSize;
    if (dot(normalized, normalized) > 1.0) { discard; }
  } else {
    float radius = clamp(v_texcoord1.z, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(v_texcoord0 - halfSize) - halfSize + vec2(radius);
    float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    if (distance > 0.0) { discard; }
  }
  gl_FragColor = vec4(v_color0.rgb * v_color0.a, v_color0.a);
}
""",
    varyingDefinitions: """vec2 v_texcoord0 : TEXCOORD0;
vec4 v_texcoord1 : TEXCOORD1;
vec2 v_texcoord2 : TEXCOORD2;
vec4 v_color0 : COLOR0;
""",
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2),
      GpuShaderInterfaceEntry(slot: gsisTexCoord1, valueType: gsvtVec4),
      GpuShaderInterfaceEntry(slot: gsisTexCoord2, valueType: gsvtVec2),
      GpuShaderInterfaceEntry(slot: gsisColor0, valueType: gsvtVec4)
    ])

proc gpuMotionImageFragmentSource*(): GpuShaderSource =
  GpuShaderSource(stage: gssFragment, label: "motion-scene-image-fragment",
    source: """$input v_texcoord0, v_texcoord1, v_color0
#include "bgfx_shader.sh"
SAMPLER2D(s_cbssMotionImage, 0);
void main()
{
  vec2 uv = v_texcoord0 / v_texcoord1.xy;
  vec4 sampled = texture2D(s_cbssMotionImage, uv);
  float alpha = sampled.a * v_color0.a;
  gl_FragColor = vec4(sampled.rgb * alpha, alpha);
}
""",
    varyingDefinitions: """vec2 v_texcoord0 : TEXCOORD0;
vec4 v_texcoord1 : TEXCOORD1;
vec2 v_texcoord2 : TEXCOORD2;
vec4 v_color0 : COLOR0;
""",
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2),
      GpuShaderInterfaceEntry(slot: gsisTexCoord1, valueType: gsvtVec4),
      GpuShaderInterfaceEntry(slot: gsisColor0, valueType: gsvtVec4)
    ])

proc isClosed*(material: GpuMotionImageMaterial): bool =
  material.isNil or material.host.isNil

proc release*(material: GpuMotionImageMaterial) =
  if material.isClosed:
    return
  for handle in [material.sampler, material.pipeline, material.vertexBuffer,
      material.vertexShader, material.fragmentShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil

proc newGpuMotionImageMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuMotionImageMaterial =
  if host.isNil:
    raise newException(ValueError, "motion scene image material requires a host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuMotionRectVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuMotionImageFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError, "motion scene image shader artifacts do not match the built-in shaders")
  result = GpuMotionImageMaterial(host: host, namespace: namespace)
  let layout = @[GpuVertexAttribute(
    semantic: gvsPosition, components: 2, componentType: gvctFloat)]
  let quad = [[0'f32, 0'f32], [0'f32, 1'f32],
    [1'f32, 0'f32], [1'f32, 1'f32]]
  var quadBytes = newSeq[byte](sizeof(quad))
  copyMem(addr quadBytes[0], unsafeAddr quad[0], quadBytes.len)
  try:
    result.vertexShader = host.createGpuShader(namespace, vertexArtifact)
    result.fragmentShader = host.createGpuShader(namespace, fragmentArtifact)
    result.pipeline = host.createGpuGraphicsPipeline(namespace,
      GpuGraphicsPipelineDescriptor(
        vertexShader: result.vertexShader,
        fragmentShader: result.fragmentShader,
        vertexLayout: layout,
        instanceDataVec4Count: gpuMotionRectVec4Count,
        colorFormat: gtfRgba8,
        topology: gptTriangleStrip,
        cullMode: gcmNone,
        blend: premultipliedAlphaGpuBlendState(),
        label: "motion-scene-image-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(quadBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "motion-scene-image-quad"), quadBytes)
    result.sampler = host.createGpuSampler(namespace,
      GpuSamplerDescriptor(name: "s_cbssMotionImage",
        addressU: gsamClamp, addressV: gsamClamp, addressW: gsamClamp,
        minFilter: gsfNearest, magFilter: gsfNearest,
        mipFilter: gsfNearest, label: "motion-scene-image-sampler"))
  except CatchableError:
    result.release()
    raise

proc isClosed*(material: GpuMotionRectMaterial): bool =
  material.isNil or material.host.isNil

proc release*(material: GpuMotionRectMaterial) =
  ## Release outside an active frame, after all submissions using this material.
  if material.isClosed:
    return
  for handle in [material.pipeline, material.vertexBuffer,
      material.vertexShader, material.fragmentShader]:
    if material.host.isGpuResourceLive(handle):
      discard material.host.releaseGpuResource(handle)
  material.host = nil
  material.vertexShader = GpuResourceHandle()
  material.fragmentShader = GpuResourceHandle()
  material.pipeline = GpuResourceHandle()
  material.vertexBuffer = GpuResourceHandle()

proc newGpuMotionRectMaterial*(
    host: GpuHost; namespace: GpuNamespaceId;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuMotionRectMaterial =
  ## Use artifacts compiled from the built-in shader pair for the selected
  ## backend. Shader compilation remains a build-time responsibility.
  if host.isNil:
    raise newException(ValueError, "motion scene GPU material requires a host")
  if vertexArtifact.descriptor.stage != gssVertex or
      vertexArtifact.sourceHash != gpuMotionRectVertexSource().gpuShaderSourceHash() or
      fragmentArtifact.descriptor.stage != gssFragment or
      fragmentArtifact.sourceHash != gpuMotionRectFragmentSource().gpuShaderSourceHash():
    raise newException(ValueError, "motion scene GPU shader artifacts do not match the built-in shaders")
  result = GpuMotionRectMaterial(host: host, namespace: namespace)
  let layout = @[GpuVertexAttribute(
    semantic: gvsPosition, components: 2, componentType: gvctFloat)]
  let quad = [[0'f32, 0'f32], [0'f32, 1'f32],
    [1'f32, 0'f32], [1'f32, 1'f32]]
  var quadBytes = newSeq[byte](sizeof(quad))
  copyMem(addr quadBytes[0], unsafeAddr quad[0], quadBytes.len)
  try:
    result.vertexShader = host.createGpuShader(namespace, vertexArtifact)
    result.fragmentShader = host.createGpuShader(namespace, fragmentArtifact)
    result.pipeline = host.createGpuGraphicsPipeline(namespace,
      GpuGraphicsPipelineDescriptor(
        vertexShader: result.vertexShader,
        fragmentShader: result.fragmentShader,
        vertexLayout: layout,
        instanceDataVec4Count: gpuMotionRectVec4Count,
        colorFormat: gtfRgba8,
        topology: gptTriangleStrip,
        cullMode: gcmNone,
        blend: premultipliedAlphaGpuBlendState(),
        label: "motion-scene-rect-pipeline"))
    result.vertexBuffer = host.createGpuBuffer(namespace,
      GpuBufferDescriptor(byteSize: uint64(quadBytes.len),
        role: gbrVertex, access: gbaStatic, vertexLayout: layout,
        label: "motion-scene-unit-quad"), quadBytes)
  except CatchableError:
    result.release()
    raise

proc submit*(
    material: GpuMotionRectMaterial; binding: GpuInstanceBinding;
    pass: GpuGraphicsPassDescriptor
): bool =
  ## Submit static or dynamic records in an active frame. Empty bindings submit
  ## nothing; the caller retains pass clear ownership.
  if material.isClosed:
    raise newException(ValueError, "motion scene GPU material is closed")
  if binding.instanceCount == 0:
    return false
  material.host.submitGpuDraw(material.namespace, pass,
    GpuDrawCommand(pipeline: material.pipeline,
      vertexBuffer: material.vertexBuffer, vertexCount: 4,
      instances: binding))
  true

proc submit*(
    material: GpuMotionRectMaterial; batch: GpuMotionRectBatch;
    pass: GpuGraphicsPassDescriptor
): bool =
  ## Sync the batch before beginning the frame. Refuse a stale scene revision.
  if material.isClosed or batch.isNil or batch.host != material.host or
      batch.namespace != material.namespace or batch.scene.isNil:
    raise newException(ValueError, "motion scene GPU material and batch do not share an owner")
  if batch.revision != batch.scene.revision:
    raise newException(ValueError, "motion scene GPU batch must be synchronized before submission")
  if batch.imageAssets.len > 0:
    raise newException(ValueError,
      "motion scene GPU image batches require an image material")
  material.submit(batch.instanceBinding(), pass)

proc submitMotionScene*(
    shapes: GpuMotionRectMaterial; images: GpuMotionImageMaterial;
    batch: GpuMotionRectBatch; pass: GpuGraphicsPassDescriptor
): bool =
  ## Submit contiguous runs in paint order; consecutive instances sharing an
  ## image use one draw and one immutable texture.
  if shapes.isClosed or batch.isNil or batch.host != shapes.host or
      batch.namespace != shapes.namespace or batch.scene.isNil or
      batch.revision != batch.scene.revision:
    raise newException(ValueError, "motion scene GPU batch must be synchronized")
  if batch.imageAssets.len > 0 and (images.isClosed or
      images.host != shapes.host or images.namespace != shapes.namespace):
    raise newException(ValueError, "motion scene GPU image material is required")
  var commands: seq[GpuDrawCommand]
  for run in batch.runs:
    let binding = GpuInstanceBinding(buffer: batch.buffer,
      firstInstance: run.first, instanceCount: run.count)
    if run.image.isNil:
      commands.add GpuDrawCommand(pipeline: shapes.pipeline,
        vertexBuffer: shapes.vertexBuffer, vertexCount: 4,
        instances: binding)
    else:
      var texture = GpuResourceHandle()
      for index, asset in batch.imageAssets:
        if asset == run.image:
          texture = batch.imageTextures[index]
          break
      commands.add GpuDrawCommand(pipeline: images.pipeline,
          vertexBuffer: images.vertexBuffer, vertexCount: 4,
          instances: binding,
          bindings: GpuBindingSet(textures: @[
            GpuTextureBinding(stage: 0, sampler: images.sampler,
              texture: texture)]))
  if commands.len == 0:
    return false
  shapes.host.submitGpuDraws(shapes.namespace, pass, commands)
  true
