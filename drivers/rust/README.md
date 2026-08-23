# Rust Craft Driver

This crate is the maintained high-level Rust Driver for Clay Board Style
System. Raw `extern "C"` declarations remain private. `Ui` and `Style` own their
CBSS resources with `Drop`, and both are intentionally confined to their UI
thread.

```rust
use cbss_craft::{
    keyword, px, rgb, EventKind, EventOutcome, InputEvent, Result, Style, Ui,
};

fn build() -> Result<()> {
    let mut panel = Style::new()?;
    panel
        .set("width", px(320.0))?
        .set("padding", px(16.0))?
        .set("flex-direction", keyword("column"))?
        .set("background-color", rgb(0.12, 0.14, 0.18))?;

    let mut ui = Ui::new()?;
    let button = ui.box_with("panel", Some(&panel), |ui| {
        ui.text("Hello from Rust", "title", None)?;
        Ok(())
    })?;
    ui.on(button, EventKind::CLICK, |_event| {
        println!("Clicked");
        EventOutcome::HANDLED
    })?;
    ui.compute(800.0, 600.0)?;
    ui.emit(button, &InputEvent::new(EventKind::CLICK))?;
    Ok(())
}
```

Reusable component functions can return a retained `CraftComponent`. The
Driver creates one stable root, exposes its `root` Style Slot, and rolls the
whole subtree back on either `Err` or panic:

```rust
let mut label = None;
let mut status = ui.component_with("status-card", "status", None, |component| {
    label = Some(component.text("Idle", "label", None)?);
    component.public_style_slot("label", label)?;
    Ok(())
})?;

let label = label.expect("label");
ui.set_text(label, "Ready")?;
ui.set_state(status.root()?, cbss_craft::NodeState::Checked, true)?;
```

Retained setters update existing nodes without rebuilding their component or
replacing handlers.

The Driver also provides a typed retained Store without introducing a virtual
DOM. Reducers update stable state, selectors publish only changed projections,
and nested transactions produce one committed revision:

```rust
#[derive(Clone)]
struct Model { count: i32 }
enum Action { Add(i32) }

let store = cbss_craft::Store::new(Model { count: 0 }, |state, action| {
    match action {
        Action::Add(amount) => state.count += amount,
    }
});
let count = store.select(|state| state.count);
let retained_ui = ui.handle();
let _watch = status.watch(&count, move |value| {
    retained_ui
        .set_text(label, &value.to_string())
        .expect("update retained Text");
}, true)?;

store.transaction(|| {
    store.dispatch(Action::Add(2));
    store.dispatch(Action::Add(3));
});
ui.unmount(&mut status)?;
```

`CraftComponent::watch` applies the current selection by default and owns the
subscription until explicit `ComponentWatch::close`, component drop, or
successful `Ui::unmount`. The captured `UiHandle` is weak and UI-thread
confined; it rejects foreign Nodes and a destroyed `Ui` instead of extending the
engine lifetime. `StoreSubscription` detaches on `Drop` or explicit `close`.
Reentrant dispatch is queued. Selector equality suppresses unaffected updates, and
`dispatch_silent` can be paired with explicit `Selector::refresh` when
publication is intentionally deferred. Commit notifications carry a revision
rather than cloning the complete State; `Store::with_state` provides a borrowed
read path when an owned snapshot is unnecessary. `Rc` ownership deliberately
keeps the Store on its UI thread instead of suggesting unsupported concurrent
mutation.

Typed navigation uses application-defined destinations rather than URL
strings. The retained stack keeps stable entry identities, revisions, back and
forward state, and dirty-domain metadata without replaying the component tree:

```rust
#[derive(Clone, PartialEq)]
enum Screen { Dashboard, Projects, Settings }

let navigator = cbss_craft::Navigator::stack(Screen::Dashboard);
let _navigation = navigator.subscribe(|change| {
    // Update the retained screen host affected by this change.
});

navigator.push(Screen::Projects);
navigator.replace(Screen::Settings);
navigator.back();
```

