use cbss_craft::{
    keyword, px, rgb, Contract, ErrorKind, EventKind, EventOutcome, InputEvent, Style, Ui,
    ABI_VERSION, CAPABILITIES, CRAFT_DIAGNOSTIC_PACK, CRAFT_DIAGNOSTIC_STYLE_REPLACEMENT,
    CRAFT_PACK_MISSING_CAPABILITY, CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY,
    CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT, DRIVER_CONTRACT_VERSION,
    STATUS_INVALID_ARGUMENT, STATUS_INVALID_HANDLE, STATUS_STYLE_ERROR,
};
use std::cell::{Cell, RefCell};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::rc::Rc;

#[test]
fn reference_tree_matches_the_driver_contract() {
    Contract::require_authoring().expect("authoring contract");
    assert_eq!(Contract::abi_version(), ABI_VERSION);
    assert_eq!(Contract::driver_version(), DRIVER_CONTRACT_VERSION);
    assert_eq!(CAPABILITIES.len(), 18);
    assert_eq!(CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY, 7);
    assert_eq!(CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT, 1);
    assert_eq!(CRAFT_PACK_MISSING_CAPABILITY, 12);

    let missing = Contract::require(&[cbss_craft::CapabilityRequirement {
        id: u32::MAX,
        minimum_version: 1,
    }])
    .expect_err("unknown capability must fail");
    assert_eq!(missing.kind(), ErrorKind::Contract);

    let mut root_style = Style::new().expect("root Style");
    root_style
        .set("width", px(200.0))
        .and_then(|style| style.set("height", px(80.0)))
        .and_then(|style| style.set("padding", px(10.0)))
        .and_then(|style| style.set("flex-direction", keyword("row")))
        .and_then(|style| style.set("background-color", rgb(0.1, 0.2, 0.3)))
        .expect("root declarations");

    let mut child_style = Style::new().expect("child Style");
    child_style
        .set("width", px(40.0))
        .and_then(|style| style.set("height", px(30.0)))
        .and_then(|style| style.number("opacity", 0.75))
        .expect("child declarations");

    let mut ui = Ui::new().expect("Ui");
    let mut child = None;
    let mut label = None;
    let mut image = None;
    let root = ui
        .box_with("root", Some(&root_style), |ui| {
            child = Some(ui.box_with("child", Some(&child_style), |ui| {
                label = Some(ui.text("Rust Craft Driver", "label", None)?);
                image = Some(ui.image("asset.png", 12.0, 8.0, "icon", None)?);
                Ok(())
            })?);
            ui.box_node("sibling", Some(&child_style))?;
            Ok(())
        })
        .expect("reference tree");
    let child = child.expect("child");
    let label = label.expect("label");
    let image = image.expect("image");

    assert_eq!(ui.node_count(), 5);
    assert_eq!(ui.child_count(root).expect("root children"), 2);
    assert_eq!(ui.parent(child).expect("child parent"), Some(root));
    assert_eq!(ui.parent(label).expect("label parent"), Some(child));
    assert_eq!(ui.parent(image).expect("image parent"), Some(child));

    ui.compute(200.0, 80.0).expect("layout");
    let root_rect = ui.rect(root).expect("root rect");
    let child_rect = ui.rect(child).expect("child rect");
    assert!((root_rect.width - 200.0).abs() < 0.001);
    assert!((root_rect.height - 80.0).abs() < 0.001);
    assert!((child_rect.width - 40.0).abs() < 0.001);
    assert!((child_rect.height - 30.0).abs() < 0.001);

    let replaced_handler_calls = Rc::new(Cell::new(0));
    let active_handler_calls = Rc::new(Cell::new(0));
    let parent_observer_calls = Rc::new(Cell::new(0));
    let replaced_counter = Rc::clone(&replaced_handler_calls);
    ui.on(child, EventKind::CLICK, move |_event| {
        replaced_counter.set(replaced_counter.get() + 1);
        EventOutcome::HANDLED
    })
    .expect("initial click handler");
    let active_counter = Rc::clone(&active_handler_calls);
    ui.on(child, EventKind::CLICK, move |event| {
        active_counter.set(active_counter.get() + 1);
        assert_eq!(event.target, child.native_id());
        assert_eq!(event.current_target, child.native_id());
        assert_eq!(event.position, Some((18.0, 22.0)));
        EventOutcome::new(true, false, true)
    })
    .expect("replacement click handler");
    let parent_counter = Rc::clone(&parent_observer_calls);
    let mut parent_observer = ui
        .subscribe(root, EventKind::CLICK, move |event| {
            parent_counter.set(parent_counter.get() + 1);
            assert_eq!(event.target, child.native_id());
            assert_eq!(event.current_target, root.native_id());
            EventOutcome::HANDLED
        })
        .expect("parent click observer");
    let first_click = ui
        .emit(
            child,
            &InputEvent::new(EventKind::CLICK)
                .position(18.0, 22.0)
                .button(1),
        )
        .expect("first click");
    assert_eq!(first_click.target, child.native_id());
    assert!(first_click.handled);
    assert!(first_click.outcome.handled());
    assert!(first_click.outcome.prevents_default());
    assert_eq!(replaced_handler_calls.get(), 0);
    assert_eq!(active_handler_calls.get(), 1);
    assert_eq!(parent_observer_calls.get(), 1);

    parent_observer.close().expect("close parent observer");
    assert!(!parent_observer.active());
    ui.emit(child, &InputEvent::new(EventKind::CLICK))
        .expect("click after observer removal");
    assert_eq!(active_handler_calls.get(), 2);
    assert_eq!(parent_observer_calls.get(), 1);

    let copied_key = Rc::new(RefCell::new(String::new()));
    let callback_key = Rc::clone(&copied_key);
    ui.on(child, EventKind::KEY_DOWN, move |event| {
        *callback_key.borrow_mut() = event.key.clone().unwrap_or_default();
        EventOutcome::HANDLED
    })
    .expect("key handler");
    ui.emit(child, &InputEvent::new(EventKind::KEY_DOWN).key("+"))
        .expect("key event");
    assert_eq!(copied_key.borrow().as_str(), "+");

    let scoped_observer_calls = Rc::new(Cell::new(0));
    {
        let scoped_counter = Rc::clone(&scoped_observer_calls);
        let _scoped_observer = ui
            .subscribe(child, EventKind::CHANGE, move |_event| {
                scoped_counter.set(scoped_counter.get() + 1);
                EventOutcome::HANDLED
            })
            .expect("scoped observer");
        ui.emit(child, &InputEvent::new(EventKind::CHANGE))
            .expect("change with observer");
        assert_eq!(scoped_observer_calls.get(), 1);
    }
    ui.emit(child, &InputEvent::new(EventKind::CHANGE))
        .expect("change after observer drop");
    assert_eq!(scoped_observer_calls.get(), 1);

    ui.on(child, EventKind::INPUT, |_event| {
        panic!("callback failure");
    })
    .expect("panicking handler");
    let failed_callback = ui
        .emit(child, &InputEvent::new(EventKind::INPUT))
        .expect("panic is contained at the FFI boundary");
    assert!(failed_callback.outcome.handled());
    assert!(failed_callback.outcome.stops_propagation());
    assert!(failed_callback.outcome.prevents_default());
    assert!(ui.callback_panicked());

    let mut other_ui = Ui::new().expect("other Ui");
    let other_root = other_ui.box_node("other-root", None).expect("other root");
    let foreign = ui.rect(other_root).expect_err("foreign Node must fail");
    assert_eq!(foreign.status_code(), Some(STATUS_INVALID_HANDLE));

    let mut reset_observer = ui
        .subscribe(child, EventKind::CHANGE, |_event| EventOutcome::HANDLED)
        .expect("observer surviving reset token");
    ui.reset().expect("reset");
    reset_observer.close().expect("close token after reset");
    assert!(!reset_observer.active());
    let exception_root = ui.box_node("exception-root", None).expect("root");
    let panic = catch_unwind(AssertUnwindSafe(|| {
        ui.within(exception_root, |ui| {
            ui.box_with("throwing-child", None, |_ui| -> cbss_craft::Result<()> {
                panic!("stop construction");
            })?;
            Ok(())
        })
        .expect("panic must occur inside closure");
    }));
    assert!(panic.is_err());
    let mut recovered_child = None;
    ui.within(exception_root, |ui| {
        recovered_child = Some(ui.box_node("recovered-child", None)?);
        Ok(())
    })
    .expect("reuse after panic");
    assert_eq!(
        ui.parent(recovered_child.expect("recovered child"))
            .expect("recovered parent"),
        Some(exception_root)
    );

    let interior_nul = ui
        .text("invalid\0text", "invalid", None)
        .expect_err("interior NUL must fail");
    assert_eq!(interior_nul.status_code(), Some(STATUS_INVALID_ARGUMENT));

    let mut invalid_style = Style::new().expect("invalid Style");
    invalid_style
        .set("definitely-not-a-property", px(1.0))
        .expect("declaration collection remains deferred");
    let mut invalid_ui = Ui::new().expect("invalid Ui");
    invalid_ui
        .box_node("invalid-root", Some(&invalid_style))
        .expect("invalid root");
    let invalid = invalid_ui
        .compute(100.0, 100.0)
        .expect_err("unknown property must fail at resolution");
    assert_eq!(invalid.status_code(), Some(STATUS_STYLE_ERROR));

    let mut detached_observer = {
        let mut temporary_ui = Ui::new().expect("temporary Ui");
        let temporary_node = temporary_ui
            .box_node("temporary", None)
            .expect("temporary node");
        temporary_ui
            .subscribe(temporary_node, EventKind::CLICK, |_event| {
                EventOutcome::HANDLED
            })
            .expect("temporary observer")
    };
    detached_observer
        .close()
        .expect("subscription may outlive its Ui safely");
    assert!(!detached_observer.active());
}

