import std/[sequtils, unittest]

import clay_board_style_system

type StreamComponent = ref object of CBSSComponent
  binding: ComponentStreamBinding[string]

type FailingMountStreamComponent = ref object of CBSSComponent
  binding: ComponentStreamBinding[string]
  escapedProducer: ref StreamProducer[string]

proc render(self: StreamComponent) =
  ui.box(self):
    ui.text("stream consumer")

method onMount(self: StreamComponent) =
  self.binding = self.attachStream(
    string,
    maxQueuedItems = 4,
    maxQueuedWeight = 64,
    dirtyDomains = {ddResource, ddPaint}
  )

proc render(self: FailingMountStreamComponent) =
  ui.box(self):
    ui.text("failing stream consumer")

method onMount(self: FailingMountStreamComponent) =
  self.binding = self.attachStream(string)
  self.escapedProducer[] = self.binding.producer()
  check self.escapedProducer[].open() == smorAccepted
  check self.escapedProducer[].pushData("queued", 6) == smorAccepted
  raise newException(ValueError, "mount failed after stream attachment")

suite "component-owned stream binding":
  test "pumping marks only configured dirty domains when state changes":
    let root = initUiRoot()
    let component = root.mount(StreamComponent())
    let source = component.binding.producer()
    var scheduler = initFrameScheduler()

    check component.binding.dirtyDomains == {ddResource, ddPaint}
    check source.open() == smorAccepted
    check source.pushData("payload", 7) == smorAccepted
    check source.finish() == smorAccepted
    let pumped = component.binding.pump(scheduler)
    check pumped.processed == 3
    check pumped.changed
    check scheduler.consumeDirty() == {ddResource, ddPaint}
    check component.binding.pending

    let events = component.binding.drain()
    check events.mapIt(it.kind) == @[sekOpen, sekData, sekEnd]
    check events[1].data == "payload"
    check not component.binding.pending

    let idle = component.binding.pump(scheduler)
    check not idle.changed
    check scheduler.consumeDirty() == {}

  test "subtree disposal invalidates escaped worker handles":
    let root = initUiRoot()
    let component = root.mount(StreamComponent())
    let source = component.binding.producer()
    check source.open() == smorAccepted
    check source.pushData("queued", 6) == smorAccepted

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check component.binding.disposed
    check source.state == ssClosed
    check source.pushData("late", 4) == smorDisposed
    check component.binding.drain().len == 0

  test "explicit binding disposal remains idempotent at component unmount":
    let root = initUiRoot()
    let component = root.mount(StreamComponent())
    let source = component.binding.producer()
    check component.binding.dispose()
    check not component.binding.dispose()
    check source.open() == smorDisposed

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check component.binding.disposed

  test "attachment is rejected outside a mounted component lifecycle":
    let component = StreamComponent()
    expect ComponentContextError:
      discard component.attachStream(int)

  test "mount rollback disposes an attached stream and escaped producer":
    let root = initUiRoot()
    let escapedProducer = new StreamProducer[string]
    let component = FailingMountStreamComponent(
      escapedProducer: escapedProducer
    )

    expect ValueError:
      root.mount(component)

    check component.state == cmsUnmounted
    check component.binding.disposed
    check escapedProducer[].state == ssClosed
    check escapedProducer[].pushData("late", 4) == smorDisposed

  test "nil and disposed bindings are inert":
    let missing: ComponentStreamBinding[int] = nil
    var scheduler = initFrameScheduler()
    check missing.producer().state == ssClosed
    check not missing.pending
    check not missing.pump(scheduler).changed
    check missing.drain().len == 0
