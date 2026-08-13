import std/[sequtils, unittest]

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type
  EffectComponent = ref object of CBSSComponent
    source: State[int]
    events: ref seq[string]
    effectValue: ComponentEffect[int]
    failDuringRender: bool

proc render(self: EffectComponent) =
  self.effectValue = self.effect(self.source, proc(value: int): EffectCleanup =
    self.events[].add "run:" & $value
    let captured = value
    cleanup(proc() = self.events[].add "cleanup:" & $captured)
  )
  ui.box(self):
    if self.failDuringRender:
      raise newException(ValueError, "render failed")
    ui.text("effect")

suite "component effects":
  test "state effects run immediately and clean before each rerun":
    let events = new seq[string]
    let source = initState(1)
    let component = initUiRoot().mount(EffectComponent(
      source: source,
      events: events
    ))

    check events[] == @["run:1"]
    discard source.set(2)
    discard source.set(3)
    check events[] == @[
      "run:1", "cleanup:1", "run:2", "cleanup:2", "run:3"
    ]
    check component.effectValue.dispose()
    check events[][^1] == "cleanup:3"
    check not component.effectValue.dispose()

  test "unmount unsubscribes and releases the current effect":
    let root = initUiRoot()
    let events = new seq[string]
    let source = initState(4)
    let component = root.mount(EffectComponent(source: source, events: events))

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check events[] == @["run:4", "cleanup:4"]
    discard source.set(5)
    check events[] == @["run:4", "cleanup:4"]

  test "a failed mount rolls back subscriptions and cleanup":
    let root = initUiRoot()
    let events = new seq[string]
    let source = initState(6)
    let component = EffectComponent(
      source: source,
      events: events,
      failDuringRender: true
    )

    expect ValueError:
      discard root.mount(component)
    check events[] == @["run:6", "cleanup:6"]
    check source.subscriberCount == 0
    discard source.set(7)
    check events[] == @["run:6", "cleanup:6"]

  test "a failing rerun leaves no stale cleanup installed":
    let root = initUiRoot()
    let events = new seq[string]
    let source = initState(1)
    let component = root.mount(EffectComponent(source: source, events: events))
    discard component.effectValue.dispose()

    var runs = 0
    let occurrence = initSignal[int]()
    let effect = component.effect(occurrence, proc(value: int): EffectCleanup =
      inc runs
      if value == 2:
        raise newException(ValueError, "effect failed")
      let captured = value
      cleanup(proc() = events[].add "event-cleanup:" & $captured)
    )
    occurrence.emit(1)
    expect ValueError:
      occurrence.emit(2)
    check events[][^1] == "event-cleanup:1"
    check effect.dispose()
    check events[].count("event-cleanup:1") == 1
    check runs == 2

  test "signal effects wait for the first occurrence":
    let root = initUiRoot()
    let events = new seq[string]
    let component = root.mount(EffectComponent(
      source: initState(0),
      events: events
    ))
    discard component.effectValue.dispose()
    events[].setLen(0)

    let occurrence = initSignal[string]()
    discard component.effect(occurrence, proc(value: string): EffectCleanup =
      events[].add value
      nil
    )
    check events[].len == 0
    occurrence.emit("ready")
    check events[] == @["ready"]

  test "reentrant state writes run in order without losing cleanup":
    let root = initUiRoot()
    let events = new seq[string]
    let component = root.mount(EffectComponent(
      source: initState(0),
      events: events
    ))
    discard component.effectValue.dispose()
    events[].setLen(0)
    let source = initState(1)

    let effect = component.effect(source, proc(value: int): EffectCleanup =
      events[].add "run:" & $value
      if value == 1:
        discard source.set(2)
      let captured = value
      cleanup(proc() = events[].add "cleanup:" & $captured)
    )
    check events[] == @["run:1", "cleanup:1", "run:2"]
    check effect.dispose()
    check events[][^1] == "cleanup:2"
