import std/[options, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type
  StoreActionKind = enum
    sakIncrement,
    sakRename

  StoreAction = object
    kind: StoreActionKind
    name: string

  StoreModel = object
    count: int
    name: string

  CountSelector = StoreSelector[StoreModel, StoreAction, int]

  SelectedComponent = ref object of CBSSComponent
    source: CountSelector
    values: ref seq[int]
    labelNode: NodeHandle

proc reduce(state: var StoreModel; action: StoreAction) =
  case action.kind
  of sakIncrement:
    inc state.count
  of sakRename:
    state.name = action.name

proc render(self: SelectedComponent) =
  ui.box(self):
    self.labelNode = ui.text("0")

method onMount(self: SelectedComponent) =
  discard self.watch(
    self.source,
    proc(value: int) = self.values[].add(value),
    dirtyDomains = {ddText, ddPaint},
    target = some(self.labelNode)
  )

suite "selected store state":
  test "selector evaluates once per commit and publishes changed values":
    let store = createStore(StoreModel(name: "ready"), reduce)
    var evaluations = 0
    let count = store.select(proc(state: StoreModel): int =
      inc evaluations
      state.count
    )
    var values: seq[int]
    discard count.signal.subscribe(proc(value: int) = values.add(value))

    store.dispatch(StoreAction(kind: sakIncrement))
    store.dispatch(StoreAction(kind: sakRename, name: "done"))

    check evaluations == 3
    check count.value == 1
    check values == @[1]

  test "transaction evaluates selector once using final state":
    let store = createStore(StoreModel(), reduce)
    var evaluations = 0
    let count = store.select(proc(state: StoreModel): int =
      inc evaluations
      state.count
    )
    var values: seq[int]
    discard count.signal.subscribe(proc(value: int) = values.add(value))

    store.transaction:
      store.dispatch(StoreAction(kind: sakIncrement))
      store.dispatch(StoreAction(kind: sakIncrement))
      store.dispatch(StoreAction(kind: sakIncrement))

    check evaluations == 2
    check count.value == 3
    check values == @[3]

  test "custom selector equality suppresses equivalent publication":
    let store = createStore(StoreModel(name: "ready"), reduce)
    let name = store.select(
      proc(state: StoreModel): string = state.name,
      proc(left, right: string): bool = left.toLowerAscii == right.toLowerAscii
    )
    var values: seq[string]
    discard name.signal.subscribe(proc(value: string) = values.add(value))

    store.dispatch(StoreAction(kind: sakRename, name: "READY"))
    store.dispatch(StoreAction(kind: sakRename, name: "done"))

    check values == @["done"]

  test "component selector watch invalidates only its declared target":
    let root = initUiRoot()
    let store = createStore(StoreModel(count: 2), reduce)
    let count = store.select(proc(state: StoreModel): int = state.count)
    let values = new seq[int]
    let component = root.mount(SelectedComponent(source: count, values: values))

    check values[] == @[2]
    check count.subscriberCount == 1
    discard root.consumeInvalidation()
    store.dispatch(StoreAction(kind: sakIncrement))

    check values[] == @[2, 3]
    let invalidation = root.consumeInvalidation()
    check invalidation.domains == {ddText, ddPaint}
    check invalidation.roots == @[component.labelNode.id]

  test "component selector watch detaches at unmount":
    let root = initUiRoot()
    let store = createStore(StoreModel(), reduce)
    let count = store.select(proc(state: StoreModel): int = state.count)
    let values = new seq[int]
    let component = root.mount(SelectedComponent(source: count, values: values))
    var interaction = initInteractionState()

    check root.disposeSubtree(component.node, interaction)
    check count.subscriberCount == 0
    store.dispatch(StoreAction(kind: sakIncrement))
    check values[] == @[0]

  test "refresh observes an explicitly silent store mutation":
    let store = createStore(StoreModel(), reduce)
    let count = store.select(proc(state: StoreModel): int = state.count)

    store.dispatchSilent(StoreAction(kind: sakIncrement))
    check count.value == 0
    count.refresh()
    check count.value == 1

  test "disposing selector detaches it from future commits":
    let store = createStore(StoreModel(), reduce)
    var evaluations = 0
    let count = store.select(proc(state: StoreModel): int =
      inc evaluations
      state.count
    )

    check count.dispose()
    check not count.dispose()
    store.dispatch(StoreAction(kind: sakIncrement))
    check evaluations == 1
    expect ValueError:
      count.refresh()
    expect ValueError:
      discard count.value

  test "one failing selector listener does not stale another selector":
    let store = createStore(StoreModel(name: "ready"), reduce)
    let count = store.select(proc(state: StoreModel): int = state.count)
    discard count.signal.subscribe(proc(value: int) =
      raise newException(ValueError, "count listener failed")
    )
    let name = store.select(proc(state: StoreModel): string = state.name)
    var names: seq[string]
    discard name.signal.subscribe(proc(value: string) = names.add(value))

    expect ValueError:
      store.transaction:
        store.dispatch(StoreAction(kind: sakIncrement))
        store.dispatch(StoreAction(kind: sakRename, name: "done"))

    check count.value == 1
    check name.value == "done"
    check names == @["done"]

  test "invalid selector construction fails before subscription":
    var store: StateRuntime[StoreModel, StoreAction]
    expect ValueError:
      discard store.select(proc(state: StoreModel): int = state.count)

    let activeStore = createStore(StoreModel(), reduce)
    expect ValueError:
      discard select[StoreModel, StoreAction, int](activeStore, nil)
