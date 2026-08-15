# CBSS Runtime Component Notes

Per-component behavior notes for the reference runtime controls and widgets.
This content was extracted from the Selectors section of
[architecture.md](architecture.md) (see `docs/design-decisions.md` D14), which
now holds only stable design intent. New or changed component behavior should
be documented here (or in module doc comments), not appended to
architecture.md.

These components are reference implementations layered on CBSS mechanisms
(see design-decisions.md D1): thin, style-neutral in intent, and replaceable
by higher-level GUI libraries. The shared authoring conventions they must
follow (state flags, activation gestures, disabled handling, event emission
order) are defined in design-decisions.md D15.

`runtime/text_input.nim` provides the first minimal component-level version of
that policy. It owns value, caret, composition text, placeholder display, and
basic edit commands such as text input, paste, Backspace, Delete, and caret
movement. The component updates its value before user `onInput`/`onChange`
handlers run, so handlers can read the current component value instead of
reconstructing it from low-level input events.

TextInput also owns selection for its own value. `Ctrl+A`/`Meta+A` selects the
full value, Shift+Arrow extends selection, text input and paste replace the
selection, and copy/cut expose the selected text through the component state.
The component does not write to an OS clipboard by itself; backend examples can
connect `onCopy`/`onCut` to SDL3 clipboard helpers while keeping that platform
boundary outside the generic runtime component.

Selection changes emit `onSelect`. `readOnly` allows focus, selection, copy, and
caret movement but blocks value-changing input, paste, cut deletion, Backspace,
and Delete. `disabled` blocks focus and editing. `maxLength` limits initial
value, explicit `setValue`, text input, and paste without splitting UTF-8
sequences.

Internal component handlers may stop further event expansion by returning
`true`. TextInput uses this to prevent read-only or disabled low-level text
input from continuing into value-level `onInput`/`onChange` events.

`runtime/textarea.nim` extends the same basic editing policy to multiline text.
It owns value, caret, selection, composition text, placeholder display, copy/cut,
paste, `readOnly`, `disabled`, and `maxLength`. Enter inserts a newline, Home
and End move within the current line, and ArrowUp/ArrowDown move by line column.
It also provides basic textarea resize behavior: a resize handle can update
width and height, respect `horizontal`/`vertical`/`both`/`none`, clamp to
min/max size values, and emit `onResize`. Direct constructor styles for
`resize`, `width`, `height`, `min-width`, `max-width`, `min-height`, and
`max-height` are read as initial runtime values. Full external stylesheet-driven
resize behavior can be wired later through the resolver/runtime bridge. The
element intentionally stays style-neutral and does not implement
product-specific editor behavior.

`runtime/label.nim` provides a label element for form-like controls. CBSS does
not need to reproduce the browser DOM `for`/`id` lookup model; a label stores an
optional `NodeHandle` target directly. Activating the label emits focus and
click on that target, so checkbox and radio controls can toggle/select while
text input and textarea controls can receive focus. This keeps the association
explicit in Nim code and avoids making ids mandatory for runtime behavior.

`runtime/fieldset.nim` provides a grouping element for form-like controls. It
owns a legend node and a list of disabled-target callbacks registered while a
fieldset block is active. `fieldset.setDisabled(true)` propagates disabled state
to controls created inside the block, and disabling the fieldset later restores
each control to its original disabled state. This keeps the expected fieldset
semantics without introducing a browser DOM ownership model.

```nim
let contact = ui.fieldset("Contact"):
  let name = ui.textInput(TextInputParams(placeholder: "Name"))
  ui.label("Name", name)

  let message = ui.textArea(TextAreaParams(placeholder: "Message"))
  ui.label("Message", message)

  let subscribe = ui.checkbox("Subscribe")
  ui.label("Subscribe to updates", subscribe)
```

`runtime/button.nim` provides the first minimal click component. It owns the
label node, disabled state, disabled click suppression, and keyboard activation
through Enter and Space. User code can still assign `button.onClick = handler`,
while disabled and inert checks remain runtime preconditions. User handlers run
before the button's intrinsic activation action and may prevent that action
without stopping propagation.

`runtime/link.nim` provides the semantic navigation primitive. It owns pointer
activation, Enter-key activation, focusability, disabled suppression, and the
accessible Link role while leaving all visual styling to injected CBSS styles.
It pushes an application-defined typed destination through an injected
`Navigator`; optional user `onClick` behavior runs before internal navigation
and may prevent it through the typed event outcome.
Space is not Link activation. The application-owned navigator must outlive its
mounted links because links keep a non-owning ARC cursor to it.

`runtime/navigation_screen_host.nim` retains prebuilt screen roots and activates
the root matching the navigator's current typed destination. Inactive roots are
`display: none` and inert, so state is preserved without leaking input, focus,
or accessibility behavior. `sync` is called once after an event batch and
coalesces any intermediate navigation changes. `replaceScreen` and
`unregisterScreen` dispose obsolete subtrees through generation-checked node
slots, removing their event, style, scroll, popup, focus, and semantic runtime
references before those slots can be reused.

`runtime/checkbox.nim` provides a boolean form component. It owns its checked
state, syncs that state to `esChecked`, suppresses pointer and keyboard changes
when disabled, and emits `onInput` followed by `onChange` only when the checked
value actually changes. User code can assign `checkbox.onChange = handler` or
read the current value with `checkbox.checked()`.

