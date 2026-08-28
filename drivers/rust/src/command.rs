use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe};
use std::rc::{Rc, Weak as RcWeak};
use std::sync::{Arc, Mutex, Weak as SyncWeak};

use crate::{Error, Result, STATUS_INVALID_ARGUMENT, STATUS_INVALID_HANDLE};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandPolicy {
    LatestOnly,
    Ordered,
    Concurrent,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandStatus {
    Queued,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandOfferResult {
    Accepted,
    Backpressure,
    InvalidState,
    Disposed,
}

struct TicketState {
    status: Cell<CommandStatus>,
}

#[derive(Clone)]
pub struct CommandTicket {
    id: u64,
    owner: RcWeak<()>,
    state: Rc<TicketState>,
}

impl CommandTicket {
    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn valid(&self) -> bool {
        self.id != 0 && self.owner.strong_count() != 0
    }

    pub fn status(&self) -> CommandStatus {
        self.state.status.get()
    }
}

impl std::fmt::Debug for CommandTicket {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CommandTicket")
            .field("id", &self.id)
            .field("status", &self.status())
            .finish()
    }
}

enum Completion<O, F> {
    Success {
        run_id: u64,
        value: O,
        weight: usize,
    },
    Failure {
        run_id: u64,
        value: F,
        weight: usize,
    },
}

impl<O, F> Completion<O, F> {
    fn run_id(&self) -> u64 {
        match self {
            Self::Success { run_id, .. } | Self::Failure { run_id, .. } => *run_id,
        }
    }

    fn weight(&self) -> usize {
        match self {
            Self::Success { weight, .. } | Self::Failure { weight, .. } => *weight,
        }
    }
}

struct CompletionState<O, F> {
    items: VecDeque<Completion<O, F>>,
    queued_weight: usize,
    disposed: bool,
    wake: Option<Arc<dyn Fn() + Send + Sync>>,
}

struct CompletionQueue<O, F> {
    state: Mutex<CompletionState<O, F>>,
    max_items: usize,
    max_weight: usize,
}

impl<O, F> CompletionQueue<O, F> {
    fn new(max_items: usize, max_weight: usize) -> Self {
        Self {
            state: Mutex::new(CompletionState {
                items: VecDeque::new(),
                queued_weight: 0,
                disposed: false,
                wake: None,
            }),
            max_items,
            max_weight,
        }
    }

    fn offer(&self, completion: Completion<O, F>) -> CommandOfferResult {
        let wake = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(|failure| failure.into_inner());
            if state.disposed {
                return CommandOfferResult::Disposed;
            }
            let weight = completion.weight();
            if state.items.len() >= self.max_items
                || weight > self.max_weight
                || state.queued_weight > self.max_weight - weight
            {
                return CommandOfferResult::Backpressure;
            }
            let was_empty = state.items.is_empty();
            state.queued_weight += weight;
            state.items.push_back(completion);
            if was_empty {
                state.wake.clone()
            } else {
                None
            }
        };
        if let Some(wake) = wake {
            let _ = catch_unwind(AssertUnwindSafe(|| wake()));
        }
        CommandOfferResult::Accepted
    }

    fn take(&self, maximum: usize) -> Vec<Completion<O, F>> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|failure| failure.into_inner());
        let count = maximum.min(state.items.len());
        let mut result = Vec::with_capacity(count);
        for _ in 0..count {
            let completion = state.items.pop_front().expect("bounded completion count");
            state.queued_weight -= completion.weight();
            result.push(completion);
        }
        result
    }

    fn has_pending(&self) -> bool {
        !self
            .state
            .lock()
            .unwrap_or_else(|failure| failure.into_inner())
            .items
            .is_empty()
    }

    fn set_wake(&self, wake: Option<Arc<dyn Fn() + Send + Sync>>) {
        self.state
            .lock()
            .unwrap_or_else(|failure| failure.into_inner())
            .wake = wake;
    }

    fn close(&self) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|failure| failure.into_inner());
        state.disposed = true;
        state.items.clear();
        state.queued_weight = 0;
        state.wake = None;
    }
}

