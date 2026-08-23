#ifndef CBSS_COMMAND_HPP
#define CBSS_COMMAND_HPP

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <exception>
#include <functional>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace cbss {

enum class CommandPolicy {
  latestOnly,
  ordered,
  concurrent,
};

enum class CommandStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
};

enum class CommandOfferResult {
  accepted,
  backpressure,
  invalidState,
  disposed,
};

namespace command_detail {

struct TicketState {
  explicit TicketState(CommandStatus initial) : status(initial) {}
  std::atomic<CommandStatus> status;
};

template <typename Output, typename Failure>
struct Completion {
  enum class Kind { success, failure };

  Completion(std::uint64_t run, Output value, std::int64_t completion_weight)
      : kind(Kind::success),
        run_id(run),
        output(new Output(std::move(value))),
        weight(completion_weight) {}

  Completion(std::uint64_t run, Failure value, std::int64_t completion_weight,
             bool)
      : kind(Kind::failure),
        run_id(run),
        failure(new Failure(std::move(value))),
        weight(completion_weight) {}

  Kind kind;
  std::uint64_t run_id;
  std::unique_ptr<Output> output;
  std::unique_ptr<Failure> failure;
  std::int64_t weight;
};

template <typename Output, typename Failure>
struct CompletionQueue {
  CompletionQueue(std::size_t item_limit, std::int64_t weight_limit)
      : max_items(item_limit), max_weight(weight_limit) {}

  template <typename CompletionValue>
  CommandOfferResult offer(CompletionValue completion) {
    std::function<void()> wake;
    {
      std::lock_guard<std::mutex> lock(gate);
      if (disposed) {
        return CommandOfferResult::disposed;
      }
      if (completion.weight < 0) {
        return CommandOfferResult::invalidState;
      }
      if (items.size() >= max_items || completion.weight > max_weight ||
          queued_weight > max_weight - completion.weight) {
        return CommandOfferResult::backpressure;
      }
      const bool was_empty = items.empty();
      items.emplace_back(std::move(completion));
      queued_weight += items.back().weight;
      if (was_empty) {
        wake = wake_callback;
      }
    }
    if (wake) {
      try {
        wake();
      } catch (...) {
        // Wake callbacks may only notify an event loop. Worker failures must
        // never cross the CommandSink boundary.
      }
    }
    return CommandOfferResult::accepted;
  }

  std::vector<Completion<Output, Failure>> take(std::size_t maximum) {
    std::vector<Completion<Output, Failure>> result;
    std::lock_guard<std::mutex> lock(gate);
    const std::size_t count = std::min(maximum, items.size());
    result.reserve(count);
    for (std::size_t index = 0; index < count; ++index) {
      queued_weight -= items.front().weight;
      result.emplace_back(std::move(items.front()));
      items.pop_front();
    }
    return result;
  }

  bool hasPending() const {
    std::lock_guard<std::mutex> lock(gate);
    return !items.empty();
  }

  void setWake(std::function<void()> callback) {
    std::lock_guard<std::mutex> lock(gate);
    wake_callback = std::move(callback);
  }

  void close() noexcept {
    std::lock_guard<std::mutex> lock(gate);
    disposed = true;
    items.clear();
    queued_weight = 0;
    wake_callback = nullptr;
  }

  mutable std::mutex gate;
  std::deque<Completion<Output, Failure>> items;
  const std::size_t max_items;
  const std::int64_t max_weight;
  std::int64_t queued_weight = 0;
  bool disposed = false;
  std::function<void()> wake_callback;
};

}  // namespace command_detail

class CommandTicket {
 public:
  CommandTicket() noexcept = default;

  std::uint64_t id() const noexcept { return id_; }
  bool valid() const noexcept {
    return id_ != 0u && !owner_.expired() && state_ != nullptr;
  }
  CommandStatus status() const noexcept {
    return state_ ? state_->status.load(std::memory_order_acquire)
                  : CommandStatus::cancelled;
  }

 private:
  CommandTicket(std::uint64_t id, const std::shared_ptr<void>& owner,
                std::shared_ptr<command_detail::TicketState> state)
      : id_(id), owner_(owner), state_(std::move(state)) {}

