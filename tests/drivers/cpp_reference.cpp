#include <cbss/craft.hpp>

#include <cassert>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <limits>
#include <memory>
#include <stdexcept>

namespace {

enum class StoreActionKind { increment, rename };

struct StoreAction {
  StoreAction(StoreActionKind action_kind, int action_amount,
              std::string action_name)
      : kind(action_kind),
        amount(action_amount),
        name(std::move(action_name)) {}

  StoreActionKind kind;
  int amount;
  std::string name;
};

struct StoreModel {
  int count = 0;
  std::string name = "ready";
};

struct CloneTrackedModel {
  explicit CloneTrackedModel(std::shared_ptr<int> clone_count)
      : clones(std::move(clone_count)) {}

  CloneTrackedModel(const CloneTrackedModel& other)
      : clones(other.clones), count(other.count) {
    ++*clones;
  }

  CloneTrackedModel(CloneTrackedModel&&) noexcept = default;
  CloneTrackedModel& operator=(const CloneTrackedModel&) = default;
  CloneTrackedModel& operator=(CloneTrackedModel&&) noexcept = default;

  std::shared_ptr<int> clones;
  int count = 0;
};

void reduceStore(StoreModel& state, const StoreAction& action) {
  if (action.kind == StoreActionKind::increment) {
    state.count += action.amount;
  } else {
    state.name = action.name;
  }
}

}  // namespace

