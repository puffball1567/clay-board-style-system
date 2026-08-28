use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::rc::{Rc, Weak};

use crate::{Error, Result, STATUS_INVALID_ARGUMENT, STATUS_INVALID_HANDLE};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CueJoinPolicy {
    All,
    Any,
    Race,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CueStartPolicy {
    Restart,
    Ignore,
    Queue,
    Parallel,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CueSessionStatus {
    Queued,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

pub type CueCancel = Box<dyn FnOnce()>;

struct SessionState {
    status: Cell<CueSessionStatus>,
    failure: RefCell<String>,
}

#[derive(Clone)]
pub struct CueSession {
    id: u64,
    owner: Weak<RefCell<RuntimeCore>>,
    state: Rc<SessionState>,
}

impl CueSession {
    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn valid(&self) -> bool {
        self.id != 0 && self.owner.strong_count() != 0
    }

    pub fn status(&self) -> CueSessionStatus {
        self.state.status.get()
    }

    pub fn failure(&self) -> String {
        self.state.failure.borrow().clone()
    }
}

impl std::fmt::Debug for CueSession {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CueSession")
            .field("id", &self.id)
            .field("status", &self.status())
            .field("failure", &self.failure())
            .finish()
    }
}

struct CompletionState {
    owner: Weak<RefCell<RuntimeCore>>,
    session_id: u64,
    stage_index: usize,
    branch_index: usize,
    settled: Cell<bool>,
}

#[derive(Clone)]
pub struct CueCompletion {
    state: Rc<CompletionState>,
}

impl CueCompletion {
    pub fn succeed(&self) {
        RuntimeCore::settle(&self.state, true, String::new());
    }

    pub fn fail(&self, message: impl Into<String>) -> Result<()> {
        let message = message.into();
        if message.is_empty() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Cue failure message cannot be empty",
            ));
        }
        RuntimeCore::settle(&self.state, false, message);
        Ok(())
    }
}

type CueExecutor = dyn Fn(CueCompletion) -> Option<CueCancel>;

struct ActionState {
    name: String,
    executor: Rc<CueExecutor>,
}

#[derive(Clone)]
pub struct CueAction(Rc<ActionState>);

impl CueAction {
    pub fn name(&self) -> &str {
        &self.0.name
    }
}

pub fn cue_action(name: impl Into<String>, callback: impl Fn() + 'static) -> Result<CueAction> {
    cue_action_with_completion(name, move |completion| {
        callback();
        completion.succeed();
        None
    })
}

pub fn cue_action_with_completion(
    name: impl Into<String>,
    executor: impl Fn(CueCompletion) -> Option<CueCancel> + 'static,
) -> Result<CueAction> {
    let name = name.into();
    if name.is_empty() {
        return Err(Error::status(
            STATUS_INVALID_ARGUMENT,
            "Cue action name cannot be empty",
        ));
    }
    Ok(CueAction(Rc::new(ActionState {
        name,
        executor: Rc::new(executor),
    })))
}

#[derive(Clone)]
pub struct CueBranch {
    action: CueAction,
    delay_seconds: f64,
}

pub fn cue_branch(action: CueAction, delay_seconds: f64) -> Result<CueBranch> {
    if !delay_seconds.is_finite() || delay_seconds < 0.0 {
        return Err(Error::status(
            STATUS_INVALID_ARGUMENT,
            "Cue branch delay must be finite and non-negative",
        ));
    }
    Ok(CueBranch {
        action,
        delay_seconds,
    })
}

pub fn cue_after(delay_seconds: f64, action: CueAction) -> Result<CueBranch> {
    cue_branch(action, delay_seconds)
}

#[derive(Clone)]
struct CueStage {
    branches: Vec<CueBranch>,
    join: CueJoinPolicy,
}

struct GraphState {
    stages: RefCell<Vec<CueStage>>,
    sealed: Cell<bool>,
}

#[derive(Clone)]
pub struct CueGraph(Rc<GraphState>);

