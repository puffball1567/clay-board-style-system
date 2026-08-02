import std/[options, unittest]

import clay_board_style_system

suite "animation clock":
  test "finite animation samples deterministic progress and becomes idle":
    var clock = initAnimationClock()
    var scheduler = initFrameScheduler()
    var samples: seq[AnimationSample]
    var lifecycle: seq[string]
    let onSample = proc(sample: AnimationSample) = samples.add sample
    let onStart = proc(id: AnimationId) = lifecycle.add("start")
    let onEnd = proc(id: AnimationId) = lifecycle.add("end")
    let id = clock.startAnimation(animationSpec(
      durationSeconds = 1.0,
      timing = linearTiming(),
      onSample = onSample,
      onStart = onStart,
      onEnd = onEnd
    ), 10.0)

    check clock.tickAnimations(scheduler, 10.0) == 1
    check samples[^1].progress == 0
    check scheduler.consumeDirty() == {ddPaint}
    scheduler.clearDeadline()
    check clock.tickAnimations(scheduler, 10.5) == 1
    check abs(samples[^1].progress - 0.5) < 0.000001
    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check clock.tickAnimations(scheduler, 11.0) == 1
    check samples[^1].phase == apAfter
    check samples[^1].progress == 1
    check lifecycle == @["start", "end"]
    check not clock.hasAnimation(id)
    check not clock.hasActiveAnimations

  test "delay schedules one wakeup instead of continuous pre-start frames":
    var clock = initAnimationClock()
    var scheduler = initFrameScheduler()
    var samples = 0
    discard clock.startAnimation(animationSpec(
      durationSeconds = 1,
      delaySeconds = 2,
      onSample = proc(sample: AnimationSample) = inc samples
    ), 5.0)

    check clock.tickAnimations(scheduler, 5.5) == 0
    check samples == 0
    check scheduler.nextDeadline == some(7.0)
    check scheduler.consumeDirty() == {}

  test "backwards fill samples once before a delayed start":
    var clock = initAnimationClock()
    var scheduler = initFrameScheduler()
    var sample: AnimationSample
    discard clock.startAnimation(animationSpec(
      durationSeconds = 1,
      delaySeconds = 2,
      fillMode = afBackwards,
      timing = linearTiming(),
      onSample = proc(value: AnimationSample) = sample = value
    ), 5.0)
    check clock.tickAnimations(scheduler, 5.5) == 1
    check sample.phase == apBefore
    check sample.progress == 0

  test "alternate directions and iteration callbacks agree":
    var clock = initAnimationClock()
    var scheduler = initFrameScheduler()
    var samples: seq[AnimationSample]
    var iterations: seq[uint64]
    let onSample = proc(sample: AnimationSample) = samples.add sample
    let onIteration = proc(id: AnimationId; iteration: uint64) =
      iterations.add iteration
    discard clock.startAnimation(animationSpec(
      durationSeconds = 1,
      iterations = some(3.0),
      direction = adAlternate,
      timing = linearTiming(),
      onSample = onSample,
      onIteration = onIteration
    ), 0.0)
    discard clock.tickAnimations(scheduler, 0.25)
    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    discard clock.tickAnimations(scheduler, 1.25)
    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    discard clock.tickAnimations(scheduler, 2.25)

    check abs(samples[0].progress - 0.25) < 0.000001
    check abs(samples[1].progress - 0.75) < 0.000001
    check abs(samples[2].progress - 0.25) < 0.000001
    check iterations == @[1'u64, 2'u64]

  test "pause and resume preserve timeline position without scheduling work":
    var clock = initAnimationClock()
    var scheduler = initFrameScheduler()
    var progress = -1.0
    let id = clock.startAnimation(animationSpec(
      durationSeconds = 2,
      timing = linearTiming(),
      onSample = proc(sample: AnimationSample) = progress = sample.progress
    ), 1.0)
    discard clock.tickAnimations(scheduler, 1.5)
    check abs(progress - 0.25) < 0.000001
    check clock.pauseAnimation(id, 1.5)
    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check clock.tickAnimations(scheduler, 5.0) == 0
    check scheduler.nextDeadline.isNone
    check clock.resumeAnimation(id, 5.0)
    discard clock.tickAnimations(scheduler, 5.5)
    check abs(progress - 0.5) < 0.000001

  test "reduced motion completes nonessential animation immediately":
    var clock = initAnimationClock()
    clock.reducedMotion = true
    var scheduler = initFrameScheduler()
    var progress = -1.0
    discard clock.startAnimation(animationSpec(
      durationSeconds = 20,
      onSample = proc(sample: AnimationSample) = progress = sample.progress
    ), 3.0)
    check clock.tickAnimations(scheduler, 3.0) == 1
    check progress == 1
    check not clock.hasActiveAnimations

  test "essential animation remains timed under reduced motion":
    var clock = initAnimationClock()
    clock.reducedMotion = true
    var scheduler = initFrameScheduler()
    var progress = -1.0
    discard clock.startAnimation(animationSpec(
      durationSeconds = 2,
      essentialMotion = true,
      timing = linearTiming(),
      onSample = proc(sample: AnimationSample) = progress = sample.progress
    ), 1.0)
    discard clock.tickAnimations(scheduler, 2.0)
    check abs(progress - 0.5) < 0.000001
    check clock.hasActiveAnimations

  test "timing functions have stable endpoints and expected shape":
    for timing in [
      linearTiming(), easeTiming(), easeInTiming(), easeOutTiming(),
      easeInOutTiming(), stepEndTiming(),
      cubicBezierTiming(0.2, 0.8, 0.4, 1.0)
    ]:
      check timing.applyTiming(0) == 0
      check timing.applyTiming(1) == 1
    check easeInTiming().applyTiming(0.5) < 0.5
    check easeOutTiming().applyTiming(0.5) > 0.5
    check stepStartTiming().applyTiming(0) == 1
    check stepStartTiming().applyTiming(0.01) == 1
    check stepEndTiming().applyTiming(0.99) == 0

  test "float keyframes interpolate within authored spans":
    let values = floatKeyframes([
      FloatKeyframe(offset: 0, value: 10),
      FloatKeyframe(offset: 0.25, value: 20),
      FloatKeyframe(offset: 1, value: 80)
    ])
    check values.sample(0) == 10
    check values.sample(0.125) == 15
    check values.sample(0.625) == 50
    check values.sample(2) == 80

  test "color keyframes use the requested interpolation space":
    let values = colorKeyframes([
      ColorKeyframe(offset: 0, value: authoredColor(rgb(1, 0, 0))),
      ColorKeyframe(offset: 1, value: authoredColor(rgb(0, 0, 1)))
    ], cisSrgbLinear)
    let midpoint = values.sample(0.5)
    check midpoint.r > 0.7
    check midpoint.g < 0.01
    check midpoint.b > 0.7

  test "invalid timing animation and keyframe inputs fail early":
    expect ValueError:
      discard initAnimationClock(0)
    expect ValueError:
      discard animationSpec(-1)
    expect ValueError:
      discard animationSpec(1, iterations = some(0.0))
    expect ValueError:
      discard cubicBezierTiming(-0.1, 0, 1, 1)
    expect ValueError:
      discard floatKeyframes([])
    expect ValueError:
      discard floatKeyframes([
        FloatKeyframe(offset: 0.8, value: 1),
        FloatKeyframe(offset: 0.2, value: 2)
      ])
