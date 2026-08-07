import std/[options, unittest]

import clay_board_style_system

suite "form component":
  test "valid form submits and emits onSubmit":
    let ui = initUiRoot()
    let login = ui.form()
    var submitted = false

    login.onSubmit = proc(event: DispatchResult): EventOutcome =
      check event.formData.isSome
      check event.formData.get.isEmpty
      submitted = true
      ignoredEvent()

    check login.submit()
    check submitted
    check login.submitted() == 1

  test "invalid form emits onInvalid instead of onSubmit":
    let ui = initUiRoot()
    let login = ui.form(valid = false)
    var submitted = false
    var invalid = false

    login.onSubmit = proc(event: DispatchResult): EventOutcome =
      submitted = true
      ignoredEvent()

    login.onInvalid = proc(event: DispatchResult): EventOutcome =
      invalid = true
      ignoredEvent()

    check not login.submit()
    check invalid
    check not submitted
    check login.invalidCount() == 1
    check login.submitted() == 0

  test "reset emits onReset":
    let ui = initUiRoot()
    let login = ui.form()
    var reset = false

    login.onReset = proc(event: DispatchResult): EventOutcome =
      reset = true
      ignoredEvent()

    check login.reset()
    check reset
    check login.resetCount() == 1

  test "disabled form suppresses submit reset and invalid":
    let ui = initUiRoot()
    let login = ui.form(disabled = true, valid = false)
    var seen = false

    login.onSubmit = proc(event: DispatchResult): EventOutcome =
      seen = true
      ignoredEvent()

    login.onInvalid = proc(event: DispatchResult): EventOutcome =
      seen = true
      ignoredEvent()

    login.onReset = proc(event: DispatchResult): EventOutcome =
      seen = true
      ignoredEvent()

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

  test "collectData snapshots ordered descendant control values":
    let ui = initUiRoot()
    let login = ui.form()
    ui.pushParent(login.container)
    let username = ui.textInput(TextInputParams(value: "Ada"))
    let notes = ui.textArea(TextAreaParams(value: "First line"))
    let role = ui.selectBox(
      [
        SelectOption(label: "Reader", value: "reader"),
        SelectOption(label: "Editor", value: "editor")
      ],
      selectedValue = "editor"
    )
    let remember = ui.checkbox(CheckboxParams(
      label: "Remember",
      checked: true
    ))
    let disabled = ui.textInput(TextInputParams(
      value: "not submitted",
      disabled: true
    ))
    ui.popParent()

    login.register("account", username)
    login.register("notes", notes)
    login.register("role", role)
    login.register("remember", remember)
    login.register("ignored", disabled)

    let collection = login.collectData()

    check collection.diagnostics.len == 0
    check collection.data.len == 4
    check collection.data[0].name == "account"
    check collection.data[0].text == "Ada"
    check collection.data[1].text == "First line"
    check collection.data[2].text == "editor"
    check collection.data[3].text == "true"

    username.setValue("Grace")
    check collection.data[0].text == "Ada"
    check login.collectData().data[0].text == "Grace"

  test "submit carries one immutable snapshot of successful controls":
    let ui = initUiRoot()
    let profile = ui.form()
    ui.pushParent(profile.container)
    let name = ui.textInput(TextInputParams(value: "Ada"))
    let enabled = ui.checkbox("Enabled", checked = true)
    let omitted = ui.checkbox("Omitted", checked = false)
    let disabled = ui.textInput(TextInputParams(
      value: "secret",
      disabled: true
    ))
    ui.popParent()
    profile.register("name", name)
    profile.register("enabled", enabled)
    profile.register("omitted", omitted)
    profile.register("disabled", disabled)

    var captured = FormData()
    profile.onSubmit = proc(event: DispatchResult): EventOutcome =
      check event.formData.isSome
      captured = event.formData.get
      name.setValue("Grace")
      ignoredEvent()

    check profile.submit()
    check captured.len == 2
    check captured[0].name == "name"
    check captured[0].text == "Ada"
    check captured[1].name == "enabled"
    check captured[1].text == "true"
    check profile.collectData().data[0].text == "Grace"

  test "invalid and disabled forms never publish a submit snapshot":
    let ui = initUiRoot()
    let invalid = ui.form(valid = false)
    let disabled = ui.form(disabled = true)
    var submitEvents = 0
    let observe = proc(event: DispatchResult): EventOutcome =
      inc submitEvents
      ignoredEvent()
    invalid.onSubmit = observe
    disabled.onSubmit = observe

    check not invalid.submit()
    check not disabled.submit()
    check submitEvents == 0

  test "checkable fields submit only their checked value":
    let ui = initUiRoot()
    let preferences = ui.form()
    let choices = initRadioSet("compact")
    ui.pushParent(preferences.container)
    let compact = ui.radio(choices, "Compact", "compact")
    let spacious = ui.radio(choices, "Spacious", "spacious")
    let unchecked = ui.checkbox("Optional")
    ui.popParent()

    preferences.register("density", compact)
    preferences.register("density", spacious)
    preferences.register("optional", unchecked)

    let initial = preferences.collectData()
    check initial.data.len == 1
    check initial.data[0].name == "density"
    check initial.data[0].text == "compact"

    spacious.select(emitEvents = false)
    let changed = preferences.collectData()
    check changed.data.len == 1
    check changed.data[0].text == "spacious"

  test "registration rejects unrelated nodes and reports disposed fields":
    let ui = initUiRoot()
    let login = ui.form()
    let outside = ui.textInput(TextInputParams(value: "outside"))
    ui.pushParent(login.container)
    let temporary = ui.textInput(TextInputParams(value: "temporary"))
    ui.popParent()

    expect ValueError:
      login.register("outside", outside)

    login.register("temporary", temporary)
    var interaction = initInteractionState()
    check ui.disposeSubtree(temporary.container, interaction)
    let collection = login.collectData()

    check collection.data.isEmpty
    check collection.diagnostics.len == 1
    check collection.diagnostics[0].kind == fddDisposedField
    check collection.diagnostics[0].name == "temporary"
