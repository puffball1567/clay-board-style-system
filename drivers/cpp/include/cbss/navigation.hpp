#ifndef CBSS_NAVIGATION_HPP
#define CBSS_NAVIGATION_HPP

#include "cbss.h"

#include <cstddef>
#include <cstdint>
#include <exception>
#include <functional>
#include <memory>
#include <stdexcept>
#include <utility>
#include <vector>

namespace cbss {

constexpr std::uint32_t navigationScreenDirtyDomains =
    CBSS_DIRTY_STYLE | CBSS_DIRTY_LAYOUT | CBSS_DIRTY_PAINT |
    CBSS_DIRTY_HIT;

template <typename Value>
class NavigationOptional {
 public:
  NavigationOptional() noexcept = default;
  NavigationOptional(const Value& value)
      : value_(std::make_shared<Value>(value)) {}
  NavigationOptional(Value&& value)
      : value_(std::make_shared<Value>(std::move(value))) {}

  bool hasValue() const noexcept { return static_cast<bool>(value_); }
  explicit operator bool() const noexcept { return hasValue(); }

  const Value& value() const {
    if (!value_) {
      throw std::logic_error("navigation value is absent");
    }
    return *value_;
  }

 private:
  std::shared_ptr<Value> value_;
};

template <typename Destination>
struct NavigationEntry {
  std::uint64_t id;
  Destination destination;
};

template <typename Destination>
struct NavigationSnapshot {
  std::vector<NavigationEntry<Destination>> entries;
  std::ptrdiff_t currentIndex = -1;
  std::uint64_t revision = 0u;

  NavigationOptional<NavigationEntry<Destination>> currentEntry() const {
    if (currentIndex < 0 ||
        static_cast<std::size_t>(currentIndex) >= entries.size()) {
      return {};
    }
    return entries[static_cast<std::size_t>(currentIndex)];
  }

  NavigationOptional<Destination> currentDestination() const {
    const NavigationOptional<NavigationEntry<Destination>> entry =
        currentEntry();
    if (!entry) {
      return {};
    }
    return entry.value().destination;
  }

  bool canGoBack() const noexcept {
    return currentIndex > 0 &&
           static_cast<std::size_t>(currentIndex) < entries.size();
  }

  bool canGoForward() const noexcept {
    return currentIndex >= 0 &&
           static_cast<std::size_t>(currentIndex + 1) < entries.size();
  }
};

enum class NavigationChangeKind { push, replace, back, forward };

template <typename Destination>
struct NavigationChange {
  NavigationChangeKind kind;
  NavigationOptional<NavigationEntry<Destination>> previous;
  NavigationOptional<NavigationEntry<Destination>> current;
  NavigationSnapshot<Destination> snapshot;
  std::uint32_t dirtyDomains = navigationScreenDirtyDomains;
};

template <typename Destination>
struct NavigationDriver {
  using Change = NavigationChange<Destination>;
  using OptionalChange = NavigationOptional<Change>;

  std::function<NavigationSnapshot<Destination>()> snapshot;
  std::function<OptionalChange(const Destination&)> push;
  std::function<OptionalChange(const Destination&)> replace;
  std::function<OptionalChange()> back;
  std::function<OptionalChange()> forward;
};

namespace detail {
template <typename Destination>
class NavigationSignal;
}  // namespace detail

class NavigationSubscription {
 public:
  NavigationSubscription() noexcept = default;
  ~NavigationSubscription() { close(); }

  NavigationSubscription(const NavigationSubscription&) = delete;
  NavigationSubscription& operator=(const NavigationSubscription&) = delete;

  NavigationSubscription(NavigationSubscription&& other) noexcept
      : close_(std::move(other.close_)), active_(std::move(other.active_)) {}

