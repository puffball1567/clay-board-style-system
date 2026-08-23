use cbss_craft::{
    attach_text_validation, attach_text_validation_with, attach_validation_with, cue, cue_action,
    cue_action_with_completion, cue_after, keyword, px, rgb, Command, CommandOfferResult,
    CommandPolicy, CommandStatus, Contract, CueCancel, CueCompletion, CueJoinPolicy, CueRuntime,
    CueSessionStatus, CueStartPolicy, ErrorKind, EventKind, EventOutcome, InputEvent, Link,
    NavigationChange, NavigationChangeKind, NavigationDriver, NavigationEntry,
    NavigationScreenHost, NavigationSnapshot, NavigationTransitionContext,
    NavigationTransitionPhase, NavigationTransitionSpec, Navigator, NodeState, Store, Style, Ui,
    ValidationBinding, ValidationFile, ValidationForm, ValidationPattern, ValidationReport,
    ValidationRules, ValidationTrigger, ValidationValue, ABI_VERSION, CAPABILITIES,
    CRAFT_DIAGNOSTIC_PACK, CRAFT_DIAGNOSTIC_STYLE_REPLACEMENT, CRAFT_PACK_MISSING_CAPABILITY,
    CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY, CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT,
    DRIVER_CONTRACT_VERSION, NAVIGATION_SCREEN_DIRTY_DOMAINS, STATUS_INVALID_ARGUMENT,
    STATUS_INVALID_HANDLE, STATUS_STYLE_ERROR,
};
use std::cell::{Cell, RefCell};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::rc::Rc;

