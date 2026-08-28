#ifndef CBSS_NAVIGATION_UI_HPP
#define CBSS_NAVIGATION_UI_HPP

#include "craft.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace cbss {

constexpr std::int32_t navigationScreenHostStylePriority = 1000000;
constexpr double defaultNavigationTransitionFrameInterval = 1.0 / 60.0;

enum class NavigationTransitionPhase {
  started,
  advanced,
  completed,
  cancelled
};

template <typename Destination>
struct NavigationTransitionContext {
  NavigationTransitionPhase phase;
  NavigationChangeKind kind;
  NavigationEntry<Destination> previous;
  NavigationEntry<Destination> current;
  Node outgoingRoot;
  Node incomingRoot;
  float progress;
};

template <typename Destination>
class NavigationTransitionSpec {
 public:
  using Context = NavigationTransitionContext<Destination>;
  using Hook = std::function<void(const Context&)>;

  NavigationTransitionSpec(double duration_seconds, Hook hook,
                           double frame_interval_seconds =
                               defaultNavigationTransitionFrameInterval)
      : durationSeconds(duration_seconds),
        frameIntervalSeconds(frame_interval_seconds),
        onTransition(std::move(hook)) {
    validate();
  }

  void validate() const {
    if (!std::isfinite(durationSeconds) || durationSeconds <= 0.0) {
      throw std::invalid_argument(
          "navigation transition duration must be finite and positive");
    }
    if (!std::isfinite(frameIntervalSeconds) ||
        frameIntervalSeconds <= 0.0) {
      throw std::invalid_argument(
          "navigation transition frame interval must be finite and positive");
    }
    if (!onTransition) {
      throw std::invalid_argument(
          "navigation transition hook must not be empty");
    }
  }

  double durationSeconds;
  double frameIntervalSeconds;
  Hook onTransition;
};

template <typename Destination>
NavigationTransitionSpec<Destination> navigationTransition(
    double duration_seconds,
    typename NavigationTransitionSpec<Destination>::Hook hook,
    double frame_interval_seconds =
        defaultNavigationTransitionFrameInterval) {
  return NavigationTransitionSpec<Destination>(
      duration_seconds, std::move(hook), frame_interval_seconds);
}

template <typename Destination>
struct NavigationScreenBinding {
  Destination destination;
  Node screenRoot;
  Node focusFallback;
  bool active;
};

template <typename Destination>
class NavigationScreenHost {
  struct ActiveNavigationTransition {
    double startedAt;
    float lastProgress;
    std::size_t outgoingIndex;
    std::size_t incomingIndex;
    NavigationEntry<Destination> previous;
    NavigationEntry<Destination> current;
    NavigationChangeKind kind;
  };

 public:
  NavigationScreenHost(Ui& ui, Navigator<Destination> navigator)
      : core_(std::make_shared<Core>(ui.handle(), std::move(navigator))) {
    const std::weak_ptr<Core> weak = core_;
    subscription_ = core_->navigator.subscribe(
        [weak](const NavigationChange<Destination>& change) {
          const std::shared_ptr<Core> core = weak.lock();
          if (!core) {
            return;
          }
          core->pendingEntry = change.current;
          core->pendingSnapshot = change.snapshot;
          core->pendingKind = change.kind;
          core->pendingChange = true;
        });
  }

  NavigationScreenHost(Ui& ui, Navigator<Destination> navigator,
                       NavigationTransitionSpec<Destination> transition)
      : NavigationScreenHost(ui, std::move(navigator)) {
    transition.validate();
    core_->transitionSpec = std::move(transition);
  }

  NavigationScreenHost(const NavigationScreenHost&) = delete;
  NavigationScreenHost& operator=(const NavigationScreenHost&) = delete;
  NavigationScreenHost(NavigationScreenHost&&) noexcept = default;
  NavigationScreenHost& operator=(NavigationScreenHost&&) noexcept = default;

  bool connected() const noexcept { return subscription_.active(); }
  bool disconnect() noexcept { return subscription_.close(); }
  std::size_t screenCount() const noexcept { return core_->screens.size(); }

  bool transitionActive() const noexcept {
    return static_cast<bool>(core_->activeTransition);
  }

  NavigationOptional<double> nextTransitionDeadline() const {
    return core_->transitionDeadline;
  }

  void setTransition(
      NavigationOptional<NavigationTransitionSpec<Destination>> transition) {
    if (core_->activeTransition) {
      throw std::logic_error(
          "cannot replace an active navigation transition");
    }
    if (transition) {
      transition.value().validate();
    }
    core_->transitionSpec = std::move(transition);
  }

