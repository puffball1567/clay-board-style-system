#ifndef CBSS_VALIDATION_UI_HPP
#define CBSS_VALIDATION_UI_HPP

#include "craft.hpp"

#include <algorithm>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace cbss {

namespace validation_ui_detail {

class ControlAdapter {
 public:
  virtual ~ControlAdapter() {}
  virtual Node node() const = 0;
  virtual bool active() const = 0;
  virtual bool disabled() const = 0;
  virtual bool checkValidity() = 0;
  virtual bool reportValidity(bool focus) = 0;
  virtual const void* valueIdentity() const = 0;
  virtual const std::vector<const void*>& dependencyIdentities() const = 0;
  virtual void addDependent(std::weak_ptr<ControlAdapter> dependent) = 0;
  virtual void refreshDependency() = 0;
};

template <typename T>
struct ControlState : ControlAdapter,
                      std::enable_shared_from_this<ControlState<T>> {
  ControlState(UiHandle ui_handle, Node control_node,
               ValidationRules<T> rules, T value,
               ValidationReport report_on)
      : ui(std::move(ui_handle)),
        control(control_node),
        dependencies(dependencyIdentityList(rules)),
        binding(std::move(rules), std::move(value), report_on) {}

  static std::vector<const void*> dependencyIdentityList(
      const ValidationRules<T>& rules) {
    std::vector<const void*> result;
    for (const ValidationValue<T>& peer : rules.dependencyReferences()) {
      result.push_back(peer.identity());
    }
    return result;
  }

  Node node() const override { return control; }
  bool active() const override { return attached && ui.active(); }
  bool disabled() const override { return is_disabled; }
  const void* valueIdentity() const override {
    return binding.valueReference().identity();
  }
  const std::vector<const void*>& dependencyIdentities() const override {
    return dependencies;
  }
  void addDependent(std::weak_ptr<ControlAdapter> dependent) override {
    const std::shared_ptr<ControlAdapter> candidate = dependent.lock();
    if (!candidate) return;
    for (const std::weak_ptr<ControlAdapter>& existing : dependents) {
      if (existing.lock() == candidate) return;
    }
    dependents.push_back(std::move(dependent));
  }

  void sync() {
    if (!active()) return;
    ui.setState(control, NodeState::invalid,
                !is_disabled && binding.shouldExpose());
    ui.setAttribute(control, "validation-message",
                    is_disabled ? std::string()
                                : binding.validationMessage());
  }

  ValidationResult evaluate(T value, ValidationTrigger trigger,
                            bool force_report = false,
                            bool notify_dependents = false) {
    if (is_disabled) return ValidationResult();
    if (evaluating) return binding.current();
    struct EvaluationGuard {
      explicit EvaluationGuard(bool& value) : value_(value) { value_ = true; }
      ~EvaluationGuard() { value_ = false; }
      bool& value_;
    } guard(evaluating);
    ValidationResult result =
        binding.evaluate(std::move(value), trigger, force_report);
    sync();
    if (notify_dependents) {
      std::vector<std::weak_ptr<ControlAdapter>> retained;
      retained.reserve(dependents.size());
      for (const std::weak_ptr<ControlAdapter>& dependent : dependents) {
        if (const std::shared_ptr<ControlAdapter> current = dependent.lock()) {
          if (current->active()) {
            current->refreshDependency();
            retained.push_back(current);
          }
        }
      }
      dependents.swap(retained);
    }
    return result;
  }

  void refreshDependency() override {
    if (!active() || is_disabled || evaluating) return;
    evaluate(binding.valueReference().get(),
             ValidationTrigger::explicitCheck);
  }

  bool checkValidity() override {
    if (is_disabled) return true;
    const T value = binding.valueReference().get();
    return evaluate(value, ValidationTrigger::explicitCheck).isValid;
  }

  bool reportValidity(bool focus) override {
    if (is_disabled) return true;
    const T value = binding.valueReference().get();
    const bool valid =
        evaluate(value, ValidationTrigger::explicitCheck, true).isValid;
    if (!valid && active()) {
      ui.emit(control, InputEvent(CBSS_EVENT_INVALID));
      if (focus) ui.setFocus(control, true);
    }
    return valid;
  }

  void close() noexcept {
    if (!attached) return;
    input.close();
    blur.close();
    attached = false;
  }

  UiHandle ui;
  Node control;
  std::vector<const void*> dependencies;
  ValidationBinding<T> binding;
  EventSubscription input;
  EventSubscription blur;
  std::vector<std::weak_ptr<ControlAdapter>> dependents;
  bool is_disabled = false;
  bool attached = true;
  bool evaluating = false;
};

}  // namespace validation_ui_detail