#[test]
fn reference_tree_matches_the_driver_contract() {
    Contract::require_authoring().expect("authoring contract");
    assert_eq!(Contract::abi_version(), ABI_VERSION);
    assert_eq!(Contract::driver_version(), DRIVER_CONTRACT_VERSION);
    assert_eq!(CAPABILITIES.len(), 19);
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
fn navigation_screen_transitions_are_retained_deadline_driven_and_reentrant() {
    assert!(NavigationTransitionSpec::<String>::new(0.0, |_| {}).is_err());
    assert!(NavigationTransitionSpec::<String>::with_frame_interval(0.2, 0.0, |_| {}).is_err());

    let mut ui = Ui::new().expect("transition Ui");
    let app = ui.box_node("transition-app", None).expect("transition app");
    let mut home = None;
    let mut settings = None;
    let mut details = None;
    ui.within(app, |scope| {
        home = Some(scope.box_node("transition-home", None)?);
        settings = Some(scope.box_node("transition-settings", None)?);
        details = Some(scope.box_node("transition-details", None)?);
        Ok(())
    })
    .expect("transition screens");
    let home = home.expect("transition home");
    let settings = settings.expect("transition settings");
    let details = details.expect("transition details");

    let navigator = Navigator::stack("home".to_owned());
    let contexts = Rc::new(RefCell::new(
        Vec::<NavigationTransitionContext<String>>::new(),
    ));
    let observed_contexts = Rc::clone(&contexts);
    let callback_navigator = navigator.clone();
    let queued_reentrant_navigation = Rc::new(Cell::new(false));
    let callback_reentry = Rc::clone(&queued_reentrant_navigation);
    let transition = NavigationTransitionSpec::with_frame_interval(
        0.2,
        0.05,
        move |context: &NavigationTransitionContext<String>| {
            observed_contexts.borrow_mut().push(context.clone());
            if context.phase == NavigationTransitionPhase::Started
                && context.current.destination == "settings"
                && !callback_reentry.replace(true)
            {
                assert!(callback_navigator.push("details".to_owned()));
            }
        },
    )
    .expect("navigation transition");
    let host = NavigationScreenHost::with_transition(&ui, navigator.clone(), transition)
        .expect("transition host");
    host.register_screen("home".to_owned(), home, None)
        .expect("register transition home");
    host.register_screen("settings".to_owned(), settings, None)
        .expect("register transition settings");
    host.register_screen("details".to_owned(), details, None)
        .expect("register transition details");

    assert!(host.sync_at(1.0).expect("initial transition sync"));
    assert!(!host.transition_active());
    assert!(contexts.borrow().is_empty());

    assert!(navigator.push("settings".to_owned()));
    assert!(host.sync_at(2.0).expect("start settings transition"));
    assert!(host.transition_active());
    assert_eq!(navigator.current_destination().as_deref(), Some("details"));
    {
        let contexts = contexts.borrow();
        let started = contexts.last().expect("started context");
        assert_eq!(started.phase, NavigationTransitionPhase::Started);
        assert_eq!(started.kind, NavigationChangeKind::Push);
        assert_eq!(started.previous.destination, "home");
        assert_eq!(started.current.destination, "settings");
        assert_eq!(started.outgoing_root, home);
        assert_eq!(started.incoming_root, settings);
        assert_eq!(started.progress, 0.0);
    }
    assert!(ui.inert(home).expect("outgoing screen inert"));
    assert!(!ui.inert(settings).expect("incoming screen active"));
    assert!(
        (host
            .next_transition_deadline()
            .expect("transition deadline")
            - 2.05)
            .abs()
            < 1e-9
    );

    assert!(host.sync_at(2.01).expect("reentrant details sync"));
    {
        let contexts = contexts.borrow();
        assert_eq!(contexts[1].phase, NavigationTransitionPhase::Cancelled);
        assert_eq!(contexts[2].phase, NavigationTransitionPhase::Started);
        assert_eq!(contexts[2].current.destination, "details");
    }
    assert!(host.advance_transition(2.11).expect("advance details"));
    assert!(host.transition_active());
    assert_eq!(
        contexts.borrow().last().expect("advanced context").phase,
        NavigationTransitionPhase::Advanced
    );
    assert!(host.advance_transition(2.21).expect("complete details"));
    assert!(!host.transition_active());
    assert!(host.next_transition_deadline().is_none());
    assert_eq!(
        contexts.borrow().last().expect("completed context").phase,
        NavigationTransitionPhase::Completed
    );

    let contexts_before_immediate_sync = contexts.borrow().len();
    assert!(navigator.back());
    assert!(host.sync().expect("legacy immediate back sync"));
    assert!(!host.transition_active());
    assert_eq!(contexts.borrow().len(), contexts_before_immediate_sync);
    assert!(navigator.forward());
    assert!(host.sync().expect("legacy immediate forward sync"));
    assert_eq!(contexts.borrow().len(), contexts_before_immediate_sync);

    assert!(navigator.back());
    assert!(host.sync_at(3.0).expect("start cancellation transition"));
    assert!(host.set_transition(None).is_err());
    assert!(host.cancel_transition().expect("manual cancellation"));
    assert!(!host.cancel_transition().expect("idempotent cancellation"));
    host.set_transition(None).expect("disable transition");
    assert!(navigator.forward());
    assert!(host.sync_at(4.0).expect("immediate sync without spec"));
    assert!(!host.transition_active());

    let disposal_phases = Rc::new(RefCell::new(Vec::new()));
    let observed_disposal_phases = Rc::clone(&disposal_phases);
    let disposal_ui = ui.handle();
    host.set_transition(Some(
        NavigationTransitionSpec::new(0.5, move |context: &NavigationTransitionContext<String>| {
            assert_eq!(context.outgoing_root, details);
            assert_eq!(context.incoming_root, settings);
            disposal_ui
                .inert(context.outgoing_root)
                .expect("outgoing root remains valid during callback");
            disposal_ui
                .inert(context.incoming_root)
                .expect("incoming root remains valid during callback");
            observed_disposal_phases.borrow_mut().push(context.phase);
        })
        .expect("disposal transition"),
    ))
    .expect("enable disposal transition");
    assert!(navigator.back());
    assert!(host.sync_at(5.0).expect("start disposal transition"));
    assert!(host.transition_active());
    assert!(host
        .unregister_screen(&"details".to_owned(), &mut ui)
        .expect("unregister outgoing screen"));
    assert!(!host.transition_active());
    assert_eq!(
        &*disposal_phases.borrow(),
        &[
            NavigationTransitionPhase::Started,
            NavigationTransitionPhase::Cancelled
        ]
    );
    assert!(host.sync_at(f64::NAN).is_err());
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
    let incompatible_pack = PACK.replace("\"minimumAbi\": 65561", "\"minimumAbi\": 4294967295");
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

#[test]
fn validation_string_and_format_rules_match_the_canonical_runtime() {
    let pattern = ValidationPattern::compile("^[A-Za-z0-9_]+$").expect("compiled pattern");
    assert!(pattern.test("account_42").expect("pattern match"));
    assert!(!pattern.test("account-42").expect("pattern mismatch"));
    assert!(ValidationPattern::compile("[").is_err());

    let rules = ValidationRules::<String>::new()
        .required("required")
        .min_length(3, "minLength")
        .max_length(12, "maxLength")
        .not_blank("notBlank")
        .matches(pattern, "matches")
        .contains("_", "contains")
        .starts_with("ab", "startsWith")
        .ends_with("cd", "endsWith");
    assert!(rules.validate(&"ab_cd".to_owned()).is_valid);
    assert_eq!(rules.validate(&String::new()).code(), "required");
    assert_eq!(rules.validate(&"a_".to_owned()).code(), "minLength");
    assert_eq!(rules.validate(&"abc-cd".to_owned()).code(), "matches");
    assert_eq!(rules.validate(&"abcd".to_owned()).code(), "contains");
    assert_eq!(rules.validate(&"zz_cd".to_owned()).code(), "startsWith");
    assert_eq!(rules.validate(&"ab_zz".to_owned()).code(), "endsWith");
    assert!(
        ValidationRules::<String>::new()
            .exact_length(2, "length")
            .validate(&"日本".to_owned())
            .is_valid
    );
    assert!(
        ValidationRules::<String>::new()
            .optional()
            .email("email")
            .validate(&String::new())
            .is_valid
    );

    let valid_formats = [
        ValidationRules::<String>::new()
            .email("email")
            .validate(&"person+tag@example.co.jp".to_owned()),
        ValidationRules::<String>::new()
            .url("url")
            .validate(&"https://example.com/path?q=1".to_owned()),
        ValidationRules::<String>::new()
            .uuid("uuid")
            .validate(&"550e8400-e29b-41d4-a716-446655440000".to_owned()),
        ValidationRules::<String>::new()
            .ip_address("ip")
            .validate(&"2001:db8::1".to_owned()),
        ValidationRules::<String>::new()
            .date("date")
            .validate(&"2024-02-29".to_owned()),
        ValidationRules::<String>::new()
            .time("time")
            .validate(&"23:59:58.125".to_owned()),
        ValidationRules::<String>::new()
            .date_time("dateTime")
            .validate(&"2024-02-29T23:59:58Z".to_owned()),
    ];
    assert!(valid_formats.iter().all(|result| result.is_valid));
    assert!(
        !ValidationRules::<String>::new()
            .date("date")
            .validate(&"2023-02-29".to_owned())
            .is_valid
    );
}

#[test]
fn validation_numeric_comparison_collection_and_file_matrix_is_typed() {
    let numeric = ValidationRules::<f64>::new()
        .min(2.0, "min")
        .expect("minimum")
        .max(10.0, "max")
        .expect("maximum")
        .range(2.0, 10.0, "range")
        .expect("range")
        .integer("integer")
        .positive("positive")
        .finite("finite")
        .multiple_of(2.0, "multipleOf")
        .expect("multiple");
    assert!(numeric.validate(&4.0).is_valid);
    assert_eq!(numeric.validate(&1.0).code(), "min");
    assert_eq!(numeric.validate(&11.0).code(), "max");
    assert_eq!(numeric.validate(&5.0).code(), "multipleOf");
    assert!(
        !ValidationRules::<f64>::new()
            .integer("integer")
            .validate(&1.5)
            .is_valid
    );
    assert!(
        !ValidationRules::<f64>::new()
            .finite("finite")
            .validate(&f64::INFINITY)
            .is_valid
    );
    assert!(ValidationRules::<f64>::new()
        .multiple_of(0.0, "multiple")
        .is_err());

    let peer = ValidationValue::new("first".to_owned());
    let comparisons = ValidationRules::<String>::new()
        .equal_to("first".to_owned(), "equalTo")
        .not_equal_to("blocked".to_owned(), "notEqualTo")
        .one_of(vec!["first".to_owned(), "second".to_owned()], "oneOf")
        .not_one_of(vec!["blocked".to_owned()], "notOneOf")
        .same_as(peer.clone(), "sameAs");
    assert!(comparisons.validate(&"first".to_owned()).is_valid);
    assert_eq!(comparisons.dependency_references().len(), 1);
    peer.set("changed".to_owned());
    assert_eq!(comparisons.validate(&"first".to_owned()).code(), "sameAs");
    assert!(
        ValidationRules::<String>::new()
            .different_from(peer, "differentFrom")
            .validate(&"other".to_owned())
            .is_valid
    );

    let items = ValidationRules::<Vec<i32>>::new()
        .min_items(2, "minItems")
        .max_items(4, "maxItems")
        .exact_items(3, "exactItems")
        .unique_items("uniqueItems");
    assert!(items.validate(&vec![1, 2, 3]).is_valid);
    assert_eq!(items.validate(&vec![1]).code(), "minItems");
    assert_eq!(items.validate(&vec![1, 1, 2]).code(), "uniqueItems");

    let files = vec![
        ValidationFile::new("photo.PNG", 512, "image/png"),
        ValidationFile::new("icon.svg", 1024, "image/svg+xml"),
    ];
    let file_rules = ValidationRules::<Vec<ValidationFile>>::new()
        .max_file_size(1024, "maxFileSize")
        .allowed_mime_types(["image/*"], "allowedMimeTypes")
        .expect("MIME rules")
        .allowed_extensions([".png", "svg"], "allowedExtensions")
        .expect("extension rules")
        .max_files(2, "maxFiles");
    assert!(file_rules.validate(&files).is_valid);
    assert_eq!(
        file_rules
            .validate(&vec![ValidationFile::new("large.png", 1025, "image/png")])
            .code(),
        "maxFileSize"
    );
    assert_eq!(
        file_rules
            .validate(&vec![ValidationFile::new("note.txt", 1, "text/plain")])
            .code(),
        "allowedMimeTypes"
    );
    assert!(ValidationRules::<Vec<ValidationFile>>::new()
        .allowed_mime_types(["image"], "mime")
        .is_err());

    let custom =
        ValidationRules::<String>::new().custom(|value| value == "approved", "custom message");
    assert!(custom.validate(&"approved".to_owned()).is_valid);
    assert_eq!(custom.validate(&"rejected".to_owned()).code(), "custom");
}

#[test]
fn validation_binding_keeps_reporting_separate_from_current_validity() {
    let rules = ValidationRules::<String>::new().required("required");
    let mut binding = ValidationBinding::new(rules, String::new(), ValidationReport::OnBlur);
    assert!(!binding.current().is_valid);
    assert!(!binding.should_expose());
    binding.evaluate(String::new(), ValidationTrigger::Input, false);
    assert!(!binding.should_expose());
    binding.evaluate(String::new(), ValidationTrigger::Blur, false);
    assert!(binding.should_expose());
    assert_eq!(binding.validation_message(), "required");
    binding.evaluate("valid".to_owned(), ValidationTrigger::Input, false);
    assert!(binding.current().is_valid);
    assert!(!binding.should_expose());

    for trigger in [
        ValidationTrigger::Input,
        ValidationTrigger::Blur,
        ValidationTrigger::Submit,
        ValidationTrigger::Explicit,
    ] {
        let rules = ValidationRules::<String>::new().required("required");
        let mut live =
            ValidationBinding::new(rules.clone(), String::new(), ValidationReport::OnInput);
        live.evaluate(String::new(), trigger, false);
        assert_eq!(
            live.should_expose(),
            matches!(trigger, ValidationTrigger::Input | ValidationTrigger::Blur)
        );
        let mut submit = ValidationBinding::new(rules, String::new(), ValidationReport::OnSubmit);
        submit.evaluate(String::new(), trigger, false);
        assert_eq!(submit.should_expose(), trigger == ValidationTrigger::Submit);
    }
}

#[test]
fn validation_controls_and_forms_attach_to_retained_events() {
    let mut ui = Ui::new().expect("validation Ui");
    let mut form_node = None;
    let mut first = None;
    let mut second = None;
    let mut outside = None;
    ui.box_with("validation-root", None, |ui| {
        form_node = Some(ui.box_with("validation-form", None, |ui| {
            first = Some(ui.box_node("validation-first", None)?);
            second = Some(ui.box_node("validation-second", None)?);
            Ok(())
        })?);
        outside = Some(ui.box_node("validation-outside", None)?);
        Ok(())
    })
    .expect("validation form tree");
    let form_node = form_node.expect("form node");
    let first = first.expect("first control");
    let second = second.expect("second control");
    let outside = outside.expect("outside control");
    ui.set_focusable(first, true, 0).expect("first focusable");
    ui.set_focusable(second, true, 0).expect("second focusable");

    let input_observers = Rc::new(Cell::new(0));
    let invalid_events = Rc::new(Cell::new(0));
    let input_counter = Rc::clone(&input_observers);
    let _input_observer = ui
        .subscribe(first, EventKind::INPUT, move |_| {
            input_counter.set(input_counter.get() + 1);
            EventOutcome::default()
        })
        .expect("input observer");
    let first_invalid_counter = Rc::clone(&invalid_events);
    let _first_invalid = ui
        .subscribe(first, EventKind::INVALID, move |_| {
            first_invalid_counter.set(first_invalid_counter.get() + 1);
            EventOutcome::default()
        })
        .expect("first invalid observer");
    let second_invalid_counter = Rc::clone(&invalid_events);
    let _second_invalid = ui
        .subscribe(second, EventKind::INVALID, move |_| {
            second_invalid_counter.set(second_invalid_counter.get() + 1);
            EventOutcome::default()
        })
        .expect("second invalid observer");

    let first_control = attach_text_validation(
        &mut ui,
        first,
        ValidationRules::<String>::new().required("first required"),
        "",
    )
    .expect("first validation attachment");
    let second_control = attach_text_validation(
        &mut ui,
        second,
        ValidationRules::<String>::new()
            .required("second required")
            .same_as(first_control.validation_value(), "values must match"),
        "",
    )
    .expect("second validation attachment");
    let mut form = ValidationForm::new(&ui, form_node).expect("Validation Form");
    form.add(&first_control).expect("first registration");
    form.add(&second_control).expect("second registration");
    assert_eq!(form.len(), 2);
    assert!(!first_control.validation_result().is_valid);
    assert_eq!(first_control.validation_message(), "");
    assert!(!form.check_validity().expect("silent form check"));
    assert_eq!(invalid_events.get(), 0);
    assert!(!form.report_validity().expect("reported form check"));
    assert_eq!(invalid_events.get(), 2);
    assert_eq!(ui.focused_node(), Some(first));
    assert_eq!(first_control.validation_message(), "first required");

    ui.emit(first, &InputEvent::new(EventKind::INPUT).text("ready"))
        .expect("valid first input");
    assert_eq!(input_observers.get(), 1);
    assert!(first_control.validation_result().is_valid);
    assert_eq!(first_control.validation_value().with(Clone::clone), "ready");
    assert!(!form.report_validity().expect("invalid form report"));
    assert_eq!(ui.focused_node(), Some(second));

    ui.emit(second, &InputEvent::new(EventKind::INPUT).text("ready"))
        .expect("valid second input");
    assert!(form.report_validity().expect("valid form report"));
    ui.emit(first, &InputEvent::new(EventKind::INPUT).text("changed"))
        .expect("peer change");
    assert!(!second_control.validation_result().is_valid);
    assert_eq!(second_control.validation_result().code(), "sameAs");
    assert_eq!(second_control.validation_message(), "values must match");
    ui.emit(first, &InputEvent::new(EventKind::INPUT).text("ready"))
        .expect("peer restored");
    assert!(second_control.validation_result().is_valid);
    second_control
        .change("manual".to_owned())
        .expect("manual dependent change");
    assert!(!second_control.validation_result().is_valid);
    first_control
        .change("manual".to_owned())
        .expect("manual source change");
    assert!(second_control.validation_result().is_valid);

    form.set_disabled(true).expect("disable form");
    assert!(!form.check_validity().expect("disabled form check"));
    assert!(!form.report_validity().expect("disabled form report"));
    form.set_disabled(false).expect("enable form");

    second_control
        .set_disabled(true)
        .expect("disable second control");
    second_control
        .input(String::new())
        .expect("disabled input is ignored");
    assert!(second_control
        .check_validity()
        .expect("disabled control is valid"));
    assert_eq!(second_control.validation_message(), "");
    assert!(form.check_validity().expect("disabled field skipped"));
    second_control
        .set_disabled(false)
        .expect("enable second control");

    let duplicate = form
        .add(&first_control)
        .expect_err("duplicate registration must fail");
    assert_eq!(duplicate.status_code(), Some(STATUS_INVALID_ARGUMENT));
    let outside_control = attach_text_validation(
        &mut ui,
        outside,
        ValidationRules::<String>::new().required("outside required"),
        "",
    )
    .expect("outside attachment");
    let foreign = form
        .add(&outside_control)
        .expect_err("outside registration must fail");
    assert_eq!(foreign.status_code(), Some(STATUS_INVALID_ARGUMENT));
    assert!(form.remove(second));
    assert!(!form.remove(second));
    second_control
        .input("detached".to_owned())
        .expect("detached dependent input");
    assert!(!second_control.validation_result().is_valid);
    first_control
        .input("detached".to_owned())
        .expect("detached source input");
    assert!(second_control.validation_result().is_valid);
    first_control.close();
    assert!(!first_control.active());
    let closed = first_control
        .check_validity()
        .expect_err("closed Validation Control must fail");
    assert_eq!(closed.status_code(), Some(STATUS_INVALID_HANDLE));

    let mut policy_ui = Ui::new().expect("validation policy Ui");
    let mut live_node = None;
    let mut blur_node = None;
    let mut submit_node = None;
    let mut boolean_node = None;
    policy_ui
        .box_with("validation-policy-root", None, |ui| {
            live_node = Some(ui.box_node("validation-live", None)?);
            blur_node = Some(ui.box_node("validation-blur", None)?);
            submit_node = Some(ui.box_node("validation-submit", None)?);
            boolean_node = Some(ui.box_node("validation-boolean", None)?);
            Ok(())
        })
        .expect("validation policy tree");
    let live_node = live_node.expect("live node");
    let blur_node = blur_node.expect("blur node");
    let submit_node = submit_node.expect("submit node");
    let boolean_node = boolean_node.expect("boolean node");
    let live_control = attach_text_validation_with(
        &mut policy_ui,
        live_node,
        ValidationRules::<String>::new().required("live required"),
        "",
        ValidationReport::OnInput,
        EventKind::INPUT,
    )
    .expect("live validation");
    let blur_control = attach_text_validation(
        &mut policy_ui,
        blur_node,
        ValidationRules::<String>::new().required("blur required"),
        "",
    )
    .expect("blur validation");
    let submit_control = attach_text_validation_with(
        &mut policy_ui,
        submit_node,
        ValidationRules::<String>::new().required("submit required"),
        "",
        ValidationReport::OnSubmit,
        EventKind::INPUT,
    )
    .expect("submit validation");
    let boolean_control = attach_validation_with(
        &mut policy_ui,
        boolean_node,
        ValidationRules::<bool>::new().custom(|value| *value, "must be true"),
        false,
        |event| event.text.as_deref() == Some("true"),
        ValidationReport::OnInput,
        EventKind::CHANGE,
    )
    .expect("boolean validation");
    let empty_input = InputEvent::new(EventKind::INPUT).text("");
    policy_ui
        .emit(live_node, &empty_input)
        .expect("live empty input");
    policy_ui
        .emit(blur_node, &empty_input)
        .expect("blur empty input");
    policy_ui
        .emit(submit_node, &empty_input)
        .expect("submit empty input");
    assert_eq!(live_control.validation_message(), "live required");
    assert_eq!(blur_control.validation_message(), "");
    assert_eq!(submit_control.validation_message(), "");
    policy_ui
        .emit(blur_node, &InputEvent::new(EventKind::BLUR))
        .expect("blur report");
    policy_ui
        .emit(submit_node, &InputEvent::new(EventKind::BLUR))
        .expect("submit blur");
    assert_eq!(blur_control.validation_message(), "blur required");
    assert_eq!(submit_control.validation_message(), "");
    assert!(!submit_control
        .report_validity()
        .expect("explicit submit report"));
    assert_eq!(submit_control.validation_message(), "submit required");
    policy_ui
        .emit(
            boolean_node,
            &InputEvent::new(EventKind::CHANGE).text("true"),
        )
        .expect("typed change");
    assert!(boolean_control.validation_result().is_valid);
}

#[test]
fn command_policies_preserve_typed_completion_and_ordering() {
    use std::cell::RefCell;
    use std::rc::Rc;

    let sinks = Rc::new(RefCell::new(Vec::new()));
    let cancellations = Rc::new(RefCell::new(0));
    let command = Command::<i32, String, String>::with_defaults({
        let sinks = Rc::clone(&sinks);
        let cancellations = Rc::clone(&cancellations);
        move |_input, sink| {
            sinks.borrow_mut().push(sink);
            let cancellations = Rc::clone(&cancellations);
            Some(Box::new(move || *cancellations.borrow_mut() += 1))
        }
    })
    .expect("latest-only Command");
    let successes = Rc::new(RefCell::new(Vec::new()));
    command
        .on_success({
            let successes = Rc::clone(&successes);
            move |value| successes.borrow_mut().push(value)
        })
        .expect("success callback");

    let first = command.run(1).expect("first run");
    let second = command.run(2).expect("second run");
    assert_eq!(first.status(), CommandStatus::Cancelled);
    assert_eq!(second.status(), CommandStatus::Running);
    assert_eq!(*cancellations.borrow(), 1);
    assert_eq!(
        sinks.borrow()[0].succeed("stale".to_owned()),
        CommandOfferResult::Accepted
    );
    assert_eq!(
        sinks.borrow()[1].succeed("current".to_owned()),
        CommandOfferResult::Accepted
    );
    assert_eq!(command.pump_all(), 2);
    assert_eq!(&*successes.borrow(), &["current"]);
    assert_eq!(second.status(), CommandStatus::Succeeded);

    let ordered_sinks = Rc::new(RefCell::new(Vec::new()));
    let ordered = Command::<i32, String, String>::new(
        {
            let ordered_sinks = Rc::clone(&ordered_sinks);
            move |_input, sink| {
                ordered_sinks.borrow_mut().push(sink);
                None
            }
        },
        CommandPolicy::Ordered,
        2,
        1024,
    )
    .expect("ordered Command");
    let first = ordered.run(1).expect("first ordered run");
    let second = ordered.run(2).expect("second ordered run");
    let third = ordered.run(3).expect("third ordered run");
    assert_eq!(first.status(), CommandStatus::Running);
    assert_eq!(second.status(), CommandStatus::Queued);
    assert_eq!(third.status(), CommandStatus::Queued);
    assert_eq!(ordered.queued_count(), 2);
    assert_eq!(
        ordered_sinks.borrow()[0].succeed("one".to_owned()),
        CommandOfferResult::Accepted
    );
    assert_eq!(ordered.pump(1), 1);
    assert_eq!(second.status(), CommandStatus::Running);
    assert_eq!(
        ordered_sinks.borrow()[1].fail("two".to_owned()),
        CommandOfferResult::Accepted
    );
    assert_eq!(ordered.pump(1), 1);
    assert_eq!(second.status(), CommandStatus::Failed);
    assert_eq!(third.status(), CommandStatus::Running);
    assert_eq!(
        ordered_sinks.borrow()[2].succeed("three".to_owned()),
        CommandOfferResult::Accepted
    );
    assert_eq!(ordered.pump(1), 1);
    assert!(!ordered.pending());
}

#[test]
fn command_backpressure_observers_worker_delivery_and_disposal_are_bounded() {
    use std::cell::RefCell;
    use std::rc::Rc;
    use std::sync::mpsc;

    let (sender, receiver) = mpsc::channel();
    let command = Command::<i32, i32, String>::new(
        move |_input, sink| {
            sender.send(sink).expect("send worker sink");
            None
        },
        CommandPolicy::Concurrent,
        1,
        8,
    )
    .expect("concurrent Command");
    let first = command.run(1).expect("first concurrent run");
    let second = command.run(2).expect("second concurrent run");
    let first_sink = receiver.recv().expect("first sink");
    let second_sink = receiver.recv().expect("second sink");
    let worker = std::thread::spawn(move || {
        assert_eq!(
            first_sink.succeed_weighted(10, 8),
            CommandOfferResult::Accepted
        );
        assert_eq!(second_sink.succeed(20), CommandOfferResult::Backpressure);
        second_sink
    });
    let second_sink = worker.join().expect("worker completion");
    assert_eq!(first.status(), CommandStatus::Running);
    assert_eq!(command.pump(1), 1);
    assert_eq!(first.status(), CommandStatus::Succeeded);
    assert_eq!(second_sink.succeed(20), CommandOfferResult::Accepted);

    let observed = Rc::new(RefCell::new(Vec::new()));
    let subscription = command
        .observe_run(&second, {
            let observed = Rc::clone(&observed);
            move |ticket, status| observed.borrow_mut().push((ticket.id(), status))
        })
        .expect("run observer");
    assert!(subscription.active());
    assert_eq!(command.pump_all(), 1);
    assert_eq!(
        &*observed.borrow(),
        &[(second.id(), CommandStatus::Succeeded)]
    );
    assert!(!subscription.active());

    let immediate = Rc::new(RefCell::new(None));
    let terminal = command
        .observe_run(&second, {
            let immediate = Rc::clone(&immediate);
            move |_ticket, status| *immediate.borrow_mut() = Some(status)
        })
        .expect("terminal observer");
    assert!(!terminal.active());
    assert_eq!(*immediate.borrow(), Some(CommandStatus::Succeeded));

    let disposable_sink = Rc::new(RefCell::new(None));
    let cancellations = Rc::new(RefCell::new(0));
    let disposable = Command::<i32, i32, String>::with_defaults({
        let disposable_sink = Rc::clone(&disposable_sink);
        let cancellations = Rc::clone(&cancellations);
        move |_input, sink| {
            disposable_sink.borrow_mut().replace(sink);
            let cancellations = Rc::clone(&cancellations);
            Some(Box::new(move || *cancellations.borrow_mut() += 1))
        }
    })
    .expect("disposable Command");
    let ticket = disposable.run(1).expect("disposable run");
    assert!(disposable.dispose());
    assert!(!disposable.dispose());
    assert_eq!(ticket.status(), CommandStatus::Cancelled);
    assert_eq!(*cancellations.borrow(), 1);
    assert_eq!(
        disposable_sink
            .borrow()
            .as_ref()
            .expect("retained sink")
            .succeed(1),
        CommandOfferResult::Disposed
    );
    assert_eq!(disposable.pump_all(), 0);

    assert!(Command::<i32, i32, String>::new(
        |_input, _sink| None,
        CommandPolicy::LatestOnly,
        0,
        1,
    )
    .is_err());
}

#[test]
fn command_cancellation_and_foreign_tickets_preserve_queue_state() {
    let sinks = Rc::new(RefCell::new(Vec::new()));
    let cancellations = Rc::new(Cell::new(0));
    let command = Command::<i32, i32, String>::new(
        {
            let sinks = Rc::clone(&sinks);
            let cancellations = Rc::clone(&cancellations);
            move |_input, sink| {
                sinks.borrow_mut().push(sink);
                let cancellations = Rc::clone(&cancellations);
                Some(Box::new(move || cancellations.set(cancellations.get() + 1)))
            }
        },
        CommandPolicy::Ordered,
        8,
        1024,
    )
    .expect("ordered Command");
    let first = command.run(1).expect("first run");
    let second = command.run(2).expect("second run");
    let third = command.run(3).expect("third run");

    assert!(command.cancel(&second));
    assert_eq!(second.status(), CommandStatus::Cancelled);
    assert!(command.cancel(&first));
    assert_eq!(first.status(), CommandStatus::Cancelled);
    assert_eq!(third.status(), CommandStatus::Running);
    assert_eq!(command.cancel_all(), 1);
    assert_eq!(third.status(), CommandStatus::Cancelled);
    assert_eq!(cancellations.get(), 2);
    assert!(!command.cancel(&first));
    assert!(!command.pending());

    let foreign = Command::<i32, i32, String>::with_defaults(|_, _| None).expect("foreign Command");
    let foreign_ticket = foreign.run(1).expect("foreign run");
    assert!(!command.cancel(&foreign_ticket));
    assert!(command.observe_run(&foreign_ticket, |_, _| {}).is_err());
}

#[test]
fn command_callback_and_executor_panics_do_not_wedge_dispatch() {
    let sinks = Rc::new(RefCell::new(Vec::new()));
    let command = Command::<i32, i32, String>::new(
        {
            let sinks = Rc::clone(&sinks);
            move |_input, sink| {
                sinks.borrow_mut().push(sink);
                None
            }
        },
        CommandPolicy::Concurrent,
        4,
        1024,
    )
    .expect("concurrent Command");
    let callback_count = Rc::new(Cell::new(0));
    command
        .on_success({
            let callback_count = Rc::clone(&callback_count);
            move |value| {
                callback_count.set(callback_count.get() + 1);
                if value == 1 {
                    panic!("first callback failed");
                }
            }
        })
        .expect("success callback");
    let first = command.run(1).expect("first run");
    let second = command.run(2).expect("second run");
    assert_eq!(sinks.borrow()[0].succeed(1), CommandOfferResult::Accepted);
    assert_eq!(sinks.borrow()[1].succeed(2), CommandOfferResult::Accepted);
    assert!(catch_unwind(AssertUnwindSafe(|| command.pump_all())).is_err());
    assert_eq!(callback_count.get(), 2);
    assert_eq!(first.status(), CommandStatus::Succeeded);
    assert_eq!(second.status(), CommandStatus::Succeeded);
    assert!(!command.pending());

    let ordered_sinks = Rc::new(RefCell::new(Vec::new()));
    let attempts = Rc::new(Cell::new(0));
    let ordered = Command::<i32, i32, String>::new(
        {
            let ordered_sinks = Rc::clone(&ordered_sinks);
            let attempts = Rc::clone(&attempts);
            move |input, sink| {
                attempts.set(attempts.get() + 1);
                if input == 2 {
                    panic!("queued executor failed");
                }
                ordered_sinks.borrow_mut().push(sink);
                None
            }
        },
        CommandPolicy::Ordered,
        4,
        1024,
    )
    .expect("ordered Command");
    let first = ordered.run(1).expect("first ordered run");
    let second = ordered.run(2).expect("second ordered run");
    let third = ordered.run(3).expect("third ordered run");
    assert_eq!(
        ordered_sinks.borrow()[0].succeed(1),
        CommandOfferResult::Accepted
    );
    assert!(catch_unwind(AssertUnwindSafe(|| ordered.pump_all())).is_err());
    assert_eq!(first.status(), CommandStatus::Succeeded);
    assert_eq!(second.status(), CommandStatus::Cancelled);
    assert_eq!(third.status(), CommandStatus::Running);
    assert_eq!(attempts.get(), 3);
    assert_eq!(
        ordered_sinks.borrow()[1].succeed(3),
        CommandOfferResult::Accepted
    );
    assert_eq!(ordered.pump_all(), 1);
    assert!(!ordered.pending());
}

#[test]
fn command_observer_lifetime_wake_coalescing_and_disposal_are_deterministic() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    let sinks = Rc::new(RefCell::new(Vec::new()));
    let command = Command::<i32, i32, String>::new(
        {
            let sinks = Rc::clone(&sinks);
            move |_input, sink| {
                sinks.borrow_mut().push(sink);
                None
            }
        },
        CommandPolicy::Concurrent,
        4,
        1024,
    )
    .expect("concurrent Command");
    let wake_count = Arc::new(AtomicUsize::new(0));
    command.set_wake_callback({
        let wake_count = Arc::clone(&wake_count);
        move || {
            wake_count.fetch_add(1, Ordering::Relaxed);
        }
    });
    let observed = Rc::new(Cell::new(0));
    let first = command.run(1).expect("first run");
    {
        let subscription = command
            .observe_run(&first, {
                let observed = Rc::clone(&observed);
                move |_, _| observed.set(observed.get() + 1)
            })
            .expect("observer");
        assert!(subscription.active());
    }
    let second = command.run(2).expect("second run");
    assert_eq!(sinks.borrow()[0].succeed(1), CommandOfferResult::Accepted);
    assert_eq!(sinks.borrow()[1].succeed(2), CommandOfferResult::Accepted);
    assert_eq!(wake_count.load(Ordering::Relaxed), 1);
    assert_eq!(command.pump_all(), 2);
    assert_eq!(observed.get(), 0);
    assert_eq!(first.status(), CommandStatus::Succeeded);
    assert_eq!(second.status(), CommandStatus::Succeeded);

    let third = command.run(3).expect("third run");
    assert_eq!(sinks.borrow()[2].succeed(3), CommandOfferResult::Accepted);
    assert_eq!(wake_count.load(Ordering::Relaxed), 2);
    assert_eq!(command.pump_all(), 1);
    assert_eq!(third.status(), CommandStatus::Succeeded);

    let disposable_sinks = Rc::new(RefCell::new(Vec::new()));
    let disposable = Command::<i32, i32, String>::new(
        {
            let disposable_sinks = Rc::clone(&disposable_sinks);
            move |_input, sink| {
                disposable_sinks.borrow_mut().push(sink);
                None
            }
        },
        CommandPolicy::Ordered,
        4,
        1024,
    )
    .expect("disposable Command");
    let active = disposable.run(1).expect("active run");
    let queued = disposable.run(2).expect("queued run");
    let _panicking_observer = disposable
        .observe_run(&active, |_, _| panic!("observer failed during disposal"))
        .expect("active observer");
    assert!(disposable.dispose());
    assert_eq!(active.status(), CommandStatus::Cancelled);
    assert_eq!(queued.status(), CommandStatus::Cancelled);
    assert_eq!(disposable.active_count(), 0);
    assert_eq!(disposable.queued_count(), 0);
}

#[test]
fn command_large_concurrent_sets_complete_in_reverse_order() {
    const RUN_COUNT: usize = 2_000;
    let sinks = Rc::new(RefCell::new(Vec::with_capacity(RUN_COUNT)));
    let command = Command::<usize, usize, String>::new(
        {
            let sinks = Rc::clone(&sinks);
            move |_input, sink| {
                sinks.borrow_mut().push(sink);
                None
            }
        },
        CommandPolicy::Concurrent,
        RUN_COUNT,
        RUN_COUNT,
    )
    .expect("large concurrent Command");
    let completed = Rc::new(RefCell::new(Vec::with_capacity(RUN_COUNT)));
    command
        .on_success({
            let completed = Rc::clone(&completed);
            move |value| completed.borrow_mut().push(value)
        })
        .expect("success callback");
    for value in 0..RUN_COUNT {
        command.run(value).expect("concurrent run");
    }
    assert_eq!(command.active_count(), RUN_COUNT);
    for value in (0..RUN_COUNT).rev() {
        assert_eq!(
            sinks.borrow()[value].succeed(value),
            CommandOfferResult::Accepted
        );
    }
    assert_eq!(command.pump_all(), RUN_COUNT);
    assert_eq!(command.active_count(), 0);
    assert_eq!(completed.borrow()[0], RUN_COUNT - 1);
    assert_eq!(completed.borrow()[RUN_COUNT - 1], 0);
}

#[test]
fn cue_serial_parallel_join_and_delayed_clock_match_canonical_runtime() {
    let runtime = CueRuntime::default();
    let events = Rc::new(RefCell::new(Vec::new()));
    let graph = cue(cue_action("A", {
        let events = Rc::clone(&events);
        move || events.borrow_mut().push("A")
    })
    .expect("A"))
    .then(
        cue_action("B", {
            let events = Rc::clone(&events);
            move || events.borrow_mut().push("B")
        })
        .expect("B"),
    )
    .and_then(|graph| {
        graph.then(
            cue_action("C", {
                let events = Rc::clone(&events);
                move || events.borrow_mut().push("C")
            })
            .expect("C"),
        )
    })
    .expect("serial graph");
    let serial = runtime
        .start(&graph, CueStartPolicy::Restart)
        .expect("serial session");
    assert_eq!(*events.borrow(), vec!["A", "B", "C"]);
    assert_eq!(serial.status(), CueSessionStatus::Succeeded);
    assert_eq!(runtime.active_count(), 0);
    assert_eq!(runtime.next_deadline(), None);

    let completions = Rc::new(RefCell::new(Vec::<CueCompletion>::new()));
    let cancellations = Rc::new(Cell::new(0));
    let deferred = |name: &str| {
        cue_action_with_completion(name.to_owned(), {
            let completions = Rc::clone(&completions);
            let cancellations = Rc::clone(&cancellations);
            move |completion| {
                completions.borrow_mut().push(completion);
                let cancellation = Rc::clone(&cancellations);
                Some(Box::new(move || cancellation.set(cancellation.get() + 1)) as CueCancel)
            }
        })
        .expect("deferred action")
    };
    let tail_runs = Rc::new(Cell::new(0));
    let parallel = cue(cue_action("start", || {}).expect("start"))
        .then_parallel(vec![deferred("first"), deferred("second")])
        .and_then(|graph| {
            graph.then(
                cue_action("tail", {
                    let tail_runs = Rc::clone(&tail_runs);
                    move || tail_runs.set(tail_runs.get() + 1)
                })
                .expect("tail"),
            )
        })
        .expect("parallel graph");
    let parallel_session = runtime
        .start(&parallel, CueStartPolicy::Restart)
        .expect("parallel session");
    assert_eq!(completions.borrow().len(), 2);
    let first_completion = completions.borrow()[0].clone();
    first_completion.succeed();
    assert_eq!(tail_runs.get(), 0);
    let second_completion = completions.borrow()[1].clone();
    second_completion.succeed();
    assert_eq!(tail_runs.get(), 1);
    assert_eq!(parallel_session.status(), CueSessionStatus::Succeeded);
    assert_eq!(cancellations.get(), 0);

    let clock = CueRuntime::new(10.0).expect("clock runtime");
    let delayed_events = Rc::new(RefCell::new(Vec::new()));
    let delayed = cue(cue_action("start", {
        let delayed_events = Rc::clone(&delayed_events);
        move || delayed_events.borrow_mut().push("start")
    })
    .expect("start"))
    .then_stage(
        vec![
            cue_after(
                0.5,
                cue_action("half", {
                    let delayed_events = Rc::clone(&delayed_events);
                    move || delayed_events.borrow_mut().push("half")
                })
                .expect("half"),
            )
            .expect("half delay"),
            cue_after(
                2.0,
                cue_action("two", {
                    let delayed_events = Rc::clone(&delayed_events);
                    move || delayed_events.borrow_mut().push("two")
                })
                .expect("two"),
            )
            .expect("two delay"),
        ],
        CueJoinPolicy::All,
    )
    .expect("delayed graph");
    let delayed_session = clock
        .start(&delayed, CueStartPolicy::Restart)
        .expect("delayed session");
    assert_eq!(clock.next_deadline(), Some(10.5));
    clock.tick(10.5).expect("half deadline");
    assert_eq!(*delayed_events.borrow(), vec!["start", "half"]);
    clock.pause();
    clock.tick(20.0).expect("paused tick");
    assert_eq!(clock.now(), 10.5);
    assert_eq!(clock.next_deadline(), None);
    clock.resume();
    clock.set_rate(2.0).expect("double rate");
    assert_eq!(clock.next_deadline(), Some(20.75));
    clock.tick(20.75).expect("two deadline");
    assert_eq!(delayed_session.status(), CueSessionStatus::Succeeded);
    assert!(clock.tick(20.0).is_err());
}

#[test]
fn cue_any_race_panics_and_late_completions_are_contained() {
    let runtime = CueRuntime::default();
    let completions = Rc::new(RefCell::new(Vec::<CueCompletion>::new()));
    let cancellations = Rc::new(Cell::new(0));
    let deferred = |name: &str| {
        cue_action_with_completion(name.to_owned(), {
            let completions = Rc::clone(&completions);
            let cancellations = Rc::clone(&cancellations);
            move |completion| {
                completions.borrow_mut().push(completion);
                let cancellation = Rc::clone(&cancellations);
                Some(Box::new(move || cancellation.set(cancellation.get() + 1)) as CueCancel)
            }
        })
        .expect("deferred action")
    };
    let tail_runs = Rc::new(Cell::new(0));
    let graph = cue(cue_action("start", || {}).expect("start"))
        .then_any(vec![
            deferred("failed"),
            deferred("winner"),
            deferred("pending"),
        ])
        .and_then(|graph| {
            graph.then(
                cue_action("tail", {
                    let tail_runs = Rc::clone(&tail_runs);
                    move || tail_runs.set(tail_runs.get() + 1)
                })
                .expect("tail"),
            )
        })
        .expect("any graph");
    let session = runtime
        .start(&graph, CueStartPolicy::Restart)
        .expect("any session");
    completions.borrow()[0]
        .fail("not this one")
        .expect("failure");
    completions.borrow()[1].succeed();
    assert_eq!(session.status(), CueSessionStatus::Succeeded);
    assert_eq!(tail_runs.get(), 1);
    assert_eq!(cancellations.get(), 1);
    let third_completion = completions.borrow()[2].clone();
    third_completion.succeed();
    assert_eq!(tail_runs.get(), 1);

    completions.borrow_mut().clear();
    let race = cue(cue_action("start", || {}).expect("start"))
        .then_race(vec![deferred("loser"), deferred("pending")])
        .expect("race graph");
    let race_session = runtime
        .start(&race, CueStartPolicy::Restart)
        .expect("race session");
    completions.borrow()[0]
        .fail("network unavailable")
        .expect("race failure");
    assert_eq!(race_session.status(), CueSessionStatus::Failed);
    assert_eq!(race_session.failure(), "network unavailable");

    let panic_cancellations = Rc::new(Cell::new(0));
    let throwing = cue_action_with_completion("throwing", |_| -> Option<CueCancel> {
        panic!("action crashed")
    })
    .expect("throwing action");
    let pending = cue_action_with_completion("pending", {
        let panic_cancellations = Rc::clone(&panic_cancellations);
        move |_| {
            let cancellation = Rc::clone(&panic_cancellations);
            Some(Box::new(move || cancellation.set(cancellation.get() + 1)))
        }
    })
    .expect("pending action");
    let panic_graph = cue(cue_action("start", || {}).expect("start"))
        .then_parallel(vec![throwing, pending])
        .expect("panic graph");
    let panic_session = runtime
        .start(&panic_graph, CueStartPolicy::Restart)
        .expect("panic session");
    assert_eq!(panic_session.status(), CueSessionStatus::Failed);
    assert_eq!(panic_session.failure(), "Cue action panicked");
    assert_eq!(panic_cancellations.get(), 1);
}

#[test]
fn cue_start_policies_queue_cancellation_and_disposal_are_deterministic() {
    let runtime = CueRuntime::default();
    let completions = Rc::new(RefCell::new(Vec::<CueCompletion>::new()));
    let cancellations = Rc::new(Cell::new(0));
    let action = cue_action_with_completion("pending", {
        let completions = Rc::clone(&completions);
        let cancellations = Rc::clone(&cancellations);
        move |completion| {
            completions.borrow_mut().push(completion);
            let cancellation = Rc::clone(&cancellations);
            Some(Box::new(move || cancellation.set(cancellation.get() + 1)))
        }
    })
    .expect("pending action");
    let graph = cue(action);
    let first = runtime
        .start(&graph, CueStartPolicy::Parallel)
        .expect("first");
    let ignored = runtime
        .start(&graph, CueStartPolicy::Ignore)
        .expect("ignored");
    let parallel = runtime
        .start(&graph, CueStartPolicy::Parallel)
        .expect("parallel");
    let queued = runtime
        .start(&graph, CueStartPolicy::Queue)
        .expect("queued");
    assert_eq!(ignored.id(), first.id());
    assert_ne!(parallel.id(), first.id());
    assert_eq!(queued.status(), CueSessionStatus::Queued);
    let replacement = runtime
        .start(&graph, CueStartPolicy::Restart)
        .expect("replacement");
    assert_eq!(first.status(), CueSessionStatus::Cancelled);
    assert_eq!(parallel.status(), CueSessionStatus::Cancelled);
    assert_eq!(queued.status(), CueSessionStatus::Cancelled);
    assert_eq!(replacement.status(), CueSessionStatus::Running);
    assert_eq!(cancellations.get(), 2);
    assert!(graph
        .clone()
        .then(cue_action("late", || {}).expect("late"))
        .is_err());
    assert!(cue_after(-1.0, cue_action("invalid", || {}).expect("invalid")).is_err());

    assert!(runtime.dispose());
    assert_eq!(replacement.status(), CueSessionStatus::Cancelled);
    assert_eq!(cancellations.get(), 3);
    completions
        .borrow()
        .last()
        .expect("late completion")
        .succeed();
    assert_eq!(replacement.status(), CueSessionStatus::Cancelled);
    assert!(!runtime.cancel(&replacement));
    assert!(!runtime.dispose());
}

#[test]
fn cue_large_synchronous_and_parallel_graphs_do_not_recurse_or_rescan() {
    const ACTION_COUNT: usize = 5_000;
    let runtime = CueRuntime::default();
    let runs = Rc::new(Cell::new(0));
    let action = cue_action("increment", {
        let runs = Rc::clone(&runs);
        move || runs.set(runs.get() + 1)
    })
    .expect("increment");
    let mut graph = cue(action.clone());
    for _ in 1..ACTION_COUNT {
        graph = graph.then(action.clone()).expect("append action");
    }
    let session = runtime
        .start(&graph, CueStartPolicy::Restart)
        .expect("large serial session");
    assert_eq!(runs.get(), ACTION_COUNT);
    assert_eq!(session.status(), CueSessionStatus::Succeeded);

    let completions = Rc::new(RefCell::new(Vec::<CueCompletion>::new()));
    let pending = cue_action_with_completion("parallel", {
        let completions = Rc::clone(&completions);
        move |completion| {
            completions.borrow_mut().push(completion);
            None
        }
    })
    .expect("parallel action");
    let branches = (0..ACTION_COUNT)
        .map(|_| cbss_craft::cue_branch(pending.clone(), 0.0).expect("branch"))
        .collect();
    let parallel = cue(cue_action("start", || {}).expect("start"))
        .then_stage(branches, CueJoinPolicy::All)
        .expect("large parallel graph");
    let parallel_session = runtime
        .start(&parallel, CueStartPolicy::Restart)
        .expect("large parallel session");
    assert_eq!(completions.borrow().len(), ACTION_COUNT);
    for completion in completions.borrow().iter() {
        completion.succeed();
    }
    assert_eq!(parallel_session.status(), CueSessionStatus::Succeeded);
    assert_eq!(runtime.active_count(), 0);
}

#[test]
fn component_owned_cue_runtimes_cancel_on_unmount_and_drop() {
    let mut ui = Ui::new().expect("Ui");
    let mut component = ui
        .component_with("owned-cue", "owned-cue", None, |_scope| Ok(()))
        .expect("component");
    assert!(component.cue_runtime_at(f64::NAN).is_err());
    assert_eq!(component.cue_runtime_count(), 0);
    let runtime = component.cue_runtime().expect("owned Cue runtime");
    let cancellation_count = Rc::new(Cell::new(0));
    let graph = cue(cue_action_with_completion("pending", {
        let cancellation_count = Rc::clone(&cancellation_count);
        move |_| {
            let cancellation_count = Rc::clone(&cancellation_count);
            Some(Box::new(move || {
                cancellation_count.set(cancellation_count.get() + 1)
            }))
        }
    })
    .expect("pending action"));
    let session = runtime
        .start(&graph, CueStartPolicy::Restart)
        .expect("owned Cue session");
    assert_eq!(component.cue_runtime_count(), 1);
    assert_eq!(ui.unmount(&mut component).expect("unmount"), 1);
    assert!(!runtime.active());
    assert_eq!(session.status(), CueSessionStatus::Cancelled);
    assert_eq!(cancellation_count.get(), 1);
    assert_eq!(component.cue_runtime_count(), 0);
    assert!(component.cue_runtime().is_err());

    let dropped_runtime;
    let dropped_session;
    let dropped_cancellations = Rc::new(Cell::new(0));
    {
        let mut dropped = ui
            .component_with("dropped-cue", "dropped-cue", None, |_scope| Ok(()))
            .expect("dropped component");
        dropped_runtime = dropped.cue_runtime().expect("dropped runtime");
        let graph = cue(cue_action_with_completion("pending", {
            let dropped_cancellations = Rc::clone(&dropped_cancellations);
            move |_| {
                let dropped_cancellations = Rc::clone(&dropped_cancellations);
                Some(Box::new(move || {
                    dropped_cancellations.set(dropped_cancellations.get() + 1)
                }))
            }
        })
        .expect("pending action"));
        dropped_session = dropped_runtime
            .start(&graph, CueStartPolicy::Restart)
            .expect("dropped session");
    }
    assert!(!dropped_runtime.active());
    assert_eq!(dropped_session.status(), CueSessionStatus::Cancelled);
    assert_eq!(dropped_cancellations.get(), 1);
}

#[test]
fn cue_fifo_equal_deadlines_and_cancel_failures_are_deterministic() {
    let runtime = CueRuntime::default();
    let completions = Rc::new(RefCell::new(Vec::<CueCompletion>::new()));
    let graph = cue(cue_action_with_completion("fifo", {
        let completions = Rc::clone(&completions);
        move |completion| {
            completions.borrow_mut().push(completion);
            None
        }
    })
    .expect("FIFO action"));
    let first = runtime
        .start(&graph, CueStartPolicy::Restart)
        .expect("first");
    let second = runtime
        .start(&graph, CueStartPolicy::Queue)
        .expect("second");
    let third = runtime.start(&graph, CueStartPolicy::Queue).expect("third");
    assert_eq!(completions.borrow().len(), 1);
    let first_completion = completions.borrow()[0].clone();
    first_completion.succeed();
    assert_eq!(first.status(), CueSessionStatus::Succeeded);
    assert_eq!(second.status(), CueSessionStatus::Running);
    assert_eq!(third.status(), CueSessionStatus::Queued);
    assert_eq!(completions.borrow().len(), 2);
    let second_completion = completions.borrow()[1].clone();
    second_completion.succeed();
    assert_eq!(second.status(), CueSessionStatus::Succeeded);
    assert_eq!(third.status(), CueSessionStatus::Running);
    assert_eq!(completions.borrow().len(), 3);
    let third_completion = completions.borrow()[2].clone();
    third_completion.succeed();
    assert_eq!(third.status(), CueSessionStatus::Succeeded);

    let deadline_runtime = CueRuntime::default();
    let deadline_order = Rc::new(RefCell::new(Vec::new()));
    let delayed = cue(cue_action("start", || {}).expect("start"))
        .then_stage(
            vec![
                cue_after(
                    1.0,
                    cue_action("first", {
                        let deadline_order = Rc::clone(&deadline_order);
                        move || deadline_order.borrow_mut().push(1)
                    })
                    .expect("first"),
                )
                .expect("first delay"),
                cue_after(
                    1.0,
                    cue_action("second", {
                        let deadline_order = Rc::clone(&deadline_order);
                        move || deadline_order.borrow_mut().push(2)
                    })
                    .expect("second"),
                )
                .expect("second delay"),
            ],
            CueJoinPolicy::All,
        )
        .expect("delayed graph");
    let delayed_session = deadline_runtime
        .start(&delayed, CueStartPolicy::Restart)
        .expect("delayed session");
    deadline_runtime.tick(1.0).expect("equal deadline");
    assert_eq!(*deadline_order.borrow(), vec![1, 2]);
    assert_eq!(delayed_session.status(), CueSessionStatus::Succeeded);

    let cancellation_runtime = CueRuntime::default();
    let cancellation_graph =
        cue(
            cue_action_with_completion("pending", |_| Some(Box::new(|| panic!("cancel failed"))))
                .expect("pending action"),
        );
    let cancellation_session = cancellation_runtime
        .start(&cancellation_graph, CueStartPolicy::Restart)
        .expect("cancellation session");
    assert!(cancellation_runtime.cancel(&cancellation_session));
    assert_eq!(cancellation_session.status(), CueSessionStatus::Cancelled);
    let foreign_runtime = CueRuntime::default();
    assert!(!foreign_runtime.cancel(&cancellation_session));
}