  std::uint64_t id_ = 0u;
  std::weak_ptr<void> owner_;
  std::shared_ptr<command_detail::TicketState> state_;

  template <typename, typename, typename>
  friend class Command;
};

class CommandRunSubscription {
 public:
  CommandRunSubscription() noexcept = default;
  ~CommandRunSubscription() { close(); }

  CommandRunSubscription(const CommandRunSubscription&) = delete;
  CommandRunSubscription& operator=(const CommandRunSubscription&) = delete;

  CommandRunSubscription(CommandRunSubscription&& other) noexcept
      : close_(std::move(other.close_)), active_(std::move(other.active_)) {}

  CommandRunSubscription& operator=(CommandRunSubscription&& other) noexcept {
    if (this != &other) {
      close();
      close_ = std::move(other.close_);
      active_ = std::move(other.active_);
    }
    return *this;
  }

  bool active() const noexcept {
    if (!active_) {
      return false;
    }
    try {
      return active_();
    } catch (...) {
      return false;
    }
  }

  bool close() noexcept {
    if (!close_) {
      return false;
    }
    bool removed = false;
    try {
      removed = close_();
    } catch (...) {
    }
    close_ = nullptr;
    active_ = nullptr;
    return removed;
  }

 private:
  CommandRunSubscription(std::function<bool()> close,
                         std::function<bool()> active)
      : close_(std::move(close)), active_(std::move(active)) {}

  std::function<bool()> close_;
  std::function<bool()> active_;

  template <typename, typename, typename>
  friend class Command;
};

template <typename Output, typename Failure>
class CommandSink {
 public:
  CommandSink() noexcept = default;

  CommandOfferResult succeed(Output output, std::int64_t weight = 1) const {
    if (weight < 0) {
      throw std::invalid_argument("Command completion weight cannot be negative");
    }
    const std::shared_ptr<Queue> queue = queue_.lock();
    if (!queue) {
      return CommandOfferResult::disposed;
    }
    return queue->offer(command_detail::Completion<Output, Failure>(
        run_id_, std::move(output), weight));
  }

  CommandOfferResult fail(Failure failure, std::int64_t weight = 1) const {
    if (weight < 0) {
      throw std::invalid_argument("Command completion weight cannot be negative");
    }
    const std::shared_ptr<Queue> queue = queue_.lock();
    if (!queue) {
      return CommandOfferResult::disposed;
    }
    return queue->offer(command_detail::Completion<Output, Failure>(
        run_id_, std::move(failure), weight, true));
  }

 private:
  using Queue = command_detail::CompletionQueue<Output, Failure>;

  CommandSink(std::uint64_t run_id, const std::shared_ptr<Queue>& queue)
      : run_id_(run_id), queue_(queue) {}

  std::uint64_t run_id_ = 0u;
  std::weak_ptr<Queue> queue_;

  template <typename, typename, typename>
  friend class Command;
};

template <typename Input, typename Output, typename Failure>
class Command {
 public:
  using Sink = CommandSink<Output, Failure>;
  using Cancel = std::function<void()>;
  using Executor = std::function<Cancel(Input, Sink)>;
  using Settled = std::function<void(CommandTicket, CommandStatus)>;

  explicit Command(Executor executor,
                   CommandPolicy policy = CommandPolicy::latestOnly,
                   std::size_t max_pending_completions = 256u,
                   std::int64_t max_pending_weight = 4 * 1024 * 1024)
      : core_(std::make_shared<Core>(std::move(executor), policy,
                                     max_pending_completions,
                                     max_pending_weight)) {}

  CommandPolicy policy() const { return requireActive().policy; }
  bool disposed() const noexcept { return !core_ || core_->disposed; }

  void onSuccess(std::function<void(Output)> callback) {
    requireActive().on_success = std::move(callback);
  }
  void onFailure(std::function<void(Failure)> callback) {
    requireActive().on_failure = std::move(callback);
  }
  void onCancelled(std::function<void(CommandTicket)> callback) {
    requireActive().on_cancelled = std::move(callback);
  }

