import std/[math, options, strutils, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/backends/sdl3/text_event_guard
import clay_board_style_system/generated/default_properties

type
  DemoActionKind = enum
    dakRunClicked,
    dakTabSelected,
    dakAltTabSelected,
    dakHeroInputChanged,
    dakCatalogInputChanged,
    dakCatalogTextareaChanged,
    dakFormNameChanged,
    dakFieldsetInputChanged

  DemoAction = object
    kind: DemoActionKind
    value: string

  DemoState = object
    runClicks: int
    selectedTab: string
    altSelectedTab: string
    heroInput: string
    catalogInput: string
    catalogTextarea: string
    formName: string
    fieldsetInput: string

  DemoViewRefs = ref object
    statusText: Option[NodeId]
    tabStatusText: Option[NodeId]
    altTabStatusText: Option[NodeId]

  FrameData = object
    styles: ResolvedTree
    layout: LayoutResult
    commands: seq[PaintCommand]
    dynamicCommands: seq[PaintCommand]
    scrollDynamicCommands: seq[PaintCommand]
    scrollDynamicTarget: Option[NodeId]
    scrollHitStart: int
    scrollHitCount: int
    regions: seq[HitRegion]

  PendingTextInput = object
    target: NodeId
    text: string
    focusSerial: int
    keyTimestamp: uint64

  CompositionInput = object
    target: NodeId
    focusSerial: int

  TextFocusDiscardMode = enum
    tfdNone,
    tfdUntilPointerUp,
    tfdUntilTextQuiet,
    tfdUntilKeyUp

  DemoHarness* = ref object
    runtime: StateRuntime[DemoState, DemoAction]
    refs: DemoViewRefs
    clipboard: string
    runClicks: int

const
  maxDemoClipboardBytes = maxPasteEventBytes
  maxWheelEventsPerFrame = 8
  scrollIndicatorIdleDelaySeconds = 0.10

proc truncateUtf8ForDemo(text: string; maxBytes: int): string

proc updateDemo(state: var DemoState; action: DemoAction) =
  case action.kind
  of dakRunClicked:
    inc state.runClicks
  of dakTabSelected:
    state.selectedTab = action.value
  of dakAltTabSelected:
    state.altSelectedTab = action.value
  of dakHeroInputChanged:
    state.heroInput = action.value
  of dakCatalogInputChanged:
    state.catalogInput = action.value
  of dakCatalogTextareaChanged:
    state.catalogTextarea = action.value
  of dakFormNameChanged:
    state.formName = action.value
  of dakFieldsetInputChanged:
    state.fieldsetInput = action.value

proc statusText(state: DemoState): string =
  if state.runClicks == 0:
    "Style -> layout -> paint commands -> SDL3 renderer"
  else:
    "Run clicked " & $state.runClicks & " time(s)"

proc tabStatusTextFor(value: string): string =
  case value
  of "data":
    "Data view selected"
  of "logs":
    "Logs view selected"
  else:
    "Info view selected"

proc tabStatusText(state: DemoState): string =
  tabStatusTextFor(state.selectedTab)

proc altTabStatusTextFor(value: string): string =
  case value
  of "data":
    "Data table"
  of "logs":
    "Activity log"
  else:
    "Overview"

proc altTabStatusText(state: DemoState): string =
  altTabStatusTextFor(state.altSelectedTab)

proc surfaceStyle(): UiStyle =
  uiStyle([
    decl("width", px(1120)),
    decl("height", px(860)),
    decl("margin-left", px(26)),
    decl("margin-top", px(24)),
    decl("padding", px(14)),
    decl("gap", px(10)),
    decl("background-color", colorValue(rgb(0.10, 0.11, 0.13))),
    decl("background-image", linearGradient(
      145,
      colorStop(rgba(0.17, 0.20, 0.25, 0.96), 0),
      colorStop(rgba(0.08, 0.09, 0.12, 0.98), 58),
      colorStop(rgba(0.06, 0.10, 0.11, 1.00), 100)
    )),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(12),
      blur = some(px(24)),
      spread = some(px(0)),
      shadowColor = some(rgba(0, 0, 0, 0.28))
    )),
    decl("color", colorValue(rgb(0.94, 0.95, 0.96))),
    decl("font-family", fontFamilyValue(genericSystemUi(), genericSansSerif())),
    decl("font-size", px(14)),
    decl("font-weight", keyword("normal")),
    decl("line-height", number(1.25)),
    decl("font-feature-settings", keyword("kern 1, liga 1"))
  ])

proc demoBodyStyle(): UiStyle =
  uiStyle([
    decl("height", px(782)),
    decl("gap", px(12)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("flex-start"))
  ])

proc demoColumnStyle(): UiStyle =
  uiStyle([
    decl("width", px(532)),
    decl("gap", px(10))
  ])

proc catalogColumnStyle(): UiStyle =
  uiStyle([
    decl("width", px(532)),
    decl("height", px(782)),
    decl("padding", px(10)),
    decl("gap", px(9)),
    decl("background-color", colorValue(rgb(0.11, 0.12, 0.14))),
    decl("background-image", linearGradient(
      145,
      colorStop(rgba(0.15, 0.16, 0.19, 0.95), 0),
      colorStop(rgba(0.08, 0.09, 0.11, 0.98), 100)
    )),
    decl("border-color", colorValue(rgb(0.25, 0.28, 0.33))),
    decl("border-width", px(1)),
    decl("border-radius", px(6))
  ])

proc headerStyle(): UiStyle =
  uiStyle([
    decl("height", px(40)),
    decl("gap", px(10)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("space-between"))
  ])

proc titleStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(18)),
    decl("font-weight", keyword("bold")),
    decl("font-stretch", keyword("semi-expanded")),
    decl("text-shadow", shadowValue(
      offsetX = px(1),
      offsetY = px(2),
      blur = some(px(5)),
      shadowColor = some(rgba(0.05, 0.32, 0.40, 0.48))
    )),
    decl("color", colorValue(rgb(0.98, 0.98, 0.98)))
  ])

proc badgeStyle(): UiStyle =
  uiStyle([
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("padding-right", px(8)),
    decl("background-color", colorValue(rgb(0.13, 0.24, 0.22))),
    decl("border-color", colorValue(rgb(0.21, 0.70, 0.55))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("color", colorValue(rgb(0.76, 1.00, 0.90)))
  ])

proc toolbarStyle(): UiStyle =
  uiStyle([
    decl("height", px(58)),
    decl("padding", px(8)),
    decl("gap", px(10)),
    decl("column-gap", px(12)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.15, 0.17, 0.20))),
    decl("background-image", linearGradient(
      120,
      colorStop(rgba(0.19, 0.22, 0.27, 0.92), 0),
      colorStop(rgba(0.12, 0.14, 0.17, 0.95), 100)
    )),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(6),
      blur = some(px(14)),
      spread = some(px(-1)),
      shadowColor = some(rgba(0, 0, 0, 0.22))
    )),
    decl("border-color", colorValue(rgb(0.26, 0.30, 0.35))),
    decl("border-width", px(1)),
    decl("border-radius", px(6))
  ])

proc buttonStyle(): UiStyle =
  uiStyle([
    decl("min-width", px(78)),
    decl("padding", px(8)),
    decl("padding-left", px(14)),
    decl("padding-right", px(14)),
    decl("margin", px(2)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.22, 0.25, 0.29))),
    decl("border-color", colorValue(rgb(0.42, 0.47, 0.54))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("color", colorValue(rgb(0.96, 0.96, 0.96))),
    decl("cursor", keyword("pointer")),
    decl("letter-spacing", px(0.25)),
    decl("font-size", px(14))
  ])

proc primaryButtonStyle(): UiStyle =
  buttonStyle() + uiStyle([
    decl("background-color", colorValue(rgb(0.16, 0.33, 0.43))),
    decl("background-image", linearGradient(
      180,
      colorStop(rgba(0.22, 0.47, 0.58, 0.88), 0),
      colorStop(rgba(0.13, 0.28, 0.37, 0.94), 100)
    )),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(4),
      blur = some(px(10)),
      spread = some(px(-1)),
      shadowColor = some(rgba(0.02, 0.14, 0.18, 0.40))
    )),
    decl("border-color", colorValue(rgb(0.25, 0.63, 0.78)))
  ])

proc hoverButtonStyle(): UiStyle =
  uiStyle([
    decl("background-color", colorValue(rgb(0.31, 0.37, 0.45))),
    decl("background-image", linearGradient(
      180,
      colorStop(rgba(0.36, 0.43, 0.52, 0.88), 0),
      colorStop(rgba(0.24, 0.29, 0.36, 0.94), 100)
    ))
  ])

proc activeButtonStyle(): UiStyle =
  uiStyle([
    decl("background-color", colorValue(rgb(0.13, 0.20, 0.25))),
    decl("background-image", linearGradient(
      180,
      colorStop(rgba(0.12, 0.25, 0.31, 0.96), 0),
      colorStop(rgba(0.08, 0.16, 0.21, 0.98), 100)
    )),
    decl("border-color", colorValue(rgb(0.38, 0.76, 0.88))),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(2),
      blur = some(px(5)),
      spread = some(px(-1)),
      shadowColor = some(rgba(0.02, 0.12, 0.16, 0.30))
    ))
  ])

proc spacerStyle(): UiStyle =
  uiStyle([
    decl("height", px(1)),
    decl("flex-grow", number(1))
  ])

proc statusStyle(): UiStyle =
  uiStyle([
    decl("padding", px(10)),
    decl("opacity", number(0.88)),
    decl("background-color", colorValue(rgb(0.12, 0.13, 0.15))),
    decl("border-color", colorValue(rgb(0.24, 0.27, 0.31))),
    decl("border-width", px(1)),
    decl("border-radius", px(6)),
    decl("color", colorValue(rgb(0.72, 0.76, 0.82)))
  ])

proc logicalPanelStyle(): UiStyle =
  uiStyle([
    decl("inline-size", px(532)),
    decl("block-size", px(42)),
    decl("padding-inline", px(12)),
    decl("padding-block", px(7)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.10, 0.14, 0.15))),
    decl("background-image", linearGradient(
      100,
      colorStop(rgba(0.13, 0.20, 0.20, 0.92), 0),
      colorStop(rgba(0.08, 0.11, 0.13, 0.96), 100)
    )),
    decl("border-block", borderValue(lineWeight = px(1), lineStyle = "solid", lineColor = rgb(0.20, 0.32, 0.34))),
    decl("border-inline-start", borderValue(lineWeight = px(3), lineStyle = "solid", lineColor = rgb(0.29, 0.72, 0.70))),
    decl("border-start-start-radius", px(6)),
    decl("border-start-end-radius", px(6)),
    decl("border-end-start-radius", px(6)),
    decl("border-end-end-radius", px(6)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(4),
      blur = some(px(9)),
      spread = some(px(-2)),
      shadowColor = some(rgba(0, 0, 0, 0.22))
    ))
  ])

proc logicalLabelStyle(): UiStyle =
  uiStyle([
    decl("padding-inline", px(8)),
    decl("padding-block", px(4)),
    decl("border-inline", borderValue(lineWeight = px(1), lineStyle = "solid", lineColor = rgb(0.30, 0.48, 0.48))),
    decl("border-block", borderValue(lineWeight = px(1), lineStyle = "solid", lineColor = rgb(0.20, 0.30, 0.31))),
    decl("border-radius", px(4)),
    decl("background-color", colorValue(rgb(0.12, 0.18, 0.19))),
    decl("color", colorValue(rgb(0.74, 0.91, 0.90))),
    decl("font-size", px(12)),
    decl("tab-size", number(4)),
    decl("direction", keyword("ltr")),
    decl("writing-mode", keyword("horizontal-tb"))
  ])

proc textInputStyle(): UiStyle =
  uiStyle([
    decl("width", px(532)),
    decl("height", px(38)),
    decl("padding", px(8)),
    decl("padding-left", px(12)),
    decl("padding-right", px(12)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.08, 0.09, 0.11))),
    decl("border-color", colorValue(rgb(0.30, 0.34, 0.40))),
    decl("border-width", px(1)),
    decl("border-radius", px(5)),
    decl("color", colorValue(rgb(0.92, 0.94, 0.96))),
    decl("cursor", keyword("text")),
    decl("overflow", keyword("hidden"))
  ])

proc textInputValueStyle(): UiStyle =
  uiStyle([
    decl("width", px(508)),
    decl("font-size", px(14)),
    decl("line-height", number(1.2)),
    decl("color", colorValue(rgb(0.92, 0.94, 0.96))),
    decl("white-space", keyword("nowrap")),
    decl("text-overflow", keyword("clip"))
  ])

proc controlsPanelStyle(): UiStyle =
  uiStyle([
    decl("height", px(204)),
    decl("padding", px(10)),
    decl("gap", px(9)),
    decl("background-color", colorValue(rgb(0.10, 0.12, 0.15))),
    decl("background-image", linearGradient(
      110,
      colorStop(rgba(0.13, 0.16, 0.20, 0.94), 0),
      colorStop(rgba(0.08, 0.10, 0.13, 0.98), 100)
    )),
    decl("border-color", colorValue(rgb(0.24, 0.28, 0.34))),
    decl("border-width", px(1)),
    decl("border-radius", px(6))
  ])

proc controlRowStyle(): UiStyle =
  uiStyle([
    decl("height", px(32)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc controlLabelStyle(): UiStyle =
  uiStyle([
    decl("min-width", px(66)),
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.64, 0.70, 0.78)))
  ])

proc choiceStyle(): UiStyle =
  uiStyle([
    decl("min-width", px(92)),
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("padding-right", px(8)),
    decl("gap", px(4)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.14, 0.16, 0.19))),
    decl("border-color", colorValue(rgb(0.30, 0.35, 0.42))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("cursor", keyword("pointer"))
  ])

proc choiceMarkerStyle(): UiStyle =
  uiStyle([
    decl("width", px(16)),
    decl("height", px(16)),
    decl("min-width", px(16)),
    decl("background-color", colorValue(rgb(0.08, 0.10, 0.12))),
    decl("border-color", colorValue(rgb(0.34, 0.40, 0.48))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(1),
      blur = some(px(3)),
      spread = some(px(0)),
      shadowColor = some(rgba(0, 0, 0, 0.28))
    )),
    decl("pointer-events", keyword("none"))
  ])

proc radioMarkerStyle(): UiStyle =
  uiStyle([
    decl("width", px(18)),
    decl("height", px(18)),
    decl("min-width", px(18)),
    decl("min-height", px(18)),
    decl("max-width", px(18)),
    decl("max-height", px(18)),
    decl("background-color", colorValue(rgb(0.08, 0.10, 0.12))),
    decl("border-color", colorValue(rgb(0.34, 0.40, 0.48))),
    decl("border-width", px(1)),
    decl("border-radius", px(9)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(1),
      blur = some(px(3)),
      spread = some(px(0)),
      shadowColor = some(rgba(0, 0, 0, 0.28))
    )),
    decl("pointer-events", keyword("none"))
  ])

proc choiceLabelStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.86, 0.89, 0.92))),
    decl("pointer-events", keyword("none"))
  ])

proc sliderStyle(): UiStyle =
  uiStyle([
    decl("width", px(206)),
    decl("height", px(28)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("cursor", keyword("pointer"))
  ])

proc sliderTrackStyle(): UiStyle =
  uiStyle([
    decl("width", px(144)),
    decl("height", px(18)),
    decl("position", keyword("relative")),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.09, 0.11, 0.14))),
    decl("border-color", colorValue(rgb(0.27, 0.34, 0.40))),
    decl("border-width", px(1)),
    decl("border-radius", px(9)),
    decl("pointer-events", keyword("none"))
  ])

proc sliderFillStyle(): UiStyle =
  uiStyle([
    decl("height", px(18)),
    decl("background-color", colorValue(rgb(0.16, 0.48, 0.58))),
    decl("background-image", linearGradient(
      90,
      colorStop(rgba(0.25, 0.75, 0.86, 0.92), 0),
      colorStop(rgba(0.12, 0.36, 0.48, 0.96), 100)
    )),
    decl("border-radius", px(9))
  ])

proc sliderThumbStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(11)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.77, 0.93, 0.98))),
    decl("pointer-events", keyword("none"))
  ])

proc controlValueStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.78, 0.84, 0.90))),
    decl("pointer-events", keyword("none"))
  ])

proc progressStyle(): UiStyle =
  uiStyle([
    decl("width", px(206)),
    decl("height", px(28)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc progressTrackStyle(): UiStyle =
  uiStyle([
    decl("width", px(144)),
    decl("height", px(18)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.08, 0.10, 0.12))),
    decl("background-image", linearGradient(
      90,
      colorStop(rgba(0.12, 0.18, 0.20, 0.98), 0),
      colorStop(rgba(0.08, 0.10, 0.12, 1.00), 100)
    )),
    decl("border-color", colorValue(rgb(0.27, 0.34, 0.40))),
    decl("border-width", px(1)),
    decl("border-radius", px(9))
  ])

proc progressFillStyle(): UiStyle =
  uiStyle([
    decl("height", px(18)),
    decl("background-color", colorValue(rgb(0.21, 0.58, 0.40))),
    decl("background-image", linearGradient(
      90,
      colorStop(rgba(0.43, 0.90, 0.62, 0.96), 0),
      colorStop(rgba(0.18, 0.48, 0.37, 0.96), 100)
    )),
    decl("border-radius", px(9))
  ])

proc selectStyle(): UiStyle =
  uiStyle([
    decl("width", px(180)),
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("gap", px(4)),
    decl("background-color", colorValue(rgb(0.12, 0.14, 0.17))),
    decl("border-color", colorValue(rgb(0.31, 0.37, 0.45))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("cursor", keyword("pointer"))
  ])

proc selectOptionStyle(): UiStyle =
  uiStyle([
    decl("width", px(164)),
    decl("height", px(24)),
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("align-items", keyword("flex-start")),
    decl("justify-content", keyword("center")),
    decl("font-size", px(11)),
    decl("color", colorValue(rgb(0.72, 0.78, 0.86))),
    decl("cursor", keyword("pointer"))
  ])

proc selectPanelStyle(): UiStyle =
  uiStyle([
    decl("width", px(180)),
    decl("padding", px(4)),
    decl("background-color", colorValue(rgb(0.10, 0.12, 0.15))),
    decl("background-image", linearGradient(
      180,
      colorStop(rgba(0.13, 0.15, 0.18, 0.98), 0),
      colorStop(rgba(0.08, 0.10, 0.13, 1.00), 100)
    )),
    decl("border-color", colorValue(rgb(0.30, 0.36, 0.44))),
    decl("border-width", px(1)),
    decl("border-radius", px(5)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(8),
      blur = some(px(16)),
      spread = some(px(-2)),
      shadowColor = some(rgba(0, 0, 0, 0.34))
    ))
  ])

proc tabsStyle(): UiStyle =
  uiStyle([
    decl("width", px(260)),
    decl("height", px(30)),
    decl("gap", px(4)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc tabStyle(): UiStyle =
  uiStyle([
    decl("padding", px(6)),
    decl("padding-left", px(9)),
    decl("padding-right", px(9)),
    decl("background-color", colorValue(rgb(0.13, 0.15, 0.18))),
    decl("border-color", colorValue(rgb(0.28, 0.33, 0.39))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.78, 0.83, 0.89))),
    decl("cursor", keyword("pointer"))
  ])

proc tabStatusStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.66, 0.75, 0.82)))
  ])

