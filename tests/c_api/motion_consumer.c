#include "cbss.h"

#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

_Static_assert(CBSS_ABI_VERSION == 0x00010015u,
    "unexpected CBSS ABI version");
_Static_assert(sizeof(CbssEvent) == 152, "CbssEvent ABI changed");
_Static_assert(sizeof(CbssMotionState) == 40,
               "CbssMotionState ABI changed");

typedef struct MotionEvents {
  int animation_starts;
  int animation_iterations;
  int animation_ends;
  int animation_cancels;
  int transition_runs;
  int transition_starts;
  int transition_ends;
  int transition_cancels;
  int invalid_payloads;
  int view_starts;
} MotionEvents;

static uint8_t on_motion_view(
    CbssContext *context, const CbssEventView *view, void *user_data) {
  MotionEvents *events = (MotionEvents *)user_data;
  const CbssEvent *event = cbss_event_view_event(view);
  (void)context;
  assert(event != NULL);
  assert(event->kind == CBSS_EVENT_ANIMATION_START);
  assert((event->flags & CBSS_EVENT_HAS_MOTION) != 0);
  assert(event->motion_name != NULL);
  assert(strcmp(event->motion_name, "pulse") == 0);
  events->view_starts += 1;
  return CBSS_EVENT_OUTCOME_HANDLED;
}

static uint8_t on_motion(
    CbssContext *context, const CbssEvent *event, void *user_data) {
  MotionEvents *events = (MotionEvents *)user_data;
  (void)context;
  if ((event->flags & CBSS_EVENT_HAS_MOTION) == 0 ||
      event->motion_name == NULL || event->motion_name[0] == '\0' ||
      event->motion_elapsed_seconds < 0.0) {
    events->invalid_payloads += 1;
  }
  switch (event->kind) {
    case CBSS_EVENT_ANIMATION_START:
      events->animation_starts += 1;
      assert(strcmp(event->motion_name, "pulse") == 0);
      break;
    case CBSS_EVENT_ANIMATION_ITERATION:
      events->animation_iterations += 1;
      assert(event->motion_iteration == 1);
      break;
    case CBSS_EVENT_ANIMATION_END:
      events->animation_ends += 1;
      break;
    case CBSS_EVENT_ANIMATION_CANCEL:
      events->animation_cancels += 1;
      break;
    case CBSS_EVENT_TRANSITION_RUN:
      events->transition_runs += 1;
      assert(strcmp(event->motion_name, "opacity") == 0);
      break;
    case CBSS_EVENT_TRANSITION_START:
      events->transition_starts += 1;
      break;
    case CBSS_EVENT_TRANSITION_END:
      events->transition_ends += 1;
      break;
    case CBSS_EVENT_TRANSITION_CANCEL:
      events->transition_cancels += 1;
      break;
    default:
      assert(0 && "unexpected motion event");
  }
  return CBSS_EVENT_OUTCOME_HANDLED;
}

static void subscribe_motion(
    CbssContext *context, uint32_t node, MotionEvents *events) {
  const uint32_t kinds[] = {
    CBSS_EVENT_ANIMATION_START,
    CBSS_EVENT_ANIMATION_ITERATION,
    CBSS_EVENT_ANIMATION_END,
    CBSS_EVENT_ANIMATION_CANCEL,
    CBSS_EVENT_TRANSITION_RUN,
    CBSS_EVENT_TRANSITION_START,
    CBSS_EVENT_TRANSITION_END,
    CBSS_EVENT_TRANSITION_CANCEL
  };
  for (size_t index = 0; index < sizeof(kinds) / sizeof(kinds[0]); ++index) {
    CbssEventSubscription subscription = 0;
    assert(cbss_node_subscribe_event(
      context, node, kinds[index], on_motion, events, &subscription
    ) == CBSS_OK);
    assert(subscription != 0);
  }
  CbssEventSubscription view_subscription = 0;
  assert(cbss_node_subscribe_event_view(
    context, node, CBSS_EVENT_ANIMATION_START, on_motion_view, events,
    &view_subscription
  ) == CBSS_OK);
  assert(view_subscription != 0);
}

static float painted_alpha(CbssContext *context, uint32_t owner) {
  const uint32_t count = cbss_context_paint_command_count(context);
  for (uint32_t index = 0; index < count; ++index) {
    CbssPaintCommand command;
    assert(cbss_context_paint_command(context, index, &command) == CBSS_OK);
    if (command.kind == CBSS_PAINT_FILL_RECT && command.owner == owner) {
      return command.color.a;
    }
  }
  return 1.0f;
}