  CommandTicket run(Input input) {
    Core& core = requireActive();
    const CommandTicket ticket = core.makeTicket();
    QueuedRun queued{ticket, std::move(input)};
    try {
      switch (core.policy) {
        case CommandPolicy::latestOnly:
          core.cancelAllInternal(true);
          core.start(std::move(queued));
          break;
        case CommandPolicy::ordered:
          if (core.active.empty()) {
            core.start(std::move(queued));
          } else {
            core.queued.emplace_back(std::move(queued));
          }
          break;
        case CommandPolicy::concurrent:
          core.start(std::move(queued));
          break;
      }
    } catch (...) {
      throw;
    }
    return ticket;
  }

  bool cancel(const CommandTicket& ticket) {
    if (disposed() || !core_->owns(ticket)) {
      return false;
    }
    bool cancelled = false;
    try {
      cancelled = core_->cancelActive(ticket.id_, true);
    } catch (...) {
      const std::exception_ptr cancellation_failure = std::current_exception();
      try {
        core_->startNextOrdered();
      } catch (...) {
      }
      std::rethrow_exception(cancellation_failure);
    }
    if (cancelled) {
      core_->startNextOrdered();
      return true;
    }
    for (auto position = core_->queued.begin(); position != core_->queued.end();
         ++position) {
      if (position->ticket.id_ == ticket.id_) {
        const CommandTicket cancelled = position->ticket;
        core_->queued.erase(position);
        core_->markCancelled(cancelled, true);
        return true;
      }
    }
    return false;
  }

  std::size_t cancelAll() {
    if (disposed()) {
      return 0u;
    }
    return core_->cancelAllInternal(true);
  }

  CommandRunSubscription observeRun(const CommandTicket& ticket,
                                    Settled callback) {
    Core& core = requireActive();
    if (!core.owns(ticket)) {
      throw std::invalid_argument("Command ticket does not belong to this Command");
    }
    if (!callback) {
      throw std::invalid_argument("Command run observer cannot be empty");
    }
    const CommandStatus current = ticket.status();
    if (current != CommandStatus::queued && current != CommandStatus::running) {
      callback(ticket, current);
      return CommandRunSubscription();
    }
    const std::uint64_t id = core.next_observer_id++;
    if (core.next_observer_id == 0u) {
      core.next_observer_id = 1u;
    }
    core.observers[ticket.id_].push_back(
        Observer{id, std::move(callback)});
    const std::weak_ptr<Core> weak = core_;
    const std::uint64_t run_id = ticket.id_;
    return CommandRunSubscription(
        [weak, run_id, id]() {
          const std::shared_ptr<Core> current = weak.lock();
          return current && current->unsubscribe(run_id, id);
        },
        [weak, run_id, id]() {
          const std::shared_ptr<Core> current = weak.lock();
          return current && current->hasObserver(run_id, id);
        });
  }

  std::size_t pump(
      std::size_t maximum = (std::numeric_limits<std::size_t>::max)()) {
    if (disposed() || maximum == 0u) {
      return 0u;
    }
    std::vector<Completion> completions = core_->queue->take(maximum);
    std::exception_ptr first_failure;
    for (Completion& completion : completions) {
      try {
        core_->complete(std::move(completion));
      } catch (...) {
        if (!first_failure) {
          first_failure = std::current_exception();
        }
      }
    }
    if (first_failure) {
      std::rethrow_exception(first_failure);
    }
    return completions.size();
  }

  bool pending() const {
    return !disposed() && (!core_->active.empty() || !core_->queued.empty() ||
                           core_->queue->hasPending());
  }
  std::size_t activeCount() const noexcept {
    return disposed() ? 0u : core_->active.size();
  }
  std::size_t queuedCount() const noexcept {
    return disposed() ? 0u : core_->queued.size();
  }

  void setWakeCallback(std::function<void()> callback) {
    if (!disposed()) {
      core_->queue->setWake(std::move(callback));
    }
  }

  bool dispose() noexcept {
    if (disposed()) {
      return false;
    }
    core_->dispose();
    return true;
  }

 private:
  using Completion = command_detail::Completion<Output, Failure>;
  using Queue = command_detail::CompletionQueue<Output, Failure>;

  struct Observer {
    std::uint64_t id;
    Settled callback;
  };

