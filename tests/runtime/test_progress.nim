import std/[math, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

suite "progress component":
  test "progress initializes value percent and visible labels":
    let ui = initUiRoot()
    let upload = ui.progress(value = 30, max = 100)

    check upload.value() == 30
    check upload.maxValue() == 100
    check upload.percent() == 0.3'f32
    check ui.tree.nodes[upload.valueNode.nodeId.nodeIndex].text == "30%"
    check ui.tree.nodes[upload.fillNode.nodeId.nodeIndex].kind == nkBox

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(140, 40))
    var fillWidth = -1'f32
    for box in layout.boxes:
      if box.node == upload.fillNode.nodeId:
        fillWidth = box.rect.w
    check abs(fillWidth - 30'f32) < 0.001'f32

  test "progress clamps value to range":
    let ui = initUiRoot()
    let upload = ui.progress(value = 120, max = 100)

    check upload.value() == 100
    check ui.tree.nodes[upload.valueNode.nodeId.nodeIndex].text == "100%"

    upload.setValue(-5)
    check upload.value() == 0
    check ui.tree.nodes[upload.valueNode.nodeId.nodeIndex].text == "0%"

  test "setMax normalizes max and reclamps value":
    let ui = initUiRoot()
    let upload = ui.progress(value = 80, max = 100)

    upload.setMax(40)

    check upload.maxValue() == 40
    check upload.value() == 40
    check ui.tree.nodes[upload.valueNode.nodeId.nodeIndex].text == "100%"

  test "indeterminate state uses active state and sentinel percent":
    let ui = initUiRoot()
    let upload = ui.progress(indeterminate = true)

    check upload.indeterminate()
    check upload.percent() == -1
    check esActive in ui.tree.nodes[upload.container.nodeId.nodeIndex].states
    check ui.tree.nodes[upload.valueNode.nodeId.nodeIndex].text == "indeterminate"

    upload.setValue(0.5)

    check not upload.indeterminate()
    check esActive notin ui.tree.nodes[upload.container.nodeId.nodeIndex].states
    check ui.tree.nodes[upload.valueNode.nodeId.nodeIndex].text == "50%"

  test "setIndeterminate toggles visible state":
    let ui = initUiRoot()
    let upload = ui.progress(value = 1, max = 4)

    upload.setIndeterminate(true)

    check upload.indeterminate()
    check esActive in ui.tree.nodes[upload.container.nodeId.nodeIndex].states
    check ui.tree.nodes[upload.valueNode.nodeId.nodeIndex].text == "indeterminate"