pub struct CommandSink<O, F> {
    run_id: u64,
    queue: SyncWeak<CompletionQueue<O, F>>,
}

impl<O, F> Clone for CommandSink<O, F> {
    fn clone(&self) -> Self {
        Self {
            run_id: self.run_id,
            queue: self.queue.clone(),
        }
    }
}

impl<O: Send + 'static, F: Send + 'static> CommandSink<O, F> {
    pub fn succeed(&self, value: O) -> CommandOfferResult {
        self.succeed_weighted(value, 1)
    }

    pub fn succeed_weighted(&self, value: O, weight: usize) -> CommandOfferResult {
        self.queue
            .upgrade()
            .map_or(CommandOfferResult::Disposed, |queue| {
                queue.offer(Completion::Success {
                    run_id: self.run_id,
                    value,
                    weight,
                })
            })
    }

    pub fn fail(&self, value: F) -> CommandOfferResult {
        self.fail_weighted(value, 1)
    }

    pub fn fail_weighted(&self, value: F, weight: usize) -> CommandOfferResult {
        self.queue
            .upgrade()
            .map_or(CommandOfferResult::Disposed, |queue| {
                queue.offer(Completion::Failure {
                    run_id: self.run_id,
                    value,
                    weight,
                })
            })
    }
}

pub type CommandCancel = Box<dyn FnOnce()>;
type CommandExecutor<I, O, F> = dyn Fn(I, CommandSink<O, F>) -> Option<CommandCancel>;
type SettledCallback = Rc<dyn Fn(CommandTicket, CommandStatus)>;
type SuccessCallback<O> = Rc<dyn Fn(O)>;
type FailureCallback<F> = Rc<dyn Fn(F)>;
type CancelledCallback = Rc<dyn Fn(CommandTicket)>;

struct Observer {
    id: u64,
    callback: SettledCallback,
}

fn notify_observers_no_unwind(observers: &mut HashMap<u64, Vec<Observer>>, ticket: &CommandTicket) {
    let Some(callbacks) = observers.remove(&ticket.id) else {
        return;
    };
    for observer in callbacks {
        let _ = catch_unwind(AssertUnwindSafe(|| {
            (observer.callback)(ticket.clone(), ticket.status())
        }));
    }
}

struct ActiveRun {
    ticket: CommandTicket,
    cancel: Option<CommandCancel>,
}

struct QueuedRun<I> {
    ticket: CommandTicket,
    input: I,
}

struct CommandCore<I, O, F> {
    policy: CommandPolicy,
    executor: RefCell<Option<Rc<CommandExecutor<I, O, F>>>>,
    queue: Arc<CompletionQueue<O, F>>,
    owner: RefCell<Option<Rc<()>>>,
    active: RefCell<HashMap<u64, ActiveRun>>,
    queued: RefCell<VecDeque<QueuedRun<I>>>,
    observers: RefCell<HashMap<u64, Vec<Observer>>>,
    on_success: RefCell<Option<SuccessCallback<O>>>,
    on_failure: RefCell<Option<FailureCallback<F>>>,
    on_cancelled: RefCell<Option<CancelledCallback>>,
    next_run_id: Cell<u64>,
    next_observer_id: Cell<u64>,
    disposed: Cell<bool>,
}