int main() {
  cbss::Contract::requireAuthoring();
  assert(cbss::Contract::abiVersion() == CBSS_ABI_VERSION);
  assert(cbss::Contract::driverVersion() ==
         CBSS_DRIVER_CONTRACT_VERSION);

  bool rejected_missing_capability = false;
  try {
    cbss::Contract::require({{UINT32_MAX, 1u}});
  } catch (const cbss::ContractError&) {
    rejected_missing_capability = true;
  }
  assert(rejected_missing_capability);

  cbss::Style root_style;
  root_style.set("width", cbss::px(200.0f))
      .set("height", cbss::px(80.0f))
      .set("padding", cbss::px(10.0f))
      .set("flex-direction", cbss::keyword("row"))
      .set("background-color", cbss::rgb(0.1f, 0.2f, 0.3f));

  cbss::Style child_style;
  child_style.set("width", cbss::px(40.0f))
      .set("height", cbss::px(30.0f))
      .number("opacity", 0.75f);

  cbss::Ui ui;
  cbss::Node child;
  cbss::Node label;
  cbss::Node image;
  const cbss::Node root = ui.box("root", root_style, [&] {
    child = ui.box("child", child_style, [&] {
      label = ui.text("C++ Craft Driver", "label");
      image = ui.image("asset.png", 12.0f, 8.0f, "icon");
    });
    ui.box("sibling", child_style);
  });

  assert(ui.nodeCount() == 5u);
  assert(ui.childCount(root) == 2u);
  assert(ui.parent(child) == root);
  assert(ui.parent(label) == child);
  assert(ui.parent(image) == child);

  ui.compute(200.0f, 80.0f);
  const CbssRect root_rect = ui.rect(root);
  const CbssRect child_rect = ui.rect(child);
  assert(std::fabs(root_rect.w - 200.0f) < 0.001f);
  assert(std::fabs(root_rect.h - 80.0f) < 0.001f);
  assert(std::fabs(child_rect.w - 40.0f) < 0.001f);
  assert(std::fabs(child_rect.h - 30.0f) < 0.001f);

  int replaced_handler_calls = 0;
  int active_handler_calls = 0;
  int parent_observer_calls = 0;
  ui.on(child, CBSS_EVENT_CLICK, [&](const cbss::Event&) {
    ++replaced_handler_calls;
    return cbss::EventOutcome::handled();
  });
  ui.on(child, CBSS_EVENT_CLICK, [&](const cbss::Event& event) {
    ++active_handler_calls;
    assert(event.target == child.nativeId());
    assert(event.current_target == child.nativeId());
    assert((event.flags & CBSS_EVENT_HAS_POSITION) != 0u);
    assert(std::fabs(event.x - 18.0f) < 0.001f);
    return cbss::EventOutcome(true, false, true);
  });
  cbss::EventSubscription parent_observer = ui.subscribe(
      root, CBSS_EVENT_CLICK, [&](const cbss::Event& event) {
        ++parent_observer_calls;
        assert(event.target == child.nativeId());
        assert(event.current_target == root.nativeId());
        return cbss::EventOutcome::handled();
      });
  cbss::InputEvent click(CBSS_EVENT_CLICK);
  click.position(18.0f, 22.0f).mouseButton(1);
  const cbss::DispatchSummary first_click = ui.emit(child, click);
  assert(first_click.target == child.nativeId());
  assert(first_click.handled);
  assert(first_click.outcome.isHandled());
  assert(first_click.outcome.preventsDefault());
  assert(replaced_handler_calls == 0);
  assert(active_handler_calls == 1);
  assert(parent_observer_calls == 1);

  parent_observer.close();
  assert(!parent_observer.active());
  ui.emit(child, click);
  assert(active_handler_calls == 2);
  assert(parent_observer_calls == 1);

  std::string copied_key;
  ui.on(child, CBSS_EVENT_KEY_DOWN, [&](const cbss::Event& event) {
    copied_key = event.key;
    return cbss::EventOutcome::handled();
  });
  cbss::InputEvent key_down(CBSS_EVENT_KEY_DOWN);
  key_down.keyValue("+");
  ui.emit(child, key_down);
  assert(copied_key == "+");

  int scoped_observer_calls = 0;
  {
    cbss::EventSubscription scoped_observer = ui.subscribe(
        child, CBSS_EVENT_CHANGE, [&](const cbss::Event&) {
          ++scoped_observer_calls;
          return cbss::EventOutcome::handled();
        });
    ui.emit(child, cbss::InputEvent(CBSS_EVENT_CHANGE));
    assert(scoped_observer_calls == 1);
  }
  ui.emit(child, cbss::InputEvent(CBSS_EVENT_CHANGE));
  assert(scoped_observer_calls == 1);

  ui.on(child, CBSS_EVENT_INPUT, [](const cbss::Event&) -> cbss::EventOutcome {
    throw std::runtime_error("callback failure");
  });
  const cbss::DispatchSummary failed_callback =
      ui.emit(child, cbss::InputEvent(CBSS_EVENT_INPUT));
  assert(failed_callback.outcome.isHandled());
  assert(failed_callback.outcome.stopsPropagation());
  assert(failed_callback.outcome.preventsDefault());
  assert(ui.callbackFailed());
  bool callback_failure_rethrown = false;
  try {
    ui.rethrowCallbackFailure();
  } catch (const std::runtime_error&) {
    callback_failure_rethrown = true;
  }
  assert(callback_failure_rethrown);
  assert(!ui.callbackFailed());

  bool rejected_invalid_node = false;
  try {
    ui.rect(cbss::Node());
  } catch (const cbss::Error& error) {
    rejected_invalid_node = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(rejected_invalid_node);

  cbss::Ui other_ui;
  const cbss::Node other_root = other_ui.box("other-root");
  bool rejected_foreign_node = false;
  try {
    ui.rect(other_root);
  } catch (const cbss::Error& error) {
    rejected_foreign_node = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(rejected_foreign_node);

  cbss::Ui component_ui;
  cbss::Node component_label;
  cbss::Node component_image;
  int retained_component_events = 0;
  cbss::CraftComponent status_component = component_ui.component(
      "status-card", "status-card-instance",
      [&](cbss::ComponentScope& component) {
        component_label = component.text("Idle", "status-label");
        component_image =
            component.image("idle.png", 16.0f, 16.0f, "status-icon");
        component.publicStyleSlot("label", component_label);
        component.publicStyleSlot("icon", component_image);
        component.onRoot(CBSS_EVENT_CHANGE, [&](const cbss::Event&) {
          ++retained_component_events;
          return cbss::EventOutcome::handled();
        });
      });
  assert(status_component.active());
  assert(status_component.craftName() == "status-card");
  assert(component_ui.parent(component_label) == status_component.root());
  assert(component_ui.textValue(component_label) == "Idle");
  assert(component_ui.imageSource(component_image) == "idle.png");
  const std::string status_component_style = R"json({
    "format":"cbss-craft-style",
    "version":1,
    "name":"status-theme",
    "rules":[{
      "selector":{"component":"status-card","slot":"root"},
      "declarations":[{
        "property":"width",
        "value":{"type":"length","unit":"px","value":180}
      }]
    }]
  })json";
  component_ui.replaceCraftStyle(status_component_style);
  component_ui.compute(320.0f, 120.0f);
  assert(std::fabs(component_ui.rect(status_component.root()).w - 180.0f) <
         0.001f);
  component_ui.setText(component_label, "Idle");
  component_ui.setImage(component_image, "idle.png", 16.0f, 16.0f);
  component_ui.setState(status_component.root(), cbss::NodeState::checked,
                        false);
  (void)component_ui.rect(component_label);

  const std::uint32_t retained_root_id = status_component.root().nativeId();
  const std::uint32_t retained_label_id = component_label.nativeId();
  component_ui.setText(component_label, "Ready");
  component_ui.setImage(component_image, "ready.png", 20.0f, 12.0f);
  component_ui.addGroup(status_component.root(), "interactive");
  component_ui.setAttribute(status_component.root(), "data-status", "ready");
  component_ui.setState(status_component.root(), cbss::NodeState::checked,
                        true);
  assert(status_component.root().nativeId() == retained_root_id);
  assert(component_label.nativeId() == retained_label_id);
  assert(component_ui.textValue(component_label) == "Ready");
  assert(component_ui.imageSource(component_image) == "ready.png");
  component_ui.emit(status_component.root(),
                    cbss::InputEvent(CBSS_EVENT_CHANGE));
  assert(retained_component_events == 1);

  const std::uint32_t children_before_failed_component =
      component_ui.childCount(status_component.root());
  bool component_failure_rolled_back = false;
  try {
    component_ui.within(status_component.root(), [&] {
      component_ui.component(
          "failing-component", "failing-component-instance",
          [](cbss::ComponentScope& component) {
            component.text("temporary", "temporary-label");
            throw std::runtime_error("component construction failed");
          });
    });
  } catch (const std::runtime_error&) {
    component_failure_rolled_back = true;
  }
  assert(component_failure_rolled_back);
  assert(component_ui.childCount(status_component.root()) ==
         children_before_failed_component);

  bool empty_craft_name_rejected = false;
  try {
    component_ui.component("", "invalid-component",
                           [](cbss::ComponentScope&) {});
  } catch (const cbss::Error& error) {
    empty_craft_name_rejected = error.status() == CBSS_INVALID_ARGUMENT;
  }
  assert(empty_craft_name_rejected);
  assert(component_ui.unmount(status_component) == 3u);
  assert(!status_component.active());
  bool inactive_component_rejected = false;
  try {
    status_component.root();
  } catch (const cbss::Error& error) {
    inactive_component_rejected = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(inactive_component_rejected);

  cbss::Ui lifecycle_ui;
  cbss::Node removable;
  cbss::Node lifecycle_child;
  cbss::Node survivor;
  const cbss::Node lifecycle_root = lifecycle_ui.box("lifecycle-root", [&] {
    removable = lifecycle_ui.box("removable", [&] {
      lifecycle_child = lifecycle_ui.box("lifecycle-child");
    });
    survivor = lifecycle_ui.box("survivor");
  });

  std::weak_ptr<int> handler_resource;
  {
    const std::shared_ptr<int> resource = std::make_shared<int>(1);
    handler_resource = resource;
    lifecycle_ui.on(lifecycle_child, CBSS_EVENT_CLICK,
                    [resource](const cbss::Event&) {
                      assert(*resource == 1);
                      return cbss::EventOutcome::handled();
                    });
  }
  std::weak_ptr<int> subscription_resource;
  cbss::EventSubscription removed_subscription;
  {
    const std::shared_ptr<int> resource = std::make_shared<int>(2);
    subscription_resource = resource;
    removed_subscription = lifecycle_ui.subscribe(
        removable, CBSS_EVENT_CHANGE, [resource](const cbss::Event&) {
          assert(*resource == 2);
          return cbss::EventOutcome::handled();
        });
  }
  assert(!handler_resource.expired());
  assert(!subscription_resource.expired());
  assert(removed_subscription.active());
  int surviving_observer_calls = 0;
  cbss::EventSubscription surviving_subscription = lifecycle_ui.subscribe(
      lifecycle_root, CBSS_EVENT_CLICK, [&](const cbss::Event& event) {
        if (event.target == survivor.nativeId()) {
          ++surviving_observer_calls;
        }
        return cbss::EventOutcome::handled();
      });
  lifecycle_ui.emit(lifecycle_child,
                    cbss::InputEvent(CBSS_EVENT_CLICK));

  bool rejected_nested_removal = false;
  lifecycle_ui.within(lifecycle_root, [&] {
    try {
      lifecycle_ui.removeSubtree(removable);
    } catch (const cbss::Error& error) {
      rejected_nested_removal = error.status() == CBSS_INVALID_ARGUMENT;
    }
  });
  assert(rejected_nested_removal);

  assert(lifecycle_ui.removeSubtree(removable) == 2u);
  assert(lifecycle_ui.childCount(lifecycle_root) == 1u);
  assert(lifecycle_ui.parent(survivor) == lifecycle_root);
  assert(!removed_subscription.active());
  assert(surviving_subscription.active());
  assert(handler_resource.expired());
  assert(subscription_resource.expired());
  removed_subscription.close();
  lifecycle_ui.emit(survivor, cbss::InputEvent(CBSS_EVENT_CLICK));
  assert(surviving_observer_calls == 1);
  surviving_subscription.close();

  bool rejected_stale_node = false;
  try {
    lifecycle_ui.rect(lifecycle_child);
  } catch (const cbss::Error& error) {
    rejected_stale_node = error.status() == CBSS_INVALID_ARGUMENT;
  }
  assert(rejected_stale_node);
  bool rejected_stale_subtree = false;
  try {
    lifecycle_ui.removeSubtree(removable);
  } catch (const cbss::Error& error) {
    rejected_stale_subtree = error.status() == CBSS_INVALID_ARGUMENT;
  }
  assert(rejected_stale_subtree);
  cbss::Node replacement;
  lifecycle_ui.within(lifecycle_root, [&] {
    replacement = lifecycle_ui.box("replacement");
  });
  assert(replacement.nativeId() != lifecycle_child.nativeId());

  bool rejected_foreign_subtree = false;
  try {
    lifecycle_ui.removeSubtree(other_root);
  } catch (const cbss::Error& error) {
    rejected_foreign_subtree = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(rejected_foreign_subtree);

  cbss::EventSubscription reset_observer = ui.subscribe(
      child, CBSS_EVENT_CHANGE, [](const cbss::Event&) {
        return cbss::EventOutcome::handled();
      });
  ui.reset();
  reset_observer.close();
  assert(!reset_observer.active());
  assert(ui.nodeCount() == 0u);

  const cbss::Node exception_root = ui.box("exception-root");
  bool child_exception = false;
  bool rejected_nested_reset = false;
  try {
    ui.within(exception_root, [&] {
      ui.box("throwing-child", [&] {
        try {
          ui.reset();
        } catch (const cbss::Error& error) {
          rejected_nested_reset =
              error.status() == CBSS_INVALID_ARGUMENT;
        }
        throw std::runtime_error("stop construction");
      });
    });
  } catch (const std::runtime_error&) {
    child_exception = true;
  }
  assert(child_exception);
  assert(rejected_nested_reset);
  cbss::Node recovered_child;
  ui.within(exception_root, [&] {
    recovered_child = ui.box("recovered-child");
  });
  assert(ui.parent(recovered_child) == exception_root);

  cbss::Style invalid_style;
  invalid_style.set("definitely-not-a-property", cbss::px(1.0f));
  cbss::Ui invalid_ui;
  invalid_ui.box("invalid-root", invalid_style);
  bool rejected_invalid_style = false;
  try {
    invalid_ui.compute(100.0f, 100.0f);
  } catch (const cbss::Error& error) {
    rejected_invalid_style = error.status() == CBSS_STYLE_ERROR;
  }
  assert(rejected_invalid_style);

  const std::string craft_style = R"json({
    "format":"cbss-craft-style",
    "version":1,
    "name":"cpp-theme",
    "rules":[{
      "selector":{"component":"cpp-card","slot":"root"},
      "declarations":[{
        "property":"width",
        "value":{"type":"length","unit":"px","value":200}
      }]
    }]
  })json";
  const std::string missing_slot_style = R"json({
    "format":"cbss-craft-style",
    "version":1,
    "name":"cpp-theme",
    "rules":[{
      "selector":{"component":"cpp-card","slot":"missing"},
      "declarations":[{
        "property":"opacity",
        "value":{"type":"number","value":0.5}
      }]
    }]
  })json";
  const std::string craft_pack = R"json({
    "format":"cbss-craft-pack",
    "version":1,
    "id":"org.example.cpp-reference",
    "packVersion":"1.0.0",
    "compatibility":{
      "minimumAbi":65561,
      "minimumDriverContract":65536,
      "capabilities":[
        {"id":16,"minimumVersion":1},
        {"id":17,"minimumVersion":1}
      ]
    },
    "components":[{"name":"cpp-card","slots":["root"]}],
    "styles":[],
    "assets":[]
  })json";
  const std::string incompatible_craft_pack = R"json({
    "format":"cbss-craft-pack",
    "version":1,
    "id":"org.example.cpp-reference",
    "packVersion":"2.0.0",
    "compatibility":{
      "minimumAbi":4294967295,
      "minimumDriverContract":65536,
      "capabilities":[
        {"id":16,"minimumVersion":1},
        {"id":17,"minimumVersion":1}
      ]
    },
    "components":[{"name":"cpp-card","slots":["root"]}],
    "styles":[],
    "assets":[]
  })json";

  cbss::Style craft_container_style;
  craft_container_style.set("width", cbss::px(500.0f))
      .set("height", cbss::px(300.0f));
  cbss::Style component_owned_style;
  component_owned_style.set("width", cbss::px(90.0f))
      .set("height", cbss::px(30.0f));
  cbss::Ui craft_ui;
  cbss::Node owned_component;
  cbss::Node replaceable_component;
  craft_ui.box("craft-root", craft_container_style, [&] {
    owned_component = craft_ui.box("owned-card", component_owned_style);
    replaceable_component = craft_ui.box("replaceable-card");
  });
  craft_ui.exposeStyleSlot(owned_component, owned_component, "cpp-card",
                           "root");
  craft_ui.exposeStyleSlot(replaceable_component, replaceable_component,
                           "cpp-card", "root");
  craft_ui.replaceCraftStyle(craft_style);
  assert(craft_ui.activeCraftStyles() ==
         std::vector<std::string>{"cpp-theme"});
  craft_ui.compute(500.0f, 300.0f);
  assert(std::fabs(craft_ui.rect(owned_component).w - 90.0f) < 0.001f);
  assert(std::fabs(craft_ui.rect(replaceable_component).w - 200.0f) <
         0.001f);

  bool rejected_missing_slot = false;
  try {
    craft_ui.replaceCraftStyle(missing_slot_style);
  } catch (const cbss::Error& error) {
    rejected_missing_slot = error.status() == CBSS_STYLE_ERROR;
  }
  assert(rejected_missing_slot);
  assert(craft_ui.activeCraftStyles() ==
         std::vector<std::string>{"cpp-theme"});
  const std::vector<cbss::CraftDiagnostic> craft_diagnostics =
      craft_ui.craftDiagnostics();
  assert(craft_diagnostics.size() == 1u);
  assert(craft_diagnostics[0].domain ==
         CBSS_CRAFT_DIAGNOSTIC_STYLE_REPLACEMENT);
  assert(!craft_diagnostics[0].path.empty());
  assert(!craft_diagnostics[0].message.empty());

  craft_ui.replaceCraftPack(craft_pack);
  const std::vector<cbss::CraftPackInfo> craft_packs =
      craft_ui.activeCraftPacks();
  assert(craft_packs.size() == 1u);
  assert(craft_packs[0].id == "org.example.cpp-reference");
  assert(craft_packs[0].version == "1.0.0");
  bool rejected_incompatible_pack = false;
  try {
    craft_ui.replaceCraftPack(incompatible_craft_pack);
  } catch (const cbss::Error& error) {
    rejected_incompatible_pack = error.status() == CBSS_STYLE_ERROR;
  }
  assert(rejected_incompatible_pack);
  assert(craft_ui.activeCraftPacks()[0].version == "1.0.0");
  const std::vector<cbss::CraftDiagnostic> pack_diagnostics =
      craft_ui.craftDiagnostics();
  assert(pack_diagnostics.size() == 1u);
  assert(pack_diagnostics[0].domain == CBSS_CRAFT_DIAGNOSTIC_PACK);
  assert(craft_ui.removeCraftPack("org.example.cpp-reference"));
  assert(craft_ui.activeCraftPacks().empty());
  assert(craft_ui.removeCraftStyle("cpp-theme"));
  assert(craft_ui.activeCraftStyles().empty());

  cbss::EventSubscription detached_observer;
  {
    cbss::Ui temporary_ui;
    const cbss::Node temporary_node = temporary_ui.box("temporary");
    detached_observer = temporary_ui.subscribe(
        temporary_node, CBSS_EVENT_CLICK, [](const cbss::Event&) {
          return cbss::EventOutcome::handled();
        });
  }
  detached_observer.close();
  assert(!detached_observer.active());

  auto store = cbss::createStore<StoreModel, StoreAction>(
      StoreModel(), reduceStore);
  int selector_evaluations = 0;
  auto count = store.select<int>([&](const StoreModel& state) {
    ++selector_evaluations;
    return state.count;
  });
  std::vector<int> selected_counts;
  cbss::StoreSubscription count_watch = count.subscribe(
      [&](const int& value) { selected_counts.push_back(value); });

  store.dispatch({StoreActionKind::increment, 1, ""});
  store.dispatch({StoreActionKind::rename, 0, "done"});
  assert(store.state().count == 1);
  assert(store.state().name == "done");
  assert(store.revision() == 2u);
  assert(selector_evaluations == 3);
  assert(selected_counts == std::vector<int>{1});

  store.transaction([&] {
    store.dispatch({StoreActionKind::increment, 2, ""});
    store.transaction([&] {
      store.dispatch({StoreActionKind::increment, 3, ""});
    });
  });
  assert(store.state().count == 6);
  assert(store.revision() == 3u);
  assert(selector_evaluations == 4);
  assert(selected_counts == (std::vector<int>{1, 6}));

  auto component_store = cbss::createStore<StoreModel, StoreAction>(
      StoreModel(), reduceStore);
  auto component_count = component_store.select<int>(
      [](const StoreModel& state) { return state.count; });
  cbss::Ui component_watch_ui;
  cbss::Node watched_label;
  cbss::Node component_marker;
  cbss::CraftComponent watched_component = component_watch_ui.component(
      "watched-counter", "watched-counter-instance",
      [&](cbss::ComponentScope& component) {
        watched_label = component.text("pending", "count-label");
        component_marker = component.box("count-marker");
      });
  const cbss::UiHandle retained_ui = component_watch_ui.handle();
  cbss::ComponentWatch component_watch = watched_component.watch(
      component_count, [retained_ui, watched_label, component_marker](
                           const int& value) {
        retained_ui.setText(watched_label, std::to_string(value));
        retained_ui.setState(component_marker, cbss::NodeState::checked,
                            value % 2 != 0);
      });
  assert(component_watch.active());
  assert(watched_component.watchCount() == 1u);
  assert(component_count.subscriberCount() == 1u);
  assert(component_watch_ui.textValue(watched_label) == "0");

  component_store.dispatch({StoreActionKind::rename, 0, "unchanged"});
  assert(component_watch_ui.textValue(watched_label) == "0");
  component_store.dispatch({StoreActionKind::increment, 3, ""});
  assert(component_watch_ui.textValue(watched_label) == "3");
  assert(component_watch.close());
  assert(!component_watch.close());
  assert(!component_watch.active());
  assert(watched_component.watchCount() == 0u);
  assert(component_count.subscriberCount() == 0u);

  bool initial_watch_failure_seen = false;
  try {
    watched_component.watch(component_count, [](const int&) {
      throw std::runtime_error("initial watch failed");
    });
  } catch (const std::runtime_error&) {
    initial_watch_failure_seen = true;
  }
  assert(initial_watch_failure_seen);
  assert(watched_component.watchCount() == 0u);
  assert(component_count.subscriberCount() == 0u);

  bool rejected_foreign_retained_node = false;
  try {
    retained_ui.setText(other_root, "foreign");
  } catch (const cbss::Error& error) {
    rejected_foreign_retained_node = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(rejected_foreign_retained_node);

  cbss::ComponentWatch unmount_watch = watched_component.watch(
      component_count,
      [retained_ui, watched_label](const int& value) {
        retained_ui.setText(watched_label, std::to_string(value));
      },
      false);
  assert(unmount_watch.active());
  assert(component_watch_ui.unmount(watched_component) == 3u);
  assert(!unmount_watch.active());
  assert(component_count.subscriberCount() == 0u);
  bool rejected_inactive_watch = false;
  try {
    watched_component.watch(component_count, [](const int&) {});
  } catch (const cbss::Error& error) {
    rejected_inactive_watch = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(rejected_inactive_watch);

  cbss::UiHandle expired_ui;
  cbss::Node expired_node;
  {
    cbss::Ui temporary_watch_ui;
    expired_ui = temporary_watch_ui.handle();
    temporary_watch_ui.box("temporary-root", [&] {
      expired_node = temporary_watch_ui.text("active", "temporary-label");
    });
    expired_ui.setText(expired_node, "updated");
    assert(expired_ui.active());
  }
  assert(!expired_ui.active());
  bool rejected_expired_ui = false;
  try {
    expired_ui.setText(expired_node, "late");
  } catch (const cbss::Error& error) {
    rejected_expired_ui = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(rejected_expired_ui);

  {
    auto dropped_component_store = cbss::createStore<StoreModel, StoreAction>(
        StoreModel(), reduceStore);
    auto dropped_component_count = dropped_component_store.select<int>(
        [](const StoreModel& state) { return state.count; });
    cbss::Ui dropped_component_ui;
    {
      cbss::CraftComponent dropped_component = dropped_component_ui.component(
          "dropped-counter", "dropped-counter-instance",
          [](cbss::ComponentScope& component) {
            component.text("ready", "dropped-label");
          });
      cbss::ComponentWatch dropped_watch = dropped_component.watch(
          dropped_component_count, [](const int&) {}, false);
      assert(dropped_watch.active());
      assert(dropped_component_count.subscriberCount() == 1u);
    }
    assert(dropped_component_count.subscriberCount() == 0u);
  }

  bool queued_reentrant_action = false;
  std::vector<std::uint64_t> revisions;
  cbss::StoreSubscription commit_watch = store.subscribe(
      [&](std::uint64_t revision) {
        revisions.push_back(revision);
        if (!queued_reentrant_action) {
          queued_reentrant_action = true;
          store.dispatch({StoreActionKind::increment, 4, ""});
        }
      });
  store.dispatch({StoreActionKind::increment, 1, ""});
  assert(store.state().count == 11);
  assert(revisions == (std::vector<std::uint64_t>{4u, 5u}));

  int later_listener_calls = 0;
  cbss::StoreSubscription failing_watch = store.subscribe(
      [](std::uint64_t) {
        throw std::runtime_error("listener failed");
      });
  cbss::StoreSubscription later_watch = store.subscribe(
      [&](std::uint64_t) { ++later_listener_calls; });
  bool listener_failure_seen = false;
  try {
    store.dispatch({StoreActionKind::rename, 0, "failure-observed"});
  } catch (const std::runtime_error&) {
    listener_failure_seen = true;
  }
  assert(listener_failure_seen);
  assert(later_listener_calls == 1);
  failing_watch.close();
  store.dispatch({StoreActionKind::rename, 0, "recovered"});
  assert(store.state().name == "recovered");
  assert(later_listener_calls == 2);

  store.dispatchSilent({StoreActionKind::increment, 10, ""});
  assert(count.value() == 11);
  count.refresh();
  assert(count.value() == 21);
  assert(selected_counts.back() == 21);
  assert(count_watch.active());
  assert(count_watch.close());
  assert(!count_watch.active());
  const std::size_t subscribers_before_selector_dispose =
      store.subscriberCount();
  assert(count.dispose());
  assert(!count.dispose());
  assert(store.subscriberCount() + 1u ==
         subscribers_before_selector_dispose);
  bool rejected_disposed_selector = false;
  try {
    count.refresh();
  } catch (const std::logic_error&) {
    rejected_disposed_selector = true;
  }
  assert(rejected_disposed_selector);

  bool transaction_failure_seen = false;
  try {
    store.transaction([&] {
      store.dispatch({StoreActionKind::increment, 1, ""});
      throw std::runtime_error("transaction body failed");
    });
  } catch (const std::runtime_error&) {
    transaction_failure_seen = true;
  }
  assert(transaction_failure_seen);
  assert(store.state().count == 22);

  auto case_insensitive_name = store.select<std::string>(
      [](const StoreModel& state) { return state.name; },
      [](const std::string& left, const std::string& right) {
        std::string folded_left = left;
        std::string folded_right = right;
        for (char& value : folded_left) {
          value = static_cast<char>(std::tolower(static_cast<unsigned char>(value)));
        }
        for (char& value : folded_right) {
          value = static_cast<char>(std::tolower(static_cast<unsigned char>(value)));
        }
        return folded_left == folded_right;
      });
  std::vector<std::string> selected_names;
  cbss::StoreSubscription name_watch = case_insensitive_name.subscribe(
      [&](const std::string& value) { selected_names.push_back(value); });
  store.dispatch({StoreActionKind::rename, 0, "RECOVERED"});
  store.dispatch({StoreActionKind::rename, 0, "final"});
  assert(selected_names == std::vector<std::string>{"final"});

  auto subscription_store = cbss::createStore<StoreModel, StoreAction>(
      StoreModel(), reduceStore);
  int removed_listener_calls = 0;
  int late_listener_calls = 0;
  cbss::StoreSubscription removed_listener;
  cbss::StoreSubscription late_listener;
  cbss::StoreSubscription mutating_listener = subscription_store.subscribe(
      [&](std::uint64_t) {
        removed_listener.close();
        if (!late_listener.active()) {
          late_listener = subscription_store.subscribe(
              [&](std::uint64_t) { ++late_listener_calls; });
        }
      });
  removed_listener = subscription_store.subscribe(
      [&](std::uint64_t) { ++removed_listener_calls; });
  subscription_store.dispatch({StoreActionKind::increment, 1, ""});
  assert(removed_listener_calls == 0);
  assert(late_listener_calls == 0);
  subscription_store.dispatch({StoreActionKind::increment, 1, ""});
  assert(late_listener_calls == 1);

  auto fallible_store = cbss::createStore<StoreModel, StoreAction>(
      StoreModel(), [](StoreModel& state, const StoreAction& action) {
        if (action.kind == StoreActionKind::increment && action.amount < 0) {
          throw std::invalid_argument("negative increment");
        }
        reduceStore(state, action);
      });
  bool reducer_failure_seen = false;
  try {
    fallible_store.dispatch({StoreActionKind::increment, -1, ""});
  } catch (const std::invalid_argument&) {
    reducer_failure_seen = true;
  }
  assert(reducer_failure_seen);
  fallible_store.dispatch({StoreActionKind::increment, 3, ""});
  assert(fallible_store.state().count == 3);
  assert(fallible_store.revision() == 1u);

  const std::shared_ptr<int> store_clone_count = std::make_shared<int>(0);
  auto clone_tracked_store = cbss::createStore<CloneTrackedModel, int>(
      CloneTrackedModel(store_clone_count),
      [](CloneTrackedModel& state, const int& amount) {
        state.count += amount;
      });
  auto tracked_count = clone_tracked_store.select<int>(
      [](const CloneTrackedModel& state) { return state.count; });
  clone_tracked_store.dispatch(1);
  clone_tracked_store.transaction([&] {
    clone_tracked_store.dispatch(2);
    clone_tracked_store.dispatch(3);
  });
  assert(tracked_count.value() == 6);
  assert(*store_clone_count == 0);
  assert(clone_tracked_store.read(
             [](const CloneTrackedModel& state) { return state.count; }) == 6);
  assert(*store_clone_count == 0);
  const CloneTrackedModel copied_state = clone_tracked_store.state();
  assert(copied_state.count == 6);
  assert(*store_clone_count == 1);

  auto navigator = cbss::createStackNavigator<std::string>("home");
  assert(navigator.currentDestination().value() == "home");
  assert(!navigator.canGoBack());
  assert(!navigator.canGoForward());
  assert(!navigator.back());
  assert(navigator.snapshot().revision == 0u);

  std::vector<cbss::NavigationChangeKind> navigation_kinds;
  std::vector<std::string> navigation_destinations;
  cbss::NavigationSubscription navigation_watch = navigator.subscribe(
      [&](const cbss::NavigationChange<std::string>& change) {
        navigation_kinds.push_back(change.kind);
        navigation_destinations.push_back(change.current.value().destination);
        assert(change.dirtyDomains == cbss::navigationScreenDirtyDomains);
      });
  assert(navigation_watch.active());
  assert(navigator.listenerCount() == 1u);

  assert(navigator.push("projects"));
  const auto projects_entry = navigator.currentEntry().value();
  assert(projects_entry.id == 2u);
  assert(navigator.push("settings"));
  assert(navigator.back());
  assert(navigator.currentDestination().value() == "projects");
  assert(navigator.canGoForward());
  assert(navigator.replace("project-detail"));
  const auto replaced_entry = navigator.currentEntry().value();
  assert(replaced_entry.id == 4u);
  assert(replaced_entry.id != projects_entry.id);
  assert(navigator.forward());
  assert(navigator.currentDestination().value() == "settings");
  assert(!navigator.forward());
  assert(navigator.back());
  assert(navigator.push("activity"));
  assert(!navigator.canGoForward());
  assert(!navigator.forward());
  const auto branched_snapshot = navigator.snapshot();
  assert(branched_snapshot.entries.size() == 3u);
  assert(branched_snapshot.entries[0].destination == "home");
  assert(branched_snapshot.entries[1].destination == "project-detail");
  assert(branched_snapshot.entries[2].destination == "activity");
  assert(branched_snapshot.revision == 7u);
  assert(navigation_kinds.size() == 7u);
  assert(navigation_destinations.back() == "activity");

  auto isolated_snapshot = navigator.snapshot();
  isolated_snapshot.entries[0].destination = "mutated-copy";
  isolated_snapshot.entries.clear();
  assert(navigator.snapshot().entries[0].destination == "home");

  auto mutation_navigator = cbss::createStackNavigator<int>(0);
  int removed_navigation_calls = 0;
  int late_navigation_calls = 0;
  cbss::NavigationSubscription removed_navigation;
  cbss::NavigationSubscription late_navigation;
  cbss::NavigationSubscription mutating_navigation =
      mutation_navigator.subscribe([&](const cbss::NavigationChange<int>&) {
        removed_navigation.close();
        if (!late_navigation.active()) {
          late_navigation = mutation_navigator.subscribe(
              [&](const cbss::NavigationChange<int>&) {
                ++late_navigation_calls;
              });
        }
      });
  removed_navigation = mutation_navigator.subscribe(
      [&](const cbss::NavigationChange<int>&) {
        ++removed_navigation_calls;
      });
  mutation_navigator.push(1);
  assert(removed_navigation_calls == 1);
  assert(late_navigation_calls == 0);
  mutation_navigator.push(2);
  assert(removed_navigation_calls == 1);
  assert(late_navigation_calls == 1);

  int later_navigation_calls = 0;
  cbss::NavigationSubscription failing_navigation =
      mutation_navigator.subscribe([](const cbss::NavigationChange<int>&) {
        throw std::runtime_error("navigation listener failed");
      });
  cbss::NavigationSubscription later_navigation =
      mutation_navigator.subscribe([&](const cbss::NavigationChange<int>&) {
        ++later_navigation_calls;
      });
  bool navigation_failure_seen = false;
  try {
    mutation_navigator.push(3);
  } catch (const std::runtime_error&) {
    navigation_failure_seen = true;
  }
  assert(navigation_failure_seen);
  assert(later_navigation_calls == 1);
  assert(mutation_navigator.currentDestination().value() == 3);
  failing_navigation.close();
  mutation_navigator.push(4);
  assert(later_navigation_calls == 2);

  const auto custom_state = std::make_shared<cbss::NavigationSnapshot<int>>();
  custom_state->entries.push_back({41u, 10});
  custom_state->currentIndex = 0;
  cbss::NavigationDriver<int> custom_driver;
  custom_driver.snapshot = [custom_state]() { return *custom_state; };
  custom_driver.push = [custom_state](const int& destination) {
    const auto previous = custom_state->currentEntry();
    custom_state->entries.push_back({42u, destination});
    custom_state->currentIndex = 1;
    ++custom_state->revision;
    const auto snapshot = *custom_state;
    return cbss::NavigationOptional<cbss::NavigationChange<int>>(
        {cbss::NavigationChangeKind::push, previous,
         snapshot.currentEntry(), snapshot,
         cbss::navigationScreenDirtyDomains});
  };
  custom_driver.replace = [](const int&) {
    return cbss::NavigationOptional<cbss::NavigationChange<int>>();
  };
  custom_driver.back = [] {
    return cbss::NavigationOptional<cbss::NavigationChange<int>>();
  };
  custom_driver.forward = [] {
    return cbss::NavigationOptional<cbss::NavigationChange<int>>();
  };
  cbss::Navigator<int> custom_navigator(custom_driver);
  assert(custom_navigator.push(20));
  assert(custom_navigator.currentDestination().value() == 20);
  assert(!custom_navigator.replace(30));

  bool invalid_driver_rejected = false;
  try {
    cbss::Navigator<int> invalid_navigator{cbss::NavigationDriver<int>()};
  } catch (const std::invalid_argument&) {
    invalid_driver_rejected = true;
  }
  assert(invalid_driver_rejected);

  cbss::NavigationSubscription expired_navigation;
  {
    auto temporary_navigator = cbss::createStackNavigator<int>(0);
    expired_navigation = temporary_navigator.subscribe(
        [](const cbss::NavigationChange<int>&) {});
    assert(expired_navigation.active());
  }
  assert(!expired_navigation.active());
  assert(!expired_navigation.close());

  cbss::Ui navigation_ui;
  const cbss::Node navigation_app = navigation_ui.box("navigation-app");
  cbss::Node home_root;
  cbss::Node home_last;
  navigation_ui.within(navigation_app, [&] {
    home_root = navigation_ui.box("home-screen", [&] {
      const cbss::Node home_first = navigation_ui.box("home-first");
      home_last = navigation_ui.box("home-last");
      navigation_ui.setFocusable(home_first);
      navigation_ui.setFocusable(home_last);
    });
  });
  cbss::Node settings_root;
  cbss::Node settings_first;
  cbss::Node settings_last;
  navigation_ui.within(navigation_app, [&] {
    settings_root = navigation_ui.box("settings-screen", [&] {
      settings_first = navigation_ui.box("settings-first");
      settings_last = navigation_ui.box("settings-last");
      navigation_ui.setFocusable(settings_first);
      navigation_ui.setFocusable(settings_last);
    });
  });
  int inactive_clicks = 0;
  navigation_ui.on(settings_last, CBSS_EVENT_CLICK,
                   [&](const cbss::Event&) {
                     ++inactive_clicks;
                     return cbss::EventOutcome::handled();
                   });

  auto screen_navigator =
      cbss::createStackNavigator<std::string>("home");
  cbss::NavigationScreenHost<std::string> screen_host(
      navigation_ui, screen_navigator);
  screen_host.registerScreen("home", home_root);
  screen_host.registerScreen("settings", settings_root, settings_first);
  bool duplicate_screen_rejected = false;
  try {
    screen_host.registerScreen("home", settings_root);
  } catch (const std::invalid_argument&) {
    duplicate_screen_rejected = true;
  }
  assert(duplicate_screen_rejected);
  assert(screen_host.sync());
  assert(screen_host.activeScreen().value().destination == "home");
  assert(!navigation_ui.inert(home_root));
  assert(navigation_ui.inert(settings_root));
  assert(!navigation_ui.emit(
                           settings_last,
                           cbss::InputEvent(CBSS_EVENT_CLICK))
               .handled);
  assert(inactive_clicks == 0);

  navigation_ui.setFocus(home_last, true);
  assert(screen_navigator.push("settings"));
  assert(screen_host.sync());
  assert(navigation_ui.focusedNode() == settings_first);
  navigation_ui.setFocus(settings_last, true);
  assert(screen_navigator.back());
  assert(screen_host.sync());
  assert(navigation_ui.focusedNode() == home_last);
  assert(screen_navigator.forward());
  assert(screen_host.sync());
  assert(navigation_ui.focusedNode() == settings_last);
  assert(screen_navigator.back());
  assert(screen_host.sync());

  cbss::Link<std::string> settings_link;
  navigation_ui.within(navigation_app, [&] {
    settings_link = cbss::Link<std::string>::mount(
        navigation_ui, screen_navigator, "settings", "Settings");
  });
  int link_clicks = 0;
  int link_bubbles = 0;
  navigation_ui.on(navigation_app, CBSS_EVENT_CLICK,
                   [&](const cbss::Event&) {
                     ++link_bubbles;
                     return cbss::EventOutcome::handled();
                   });
  std::string destination_seen_by_link;
  settings_link.onClick([&](const cbss::Event&) {
    ++link_clicks;
    destination_seen_by_link =
        screen_navigator.currentDestination().value();
    return cbss::EventOutcome::handled();
  });
  const cbss::DispatchSummary link_click = navigation_ui.emit(
      settings_link.container(), cbss::InputEvent(CBSS_EVENT_CLICK));
  assert(link_click.handled);
  assert(link_clicks == 1);
  assert(link_bubbles == 1);
  assert(destination_seen_by_link == "home");
  assert(screen_navigator.currentDestination().value() == "settings");
  assert(screen_host.sync());

  assert(screen_navigator.back());
  assert(screen_host.sync());
  const cbss::DispatchSummary link_enter = navigation_ui.emit(
      settings_link.container(),
      cbss::InputEvent(CBSS_EVENT_KEY_DOWN).keyValue("Enter"));
  assert(link_enter.handled);
  assert(link_clicks == 2);
  assert(link_bubbles == 2);
  assert(screen_navigator.currentDestination().value() == "settings");
  assert(screen_host.sync());
  settings_link.setLabel("Project settings");
  assert(settings_link.label() == "Project settings");
  assert(navigation_ui.textValue(settings_link.labelNode()) ==
         "Project settings");
  settings_link.setDisabled(true);
  assert(!settings_link.activate());
  assert(!navigation_ui.emit(
                           settings_link.container(),
                           cbss::InputEvent(CBSS_EVENT_CLICK))
               .handled);
  assert(link_clicks == 2);
  assert(link_bubbles == 2);

  cbss::Link<std::string> prevented_link;
  navigation_ui.within(navigation_app, [&] {
    prevented_link = cbss::Link<std::string>::mount(
        navigation_ui, screen_navigator, "blocked", "Blocked");
  });
  prevented_link.onClick([](const cbss::Event&) {
    return cbss::EventOutcome(true, false, true);
  });
  const std::string before_prevented =
      screen_navigator.currentDestination().value();
  assert(navigation_ui.emit(
                          prevented_link.container(),
                          cbss::InputEvent(CBSS_EVENT_CLICK))
             .outcome.preventsDefault());
  assert(screen_navigator.currentDestination().value() == before_prevented);
  assert(link_bubbles == 3);
  assert(!navigation_ui.emit(
                            prevented_link.container(),
                            cbss::InputEvent(CBSS_EVENT_KEY_DOWN)
                                .keyValue(" "))
              .handled);
  assert(screen_navigator.currentDestination().value() == before_prevented);

  assert(screen_host.connected());
  assert(screen_host.disconnect());
  assert(!screen_host.connected());
  assert(screen_navigator.back());
  assert(!screen_host.sync());
  screen_host.queueCurrent();
  assert(screen_host.sync());
  assert(screen_host.activeScreen().value().destination == "home");

  bool invalid_transition_rejected = false;
  try {
    cbss::navigationTransition<std::string>(
        0.0, [](const cbss::NavigationTransitionContext<std::string>&) {});
  } catch (const std::invalid_argument&) {
    invalid_transition_rejected = true;
  }
  assert(invalid_transition_rejected);
  invalid_transition_rejected = false;
  try {
    cbss::navigationTransition<std::string>(
        0.2, {}, cbss::defaultNavigationTransitionFrameInterval);
  } catch (const std::invalid_argument&) {
    invalid_transition_rejected = true;
  }
  assert(invalid_transition_rejected);

  cbss::Ui transition_ui;
  const cbss::Node transition_app = transition_ui.box("transition-app");
  cbss::Node transition_home;
  cbss::Node transition_settings;
  cbss::Node transition_details;
  transition_ui.within(transition_app, [&] {
    transition_home = transition_ui.box("transition-home");
    transition_settings = transition_ui.box("transition-settings");
    transition_details = transition_ui.box("transition-details");
  });
  std::vector<cbss::NavigationTransitionContext<std::string>>
      transition_contexts;
  auto transition_navigator =
      cbss::createStackNavigator<std::string>("home");
  cbss::NavigationScreenHost<std::string> transition_host(
      transition_ui, transition_navigator,
      cbss::navigationTransition<std::string>(
          0.2,
          [&](const cbss::NavigationTransitionContext<std::string>& context) {
            transition_contexts.push_back(context);
          },
          0.05));
  transition_host.registerScreen("home", transition_home);
  transition_host.registerScreen("settings", transition_settings);
  transition_host.registerScreen("details", transition_details);
  assert(transition_host.sync(1.0));
  assert(!transition_host.transitionActive());
  assert(transition_contexts.empty());

  assert(transition_navigator.push("settings"));
  assert(transition_host.sync(2.0));
  assert(transition_host.transitionActive());
  assert(transition_contexts.size() == 1u);
  assert(transition_contexts.back().phase ==
         cbss::NavigationTransitionPhase::started);
  assert(transition_contexts.back().kind ==
         cbss::NavigationChangeKind::push);
  assert(transition_contexts.back().previous.destination == "home");
  assert(transition_contexts.back().current.destination == "settings");
  assert(transition_contexts.back().outgoingRoot == transition_home);
  assert(transition_contexts.back().incomingRoot == transition_settings);
  assert(transition_contexts.back().progress == 0.0f);
  assert(transition_ui.inert(transition_home));
  assert(!transition_ui.inert(transition_settings));
  assert(transition_host.nextTransitionDeadline());
  assert(std::abs(transition_host.nextTransitionDeadline().value() - 2.05) <
         0.000001);

  assert(transition_host.advanceTransition(2.1));
  assert(transition_host.transitionActive());
  assert(transition_contexts.back().phase ==
         cbss::NavigationTransitionPhase::advanced);
  assert(std::abs(transition_contexts.back().progress - 0.5f) < 0.0001f);
  assert(transition_host.advanceTransition(2.2));
  assert(!transition_host.transitionActive());
  assert(!transition_host.nextTransitionDeadline());
  assert(transition_contexts.back().phase ==
         cbss::NavigationTransitionPhase::completed);
  assert(transition_contexts.back().progress == 1.0f);

  const std::size_t contexts_before_immediate_sync =
      transition_contexts.size();
  assert(transition_navigator.back());
  assert(transition_host.sync());
  assert(!transition_host.transitionActive());
  assert(transition_contexts.size() == contexts_before_immediate_sync);
  assert(transition_navigator.forward());
  assert(transition_host.sync());
  assert(transition_contexts.size() == contexts_before_immediate_sync);

  assert(transition_navigator.push("details"));
  assert(transition_host.sync(3.0));
  assert(transition_host.transitionActive());
  assert(transition_navigator.back());
  assert(transition_host.sync(3.05));
  assert(transition_contexts[transition_contexts.size() - 2u].phase ==
         cbss::NavigationTransitionPhase::cancelled);
  assert(transition_contexts.back().phase ==
         cbss::NavigationTransitionPhase::started);
  bool active_transition_replacement_rejected = false;
  try {
    transition_host.setTransition(
        cbss::NavigationOptional<
            cbss::NavigationTransitionSpec<std::string>>());
  } catch (const std::logic_error&) {
    active_transition_replacement_rejected = true;
  }
  assert(active_transition_replacement_rejected);
  assert(transition_host.cancelTransition());
  assert(!transition_host.cancelTransition());
  transition_host.setTransition(
      cbss::NavigationOptional<
          cbss::NavigationTransitionSpec<std::string>>());
  assert(transition_navigator.forward());
  assert(transition_host.sync(4.0));
  assert(!transition_host.transitionActive());

  std::vector<cbss::NavigationTransitionPhase> disposal_phases;
  transition_host.setTransition(
      cbss::navigationTransition<std::string>(
          0.5,
          [&](const cbss::NavigationTransitionContext<std::string>& context) {
            disposal_phases.push_back(context.phase);
            static_cast<void>(transition_ui.inert(context.outgoingRoot));
            static_cast<void>(transition_ui.inert(context.incomingRoot));
          }));
  assert(transition_navigator.back());
  assert(transition_host.sync(5.0));
  assert(transition_host.transitionActive());
  assert(transition_host.unregisterScreen("details", transition_ui));
  assert(!transition_host.transitionActive());
  assert(disposal_phases.size() == 2u);
  assert(disposal_phases[0] == cbss::NavigationTransitionPhase::started);
  assert(disposal_phases[1] == cbss::NavigationTransitionPhase::cancelled);

  bool invalid_time_rejected = false;
  try {
    transition_host.sync(NAN);
  } catch (const std::invalid_argument&) {
    invalid_time_rejected = true;
  }
  assert(invalid_time_rejected);

  cbss::Contract::require({{CBSS_CAPABILITY_VALIDATION_PATTERN, 1u}});
  const cbss::ValidationPattern identifier_pattern("^[A-Za-z0-9_]+$");
  assert(identifier_pattern.test("account_42"));
  assert(!identifier_pattern.test("account-42"));
  bool malformed_pattern_rejected = false;
  try {
    const cbss::ValidationPattern malformed("[");
  } catch (const std::invalid_argument&) {
    malformed_pattern_rejected = true;
  }
  assert(malformed_pattern_rejected);

  const auto account_rules = cbss::ValidationRules<std::string>()
      .required("required")
      .minLength(3, "minLength")
      .maxLength(12, "maxLength")
      .notBlank("notBlank")
      .matches(identifier_pattern, "matches")
      .contains("_", "contains")
      .startsWith("ab", "startsWith")
      .endsWith("cd", "endsWith");
  assert(account_rules.validate("ab_cd").isValid);
  assert(account_rules.validate("").issue.code == "required");
  assert(account_rules.validate("a_").issue.code == "minLength");
  assert(account_rules.validate("abc-cd").issue.code == "matches");
  assert(account_rules.validate("abcd").issue.code == "contains");
  assert(account_rules.validate("zz_cd").issue.code == "startsWith");
  assert(account_rules.validate("ab_zz").issue.code == "endsWith");
  assert(cbss::ValidationRules<std::string>()
             .exactLength(2)
             .validate("日本")
             .isValid);
  assert(cbss::ValidationRules<std::string>()
             .optional()
             .email()
             .validate("")
             .isValid);

  assert(cbss::ValidationRules<std::string>()
             .email()
             .validate("person+tag@example.co.jp")
             .isValid);
  assert(cbss::ValidationRules<std::string>()
             .url()
             .validate("https://example.com/path?q=1")
             .isValid);
  assert(cbss::ValidationRules<std::string>()
             .uuid()
             .validate("550e8400-e29b-41d4-a716-446655440000")
             .isValid);
  assert(cbss::ValidationRules<std::string>()
             .ipAddress()
             .validate("2001:db8::1")
             .isValid);
  assert(cbss::ValidationRules<std::string>()
             .date()
             .validate("2024-02-29")
             .isValid);
  assert(cbss::ValidationRules<std::string>()
             .time()
             .validate("23:59:58.125")
             .isValid);
  assert(cbss::ValidationRules<std::string>()
             .dateTime()
             .validate("2024-02-29T23:59:58Z")
             .isValid);

  const auto number_rules = cbss::ValidationRules<double>()
      .min(2.0, "min")
      .max(10.0, "max")
      .range(2.0, 10.0, "range")
      .integer("integer")
      .positive("positive")
      .finite("finite")
      .multipleOf(2.0, "multipleOf");
  assert(number_rules.validate(4.0).isValid);
  assert(number_rules.validate(1.0).issue.code == "min");
  assert(number_rules.validate(11.0).issue.code == "max");
  assert(number_rules.validate(5.0).issue.code == "multipleOf");
  assert(!cbss::ValidationRules<double>().finite().validate(INFINITY).isValid);
  assert(cbss::ValidationRules<double>().max(INFINITY).validate(42.0).isValid);
  assert(cbss::ValidationRules<double>().min(-INFINITY).validate(42.0).isValid);
  assert(!cbss::ValidationRules<double>().integer().validate(1.5).isValid);
  assert(cbss::ValidationRules<int>().negative().validate(-1).isValid);
  bool invalid_multiple_rejected = false;
  try {
    cbss::ValidationRules<double>().multipleOf(0.0);
  } catch (const std::invalid_argument&) {
    invalid_multiple_rejected = true;
  }
  assert(invalid_multiple_rejected);

  cbss::ValidationValue<std::string> password("first");
  const auto comparison_rules = cbss::ValidationRules<std::string>()
      .equalTo("first", "equalTo")
      .notEqualTo("blocked", "notEqualTo")
      .oneOf({"first", "second"}, "oneOf")
      .notOneOf({"blocked"}, "notOneOf")
      .sameAs(password, "sameAs");
  assert(comparison_rules.validate("first").isValid);
  password.set("changed");
  assert(comparison_rules.validate("first").issue.code == "sameAs");
  assert(cbss::ValidationRules<std::string>()
             .differentFrom(password)
             .validate("other")
             .isValid);

  const auto item_rules = cbss::ValidationRules<std::vector<int>>()
      .minItems(2, "minItems")
      .maxItems(4, "maxItems")
      .exactItems(3, "exactItems")
      .uniqueItems("uniqueItems");
  assert(item_rules.validate({1, 2, 3}).isValid);
  assert(item_rules.validate({1}).issue.code == "minItems");
  assert(item_rules.validate({1, 1, 2}).issue.code == "uniqueItems");

  const std::vector<cbss::ValidationFile> files = {
      {"photo.PNG", "image/png", 512},
      {"icon.svg", "image/svg+xml", 1024}};
  const auto file_rules =
      cbss::ValidationRules<std::vector<cbss::ValidationFile>>()
          .maxFileSize(1024, "maxFileSize")
          .allowedMimeTypes({"image/*"}, "allowedMimeTypes")
          .allowedExtensions({".png", "svg"}, "allowedExtensions")
          .maxFiles(2, "maxFiles");
  assert(file_rules.validate(files).isValid);
  assert(file_rules.validate({{"large.png", "image/png", 1025}})
             .issue.code == "maxFileSize");
  assert(file_rules.validate({{"note.txt", "text/plain", 1}})
             .issue.code == "allowedMimeTypes");

  const auto custom_rules = cbss::ValidationRules<std::string>().custom(
      [](const std::string& value) { return value == "approved"; },
      "custom message");
  assert(custom_rules.validate("approved").isValid);
  assert(custom_rules.validate("rejected").issue.code == "custom");

  cbss::ValidationBinding<std::string> validation_binding(
      cbss::ValidationRules<std::string>().required("required"), "",
      cbss::ValidationReport::onBlur);
  assert(!validation_binding.current().isValid);
  assert(!validation_binding.shouldExpose());
  validation_binding.evaluate("", cbss::ValidationTrigger::input);
  assert(!validation_binding.shouldExpose());
  validation_binding.evaluate("", cbss::ValidationTrigger::blur);
  assert(validation_binding.shouldExpose());
  assert(validation_binding.validationMessage() == "required");
  validation_binding.evaluate("valid", cbss::ValidationTrigger::input);
  assert(validation_binding.current().isValid);
  assert(!validation_binding.shouldExpose());

  using StringCommand = cbss::Command<int, std::string, std::string>;
  using StringSink = cbss::CommandSink<std::string, std::string>;
  const std::shared_ptr<std::vector<StringSink>> latest_sinks =
      std::make_shared<std::vector<StringSink>>();
  const std::shared_ptr<int> latest_cancellations = std::make_shared<int>(0);
  StringCommand latest_command(
      [latest_sinks, latest_cancellations](int, StringSink sink) {
        latest_sinks->push_back(sink);
        return StringCommand::Cancel(
            [latest_cancellations]() { ++*latest_cancellations; });
      });
  std::vector<std::string> command_successes;
  latest_command.onSuccess(
      [&](std::string value) { command_successes.push_back(std::move(value)); });
  const cbss::CommandTicket latest_first = latest_command.run(1);
  const cbss::CommandTicket latest_second = latest_command.run(2);
  assert(latest_first.status() == cbss::CommandStatus::cancelled);
  assert(latest_second.status() == cbss::CommandStatus::running);
  assert(*latest_cancellations == 1);
  assert((*latest_sinks)[0].succeed("stale") ==
         cbss::CommandOfferResult::accepted);
  assert((*latest_sinks)[1].succeed("current") ==
         cbss::CommandOfferResult::accepted);
  assert(latest_command.pump() == 2u);
  assert(command_successes == std::vector<std::string>({"current"}));
  assert(latest_second.status() == cbss::CommandStatus::succeeded);

  const std::shared_ptr<std::vector<StringSink>> ordered_sinks =
      std::make_shared<std::vector<StringSink>>();
  StringCommand ordered_command(
      [ordered_sinks](int, StringSink sink) {
        ordered_sinks->push_back(sink);
        return StringCommand::Cancel();
      },
      cbss::CommandPolicy::ordered, 2u);
  std::vector<std::string> ordered_results;
  ordered_command.onSuccess(
      [&](std::string value) { ordered_results.push_back(std::move(value)); });
  const cbss::CommandTicket ordered_first = ordered_command.run(1);
  const cbss::CommandTicket ordered_second = ordered_command.run(2);
  const cbss::CommandTicket ordered_third = ordered_command.run(3);
  assert(ordered_first.status() == cbss::CommandStatus::running);
  assert(ordered_second.status() == cbss::CommandStatus::queued);
  assert(ordered_third.status() == cbss::CommandStatus::queued);
  assert(ordered_command.activeCount() == 1u);
  assert(ordered_command.queuedCount() == 2u);
  assert((*ordered_sinks)[0].succeed("one") ==
         cbss::CommandOfferResult::accepted);
  assert(ordered_command.pump(1u) == 1u);
  assert(ordered_second.status() == cbss::CommandStatus::running);
  assert((*ordered_sinks)[1].fail("two") ==
         cbss::CommandOfferResult::accepted);
  assert(ordered_command.pump(1u) == 1u);
  assert(ordered_second.status() == cbss::CommandStatus::failed);
  assert(ordered_third.status() == cbss::CommandStatus::running);
  assert((*ordered_sinks)[2].succeed("three") ==
         cbss::CommandOfferResult::accepted);
  assert(ordered_command.pump(1u) == 1u);
  assert(ordered_results == std::vector<std::string>({"one", "three"}));
  assert(!ordered_command.pending());

  const std::shared_ptr<std::vector<StringSink>> concurrent_sinks =
      std::make_shared<std::vector<StringSink>>();
  StringCommand concurrent_command(
      [concurrent_sinks](int, StringSink sink) {
        concurrent_sinks->push_back(sink);
        return StringCommand::Cancel();
      },
      cbss::CommandPolicy::concurrent, 1u);
  std::vector<std::string> concurrent_results;
  concurrent_command.onSuccess([&](std::string value) {
    concurrent_results.push_back(std::move(value));
  });
  const cbss::CommandTicket concurrent_first = concurrent_command.run(1);
  const cbss::CommandTicket concurrent_second = concurrent_command.run(2);
  assert((*concurrent_sinks)[0].succeed("first") ==
         cbss::CommandOfferResult::accepted);
  assert((*concurrent_sinks)[1].succeed("second") ==
         cbss::CommandOfferResult::backpressure);
  assert(concurrent_command.pump(1u) == 1u);
  assert((*concurrent_sinks)[1].succeed("second") ==
         cbss::CommandOfferResult::accepted);
  assert(concurrent_command.pump(1u) == 1u);
  assert(concurrent_first.status() == cbss::CommandStatus::succeeded);
  assert(concurrent_second.status() == cbss::CommandStatus::succeeded);

  const std::shared_ptr<std::vector<StringSink>> observed_sinks =
      std::make_shared<std::vector<StringSink>>();
  StringCommand observed_command(
      [observed_sinks](int, StringSink sink) {
        observed_sinks->push_back(sink);
        return StringCommand::Cancel();
      },
      cbss::CommandPolicy::concurrent);
  const cbss::CommandTicket observed_ticket = observed_command.run(1);
  cbss::CommandStatus observed_status = cbss::CommandStatus::running;
  cbss::CommandRunSubscription observed_subscription =
      observed_command.observeRun(
          observed_ticket,
          [&](cbss::CommandTicket ticket, cbss::CommandStatus status) {
            assert(ticket.id() == observed_ticket.id());
            observed_status = status;
          });
  assert(observed_subscription.active());
  assert((*observed_sinks)[0].succeed("done") ==
         cbss::CommandOfferResult::accepted);
  assert(observed_command.pump() == 1u);
  assert(observed_status == cbss::CommandStatus::succeeded);
  assert(!observed_subscription.active());

  cbss::CommandStatus immediate_status = cbss::CommandStatus::running;
  cbss::CommandRunSubscription immediate_subscription =
      observed_command.observeRun(
          observed_ticket,
          [&](cbss::CommandTicket, cbss::CommandStatus status) {
            immediate_status = status;
          });
  assert(!immediate_subscription.active());
  assert(immediate_status == cbss::CommandStatus::succeeded);

  const std::shared_ptr<std::vector<StringSink>> disposable_sinks =
      std::make_shared<std::vector<StringSink>>();
  const std::shared_ptr<int> dispose_cancellations = std::make_shared<int>(0);
  StringCommand disposable_command(
      [disposable_sinks, dispose_cancellations](int, StringSink sink) {
        disposable_sinks->push_back(sink);
        return StringCommand::Cancel(
            [dispose_cancellations]() { ++*dispose_cancellations; });
      });
  const cbss::CommandTicket disposable_ticket = disposable_command.run(1);
  assert(disposable_command.dispose());
  assert(!disposable_command.dispose());
  assert(disposable_ticket.status() == cbss::CommandStatus::cancelled);
  assert(*dispose_cancellations == 1);
  assert((*disposable_sinks)[0].succeed("late") ==
         cbss::CommandOfferResult::disposed);
  assert(disposable_command.pump() == 0u);

  const std::shared_ptr<std::vector<StringSink>> cancellation_sinks =
      std::make_shared<std::vector<StringSink>>();
  const std::shared_ptr<int> explicit_cancellations = std::make_shared<int>(0);
  StringCommand cancellation_command(
      [cancellation_sinks, explicit_cancellations](int, StringSink sink) {
        cancellation_sinks->push_back(sink);
        return StringCommand::Cancel(
            [explicit_cancellations]() { ++*explicit_cancellations; });
      },
      cbss::CommandPolicy::ordered);
  const cbss::CommandTicket cancellation_first = cancellation_command.run(1);
  const cbss::CommandTicket cancellation_second = cancellation_command.run(2);
  const cbss::CommandTicket cancellation_third = cancellation_command.run(3);
  assert(cancellation_command.cancel(cancellation_second));
  assert(cancellation_second.status() == cbss::CommandStatus::cancelled);
  assert(cancellation_command.cancel(cancellation_first));
  assert(cancellation_third.status() == cbss::CommandStatus::running);
  assert(cancellation_command.cancelAll() == 1u);
  assert(cancellation_third.status() == cbss::CommandStatus::cancelled);
  assert(*explicit_cancellations == 2);
  assert(!cancellation_command.pending());

  StringCommand foreign_command(
      [](int, StringSink) { return StringCommand::Cancel(); });
  const cbss::CommandTicket foreign_ticket = foreign_command.run(1);
  assert(!cancellation_command.cancel(foreign_ticket));
  bool foreign_observer_rejected = false;
  try {
    cancellation_command.observeRun(
        foreign_ticket, [](cbss::CommandTicket, cbss::CommandStatus) {});
  } catch (const std::invalid_argument&) {
    foreign_observer_rejected = true;
  }
  assert(foreign_observer_rejected);

  const std::shared_ptr<std::vector<StringSink>> callback_sinks =
      std::make_shared<std::vector<StringSink>>();
  StringCommand callback_command(
      [callback_sinks](int, StringSink sink) {
        callback_sinks->push_back(sink);
        return StringCommand::Cancel();
      },
      cbss::CommandPolicy::concurrent);
  int callback_count = 0;
  callback_command.onSuccess([&](std::string value) {
    ++callback_count;
    if (value == "first") {
      throw std::runtime_error("first callback failed");
    }
  });
  const cbss::CommandTicket callback_first = callback_command.run(1);
  const cbss::CommandTicket callback_second = callback_command.run(2);
  assert((*callback_sinks)[0].succeed("first") ==
         cbss::CommandOfferResult::accepted);
  assert((*callback_sinks)[1].succeed("second") ==
         cbss::CommandOfferResult::accepted);
  bool callback_failure_reported = false;
  try {
    callback_command.pump();
  } catch (const std::runtime_error&) {
    callback_failure_reported = true;
  }
  assert(callback_failure_reported);
  assert(callback_count == 2);
  assert(callback_first.status() == cbss::CommandStatus::succeeded);
  assert(callback_second.status() == cbss::CommandStatus::succeeded);
  assert(!callback_command.pending());

  const std::shared_ptr<std::vector<StringSink>> executor_sinks =
      std::make_shared<std::vector<StringSink>>();
  int executor_attempts = 0;
  StringCommand executor_command(
      [executor_sinks, &executor_attempts](int input, StringSink sink) {
        ++executor_attempts;
        if (input == 2) {
          throw std::runtime_error("queued executor failed");
        }
        executor_sinks->push_back(sink);
        return StringCommand::Cancel();
      },
      cbss::CommandPolicy::ordered);
  const cbss::CommandTicket executor_first = executor_command.run(1);
  const cbss::CommandTicket executor_second = executor_command.run(2);
  const cbss::CommandTicket executor_third = executor_command.run(3);
  assert((*executor_sinks)[0].succeed("one") ==
         cbss::CommandOfferResult::accepted);
  bool executor_failure_reported = false;
  try {
    executor_command.pump();
  } catch (const std::runtime_error&) {
    executor_failure_reported = true;
  }
  assert(executor_failure_reported);
  assert(executor_first.status() == cbss::CommandStatus::succeeded);
  assert(executor_second.status() == cbss::CommandStatus::cancelled);
  assert(executor_third.status() == cbss::CommandStatus::running);
  assert(executor_attempts == 3);
  assert((*executor_sinks)[1].succeed("three") ==
         cbss::CommandOfferResult::accepted);
  assert(executor_command.pump() == 1u);
  assert(!executor_command.pending());

  const std::shared_ptr<std::vector<StringSink>> wake_sinks =
      std::make_shared<std::vector<StringSink>>();
  StringCommand wake_command(
      [wake_sinks](int, StringSink sink) {
        wake_sinks->push_back(sink);
        return StringCommand::Cancel();
      },
      cbss::CommandPolicy::concurrent);
  int wake_count = 0;
  wake_command.setWakeCallback([&]() { ++wake_count; });
  int removed_observer_calls = 0;
  const cbss::CommandTicket wake_first = wake_command.run(1);
  {
    cbss::CommandRunSubscription removed = wake_command.observeRun(
        wake_first, [&](cbss::CommandTicket, cbss::CommandStatus) {
          ++removed_observer_calls;
        });
    assert(removed.active());
  }
  const cbss::CommandTicket wake_second = wake_command.run(2);
  assert((*wake_sinks)[0].succeed("one") ==
         cbss::CommandOfferResult::accepted);
  assert((*wake_sinks)[1].succeed("two") ==
         cbss::CommandOfferResult::accepted);
  assert(wake_count == 1);
  assert(wake_command.pump() == 2u);
  assert(removed_observer_calls == 0);
  assert(wake_first.status() == cbss::CommandStatus::succeeded);
  assert(wake_second.status() == cbss::CommandStatus::succeeded);
  const cbss::CommandTicket wake_third = wake_command.run(3);
  assert((*wake_sinks)[2].succeed("three") ==
         cbss::CommandOfferResult::accepted);
  assert(wake_count == 2);
  assert(wake_command.pump() == 1u);
  assert(wake_third.status() == cbss::CommandStatus::succeeded);

  const std::shared_ptr<std::vector<StringSink>> robust_dispose_sinks =
      std::make_shared<std::vector<StringSink>>();
  StringCommand robust_dispose_command(
      [robust_dispose_sinks](int, StringSink sink) {
        robust_dispose_sinks->push_back(sink);
        return StringCommand::Cancel();
      },
      cbss::CommandPolicy::ordered);
  const cbss::CommandTicket robust_active = robust_dispose_command.run(1);
  const cbss::CommandTicket robust_queued = robust_dispose_command.run(2);
  cbss::CommandRunSubscription throwing_observer =
      robust_dispose_command.observeRun(
          robust_active, [](cbss::CommandTicket, cbss::CommandStatus) {
            throw std::runtime_error("observer failed during disposal");
          });
  assert(robust_dispose_command.dispose());
  assert(robust_active.status() == cbss::CommandStatus::cancelled);
  assert(robust_queued.status() == cbss::CommandStatus::cancelled);

  const std::size_t large_command_count = 2000u;
  using NumericCommand = cbss::Command<std::size_t, std::size_t, std::string>;
  using NumericSink = cbss::CommandSink<std::size_t, std::string>;
  const std::shared_ptr<std::vector<NumericSink>> large_sinks =
      std::make_shared<std::vector<NumericSink>>();
  large_sinks->reserve(large_command_count);
  NumericCommand large_command(
      [large_sinks](std::size_t, NumericSink sink) {
        large_sinks->push_back(sink);
        return NumericCommand::Cancel();
      },
      cbss::CommandPolicy::concurrent, large_command_count,
      static_cast<std::int64_t>(large_command_count));
  std::vector<std::size_t> large_results;
  large_results.reserve(large_command_count);
  large_command.onSuccess(
      [&](std::size_t value) { large_results.push_back(value); });
  for (std::size_t value = 0u; value < large_command_count; ++value) {
    large_command.run(value);
  }
  for (std::size_t value = large_command_count; value > 0u; --value) {
    assert((*large_sinks)[value - 1u].succeed(value - 1u) ==
           cbss::CommandOfferResult::accepted);
  }
  assert(large_command.pump() == large_command_count);
  assert(large_results.front() == large_command_count - 1u);
  assert(large_results.back() == 0u);
  assert(!large_command.pending());

  bool negative_weight_rejected = false;
  try {
    (*large_sinks)[0].succeed(0u, -1);
  } catch (const std::invalid_argument&) {
    negative_weight_rejected = true;
  }
  assert(negative_weight_rejected);

  bool command_limits_rejected = false;
  try {
    StringCommand invalid_command(
        [](int, StringSink) { return StringCommand::Cancel(); },
        cbss::CommandPolicy::latestOnly, 0u);
  } catch (const std::invalid_argument&) {
    command_limits_rejected = true;
  }
  assert(command_limits_rejected);

  std::vector<std::string> cue_events;
  cbss::CueRuntime cue_runtime;
  cbss::CueGraph serial_cue = cbss::cue(cbss::cueAction(
      "A", [&]() { cue_events.push_back("A"); }));
  serial_cue.then(cbss::cueAction(
      "B", [&]() { cue_events.push_back("B"); }))
      .then(cbss::cueAction(
          "C", [&]() { cue_events.push_back("C"); }));
  const cbss::CueSession serial_session = cue_runtime.start(serial_cue);
  assert((cue_events == std::vector<std::string>{"A", "B", "C"}));
  assert(serial_session.status() == cbss::CueSessionStatus::succeeded);
  assert(cue_runtime.activeCount() == 0u);
  assert(!cue_runtime.hasDeadline());

  const std::shared_ptr<std::vector<cbss::CueCompletion>> all_completions =
      std::make_shared<std::vector<cbss::CueCompletion>>();
  int all_cancellations = 0;
  const cbss::CueAction first_deferred = cbss::cueAction(
      "first", [all_completions, &all_cancellations](
                   cbss::CueCompletion completion) {
        all_completions->push_back(completion);
        return cbss::CueCancel([&all_cancellations]() {
          ++all_cancellations;
        });
      });
  const cbss::CueAction second_deferred = cbss::cueAction(
      "second", [all_completions, &all_cancellations](
                    cbss::CueCompletion completion) {
        all_completions->push_back(completion);
        return cbss::CueCancel([&all_cancellations]() {
          ++all_cancellations;
        });
      });
  int all_tail = 0;
  cbss::CueGraph all_graph = cbss::cue(cbss::cueAction("start", []() {}));
  all_graph.thenParallel({first_deferred, second_deferred})
      .then(cbss::cueAction("tail", [&]() { ++all_tail; }));
  const cbss::CueSession all_session = cue_runtime.start(all_graph);
  assert(all_completions->size() == 2u);
  (*all_completions)[0].succeed();
  assert(all_tail == 0);
  (*all_completions)[1].succeed();
  assert(all_tail == 1);
  assert(all_session.status() == cbss::CueSessionStatus::succeeded);
  assert(all_cancellations == 0);

  cbss::CueRuntime clock_runtime(10.0);
  std::vector<std::string> delayed_events;
  cbss::CueGraph delayed = cbss::cue(cbss::cueAction(
      "start", [&]() { delayed_events.push_back("start"); }));
  delayed.thenStage({
      cbss::cueAfter(0.5, cbss::cueAction(
          "half", [&]() { delayed_events.push_back("half"); })),
      cbss::cueAfter(2.0, cbss::cueAction(
          "two", [&]() { delayed_events.push_back("two"); }))});
  const cbss::CueSession delayed_session = clock_runtime.start(delayed);
  assert(clock_runtime.hasDeadline());
  assert(clock_runtime.nextDeadline() == 10.5);
  clock_runtime.tick(10.5);
  assert((delayed_events == std::vector<std::string>{"start", "half"}));
  assert(clock_runtime.nextDeadline() == 12.0);
  clock_runtime.pause();
  clock_runtime.tick(20.0);
  assert(clock_runtime.now() == 10.5);
  assert(!clock_runtime.hasDeadline());
  clock_runtime.resume();
  clock_runtime.setRate(2.0);
  assert(clock_runtime.nextDeadline() == 20.75);
  clock_runtime.tick(20.75);
  assert(delayed_session.status() == cbss::CueSessionStatus::succeeded);

  const std::shared_ptr<std::vector<cbss::CueCompletion>> any_completions =
      std::make_shared<std::vector<cbss::CueCompletion>>();
  int pending_cancelled = 0;
  auto deferred_cue = [&](const std::string& name) {
    return cbss::cueAction(name, [any_completions, &pending_cancelled](
                                     cbss::CueCompletion completion) {
      any_completions->push_back(completion);
      return cbss::CueCancel([&pending_cancelled]() {
        ++pending_cancelled;
      });
    });
  };
  int any_tail = 0;
  cbss::CueGraph any_graph = cbss::cue(cbss::cueAction("start", []() {}));
  any_graph.thenAny(
      {deferred_cue("failed"), deferred_cue("winner"),
       deferred_cue("pending")})
      .then(cbss::cueAction("tail", [&]() { ++any_tail; }));
  const cbss::CueSession any_session = cue_runtime.start(any_graph);
  (*any_completions)[0].fail("not this one");
  (*any_completions)[1].succeed();
  assert(any_session.status() == cbss::CueSessionStatus::succeeded);
  assert(any_tail == 1);
  assert(pending_cancelled == 1);
  (*any_completions)[2].succeed();
  assert(any_tail == 1);

  const std::shared_ptr<std::vector<cbss::CueCompletion>> race_completions =
      std::make_shared<std::vector<cbss::CueCompletion>>();
  int race_cancelled = 0;
  auto race_action = [&](const std::string& name) {
    return cbss::cueAction(name, [race_completions, &race_cancelled](
                                     cbss::CueCompletion completion) {
      race_completions->push_back(completion);
      return cbss::CueCancel([&race_cancelled]() { ++race_cancelled; });
    });
  };
  cbss::CueGraph race_graph = cbss::cue(cbss::cueAction("start", []() {}));
  race_graph.thenRace({race_action("loser"), race_action("pending")});
  const cbss::CueSession race_session = cue_runtime.start(race_graph);
  (*race_completions)[0].fail("network unavailable");
  assert(race_session.status() == cbss::CueSessionStatus::failed);
  assert(race_session.failure() == "network unavailable");
  assert(race_cancelled == 1);

  int thrown_cancelled = 0;
  const cbss::CueAction throwing_cue = cbss::cueAction(
      "throwing", [](cbss::CueCompletion) -> cbss::CueCancel {
        throw std::runtime_error("action crashed");
      });
  const cbss::CueAction thrown_pending = cbss::cueAction(
      "pending", [&thrown_cancelled](cbss::CueCompletion) {
        return cbss::CueCancel(
            [&thrown_cancelled]() { ++thrown_cancelled; });
      });
  cbss::CueGraph thrown_graph =
      cbss::cue(cbss::cueAction("start", []() {}));
  thrown_graph.thenParallel({throwing_cue, thrown_pending});
  const cbss::CueSession thrown_session = cue_runtime.start(thrown_graph);
  assert(thrown_session.status() == cbss::CueSessionStatus::failed);
  assert(thrown_session.failure() == "action crashed");
  assert(thrown_cancelled == 1);

  const std::shared_ptr<std::vector<cbss::CueCompletion>> policy_completions =
      std::make_shared<std::vector<cbss::CueCompletion>>();
  int policy_cancelled = 0;
  const cbss::CueAction policy_action = cbss::cueAction(
      "policy", [policy_completions, &policy_cancelled](
                    cbss::CueCompletion completion) {
        policy_completions->push_back(completion);
        return cbss::CueCancel(
            [&policy_cancelled]() { ++policy_cancelled; });
      });
  cbss::CueGraph policy_graph = cbss::cue(policy_action);
  const cbss::CueSession policy_first = cue_runtime.start(policy_graph);
  const cbss::CueSession policy_ignored =
      cue_runtime.start(policy_graph, cbss::CueStartPolicy::ignore);
  const cbss::CueSession policy_parallel =
      cue_runtime.start(policy_graph, cbss::CueStartPolicy::parallel);
  const cbss::CueSession policy_queued =
      cue_runtime.start(policy_graph, cbss::CueStartPolicy::queue);
  assert(policy_ignored.id() == policy_first.id());
  assert(policy_parallel.id() != policy_first.id());
  assert(policy_queued.status() == cbss::CueSessionStatus::queued);
  const cbss::CueSession policy_restart =
      cue_runtime.start(policy_graph, cbss::CueStartPolicy::restart);
  assert(policy_first.status() == cbss::CueSessionStatus::cancelled);
  assert(policy_parallel.status() == cbss::CueSessionStatus::cancelled);
  assert(policy_queued.status() == cbss::CueSessionStatus::cancelled);
  assert(policy_restart.status() == cbss::CueSessionStatus::running);
  assert(policy_cancelled == 2);

  bool sealed_graph_rejected = false;
  try {
    policy_graph.then(cbss::cueAction("late", []() {}));
  } catch (const std::logic_error&) {
    sealed_graph_rejected = true;
  }
  assert(sealed_graph_rejected);
  bool invalid_delay_rejected = false;
  try {
    cbss::branch(policy_action, -1.0);
  } catch (const std::invalid_argument&) {
    invalid_delay_rejected = true;
  }
  assert(invalid_delay_rejected);

  cbss::CueRuntime chain_runtime;
  int chain_runs = 0;
  const cbss::CueAction chain_action =
      cbss::cueAction("chain", [&]() { ++chain_runs; });
  cbss::CueGraph chain_graph = cbss::cue(chain_action);
  for (std::size_t index = 1u; index < 5000u; ++index) {
    chain_graph.then(chain_action);
  }
  const cbss::CueSession chain_session = chain_runtime.start(chain_graph);
  assert(chain_runs == 5000);
  assert(chain_session.status() == cbss::CueSessionStatus::succeeded);

  const std::shared_ptr<std::vector<cbss::CueCompletion>> large_completions =
      std::make_shared<std::vector<cbss::CueCompletion>>();
  large_completions->reserve(5000u);
  const cbss::CueAction large_parallel_action = cbss::cueAction(
      "parallel", [large_completions](cbss::CueCompletion completion) {
        large_completions->push_back(completion);
        return cbss::CueCancel();
      });
  std::vector<cbss::CueBranch> large_branches;
  large_branches.reserve(5000u);
  for (std::size_t index = 0u; index < 5000u; ++index) {
    large_branches.push_back(cbss::branch(large_parallel_action));
  }
  cbss::CueGraph large_parallel_graph =
      cbss::cue(cbss::cueAction("start", []() {}));
  large_parallel_graph.thenStage(std::move(large_branches));
  const cbss::CueSession large_parallel_session =
      chain_runtime.start(large_parallel_graph);
  assert(large_completions->size() == 5000u);
  for (const cbss::CueCompletion& completion : *large_completions) {
    completion.succeed();
  }
  assert(large_parallel_session.status() ==
         cbss::CueSessionStatus::succeeded);

  const std::shared_ptr<std::vector<cbss::CueCompletion>> fifo_completions =
      std::make_shared<std::vector<cbss::CueCompletion>>();
  const cbss::CueAction fifo_action = cbss::cueAction(
      "fifo", [fifo_completions](cbss::CueCompletion completion) {
        fifo_completions->push_back(completion);
        return cbss::CueCancel();
      });
  cbss::CueGraph fifo_graph = cbss::cue(fifo_action);
  const cbss::CueSession fifo_first = chain_runtime.start(fifo_graph);
  const cbss::CueSession fifo_second =
      chain_runtime.start(fifo_graph, cbss::CueStartPolicy::queue);
  const cbss::CueSession fifo_third =
      chain_runtime.start(fifo_graph, cbss::CueStartPolicy::queue);
  assert(fifo_completions->size() == 1u);
  const cbss::CueCompletion fifo_first_completion = (*fifo_completions)[0];
  fifo_first_completion.succeed();
  assert(fifo_first.status() == cbss::CueSessionStatus::succeeded);
  assert(fifo_second.status() == cbss::CueSessionStatus::running);
  assert(fifo_third.status() == cbss::CueSessionStatus::queued);
  assert(fifo_completions->size() == 2u);
  const cbss::CueCompletion fifo_second_completion = (*fifo_completions)[1];
  fifo_second_completion.succeed();
  assert(fifo_second.status() == cbss::CueSessionStatus::succeeded);
  assert(fifo_third.status() == cbss::CueSessionStatus::running);
  assert(fifo_completions->size() == 3u);
  const cbss::CueCompletion fifo_third_completion = (*fifo_completions)[2];
  fifo_third_completion.succeed();
  assert(fifo_third.status() == cbss::CueSessionStatus::succeeded);

  cbss::CueRuntime equal_deadline_runtime;
  std::vector<int> equal_deadline_order;
  cbss::CueGraph equal_deadline_graph =
      cbss::cue(cbss::cueAction("start", []() {}));
  equal_deadline_graph.thenStage(
      {cbss::cueAfter(1.0, cbss::cueAction(
                               "first", [&equal_deadline_order]() {
                                 equal_deadline_order.push_back(1);
                               })),
       cbss::cueAfter(1.0, cbss::cueAction(
                               "second", [&equal_deadline_order]() {
                                 equal_deadline_order.push_back(2);
                               }))});
  const cbss::CueSession equal_deadline_session =
      equal_deadline_runtime.start(equal_deadline_graph);
  equal_deadline_runtime.tick(1.0);
  assert((equal_deadline_order == std::vector<int>{1, 2}));
  assert(equal_deadline_session.status() ==
         cbss::CueSessionStatus::succeeded);

  cbss::CueRuntime throwing_cancel_runtime;
  cbss::CueGraph throwing_cancel_graph = cbss::cue(cbss::cueAction(
      "pending", [](cbss::CueCompletion) {
        return cbss::CueCancel(
            []() { throw std::runtime_error("cancel failed"); });
      }));
  const cbss::CueSession throwing_cancel_session =
      throwing_cancel_runtime.start(throwing_cancel_graph);
  assert(throwing_cancel_runtime.cancel(throwing_cancel_session));
  assert(throwing_cancel_session.status() ==
         cbss::CueSessionStatus::cancelled);
  cbss::CueRuntime foreign_cancel_runtime;
  assert(!foreign_cancel_runtime.cancel(throwing_cancel_session));

  cbss::Ui owned_cue_ui;
  cbss::CraftComponent owned_cue_component = owned_cue_ui.component(
      "owned-cue", "owned-cue", [](cbss::ComponentScope&) {});
  bool invalid_owned_clock_rejected = false;
  try {
    owned_cue_component.cueRuntime(
        std::numeric_limits<double>::quiet_NaN());
  } catch (const std::invalid_argument&) {
    invalid_owned_clock_rejected = true;
  }
  assert(invalid_owned_clock_rejected);
  assert(owned_cue_component.cueRuntimeCount() == 0u);
  cbss::CueRuntime owned_cue_runtime = owned_cue_component.cueRuntime();
  int owned_cue_cancelled = 0;
  cbss::CueGraph owned_cue_graph = cbss::cue(cbss::cueAction(
      "pending", [&owned_cue_cancelled](cbss::CueCompletion) {
        return cbss::CueCancel(
            [&owned_cue_cancelled]() { ++owned_cue_cancelled; });
      }));
  const cbss::CueSession owned_cue_session =
      owned_cue_runtime.start(owned_cue_graph);
  assert(owned_cue_component.cueRuntimeCount() == 1u);
  assert(owned_cue_ui.unmount(owned_cue_component) == 1u);
  assert(!owned_cue_runtime.active());
  assert(owned_cue_session.status() == cbss::CueSessionStatus::cancelled);
  assert(owned_cue_cancelled == 1);
  assert(owned_cue_component.cueRuntimeCount() == 0u);
  bool unmounted_cue_rejected = false;
  try {
    owned_cue_component.cueRuntime();
  } catch (const cbss::Error& error) {
    unmounted_cue_rejected = error.status() == CBSS_INVALID_HANDLE;
  }
  assert(unmounted_cue_rejected);

  cbss::CueRuntime dropped_cue_runtime;
  cbss::CueSession dropped_cue_session;
  int dropped_cue_cancelled = 0;
  {
    cbss::Ui dropped_cue_ui;
    cbss::CraftComponent dropped_cue_component = dropped_cue_ui.component(
        "dropped-cue", "dropped-cue", [](cbss::ComponentScope&) {});
    dropped_cue_runtime = dropped_cue_component.cueRuntime();
    cbss::CueGraph dropped_cue_graph = cbss::cue(cbss::cueAction(
        "pending", [&dropped_cue_cancelled](cbss::CueCompletion) {
          return cbss::CueCancel(
              [&dropped_cue_cancelled]() { ++dropped_cue_cancelled; });
        }));
    dropped_cue_session = dropped_cue_runtime.start(dropped_cue_graph);
  }
  assert(!dropped_cue_runtime.active());
  assert(dropped_cue_session.status() == cbss::CueSessionStatus::cancelled);
  assert(dropped_cue_cancelled == 1);

  cue_runtime.dispose();
  assert(policy_restart.status() == cbss::CueSessionStatus::cancelled);
  assert(policy_cancelled == 3);
  (*policy_completions).back().succeed();
  assert(policy_restart.status() == cbss::CueSessionStatus::cancelled);

  return 0;
}
