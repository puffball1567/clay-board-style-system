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

  test "registered control validation blocks submit and focuses the first invalid field":
    let ui = initUiRoot()
    let login = ui.form()
    ui.pushParent(login.container)
    let username = ui.textInput(
      "",
      validationRules[string]().required("Username is required"),
      reportOn = ValidationReport.onSubmit
    )
    let emailInput = ui.textInput(
      "bad",
      validationRules[string]().email("Email is invalid"),
      reportOn = ValidationReport.onSubmit
    )
    ui.popParent()
    login.register("username", username)
    login.register("email", emailInput)

    var submitted = false
    var invalidEvents = 0
    login.onSubmit = proc(event: DispatchResult): EventOutcome =
      submitted = true
      ignoredEvent()
    username.container.onInvalid = proc(event: DispatchResult): EventOutcome =
      inc invalidEvents
      ignoredEvent()
    emailInput.container.onInvalid = proc(event: DispatchResult): EventOutcome =
      inc invalidEvents
      ignoredEvent()

    check not login.checkValidity()
    check username.validationMessage.len == 0
    check not login.submit()
    check not submitted
    check invalidEvents == 2
    check login.invalidCount == 1
    check ui.focusRequestPending
    check ui.focusRequestTarget == some(username.container.nodeId)
    check username.validationMessage == "Username is required"
    check esInvalid in ui.tree.nodes[username.container.nodeId.nodeIndex].states

  test "valid controls submit one immutable FormData snapshot":
    let ui = initUiRoot()
    let profile = ui.form()
    ui.pushParent(profile.container)
    let name = ui.textInput(
      "Ada",
      validationRules[string]().required().minLength(2)
    )
    let terms = ui.checkbox(
      "Accept terms",
      validationRules[bool]().equalTo(true, "Accept the terms"),
      checked = true
    )
    ui.popParent()
    profile.register("name", name)
    profile.register("terms", terms)

    var captured = FormData()
    profile.onSubmit = proc(event: DispatchResult): EventOutcome =
      captured = event.formData.get
      ignoredEvent()

    check profile.checkValidity()
    check profile.reportValidity()
    check profile.submit()
    check captured.len == 2
    check captured[0].text == "Ada"
    check captured[1].text == "true"

  test "disabled validating controls are excluded from validation":
    let ui = initUiRoot()
    let form = ui.form()
    ui.pushParent(form.container)
    let disabled = ui.textInput(
      "",
      validationRules[string]().required(),
      disabled = true
    )
    ui.popParent()
    form.register("disabled", disabled)

    check form.checkValidity()
    check form.submit()

  test "onBlur reporting keeps invalid input editable and clears after correction":
    let ui = initUiRoot()
    let input = ui.textInput(
      "",
      validationRules[string]().required("Required"),
      reportOn = ValidationReport.onBlur
    )

    check not input.validationResult.isValid
    check input.validationMessage.len == 0
    input.blur()
    check input.validationMessage == "Required"
    input.setValue("corrected")
    check input.validationResult.isValid
    check input.validationMessage.len == 0

  test "all validating control adapters participate in one form validity matrix":
    let ui = initUiRoot()
    let form = ui.form()
    let radios = initRadioSet()
    ui.pushParent(form.container)
    let text = ui.textInput("", validationRules[string]().required())
    let area = ui.textArea("", validationRules[string]().required())
    let select = ui.selectBox(
      [SelectOption(label: "Choose", value: "")],
      validationRules[string]().required()
    )
    let checkbox = ui.checkbox(
      "Consent",
      validationRules[bool]().equalTo(true)
    )
    let radio = ui.radio(radios, "Choice", "choice")
    radios.setValidation(validationRules[string]().required())
    let file = ui.fileInput(
      FileInputParams(),
      validationRules[seq[ValidationFile]]().required()
    )
    ui.popParent()

    form.register("text", text)
    form.register("area", area)
    form.register("select", select)
    form.register("checkbox", checkbox)
    form.register("radio", radio)
    form.register("file", file)
    check not form.checkValidity()

    text.setDisabled(true)
    area.setDisabled(true)
    select.setDisabled(true)
    checkbox.setDisabled(true)
    radio.setDisabled(true)
    file.setDisabled(true)

    check text.checkValidity() and text.reportValidity()
    check area.checkValidity() and area.reportValidity()
    check select.checkValidity() and select.reportValidity()
    check checkbox.checkValidity() and checkbox.reportValidity()
    check radios.checkValidity() and radios.reportValidity()
    check file.checkValidity() and file.reportValidity()
    for node in [
      text.container,
      area.container,
      select.container,
      checkbox.container,
      radio.container,
      file.container
    ]:
      check esInvalid notin ui.tree.nodes[node.nodeId.nodeIndex].states
      check ui.tree.nodes[node.nodeId.nodeIndex]
        .attrValue("validation-message") == some("")
    check form.checkValidity()
    check form.submit()
