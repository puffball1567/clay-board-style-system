#ifndef CBSS_CUE_HPP
#define CBSS_CUE_HPP

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace cbss {

enum class CueJoinPolicy { all, any, race };
enum class CueStartPolicy { restart, ignore, queue, parallel };
enum class CueSessionStatus { queued, running, succeeded, failed, cancelled };

using CueCancel = std::function<void()>;

namespace cue_detail {
struct RuntimeCore;
struct ActiveSession;
struct QueuedSession;

struct SessionState {
  explicit SessionState(CueSessionStatus initial) : status(initial) {}
  CueSessionStatus status;
  std::string failure;
};

struct CompletionState {
  std::weak_ptr<RuntimeCore> owner;
  std::uint64_t sessionId = 0u;
  std::size_t stageIndex = 0u;
  std::size_t branchIndex = 0u;
  bool settled = false;
};
}  // namespace cue_detail

class CueSession {
 public:
  CueSession() noexcept = default;

  std::uint64_t id() const noexcept { return id_; }
  bool valid() const noexcept {
    return id_ != 0u && !owner_.expired() && state_ != nullptr;
  }
  CueSessionStatus status() const noexcept {
    return state_ ? state_->status : CueSessionStatus::cancelled;
  }
  const std::string& failure() const noexcept {
    static const std::string empty;
    return state_ ? state_->failure : empty;
  }

 private:
  CueSession(std::uint64_t id, const std::shared_ptr<void>& owner,
             std::shared_ptr<cue_detail::SessionState> state)
      : id_(id), owner_(owner), state_(std::move(state)) {}

  std::uint64_t id_ = 0u;
  std::weak_ptr<void> owner_;
  std::shared_ptr<cue_detail::SessionState> state_;

  friend struct cue_detail::RuntimeCore;
  friend class CueRuntime;
};

class CueCompletion {
 public:
  CueCompletion() noexcept = default;
  void succeed() const noexcept;
  void fail(const std::string& message) const;

 private:
  explicit CueCompletion(std::shared_ptr<cue_detail::CompletionState> state)
      : state_(std::move(state)) {}
  std::shared_ptr<cue_detail::CompletionState> state_;

  friend struct cue_detail::RuntimeCore;
};

class CueAction {
 public:
  using Executor = std::function<CueCancel(CueCompletion)>;

  CueAction() noexcept = default;
  CueAction(std::string name, Executor executor)
      : state_(std::make_shared<State>(std::move(name), std::move(executor))) {
    if (state_->name.empty()) {
      throw std::invalid_argument("Cue action name cannot be empty");
    }
    if (!state_->executor) {
      throw std::invalid_argument("Cue action executor cannot be empty");
    }
  }

  const std::string& name() const {
    static const std::string empty;
    return state_ ? state_->name : empty;
  }
  bool valid() const noexcept { return state_ != nullptr; }

 private:
  struct State {
    State(std::string actionName, Executor actionExecutor)
        : name(std::move(actionName)), executor(std::move(actionExecutor)) {}
    std::string name;
    Executor executor;
  };

  std::shared_ptr<State> state_;
  friend struct cue_detail::ActiveSession;
  friend struct cue_detail::QueuedSession;
  friend struct cue_detail::RuntimeCore;
};

inline CueAction cueAction(const std::string& name,
                           CueAction::Executor executor) {
  return CueAction(name, std::move(executor));
}

inline CueAction cueAction(const std::string& name,
                           std::function<void()> callback) {
  if (!callback) {
    throw std::invalid_argument("Cue action callback cannot be empty");
  }
  return CueAction(name, [callback](CueCompletion completion) {
    callback();
    completion.succeed();
    return CueCancel();
  });
}

struct CueBranch {
  CueAction action;
  double delaySeconds = 0.0;
};

inline CueBranch branch(CueAction action, double delay_seconds = 0.0) {
  if (!action.valid()) {
    throw std::invalid_argument("Cue branch action cannot be empty");
  }
  if (!std::isfinite(delay_seconds) || delay_seconds < 0.0) {
    throw std::invalid_argument(
        "Cue branch delay must be finite and non-negative");
  }
  return CueBranch{std::move(action), delay_seconds};
}

inline CueBranch cueAfter(double delay_seconds, CueAction action) {
  return branch(std::move(action), delay_seconds);
}

struct CueStage {
  std::vector<CueBranch> branches;
  CueJoinPolicy join = CueJoinPolicy::all;
};

class CueGraph {
 public:
  CueGraph() noexcept = default;
  explicit CueGraph(CueAction first) : state_(std::make_shared<State>()) {
    state_->stages.push_back(CueStage{{branch(std::move(first))},
                                      CueJoinPolicy::all});
  }

  CueGraph& then(CueAction action) {
    requireMutable();
    state_->stages.push_back(
        CueStage{{branch(std::move(action))}, CueJoinPolicy::all});
    return *this;
  }

  CueGraph& thenStage(std::vector<CueBranch> branches,
                      CueJoinPolicy join = CueJoinPolicy::all) {
    requireMutable();
    if (branches.empty()) {
      throw std::invalid_argument("Cue stage requires at least one branch");
    }
    state_->stages.push_back(CueStage{std::move(branches), join});
    return *this;
  }

  CueGraph& thenParallel(std::initializer_list<CueAction> actions) {
    return thenActions(actions, CueJoinPolicy::all);
  }
  CueGraph& thenAny(std::initializer_list<CueAction> actions) {
    return thenActions(actions, CueJoinPolicy::any);
  }
  CueGraph& thenRace(std::initializer_list<CueAction> actions) {
    return thenActions(actions, CueJoinPolicy::race);
  }

  bool valid() const noexcept {
    return state_ != nullptr && !state_->stages.empty();
  }

 private:
  struct State {
    std::vector<CueStage> stages;
    bool sealed = false;
  };

  void requireMutable() {
    if (!state_) {
      throw std::invalid_argument("Cue graph cannot be empty");
    }
    if (state_->sealed) {
      throw std::logic_error("a started Cue graph cannot be modified");
    }
  }

  CueGraph& thenActions(std::initializer_list<CueAction> actions,
                        CueJoinPolicy join) {
    std::vector<CueBranch> branches;
    branches.reserve(actions.size());
    for (const CueAction& action : actions) {
      branches.push_back(branch(action));
    }
    return thenStage(std::move(branches), join);
  }

  std::shared_ptr<State> state_;
  friend struct cue_detail::ActiveSession;
  friend struct cue_detail::QueuedSession;
  friend struct cue_detail::RuntimeCore;
  friend class CueRuntime;
};

inline CueGraph cue(CueAction first) { return CueGraph(std::move(first)); }

namespace cue_detail {

struct ActiveBranch {
  CueBranch definition;
  std::shared_ptr<CompletionState> completion;
  CueCancel cancel;
  bool started = false;
  bool settled = false;
  bool succeeded = false;
};

struct ActiveSession {
  std::shared_ptr<CueGraph::State> graph;
  CueSession ticket;
  std::size_t stageIndex = 0u;
  double stageStartedAt = 0.0;
  std::vector<ActiveBranch> branches;
  bool stageOpen = false;
  bool launchingStage = false;
  std::size_t settledCount = 0u;
  std::size_t succeededCount = 0u;
  std::string firstFailure;
};

struct QueuedSession {
  std::shared_ptr<CueGraph::State> graph;
  CueSession ticket;
};

struct RuntimeCore : std::enable_shared_from_this<RuntimeCore> {
  explicit RuntimeCore(double initial) : nowValue(initial), hostNowValue(initial) {}
  ~RuntimeCore() { dispose(); }

  CueSession makeSession(CueSessionStatus status) {
    if (nextSessionId == 0u) {
      throw std::overflow_error("Cue session identifier space exhausted");
    }
    const std::shared_ptr<SessionState> state =
        std::make_shared<SessionState>(status);
    return CueSession(nextSessionId++, shared_from_this(), std::move(state));
  }

  void invokeCancel(ActiveBranch& branch) noexcept {
    CueCancel callback = std::move(branch.cancel);
    if (branch.completion) {
      branch.completion->owner.reset();
      branch.completion->settled = true;
    }
    if (callback) {
      try {
        callback();
      } catch (...) {
      }
    }
  }

  void removeActive(const void* graph, std::uint64_t session_id) {
    const auto found = activeByGraph.find(graph);
    if (found == activeByGraph.end()) return;
    std::vector<std::uint64_t>& ids = found->second;
    ids.erase(std::remove(ids.begin(), ids.end(), session_id), ids.end());
    if (ids.empty()) activeByGraph.erase(found);
  }

  void activateQueued(const void* graph) {
    if (activeByGraph.count(graph) != 0u) return;
    const auto found = queuedByGraph.find(graph);
    if (found == queuedByGraph.end()) return;
    std::deque<QueuedSession>& queue = found->second;
    while (!queue.empty() &&
           queue.front().ticket.status() != CueSessionStatus::queued) {
      queue.pop_front();
    }
    if (queue.empty()) {
      queuedByGraph.erase(found);
      return;
    }
    QueuedSession next = std::move(queue.front());
    queue.pop_front();
    if (queue.empty()) queuedByGraph.erase(graph);
    next.ticket.state_->status = CueSessionStatus::running;
    const std::uint64_t id = next.ticket.id();
    std::shared_ptr<ActiveSession> active = std::make_shared<ActiveSession>();
    active->graph = std::move(next.graph);
    active->ticket = next.ticket;
    sessions[id] = std::move(active);
    activeByGraph[graph].push_back(id);
  }

  void finishSession(std::uint64_t session_id, CueSessionStatus status,
                     std::string failure = std::string()) {
    const auto found = sessions.find(session_id);
    if (found == sessions.end()) return;
    const std::shared_ptr<ActiveSession> session = found->second;
    for (ActiveBranch& branch : session->branches) {
      if (!branch.settled) invokeCancel(branch);
    }
    session->ticket.state_->status = status;
    session->ticket.state_->failure = std::move(failure);
    const void* graph = session->graph.get();
    sessions.erase(found);
    removeActive(graph, session_id);
    activateQueued(graph);
  }

  bool evaluateStage(std::uint64_t session_id) {
    const auto found = sessions.find(session_id);
    if (found == sessions.end()) return false;
    const std::shared_ptr<ActiveSession> session = found->second;
    if (!session->stageOpen || session->launchingStage) return false;
    const std::size_t total = session->branches.size();
    bool advance = false;
    bool fail = false;
    switch (session->graph->stages[session->stageIndex].join) {
      case CueJoinPolicy::all:
        fail = session->settledCount > session->succeededCount;
        advance = session->settledCount == total &&
                  session->succeededCount == total;
        break;
      case CueJoinPolicy::any:
        advance = session->succeededCount > 0u;
        fail = session->settledCount == total &&
               session->succeededCount == 0u;
        break;
      case CueJoinPolicy::race:
        if (session->settledCount > 0u) {
          advance = session->succeededCount > 0u;
          fail = !advance;
        }
        break;
    }
    if (!advance && !fail) return false;
    session->stageOpen = false;
    for (ActiveBranch& branch : session->branches) {
      if (!branch.settled) {
        invokeCancel(branch);
        branch.settled = true;
      }
    }
    if (fail) {
      finishSession(session_id, CueSessionStatus::failed,
                    session->firstFailure);
    } else {
      ++session->stageIndex;
      session->branches.clear();
    }
    return true;
  }

  void settle(const std::shared_ptr<CompletionState>& completion,
              bool succeeded, const std::string& failure) noexcept {
    if (disposed || !completion || completion->settled) return;
    const auto found = sessions.find(completion->sessionId);
    if (found == sessions.end()) {
      completion->owner.reset();
      completion->settled = true;
      return;
    }
    const std::shared_ptr<ActiveSession> session = found->second;
    if (session->stageIndex != completion->stageIndex ||
        completion->branchIndex >= session->branches.size() ||
        session->branches[completion->branchIndex].completion != completion) {
      completion->owner.reset();
      completion->settled = true;
      return;
    }
    completion->settled = true;
    completion->owner.reset();
    ActiveBranch& branch = session->branches[completion->branchIndex];
    branch.settled = true;
    branch.succeeded = succeeded;
    branch.cancel = CueCancel();
    ++session->settledCount;
    if (succeeded) {
      ++session->succeededCount;
    } else if (session->firstFailure.empty()) {
      session->firstFailure = failure.empty()
          ? "Cue action failed: " + branch.definition.action.name()
          : failure;
    }
    if (evaluateStage(completion->sessionId)) process();
  }

  void startBranch(std::uint64_t session_id, std::size_t expected_stage,
                   std::size_t branch_index) {
    const auto found = sessions.find(session_id);
    if (found == sessions.end()) return;
    const std::shared_ptr<ActiveSession> session = found->second;
    if (session->stageIndex != expected_stage || !session->stageOpen ||
        branch_index >= session->branches.size() ||
        session->branches[branch_index].started) {
      return;
    }
    ActiveBranch& branch = session->branches[branch_index];
    branch.started = true;
    const std::shared_ptr<CompletionState> completion =
        std::make_shared<CompletionState>();
    completion->owner = shared_from_this();
    completion->sessionId = session_id;
    completion->stageIndex = expected_stage;
    completion->branchIndex = branch_index;
    branch.completion = completion;
    const CueAction action = branch.definition.action;
    try {
      CueCancel cancel = action.state_->executor(CueCompletion(completion));
      const auto current = sessions.find(session_id);
      if (current != sessions.end() &&
          current->second->stageIndex == expected_stage &&
          branch_index < current->second->branches.size()) {
        ActiveBranch& active = current->second->branches[branch_index];
        if (active.completion == completion && !active.settled) {
          active.cancel = std::move(cancel);
        }
      }
    } catch (const std::exception& error) {
      settle(completion, false, error.what());
    } catch (...) {
      settle(completion, false, "Cue action threw a non-standard exception");
    }
  }

  void openStage(std::uint64_t session_id) {
    const auto found = sessions.find(session_id);
    if (found == sessions.end()) return;
    const std::shared_ptr<ActiveSession> session = found->second;
    if (session->stageIndex >= session->graph->stages.size()) {
      finishSession(session_id, CueSessionStatus::succeeded);
      return;
    }
    const CueStage& stage = session->graph->stages[session->stageIndex];
    session->stageStartedAt = nowValue;
    session->stageOpen = true;
    session->launchingStage = true;
    session->settledCount = 0u;
    session->succeededCount = 0u;
    session->firstFailure.clear();
    session->branches.clear();
    session->branches.reserve(stage.branches.size());
    for (const CueBranch& definition : stage.branches) {
      ActiveBranch active;
      active.definition = definition;
      session->branches.push_back(std::move(active));
    }
    const std::size_t expected = session->stageIndex;
    for (std::size_t index = 0u; index < stage.branches.size(); ++index) {
      const auto current = sessions.find(session_id);
      if (current == sessions.end() || current->second->stageIndex != expected ||
          !current->second->stageOpen) {
        break;
      }
      if (stage.branches[index].delaySeconds == 0.0) {
        startBranch(session_id, expected, index);
      }
    }
    const auto current = sessions.find(session_id);
    if (current != sessions.end() && current->second->stageIndex == expected) {
      current->second->launchingStage = false;
      evaluateStage(session_id);
    }
  }

  void process() {
    if (disposed || processing) return;
    processing = true;
    try {
      bool changed = true;
      while (changed) {
        changed = false;
        std::vector<std::uint64_t> ids;
        ids.reserve(sessions.size());
        for (const auto& item : sessions) ids.push_back(item.first);
        std::sort(ids.begin(), ids.end());
        for (const std::uint64_t id : ids) {
          auto found = sessions.find(id);
          if (found == sessions.end()) continue;
          const std::size_t before = found->second->stageIndex;
          if (!found->second->stageOpen) {
            openStage(id);
            changed = true;
          }
          found = sessions.find(id);
          if (found == sessions.end()) continue;
          const std::size_t expected = found->second->stageIndex;
          std::vector<std::size_t> due;
          for (std::size_t index = 0u;
               index < found->second->branches.size(); ++index) {
            const ActiveBranch& active = found->second->branches[index];
            if (!active.started && nowValue >= found->second->stageStartedAt +
                                                active.definition.delaySeconds) {
              due.push_back(index);
            }
          }
          for (const std::size_t index : due) {
            found = sessions.find(id);
            if (found != sessions.end() &&
                found->second->stageIndex == expected) {
              found->second->launchingStage = true;
              startBranch(id, expected, index);
            }
          }
          found = sessions.find(id);
          if (!due.empty() && found != sessions.end() &&
              found->second->stageIndex == expected) {
            found->second->launchingStage = false;
            evaluateStage(id);
          }
          found = sessions.find(id);
          if (found != sessions.end()) {
            evaluateStage(id);
            found = sessions.find(id);
            if (found == sessions.end() || found->second->stageIndex != before) {
              changed = true;
            }
          } else {
            changed = true;
          }
        }
      }
    } catch (...) {
      processing = false;
      throw;
    }
    processing = false;
  }

  CueSession start(CueGraph graph, CueStartPolicy policy) {
    if (disposed || !graph.valid()) {
      throw std::invalid_argument("Cue runtime and graph must be active");
    }
    graph.state_->sealed = true;
    const void* key = graph.state_.get();
    std::vector<std::uint64_t> active = activeByGraph[key];
    if (policy == CueStartPolicy::ignore && !active.empty()) {
      const auto found = sessions.find(active.front());
      if (found != sessions.end()) return found->second->ticket;
    }
    if (policy == CueStartPolicy::restart) {
      auto queued = queuedByGraph.find(key);
      if (queued != queuedByGraph.end()) {
        for (QueuedSession& item : queued->second) {
          item.ticket.state_->status = CueSessionStatus::cancelled;
        }
        queuedByGraph.erase(queued);
      }
      for (const std::uint64_t id : active) cancelById(id);
    } else if (policy == CueStartPolicy::queue && !active.empty()) {
      CueSession ticket = makeSession(CueSessionStatus::queued);
      queuedByGraph[key].push_back(QueuedSession{graph.state_, ticket});
      return ticket;
    }

    CueSession ticket = makeSession(CueSessionStatus::running);
    std::shared_ptr<ActiveSession> session = std::make_shared<ActiveSession>();
    session->graph = graph.state_;
    session->ticket = ticket;
    sessions[ticket.id()] = std::move(session);
    activeByGraph[key].push_back(ticket.id());
    process();
    return ticket;
  }

  bool cancelById(std::uint64_t id) {
    if (sessions.count(id) == 0u) return false;
    finishSession(id, CueSessionStatus::cancelled);
    process();
    return true;
  }

  bool cancel(const CueSession& ticket) {
    if (disposed || !ticket.valid() ||
        ticket.owner_.lock().get() != shared_from_this().get()) {
      return false;
    }
    if (cancelById(ticket.id())) return true;
    for (auto& item : queuedByGraph) {
      for (QueuedSession& queued : item.second) {
        if (queued.ticket.id() == ticket.id() &&
            queued.ticket.status() == CueSessionStatus::queued) {
          queued.ticket.state_->status = CueSessionStatus::cancelled;
          return true;
        }
      }
    }
    return false;
  }

  void tick(double now_seconds) {
    if (disposed) return;
    if (!std::isfinite(now_seconds)) {
      throw std::invalid_argument("Cue runtime time must be finite");
    }
    if (now_seconds < hostNowValue) {
      throw std::invalid_argument("Cue runtime time must be monotonic");
    }
    const double elapsed = now_seconds - hostNowValue;
    hostNowValue = now_seconds;
    if (!pausedValue) {
      nowValue += elapsed * rateValue;
      process();
    }
  }

  double nextDeadline() const noexcept {
    if (disposed || pausedValue) {
      return std::numeric_limits<double>::quiet_NaN();
    }
    double logical = std::numeric_limits<double>::infinity();
    for (const auto& item : sessions) {
      const ActiveSession& session = *item.second;
      if (!session.stageOpen) continue;
      for (const ActiveBranch& branch : session.branches) {
        if (!branch.started) {
          logical = std::min(logical, session.stageStartedAt +
                                          branch.definition.delaySeconds);
        }
      }
    }
    if (!std::isfinite(logical)) {
      return std::numeric_limits<double>::quiet_NaN();
    }
    const double remaining = std::max(0.0, logical - nowValue);
    return hostNowValue + remaining / rateValue;
  }

  void dispose() noexcept {
    if (disposed) return;
    disposed = true;
    for (auto& item : sessions) {
      const std::shared_ptr<ActiveSession>& session = item.second;
      for (ActiveBranch& branch : session->branches) {
        if (!branch.settled) invokeCancel(branch);
      }
      session->ticket.state_->status = CueSessionStatus::cancelled;
    }
    for (auto& item : queuedByGraph) {
      for (QueuedSession& queued : item.second) {
        queued.ticket.state_->status = CueSessionStatus::cancelled;
      }
    }
    sessions.clear();
    activeByGraph.clear();
    queuedByGraph.clear();
  }

  double nowValue;
  double hostNowValue;
  double rateValue = 1.0;
  bool pausedValue = false;
  std::uint64_t nextSessionId = 1u;
  std::unordered_map<std::uint64_t, std::shared_ptr<ActiveSession>> sessions;
  std::unordered_map<const void*, std::vector<std::uint64_t>> activeByGraph;
  std::unordered_map<const void*, std::deque<QueuedSession>> queuedByGraph;
  bool processing = false;
  bool disposed = false;
};

}  // namespace cue_detail

inline void CueCompletion::succeed() const noexcept {
  if (!state_ || state_->settled) return;
  const std::shared_ptr<cue_detail::RuntimeCore> owner = state_->owner.lock();
  if (owner) owner->settle(state_, true, std::string());
}

inline void CueCompletion::fail(const std::string& message) const {
  if (message.empty()) {
    throw std::invalid_argument("Cue failure message cannot be empty");
  }
  if (!state_ || state_->settled) return;
  const std::shared_ptr<cue_detail::RuntimeCore> owner = state_->owner.lock();
  if (owner) owner->settle(state_, false, message);
}

class CueRuntime {
 public:
  explicit CueRuntime(double initial_time = 0.0) {
    if (!std::isfinite(initial_time)) {
      throw std::invalid_argument("Cue runtime time must be finite");
    }
    core_ = std::make_shared<cue_detail::RuntimeCore>(initial_time);
  }

  CueSession start(CueGraph graph,
                   CueStartPolicy policy = CueStartPolicy::restart) {
    requireActive();
    return core_->start(std::move(graph), policy);
  }
  bool cancel(const CueSession& ticket) {
    return core_ && core_->cancel(ticket);
  }
  void tick(double now_seconds) {
    requireActive();
    core_->tick(now_seconds);
  }
  double now() const noexcept { return core_ ? core_->nowValue : 0.0; }
  bool paused() const noexcept { return core_ && core_->pausedValue; }
  void pause() noexcept {
    if (core_ && !core_->disposed) core_->pausedValue = true;
  }
  void resume() noexcept {
    if (core_ && !core_->disposed) core_->pausedValue = false;
  }
  double rate() const noexcept { return core_ ? core_->rateValue : 1.0; }
  void setRate(double value) {
    requireActive();
    if (!std::isfinite(value) || value <= 0.0) {
      throw std::invalid_argument(
          "Cue runtime rate must be finite and positive");
    }
    core_->rateValue = value;
  }
  double nextDeadline() const noexcept {
    return core_ ? core_->nextDeadline()
                 : std::numeric_limits<double>::quiet_NaN();
  }
  bool hasDeadline() const noexcept { return std::isfinite(nextDeadline()); }
  std::size_t activeCount() const noexcept {
    return core_ && !core_->disposed ? core_->sessions.size() : 0u;
  }
  bool active() const noexcept { return core_ && !core_->disposed; }
  void dispose() noexcept {
    if (core_) core_->dispose();
  }

 private:
  void requireActive() const {
    if (!active()) throw std::logic_error("Cue runtime is not active");
  }
  std::shared_ptr<cue_detail::RuntimeCore> core_;
};

}  // namespace cbss

#endif