pub fn cue(first: CueAction) -> CueGraph {
    CueGraph(Rc::new(GraphState {
        stages: RefCell::new(vec![CueStage {
            branches: vec![CueBranch {
                action: first,
                delay_seconds: 0.0,
            }],
            join: CueJoinPolicy::All,
        }]),
        sealed: Cell::new(false),
    }))
}

impl CueGraph {
    fn require_mutable(&self) -> Result<()> {
        if self.0.sealed.get() {
            return Err(Error::status(
                STATUS_INVALID_HANDLE,
                "a started Cue graph cannot be modified",
            ));
        }
        Ok(())
    }

    pub fn then(self, action: CueAction) -> Result<Self> {
        self.require_mutable()?;
        self.0.stages.borrow_mut().push(CueStage {
            branches: vec![CueBranch {
                action,
                delay_seconds: 0.0,
            }],
            join: CueJoinPolicy::All,
        });
        Ok(self)
    }

    pub fn then_stage(self, branches: Vec<CueBranch>, join: CueJoinPolicy) -> Result<Self> {
        self.require_mutable()?;
        if branches.is_empty() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Cue stage requires at least one branch",
            ));
        }
        self.0.stages.borrow_mut().push(CueStage { branches, join });
        Ok(self)
    }

    pub fn then_parallel(self, actions: Vec<CueAction>) -> Result<Self> {
        self.then_actions(actions, CueJoinPolicy::All)
    }

    pub fn then_any(self, actions: Vec<CueAction>) -> Result<Self> {
        self.then_actions(actions, CueJoinPolicy::Any)
    }

    pub fn then_race(self, actions: Vec<CueAction>) -> Result<Self> {
        self.then_actions(actions, CueJoinPolicy::Race)
    }

    fn then_actions(self, actions: Vec<CueAction>, join: CueJoinPolicy) -> Result<Self> {
        let branches = actions
            .into_iter()
            .map(|action| CueBranch {
                action,
                delay_seconds: 0.0,
            })
            .collect();
        self.then_stage(branches, join)
    }
}

struct ActiveBranch {
    definition: CueBranch,
    completion: Option<Rc<CompletionState>>,
    cancel: Option<CueCancel>,
    started: bool,
    settled: bool,
    succeeded: bool,
}

struct ActiveSession {
    graph: Rc<GraphState>,
    ticket: CueSession,
    stage_index: usize,
    stage_started_at: f64,
    branches: Vec<ActiveBranch>,
    stage_open: bool,
    launching_stage: bool,
    settled_count: usize,
    succeeded_count: usize,
    first_failure: String,
}

struct QueuedSession {
    graph: Rc<GraphState>,
    ticket: CueSession,
}

struct RuntimeCore {
    now: f64,
    host_now: f64,
    rate: f64,
    paused: bool,
    next_session_id: u64,
    sessions: HashMap<u64, Rc<RefCell<ActiveSession>>>,
    active_by_graph: HashMap<usize, Vec<u64>>,
    queued_by_graph: HashMap<usize, VecDeque<QueuedSession>>,
    processing: bool,
    disposed: bool,
}

impl RuntimeCore {
    fn graph_key(graph: &Rc<GraphState>) -> usize {
        Rc::as_ptr(graph) as usize
    }

    fn make_session(core: &Rc<RefCell<Self>>, status: CueSessionStatus) -> Result<CueSession> {
        let id = {
            let mut runtime = core.borrow_mut();
            if runtime.next_session_id == 0 {
                return Err(Error::status(
                    STATUS_INVALID_HANDLE,
                    "Cue session identifier space exhausted",
                ));
            }
            let id = runtime.next_session_id;
            runtime.next_session_id += 1;
            id
        };
        Ok(CueSession {
            id,
            owner: Rc::downgrade(core),
            state: Rc::new(SessionState {
                status: Cell::new(status),
                failure: RefCell::new(String::new()),
            }),
        })
    }