  NavigationSubscription& operator=(NavigationSubscription&& other) noexcept {
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
  NavigationSubscription(std::function<bool()> close,
                         std::function<bool()> active)
      : close_(std::move(close)), active_(std::move(active)) {}

  std::function<bool()> close_;
  std::function<bool()> active_;

  template <typename>
  friend class detail::NavigationSignal;
};

namespace detail {

template <typename Destination>
class NavigationSignal
    : public std::enable_shared_from_this<NavigationSignal<Destination>> {
 public:
  using Change = NavigationChange<Destination>;
  using Listener = std::function<void(const Change&)>;

  NavigationSubscription subscribe(Listener listener) {
    if (!listener) {
      throw std::invalid_argument("navigation listener cannot be empty");
    }
    const std::uint64_t id = nextId_++;
    if (nextId_ == 0u) {
      nextId_ = 1u;
    }
    listeners_.push_back({id, std::move(listener)});
    const std::weak_ptr<NavigationSignal<Destination>> weak =
        this->shared_from_this();
    return NavigationSubscription(
        [weak, id]() {
          const std::shared_ptr<NavigationSignal<Destination>> signal =
              weak.lock();
          return signal && signal->remove(id);
        },
        [weak, id]() {
          const std::shared_ptr<NavigationSignal<Destination>> signal =
              weak.lock();
          return signal && signal->contains(id);
        });
  }

  void emit(const Change& change) {
    std::vector<Listener> callbacks;
    callbacks.reserve(listeners_.size());
    for (const Binding& binding : listeners_) {
      callbacks.push_back(binding.listener);
    }
    std::exception_ptr firstFailure;
    for (const Listener& callback : callbacks) {
      try {
        callback(change);
      } catch (...) {
        if (!firstFailure) {
          firstFailure = std::current_exception();
        }
      }
    }
    if (firstFailure) {
      std::rethrow_exception(firstFailure);
    }
  }

  void clear() noexcept { listeners_.clear(); }
  std::size_t count() const noexcept { return listeners_.size(); }

 private:
  struct Binding {
    std::uint64_t id;
    Listener listener;
  };

  bool contains(std::uint64_t id) const noexcept {
    for (const Binding& binding : listeners_) {
      if (binding.id == id) {
        return true;
      }
    }
    return false;
  }

  bool remove(std::uint64_t id) noexcept {
    for (std::size_t index = 0u; index < listeners_.size(); ++index) {
      if (listeners_[index].id == id) {
        listeners_.erase(listeners_.begin() +
                         static_cast<std::ptrdiff_t>(index));
        return true;
      }
    }
    return false;
  }

  std::vector<Binding> listeners_;
  std::uint64_t nextId_ = 1u;
};

}  // namespace detail

template <typename Destination>
class Navigator {
 public:
  using Driver = NavigationDriver<Destination>;
  using Change = NavigationChange<Destination>;
  using Listener = std::function<void(const Change&)>;

  explicit Navigator(Driver driver)
      : core_(std::make_shared<Core>(std::move(driver))) {
    core_->validate();
  }

  NavigationSnapshot<Destination> snapshot() const {
    return core_->driver.snapshot();
  }

  NavigationOptional<NavigationEntry<Destination>> currentEntry() const {
    return snapshot().currentEntry();
  }

  NavigationOptional<Destination> currentDestination() const {
    return snapshot().currentDestination();
  }

  bool canGoBack() const { return snapshot().canGoBack(); }
  bool canGoForward() const { return snapshot().canGoForward(); }

  NavigationSubscription subscribe(Listener listener) {
    return core_->listeners->subscribe(std::move(listener));
  }

  void clearListeners() noexcept { core_->listeners->clear(); }
  std::size_t listenerCount() const noexcept {
    return core_->listeners->count();
  }

  bool push(const Destination& destination) {
    return apply(core_->driver.push(destination));
  }

  bool replace(const Destination& destination) {
    return apply(core_->driver.replace(destination));
  }

  bool back() { return apply(core_->driver.back()); }
  bool forward() { return apply(core_->driver.forward()); }

 private:
  struct Core {
    explicit Core(Driver source)
        : driver(std::move(source)),
          listeners(std::make_shared<detail::NavigationSignal<Destination>>()) {}

