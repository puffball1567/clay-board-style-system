use std::cell::{Cell, RefCell};
use std::rc::{Rc, Weak};

use crate::{
    Error, Event, EventKind, EventOutcome, EventSubscription, EventView, FormData, Node, NodeState,
    Result, Ui, UiHandle, ValidationBinding, ValidationReport, ValidationResult, ValidationRules,
    ValidationTrigger, ValidationValue, ValidationValueType, STATUS_INVALID_ARGUMENT,
    STATUS_INVALID_HANDLE,
};

trait ValidationControlAdapter {
    fn node(&self) -> Node;
    fn active(&self) -> bool;
    fn disabled(&self) -> bool;
    fn check_validity(&self) -> Result<bool>;
    fn report_validity(&self, focus: bool) -> Result<bool>;
    fn value_identity(&self) -> usize;
    fn dependency_identities(&self) -> &[usize];
    fn add_dependent(&self, dependent: Weak<dyn ValidationControlAdapter>);
    fn refresh_dependency(&self) -> Result<()>;
}

struct EvaluationGuard<'a>(&'a Cell<bool>);

impl Drop for EvaluationGuard<'_> {
    fn drop(&mut self) {
        self.0.set(false);
    }
}

struct ValidationControlState<T> {
    ui: UiHandle,
    node: Node,
    dependencies: Vec<usize>,
    binding: RefCell<ValidationBinding<T>>,
    dependents: RefCell<Vec<Weak<dyn ValidationControlAdapter>>>,
    subscriptions: RefCell<Vec<EventSubscription>>,
    disabled: Cell<bool>,
    active: Cell<bool>,
    evaluating: Cell<bool>,
}

impl<T> ValidationControlState<T>
where
    T: Clone + ValidationValueType + 'static,
{
    fn sync(&self) -> Result<()> {
        if !self.active() {
            return Ok(());
        }
        let binding = self.binding.borrow();
        let disabled = self.disabled.get();
        self.ui.set_state(
            self.node,
            NodeState::Invalid,
            !disabled && binding.should_expose(),
        )?;
        self.ui.set_attribute(
            self.node,
            "validation-message",
            if disabled {
                ""
            } else {
                binding.validation_message()
            },
        )
    }

    fn evaluate(
        &self,
        value: T,
        trigger: ValidationTrigger,
        force_report: bool,
        notify_dependents: bool,
    ) -> Result<ValidationResult> {
        if self.disabled.get() {
            return Ok(ValidationResult::valid());
        }
        if self.evaluating.replace(true) {
            return Ok(self.binding.borrow().current().clone());
        }
        let _guard = EvaluationGuard(&self.evaluating);
        let result = self
            .binding
            .borrow_mut()
            .evaluate(value, trigger, force_report)
            .clone();
        self.sync()?;
        if notify_dependents {
            let snapshot = self.dependents.borrow().clone();
            let mut retained = Vec::with_capacity(snapshot.len());
            for dependent in snapshot {
                if let Some(current) = dependent.upgrade() {
                    if current.active() {
                        current.refresh_dependency()?;
                        retained.push(Rc::downgrade(&current));
                    }
                }
            }
            *self.dependents.borrow_mut() = retained;
        }
        Ok(result)
    }

    fn current_value(&self) -> T {
        self.binding.borrow().value_reference().with(Clone::clone)
    }

    fn close(&self) {
        if !self.active.replace(false) {
            return;
        }
        for subscription in self.subscriptions.borrow_mut().iter_mut() {
            let _ = subscription.close();
        }
        self.subscriptions.borrow_mut().clear();
    }
}

impl<T> ValidationControlAdapter for ValidationControlState<T>
where
    T: Clone + ValidationValueType + 'static,
{
    fn node(&self) -> Node {
        self.node
    }

    fn active(&self) -> bool {
        self.active.get() && self.ui.active()
    }

    fn disabled(&self) -> bool {
        self.disabled.get()
    }

    fn check_validity(&self) -> Result<bool> {
        if self.disabled.get() {
            return Ok(true);
        }
        Ok(self
            .evaluate(
                self.current_value(),
                ValidationTrigger::Explicit,
                false,
                false,
            )?
            .is_valid)
    }

    fn report_validity(&self, focus: bool) -> Result<bool> {
        if self.disabled.get() {
            return Ok(true);
        }
        let valid = self
            .evaluate(
                self.current_value(),
                ValidationTrigger::Explicit,
                true,
                false,
            )?
            .is_valid;
        if !valid && self.active() {
            self.ui
                .emit(self.node, &crate::InputEvent::new(EventKind::INVALID))?;
            if focus {
                self.ui.set_focus(Some(self.node), true)?;
            }
        }
        Ok(valid)
    }

    fn value_identity(&self) -> usize {
        self.binding.borrow().value_reference().identity()
    }

    fn dependency_identities(&self) -> &[usize] {
        &self.dependencies
    }

    fn add_dependent(&self, dependent: Weak<dyn ValidationControlAdapter>) {
        if self
            .dependents
            .borrow()
            .iter()
            .any(|existing| existing.ptr_eq(&dependent))
        {
            return;
        }
        self.dependents.borrow_mut().push(dependent);
    }

    fn refresh_dependency(&self) -> Result<()> {
        if !self.active() || self.disabled.get() || self.evaluating.get() {
            return Ok(());
        }
        self.evaluate(
            self.current_value(),
            ValidationTrigger::Explicit,
            false,
            false,
        )?;
        Ok(())
    }
}

