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