proc altPanelStyle(): UiStyle =
  uiStyle([
    decl("height", px(204)),
    decl("padding", px(10)),
    decl("gap", px(9)),
    decl("background-color", colorValue(rgb(0.95, 0.97, 0.98))),
    decl("border-color", colorValue(rgb(0.68, 0.74, 0.82))),
    decl("border-width", px(1)),
    decl("border-radius", px(3)),
    decl("color", colorValue(rgb(0.10, 0.12, 0.15)))
  ])

proc altRowStyle(): UiStyle =
  uiStyle([
    decl("height", px(32)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc altLabelStyle(): UiStyle =
  uiStyle([
    decl("min-width", px(66)),
    decl("font-size", px(12)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.21, 0.25, 0.30)))
  ])

proc altChoiceStyle(): UiStyle =
  uiStyle([
    decl("min-width", px(92)),
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("padding-right", px(8)),
    decl("gap", px(5)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(1.00, 1.00, 1.00))),
    decl("border-color", colorValue(rgb(0.64, 0.70, 0.78))),
    decl("border-width", px(1)),
    decl("border-radius", px(2)),
    decl("cursor", keyword("pointer"))
  ])

proc altCheckboxMarkerStyle(): UiStyle =
  uiStyle([
    decl("width", px(16)),
    decl("height", px(16)),
    decl("min-width", px(16)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.98, 0.99, 1.00))),
    decl("border-color", colorValue(rgb(0.45, 0.51, 0.60))),
    decl("border-width", px(1)),
    decl("border-radius", px(2)),
    decl("pointer-events", keyword("none"))
  ])

proc altRadioMarkerStyle(): UiStyle =
  uiStyle([
    decl("width", px(18)),
    decl("height", px(18)),
    decl("min-width", px(18)),
    decl("min-height", px(18)),
    decl("max-width", px(18)),
    decl("max-height", px(18)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.98, 0.99, 1.00))),
    decl("border-color", colorValue(rgb(0.45, 0.51, 0.60))),
    decl("border-width", px(1)),
    decl("border-radius", px(9)),
    decl("pointer-events", keyword("none"))
  ])

proc altTextStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.13, 0.16, 0.19))),
    decl("pointer-events", keyword("none"))
  ])

proc altSelectStyle(): UiStyle =
  uiStyle([
    decl("width", px(180)),
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("gap", px(4)),
    decl("background-color", colorValue(rgb(1.00, 1.00, 1.00))),
    decl("border-color", colorValue(rgb(0.54, 0.61, 0.70))),
    decl("border-width", px(1)),
    decl("border-radius", px(2)),
    decl("cursor", keyword("pointer"))
  ])

proc altSelectPanelStyle(): UiStyle =
  uiStyle([
    decl("width", px(180)),
    decl("padding", px(4)),
    decl("background-color", colorValue(rgb(1.00, 1.00, 1.00))),
    decl("border-color", colorValue(rgb(0.54, 0.61, 0.70))),
    decl("border-width", px(1)),
    decl("border-radius", px(2)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(8),
      blur = some(px(18)),
      spread = some(px(-4)),
      shadowColor = some(rgba(0.11, 0.14, 0.18, 0.26))
    ))
  ])

proc altSelectOptionStyle(): UiStyle =
  uiStyle([
    decl("width", px(164)),
    decl("height", px(24)),
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("align-items", keyword("flex-start")),
    decl("justify-content", keyword("center")),
    decl("font-size", px(11)),
    decl("color", colorValue(rgb(0.18, 0.22, 0.27))),
    decl("cursor", keyword("pointer"))
  ])

proc altSliderStyle(): UiStyle =
  uiStyle([
    decl("width", px(206)),
    decl("height", px(28)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("cursor", keyword("pointer"))
  ])

proc altSliderTrackStyle(): UiStyle =
  uiStyle([
    decl("width", px(144)),
    decl("height", px(18)),
    decl("position", keyword("relative")),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.84, 0.88, 0.92))),
    decl("border-color", colorValue(rgb(0.64, 0.70, 0.78))),
    decl("border-width", px(1)),
    decl("border-radius", px(2)),
    decl("pointer-events", keyword("none"))
  ])

proc altSliderFillStyle(): UiStyle =
  uiStyle([
    decl("height", px(18)),
    decl("background-color", colorValue(rgb(0.11, 0.33, 0.72))),
    decl("border-radius", px(2))
  ])

proc altSliderThumbStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(11)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(1.00, 1.00, 1.00))),
    decl("pointer-events", keyword("none"))
  ])

proc altProgressStyle(): UiStyle =
  altSliderStyle()

proc altProgressTrackStyle(): UiStyle =
  altSliderTrackStyle()

proc altProgressFillStyle(): UiStyle =
  uiStyle([
    decl("height", px(18)),
    decl("background-color", colorValue(rgb(0.20, 0.56, 0.28))),
    decl("border-radius", px(2))
  ])

proc altValueStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(12)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.20, 0.25, 0.31))),
    decl("pointer-events", keyword("none"))
  ])

proc altTabsStyle(): UiStyle =
  uiStyle([
    decl("width", px(260)),
    decl("height", px(30)),
    decl("gap", px(0)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc altTabStyle(): UiStyle =
  uiStyle([
    decl("padding", px(6)),
    decl("padding-left", px(10)),
    decl("padding-right", px(10)),
    decl("background-color", colorValue(rgb(0.90, 0.93, 0.96))),
    decl("border-color", colorValue(rgb(0.60, 0.67, 0.75))),
    decl("border-width", px(1)),
    decl("border-radius", px(0)),
    decl("font-size", px(12)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.20, 0.25, 0.31))),
    decl("cursor", keyword("pointer"))
  ])

proc altTabStatusStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.30, 0.36, 0.43)))
  ])

proc propertyPanelStyle(): UiStyle =
  uiStyle([
    decl("width", px(500)),
    decl("height", px(148)),
    decl("padding", px(9)),
    decl("gap", px(6)),
    decl("flex-direction", keyword("column")),
    decl("align-items", keyword("stretch")),
    decl("background-color", colorValue(rgb(0.13, 0.13, 0.15))),
    decl("border-color", colorValue(rgb(0.28, 0.30, 0.35))),
    decl("border-width", px(1)),
    decl("border-radius", px(5))
  ])

proc propertyRowStyle(): UiStyle =
  uiStyle([
    decl("height", px(34)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc propertyLabelStyle(): UiStyle =
  uiStyle([
    decl("width", px(112)),
    decl("height", px(28)),
    decl("padding-left", px(6)),
    decl("padding-right", px(6)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.13, 0.13, 0.15))),
    decl("border-color", colorValue(rgb(0.28, 0.30, 0.35))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("font-size", px(10)),
    decl("color", colorValue(rgb(0.68, 0.74, 0.82)))
  ])

proc propertyLabelTextStyle(): UiStyle =
  uiStyle([
    decl("width", px(96)),
    decl("font-size", px(10)),
    decl("line-height", px(16)),
    decl("text-align", keyword("center")),
    decl("white-space", keyword("nowrap")),
    decl("color", colorValue(rgb(0.68, 0.74, 0.82)))
  ])

proc outlineSampleStyle(): UiStyle =
  uiStyle([
    decl("width", px(102)),
    decl("height", px(34)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.18, 0.21, 0.25))),
    decl("border-color", colorValue(rgb(0.36, 0.42, 0.50))),
    decl("border-width", px(2)),
    decl("border-radius", px(4)),
    decl("outline", borderValue(lineWeight = px(2), lineStyle = "solid", lineColor = rgb(0.95, 0.71, 0.20))),
    decl("outline-offset", px(4)),
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.98, 0.92, 0.78)))
  ])

proc decoratedSampleStyle(decorationStyle = "solid"; width = 86'f32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(30)),
    decl("font-size", px(13)),
    decl("line-height", px(24)),
    decl("letter-spacing", px(0.4)),
    decl("text-decoration", keyword("underline")),
    decl("text-decoration-style", keyword(decorationStyle)),
    decl("text-decoration-color", colorValue(rgb(0.45, 0.86, 0.98))),
    decl("text-decoration-thickness", px(2)),
    decl("text-underline-offset", px(2)),
    decl("color", colorValue(rgb(0.92, 0.97, 1.00)))
  ])

proc shadowTextSampleStyle(): UiStyle =
  uiStyle([
    decl("width", px(112)),
    decl("height", px(30)),
    decl("font-size", px(16)),
    decl("font-weight", keyword("bold")),
    decl("line-height", px(24)),
    decl("text-shadow", shadowValue(
      offsetX = px(2),
      offsetY = px(2),
      shadowColor = some(rgba(0.12, 0.58, 0.90, 0.55))
    )),
    decl("color", colorValue(rgb(0.96, 0.98, 1.00)))
  ])

proc opacitySampleStyle(): UiStyle =
  uiStyle([
    decl("width", px(90)),
    decl("height", px(34)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.20, 0.55, 0.38))),
    decl("border-radius", px(4)),
    decl("opacity", number(0.32)),
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(1.00, 1.00, 1.00)))
  ])

proc overflowClipSampleStyle(): UiStyle =
  uiStyle([
    decl("width", px(128)),
    decl("height", px(30)),
    decl("padding", px(6)),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.11, 0.16, 0.21))),
    decl("border-color", colorValue(rgb(0.34, 0.62, 0.84))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("overflow", keyword("hidden"))
  ])

proc overflowClipTextStyle(): UiStyle =
  uiStyle([
    decl("width", px(210)),
    decl("font-size", px(12)),
    decl("line-height", px(18)),
    decl("white-space", keyword("nowrap")),
    decl("color", colorValue(rgb(0.82, 0.94, 1.00)))
  ])

proc contentHiddenSampleStyle(): UiStyle =
  uiStyle([
    decl("width", px(82)),
    decl("height", px(30)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.23, 0.16, 0.25))),
    decl("border-color", colorValue(rgb(0.68, 0.46, 0.76))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("content-visibility", keyword("hidden")),
    decl("font-size", px(12)),
    decl("color", colorValue(rgb(0.98, 0.88, 1.00)))
  ])

proc scrollSampleStyle(): UiStyle =
  uiStyle([
    decl("width", px(112)),
    decl("height", px(30)),
    decl("padding-left", px(6)),
    decl("padding-right", px(6)),
    decl("flex-direction", keyword("column")),
    decl("overflow-y", keyword("auto")),
    decl("overscroll-behavior", keyword("contain")),
    decl("scrollbar-width", keyword("thin")),
    decl("scrollbar-visibility", keyword("scrolling")),
    decl("scrollbar-color", colorPairValue(
      rgb(0.36, 0.78, 0.68), rgb(0.08, 0.14, 0.13)
    )),
    decl("background-color", colorValue(rgb(0.10, 0.18, 0.17))),
    decl("border-color", colorValue(rgb(0.28, 0.62, 0.55))),
    decl("border-width", px(1)),
    decl("border-radius", px(4))
  ])

proc scrollSampleLineStyle(): UiStyle =
  uiStyle([
    decl("width", px(98)),
    decl("height", px(18)),
    decl("flex-shrink", number(0)),
    decl("font-size", px(10)),
    decl("line-height", px(18)),
    decl("color", colorValue(rgb(0.76, 0.94, 0.88)))
  ])

proc catalogTitleStyle(): UiStyle =
  uiStyle([
    decl("height", px(26)),
    decl("font-size", px(15)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.93, 0.95, 0.98)))
  ])

proc catalogSectionStyle(height: float32): UiStyle =
  uiStyle([
    decl("height", px(height)),
    decl("padding", px(8)),
    decl("gap", px(7)),
    decl("background-color", colorValue(rgb(0.14, 0.16, 0.19))),
    decl("border-color", colorValue(rgb(0.28, 0.32, 0.38))),
    decl("border-width", px(1)),
    decl("border-radius", px(5))
  ])

proc catalogRowStyle(): UiStyle =
  uiStyle([
    decl("height", px(30)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc catalogTallRowStyle(): UiStyle =
  uiStyle([
    decl("height", px(90)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("flex-start"))
  ])

proc catalogSplitRowStyle(height: float32): UiStyle =
  uiStyle([
    decl("height", px(height)),
    decl("gap", px(12)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("flex-start"))
  ])

proc catalogLabeledStackStyle(width: float32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("gap", px(4))
  ])

proc catalogFieldsetRowStyle(): UiStyle =
  catalogTallRowStyle() + uiStyle([
    decl("height", px(112))
  ])

proc catalogLabelStyle(): UiStyle =
  uiStyle([
    decl("width", px(86)),
    decl("font-size", px(11)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.65, 0.72, 0.80)))
  ])

proc catalogStackLabelStyle(width: float32): UiStyle =
  catalogLabelStyle() + uiStyle([
    decl("width", px(width)),
    decl("line-height", px(14)),
    decl("white-space", keyword("nowrap"))
  ])

proc compactInputStyle(width: float32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(30)),
    decl("padding", px(6)),
    decl("padding-left", px(9)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.08, 0.09, 0.11))),
    decl("border-color", colorValue(rgb(0.33, 0.38, 0.46))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("color", colorValue(rgb(0.93, 0.95, 0.98))),
    decl("cursor", keyword("text")),
    decl("overflow", keyword("hidden"))
  ])

proc compactInputValueStyle(width = 168'f32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("font-size", px(12)),
    decl("line-height", px(16)),
    decl("white-space", keyword("nowrap")),
    decl("color", colorValue(rgb(0.93, 0.95, 0.98)))
  ])

proc textAreaStyle(): UiStyle =
  uiStyle([
    decl("width", px(206)),
    decl("height", px(70)),
    decl("min-width", px(206)),
    decl("max-width", px(206)),
    decl("min-height", px(54)),
    decl("max-height", px(96)),
    decl("padding", px(7)),
    decl("background-color", colorValue(rgb(0.08, 0.09, 0.11))),
    decl("border-color", colorValue(rgb(0.33, 0.38, 0.46))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("resize", keyword("both")),
    decl("cursor", keyword("text"))
  ])

proc textAreaValueStyle(): UiStyle =
  uiStyle([
    decl("width", px(190)),
    decl("font-size", px(12)),
    decl("line-height", px(16)),
    decl("color", colorValue(rgb(0.91, 0.94, 0.97))),
    decl("white-space", keyword("pre-wrap"))
  ])

proc listBoxStyle(): UiStyle =
  uiStyle([
    decl("width", px(150)),
    decl("height", px(74)),
    decl("padding", px(4)),
    decl("gap", px(2)),
    decl("background-color", colorValue(rgb(0.09, 0.10, 0.12))),
    decl("border-color", colorValue(rgb(0.31, 0.36, 0.43))),
    decl("border-width", px(1)),
    decl("border-radius", px(4))
  ])

proc listItemStyle(): UiStyle =
  uiStyle([
    decl("height", px(20)),
    decl("padding", px(4)),
    decl("padding-left", px(6)),
    decl("padding-right", px(6)),
    decl("padding-top", px(0)),
    decl("padding-bottom", px(0)),
    decl("font-size", px(11)),
    decl("line-height", px(20)),
    decl("color", colorValue(rgb(0.79, 0.84, 0.90))),
    decl("cursor", keyword("default"))
  ])

proc commandMenuItemStyle(): UiStyle =
  listItemStyle() + uiStyle([
    decl("cursor", keyword("pointer"))
  ])

proc commandMenuStyle(): UiStyle =
  listBoxStyle() + uiStyle([
    decl("width", px(154)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(8),
      blur = some(px(16)),
      spread = some(px(-4)),
      shadowColor = some(rgba(0, 0, 0, 0.34))
    ))
  ])

proc dialogStyle(): UiStyle =
  uiStyle([
    decl("width", px(206)),
    decl("height", px(88)),
    decl("padding", px(9)),
    decl("gap", px(5)),
    decl("background-color", colorValue(rgb(0.95, 0.96, 0.98))),
    decl("border-color", colorValue(rgb(0.54, 0.60, 0.69))),
    decl("border-width", px(1)),
    decl("border-radius", px(5)),
    decl("box-shadow", shadowValue(
      offsetX = px(0),
      offsetY = px(8),
      blur = some(px(16)),
      spread = some(px(-3)),
      shadowColor = some(rgba(0, 0, 0, 0.28))
    ))
  ])

proc dialogTitleStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(13)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.13, 0.16, 0.20)))
  ])

proc dialogBodyStyle(): UiStyle =
  uiStyle([
    decl("width", px(188)),
    decl("font-size", px(11)),
    decl("line-height", px(16)),
    decl("white-space", keyword("pre-wrap")),
    decl("color", colorValue(rgb(0.30, 0.35, 0.42)))
  ])