    void validate() const {
      if (!driver.snapshot || !driver.push || !driver.replace ||
          !driver.back || !driver.forward) {
        throw std::invalid_argument(
            "navigation driver requires snapshot, push, replace, back, and "
            "forward operations");
      }
    }

    Driver driver;
    std::shared_ptr<detail::NavigationSignal<Destination>> listeners;
  };

  bool apply(const NavigationOptional<Change>& change) {
    if (!change) {
      return false;
    }
    core_->listeners->emit(change.value());
    return true;
  }

  std::shared_ptr<Core> core_;
};

template <typename Destination>
NavigationDriver<Destination> stackNavigationDriver(
    Destination initialDestination) {
  struct State {
    std::vector<NavigationEntry<Destination>> entries;
    std::ptrdiff_t currentIndex = -1;
    std::uint64_t revision = 0u;
    std::uint64_t nextEntryId = 1u;

    NavigationEntry<Destination> next(const Destination& destination) {
      return {nextEntryId++, destination};
    }

    NavigationSnapshot<Destination> snapshot() const {
      return {entries, currentIndex, revision};
    }

    NavigationChange<Destination> change(
        NavigationChangeKind kind,
        NavigationOptional<NavigationEntry<Destination>> previous) const {
      const NavigationSnapshot<Destination> currentSnapshot = snapshot();
      return {kind, std::move(previous), currentSnapshot.currentEntry(),
              currentSnapshot, navigationScreenDirtyDomains};
    }
  };

  const std::shared_ptr<State> state = std::make_shared<State>();
  state->entries.push_back(state->next(initialDestination));
  state->currentIndex = 0;

  NavigationDriver<Destination> driver;
  driver.snapshot = [state]() { return state->snapshot(); };
  driver.push = [state](const Destination& destination) {
    const auto previous = state->snapshot().currentEntry();
    if (state->currentIndex + 1 <
        static_cast<std::ptrdiff_t>(state->entries.size())) {
      state->entries.resize(static_cast<std::size_t>(state->currentIndex + 1));
    }
    state->entries.push_back(state->next(destination));
    state->currentIndex =
        static_cast<std::ptrdiff_t>(state->entries.size()) - 1;
    ++state->revision;
    return NavigationOptional<NavigationChange<Destination>>(
        state->change(NavigationChangeKind::push, previous));
  };
  driver.replace = [state](const Destination& destination) {
    const auto previous = state->snapshot().currentEntry();
    if (state->currentIndex < 0 ||
        static_cast<std::size_t>(state->currentIndex) >= state->entries.size()) {
      state->entries.push_back(state->next(destination));
      state->currentIndex =
          static_cast<std::ptrdiff_t>(state->entries.size()) - 1;
    } else {
      state->entries[static_cast<std::size_t>(state->currentIndex)] =
          state->next(destination);
    }
    ++state->revision;
    return NavigationOptional<NavigationChange<Destination>>(
        state->change(NavigationChangeKind::replace, previous));
  };
  driver.back = [state]() {
    if (state->currentIndex <= 0 ||
        static_cast<std::size_t>(state->currentIndex) >= state->entries.size()) {
      return NavigationOptional<NavigationChange<Destination>>();
    }
    const auto previous = state->snapshot().currentEntry();
    --state->currentIndex;
    ++state->revision;
    return NavigationOptional<NavigationChange<Destination>>(
        state->change(NavigationChangeKind::back, previous));
  };
  driver.forward = [state]() {
    if (state->currentIndex < 0 ||
        state->currentIndex + 1 >=
            static_cast<std::ptrdiff_t>(state->entries.size())) {
      return NavigationOptional<NavigationChange<Destination>>();
    }
    const auto previous = state->snapshot().currentEntry();
    ++state->currentIndex;
    ++state->revision;
    return NavigationOptional<NavigationChange<Destination>>(
        state->change(NavigationChangeKind::forward, previous));
  };
  return driver;
}

template <typename Destination>
Navigator<Destination> createStackNavigator(Destination initialDestination) {
  return Navigator<Destination>(
      stackNavigationDriver(std::move(initialDestination)));
}

}  // namespace cbss

#endif