    fn invoke_cancel(branch: &mut ActiveBranch) {
        if let Some(completion) = branch.completion.as_ref() {
            completion.settled.set(true);
        }
        if let Some(cancel) = branch.cancel.take() {
            let _ = catch_unwind(AssertUnwindSafe(cancel));
        }
    }

    fn remove_active(runtime: &mut Self, graph: usize, session_id: u64) {
        let remove = if let Some(ids) = runtime.active_by_graph.get_mut(&graph) {
            ids.retain(|id| *id != session_id);
            ids.is_empty()
        } else {
            false
        };
        if remove {
            runtime.active_by_graph.remove(&graph);
        }
    }

    fn activate_queued(core: &Rc<RefCell<Self>>, graph: usize) {
        let next = {
            let mut runtime = core.borrow_mut();
            if runtime.active_by_graph.contains_key(&graph) {
                return;
            }
            let mut next = None;
            let mut remove_queue = false;
            if let Some(queue) = runtime.queued_by_graph.get_mut(&graph) {
                while queue
                    .front()
                    .is_some_and(|item| item.ticket.status() != CueSessionStatus::Queued)
                {
                    queue.pop_front();
                }
                next = queue.pop_front();
                remove_queue = queue.is_empty();
            }
            if remove_queue {
                runtime.queued_by_graph.remove(&graph);
            }
            next
        };
        let Some(next) = next else {
            return;
        };
        next.ticket.state.status.set(CueSessionStatus::Running);
        let id = next.ticket.id;
        let session = Rc::new(RefCell::new(ActiveSession {
            graph: next.graph,
            ticket: next.ticket,
            stage_index: 0,
            stage_started_at: 0.0,
            branches: Vec::new(),
            stage_open: false,
            launching_stage: false,
            settled_count: 0,
            succeeded_count: 0,
            first_failure: String::new(),
        }));
        let mut runtime = core.borrow_mut();
        runtime.sessions.insert(id, session);
        runtime.active_by_graph.entry(graph).or_default().push(id);
    }

    fn finish_session(
        core: &Rc<RefCell<Self>>,
        session_id: u64,
        status: CueSessionStatus,
        failure: String,
    ) {
        let session = core.borrow_mut().sessions.remove(&session_id);
        let Some(session) = session else {
            return;
        };
        let graph = {
            let mut session = session.borrow_mut();
            for branch in &mut session.branches {
                if !branch.settled {
                    Self::invoke_cancel(branch);
                }
            }
            session.ticket.state.status.set(status);
            *session.ticket.state.failure.borrow_mut() = failure;
            Self::graph_key(&session.graph)
        };
        {
            let mut runtime = core.borrow_mut();
            Self::remove_active(&mut runtime, graph, session_id);
        }
        Self::activate_queued(core, graph);
    }

    fn evaluate_stage(core: &Rc<RefCell<Self>>, session_id: u64) -> bool {
        let session = core.borrow().sessions.get(&session_id).cloned();
        let Some(session) = session else {
            return false;
        };
        let (advance, fail, failure) = {
            let mut session = session.borrow_mut();
            if !session.stage_open || session.launching_stage {
                return false;
            }
            let total = session.branches.len();
            let join = session.graph.stages.borrow()[session.stage_index].join;
            let (advance, fail) = match join {
                CueJoinPolicy::All => (
                    session.settled_count == total && session.succeeded_count == total,
                    session.settled_count > session.succeeded_count,
                ),
                CueJoinPolicy::Any => (
                    session.succeeded_count > 0,
                    session.settled_count == total && session.succeeded_count == 0,
                ),
                CueJoinPolicy::Race => {
                    if session.settled_count == 0 {
                        (false, false)
                    } else {
                        (session.succeeded_count > 0, session.succeeded_count == 0)
                    }
                }
            };
            if !advance && !fail {
                return false;
            }
            session.stage_open = false;
            for branch in &mut session.branches {
                if !branch.settled {
                    Self::invoke_cancel(branch);
                    branch.settled = true;
                }
            }
            (advance, fail, session.first_failure.clone())
        };
        if fail {
            Self::finish_session(core, session_id, CueSessionStatus::Failed, failure);
        } else if advance {
            let mut session = session.borrow_mut();
            session.stage_index += 1;
            session.branches.clear();
        }
        true
    }