`runtime/switch.nim` provides a semantic boolean switch for settings that take
effect immediately. It owns a track and transform-positioned thumb, exposes the
dedicated Switch accessibility role, supports pointer plus Space/Enter
activation, and follows the same `onInput` then `onChange` value contract as
Checkbox. The thumb transform and checked-track overlay opacity use a default
180ms `ease` transition. Reversing while active continues from the sampled
visual position rather than jumping to an endpoint. Base, track, thumb, label,
checked-track, and checked-thumb styles are all injectable; higher-level GUI
libraries can therefore replace the reference appearance without replacing the
control behavior.

```nim
let liveUpdates = ui.switch(
  "Live updates",
  checked = true,
  transitionDurationSeconds = 0.18,
  transitionTiming = easeTiming(),
  checkedTrackStyle = uiStyle([
    decl("background-color", colorValue(rgb(0.20, 0.66, 0.52)))
  ])
)

liveUpdates.onChange = proc(event: DispatchResult): EventOutcome =
  echo liveUpdates.checked()
  ignoredEvent()
```

Hosts call `ui.tickOwnedAnimations(scheduler, nowSeconds)` once per event-loop
pass and `ui.scheduleOwnedAnimations(scheduler, nowSeconds)` after rebuilding
their wait deadline. No animation means no deadline and the host can remain
blocked in `SDL_WaitEvent`. `ui.setReducedMotion(true)` makes nonessential
control motion complete on its next tick. Owned animations are canceled when
their component subtree is disposed.

`runtime/radio.nim` provides a small exclusive-choice component around
`RadioSet`. The set stores the selected value and updates peer radios directly,
without relying on CSS-like id/class matching. This keeps radio exclusivity as
component state, while ids and groups remain optional style/design-source
metadata. A radio emits value-level `onInput`/`onChange` when it becomes the
selected item; selecting an already checked radio is a no-op.

`runtime/select_box.nim` provides a small value-selecting component. It owns the
option list, selected index, open state, disabled state, selected option
metadata, and ArrowUp/ArrowDown keyboard selection. Option clicks select a value
and close the component. The first implementation keeps popup/menu rendering
inside the CBSS tree as reference behavior; a higher-level GUI library can later
replace that visual layer while keeping the same selected-value and event
contract.

`runtime/slider.nim` provides a numeric value component. It owns min/max/step
clamping, disabled state, pointer-local value updates, drag state, and keyboard
adjustment through arrow keys, Home, and End. The first implementation accepts a
`trackWidth` parameter as the input coordinate basis; later layout integration
can replace that with measured track geometry without changing the value/event
contract.

`runtime/progress.nim` provides a read-only progress component. It owns
value/max clamping, percentage display, and indeterminate state. Indeterminate
progress maps to `esActive` so style rules can distinguish ongoing work without
inventing a new selector mechanism.

`runtime/form.nim` owns `onSubmit`, `onReset`, and `onInvalid` dispatch plus
explicit field registration and immutable `FormData` collection. Text inputs,
text areas, selects, checkboxes, radios, and file inputs register by handle and
field name; collection does not require CSS selectors or public ids. Disabled
and unchecked controls follow the documented form rules, while disposed or
value-less registrations produce diagnostics instead of being silently lost.
Successful submission collects once and transports the resulting immutable
snapshot on the submit event; later control mutations cannot change it.

Version 0.5 extends this existing registration model with reusable typed
validation rules attached to controls. Controls retain current validity while
error reporting remains independently configurable for input, blur, or submit.
Forms gain `checkValidity()` and `reportValidity()`; `submit()` validates before
collecting the immutable snapshot. Network-backed checks remain explicit
Commands rather than hidden rules. The target contract is documented in
[Form Validation Design](form-validation.md).

`runtime/file_input.nim` provides a style-neutral file-selection boundary. It
does not open paths or own a platform picker. User activation gives application
code a copied `FileSelectionRequest`; the host applies its permission, sandbox,
content, and size policy, then supplies immutable `Blob` values with
`setFiles`. Single/multiple constraints, disabled behavior, keyboard
activation, accessibility value updates, input/change events, and ordered
FormData entries remain CBSS-owned behavior.

`runtime/dialog.nim` provides an open/close component with `onShow`, `onClose`,
and `onCancel`. Open state maps to `esActive`; closed state maps to `esDisabled`
so hit and input behavior can be styled or filtered consistently. Escape
dispatches cancel, then close.

`runtime/widgets/tabs.nim` provides an indexed reference widget. It stores tab
items as an array, marks the selected tab with `esSelected`, skips disabled tabs,
and emits value-level `onInput`/`onChange` when the selected value changes. This
is the preferred shape for structural UI choices: the widget owns array order
and selection instead of relying on structural selectors.

`runtime/widgets/list_box.nim` provides a permanently visible indexed reference
widget. It follows the same array-owned selection model as Tabs and Select, with
ArrowUp/ArrowDown/Home/End navigation and `esSelected`/`esDisabled` state
syncing on item nodes.

`runtime/widgets/command_menu.nim` provides a small command-menu reference
widget. It owns open/closed state, active item index, disabled item skipping,
`onShow`/`onClose`, and value-level `onInput`/`onChange` when a command item is
activated. Closed command menus map to `esDisabled` and open command menus map
to `esActive`. It is intentionally not modeled as the HTML `<menu>` element.
