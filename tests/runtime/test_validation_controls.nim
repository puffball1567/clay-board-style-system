import std/[options, unittest]

import clay_board_style_system

suite "validating controls":
  test "onInput text input reports required after a focus and blur cycle":
    let ui = initUiRoot()
    let input = ui.textInput(
      "",
      validationRules[string]().required("Required"),
      reportOn = ValidationReport.onInput
    )

    check not input.validationResult.isValid
    check input.validationMessage.len == 0
    check esInvalid notin ui.tree.nodes[input.container.nodeId.nodeIndex].states
    input.focus()
    input.blur()
    check input.validationMessage == "Required"
    check esInvalid in ui.tree.nodes[input.container.nodeId.nodeIndex].states

  test "textarea tracks current validity and reports on blur":
    let ui = initUiRoot()
    let area = ui.textArea(
      "short",
      validationRules[string]().minLength(10, "Write more"),
      reportOn = ValidationReport.onBlur
    )

    check not area.validationResult.isValid
    check area.validationMessage.len == 0
    check esInvalid notin ui.tree.nodes[area.container.nodeId.nodeIndex].states
    area.blur()
    check area.validationMessage == "Write more"
    check esInvalid in ui.tree.nodes[area.container.nodeId.nodeIndex].states
    area.setValue("long enough text")
    check area.validationResult.isValid
    check esInvalid notin ui.tree.nodes[area.container.nodeId.nodeIndex].states

  test "select validates the selected value":
    let ui = initUiRoot()
    let select = ui.selectBox(
      [
        SelectOption(label: "Choose", value: ""),
        SelectOption(label: "Editor", value: "editor")
      ],
      validationRules[string]().required("Choose a role"),
      reportOn = ValidationReport.onInput
    )

    check not select.validationResult.isValid
    check esInvalid notin ui.tree.nodes[select.container.nodeId.nodeIndex].states
    select.setSelectedValue("editor", emitEvents = true)
    check select.validationResult.isValid
    check select.validationMessage.len == 0
    select.setSelectedValue("", emitEvents = true)
    check esInvalid in ui.tree.nodes[select.container.nodeId.nodeIndex].states

  test "checkbox can require affirmative consent":
    let ui = initUiRoot()
    let consent = ui.checkbox(
      "Consent",
      validationRules[bool]().equalTo(true, "Consent is required"),
      reportOn = ValidationReport.onInput
    )

    check not consent.validationResult.isValid
    check esInvalid notin ui.tree.nodes[consent.container.nodeId.nodeIndex].states
    consent.toggle()
    check consent.checked
    check consent.validationResult.isValid
    consent.toggle()
    check esInvalid in ui.tree.nodes[consent.container.nodeId.nodeIndex].states

  test "radio set validates one shared selected value":
    let ui = initUiRoot()
    let choices = initRadioSet()
    let compact = ui.radio(choices, "Compact", "compact")
    let spacious = ui.radio(choices, "Spacious", "spacious")
    choices.setValidation(
      validationRules[string]().required("Choose a density"),
      ValidationReport.onSubmit
    )

    check not choices.validationResult.isValid
    check esInvalid notin ui.tree.nodes[compact.container.nodeId.nodeIndex].states
    check esInvalid notin ui.tree.nodes[spacious.container.nodeId.nodeIndex].states
    check not choices.reportValidity()
    check esInvalid in ui.tree.nodes[compact.container.nodeId.nodeIndex].states
    check esInvalid in ui.tree.nodes[spacious.container.nodeId.nodeIndex].states
    spacious.select()
    check choices.validationResult.isValid
    check esInvalid notin ui.tree.nodes[compact.container.nodeId.nodeIndex].states
    check esInvalid notin ui.tree.nodes[spacious.container.nodeId.nodeIndex].states

  test "file input validates immutable Blob metadata":
    let ui = initUiRoot()
    let input = ui.fileInput(
      FileInputParams(multiple: true),
      validationRules[seq[ValidationFile]]()
        .required("Choose a file")
        .maxFiles(1, "Choose one file")
        .maxFileSize(4, "File is too large")
        .allowedMimeTypes(["text/plain"])
        .allowedExtensions(["txt"]),
      reportOn = ValidationReport.onInput
    )

    check not input.validationResult.isValid
    check esInvalid notin ui.tree.nodes[input.container.nodeId.nodeIndex].states
    input.setFiles([
      fileInputValue(newBlob([byte 1, 2, 3], mimeType = "text/plain"), "note.txt")
    ], emitEvents = true)
    check input.validationResult.isValid

    input.setFiles([
      fileInputValue(newBlob([byte 1, 2, 3, 4, 5], mimeType = "text/plain"), "large.txt")
    ], emitEvents = true)
    check not input.validationResult.isValid
    check input.validationMessage == "File is too large"
    check esInvalid in ui.tree.nodes[input.container.nodeId.nodeIndex].states

  test "validation message remains queryable through the retained attribute":
    let ui = initUiRoot()
    let input = ui.textInput(
      "",
      validationRules[string]().required("Required"),
      reportOn = ValidationReport.onBlur
    )
    input.blur()

    check ui.tree.nodes[input.container.nodeId.nodeIndex]
      .attrValue("validation-message") == some("Required")

  test "cross-field dependencies revalidate only explicit dependants":
    let ui = initUiRoot()
    let password = ui.textInput(TextInputParams(value: "secret"))
    let confirmation = ui.textInput(TextInputParams(value: "secret"))
    let unrelated = ui.textInput(
      "stable",
      validationRules[string]().equalTo("stable")
    )
    confirmation.setValidation(
      validationRules[string]().sameAs(
        password.validationValue,
        "Passwords do not match"
      )
    )

    check confirmation.validationResult.isValid
    password.setValue("changed")
    check not confirmation.validationResult.isValid
    check unrelated.validationResult.isValid
    confirmation.setValue("changed")
    check confirmation.validationResult.isValid

  test "disposing a dependent control removes its retained dependency callback":
    let ui = initUiRoot()
    let source = ui.textInput(TextInputParams(value: "first"))
    let dependent = ui.textInput(TextInputParams(value: "first"))
    dependent.setValidation(
      validationRules[string]().sameAs(source.validationValue)
    )
    var interaction = initInteractionState()

    check ui.disposeSubtree(dependent.container, interaction)
    source.setValue("second")
    check not dependent.container.valid()

  test "dependency dispatch is source-indexed and suppresses recursive refresh":
    let ui = initUiRoot()
    let sourceA = initValidationValue("a")
    let sourceB = initValidationValue("b")
    let targetA = ui.box(code = "validation-target-a")
    let targetB = ui.box(code = "validation-target-b")
    var refreshedA = 0
    var refreshedB = 0

    ui.registerValidationDependency(
      sourceA.identity,
      targetA.nodeId,
      proc() =
        inc refreshedA
        ui.notifyValidationDependencies(sourceA.identity)
    )
    ui.registerValidationDependency(
      sourceB.identity,
      targetB.nodeId,
      proc() = inc refreshedB
    )

    ui.notifyValidationDependencies(sourceA.identity)
    check refreshedA == 1
    check refreshedB == 0

  test "replacing validation removes the previous cross-field dependency":
    let ui = initUiRoot()
    let firstSource = ui.textInput(TextInputParams(value: "first"))
    let secondSource = ui.textInput(TextInputParams(value: "second"))
    let dependent = ui.textInput(TextInputParams(value: "first"))

    dependent.setValidation(
      validationRules[string]().sameAs(firstSource.validationValue)
    )
    dependent.setValidation(
      validationRules[string]().sameAs(secondSource.validationValue)
    )
    dependent.setValue("second")
    check dependent.validationResult.isValid

    firstSource.setValue("changed")
    check dependent.validationResult.isValid
    secondSource.setValue("changed")
    check not dependent.validationResult.isValid