  bool cancelTransition() {
    if (!core_->activeTransition) {
      return false;
    }
    const ActiveNavigationTransition transition =
        core_->activeTransition.value();
    core_->activeTransition = {};
    core_->transitionDeadline = {};
    if (transition.outgoingIndex != transition.incomingIndex) {
      core_->setScreenActive(transition.outgoingIndex, false);
    }
    core_->emitTransition(transition, NavigationTransitionPhase::cancelled,
                          transition.lastProgress);
    return true;
  }

  bool advanceTransition(double now_seconds) {
    validateTime(now_seconds);
    if (!core_->activeTransition || !core_->transitionSpec) {
      return false;
    }
    ActiveNavigationTransition transition = core_->activeTransition.value();
    const NavigationTransitionSpec<Destination>& spec =
        core_->transitionSpec.value();
    const double elapsed = std::max(0.0, now_seconds - transition.startedAt);
    const float progress = static_cast<float>(
        std::min(1.0, elapsed / spec.durationSeconds));
    transition.lastProgress = progress;
    core_->activeTransition = transition;

    if (progress >= 1.0f) {
      core_->activeTransition = {};
      core_->transitionDeadline = {};
      if (transition.outgoingIndex != transition.incomingIndex) {
        core_->setScreenActive(transition.outgoingIndex, false);
      }
      core_->emitTransition(transition, NavigationTransitionPhase::completed,
                            1.0f);
      return true;
    }

    core_->transitionDeadline = std::min(
        now_seconds + spec.frameIntervalSeconds,
        transition.startedAt + spec.durationSeconds);
    core_->emitTransition(transition, NavigationTransitionPhase::advanced,
                          progress);
    return true;
  }

  NavigationOptional<NavigationScreenBinding<Destination>> activeScreen()
      const {
    if (core_->activeIndex < 0 ||
        static_cast<std::size_t>(core_->activeIndex) >=
            core_->screens.size()) {
      return {};
    }
    return core_->screens[static_cast<std::size_t>(core_->activeIndex)];
  }

  NavigationOptional<Destination> pendingDestination() const {
    if (!core_->pendingChange || !core_->pendingEntry) {
      return {};
    }
    return core_->pendingEntry.value().destination;
  }

  void registerScreen(const Destination& destination, Node screen_root,
                      Node focus_fallback = Node()) {
    core_->validateNode(screen_root, "navigation screen root");
    if (focus_fallback.valid()) {
      core_->validateNode(focus_fallback, "navigation focus fallback");
      if (!core_->descendantOrSelf(focus_fallback, screen_root)) {
        throw std::invalid_argument(
            "navigation focus fallback must belong to the registered "
            "screen");
      }
    }
    if (core_->findScreenIndex(destination) >= 0) {
      throw std::invalid_argument(
          "navigation destination is already registered");
    }
    for (const NavigationScreenBinding<Destination>& screen :
         core_->screens) {
      if (core_->descendantOrSelf(screen_root, screen.screenRoot) ||
          core_->descendantOrSelf(screen.screenRoot, screen_root)) {
        throw std::invalid_argument(
            "navigation screen roots must not overlap");
      }
    }
    core_->screens.push_back(
        {destination, screen_root, focus_fallback, true});
    core_->setScreenActive(core_->screens.size() - 1u, false);
  }

  bool unregisterScreen(const Destination& destination, Ui& ui) {
    const std::ptrdiff_t index = core_->findScreenIndex(destination);
    if (index < 0) {
      return false;
    }
    cancelTransition();
    const std::size_t position = static_cast<std::size_t>(index);
    const Node screen_root = core_->screens[position].screenRoot;
    const bool was_active = index == core_->activeIndex;
    if (was_active) {
      core_->activeIndex = -1;
      core_->activeEntryId = NavigationOptional<std::uint64_t>();
    } else if (index < core_->activeIndex) {
      --core_->activeIndex;
    }
    core_->screens.erase(core_->screens.begin() + index);
    ui.removeSubtree(screen_root);
    if (was_active) {
      queueCurrent();
    }
    return true;
  }

