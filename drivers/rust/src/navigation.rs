use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe};
use std::rc::{Rc, Weak};

pub const DIRTY_STYLE: u32 = 1 << 0;
pub const DIRTY_LAYOUT: u32 = 1 << 1;
pub const DIRTY_PAINT: u32 = 1 << 2;
pub const DIRTY_HIT: u32 = 1 << 3;
pub const NAVIGATION_SCREEN_DIRTY_DOMAINS: u32 =
    DIRTY_STYLE | DIRTY_LAYOUT | DIRTY_PAINT | DIRTY_HIT;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NavigationEntry<D> {
    pub id: u64,
    pub destination: D,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NavigationSnapshot<D> {
    pub entries: Vec<NavigationEntry<D>>,
    pub current_index: Option<usize>,
    pub revision: u64,
}

impl<D> NavigationSnapshot<D> {
    pub fn current_entry(&self) -> Option<&NavigationEntry<D>> {
        self.current_index.and_then(|index| self.entries.get(index))
    }

    pub fn current_destination(&self) -> Option<&D> {
        self.current_entry().map(|entry| &entry.destination)
    }

    pub fn can_go_back(&self) -> bool {
        self.current_index.is_some_and(|index| index > 0)
    }

    pub fn can_go_forward(&self) -> bool {
        self.current_index
            .is_some_and(|index| index + 1 < self.entries.len())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavigationChangeKind {
    Push,
    Replace,
    Back,
    Forward,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NavigationChange<D> {
    pub kind: NavigationChangeKind,
    pub previous: Option<NavigationEntry<D>>,
    pub current: Option<NavigationEntry<D>>,
    pub snapshot: NavigationSnapshot<D>,
    pub dirty_domains: u32,
}

type SnapshotOperation<D> = Rc<dyn Fn() -> NavigationSnapshot<D>>;
type DestinationOperation<D> = Rc<dyn Fn(D) -> Option<NavigationChange<D>>>;
type StepOperation<D> = Rc<dyn Fn() -> Option<NavigationChange<D>>>;

pub struct NavigationDriver<D> {
    snapshot: SnapshotOperation<D>,
    push: DestinationOperation<D>,
    replace: DestinationOperation<D>,
    back: StepOperation<D>,
    forward: StepOperation<D>,
}

impl<D> Clone for NavigationDriver<D> {
    fn clone(&self) -> Self {
        Self {
            snapshot: Rc::clone(&self.snapshot),
            push: Rc::clone(&self.push),
            replace: Rc::clone(&self.replace),
            back: Rc::clone(&self.back),
            forward: Rc::clone(&self.forward),
        }
    }
}

impl<D> NavigationDriver<D> {
    pub fn new(
        snapshot: impl Fn() -> NavigationSnapshot<D> + 'static,
        push: impl Fn(D) -> Option<NavigationChange<D>> + 'static,
        replace: impl Fn(D) -> Option<NavigationChange<D>> + 'static,
        back: impl Fn() -> Option<NavigationChange<D>> + 'static,
        forward: impl Fn() -> Option<NavigationChange<D>> + 'static,
    ) -> Self {
        Self {
            snapshot: Rc::new(snapshot),
            push: Rc::new(push),
            replace: Rc::new(replace),
            back: Rc::new(back),
            forward: Rc::new(forward),
        }
    }
}

type NavigationListener<D> = Rc<dyn Fn(&NavigationChange<D>)>;

struct ListenerBinding<D> {
    id: u64,
    callback: NavigationListener<D>,
}

struct NavigationSignal<D> {
    listeners: RefCell<Vec<ListenerBinding<D>>>,
    index: RefCell<HashMap<u64, usize>>,
    next_id: Cell<u64>,
}

impl<D: 'static> NavigationSignal<D> {
    fn new() -> Rc<Self> {
        Rc::new(Self {
            listeners: RefCell::new(Vec::new()),
            index: RefCell::new(HashMap::new()),
            next_id: Cell::new(1),
        })
    }

    fn subscribe(
        self: &Rc<Self>,
        callback: impl Fn(&NavigationChange<D>) + 'static,
    ) -> NavigationSubscription {
        let id = self.next_id.get();
        let next = id.wrapping_add(1);
        self.next_id.set(if next == 0 { 1 } else { next });
        let mut listeners = self.listeners.borrow_mut();
        let position = listeners.len();
        listeners.push(ListenerBinding {
            id,
            callback: Rc::new(callback),
        });
        drop(listeners);
        self.index.borrow_mut().insert(id, position);

        let weak_close = Rc::downgrade(self);
        let weak_active = Weak::clone(&weak_close);
        NavigationSubscription {
            close: Some(Box::new(move || {
                weak_close.upgrade().is_some_and(|source| source.remove(id))
            })),
            active: Box::new(move || {
                weak_active
                    .upgrade()
                    .is_some_and(|source| source.contains(id))
            }),
        }
    }

    fn emit(&self, change: &NavigationChange<D>) {
        let callbacks = self
            .listeners
            .borrow()
            .iter()
            .map(|binding| Rc::clone(&binding.callback))
            .collect::<Vec<_>>();
        let mut first_failure = None;
        for callback in callbacks {
            if let Err(failure) = catch_unwind(AssertUnwindSafe(|| callback(change))) {
                if first_failure.is_none() {
                    first_failure = Some(failure);
                }
            }
        }
        if let Some(failure) = first_failure {
            resume_unwind(failure);
        }
    }

    fn contains(&self, id: u64) -> bool {
        self.index.borrow().contains_key(&id)
    }

    fn remove(&self, id: u64) -> bool {
        let Some(position) = self.index.borrow_mut().remove(&id) else {
            return false;
        };
        self.listeners.borrow_mut().remove(position);
        self.rebuild_index();
        true
    }

    fn clear(&self) {
        self.listeners.borrow_mut().clear();
        self.index.borrow_mut().clear();
    }

    fn len(&self) -> usize {
        self.index.borrow().len()
    }

    fn rebuild_index(&self) {
        let listeners = self.listeners.borrow();
        let mut index = self.index.borrow_mut();
        index.clear();
        for (position, binding) in listeners.iter().enumerate() {
            index.insert(binding.id, position);
        }
    }
}

pub struct NavigationSubscription {
    close: Option<Box<dyn FnOnce() -> bool>>,
    active: Box<dyn Fn() -> bool>,
}

impl NavigationSubscription {
    pub fn active(&self) -> bool {
        self.close.is_some() && (self.active)()
    }

    pub fn close(&mut self) -> bool {
        let Some(close) = self.close.take() else {
            return false;
        };
        close()
    }
}

impl Drop for NavigationSubscription {
    fn drop(&mut self) {
        let _ = self.close();
    }
}

struct NavigatorCore<D> {
    driver: NavigationDriver<D>,
    listeners: Rc<NavigationSignal<D>>,
}

pub struct Navigator<D> {
    core: Rc<NavigatorCore<D>>,
}

impl<D> Clone for Navigator<D> {
    fn clone(&self) -> Self {
        Self {
            core: Rc::clone(&self.core),
        }
    }
}

impl<D: Clone + 'static> Navigator<D> {
    pub fn new(driver: NavigationDriver<D>) -> Self {
        Self {
            core: Rc::new(NavigatorCore {
                driver,
                listeners: NavigationSignal::new(),
            }),
        }
    }

    pub fn stack(initial_destination: D) -> Self {
        Self::new(stack_navigation_driver(initial_destination))
    }

    pub fn snapshot(&self) -> NavigationSnapshot<D> {
        (self.core.driver.snapshot)()
    }

    pub fn current_entry(&self) -> Option<NavigationEntry<D>> {
        self.snapshot().current_entry().cloned()
    }

    pub fn current_destination(&self) -> Option<D> {
        self.snapshot().current_destination().cloned()
    }

    pub fn can_go_back(&self) -> bool {
        self.snapshot().can_go_back()
    }

    pub fn can_go_forward(&self) -> bool {
        self.snapshot().can_go_forward()
    }

    pub fn subscribe(
        &self,
        listener: impl Fn(&NavigationChange<D>) + 'static,
    ) -> NavigationSubscription {
        self.core.listeners.subscribe(listener)
    }

    pub fn clear_listeners(&self) {
        self.core.listeners.clear();
    }

    pub fn listener_count(&self) -> usize {
        self.core.listeners.len()
    }

    pub fn push(&self, destination: D) -> bool {
        self.apply((self.core.driver.push)(destination))
    }

    pub fn replace(&self, destination: D) -> bool {
        self.apply((self.core.driver.replace)(destination))
    }

    pub fn back(&self) -> bool {
        self.apply((self.core.driver.back)())
    }

    pub fn forward(&self) -> bool {
        self.apply((self.core.driver.forward)())
    }

    fn apply(&self, change: Option<NavigationChange<D>>) -> bool {
        let Some(change) = change else {
            return false;
        };
        self.core.listeners.emit(&change);
        true
    }
}

struct StackNavigationState<D> {
    entries: Vec<NavigationEntry<D>>,
    current_index: Option<usize>,
    revision: u64,
    next_entry_id: u64,
}

impl<D: Clone> StackNavigationState<D> {
    fn next_entry(&mut self, destination: D) -> NavigationEntry<D> {
        let entry = NavigationEntry {
            id: self.next_entry_id,
            destination,
        };
        self.next_entry_id = self.next_entry_id.wrapping_add(1);
        if self.next_entry_id == 0 {
            self.next_entry_id = 1;
        }
        entry
    }

    fn snapshot(&self) -> NavigationSnapshot<D> {
        NavigationSnapshot {
            entries: self.entries.clone(),
            current_index: self.current_index,
            revision: self.revision,
        }
    }

    fn change(
        &self,
        kind: NavigationChangeKind,
        previous: Option<NavigationEntry<D>>,
    ) -> NavigationChange<D> {
        let snapshot = self.snapshot();
        NavigationChange {
            kind,
            previous,
            current: snapshot.current_entry().cloned(),
            snapshot,
            dirty_domains: NAVIGATION_SCREEN_DIRTY_DOMAINS,
        }
    }
}

pub fn stack_navigation_driver<D: Clone + 'static>(initial_destination: D) -> NavigationDriver<D> {
    let mut initial_state = StackNavigationState {
        entries: Vec::new(),
        current_index: None,
        revision: 0,
        next_entry_id: 1,
    };
    let initial_entry = initial_state.next_entry(initial_destination);
    initial_state.entries.push(initial_entry);
    initial_state.current_index = Some(0);
    let state = Rc::new(RefCell::new(initial_state));

    let snapshot_state = Rc::clone(&state);
    let push_state = Rc::clone(&state);
    let replace_state = Rc::clone(&state);
    let back_state = Rc::clone(&state);
    let forward_state = Rc::clone(&state);

    NavigationDriver::new(
        move || snapshot_state.borrow().snapshot(),
        move |destination| {
            let mut state = push_state.borrow_mut();
            let previous = state.snapshot().current_entry().cloned();
            if let Some(index) = state.current_index {
                state.entries.truncate(index + 1);
            }
            let entry = state.next_entry(destination);
            state.entries.push(entry);
            state.current_index = Some(state.entries.len() - 1);
            state.revision = state.revision.wrapping_add(1);
            Some(state.change(NavigationChangeKind::Push, previous))
        },
        move |destination| {
            let mut state = replace_state.borrow_mut();
            let previous = state.snapshot().current_entry().cloned();
            let entry = state.next_entry(destination);
            if let Some(index) = state
                .current_index
                .filter(|index| *index < state.entries.len())
            {
                state.entries[index] = entry;
            } else {
                state.entries.push(entry);
                state.current_index = Some(state.entries.len() - 1);
            }
            state.revision = state.revision.wrapping_add(1);
            Some(state.change(NavigationChangeKind::Replace, previous))
        },
        move || {
            let mut state = back_state.borrow_mut();
            let index = state.current_index?;
            if index == 0 || index >= state.entries.len() {
                return None;
            }
            let previous = state.snapshot().current_entry().cloned();
            state.current_index = Some(index - 1);
            state.revision = state.revision.wrapping_add(1);
            Some(state.change(NavigationChangeKind::Back, previous))
        },
        move || {
            let mut state = forward_state.borrow_mut();
            let index = state.current_index?;
            if index + 1 >= state.entries.len() {
                return None;
            }
            let previous = state.snapshot().current_entry().cloned();
            state.current_index = Some(index + 1);
            state.revision = state.revision.wrapping_add(1);
            Some(state.change(NavigationChangeKind::Forward, previous))
        },
    )
}