    fn settle(completion: &Rc<CompletionState>, succeeded: bool, failure: String) {
        if completion.settled.get() {
            return;
        }
        let Some(core) = completion.owner.upgrade() else {
            completion.settled.set(true);
            return;
        };
        if core.borrow().disposed {
            completion.settled.set(true);
            return;
        }
        let session = core.borrow().sessions.get(&completion.session_id).cloned();
        let Some(session) = session else {
            completion.settled.set(true);
            return;
        };
        {
            let mut session = session.borrow_mut();
            if session.stage_index != completion.stage_index
                || completion.branch_index >= session.branches.len()
                || session.branches[completion.branch_index]
                    .completion
                    .as_ref()
                    .is_none_or(|candidate| !Rc::ptr_eq(candidate, completion))
            {
                completion.settled.set(true);
                return;
            }
            completion.settled.set(true);
            let action_name = {
                let branch = &mut session.branches[completion.branch_index];
                branch.settled = true;
                branch.succeeded = succeeded;
                branch.cancel = None;
                branch.definition.action.name().to_owned()
            };
            session.settled_count += 1;
            if succeeded {
                session.succeeded_count += 1;
            } else if session.first_failure.is_empty() {
                session.first_failure = if failure.is_empty() {
                    format!("Cue action failed: {action_name}")
                } else {
                    failure
                };
            }
        }
        if Self::evaluate_stage(&core, completion.session_id) {
            Self::process(&core);
        }
    }

    fn start_branch(
        core: &Rc<RefCell<Self>>,
        session_id: u64,
        expected_stage: usize,
        branch_index: usize,
    ) {
        let session = core.borrow().sessions.get(&session_id).cloned();
        let Some(session) = session else {
            return;
        };
        let (action, completion) = {
            let mut session = session.borrow_mut();
            if session.stage_index != expected_stage
                || !session.stage_open
                || branch_index >= session.branches.len()
                || session.branches[branch_index].started
            {
                return;
            }
            let completion = Rc::new(CompletionState {
                owner: Rc::downgrade(core),
                session_id,
                stage_index: expected_stage,
                branch_index,
                settled: Cell::new(false),
            });
            let branch = &mut session.branches[branch_index];
            branch.started = true;
            branch.completion = Some(Rc::clone(&completion));
            (branch.definition.action.clone(), completion)
        };
        let execution = catch_unwind(AssertUnwindSafe(|| {
            (action.0.executor)(CueCompletion {
                state: Rc::clone(&completion),
            })
        }));
        match execution {
            Ok(cancel) => {
                let current = { core.borrow().sessions.get(&session_id).cloned() };
                if let Some(session) = current {
                    let mut session = session.borrow_mut();
                    if session.stage_index == expected_stage
                        && branch_index < session.branches.len()
                        && session.branches[branch_index]
                            .completion
                            .as_ref()
                            .is_some_and(|candidate| Rc::ptr_eq(candidate, &completion))
                        && !session.branches[branch_index].settled
                    {
                        session.branches[branch_index].cancel = cancel;
                    }
                }
            }
            Err(_) => Self::settle(&completion, false, "Cue action panicked".to_owned()),
        }
    }