Forward history is discarded after branching from an older entry. Replacing a
destination creates a new entry identity, while back and forward preserve the
existing identities. Boundary operations are no-ops and do not publish a
revision. `NavigationDriver` can replace the built-in stack policy without
changing application destination types. `NavigationSubscription` detaches on
`Drop` or explicit `close`; listener changes made during a notification take
effect on the next navigation change.

`NavigationScreenHost` keeps each registered screen subtree mounted and changes
only active/inert and `display` state. Focus is remembered by stable history
entry, so back and forward restore the control used in that specific entry.
`Link<Destination>` supplies the semantic click/Enter default while allowing a
public click handler to observe or prevent navigation:

```rust
let host = cbss_craft::NavigationScreenHost::new(&ui, navigator.clone());
host.register_screen(Screen::Dashboard, dashboard_root, Some(search))?;
host.register_screen(Screen::Projects, projects_root, Some(filter))?;
host.sync()?;

let projects = cbss_craft::Link::mount_in(
    &mut ui,
    app,
    navigator.clone(),
    Screen::Projects,
    "Projects",
    false,
    None,
    None,
    "projects-link",
)?;
projects.on_click(|_| cbss_craft::EventOutcome::HANDLED)?;
```

Inactive screens reject direct events and focus, and are excluded from layout,
paint, hit testing, and accessibility without rebuilding their Nodes. A public
Link click handler runs before navigation and may set prevent-default to cancel
that intrinsic action.

Optional screen transitions keep the outgoing and incoming retained roots
mounted together while making only the incoming root interactive. Calling
`sync()` keeps the legacy immediate behavior; `sync_at(now)` starts the
configured transition from a monotonic timestamp:

```rust
let transition = cbss_craft::NavigationTransitionSpec::new(0.2, |frame| {
    // Apply retained Style changes from frame.phase and frame.progress.
})?;
let host = cbss_craft::NavigationScreenHost::with_transition(
    &ui,
    navigator.clone(),
    transition,
)?;

host.sync_at(monotonic_seconds())?;
while host.transition_active() {
    // Wait until input arrives or next_transition_deadline() becomes due.
    host.advance_transition(monotonic_seconds())?;
}
```

`Started`, `Advanced`, `Completed`, and `Cancelled` callbacks carry typed old
and new entries plus both roots. The host returns a next-frame deadline instead
of creating a continuous frame loop, so an idle application can remain blocked
in its platform event wait. A transition hook may enqueue another navigation
without borrowing the screen-host state. A newer navigation cancels the current
transition before starting the next one, and screen removal cancels before
invalidating either callback root.

Typed validation chains are ordinary retained Rust values. Built-in rules are
declared once, stop at the first failure, and keep reporting policy separate
from current validity:

```rust
let pattern = cbss_craft::ValidationPattern::compile("^[A-Za-z0-9_]+$")?;
let rules = cbss_craft::ValidationRules::<String>::new()
    .required("Account is required")
    .min_length(3, "Account is too short")
    .matches(pattern, "Use letters, digits, or underscores");

let mut account = cbss_craft::ValidationBinding::new(
    rules,
    String::new(),
    cbss_craft::ValidationReport::OnBlur,
);
account.evaluate(
    "invalid-name".to_owned(),
    cbss_craft::ValidationTrigger::Blur,
    false,
);
if account.should_expose() {
    show_error(account.validation_message());
}
```

The Driver exposes all 40 canonical string, format, numeric, comparison,
collection, file-metadata, and custom operations. Regex and format checks use
the bounded engine capability rather than host-specific regex, URL, or date
semantics.

Rules can be attached to existing retained controls without replacing public
event handlers:

```rust
let account = cbss_craft::attach_text_validation(
    &mut ui,
    account_node,
    rules,
    "",
)?;

let mut validation_form = cbss_craft::ValidationForm::new(&ui, form_node)?;
validation_form.add(&account)?;

if validation_form.report_validity()? {
    save_account(account.validation_value().with(Clone::clone));
}
```

The attachment observes full values carried by `input`, keeps invalid Style
state and `validation-message` synchronized, and reports `invalid` through
additive subscriptions. Generic typed controls use `attach_validation` or
`attach_validation_with` with an event-to-value extractor. `ValidationForm`
skips disabled controls and focuses the first invalid control. Registering
controls also wires `same_as`/`different_from` peer edges so a
source change rechecks only its declared dependants. The weak edges expire with
either attachment and do not extend a component lifetime. The separate
immutable FormData/submit Driver surface is not approximated by this
validation-only adapter.

