# Form Validation Design

Status: `Released in Version 0.5`

CBSS form validation is a retained UI capability, not a transport protocol or
a replacement for backend validation. Applications declare reusable typed
rules, controls keep their validity current as values change, and forms decide
when to report those results to a user.

The design follows the useful part of browser constraint validation: validity
is reactive, reporting policy is separate, invalid intermediate input remains
editable, and submission is stopped before application transport runs. It does
not reproduce HTML attributes, a DOM, or browser validation messages.

## Authoring Model

Rules are created once and attached to a control:

```nim
let usernamePattern = compileRegex("^[A-Za-z0-9_]+$")

let usernameRules =
  validationRules[string]()
    .required("Username is required")
    .minLength(3, "Username is too short")
    .matches(usernamePattern, "Use letters, numbers, or underscores")

let usernameInput = ui.textInput(
  username,
  validation = usernameRules,
  reportOn = ValidationReport.onBlur
)
```

`ValidationRules[T]` is an ordinary typed Nim value. It can be imported,
injected into a component, shared by controls with the same contract, and
tested without constructing a `UiRoot`. Control attachment is the normal UI
path, while direct validation remains available:

```nim
let result = usernameRules.validate(username)
if not result.isValid:
  echo result.message
```

Rule attachment does not make the control own application policy. The
application owns rule selection, error wording, and what happens after a valid
submission.

## Validity And Reporting

Every validating control keeps a current validity result. A value change
evaluates only that control and explicitly registered cross-field dependants.
It does not rebuild the component, scan the form, or invalidate unrelated UI.

The implemented controls are text input, text area, select, checkbox, radio
set, and file input. Each exposes `setValidation`, `validationResult`,
`validationMessage`, `checkValidity`, and `reportValidity` (radio validation is
owned by `RadioSet`). `validationValue` exposes an explicit retained peer for
`sameAs` and `differentFrom` without public ids or selector lookup.

Computing validity and presenting an error are separate operations:

- `onInput` reports while the value changes and when the user leaves a control
  that is still invalid;
- `onBlur` reports after the user leaves the control;
- `onSubmit` reports when submission is attempted; and
- after a failure has been reported, a control may update the visible result
  on input so the user can see when the value becomes valid.

Invalid input remains editable. CBSS does not reject an intermediate value at
the key-event boundary by default. A numeric field may temporarily contain a
minus sign, and a partially entered email address may remain in the control
while its validity is false.

Disabled controls are barred from constraint validation. Their direct
`checkValidity()` and `reportValidity()` calls succeed without dispatching an
invalid event, and they do not expose invalid Style or accessibility state.
Re-enabling a control restores validation from its retained value and rules.

Validity feeds the same retained mechanisms as other control state:

- invalid-state Style selection;
- an accessible invalid state, with author-owned error components connected
  through the existing accessible description relationship;
- an optional error component owned by the authoring component; and
- bounded paint, semantic, and accessibility invalidation when the visible or
  exposed result changes.

CBSS does not invent application error copy or force every form library to use
one visual error component.

## Form Contract

The Version 0.5 form surface adds browser-familiar operations without browser
submission behavior:

- `form.checkValidity()` evaluates enabled registered controls and returns a
  Boolean without forcing visible reports;
- `form.reportValidity()` evaluates, exposes errors, and focuses the first
  invalid control under the active focus policy; and
- `form.submit()` runs form validation before collecting one immutable
  `FormData` snapshot and dispatching `onSubmit`.

An invalid submission does not invoke application transport. Disabled controls
are excluded from both successful-control collection and required-value
failure. Disposed registrations remain diagnostics rather than disappearing
silently.

```nim
form.onSubmit = proc(event: DispatchResult): EventOutcome =
  let data = event.formData.get
  sendRequestWithJoubako(data)
  handledEvent()

discard form.submit()
```

The callback runs only after local validation succeeds. Backend code must still
validate the submitted data authoritatively because frontend validation is a
usability and early-rejection boundary, not a security boundary.

The Version 0.6 C++14 and Rust reference Drivers expose the same retained
control-reporting path through `ValidationControl[T]` and `ValidationForm`.
Attachments use additive `input` and `blur` observers, update only the changed
control, preserve application handlers, synchronize invalid Style/message
state, skip disabled controls, and focus the first invalid registered control.
Form registration also connects declared peer identities with weak dependency
edges, so a changed source rechecks only `sameAs`/`differentFrom` dependants;
cycle guards prevent recursive re-entry and the edges do not retain controls.
The high-level foreign FormData builder and payload-bearing submit event remain
a separate Driver task; the validation adapter does not emit a payload-free
event under the canonical `submit` name.

## Built-In Rules

The first field-focused release contains 40 synchronous operations:

- **Presence and strings:** `required`, `optional`, `minLength`, `maxLength`,
  `exactLength`, `notBlank`, `matches`, `contains`, `startsWith`, and
  `endsWith`.
- **Formats:** `email`, `url`, `uuid`, `ipAddress`, `date`, `time`, and
  `dateTime`. `matches` is the regular-expression rule; there is no duplicate
  `regex` rule.
- **Numbers:** `min`, `max`, `range`, `integer`, `positive`, `negative`,
  `finite`, and `multipleOf`.
