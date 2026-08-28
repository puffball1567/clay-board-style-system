use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe};
use std::rc::Rc;

type SignalListener<T> = Rc<dyn Fn(&T)>;
type StoreReducer<S, A> = Box<dyn Fn(&mut S, &A)>;
type SelectorEquality<T> = Box<dyn Fn(&T, &T) -> bool>;

pub struct StoreSubscription {
    close: Option<Box<dyn FnOnce() -> bool>>,
    active: Box<dyn Fn() -> bool>,
}

impl StoreSubscription {
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

impl Drop for StoreSubscription {
    fn drop(&mut self) {
        let _ = self.close();
    }
}

struct Binding<T> {
    id: u64,
    listener: Option<SignalListener<T>>,
    active: bool,
}

struct SignalCore<T> {
    bindings: RefCell<Vec<Binding<T>>>,
    index: RefCell<HashMap<u64, usize>>,
    next_id: Cell<u64>,
    emit_depth: Cell<usize>,
    inactive_count: Cell<usize>,
}

impl<T: 'static> SignalCore<T> {
    fn new() -> Rc<Self> {
        Rc::new(Self {
            bindings: RefCell::new(Vec::new()),
            index: RefCell::new(HashMap::new()),
            next_id: Cell::new(1),
            emit_depth: Cell::new(0),
            inactive_count: Cell::new(0),
        })
    }

    fn subscribe(self: &Rc<Self>, listener: impl Fn(&T) + 'static) -> StoreSubscription {
        let id = self.next_id.get();
        let next = id.wrapping_add(1);
        self.next_id.set(if next == 0 { 1 } else { next });
        let mut bindings = self.bindings.borrow_mut();
        let position = bindings.len();
        bindings.push(Binding {
            id,
            listener: Some(Rc::new(listener)),
            active: true,
        });
        drop(bindings);
        self.index.borrow_mut().insert(id, position);

        let weak_close = Rc::downgrade(self);
        let weak_active = weak_close.clone();
        StoreSubscription {
            close: Some(Box::new(move || {
                if let Some(source) = weak_close.upgrade() {
                    source.unsubscribe(id)
                } else {
                    false
                }
            })),
            active: Box::new(move || {
                weak_active
                    .upgrade()
                    .is_some_and(|source| source.contains(id))
            }),
        }
    }

    fn emit(&self, value: &T) {
        self.emit_depth.set(self.emit_depth.get() + 1);
        let count = self.bindings.borrow().len();
        let mut first_failure = None;

        for position in 0..count {
            let listener = {
                let bindings = self.bindings.borrow();
                let binding = &bindings[position];
                if binding.active {
                    binding.listener.clone()
                } else {
                    None
                }
            };
            if let Some(listener) = listener {
                if let Err(failure) = catch_unwind(AssertUnwindSafe(|| listener(value))) {
                    if first_failure.is_none() {
                        first_failure = Some(failure);
                    }
                }
            }
        }

        self.emit_depth.set(self.emit_depth.get() - 1);
        if self.emit_depth.get() == 0 {
            self.compact();
        }
        if let Some(failure) = first_failure {
            resume_unwind(failure);
        }
    }

    fn contains(&self, id: u64) -> bool {
        self.index.borrow().contains_key(&id)
    }

    fn listener_count(&self) -> usize {
        self.index.borrow().len()
    }

    fn unsubscribe(&self, id: u64) -> bool {
        let Some(position) = self.index.borrow_mut().remove(&id) else {
            return false;
        };
        if self.emit_depth.get() > 0 {
            let mut bindings = self.bindings.borrow_mut();
            bindings[position].active = false;
            bindings[position].listener = None;
            self.inactive_count.set(self.inactive_count.get() + 1);
        } else {
            self.bindings.borrow_mut().remove(position);
            self.rebuild_index();
        }
        true
    }

    fn clear(&self) {
        self.index.borrow_mut().clear();
        if self.emit_depth.get() == 0 {
            self.bindings.borrow_mut().clear();
            self.inactive_count.set(0);
            return;
        }
        let mut bindings = self.bindings.borrow_mut();
        for binding in bindings.iter_mut() {
            if binding.active {
                binding.active = false;
                binding.listener = None;
                self.inactive_count.set(self.inactive_count.get() + 1);
            }
        }
    }

