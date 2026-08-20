# Rust Craft Driver

This crate is the maintained high-level Rust Driver for Clay Board Style
System. Raw `extern "C"` declarations remain private. `Ui` and `Style` own their
CBSS resources with `Drop`, and both are intentionally confined to their UI
thread.

```rust
use cbss_craft::{keyword, px, rgb, Result, Style, Ui};

fn build() -> Result<()> {
    let mut panel = Style::new()?;
    panel
        .set("width", px(320.0))?
        .set("padding", px(16.0))?
        .set("flex-direction", keyword("column"))?
        .set("background-color", rgb(0.12, 0.14, 0.18))?;

    let mut ui = Ui::new()?;
    ui.box_with("panel", Some(&panel), |ui| {
        ui.text("Hello from Rust", "title", None)?;
        Ok(())
    })?;
    ui.compute(800.0, 600.0)
}
```

Set `CBSS_LIB_DIR` to the directory containing the shared or static C ABI
library. Set `CBSS_STATIC=1` for static linking. On Linux, a shared build also
needs that directory in `LD_LIBRARY_PATH` when the application starts.

The scoped authoring closure receives a `Scope` rather than exposing a parent
Node identifier. This makes early `Result` returns and panic unwinding safe
without replaying or repairing a mutable parent stack. Nodes also retain their
owning context identity, so a Node from another `Ui` is rejected before FFI.
