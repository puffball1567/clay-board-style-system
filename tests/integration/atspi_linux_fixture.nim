when not defined(linux):
  {.error: "The AT-SPI session fixture requires Linux.".}

import std/[os, times]

import clay_board_style_system
import clay_board_style_system/backends/atspi/linux_dbus
import clay_board_style_system/generated/default_properties

proc fixedStyle(width, height: float32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(height))
  ])

proc layoutFor(ui: UiRoot): LayoutResult =
  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  doAssert not diagnostics.hasErrors
  computeLayout(ui.tree, styles, size(640, 480))

proc main() =
  let ui = initUiRoot()
  let app = ui.box(fixedStyle(400, 240), id = "app")
  ui.pushParent(app)
  let save = ui.button("Save", style = fixedStyle(120, 32))
  save.container.setCode("save-action")
  let enabled = ui.checkbox("Enabled", style = fixedStyle(140, 32))
  let volume = ui.slider(value = 25, min = 0, max = 100,
    style = fixedStyle(180, 32))
  ui.popParent()

  var activations = 0
  save.onClick = proc(event: DispatchResult): EventOutcome =
    inc activations
    true

  let transport = initLinuxAtspiTransport(ui)
  if not transport.connected():
    stderr.writeLine("AT-SPI transport unavailable: " & transport.lastError)
    quit(QuitFailure)
  defer:
    transport.close()

  let dbusTransport = transport.atspiTransport()
  let adapter = initAtspiAdapter(dbusTransport)
  if not adapter.refresh(ui, ui.layoutFor(), "CBSS AT-SPI fixture", "test"):
    stderr.writeLine("AT-SPI publish failed: " & transport.lastError)
    quit(QuitFailure)

  doAssert not dbusTransport.publish(
    AtspiSnapshot(nodes: @[
      AtspiNode(objectPath: "/tmp/untrusted")
    ]),
    @[]
  )

  stdout.writeLine("READY " & transport.uniqueBusName())
  stdout.writeLine("ROOT " & atspiRootPath)
  stdout.writeLine("BUTTON " & objectPathFor(save.container.nodeId))
  stdout.writeLine("CHECKBOX " & objectPathFor(enabled.container.nodeId))
  stdout.writeLine("SLIDER " & objectPathFor(volume.container.nodeId))
  stdout.flushFile()

  let deadline = epochTime() + 8.0
  while epochTime() < deadline:
    discard transport.poll()
    sleep(2)

  stdout.writeLine("ACTIVATIONS " & $activations)
  transport.close()
  transport.close()
  doAssert not transport.connected()
  doAssert transport.poll() == 0
  stdout.writeLine("CLOSED true")
  stdout.flushFile()

when isMainModule:
  main()
