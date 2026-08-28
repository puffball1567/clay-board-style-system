use cbss_craft::{
    attach_text_validation, cue, cue_action, cue_action_with_completion, keyword, px, Command,
    CommandOfferResult, CueCancel, CueCompletion, CueRuntime, CueSessionStatus, CueStartPolicy,
    EventKind, EventOutcome, InputEvent, Navigator, NodeState, Store, Style, Ui, ValidationForm,
    ValidationRules, STATUS_STYLE_ERROR,
};
use std::cell::Cell;
use std::cell::RefCell;
use std::env;
use std::fs;
use std::rc::Rc;

const STYLE: &str = include_str!("../../../fixtures/drivers/reference_application_style.json");
const INVALID_STYLE: &str =
    include_str!("../../../fixtures/drivers/invalid_application_style.json");

fn trace(image_path: Option<&str>) -> Result<String, Box<dyn std::error::Error>> {
    let mut root_style = Style::new()?;
    root_style
        .set("width", px(320.0))?
        .set("height", px(200.0))?
        .set("padding", px(12.0))?
        .set("gap", px(8.0))?
        .set("flex-direction", keyword("column"))?;

    let mut ui = Ui::new()?;
    let mut panel = None;
    let mut field = None;
    let mut form_node = None;
    ui.box_with("root", Some(&root_style), |ui| {
        panel = Some(ui.box_with("panel", None, |ui| {
            ui.text("Reference", "panel-label", None)?;
            Ok(())
        })?);
        form_node = Some(ui.box_with("form", None, |ui| {
            field = Some(ui.box_node("account", None)?);
            Ok(())
        })?);
        Ok(())
    })?;
    let panel = panel.expect("panel");
    let field = field.expect("field");
    let form_node = form_node.expect("form");
    ui.expose_style_slot(panel, panel, "reference-card", "root")?;
    ui.replace_craft_style(STYLE)?;
    ui.compute(320.0, 200.0)?;
    let panel_rect = ui.rect(panel)?;
    if let Some(path) = image_path {
        let invalid = ui
            .write_reference_ppm(path, 0, 200)
            .expect_err("invalid reference PPM dimensions must fail");
        assert_eq!(
            invalid.status_code(),
            Some(cbss_craft::STATUS_INVALID_ARGUMENT)
        );
        ui.write_reference_ppm(path, 320, 200)?;
    }

    let event_order = Rc::new(RefCell::new(Vec::<String>::new()));
    let handler_order = Rc::clone(&event_order);
    let event_ui = ui.handle();
    ui.on(panel, EventKind::CLICK, move |_| {
        handler_order.borrow_mut().push("handler".to_owned());
        event_ui
            .set_state(panel, NodeState::Hover, true)
            .expect("set hover state");
        EventOutcome::HANDLED
    })?;
    let observer_order = Rc::clone(&event_order);
    let observer = ui.subscribe(panel, EventKind::CLICK, move |_| {
        observer_order.borrow_mut().push("observer".to_owned());
        EventOutcome::default()
    })?;
    let click = ui.emit(panel, &InputEvent::new(EventKind::CLICK))?;

    let account = attach_text_validation(
        &mut ui,
        field,
        ValidationRules::<String>::new().required("account required"),
        "",
    )?;
    let mut form = ValidationForm::new(&ui, form_node)?;
    form.register_text_field("account", &account)?;
    let submitted = Rc::new(RefCell::new(String::new()));
    let submitted_value = Rc::clone(&submitted);
    form.on_submit(move |event| {
        let entry = event
            .form_data()
            .expect("submit FormData")
            .entry(0)
            .expect("account entry");
        let value = match entry.value {
            cbss_craft::FormDataValue::Text(value) => value,
            cbss_craft::FormDataValue::Blob { .. } => panic!("unexpected Blob"),
        };
        submitted_value.replace(format!("{}:{value}", entry.name));
        EventOutcome::HANDLED
    })?;
    account.input("ready".to_owned())?;
    let submitted_ok = form.submit_collected()?;

    let store = Store::new(0_i32, |state, amount: &i32| *state += *amount);
    store.dispatch(2);
    store.transaction(|| {
        store.dispatch(3);
        store.dispatch(4);
    });

    let navigator = Navigator::stack("home".to_owned());
    navigator.push("projects".to_owned());
    navigator.push("settings".to_owned());
    navigator.back();

    let command_sinks = Rc::new(RefCell::new(Vec::new()));
    let command_cancellations = Rc::new(Cell::new(0));
    let command = Command::<i32, String, String>::with_defaults({
        let command_sinks = Rc::clone(&command_sinks);
        let command_cancellations = Rc::clone(&command_cancellations);
        move |_, sink| {
            command_sinks.borrow_mut().push(sink);
            let command_cancellations = Rc::clone(&command_cancellations);
            Some(Box::new(move || {
                command_cancellations.set(command_cancellations.get() + 1)
            }))
        }
    })?;
    let command_successes = Rc::new(RefCell::new(Vec::new()));
    command.on_success({
        let command_successes = Rc::clone(&command_successes);
        move |value| command_successes.borrow_mut().push(value)
    })?;
    let command_first = command.run(1)?;
    let command_second = command.run(2)?;
    let command_first_cancelled = command_first.status() == cbss_craft::CommandStatus::Cancelled;
    command_sinks.borrow()[0].succeed("stale".to_owned());
    command_sinks.borrow()[1].succeed("current".to_owned());
    command.pump_all();
    let command_second_succeeded = command_second.status() == cbss_craft::CommandStatus::Succeeded;
    let command_stale_ignored = command_successes.borrow().as_slice() == ["current"];
    let command_third = command.run(3)?;
    let command_late_sink = command_sinks.borrow()[2].clone();
    command.dispose();
    let command_third_cancelled = command_third.status() == cbss_craft::CommandStatus::Cancelled;
    let command_late_disposed =
        command_late_sink.succeed("late".to_owned()) == CommandOfferResult::Disposed;

    let cue_completions = Rc::new(RefCell::new(Vec::<CueCompletion>::new()));
    let cue_cancellations = Rc::new(Cell::new(0));
    let cue_tail_runs = Rc::new(Cell::new(0));
    let cue_graph = cue(cue_action_with_completion("pending", {
        let cue_completions = Rc::clone(&cue_completions);
        let cue_cancellations = Rc::clone(&cue_cancellations);
        move |completion| {
            cue_completions.borrow_mut().push(completion);
            let cue_cancellations = Rc::clone(&cue_cancellations);
            Some(Box::new(move || cue_cancellations.set(cue_cancellations.get() + 1)) as CueCancel)
        }
    })?)
    .then(cue_action("tail", {
        let cue_tail_runs = Rc::clone(&cue_tail_runs);
        move || cue_tail_runs.set(cue_tail_runs.get() + 1)
    })?)?;
    let cue_runtime = CueRuntime::default();
    let cue_session = cue_runtime.start(&cue_graph, CueStartPolicy::Restart)?;
    let cue_cancelled = cue_runtime.cancel(&cue_session);
    cue_completions.borrow()[0].succeed();
    let cue_late_ignored =
        cue_tail_runs.get() == 0 && cue_session.status() == CueSessionStatus::Cancelled;

    let invalid_status = ui
        .replace_craft_style(INVALID_STYLE)
        .expect_err("invalid Craft Style must fail")
        .status_code()
        .unwrap_or_default();
    assert_eq!(invalid_status, STATUS_STYLE_ERROR);
    let diagnostics = ui.craft_diagnostics()?;
    let removed = ui.remove_subtree(panel)?;

    let mut output = String::new();
    output.push_str("cbss-driver-reference-v1\n");
    output.push_str(&format!("layout.panel.width={:.3}\n", panel_rect.width));
    output.push_str(&format!("layout.panel.height={:.3}\n", panel_rect.height));
    output.push_str(&format!("event.order={}\n", event_order.borrow().join(",")));
    output.push_str(&format!("event.dispatch-count={}\n", click.dispatch_count));
    output.push_str(&format!("event.handled={}\n", i32::from(click.handled)));
    output.push_str(&format!(
        "event.needs-compute={}\n",
        i32::from(click.needs_compute)
    ));
    output.push_str(&format!("form.submitted={}\n", i32::from(submitted_ok)));
    output.push_str(&format!("form.payload={}\n", submitted.borrow()));
    output.push_str(&format!("store.value={}\n", store.state()));
    output.push_str(&format!("store.revision={}\n", store.revision()));
    output.push_str(&format!(
        "navigation.current={}\n",
        navigator
            .current_destination()
            .expect("current destination")
    ));
    output.push_str(&format!(
        "navigation.revision={}\n",
        navigator.snapshot().revision
    ));
    output.push_str(&format!(
        "command.first-cancelled={}\n",
        i32::from(command_first_cancelled)
    ));
    output.push_str(&format!(
        "command.second-succeeded={}\n",
        i32::from(command_second_succeeded)
    ));
    output.push_str(&format!(
        "command.third-cancelled={}\n",
        i32::from(command_third_cancelled)
    ));
    output.push_str(&format!(
        "command.cancel-count={}\n",
        command_cancellations.get()
    ));
    output.push_str(&format!(
        "command.stale-ignored={}\n",
        i32::from(command_stale_ignored)
    ));
    output.push_str(&format!(
        "command.late-disposed={}\n",
        i32::from(command_late_disposed)
    ));
    output.push_str(&format!("cue.cancelled={}\n", i32::from(cue_cancelled)));
    output.push_str(&format!("cue.cancel-count={}\n", cue_cancellations.get()));
    output.push_str(&format!(
        "cue.late-ignored={}\n",
        i32::from(cue_late_ignored)
    ));
    output.push_str(&format!("style.active={}\n", ui.active_craft_styles()[0]));
    output.push_str(&format!("style.invalid-status={invalid_status}\n"));
    output.push_str(&format!("style.diagnostics={}\n", diagnostics.len()));
    output.push_str(&format!("lifecycle.removed={removed}\n"));
    output.push_str(&format!(
        "lifecycle.observer-active={}\n",
        i32::from(observer.active())
    ));
    Ok(output)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments.len() > 2 {
        return Err("expected at most a trace path and a reference image path".into());
    }
    let output = trace(arguments.get(1).map(String::as_str))?;
    if let Some(path) = arguments.first() {
        fs::write(path, output)?;
    } else {
        print!("{output}");
    }
    Ok(())
}