    fn open_stage(core: &Rc<RefCell<Self>>, session_id: u64) {
        let session = core.borrow().sessions.get(&session_id).cloned();
        let Some(session) = session else {
            return;
        };
        let stage = {
            let session = session.borrow();
            let stages = session.graph.stages.borrow();
            stages.get(session.stage_index).cloned()
        };
        let Some(stage) = stage else {
            Self::finish_session(core, session_id, CueSessionStatus::Succeeded, String::new());
            return;
        };
        let expected = {
            let now = core.borrow().now;
            let mut session = session.borrow_mut();
            session.stage_started_at = now;
            session.stage_open = true;
            session.launching_stage = true;
            session.settled_count = 0;
            session.succeeded_count = 0;
            session.first_failure.clear();
            session.branches = stage
                .branches
                .iter()
                .cloned()
                .map(|definition| ActiveBranch {
                    definition,
                    completion: None,
                    cancel: None,
                    started: false,
                    settled: false,
                    succeeded: false,
                })
                .collect();
            session.stage_index
        };
        for (index, definition) in stage.branches.iter().enumerate() {
            let still_open = core
                .borrow()
                .sessions
                .get(&session_id)
                .is_some_and(|current| {
                    let current = current.borrow();
                    current.stage_index == expected && current.stage_open
                });
            if !still_open {
                break;
            }
            if definition.delay_seconds == 0.0 {
                Self::start_branch(core, session_id, expected, index);
            }
        }
        let current = { core.borrow().sessions.get(&session_id).cloned() };
        if let Some(session) = current {
            if session.borrow().stage_index == expected {
                session.borrow_mut().launching_stage = false;
                Self::evaluate_stage(core, session_id);
            }
        }
    }

    fn process(core: &Rc<RefCell<Self>>) {
        {
            let mut runtime = core.borrow_mut();
            if runtime.disposed || runtime.processing {
                return;
            }
            runtime.processing = true;
        }
        let execution = catch_unwind(AssertUnwindSafe(|| {
            let mut changed = true;
            while changed {
                changed = false;
                let mut ids = core.borrow().sessions.keys().copied().collect::<Vec<_>>();
                ids.sort_unstable();
                for id in ids {
                    let session = core.borrow().sessions.get(&id).cloned();
                    let Some(session) = session else {
                        continue;
                    };
                    let before = session.borrow().stage_index;
                    if !session.borrow().stage_open {
                        Self::open_stage(core, id);
                        changed = true;
                    }
                    let session = core.borrow().sessions.get(&id).cloned();
                    let Some(session) = session else {
                        continue;
                    };
                    let (expected, due) = {
                        let now = core.borrow().now;
                        let session = session.borrow();
                        let due = session
                            .branches
                            .iter()
                            .enumerate()
                            .filter_map(|(index, branch)| {
                                (!branch.started
                                    && now
                                        >= session.stage_started_at
                                            + branch.definition.delay_seconds)
                                    .then_some(index)
                            })
                            .collect::<Vec<_>>();
                        (session.stage_index, due)
                    };
                    for index in &due {
                        let current = { core.borrow().sessions.get(&id).cloned() };
                        if let Some(session) = current {
                            if session.borrow().stage_index == expected {
                                session.borrow_mut().launching_stage = true;
                                Self::start_branch(core, id, expected, *index);
                            }
                        }
                    }
                    if !due.is_empty() {
                        let current = { core.borrow().sessions.get(&id).cloned() };
                        if let Some(session) = current {
                            if session.borrow().stage_index == expected {
                                session.borrow_mut().launching_stage = false;
                                Self::evaluate_stage(core, id);
                            }
                        }
                    }
                    Self::evaluate_stage(core, id);
                    let current = { core.borrow().sessions.get(&id).cloned() };
                    match current {
                        None => changed = true,
                        Some(session) if session.borrow().stage_index != before => changed = true,
                        Some(_) => {}
                    }
                }
            }
        }));
        core.borrow_mut().processing = false;
        if let Err(panic) = execution {
            std::panic::resume_unwind(panic);
        }
    }

    fn cancel_by_id(core: &Rc<RefCell<Self>>, id: u64) -> bool {
        if !core.borrow().sessions.contains_key(&id) {
            return false;
        }
        Self::finish_session(core, id, CueSessionStatus::Cancelled, String::new());
        Self::process(core);
        true
    }