- **Comparison and selection:** `equalTo`, `notEqualTo`, `oneOf`, `notOneOf`,
  `sameAs`, and `differentFrom`.
- **Collections and multiple selection:** `minItems`, `maxItems`, `exactItems`,
  and `uniqueItems`.
- **Files:** `maxFileSize`, `allowedMimeTypes`, `allowedExtensions`, and
  `maxFiles`.
- **Extension:** `custom`.

Validation and normalization remain separate. Trimming, case conversion,
Unicode normalization, coercion, parsing, and default insertion must not
silently mutate a value during validation.

Format rules answer only whether a value has the declared shape. `url` does
not decide which schemes an application may open, and file MIME metadata does
not prove file contents are safe. Applications must apply scheme allowlists,
backend validation, and content inspection at their trust boundaries.
`matches` performs a whole-value match and accepts only a prepared
`ValidationPattern`. Its pure Nim regex engine provides linear-time matching
without a native PCRE runtime dependency. Applications must still bound and
prepare attacker-controlled pattern definitions away from the UI thread.

## Cross-Field Rules

`sameAs` and `differentFrom` declare an explicit dependency on another retained
control value. When that peer changes, CBSS revalidates only registered
dependants. It does not subscribe every field to an entire form or infer
dependencies from a closure.

```nim
let password = ui.textInput(TextInputParams(
  value: "",
  inputType: TextInputType.password
))
let confirmation = ui.textInput(TextInputParams(
  value: "",
  inputType: TextInputType.password
))

confirmation.setValidation(
  validationRules[string]().sameAs(
    password.validationValue,
    "Passwords do not match"
  )
)
```

The dependency registry suppresses recursive refresh of an active target and
removes registrations when the dependent subtree is disposed. Replacing a
control's rule set also replaces its dependency registrations.

## Asynchronous Checks

Network queries and application-state lookups do not belong in the validation
rule chain. Username availability, invitation validity, and server-side policy
are Commands or application operations that may use Joubako:

```nim
let local = usernameRules.validate(usernameInput.value)
if local.isValid:
  usernameAvailability.execute(usernameInput.value)
```

The Command owns cancellation, stale-result rejection, progress, and retained
UI publication. Joubako owns HTTP request construction and transport. This
keeps synchronous value validity deterministic and prevents a hidden network
request from running on every keystroke. There is no `customAsync` validator in
the Version 0.5 rule set.

## Performance And Ownership

- Built-in rules are typed descriptors or a bounded tagged representation, not
  one capturing closure per rule.
- Rules are prepared once. Input events do not rebuild rule lists or compile
  regular expressions.
- The success path borrows its value where possible, performs no input string
  copy, and allocates no error collection.
- Evaluation stops at the first failure. A future explicit all-error API may
  allocate only while recording failures; Version 0.5 does not expose one.
- `optional` short-circuits rules that do not apply to an absent value;
  `required` and `notBlank` remain distinct.
- File rules inspect immutable Blob/file metadata and bounded counts. They do
  not read file contents, trust advisory MIME metadata as a security decision,
  or perform transport work.
- `custom` accepts a typed Nim procedure. A capturing closure is an explicit
  author cost, not the built-in execution model.
- Rule ownership and control subscriptions are disposed with their component
  under ARC and ORC. No validation subscription may retain a dead `UiRoot`.

## Release Gates

Version 0.5 validation is complete only when the following are covered under
ARC and ORC:

- every built-in rule, including boundary, malformed, absent, and non-finite
  cases;
- all reporting modes and the transition from invalid to valid;
- disabled, disposed, and conditionally mounted controls;
- cross-field dependency updates and cycle protection;
- `checkValidity`, `reportValidity`, invalid submit, valid submit, focus, and
  immutable FormData collection order;
- accessibility invalid state and author-owned error relationships;
- no input-value copy or error-collection allocation on the common success
  path, plus bounded dirty-work performance checks; and
- component and form integration tests proving that unrelated controls and
  layout are not recomputed.

The validation suite is maintained as a matrix rather than a single happy-path
test:

| Dimension | Required coverage |
| --- | --- |
| Rule operations | All 40 operations with accepted and rejected values; `optional` with absent and present values |
| Boundaries | Exact limits, Unicode length, malformed descriptors, malformed formats, NaN, and infinity |
| Controls | Text input, text area, select, checkbox, radio set, and file input |
| Reporting | `onInput`, `onBlur`, `onSubmit`, explicit checks, correction after failure, and disabled controls |
| Dependencies | Peer update, unrelated peer isolation, replacement, disposal, source indexing, and recursion suppression |
| Forms | Check, report, invalid event, first-invalid focus, disabled exclusion, and immutable successful data |
| Ownership | ARC and ORC, ASan, Linux integrated LSan, and Valgrind definite/indirect leak checks |
| ABI and semantics | C/C++ header consumers, shared/static C consumers, invalid state, and AT-SPI mapping |
| Performance | Prepared descriptors and precompiled regular expressions at 10k and 100k iterations |

Later optional schema modules may cover runtime object, tuple, union, and
recursive-data validation where runtime input makes them useful. Nim's static
type system remains the primary schema mechanism for ordinary application
objects.
