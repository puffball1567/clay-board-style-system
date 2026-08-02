import std/[options, unittest]

import clay_board_style_system/core/[geometry, node]
import clay_board_style_system/input/events
import clay_board_style_system/runtime/render_surface

proc placement(
    x = 10.0'f32;
    y = 20.0'f32;
    width = 120.0'f32;
    height = 80.0'f32;
    scale = 2.0'f32;
    opacity = 1.0'f32
): RenderSurfacePlacement =
  renderSurfacePlacement(
    rect(x, y, width, height),
    rect(x, y, width, height),
    pixelScale = scale,
    opacity = opacity
  )

suite "render surface lifecycle":
  test "transformed placement preserves logical size and inverse local input":
    let transform = translationAffine2D(100, 50) * scaleAffine2D(2, 3)
    let placement = renderSurfacePlacement(
      rect(10, 20, 30, 40),
      rect(0, 0, 500, 500),
      pixelScale = 2,
      transform = transform
    )
    check placement.bounds == rect(120, 110, 60, 120)
    check placement.localBounds == rect(0, 0, 30, 40)
    check placement.pixelSize == size(60, 80)
    let hostPoint = transform.transformPoint(vec2(15, 27))
    check placement.toLocal(hostPoint) == vec2(5, 7)

  test "mount publishes versioned placement and initial state exactly once":
    var registry = initRenderSurfaceRegistry()
    var mounts: seq[RenderSurfaceMount]
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      name: "chart",
      callbacks: RenderSurfaceCallbacks(
        onMount: proc(event: RenderSurfaceMount) = mounts.add event
      )
    ))
    registry.mountSurface(id, NodeId(7), placement(), revision = 4)

    check registry.surfaceState(id) == rssMounted
    check registry.surfaceName(id) == "chart"
    check mounts.len == 1
    check mounts[0].apiVersion == renderSurfaceApiVersion
    check mounts[0].surface == id
    check mounts[0].node == NodeId(7)
    check mounts[0].visible
    check mounts[0].revision == 4
    expect ValueError:
      registry.mountSurface(id, NodeId(7), placement())

  test "placement separates host coordinates from local coordinates":
    let value = placement(x = 30, y = 40, width = 100, height = 50, scale = 1.5)
    check value.localBounds == rect(0, 0, 100, 50)
    check value.toLocal(vec2(52, 49)) == vec2(22, 9)
    check value.pixelSize == size(150, 75)

  test "resize fires only for size or scale while update observes all placement changes":
    var registry = initRenderSurfaceRegistry()
    var resizeCount = 0
    var updateCount = 0
    var lastResize: RenderSurfaceResize
    let onResize = proc(event: RenderSurfaceResize) =
      inc resizeCount
      lastResize = event
    let onUpdate = proc(event: RenderSurfaceUpdate) =
      inc updateCount
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onResize: onResize,
        onUpdate: onUpdate
      )
    ))
    registry.mountSurface(id, NodeId(1), placement())

    check registry.placeSurface(id, placement(x = 15))
    check resizeCount == 0
    check updateCount == 1
    check registry.placeSurface(id, placement(width = 200, scale = 1.5))
    check resizeCount == 1
    check updateCount == 2
    check lastResize.logicalSize == size(200, 80)
    check lastResize.pixelSize == size(300, 120)
    check not registry.placeSurface(id, placement(width = 200, scale = 1.5))

  test "revision updates are retained and duplicate revisions are ignored":
    var registry = initRenderSurfaceRegistry()
    var revisions: seq[uint64]
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onUpdate: proc(event: RenderSurfaceUpdate) = revisions.add event.revision
      )
    ))
    registry.mountSurface(id, NodeId(1), placement(), revision = 8)
    check not registry.updateSurface(id, 8)
    check registry.updateSurface(id, 9)
    check revisions == @[9'u64]

  test "effective visibility follows clipping opacity and explicit visibility":
    var registry = initRenderSurfaceRegistry()
    var changes: seq[bool]
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onVisibility: proc(visible: bool) = changes.add visible
      )
    ))
    registry.mountSurface(id, NodeId(1), placement())
    check registry.setSurfaceVisible(id, false)
    check changes == @[false]
    check registry.setSurfaceVisible(id, true)
    check changes == @[false, true]
    check registry.placeSurface(id, placement(opacity = 0))
    check changes == @[false, true, false]
    check registry.placeSurface(id, placement(opacity = 1))
    check changes == @[false, true, false, true]

  test "frame requests are one shot unless the callback requests another":
    var registry = initRenderSurfaceRegistry()
    var frames: seq[RenderSurfaceFrame]
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onFrame: proc(event: RenderSurfaceFrame): RenderSurfaceFrameResult =
          frames.add event
          if event.frameNumber < 2: rsfRequestNext else: rsfIdle
      )
    ))
    registry.mountSurface(id, NodeId(1), placement())
    check registry.requestSurfaceFrame(id)
    check registry.needsSurfaceFrame
    check registry.runSurfaceFrames(10.0) == 1
    check registry.needsSurfaceFrame
    check registry.runSurfaceFrames(10.016) == 1
    check not registry.needsSurfaceFrame
    check frames.len == 2
    check frames[0].deltaSeconds == 0
    check abs(frames[1].deltaSeconds - 0.016) < 0.000001

  test "hidden and device-lost surfaces retain but do not run pending frames":
    var registry = initRenderSurfaceRegistry()
    var frames = 0
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onFrame: proc(event: RenderSurfaceFrame): RenderSurfaceFrameResult =
          inc frames
          rsfIdle
      )
    ))
    registry.mountSurface(id, NodeId(1), placement())
    discard registry.requestSurfaceFrame(id)
    discard registry.setSurfaceVisible(id, false)
    check registry.runSurfaceFrames(1.0) == 0
    discard registry.setSurfaceVisible(id, true)
    check registry.runSurfaceFrames(1.0) == 1
    discard registry.requestSurfaceFrame(id)
    check registry.loseSurfaceDevice(id)
    check registry.runSurfaceFrames(2.0) == 0
    check registry.restoreSurfaceDevice(id)
    check registry.runSurfaceFrames(2.0) == 1
    check frames == 2

  test "input coordinates are local and clipped unless pointer capture is active":
    var registry = initRenderSurfaceRegistry()
    var inputs: seq[RenderSurfaceInput]
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onInput: proc(event: RenderSurfaceInput): bool =
          inputs.add event
          true
      )
    ))
    registry.mountSurface(id, NodeId(1), placement())
    check registry.dispatchSurfaceInput(id, pointerDownEvent(vec2(22, 31)))
    check inputs[^1].localPosition == some(vec2(12, 11))
    check inputs[^1].inside
    check not inputs[^1].captured
    check not registry.dispatchSurfaceInput(id, pointerMoveEvent(vec2(500, 500)))
    check inputs.len == 1
    check registry.dispatchSurfaceInput(id, pointerMoveEvent(vec2(500, 500)), captured = true)
    check inputs[^1].localPosition == some(vec2(490, 480))
    check not inputs[^1].inside
    check inputs[^1].captured

  test "device loss and restoration have deterministic visibility ordering":
    var registry = initRenderSurfaceRegistry()
    var events: seq[string]
    let onVisibility = proc(visible: bool) = events.add("visible:" & $visible)
    let onDeviceLost = proc() = events.add("lost")
    let onDeviceRestored = proc() = events.add("restored")
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onVisibility: onVisibility,
        onDeviceLost: onDeviceLost,
        onDeviceRestored: onDeviceRestored
      )
    ))
    registry.mountSurface(id, NodeId(1), placement())
    check registry.loseSurfaceDevice(id)
    check registry.restoreSurfaceDevice(id)
    check events == @["visible:false", "lost", "restored", "visible:true"]

  test "unmount and unregister release resources exactly once":
    var registry = initRenderSurfaceRegistry()
    var unmounts = 0
    var visibility: seq[bool]
    let onVisibility = proc(visible: bool) = visibility.add visible
    let onUnmount = proc() =
      inc unmounts
    let id = registry.registerSurface(RenderSurfaceDescriptor(
      callbacks: RenderSurfaceCallbacks(
        onVisibility: onVisibility,
        onUnmount: onUnmount
      )
    ))
    registry.mountSurface(id, NodeId(1), placement())
    check registry.unmountSurface(id)
    check not registry.unmountSurface(id)
    check unmounts == 1
    check visibility == @[false]
    check registry.unregisterSurface(id)
    check unmounts == 1
    check not registry.hasSurface(id)

  test "unmount all uses registration order":
    var registry = initRenderSurfaceRegistry()
    var order: seq[int]
    proc unmountCallback(value: int): RenderSurfaceUnmountCallback =
      result = proc() = order.add value
    for index in 0 ..< 3:
      let id = registry.registerSurface(RenderSurfaceDescriptor(
        callbacks: RenderSurfaceCallbacks(
          onUnmount: unmountCallback(index)
        )
      ))
      registry.mountSurface(id, NodeId(index), placement())
    registry.unmountAllSurfaces()
    check order == @[0, 1, 2]

  test "invalid placements and unknown identifiers fail without callbacks":
    var registry = initRenderSurfaceRegistry()
    expect ValueError:
      discard renderSurfacePlacement(rect(0, 0, -1, 1), rect(0, 0, 1, 1))
    expect ValueError:
      discard renderSurfacePlacement(rect(0, 0, 1, 1), rect(0, 0, 1, 1), pixelScale = 0)
    expect ValueError:
      registry.mountSurface(RenderSurfaceId(999), NodeId(1), placement())
    check not registry.requestSurfaceFrame(RenderSurfaceId(999))
