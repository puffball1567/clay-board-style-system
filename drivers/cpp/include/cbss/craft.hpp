#ifndef CBSS_CRAFT_HPP
#define CBSS_CRAFT_HPP

#include "cbss.h"
#include "store.hpp"

#include <cstdint>
#include <exception>
#include <functional>
#include <initializer_list>
#include <memory>
#include <new>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace cbss {

class Error : public std::runtime_error {
 public:
  Error(CbssStatus status, const std::string& message)
      : std::runtime_error(message), status_(status) {}

  CbssStatus status() const noexcept { return status_; }

 private:
  CbssStatus status_;
};

class ContractError : public std::runtime_error {
 public:
  explicit ContractError(const std::string& message)
      : std::runtime_error(message) {}
};

struct CapabilityRequirement {
  std::uint32_t id;
  std::uint32_t minimum_version;
};

class Contract {
 public:
  static std::uint32_t abiVersion() noexcept { return cbss_abi_version(); }

  static std::uint32_t driverVersion() noexcept {
    return cbss_driver_contract_version();
  }

  static bool has(std::uint32_t capability,
                  std::uint32_t minimum_version = 1u) noexcept {
    return cbss_has_capability(capability, minimum_version) != 0;
  }

  static void require(
      std::initializer_list<CapabilityRequirement> capabilities) {
    if (abiVersion() != CBSS_ABI_VERSION) {
      std::ostringstream message;
      message << "CBSS ABI mismatch: C++ Driver expects "
              << CBSS_ABI_VERSION << ", runtime provides " << abiVersion();
      throw ContractError(message.str());
    }
    if (driverVersion() != CBSS_DRIVER_CONTRACT_VERSION) {
      std::ostringstream message;
      message << "Craft Driver contract mismatch: C++ Driver expects "
              << CBSS_DRIVER_CONTRACT_VERSION << ", runtime provides "
              << driverVersion();
      throw ContractError(message.str());
    }
    for (const CapabilityRequirement& requirement : capabilities) {
      if (!has(requirement.id, requirement.minimum_version)) {
        std::ostringstream message;
        message << "CBSS capability " << requirement.id << " version "
                << requirement.minimum_version << " is unavailable";
        throw ContractError(message.str());
      }
    }
  }

  static void requireAuthoring() {
    require({
        {CBSS_CAPABILITY_RETAINED_TREE, 1u},
        {CBSS_CAPABILITY_TYPED_STYLE, 1u},
        {CBSS_CAPABILITY_FLEX_LAYOUT, 1u},
    });
  }
};

enum class Unit : std::uint32_t {
  px = CBSS_UNIT_PX,
  percent = CBSS_UNIT_PERCENT,
  em = CBSS_UNIT_EM,
  rem = CBSS_UNIT_REM,
  fill = CBSS_UNIT_FILL,
  content = CBSS_UNIT_CONTENT,
  minContent = CBSS_UNIT_MIN_CONTENT,
  maxContent = CBSS_UNIT_MAX_CONTENT,
  fitContent = CBSS_UNIT_FIT_CONTENT,
  automatic = CBSS_UNIT_AUTO,
  none = CBSS_UNIT_NONE,
  vw = CBSS_UNIT_VW,
  vh = CBSS_UNIT_VH,
  vmin = CBSS_UNIT_VMIN,
  vmax = CBSS_UNIT_VMAX,
  lh = CBSS_UNIT_LH,
  rlh = CBSS_UNIT_RLH,
  ex = CBSS_UNIT_EX,
  ch = CBSS_UNIT_CH,
  rex = CBSS_UNIT_REX,
  rch = CBSS_UNIT_RCH,
};

struct Length {
  Unit unit;
  float value;
};

inline Length px(float value) { return {Unit::px, value}; }
inline Length percent(float value) { return {Unit::percent, value}; }
inline Length em(float value) { return {Unit::em, value}; }
inline Length rem(float value) { return {Unit::rem, value}; }
inline Length fill(float value = 1.0f) { return {Unit::fill, value}; }
inline Length content() { return {Unit::content, 0.0f}; }
inline Length automatic() { return {Unit::automatic, 0.0f}; }

struct Keyword {
  std::string value;
};

inline Keyword keyword(std::string value) { return {std::move(value)}; }

struct Color {
  float red;
  float green;
  float blue;
  float alpha;
};

enum class NodeState : std::uint32_t {
  hover = CBSS_STATE_HOVER,
  active = CBSS_STATE_ACTIVE,
  focus = CBSS_STATE_FOCUS,
  focusVisible = CBSS_STATE_FOCUS_VISIBLE,
  disabled = CBSS_STATE_DISABLED,
  checked = CBSS_STATE_CHECKED,
  selected = CBSS_STATE_SELECTED,
  open = CBSS_STATE_OPEN,
  invalid = CBSS_STATE_INVALID,
};

struct CraftDiagnostic {
  std::uint32_t domain;
  std::uint32_t code;
  std::string path;
  std::string message;
};

struct CraftPackInfo {
  std::string id;
  std::string version;
};

inline Color rgb(float red, float green, float blue) {
  return {red, green, blue, 1.0f};
}

inline Color rgba(float red, float green, float blue, float alpha) {
  return {red, green, blue, alpha};
}

class Style {
 public:
  Style() : handle_(cbss_style_create()) {
    if (handle_ == nullptr) {
      throw std::bad_alloc();
    }
  }

