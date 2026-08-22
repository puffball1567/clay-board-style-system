#ifndef CBSS_STORE_HPP
#define CBSS_STORE_HPP

#include <cstddef>
#include <cstdint>
#include <exception>
#include <functional>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace cbss {

namespace detail {
template <typename Value>
class StoreSignal;
}  // namespace detail

class StoreSubscription {
 public:
  StoreSubscription() noexcept = default;
  ~StoreSubscription() { close(); }

  StoreSubscription(const StoreSubscription&) = delete;
  StoreSubscription& operator=(const StoreSubscription&) = delete;

  StoreSubscription(StoreSubscription&& other) noexcept
      : close_(std::move(other.close_)), active_(std::move(other.active_)) {}

  StoreSubscription& operator=(StoreSubscription&& other) noexcept {
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
  StoreSubscription(std::function<bool()> close,
                    std::function<bool()> active)
      : close_(std::move(close)), active_(std::move(active)) {}

  std::function<bool()> close_;
  std::function<bool()> active_;

  template <typename>
  friend class detail::StoreSignal;
};

namespace detail {

template <typename Value>
class StoreSignal : public std::enable_shared_from_this<StoreSignal<Value>> {
 public:
  using Listener = std::function<void(const Value&)>;

  StoreSubscription subscribe(Listener listener) {
    if (!listener) {
      throw std::invalid_argument("Store listener cannot be empty");
    }
    const std::uint64_t id = next_id_++;
    if (next_id_ == 0u) {
      next_id_ = 1u;
    }
    const std::shared_ptr<Listener> callback =
        std::make_shared<Listener>(std::move(listener));
    bindings_.push_back(Binding{id, callback, true});
    try {
      index_[id] = bindings_.size() - 1u;
    } catch (...) {
      bindings_.pop_back();
      throw;
    }
    std::weak_ptr<StoreSignal<Value>> weak = this->shared_from_this();
    return StoreSubscription(
        [weak, id]() {
          if (const std::shared_ptr<StoreSignal<Value>> source = weak.lock()) {
            return source->unsubscribe(id);
          }
          return false;
        },
        [weak, id]() {
          const std::shared_ptr<StoreSignal<Value>> source = weak.lock();
          return source && source->contains(id);
        });
  }

  void emit(const Value& value) {
    ++emit_depth_;
    const std::size_t count = bindings_.size();
    std::exception_ptr first_failure;
    for (std::size_t index = 0; index < count; ++index) {
      if (!bindings_[index].active) {
        continue;
      }
      const std::shared_ptr<Listener> listener = bindings_[index].listener;
      try {
        (*listener)(value);
      } catch (...) {
        if (!first_failure) {
          first_failure = std::current_exception();
        }
      }
    }
    --emit_depth_;
    if (emit_depth_ == 0u) {
      compact();
    }
    if (first_failure) {
      std::rethrow_exception(first_failure);
    }
  }

  void clear() noexcept {
    index_.clear();
    if (emit_depth_ == 0u) {
      bindings_.clear();
      inactive_count_ = 0u;
      return;
    }
    for (Binding& binding : bindings_) {
      if (binding.active) {
        binding.active = false;
        binding.listener.reset();
        ++inactive_count_;
      }
    }
  }

  std::size_t listenerCount() const noexcept { return index_.size(); }

 private:
  struct Binding {
    std::uint64_t id;
    std::shared_ptr<Listener> listener;
    bool active;
  };

  bool contains(std::uint64_t id) const noexcept {
    return index_.find(id) != index_.end();
  }

  bool unsubscribe(std::uint64_t id) noexcept {
    const auto found = index_.find(id);
    if (found == index_.end()) {
      return false;
    }
    const std::size_t position = found->second;
    index_.erase(found);
    if (emit_depth_ != 0u) {
      bindings_[position].active = false;
      bindings_[position].listener.reset();
      ++inactive_count_;
      return true;
    }
    bindings_.erase(bindings_.begin() + static_cast<std::ptrdiff_t>(position));
    for (std::size_t index = position; index < bindings_.size(); ++index) {
      const auto retained = index_.find(bindings_[index].id);
      if (retained != index_.end()) {
        retained->second = index;
      }
    }
    return true;
  }