Typed Commands connect UI actions to asynchronous work while keeping UI
mutation on the owning thread:

```rust
let save = cbss_craft::Command::<Document, SaveResult, SaveError>::with_defaults(
    move |document, sink| {
        let request = repository.save(
            document,
            {
                let sink = sink.clone();
                move |result| { let _ = sink.succeed(result); }
            },
            move |error| { let _ = sink.fail(error); },
        );
        Some(Box::new(move || request.cancel()))
    },
)?;

save.on_success(|result| show_saved(result))?;
let ticket = save.run(current_document())?;
```

`LatestOnly`, `Ordered`, and `Concurrent` policies are explicit. A cloneable,
`Send` `CommandSink` crosses worker boundaries through a bounded queue; the UI
thread applies completions with `pump` or `pump_all`. Tickets retain terminal
status, ticket-scoped observers detach on `Drop`, cancellation advances
ordered work, and disposal rejects late completion offers. Queue item and
weight limits return `Backpressure` instead of dropping a result. A thread-safe
wake callback may post one host event when an empty completion queue becomes
non-empty.

Cue graphs coordinate serial actions, delayed parallel work, and explicit
joins without application-maintained completion flags:

```rust
let timeline = status.cue_runtime()?;
let reveal = cbss_craft::cue(cbss_craft::cue_action("prepare", prepare_card)?)
    .then_stage(
        vec![
            cbss_craft::cue_after(
                0.1,
                cbss_craft::cue_action("title", reveal_title)?,
            )?,
            cbss_craft::cue_after(
                0.1,
                cbss_craft::cue_action("chart", reveal_chart)?,
            )?,
        ],
        cbss_craft::CueJoinPolicy::All,
    )?
    .then(cbss_craft::cue_action("ready", mark_ready)?)?;

let session = timeline.start(&reveal, cbss_craft::CueStartPolicy::Restart)?;
timeline.tick(0.1)?;
```

Actions may retain their `CueCompletion` and return a cancellation closure for
asynchronous work. `All`, `Any`, and `Race` joins and `Restart`, `Ignore`,
`Queue`, and `Parallel` repeated-start policies are explicit. Each runtime owns
an independent monotonic logical clock with pause/resume, rate, and
next-deadline queries. A runtime created through
`CraftComponent::cue_runtime` is cancelled when its component is unmounted or
dropped, even if application code still holds a cloned runtime or session
handle. Standalone `CueRuntime` values remain available for
application-scoped orchestration.

Set `CBSS_LIB_DIR` to the directory containing the shared or static C ABI
library. Set `CBSS_STATIC=1` for static linking. On Linux, a shared build also
needs that directory in `LD_LIBRARY_PATH` when the application starts.

The scoped authoring closure receives a `Scope` rather than exposing a parent
Node identifier. This makes early `Result` returns and panic unwinding safe
without replaying or repairing a mutable parent stack. Nodes also retain their
owning context identity, so a Node from another `Ui` is rejected before FFI.

`Ui::on` replaces the public handler for one node/event pair. `Ui::subscribe`
adds an observer and returns an `EventSubscription` that unregisters on `Drop`
or explicit `close`. Callback event strings are copied before the C callback
returns. Rust panics are contained at the FFI boundary and can be detected with
`Ui::callback_panicked`; they never unwind through Nim or C.
`Ui::remove_subtree` atomically removes a retained branch and releases the
Driver-owned callback holders after native blur and motion-cancellation
delivery completes. Existing subscription tokens immediately report inactive,
and generation-checked `Node` values cannot alias later replacements.

Portable presentation and package metadata use the same bounded JSON contracts
as Nim and C. A component exposes only deliberate public targets with
`expose_style_slot`; `replace_craft_style` and `replace_craft_pack` are atomic.
`active_craft_styles`, `active_craft_packs`, and `craft_diagnostics` return
owned Rust values. The Driver never reads asset paths from a Pack manifest.
