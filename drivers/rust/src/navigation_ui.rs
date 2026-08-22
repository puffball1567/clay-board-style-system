use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};

use crate::{
    keyword, AccessibleRole, Error, Event, EventKind, EventOutcome, InputEvent, Node, NodeState,
    Result, Style, Ui, UiHandle, STATUS_INVALID_ARGUMENT,
};
use crate::{
    NavigationChange, NavigationChangeKind, NavigationEntry, NavigationSnapshot,
    NavigationSubscription, Navigator,
};

pub const NAVIGATION_SCREEN_HOST_STYLE_PRIORITY: i32 = 1_000_000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NavigationScreenBinding<D> {
    pub destination: D,
    pub screen_root: Node,
    pub focus_fallback: Option<Node>,
    pub active: bool,
}

struct ScreenHostCore<D> {
    ui: UiHandle,
    navigator: Navigator<D>,
    screens: Vec<NavigationScreenBinding<D>>,
    active_index: Option<usize>,
    active_entry_id: Option<u64>,
    pending_entry: Option<NavigationEntry<D>>,
    pending_snapshot: Option<NavigationSnapshot<D>>,
    pending_kind: Option<NavigationChangeKind>,
    pending_change: bool,
    saved_focus: HashMap<u64, Node>,
}

impl<D: Clone + PartialEq + 'static> ScreenHostCore<D> {
    fn new(ui: UiHandle, navigator: Navigator<D>) -> Self {
        Self {
            pending_entry: navigator.current_entry(),
            pending_snapshot: Some(navigator.snapshot()),
            ui,
            navigator,
            screens: Vec::new(),
            active_index: None,
            active_entry_id: None,
            pending_kind: None,
            pending_change: true,
            saved_focus: HashMap::new(),
        }
    }

    fn validate_node(&self, node: Node, description: &str) -> Result<()> {
        self.ui.inert(node).map(|_| ()).map_err(|_| {
            Error::status(
                STATUS_INVALID_ARGUMENT,
                format!("{description} belongs to another Ui or is no longer active"),
            )
        })
    }

    fn descendant_or_self(&self, node: Node, ancestor: Node) -> Result<bool> {
        let mut current = Some(node);
        while let Some(node) = current {
            if node == ancestor {
                return Ok(true);
            }
            current = self.ui.parent(node)?;
        }
        Ok(false)
    }

    fn find_screen_index(&self, destination: &D) -> Option<usize> {
        self.screens
            .iter()
            .position(|screen| &screen.destination == destination)
    }

    fn set_screen_active(&mut self, index: usize, active: bool) -> Result<()> {
        let Some(screen) = self.screens.get_mut(index) else {
            return Ok(());
        };
        if screen.active == active {
            return Ok(());
        }
        self.ui.set_inert(screen.screen_root, !active)?;
        let mut visibility = Style::new()?;
        visibility.set("display", keyword(if active { "flex" } else { "none" }))?;
        self.ui.apply(
            screen.screen_root,
            &visibility,
            0,
            NAVIGATION_SCREEN_HOST_STYLE_PRIORITY,
        )?;
        screen.active = active;
        Ok(())
    }

    fn retain_entries(&mut self, snapshot: &NavigationSnapshot<D>) {
        let retained = snapshot
            .entries
            .iter()
            .map(|entry| entry.id)
            .collect::<HashSet<_>>();
        self.saved_focus.retain(|entry, _| retained.contains(entry));
    }

    fn restore_focus(
        &mut self,
        entry: u64,
        screen_root: Node,
        fallback: Option<Node>,
    ) -> Result<()> {
        if let Some(saved) = self.saved_focus.get(&entry).copied() {
            match self.descendant_or_self(saved, screen_root) {
                Ok(true) => match self.ui.set_focus(Some(saved), true) {
                    Ok(()) => return Ok(()),
                    Err(error) if error.status_code() == Some(STATUS_INVALID_ARGUMENT) => {
                        self.saved_focus.remove(&entry);
                    }
                    Err(error) => return Err(error),
                },
                Ok(false) | Err(_) => {
                    self.saved_focus.remove(&entry);
                }
            }
        }
        if let Some(fallback) = fallback {
            match self.ui.set_focus(Some(fallback), true) {
                Ok(()) => return Ok(()),
                Err(error) if error.status_code() == Some(STATUS_INVALID_ARGUMENT) => {}
                Err(error) => return Err(error),
            }
        }
        let target = self.ui.first_focusable(screen_root)?;
        self.ui.set_focus(target, true)
    }

    fn finish_pending(&mut self) {
        self.pending_change = false;
        self.pending_snapshot = None;
        self.pending_kind = None;
    }
}

