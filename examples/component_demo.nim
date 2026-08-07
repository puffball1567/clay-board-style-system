import std/options

import clay_board_style_system
import clay_board_style_system/generated/default_properties

type
  SaveButton = ref object of CBSSComponent
    label: string
    saved: ref bool

  Toolbar = ref object of CBSSComponent
    saveButton: SaveButton

proc saveButtonStyle(): UiStyle =
  uiStyle([
    width(112),
    height(40),
    padding(10),
    decl("background-color", oklch(0.62, 0.16, 250))
  ])

proc render(self: SaveButton) =
  proc onSave(event: DispatchResult): EventOutcome =
    self.saved[] = true
    return stoppedEvent()

  ui.box(self, ownedStyle = saveButtonStyle()):
    ui.text(self.label)

  self.onClick = onSave

proc render(self: Toolbar) =
  ui.box(self, ownedStyle = uiStyle([
    width(320),
    padding(12),
    gap(8),
    flexDirection(fdRow)
  ])):
    ui.text("Project")
    ui.mount(self.saveButton)

proc main() =
  let saved = new bool
  let root = initUiRoot()
  let saveButton = SaveButton(
    label: "Save",
    saved: saved,
    style: uiStyle([height(48)])
  )
  let toolbar = root.mount(Toolbar(saveButton: saveButton))

  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(
    root.tree,
    root.styleSheets(),
    defaultProperties(),
    diagnostics,
    viewportSize = some(size(320, 80))
  )
  doAssert not diagnostics.hasErrors
  let layout = computeLayout(root.tree, styles, size(320, 80))
  doAssert layout.boxes.len > 0
  doAssert toolbar.mounted
  doAssert root.events.emit(root.tree, saveButton.node.id, iekClick)
  doAssert saved[]

  echo "Mounted Toolbar and handled SaveButton.onClick"

when isMainModule:
  main()