#[test]
fn craft_style_and_pack_loading_are_atomic_and_slot_scoped() {
    const STYLE: &str = r#"{
      "format":"cbss-craft-style",
      "version":1,
      "name":"rust-theme",
      "rules":[{
        "selector":{"component":"rust-card","slot":"root"},
        "declarations":[{
          "property":"width",
          "value":{"type":"length","unit":"px","value":200}
        }]
      }]
    }"#;
    const MISSING_SLOT_STYLE: &str = r#"{
      "format":"cbss-craft-style",
      "version":1,
      "name":"rust-theme",
      "rules":[{
        "selector":{"component":"rust-card","slot":"missing"},
        "declarations":[{
          "property":"opacity",
          "value":{"type":"number","value":0.5}
        }]
      }]
    }"#;
    const PACK: &str = include_str!("../../../tests/fixtures/craft_pack/reference.json");

    let mut container_style = Style::new().expect("container Style");
    container_style
        .set("width", px(500.0))
        .and_then(|style| style.set("height", px(300.0)))
        .expect("container declarations");
    let mut owned_style = Style::new().expect("component-owned Style");
    owned_style
        .set("width", px(90.0))
        .and_then(|style| style.set("height", px(30.0)))
        .expect("component-owned declarations");

    let mut ui = Ui::new().expect("Ui");
    let mut owned = None;
    let mut replaceable = None;
    ui.box_with("craft-root", Some(&container_style), |ui| {
        owned = Some(ui.box_node("owned-card", Some(&owned_style))?);
        replaceable = Some(ui.box_node("replaceable-card", None)?);
        Ok(())
    })
    .expect("Craft component tree");
    let owned = owned.expect("owned component");
    let replaceable = replaceable.expect("replaceable component");
    ui.expose_style_slot(owned, owned, "rust-card", "root")
        .expect("owned Slot");
    ui.expose_style_slot(replaceable, replaceable, "rust-card", "root")
        .expect("replaceable Slot");

    ui.replace_craft_style(STYLE).expect("replace Craft Style");
    assert_eq!(ui.active_craft_styles(), vec!["rust-theme"]);
    ui.compute(500.0, 300.0).expect("layout with Craft Style");
    assert!((ui.rect(owned).expect("owned rect").width - 90.0).abs() < 0.001);
    assert!((ui.rect(replaceable).expect("replaceable rect").width - 200.0).abs() < 0.001);

    let rejected = ui
        .replace_craft_style(MISSING_SLOT_STYLE)
        .expect_err("undeclared Slot must fail");
    assert_eq!(rejected.status_code(), Some(STATUS_STYLE_ERROR));
    assert_eq!(ui.active_craft_styles(), vec!["rust-theme"]);
    let diagnostics = ui.craft_diagnostics().expect("Craft diagnostics");
    assert_eq!(diagnostics.len(), 1);
    assert_eq!(diagnostics[0].domain, CRAFT_DIAGNOSTIC_STYLE_REPLACEMENT);
    assert!(!diagnostics[0].path.is_empty());
    assert!(!diagnostics[0].message.is_empty());

    ui.replace_craft_pack(PACK).expect("replace Craft Pack");
    assert_eq!(
        ui.active_craft_packs(),
        vec![cbss_craft::CraftPackInfo {
            id: "org.example.dashboard".to_owned(),
            version: "1.2.0".to_owned(),
        }]
    );
    let incompatible_pack = PACK.replace("\"minimumAbi\": 65559", "\"minimumAbi\": 4294967295");
    let rejected_pack = ui
        .replace_craft_pack(&incompatible_pack)
        .expect_err("incompatible Pack must fail");
    assert_eq!(rejected_pack.status_code(), Some(STATUS_STYLE_ERROR));
    assert_eq!(ui.active_craft_packs()[0].version, "1.2.0");
    let pack_diagnostics = ui.craft_diagnostics().expect("Pack diagnostics");
    assert_eq!(pack_diagnostics.len(), 1);
    assert_eq!(pack_diagnostics[0].domain, CRAFT_DIAGNOSTIC_PACK);
    assert!(ui
        .remove_craft_pack("org.example.dashboard")
        .expect("remove Craft Pack"));
    assert!(ui.active_craft_packs().is_empty());
    assert!(ui
        .remove_craft_style("rust-theme")
        .expect("remove Craft Style"));
    assert!(ui.active_craft_styles().is_empty());
}
