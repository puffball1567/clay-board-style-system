# C++ Craft Driver

This header-only C++14 Driver is the first high-level foreign-language
authoring surface for Clay Board Style System. It wraps the stable C ABI but
keeps raw context pointers, parent node identifiers, status checks, and manual
destruction out of ordinary application code.

```cpp
#include <cbss/craft.hpp>
#include <iostream>

cbss::Style panel;
panel.set("width", cbss::px(320))
     .set("padding", cbss::px(16))
     .set("flex-direction", cbss::keyword("column"))
     .set("background-color", cbss::rgb(0.12f, 0.14f, 0.18f));

cbss::Ui ui;
const cbss::Node button = ui.box("panel", panel, [&] {
  ui.text("Hello from C++", "title");
});
ui.on(button, CBSS_EVENT_CLICK, [](const cbss::Event&) {
  std::cout << "Clicked\n";
  return cbss::EventOutcome::handled();
});
ui.compute(800, 600);
ui.emit(button, cbss::InputEvent(CBSS_EVENT_CLICK));
```

Reusable component functions can return a retained `CraftComponent`. The
Driver creates one stable root, exposes its `root` Style Slot, and rolls the
whole subtree back if construction throws:

```cpp
cbss::Node label;
cbss::CraftComponent status = ui.component(
    "status-card", "status", [&](cbss::ComponentScope& component) {
      label = component.text("Idle", "label");
      component.publicStyleSlot("label", label);
    });

ui.setText(label, "Ready");
ui.setState(status.root(), cbss::NodeState::checked, true);
```

These retained setters update the existing nodes; they do not rebuild the
component or replace its handlers. `Ui::unmount` removes the complete component
subtree and invalidates the wrapper.

The Driver also provides a typed retained Store without introducing a virtual
DOM. Reducers update one stable state object, selectors publish only changed
projections, and nested transactions produce one committed revision:

```cpp
struct Model { int count = 0; };
struct Add { int amount; };

auto store = cbss::createStore<Model, Add>(
    Model(), [](Model& state, const Add& action) {
      state.count += action.amount;
    });
auto count = store.select<int>([](const Model& state) { return state.count; });
auto retainedUi = ui.handle();
auto watch = status.watch(count, [retainedUi, label](const int& value) {
  retainedUi.setText(label, std::to_string(value));
});

store.transaction([&] {
  store.dispatch({2});
  store.dispatch({3});
});
```

`CraftComponent::watch` applies the current selection by default and owns the
subscription until explicit `ComponentWatch::close`, component destruction, or
successful `Ui::unmount`. The captured `UiHandle` is a weak, UI-thread-confined
retained-mutation handle; it rejects foreign Nodes and a destroyed `Ui` rather
than extending the engine lifetime. `StoreSubscription` is move-only and
detaches through RAII or `close()`. Reentrant dispatch is queued. Selector
equality suppresses unaffected updates, and `dispatchSilent` can be paired with
explicit `Selector::refresh` when publication is intentionally deferred. Commit
notifications carry a revision rather than copying the complete State;
`Store::read` provides a borrowed read path when a State copy is unnecessary.
Store and UI operations remain confined to the owning UI thread.

Typed navigation uses application-defined destinations rather than URL
strings. The retained stack keeps stable entry identities, revisions, back and
forward state, and dirty-domain metadata without rebuilding the UI tree:

```cpp
enum class Screen { dashboard, projects, settings };

auto navigator = cbss::createStackNavigator(Screen::dashboard);
auto navigation = navigator.subscribe(
    [](const cbss::NavigationChange<Screen>& change) {
      // Update the retained screen host affected by this change.
    });

navigator.push(Screen::projects);
navigator.replace(Screen::settings);
navigator.back();
```

Forward history is discarded after branching from an older entry. Replacing a
destination creates a new entry identity, while back and forward preserve the
existing identities. Boundary operations are no-ops and do not publish a
revision. `NavigationDriver` can replace the built-in stack policy without
changing application destination types. `NavigationSubscription` is move-only
and detaches through RAII or `close()`; listener changes made during a
notification take effect on the next navigation change.

`NavigationScreenHost` keeps each registered screen subtree mounted and changes
only active/inert and `display` state. Focus is remembered by stable history
entry, so back and forward restore the control used in that specific entry.
`Link<Destination>` supplies the semantic click/Enter default while leaving
application behavior replaceable through `onClick`:

```cpp
cbss::NavigationScreenHost<Screen> host(ui, navigator);
host.registerScreen(Screen::dashboard, dashboardRoot, dashboardSearch);
host.registerScreen(Screen::projects, projectsRoot, projectsFilter);
host.sync();

cbss::Link<Screen> projectsLink;
ui.within(app, [&] {
  projectsLink = cbss::Link<Screen>::mount(
      ui, navigator, Screen::projects, "Projects");
});
projectsLink.onClick([](const cbss::Event&) {
  return cbss::EventOutcome::handled();
});
```

Inactive screens reject direct events and focus, and are excluded from layout,
paint, hit testing, and accessibility without rebuilding their Nodes. A public
Link click handler runs before navigation and may set prevent-default to cancel
that intrinsic action.

Typed validation chains are ordinary retained C++ values. Built-in rules are
declared once, stop at the first failure, and keep reporting policy separate
from current validity:

```cpp
const cbss::ValidationPattern accountPattern("^[A-Za-z0-9_]+$");
const auto accountRules = cbss::ValidationRules<std::string>()
    .required("Account is required")
    .minLength(3)
    .matches(accountPattern);

cbss::ValidationBinding<std::string> account(
    accountRules, "", cbss::ValidationReport::onBlur);
account.evaluate("invalid-name", cbss::ValidationTrigger::blur);
if (account.shouldExpose()) {
  showError(account.validationMessage());
}
```

The Driver exposes all 40 canonical string, format, numeric, comparison,
collection, file-metadata, and custom operations. Regex and format checks use
the bounded engine capability, so C++ does not silently substitute
`std::regex` or platform-specific URL/date parsing.

Typed Commands connect UI actions to asynchronous work without allowing a
worker to call UI code directly:

```cpp
using SaveCommand = cbss::Command<Document, SaveResult, SaveError>;

SaveCommand save([&](Document document, SaveCommand::Sink sink) {
  auto request = repository.save(
      std::move(document),
      [sink](SaveResult result) mutable { sink.succeed(std::move(result)); },
      [sink](SaveError error) mutable { sink.fail(std::move(error)); });
  return SaveCommand::Cancel([request]() mutable { request.cancel(); });
});

save.onSuccess([&](SaveResult result) { showSaved(std::move(result)); });
const cbss::CommandTicket ticket = save.run(currentDocument());
```

`latestOnly`, `ordered`, and `concurrent` policies are explicit. Copyable
`CommandSink` values cross worker boundaries through a bounded queue; the UI
thread applies completions with `pump`. Tickets retain terminal status,
ticket-scoped observers detach through RAII, cancellation advances ordered
work, and disposal rejects late completion offers. Queue item and weight
limits report backpressure instead of silently dropping a result. A wake
callback may post one host event when an empty completion queue becomes
non-empty.

The Driver negotiates the engine ABI, Driver contract, and baseline authoring
capabilities before it constructs a context. `Ui` and `Style` use deterministic
RAII lifetime. Nested callbacks maintain parentage with an exception-safe
scope, so user code does not pass parent handles.

`Ui::on` replaces one public node handler. `Ui::subscribe` adds an observer and
returns a move-only `EventSubscription` that unregisters through RAII or
explicit `close()`. Callback event strings are copied before the C callback
returns. Exceptions are contained at the C boundary; `callbackFailed()` and
`rethrowCallbackFailure()` let the application handle them on the C++ side.
`Ui::removeSubtree` atomically removes a retained branch and releases the
Driver-owned callback holders after native blur and motion-cancellation
delivery completes. Removed subscription tokens immediately report inactive,
and generation-checked `Node` values cannot alias later replacements.

Portable presentation and package metadata use the same bounded JSON contracts
as Nim and C. A component exposes only deliberate public targets with
`exposeStyleSlot`; `replaceCraftStyle` and `replaceCraftPack` are atomic.
`activeCraftStyles`, `activeCraftPacks`, and `craftDiagnostics` provide typed
queries without exposing C buffers. The Driver never reads asset paths from a
Pack manifest.

Compile against either the shared or static C ABI library:

```sh
c++ -std=c++14 -Iinclude -Idrivers/cpp/include app.cpp \
  -L/path/to/cbss/lib -lcbss -o app
```

The public escape hatches `nativeHandle()` and `Node::nativeId()` are intended
for advanced integrations that need C ABI features not yet covered by this
Driver. They are not required by the normal nested authoring path.
