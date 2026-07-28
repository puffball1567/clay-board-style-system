import ../core/node
import ../input/events
import ./ui_root

type
  FieldsetParams* = object
    legend*: string
    disabled*: bool

  FieldsetState* = ref object
    legend*: string
    disabled*: bool
    disabledTargets*: seq[DisabledSetter]

  FieldsetHandle* = object
    root*: UiRoot
    container*: NodeHandle
    legendNode*: NodeHandle
    state*: FieldsetState

proc legend*(fieldset: FieldsetHandle): string =
  fieldset.state.legend

proc disabled*(fieldset: FieldsetHandle): bool =
  fieldset.state.disabled

proc setLegend*(fieldset: FieldsetHandle; legend: string) =
  fieldset.state.legend = legend
  fieldset.root.tree.nodes[fieldset.legendNode.id.nodeIndex].text = legend

proc addDisabledTarget*(fieldset: FieldsetHandle; setter: DisabledSetter) =
  fieldset.state.disabledTargets.add setter
  if fieldset.state.disabled:
    setter(true)

proc setDisabled*(fieldset: FieldsetHandle; disabled: bool) =
  fieldset.state.disabled = disabled
  fieldset.container.setState(esDisabled, disabled)
  for setter in fieldset.state.disabledTargets:
    setter(disabled)

proc `onChange=`*(fieldset: FieldsetHandle; handler: EventHandler) =
  fieldset.container.onChange = handler

proc fieldset*(
    root: UiRoot;
    params: FieldsetParams;
    style = UiStyle();
    legendStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["fieldset"]
): FieldsetHandle {.discardable.} =
  result.root = root
  result.state = FieldsetState(
    legend: params.legend,
    disabled: params.disabled,
    disabledTargets: @[]
  )
  result.container = root.box(style, id = id, groups = groups)
  result.legendNode = root.text(result.container, params.legend, legendStyle, groups = ["legend"])
  result.setDisabled(params.disabled)

proc fieldset*(
    root: UiRoot;
    legend: string;
    disabled = false;
    style = UiStyle();
    legendStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["fieldset"]
): FieldsetHandle {.discardable.} =
  root.fieldset(
    FieldsetParams(legend: legend, disabled: disabled),
    style = style,
    legendStyle = legendStyle,
    id = id,
    groups = groups
  )

template fieldset*(
    root: UiRoot;
    legend: string;
    body: untyped
): FieldsetHandle =
  block:
    let fieldsetHandle {.gensym.} = root.fieldset(legend)
    root.pushParent(fieldsetHandle.container)
    root.pushFieldsetContext(proc(setter: DisabledSetter) =
      fieldsetHandle.addDisabledTarget(setter)
    )
    try:
      body
    finally:
      root.popFieldsetContext()
      root.popParent()
    fieldsetHandle

template fieldset*(
    root: UiRoot;
    output: var FieldsetHandle;
    legend: string;
    body: untyped
) =
  block:
    output = root.fieldset(legend)
    root.pushParent(output.container)
    root.pushFieldsetContext(proc(setter: DisabledSetter) =
      output.addDisabledTarget(setter)
    )
    try:
      body
    finally:
      root.popFieldsetContext()
      root.popParent()