impl<I: 'static, O: Send + 'static, F: Send + 'static> CommandCore<I, O, F> {
    fn make_ticket(&self) -> CommandTicket {
        let id = self.next_run_id.get();
        let next = id.wrapping_add(1);
        self.next_run_id.set(if next == 0 { 1 } else { next });
        CommandTicket {
            id,
            owner: Rc::downgrade(self.owner.borrow().as_ref().expect("active Command owner")),
            state: Rc::new(TicketState {
                status: Cell::new(CommandStatus::Queued),
            }),
        }
    }

    fn owns(&self, ticket: &CommandTicket) -> bool {
        let owner = self.owner.borrow();
        owner.as_ref().is_some_and(|owner| {
            ticket
                .owner
                .upgrade()
                .is_some_and(|ticket_owner| Rc::ptr_eq(owner, &ticket_owner))
        })
    }

    fn start(&self, queued: QueuedRun<I>) {
        let ticket = queued.ticket.clone();
        ticket.state.status.set(CommandStatus::Running);
        self.active.borrow_mut().insert(
            ticket.id,
            ActiveRun {
                ticket: ticket.clone(),
                cancel: None,
            },
        );
        let executor = self
            .executor
            .borrow()
            .as_ref()
            .expect("active Command executor")
            .clone();
        let result = catch_unwind(AssertUnwindSafe(|| {
            executor(
                queued.input,
                CommandSink {
                    run_id: ticket.id,
                    queue: Arc::downgrade(&self.queue),
                },
            )
        }));
        match result {
            Ok(cancel) => {
                if let Some(active) = self.active.borrow_mut().get_mut(&ticket.id) {
                    active.cancel = cancel;
                } else if let Some(cancel) = cancel {
                    let _ = catch_unwind(AssertUnwindSafe(cancel));
                }
            }
            Err(failure) => {
                self.active.borrow_mut().remove(&ticket.id);
                ticket.state.status.set(CommandStatus::Cancelled);
                let _ = catch_unwind(AssertUnwindSafe(|| self.notify_settled(&ticket)));
                let _ = catch_unwind(AssertUnwindSafe(|| self.start_next_ordered()));
                resume_unwind(failure);
            }
        }
    }

    fn start_next_ordered(&self) {
        if self.policy != CommandPolicy::Ordered || !self.active.borrow().is_empty() {
            return;
        }
        let next = self.queued.borrow_mut().pop_front();
        if let Some(next) = next {
            self.start(next);
        }
    }

    fn mark_cancelled(&self, ticket: CommandTicket, notify: bool) {
        ticket.state.status.set(CommandStatus::Cancelled);
        let mut first_failure =
            catch_unwind(AssertUnwindSafe(|| self.notify_settled(&ticket))).err();
        if notify {
            let callback = self.on_cancelled.borrow().clone();
            if let Some(callback) = callback {
                if let Err(failure) = catch_unwind(AssertUnwindSafe(|| callback(ticket))) {
                    if first_failure.is_none() {
                        first_failure = Some(failure);
                    }
                }
            }
        }
        if let Some(failure) = first_failure {
            resume_unwind(failure);
        }
    }

    fn cancel_active(&self, id: u64, notify: bool) -> bool {
        let Some(mut run) = self.active.borrow_mut().remove(&id) else {
            return false;
        };
        if let Some(cancel) = run.cancel.take() {
            let _ = catch_unwind(AssertUnwindSafe(cancel));
        }
        self.mark_cancelled(run.ticket, notify);
        true
    }

    fn cancel_all_internal(&self, notify: bool) -> usize {
        let active_ids = self.active.borrow().keys().copied().collect::<Vec<_>>();
        let mut count = 0;
        let mut first_failure = None;
        for id in active_ids {
            match catch_unwind(AssertUnwindSafe(|| self.cancel_active(id, notify))) {
                Ok(cancelled) => count += usize::from(cancelled),
                Err(failure) => {
                    count += 1;
                    if first_failure.is_none() {
                        first_failure = Some(failure);
                    }
                }
            }
        }
        loop {
            let queued = self.queued.borrow_mut().pop_back();
            let Some(queued) = queued else {
                break;
            };
            count += 1;
            if let Err(failure) = catch_unwind(AssertUnwindSafe(|| {
                self.mark_cancelled(queued.ticket, notify)
            })) {
                if first_failure.is_none() {
                    first_failure = Some(failure);
                }
            }
        }
        if let Some(failure) = first_failure {
            resume_unwind(failure);
        }
        count
    }

    fn complete(&self, completion: Completion<O, F>) {
        let run_id = completion.run_id();
        let Some(run) = self.active.borrow_mut().remove(&run_id) else {
            return;
        };
        match completion {
            Completion::Success { value, .. } => {
                run.ticket.state.status.set(CommandStatus::Succeeded);
                let mut first_failure =
                    catch_unwind(AssertUnwindSafe(|| self.notify_settled(&run.ticket))).err();
                if let Err(failure) = catch_unwind(AssertUnwindSafe(|| self.start_next_ordered())) {
                    if first_failure.is_none() {
                        first_failure = Some(failure);
                    }
                }
                let callback = self.on_success.borrow().clone();
                if let Some(callback) = callback {
                    if let Err(failure) = catch_unwind(AssertUnwindSafe(|| callback(value))) {
                        if first_failure.is_none() {
                            first_failure = Some(failure);
                        }
                    }
                }
                if let Some(failure) = first_failure {
                    resume_unwind(failure);
                }
            }
            Completion::Failure { value, .. } => {
                run.ticket.state.status.set(CommandStatus::Failed);
                let mut first_failure =
                    catch_unwind(AssertUnwindSafe(|| self.notify_settled(&run.ticket))).err();
                if let Err(failure) = catch_unwind(AssertUnwindSafe(|| self.start_next_ordered())) {
                    if first_failure.is_none() {
                        first_failure = Some(failure);
                    }
                }
                let callback = self.on_failure.borrow().clone();
                if let Some(callback) = callback {
                    if let Err(failure) = catch_unwind(AssertUnwindSafe(|| callback(value))) {
                        if first_failure.is_none() {
                            first_failure = Some(failure);
                        }
                    }
                }
                if let Some(failure) = first_failure {
                    resume_unwind(failure);
                }
            }
        }
    }

    fn notify_settled(&self, ticket: &CommandTicket) {
        let callbacks = self.observers.borrow_mut().remove(&ticket.id);
        let Some(callbacks) = callbacks else {
            return;
        };
        let mut first_failure = None;
        for observer in callbacks {
            if let Err(failure) = catch_unwind(AssertUnwindSafe(|| {
                (observer.callback)(ticket.clone(), ticket.status())
            })) {
                if first_failure.is_none() {
                    first_failure = Some(failure);
                }
            }
        }
        if let Some(failure) = first_failure {
            resume_unwind(failure);
        }
    }

    fn unsubscribe(&self, run_id: u64, observer_id: u64) -> bool {
        let mut observers = self.observers.borrow_mut();
        let Some(bindings) = observers.get_mut(&run_id) else {
            return false;
        };
        let Some(position) = bindings.iter().position(|item| item.id == observer_id) else {
            return false;
        };
        bindings.remove(position);
        if bindings.is_empty() {
            observers.remove(&run_id);
        }
        true
    }

    fn has_observer(&self, run_id: u64, observer_id: u64) -> bool {
        self.observers
            .borrow()
            .get(&run_id)
            .is_some_and(|items| items.iter().any(|item| item.id == observer_id))
    }

    fn dispose(&self) -> bool {
        if self.disposed.replace(true) {
            return false;
        }
        let _ = catch_unwind(AssertUnwindSafe(|| self.cancel_all_internal(false)));
        self.observers.borrow_mut().clear();
        self.executor.borrow_mut().take();
        self.on_success.borrow_mut().take();
        self.on_failure.borrow_mut().take();
        self.on_cancelled.borrow_mut().take();
        self.queue.close();
        self.owner.borrow_mut().take();
        true
    }
}