proc detailsStyle(): UiStyle =
  uiStyle([
    decl("width", px(310)),
    decl("gap", px(5)),
    decl("padding", px(7)),
    decl("background-color", colorValue(rgb(0.10, 0.12, 0.15))),
    decl("background-image", linearGradient(
      150,
      colorStop(rgba(0.16, 0.20, 0.24, 0.98), 0),
      colorStop(rgba(0.09, 0.11, 0.14, 1.0), 100)
    )),
    decl("border-color", colorValue(rgb(0.31, 0.38, 0.46))),
    decl("border-width", px(1)),
    decl("border-radius", px(5))
  ])

proc detailsSummaryStyle(): UiStyle =
  uiStyle([
    decl("height", px(24)),
    decl("gap", px(7)),
    decl("cursor", keyword("pointer"))
  ])

proc detailsMarkerStyle(): UiStyle =
  uiStyle([
    decl("width", px(14)),
    decl("height", px(18)),
    decl("font-size", px(12)),
    decl("line-height", px(18)),
    decl("color", colorValue(rgb(0.40, 0.86, 0.95)))
  ])

proc detailsSummaryTextStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(12)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.91, 0.95, 0.98)))
  ])

proc detailsBodyStyle(): UiStyle =
  uiStyle([
    decl("width", px(296)),
    decl("height", px(34)),
    decl("padding-left", px(21)),
    decl("font-size", px(11)),
    decl("line-height", px(15)),
    decl("white-space", keyword("pre-wrap")),
    decl("color", colorValue(rgb(0.68, 0.76, 0.84)))
  ])

proc imageFrameStyle(): UiStyle =
  uiStyle([
    decl("width", px(96)),
    decl("height", px(64)),
    decl("position", keyword("relative")),
    decl("background-color", colorValue(rgb(0.08, 0.10, 0.12))),
    decl("background-image", linearGradient(
      135,
      colorStop(rgba(0.20, 0.48, 0.62, 0.98), 0),
      colorStop(rgba(0.24, 0.62, 0.42, 0.94), 58),
      colorStop(rgba(0.92, 0.68, 0.25, 0.96), 100)
    )),
    decl("border-color", colorValue(rgb(0.35, 0.42, 0.50))),
    decl("border-width", px(1)),
    decl("border-radius", px(6)),
    decl("overflow", keyword("hidden"))
  ])

proc imageLabelStyle(): UiStyle =
  uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(6)),
    decl("bottom", px(4)),
    decl("font-size", px(11)),
    decl("line-height", px(14)),
    decl("color", colorValue(rgb(0.96, 0.98, 1.0)))
  ])

proc formShellStyle(): UiStyle =
  uiStyle([
    decl("width", px(234)),
    decl("height", px(86)),
    decl("padding", px(7)),
    decl("gap", px(6)),
    decl("background-color", colorValue(rgb(0.10, 0.11, 0.13))),
    decl("border-color", colorValue(rgb(0.29, 0.34, 0.40))),
    decl("border-width", px(1)),
    decl("border-radius", px(4))
  ])

proc fieldsetStyle(): UiStyle =
  uiStyle([
    decl("width", px(234)),
    decl("height", px(108)),
    decl("padding", px(7)),
    decl("gap", px(6)),
    decl("background-color", colorValue(rgb(0.10, 0.11, 0.13))),
    decl("border-color", colorValue(rgb(0.29, 0.34, 0.40))),
    decl("border-width", px(1)),
    decl("border-radius", px(4))
  ])

proc legendStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(11)),
    decl("font-weight", keyword("bold")),
    decl("color", colorValue(rgb(0.68, 0.86, 0.92)))
  ])

proc overlayStyle(): UiStyle =
  uiStyle([
    decl("position", keyword("absolute")),
    decl("z-index", number(10)),
    decl("right", px(16)),
    decl("bottom", px(14)),
    decl("padding", px(5)),
    decl("padding-left", px(8)),
    decl("padding-right", px(8)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.18, 0.16, 0.28))),
    decl("border-color", colorValue(rgb(0.54, 0.45, 0.86))),
    decl("border-width", px(1)),
    decl("border-radius", px(5)),
    decl("color", colorValue(rgb(0.88, 0.84, 1.00))),
    decl("font-size", px(12))
  ])

proc buttonStateStyles(): StyleSheet =
  var hoverButton = group("button")
  hoverButton.requiredStates.incl esHover
  var activeButton = group("button")
  activeButton.requiredStates.incl esActive
  var focusedTextInput = group("text-input")
  focusedTextInput.requiredStates.incl esFocus
  var checkedChoice = group("checkbox")
  checkedChoice.requiredStates.incl esChecked
  var checkedRadio = group("radio")
  checkedRadio.requiredStates.incl esChecked
  var checkedAltChoice = group("checkbox-alt")
  checkedAltChoice.requiredStates.incl esChecked
  var checkedAltRadio = group("radio-alt")
  checkedAltRadio.requiredStates.incl esChecked
  var selectedTab = group("tab")
  selectedTab.requiredStates.incl esSelected
  var selectedAltTab = group("tab-alt")
  selectedAltTab.requiredStates.incl esSelected
  var activeSelect = group("select")
  activeSelect.requiredStates.incl esOpen
  var activeAltSelect = group("select-alt")
  activeAltSelect.requiredStates.incl esOpen
  var selectedListItem = group("list-item")
  selectedListItem.requiredStates.incl esSelected
  var selectedCommandItem = group("command-menu-item")
  selectedCommandItem.requiredStates.incl esSelected
  var disabledTextInput = group("text-input")
  disabledTextInput.requiredStates.incl esDisabled
  var disabledTextArea = group("textarea")
  disabledTextArea.requiredStates.incl esDisabled
  var disabledFieldset = group("fieldset")
  disabledFieldset.requiredStates.incl esDisabled
  var disabledChoice = group("checkbox")
  disabledChoice.requiredStates.incl esDisabled
  var disabledRadio = group("radio")
  disabledRadio.requiredStates.incl esDisabled
  var disabledListItem = group("list-item")
  disabledListItem.requiredStates.incl esDisabled
  var disabledCommandItem = group("command-menu-item")
  disabledCommandItem.requiredStates.incl esDisabled
  styleSheet([
    rule(hoverButton, hoverButtonStyle().declarations),
    rule(activeButton, activeButtonStyle().declarations),
    rule(focusedTextInput, [
      decl("border-color", colorValue(rgb(0.35, 0.80, 0.94))),
      decl("box-shadow", shadowValue(
        offsetX = px(0),
        offsetY = px(0),
        blur = some(px(10)),
        spread = some(px(0)),
        shadowColor = some(rgba(0.18, 0.62, 0.82, 0.46))
      ))
    ]),
    rule(checkedChoice, [
      decl("background-color", colorValue(rgb(0.10, 0.30, 0.25))),
      decl("background-image", linearGradient(
        90,
        colorStop(rgba(0.13, 0.38, 0.31, 0.96), 0),
        colorStop(rgba(0.09, 0.20, 0.20, 0.98), 100)
      )),
      decl("border-color", colorValue(rgb(0.24, 0.86, 0.66))),
      decl("box-shadow", shadowValue(
        offsetX = px(0),
        offsetY = px(2),
        blur = some(px(7)),
        spread = some(px(-2)),
        shadowColor = some(rgba(0.05, 0.36, 0.27, 0.42))
      ))
    ]),
    rule(checkedRadio, [
      decl("background-color", colorValue(rgb(0.11, 0.22, 0.34))),
      decl("background-image", linearGradient(
        90,
        colorStop(rgba(0.15, 0.33, 0.47, 0.96), 0),
        colorStop(rgba(0.09, 0.15, 0.22, 0.98), 100)
      )),
      decl("border-color", colorValue(rgb(0.34, 0.70, 0.96))),
      decl("box-shadow", shadowValue(
        offsetX = px(0),
        offsetY = px(2),
        blur = some(px(7)),
        spread = some(px(-2)),
        shadowColor = some(rgba(0.05, 0.21, 0.37, 0.42))
      ))
    ]),
    rule(checkedAltChoice, [
      decl("background-color", colorValue(rgb(0.88, 0.94, 1.00))),
      decl("border-color", colorValue(rgb(0.12, 0.36, 0.74)))
    ]),
    rule(checkedAltRadio, [
      decl("background-color", colorValue(rgb(0.90, 0.96, 0.91))),
      decl("border-color", colorValue(rgb(0.16, 0.54, 0.24)))
    ]),
    rule(selectedTab, [
      decl("background-color", colorValue(rgb(0.18, 0.33, 0.40))),
      decl("border-color", colorValue(rgb(0.35, 0.72, 0.84))),
      decl("color", colorValue(rgb(0.92, 0.98, 1.00)))
    ]),
    rule(selectedAltTab, [
      decl("background-color", colorValue(rgb(0.12, 0.32, 0.68))),
      decl("border-color", colorValue(rgb(0.08, 0.22, 0.48))),
      decl("color", colorValue(rgb(1.00, 1.00, 1.00)))
    ]),
    rule(activeSelect, [
      decl("border-color", colorValue(rgb(0.35, 0.72, 0.84)))
    ]),
    rule(activeAltSelect, [
      decl("border-color", colorValue(rgb(0.12, 0.32, 0.68)))
    ]),
    rule(selectedListItem, [
      decl("background-color", colorValue(rgb(0.17, 0.34, 0.45))),
      decl("color", colorValue(rgb(0.92, 0.98, 1.00)))
    ]),
    rule(selectedCommandItem, [
      decl("background-color", colorValue(rgb(0.24, 0.28, 0.34))),
      decl("color", colorValue(rgb(0.94, 0.96, 0.99)))
    ]),
    rule(disabledTextInput, [
      decl("opacity", number(0.56)),
      decl("cursor", keyword("default")),
      decl("background-color", colorValue(rgb(0.07, 0.08, 0.10))),
      decl("border-color", colorValue(rgb(0.22, 0.25, 0.30))),
      decl("color", colorValue(rgb(0.54, 0.59, 0.65)))
    ]),
    rule(disabledTextArea, [
      decl("opacity", number(0.56)),
      decl("cursor", keyword("default")),
      decl("background-color", colorValue(rgb(0.07, 0.08, 0.10))),
      decl("border-color", colorValue(rgb(0.22, 0.25, 0.30))),
      decl("color", colorValue(rgb(0.54, 0.59, 0.65)))
    ]),
    rule(disabledFieldset, [
      decl("opacity", number(0.72)),
      decl("background-color", colorValue(rgb(0.08, 0.09, 0.11))),
      decl("border-color", colorValue(rgb(0.21, 0.24, 0.28)))
    ]),
    rule(disabledChoice, [
      decl("opacity", number(0.52)),
      decl("cursor", keyword("default")),
      decl("background-color", colorValue(rgb(0.10, 0.11, 0.13))),
      decl("border-color", colorValue(rgb(0.23, 0.26, 0.31))),
      decl("box-shadow", shadowValue(offsetX = px(0), offsetY = px(0), blur = some(px(0))))
    ]),
    rule(disabledRadio, [
      decl("opacity", number(0.52)),
      decl("cursor", keyword("default")),
      decl("background-color", colorValue(rgb(0.10, 0.11, 0.13))),
      decl("border-color", colorValue(rgb(0.23, 0.26, 0.31))),
      decl("box-shadow", shadowValue(offsetX = px(0), offsetY = px(0), blur = some(px(0))))
    ]),
    rule(disabledListItem, [
      decl("opacity", number(0.46)),
      decl("cursor", keyword("default")),
      decl("color", colorValue(rgb(0.47, 0.52, 0.58)))
    ]),
    rule(disabledCommandItem, [
      decl("opacity", number(0.46)),
      decl("cursor", keyword("default")),
      decl("color", colorValue(rgb(0.47, 0.52, 0.58)))
    ])
  ])

proc addButtonStateOverrides(ui: UiRoot; button: ButtonHandle) =
  button.container.applyHoverStyle(hoverButtonStyle())
  button.container.applyActiveStyle(activeButtonStyle())

proc RunButton(ui: UiRoot; onRun: proc() {.closure.}; style = primaryButtonStyle()): ButtonHandle {.discardable.} =
  result = ui.button("Run", style = style)
  ui.addButtonStateOverrides(result)
  proc handleRun(event: DispatchResult): bool =
    onRun()
    true

  result.onClick = handleRun

proc ToolButton(ui: UiRoot; label: string; style = buttonStyle()): ButtonHandle {.discardable.} =
  result = ui.button(label, style = style)
  ui.addButtonStateOverrides(result)

proc Header(ui: UiRoot): NodeHandle {.discardable.} =
  ui.box(result, headerStyle()):
    ui.text("Clay Board Style System", titleStyle())
    ui.box(badgeStyle()):
      ui.text("SDL3")

proc Toolbar(ui: UiRoot; onRun: proc() {.closure.}): NodeHandle {.discardable.} =
  ui.box(result, toolbarStyle()):
    RunButton(ui, onRun)
    ui.box(spacerStyle())
    ToolButton(ui, "Inspect")
    ToolButton(ui, "Export")

proc StatusPanel(ui: UiRoot; state: DemoState; refs: DemoViewRefs): NodeHandle {.discardable.} =
  ui.box(result, statusStyle()):
    let label = ui.text(state.statusText())
    refs.statusText = some(label.id)

proc syncStatusText(ui: UiRoot; refs: DemoViewRefs; state: DemoState) =
  if refs.statusText.isSome:
    ui.tree.nodes[refs.statusText.get.nodeIndex].text = state.statusText()

proc syncTabStatusText(ui: UiRoot; refs: DemoViewRefs; value: string) =
  if refs.tabStatusText.isSome:
    ui.tree.nodes[refs.tabStatusText.get.nodeIndex].text = tabStatusTextFor(value)

proc syncAltTabStatusText(ui: UiRoot; refs: DemoViewRefs; value: string) =
  if refs.altTabStatusText.isSome:
    ui.tree.nodes[refs.altTabStatusText.get.nodeIndex].text = altTabStatusTextFor(value)

proc LogicalPanel(ui: UiRoot): NodeHandle {.discardable.} =
  ui.box(result, logicalPanelStyle()):
    ui.text("logical", logicalLabelStyle())
    ui.text("inline/block", logicalLabelStyle())
    ui.text("border start/end", logicalLabelStyle())

proc DemoTextInput(ui: UiRoot; state: DemoState; valueDispatch: DispatchProc[DemoAction]): TextInputHandle {.discardable.} =
  result = ui.textInput(
    TextInputParams(value: state.heroInput, placeholder: "Type here"),
    style = textInputStyle(),
    textStyle = textInputValueStyle(),
    id = "hero-input"
  )

  result.container.onInput = proc(event: DispatchResult): bool =
    if event.event.text.isSome:
      valueDispatch(DemoAction(kind: dakHeroInputChanged, value: event.event.text.get))
    false

proc ControlsPanel(
    ui: UiRoot;
    state: DemoState;
    valueDispatch: DispatchProc[DemoAction];
    refs: DemoViewRefs
): NodeHandle {.discardable.} =
  ui.box(result, controlsPanelStyle()):
    ui.box(controlRowStyle()):
      ui.text("menu", controlLabelStyle())
      ui.selectBox(
        [
          SelectOption(label: "Balanced", value: "balanced"),
          SelectOption(label: "Compact", value: "compact"),
          SelectOption(label: "Detailed", value: "detailed")
        ],
        selectedValue = "balanced",
        style = selectStyle(),
        valueStyle = choiceLabelStyle(),
        panelStyle = selectPanelStyle(),
        optionStyle = selectOptionStyle()
      )

    ui.box(controlRowStyle()):
      ui.text("choices", controlLabelStyle())
      ui.checkbox(
        "Snap",
        checked = true,
        style = choiceStyle(),
        markerStyle = choiceMarkerStyle(),
        labelStyle = choiceLabelStyle()
      )
      let mode = initRadioSet("edit")
      ui.radio(mode, "Edit", "edit", style = choiceStyle(), markerStyle = radioMarkerStyle(), labelStyle = choiceLabelStyle())
      ui.radio(mode, "Preview", "preview", style = choiceStyle(), markerStyle = radioMarkerStyle(), labelStyle = choiceLabelStyle())

    ui.box(controlRowStyle()):
      ui.text("slider", controlLabelStyle())
      ui.slider(
        value = 64,
        min = 0,
        max = 100,
        step = 4,
        trackWidth = 144,
        style = sliderStyle(),
        trackStyle = sliderTrackStyle(),
        fillStyle = sliderFillStyle(),
        thumbStyle = sliderThumbStyle(),
        valueStyle = controlValueStyle()
      )
      ui.progress(
        value = 72,
        max = 100,
        trackWidth = 144,
        style = progressStyle(),
        trackStyle = progressTrackStyle(),
        fillStyle = progressFillStyle(),
        valueStyle = controlValueStyle()
      )

    ui.box(controlRowStyle()):
      ui.text("tabs", controlLabelStyle())
      let demoTabs = ui.tabs(
        [
          TabItem(label: "Info", value: "info"),
          TabItem(label: "Data", value: "data"),
          TabItem(label: "Logs", value: "logs")
        ],
        selectedValue = state.selectedTab,
        style = tabsStyle(),
        tabStyle = tabStyle()
      )
      demoTabs.onChange = proc(event: DispatchResult): bool =
        let value = demoTabs.selectedValue()
        valueDispatch(DemoAction(kind: dakTabSelected, value: value))
        ui.syncTabStatusText(refs, value)
        false

    ui.box(controlRowStyle()):
      ui.text("", controlLabelStyle())
      let status = ui.text(state.tabStatusText(), tabStatusStyle())
      refs.tabStatusText = some(status.id)

