use cbss_craft::{
    keyword, px, rgb, Contract, ErrorKind, EventKind, EventOutcome, InputEvent, Link,
    NavigationChange, NavigationChangeKind, NavigationDriver, NavigationEntry,
    NavigationScreenHost, NavigationSnapshot, Navigator, NodeState, Store, Style, Ui, ABI_VERSION,
    CAPABILITIES, CRAFT_DIAGNOSTIC_PACK, CRAFT_DIAGNOSTIC_STYLE_REPLACEMENT,
    CRAFT_PACK_MISSING_CAPABILITY, CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY,
    CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT, DRIVER_CONTRACT_VERSION,
    NAVIGATION_SCREEN_DIRTY_DOMAINS, STATUS_INVALID_ARGUMENT, STATUS_INVALID_HANDLE,
    STATUS_STYLE_ERROR,
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
fn retained_navigation_and_links_match_the_nim_contract() {
    let mut ui = Ui::new().expect("navigation Ui");
    let app = ui
        .box_node("navigation-app", None)
        .expect("navigation root");
    let mut home_root = None;
    let mut home_first = None;
    let mut home_last = None;
    ui.within(app, |scope| {
        home_root = Some(scope.box_with("home-screen", None, |screen| {
            home_first = Some(screen.box_node("home-first", None)?);
            home_last = Some(screen.box_node("home-last", None)?);
            Ok(())
        })?);
        Ok(())
    })
    .expect("home screen");
    let home_root = home_root.expect("home root");
    let home_first = home_first.expect("home first");
    let home_last = home_last.expect("home last");
    ui.set_focusable(home_first, true, 0)
        .expect("focusable home first");
    ui.set_focusable(home_last, true, 0)
        .expect("focusable home last");

    let mut settings_root = None;
    let mut settings_first = None;
    let mut settings_last = None;
    ui.within(app, |scope| {
        settings_root = Some(scope.box_with("settings-screen", None, |screen| {
            settings_first = Some(screen.box_node("settings-first", None)?);
            settings_last = Some(screen.box_node("settings-last", None)?);
            Ok(())
        })?);
        Ok(())
    })
    .expect("settings screen");
    let settings_root = settings_root.expect("settings root");
    let settings_first = settings_first.expect("settings first");
    let settings_last = settings_last.expect("settings last");
    ui.set_focusable(settings_first, true, 0)
        .expect("focusable settings first");
    ui.set_focusable(settings_last, true, 0)
        .expect("focusable settings last");

    let inactive_clicks = Rc::new(Cell::new(0));
    let observed_inactive_clicks = Rc::clone(&inactive_clicks);
    ui.on(settings_last, EventKind::CLICK, move |_| {
        observed_inactive_clicks.set(observed_inactive_clicks.get() + 1);
        EventOutcome::HANDLED
    })
    .expect("inactive click handler");

    let navigator = Navigator::stack("home".to_owned());
    let mut host = NavigationScreenHost::new(&ui, navigator.clone());
    host.register_screen("home".to_owned(), home_root, None)
        .expect("register home");
    host.register_screen("settings".to_owned(), settings_root, Some(settings_first))
        .expect("register settings");
    assert_eq!(
        host.register_screen("home".to_owned(), settings_root, None)
            .expect_err("duplicate destination must fail")
            .status_code(),
        Some(STATUS_INVALID_ARGUMENT)
    );
    assert!(host.sync().expect("initial host sync"));
    assert_eq!(
        host.active_screen()
            .expect("active home screen")
            .destination,
        "home"
    );
    assert!(!ui.inert(home_root).expect("home inert state"));
    assert!(ui.inert(settings_root).expect("settings inert state"));
    assert!(
        !ui.emit(settings_last, &InputEvent::new(EventKind::CLICK))
            .expect("inactive click")
            .handled
    );
    assert_eq!(inactive_clicks.get(), 0);

    ui.set_focus(Some(home_last), true)
        .expect("focus home last");
    assert!(navigator.push("settings".to_owned()));
    assert!(host.sync().expect("settings sync"));
    assert_eq!(ui.focused_node(), Some(settings_first));
    ui.set_focus(Some(settings_last), true)
        .expect("focus settings last");
    assert!(navigator.back());
    assert!(host.sync().expect("home back sync"));
    assert_eq!(ui.focused_node(), Some(home_last));
    assert!(navigator.forward());
    assert!(host.sync().expect("settings forward sync"));
    assert_eq!(ui.focused_node(), Some(settings_last));
    assert!(navigator.back());
    assert!(host.sync().expect("home link preparation"));

    let link = Link::mount_in(
        &mut ui,
        app,
        navigator.clone(),
        "settings".to_owned(),
        "Settings",
        false,
        None,
        None,
        "settings-link",
    )
    .expect("settings Link");
    let link_clicks = Rc::new(Cell::new(0));
    let link_bubbles = Rc::new(Cell::new(0));
    let observed_bubbles = Rc::clone(&link_bubbles);
    ui.on(app, EventKind::CLICK, move |_| {
        observed_bubbles.set(observed_bubbles.get() + 1);
        EventOutcome::HANDLED
    })
    .expect("Link bubble handler");
    let destination_seen = Rc::new(RefCell::new(String::new()));
    let observed_clicks = Rc::clone(&link_clicks);
    let observed_destination = Rc::clone(&destination_seen);
    let observed_navigator = navigator.clone();
    link.on_click(move |_| {
        observed_clicks.set(observed_clicks.get() + 1);
        *observed_destination.borrow_mut() = observed_navigator
            .current_destination()
            .expect("destination before Link default");
        EventOutcome::HANDLED
    })
    .expect("Link click handler");

    assert!(
        ui.emit(link.container(), &InputEvent::new(EventKind::CLICK))
            .expect("Link click")
            .handled
    );
    assert_eq!(link_clicks.get(), 1);
    assert_eq!(link_bubbles.get(), 1);
    assert_eq!(&*destination_seen.borrow(), "home");
    assert_eq!(navigator.current_destination().as_deref(), Some("settings"));
    assert!(host.sync().expect("Link destination sync"));

    assert!(navigator.back());
    assert!(host.sync().expect("Link Enter preparation"));
    assert!(
        ui.emit(
            link.container(),
            &InputEvent::new(EventKind::KEY_DOWN).key("Enter"),
        )
        .expect("Link Enter")
        .handled
    );
    assert_eq!(link_clicks.get(), 2);
    assert_eq!(link_bubbles.get(), 2);

    let prevented_link = Link::mount_in(
        &mut ui,
        app,
        navigator.clone(),
        "blocked".to_owned(),
        "Blocked",
        false,
        None,
        None,
        "blocked-link",
    )
    .expect("prevented Link");
    prevented_link
        .on_click(|_| EventOutcome::new(true, false, true))
        .expect("prevented Link handler");
    let before_prevented = navigator.current_destination();
    assert!(ui
        .emit(
            prevented_link.container(),
            &InputEvent::new(EventKind::CLICK),
        )
        .expect("prevented Link click")
        .outcome
        .prevents_default());
    assert_eq!(navigator.current_destination(), before_prevented);
    assert_eq!(link_bubbles.get(), 3);
    assert!(
        !ui.emit(
            prevented_link.container(),
            &InputEvent::new(EventKind::KEY_DOWN).key(" "),
        )
        .expect("Link Space")
        .handled
    );
    assert_eq!(navigator.current_destination(), before_prevented);
    assert_eq!(navigator.current_destination().as_deref(), Some("settings"));
    assert!(host.sync().expect("Link Enter destination sync"));
    link.set_label("Project settings")
        .expect("update Link label");
    assert_eq!(link.label(), "Project settings");
    assert_eq!(
        ui.text_value(link.label_node()).expect("Link label text"),
        "Project settings"
    );
    link.set_disabled(true).expect("disable Link");
    assert!(!link.activate());
    assert!(
        !ui.emit(link.container(), &InputEvent::new(EventKind::CLICK))
            .expect("disabled Link click")
            .handled
    );
    assert_eq!(link_clicks.get(), 2);
    assert_eq!(link_bubbles.get(), 3);

    assert!(host.connected());
    assert!(host.disconnect());
    assert!(!host.connected());
    assert!(navigator.back());
    assert!(!host.sync().expect("disconnected host sync"));
    host.queue_current();
    assert!(host.sync().expect("manual host sync"));
    assert_eq!(
        host.active_screen()
            .expect("active home after manual sync")
            .destination,
        "home"
    );
}

#[test]
fn craft_components_support_retained_updates_and_atomic_lifecycle() {
    let mut ui = Ui::new().expect("Ui");
    let mut label = None;
    let mut image = None;
    let events = Rc::new(Cell::new(0));
    let component_events = Rc::clone(&events);
    let mut component = ui
        .component_with("status-card", "status-card-instance", None, |component| {
            label = Some(component.text("Idle", "status-label", None)?);
            image = Some(component.image("idle.png", 16.0, 16.0, "status-icon", None)?);
            component.public_style_slot("label", label)?;
            component.public_style_slot("icon", image)?;
            component.on_root(EventKind::CHANGE, move |_event| {
                component_events.set(component_events.get() + 1);
                EventOutcome::HANDLED
            })?;
            Ok(())
        })
        .expect("status component");
    let label = label.expect("label");
    let image = image.expect("image");
    let root = component.root().expect("component root");
    assert!(component.active());
    assert_eq!(component.craft_name(), "status-card");
    assert_eq!(ui.parent(label).expect("label parent"), Some(root));
    assert_eq!(ui.text_value(label).expect("initial text"), "Idle");
    assert_eq!(ui.image_source(image).expect("initial image"), "idle.png");
    let status_component_style = r#"{
      "format":"cbss-craft-style",
      "version":1,
      "name":"status-theme",
      "rules":[{
        "selector":{"component":"status-card","slot":"root"},
        "declarations":[{
          "property":"width",
          "value":{"type":"length","unit":"px","value":180}
        }]
      }]
    }"#;
    ui.replace_craft_style(status_component_style)
        .expect("component root Craft Style");
    ui.compute(320.0, 120.0).expect("initial component layout");
    assert!((ui.rect(root).expect("component root rect").width - 180.0).abs() < 0.001);
    ui.set_text(label, "Idle").expect("unchanged Text update");
    ui.set_image(image, "idle.png", 16.0, 16.0)
        .expect("unchanged Image update");
    ui.set_state(root, NodeState::Checked, false)
        .expect("unchanged state update");
    ui.rect(label)
        .expect("unchanged retained values preserve computed layout");

    let root_id = root.native_id();
    let label_id = label.native_id();
    ui.set_text(label, "Ready").expect("retained Text update");
    ui.set_image(image, "ready.png", 20.0, 12.0)
        .expect("retained Image update");
    ui.add_group(root, "interactive").expect("retained group");
    ui.set_attribute(root, "data-status", "ready")
        .expect("retained attribute");
    ui.set_state(root, NodeState::Checked, true)
        .expect("retained state");
    assert_eq!(
        component.root().expect("retained root").native_id(),
        root_id
    );
    assert_eq!(label.native_id(), label_id);
    assert_eq!(ui.text_value(label).expect("updated text"), "Ready");
    assert_eq!(ui.image_source(image).expect("updated image"), "ready.png");
    ui.emit(root, &InputEvent::new(EventKind::CHANGE))
        .expect("retained event");
    assert_eq!(events.get(), 1);

    let children_before_failure = ui.child_count(root).expect("children before failure");
    let construction_error = ui
        .within(root, |scope| {
            scope.component_with(
                "failing-component",
                "failing-component-instance",
                None,
                |component| {
                    component.text("temporary", "temporary-label", None)?;
                    component.text("invalid\0text", "invalid-label", None)?;
                    Ok(())
                },
            )?;
            Ok(())
        })
        .expect_err("failed component must roll back");
    assert_eq!(
        construction_error.status_code(),
        Some(STATUS_INVALID_ARGUMENT)
    );
    assert_eq!(
        ui.child_count(root).expect("children after failure"),
        children_before_failure
    );

    let panic = catch_unwind(AssertUnwindSafe(|| {
        ui.within(root, |scope| {
            scope.component_with(
                "panicking-component",
                "panicking-component-instance",
                None,
                |component| {
                    component.text("temporary", "panic-label", None)?;
                    panic!("component construction panic");
                },
            )?;
            Ok(())
        })
    }));
    assert!(panic.is_err());
    assert_eq!(
        ui.child_count(root).expect("children after panic"),
        children_before_failure
    );

    let empty_name = ui
        .component_with("", "invalid-component", None, |_component| Ok(()))
        .expect_err("empty Craft name must fail");
    assert_eq!(empty_name.status_code(), Some(STATUS_INVALID_ARGUMENT));
    assert_eq!(ui.unmount(&mut component).expect("unmount component"), 3);
    assert!(!component.active());
    let inactive = component
        .root()
        .expect_err("inactive component root must fail");
    assert_eq!(inactive.status_code(), Some(STATUS_INVALID_HANDLE));
}

