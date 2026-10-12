import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/runtime/[motion_scene, motion_scene_ui,
  motion_scene_timeline, motion_scene_timeline_ui]

proc initial(): MotionScene =
  newMotionScene(motionSceneSnapshot(size(200, 100), [
    motionRect(MotionObjectId(1), rect(0, 0, 10, 10), rgb(1, 0, 0)),
    motionRect(MotionObjectId(2), rect(0, 20, 10, 10), rgb(0, 1, 0))
  ]))

proc track(property = mspX; first = 0.0; last = 100.0;
    id = MotionObjectId(1)): MotionFloatTrack =
  motionTrack(id, property, [FloatKeyframe(offset: 0, value: first),
    FloatKeyframe(offset: 1, value: last)])

proc value(scene: MotionScene; id = MotionObjectId(1)): MotionObject =
  scene.snapshot.objectById(id).get

proc tick(timeline: MotionTimeline; now: float64): FrameScheduler =
  result = initFrameScheduler()
  discard timeline.advance(result, now)

suite "CPU Motion Scene timelines":
  test "batch tracks sample shared keyframes and finish without a deadline":
    let scene = initial()
    let timeline = newMotionTimeline(scene, [track(),
      track(mspOpacity, 1, 0), track(mspY, 20, 40, MotionObjectId(2))], 2, 10)
    let revision = scene.revision
    var first = timeline.tick(10)
    check scene.revision == revision
    check first.consumeDirty() == {}
    check first.nextDeadline.isSome
    var middle = timeline.tick(11)
    check middle.consumeDirty() == {ddPaint}
    check scene.value.bounds.x == 50
    check scene.value.opacity == 0.5
    check scene.value(MotionObjectId(2)).bounds.y == 30
    check scene.hitTest(vec2(52, 2)).get.id == MotionObjectId(1)
    discard timeline.tick(10.5)
    check scene.value.bounds.x == 50
    var final = timeline.tick(12)
    check scene.value.bounds.x == 100
    check scene.value.opacity == 0
    check timeline.state == mtsFinished
    check final.nextDeadline.isNone
    check final.consumeDirty() == {ddPaint}
    var idle = timeline.tick(13)
    check idle.waitTimeoutMs(13) == -1

  test "delays use a deadline and backwards fill follows clock easing":
    let scene = initial()
    let timeline = newMotionTimeline(scene, [track(mspX, 10, 30)], 1, 5,
      delaySeconds = 2, timing = stepEndTiming())
    var waiting = timeline.tick(5)
    check waiting.nextDeadline == some(7.0)
    check waiting.consumeDirty() == {}
    check scene.value.bounds.x == 0
    discard timeline.tick(7.5)
    check scene.value.bounds.x == 10
    let revision = scene.revision
    var unchanged = timeline.tick(7.75)
    check unchanged.consumeDirty() == {}
    check scene.revision == revision
    discard timeline.tick(8)
    check scene.value.bounds.x == 30
    let backwards = newMotionTimeline(scene, [track(mspX, 80, 100)], 1, 9,
      delaySeconds = 2, fillMode = afBackwards, direction = adReverse)
    discard backwards.tick(9)
    check scene.value.bounds.x == 100
    discard backwards.tick(12)
    check scene.value.bounds.x == 30
    check backwards.state == mtsFinished

  test "iterations alternate and no-fill restores the base":
    let scene = initial()
    let timeline = newMotionTimeline(scene, [track()], 1, 0,
      iterations = 2, direction = adAlternate)
    discard timeline.tick(0.75)
    check scene.value.bounds.x == 75
    discard timeline.tick(1.25)
    check scene.value.bounds.x == 75
    discard timeline.tick(2)
    check scene.value.bounds.x == 0
    let noFill = newMotionTimeline(scene, [track()], 1, 3, fillMode = afNone)
    discard noFill.tick(3.5)
    check scene.value.bounds.x == 50
    discard noFill.tick(4)
    check scene.value.bounds.x == 0

  test "pause samples its time and resume excludes the paused interval":
    let scene = initial()
    let timeline = newMotionTimeline(scene, [track()], 2, 0)
    check timeline.pause(0.5)
    check scene.value.bounds.x == 25
    check timeline.state == mtsPaused
    var paused = timeline.tick(5)
    check paused.waitTimeoutMs(5) == -1
    check scene.value.bounds.x == 25
    check timeline.resume(5)
    discard timeline.tick(5.5)
    check scene.value.bounds.x == 50
    check not timeline.resume(5.5)
    discard timeline.tick(6.5)
    check timeline.state == mtsFinished

  test "cancellation freezes or restores and never overwrites external replacement":
    let scene = initial()
    let frozen = newMotionTimeline(scene, [track()], 1, 0)
    discard frozen.tick(0.5)
    check frozen.cancel()
    check not frozen.cancel()
    discard frozen.tick(1)
    check scene.value.bounds.x == 50
    let restored = newMotionTimeline(scene, [track()], 1, 2)
    discard restored.tick(2.75)
    check restored.cancel(restoreBase = true)
    check scene.value.bounds.x == 50
    let external = newMotionTimeline(scene, [track()], 1, 3)
    let replacement = motionSceneSnapshot(size(200, 100), [
      motionRect(MotionObjectId(1), rect(125, 0, 10, 10), rgb(0, 0, 1))])
    discard scene.replaceSnapshot(replacement)
    var idle = external.tick(3.5)
    check external.state == mtsCancelled
    check scene.snapshot == replacement
    check idle.waitTimeoutMs(3.5) == -1
    check not external.cancel(restoreBase = true)

  test "reduced motion completes nonessential tracks while essential tracks continue":
    let scene = initial()
    let reduced = newMotionTimeline(scene, [track()], 2, 0, reducedMotion = true)
    var finished = reduced.tick(0)
    check scene.value.bounds.x == 100
    check reduced.state == mtsFinished
    check finished.nextDeadline.isNone
    let essential = newMotionTimeline(scene, [track()], 2, 1,
      reducedMotion = true, essentialMotion = true)
    discard essential.tick(1.5)
    check essential.state == mtsRunning
    check scene.value.bounds.x == 25
    let toggled = newMotionTimeline(scene, [track(mspY, 0, 80)], 2, 2)
    toggled.setReducedMotion(true)
    discard toggled.tick(2)
    check toggled.state == mtsFinished
    check scene.value.bounds.y == 80

  test "size radius and affine translation tracks retain unanimated properties":
    let scene = initial()
    let timeline = newMotionTimeline(scene, [track(mspWidth, 10, 30),
      track(mspHeight, 10, 30), track(mspRadius, 0, 10),
      track(mspTranslateX, 0, 20), track(mspTranslateY, 0, 40)], 1, 0)
    discard timeline.tick(0.5)
    let value = scene.value
    check value.bounds.w == 20 and value.bounds.h == 20
    check value.radius == 5
    check value.transform.tx == 10 and value.transform.ty == 20
    check value.color == rgb(1, 0, 0)
    check value.id == MotionObjectId(1)
    check scene.hitTest(vec2(15, 25)).get.id == MotionObjectId(1)

  test "invalid authoring and time fail before publication":
    let scene = initial()
    let before = scene.snapshot
    expect ValueError: discard motionTrack(MotionObjectId(1), mspX, [])
    expect ValueError: discard track(mspOpacity, 0, 2)
    expect ValueError: discard track(mspWidth, -1, 10)
    expect ValueError: discard track(mspX, 0, Inf)
    expect ValueError: discard track(mspX, 0, 1e39)
    expect ValueError: discard motionTrack(MotionObjectId(1), mspX,
      [FloatKeyframe(offset: 1, value: 0), FloatKeyframe(offset: 0, value: 1)])
    expect ValueError: discard newMotionTimeline(scene, [track(), track()], 1, 0)
    expect ValueError: discard newMotionTimeline(scene, [track(id = MotionObjectId(99))], 1, 0)
    expect ValueError: discard newMotionTimeline(scene, [MotionFloatTrack()], 1, 0)
    expect ValueError: discard newMotionTimeline(scene, [track()], -1, 0)
    expect ValueError: discard newMotionTimeline(scene, [track()], 1, NaN)
    expect ValueError: discard newMotionTimeline(scene, [track()], 1, 0, iterations = 0)
    expect ValueError: discard newMotionTimeline(scene, [track()], 1, 0,
      timing = TimingFunction(kind: tfCubicBezier, x1: -1))
    let timeline = newMotionTimeline(scene, [track()], 1, 0)
    for invalid in [NaN, Inf, NegInf]:
      expect ValueError: discard timeline.tick(invalid)
    check scene.snapshot == before
    check timeline.state == mtsRunning

  test "overflowing sampled geometry cancels atomically":
    let scene = newMotionScene(motionSceneSnapshot(size(10, 10), [
      motionRect(MotionObjectId(1), rect(0, 0, 1, 1), rgb(1, 0, 0),
        transform = scaleAffine2D(2, 2))]))
    let before = scene.snapshot
    let timeline = newMotionTimeline(scene, [track(mspX, 0, 3e38)], 1, 0)
    expect ValueError: discard timeline.tick(1)
    check timeline.state == mtsCancelled
    check scene.snapshot == before

  test "keyframes are copied and UI publication is paint-only":
    var stops = @[FloatKeyframe(offset: 0, value: 0), FloatKeyframe(offset: 1, value: 100)]
    let authored = motionTrack(MotionObjectId(1), mspX, stops)
    stops[1].value = 10
    let scene = initial()
    let timeline = newMotionTimeline(scene, [authored], 1, 0)
    let ui = initUiRoot()
    let view = ui.motionScene(scene)
    discard ui.consumeInvalidation()
    var scheduler = initFrameScheduler()
    scheduler.requestDeadline(0.6)
    check timeline.advance(view, scheduler, 0.5)
    check scene.value.bounds.x == 50
    check ui.tree.nodes.len == 1
    check ui.consumeInvalidation().domains == {ddPaint}
    check scheduler.nextDeadline.get < 0.6
    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check not timeline.advance(view, scheduler, 0.5)
    check not ui.hasPendingInvalidation
    var interaction = initInteractionState()
    check ui.disposeSubtree(view.nodeHandle, interaction)
    scheduler.clearDeadline()
    check not timeline.advance(view, scheduler, 0.75)
    check timeline.state == mtsCancelled
    check scheduler.nextDeadline.isNone

  test "thousands of tracks use one UI node and stop scheduling at completion":
    var objects: seq[MotionObject]
    var tracks: seq[MotionFloatTrack]
    for index in 1 .. 2000:
      let id = MotionObjectId(index.uint64)
      objects.add motionRect(id, rect(0, index.float32, 1, 1), rgb(1, 0, 0))
      tracks.add track(id = id)
    let scene = newMotionScene(motionSceneSnapshot(size(200, 2100), objects))
    let timeline = newMotionTimeline(scene, tracks, 1, 0)
    let ui = initUiRoot()
    let view = ui.motionScene(scene)
    discard ui.consumeInvalidation()
    var scheduler = initFrameScheduler()
    check timeline.advance(view, scheduler, 0.5)
    check scene.value(MotionObjectId(2000)).bounds.x == 50
    check scene.snapshot.objectCount == 2000
    check ui.tree.nodes.len == 1
    check ui.consumeInvalidation().domains == {ddPaint}
    scheduler.clearDeadline()
    discard timeline.advance(view, scheduler, 1)
    check scheduler.nextDeadline.isNone
    check timeline.state == mtsFinished

  test "authoring limits reject oversized tracks and aggregate keyframe budgets":
    let scene = initial()
    expect ValueError:
      discard motionTrack(MotionObjectId(1), mspX,
        newSeq[FloatKeyframe](maxMotionTrackKeyframes + 1))
    expect ValueError:
      discard newMotionTimeline(scene,
        newSeq[MotionFloatTrack](maxMotionTimelineTracks + 1), 1, 0)
    expect ValueError:
      discard newMotionTimeline(scene, [track()], 1, 0,
        iterations = maxMotionTimelineIterations + 1)
    var objects: seq[MotionObject]
    var tracks: seq[MotionFloatTrack]
    let stops = newSeq[FloatKeyframe](maxMotionTrackKeyframes)
    for index in 1 .. (maxMotionTimelineKeyframes div maxMotionTrackKeyframes) + 1:
      let id = MotionObjectId(index.uint64)
      objects.add motionRect(id, rect(0, 0, 1, 1), rgb(1, 0, 0))
      tracks.add motionTrack(id, mspX, stops)
    let large = newMotionScene(motionSceneSnapshot(size(10, 10), objects))
    let before = large.snapshot
    expect ValueError: discard newMotionTimeline(large, tracks, 1, 0)
    check large.snapshot == before

  test "scheduler merging preserves other producers and delayed idle":
    let scene = initial()
    let timeline = newMotionTimeline(scene, [track()], 1, 0, delaySeconds = 2)
    var scheduler = initFrameScheduler()
    scheduler.requestDeadline(0.25)
    scheduler.markDirty(ddLayout)
    discard timeline.advance(scheduler, 0)
    check scheduler.nextDeadline == some(0.25)
    check scheduler.consumeDirty() == {ddLayout}
    let pending = scene.beginUpdate()
    discard timeline.tick(2.5)
    check not pending.isPending