  ~Style() { cbss_style_destroy(handle_); }

  Style(const Style&) = delete;
  Style& operator=(const Style&) = delete;

  Style(Style&& other) noexcept : handle_(other.handle_) {
    other.handle_ = nullptr;
  }

  Style& operator=(Style&& other) noexcept {
    if (this != &other) {
      cbss_style_destroy(handle_);
      handle_ = other.handle_;
      other.handle_ = nullptr;
    }
    return *this;
  }

  Style& set(const std::string& property, Length value) {
    check(cbss_style_set_length(handle_, property.c_str(),
                                static_cast<std::uint32_t>(value.unit),
                                value.value),
          "set length property '" + property + "'");
    return *this;
  }

  Style& set(const std::string& property, Keyword value) {
    check(cbss_style_set_keyword(handle_, property.c_str(),
                                 value.value.c_str()),
          "set keyword property '" + property + "'");
    return *this;
  }

  Style& set(const std::string& property, Color value) {
    const CbssColor color = {
        value.red, value.green, value.blue, value.alpha};
    check(cbss_style_set_color(handle_, property.c_str(), color),
          "set color property '" + property + "'");
    return *this;
  }

  Style& number(const std::string& property, float value) {
    check(cbss_style_set_number(handle_, property.c_str(), value),
          "set numeric property '" + property + "'");
    return *this;
  }

  Style& clear() {
    check(cbss_style_clear(handle_), "clear Style");
    return *this;
  }

  CbssStyle* nativeHandle() const noexcept { return handle_; }

 private:
  static void check(CbssStatus status, const std::string& operation) {
    if (status != CBSS_OK) {
      throw Error(status, "Unable to " + operation);
    }
  }

  CbssStyle* handle_;
};

class Node {
 public:
  Node() noexcept : owner_(nullptr), value_(CBSS_NODE_NONE) {}

  bool valid() const noexcept {
    return owner_ != nullptr && value_ != CBSS_NODE_NONE;
  }
  std::uint32_t nativeId() const noexcept { return value_; }

  friend bool operator==(Node left, Node right) noexcept {
    return left.owner_ == right.owner_ && left.value_ == right.value_;
  }

  friend bool operator!=(Node left, Node right) noexcept {
    return !(left == right);
  }

 private:
  Node(const CbssContext* owner, std::uint32_t value) noexcept
      : owner_(owner), value_(value) {}

  const CbssContext* owner_;
  std::uint32_t value_;
  friend class Ui;
};

class Ui;
class ComponentScope;

class CraftComponent {
 public:
  CraftComponent() noexcept : active_(false) {}

  CraftComponent(const CraftComponent&) = delete;
  CraftComponent& operator=(const CraftComponent&) = delete;

  CraftComponent(CraftComponent&& other) noexcept
      : root_(other.root_),
        craft_name_(std::move(other.craft_name_)),
        active_(other.active_) {
    other.root_ = Node();
    other.active_ = false;
  }

  CraftComponent& operator=(CraftComponent&& other) noexcept {
    if (this != &other) {
      root_ = other.root_;
      craft_name_ = std::move(other.craft_name_);
      active_ = other.active_;
      other.root_ = Node();
      other.active_ = false;
    }
    return *this;
  }

  bool active() const noexcept { return active_; }

  Node root() const {
    if (!active_) {
      throw Error(CBSS_INVALID_HANDLE,
                  "access Craft Component: component is not mounted");
    }
    return root_;
  }

  const std::string& craftName() const noexcept { return craft_name_; }

 private:
  CraftComponent(Node root, std::string craft_name)
      : root_(root), craft_name_(std::move(craft_name)), active_(true) {}

  Node root_;
  std::string craft_name_;
  bool active_;
  friend class Ui;
  friend class ComponentScope;
};

class ComponentScope {
 public:
  Node root() const { return component_.root(); }
  const std::string& craftName() const noexcept {
    return component_.craftName();
  }

  Node box(const std::string& identifier = std::string());
  Node box(const std::string& identifier, const Style& style);

  template <typename Children>
  Node box(const std::string& identifier, Children&& children);

  template <typename Children>
  Node box(const std::string& identifier, const Style& style,
           Children&& children);

  Node text(const std::string& value,
            const std::string& identifier = std::string());
  Node text(const std::string& value, const std::string& identifier,
            const Style& style);
  Node image(const std::string& source, float width, float height,
             const std::string& identifier = std::string());
  Node image(const std::string& source, float width, float height,
             const std::string& identifier, const Style& style);
  void publicStyleSlot(const std::string& slot);
  void publicStyleSlot(const std::string& slot, Node target);

  template <typename Callback>
  void on(Node node, CbssEventKind kind, Callback&& callback);

  template <typename Callback>
  void onRoot(CbssEventKind kind, Callback&& callback);

 private:
  ComponentScope(Ui& ui, CraftComponent& component)
      : ui_(ui), component_(component) {}

  Ui& ui_;
  CraftComponent& component_;
  friend class Ui;
};

class EventOutcome {
 public:
  constexpr EventOutcome(bool handled = false,
                         bool stop_propagation = false,
                         bool prevent_default = false) noexcept
      : bits_((handled
                   ? static_cast<std::uint8_t>(CBSS_EVENT_OUTCOME_HANDLED)
                   : 0u) |
              (stop_propagation
                   ? static_cast<std::uint8_t>(
                         CBSS_EVENT_OUTCOME_STOP_PROPAGATION)
                   : 0u) |
              (prevent_default
                   ? static_cast<std::uint8_t>(
                         CBSS_EVENT_OUTCOME_PREVENT_DEFAULT)
                   : 0u)) {}

