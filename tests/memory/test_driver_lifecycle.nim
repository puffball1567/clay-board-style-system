import clay_board_style_system
import clay_board_style_system/testing/test_driver

proc exerciseDriverLifecycle() =
  let ui = initUiRoot()
  discard ui.box()
  block:
    let driver = initCbssTestDriver(ui, size(120, 80))
    driver.clipboard = "paste"
    driver.clipboard.add " text"
    doAssert ui.clipboardTextProvider() == "paste text"
    ui.writeClipboardText("copied text")
    doAssert driver.clipboard == "copied text"

  # The UI can outlive the driver; its callbacks must still own valid storage.
  doAssert ui.clipboardTextProvider() == "copied text"
  ui.writeClipboardText("after driver release")
  doAssert ui.clipboardTextProvider() == "after driver release"

proc retainedCallbacks(): tuple[read: ClipboardTextProvider,
    write: ClipboardTextWriter] =
  let driver = initCbssTestDriver(initUiRoot(), size(120, 80))
  driver.clipboard = "retained"
  (driver.ui.clipboardTextProvider, driver.ui.clipboardTextWriter)

proc exerciseRetainedCallbacks() =
  let callbacks = retainedCallbacks()
  doAssert callbacks.read() == "retained"
  callbacks.write("still valid")
  doAssert callbacks.read() == "still valid"

# No unittest globals: all fixture owners leave scope before the leak check.
for iteration in 0 ..< 100:
  exerciseDriverLifecycle()
  exerciseRetainedCallbacks()

when defined(gcOrc):
  # Release ORC's cycle-candidate buffer before checking all leak kinds.
  GC_fullCollect()