pub struct NavigationScreenHost<D: Clone + PartialEq + 'static> {
    core: Rc<RefCell<ScreenHostCore<D>>>,
    subscription: NavigationSubscription,
}

impl<D: Clone + PartialEq + 'static> NavigationScreenHost<D> {
    pub fn new(ui: &Ui, navigator: Navigator<D>) -> Self {
        let core = Rc::new(RefCell::new(ScreenHostCore::new(
            ui.handle(),
            navigator.clone(),
        )));
        let weak: Weak<RefCell<ScreenHostCore<D>>> = Rc::downgrade(&core);
        let subscription = navigator.subscribe(move |change: &NavigationChange<D>| {
            let Some(core) = weak.upgrade() else {
                return;
            };
            let mut core = core.borrow_mut();
            core.pending_entry = change.current.clone();
            core.pending_snapshot = Some(change.snapshot.clone());
            core.pending_kind = Some(change.kind);
            core.pending_change = true;
        });
        Self { core, subscription }
    }

    pub fn connected(&self) -> bool {
        self.subscription.active()
    }

    pub fn disconnect(&mut self) -> bool {
        self.subscription.close()
    }

    pub fn screen_count(&self) -> usize {
        self.core.borrow().screens.len()
    }

    pub fn active_screen(&self) -> Option<NavigationScreenBinding<D>> {
        let core = self.core.borrow();
        core.active_index
            .and_then(|index| core.screens.get(index).cloned())
    }

    pub fn pending_destination(&self) -> Option<D> {
        let core = self.core.borrow();
        core.pending_change
            .then(|| {
                core.pending_entry
                    .as_ref()
                    .map(|entry| entry.destination.clone())
            })
            .flatten()
    }

    pub fn register_screen(
        &self,
        destination: D,
        screen_root: Node,
        focus_fallback: Option<Node>,
    ) -> Result<()> {
        let mut core = self.core.borrow_mut();
        core.validate_node(screen_root, "navigation screen root")?;
        if let Some(fallback) = focus_fallback {
            core.validate_node(fallback, "navigation focus fallback")?;
            if !core.descendant_or_self(fallback, screen_root)? {
                return Err(Error::status(
                    STATUS_INVALID_ARGUMENT,
                    "navigation focus fallback must belong to the registered screen",
                ));
            }
        }
        if core.find_screen_index(&destination).is_some() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "navigation destination is already registered",
            ));
        }
        for screen in &core.screens {
            if core.descendant_or_self(screen_root, screen.screen_root)?
                || core.descendant_or_self(screen.screen_root, screen_root)?
            {
                return Err(Error::status(
                    STATUS_INVALID_ARGUMENT,
                    "navigation screen roots must not overlap",
                ));
            }
        }
        core.screens.push(NavigationScreenBinding {
            destination,
            screen_root,
            focus_fallback,
            active: true,
        });
        let index = core.screens.len() - 1;
        core.set_screen_active(index, false)
    }

    pub fn unregister_screen(&self, destination: &D, ui: &mut Ui) -> Result<bool> {
        let mut core = self.core.borrow_mut();
        let Some(index) = core.find_screen_index(destination) else {
            return Ok(false);
        };
        let screen_root = core.screens[index].screen_root;
        let was_active = core.active_index == Some(index);
        if was_active {
            core.active_index = None;
            core.active_entry_id = None;
        } else if core.active_index.is_some_and(|active| index < active) {
            core.active_index = core.active_index.map(|active| active - 1);
        }
        core.screens.remove(index);
        ui.remove_subtree(screen_root)?;
        if was_active {
            core.pending_entry = core.navigator.current_entry();
            core.pending_snapshot = Some(core.navigator.snapshot());
            core.pending_kind = None;
            core.pending_change = true;
        }
        Ok(true)
    }

    pub fn replace_screen(
        &self,
        destination: &D,
        screen_root: Node,
        focus_fallback: Option<Node>,
        ui: &mut Ui,
    ) -> Result<bool> {
        let mut core = self.core.borrow_mut();
        let Some(index) = core.find_screen_index(destination) else {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "navigation destination is not registered",
            ));
        };
        core.validate_node(screen_root, "replacement navigation screen root")?;
        if let Some(fallback) = focus_fallback {
            core.validate_node(fallback, "navigation focus fallback")?;
            if !core.descendant_or_self(fallback, screen_root)? {
                return Err(Error::status(
                    STATUS_INVALID_ARGUMENT,
                    "navigation focus fallback must belong to the replacement screen",
                ));
            }
        }
        let previous = core.screens[index].clone();
        if previous.screen_root == screen_root {
            core.screens[index].focus_fallback = focus_fallback;
            return Ok(false);
        }
        if core.descendant_or_self(screen_root, previous.screen_root)?
            || core.descendant_or_self(previous.screen_root, screen_root)?
        {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "replacement screen must be disjoint from the previous screen",
            ));
        }
        for (other_index, other) in core.screens.iter().enumerate() {
            if other_index != index
                && (core.descendant_or_self(screen_root, other.screen_root)?
                    || core.descendant_or_self(other.screen_root, screen_root)?)
            {
                return Err(Error::status(
                    STATUS_INVALID_ARGUMENT,
                    "navigation screen roots must not overlap",
                ));
            }
        }
        let was_active = core.active_index == Some(index);
        core.screens[index] = NavigationScreenBinding {
            destination: destination.clone(),
            screen_root,
            focus_fallback,
            active: !was_active,
        };
        core.set_screen_active(index, was_active)?;
        ui.remove_subtree(previous.screen_root)?;
        if was_active {
            if let Some(entry) = core.active_entry_id {
                core.restore_focus(entry, screen_root, focus_fallback)?;
            }
        }
        Ok(true)
    }

    pub fn queue_current(&self) {
        let mut core = self.core.borrow_mut();
        core.pending_entry = core.navigator.current_entry();
        core.pending_snapshot = Some(core.navigator.snapshot());
        core.pending_kind = None;
        core.pending_change = true;
    }

    pub fn sync(&self) -> Result<bool> {
        let mut core = self.core.borrow_mut();
        if !core.pending_change {
            return Ok(false);
        }
        let Some(target) = core.pending_entry.clone() else {
            if let Some(previous) = core.active_index {
                core.ui.set_focus(None, false)?;
                core.set_screen_active(previous, false)?;
                core.active_index = None;
                core.active_entry_id = None;
                core.finish_pending();
                return Ok(true);
            }
            core.finish_pending();
            return Ok(false);
        };
        let Some(target_index) = core.find_screen_index(&target.destination) else {
            return Ok(false);
        };
        if core.active_entry_id == Some(target.id) {
            core.finish_pending();
            return Ok(false);
        }

        let previous_index = core.active_index;
        let previous_entry = core.active_entry_id;
        if let (Some(index), Some(entry), Some(focused)) =
            (previous_index, previous_entry, core.ui.focused_node())
        {
            if core.descendant_or_self(focused, core.screens[index].screen_root)? {
                core.saved_focus.insert(entry, focused);
            }
        }
        if core.pending_kind == Some(NavigationChangeKind::Replace) {
            if let Some(entry) = previous_entry {
                core.saved_focus.remove(&entry);
            }
        } else if let Some(snapshot) = core.pending_snapshot.clone() {
            core.retain_entries(&snapshot);
        }

        if previous_index != Some(target_index) {
            core.set_screen_active(target_index, true)?;
        }
        core.active_index = Some(target_index);
        core.active_entry_id = Some(target.id);
        core.finish_pending();

        if previous_entry.is_some() {
            let screen = core.screens[target_index].clone();
            core.restore_focus(target.id, screen.screen_root, screen.focus_fallback)?;
        }
        if let Some(previous) = previous_index.filter(|index| *index != target_index) {
            core.set_screen_active(previous, false)?;
        }
        Ok(true)
    }
}

