import std/options

import clay_board_style_system

const lifecycleIterations = 16

type LifecycleScreen = enum
  lcsHome,
  lcsDetails

type MemoryComponent = ref object of CBSSComponent
  clicks: ref int
  mounts: ref int
  unmounts: ref int

proc render(self: MemoryComponent) =
  proc handleClick(event: DispatchResult): EventOutcome =
    inc self.clicks[]
    return stoppedEvent()

  ui.box(self):
    ui.text("Typed component")

  self.onClick = handleClick

method onMount(self: MemoryComponent) =
  inc self.mounts[]

method onUnmount(self: MemoryComponent) =
  inc self.unmounts[]

proc exerciseWidgetLifecycle() =
  for iteration in 0 ..< lifecycleIterations:
    let navigator = initStackNavigator(lcsHome)
    let navigationFocus = initNavigationFocusMemory()
    var navigationInvalidation = initInvalidationState()
    var interaction = initInteractionState()
    navigator.addListener(proc(change: NavigationChange[LifecycleScreen]) =
      navigationInvalidation.markDirty(change.dirtyDomains)
    )
    navigator.addListener(proc(change: NavigationChange[LifecycleScreen]) =
      navigationFocus.captureFocus(change, interaction)
    )
    block:
      let ui = initUiRoot()

      let button = ui.button("Run " & $iteration)
      button.onClick = proc(event: DispatchResult): EventOutcome =
        button.setLabel("Replaced")
        ignoredEvent()
      button.onClick = proc(event: DispatchResult): EventOutcome =
        button.setLabel("Handled")
        stoppedEvent()
      discard button.container.emit(InputEvent(kind: iekClick))
      discard button.container.emit(keyDownEvent("Enter"))

      let detailsLink = ui.link(navigator, lcsDetails, "Open details")
      discard detailsLink.container.emit(InputEvent(kind: iekClick))
      doAssert navigator.currentDestination() == some(lcsDetails)
      doAssert navigationInvalidation.dirty()
      navigationFocus.restoreFocus(ui, interaction, detailsLink.container)
      discard navigator.back()

      let homeScreen = ui.box(groups = ["screen-home"])
      ui.pushParent(homeScreen)
      let homeScreenButton = ui.button("Home screen")
      ui.popParent()
      let detailsScreen = ui.box(groups = ["screen-details"])
      ui.pushParent(detailsScreen)
      let detailsScreenButton = ui.button("Details screen")
      ui.popParent()
      let screenHost = initNavigationScreenHost(ui, navigator)
      screenHost.registerScreen(
        lcsHome,
        homeScreen,
        focusFallback = some(homeScreenButton.container)
      )
      screenHost.registerScreen(
        lcsDetails,
        detailsScreen,
        focusFallback = some(detailsScreenButton.container)
      )
      screenHost.sync(interaction)
      discard ui.setFocus(
        interaction,
        some(homeScreenButton.container.nodeId),
        focusVisible = true
      )
      navigator.push(lcsDetails)
      screenHost.sync(interaction)
      discard navigator.back()
      screenHost.sync(interaction)

      let replacementHome = ui.box(groups = ["screen-home-replacement"])
      ui.pushParent(replacementHome)
      let replacementHomeButton = ui.button("Replacement home")
      ui.popParent()
      doAssert screenHost.replaceScreen(
        lcsHome,
        replacementHome,
        interaction,
        focusFallback = some(replacementHomeButton.container)
      )
      doAssert not homeScreen.valid()
      doAssert replacementHome.valid()
      homeScreenButton.setLabel("stale")
      doAssert ui.tree.nodes[replacementHomeButton.labelNode.id.nodeIndex].text ==
        "Replacement home"
      doAssert screenHost.unregisterScreen(lcsDetails, interaction)
      doAssert not detailsScreen.valid()
      doAssert screenHost.screenCount() == 1
      if iteration mod 2 == 0:
        doAssert screenHost.disconnect()

      let checkbox = ui.checkbox("Enabled")
      discard checkbox.container.emit(InputEvent(kind: iekClick))

      let switchControl = ui.switch("Live updates")
      discard switchControl.container.emit(InputEvent(kind: iekClick))
      doAssert switchControl.checked()

      let details = ui.details("Details", "Lifecycle body")
      discard details.summaryNode.emit(InputEvent(kind: iekClick))
      details.setOpen(false)

      let dialog = ui.dialog(title = "Confirm", body = "Continue?", open = true)
      discard dialog.container.emit(keyDownEvent("Escape"))

      let fieldset = ui.fieldset("Options")
      fieldset.setDisabled(true)
      fieldset.setDisabled(false)

      let form = ui.form()
      doAssert form.submit()
      doAssert form.reset()

      let uploadForm = ui.form()
      ui.pushParent(uploadForm.container)
      let fileInput = ui.fileInput(FileInputParams(multiple: true))
      ui.popParent()
      uploadForm.register("attachment", fileInput)
      fileInput.onClick = proc(event: DispatchResult): EventOutcome =
        ignoredEvent()
      fileInput.setFiles([
        fileInputValue(newBlob([byte iteration]), "lifecycle.bin")
      ], emitEvents = true)
      let uploadSnapshot = uploadForm.collectData()
      doAssert uploadSnapshot.diagnostics.len == 0
      doAssert uploadSnapshot.data.len == 1
      fileInput.clear()

      let imageParent = ui.box(groups = ["image-parent"])
      let image = ui.image(imageParent, "asset.png", width = 32, height = 32)
      image.setSource("asset-updated.png")

      let input = ui.textInput(TextInputParams(value: "input"))
      let label = ui.label("Input", input)
      discard label.container.emit(InputEvent(kind: iekClick))
      discard input.container.emit(textInputEvent(" value"))
      discard input.container.emit(compositionStartEvent("preedit"))
      discard input.container.emit(compositionUpdateEvent("updated"))
      discard input.container.emit(compositionEndEvent("committed"))

      var clipboard = "clipboard"
      ui.configureClipboardTextProvider(proc(): string = clipboard)
      ui.configureClipboardTextWriter(proc(text: string) =
        clipboard = text
        input.setValue(text)
      )
      ui.writeClipboardText("written")

      discard ui.setFocus(interaction, some(input.container.nodeId), focusVisible = true)

      let progress = ui.progress(value = 0.25, max = 1.0)
      progress.setValue(0.75)

      let radioSet = initRadioSet()
      let firstRadio = ui.radio(radioSet, "First", "first", checked = true)
      let secondRadio = ui.radio(radioSet, "Second", "second")
      discard secondRadio.container().emit(InputEvent(kind: iekClick))
      doAssert not firstRadio.checked()

      let select = ui.selectBox(@[
        SelectOption(label: "Alpha", value: "alpha"),
        SelectOption(label: "Beta", value: "beta")
      ])
      discard select.container.emit(keyDownEvent("ArrowDown"))
      discard select.container.emit(keyDownEvent("Enter"))

      let slider = ui.slider(value = 25, min = 0, max = 100, step = 5)
      discard slider.container.emit(keyDownEvent("ArrowRight"))

      let area = ui.textArea(TextAreaParams(value: "line one"))
      discard area.container.emit(textInputEvent("\nline two"))
      discard area.container.emit(compositionStartEvent("area preedit"))
      discard area.container.emit(compositionUpdateEvent("area update"))
      discard area.container.emit(compositionEndEvent("area commit"))
      discard ui.setFocus(interaction, some(area.container.nodeId), focusVisible = true)

      let menu = ui.commandMenu(@[
        CommandMenuItem(label: "Open", value: "open"),
        CommandMenuItem(label: "Close", value: "close")
      ], open = true)
      discard menu.container.emit(keyDownEvent("ArrowDown"))
      discard menu.container.emit(keyDownEvent("Enter"))
      discard menu.close()

      let list = ui.listBox(@[
        ListItem(label: "Alpha", value: "alpha"),
        ListItem(label: "Beta", value: "beta")
      ])
      discard list.container.emit(keyDownEvent("ArrowDown"))

      let tabs = ui.tabs(@[
        TabItem(label: "Preview", value: "preview"),
        TabItem(label: "Code", value: "code")
      ])
      discard tabs.container.emit(keyDownEvent("ArrowRight"))

      let contextTarget = ui.box(groups = ["context-target"])
      discard ui.mountDefaultContextMenu(imageParent)
      doAssert ui.showDefaultContextMenu(some(contextTarget.nodeId), vec2(8, 8))
      discard ui.closeDefaultContextMenu()

      let componentClicks = new int
      let componentMounts = new int
      let componentUnmounts = new int
      let component = ui.mount(MemoryComponent(
        clicks: componentClicks,
        mounts: componentMounts,
        unmounts: componentUnmounts
      ))
      doAssert componentMounts[] == 1
      doAssert component.node.emit(InputEvent(kind: iekClick))
      doAssert componentClicks[] == 1
      doAssert ui.disposeSubtree(component.node, interaction)
      doAssert componentUnmounts[] == 1

exerciseWidgetLifecycle()
