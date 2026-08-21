#include <cbss/craft.hpp>

#include <cassert>
#include <cmath>
#include <cstdint>

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
      "minimumAbi":65558,
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
  return 0;
}
