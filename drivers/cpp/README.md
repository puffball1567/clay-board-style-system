# C++ Craft Driver

This header-only C++14 Driver is the first high-level foreign-language
authoring surface for Clay Board Style System. It wraps the stable C ABI but
keeps raw context pointers, parent node identifiers, status checks, and manual
destruction out of ordinary application code.

```cpp
#include <cbss/craft.hpp>

cbss::Style panel;
panel.set("width", cbss::px(320))
     .set("padding", cbss::px(16))
     .set("flex-direction", cbss::keyword("column"))
     .set("background-color", cbss::rgb(0.12f, 0.14f, 0.18f));

cbss::Ui ui;
ui.box("panel", panel, [&] {
  ui.text("Hello from C++", "title");
});
ui.compute(800, 600);
```

The Driver negotiates the engine ABI, Driver contract, and baseline authoring
capabilities before it constructs a context. `Ui` and `Style` use deterministic
RAII lifetime. Nested callbacks maintain parentage with an exception-safe
scope, so user code does not pass parent handles.

Compile against either the shared or static C ABI library:

```sh
c++ -std=c++14 -Iinclude -Idrivers/cpp/include app.cpp \
  -L/path/to/cbss/lib -lcbss -o app
```

The public escape hatches `nativeHandle()` and `Node::nativeId()` are intended
for advanced integrations that need C ABI features not yet covered by this
Driver. They are not required by the normal nested authoring path.