proc AltControlsPanel(
    ui: UiRoot;
    state: DemoState;
    valueDispatch: DispatchProc[DemoAction];
    refs: DemoViewRefs
): NodeHandle {.discardable.} =
  ui.box(result, altPanelStyle()):
    ui.box(altRowStyle()):
      ui.text("menu", altLabelStyle())
      ui.selectBox(
        [
          SelectOption(label: "Standard", value: "standard"),
          SelectOption(label: "Editorial", value: "editorial"),
          SelectOption(label: "Dense", value: "dense")
        ],
        selectedValue = "standard",
        style = altSelectStyle(),
        valueStyle = altTextStyle(),
        panelStyle = altSelectPanelStyle(),
        optionStyle = altSelectOptionStyle(),
        groups = ["select-alt"]
      )

    ui.box(altRowStyle()):
      ui.text("choices", altLabelStyle())
      ui.checkbox(
        "Pinned",
        checked = true,
        style = altChoiceStyle(),
        markerStyle = altCheckboxMarkerStyle(),
        labelStyle = altTextStyle(),
        groups = ["checkbox-alt"]
      )
      let mode = initRadioSet("view")
      ui.radio(mode, "View", "view", style = altChoiceStyle(), markerStyle = altRadioMarkerStyle(), labelStyle = altTextStyle(), groups = ["radio-alt"])
      ui.radio(mode, "Edit", "edit", style = altChoiceStyle(), markerStyle = altRadioMarkerStyle(), labelStyle = altTextStyle(), groups = ["radio-alt"])

    ui.box(altRowStyle()):
      ui.text("range", altLabelStyle())
      ui.slider(
        value = 38,
        min = 0,
        max = 100,
        step = 2,
        trackWidth = 144,
        style = altSliderStyle(),
        trackStyle = altSliderTrackStyle(),
        fillStyle = altSliderFillStyle(),
        thumbStyle = altSliderThumbStyle(),
        valueStyle = altValueStyle()
      )
      ui.progress(
        value = 46,
        max = 100,
        trackWidth = 144,
        style = altProgressStyle(),
        trackStyle = altProgressTrackStyle(),
        fillStyle = altProgressFillStyle(),
        valueStyle = altValueStyle()
      )

    ui.box(altRowStyle()):
      ui.text("tabs", altLabelStyle())
      let demoTabs = ui.tabs(
        [
          TabItem(label: "Info", value: "info"),
          TabItem(label: "Data", value: "data"),
          TabItem(label: "Logs", value: "logs")
        ],
        selectedValue = state.altSelectedTab,
        style = altTabsStyle(),
        tabStyle = altTabStyle(),
        tabGroups = ["tab-alt"]
      )
      demoTabs.onChange = proc(event: DispatchResult): bool =
        let value = demoTabs.selectedValue()
        valueDispatch(DemoAction(kind: dakAltTabSelected, value: value))
        ui.syncAltTabStatusText(refs, value)
        false

    ui.box(altRowStyle()):
      ui.text("", altLabelStyle())
      let status = ui.text(state.altTabStatusText(), altTabStatusStyle())
      refs.altTabStatusText = some(status.id)

proc PropertyPanel(ui: UiRoot): NodeHandle {.discardable.} =
  result = ui.box(propertyPanelStyle(), code = "property-panel")
  ui.pushParent(result)
  try:
    ui.box(propertyRowStyle()):
      ui.box(propertyLabelStyle()):
        ui.text("paint", propertyLabelTextStyle())
      ui.box(outlineSampleStyle()):
        ui.text("outline")
      ui.text("shadow text", shadowTextSampleStyle())
      ui.box(opacitySampleStyle()):
        ui.text("opacity")
    ui.box(propertyRowStyle()):
      ui.box(propertyLabelStyle()):
        ui.text("decoration", propertyLabelTextStyle())
      ui.text("solid", decoratedSampleStyle("solid", 72))
      ui.text("dashed", decoratedSampleStyle("dashed", 82))
      ui.text("dotted", decoratedSampleStyle("dotted", 80))
      ui.text("double", decoratedSampleStyle("double", 82))
    ui.box(propertyRowStyle()):
      ui.box(propertyLabelStyle()):
        ui.text("visibility", propertyLabelTextStyle())
      ui.box(overflowClipSampleStyle()):
        ui.text("overflow hidden clips long text", overflowClipTextStyle())
      ui.box(contentHiddenSampleStyle()):
        ui.text("hidden")
      let scrollSample = ui.box(
        scrollSampleStyle(), id = "property-scroll-sample"
      )
      ui.pushParent(scrollSample)
      try:
        ui.text("scroll row 1", scrollSampleLineStyle())
        ui.text("scroll row 2", scrollSampleLineStyle())
        ui.text("scroll row 3", scrollSampleLineStyle())
      finally:
        ui.popParent()
  finally:
    ui.popParent()