  void compact() {
    if (inactive_count_ == 0u) {
      return;
    }
    std::size_t target = 0u;
    for (std::size_t source = 0u; source < bindings_.size(); ++source) {
      if (bindings_[source].active) {
        if (target != source) {
          bindings_[target] = std::move(bindings_[source]);
        }
        const auto indexed = index_.find(bindings_[target].id);
        if (indexed != index_.end()) {
          indexed->second = target;
        }
        ++target;
      }
    }
    bindings_.resize(target);
    inactive_count_ = 0u;
  }

  std::vector<Binding> bindings_;
  std::unordered_map<std::uint64_t, std::size_t> index_;
  std::uint64_t next_id_ = 1u;
  std::size_t emit_depth_ = 0u;
  std::size_t inactive_count_ = 0u;

};

}  // namespace detail

template <typename Value>
class Selector;

template <typename State, typename Action>
class Store {
 public:
  using Reducer = std::function<void(State&, const Action&)>;
  using Listener = std::function<void(std::uint64_t)>;

  Store(State initial_state, Reducer reducer)
      : core_(std::make_shared<Core>(std::move(initial_state),
                                     std::move(reducer))) {
    if (!core_->reducer) {
      throw std::invalid_argument("Store reducer cannot be empty");
    }
  }

  State state() const { return core_->state; }
  template <typename Reader>
  auto read(Reader&& reader) const
      -> decltype(std::forward<Reader>(reader)(
          std::declval<const State&>())) {
    return std::forward<Reader>(reader)(core_->state);
  }
  std::uint64_t revision() const noexcept { return core_->revision; }
  std::size_t subscriberCount() const noexcept {
    return core_->commits->listenerCount();
  }

  void dispatch(Action action) {
    core_->pending_actions.push_back(std::move(action));
    core_->drain();
  }

  void dispatchSilent(const Action& action) { core_->reducer(core_->state, action); }

  template <typename Body>
  void transaction(Body&& body) {
    ++core_->transaction_depth;
    std::exception_ptr body_failure;
    try {
      std::forward<Body>(body)();
    } catch (...) {
      body_failure = std::current_exception();
    }
    --core_->transaction_depth;

    std::exception_ptr commit_failure;
    if (core_->transaction_depth == 0u) {
      try {
        core_->drain();
      } catch (...) {
        commit_failure = std::current_exception();
      }
    }
    if (body_failure) {
      std::rethrow_exception(body_failure);
    }
    if (commit_failure) {
      std::rethrow_exception(commit_failure);
    }
  }

  StoreSubscription subscribe(Listener listener) {
    if (!listener) {
      throw std::invalid_argument("Store listener cannot be empty");
    }
    return core_->commits->subscribe(std::move(listener));
  }

  template <typename Value, typename Projection>
  Selector<Value> select(Projection projection) const {
    return select<Value>(std::move(projection), std::equal_to<Value>());
  }

  template <typename Value, typename Projection, typename Equal>
  Selector<Value> select(Projection projection, Equal equal) const;

 private:
  struct Core {
    Core(State value, Reducer update)
        : state(std::move(value)),
          reducer(std::move(update)),
          commits(std::make_shared<detail::StoreSignal<std::uint64_t>>()) {}

    void publishCommit() {
      if (!pending_commit) {
        return;
      }
      pending_commit = false;
      ++revision;
      commits->emit(revision);
    }