static CbssStyle *box_style(float opacity) {
  CbssStyle *style = cbss_style_create();
  assert(style != NULL);
  assert(cbss_style_set_length(style, "width", CBSS_UNIT_PX, 100) == CBSS_OK);
  assert(cbss_style_set_length(style, "height", CBSS_UNIT_PX, 60) == CBSS_OK);
  assert(cbss_style_set_color(
    style, "background-color", (CbssColor){0.2f, 0.4f, 0.8f, 1.0f}
  ) == CBSS_OK);
  assert(cbss_style_set_number(style, "opacity", opacity) == CBSS_OK);
  return style;
}

static float first_transform_x(CbssContext *context) {
  const uint32_t count = cbss_context_paint_command_count(context);
  for (uint32_t index = 0; index < count; ++index) {
    CbssPaintCommand command;
    assert(cbss_context_paint_command(context, index, &command) == CBSS_OK);
    if (command.kind == CBSS_PAINT_PUSH_TRANSFORM) {
      CbssAffineTransform transform;
      assert(cbss_paint_command_transform(
        context, index, &transform
      ) == CBSS_OK);
      return transform.tx;
    }
  }
  return 0.0f;
}

static CbssKeyframes *pulse_keyframes(void) {
  CbssKeyframes *keyframes = NULL;
  CbssStyle *step = cbss_style_create();
  assert(step != NULL);
  assert(cbss_keyframes_create("pulse", &keyframes) == CBSS_OK);
  assert(keyframes != NULL);
  assert(cbss_style_set_number(step, "opacity", 0.2f) == CBSS_OK);
  assert(cbss_keyframes_add_step(keyframes, 0.0, step) == CBSS_OK);
  assert(cbss_style_clear(step) == CBSS_OK);
  assert(cbss_style_set_number(step, "opacity", 1.0f) == CBSS_OK);
  assert(cbss_keyframes_add_step(keyframes, 1.0, step) == CBSS_OK);
  cbss_style_destroy(step);
  return keyframes;
}

static CbssKeyframes *move_keyframes(void) {
  CbssKeyframes *keyframes = NULL;
  CbssStyle *step = cbss_style_create();
  CbssTransformOperation operation = {
    .kind = CBSS_TRANSFORM_TRANSLATE,
    .flags = CBSS_TRANSFORM_HAS_X | CBSS_TRANSFORM_HAS_Y,
    .x_unit = CBSS_UNIT_PX,
    .y_unit = CBSS_UNIT_PX,
    .x = 0.0f,
    .y = 0.0f
  };
  assert(step != NULL);
  assert(cbss_keyframes_create("move", &keyframes) == CBSS_OK);
  assert(cbss_style_set_transform(
    step, "transform", &operation, 1
  ) == CBSS_OK);
  assert(cbss_keyframes_add_step(keyframes, 0.0, step) == CBSS_OK);
  operation.x = 40.0f;
  assert(cbss_style_set_transform(
    step, "transform", &operation, 1
  ) == CBSS_OK);
  assert(cbss_keyframes_add_step(keyframes, 1.0, step) == CBSS_OK);
  cbss_style_destroy(step);
  return keyframes;
}

