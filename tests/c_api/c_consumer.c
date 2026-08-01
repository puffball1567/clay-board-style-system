#include "cbss.h"

#include <assert.h>
#include <stddef.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(CbssRect) == 16, "CbssRect ABI changed");
_Static_assert(sizeof(CbssColor) == 16, "CbssColor ABI changed");
_Static_assert(sizeof(CbssLayoutBox) == 24, "CbssLayoutBox ABI changed");
_Static_assert(sizeof(CbssHitResult) == 24, "CbssHitResult ABI changed");
_Static_assert(sizeof(CbssPaintCommand) == 64,
               "CbssPaintCommand ABI changed");
_Static_assert(sizeof(CbssTextStyle) == 24, "CbssTextStyle ABI changed");
_Static_assert(sizeof(CbssGradientStop) == 20,
               "CbssGradientStop ABI changed");
_Static_assert(sizeof(CbssTransformOperation) == 36,
               "CbssTransformOperation ABI changed");
_Static_assert(sizeof(CbssInputEvent) == 48,
               "CbssInputEvent ABI changed");
_Static_assert(sizeof(CbssEvent) == 64, "CbssEvent ABI changed");
_Static_assert(sizeof(CbssDispatchSummary) == 12,
               "CbssDispatchSummary ABI changed");
_Static_assert(sizeof(CbssScrollMetrics) == 36,
               "CbssScrollMetrics ABI changed");
_Static_assert(sizeof(CbssAccessibility) == 32,
               "CbssAccessibility ABI changed");
_Static_assert(offsetof(CbssPaintCommand, string_bytes) == 60,
               "CbssPaintCommand ABI changed");

typedef struct CallbackState {
  uint32_t label;
  uint32_t child;
  int child_clicks;
  int root_clicks;
  int focus_events;
  int text_events;
} CallbackState;

static void require_ok(CbssContext *context, CbssStatus status) {
  if (status == CBSS_OK) {
    return;
  }
  char message[512];
  cbss_context_last_error(context, message, sizeof(message));
  fprintf(stderr, "CBSS error %d: %s\n", status, message);
  assert(status == CBSS_OK);
}

static uint8_t handle_event(
    CbssContext *context, const CbssEvent *event, void *user_data) {
  CallbackState *state = user_data;
  assert(event->target != CBSS_NODE_NONE);
  if (event->kind == CBSS_EVENT_CLICK) {
    if (event->current_target == state->child) {
      ++state->child_clicks;
      require_ok(context, cbss_node_set_text(
          context, state->label, "Clicked from C"));
    } else {
      ++state->root_clicks;
    }
  } else if (event->kind == CBSS_EVENT_FOCUS) {
    ++state->focus_events;
  } else if (event->kind == CBSS_EVENT_BEFORE_INPUT ||
             event->kind == CBSS_EVENT_TEXT_INPUT ||
             event->kind == CBSS_EVENT_INPUT ||
             event->kind == CBSS_EVENT_CHANGE) {
    assert((event->flags & CBSS_EVENT_HAS_TEXT) != 0);
    assert(strcmp(event->text, "x") == 0);
    ++state->text_events;
  }
  return 0;
}