proc ComponentCatalog(
    ui: UiRoot;
    state: DemoState;
    dispatch: DispatchProc[DemoAction];
    valueDispatch: DispatchProc[DemoAction]
): NodeHandle {.discardable.} =
  ui.box(result, catalogColumnStyle()):
    ui.text("Component catalog", catalogTitleStyle())

    ui.box(catalogSectionStyle(124)):
      ui.box(catalogRowStyle()):
        ui.text("text input", catalogLabelStyle())
        let compact = ui.textInput(
          TextInputParams(value: state.catalogInput, placeholder: "Type"),
          style = compactInputStyle(190),
          textStyle = compactInputValueStyle(),
          id = "catalog-input"
        )
        compact.container.onInput = proc(event: DispatchResult): bool =
          if event.event.text.isSome:
            valueDispatch(DemoAction(kind: dakCatalogInputChanged, value: event.event.text.get))
          false
        ui.label("label target", compact, style = choiceStyle(), textStyle = choiceLabelStyle())
      ui.box(catalogRowStyle()):
        ui.text("textarea", catalogLabelStyle())
        let area = ui.textArea(
          TextAreaParams(
            value: state.catalogTextarea,
            placeholder: "Notes",
            resize: some(rkBoth),
            width: some(206'f32),
            height: some(70'f32),
            minWidth: some(206'f32),
            maxWidth: some(206'f32),
            minHeight: some(54'f32),
            maxHeight: some(96'f32)
          ),
          style = textAreaStyle(),
          textStyle = textAreaValueStyle(),
          id = "catalog-textarea"
        )
        area.container.onInput = proc(event: DispatchResult): bool =
          if event.event.text.isSome:
            valueDispatch(DemoAction(kind: dakCatalogTextareaChanged, value: event.event.text.get))
          false

    ui.box(catalogSectionStyle(118)):
      ui.box(catalogSplitRowStyle(96), "command-menu-row"):
        ui.box(catalogLabeledStackStyle(150)):
          ui.text(
            "list box",
            catalogStackLabelStyle(150),
            id = "catalog-list-box-label"
          )
          ui.listBox(
            [
              ListItem(label: "Overview", value: "overview"),
              ListItem(label: "Details", value: "details"),
              ListItem(label: "Disabled", value: "disabled", disabled: true)
            ],
            selectedValue = "details",
            style = listBoxStyle(),
            itemStyle = listItemStyle(),
            id = "catalog-list-box"
          )
        ui.box(catalogLabeledStackStyle(154)):
          ui.text(
            "command menu",
            catalogStackLabelStyle(154),
            id = "catalog-command-menu-label"
          )
          ui.commandMenu(
            [
              CommandMenuItem(label: "Open", value: "open"),
              CommandMenuItem(label: "Rename", value: "rename"),
              CommandMenuItem(label: "Delete", value: "delete", disabled: true)
            ],
            open = true,
            style = commandMenuStyle(),
            itemStyle = commandMenuItemStyle(),
            id = "catalog-command-menu"
          )

    ui.box(catalogSectionStyle(196)):
      ui.box(catalogTallRowStyle()):
        ui.text("dialog", catalogLabelStyle())
        ui.dialog(
          title = "Dialog",
          body = "Open state with title\nand body.",
          open = true,
          modal = false,
          style = dialogStyle(),
          titleStyle = dialogTitleStyle(),
          bodyStyle = dialogBodyStyle()
        )
        ui.box(imageFrameStyle()):
          discard ui.image(
            "examples/assets/catalog-preview.png",
            width = 96,
            height = 64,
            style = uiStyle([
              decl("width", px(96)),
              decl("height", px(64)),
              decl("object-fit", keyword("cover")),
              decl("object-position", keyword("center"))
            ])
          )
          ui.text("image", imageLabelStyle())
      ui.box(catalogTallRowStyle()):
        ui.text("details", catalogLabelStyle())
        ui.details(
          "Native component notes",
          "Click the summary to collapse or\nexpand this content.",
          open = true,
          style = detailsStyle(),
          summaryStyle = detailsSummaryStyle(),
          markerStyle = detailsMarkerStyle(),
          summaryTextStyle = detailsSummaryTextStyle(),
          bodyStyle = detailsBodyStyle()
        )

    ui.box(catalogSectionStyle(230)):
      ui.box(catalogFieldsetRowStyle()):
        ui.text("form", catalogLabelStyle())
        let demoForm = ui.form(valid = true, style = formShellStyle())
        ui.pushParent(demoForm.container)
        try:
          ui.text("Form shell", legendStyle())
          let nameInput = ui.textInput(
            TextInputParams(value: state.formName, placeholder: "Name"),
            style = compactInputStyle(188),
            textStyle = compactInputValueStyle(),
            id = "form-name-input"
          )
          nameInput.container.onInput = proc(event: DispatchResult): bool =
            if event.event.text.isSome:
              valueDispatch(DemoAction(kind: dakFormNameChanged, value: event.event.text.get))
            false
          ui.label("Name label", nameInput, style = choiceStyle(), textStyle = choiceLabelStyle())
        finally:
          ui.popParent()
      ui.box(catalogTallRowStyle()):
        ui.text("fieldset", catalogLabelStyle())
        let disabledSet = ui.fieldset(
          "Disabled fieldset",
          disabled = true,
          style = fieldsetStyle(),
          legendStyle = legendStyle()
        )
        ui.pushParent(disabledSet.container)
        ui.pushFieldsetContext(proc(setter: DisabledSetter) =
          disabledSet.addDisabledTarget(setter)
        )
        try:
          ui.checkbox(
            "Locked",
            checked = true,
            style = choiceStyle(),
            markerStyle = choiceMarkerStyle(),
            labelStyle = choiceLabelStyle()
          )
          ui.textInput(
            TextInputParams(value: state.fieldsetInput),
            style = compactInputStyle(200),
            textStyle = compactInputValueStyle(180),
            id = "fieldset-disabled-input"
          )
        finally:
          ui.popFieldsetContext()
          ui.popParent()

proc OverlayBadge(ui: UiRoot): NodeHandle {.discardable.} =
  ui.box(result, overlayStyle(), "absolute-badge"):
    ui.text("absolute")

proc App(
    ui: UiRoot;
    state: DemoState;
    dispatch: DispatchProc[DemoAction];
    valueDispatch: DispatchProc[DemoAction];
    refs: DemoViewRefs;
    onRun: proc() {.closure.}
): NodeHandle {.discardable.} =
  ui.addStyle(buttonStateStyles())
  ui.box(result, surfaceStyle(), "demo-surface"):
    Header(ui)
    ui.box(demoBodyStyle(), "demo-body"):
      ui.box(demoColumnStyle()):
        Toolbar(ui, onRun)
        DemoTextInput(ui, state, valueDispatch)
        ControlsPanel(ui, state, valueDispatch, refs)
        AltControlsPanel(ui, state, valueDispatch, refs)
        PropertyPanel(ui)
        StatusPanel(ui, state, refs)
        LogicalPanel(ui)
      ComponentCatalog(ui, state, dispatch, valueDispatch)
    OverlayBadge(ui)

proc makeUi(
    state: DemoState;
    dispatch: DispatchProc[DemoAction];
    valueDispatch: DispatchProc[DemoAction];
    refs: DemoViewRefs;
    onRun: proc() {.closure.};
    clipboardRead: proc(): string {.closure.};
    clipboardWrite: proc(text: string) {.closure.}
): UiRoot =
  result = initUiRoot()
  result.configureClipboardTextProvider(clipboardRead)
  result.configureClipboardTextWriter(clipboardWrite)
  let app = App(result, state, dispatch, valueDispatch, refs, onRun)
  result.mountDefaultContextMenu(app)

proc initDemoHarness*(): DemoHarness =
  DemoHarness(
    runtime: initStateRuntime(DemoState(
      runClicks: 0,
      selectedTab: "info",
      altSelectedTab: "info",
      heroInput: "",
      catalogInput: "Editable",
      catalogTextarea: "Line one\nLine two",
      formName: "Ada",
      fieldsetInput: "Disabled"
    ), updateDemo),
    refs: DemoViewRefs(statusText: none(NodeId)),
    clipboard: "",
    runClicks: 0
  )

proc buildDemoHarnessUi*(harness: DemoHarness): UiRoot =
  proc handleRun() =
    inc harness.runClicks
  proc readClipboard(): string =
    harness.clipboard
  proc writeClipboard(text: string) =
    harness.clipboard = text.truncateUtf8ForDemo(maxDemoClipboardBytes)
  makeUi(
    harness.runtime.state,
    harness.runtime.dispatcher(),
    harness.runtime.silentDispatcher(),
    harness.refs,
    handleRun,
    readClipboard,
    writeClipboard
  )

proc consumeDemoHarnessDirty*(harness: DemoHarness): bool =
  harness.runtime.consumeDirty()

proc setDemoHarnessClipboard*(harness: DemoHarness; text: string) =
  harness.clipboard = text.truncateUtf8ForDemo(maxDemoClipboardBytes)

proc demoHarnessClipboard*(harness: DemoHarness): string =
  harness.clipboard

proc elapsedMs(start: float): string

proc subtreeMembership(tree: Tree; root: NodeId): seq[bool] =
  result = newSeq[bool](tree.nodes.len)
  if root.nodeIndex < 0 or root.nodeIndex >= tree.nodes.len:
    return
  var pending = @[root]
  while pending.len > 0:
    let id = pending.pop()
    if result[id.nodeIndex]:
      continue
    result[id.nodeIndex] = true
    for child in tree.nodes[id.nodeIndex].children:
      pending.add child

proc replaceSpan[T](
    items: var seq[T];
    start, count: int;
    replacement: openArray[T]
) =
  assert start >= 0 and count >= 0 and start + count <= items.len
  let oldLen = items.len
  let delta = replacement.len - count
  if delta > 0:
    items.setLen(oldLen + delta)
    if start + count < oldLen:
      for index in countdown(oldLen - 1, start + count):
        items[index + delta] = move(items[index])
  elif delta < 0:
    for index in start + count ..< oldLen:
      items[index + delta] = move(items[index])
    items.setLen(oldLen + delta)
  for index, item in replacement:
    items[start + index] = item

proc buildFrame(
    ui: UiRoot;
    viewport: Size;
    textEngine: TextEngine;
    fonts: FontRegistry
): FrameData =
  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    quit 1

  let layout = computeLayout(ui.tree, styles, viewport, textEngine, fonts)
  ui.scroll.syncScrollState(ui.tree, styles, layout)
  FrameData(
    styles: styles,
    layout: layout,
    commands: buildPaintCommands(ui.tree, styles, layout, ui.scroll),
    dynamicCommands: @[],
    scrollDynamicCommands: @[],
    scrollDynamicTarget: none(NodeId),
    scrollHitStart: -1,
    scrollHitCount: 0,
    regions: buildHitRegions(ui.tree, layout, styles, ui.scroll)
  )

proc repaintFrame(ui: UiRoot; frame: var FrameData) =
  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    quit 1

  frame.styles = styles
  ui.scroll.syncScrollState(ui.tree, styles, frame.layout)
  frame.commands = buildPaintCommands(ui.tree, styles, frame.layout, ui.scroll)
  frame.regions = buildHitRegions(ui.tree, frame.layout, styles, ui.scroll)
  frame.dynamicCommands.setLen(0)
  frame.scrollDynamicCommands.setLen(0)
  frame.scrollDynamicTarget = none(NodeId)
  frame.scrollHitStart = -1
  frame.scrollHitCount = 0

proc repaintScrollFrame(ui: UiRoot; frame: var FrameData; target: NodeId) =
  ## A retained scroll offset changes paint and hit coordinates, not styles or
  ## layout. During active scrolling, only the moving subtree is rebuilt and
  ## composited over a static layer that excludes that subtree.
  frame.scrollDynamicCommands = buildPaintCommandsForSubtree(
    ui.tree, frame.styles, frame.layout, target, ui.scroll
  )
  if frame.scrollDynamicTarget != some(target):
    let membership = subtreeMembership(ui.tree, target)
    var first = -1
    var last = -1
    for index, region in frame.regions:
      if region.node.nodeIndex >= 0 and
          region.node.nodeIndex < membership.len and
          membership[region.node.nodeIndex]:
        if first < 0:
          first = index
        last = index
    frame.scrollHitStart = first
    frame.scrollHitCount =
      if first >= 0: last - first + 1
      else: 0

  let updatedRegions = buildHitRegionsForSubtree(
    ui.tree, frame.layout, frame.styles, target, ui.scroll
  )
  if frame.scrollHitStart >= 0:
    frame.regions.replaceSpan(
      frame.scrollHitStart, frame.scrollHitCount, updatedRegions
    )
    frame.scrollHitCount = updatedRegions.len
  frame.scrollDynamicTarget = some(target)

proc finishScrollFrame(ui: UiRoot; frame: var FrameData) =
  ## Bake the final offset and hidden scrolling-only scrollbar back once.
  frame.commands = buildPaintCommands(
    ui.tree, frame.styles, frame.layout, ui.scroll
  )
  frame.regions = buildHitRegions(
    ui.tree, frame.layout, frame.styles, ui.scroll
  )
  frame.scrollDynamicCommands.setLen(0)
  frame.scrollDynamicTarget = none(NodeId)
  frame.scrollHitStart = -1
  frame.scrollHitCount = 0

proc repaintTextControlFrame(
    ui: UiRoot;
    frame: var FrameData;
    target: NodeId;
    textEngine: TextEngine;
    fonts: FontRegistry
) =
  when defined(cbssTracePerf):
    echo "[perf-detail] text repaint begin target=", target.nodeIndex
    flushFile(stdout)
  var diagnostics: Diagnostics
  let sheets = ui.styleSheets()
  let styleStart = epochTime()
  if not resolveSubtreeStyles(
      ui.tree,
      target,
      sheets,
      defaultProperties(),
      diagnostics,
      frame.styles
  ):
    frame.styles = resolveTreeStyles(ui.tree, sheets, defaultProperties(), diagnostics)
  when defined(cbssTracePerf):
    echo "[perf-detail] text styles ms=", elapsedMs(styleStart), " target=", target.nodeIndex
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    quit 1

  let layoutStart = epochTime()
  discard relayoutSubtree(ui.tree, frame.styles, target, frame.layout, textEngine, fonts)
  ui.scroll.syncScrollState(ui.tree, frame.styles, frame.layout)
  when defined(cbssTracePerf):
    echo "[perf-detail] text layout ms=", elapsedMs(layoutStart), " target=", target.nodeIndex
  let paintStart = epochTime()
  frame.dynamicCommands = buildPaintCommandsForSubtree(
    ui.tree,
    frame.styles,
    frame.layout,
    target,
    ui.scroll
  )
  when defined(cbssTracePerf):
    echo "[perf-detail] text commands ms=", elapsedMs(paintStart),
      " count=", frame.dynamicCommands.len

proc repaintDirtySubtrees(
    ui: UiRoot;
    frame: var FrameData;
    roots: openArray[NodeId];
    textEngine: TextEngine;
    fonts: FontRegistry
) =
  var diagnostics: Diagnostics
  let sheets = ui.styleSheets()
  let styleStart = epochTime()
  for root in roots:
    discard resolveSubtreeStyles(
      ui.tree,
      root,
      sheets,
      defaultProperties(),
      diagnostics,
      frame.styles
    )
  when defined(cbssTracePerf):
    echo "[perf-detail] dirty styles ms=", elapsedMs(styleStart), " roots=", roots.len
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    quit 1
  let layoutStart = epochTime()
  for root in roots:
    discard relayoutSubtree(ui.tree, frame.styles, root, frame.layout, textEngine, fonts)
  ui.scroll.syncScrollState(ui.tree, frame.styles, frame.layout)
  when defined(cbssTracePerf):
    echo "[perf-detail] dirty layout ms=", elapsedMs(layoutStart), " roots=", roots.len
  let paintStart = epochTime()
  frame.commands = buildPaintCommands(ui.tree, frame.styles, frame.layout, ui.scroll)
  frame.regions = buildHitRegions(ui.tree, frame.layout, frame.styles, ui.scroll)
  frame.dynamicCommands.setLen(0)
  frame.scrollDynamicCommands.setLen(0)
  frame.scrollDynamicTarget = none(NodeId)
  frame.scrollHitStart = -1
  frame.scrollHitCount = 0
  when defined(cbssTracePerf):
    echo "[perf-detail] dirty commands ms=", elapsedMs(paintStart), " count=", frame.commands.len

const traceTextInput = defined(cbssTraceTextInput)
const traceBackspaceLock = defined(cbssTraceBackspaceLock)
proc nodeTraceLabel(ui: UiRoot; target: Option[NodeId]): string =
  if target.isNone:
    return "none"
  let id = target.get
  if id.nodeIndex < 0 or id.nodeIndex >= ui.tree.nodes.len:
    return "invalid#" & $id.nodeIndex
  let node = ui.tree.nodes[id.nodeIndex]
  result = "#" & $id.nodeIndex
  if node.id.len > 0:
    result.add "(" & node.id & ")"
  if node.groups.len > 0:
    result.add "["
    for index, group in node.groups:
      if index > 0:
        result.add ","
      result.add group
    result.add "]"

proc traceInput(ui: UiRoot; message: string) =
  if traceTextInput:
    echo "[input ", formatFloat(epochTime(), ffDecimal, 3), "] ", message

proc traceBackspace(ui: UiRoot; message: string) =
  if traceBackspaceLock:
    echo "[backspace ", formatFloat(epochTime(), ffDecimal, 3), "] ", message

proc tracePerf(ui: UiRoot; message: string) =
  when defined(cbssTracePerf):
    echo "[perf  ", formatFloat(epochTime(), ffDecimal, 3), "] ", message

proc elapsedMs(start: float): string =
  formatFloat((epochTime() - start) * 1000.0, ffDecimal, 2)

proc pendingTrace(ui: UiRoot; pendingTextInput: Option[PendingTextInput]): string =
  if pendingTextInput.isNone:
    return "none"
  let pending = pendingTextInput.get
  ui.nodeTraceLabel(some(pending.target)) & " text=\"" & pending.text &
    "\" focusSerial=" & $pending.focusSerial &
    " keyTimestamp=" & $pending.keyTimestamp

proc compositionTrace(ui: UiRoot; composition: Option[CompositionInput]): string =
  if composition.isNone:
    return "none"
  let active = composition.get
  ui.nodeTraceLabel(some(active.target)) & " focusSerial=" & $active.focusSerial

proc eventTrace(event: Sdl3Event): string =
  result = $event.kind & " timestamp=" & $event.timestamp
  case event.kind
  of sekKeyDown, sekKeyUp:
    result.add " key=\"" & event.key & "\" repeat=" & $event.repeat
  of sekTextInput, sekCompositionStart, sekCompositionUpdate, sekCompositionEnd:
    result.add " text=\"" & event.text & "\""
  of sekCompositionCandidates:
    result.add " candidates=" & $event.candidates.len &
      " selected=" & $event.selectedCandidate &
      " horizontal=" & $event.horizontalCandidates
  of sekPointerDown, sekPointerUp:
    result.add " button=" & $event.button &
      " point=(" & $event.buttonX & "," & $event.buttonY & ")"
  of sekPointerMove:
    result.add " point=(" & $event.x & "," & $event.y & ")"
  else:
    discard

proc traceRawEvent(label: string; event: Sdl3Event) =
  if traceTextInput and event.kind in {
      sekKeyDown, sekKeyUp, sekTextInput,
      sekCompositionStart, sekCompositionUpdate, sekCompositionEnd, sekCompositionCandidates,
      sekPointerDown, sekPointerUp
  }:
    echo "[cbss text-input] " & label & " " & event.eventTrace()

proc writeCapturedFramePpm(path: string; frame: Sdl3CapturedFrame) =
  var data = "P3\n" & $frame.width & " " & $frame.height & "\n255\n"
  for y in 0 ..< frame.height:
    for x in 0 ..< frame.width:
      let offset = (y * frame.width + x) * 3
      data.add $frame.pixels[offset] & " " &
        $frame.pixels[offset + 1] & " " &
        $frame.pixels[offset + 2]
      if x + 1 < frame.width:
        data.add " "
    data.add "\n"
  writeFile(path, data)

proc subtreeNodes(ui: UiRoot; target: NodeId): seq[NodeId] =
  if target.nodeIndex < 0 or target.nodeIndex >= ui.tree.nodes.len:
    return
  var pending = @[target]
  while pending.len > 0:
    let current = pending.pop()
    result.add current
    for child in ui.tree.nodes[current.nodeIndex].children:
      pending.add child

proc textControlDynamicNodes(ui: UiRoot; target: NodeId): seq[NodeId] =
  ui.subtreeNodes(target)

proc containsNode(nodes: openArray[NodeId]; target: NodeId): bool =
  for node in nodes:
    if node == target:
      return true

proc addDirtyRoot(roots: var seq[NodeId]; target: Option[NodeId]) =
  if target.isNone:
    return
  for existing in roots:
    if existing == target.get:
      return
  roots.add target.get

proc isPrintableTextKey(key: string; ctrl, alt, meta: bool): bool =
  not ctrl and not alt and not meta and key.len == 1 and key[0] >= ' ' and key[0] <= '~'

proc printableTextFromKey(key: string; ctrl, alt, meta: bool): Option[string] =
  if not isPrintableTextKey(key, ctrl, alt, meta):
    return none(string)
  some(key)

proc deleteLastUtf8Rune(text: var string): bool =
  if text.len == 0:
    return false
  var start = text.len - 1
  while start > 0 and (ord(text[start]) and 0b1100_0000) == 0b1000_0000:
    dec start
  text.delete(start .. text.len - 1)
  true

proc truncateUtf8ForDemo(text: string; maxBytes: int): string =
  if maxBytes <= 0:
    return ""
  if text.len <= maxBytes:
    return text
  var stop = maxBytes
  while stop > 0 and (ord(text[stop]) and 0b1100_0000) == 0b1000_0000:
    dec stop
  text[0 ..< stop]

proc isTextInputTarget(ui: UiRoot; target: NodeId): bool =
  target.nodeIndex >= 0 and target.nodeIndex < ui.tree.nodes.len and
    (ui.tree.nodes[target.nodeIndex].hasGroup("text-input") or
      ui.tree.nodes[target.nodeIndex].hasGroup("textarea"))

proc isValidTextInputTarget(ui: UiRoot; target: NodeId): bool =
  target.nodeIndex >= 0 and target.nodeIndex < ui.tree.nodes.len and
    ui.isTextInputTarget(target) and
    esDisabled notin ui.tree.nodes[target.nodeIndex].states

proc inputTargetForHit(ui: UiRoot; target: Option[NodeId]): Option[NodeId] =
  var current = target
  while current.isSome:
    let id = current.get
    if ui.isTextInputTarget(id):
      if ui.isValidTextInputTarget(id):
        return some(id)
      return none(NodeId)
    current = ui.tree.nodes[id.nodeIndex].parent
  none(NodeId)

proc isTextControlChromeHit(ui: UiRoot; target: Option[NodeId]): bool =
  var current = target
  while current.isSome:
    let id = current.get
    if id.nodeIndex >= 0 and id.nodeIndex < ui.tree.nodes.len:
      let node = ui.tree.nodes[id.nodeIndex]
      if node.hasGroup("textarea-resize-handle") or
          node.hasGroup("textarea-scrollbar-track") or
          node.hasGroup("textarea-scrollbar-thumb"):
        return true
    current = ui.tree.nodes[id.nodeIndex].parent
  false

proc textControlHitAtPoint(
    ui: UiRoot;
    regions: openArray[HitRegion];
    point: Vec2
): Option[HitTestResult] =
  var bestTarget = none(NodeId)
  var bestRect = rect(0, 0, 0, 0)
  var bestArea = 0.0'f32
  for region in regions:
    if not region.rect.contains(point):
      continue
    let target = ui.inputTargetForHit(some(region.node))
    if target.isNone or ui.isTextControlChromeHit(some(region.node)):
      continue
    var targetRect = region.rect
    for candidate in regions:
      if candidate.node == target.get:
        targetRect = candidate.rect
        break
    let area = targetRect.w * targetRect.h
    if bestTarget.isNone or area < bestArea:
      bestTarget = target
      bestRect = targetRect
      bestArea = area
  if bestTarget.isSome:
    return some(HitTestResult(
      node: bestTarget.get,
      local: vec2(point.x - bestRect.x, point.y - bestRect.y)
    ))
  none(HitTestResult)

proc localForNodeAtPoint(
    regions: openArray[HitRegion];
    target: NodeId;
    point: Vec2
): Option[Vec2] =
  for region in regions:
    if region.node == target:
      return some(vec2(point.x - region.rect.x, point.y - region.rect.y))
  none(Vec2)

proc normalizeTextControlDispatches(
    ui: UiRoot;
    regions: openArray[HitRegion];
    dispatches: var seq[DispatchResult]
) =
  for dispatch in dispatches.mitems:
    if dispatch.event.kind notin {iekPointerMove, iekPointerDown, iekPointerUp, iekDrag, iekDragOver}:
      continue
    if dispatch.event.position.isNone:
      continue
    if dispatch.event.kind == iekDrag and dispatch.target.isSome and ui.isTextInputTarget(dispatch.target.get):
      let local = localForNodeAtPoint(regions, dispatch.target.get, dispatch.event.position.get)
      if local.isSome:
        dispatch.local = local
      continue
    let textHit = ui.textControlHitAtPoint(regions, dispatch.event.position.get)
    if textHit.isSome:
      dispatch.target = some(textHit.get.node)
      dispatch.local = some(textHit.get.local)

proc isTextCaretNode(ui: UiRoot; id: NodeId): bool =
  id.nodeIndex >= 0 and id.nodeIndex < ui.tree.nodes.len and
    (ui.tree.nodes[id.nodeIndex].hasGroup("text-input-caret") or
      ui.tree.nodes[id.nodeIndex].hasGroup("textarea-caret"))

proc collectCaretNodes(ui: UiRoot; id: NodeId; output: var seq[NodeId]) =
  if id.nodeIndex < 0 or id.nodeIndex >= ui.tree.nodes.len:
    return
  if ui.isTextCaretNode(id):
    output.add id
  for child in ui.tree.nodes[id.nodeIndex].children:
    ui.collectCaretNodes(child, output)

proc caretNodesForTarget(ui: UiRoot; target: NodeId): seq[NodeId] =
  ui.collectCaretNodes(target, result)

proc caretBlinkSheet(ui: UiRoot; target: NodeId; visible: bool): StyleSheet =
  var rules: seq[StyleRule] = @[]
  let opacityValue = if visible: 1.0'f32 else: 0.0'f32
  for caretNode in ui.caretNodesForTarget(target):
    rules.add rule(
      target(caretNode),
      [decl("opacity", number(opacityValue))],
      priority = 1000
    )
  styleSheet(rules)

proc setCaretBlinkVisible(
    ui: UiRoot;
    inputState: InteractionState;
    blinkSheetIndex: var Option[int];
    visible: bool
): bool =
  if inputState.focusedTarget.isNone or not ui.isTextInputTarget(inputState.focusedTarget.get):
    return false
  let sheet = ui.caretBlinkSheet(inputState.focusedTarget.get, visible)
  if sheet.rules.len == 0:
    return false
  if blinkSheetIndex.isSome and blinkSheetIndex.get < ui.componentStyles.len:
    ui.componentStyles[blinkSheetIndex.get] = sheet
  else:
    ui.componentStyles.add sheet
    blinkSheetIndex = some(ui.componentStyles.len - 1)
  true

proc clearCaretBlinkSheet(ui: UiRoot; blinkSheetIndex: var Option[int]) =
  if blinkSheetIndex.isSome and blinkSheetIndex.get < ui.componentStyles.len:
    ui.componentStyles[blinkSheetIndex.get] = styleSheet([])
  blinkSheetIndex = none(int)

proc moveFocusedTextControlCaretToEnd(ui: UiRoot; target: NodeId) =
  discard ui.events.emit(ui.tree, target, keyDownEvent("End", ctrlKey = true))

proc moveTextControlFocus(
    ui: UiRoot;
    inputState: var InteractionState;
    direction: int
): bool =
  result = ui.moveFocus(inputState, direction)
  if result and inputState.focusedTarget.isSome and
      ui.isTextInputTarget(inputState.focusedTarget.get):
    ui.moveFocusedTextControlCaretToEnd(inputState.focusedTarget.get)

proc normalizeTextControlFocus(ui: UiRoot; inputState: var InteractionState; hitTarget: Option[NodeId]) =
  discard ui.normalizeFocus(inputState, hitTarget)

proc cursorForPoint(ui: UiRoot; regions: openArray[HitRegion]; point: Vec2): CursorKind =
  let hit = hitTest(regions, point)
  let hitTarget =
    if hit.isSome: some(hit.get.node)
    else: none(NodeId)
  if ui.isTextControlChromeHit(hitTarget):
    cursorForHit(hit)
  elif ui.inputTargetForHit(hitTarget).isSome or
      ui.textControlHitAtPoint(regions, point).isSome:
    ckText
  else:
    cursorForHit(hit)

proc isContextMenuHit(ui: UiRoot; target: Option[NodeId]): bool =
  var current = target
  while current.isSome:
    let id = current.get
    if ui.tree.nodes[id.nodeIndex].hasGroup("context-menu") or
        ui.tree.nodes[id.nodeIndex].hasGroup("context-menu-item"):
      return true
    current = ui.tree.nodes[id.nodeIndex].parent
  false

proc hasGroupInPath(ui: UiRoot; target: Option[NodeId]; groups: openArray[string]): bool =
  var current = target
  while current.isSome:
    let id = current.get
    if id.nodeIndex < 0 or id.nodeIndex >= ui.tree.nodes.len:
      return false
    for group in groups:
      if ui.tree.nodes[id.nodeIndex].hasGroup(group):
        return true
    current = ui.tree.nodes[id.nodeIndex].parent
  false

proc isLayoutChangingInteractionHit(ui: UiRoot; target: Option[NodeId]): bool =
  ui.hasGroupInPath(target, [
    "select", "select-alt", "select-panel", "select-option",
    "details", "details-summary", "details-marker", "details-summary-text",
    "radio", "radio-alt", "radio-marker", "radio-indicator",
    "text-input", "text-input-selection", "text-input-caret",
    "textarea", "textarea-selection", "textarea-caret",
    "textarea-resize-handle",
    "slider", "slider-track", "slider-fill", "slider-thumb", "slider-value"
  ])

proc isLayoutChangingDrag(ui: UiRoot; inputState: InteractionState): bool =
  ui.hasGroupInPath(inputState.pressedTarget, [
    "text-input", "text-input-selection", "text-input-caret",
    "textarea", "textarea-selection", "textarea-caret",
    "textarea-resize-handle",
    "slider", "slider-track", "slider-fill", "slider-thumb", "slider-value"
  ])

proc isTextEditRepeatKey(key: string): bool =
  key in [
    "Backspace", "Delete",
    "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown",
    "Home", "End", "PageUp", "PageDown"
  ]

proc isStaleAfterTextFocusChange(event: Sdl3Event; textFocusChangedAt: uint64): bool =
  textFocusChangedAt != 0'u64 and event.timestamp != 0'u64 and event.timestamp <= textFocusChangedAt

proc shouldYieldForInteractiveFrame(
    event: Sdl3Event;
    needsFrame, paintOnlyDirty, frameDirty: bool;
    processedEvents: int
): bool =
  if not needsFrame and not paintOnlyDirty and not frameDirty:
    return false
  if event.kind == sekKeyDown and
      (event.ctrl or event.meta) and
      event.key.toLowerAscii() in ["c", "x", "v"]:
    # Clipboard operations can trigger text shaping and platform ownership
    # changes. Preserve SDL queue order, but commit at most one per frame.
    return true
  if processedEvents >= 64:
    return true
  case event.kind
  of sekWheel:
    true
  of sekPointerMove:
    processedEvents >= 8
  of sekKeyDown:
    # A printable keydown is only ownership metadata. Keep draining until
    # SDL delivers the layout-aware text event, but paint editing keys now.
    paintOnlyDirty or frameDirty
  of sekTextInput, sekCompositionStart, sekCompositionUpdate, sekCompositionEnd:
    true
  of sekKeyUp, sekCompositionCandidates:
    false
  else:
    false

proc focusedTextInputPlacement(
    ui: UiRoot;
    frame: FrameData;
    inputState: InteractionState;
    viewport: Size
): tuple[area: Option[Rect], cursor: int] =
  if inputState.focusedTarget.isNone:
    return (none(Rect), 0)
  let focused = inputState.focusedTarget.get
  if not ui.isTextInputTarget(focused):
    return (none(Rect), 0)
  var area = none(Rect)
  for box in frame.layout.boxes:
    if box.node == focused:
      area = some(box.rect)
      break
  if area.isNone:
    return (none(Rect), 0)
  let inputRect = area.get
  var textArea = inputRect
  var cursorX = inputRect.x
  for caretNode in ui.caretNodesForTarget(focused):
    for box in frame.layout.boxes:
      if box.node == caretNode:
        cursorX = box.rect.x
        textArea = rect(
          inputRect.x,
          min(max(inputRect.y, box.rect.y), inputRect.y + inputRect.h - max(1.0'f32, box.rect.h)),
          inputRect.w,
          max(1.0'f32, min(inputRect.h, box.rect.h))
        )
        break
    if cursorX != inputRect.x:
      break
  let clamped = rect(
    min(max(0.0'f32, textArea.x), max(0.0'f32, viewport.w - 1.0'f32)),
    min(max(0.0'f32, textArea.y), max(0.0'f32, viewport.h - 1.0'f32)),
    min(textArea.w, max(1.0'f32, viewport.w - textArea.x)),
    min(textArea.h, max(1.0'f32, viewport.h - textArea.y))
  )
  var cursor = int(round(cursorX - clamped.x))
  cursor = max(0, min(cursor, int(round(clamped.w))))
  when defined(cbssTraceTextInputArea):
    ui.traceInput(
      "textInputArea target=" & ui.nodeTraceLabel(some(focused)) &
      " input=(" & $inputRect.x & "," & $inputRect.y & "," & $inputRect.w & "," & $inputRect.h & ")" &
      " area=(" & $clamped.x & "," & $clamped.y & "," & $clamped.w & "," & $clamped.h & ")" &
      " cursor=" & $cursor
    )
  return (some(clamped), cursor)

proc syncTextInputArea(app: var Sdl3Renderer; ui: UiRoot; frame: FrameData; inputState: InteractionState) =
  let placement = focusedTextInputPlacement(ui, frame, inputState, app.windowSize())
  discard app.setTextInputArea(placement.area, placement.cursor)

proc emitTextControlEvent(ui: UiRoot; target: NodeId; event: InputEvent): bool =
  let started = epochTime()
  when defined(cbssTracePerf):
    if event.kind in {iekPaste, iekTextInput, iekCompositionStart, iekCompositionUpdate, iekCompositionEnd}:
      echo "[perf-detail] dispatch begin kind=", event.kind,
        " bytes=", (if event.text.isSome: event.text.get.len else: 0),
        " target=", target.nodeIndex
      flushFile(stdout)
  result = ui.events.emit(ui.tree, target, event)
  when defined(cbssTracePerf):
    if event.kind in {iekPaste, iekTextInput, iekCompositionStart, iekCompositionUpdate, iekCompositionEnd}:
      echo "[perf-detail] dispatch kind=", event.kind,
        " ms=", elapsedMs(started),
        " bytes=", (if event.text.isSome: event.text.get.len else: 0),
        " target=", target.nodeIndex
      flushFile(stdout)

proc textEventTarget(
    ui: UiRoot;
    inputState: InteractionState;
    pendingTextInput: var Option[PendingTextInput];
    compositionTarget: Option[CompositionInput];
    text: string;
    textTimestamp: uint64;
    currentFocusSerial: int
): Option[NodeId] =
  ui.traceInput(
    "resolve textInput target focus=" & ui.nodeTraceLabel(inputState.focusedTarget) &
    " composition=" & ui.compositionTrace(compositionTarget) &
    " pending=" & ui.pendingTrace(pendingTextInput) &
    " text=\"" & text & "\""
  )
  if pendingTextInput.isSome:
    let pending = pendingTextInput.get
    pendingTextInput = none(PendingTextInput)
    let target = pending.target
    if inputState.focusedTarget.isSome and
        inputState.focusedTarget.get == target and
        pending.focusSerial == currentFocusSerial and
        (pending.keyTimestamp == 0'u64 or textTimestamp == 0'u64 or textTimestamp >= pending.keyTimestamp) and
        ui.isValidTextInputTarget(target):
      ui.traceInput("deliver textInput to pending target " & ui.nodeTraceLabel(some(target)))
      return some(target)
    ui.traceInput(
      "drop stale pending textInput target=" & ui.nodeTraceLabel(some(target)) &
      " expected=\"" & pending.text & "\" serial=" & $pending.focusSerial &
      " currentSerial=" & $currentFocusSerial &
      " keyTimestamp=" & $pending.keyTimestamp &
      " textTimestamp=" & $textTimestamp
    )
    return none(NodeId)

  if compositionTarget.isSome and
      inputState.focusedTarget.isSome and
      inputState.focusedTarget.get == compositionTarget.get.target and
      compositionTarget.get.focusSerial == currentFocusSerial and
      ui.isValidTextInputTarget(compositionTarget.get.target):
    let target = compositionTarget.get.target
    ui.traceInput("deliver textInput to composition target " & ui.nodeTraceLabel(some(target)))
    return some(target)

  if inputState.focusedTarget.isSome and
      ui.isValidTextInputTarget(inputState.focusedTarget.get):
    let target = inputState.focusedTarget.get
    ui.traceInput("deliver unreserved textInput to focused target " & ui.nodeTraceLabel(some(target)))
    return some(target)

  ui.traceInput("drop textInput: no matching focused target")
  none(NodeId)

proc emitImageEvents(ui: UiRoot; events: openArray[Sdl3ImageEvent]): bool =
  for event in events:
    case event.kind
    of sieLoadStart:
      if ui.events.emit(event.node, iekLoadStart):
        result = true
    of sieLoad:
      if ui.events.emit(event.node, iekLoad):
        result = true
    of sieError:
      if ui.events.emit(event.node, iekError):
        result = true
    of sieLoadEnd:
      if ui.events.emit(event.node, iekLoadEnd):
        result = true

proc pollDemoEvent(
    app: var Sdl3Renderer;
    queuedEvents: var seq[Sdl3Event];
    event: var Sdl3Event
): bool =
  if queuedEvents.len > 0:
    event = queuedEvents[0]
    queuedEvents.delete(0)
    traceRawEvent("poll queued", event)
    return true
  result = app.pollEvent(event)
  if result:
    traceRawEvent("poll sdl", event)

proc coalescePointerMove(
    app: var Sdl3Renderer;
    queuedEvents: var seq[Sdl3Event];
    event: var Sdl3Event;
    processedEvents: var int
) =
  if event.kind != sekPointerMove:
    return
  var next: Sdl3Event
  while app.pollDemoEvent(queuedEvents, next):
    if next.kind == sekPointerMove:
      event = next
      inc processedEvents
    else:
      queuedEvents.insert(next, 0)
      break

proc coalesceWheel(
    app: var Sdl3Renderer;
    queuedEvents: var seq[Sdl3Event];
    event: var Sdl3Event;
    processedEvents: var int
) =
  if event.kind != sekWheel:
    return
  var next: Sdl3Event
  while processedEvents < maxWheelEventsPerFrame and
      app.pollDemoEvent(queuedEvents, next):
    if next.kind == sekWheel:
      event.wheelX += next.wheelX
      event.wheelY += next.wheelY
      event.wheelMouseX = next.wheelMouseX
      event.wheelMouseY = next.wheelMouseY
      event.timestamp = next.timestamp
      inc processedEvents
    else:
      queuedEvents.insert(next, 0)
      break

proc coalesceTextEditKeyRepeat(
    app: var Sdl3Renderer;
    queuedEvents: var seq[Sdl3Event];
    event: var Sdl3Event;
    processedEvents: var int
) =
  if event.kind != sekKeyDown or not event.repeat or not event.key.isTextEditRepeatKey:
    return
  var next: Sdl3Event
  while app.pollDemoEvent(queuedEvents, next):
    if next.kind == sekKeyDown and next.repeat and next.key == event.key:
      event = next
      inc processedEvents
    else:
      queuedEvents.insert(next, 0)
      break

proc discardQueuedTextControlEventsForFocusMove(
    app: var Sdl3Renderer;
    queuedEvents: var seq[Sdl3Event]
): tuple[
    count: int;
    sawKeyUp: bool;
    keyDownCount: int;
    keyUpCount: int;
    textInputCount: int;
    compositionCount: int
  ] =
  var kept: seq[Sdl3Event] = @[]
  var next: Sdl3Event
  while app.pollDemoEvent(queuedEvents, next):
    if next.isQueuedTextControlEvent:
      inc result.count
      traceRawEvent("discard focus-move", next)
      case next.kind
      of sekKeyDown:
        inc result.keyDownCount
      of sekKeyUp:
        inc result.keyUpCount
        result.sawKeyUp = true
      of sekTextInput:
        inc result.textInputCount
      of sekCompositionStart, sekCompositionUpdate, sekCompositionEnd, sekCompositionCandidates:
        inc result.compositionCount
      else:
        discard
    else:
      kept.add next
  queuedEvents = kept

proc discardTrace(discarded: tuple[
    count: int;
    sawKeyUp: bool;
    keyDownCount: int;
    keyUpCount: int;
    textInputCount: int;
    compositionCount: int
  ]): string =
  "count=" & $discarded.count &
    " keyDown=" & $discarded.keyDownCount &
    " keyUp=" & $discarded.keyUpCount &
    " textInput=" & $discarded.textInputCount &
    " composition=" & $discarded.compositionCount &
    " sawKeyUp=" & $discarded.sawKeyUp

proc main() =
  var demo = initStateRuntime(DemoState(
    runClicks: 0,
    selectedTab: "info",
    altSelectedTab: "info",
    heroInput: "",
    catalogInput: "Editable",
    catalogTextarea: "Line one\nLine two",
    formName: "Ada",
    fieldsetInput: "Disabled"
  ), updateDemo)
  let viewRefs = DemoViewRefs(statusText: none(NodeId))
  var ui: UiRoot
  proc handleRun() =
    inc demo.state.runClicks
    ui.syncStatusText(viewRefs, demo.state)

  var appClipboard = ""
  var pendingSystemClipboard = none(string)
  proc readClipboard(): string =
    if appClipboard.len == 0:
      when defined(cbssTracePerf):
        echo "[perf-detail] clipboard read begin"
        flushFile(stdout)
      appClipboard = clipboardText(maxDemoClipboardBytes)
      when defined(cbssTracePerf):
        echo "[perf-detail] clipboard read end bytes=", appClipboard.len
        flushFile(stdout)
    appClipboard
  proc writeClipboard(text: string) =
    appClipboard = text.truncateUtf8ForDemo(maxDemoClipboardBytes)
    pendingSystemClipboard = some(appClipboard)
    when defined(cbssTracePerf):
      echo "[perf-detail] clipboard write queued bytes=", appClipboard.len
      flushFile(stdout)

  ui = makeUi(demo.state, demo.dispatcher(), demo.silentDispatcher(), viewRefs, handleRun, readClipboard, writeClipboard)
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  let textEngine = cosmic.textEngine()
  ui.configureTextLayout(textEngine, fonts)
  var app = initSdl3Renderer("Clay Board Style System - SDL3", 1200, 980)
  var viewport = app.windowSize()
  var frame = buildFrame(ui, viewport, textEngine, fonts)
  var inputState = initInteractionState()
  var scheduler = initFrameScheduler()
  var scrollIdleDeadline = none(float64)
  demo.markClean()
  var running = true
  var pendingFrame = false
  var frameDirty = true
  var staticLayerDirty = true
  var layeredTextTarget = none(NodeId)
  var pendingTextInput = none(PendingTextInput)
  var compositionTarget = none(CompositionInput)
  var compositionText = ""
  var caretBlinkVisible = true
  var nextCaretBlinkAt = epochTime() + 0.5
  var caretSolidUntil = 0.0
  var caretBlinkSheetIndex = none(int)
  var lastTextRepeatKey = ""
  var lastTextRepeatTarget = none(NodeId)
  var lastTextRepeatAt = 0.0
  var textFocusChangedAt = 0'u64
  var textFocusDiscardMode = tfdNone
  var textFocusQuietPasses = 0
  var queuedEvents: seq[Sdl3Event] = @[]
  var pendingDemoCapture = false
  let demoCapturePath = "/tmp/cbss_demo_capture.ppm"

  while running:
    if textFocusDiscardMode != tfdNone:
      let discardedTextEvents = app.discardQueuedTextControlEventsForFocusMove(queuedEvents)
      if discardedTextEvents.count > 0:
        ui.traceInput(
          "drain text events after focus change " & discardedTextEvents.discardTrace()
        )
        textFocusQuietPasses = 0
      elif textFocusDiscardMode == tfdUntilTextQuiet:
        inc textFocusQuietPasses
        ui.traceInput(
          "focus-move text stream quiet pass=" & $textFocusQuietPasses
        )
        if textFocusQuietPasses >= 2:
          ui.traceInput("finish focus-move input discard after text stream quiet")
          textFocusDiscardMode = tfdNone
          textFocusQuietPasses = 0
          pendingTextInput = none(PendingTextInput)
          compositionTarget = none(CompositionInput)
          compositionText = ""
          lastTextRepeatKey = ""
          lastTextRepeatTarget = none(NodeId)
          lastTextRepeatAt = 0.0
      if textFocusDiscardMode == tfdUntilKeyUp and discardedTextEvents.sawKeyUp:
        textFocusDiscardMode = tfdNone
        textFocusQuietPasses = 0
        pendingTextInput = none(PendingTextInput)
        compositionTarget = none(CompositionInput)
        compositionText = ""
        lastTextRepeatKey = ""
        lastTextRepeatTarget = none(NodeId)
        lastTextRepeatAt = 0.0
    var event: Sdl3Event
    var needsFrame = pendingFrame
    var paintOnlyDirty = false
    var dirtyStyleRoots: seq[NodeId] = @[]
    var retainedScrollPaintPending = false
    var textScrollPaintTarget = none(NodeId)
    var processedEvents = 0
    pendingFrame = false
    while app.pollDemoEvent(queuedEvents, event):
      inc processedEvents
      app.coalescePointerMove(queuedEvents, event, processedEvents)
      app.coalesceWheel(queuedEvents, event, processedEvents)
      app.coalesceTextEditKeyRepeat(queuedEvents, event, processedEvents)
      if event.isStaleTextControlEvent(textFocusChangedAt):
        ui.traceInput(
          "drop stale text-control event kind=" & $event.kind &
          " timestamp=" & $event.timestamp &
          " focusChangedAt=" & $textFocusChangedAt
        )
        continue
      case event.kind
      of sekQuit:
        running = false
      of sekExpose:
        frameDirty = true
      of sekResize:
        let nextViewport = size(event.width.float32, event.height.float32)
        if abs(nextViewport.w - viewport.w) > 0.5'f32 or abs(nextViewport.h - viewport.h) > 0.5'f32:
          viewport = nextViewport
          if ui.tree.root.isSome:
            discard ui.events.emit(ui.tree, ui.tree.root.get, InputEvent(kind: iekResize))
          needsFrame = true
      of sekFocus:
        staticLayerDirty = true
        if ui.tree.root.isSome:
          discard ui.events.emit(ui.tree, ui.tree.root.get, InputEvent(kind: iekFocus))
        # A different application may have changed the system clipboard while
        # this window was inactive. The next paste will take one fresh snapshot.
        appClipboard = ""
        ui.invalidateClipboardText()
        paintOnlyDirty = true
      of sekBlur:
        staticLayerDirty = true
        if ui.tree.root.isSome:
          discard ui.events.emit(ui.tree, ui.tree.root.get, InputEvent(kind: iekBlur))
        pendingTextInput = none(PendingTextInput)
        compositionTarget = none(CompositionInput)
        compositionText = ""
        lastTextRepeatKey = ""
        lastTextRepeatTarget = none(NodeId)
        lastTextRepeatAt = 0.0
        paintOnlyDirty = true
      of sekPointerMove:
        let point = vec2(event.x, event.y)
        app.setCursor(ui.cursorForPoint(frame.regions, point))
        let previousHover = inputState.hoveredTarget
        let dragging = inputState.pressedTarget.isSome
        let scrollbarPointer = inputState.scrollbarPointerTarget.isSome
        let scrollRevision = ui.scroll.revision
        var dispatches = inputState.processInput(
          ui.tree, frame.regions,
          pointerMoveEvent(point, event.pointer, event.timestamp), ui.scroll
        )
        ui.normalizeTextControlDispatches(frame.regions, dispatches)
        discard ui.events.handle(ui.tree, dispatches)
        if ui.scroll.revision != scrollRevision:
          retainedScrollPaintPending = true
          frameDirty = true
        if not scrollbarPointer:
          if previousHover != inputState.hoveredTarget:
            dirtyStyleRoots.addDirtyRoot(previousHover)
            dirtyStyleRoots.addDirtyRoot(inputState.hoveredTarget)
            staticLayerDirty = true
          if dragging:
            dirtyStyleRoots.addDirtyRoot(inputState.pressedTarget)
            if ui.inputTargetForHit(inputState.pressedTarget).isNone:
              staticLayerDirty = true
          if dragging and ui.isLayoutChangingDrag(inputState):
            needsFrame = true
          elif dragging or previousHover != inputState.hoveredTarget:
            paintOnlyDirty = true
      of sekPointerDown:
        let point = vec2(event.buttonX, event.buttonY)
        if ui.defaultContextMenuOpen and event.button != 3:
          if ui.containsDefaultContextMenuPoint(point):
            discard ui.activateDefaultContextMenuAt(point)
            needsFrame = true
            continue
          elif ui.closeDefaultContextMenu():
            needsFrame = true
        let hit = hitTest(frame.regions, point)
        let scrollbarHit = hit.isSome and hit.get.kind.isScrollbar
        let hitTarget =
          if hit.isSome: some(hit.get.node)
          else: none(NodeId)
        if ui.closeOpenPopups(hitTarget):
          needsFrame = true
          continue
        if ui.isContextMenuHit(hitTarget):
          discard ui.events.handle(ui.tree, DispatchResult(
            target: hitTarget,
            local:
              if hit.isSome: some(hit.get.local)
              else: none(Vec2),
            event: pointerDownEvent(
              point, event.button, event.pointer, event.timestamp
            )
          ))
          needsFrame = true
          continue
        if event.button == 3 and not ui.isContextMenuHit(hitTarget):
          needsFrame = true
          continue
        if scrollbarHit:
          let scrollRevision = ui.scroll.revision
          var dispatches = inputState.processInput(
            ui.tree, frame.regions,
            pointerDownEvent(
              point, event.button, event.pointer, event.timestamp
            ), ui.scroll
          )
          discard ui.events.handle(ui.tree, dispatches)
          if ui.scroll.revision != scrollRevision:
            retainedScrollPaintPending = true
            frameDirty = true
          continue
        staticLayerDirty = true
        let previousFocusedTarget = inputState.focusedTarget
        dirtyStyleRoots.addDirtyRoot(hitTarget)
        dirtyStyleRoots.addDirtyRoot(previousFocusedTarget)
        ui.traceInput(
          "pointerDown hit=" & ui.nodeTraceLabel(hitTarget) &
          " previousFocus=" & ui.nodeTraceLabel(previousFocusedTarget)
        )
        let textHit = ui.textControlHitAtPoint(frame.regions, point)
        let normalizedHitTarget =
          if textHit.isSome: some(textHit.get.node)
          else: hitTarget
        var dispatches = inputState.processInput(
          ui.tree, frame.regions,
          pointerDownEvent(
            point, event.button, event.pointer, event.timestamp
          ), ui.scroll
        )
        ui.normalizeTextControlDispatches(frame.regions, dispatches)
        discard ui.events.handle(ui.tree, dispatches)
        ui.normalizeTextControlFocus(inputState, normalizedHitTarget)
        dirtyStyleRoots.addDirtyRoot(inputState.focusedTarget)
        if textHit.isSome:
          inputState.pressedTarget = some(textHit.get.node)
        if previousFocusedTarget != inputState.focusedTarget:
          textFocusChangedAt = event.timestamp
          textFocusDiscardMode = tfdUntilPointerUp
          textFocusQuietPasses = 0
          discard app.interruptTextInput()
          let discardedTextEvents = app.discardQueuedTextControlEventsForFocusMove(queuedEvents)
          ui.traceInput(
            "focus changed " & ui.nodeTraceLabel(previousFocusedTarget) &
            " -> " & ui.nodeTraceLabel(inputState.focusedTarget) &
            "; focusSerial=" & $inputState.focusSerial &
            " eventTimestamp=" & $event.timestamp &
            "; clear pending/composition; discardedTextEvents=" &
            discardedTextEvents.discardTrace()
          )
          pendingTextInput = none(PendingTextInput)
          compositionTarget = none(CompositionInput)
          compositionText = ""
          lastTextRepeatKey = ""
          lastTextRepeatTarget = none(NodeId)
          lastTextRepeatAt = 0.0
          caretBlinkVisible = true
          nextCaretBlinkAt = epochTime() + 0.5
          if inputState.focusedTarget.isSome:
            discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
          else:
            ui.clearCaretBlinkSheet(caretBlinkSheetIndex)
          paintOnlyDirty = true
        elif inputState.focusedTarget.isSome and ui.inputTargetForHit(normalizedHitTarget).isSome:
          caretBlinkVisible = true
          nextCaretBlinkAt = epochTime() + 0.5
          discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
          paintOnlyDirty = true
        if ui.isLayoutChangingInteractionHit(normalizedHitTarget):
          needsFrame = true
        else:
          paintOnlyDirty = true
      of sekPointerUp:
        let point = vec2(event.buttonX, event.buttonY)
        let previousPressedTarget = inputState.pressedTarget
        let scrollbarPointer = inputState.scrollbarPointerTarget.isSome
        if textFocusDiscardMode == tfdUntilPointerUp:
          discard app.interruptTextInput()
          let discardedTextEvents = app.discardQueuedTextControlEventsForFocusMove(queuedEvents)
          ui.traceInput(
            "finish focus-move input discard on pointerUp; discardedTextEvents=" &
            discardedTextEvents.discardTrace()
          )
          pendingTextInput = none(PendingTextInput)
          compositionTarget = none(CompositionInput)
          compositionText = ""
          lastTextRepeatKey = ""
          lastTextRepeatTarget = none(NodeId)
          lastTextRepeatAt = 0.0
          textFocusDiscardMode = tfdNone
          textFocusQuietPasses = 0
        if ui.defaultContextMenuOpen and event.button != 3 and ui.containsDefaultContextMenuPoint(point):
          needsFrame = true
          continue
        let hit = hitTest(frame.regions, point)
        let hitTarget =
          if hit.isSome: some(hit.get.node)
          else: none(NodeId)
        if ui.isContextMenuHit(hitTarget):
          discard ui.events.handle(ui.tree, DispatchResult(
            target: hitTarget,
            local:
              if hit.isSome: some(hit.get.local)
              else: none(Vec2),
            event: pointerUpEvent(
              point, event.button, event.pointer, event.timestamp
            )
          ))
          needsFrame = true
          continue
        if event.button == 3 and not ui.isContextMenuHit(hitTarget):
          let textHit = ui.textControlHitAtPoint(frame.regions, point)
          let menuTarget =
            if textHit.isSome: some(textHit.get.node)
            elif ui.inputTargetForHit(hitTarget).isSome: ui.inputTargetForHit(hitTarget)
            else: hitTarget
          if ui.showDefaultContextMenu(menuTarget, point):
            needsFrame = true
          continue
        var dispatches = inputState.processInput(
          ui.tree, frame.regions,
          pointerUpEvent(
            point, event.button, event.pointer, event.timestamp
          ), ui.scroll
        )
        ui.normalizeTextControlDispatches(frame.regions, dispatches)
        discard ui.events.handle(ui.tree, dispatches)
        if scrollbarPointer:
          continue
        staticLayerDirty = true
        dirtyStyleRoots.addDirtyRoot(previousPressedTarget)
        dirtyStyleRoots.addDirtyRoot(hitTarget)
        if ui.isLayoutChangingInteractionHit(hitTarget) or ui.isLayoutChangingDrag(inputState):
          needsFrame = true
        else:
          paintOnlyDirty = true
      of sekKeyDown:
        if inputState.focusedTarget.isNone or
            not ui.isTextInputTarget(inputState.focusedTarget.get):
          staticLayerDirty = true
        var handledTextControlKey = false
        if event.key == "F12" and not event.ctrl and not event.alt and not event.meta:
          app.requestFrameCapture()
          pendingDemoCapture = true
          frameDirty = true
          handledTextControlKey = true
          echo "CBSS demo capture requested: " & demoCapturePath
        if event.key == "Tab" and not event.ctrl and not event.alt and not event.meta:
          pendingTextInput = none(PendingTextInput)
          compositionTarget = none(CompositionInput)
          compositionText = ""
          lastTextRepeatKey = ""
          lastTextRepeatTarget = none(NodeId)
          lastTextRepeatAt = 0.0
          if ui.moveTextControlFocus(inputState, if event.shift: -1 else: 1):
            textFocusChangedAt = event.timestamp
            textFocusDiscardMode = tfdUntilKeyUp
            textFocusQuietPasses = 0
            discard app.interruptTextInput()
            let discardedTextEvents = app.discardQueuedTextControlEventsForFocusMove(queuedEvents)
            if discardedTextEvents.sawKeyUp:
              textFocusDiscardMode = tfdNone
              textFocusQuietPasses = 0
            ui.traceInput(
              "tab focus changed; clear pending/composition; discardedTextEvents=" &
              discardedTextEvents.discardTrace() &
              " focusSerial=" & $inputState.focusSerial &
              " eventTimestamp=" & $event.timestamp
            )
            handledTextControlKey = true
            caretBlinkVisible = true
            caretSolidUntil = epochTime() + 0.35
            nextCaretBlinkAt = caretSolidUntil + 0.5
            discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
            paintOnlyDirty = true
        if not handledTextControlKey and inputState.focusedTarget.isSome:
          let focused = inputState.focusedTarget.get
          let textInputFocused = ui.isTextInputTarget(focused)
          if textInputFocused:
            if textFocusDiscardMode != tfdNone:
              ui.traceInput(
                "drop keyDown after focus move key=\"" & event.key &
                "\" focus=" & ui.nodeTraceLabel(some(focused)) &
                " focusSerial=" & $inputState.focusSerial &
                " eventTimestamp=" & $event.timestamp
              )
              pendingTextInput = none(PendingTextInput)
              compositionTarget = none(CompositionInput)
              compositionText = ""
              continue
            if event.isStaleAfterTextFocusChange(textFocusChangedAt):
              ui.traceInput(
                "drop stale keyDown after focus change key=\"" & event.key &
                "\" focus=" & ui.nodeTraceLabel(some(focused)) &
                " focusSerial=" & $inputState.focusSerial &
                " eventTimestamp=" & $event.timestamp &
                " focusChangedAt=" & $textFocusChangedAt
              )
              continue
            ui.traceInput(
              "keyDown key=\"" & event.key & "\" focus=" &
              ui.nodeTraceLabel(some(focused)) &
              " focusSerial=" & $inputState.focusSerial &
              " eventTimestamp=" & $event.timestamp &
              " printable=" & $isPrintableTextKey(event.key, event.ctrl, event.alt, event.meta) &
              " pendingBefore=" & ui.pendingTrace(pendingTextInput)
            )
            if event.key == "Backspace" or isPrintableTextKey(event.key, event.ctrl, event.alt, event.meta):
              ui.traceBackspace(
                "keyDown key=\"" & event.key &
                "\" repeat=" & $event.repeat &
                " focus=" & ui.nodeTraceLabel(some(focused)) &
                " serial=" & $inputState.focusSerial &
                " composition=" & ui.compositionTrace(compositionTarget) &
                " compositionBytes=" & $compositionText.len &
                " pending=" & ui.pendingTrace(pendingTextInput)
              )
            let repeatNow = epochTime()
            let shouldLimitRepeat = event.repeat or event.key.isTextEditRepeatKey
            if shouldLimitRepeat and
                lastTextRepeatKey == event.key and
                lastTextRepeatTarget == some(focused) and
                repeatNow - lastTextRepeatAt < 0.045:
              continue
            lastTextRepeatKey = event.key
            lastTextRepeatTarget = some(focused)
            lastTextRepeatAt = repeatNow
          if event.ctrl or event.meta:
            if textInputFocused:
              handledTextControlKey = true
              pendingTextInput = none(PendingTextInput)
              compositionTarget = none(CompositionInput)
              compositionText = ""
              let changed =
                case event.key.toLowerAscii()
                of "c":
                  ui.emitTextControlEvent(focused, copyEvent())
                of "x":
                  let didChange = ui.emitTextControlEvent(focused, cutEvent())
                  if didChange:
                    discard app.clearTextComposition()
                    app.discardPendingTextInputEvents()
                  didChange
                of "v":
                  # The clipboard edit starts a new text transaction. Keep the
                  # SDL composition tracker aligned with the local target so
                  # the next preedit is emitted as CompositionStart.
                  discard app.clearTextComposition()
                  app.discardPendingTextInputEvents()
                  ui.emitTextControlEvent(focused, pasteEvent(ui.clipboardText()))
                else:
                  ui.emitTextControlEvent(focused, keyDownEvent(
                    event.key,
                    ctrlKey = event.ctrl,
                    altKey = event.alt,
                    shiftKey = event.shift,
                    metaKey = event.meta
                  ))
              if changed and event.key.toLowerAscii() in ["x", "backspace", "delete"]:
                discard app.clearTextComposition()
                app.discardPendingTextInputEvents()
                pendingTextInput = none(PendingTextInput)
                compositionTarget = none(CompositionInput)
                compositionText = ""
              paintOnlyDirty = paintOnlyDirty or changed or event.key.toLowerAscii() in ["a", "x", "v", "z", "y", "arrowleft", "arrowright", "home", "end"]
              caretBlinkVisible = true
              caretSolidUntil = epochTime() + 0.35
              nextCaretBlinkAt = caretSolidUntil + 0.5
              discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
            else:
              case event.key.toLowerAscii()
              of "c":
                discard ui.events.emitFocused(inputState, copyEvent())
              of "x":
                discard ui.events.emitFocused(inputState, cutEvent())
              of "v":
                discard ui.events.emitFocused(inputState, pasteEvent(ui.clipboardText()))
              else:
                discard ui.events.emit(ui.tree, focused, keyDownEvent(
                  event.key,
                  ctrlKey = event.ctrl,
                  altKey = event.alt,
                  shiftKey = event.shift,
                  metaKey = event.meta
                ))
          else:
            if textInputFocused:
              handledTextControlKey = true
              let printableText = printableTextFromKey(event.key, event.ctrl, event.alt, event.meta)
              if printableText.isSome:
                if compositionTarget.isSome and compositionText.len > 0:
                  ui.traceBackspace(
                    "printable during composition key=\"" & event.key &
                    "\" compositionBytes=" & $compositionText.len &
                    " target=" & ui.compositionTrace(compositionTarget)
                  )
                  pendingTextInput = none(PendingTextInput)
                  caretBlinkVisible = true
                  caretSolidUntil = epochTime() + 0.35
                  nextCaretBlinkAt = caretSolidUntil + 0.5
                  discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
                  paintOnlyDirty = true
                  continue
                pendingTextInput = some(PendingTextInput(
                  target: focused,
                  text: printableText.get,
                  focusSerial: inputState.focusSerial,
                  keyTimestamp: event.timestamp
                ))
                ui.traceInput(
                  "queued printable key target=" & ui.nodeTraceLabel(some(focused)) &
                  " focusSerial=" & $inputState.focusSerial &
                  " keyTimestamp=" & $event.timestamp &
                  " pendingAfter=" & ui.pendingTrace(pendingTextInput)
                )
                caretBlinkVisible = true
                caretSolidUntil = epochTime() + 0.35
                nextCaretBlinkAt = caretSolidUntil + 0.5
              else:
                pendingTextInput = none(PendingTextInput)
                if event.key == "Backspace":
                  ui.traceBackspace(
                    "dispatch backspace to runtime compositionBeforeClear=" &
                    ui.compositionTrace(compositionTarget) &
                    " compositionBytes=" & $compositionText.len
                  )
                let hadCompositionTarget = compositionTarget.isSome
                let hadVisibleComposition = compositionText.len > 0
                let changed = ui.emitTextControlEvent(focused, keyDownEvent(
                  event.key,
                  ctrlKey = event.ctrl,
                  altKey = event.alt,
                  shiftKey = event.shift,
                  metaKey = event.meta
                ))
                if event.key == "Backspace" and hadVisibleComposition:
                  discard compositionText.deleteLastUtf8Rune()
                elif event.key == "Delete" and hadVisibleComposition:
                  compositionText = ""
                elif hadCompositionTarget and not hadVisibleComposition and event.key.isTextEditRepeatKey:
                  discard app.clearTextComposition()
                  ui.traceBackspace(
                    "clear SDL composition after empty edit key=\"" & event.key & "\""
                  )
                  compositionTarget = none(CompositionInput)
                  compositionText = ""
                elif not event.key.isTextEditRepeatKey:
                  compositionTarget = none(CompositionInput)
                  compositionText = ""
                paintOnlyDirty = paintOnlyDirty or changed
                if changed and event.key in ["Backspace", "Delete"]:
                  discard app.clearTextComposition()
                  app.discardPendingTextInputEvents()
                  pendingTextInput = none(PendingTextInput)
                  compositionTarget = none(CompositionInput)
                  compositionText = ""
                if changed:
                  caretBlinkVisible = true
                  caretSolidUntil = epochTime() + 0.35
                  nextCaretBlinkAt = caretSolidUntil + 0.5
                  discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
            else:
              discard ui.events.emit(ui.tree, focused, keyDownEvent(
                event.key,
                ctrlKey = event.ctrl,
                altKey = event.alt,
                shiftKey = event.shift,
                metaKey = event.meta
              ))
        if not handledTextControlKey:
          paintOnlyDirty = true
      of sekKeyUp:
        if inputState.focusedTarget.isNone or
            not ui.isTextInputTarget(inputState.focusedTarget.get):
          staticLayerDirty = true
        if inputState.focusedTarget.isSome:
          let focused = inputState.focusedTarget.get
          if ui.isTextInputTarget(focused) and textFocusDiscardMode == tfdUntilKeyUp:
            textFocusDiscardMode = tfdNone
            pendingTextInput = none(PendingTextInput)
            compositionTarget = none(CompositionInput)
            compositionText = ""
            lastTextRepeatKey = ""
            lastTextRepeatTarget = none(NodeId)
            lastTextRepeatAt = 0.0
            continue
          discard ui.events.emit(ui.tree, focused, keyUpEvent(
            event.key,
            ctrlKey = event.ctrl,
            altKey = event.alt,
            shiftKey = event.shift,
            metaKey = event.meta
          ))
          if event.key == lastTextRepeatKey:
            lastTextRepeatKey = ""
            lastTextRepeatTarget = none(NodeId)
            lastTextRepeatAt = 0.0
          paintOnlyDirty = true
        else:
          paintOnlyDirty = true
      of sekCompositionStart:
        if textFocusDiscardMode != tfdNone:
          continue
        if event.isStaleAfterTextFocusChange(textFocusChangedAt):
          ui.traceInput(
            "drop stale compositionStart after focus change text=\"" & event.text & "\""
          )
          continue
        pendingTextInput = none(PendingTextInput)
        compositionText = event.text
        let target =
          if inputState.focusedTarget.isSome and ui.isValidTextInputTarget(inputState.focusedTarget.get):
            inputState.focusedTarget
          else:
            none(NodeId)
        compositionTarget =
          if target.isSome:
            some(CompositionInput(target: target.get, focusSerial: inputState.focusSerial))
          else:
            none(CompositionInput)
        ui.traceInput(
          "compositionStart text=\"" & event.text & "\" target=" &
          ui.nodeTraceLabel(target)
        )
        ui.traceBackspace(
          "compositionStart bytes=" & $event.text.len &
          " target=" & ui.nodeTraceLabel(target) &
          " serial=" & $inputState.focusSerial
        )
        if target.isSome:
          let changed = ui.emitTextControlEvent(target.get, compositionStartEvent(event.text))
          paintOnlyDirty = paintOnlyDirty or changed
          if changed:
            caretBlinkVisible = true
            caretSolidUntil = epochTime() + 0.35
            nextCaretBlinkAt = caretSolidUntil + 0.5
            discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
        paintOnlyDirty = true
      of sekCompositionUpdate:
        if textFocusDiscardMode != tfdNone:
          continue
        if event.isStaleAfterTextFocusChange(textFocusChangedAt):
          ui.traceInput(
            "drop stale compositionUpdate after focus change text=\"" & event.text & "\""
          )
          continue
        pendingTextInput = none(PendingTextInput)
        compositionText = event.text
        let target =
          if compositionTarget.isSome and
              inputState.focusedTarget.isSome and
              inputState.focusedTarget.get == compositionTarget.get.target and
              compositionTarget.get.focusSerial == inputState.focusSerial and
              ui.isValidTextInputTarget(compositionTarget.get.target):
            some(compositionTarget.get.target)
          else:
            none(NodeId)
        if target.isSome:
          ui.traceInput(
            "compositionUpdate text=\"" & event.text & "\" target=" &
            ui.nodeTraceLabel(target)
          )
          ui.traceBackspace(
            "compositionUpdate bytes=" & $event.text.len &
            " target=" & ui.nodeTraceLabel(target) &
            " serial=" & $inputState.focusSerial
          )
          let changed = ui.emitTextControlEvent(target.get, compositionUpdateEvent(event.text))
          ui.traceBackspace(
            "compositionUpdate applied changed=" & $changed &
            " textBytes=" & $event.text.len
          )
          paintOnlyDirty = paintOnlyDirty or changed
          if changed:
            caretBlinkVisible = true
            caretSolidUntil = epochTime() + 0.35
            nextCaretBlinkAt = caretSolidUntil + 0.5
            discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
        paintOnlyDirty = true
      of sekCompositionEnd:
        if textFocusDiscardMode != tfdNone:
          continue
        if event.isStaleAfterTextFocusChange(textFocusChangedAt):
          ui.traceInput(
            "drop stale compositionEnd after focus change text=\"" & event.text & "\""
          )
          continue
        pendingTextInput = none(PendingTextInput)
        compositionText = ""
        let target =
          if compositionTarget.isSome and
              inputState.focusedTarget.isSome and
              inputState.focusedTarget.get == compositionTarget.get.target and
              compositionTarget.get.focusSerial == inputState.focusSerial and
              ui.isValidTextInputTarget(compositionTarget.get.target):
            some(compositionTarget.get.target)
          else:
            none(NodeId)
        if target.isSome:
          ui.traceInput(
            "compositionEnd text=\"" & event.text & "\" target=" &
            ui.nodeTraceLabel(target)
          )
          ui.traceBackspace(
            "compositionEnd bytes=" & $event.text.len &
            " target=" & ui.nodeTraceLabel(target) &
            " serial=" & $inputState.focusSerial
          )
          let changed = ui.emitTextControlEvent(target.get, compositionEndEvent(event.text))
          paintOnlyDirty = paintOnlyDirty or changed
          if changed:
            caretBlinkVisible = true
            caretSolidUntil = epochTime() + 0.35
            nextCaretBlinkAt = caretSolidUntil + 0.5
            discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
        paintOnlyDirty = true
      of sekCompositionCandidates:
        if textFocusDiscardMode != tfdNone:
          continue
        ui.traceInput(
          "compositionCandidates count=" & $event.candidates.len &
          " selected=" & $event.selectedCandidate &
          " horizontal=" & $event.horizontalCandidates &
          " focus=" & ui.nodeTraceLabel(inputState.focusedTarget)
        )
      of sekTextInput:
        if textFocusDiscardMode != tfdNone:
          pendingTextInput = none(PendingTextInput)
          compositionTarget = none(CompositionInput)
          compositionText = ""
          continue
        if event.isStaleAfterTextFocusChange(textFocusChangedAt):
          ui.traceInput(
            "drop stale textInput after focus change text=\"" & event.text & "\""
          )
          continue
        ui.traceInput(
          "SDL textInput text=\"" & event.text & "\" focus=" &
          ui.nodeTraceLabel(inputState.focusedTarget) &
          " focusSerial=" & $inputState.focusSerial &
          " textTimestamp=" & $event.timestamp &
          " pending=" & ui.pendingTrace(pendingTextInput) &
          " composition=" & ui.compositionTrace(compositionTarget)
        )
        ui.traceBackspace(
          "textInput bytes=" & $event.text.len &
          " focus=" & ui.nodeTraceLabel(inputState.focusedTarget) &
          " serial=" & $inputState.focusSerial &
          " composition=" & ui.compositionTrace(compositionTarget) &
          " pending=" & ui.pendingTrace(pendingTextInput)
        )
        let target = ui.textEventTarget(
          inputState,
          pendingTextInput,
          compositionTarget,
          event.text,
          event.timestamp,
          inputState.focusSerial
        )
        if target.isSome:
          let changed = ui.emitTextControlEvent(target.get, textInputEvent(event.text))
          ui.traceInput(
            "applied textInput text=\"" & event.text & "\" target=" &
            ui.nodeTraceLabel(target) & " changed=" & $changed
          )
          paintOnlyDirty = paintOnlyDirty or changed
          if changed:
            caretBlinkVisible = true
            caretSolidUntil = epochTime() + 0.35
            nextCaretBlinkAt = caretSolidUntil + 0.5
            discard ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true)
        compositionTarget = none(CompositionInput)
        compositionText = ""
      of sekWheel:
        let point = vec2(event.wheelMouseX, event.wheelMouseY)
        let textHit = ui.textControlHitAtPoint(frame.regions, point)
        let scrollRevision = ui.scroll.revision
        let wheel = wheelEvent(point, event.scrollDelta())
        let dispatches =
          if textHit.isSome:
            # Textareas own their internal retained offset. Do not apply the
            # same wheel delta to a generic ancestor scroll container too.
            inputState.processInput(ui.tree, frame.regions, wheel)
          else:
            inputState.processInput(ui.tree, frame.regions, wheel, ui.scroll)
        let handled = ui.events.handle(ui.tree, dispatches)
        if ui.scroll.revision != scrollRevision:
          retainedScrollPaintPending = true
          frameDirty = true
        if handled and textHit.isSome:
          inputState.beginScroll(textHit.get.node)
          textScrollPaintTarget = some(textHit.get.node)
          frameDirty = true
        scrollIdleDeadline = some(
          epochTime() + scrollIndicatorIdleDelaySeconds
        )
      of sekTouchStart:
        staticLayerDirty = true
        let input = event.pointerInputEvent()
        if input.isSome:
          let dispatches = inputState.processInput(ui.tree, frame.regions, input.get)
          discard ui.events.handle(ui.tree, dispatches)
        paintOnlyDirty = true
      of sekTouchMove:
        staticLayerDirty = true
        let input = event.pointerInputEvent()
        if input.isSome:
          let dispatches = inputState.processInput(
            ui.tree, frame.regions, input.get
          )
          discard ui.events.handle(ui.tree, dispatches)
        paintOnlyDirty = true
      of sekTouchEnd:
        staticLayerDirty = true
        let input = event.pointerInputEvent()
        if input.isSome:
          let dispatches = inputState.processInput(ui.tree, frame.regions, input.get)
          discard ui.events.handle(ui.tree, dispatches)
        paintOnlyDirty = true
      of sekTouchCancel:
        staticLayerDirty = true
        let input = event.pointerInputEvent()
        if input.isSome:
          let dispatches = inputState.processInput(ui.tree, frame.regions, input.get)
          discard ui.events.handle(ui.tree, dispatches)
        paintOnlyDirty = true
      of sekPenProximityIn, sekPenProximityOut,
         sekPenButtonDown, sekPenButtonUp:
        let input = event.pointerInputEvent()
        if input.isSome:
          let dispatches = inputState.processInput(
            ui.tree, frame.regions, input.get, ui.scroll
          )
          discard ui.events.handle(ui.tree, dispatches)
        paintOnlyDirty = true
      if ui.reconcileFocus(inputState):
        staticLayerDirty = true
        paintOnlyDirty = true
      if shouldYieldForInteractiveFrame(
          event, needsFrame, paintOnlyDirty, frameDirty, processedEvents
      ):
        break
    if retainedScrollPaintPending:
      if inputState.scrollTarget.isSome:
        let target = inputState.scrollTarget.get
        if frame.scrollDynamicTarget != inputState.scrollTarget:
          if frame.scrollDynamicTarget.isSome:
            finishScrollFrame(ui, frame)
          staticLayerDirty = true
        repaintScrollFrame(ui, frame, target)
        frameDirty = true
    if textScrollPaintTarget.isSome:
      let target = textScrollPaintTarget.get
      if inputState.focusedTarget.isSome and inputState.focusedTarget.get == target:
        repaintTextControlFrame(ui, frame, target, textEngine, fonts)
      else:
        repaintDirtySubtrees(ui, frame, [target], textEngine, fonts)
        staticLayerDirty = true
      frameDirty = true
    if scrollIdleDeadline.isSome and epochTime() >= scrollIdleDeadline.get:
      let scrollRevision = ui.scroll.revision
      let scrollEndDispatches = inputState.finishScroll(ui.scroll)
      if scrollEndDispatches.len > 0:
        discard ui.events.handle(ui.tree, scrollEndDispatches)
      if ui.scroll.revision != scrollRevision:
        finishScrollFrame(ui, frame)
        staticLayerDirty = true
        frameDirty = true
      scrollIdleDeadline = none(float64)

    if inputState.focusedTarget.isSome and ui.isTextInputTarget(inputState.focusedTarget.get):
      let now = epochTime()
      if now < caretSolidUntil:
        caretBlinkVisible = true
        if ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, true):
          paintOnlyDirty = true
        nextCaretBlinkAt = caretSolidUntil + 0.5
      elif now >= nextCaretBlinkAt:
        caretBlinkVisible = not caretBlinkVisible
        if ui.setCaretBlinkVisible(inputState, caretBlinkSheetIndex, caretBlinkVisible):
          paintOnlyDirty = true
        nextCaretBlinkAt = now + 0.5
    else:
      caretBlinkVisible = true
      caretSolidUntil = 0.0
      ui.clearCaretBlinkSheet(caretBlinkSheetIndex)

    let demoDirty = demo.consumeDirty()
    if demoDirty:
      scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})
    elif needsFrame:
      scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})
    elif paintOnlyDirty:
      scheduler.markDirty(ddPaint)
    let dirtyDomains = scheduler.consumeDirty()

    if demoDirty:
      ui = makeUi(demo.state, demo.dispatcher(), demo.silentDispatcher(), viewRefs, handleRun, readClipboard, writeClipboard)
      ui.configureTextLayout(textEngine, fonts)
      caretBlinkSheetIndex = none(int)
      let frameStart = epochTime()
      frame = buildFrame(ui, viewport, textEngine, fonts)
      ui.tracePerf(
        "buildFrame demoDirty ms=" & elapsedMs(frameStart) &
        " styles=" & $ui.componentStyles.len &
        " commands=" & $frame.commands.len &
        " regions=" & $frame.regions.len
      )
      frameDirty = true
      staticLayerDirty = true
    elif ({ddStyle, ddLayout, ddHit, ddResource} * dirtyDomains) != {}:
      let frameStart = epochTime()
      frame = buildFrame(ui, viewport, textEngine, fonts)
      ui.tracePerf(
        "buildFrame needsFrame ms=" & elapsedMs(frameStart) &
        " styles=" & $ui.componentStyles.len &
        " commands=" & $frame.commands.len &
        " regions=" & $frame.regions.len
      )
      frameDirty = true
      staticLayerDirty = true
    elif dirtyDomains != {}:
      let frameStart = epochTime()
      if dirtyStyleRoots.len > 0:
        repaintDirtySubtrees(ui, frame, dirtyStyleRoots, textEngine, fonts)
      elif not staticLayerDirty and
          inputState.focusedTarget.isSome and
          ui.isTextInputTarget(inputState.focusedTarget.get):
        repaintTextControlFrame(ui, frame, inputState.focusedTarget.get, textEngine, fonts)
      else:
        repaintFrame(ui, frame)
      ui.tracePerf(
        "repaintFrame paintOnly ms=" & elapsedMs(frameStart) &
        " styles=" & $ui.componentStyles.len &
        " commands=" & $frame.commands.len &
        " regions=" & $frame.regions.len
      )
      frameDirty = true
    app.syncTextInputArea(ui, frame, inputState)

    if frameDirty:
      let dynamicTarget =
        if inputState.focusedTarget.isSome and
            ui.isTextInputTarget(inputState.focusedTarget.get):
          inputState.focusedTarget
        else:
          none(NodeId)
      if dynamicTarget != layeredTextTarget:
        staticLayerDirty = true
        layeredTextTarget = dynamicTarget
      let scrollDynamicNodes =
        if frame.scrollDynamicTarget.isSome:
          ui.subtreeNodes(frame.scrollDynamicTarget.get)
        else:
          newSeq[NodeId]()
      let textCoveredByScroll =
        dynamicTarget.isSome and scrollDynamicNodes.containsNode(dynamicTarget.get)
      var dynamicNodes = scrollDynamicNodes
      if dynamicTarget.isSome and not textCoveredByScroll:
        dynamicNodes.add ui.textControlDynamicNodes(dynamicTarget.get)
      # Focused text controls are excluded from the retained static texture.
      # Paint-only paths may clear their cached commands, so restore the whole
      # control subtree before compositing instead of allowing a blank frame.
      if dynamicTarget.isSome and not textCoveredByScroll and
          frame.dynamicCommands.len == 0:
        frame.dynamicCommands = buildPaintCommandsForSubtree(
          ui.tree,
          frame.styles,
          frame.layout,
          dynamicTarget.get,
          ui.scroll
        )
      var dynamicCommands = newSeqOfCap[PaintCommand](
        frame.dynamicCommands.len + frame.scrollDynamicCommands.len
      )
      if not textCoveredByScroll:
        dynamicCommands.add frame.dynamicCommands
      dynamicCommands.add frame.scrollDynamicCommands
      let renderStart = epochTime()
      when defined(cbssTracePerf):
        echo "[perf-detail] render begin static=", staticLayerDirty,
          " dynamicNodes=", dynamicNodes.len,
          " commands=", frame.commands.len
        flushFile(stdout)
      app.renderLayered(
        frame.commands,
        cosmic,
        fonts,
        rgb(0.95, 0.95, 0.95),
        rebuildStatic = staticLayerDirty,
        dynamicNodes = dynamicNodes,
        dynamicCommands = dynamicCommands
      )
      ui.tracePerf(
        "render ms=" & elapsedMs(renderStart) &
        " commands=" & $frame.commands.len &
        " focus=" & ui.nodeTraceLabel(inputState.focusedTarget)
      )
      if pendingDemoCapture:
        let captured = app.capturedFrame()
        if captured.isSome:
          writeCapturedFramePpm(demoCapturePath, captured.get)
          echo "CBSS demo capture saved: " & demoCapturePath
        else:
          echo "CBSS demo capture failed: no captured frame"
        pendingDemoCapture = false
      frameDirty = false
      staticLayerDirty = false
      discard emitImageEvents(ui, app.takeImageEvents())
    if pendingSystemClipboard.isSome:
      # SDL's Wayland clipboard bridge can synchronously communicate with the
      # compositor. Coalesce writes and keep them outside event dispatch.
      when defined(cbssTracePerf):
        echo "[perf-detail] clipboard platform write begin bytes=", pendingSystemClipboard.get.len
        flushFile(stdout)
      discard setClipboardText(pendingSystemClipboard.get)
      when defined(cbssTracePerf):
        echo "[perf-detail] clipboard platform write end"
        flushFile(stdout)
      pendingSystemClipboard = none(string)
    scheduler.clearDeadline()
    let idleNow = epochTime()
    if scrollIdleDeadline.isSome:
      scheduler.requestDeadline(scrollIdleDeadline.get)
    if inputState.focusedTarget.isSome and
        ui.isTextInputTarget(inputState.focusedTarget.get):
      if idleNow < caretSolidUntil:
        scheduler.requestDeadline(caretSolidUntil)
      else:
        scheduler.requestDeadline(nextCaretBlinkAt)
    if textFocusDiscardMode != tfdNone:
      scheduler.requestDeadline(idleNow + 0.001)

    if running and queuedEvents.len == 0 and not frameDirty and not pendingFrame:
      var waitedEvent: Sdl3Event
      let timeoutMs = scheduler.waitTimeoutMs(idleNow)
      let received =
        if timeoutMs < 0:
          app.waitEvent(waitedEvent)
        else:
          app.waitEventTimeout(waitedEvent, timeoutMs)
      if received:
        queuedEvents.add waitedEvent

  app.close()
  cosmic.close()

when isMainModule:
  main()