    fn compact(&self) {
        if self.inactive_count.get() == 0 {
            return;
        }
        self.bindings.borrow_mut().retain(|binding| binding.active);
        self.inactive_count.set(0);
        self.rebuild_index();
    }

    fn rebuild_index(&self) {
        let bindings = self.bindings.borrow();
        let mut index = self.index.borrow_mut();
        index.clear();
        for (position, binding) in bindings.iter().enumerate() {
            if binding.active {
                index.insert(binding.id, position);
            }
        }
    }
}

struct StoreCore<S, A> {
    state: RefCell<S>,
    reducer: StoreReducer<S, A>,
    commits: Rc<SignalCore<u64>>,
    pending_actions: RefCell<VecDeque<A>>,
    revision: Cell<u64>,
    transaction_depth: Cell<usize>,
    pending_commit: Cell<bool>,
    processing: Cell<bool>,
}

impl<S: 'static, A: 'static> StoreCore<S, A> {
    fn publish_commit(&self) {
        if !self.pending_commit.replace(false) {
            return;
        }
        let revision = self.revision.get().wrapping_add(1);
        self.revision.set(revision);
        self.commits.emit(&revision);
    }

    fn drain(&self) {
        if self.processing.replace(true) {
            return;
        }
        let mut first_failure = None;

        loop {
            let action = self.pending_actions.borrow_mut().pop_front();
            let Some(action) = action else {
                break;
            };
            let reduced = catch_unwind(AssertUnwindSafe(|| {
                (self.reducer)(&mut self.state.borrow_mut(), &action);
            }));
            match reduced {
                Ok(()) => {
                    self.pending_commit.set(true);
                    if self.transaction_depth.get() == 0 {
                        if let Err(failure) =
                            catch_unwind(AssertUnwindSafe(|| self.publish_commit()))
                        {
                            if first_failure.is_none() {
                                first_failure = Some(failure);
                            }
                        }
                    }
                }
                Err(failure) => {
                    if first_failure.is_none() {
                        first_failure = Some(failure);
                    }
                }
            }
        }

        if self.transaction_depth.get() == 0 && self.pending_commit.get() {
            if let Err(failure) = catch_unwind(AssertUnwindSafe(|| self.publish_commit())) {
                if first_failure.is_none() {
                    first_failure = Some(failure);
                }
            }
        }
        self.processing.set(false);
        if let Some(failure) = first_failure {
            resume_unwind(failure);
        }
    }
}

pub struct Store<S, A> {
    core: Rc<StoreCore<S, A>>,
}

impl<S, A> Clone for Store<S, A> {
    fn clone(&self) -> Self {
        Self {
            core: Rc::clone(&self.core),
        }
    }
}

impl<S: 'static, A: 'static> Store<S, A> {
    pub fn new(initial_state: S, reducer: impl Fn(&mut S, &A) + 'static) -> Self {
        Self {
            core: Rc::new(StoreCore {
                state: RefCell::new(initial_state),
                reducer: Box::new(reducer),
                commits: SignalCore::new(),
                pending_actions: RefCell::new(VecDeque::new()),
                revision: Cell::new(0),
                transaction_depth: Cell::new(0),
                pending_commit: Cell::new(false),
                processing: Cell::new(false),
            }),
        }
    }

    pub fn state(&self) -> S
    where
        S: Clone,
    {
        self.core.state.borrow().clone()
    }

    pub fn with_state<R>(&self, read: impl FnOnce(&S) -> R) -> R {
        read(&self.core.state.borrow())
    }

    pub fn revision(&self) -> u64 {
        self.core.revision.get()
    }

    pub fn subscriber_count(&self) -> usize {
        self.core.commits.listener_count()
    }

    pub fn dispatch(&self, action: A) {
        self.core.pending_actions.borrow_mut().push_back(action);
        self.core.drain();
    }

    pub fn dispatch_silent(&self, action: &A) {
        (self.core.reducer)(&mut self.core.state.borrow_mut(), action);
    }