    void drain() {
      if (processing) {
        return;
      }
      processing = true;
      std::size_t position = 0u;
      std::exception_ptr first_failure;
      while (position < pending_actions.size()) {
        Action action = std::move(pending_actions[position++]);
        try {
          reducer(state, action);
          pending_commit = true;
          if (transaction_depth == 0u) {
            publishCommit();
          }
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
      }
      pending_actions.clear();
      if (transaction_depth == 0u && pending_commit) {
        try {
          publishCommit();
        } catch (...) {
          if (!first_failure) {
            first_failure = std::current_exception();
          }
        }
      }
      processing = false;
      if (first_failure) {
        std::rethrow_exception(first_failure);
      }
    }

    State state;
    Reducer reducer;
    std::shared_ptr<detail::StoreSignal<std::uint64_t>> commits;
    std::vector<Action> pending_actions;
    std::uint64_t revision = 0u;
    std::size_t transaction_depth = 0u;
    bool pending_commit = false;
    bool processing = false;
  };

  explicit Store(std::shared_ptr<Core> core) : core_(std::move(core)) {}

  std::shared_ptr<Core> core_;

  template <typename>
  friend class Selector;
};

template <typename Value>
class Selector {
 public:
  Value value() const {
    requireActive();
    return core_->value;
  }

  bool disposed() const noexcept { return !core_ || core_->disposed; }

  std::size_t subscriberCount() const noexcept {
    return disposed() ? 0u : core_->changes->listenerCount();
  }

  StoreSubscription subscribe(std::function<void(const Value&)> listener) {
    requireActive();
    return core_->changes->subscribe(std::move(listener));
  }

  void refresh() {
    requireActive();
    core_->refresh();
  }

  bool dispose() noexcept {
    if (disposed()) {
      return false;
    }
    core_->disposed = true;
    core_->source.close();
    core_->changes->clear();
    core_->refresh_value = nullptr;
    return true;
  }

 private:
  struct Core {
    Core(Value initial_value, std::function<bool(const Value&, const Value&)> eq)
        : value(std::move(initial_value)),
          equal(std::move(eq)),
          changes(std::make_shared<detail::StoreSignal<Value>>()) {}

    void set(Value next) {
      if (equal(value, next)) {
        return;
      }
      value = std::move(next);
      changes->emit(value);
    }

    void refresh() {
      if (!refresh_value) {
        throw std::logic_error("Selector is disposed");
      }
      set(refresh_value());
    }

    Value value;
    std::function<bool(const Value&, const Value&)> equal;
    std::shared_ptr<detail::StoreSignal<Value>> changes;
    StoreSubscription source;
    std::function<Value()> refresh_value;
    bool disposed = false;
  };

  explicit Selector(std::shared_ptr<Core> core) : core_(std::move(core)) {}

  void requireActive() const {
    if (disposed()) {
      throw std::logic_error("Selector is disposed");
    }
  }

  std::shared_ptr<Core> core_;

  template <typename, typename>
  friend class Store;
};

template <typename State, typename Action>
template <typename Value, typename Projection, typename Equal>
Selector<Value> Store<State, Action>::select(Projection projection,
                                              Equal equal) const {
  const std::function<Value(const State&)> project = std::move(projection);
  const std::function<bool(const Value&, const Value&)> compare =
      std::move(equal);
  if (!project) {
    throw std::invalid_argument("Selector projection cannot be empty");
  }
  if (!compare) {
    throw std::invalid_argument("Selector equality cannot be empty");
  }

  using SelectorCore = typename Selector<Value>::Core;
  const std::shared_ptr<SelectorCore> selected =
      std::make_shared<SelectorCore>(project(core_->state), compare);
  const std::weak_ptr<SelectorCore> weak_selected = selected;
  const std::shared_ptr<typename Store<State, Action>::Core> store = core_;
  selected->refresh_value = [store, project]() {
    return project(store->state);
  };
  selected->source = core_->commits->subscribe(
      [weak_selected, store, project](const std::uint64_t&) {
        if (const std::shared_ptr<SelectorCore> current = weak_selected.lock()) {
          if (!current->disposed) {
            current->set(project(store->state));
          }
        }
      });
  return Selector<Value>(selected);
}

template <typename State, typename Action, typename Reducer>
Store<State, Action> createStore(State initial_state, Reducer reducer) {
  return Store<State, Action>(std::move(initial_state), std::move(reducer));
}

}  // namespace cbss

#endif