impl<T> Drop for ValidationControlState<T> {
    fn drop(&mut self) {
        if !self.active.replace(false) {
            return;
        }
        for subscription in self.subscriptions.get_mut().iter_mut() {
            let _ = subscription.close();
        }
        self.subscriptions.get_mut().clear();
    }
}

#[derive(Clone)]
pub struct ValidationControl<T> {
    state: Rc<ValidationControlState<T>>,
}

impl<T> ValidationControl<T>
where
    T: Clone + ValidationValueType + 'static,
{
    fn require_active(&self) -> Result<()> {
        if self.active() {
            Ok(())
        } else {
            Err(Error::status(
                STATUS_INVALID_HANDLE,
                "access Validation Control: attachment is not active",
            ))
        }
    }

    pub fn active(&self) -> bool {
        self.state.active()
    }

    pub fn node(&self) -> Node {
        self.state.node
    }

    pub fn input(&self, value: T) -> Result<ValidationResult> {
        self.require_active()?;
        self.state
            .evaluate(value, ValidationTrigger::Input, false, true)
    }

    pub fn change(&self, value: T) -> Result<ValidationResult> {
        self.input(value)
    }

    pub fn blur(&self) -> Result<ValidationResult> {
        self.require_active()?;
        self.state.evaluate(
            self.state.current_value(),
            ValidationTrigger::Blur,
            false,
            false,
        )
    }

    pub fn check_validity(&self) -> Result<bool> {
        self.require_active()?;
        self.state.check_validity()
    }

    pub fn report_validity(&self) -> Result<bool> {
        self.require_active()?;
        self.state.report_validity(true)
    }

    pub fn validation_result(&self) -> ValidationResult {
        self.state.binding.borrow().current().clone()
    }

    pub fn validation_message(&self) -> String {
        if self.state.disabled.get() {
            String::new()
        } else {
            self.state.binding.borrow().validation_message().to_owned()
        }
    }

    pub fn validation_value(&self) -> ValidationValue<T> {
        self.state.binding.borrow().value_reference()
    }

    pub fn set_disabled(&self, disabled: bool) -> Result<()> {
        self.require_active()?;
        self.state.disabled.set(disabled);
        self.state
            .ui
            .set_state(self.state.node, NodeState::Disabled, disabled)?;
        self.state.sync()
    }

    pub fn disabled(&self) -> bool {
        self.state.disabled.get()
    }

    pub fn close(&self) {
        self.state.close();
    }
}

pub fn attach_validation<T, F>(
    ui: &mut Ui,
    node: Node,
    rules: ValidationRules<T>,
    initial_value: T,
    extract_value: F,
) -> Result<ValidationControl<T>>
where
    T: Clone + ValidationValueType + 'static,
    F: FnMut(&Event) -> T + 'static,
{
    attach_validation_with(
        ui,
        node,
        rules,
        initial_value,
        extract_value,
        ValidationReport::OnBlur,
        EventKind::INPUT,
    )
}

pub fn attach_validation_with<T, F>(
    ui: &mut Ui,
    node: Node,
    rules: ValidationRules<T>,
    initial_value: T,
    mut extract_value: F,
    report_on: ValidationReport,
    value_event: EventKind,
) -> Result<ValidationControl<T>>
where
    T: Clone + ValidationValueType + 'static,
    F: FnMut(&Event) -> T + 'static,
{
    ui.set_focusable(node, true, 0)?;
    let dependencies = rules
        .dependency_references()
        .iter()
        .map(ValidationValue::identity)
        .collect();
    let state = Rc::new(ValidationControlState {
        ui: ui.handle(),
        node,
        dependencies,
        binding: RefCell::new(ValidationBinding::new(rules, initial_value, report_on)),
        dependents: RefCell::new(Vec::new()),
        subscriptions: RefCell::new(Vec::new()),
        disabled: Cell::new(false),
        active: Cell::new(true),
        evaluating: Cell::new(false),
    });

    let weak: Weak<ValidationControlState<T>> = Rc::downgrade(&state);
    let input = ui.subscribe(node, value_event, move |event| {
        if let Some(current) = weak.upgrade() {
            if current.active() && !current.disabled.get() {
                current
                    .evaluate(extract_value(event), ValidationTrigger::Input, false, true)
                    .unwrap_or_else(|error| {
                        panic!("Validation Control input update failed: {error}")
                    });
            }
        }
        EventOutcome::default()
    })?;

    let weak = Rc::downgrade(&state);
    let blur = ui.subscribe(node, EventKind::BLUR, move |_| {
        if let Some(current) = weak.upgrade() {
            if current.active() && !current.disabled.get() {
                current
                    .evaluate(
                        current.current_value(),
                        ValidationTrigger::Blur,
                        false,
                        false,
                    )
                    .unwrap_or_else(|error| {
                        panic!("Validation Control blur update failed: {error}")
                    });
            }
        }
        EventOutcome::default()
    })?;

    state.subscriptions.borrow_mut().extend([input, blur]);
    state.sync()?;
    Ok(ValidationControl { state })
}