    pub fn transaction<R>(&self, body: impl FnOnce() -> R) -> R {
        self.core
            .transaction_depth
            .set(self.core.transaction_depth.get() + 1);
        let body_result = catch_unwind(AssertUnwindSafe(body));
        self.core
            .transaction_depth
            .set(self.core.transaction_depth.get() - 1);
        let commit_result = if self.core.transaction_depth.get() == 0 {
            catch_unwind(AssertUnwindSafe(|| self.core.drain()))
        } else {
            Ok(())
        };

        match body_result {
            Ok(value) => {
                if let Err(failure) = commit_result {
                    resume_unwind(failure);
                }
                value
            }
            Err(failure) => resume_unwind(failure),
        }
    }

    pub fn subscribe(&self, listener: impl Fn(u64) + 'static) -> StoreSubscription {
        self.core
            .commits
            .subscribe(move |revision| listener(*revision))
    }

    pub fn select<T: Clone + PartialEq + 'static>(
        &self,
        projection: impl Fn(&S) -> T + 'static,
    ) -> Selector<T> {
        self.select_by(projection, |left, right| left == right)
    }

    pub fn select_by<T: Clone + 'static>(
        &self,
        projection: impl Fn(&S) -> T + 'static,
        equal: impl Fn(&T, &T) -> bool + 'static,
    ) -> Selector<T> {
        let project: Rc<dyn Fn(&S) -> T> = Rc::new(projection);
        let initial = project(&self.core.state.borrow());
        let core = Rc::new(SelectorCore {
            value: RefCell::new(initial),
            equal: Box::new(equal),
            changes: SignalCore::new(),
            source: RefCell::new(None),
            refresh_value: {
                let source = Rc::clone(&self.core);
                let project = project.clone();
                Box::new(move || {
                    let selected = project(&source.state.borrow());
                    selected
                })
            },
            disposed: Cell::new(false),
        });
        let weak_selected = Rc::downgrade(&core);
        let source_store = Rc::downgrade(&self.core);
        let source = self.core.commits.subscribe(move |_revision| {
            if let Some(selected) = weak_selected.upgrade() {
                if !selected.disposed.get() {
                    if let Some(source) = source_store.upgrade() {
                        selected.set(project(&source.state.borrow()));
                    }
                }
            }
        });
        core.source.borrow_mut().replace(source);
        Selector { core }
    }
}

struct SelectorCore<T> {
    value: RefCell<T>,
    equal: SelectorEquality<T>,
    changes: Rc<SignalCore<T>>,
    source: RefCell<Option<StoreSubscription>>,
    refresh_value: Box<dyn Fn() -> T>,
    disposed: Cell<bool>,
}

impl<T: Clone + 'static> SelectorCore<T> {
    fn set(&self, next: T) {
        if (self.equal)(&self.value.borrow(), &next) {
            return;
        }
        self.value.replace(next);
        let current = self.value.borrow().clone();
        self.changes.emit(&current);
    }
}

#[derive(Clone)]
pub struct Selector<T> {
    core: Rc<SelectorCore<T>>,
}

impl<T: Clone + 'static> Selector<T> {
    pub fn value(&self) -> T {
        self.require_active();
        self.core.value.borrow().clone()
    }

    pub fn disposed(&self) -> bool {
        self.core.disposed.get()
    }

    pub fn subscriber_count(&self) -> usize {
        if self.disposed() {
            0
        } else {
            self.core.changes.listener_count()
        }
    }

    pub fn subscribe(&self, listener: impl Fn(&T) + 'static) -> StoreSubscription {
        self.require_active();
        self.core.changes.subscribe(listener)
    }

    pub fn refresh(&self) {
        self.require_active();
        self.core.set((self.core.refresh_value)());
    }

    pub fn dispose(&self) -> bool {
        if self.core.disposed.replace(true) {
            return false;
        }
        if let Some(mut source) = self.core.source.borrow_mut().take() {
            source.close();
        }
        self.core.changes.clear();
        true
    }

    fn require_active(&self) {
        assert!(!self.disposed(), "Selector is disposed");
    }
}