  struct ActiveRun {
    CommandTicket ticket;
    Cancel cancel;
  };

  struct QueuedRun {
    CommandTicket ticket;
    Input input;
  };

  struct Core : public std::enable_shared_from_this<Core> {
    Core(Executor operation, CommandPolicy command_policy,
         std::size_t max_items, std::int64_t max_weight)
        : policy(command_policy),
          executor(std::move(operation)),
          queue(std::make_shared<Queue>(max_items, max_weight)),
          owner(std::make_shared<int>(0)) {
      if (!executor) {
        throw std::invalid_argument("Command executor cannot be empty");
      }
      if (max_items == 0u || max_weight <= 0) {
        throw std::invalid_argument("Command completion limits must be positive");
      }
    }

    ~Core() { dispose(); }

    CommandTicket makeTicket() {
      const std::uint64_t id = next_run_id++;
      if (next_run_id == 0u) {
        next_run_id = 1u;
      }
      return CommandTicket(id, owner,
          std::make_shared<command_detail::TicketState>(CommandStatus::queued));
    }

    bool owns(const CommandTicket& ticket) const noexcept {
      const std::shared_ptr<void> ticket_owner = ticket.owner_.lock();
      return ticket.id_ != 0u && ticket.state_ && ticket_owner &&
             ticket_owner.get() == owner.get();
    }

    void start(QueuedRun queued_run) {
      queued_run.ticket.state_->status.store(CommandStatus::running,
                                               std::memory_order_release);
      const std::uint64_t id = queued_run.ticket.id_;
      active.emplace(id, ActiveRun{queued_run.ticket, Cancel()});
      try {
        Cancel cancellation = executor(
            std::move(queued_run.input), Sink(id, queue));
        const auto retained = active.find(id);
        if (retained != active.end()) {
          retained->second.cancel = std::move(cancellation);
        } else {
          invokeCancel(cancellation);
        }
      } catch (...) {
        active.erase(id);
        queued_run.ticket.state_->status.store(CommandStatus::cancelled,
                                                std::memory_order_release);
        const std::exception_ptr executor_failure = std::current_exception();
        try {
          notifySettled(queued_run.ticket);
        } catch (...) {
        }
        try {
          startNextOrdered();
        } catch (...) {
        }
        std::rethrow_exception(executor_failure);
      }
    }

    void startNextOrdered() {
      if (policy != CommandPolicy::ordered || !active.empty() || queued.empty()) {
        return;
      }
      QueuedRun next = std::move(queued.front());
      queued.pop_front();
      start(std::move(next));
    }

    static void invokeCancel(Cancel& cancellation) noexcept {
      if (!cancellation) {
        return;
      }
      Cancel retained = std::move(cancellation);
      try {
        retained();
      } catch (...) {
      }
    }

    bool cancelActive(std::uint64_t id, bool notify) {
      const auto found = active.find(id);
      if (found == active.end()) {
        return false;
      }
      ActiveRun run = std::move(found->second);
      active.erase(found);
      invokeCancel(run.cancel);
      markCancelled(run.ticket, notify);
      return true;
    }