  static constexpr EventOutcome handled() noexcept {
    return EventOutcome(true, false, false);
  }

  constexpr bool isHandled() const noexcept {
    return (bits_ & CBSS_EVENT_OUTCOME_HANDLED) != 0u;
  }
  constexpr bool stopsPropagation() const noexcept {
    return (bits_ & CBSS_EVENT_OUTCOME_STOP_PROPAGATION) != 0u;
  }
  constexpr bool preventsDefault() const noexcept {
    return (bits_ & CBSS_EVENT_OUTCOME_PREVENT_DEFAULT) != 0u;
  }
  constexpr std::uint8_t bits() const noexcept { return bits_; }

 private:
  std::uint8_t bits_;
};

struct Event {
  CbssEventKind kind;
  std::uint32_t target;
  std::uint32_t current_target;
  std::uint32_t flags;
  float local_x;
  float local_y;
  float x;
  float y;
  float delta_x;
  float delta_y;
  std::int32_t button;
  std::uint32_t modifiers;
  std::string key;
  std::string text;
  CbssPointerData pointer;
  std::uint64_t timestamp;
  std::string motion_name;
  double motion_elapsed_seconds;
  std::uint64_t motion_iteration;

  explicit Event(const CbssEvent& value)
      : kind(static_cast<CbssEventKind>(value.kind)),
        target(value.target),
        current_target(value.current_target),
        flags(value.flags),
        local_x(value.local_x),
        local_y(value.local_y),
        x(value.x),
        y(value.y),
        delta_x(value.delta_x),
        delta_y(value.delta_y),
        button(value.button),
        modifiers(value.modifiers),
        key((value.flags & CBSS_EVENT_HAS_KEY) != 0u && value.key != nullptr
                ? value.key
                : ""),
        text((value.flags & CBSS_EVENT_HAS_TEXT) != 0u && value.text != nullptr
                 ? value.text
                 : ""),
        pointer(value.pointer),
        timestamp(value.timestamp),
        motion_name((value.flags & CBSS_EVENT_HAS_MOTION) != 0u &&
                            value.motion_name != nullptr
                        ? value.motion_name
                        : ""),
        motion_elapsed_seconds(value.motion_elapsed_seconds),
        motion_iteration(value.motion_iteration) {}
};

struct InputEvent {
  explicit InputEvent(CbssEventKind event_kind) : kind(event_kind) {}

  InputEvent& position(float value_x, float value_y) noexcept {
    flags |= CBSS_INPUT_HAS_POSITION;
    x = value_x;
    y = value_y;
    return *this;
  }

  InputEvent& movement(float value_x, float value_y) noexcept {
    flags |= CBSS_INPUT_HAS_DELTA;
    delta_x = value_x;
    delta_y = value_y;
    return *this;
  }

  InputEvent& mouseButton(std::int32_t value) noexcept {
    flags |= CBSS_INPUT_HAS_BUTTON;
    button = value;
    return *this;
  }

  InputEvent& keyValue(std::string value) {
    flags |= CBSS_INPUT_HAS_KEY;
    key = std::move(value);
    return *this;
  }

  InputEvent& textValue(std::string value) {
    flags |= CBSS_INPUT_HAS_TEXT;
    text = std::move(value);
    return *this;
  }

  InputEvent& pointerValue(const CbssPointerData& value) noexcept {
    flags |= CBSS_INPUT_HAS_POINTER;
    pointer = value;
    return *this;
  }

  CbssEventKind kind;
  std::uint32_t flags = 0u;
  std::uint32_t modifiers = 0u;
  std::int32_t button = 0;
  float x = 0.0f;
  float y = 0.0f;
  float delta_x = 0.0f;
  float delta_y = 0.0f;
  std::string key;
  std::string text;
  CbssPointerData pointer = {};
  std::uint64_t timestamp = 0u;

 private:
  CbssInputEvent native() const noexcept {
    CbssInputEvent result = {};
    result.kind = static_cast<std::uint32_t>(kind);
    result.flags = flags;
    result.modifiers = modifiers;
    result.button = button;
    result.x = x;
    result.y = y;
    result.delta_x = delta_x;
    result.delta_y = delta_y;
    result.key = (flags & CBSS_INPUT_HAS_KEY) != 0u ? key.c_str() : nullptr;
    result.text =
        (flags & CBSS_INPUT_HAS_TEXT) != 0u ? text.c_str() : nullptr;
    result.pointer = pointer;
    result.timestamp = timestamp;
    return result;
  }

  friend class Ui;
};

struct DispatchSummary {
  std::uint32_t target;
  std::uint32_t dispatch_count;
  bool handled;
  EventOutcome outcome;
  bool needs_compute;
  bool paint_changed;
  bool focus_changed;
};