template <typename T>
class ValidationControl {
 public:
  ValidationControl() noexcept = default;

  bool active() const noexcept { return state_ && state_->active(); }
  Node node() const { return requireState().control; }

  ValidationResult input(T value) {
    return requireState().evaluate(std::move(value), ValidationTrigger::input,
                                   false, true);
  }

  ValidationResult change(T value) {
    return input(std::move(value));
  }

  ValidationResult blur() {
    validation_ui_detail::ControlState<T>& state = requireState();
    return state.evaluate(state.binding.valueReference().get(),
                          ValidationTrigger::blur);
  }

  bool checkValidity() { return requireState().checkValidity(); }
  bool reportValidity() { return requireState().reportValidity(true); }

  const ValidationResult& validationResult() const {
    return requireState().binding.current();
  }

  std::string validationMessage() const {
    const validation_ui_detail::ControlState<T>& state = requireState();
    return state.is_disabled ? std::string()
                             : state.binding.validationMessage();
  }

  ValidationValue<T> validationValue() const {
    return requireState().binding.valueReference();
  }

  void setDisabled(bool disabled) {
    validation_ui_detail::ControlState<T>& state = requireState();
    state.is_disabled = disabled;
    state.ui.setState(state.control, NodeState::disabled, disabled);
    state.sync();
  }

  bool disabled() const { return requireState().is_disabled; }

  void close() noexcept {
    if (state_) state_->close();
  }

 private:
  explicit ValidationControl(
      std::shared_ptr<validation_ui_detail::ControlState<T>> state)
      : state_(std::move(state)) {}

  validation_ui_detail::ControlState<T>& requireState() const {
    if (!active()) {
      throw Error(CBSS_INVALID_HANDLE,
                  "access Validation Control: attachment is not active");
    }
    return *state_;
  }

  std::shared_ptr<validation_ui_detail::ControlState<T>> state_;
  template <typename U, typename Extractor>
  friend ValidationControl<U> attachValidation(
      Ui&, Node, ValidationRules<U>, U, Extractor&&,
      ValidationReport, CbssEventKind);
  friend class ValidationForm;
};

template <typename T, typename Extractor>
ValidationControl<T> attachValidation(
    Ui& ui, Node node, ValidationRules<T> rules, T initial_value,
    Extractor&& extract_value,
    ValidationReport report_on = ValidationReport::onBlur,
    CbssEventKind value_event = CBSS_EVENT_INPUT) {
  std::function<T(const Event&)> extractor =
      std::forward<Extractor>(extract_value);
  if (!extractor) {
    throw std::invalid_argument(
        "Validation Control value extractor cannot be empty");
  }
  ui.setFocusable(node, true, 0);

  typedef validation_ui_detail::ControlState<T> State;
  const std::shared_ptr<State> state = std::make_shared<State>(
      ui.handle(), node, std::move(rules), std::move(initial_value), report_on);
  const std::weak_ptr<State> weak = state;
  state->input = ui.subscribe(
      node, value_event,
      [weak, extractor](const Event& event) mutable {
        if (const std::shared_ptr<State> current = weak.lock()) {
          if (current->active() && !current->is_disabled) {
            current->evaluate(extractor(event), ValidationTrigger::input,
                              false, true);
          }
        }
        return EventOutcome();
      });
  state->blur = ui.subscribe(
      node, CBSS_EVENT_BLUR,
      [weak](const Event&) {
        if (const std::shared_ptr<State> current = weak.lock()) {
          if (current->active() && !current->is_disabled) {
            current->evaluate(current->binding.valueReference().get(),
                              ValidationTrigger::blur);
          }
        }
        return EventOutcome();
      });
  state->sync();
  return ValidationControl<T>(state);
}