    fn dispose(core: &Rc<RefCell<Self>>) -> bool {
        let (sessions, queued) = {
            let mut runtime = core.borrow_mut();
            if runtime.disposed {
                return false;
            }
            runtime.disposed = true;
            let sessions = runtime
                .sessions
                .drain()
                .map(|(_, value)| value)
                .collect::<Vec<_>>();
            let queued = runtime
                .queued_by_graph
                .drain()
                .flat_map(|(_, values)| values)
                .collect::<Vec<_>>();
            runtime.active_by_graph.clear();
            (sessions, queued)
        };
        for session in sessions {
            let mut session = session.borrow_mut();
            for branch in &mut session.branches {
                if !branch.settled {
                    Self::invoke_cancel(branch);
                }
            }
            session.ticket.state.status.set(CueSessionStatus::Cancelled);
        }
        for queued in queued {
            queued.ticket.state.status.set(CueSessionStatus::Cancelled);
        }
        true
    }
}

#[derive(Clone)]
pub struct CueRuntime {
    core: Rc<RefCell<RuntimeCore>>,
}

impl CueRuntime {
    pub fn new(initial_time: f64) -> Result<Self> {
        if !initial_time.is_finite() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Cue runtime time must be finite",
            ));
        }
        Ok(Self {
            core: Rc::new(RefCell::new(RuntimeCore {
                now: initial_time,
                host_now: initial_time,
                rate: 1.0,
                paused: false,
                next_session_id: 1,
                sessions: HashMap::new(),
                active_by_graph: HashMap::new(),
                queued_by_graph: HashMap::new(),
                processing: false,
                disposed: false,
            })),
        })
    }

    pub fn start(&self, graph: &CueGraph, policy: CueStartPolicy) -> Result<CueSession> {
        if self.core.borrow().disposed {
            return Err(Error::status(
                STATUS_INVALID_HANDLE,
                "Cue runtime is not active",
            ));
        }
        graph.0.sealed.set(true);
        let key = RuntimeCore::graph_key(&graph.0);
        let active = self
            .core
            .borrow()
            .active_by_graph
            .get(&key)
            .cloned()
            .unwrap_or_default();
        if policy == CueStartPolicy::Ignore {
            if let Some(session) = active
                .first()
                .and_then(|id| self.core.borrow().sessions.get(id).cloned())
            {
                return Ok(session.borrow().ticket.clone());
            }
        }
        if policy == CueStartPolicy::Restart {
            if let Some(mut queued) = self.core.borrow_mut().queued_by_graph.remove(&key) {
                for item in &mut queued {
                    item.ticket.state.status.set(CueSessionStatus::Cancelled);
                }
            }
            for id in active {
                RuntimeCore::cancel_by_id(&self.core, id);
            }
        } else if policy == CueStartPolicy::Queue && !active.is_empty() {
            let ticket = RuntimeCore::make_session(&self.core, CueSessionStatus::Queued)?;
            self.core
                .borrow_mut()
                .queued_by_graph
                .entry(key)
                .or_default()
                .push_back(QueuedSession {
                    graph: Rc::clone(&graph.0),
                    ticket: ticket.clone(),
                });
            return Ok(ticket);
        }
        let ticket = RuntimeCore::make_session(&self.core, CueSessionStatus::Running)?;
        let session = Rc::new(RefCell::new(ActiveSession {
            graph: Rc::clone(&graph.0),
            ticket: ticket.clone(),
            stage_index: 0,
            stage_started_at: 0.0,
            branches: Vec::new(),
            stage_open: false,
            launching_stage: false,
            settled_count: 0,
            succeeded_count: 0,
            first_failure: String::new(),
        }));
        {
            let mut runtime = self.core.borrow_mut();
            runtime.sessions.insert(ticket.id, session);
            runtime
                .active_by_graph
                .entry(key)
                .or_default()
                .push(ticket.id);
        }
        RuntimeCore::process(&self.core);
        Ok(ticket)
    }

    pub fn cancel(&self, ticket: &CueSession) -> bool {
        if self.core.borrow().disposed
            || !ticket.valid()
            || !Weak::ptr_eq(&ticket.owner, &Rc::downgrade(&self.core))
        {
            return false;
        }
        if RuntimeCore::cancel_by_id(&self.core, ticket.id) {
            return true;
        }
        let mut runtime = self.core.borrow_mut();
        for queue in runtime.queued_by_graph.values_mut() {
            if let Some(item) = queue.iter_mut().find(|item| {
                item.ticket.id == ticket.id && item.ticket.status() == CueSessionStatus::Queued
            }) {
                item.ticket.state.status.set(CueSessionStatus::Cancelled);
                return true;
            }
        }
        false
    }

    pub fn tick(&self, now_seconds: f64) -> Result<()> {
        if !now_seconds.is_finite() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Cue runtime time must be finite",
            ));
        }
        {
            let mut runtime = self.core.borrow_mut();
            if runtime.disposed {
                return Ok(());
            }
            if now_seconds < runtime.host_now {
                return Err(Error::status(
                    STATUS_INVALID_ARGUMENT,
                    "Cue runtime time must be monotonic",
                ));
            }
            let elapsed = now_seconds - runtime.host_now;
            runtime.host_now = now_seconds;
            if !runtime.paused {
                runtime.now += elapsed * runtime.rate;
            } else {
                return Ok(());
            }
        }
        RuntimeCore::process(&self.core);
        Ok(())
    }

    pub fn now(&self) -> f64 {
        self.core.borrow().now
    }

    pub fn paused(&self) -> bool {
        self.core.borrow().paused
    }

    pub fn pause(&self) {
        if !self.core.borrow().disposed {
            self.core.borrow_mut().paused = true;
        }
    }

    pub fn resume(&self) {
        if !self.core.borrow().disposed {
            self.core.borrow_mut().paused = false;
        }
    }

    pub fn rate(&self) -> f64 {
        self.core.borrow().rate
    }

    pub fn set_rate(&self, rate: f64) -> Result<()> {
        if !rate.is_finite() || rate <= 0.0 {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "Cue runtime rate must be finite and positive",
            ));
        }
        let mut runtime = self.core.borrow_mut();
        if runtime.disposed {
            return Err(Error::status(
                STATUS_INVALID_HANDLE,
                "Cue runtime is not active",
            ));
        }
        runtime.rate = rate;
        Ok(())
    }

    pub fn next_deadline(&self) -> Option<f64> {
        let runtime = self.core.borrow();
        if runtime.disposed || runtime.paused {
            return None;
        }
        let mut logical: Option<f64> = None;
        for session in runtime.sessions.values() {
            let session = session.borrow();
            if !session.stage_open {
                continue;
            }
            for branch in &session.branches {
                if !branch.started {
                    let deadline = session.stage_started_at + branch.definition.delay_seconds;
                    logical = Some(logical.map_or(deadline, |current| current.min(deadline)));
                }
            }
        }
        logical.map(|deadline| runtime.host_now + (deadline - runtime.now).max(0.0) / runtime.rate)
    }

    pub fn active_count(&self) -> usize {
        let runtime = self.core.borrow();
        if runtime.disposed {
            0
        } else {
            runtime.sessions.len()
        }
    }

    pub fn active(&self) -> bool {
        !self.core.borrow().disposed
    }

    pub fn dispose(&self) -> bool {
        RuntimeCore::dispose(&self.core)
    }
}

impl Default for CueRuntime {
    fn default() -> Self {
        Self::new(0.0).expect("zero is a finite Cue runtime time")
    }
}

impl Drop for RuntimeCore {
    fn drop(&mut self) {
        for session in self.sessions.values() {
            let mut session = session.borrow_mut();
            for branch in &mut session.branches {
                if !branch.settled {
                    Self::invoke_cancel(branch);
                }
            }
            session.ticket.state.status.set(CueSessionStatus::Cancelled);
        }
        for queue in self.queued_by_graph.values() {
            for queued in queue {
                queued.ticket.state.status.set(CueSessionStatus::Cancelled);
            }
        }
    }
}
