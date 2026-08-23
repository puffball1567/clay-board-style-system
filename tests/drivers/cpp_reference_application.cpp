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

  using ReferenceCommand = cbss::Command<int, std::string, std::string>;
  using ReferenceSink = cbss::CommandSink<std::string, std::string>;
  const std::shared_ptr<std::vector<ReferenceSink>> command_sinks =
      std::make_shared<std::vector<ReferenceSink>>();
  const std::shared_ptr<int> command_cancellations = std::make_shared<int>(0);
  ReferenceCommand command(
      [command_sinks, command_cancellations](int, ReferenceSink sink) {
        command_sinks->push_back(sink);
        return ReferenceCommand::Cancel(
            [command_cancellations]() { ++*command_cancellations; });
      });
  std::vector<std::string> command_successes;
  command.onSuccess([&](std::string value) {
    command_successes.push_back(std::move(value));
  });
  const cbss::CommandTicket command_first = command.run(1);
  const cbss::CommandTicket command_second = command.run(2);
  const bool command_first_cancelled =
      command_first.status() == cbss::CommandStatus::cancelled;
  (*command_sinks)[0].succeed("stale");
  (*command_sinks)[1].succeed("current");
  command.pump();
  const bool command_second_succeeded =
      command_second.status() == cbss::CommandStatus::succeeded;
  const bool command_stale_ignored =
      command_successes == std::vector<std::string>({"current"});
  const cbss::CommandTicket command_third = command.run(3);
  const ReferenceSink command_late_sink = (*command_sinks)[2];
  command.dispose();
  const bool command_third_cancelled =
      command_third.status() == cbss::CommandStatus::cancelled;
  const bool command_late_disposed =
      command_late_sink.succeed("late") == cbss::CommandOfferResult::disposed;

  const std::shared_ptr<std::vector<cbss::CueCompletion>> cue_completions =
      std::make_shared<std::vector<cbss::CueCompletion>>();
  const std::shared_ptr<int> cue_cancellations = std::make_shared<int>(0);
  int cue_tail_runs = 0;
  cbss::CueGraph cue_graph = cbss::cue(cbss::cueAction(
      "pending", [cue_completions, cue_cancellations](
                     cbss::CueCompletion completion) {
        cue_completions->push_back(completion);
        return cbss::CueCancel(
            [cue_cancellations]() { ++*cue_cancellations; });
      }));
  cue_graph.then(cbss::cueAction("tail", [&]() { ++cue_tail_runs; }));
  cbss::CueRuntime cue_runtime;
  const cbss::CueSession cue_session = cue_runtime.start(cue_graph);
  const bool cue_cancelled = cue_runtime.cancel(cue_session);
  (*cue_completions)[0].succeed();
  const bool cue_late_ignored =
      cue_tail_runs == 0 &&
      cue_session.status() == cbss::CueSessionStatus::cancelled;

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
  output << "command.first-cancelled=" << (command_first_cancelled ? 1 : 0)
         << '\n';
  output << "command.second-succeeded=" << (command_second_succeeded ? 1 : 0)
         << '\n';
  output << "command.third-cancelled=" << (command_third_cancelled ? 1 : 0)
         << '\n';
  output << "command.cancel-count=" << *command_cancellations << '\n';
  output << "command.stale-ignored=" << (command_stale_ignored ? 1 : 0)
         << '\n';
  output << "command.late-disposed=" << (command_late_disposed ? 1 : 0)
         << '\n';
  output << "cue.cancelled=" << (cue_cancelled ? 1 : 0) << '\n';
  output << "cue.cancel-count=" << *cue_cancellations << '\n';
  output << "cue.late-ignored=" << (cue_late_ignored ? 1 : 0) << '\n';
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