namespace detail {

struct EventCallbackState
    : std::enable_shared_from_this<EventCallbackState> {
  explicit EventCallbackState(std::function<EventOutcome(const Event&)> value)
      : callback(std::move(value)) {}

  static std::uint8_t invoke(CbssContext*, const CbssEvent* event,
                             void* user_data) noexcept {
    if (event == nullptr || user_data == nullptr) {
      return EventOutcome(true, true, true).bits();
    }
    EventCallbackState* raw = static_cast<EventCallbackState*>(user_data);
    try {
      const std::shared_ptr<EventCallbackState> keep_alive =
          raw->shared_from_this();
      return keep_alive->callback(Event(*event)).bits();
    } catch (...) {
      raw->failure = std::current_exception();
      return EventOutcome(true, true, true).bits();
    }
  }

  std::function<EventOutcome(const Event&)> callback;
  std::exception_ptr failure;
};

struct EventSubscriptionState {
  std::uint32_t node;
  std::shared_ptr<EventCallbackState> callback;
};

struct EventDriverState {
  explicit EventDriverState(CbssContext* value) : context(value) {}

  void addSubscription(
      std::uint64_t id, std::uint32_t node,
      const std::shared_ptr<EventCallbackState>& callback) {
    subscriptions.emplace(id, EventSubscriptionState{node, callback});
    try {
      subscriptions_by_node[node].insert(id);
    } catch (...) {
      subscriptions.erase(id);
      throw;
    }
  }

  void unsubscribe(std::uint64_t id) noexcept {
    if (context == nullptr) {
      return;
    }
    const auto found = subscriptions.find(id);
    if (found == subscriptions.end()) {
      return;
    }
    if (cbss_context_unsubscribe_event(context, id) == CBSS_OK) {
      const std::uint32_t node = found->second.node;
      subscriptions.erase(found);
      const auto indexed = subscriptions_by_node.find(node);
      if (indexed != subscriptions_by_node.end()) {
        indexed->second.erase(id);
        if (indexed->second.empty()) {
          subscriptions_by_node.erase(indexed);
        }
      }
    }
  }

  bool hasSubscription(std::uint64_t id) const noexcept {
    return subscriptions.find(id) != subscriptions.end();
  }

  void releaseNodes(
      const std::unordered_set<std::uint32_t>& nodes) noexcept {
    for (const std::uint32_t node : nodes) {
      handlers.erase(node);
      const auto indexed = subscriptions_by_node.find(node);
      if (indexed == subscriptions_by_node.end()) {
        continue;
      }
      for (const std::uint64_t id : indexed->second) {
        subscriptions.erase(id);
      }
      subscriptions_by_node.erase(indexed);
    }
  }

  void clear() noexcept {
    handlers.clear();
    subscriptions.clear();
    subscriptions_by_node.clear();
  }

  CbssContext* context;
  std::unordered_map<
      std::uint32_t,
      std::unordered_map<std::uint32_t, std::shared_ptr<EventCallbackState>>>
      handlers;
  std::unordered_map<std::uint64_t, EventSubscriptionState> subscriptions;
  std::unordered_map<std::uint32_t, std::unordered_set<std::uint64_t>>
      subscriptions_by_node;
};

}  // namespace detail

class EventSubscription {
 public:
  EventSubscription() noexcept : id_(0u), active_(false) {}
  ~EventSubscription() { close(); }

  EventSubscription(const EventSubscription&) = delete;
  EventSubscription& operator=(const EventSubscription&) = delete;

  EventSubscription(EventSubscription&& other) noexcept
      : state_(std::move(other.state_)),
        id_(other.id_),
        active_(other.active_) {
    other.id_ = 0u;
    other.active_ = false;
  }

  EventSubscription& operator=(EventSubscription&& other) noexcept {
    if (this != &other) {
      close();
      state_ = std::move(other.state_);
      id_ = other.id_;
      active_ = other.active_;
      other.id_ = 0u;
      other.active_ = false;
    }
    return *this;
  }

  bool active() const noexcept {
    if (!active_) {
      return false;
    }
    const std::shared_ptr<detail::EventDriverState> state = state_.lock();
    return state && state->hasSubscription(id_);
  }

  void close() noexcept {
    if (!active_) {
      return;
    }
    if (const std::shared_ptr<detail::EventDriverState> state = state_.lock()) {
      state->unsubscribe(id_);
    }
    active_ = false;
  }

 private:
  EventSubscription(std::weak_ptr<detail::EventDriverState> state,
                    std::uint64_t id) noexcept
      : state_(std::move(state)), id_(id), active_(true) {}

  std::weak_ptr<detail::EventDriverState> state_;
  std::uint64_t id_;
  bool active_;
  friend class Ui;
};

class Ui {
 public:
  Ui() : context_(nullptr) {
    Contract::requireAuthoring();
    context_ = cbss_context_create();
    if (context_ == nullptr) {
      throw std::bad_alloc();
    }
    try {
      events_ = std::make_shared<detail::EventDriverState>(context_);
    } catch (...) {
      cbss_context_destroy(context_);
      context_ = nullptr;
      throw;
    }
  }

  ~Ui() {
    cbss_context_destroy(context_);
    if (events_) {
      events_->context = nullptr;
      events_->clear();
    }
  }

  Ui(const Ui&) = delete;
  Ui& operator=(const Ui&) = delete;
  Ui(Ui&&) = delete;
  Ui& operator=(Ui&&) = delete;

  Node box(const std::string& identifier = std::string()) {
    return addBox(identifier, nullptr);
  }

  Node box(const std::string& identifier, const Style& style) {
    return addBox(identifier, &style);
  }