struct LinkState<D> {
    navigator: Navigator<D>,
    destination: D,
    label: String,
    disabled: bool,
}

pub struct Link<D: Clone + 'static> {
    ui: UiHandle,
    container: Node,
    label_node: Node,
    state: Rc<RefCell<LinkState<D>>>,
}

impl<D: Clone + 'static> Link<D> {
    #[allow(clippy::too_many_arguments)]
    pub fn mount(
        ui: &mut Ui,
        navigator: Navigator<D>,
        destination: D,
        label: impl Into<String>,
        disabled: bool,
        container_style: Option<&Style>,
        text_style: Option<&Style>,
        identifier: &str,
    ) -> Result<Self> {
        Self::mount_at(
            ui,
            None,
            navigator,
            destination,
            label,
            disabled,
            container_style,
            text_style,
            identifier,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn mount_in(
        ui: &mut Ui,
        parent: Node,
        navigator: Navigator<D>,
        destination: D,
        label: impl Into<String>,
        disabled: bool,
        container_style: Option<&Style>,
        text_style: Option<&Style>,
        identifier: &str,
    ) -> Result<Self> {
        ui.require_node(parent, "mount Link parent")?;
        Self::mount_at(
            ui,
            Some(parent),
            navigator,
            destination,
            label,
            disabled,
            container_style,
            text_style,
            identifier,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn mount_at(
        ui: &mut Ui,
        parent: Option<Node>,
        navigator: Navigator<D>,
        destination: D,
        label: impl Into<String>,
        disabled: bool,
        container_style: Option<&Style>,
        text_style: Option<&Style>,
        identifier: &str,
    ) -> Result<Self> {
        let label = label.into();
        let state = Rc::new(RefCell::new(LinkState {
            navigator,
            destination,
            label: label.clone(),
            disabled,
        }));
        let container = ui.add_box(parent, identifier, container_style)?;
        let mut label_node = None;
        ui.within(container, |scope| {
            label_node = Some(scope.text(&label, "", text_style)?);
            Ok(())
        })?;
        let label_node = label_node.expect("Link label construction must assign a Node");
        let mut passthrough = Style::new()?;
        passthrough.set("pointer-events", keyword("none"))?;
        ui.apply(label_node, &passthrough, 0, 1)?;
        ui.set_focusable(container, true, 0)?;
        ui.set_accessibility(container, AccessibleRole::Link, &label, "")?;
        ui.set_state(container, NodeState::Disabled, disabled)?;

        let handle = ui.handle();
        let click_state = Rc::clone(&state);
        handle.set_default_action(container, EventKind::CLICK, move |_| {
            let state = click_state.borrow();
            if state.disabled {
                return EventOutcome::CONTINUE;
            }
            let activated = state.navigator.push(state.destination.clone());
            EventOutcome::new(activated, activated, false)
        })?;
        let key_handle = handle.clone();
        let key_state = Rc::clone(&state);
        handle.set_default_action(container, EventKind::KEY_DOWN, move |event| {
            if key_state.borrow().disabled || event.key.as_deref() != Some("Enter") {
                return EventOutcome::CONTINUE;
            }
            key_handle
                .emit(container, &InputEvent::new(EventKind::CLICK))
                .unwrap_or_else(|error| panic!("Link Enter activation failed: {error}"))
                .outcome
        })?;
        Ok(Self {
            ui: handle,
            container,
            label_node,
            state,
        })
    }

    pub fn container(&self) -> Node {
        self.container
    }

    pub fn label_node(&self) -> Node {
        self.label_node
    }

    pub fn label(&self) -> String {
        self.state.borrow().label.clone()
    }

    pub fn destination(&self) -> D {
        self.state.borrow().destination.clone()
    }

    pub fn disabled(&self) -> bool {
        self.state.borrow().disabled
    }

    pub fn set_label(&self, label: impl Into<String>) -> Result<()> {
        let label = label.into();
        self.state.borrow_mut().label = label.clone();
        self.ui.set_text(self.label_node, &label)?;
        self.ui
            .set_accessibility(self.container, AccessibleRole::Link, &label, "")
    }

    pub fn set_destination(&self, destination: D) {
        self.state.borrow_mut().destination = destination;
    }

    pub fn set_disabled(&self, disabled: bool) -> Result<()> {
        self.state.borrow_mut().disabled = disabled;
        self.ui
            .set_state(self.container, NodeState::Disabled, disabled)
    }

    pub fn activate(&self) -> bool {
        let state = self.state.borrow();
        !state.disabled && state.navigator.push(state.destination.clone())
    }

    pub fn on_click(&self, handler: impl FnMut(&Event) -> EventOutcome + 'static) -> Result<()> {
        self.ui.on(self.container, EventKind::CLICK, handler)
    }
}