pub fn attach_text_validation(
    ui: &mut Ui,
    node: Node,
    rules: ValidationRules<String>,
    initial_value: impl Into<String>,
) -> Result<ValidationControl<String>> {
    attach_text_validation_with(
        ui,
        node,
        rules,
        initial_value,
        ValidationReport::OnBlur,
        EventKind::INPUT,
    )
}

pub fn attach_text_validation_with(
    ui: &mut Ui,
    node: Node,
    rules: ValidationRules<String>,
    initial_value: impl Into<String>,
    report_on: ValidationReport,
    value_event: EventKind,
) -> Result<ValidationControl<String>> {
    attach_validation_with(
        ui,
        node,
        rules,
        initial_value.into(),
        |event| event.text.clone().unwrap_or_default(),
        report_on,
        value_event,
    )
}

pub struct ValidationForm {
    ui: UiHandle,
    node: Node,
    controls: Vec<Rc<dyn ValidationControlAdapter>>,
    disabled: bool,
}

impl ValidationForm {
    pub fn new(ui: &Ui, node: Node) -> Result<Self> {
        let handle = ui.handle();
        let _ = handle.parent(node)?;
        Ok(Self {
            ui: handle,
            node,
            controls: Vec::new(),
            disabled: false,
        })
    }

    pub fn add<T>(&mut self, control: &ValidationControl<T>) -> Result<()>
    where
        T: Clone + ValidationValueType + 'static,
    {
        if !control.active() {
            return Err(Error::status(
                STATUS_INVALID_HANDLE,
                "register Validation Control: attachment is not active",
            ));
        }
        let mut current = Some(control.node());
        let mut descendant = false;
        while let Some(node) = current {
            if node == self.node {
                descendant = true;
                break;
            }
            current = self.ui.parent(node)?;
        }
        if !descendant {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Validation Control must belong to the Validation Form",
            ));
        }
        if self
            .controls
            .iter()
            .any(|entry| entry.node() == control.node())
        {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Validation Control is already registered",
            ));
        }
        let added: Rc<dyn ValidationControlAdapter> = control.state.clone();
        let weak_added = Rc::downgrade(&added);
        for existing in &self.controls {
            if existing
                .dependency_identities()
                .contains(&added.value_identity())
            {
                added.add_dependent(Rc::downgrade(existing));
            }
            if added
                .dependency_identities()
                .contains(&existing.value_identity())
            {
                existing.add_dependent(weak_added.clone());
            }
        }
        self.controls.push(added);
        Ok(())
    }

    pub fn remove(&mut self, node: Node) -> bool {
        let Some(index) = self.controls.iter().position(|entry| entry.node() == node) else {
            return false;
        };
        self.controls.remove(index);
        true
    }

    pub fn set_disabled(&mut self, disabled: bool) -> Result<()> {
        self.disabled = disabled;
        self.ui.set_state(self.node, NodeState::Disabled, disabled)
    }

    pub fn disabled(&self) -> bool {
        self.disabled
    }

    pub fn check_validity(&self) -> Result<bool> {
        if self.disabled {
            return Ok(false);
        }
        let mut valid = true;
        for control in &self.controls {
            if control.active() && !control.disabled() && !control.check_validity()? {
                valid = false;
            }
        }
        Ok(valid)
    }

    pub fn report_validity(&self) -> Result<bool> {
        if self.disabled {
            return Ok(false);
        }
        let mut valid = true;
        let mut first_invalid = None;
        for control in &self.controls {
            if !control.active() || control.disabled() {
                continue;
            }
            if !control.report_validity(false)? {
                valid = false;
                first_invalid.get_or_insert_with(|| control.node());
            }
        }
        if let Some(node) = first_invalid {
            self.ui.set_focus(Some(node), true)?;
        }
        Ok(valid)
    }

    pub fn on_submit<F>(&self, callback: F) -> Result<()>
    where
        F: FnMut(&EventView) -> EventOutcome + 'static,
    {
        self.ui.on_view(self.node, EventKind::SUBMIT, callback)
    }

    pub fn submit(&self, data: &FormData) -> Result<bool> {
        if self.disabled || !self.report_validity()? {
            return Ok(false);
        }
        self.ui.emit_submit(self.node, data)?;
        Ok(true)
    }

    pub fn len(&self) -> usize {
        self.controls.len()
    }

    pub fn is_empty(&self) -> bool {
        self.controls.is_empty()
    }
}
