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

ui.set_text(label.expect("label"), "Ready")?;
ui.set_state(status.root()?, cbss_craft::NodeState::Checked, true)?;
ui.unmount(&mut status)?;
```

Retained setters update existing nodes without rebuilding their component or
replacing handlers. Rust state crates or application-owned values can drive
this surface without introducing a Driver-specific virtual DOM.

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
