#include <cbss/craft.hpp>

#include <cassert>
#include <cctype>
#include <cmath>
#include <cstdint>
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
      "minimumAbi":65559,
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

  return 0;
}