int main(void) {
  assert(cbss_abi_version() == CBSS_ABI_VERSION);
  CbssContext *context = cbss_context_create();
  assert(context != NULL);
  const uint32_t root = cbss_context_add_box(
    context, CBSS_NODE_NONE, "root"
  );
  const uint32_t animated = cbss_context_add_box(
    context, root, "animated"
  );
  assert(root != CBSS_NODE_NONE && animated != CBSS_NODE_NONE);

  MotionEvents events = {0};
  subscribe_motion(context, animated, &events);

  CbssKeyframes *keyframes = pulse_keyframes();
  assert(cbss_context_register_keyframes(context, keyframes) == CBSS_OK);
  assert(cbss_context_has_keyframes(context, "pulse") == 1);
  cbss_keyframes_destroy(keyframes);

  CbssStyle *animated_style = box_style(1.0f);
  assert(cbss_style_set_keyword(
    animated_style, "animation-name", "pulse"
  ) == CBSS_OK);
  assert(cbss_style_set_number(
    animated_style, "animation-duration", 1.0f
  ) == CBSS_OK);
  assert(cbss_style_set_number(
    animated_style, "animation-iteration-count", 2.0f
  ) == CBSS_OK);
  assert(cbss_style_set_keyword(
    animated_style, "animation-timing-function", "linear"
  ) == CBSS_OK);
  assert(cbss_style_set_keyword(
    animated_style, "animation-fill-mode", "forwards"
  ) == CBSS_OK);
  assert(cbss_node_apply_style(
    context, animated, animated_style, 0, 0
  ) == CBSS_OK);
  cbss_style_destroy(animated_style);

  assert(cbss_context_compute_at(context, 320, 180, 10.0) == CBSS_OK);
  CbssMotionState state;
  assert(cbss_context_motion_state(context, &state) == CBSS_OK);
  assert(state.active_animations == 1);
  assert(state.active_transitions == 0);
  assert(state.has_deadline == 1);
  assert(state.next_deadline > 10.0);
  assert(events.animation_starts == 1);
  assert(events.view_starts == 1);
  assert(fabsf(painted_alpha(context, animated) - 0.2f) < 0.03f);

  assert(cbss_context_advance_motion(context, 10.5, &state) == CBSS_OK);
  assert(state.sampled_animations == 1);
  assert((state.dirty_domains & CBSS_DIRTY_PAINT) != 0);
  assert((state.dirty_domains & CBSS_DIRTY_ANIMATION) != 0);
  assert(fabsf(painted_alpha(context, animated) - 0.6f) < 0.05f);

  assert(cbss_context_advance_motion(context, 11.0, &state) == CBSS_OK);
  assert(events.animation_iterations == 1);
  assert(cbss_context_advance_motion(context, 12.0, &state) == CBSS_OK);
  assert(state.active_animations == 0);
  assert(state.has_deadline == 0);
  assert(events.animation_ends == 1);
  assert(fabsf(painted_alpha(context, animated) - 1.0f) < 0.03f);

  assert(cbss_node_clear_style(context, animated, 0, 0) == CBSS_OK);
  CbssStyle *base = box_style(0.2f);
  assert(cbss_node_apply_style(context, animated, base, 0, 0) == CBSS_OK);
  cbss_style_destroy(base);

  CbssStyle *hover = box_style(1.0f);
  assert(cbss_style_set_keyword(
    hover, "transition-property", "opacity"
  ) == CBSS_OK);
  assert(cbss_style_set_number(
    hover, "transition-duration", 1.0f
  ) == CBSS_OK);
  assert(cbss_style_set_keyword(
    hover, "transition-timing-function", "linear"
  ) == CBSS_OK);
  assert(cbss_node_apply_style(
    context, animated, hover, 1u << CBSS_STATE_HOVER, 1
  ) == CBSS_OK);
  cbss_style_destroy(hover);

  assert(cbss_context_compute_at(context, 320, 180, 20.0) == CBSS_OK);
  assert(cbss_node_set_state(context, animated, CBSS_STATE_HOVER, 1) == CBSS_OK);
  assert(cbss_context_recompute_at(context, 20.0) == CBSS_OK);
  assert(cbss_context_motion_state(context, &state) == CBSS_OK);
  assert(state.active_transitions == 1);
  assert(events.transition_runs >= 1);
  assert(events.transition_starts >= 1);
  assert(cbss_context_advance_motion(context, 20.5, &state) == CBSS_OK);
  assert(state.sampled_transitions == 1);
  assert(fabsf(painted_alpha(context, animated) - 0.6f) < 0.05f);

  CbssStyle *base_with_transition = box_style(0.2f);
  assert(cbss_style_set_keyword(
    base_with_transition, "transition-property", "opacity"
  ) == CBSS_OK);
  assert(cbss_style_set_number(
    base_with_transition, "transition-duration", 1.0f
  ) == CBSS_OK);
  assert(cbss_style_set_keyword(
    base_with_transition, "transition-timing-function", "linear"
  ) == CBSS_OK);
  assert(cbss_node_apply_style(
    context, animated, base_with_transition, 0, 0
  ) == CBSS_OK);
  cbss_style_destroy(base_with_transition);
  assert(cbss_node_set_state(context, animated, CBSS_STATE_HOVER, 0) == CBSS_OK);
  assert(cbss_context_recompute_at(context, 20.5) == CBSS_OK);
  assert(cbss_context_motion_state(context, &state) == CBSS_OK);
  assert(state.active_transitions == 1);
  assert(events.transition_cancels >= 1);
  assert(cbss_context_advance_motion(context, 21.0, &state) == CBSS_OK);
  assert(fabsf(painted_alpha(context, animated) - 0.4f) < 0.05f);
  assert(cbss_context_advance_motion(context, 21.5, &state) == CBSS_OK);
  assert(state.active_transitions == 0);
  assert(events.transition_ends >= 1);

  assert(cbss_node_set_state(context, animated, CBSS_STATE_HOVER, 1) == CBSS_OK);
  assert(cbss_context_recompute_at(context, 22.0) == CBSS_OK);
  assert(cbss_context_motion_state(context, &state) == CBSS_OK);
  assert(state.active_transitions == 1);
  assert(cbss_context_set_reduced_motion(context, 1) == CBSS_OK);
  assert(cbss_context_motion_state(context, &state) == CBSS_OK);
  assert(state.reduced_motion == 1);
  assert(state.active_transitions == 0);

  keyframes = pulse_keyframes();
  assert(cbss_context_register_keyframes(context, keyframes) == CBSS_OK);
  cbss_keyframes_destroy(keyframes);
  CbssStyle *animation_again = box_style(1.0f);
  assert(cbss_style_set_keyword(
    animation_again, "animation-name", "pulse"
  ) == CBSS_OK);
  assert(cbss_style_set_number(
    animation_again, "animation-duration", 10.0f
  ) == CBSS_OK);
  assert(cbss_node_clear_style(context, animated, 0, 0) == CBSS_OK);
  assert(cbss_node_apply_style(
    context, animated, animation_again, 0, 0
  ) == CBSS_OK);
  cbss_style_destroy(animation_again);
  assert(cbss_context_set_reduced_motion(context, 0) == CBSS_OK);
  assert(cbss_context_recompute_at(context, 30.0) == CBSS_OK);
  assert(cbss_context_unregister_keyframes(context, "pulse") == CBSS_OK);
  assert(cbss_context_has_keyframes(context, "pulse") == 0);
  assert(events.animation_cancels >= 1);

  CbssKeyframes *invalid = NULL;
  assert(cbss_keyframes_create("", &invalid) == CBSS_INVALID_ARGUMENT);
  assert(cbss_keyframes_create("bad", &invalid) == CBSS_OK);
  assert(cbss_context_register_keyframes(
    context, invalid
  ) == CBSS_INVALID_ARGUMENT);
  CbssStyle *invalid_step = cbss_style_create();
  assert(invalid_step != NULL);
  assert(cbss_style_set_length(
    invalid_step, "width", CBSS_UNIT_PX, 10
  ) == CBSS_OK);
  assert(cbss_keyframes_add_step(
    invalid, 0.0, invalid_step
  ) == CBSS_STYLE_ERROR);
  assert(cbss_style_clear(invalid_step) == CBSS_OK);
  assert(cbss_style_set_number(invalid_step, "opacity", 1) == CBSS_OK);
  assert(cbss_keyframes_add_step(
    invalid, 0.7, invalid_step
  ) == CBSS_OK);
  assert(cbss_keyframes_add_step(
    invalid, 0.2, invalid_step
  ) == CBSS_INVALID_ARGUMENT);
  assert(cbss_context_register_keyframes(
    context, invalid
  ) == CBSS_OK);
  assert(cbss_context_advance_motion(
    context, 29.0, &state
  ) == CBSS_INVALID_ARGUMENT);
  assert(cbss_context_set_reduced_motion(context, 2) == CBSS_INVALID_ARGUMENT);
  cbss_style_destroy(invalid_step);
  cbss_keyframes_destroy(invalid);

  const uint32_t moving = cbss_context_add_box(context, root, "moving");
  assert(moving != CBSS_NODE_NONE);
  CbssKeyframes *move = move_keyframes();
  assert(cbss_context_register_keyframes(context, move) == CBSS_OK);
  cbss_keyframes_destroy(move);
  CbssStyle *moving_style = box_style(1.0f);
  assert(cbss_style_set_keyword(
    moving_style, "animation-name", "move"
  ) == CBSS_OK);
  assert(cbss_style_set_number(
    moving_style, "animation-duration", 1.0f
  ) == CBSS_OK);
  assert(cbss_style_set_keyword(
    moving_style, "animation-timing-function", "linear"
  ) == CBSS_OK);
  assert(cbss_node_apply_style(
    context, moving, moving_style, 0, 0
  ) == CBSS_OK);
  cbss_style_destroy(moving_style);
  assert(cbss_context_compute_at(context, 320, 240, 40.0) == CBSS_OK);
  assert(cbss_context_advance_motion(context, 40.5, &state) == CBSS_OK);
  assert(state.sampled_animations == 1);
  assert((state.dirty_domains & CBSS_DIRTY_HIT) != 0);
  assert(fabsf(first_transform_x(context) - 20.0f) < 0.1f);

  assert(events.invalid_payloads == 0);
  keyframes = pulse_keyframes();
  assert(cbss_context_register_keyframes(context, keyframes) == CBSS_OK);
  cbss_keyframes_destroy(keyframes);
  const int cancels_before_reset = events.animation_cancels;
  assert(cbss_context_recompute_at(context, 50.0) == CBSS_OK);
  assert(cbss_context_reset(context) == CBSS_OK);
  assert(events.animation_cancels == cancels_before_reset + 1);
  cbss_context_destroy(context);
  return 0;
}