  bool replaceScreen(const Destination& destination, Node screen_root, Ui& ui,
                     Node focus_fallback = Node()) {
    const std::ptrdiff_t index = core_->findScreenIndex(destination);
    if (index < 0) {
      throw std::invalid_argument(
          "navigation destination is not registered");
    }
    core_->validateNode(screen_root, "replacement navigation screen root");
    if (focus_fallback.valid()) {
      core_->validateNode(focus_fallback, "navigation focus fallback");
      if (!core_->descendantOrSelf(focus_fallback, screen_root)) {
        throw std::invalid_argument(
            "navigation focus fallback must belong to the replacement "
            "screen");
      }
    }

    const std::size_t position = static_cast<std::size_t>(index);
    const NavigationScreenBinding<Destination> previous =
        core_->screens[position];
    if (previous.screenRoot == screen_root) {
      core_->screens[position].focusFallback = focus_fallback;
      return false;
    }
    if (core_->descendantOrSelf(screen_root, previous.screenRoot) ||
        core_->descendantOrSelf(previous.screenRoot, screen_root)) {
      throw std::invalid_argument(
          "replacement screen must be disjoint from the previous screen");
    }
    for (std::size_t other = 0u; other < core_->screens.size(); ++other) {
      if (other == position) {
        continue;
      }
      const Node root = core_->screens[other].screenRoot;
      if (core_->descendantOrSelf(screen_root, root) ||
          core_->descendantOrSelf(root, screen_root)) {
        throw std::invalid_argument(
            "navigation screen roots must not overlap");
      }
    }

    cancelTransition();

    const bool was_active = index == core_->activeIndex;
    core_->screens[position] =
        {destination, screen_root, focus_fallback, !was_active};
    core_->setScreenActive(position, was_active);
    ui.removeSubtree(previous.screenRoot);
    if (was_active && core_->activeEntryId) {
      core_->restoreFocus(core_->activeEntryId.value(), screen_root,
                          focus_fallback);
    }
    return true;
  }

  void queueCurrent() {
    core_->pendingEntry = core_->navigator.currentEntry();
    core_->pendingSnapshot = core_->navigator.snapshot();
    core_->pendingKind = NavigationOptional<NavigationChangeKind>();
    core_->pendingChange = true;
  }

  bool sync() { return syncPending(false, 0.0); }

  bool sync(double now_seconds) {
    validateTime(now_seconds);
    return syncPending(true, now_seconds);
  }

 private:
  static void validateTime(double now_seconds) {
    if (!std::isfinite(now_seconds)) {
      throw std::invalid_argument(
          "navigation transition time must be finite");
    }
  }

  bool syncPending(bool transition_aware, double now_seconds) {
    if (!core_->pendingChange) {
      return false;
    }
    cancelTransition();
    if (!core_->pendingEntry) {
      if (core_->activeIndex >= 0) {
        const std::size_t previous =
            static_cast<std::size_t>(core_->activeIndex);
        core_->ui.setFocus();
        core_->setScreenActive(previous, false);
        core_->activeIndex = -1;
        core_->activeEntryId = NavigationOptional<std::uint64_t>();
        core_->finishPending();
        return true;
      }
      core_->finishPending();
      return false;
    }

    const NavigationEntry<Destination> target = core_->pendingEntry.value();
    const NavigationOptional<NavigationChangeKind> change_kind =
        core_->pendingKind;
    const std::ptrdiff_t target_index =
        core_->findScreenIndex(target.destination);
    if (target_index < 0) {
      return false;
    }
    if (core_->activeEntryId && core_->activeEntryId.value() == target.id) {
      core_->finishPending();
      return false;
    }

    const std::ptrdiff_t previous_index = core_->activeIndex;
    const NavigationOptional<std::uint64_t> previous_entry =
        core_->activeEntryId;
    if (previous_index >= 0 && previous_entry) {
      const Node focused = core_->ui.focusedNode();
      if (focused.valid() && core_->descendantOrSelf(
                                 focused,
                                 core_->screens[static_cast<std::size_t>(
                                     previous_index)]
                                     .screenRoot)) {
        core_->savedFocus[previous_entry.value()] = focused;
      }
    }
    if (core_->pendingKind &&
        core_->pendingKind.value() == NavigationChangeKind::replace &&
        previous_entry) {
      core_->savedFocus.erase(previous_entry.value());
    } else if (core_->pendingSnapshot) {
      core_->retainEntries(core_->pendingSnapshot.value());
    }

    const std::size_t target_position =
        static_cast<std::size_t>(target_index);
    if (target_index != previous_index) {
      core_->setScreenActive(target_position, true);
    }
    core_->activeIndex = target_index;
    core_->activeEntryId = target.id;
    core_->finishPending();

    if (previous_entry) {
      core_->restoreFocus(target.id,
                          core_->screens[target_position].screenRoot,
                          core_->screens[target_position].focusFallback);
    }
    if (previous_index >= 0 && previous_index != target_index) {
      if (transition_aware && core_->transitionSpec && change_kind &&
          previous_entry) {
        core_->startTransition(
            now_seconds, static_cast<std::size_t>(previous_index),
            target_position,
            NavigationEntry<Destination>{
                previous_entry.value(),
                core_->screens[static_cast<std::size_t>(previous_index)]
                    .destination},
            target, change_kind.value());
      } else {
        core_->setScreenActive(static_cast<std::size_t>(previous_index),
                               false);
      }
    }
    return true;
  }

