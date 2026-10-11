## Bounded GPU instance encoding for the CPU Motion Scene reference snapshot.
## Import explicitly; ordinary UI and headless Motion Scene builds stay CPU-only.
import std/[math, options]

import ../core/geometry
import ./[gpu_host, gpu_shader_builder, motion_scene]

const gpuMotionRectVec4Count* = 5'u8

type GpuMotionRectRecord* = array[5, array[4, float32]]

type GpuMotionRectBatch* = ref object
  ## Owns one dynamic instance buffer and the last successfully uploaded frame.
  host: GpuHost
  namespace: GpuNamespaceId
  scene: MotionScene
  revision: uint64
  buffer: GpuResourceHandle
  capacity: int
  records: seq[GpuMotionRectRecord]

static:
  doAssert sizeof(GpuMotionRectRecord) == 80

proc gpuMotionRectRecords*(snapshot: MotionSceneSnapshot): seq[GpuMotionRectRecord] =
  ## Packs drawable rounded rectangles in CPU paint order. The five vec4 rows
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
      [item.transform.m11, item.transform.m21, origin.x, 0'f32],
      [item.transform.m12, item.transform.m22, origin.y, 0'f32],
      [item.bounds.w, item.bounds.h, item.radius, 0'f32],
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
  batch.host = nil
  batch.namespace = GpuNamespaceId(0)
  batch.scene = nil
  batch.revision = 0
  batch.buffer = GpuResourceHandle()
  batch.capacity = 0
  batch.records.setLen(0)

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
  if live and batch.scene == scene and batch.revision == scene.revision:
    return false
  let next = gpuMotionRectRecords(scene.snapshot)
  result = next.len != batch.records.len
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
  batch.host = host
  batch.namespace = namespace
  batch.scene = scene
  batch.revision = scene.revision
  batch.records = next

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
  builder.setVaryingOutput(gsisTexCoord1, builder.swizzle(shape, "xyz"))
  builder.setVaryingOutput(gsisColor0, color)
  builder.emitGpuShaderSource()

proc gpuMotionRectFragmentSource*(): GpuShaderSource =
  GpuShaderSource(stage: gssFragment, label: "motion-scene-rect-fragment",
    source: """$input v_texcoord0, v_texcoord1, v_color0
#include "bgfx_shader.sh"
void main()
{
  vec2 halfSize = v_texcoord1.xy * 0.5;
  float radius = clamp(v_texcoord1.z, 0.0, min(halfSize.x, halfSize.y));
  vec2 q = abs(v_texcoord0 - halfSize) - halfSize + vec2(radius);
  float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  if (distance > 0.0) { discard; }
  gl_FragColor = v_color0;
}
""",
    varyingDefinitions: """vec2 v_texcoord0 : TEXCOORD0;
vec3 v_texcoord1 : TEXCOORD1;
vec4 v_color0 : COLOR0;
""",
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2),
      GpuShaderInterfaceEntry(slot: gsisTexCoord1, valueType: gsvtVec3),
      GpuShaderInterfaceEntry(slot: gsisColor0, valueType: gsvtVec4)
    ])