  template <
      typename Children,
      typename std::enable_if<
          !std::is_same<typename std::decay<Children>::type, Style>::value,
          int>::type = 0>
  Node box(const std::string& identifier, Children&& children) {
    Node node = addBox(identifier, nullptr);
    ParentScope scope(*this, node);
    std::forward<Children>(children)();
    return node;
  }

  template <typename Children>
  Node box(const std::string& identifier, const Style& style,
           Children&& children) {
    Node node = addBox(identifier, &style);
    ParentScope scope(*this, node);
    std::forward<Children>(children)();
    return node;
  }

  template <typename Children>
  void within(Node parent, Children&& children) {
    requireNode(parent, "enter parent scope");
    ParentScope scope(*this, parent);
    std::forward<Children>(children)();
  }

  Node text(const std::string& value,
            const std::string& identifier = std::string()) {
    return addText(value, identifier, nullptr);
  }

  Node text(const std::string& value, const std::string& identifier,
            const Style& style) {
    return addText(value, identifier, &style);
  }

  Node image(const std::string& source, float width, float height,
             const std::string& identifier = std::string()) {
    return addImage(source, width, height, identifier, nullptr);
  }

  Node image(const std::string& source, float width, float height,
             const std::string& identifier, const Style& style) {
    return addImage(source, width, height, identifier, &style);
  }

  template <typename Children>
  CraftComponent component(const std::string& craft_name,
                           const std::string& identifier,
                           Children&& children) {
    return addComponent(craft_name, identifier, nullptr,
                        std::forward<Children>(children));
  }

  template <typename Children>
  CraftComponent component(const std::string& craft_name,
                           const std::string& identifier,
                           const Style& owned_style, Children&& children) {
    return addComponent(craft_name, identifier, &owned_style,
                        std::forward<Children>(children));
  }

  std::uint32_t unmount(CraftComponent& component) {
    if (!component.active_) {
      throw Error(CBSS_INVALID_HANDLE,
                  "unmount Craft Component: component is not mounted");
    }
    requireNode(component.root_, "unmount Craft Component");
    const std::uint32_t removed = removeSubtree(component.root_);
    component.root_ = Node();
    component.active_ = false;
    return removed;
  }

  void setText(Node node, const std::string& value) {
    requireNode(node, "set Text value");
    check(cbss_node_set_text(context_, node.value_, value.c_str()),
          "set Text value");
  }

  std::string textValue(Node node) const {
    requireNode(node, "read Text value");
    return readContextString(
        [this, node](char* buffer, std::uint32_t capacity) {
          return cbss_node_text(context_, node.value_, buffer, capacity);
        });
  }

  void setImage(Node node, const std::string& source, float width,
                float height) {
    requireNode(node, "set Image value");
    check(cbss_node_set_image(context_, node.value_, source.c_str(), width,
                              height),
          "set Image value");
  }

  std::string imageSource(Node node) const {
    requireNode(node, "read Image source");
    return readContextString(
        [this, node](char* buffer, std::uint32_t capacity) {
          return cbss_node_image_source(context_, node.value_, buffer,
                                        capacity);
        });
  }

  void addGroup(Node node, const std::string& group) {
    requireNode(node, "add group");
    check(cbss_node_add_group(context_, node.value_, group.c_str()),
          "add group");
  }

  void setAttribute(Node node, const std::string& name,
                    const std::string& value) {
    requireNode(node, "set attribute");
    check(cbss_node_set_attribute(context_, node.value_, name.c_str(),
                                  value.c_str()),
          "set attribute");
  }

  void setState(Node node, NodeState state, bool enabled) {
    requireNode(node, "set retained state");
    check(cbss_node_set_state(context_, node.value_,
                              static_cast<std::uint32_t>(state),
                              enabled ? 1u : 0u),
          "set retained state");
  }

  void apply(Node node, const Style& style, std::uint32_t state_mask = 0u,
             std::int32_t priority = 0) {
    requireNode(node, "apply Style");
    check(cbss_node_apply_style(context_, node.value_, style.nativeHandle(),
                                state_mask, priority),
          "apply Style");
  }

  void exposeStyleSlot(Node owner, Node target,
                       const std::string& component,
                       const std::string& slot) {
    Contract::require({{CBSS_CAPABILITY_CRAFT_STYLE, 1u}});
    requireNode(owner, "expose Craft Style Slot owner");
    requireNode(target, "expose Craft Style Slot target");
    check(cbss_node_expose_craft_style_slot(
              context_, owner.value_, target.value_, component.c_str(),
              slot.c_str()),
          "expose Craft Style Slot");
  }

  void replaceCraftStyle(const std::string& source) {
    Contract::require({{CBSS_CAPABILITY_CRAFT_STYLE, 1u}});
    if (source.empty()) {
      throw Error(CBSS_INVALID_ARGUMENT,
                  "replace Craft Style: source is empty");
    }
    check(cbss_context_replace_craft_style_json(
              context_, reinterpret_cast<const std::uint8_t*>(source.data()),
              checkedSourceLength(source, CBSS_MAX_CRAFT_STYLE_SOURCE_BYTES,
                                  "replace Craft Style")),
          "replace Craft Style");
  }

  bool removeCraftStyle(const std::string& name) {
    std::uint8_t removed = 0u;
    check(cbss_context_remove_craft_style(
              context_, name.c_str(), &removed),
          "remove Craft Style");
    return removed != 0u;
  }