  struct Core {
    Core(UiHandle ui_handle, Navigator<Destination> source)
        : ui(std::move(ui_handle)),
          navigator(std::move(source)),
          pendingEntry(navigator.currentEntry()),
          pendingSnapshot(navigator.snapshot()),
          pendingChange(true) {}

    void validateNode(Node node, const std::string& description) const {
      if (!node.valid()) {
        throw std::invalid_argument(description + " is invalid");
      }
      try {
        static_cast<void>(ui.inert(node));
      } catch (const Error&) {
        throw std::invalid_argument(description + " belongs to another Ui");
      }
    }

    bool descendantOrSelf(Node node, Node ancestor) const {
      Node current = node;
      while (current.valid()) {
        if (current == ancestor) {
          return true;
        }
        current = ui.parent(current);
      }
      return false;
    }

    std::ptrdiff_t findScreenIndex(const Destination& destination) const {
      for (std::size_t index = 0u; index < screens.size(); ++index) {
        if (screens[index].destination == destination) {
          return static_cast<std::ptrdiff_t>(index);
        }
      }
      return -1;
    }

    void setScreenActive(std::size_t index, bool active) {
      if (index >= screens.size() || screens[index].active == active) {
        return;
      }
      ui.setInert(screens[index].screenRoot, !active);
      Style visibility;
      visibility.set("display", keyword(active ? "flex" : "none"));
      ui.apply(screens[index].screenRoot, visibility, 0u,
               navigationScreenHostStylePriority);
      screens[index].active = active;
    }

    void retainEntries(const NavigationSnapshot<Destination>& snapshot) {
      std::unordered_set<std::uint64_t> retained;
      for (const NavigationEntry<Destination>& entry : snapshot.entries) {
        retained.insert(entry.id);
      }
      for (auto item = savedFocus.begin(); item != savedFocus.end();) {
        if (retained.count(item->first) == 0u) {
          item = savedFocus.erase(item);
        } else {
          ++item;
        }
      }
    }

    void restoreFocus(std::uint64_t entry, Node screen_root,
                      Node fallback) {
      const auto saved = savedFocus.find(entry);
      if (saved != savedFocus.end()) {
        try {
          if (descendantOrSelf(saved->second, screen_root)) {
            ui.setFocus(saved->second, true);
            return;
          } else {
            savedFocus.erase(saved);
          }
        } catch (const Error& error) {
          if (error.status() != CBSS_INVALID_ARGUMENT) {
            throw;
          }
          savedFocus.erase(saved);
        }
      }
      if (fallback.valid()) {
        try {
          ui.setFocus(fallback, true);
          return;
        } catch (const Error& error) {
          if (error.status() != CBSS_INVALID_ARGUMENT) {
            throw;
          }
        }
      }
      ui.setFocus(ui.firstFocusable(screen_root), true);
    }

    void finishPending() {
      pendingChange = false;
      pendingSnapshot = NavigationOptional<NavigationSnapshot<Destination>>();
      pendingKind = NavigationOptional<NavigationChangeKind>();
    }

    void emitTransition(const ActiveNavigationTransition& transition,
                        NavigationTransitionPhase phase, float progress) {
      if (!transitionSpec) {
        return;
      }
      transitionSpec.value().onTransition(
          NavigationTransitionContext<Destination>{
              phase,
              transition.kind,
              transition.previous,
              transition.current,
              screens[transition.outgoingIndex].screenRoot,
              screens[transition.incomingIndex].screenRoot,
              progress});
    }

    void startTransition(double now_seconds, std::size_t outgoing_index,
                         std::size_t incoming_index,
                         NavigationEntry<Destination> previous,
                         NavigationEntry<Destination> current,
                         NavigationChangeKind kind) {
      const NavigationTransitionSpec<Destination>& spec =
          transitionSpec.value();
      const ActiveNavigationTransition transition{
          now_seconds, 0.0f, outgoing_index, incoming_index,
          std::move(previous), std::move(current), kind};
      ui.setInert(screens[outgoing_index].screenRoot, true);
      activeTransition = transition;
      transitionDeadline = std::min(now_seconds + spec.frameIntervalSeconds,
                                    now_seconds + spec.durationSeconds);
      emitTransition(transition, NavigationTransitionPhase::started, 0.0f);
    }