#[test]
fn subtree_removal_releases_driver_owned_callbacks_and_invalidates_nodes() {
    let mut ui = Ui::new().expect("Ui");
    let mut removable = None;
    let mut child = None;
    let mut survivor = None;
    let root = ui
        .box_with("lifecycle-root", None, |ui| {
            removable = Some(ui.box_with("removable", None, |ui| {
                child = Some(ui.box_node("lifecycle-child", None)?);
                Ok(())
            })?);
            survivor = Some(ui.box_node("survivor", None)?);
            Ok(())
        })
        .expect("lifecycle tree");
    let removable = removable.expect("removable subtree");
    let child = child.expect("subtree child");
    let survivor = survivor.expect("surviving sibling");

    let handler_resource = Rc::new(1_u8);
    let weak_handler_resource = Rc::downgrade(&handler_resource);
    let retained_handler_resource = Rc::clone(&handler_resource);
    ui.on(child, EventKind::CLICK, move |_event| {
        assert_eq!(*retained_handler_resource, 1);
        EventOutcome::HANDLED
    })
    .expect("subtree handler");
    drop(handler_resource);

    let subscription_resource = Rc::new(2_u8);
    let weak_subscription_resource = Rc::downgrade(&subscription_resource);
    let retained_subscription_resource = Rc::clone(&subscription_resource);
    let mut subscription = ui
        .subscribe(removable, EventKind::CHANGE, move |_event| {
            assert_eq!(*retained_subscription_resource, 2);
            EventOutcome::HANDLED
        })
        .expect("subtree subscription");
    drop(subscription_resource);

    assert!(weak_handler_resource.upgrade().is_some());
    assert!(weak_subscription_resource.upgrade().is_some());
    assert!(subscription.active());
    let surviving_observer_calls = Rc::new(Cell::new(0));
    let surviving_counter = Rc::clone(&surviving_observer_calls);
    let mut surviving_subscription = ui
        .subscribe(root, EventKind::CLICK, move |event| {
            if event.target == survivor.native_id() {
                surviving_counter.set(surviving_counter.get() + 1);
            }
            EventOutcome::HANDLED
        })
        .expect("surviving subscription");
    ui.emit(child, &InputEvent::new(EventKind::CLICK))
        .expect("handler before removal");

    assert_eq!(ui.remove_subtree(removable).expect("remove subtree"), 2);
    assert_eq!(ui.child_count(root).expect("remaining root children"), 1);
    assert_eq!(ui.parent(survivor).expect("survivor parent"), Some(root));
    assert!(!subscription.active());
    assert!(surviving_subscription.active());
    assert!(weak_handler_resource.upgrade().is_none());
    assert!(weak_subscription_resource.upgrade().is_none());
    subscription.close().expect("close removed subscription");
    ui.emit(survivor, &InputEvent::new(EventKind::CLICK))
        .expect("surviving event");
    assert_eq!(surviving_observer_calls.get(), 1);
    surviving_subscription
        .close()
        .expect("close surviving subscription");

    let stale = ui.rect(child).expect_err("removed Node must be stale");
    assert_eq!(stale.status_code(), Some(STATUS_INVALID_ARGUMENT));
    let stale_subtree = ui
        .remove_subtree(removable)
        .expect_err("removed subtree must stay stale");
    assert_eq!(stale_subtree.status_code(), Some(STATUS_INVALID_ARGUMENT));
    let mut replacement = None;
    ui.within(root, |ui| {
        replacement = Some(ui.box_node("replacement", None)?);
        Ok(())
    })
    .expect("replacement child");
    assert_ne!(
        replacement.expect("replacement").native_id(),
        child.native_id()
    );

    let mut other_ui = Ui::new().expect("other Ui");
    let foreign = other_ui.box_node("foreign", None).expect("foreign Node");
    let rejected = ui
        .remove_subtree(foreign)
        .expect_err("foreign subtree must fail");
    assert_eq!(rejected.status_code(), Some(STATUS_INVALID_HANDLE));
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
    let incompatible_pack = PACK.replace("\"minimumAbi\": 65560", "\"minimumAbi\": 4294967295");
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

#[derive(Clone, Debug, PartialEq, Eq)]
struct StoreModel {
    count: i32,
    name: String,
}

enum StoreAction {
    Increment(i32),
    Rename(String),
}

fn reduce_store(state: &mut StoreModel, action: &StoreAction) {
    match action {
        StoreAction::Increment(amount) => state.count += amount,
        StoreAction::Rename(name) => state.name.clone_from(name),
    }
}

#[test]
fn retained_store_transactions_selectors_and_failures_are_bounded() {
    let store = Store::new(
        StoreModel {
            count: 0,
            name: "ready".to_owned(),
        },
        reduce_store,
    );
    let selector_evaluations = Rc::new(Cell::new(0));
    let evaluation_counter = Rc::clone(&selector_evaluations);
    let count = store.select(move |state| {
        evaluation_counter.set(evaluation_counter.get() + 1);
        state.count
    });
    let selected_counts = Rc::new(RefCell::new(Vec::new()));
    let observed_counts = Rc::clone(&selected_counts);
    let mut count_watch = count.subscribe(move |value| {
        observed_counts.borrow_mut().push(*value);
    });

    store.dispatch(StoreAction::Increment(1));
    store.dispatch(StoreAction::Rename("done".to_owned()));
    assert_eq!(store.state().count, 1);
    assert_eq!(store.state().name, "done");
    assert_eq!(store.revision(), 2);
    assert_eq!(selector_evaluations.get(), 3);
    assert_eq!(*selected_counts.borrow(), vec![1]);

    store.transaction(|| {
        store.dispatch(StoreAction::Increment(2));
        store.transaction(|| {
            store.dispatch(StoreAction::Increment(3));
        });
    });
    assert_eq!(store.state().count, 6);
    assert_eq!(store.revision(), 3);
    assert_eq!(selector_evaluations.get(), 4);
    assert_eq!(*selected_counts.borrow(), vec![1, 6]);

    let revisions = Rc::new(RefCell::new(Vec::new()));
    let observed_revisions = Rc::clone(&revisions);
    let reentrant_store = store.clone();
    let queued_reentrant_action = Rc::new(Cell::new(false));
    let queued = Rc::clone(&queued_reentrant_action);
    let _commit_watch = store.subscribe(move |revision| {
        observed_revisions.borrow_mut().push(revision);
        if !queued.replace(true) {
            reentrant_store.dispatch(StoreAction::Increment(4));
        }
    });
    store.dispatch(StoreAction::Increment(1));
    assert_eq!(store.state().count, 11);
    assert_eq!(*revisions.borrow(), vec![4, 5]);

    let later_listener_calls = Rc::new(Cell::new(0));
    let mut failing_watch = store.subscribe(|_| panic!("listener failed"));
    let later_calls = Rc::clone(&later_listener_calls);
    let _later_watch = store.subscribe(move |_| {
        later_calls.set(later_calls.get() + 1);
    });
    let listener_failure = catch_unwind(AssertUnwindSafe(|| {
        store.dispatch(StoreAction::Rename("failure-observed".to_owned()));
    }));
    assert!(listener_failure.is_err());
    assert_eq!(later_listener_calls.get(), 1);
    assert!(failing_watch.close());
    store.dispatch(StoreAction::Rename("recovered".to_owned()));
    assert_eq!(store.state().name, "recovered");
    assert_eq!(later_listener_calls.get(), 2);

    store.dispatch_silent(&StoreAction::Increment(10));
    assert_eq!(count.value(), 11);
    count.refresh();
    assert_eq!(count.value(), 21);
    assert_eq!(selected_counts.borrow().last(), Some(&21));
    assert!(count_watch.active());
    assert!(count_watch.close());
    assert!(!count_watch.active());
    let subscribers_before_selector_dispose = store.subscriber_count();
    assert!(count.dispose());
    assert!(!count.dispose());
    assert_eq!(
        store.subscriber_count() + 1,
        subscribers_before_selector_dispose
    );
    assert!(catch_unwind(AssertUnwindSafe(|| count.refresh())).is_err());

    let transaction_failure = catch_unwind(AssertUnwindSafe(|| {
        store.transaction(|| {
            store.dispatch(StoreAction::Increment(1));
            panic!("transaction body failed");
        });
    }));
    assert!(transaction_failure.is_err());
    assert_eq!(store.state().count, 22);
}

#[test]
fn component_owned_selector_watch_updates_retained_nodes_and_detaches() {
    let store = Store::new(
        StoreModel {
            count: 0,
            name: "ready".to_owned(),
        },
        reduce_store,
    );
    let count = store.select(|state| state.count);
    let mut ui = Ui::new().expect("Ui");
    let mut label = None;
    let mut marker = None;
    let mut component = ui
        .component_with(
            "watched-counter",
            "watched-counter-instance",
            None,
            |component| {
                label = Some(component.text("pending", "count-label", None)?);
                marker = Some(component.box_node("count-marker", None)?);
                Ok(())
            },
        )
        .expect("watched component");
    let label = label.expect("label");
    let marker = marker.expect("marker");
    let retained_ui = ui.handle();
    let update_ui = retained_ui.clone();
    let watch = component
        .watch(
            &count,
            move |value| {
                update_ui
                    .set_text(label, &value.to_string())
                    .expect("update watched Text");
                update_ui
                    .set_state(marker, NodeState::Checked, value % 2 != 0)
                    .expect("update watched state");
            },
            true,
        )
        .expect("component watch");

    assert!(watch.active());
    assert_eq!(component.watch_count(), 1);
    assert_eq!(count.subscriber_count(), 1);
    assert_eq!(ui.text_value(label).expect("initial watched Text"), "0");

    store.dispatch(StoreAction::Rename("unchanged".to_owned()));
    assert_eq!(ui.text_value(label).expect("unchanged watched Text"), "0");
    store.dispatch(StoreAction::Increment(3));
    assert_eq!(ui.text_value(label).expect("updated watched Text"), "3");
    assert!(watch.close());
    assert!(!watch.close());
    assert!(!watch.active());
    assert_eq!(component.watch_count(), 0);
    assert_eq!(count.subscriber_count(), 0);

    let initial_failure = catch_unwind(AssertUnwindSafe(|| {
        let _ = component.watch(&count, |_| panic!("initial watch failed"), true);
    }));
    assert!(initial_failure.is_err());
    assert_eq!(component.watch_count(), 0);
    assert_eq!(count.subscriber_count(), 0);

    let mut foreign_ui = Ui::new().expect("foreign Ui");
    let foreign_node = foreign_ui
        .box_node("foreign-node", None)
        .expect("foreign Node");
    let foreign = retained_ui
        .set_text(foreign_node, "rejected")
        .expect_err("foreign retained Node must fail");
    assert_eq!(foreign.status_code(), Some(STATUS_INVALID_HANDLE));

    let unmount_ui = retained_ui.clone();
    let unmount_watch = component
        .watch(
            &count,
            move |value| {
                unmount_ui
                    .set_text(label, &value.to_string())
                    .expect("update before unmount");
            },
            false,
        )
        .expect("unmount watch");
    assert!(unmount_watch.active());
    assert_eq!(ui.unmount(&mut component).expect("unmount"), 3);
    assert!(!unmount_watch.active());
    assert_eq!(count.subscriber_count(), 0);
    let inactive = component
        .watch(&count, |_| {}, true)
        .expect_err("inactive component watch must fail");
    assert_eq!(inactive.status_code(), Some(STATUS_INVALID_HANDLE));

    let expired_handle;
    let expired_node;
    {
        let mut temporary_ui = Ui::new().expect("temporary Ui");
        expired_handle = temporary_ui.handle();
        let mut temporary_label = None;
        temporary_ui
            .box_with("temporary-root", None, |ui| {
                temporary_label = Some(ui.text("active", "temporary-label", None)?);
                Ok(())
            })
            .expect("temporary tree");
        expired_node = temporary_label.expect("temporary Text");
        expired_handle
            .set_text(expired_node, "updated")
            .expect("active UiHandle");
        assert!(expired_handle.active());
    }
    assert!(!expired_handle.active());
    let expired = expired_handle
        .set_text(expired_node, "late")
        .expect_err("expired UiHandle must fail");
    assert_eq!(expired.status_code(), Some(STATUS_INVALID_HANDLE));
}

#[test]
fn component_owned_selector_watch_detaches_when_component_is_dropped() {
    let store = Store::new(
        StoreModel {
            count: 0,
            name: "ready".to_owned(),
        },
        reduce_store,
    );
    let count = store.select(|state| state.count);
    let mut ui = Ui::new().expect("Ui");

    {
        let mut component = ui
            .component_with(
                "dropped-counter",
                "dropped-counter-instance",
                None,
                |component| {
                    component.text("ready", "dropped-label", None)?;
                    Ok(())
                },
            )
            .expect("component");
        let watch = component
            .watch(&count, |_| {}, false)
            .expect("component watch");
        assert!(watch.active());
        assert_eq!(count.subscriber_count(), 1);
    }

    assert_eq!(count.subscriber_count(), 0);
}

#[test]
fn retained_store_custom_selector_equality_suppresses_equivalent_values() {
    let store = Store::new(
        StoreModel {
            count: 0,
            name: "ready".to_owned(),
        },
        reduce_store,
    );
    let name = store.select_by(
        |state| state.name.clone(),
        |left, right| left.eq_ignore_ascii_case(right),
    );
    let values = Rc::new(RefCell::new(Vec::new()));
    let observed = Rc::clone(&values);
    let _watch = name.subscribe(move |value| observed.borrow_mut().push(value.clone()));

    store.dispatch(StoreAction::Rename("READY".to_owned()));
    store.dispatch(StoreAction::Rename("done".to_owned()));

    assert_eq!(*values.borrow(), vec!["done"]);
}

#[test]
fn retained_store_subscription_mutation_and_reducer_failure_recover() {
    let store = Store::new(
        StoreModel {
            count: 0,
            name: "ready".to_owned(),
        },
        reduce_store,
    );
    let removed_listener_calls = Rc::new(Cell::new(0));
    let late_listener_calls = Rc::new(Cell::new(0));
    let removed_listener = Rc::new(RefCell::new(None::<cbss_craft::StoreSubscription>));
    let late_listener = Rc::new(RefCell::new(None::<cbss_craft::StoreSubscription>));

    let removed_slot = Rc::clone(&removed_listener);
    let late_slot = Rc::clone(&late_listener);
    let late_calls = Rc::clone(&late_listener_calls);
    let subscription_source = store.clone();
    let _mutating_listener = store.subscribe(move |_| {
        if let Some(listener) = removed_slot.borrow_mut().as_mut() {
            listener.close();
        }
        if late_slot.borrow().is_none() {
            let observed = Rc::clone(&late_calls);
            late_slot
                .borrow_mut()
                .replace(subscription_source.subscribe(move |_| {
                    observed.set(observed.get() + 1);
                }));
        }
    });
    let removed_calls = Rc::clone(&removed_listener_calls);
    removed_listener
        .borrow_mut()
        .replace(store.subscribe(move |_| {
            removed_calls.set(removed_calls.get() + 1);
        }));

    store.dispatch(StoreAction::Increment(1));
    assert_eq!(removed_listener_calls.get(), 0);
    assert_eq!(late_listener_calls.get(), 0);
    store.dispatch(StoreAction::Increment(1));
    assert_eq!(late_listener_calls.get(), 1);

    let fallible = Store::new(
        StoreModel {
            count: 0,
            name: "ready".to_owned(),
        },
        |state, action| {
            if matches!(action, StoreAction::Increment(amount) if *amount < 0) {
                panic!("negative increment");
            }
            reduce_store(state, action);
        },
    );
    assert!(catch_unwind(AssertUnwindSafe(|| {
        fallible.dispatch(StoreAction::Increment(-1));
    }))
    .is_err());
    fallible.dispatch(StoreAction::Increment(3));
    assert_eq!(fallible.state().count, 3);
    assert_eq!(fallible.revision(), 1);
}

struct CloneTrackedModel {
    clones: Rc<Cell<usize>>,
    count: i32,
}

impl Clone for CloneTrackedModel {
    fn clone(&self) -> Self {
        self.clones.set(self.clones.get() + 1);
        Self {
            clones: Rc::clone(&self.clones),
            count: self.count,
        }
    }
}

#[test]
fn retained_store_commits_do_not_clone_the_complete_state() {
    let clone_count = Rc::new(Cell::new(0));
    let store = Store::new(
        CloneTrackedModel {
            clones: Rc::clone(&clone_count),
            count: 0,
        },
        |state, amount| state.count += amount,
    );
    let count = store.select(|state| state.count);

    store.dispatch(1);
    store.transaction(|| {
        store.dispatch(2);
        store.dispatch(3);
    });

    assert_eq!(count.value(), 6);
    assert_eq!(clone_count.get(), 0);
    assert_eq!(store.with_state(|state| state.count), 6);
    assert_eq!(clone_count.get(), 0);
    assert_eq!(store.state().count, 6);
    assert_eq!(clone_count.get(), 1);
}

#[test]
fn typed_navigation_preserves_history_metadata_and_snapshot_isolation() {
    let navigator = Navigator::stack("home".to_owned());
    assert_eq!(navigator.current_destination().as_deref(), Some("home"));
    assert!(!navigator.can_go_back());
    assert!(!navigator.can_go_forward());
    assert!(!navigator.back());
    assert_eq!(navigator.snapshot().revision, 0);

    let kinds = Rc::new(RefCell::new(Vec::new()));
    let destinations = Rc::new(RefCell::new(Vec::new()));
    let observed_kinds = Rc::clone(&kinds);
    let observed_destinations = Rc::clone(&destinations);
    let mut watch = navigator.subscribe(move |change| {
        observed_kinds.borrow_mut().push(change.kind);
        observed_destinations.borrow_mut().push(
            change
                .current
                .as_ref()
                .expect("current entry")
                .destination
                .clone(),
        );
        assert_eq!(change.dirty_domains, NAVIGATION_SCREEN_DIRTY_DOMAINS);
    });
    assert!(watch.active());
    assert_eq!(navigator.listener_count(), 1);

    assert!(navigator.push("projects".to_owned()));
    let projects_entry = navigator.current_entry().expect("projects entry");
    assert_eq!(projects_entry.id, 2);
    assert!(navigator.push("settings".to_owned()));
    assert!(navigator.back());
    assert_eq!(navigator.current_destination().as_deref(), Some("projects"));
    assert!(navigator.can_go_forward());
    assert!(navigator.replace("project-detail".to_owned()));
    let replaced_entry = navigator.current_entry().expect("replacement entry");
    assert_eq!(replaced_entry.id, 4);
    assert_ne!(replaced_entry.id, projects_entry.id);
    assert!(navigator.forward());
    assert_eq!(navigator.current_destination().as_deref(), Some("settings"));
    assert!(!navigator.forward());
    assert!(navigator.back());
    assert!(navigator.push("activity".to_owned()));
    assert!(!navigator.can_go_forward());
    assert!(!navigator.forward());

    let snapshot = navigator.snapshot();
    assert_eq!(snapshot.entries.len(), 3);
    assert_eq!(snapshot.entries[0].destination, "home");
    assert_eq!(snapshot.entries[1].destination, "project-detail");
    assert_eq!(snapshot.entries[2].destination, "activity");
    assert_eq!(snapshot.revision, 7);
    assert_eq!(kinds.borrow().len(), 7);
    assert_eq!(
        destinations.borrow().last().map(String::as_str),
        Some("activity")
    );

    let mut isolated = navigator.snapshot();
    isolated.entries[0].destination = "mutated-copy".to_owned();
    isolated.entries.clear();
    assert_eq!(navigator.snapshot().entries[0].destination, "home");

    assert!(watch.close());
    assert!(!watch.close());
    assert!(!watch.active());
    assert_eq!(navigator.listener_count(), 0);
}

#[test]
fn navigation_listener_mutation_failure_and_lifetime_are_deterministic() {
    let navigator = Navigator::stack(0);
    let removed_calls = Rc::new(Cell::new(0));
    let late_calls = Rc::new(Cell::new(0));
    let removed = Rc::new(RefCell::new(None::<cbss_craft::NavigationSubscription>));
    let late = Rc::new(RefCell::new(None::<cbss_craft::NavigationSubscription>));

    let removed_slot = Rc::clone(&removed);
    let late_slot = Rc::clone(&late);
    let late_counter = Rc::clone(&late_calls);
    let subscription_source = navigator.clone();
    let _mutating = navigator.subscribe(move |_| {
        if let Some(subscription) = removed_slot.borrow_mut().as_mut() {
            subscription.close();
        }
        if late_slot.borrow().is_none() {
            let observed = Rc::clone(&late_counter);
            late_slot
                .borrow_mut()
                .replace(subscription_source.subscribe(move |_| {
                    observed.set(observed.get() + 1);
                }));
        }
    });
    let removed_counter = Rc::clone(&removed_calls);
    removed.borrow_mut().replace(navigator.subscribe(move |_| {
        removed_counter.set(removed_counter.get() + 1);
    }));

    navigator.push(1);
    assert_eq!(removed_calls.get(), 1);
    assert_eq!(late_calls.get(), 0);
    navigator.push(2);
    assert_eq!(removed_calls.get(), 1);
    assert_eq!(late_calls.get(), 1);

    let later_calls = Rc::new(Cell::new(0));
    let mut failing = navigator.subscribe(|_| panic!("navigation listener failed"));
    let later_counter = Rc::clone(&later_calls);
    let _later = navigator.subscribe(move |_| later_counter.set(later_counter.get() + 1));
    let failure = catch_unwind(AssertUnwindSafe(|| navigator.push(3)));
    assert!(failure.is_err());
    assert_eq!(later_calls.get(), 1);
    assert_eq!(navigator.current_destination(), Some(3));
    assert!(failing.close());
    assert!(navigator.push(4));
    assert_eq!(later_calls.get(), 2);

    navigator.clear_listeners();
    assert_eq!(navigator.listener_count(), 0);

    let mut expired;
    {
        let temporary = Navigator::stack(0);
        expired = temporary.subscribe(|_| {});
        assert!(expired.active());
    }
    assert!(!expired.active());
    assert!(!expired.close());
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum StructuredDestination {
    Dashboard,
    Project { id: u64, tab: String },
}

#[test]
fn navigation_supports_structured_destinations_and_custom_drivers() {
    let structured = Navigator::stack(StructuredDestination::Dashboard);
    assert!(structured.push(StructuredDestination::Project {
        id: 17,
        tab: "activity".to_owned(),
    }));
    assert_eq!(
        structured.current_destination(),
        Some(StructuredDestination::Project {
            id: 17,
            tab: "activity".to_owned(),
        })
    );

    let state = Rc::new(RefCell::new(NavigationSnapshot {
        entries: vec![NavigationEntry {
            id: 41,
            destination: 10,
        }],
        current_index: Some(0),
        revision: 0,
    }));
    let snapshot_state = Rc::clone(&state);
    let push_state = Rc::clone(&state);
    let driver = NavigationDriver::new(
        move || snapshot_state.borrow().clone(),
        move |destination| {
            let mut snapshot = push_state.borrow_mut();
            let previous = snapshot.current_entry().cloned();
            snapshot.entries.push(NavigationEntry {
                id: 42,
                destination,
            });
            snapshot.current_index = Some(1);
            snapshot.revision += 1;
            Some(NavigationChange {
                kind: NavigationChangeKind::Push,
                previous,
                current: snapshot.current_entry().cloned(),
                snapshot: snapshot.clone(),
                dirty_domains: NAVIGATION_SCREEN_DIRTY_DOMAINS,
            })
        },
        |_| None,
        || None,
        || None,
    );
    let custom = Navigator::new(driver);
    assert!(custom.push(20));
    assert_eq!(custom.current_destination(), Some(20));
    assert!(!custom.replace(30));
}
