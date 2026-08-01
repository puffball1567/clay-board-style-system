import ../core/node
import ../input/events
import ./ui_root

type
  FormParams* = object
    disabled*: bool
    valid*: bool

  FormState* = ref object
    disabled*: bool
    valid*: bool
    submitted*: int
    resetCount*: int
    invalidCount*: int

  FormHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    state*: FormState

proc submitted*(form: FormHandle): int =
  form.state.submitted

proc resetCount*(form: FormHandle): int =
  form.state.resetCount

proc invalidCount*(form: FormHandle): int =
  form.state.invalidCount

proc disabled*(form: FormHandle): bool =
  form.state.disabled

proc valid*(form: FormHandle): bool =
  form.state.valid

proc setDisabled*(form: FormHandle; disabled: bool) =
  form.state.disabled = disabled
  form.container.setState(esDisabled, disabled)

proc setValid*(form: FormHandle; valid: bool) =
  form.state.valid = valid

proc submit*(form: FormHandle): bool =
  if form.state.disabled:
    return false
  if not form.state.valid:
    inc form.state.invalidCount
    discard form.container.emit(iekInvalid)
    return false
  inc form.state.submitted
  discard form.container.emit(iekSubmit)
  true

proc reset*(form: FormHandle): bool =
  if form.state.disabled:
    return false
  inc form.state.resetCount
  discard form.container.emit(iekReset)
  true

proc `onSubmit=`*(form: FormHandle; handler: EventHandler) =
  form.container.onSubmit = handler

proc `onReset=`*(form: FormHandle; handler: EventHandler) =
  form.container.onReset = handler

proc `onInvalid=`*(form: FormHandle; handler: EventHandler) =
  form.container.onInvalid = handler

proc form*(
    root: UiRoot;
    params = FormParams(valid: true);
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["form"]
): FormHandle {.discardable.} =
  result.root = root
  result.state = FormState(disabled: params.disabled, valid: params.valid)
  result.container = root.box(style, id = id, groups = groups)
  result.container.setState(esDisabled, params.disabled)

proc form*(
    root: UiRoot;
    valid = true;
    disabled = false;
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["form"]
): FormHandle {.discardable.} =
  root.form(FormParams(disabled: disabled, valid: valid), style = style, id = id, groups = groups)