impl<I, O, F> Drop for CommandCore<I, O, F> {
    fn drop(&mut self) {
        self.queue.close();
        let observers = self.observers.get_mut();
        for (_, mut run) in self.active.get_mut().drain() {
            run.ticket.state.status.set(CommandStatus::Cancelled);
            if let Some(cancel) = run.cancel.take() {
                let _ = catch_unwind(AssertUnwindSafe(cancel));
            }
            notify_observers_no_unwind(observers, &run.ticket);
        }
        for run in self.queued.get_mut().drain(..) {
            run.ticket.state.status.set(CommandStatus::Cancelled);
            notify_observers_no_unwind(observers, &run.ticket);
        }
        observers.clear();
    }
}

#[derive(Clone)]
pub struct Command<I, O, F> {
    core: Rc<CommandCore<I, O, F>>,
}

impl<I: 'static, O: Send + 'static, F: Send + 'static> Command<I, O, F> {
    pub fn new(
        executor: impl Fn(I, CommandSink<O, F>) -> Option<CommandCancel> + 'static,
        policy: CommandPolicy,
        max_pending_completions: usize,
        max_pending_weight: usize,
    ) -> Result<Self> {
        if max_pending_completions == 0 || max_pending_weight == 0 {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Command completion limits must be positive",
            ));
        }
        Ok(Self {
            core: Rc::new(CommandCore {
                policy,
                executor: RefCell::new(Some(Rc::new(executor))),
                queue: Arc::new(CompletionQueue::new(
                    max_pending_completions,
                    max_pending_weight,
                )),
                owner: RefCell::new(Some(Rc::new(()))),
                active: RefCell::new(HashMap::new()),
                queued: RefCell::new(VecDeque::new()),
                observers: RefCell::new(HashMap::new()),
                on_success: RefCell::new(None),
                on_failure: RefCell::new(None),
                on_cancelled: RefCell::new(None),
                next_run_id: Cell::new(1),
                next_observer_id: Cell::new(1),
                disposed: Cell::new(false),
            }),
        })
    }

    pub fn with_defaults(
        executor: impl Fn(I, CommandSink<O, F>) -> Option<CommandCancel> + 'static,
    ) -> Result<Self> {
        Self::new(executor, CommandPolicy::LatestOnly, 256, 4 * 1024 * 1024)
    }

    pub fn policy(&self) -> CommandPolicy {
        self.core.policy
    }

    pub fn disposed(&self) -> bool {
        self.core.disposed.get()
    }

    pub fn on_success(&self, callback: impl Fn(O) + 'static) -> Result<()> {
        self.require_active()?;
        self.core.on_success.replace(Some(Rc::new(callback)));
        Ok(())
    }

    pub fn on_failure(&self, callback: impl Fn(F) + 'static) -> Result<()> {
        self.require_active()?;
        self.core.on_failure.replace(Some(Rc::new(callback)));
        Ok(())
    }

    pub fn on_cancelled(&self, callback: impl Fn(CommandTicket) + 'static) -> Result<()> {
        self.require_active()?;
        self.core.on_cancelled.replace(Some(Rc::new(callback)));
        Ok(())
    }

    pub fn run(&self, input: I) -> Result<CommandTicket> {
        self.require_active()?;
        let ticket = self.core.make_ticket();
        let queued = QueuedRun {
            ticket: ticket.clone(),
            input,
        };
        match self.core.policy {
            CommandPolicy::LatestOnly => {
                self.core.cancel_all_internal(true);
                self.core.start(queued);
            }
            CommandPolicy::Ordered => {
                if self.core.active.borrow().is_empty() {
                    self.core.start(queued);
                } else {
                    self.core.queued.borrow_mut().push_back(queued);
                }
            }
            CommandPolicy::Concurrent => self.core.start(queued),
        }
        Ok(ticket)
    }

    pub fn cancel(&self, ticket: &CommandTicket) -> bool {
        if self.disposed() || !self.core.owns(ticket) {
            return false;
        }
        match catch_unwind(AssertUnwindSafe(|| {
            self.core.cancel_active(ticket.id, true)
        })) {
            Ok(true) => {
                self.core.start_next_ordered();
                return true;
            }
            Ok(false) => {}
            Err(failure) => {
                let _ = catch_unwind(AssertUnwindSafe(|| self.core.start_next_ordered()));
                resume_unwind(failure);
            }
        }
        let position = self
            .core
            .queued
            .borrow()
            .iter()
            .position(|queued| queued.ticket.id == ticket.id);
        let Some(position) = position else {
            return false;
        };
        let cancelled = self
            .core
            .queued
            .borrow_mut()
            .remove(position)
            .expect("queued Command position");
        self.core.mark_cancelled(cancelled.ticket, true);
        true
    }

    pub fn cancel_all(&self) -> usize {
        if self.disposed() {
            0
        } else {
            self.core.cancel_all_internal(true)
        }
    }

    pub fn observe_run(
        &self,
        ticket: &CommandTicket,
        callback: impl Fn(CommandTicket, CommandStatus) + 'static,
    ) -> Result<CommandRunSubscription<I, O, F>> {
        self.require_active()?;
        if !self.core.owns(ticket) {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Command ticket does not belong to this Command",
            ));
        }
        if !matches!(
            ticket.status(),
            CommandStatus::Queued | CommandStatus::Running
        ) {
            callback(ticket.clone(), ticket.status());
            return Ok(CommandRunSubscription::inactive());
        }
        let id = self.core.next_observer_id.get();
        let next = id.wrapping_add(1);
        self.core
            .next_observer_id
            .set(if next == 0 { 1 } else { next });
        self.core
            .observers
            .borrow_mut()
            .entry(ticket.id)
            .or_default()
            .push(Observer {
                id,
                callback: Rc::new(callback),
            });
        Ok(CommandRunSubscription {
            core: Rc::downgrade(&self.core),
            run_id: ticket.id,
            id,
            closed: false,
        })
    }

    pub fn pump(&self, maximum: usize) -> usize {
        if self.disposed() || maximum == 0 {
            return 0;
        }
        let completions = self.core.queue.take(maximum);
        let count = completions.len();
        let mut first_failure = None;
        for completion in completions {
            if let Err(failure) = catch_unwind(AssertUnwindSafe(|| self.core.complete(completion)))
            {
                if first_failure.is_none() {
                    first_failure = Some(failure);
                }
            }
        }
        if let Some(failure) = first_failure {
            resume_unwind(failure);
        }
        count
    }

    pub fn pump_all(&self) -> usize {
        self.pump(usize::MAX)
    }

    pub fn pending(&self) -> bool {
        !self.disposed()
            && (!self.core.active.borrow().is_empty()
                || !self.core.queued.borrow().is_empty()
                || self.core.queue.has_pending())
    }

    pub fn active_count(&self) -> usize {
        if self.disposed() {
            0
        } else {
            self.core.active.borrow().len()
        }
    }

    pub fn queued_count(&self) -> usize {
        if self.disposed() {
            0
        } else {
            self.core.queued.borrow().len()
        }
    }

    pub fn set_wake_callback(&self, callback: impl Fn() + Send + Sync + 'static) {
        if !self.disposed() {
            self.core.queue.set_wake(Some(Arc::new(callback)));
        }
    }

    pub fn clear_wake_callback(&self) {
        if !self.disposed() {
            self.core.queue.set_wake(None);
        }
    }

    pub fn dispose(&self) -> bool {
        self.core.dispose()
    }

    fn require_active(&self) -> Result<()> {
        if self.disposed() {
            Err(Error::status(
                STATUS_INVALID_HANDLE,
                "Command is not active",
            ))
        } else {
            Ok(())
        }
    }
}