  std::vector<std::string> activeCraftStyles() const {
    std::vector<std::string> result;
    const std::uint32_t count =
        cbss_context_active_craft_style_count(context_);
    result.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index) {
      result.push_back(readContextString(
          [this, index](char* buffer, std::uint32_t capacity) {
            return cbss_context_active_craft_style_name(
                context_, index, buffer, capacity);
          }));
    }
    return result;
  }

  void replaceCraftPack(const std::string& source) {
    Contract::require({{CBSS_CAPABILITY_CRAFT_PACK, 1u}});
    if (source.empty()) {
      throw Error(CBSS_INVALID_ARGUMENT,
                  "replace Craft Pack: source is empty");
    }
    check(cbss_context_replace_craft_pack_json(
              context_, reinterpret_cast<const std::uint8_t*>(source.data()),
              checkedSourceLength(source, CBSS_MAX_CRAFT_PACK_SOURCE_BYTES,
                                  "replace Craft Pack")),
          "replace Craft Pack");
  }

  bool removeCraftPack(const std::string& id) {
    std::uint8_t removed = 0u;
    check(cbss_context_remove_craft_pack(context_, id.c_str(), &removed),
          "remove Craft Pack");
    return removed != 0u;
  }

  std::vector<CraftPackInfo> activeCraftPacks() const {
    std::vector<CraftPackInfo> result;
    const std::uint32_t count =
        cbss_context_active_craft_pack_count(context_);
    result.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index) {
      CraftPackInfo info;
      info.id = readContextString(
          [this, index](char* buffer, std::uint32_t capacity) {
            return cbss_context_active_craft_pack_id(
                context_, index, buffer, capacity);
          });
      info.version = readContextString(
          [this, index](char* buffer, std::uint32_t capacity) {
            return cbss_context_active_craft_pack_version(
                context_, index, buffer, capacity);
          });
      result.push_back(std::move(info));
    }
    return result;
  }

  std::vector<CraftDiagnostic> craftDiagnostics() const {
    std::vector<CraftDiagnostic> result;
    const std::uint32_t count = cbss_context_craft_diagnostic_count(context_);
    result.reserve(count);
    for (std::uint32_t index = 0; index < count; ++index) {
      CbssCraftDiagnostic native = {};
      check(cbss_context_craft_diagnostic_at(context_, index, &native),
            "read Craft diagnostic");
      CraftDiagnostic diagnostic;
      diagnostic.domain = native.domain;
      diagnostic.code = native.code;
      diagnostic.path = readContextString(
          [this, index](char* buffer, std::uint32_t capacity) {
            return cbss_context_craft_diagnostic_path(
                context_, index, buffer, capacity);
          });
      diagnostic.message = readContextString(
          [this, index](char* buffer, std::uint32_t capacity) {
            return cbss_context_craft_diagnostic_message(
                context_, index, buffer, capacity);
          });
      result.push_back(std::move(diagnostic));
    }
    return result;
  }

  void compute(float width, float height) {
    check(cbss_context_compute(context_, width, height), "compute layout");
  }

  CbssRect rect(Node node) const {
    requireNode(node, "read layout rectangle");
    CbssRect result = {};
    check(cbss_node_layout_rect(context_, node.value_, &result),
          "read layout rectangle");
    return result;
  }

  std::uint32_t nodeCount() const noexcept {
    return cbss_context_node_count(context_);
  }

  Node parent(Node node) const {
    requireNode(node, "read parent");
    return ownedNode(cbss_node_parent(context_, node.value_));
  }

  std::uint32_t childCount(Node node) const {
    requireNode(node, "read child count");
    return cbss_node_child_count(context_, node.value_);
  }

  std::uint32_t removeSubtree(Node root) {
    Contract::require({{CBSS_CAPABILITY_SUBTREE_LIFECYCLE, 1u}});
    requireNode(root, "remove subtree");
    if (!parents_.empty()) {
      throw Error(CBSS_INVALID_ARGUMENT,
                  "remove subtree: nested construction is active");
    }
    return removeSubtreeNow(root);
  }

  void on(Node node, CbssEventKind kind,
          std::function<EventOutcome(const Event&)> callback) {
    requireEvents();
    requireNode(node, "set event handler");
    if (!callback) {
      throw Error(CBSS_INVALID_ARGUMENT,
                  "set event handler: callback is empty");
    }
    const std::shared_ptr<detail::EventCallbackState> holder =
        std::make_shared<detail::EventCallbackState>(std::move(callback));
    check(cbss_node_set_event_handler(
              context_, node.value_, static_cast<std::uint32_t>(kind),
              &detail::EventCallbackState::invoke, holder.get()),
          "set event handler");
    try {
      events_->handlers[node.value_][static_cast<std::uint32_t>(kind)] = holder;
    } catch (...) {
      cbss_node_set_event_handler(context_, node.value_,
                                  static_cast<std::uint32_t>(kind), nullptr,
                                  nullptr);
      throw;
    }
  }

  void clearHandler(Node node, CbssEventKind kind) {
    requireNode(node, "clear event handler");
    check(cbss_node_set_event_handler(
              context_, node.value_, static_cast<std::uint32_t>(kind), nullptr,
              nullptr),
          "clear event handler");
    const auto node_handlers = events_->handlers.find(node.value_);
    if (node_handlers != events_->handlers.end()) {
      node_handlers->second.erase(static_cast<std::uint32_t>(kind));
      if (node_handlers->second.empty()) {
        events_->handlers.erase(node_handlers);
      }
    }
  }

  EventSubscription subscribe(
      Node node, CbssEventKind kind,
      std::function<EventOutcome(const Event&)> callback) {
    requireEvents();
    requireNode(node, "subscribe event");
    if (!callback) {
      throw Error(CBSS_INVALID_ARGUMENT, "subscribe event: callback is empty");
    }
    const std::shared_ptr<detail::EventCallbackState> holder =
        std::make_shared<detail::EventCallbackState>(std::move(callback));
    std::uint64_t subscription = 0u;
    check(cbss_node_subscribe_event(
              context_, node.value_, static_cast<std::uint32_t>(kind),
              &detail::EventCallbackState::invoke, holder.get(),
              &subscription),
          "subscribe event");
    try {
      events_->addSubscription(subscription, node.value_, holder);
    } catch (...) {
      cbss_context_unsubscribe_event(context_, subscription);
      throw;
    }
    return EventSubscription(events_, subscription);
  }

  DispatchSummary emit(Node node, const InputEvent& input) {
    requireEvents();
    requireNode(node, "emit event");
    const CbssInputEvent native = input.native();
    CbssDispatchSummary summary = {};
    check(cbss_context_emit_event(context_, node.value_, &native, &summary),
          "emit event");
    return DispatchSummary{
        summary.target,
        summary.dispatch_count,
        summary.handled != 0u,
        EventOutcome((summary.outcome & CBSS_EVENT_OUTCOME_HANDLED) != 0u,
                     (summary.outcome &
                      CBSS_EVENT_OUTCOME_STOP_PROPAGATION) != 0u,
                     (summary.outcome & CBSS_EVENT_OUTCOME_PREVENT_DEFAULT) !=
                         0u),
        summary.needs_compute != 0u,
        summary.paint_changed != 0u,
        summary.focus_changed != 0u};
  }

  bool callbackFailed() const noexcept {
    for (const auto& item : events_->handlers) {
      for (const auto& handler : item.second) {
        if (handler.second->failure) {
          return true;
        }
      }
    }
    for (const auto& item : events_->subscriptions) {
      if (item.second.callback->failure) {
        return true;
      }
    }
    return false;
  }

  void rethrowCallbackFailure() {
    for (const auto& item : events_->handlers) {
      for (const auto& handler : item.second) {
        if (handler.second->failure) {
          const std::exception_ptr failure = handler.second->failure;
          handler.second->failure = nullptr;
          std::rethrow_exception(failure);
        }
      }
    }
    for (const auto& item : events_->subscriptions) {
      if (item.second.callback->failure) {
        const std::exception_ptr failure = item.second.callback->failure;
        item.second.callback->failure = nullptr;
        std::rethrow_exception(failure);
      }
    }
  }

  void reset() {
    if (!parents_.empty()) {
      throw Error(CBSS_INVALID_ARGUMENT,
                  "reset UI: nested construction is active");
    }
    check(cbss_context_reset(context_), "reset UI");
    events_->clear();
  }

  CbssContext* nativeHandle() const noexcept { return context_; }

 private:
  class ParentScope {
   public:
    ParentScope(Ui& ui, Node node) : ui_(ui) {
      ui_.parents_.push_back(node.value_);
    }

    ~ParentScope() { ui_.parents_.pop_back(); }

    ParentScope(const ParentScope&) = delete;
    ParentScope& operator=(const ParentScope&) = delete;

   private:
    Ui& ui_;
  };

  std::uint32_t currentParent() const noexcept {
    return parents_.empty() ? CBSS_NODE_NONE : parents_.back();
  }

  std::unordered_set<std::uint32_t> collectSubtree(Node root) const {
    std::unordered_set<std::uint32_t> result;
    std::vector<std::uint32_t> pending(1u, root.value_);
    while (!pending.empty()) {
      const std::uint32_t node = pending.back();
      pending.pop_back();
      if (!result.insert(node).second) {
        continue;
      }
      const std::uint32_t count = cbss_node_child_count(context_, node);
      for (std::uint32_t index = 0u; index < count; ++index) {
        const std::uint32_t child = cbss_node_child(context_, node, index);
        if (child == CBSS_NODE_NONE) {
          throw Error(CBSS_INTERNAL_ERROR,
                      "remove subtree: unable to enumerate child Node");
        }
        pending.push_back(child);
      }
    }
    return result;
  }

  std::uint32_t removeSubtreeNow(Node root) {
    const std::unordered_set<std::uint32_t> nodes = collectSubtree(root);
    std::uint32_t removed = 0u;
    check(cbss_context_remove_subtree(context_, root.value_, &removed),
          "remove subtree");
    events_->releaseNodes(nodes);
    return removed;
  }

  static void requireEvents() {
    Contract::require({{CBSS_CAPABILITY_STANDARD_EVENTS, 1u}});
  }

  static std::uint32_t checkedSourceLength(
      const std::string& source, std::uint32_t maximum,
      const std::string& operation) {
    if (source.size() > maximum ||
        source.size() > std::numeric_limits<std::uint32_t>::max()) {
      throw Error(CBSS_OUT_OF_RANGE, operation + ": source is too large");
    }
    return static_cast<std::uint32_t>(source.size());
  }

  template <typename Reader>
  static std::string readContextString(Reader reader) {
    const std::uint32_t length = reader(nullptr, 0u);
    if (length == 0u) {
      return std::string();
    }
    std::vector<char> buffer(static_cast<std::size_t>(length) + 1u, '\0');
    reader(buffer.data(), static_cast<std::uint32_t>(buffer.size()));
    return std::string(buffer.data(), length);
  }

  Node addBox(const std::string& identifier, const Style* style) {
    Node node = ownedNode(cbss_context_add_box(
        context_, currentParent(), identifier.c_str()));
    checkAdded(node, "add Box");
    if (style != nullptr) {
      apply(node, *style);
    }
    return node;
  }

  Node addText(const std::string& value, const std::string& identifier,
               const Style* style) {
    Node node = ownedNode(cbss_context_add_text(
        context_, currentParent(), value.c_str(), identifier.c_str()));
    checkAdded(node, "add Text");
    if (style != nullptr) {
      apply(node, *style);
    }
    return node;
  }

  Node addImage(const std::string& source, float width, float height,
                const std::string& identifier, const Style* style) {
    Node node = ownedNode(cbss_context_add_image(
        context_, currentParent(), source.c_str(), width, height,
        identifier.c_str()));
    checkAdded(node, "add Image");
    if (style != nullptr) {
      apply(node, *style);
    }
    return node;
  }

  template <typename Children>
  CraftComponent addComponent(const std::string& craft_name,
                              const std::string& identifier,
                              const Style* owned_style,
                              Children&& children) {
    if (craft_name.empty() || craft_name.find('\0') != std::string::npos) {
      throw Error(CBSS_INVALID_ARGUMENT,
                  "mount Craft Component: craft name is empty or contains "
                  "an interior NUL byte");
    }
    const Node root = addBox(identifier, owned_style);
    CraftComponent component(root, craft_name);
    try {
      exposeStyleSlot(root, root, craft_name, "root");
      {
        ParentScope parent(*this, root);
        ComponentScope scope(*this, component);
        std::forward<Children>(children)(scope);
      }
    } catch (...) {
      try {
        removeSubtreeNow(root);
      } catch (...) {
      }
      component.root_ = Node();
      component.active_ = false;
      throw;
    }
    return component;
  }

  void checkAdded(Node node, const std::string& operation) const {
    if (!node.valid()) {
      throw Error(CBSS_INTERNAL_ERROR,
                  operation + ": " + contextErrorMessage());
    }
  }

  void requireNode(Node node, const std::string& operation) const {
    if (!node.valid()) {
      throw Error(CBSS_INVALID_HANDLE, operation + ": invalid Node");
    }
    if (node.owner_ != context_) {
      throw Error(CBSS_INVALID_HANDLE,
                  operation + ": Node belongs to another Ui");
    }
  }

  Node ownedNode(std::uint32_t value) const noexcept {
    return value == CBSS_NODE_NONE ? Node() : Node(context_, value);
  }

  void check(CbssStatus status, const std::string& operation) const {
    if (status != CBSS_OK) {
      throw Error(status, operation + ": " + contextErrorMessage());
    }
  }

  std::string contextErrorMessage() const {
    char buffer[512] = {};
    const std::uint32_t length =
        cbss_context_last_error(context_, buffer, sizeof(buffer));
    if (length == 0u) {
      return "no diagnostic was provided";
    }
    return std::string(buffer);
  }

  CbssContext* context_;
  std::vector<std::uint32_t> parents_;
  std::shared_ptr<detail::EventDriverState> events_;
};

