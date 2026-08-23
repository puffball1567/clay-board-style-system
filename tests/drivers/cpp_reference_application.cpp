#include "cbss/craft.hpp"
#include "cbss/validation_ui.hpp"

#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::string readFile(const std::string& path) {
  std::ifstream input(path.c_str(), std::ios::binary);
  if (!input) throw std::runtime_error("unable to open fixture: " + path);
  std::ostringstream content;
  content << input.rdbuf();
  return content.str();
}

std::string join(const std::vector<std::string>& values) {
  std::string result;
  for (std::size_t index = 0; index < values.size(); ++index) {
    if (index != 0u) result += ',';
    result += values[index];
  }
  return result;
}

struct Counter {
  int value = 0;
};

void writeTrace(std::ostream& output) {
  const std::string style = readFile(
      "tests/fixtures/drivers/reference_application_style.json");
  const std::string invalid_style = readFile(
      "tests/fixtures/drivers/invalid_application_style.json");

  cbss::Style root_style;
  root_style.set("width", cbss::px(320.0f))
      .set("height", cbss::px(200.0f))
      .set("padding", cbss::px(12.0f))
      .set("gap", cbss::px(8.0f))
      .set("flex-direction", cbss::keyword("column"));

  cbss::Ui ui;
  cbss::Node panel;
  cbss::Node field;
  cbss::Node form_node;
  ui.box("root", root_style, [&] {
    panel = ui.box("panel", [&] { ui.text("Reference", "panel-label"); });
    form_node = ui.box("form", [&] { field = ui.box("account"); });
  });
  ui.exposeStyleSlot(panel, panel, "reference-card", "root");
  ui.replaceCraftStyle(style);
  ui.compute(320.0f, 200.0f);
  const CbssRect panel_rect = ui.rect(panel);

  std::vector<std::string> event_order;
  const cbss::UiHandle event_ui = ui.handle();
  ui.on(panel, CBSS_EVENT_CLICK, [&](const cbss::Event&) {
    event_order.push_back("handler");
    event_ui.setState(panel, cbss::NodeState::hover, true);
    return cbss::EventOutcome::handled();
  });
  cbss::EventSubscription observer = ui.subscribe(
      panel, CBSS_EVENT_CLICK, [&](const cbss::Event&) {
        event_order.push_back("observer");
        return cbss::EventOutcome();
      });
  const cbss::DispatchSummary click =
      ui.emit(panel, cbss::InputEvent(CBSS_EVENT_CLICK));

  auto account = cbss::attachTextValidation(
      ui, field,
      cbss::ValidationRules<std::string>().required("account required"));
  cbss::ValidationForm form(ui, form_node);
  form.registerTextField("account", account);
  std::string submitted;
  form.onSubmit([&](const cbss::EventView& event) {
    const cbss::FormDataEntry entry = event.formData().entry(0u);
    submitted = entry.name + ':' + entry.text;
    return cbss::EventOutcome::handled();
  });
  account.input("ready");
  const bool submitted_ok = form.submitCollected();

  auto store = cbss::createStore<Counter, int>(
      Counter(), [](Counter& state, const int& amount) {
        state.value += amount;
      });
  store.dispatch(2);
  store.transaction([&] {
    store.dispatch(3);
    store.dispatch(4);
  });

  auto navigator = cbss::createStackNavigator<std::string>("home");
  navigator.push("projects");
  navigator.push("settings");
  navigator.back();

  int invalid_status = 0;
  try {
    ui.replaceCraftStyle(invalid_style);
  } catch (const cbss::Error& error) {
    invalid_status = error.status();
  }
  const std::vector<cbss::CraftDiagnostic> diagnostics =
      ui.craftDiagnostics();
  const std::uint32_t removed = ui.removeSubtree(panel);

  output << "cbss-driver-reference-v1\n";
  output << std::fixed << std::setprecision(3);
  output << "layout.panel.width=" << panel_rect.w << '\n';
  output << "layout.panel.height=" << panel_rect.h << '\n';
  output << "event.order=" << join(event_order) << '\n';
  output << "event.dispatch-count=" << click.dispatch_count << '\n';
  output << "event.handled=" << (click.handled ? 1 : 0) << '\n';
  output << "event.needs-compute=" << (click.needs_compute ? 1 : 0) << '\n';
  output << "form.submitted=" << (submitted_ok ? 1 : 0) << '\n';
  output << "form.payload=" << submitted << '\n';
  output << "store.value=" << store.state().value << '\n';
  output << "store.revision=" << store.revision() << '\n';
  output << "navigation.current="
         << navigator.currentDestination().value() << '\n';
  output << "navigation.revision=" << navigator.snapshot().revision << '\n';
  output << "style.active=" << ui.activeCraftStyles().at(0) << '\n';
  output << "style.invalid-status=" << invalid_status << '\n';
  output << "style.diagnostics=" << diagnostics.size() << '\n';
  output << "lifecycle.removed=" << removed << '\n';
  output << "lifecycle.observer-active=" << (observer.active() ? 1 : 0)
         << '\n';
}

}  // namespace

int main(int argc, char** argv) {
  try {
    if (argc == 1) {
      writeTrace(std::cout);
      return 0;
    }
    if (argc != 2) return 2;
    std::ofstream output(argv[1], std::ios::binary | std::ios::trunc);
    if (!output) return 3;
    writeTrace(output);
    return output ? 0 : 4;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