int main(void) {
  assert(cbss_abi_version() == CBSS_ABI_VERSION);

  CbssContext *context = cbss_context_create();
  CbssStyle *root_style = cbss_style_create();
  CbssStyle *child_style = cbss_style_create();
  assert(context != NULL);
  assert(root_style != NULL);
  assert(child_style != NULL);

  uint32_t root = cbss_context_add_box(context, CBSS_NODE_NONE, "root");
  uint32_t child = cbss_context_add_box(context, root, "child");
  uint32_t label = cbss_context_add_text(context, child, "C ABI", "label");
  uint32_t sibling = cbss_context_add_box(context, root, "sibling");
  assert(root != CBSS_NODE_NONE);
  assert(child != CBSS_NODE_NONE);
  assert(label != CBSS_NODE_NONE);
  assert(sibling != CBSS_NODE_NONE);
  assert(cbss_node_kind(context, root) == CBSS_NODE_BOX);
  assert(cbss_node_kind(context, label) == CBSS_NODE_TEXT);
  assert(cbss_node_parent(context, label) == child);
  assert(cbss_node_child_count(context, root) == 2);
  assert(cbss_node_child(context, root, 0) == child);
  char identifier[32];
  assert(cbss_node_identifier(
      context, child, identifier, sizeof(identifier)) == 5);
  assert(strcmp(identifier, "child") == 0);

  assert(cbss_style_set_length(
      root_style, "width", CBSS_UNIT_PX, 200.0f) == CBSS_OK);
  assert(cbss_style_set_length(
      root_style, "height", CBSS_UNIT_PX, 80.0f) == CBSS_OK);
  assert(cbss_style_set_keyword(
      root_style, "flex-direction", "row") == CBSS_OK);
  assert(cbss_style_set_length(
      root_style, "padding", CBSS_UNIT_PX, 10.0f) == CBSS_OK);
  assert(cbss_style_set_color(
      root_style, "background-color",
      (CbssColor){0.1f, 0.2f, 0.3f, 1.0f}) == CBSS_OK);
  CbssGradientStop gradient[] = {
      {{0.1f, 0.2f, 0.3f, 1.0f}, 0.0f},
      {{0.3f, 0.4f, 0.5f, 1.0f}, 1.0f}
  };
  assert(cbss_style_set_linear_gradient(
      root_style, "background-image", 90.0f, gradient, 2) == CBSS_OK);

  assert(cbss_style_set_length(
      child_style, "width", CBSS_UNIT_PX, 40.0f) == CBSS_OK);
  assert(cbss_style_set_length(
      child_style, "height", CBSS_UNIT_PX, 30.0f) == CBSS_OK);
  assert(cbss_style_set_color(
      child_style, "color",
      (CbssColor){1.0f, 1.0f, 1.0f, 1.0f}) == CBSS_OK);
  assert(cbss_style_set_border(
      child_style, "border",
      CBSS_BORDER_HAS_WIDTH | CBSS_BORDER_HAS_STYLE |
          CBSS_BORDER_HAS_COLOR,
      CBSS_UNIT_PX, 1.0f, "solid",
      (CbssColor){0.8f, 0.8f, 0.8f, 1.0f}) == CBSS_OK);
  assert(cbss_style_set_shadow(
      child_style, "box-shadow",
      CBSS_UNIT_PX, 0.0f, CBSS_UNIT_PX, 1.0f,
      CBSS_SHADOW_HAS_BLUR | CBSS_SHADOW_HAS_COLOR,
      CBSS_UNIT_PX, 2.0f, CBSS_UNIT_PX, 0.0f,
      (CbssColor){0.0f, 0.0f, 0.0f, 0.25f}) == CBSS_OK);
  CbssTransformOperation identity = {
      .kind = CBSS_TRANSFORM_SCALE,
      .flags = CBSS_TRANSFORM_HAS_X | CBSS_TRANSFORM_HAS_Y,
      .x = 1.0f,
      .y = 1.0f
  };
  assert(cbss_style_set_transform(
      child_style, "transform", &identity, 1) == CBSS_OK);

  require_ok(context, cbss_node_apply_style(
      context, root, root_style, 0, 0));
  require_ok(context, cbss_node_apply_style(
      context, child, child_style, 0, 0));
  require_ok(context, cbss_node_apply_style(
      context, sibling, child_style, 0, 0));
  require_ok(context, cbss_node_set_focusable(context, child, 1, 0));
  require_ok(context, cbss_node_set_focusable(context, sibling, 1, 0));
  require_ok(context, cbss_node_set_accessibility(
      context, child, CBSS_ROLE_BUTTON, "C button", "Runs the C action"));
  require_ok(context, cbss_node_set_accessibility(
      context, sibling, CBSS_ROLE_LINK, "C link", "Opens a destination"));
  require_ok(context, cbss_node_set_accessible_value(
      context, child, "ready"));

  CallbackState callback_state = {
      .label = label,
      .child = child
  };
  require_ok(context, cbss_node_set_event_handler(
      context, child, CBSS_EVENT_CLICK, handle_event, &callback_state));
  require_ok(context, cbss_node_set_event_handler(
      context, root, CBSS_EVENT_CLICK, handle_event, &callback_state));
  require_ok(context, cbss_node_set_event_handler(
      context, child, CBSS_EVENT_FOCUS, handle_event, &callback_state));
  require_ok(context, cbss_node_set_event_handler(
      context, child, CBSS_EVENT_BEFORE_INPUT,
      handle_event, &callback_state));
  require_ok(context, cbss_node_set_event_handler(
      context, child, CBSS_EVENT_TEXT_INPUT, handle_event, &callback_state));
  require_ok(context, cbss_node_set_event_handler(
      context, child, CBSS_EVENT_INPUT, handle_event, &callback_state));
  require_ok(context, cbss_node_set_event_handler(
      context, child, CBSS_EVENT_CHANGE, handle_event, &callback_state));
  require_ok(context, cbss_context_compute(context, 200.0f, 80.0f));

  CbssAccessibility accessibility;
  require_ok(context, cbss_node_accessibility(
      context, child, &accessibility));
  assert(accessibility.role == CBSS_ROLE_BUTTON);
  char accessible_name[32];
  assert(cbss_node_accessible_name(
      context, child, accessible_name, sizeof(accessible_name)) == 8);
  assert(strcmp(accessible_name, "C button") == 0);
  require_ok(context, cbss_node_accessibility(
      context, sibling, &accessibility));
  assert(accessibility.role == CBSS_ROLE_LINK);

  CbssRect child_rect;
  require_ok(context, cbss_node_layout_rect(context, child, &child_rect));
  assert(fabsf(child_rect.x - 10.0f) < 0.01f);
  assert(fabsf(child_rect.y - 10.0f) < 0.01f);
  assert(fabsf(child_rect.w - 40.0f) < 0.01f);
  assert(fabsf(child_rect.h - 30.0f) < 0.01f);

  assert(cbss_style_set_length(
      child_style, "width", CBSS_UNIT_PX, 60.0f) == CBSS_OK);
  require_ok(context, cbss_context_compute(context, 200.0f, 80.0f));
  require_ok(context, cbss_node_layout_rect(context, child, &child_rect));
  assert(fabsf(child_rect.w - 40.0f) < 0.01f);
  require_ok(context, cbss_node_apply_style(
      context, sibling, child_style, 0, 0));
  require_ok(context, cbss_context_recompute(context));
  CbssRect sibling_rect;
  require_ok(context, cbss_node_layout_rect(
      context, sibling, &sibling_rect));
  assert(fabsf(sibling_rect.w - 60.0f) < 0.01f);

  CbssHitResult hit;
  require_ok(context, cbss_context_hit_test(context, 12.0f, 12.0f, &hit));
  assert(hit.node == label || hit.node == child);

  uint32_t command_count = cbss_context_paint_command_count(context);
  assert(command_count > 0);
  int found_text = 0;
  for (uint32_t i = 0; i < command_count; ++i) {
    CbssPaintCommand command;
    require_ok(context, cbss_context_paint_command(context, i, &command));
    if (command.kind == CBSS_PAINT_DRAW_TEXT) {
      char text[32];
      assert(cbss_paint_command_string(context, i, text, sizeof(text)) == 5);
      assert(strcmp(text, "C ABI") == 0);
      found_text = 1;
    }
  }
  assert(found_text);

  CbssDispatchSummary dispatch;
  CbssInputEvent pointer_down = {
      .kind = CBSS_EVENT_POINTER_DOWN,
      .flags = CBSS_INPUT_HAS_POSITION | CBSS_INPUT_HAS_BUTTON,
      .button = 0,
      .x = 12.0f,
      .y = 12.0f
  };
  require_ok(context, cbss_context_dispatch_input(
      context, &pointer_down, &dispatch));
  assert(dispatch.focus_changed);
  assert(dispatch.needs_compute);
  assert(cbss_context_focused_node(context) == child);
  assert(callback_state.focus_events == 1);
  require_ok(context, cbss_context_recompute(context));

  CbssInputEvent pointer_up = pointer_down;
  pointer_up.kind = CBSS_EVENT_POINTER_UP;
  require_ok(context, cbss_context_dispatch_input(
      context, &pointer_up, &dispatch));
  assert(callback_state.child_clicks == 1);
  assert(callback_state.root_clicks == 1);
  assert(dispatch.needs_compute);
  require_ok(context, cbss_context_recompute(context));

  CbssInputEvent text_input = {
      .kind = CBSS_EVENT_TEXT_INPUT,
      .flags = CBSS_INPUT_HAS_TEXT,
      .text = "x"
  };
  require_ok(context, cbss_context_dispatch_input(
      context, &text_input, &dispatch));
  assert(callback_state.text_events == 4);

  CbssInputEvent tab = {
      .kind = CBSS_EVENT_KEY_DOWN,
      .flags = CBSS_INPUT_HAS_KEY,
      .key = "Tab"
  };
  require_ok(context, cbss_context_dispatch_input(context, &tab, &dispatch));
  assert(dispatch.focus_changed);
  assert(cbss_context_focused_node(context) == sibling);
  require_ok(context, cbss_context_recompute(context));
  require_ok(context, cbss_node_clear_style(context, sibling, 0, 0));
  assert(cbss_node_clear_style(
      context, sibling, 0, 0) == CBSS_OUT_OF_RANGE);

  cbss_style_destroy(child_style);
  cbss_style_destroy(root_style);
  cbss_context_destroy(context);

  CbssContext *invalid_context = cbss_context_create();
  CbssStyle *invalid_style = cbss_style_create();
  assert(invalid_context != NULL);
  assert(invalid_style != NULL);
  uint32_t invalid_root = cbss_context_add_box(
      invalid_context, CBSS_NODE_NONE, "invalid-root");
  assert(cbss_style_set_keyword(
      invalid_style, "property-that-does-not-exist", "value") == CBSS_OK);
  assert(cbss_node_apply_style(
      invalid_context, invalid_root, invalid_style, 0, 0) == CBSS_OK);
  assert(cbss_context_compute(
      invalid_context, 100.0f, 100.0f) == CBSS_STYLE_ERROR);
  assert(cbss_context_diagnostic_count(invalid_context) > 0);
  char error[256];
  assert(cbss_context_last_error(
      invalid_context, error, sizeof(error)) > 0);
  assert(strstr(error, "unknown style property") != NULL);
  cbss_style_destroy(invalid_style);
  cbss_context_destroy(invalid_context);

  CbssContext *scroll_context = cbss_context_create();
  CbssStyle *scroll_style = cbss_style_create();
  CbssStyle *content_style = cbss_style_create();
  assert(scroll_context != NULL);
  assert(scroll_style != NULL);
  assert(content_style != NULL);
  uint32_t scroll_root = cbss_context_add_box(
      scroll_context, CBSS_NODE_NONE, "scroll-root");
  uint32_t scroll_content = cbss_context_add_box(
      scroll_context, scroll_root, "scroll-content");
  assert(scroll_root != CBSS_NODE_NONE);
  assert(scroll_content != CBSS_NODE_NONE);
  assert(cbss_style_set_length(
      scroll_style, "width", CBSS_UNIT_PX, 100.0f) == CBSS_OK);
  assert(cbss_style_set_length(
      scroll_style, "height", CBSS_UNIT_PX, 40.0f) == CBSS_OK);
  assert(cbss_style_set_keyword(
      scroll_style, "overflow-y", "scroll") == CBSS_OK);
  assert(cbss_style_set_length(
      content_style, "width", CBSS_UNIT_PX, 100.0f) == CBSS_OK);
  assert(cbss_style_set_length(
      content_style, "height", CBSS_UNIT_PX, 100.0f) == CBSS_OK);
  assert(cbss_style_set_number(
      content_style, "flex-shrink", 0.0f) == CBSS_OK);
  require_ok(scroll_context, cbss_node_apply_style(
      scroll_context, scroll_root, scroll_style, 0, 0));
  require_ok(scroll_context, cbss_node_apply_style(
      scroll_context, scroll_content, content_style, 0, 0));
  require_ok(scroll_context, cbss_context_compute(
      scroll_context, 100.0f, 40.0f));

  CbssScrollMetrics metrics;
  require_ok(scroll_context, cbss_node_scroll_metrics(
      scroll_context, scroll_root, &metrics));
  assert(fabsf(metrics.max_offset_y - 60.0f) < 0.01f);
  CbssInputEvent wheel = {
      .kind = CBSS_EVENT_WHEEL,
      .flags = CBSS_INPUT_HAS_POSITION | CBSS_INPUT_HAS_DELTA,
      .x = 10.0f,
      .y = 10.0f,
      .delta_y = 15.0f
  };
  require_ok(scroll_context, cbss_context_dispatch_input(
      scroll_context, &wheel, &dispatch));
  assert(dispatch.paint_changed);
  assert(!dispatch.needs_compute);
  require_ok(scroll_context, cbss_node_scroll_metrics(
      scroll_context, scroll_root, &metrics));
  assert(fabsf(metrics.offset_y - 15.0f) < 0.01f);
  require_ok(scroll_context, cbss_node_set_scrolling(
      scroll_context, scroll_root, 0));
  cbss_style_destroy(content_style);
  cbss_style_destroy(scroll_style);
  cbss_context_destroy(scroll_context);

  for (int i = 0; i < 100; ++i) {
    CbssContext *short_lived = cbss_context_create();
    CbssStyle *short_style = cbss_style_create();
    assert(short_lived != NULL);
    assert(short_style != NULL);
    cbss_style_destroy(short_style);
    cbss_context_destroy(short_lived);
  }
  return 0;
}