pub struct CommandRunSubscription<I, O, F> {
    core: RcWeak<CommandCore<I, O, F>>,
    run_id: u64,
    id: u64,
    closed: bool,
}

impl<I: 'static, O: Send + 'static, F: Send + 'static> CommandRunSubscription<I, O, F> {
    fn inactive() -> Self {
        Self {
            core: RcWeak::new(),
            run_id: 0,
            id: 0,
            closed: true,
        }
    }

    pub fn active(&self) -> bool {
        !self.closed
            && self
                .core
                .upgrade()
                .is_some_and(|core| core.has_observer(self.run_id, self.id))
    }

    pub fn close(&mut self) -> bool {
        if self.closed {
            return false;
        }
        self.closed = true;
        self.core
            .upgrade()
            .is_some_and(|core| core.unsubscribe(self.run_id, self.id))
    }
}

impl<I, O, F> Drop for CommandRunSubscription<I, O, F> {
    fn drop(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        if let Some(core) = self.core.upgrade() {
            let mut observers = core.observers.borrow_mut();
            if let Some(bindings) = observers.get_mut(&self.run_id) {
                if let Some(position) = bindings.iter().position(|item| item.id == self.id) {
                    bindings.remove(position);
                }
                if bindings.is_empty() {
                    observers.remove(&self.run_id);
                }
            }
        }
    }
}

pub fn command<I: 'static, O: Send + 'static, F: Send + 'static>(
    executor: impl Fn(I, CommandSink<O, F>) -> Option<CommandCancel> + 'static,
) -> Result<Command<I, O, F>> {
    Command::with_defaults(executor)
}
