import std/[strformat, times]

import clay_board_style_system

const
  surfaceCount = 10_000
  idleProbeCount = 1_000_000
  canvasCommandCount = 10_000
  canvasIterations = 30
  transformScopeCount = 1_000
  transformIterations = 30
  layerScopeCount = 1_000
  layerIterations = 30
  curveSegmentCount = 1_000
  curveIterations = 30

proc elapsedMilliseconds(started: float): float =
  (cpuTime() - started) * 1000.0

var registry = initRenderSurfaceRegistry()
for index in 0 ..< surfaceCount:
  let id = registry.registerSurface(RenderSurfaceDescriptor(name: $index))
  registry.mountSurface(
    id,
    NodeId(index + 1),
    renderSurfacePlacement(rect(0, 0, 20, 20), rect(0, 0, 20, 20)),
    visible = false
  )
  doAssert registry.requestSurfaceFrame(id)

let idleStarted = cpuTime()
var idleResult = false
for _ in 0 ..< idleProbeCount:
  idleResult = idleResult xor registry.needsSurfaceFrame()
let idleMs = elapsedMilliseconds(idleStarted)
doAssert not idleResult
when not defined(cbssMemoryCheck):
  doAssert idleMs <= 50.0,
    &"idle surface scheduling exceeded O(1) budget: {idleMs:.3f} ms"

let canvas = newCanvas2D()
for index in 0 ..< canvasCommandCount:
  canvas.fillRect(
    rect((index mod 100).float32, (index div 100).float32, 1, 1),
    rgba(0.2, 0.5, 0.8, 0.9)
  )

let canvasStarted = cpuTime()
var flattened = 0
for _ in 0 ..< canvasIterations:
  flattened += canvas.paintCommands(
    NodeId(1), rect(10, 20, 640, 480), 0.8
  ).len
let canvasMs = elapsedMilliseconds(canvasStarted)
let canvasAverageMs = canvasMs / canvasIterations.float
doAssert flattened == canvasCommandCount * canvasIterations
when not defined(cbssMemoryCheck):
  doAssert canvasAverageMs <= 4.0,
    &"10k-command Canvas flatten exceeded budget: {canvasAverageMs:.3f} ms"

let transformedCanvas = newCanvas2D()
for index in 0 ..< transformScopeCount:
  transformedCanvas.save()
  transformedCanvas.translate(
    (index mod 32).float32 + 1, (index div 32).float32 + 1
  )
  transformedCanvas.fillRect(rect(0, 0, 4, 4), rgb(0.8, 0.3, 0.2))
  transformedCanvas.restore()

let transformStarted = cpuTime()
var flattenedTransformCommands = 0
for _ in 0 ..< transformIterations:
  flattenedTransformCommands += transformedCanvas.paintCommands(
    NodeId(1), rect(10, 20, 640, 480)
  ).len
let transformMs = elapsedMilliseconds(transformStarted)
let transformAverageMs = transformMs / transformIterations.float
doAssert flattenedTransformCommands == transformScopeCount * 3 * transformIterations
when not defined(cbssMemoryCheck):
  doAssert transformAverageMs <= 4.0,
    &"1k transformed Canvas scopes exceeded budget: {transformAverageMs:.3f} ms"

let layeredCanvas = newCanvas2D()
for index in 0 ..< layerScopeCount:
  let x = (index mod 32).float32 * 5
  let y = (index div 32).float32 * 5
  layeredCanvas.beginLayer(
    rect(x, y, 4, 4), opacity = 0.75,
    compositeMode = lcmSourceOver
  )
  layeredCanvas.fillRect(rect(x, y, 4, 4), rgb(0.3, 0.7, 0.9))
  layeredCanvas.endLayer()

let layerStarted = cpuTime()
var flattenedLayerCommands = 0
for _ in 0 ..< layerIterations:
  flattenedLayerCommands += layeredCanvas.paintCommands(
    NodeId(1), rect(10, 20, 640, 480)
  ).len
let layerMs = elapsedMilliseconds(layerStarted)
let layerAverageMs = layerMs / layerIterations.float
doAssert flattenedLayerCommands == layerScopeCount * 3 * layerIterations
when not defined(cbssMemoryCheck):
  doAssert layerAverageMs <= 4.0,
    &"1k bounded Canvas layers exceeded budget: {layerAverageMs:.3f} ms"

var curve = initPath2D()
curve.moveTo(vec2(0, 50))
for index in 0 ..< curveSegmentCount:
  let startX = index.float32 * 4
  let direction = if index mod 2 == 0: -1.0'f32 else: 1.0'f32
  curve.bezierCurveTo(
    vec2(startX + 1, 50 + direction * 12),
    vec2(startX + 3, 50 - direction * 12),
    vec2(startX + 4, 50)
  )

let curveStarted = cpuTime()
var curvePointCount = 0
for _ in 0 ..< curveIterations:
  for contour in curve.flattened(0.25):
    curvePointCount += contour.points.len
let curveMs = elapsedMilliseconds(curveStarted)
let curveAverageMs = curveMs / curveIterations.float
doAssert curvePointCount > curveSegmentCount * curveIterations
when not defined(cbssMemoryCheck):
  doAssert curveAverageMs <= 12.0,
    &"1k-curve path flatten exceeded budget: {curveAverageMs:.3f} ms"

echo &"render-surface idle probes ({surfaceCount} registered): {idleMs:.3f} ms / {idleProbeCount}"
echo &"Canvas flatten ({canvasCommandCount} commands): {canvasAverageMs:.3f} ms average"
echo &"Canvas transform flatten ({transformScopeCount} scopes): {transformAverageMs:.3f} ms average"
echo &"Canvas layer flatten ({layerScopeCount} scopes): {layerAverageMs:.3f} ms average"
echo &"Path flatten ({curveSegmentCount} cubic curves): {curveAverageMs:.3f} ms average"