inline ValidationControl<std::string> attachTextValidation(
    Ui& ui, Node node, ValidationRules<std::string> rules,
    std::string initial_value = std::string(),
    ValidationReport report_on = ValidationReport::onBlur,
    CbssEventKind value_event = CBSS_EVENT_INPUT) {
  return attachValidation<std::string>(
      ui, node, std::move(rules), std::move(initial_value),
      [](const Event& event) { return event.text; }, report_on, value_event);
}

class ValidationForm {
 public:
  ValidationForm(Ui& ui, Node form_node)
      : ui_(ui.handle()), form_(form_node) {
    if (!form_.valid()) {
      throw Error(CBSS_INVALID_HANDLE,
                  "create Validation Form: form Node is not active");
    }
    (void)ui_.parent(form_);
  }

  template <typename T>
  void add(const ValidationControl<T>& control) {
    if (!control.active()) {
      throw Error(CBSS_INVALID_HANDLE,
                  "register Validation Control: attachment is not active");
    }
    Node current = control.node();
    bool descendant = false;
    while (current.valid()) {
      if (current == form_) {
        descendant = true;
        break;
      }
      current = ui_.parent(current);
    }
    if (!descendant) {
      throw Error(CBSS_INVALID_ARGUMENT,
                  "Validation Control must belong to the Validation Form");
    }
    for (const auto& existing : controls_) {
      if (existing && existing->node() == control.node()) {
        throw Error(CBSS_INVALID_ARGUMENT,
                    "Validation Control is already registered");
      }
    }
    const std::shared_ptr<validation_ui_detail::ControlAdapter> added =
        control.state_;
    const std::weak_ptr<validation_ui_detail::ControlAdapter> weak_added =
        added;
    for (const auto& existing : controls_) {
      if (!existing) continue;
      const auto& existing_dependencies = existing->dependencyIdentities();
      if (std::find(existing_dependencies.begin(), existing_dependencies.end(),
                    added->valueIdentity()) != existing_dependencies.end()) {
        added->addDependent(existing);
      }
      const auto& added_dependencies = added->dependencyIdentities();
      if (std::find(added_dependencies.begin(), added_dependencies.end(),
                    existing->valueIdentity()) != added_dependencies.end()) {
        existing->addDependent(weak_added);
      }
    }
    controls_.push_back(added);
  }

  bool remove(Node node) {
    for (auto position = controls_.begin(); position != controls_.end();
         ++position) {
      if (*position && (*position)->node() == node) {
        controls_.erase(position);
        return true;
      }
    }
    return false;
  }

  void setDisabled(bool disabled) {
    disabled_ = disabled;
    ui_.setState(form_, NodeState::disabled, disabled);
  }

  bool disabled() const noexcept { return disabled_; }

  bool checkValidity() {
    if (disabled_) return false;
    bool valid = true;
    for (const auto& control : controls_) {
      if (control && control->active() && !control->disabled() &&
          !control->checkValidity()) {
        valid = false;
      }
    }
    return valid;
  }

  bool reportValidity() {
    if (disabled_) return false;
    bool valid = true;
    bool focused = false;
    const auto controls = controls_;
    for (const auto& control : controls) {
      if (!control || !control->active() || control->disabled()) continue;
      if (!control->reportValidity(false)) {
        valid = false;
        if (!focused) {
          ui_.setFocus(control->node(), true);
          focused = true;
        }
      }
    }
    return valid;
  }

  void onSubmit(std::function<EventOutcome(const EventView&)> callback) {
    ui_.onView(form_, CBSS_EVENT_SUBMIT, std::move(callback));
  }

  bool submit(const FormData& data) {
    if (disabled_ || !reportValidity()) return false;
    ui_.emitSubmit(form_, data);
    return true;
  }

  std::size_t size() const noexcept { return controls_.size(); }

 private:
  UiHandle ui_;
  Node form_;
  std::vector<std::shared_ptr<validation_ui_detail::ControlAdapter>> controls_;
  bool disabled_ = false;
};

}  // namespace cbss

#endif
