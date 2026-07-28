import std/unittest

import clay_board_style_system

suite "form component":
  test "valid form submits and emits onSubmit":
    let ui = initUiRoot()
    let login = ui.form()
    var submitted = false

    login.onSubmit = proc(event: DispatchResult): bool =
      submitted = true
      false

    check login.submit()
    check submitted
    check login.submitted() == 1

  test "invalid form emits onInvalid instead of onSubmit":
    let ui = initUiRoot()
    let login = ui.form(valid = false)
    var submitted = false
    var invalid = false

    login.onSubmit = proc(event: DispatchResult): bool =
      submitted = true
      false

    login.onInvalid = proc(event: DispatchResult): bool =
      invalid = true
      false

    check not login.submit()
    check invalid
    check not submitted
    check login.invalidCount() == 1
    check login.submitted() == 0

  test "reset emits onReset":
    let ui = initUiRoot()
    let login = ui.form()
    var reset = false

    login.onReset = proc(event: DispatchResult): bool =
      reset = true
      false

    check login.reset()
    check reset
    check login.resetCount() == 1

  test "disabled form suppresses submit reset and invalid":
    let ui = initUiRoot()
    let login = ui.form(disabled = true, valid = false)
    var seen = false

    login.onSubmit = proc(event: DispatchResult): bool =
      seen = true
      false

    login.onInvalid = proc(event: DispatchResult): bool =
      seen = true
      false

    login.onReset = proc(event: DispatchResult): bool =
      seen = true
      false

    check not login.submit()
    check not login.reset()
    check not seen
    check login.submitted() == 0
    check login.resetCount() == 0
    check login.invalidCount() == 0
    check esDisabled in ui.tree.nodes[login.container.nodeId.nodeIndex].states

  test "setValid and setDisabled update behavior":
    let ui = initUiRoot()
    let login = ui.form(valid = false)

    login.setValid(true)
    check login.submit()

    login.setDisabled(true)
    check login.disabled()
    check not login.submit()
    check esDisabled in ui.tree.nodes[login.container.nodeId.nodeIndex].states