    UiHandle ui;
    Navigator<Destination> navigator;
    std::vector<NavigationScreenBinding<Destination>> screens;
    std::ptrdiff_t activeIndex = -1;
    NavigationOptional<std::uint64_t> activeEntryId;
    NavigationOptional<NavigationEntry<Destination>> pendingEntry;
    NavigationOptional<NavigationSnapshot<Destination>> pendingSnapshot;
    NavigationOptional<NavigationChangeKind> pendingKind;
    bool pendingChange;
    std::unordered_map<std::uint64_t, Node> savedFocus;
    NavigationOptional<NavigationTransitionSpec<Destination>> transitionSpec;
    NavigationOptional<ActiveNavigationTransition> activeTransition;
    NavigationOptional<double> transitionDeadline;
  };

  std::shared_ptr<Core> core_;
  NavigationSubscription subscription_;
};

template <typename Destination>
class Link {
 public:
  static Link mount(Ui& ui, Navigator<Destination> navigator,
                    Destination destination, std::string label,
                    bool disabled = false,
                    const Style* container_style = nullptr,
                    const Style* text_style = nullptr,
                    const std::string& identifier = std::string()) {
    Link result;
    result.ui_ = ui.handle();
    result.state_ = std::make_shared<State>(
        std::move(navigator), std::move(destination), std::move(label),
        disabled);
    result.container_ = container_style == nullptr
                            ? ui.box(identifier)
                            : ui.box(identifier, *container_style);
    ui.within(result.container_, [&]() {
      result.labelNode_ =
          text_style == nullptr
              ? ui.text(result.state_->label)
              : ui.text(result.state_->label, std::string(), *text_style);
    });
    Style pointer_passthrough;
    pointer_passthrough.set("pointer-events", keyword("none"));
    ui.apply(result.labelNode_, pointer_passthrough, 0u, 1);
    ui.setFocusable(result.container_);
    ui.setAccessibility(result.container_, AccessibleRole::link,
                        result.state_->label);
    ui.setState(result.container_, NodeState::disabled, disabled);

    const std::shared_ptr<State> click_state = result.state_;
    result.ui_.setDefaultAction(
        result.container_, CBSS_EVENT_CLICK,
        [click_state](const Event&) {
          if (click_state->disabled) {
            return EventOutcome();
          }
          const bool activated =
              click_state->navigator.push(click_state->destination);
          return EventOutcome(activated, activated, false);
        });
    const UiHandle key_ui = result.ui_;
    const Node key_container = result.container_;
    const std::shared_ptr<State> key_state = result.state_;
    result.ui_.setDefaultAction(
        result.container_, CBSS_EVENT_KEY_DOWN,
        [key_ui, key_container, key_state](const Event& event) {
          if (key_state->disabled || event.key != "Enter") {
            return EventOutcome();
          }
          return key_ui.emit(key_container, InputEvent(CBSS_EVENT_CLICK))
              .outcome;
        });
    return result;
  }

  Node container() const noexcept { return container_; }
  Node labelNode() const noexcept { return labelNode_; }
  const std::string& label() const noexcept { return state_->label; }
  const Destination& destination() const noexcept {
    return state_->destination;
  }
  bool disabled() const noexcept { return state_->disabled; }

  void setLabel(std::string label) {
    state_->label = std::move(label);
    ui_.setText(labelNode_, state_->label);
    ui_.setAccessibility(container_, AccessibleRole::link, state_->label);
  }

  void setDestination(Destination destination) {
    state_->destination = std::move(destination);
  }

  void setDisabled(bool disabled) {
    state_->disabled = disabled;
    ui_.setState(container_, NodeState::disabled, disabled);
  }

  bool activate() {
    return !state_->disabled &&
           state_->navigator.push(state_->destination);
  }

  void onClick(std::function<EventOutcome(const Event&)> handler) {
    ui_.on(container_, CBSS_EVENT_CLICK, std::move(handler));
  }

 private:
  struct State {
    State(Navigator<Destination> source, Destination target,
          std::string text, bool is_disabled)
        : navigator(std::move(source)),
          destination(std::move(target)),
          label(std::move(text)),
          disabled(is_disabled) {}

    Navigator<Destination> navigator;
    Destination destination;
    std::string label;
    bool disabled;
  };

  UiHandle ui_;
  Node container_;
  Node labelNode_;
  std::shared_ptr<State> state_;
};

}  // namespace cbss

#endif
