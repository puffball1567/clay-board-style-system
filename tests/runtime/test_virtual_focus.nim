import std/[options, tables, unittest]

import clay_board_style_system

proc planAt(offset: float32): VirtualRangePlan =
  planVirtualRange(
    100,
    virtualViewport(offset, 30),
    virtualizationConfig(
      estimatedItemExtent = 10,
      maxMaterializedItems = 8
    )
  )

proc keysFor(plan: VirtualRangePlan): seq[int] =
  for item in plan.items:
    result.add item.index

suite "stable-key virtual focus retention":
  test "explicit code restores the intended child after internal reordering":
    let ui = initUiRoot()
    let host = ui.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let focusMemory = initVirtualFocusMemory[int]()
    var reverseChildren = false
    var editorByKey = initTable[int, NodeHandle]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = ui.box()
      if reverseChildren:
        let other = ui.box(parent = some(result), code = "other")
        other.setFocusable()
      let editor = ui.box(parent = some(result), code = "editor")
      editor.setFocusable()
      editorByKey[key] = editor
      if not reverseChildren:
        let other = ui.box(parent = some(result), code = "other")
        other.setFocusable()

    let firstPlan = planAt(0)
    discard pool.reconcileVirtualNodes(
      ui,
      host,
      interaction,
      firstPlan,
      firstPlan.keysFor(),
      mount,
      focusMemory = focusMemory
    )
    check ui.setFocus(
      interaction,
      some(editorByKey[0].id),
      focusVisible = true
    )

    let awayPlan = planAt(20)
    discard pool.reconcileVirtualNodes(
      ui,
      host,
      interaction,
      awayPlan,
      awayPlan.keysFor(),
      mount,
      focusMemory = focusMemory
    )
    check interaction.focusedTarget.isNone
    check focusMemory.pendingKey() == some(0)

    reverseChildren = true
    discard pool.reconcileVirtualNodes(
      ui,
      host,
      interaction,
      firstPlan,
      firstPlan.keysFor(),
      mount,
      focusMemory = focusMemory
    )

    check interaction.focusedTarget == some(editorByKey[0].id)
    check esFocusVisible in ui.tree.nodes[editorByKey[0].id.nodeIndex].states
    check not focusMemory.hasPendingFocus

  test "structural path restores a target without an explicit code":
    let ui = initUiRoot()
    let host = ui.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let focusMemory = initVirtualFocusMemory[int]()
    var targetByKey = initTable[int, NodeHandle]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = ui.box()
      let wrapper = ui.box(parent = some(result))
      let target = ui.box(parent = some(wrapper))
      target.setFocusable()
      targetByKey[key] = target

    let visible = planAt(0)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )
    check ui.setFocus(interaction, some(targetByKey[0].id), focusVisible = false)
    let away = planAt(20)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, away, away.keysFor(), mount,
      focusMemory = focusMemory
    )
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )

    check interaction.focusedTarget == some(targetByKey[0].id)
    check esFocus in ui.tree.nodes[targetByKey[0].id.nodeIndex].states
    check esFocusVisible notin ui.tree.nodes[targetByKey[0].id.nodeIndex].states

  test "a later focus operation cancels pending virtual restoration":
    let ui = initUiRoot()
    let host = ui.box()
    let outside = ui.box()
    outside.setFocusable()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let focusMemory = initVirtualFocusMemory[int]()
    var targetByKey = initTable[int, NodeHandle]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = ui.box()
      let target = ui.box(parent = some(result), code = "target")
      target.setFocusable()
      targetByKey[key] = target

    let visible = planAt(0)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )
    discard ui.setFocus(interaction, some(targetByKey[0].id), true)
    let away = planAt(20)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, away, away.keysFor(), mount,
      focusMemory = focusMemory
    )
    check focusMemory.hasPendingFocus

    discard ui.setFocus(interaction, some(outside.id), true)
    discard ui.setFocus(interaction, none(NodeId), true)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )

    check interaction.focusedTarget.isNone
    check not focusMemory.hasPendingFocus

  test "a removed explicit code cannot redirect focus to the old child path":
    let ui = initUiRoot()
    let host = ui.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let focusMemory = initVirtualFocusMemory[int]()
    var includeEditor = true
    var targetByKey = initTable[int, NodeHandle]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = ui.box()
      let code = if includeEditor: "editor" else: "replacement"
      let target = ui.box(parent = some(result), code = code)
      target.setFocusable()
      targetByKey[key] = target

    let visible = planAt(0)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )
    discard ui.setFocus(interaction, some(targetByKey[0].id), true)
    let away = planAt(20)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, away, away.keysFor(), mount,
      focusMemory = focusMemory
    )
    includeEditor = false
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )

    check interaction.focusedTarget.isNone
    check not focusMemory.hasPendingFocus
    check targetByKey[0].focusable

  test "a retained focused key keeps its original Node ID without a pending record":
    let ui = initUiRoot()
    let host = ui.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let focusMemory = initVirtualFocusMemory[int]()
    var targetByKey = initTable[int, NodeHandle]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = ui.box()
      let target = ui.box(parent = some(result))
      target.setFocusable()
      targetByKey[key] = target

    let first = planAt(0)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, first, first.keysFor(), mount,
      focusMemory = focusMemory
    )
    let retainedTarget = targetByKey[2]
    discard ui.setFocus(interaction, some(retainedTarget.id), true)
    let second = planAt(20)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, second, second.keysFor(), mount,
      focusMemory = focusMemory
    )

    check interaction.focusedTarget == some(retainedTarget.id)
    check retainedTarget.valid
    check not focusMemory.hasPendingFocus

  test "clearing and rebuilding a pool can restore the same logical item":
    let ui = initUiRoot()
    let host = ui.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let focusMemory = initVirtualFocusMemory[int]()
    var targetByKey = initTable[int, NodeHandle]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = ui.box()
      let target = ui.box(parent = some(result), code = "target")
      target.setFocusable()
      targetByKey[key] = target

    let visible = planAt(0)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )
    discard ui.setFocus(interaction, some(targetByKey[1].id), true)
    check pool.clearVirtualNodes(ui, host, interaction, focusMemory) == 3
    check interaction.focusedTarget.isNone
    check focusMemory.pendingKey() == some(1)

    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )
    check interaction.focusedTarget == some(targetByKey[1].id)
    check not focusMemory.hasPendingFocus

  test "duplicate explicit codes fail closed instead of choosing arbitrarily":
    let ui = initUiRoot()
    let host = ui.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let focusMemory = initVirtualFocusMemory[int]()
    var duplicateOnRemount = false
    var targetByKey = initTable[int, NodeHandle]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = ui.box()
      let target = ui.box(parent = some(result), code = "target")
      target.setFocusable()
      targetByKey[key] = target
      if duplicateOnRemount:
        let duplicate = ui.box(parent = some(result), code = "target")
        duplicate.setFocusable()

    let visible = planAt(0)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )
    discard ui.setFocus(interaction, some(targetByKey[0].id), true)
    let away = planAt(20)
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, away, away.keysFor(), mount,
      focusMemory = focusMemory
    )
    duplicateOnRemount = true
    discard pool.reconcileVirtualNodes(
      ui, host, interaction, visible, visible.keysFor(), mount,
      focusMemory = focusMemory
    )

    check interaction.focusedTarget.isNone
    check not focusMemory.hasPendingFocus