    void markCancelled(const CommandTicket& ticket, bool notify) {
      ticket.state_->status.store(CommandStatus::cancelled,
                                  std::memory_order_release);
      std::exception_ptr first_failure;
      try {
        notifySettled(ticket);
      } catch (...) {
        first_failure = std::current_exception();
      }
      if (notify && on_cancelled) {
        try {
          on_cancelled(ticket);
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
      }
      if (first_failure) {
        std::rethrow_exception(first_failure);
      }
    }

    std::size_t cancelAllInternal(bool notify) {
      std::size_t result = 0u;
      std::exception_ptr first_failure;
      while (!active.empty()) {
        const std::uint64_t id = active.begin()->first;
        try {
          cancelActive(id, notify);
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
        ++result;
      }
      while (!queued.empty()) {
        const CommandTicket ticket = queued.back().ticket;
        queued.pop_back();
        try {
          markCancelled(ticket, notify);
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
        ++result;
      }
      if (first_failure) {
        std::rethrow_exception(first_failure);
      }
      return result;
    }

    void complete(Completion completion) {
      const auto found = active.find(completion.run_id);
      if (found == active.end()) {
        return;
      }
      const CommandTicket ticket = found->second.ticket;
      active.erase(found);
      std::exception_ptr first_failure;
      if (completion.kind == Completion::Kind::success) {
        ticket.state_->status.store(CommandStatus::succeeded,
                                    std::memory_order_release);
        try {
          notifySettled(ticket);
        } catch (...) {
          first_failure = std::current_exception();
        }
        try {
          startNextOrdered();
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
        if (on_success) {
          try {
            on_success(std::move(*completion.output));
          } catch (...) {
            if (!first_failure) {
              first_failure = std::current_exception();
            }
          }
        }
      } else {
        ticket.state_->status.store(CommandStatus::failed,
                                    std::memory_order_release);
        try {
          notifySettled(ticket);
        } catch (...) {
          first_failure = std::current_exception();
        }
        try {
          startNextOrdered();
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
        if (on_failure) {
          try {
            on_failure(std::move(*completion.failure));
          } catch (...) {
            if (!first_failure) {
              first_failure = std::current_exception();
            }
          }
        }
      }
      if (first_failure) {
        std::rethrow_exception(first_failure);
      }
    }

    void notifySettled(const CommandTicket& ticket) {
      const auto found = observers.find(ticket.id_);
      if (found == observers.end()) {
        return;
      }
      std::vector<Observer> retained = std::move(found->second);
      observers.erase(found);
      std::exception_ptr first_failure;
      for (Observer& observer : retained) {
        try {
          observer.callback(ticket, ticket.status());
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
      }
      if (first_failure) {
        std::rethrow_exception(first_failure);
      }
    }

    bool unsubscribe(std::uint64_t run_id, std::uint64_t observer_id) {
      const auto found = observers.find(run_id);
      if (found == observers.end()) {
        return false;
      }
      std::vector<Observer>& bindings = found->second;
      const auto observer = std::find_if(
          bindings.begin(), bindings.end(), [observer_id](const Observer& item) {
            return item.id == observer_id;
          });
      if (observer == bindings.end()) {
        return false;
      }
      bindings.erase(observer);
      if (bindings.empty()) {
        observers.erase(found);
      }
      return true;
    }

    bool hasObserver(std::uint64_t run_id, std::uint64_t observer_id) const {
      const auto found = observers.find(run_id);
      return found != observers.end() &&
          std::any_of(found->second.begin(), found->second.end(),
                      [observer_id](const Observer& item) {
                        return item.id == observer_id;
                      });
    }

    void dispose() noexcept {
      if (disposed) {
        return;
      }
      disposed = true;
      try {
        cancelAllInternal(false);
      } catch (...) {
      }
      observers.clear();
      executor = nullptr;
      on_success = nullptr;
      on_failure = nullptr;
      on_cancelled = nullptr;
      queue->close();
      owner.reset();
    }

    CommandPolicy policy;
    Executor executor;
    std::shared_ptr<Queue> queue;
    std::shared_ptr<void> owner;
    std::unordered_map<std::uint64_t, ActiveRun> active;
    std::deque<QueuedRun> queued;
    std::unordered_map<std::uint64_t, std::vector<Observer>> observers;
    std::function<void(Output)> on_success;
    std::function<void(Failure)> on_failure;
    std::function<void(CommandTicket)> on_cancelled;
    std::uint64_t next_run_id = 1u;
    std::uint64_t next_observer_id = 1u;
    bool disposed = false;
  };

  Core& requireActive() const {
    if (disposed()) {
      throw std::logic_error("Command is not active");
    }
    return *core_;
  }

  std::shared_ptr<Core> core_;
};

template <typename Input, typename Output, typename Failure, typename Executor>
Command<Input, Output, Failure> command(
    Executor executor, CommandPolicy policy = CommandPolicy::latestOnly,
    std::size_t max_pending_completions = 256u,
    std::int64_t max_pending_weight = 4 * 1024 * 1024) {
  return Command<Input, Output, Failure>(
      std::move(executor), policy, max_pending_completions,
      max_pending_weight);
}

}  // namespace cbss

#endif