inline Node ComponentScope::box(const std::string& identifier) {
  return ui_.box(identifier);
}

inline Node ComponentScope::box(const std::string& identifier,
                                const Style& style) {
  return ui_.box(identifier, style);
}

template <typename Children>
Node ComponentScope::box(const std::string& identifier, Children&& children) {
  return ui_.box(identifier, std::forward<Children>(children));
}

template <typename Children>
Node ComponentScope::box(const std::string& identifier, const Style& style,
                         Children&& children) {
  return ui_.box(identifier, style, std::forward<Children>(children));
}

inline Node ComponentScope::text(const std::string& value,
                                 const std::string& identifier) {
  return ui_.text(value, identifier);
}

inline Node ComponentScope::text(const std::string& value,
                                 const std::string& identifier,
                                 const Style& style) {
  return ui_.text(value, identifier, style);
}

inline Node ComponentScope::image(const std::string& source, float width,
                                  float height,
                                  const std::string& identifier) {
  return ui_.image(source, width, height, identifier);
}

inline Node ComponentScope::image(const std::string& source, float width,
                                  float height,
                                  const std::string& identifier,
                                  const Style& style) {
  return ui_.image(source, width, height, identifier, style);
}

inline void ComponentScope::publicStyleSlot(const std::string& slot) {
  publicStyleSlot(slot, component_.root());
}

inline void ComponentScope::publicStyleSlot(const std::string& slot,
                                            Node target) {
  ui_.exposeStyleSlot(component_.root(), target, component_.craftName(), slot);
}

template <typename Callback>
void ComponentScope::on(Node node, CbssEventKind kind, Callback&& callback) {
  ui_.on(node, kind, std::forward<Callback>(callback));
}

template <typename Callback>
void ComponentScope::onRoot(CbssEventKind kind, Callback&& callback) {
  on(component_.root(), kind, std::forward<Callback>(callback));
}

}  // namespace cbss

#endif
