#include "cbss.h"

_Static_assert(CBSS_ABI_VERSION == 0x00010005u, "unexpected CBSS ABI version");

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
_Static_assert(sizeof(CbssAffineTransform) == 24,
               "CbssAffineTransform ABI changed");
_Static_assert(sizeof(CbssPathSegment) == 28,
               "CbssPathSegment ABI changed");
_Static_assert(sizeof(CbssTextStyle) == 24, "CbssTextStyle ABI changed");
_Static_assert(sizeof(CbssGradientStop) == 20,
               "CbssGradientStop ABI changed");
_Static_assert(sizeof(CbssColorValueGradientStop) == 16,
               "CbssColorValueGradientStop ABI changed");
_Static_assert(sizeof(CbssTransformOperation) == 36,
               "CbssTransformOperation ABI changed");
_Static_assert(sizeof(CbssPointerData) == 56,
               "CbssPointerData ABI changed");
_Static_assert(sizeof(CbssInputEvent) == 112,
               "CbssInputEvent ABI changed");
_Static_assert(sizeof(CbssEvent) == 128, "CbssEvent ABI changed");
_Static_assert(sizeof(CbssDispatchSummary) == 12,
               "CbssDispatchSummary ABI changed");
_Static_assert(sizeof(CbssScrollMetrics) == 36,
               "CbssScrollMetrics ABI changed");
_Static_assert(sizeof(CbssAccessibility) == 32,
               "CbssAccessibility ABI changed");
_Static_assert(sizeof(CbssRenderSurfacePlacement) == 40,
               "CbssRenderSurfacePlacement ABI changed");
_Static_assert(sizeof(CbssRenderSurfaceEvent) == 232,
               "CbssRenderSurfaceEvent ABI changed");
_Static_assert(offsetof(CbssPaintCommand, string_bytes) == 60,
               "CbssPaintCommand ABI changed");

typedef struct CallbackState {
  uint32_t label;
  uint32_t child;
  int child_clicks;
  int root_clicks;
  int focus_events;
  int text_events;
  int pen_events;
} CallbackState;

typedef struct SurfaceState {
  uint64_t surface;
  uint32_t node;
  int mounts;
  int updates;
  int resizes;
  int inputs;
  int frames;
  int visibility_changes;
  int device_lost;
  int device_restored;
  int unmounts;
  float local_x;
  float local_y;
  int draw_on_mount;
  int pen_inputs;
} SurfaceState;

static uint32_t handle_surface(
    CbssContext *context, const CbssRenderSurfaceEvent *event,
    void *user_data) {
  SurfaceState *state = user_data;
  assert(context != NULL);
  assert(event->api_version == 1);
  assert(event->surface == state->surface);
  switch (event->kind) {
    case CBSS_SURFACE_MOUNT:
      ++state->mounts;
      state->node = event->node;
      assert((event->flags & CBSS_SURFACE_VISIBLE) != 0);
      assert(event->placement.bounds.w > 0.0f);
      if (state->draw_on_mount) {
        uint64_t revision = 0;
        assert(cbss_render_surface_canvas_fill_rect(
            context, state->surface,
            (CbssRect){20.0f, 16.0f, 4.0f, 4.0f},
            (CbssColor){1.0f, 1.0f, 0.0f, 1.0f}, 0.0f) == CBSS_OK);
        assert(cbss_render_surface_canvas_commit(
            context, state->surface, &revision) == CBSS_OK);
        assert(revision == 2);
      }
      break;
    case CBSS_SURFACE_UPDATE:
      ++state->updates;
      break;
    case CBSS_SURFACE_RESIZE:
      ++state->resizes;
      assert(event->pixel_width >= event->logical_width);
      break;
    case CBSS_SURFACE_INPUT:
      ++state->inputs;
      if ((event->flags & CBSS_SURFACE_HAS_LOCAL_POSITION) != 0) {
        assert((event->flags & CBSS_SURFACE_INSIDE) != 0);
        state->local_x = event->local_x;
        state->local_y = event->local_y;
      }
      if ((event->input.flags & CBSS_INPUT_HAS_POINTER) != 0) {
        ++state->pen_inputs;
        assert(event->input.pointer.device == CBSS_POINTER_PEN_DIRECT);
        assert(event->input.timestamp == 9001);
        assert(event->input.pointer.device_id == 77);
        assert((event->input.pointer.axes & CBSS_POINTER_AXIS_PRESSURE) != 0);
        assert((event->input.pointer.axes & CBSS_POINTER_AXIS_TILT_X) != 0);
        assert(fabsf(event->input.pointer.pressure - 0.625f) < 0.001f);
        assert(fabsf(event->input.pointer.tilt_x + 18.0f) < 0.001f);
        assert(event->input.pointer.eraser == 1);
      }
      return CBSS_SURFACE_HANDLED;
    case CBSS_SURFACE_FRAME:
      ++state->frames;
      if (state->frames == 1) {
        return CBSS_SURFACE_REQUEST_NEXT_FRAME;
      }
      break;
    case CBSS_SURFACE_VISIBILITY:
      ++state->visibility_changes;
      break;
    case CBSS_SURFACE_DEVICE_LOST:
      ++state->device_lost;
      break;
    case CBSS_SURFACE_DEVICE_RESTORED:
      ++state->device_restored;
      break;
    case CBSS_SURFACE_UNMOUNT:
      ++state->unmounts;
      break;
    default:
      assert(0 && "unknown render surface event");
  }
  return 0;
}

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
  } else if (event->kind == CBSS_EVENT_PEN_BUTTON_DOWN) {
    assert((event->flags & CBSS_EVENT_HAS_POINTER) != 0);
    assert(event->pointer.device == CBSS_POINTER_PEN_DIRECT);
    assert(event->timestamp == 9002);
    assert(event->pointer.device_id == 77);
    assert((event->pointer.axes & CBSS_POINTER_AXIS_PRESSURE) != 0);
    assert(fabsf(event->pointer.pressure - 0.625f) < 0.001f);
    ++state->pen_events;
  }
  return 0;
}

int main(void) {
  assert(cbss_abi_version() == CBSS_ABI_VERSION);
  assert(CBSS_PAINT_PUSH_LAYER == 11);
  assert(CBSS_PAINT_POP_LAYER == 12);
  assert(CBSS_LAYER_SOURCE_OVER == 0);
  assert(CBSS_LAYER_COPY == 1);
  assert(CBSS_LAYER_ADDITIVE == 2);

  CbssContext *context = cbss_context_create();
  CbssStyle *root_style = cbss_style_create();
  CbssStyle *child_style = cbss_style_create();
  CbssStyle *surface_style = cbss_style_create();
  assert(context != NULL);
  assert(root_style != NULL);
  assert(child_style != NULL);
  assert(surface_style != NULL);

  SurfaceState surface_state = {.draw_on_mount = 1};
  assert(cbss_context_register_render_surface(
      context, "invalid", NULL, NULL,
      &surface_state.surface) == CBSS_INVALID_ARGUMENT);
  assert(cbss_context_register_render_surface(
      context, "invalid", handle_surface, &surface_state,
      NULL) == CBSS_INVALID_ARGUMENT);
  assert(cbss_context_register_render_surface(
      context, "c-surface", handle_surface, &surface_state,
      &surface_state.surface) == CBSS_OK);
  assert(surface_state.surface != 0);
  assert(cbss_render_surface_request_frame(
      context, UINT64_MAX) == CBSS_OUT_OF_RANGE);
  assert(cbss_render_surface_canvas_clear(
      context, UINT64_MAX) == CBSS_OUT_OF_RANGE);
  assert(cbss_render_surface_canvas_clear(
      NULL, surface_state.surface) == CBSS_INVALID_HANDLE);
  assert(cbss_render_surface_canvas_commit(
      NULL, surface_state.surface, NULL) == CBSS_INVALID_HANDLE);
  assert(cbss_render_surface_canvas_fill_rect(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, NAN, 10.0f},
      (CbssColor){1.0f, 0.0f, 0.0f, 1.0f}, 0.0f) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_fill_rect(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f},
      (CbssColor){NAN, 0.0f, 0.0f, 1.0f}, 0.0f) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_transform(
      context, surface_state.surface,
      (CbssAffineTransform){1.0f, 0.0f, 0.0f, NAN, 0.0f, 0.0f}) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_push_clip(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f}, -1.0f) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_begin_layer(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f},
      1.0f, UINT32_MAX) == CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_begin_layer(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f},
      1.01f, CBSS_LAYER_SOURCE_OVER) == CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_fill_linear_gradient(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f}, 0.0f,
      CBSS_COLOR_INTERPOLATE_SRGB, NULL, 1, 0.0f) ==
      CBSS_INVALID_ARGUMENT);
  CbssGradientStop invalid_canvas_stop = {
      {1.0f, 0.0f, 0.0f, 1.0f}, NAN
  };
  assert(cbss_render_surface_canvas_fill_linear_gradient(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f}, 0.0f,
      CBSS_COLOR_INTERPOLATE_SRGB, &invalid_canvas_stop, 1, 0.0f) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_stroke_rect(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f},
      (CbssColor){1.0f, 0.0f, 0.0f, 1.0f}, 0.0f, 0.0f) ==
      CBSS_INVALID_ARGUMENT);
  CbssPathSegment invalid_canvas_path = {
      .kind = UINT32_MAX,
      .endpoint_x = 1.0f,
      .endpoint_y = 1.0f
  };
  assert(cbss_render_surface_canvas_stroke_path(
      context, surface_state.surface, &invalid_canvas_path, 1,
      (CbssColor){1.0f, 0.0f, 0.0f, 1.0f}, 1.0f,
      CBSS_STROKE_CAP_BUTT, CBSS_STROKE_JOIN_MITER, 4.0f) ==
      CBSS_INVALID_ARGUMENT);
  CbssTextStyle invalid_canvas_text_style = {
      .flags = 1u << 31
  };
  assert(cbss_render_surface_canvas_draw_text(
      context, surface_state.surface, "invalid", 0.0f, 0.0f,
      (CbssColor){1.0f, 1.0f, 1.0f, 1.0f},
      &invalid_canvas_text_style, NULL, 0.0f, 0) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_draw_image(
      context, surface_state.surface, "",
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f}, 1.0f) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_render_surface_canvas_draw_image(
      context, surface_state.surface, "invalid.png",
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f}, 1.1f) ==
      CBSS_INVALID_ARGUMENT);
  assert(cbss_context_set_pixel_scale(context, 0.0f) == CBSS_INVALID_ARGUMENT);
  assert(cbss_context_set_pixel_scale(context, NAN) == CBSS_INVALID_ARGUMENT);

  CbssColorValue *red = NULL;
  CbssColorValue *blue = NULL;
  CbssColorValue *mixed = NULL;
  CbssColorValue *parsed_color = NULL;
  CbssColorValue *parsed_mix = NULL;
  CbssColorValue *contextual = NULL;
  assert(cbss_color_value_create(
      UINT32_MAX, 0.0f, 0.0f, 0.0f, 1.0f, 0,
      &parsed_color) == CBSS_INVALID_ARGUMENT);
  assert(parsed_color == NULL);
  assert(cbss_color_value_create(
      CBSS_COLOR_SRGB, 0.0f, 0.0f, 0.0f, 1.0f, 1u << 20,
      &parsed_color) == CBSS_INVALID_ARGUMENT);
  assert(parsed_color == NULL);
  assert(cbss_color_value_create(
      CBSS_COLOR_SRGB, 1.0f, 0.0f, 0.0f, 1.0f, 0, &red) == CBSS_OK);
  assert(cbss_color_value_create(
      CBSS_COLOR_SRGB, 0.0f, 0.0f, 1.0f, 1.0f, 0, &blue) == CBSS_OK);
  assert(red != NULL && blue != NULL);
  assert(cbss_color_mix_create(
      red, blue, CBSS_COLOR_INTERPOLATE_SRGB,
      CBSS_COLOR_MIX_HAS_FIRST_PERCENTAGE |
          CBSS_COLOR_MIX_HAS_SECOND_PERCENTAGE,
      25.0f, 75.0f, &mixed) == CBSS_OK);
  CbssColor resolved_color;
  assert(cbss_color_value_resolve(
      mixed, (CbssColor){0.0f, 0.0f, 0.0f, 1.0f},
      &resolved_color) == CBSS_OK);
  assert(fabsf(resolved_color.r - 0.25f) < 0.002f);
  assert(fabsf(resolved_color.g) < 0.002f);
  assert(fabsf(resolved_color.b - 0.75f) < 0.002f);
  assert(fabsf(resolved_color.a - 1.0f) < 0.002f);
  assert(cbss_color_mix_create(
      mixed, blue, CBSS_COLOR_INTERPOLATE_SRGB, 0,
      0.0f, 0.0f, &parsed_mix) == CBSS_INVALID_ARGUMENT);
  assert(parsed_mix == NULL);

  char color_error[128] = {0};
  assert(cbss_color_value_parse(
      "oklch(68% 0.17 245deg)", &parsed_color,
      color_error, sizeof(color_error)) == CBSS_OK);
  assert(parsed_color != NULL);
  assert(cbss_color_value_resolve(
      parsed_color, (CbssColor){0.0f, 0.0f, 0.0f, 1.0f},
      &resolved_color) == CBSS_OK);
  assert(isfinite(resolved_color.r));
  assert(isfinite(resolved_color.g));
  assert(isfinite(resolved_color.b));
  assert(cbss_color_mix_parse(
      "color-mix(in srgb, red 20%, blue 80%)", &parsed_mix,
      color_error, sizeof(color_error)) == CBSS_OK);
  assert(parsed_mix != NULL);
  assert(cbss_color_value_resolve(
      parsed_mix, (CbssColor){0.0f, 0.0f, 0.0f, 1.0f},
      &resolved_color) == CBSS_OK);
  assert(fabsf(resolved_color.r - 0.2f) < 0.002f);
  assert(fabsf(resolved_color.b - 0.8f) < 0.002f);
  assert(cbss_color_value_parse(
      "not-a-color", &contextual,
      color_error, sizeof(color_error)) == CBSS_INVALID_ARGUMENT);
  assert(contextual == NULL);
  assert(color_error[0] != '\0');

  assert(cbss_color_value_current(&contextual) == CBSS_OK);
  assert(cbss_color_value_resolve(
      contextual, (CbssColor){0.2f, 0.3f, 0.4f, 0.5f},
      &resolved_color) == CBSS_OK);
  assert(fabsf(resolved_color.r - 0.2f) < 0.002f);
  assert(fabsf(resolved_color.g - 0.3f) < 0.002f);
  assert(fabsf(resolved_color.b - 0.4f) < 0.002f);
  assert(fabsf(resolved_color.a - 0.5f) < 0.002f);
  cbss_color_value_destroy(parsed_color);
  parsed_color = NULL;
  assert(cbss_color_value_create(
      CBSS_COLOR_SRGB, NAN, 0.0f, 0.0f, 1.0f, 0,
      &parsed_color) == CBSS_INVALID_ARGUMENT);
  assert(parsed_color == NULL);

  assert(cbss_style_set_color_value(
      child_style, "background-color", mixed) == CBSS_OK);
  assert(cbss_style_set_color_value(
      child_style, "background-color", NULL) == CBSS_INVALID_ARGUMENT);
  cbss_color_value_destroy(contextual);
  cbss_color_value_destroy(mixed);
  cbss_color_value_destroy(parsed_mix);
  cbss_color_value_destroy(blue);
  cbss_color_value_destroy(red);

  uint32_t root = cbss_context_add_box(context, CBSS_NODE_NONE, "root");
  uint32_t child = cbss_context_add_box(context, root, "child");
  uint32_t label = cbss_context_add_text(context, child, "C ABI", "label");
  uint32_t sibling = cbss_context_add_box(context, root, "sibling");
  uint32_t surface_node = cbss_context_add_render_surface(
      context, root, surface_state.surface, "surface");
  assert(root != CBSS_NODE_NONE);
  assert(child != CBSS_NODE_NONE);
  assert(label != CBSS_NODE_NONE);
  assert(sibling != CBSS_NODE_NONE);
  assert(surface_node != CBSS_NODE_NONE);
  assert(cbss_context_add_render_surface(
      context, root, surface_state.surface,
      "duplicate-surface") == CBSS_NODE_NONE);
  assert(cbss_node_kind(context, root) == CBSS_NODE_BOX);
  assert(cbss_node_kind(context, label) == CBSS_NODE_TEXT);
  assert(cbss_node_parent(context, label) == child);
  assert(cbss_node_child_count(context, root) == 3);
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
  assert(cbss_style_set_color(
      root_style, "color",
      (CbssColor){0.85f, 0.75f, 0.65f, 1.0f}) == CBSS_OK);
  CbssGradientStop gradient[] = {
      {{0.1f, 0.2f, 0.3f, 1.0f}, 0.0f},
      {{0.3f, 0.4f, 0.5f, 1.0f}, 1.0f}
  };
  assert(cbss_style_set_linear_gradient_in(
      root_style, "background-image", 90.0f,
      CBSS_COLOR_INTERPOLATE_OKLAB, gradient, 2) == CBSS_OK);
  CbssColorValue *gradient_p3 = NULL;
  CbssColorValue *gradient_current = NULL;
  assert(cbss_color_value_create(
      CBSS_COLOR_DISPLAY_P3, 0.92f, 0.18f, 0.08f, 1.0f, 0,
      &gradient_p3) == CBSS_OK);
  assert(cbss_color_value_current(&gradient_current) == CBSS_OK);
  CbssColor expected_gradient_p3;
  assert(cbss_color_value_resolve(
      gradient_p3, (CbssColor){0.0f, 0.0f, 0.0f, 1.0f},
      &expected_gradient_p3) == CBSS_OK);
  CbssColorValueGradientStop authored_gradient[] = {
      {gradient_p3, 0.0f},
      {gradient_current, 1.0f}
  };
  CbssColorValueGradientStop invalid_authored_gradient[] = {
      {NULL, 0.0f}
  };
  assert(cbss_style_set_linear_gradient_color_values(
      root_style, "background-image", 90.0f,
      CBSS_COLOR_INTERPOLATE_OKLAB,
      invalid_authored_gradient, 1) == CBSS_INVALID_ARGUMENT);
  assert(cbss_style_set_linear_gradient_color_values(
      root_style, "background-image", 90.0f,
      CBSS_COLOR_INTERPOLATE_OKLAB, authored_gradient, 2) == CBSS_OK);
  cbss_color_value_destroy(gradient_current);
  cbss_color_value_destroy(gradient_p3);

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
  CbssTransformOperation translation = {
      .kind = CBSS_TRANSFORM_TRANSLATE,
      .flags = CBSS_TRANSFORM_HAS_X | CBSS_TRANSFORM_HAS_Y,
      .x_unit = CBSS_UNIT_PX,
      .y_unit = CBSS_UNIT_PX,
      .x = 1.0f,
      .y = 0.0f
  };
  assert(cbss_style_set_transform(
      child_style, "transform", &translation, 1) == CBSS_OK);
  assert(cbss_style_set_length(
      surface_style, "width", CBSS_UNIT_PX, 30.0f) == CBSS_OK);
  assert(cbss_style_set_length(
      surface_style, "height", CBSS_UNIT_PX, 24.0f) == CBSS_OK);

  require_ok(context, cbss_node_apply_style(
      context, root, root_style, 0, 0));
  require_ok(context, cbss_node_apply_style(
      context, child, child_style, 0, 0));
  require_ok(context, cbss_node_apply_style(
      context, sibling, child_style, 0, 0));
  require_ok(context, cbss_node_apply_style(
      context, surface_node, surface_style, 0, 0));
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
  require_ok(context, cbss_node_set_event_handler(
      context, child, CBSS_EVENT_PEN_BUTTON_DOWN,
      handle_event, &callback_state));

  CbssPathSegment surface_path[] = {
      {.kind = CBSS_PATH_MOVE_TO, .endpoint_x = 1.0f, .endpoint_y = 1.0f},
      {.kind = CBSS_PATH_LINE_TO, .endpoint_x = 12.0f, .endpoint_y = 8.0f}
  };
  CbssTextStyle surface_text_style = {
      .flags = CBSS_TEXT_HAS_FONT_SIZE | CBSS_TEXT_HAS_FONT_WEIGHT,
      .font_size = 12.0f,
      .font_weight = 600.0f
  };
  require_ok(context, cbss_render_surface_canvas_clear(
      context, surface_state.surface));
  require_ok(context, cbss_render_surface_canvas_save(
      context, surface_state.surface));
  require_ok(context, cbss_render_surface_canvas_transform(
      context, surface_state.surface,
      (CbssAffineTransform){1.0f, 0.0f, 0.0f, 1.0f, 2.0f, 3.0f}));
  require_ok(context, cbss_render_surface_canvas_begin_layer(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 28.0f, 22.0f},
      0.75f, CBSS_LAYER_SOURCE_OVER));
  require_ok(context, cbss_render_surface_canvas_push_clip(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 28.0f, 22.0f}, 2.0f));
  require_ok(context, cbss_render_surface_canvas_fill_rect(
      context, surface_state.surface,
      (CbssRect){1.0f, 1.0f, 12.0f, 8.0f},
      (CbssColor){1.0f, 0.0f, 0.0f, 1.0f}, 1.0f));
  require_ok(context, cbss_render_surface_canvas_fill_linear_gradient(
      context, surface_state.surface,
      (CbssRect){13.0f, 1.0f, 12.0f, 8.0f}, 90.0f,
      CBSS_COLOR_INTERPOLATE_OKLAB, gradient, 2, 1.0f));
  require_ok(context, cbss_render_surface_canvas_stroke_rect(
      context, surface_state.surface,
      (CbssRect){1.0f, 10.0f, 12.0f, 8.0f},
      (CbssColor){0.0f, 1.0f, 0.0f, 1.0f}, 1.0f, 1.0f));
  require_ok(context, cbss_render_surface_canvas_stroke_path(
      context, surface_state.surface, surface_path, 2,
      (CbssColor){0.0f, 0.0f, 1.0f, 1.0f}, 1.0f,
      CBSS_STROKE_CAP_ROUND, CBSS_STROKE_JOIN_ROUND, 4.0f));
  require_ok(context, cbss_render_surface_canvas_draw_text(
      context, surface_state.surface, "Surface", 2.0f, 18.0f,
      (CbssColor){1.0f, 1.0f, 1.0f, 1.0f},
      &surface_text_style, "sans-serif", 24.0f, 1));
  require_ok(context, cbss_render_surface_canvas_draw_image(
      context, surface_state.surface, "surface.png",
      (CbssRect){16.0f, 10.0f, 8.0f, 8.0f}, 0.8f));
  require_ok(context, cbss_render_surface_canvas_pop_clip(
      context, surface_state.surface));
  require_ok(context, cbss_render_surface_canvas_end_layer(
      context, surface_state.surface));
  require_ok(context, cbss_render_surface_canvas_restore(
      context, surface_state.surface));
  uint64_t canvas_revision = 0;
  require_ok(context, cbss_render_surface_canvas_commit(
      context, surface_state.surface, &canvas_revision));
  assert(canvas_revision == 1);
  uint64_t unchanged_canvas_revision = 0;
  require_ok(context, cbss_render_surface_canvas_commit(
      context, surface_state.surface, &unchanged_canvas_revision));
  assert(unchanged_canvas_revision == canvas_revision);
  require_ok(context, cbss_context_compute(context, 200.0f, 80.0f));
  assert(surface_state.mounts == 1);
  assert(surface_state.node == surface_node);

  CbssRect surface_rect;
  require_ok(context, cbss_node_layout_rect(
      context, surface_node, &surface_rect));
  CbssInputEvent surface_pointer = {
      .kind = CBSS_EVENT_POINTER_MOVE,
      .flags = CBSS_INPUT_HAS_POSITION | CBSS_INPUT_HAS_POINTER,
      .x = surface_rect.x + 4.0f,
      .y = surface_rect.y + 5.0f,
      .timestamp = 9001,
      .pointer = {
          .device = CBSS_POINTER_PEN_DIRECT,
          .axes = CBSS_POINTER_AXIS_PRESSURE | CBSS_POINTER_AXIS_TILT_X,
          .device_id = 77,
          .pressure = 0.625f,
          .tilt_x = -18.0f,
          .contact = 1,
          .primary = 1,
          .eraser = 1,
          .in_proximity = 1
      }
  };
  CbssDispatchSummary surface_dispatch;
  require_ok(context, cbss_context_dispatch_input(
      context, &surface_pointer, &surface_dispatch));
  assert(surface_dispatch.handled);
  assert(surface_state.inputs >= 1);
  assert(fabsf(surface_state.local_x - 4.0f) < 0.01f);
  assert(fabsf(surface_state.local_y - 5.0f) < 0.01f);
  assert(surface_state.pen_inputs == 1);

  require_ok(context, cbss_context_recompute(context));
  require_ok(context, cbss_context_set_pixel_scale(context, 2.0f));
  assert(surface_state.resizes == 1);
  require_ok(context, cbss_render_surface_update(
      context, surface_state.surface, 7));
  assert(surface_state.updates >= 2);
  require_ok(context, cbss_render_surface_request_frame(
      context, surface_state.surface));
  assert(cbss_context_needs_render_surface_frame(context));
  uint32_t surface_frames = 0;
  assert(cbss_context_run_render_surface_frames(
      context, NAN, &surface_frames) == CBSS_INVALID_ARGUMENT);
  require_ok(context, cbss_context_run_render_surface_frames(
      context, 1.0, &surface_frames));
  assert(surface_frames == 1);
  assert(cbss_context_needs_render_surface_frame(context));
  require_ok(context, cbss_context_run_render_surface_frames(
      context, 1.016, &surface_frames));
  assert(surface_frames == 1);
  assert(!cbss_context_needs_render_surface_frame(context));
  assert(surface_state.frames == 2);
  require_ok(context, cbss_render_surface_set_device_available(
      context, surface_state.surface, 0));
  require_ok(context, cbss_render_surface_set_device_available(
      context, surface_state.surface, 1));
  assert(surface_state.device_lost == 1);
  assert(surface_state.device_restored == 1);

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
  int found_gradient = 0;
  int found_transform_push = 0;
  int found_transform_pop = 0;
  int found_surface_fill = 0;
  int found_surface_gradient = 0;
  int found_surface_path = 0;
  int found_surface_text = 0;
  int found_surface_image = 0;
  int found_surface_layer = 0;
  for (uint32_t i = 0; i < command_count; ++i) {
    CbssPaintCommand command;
    require_ok(context, cbss_context_paint_command(context, i, &command));
    if (command.kind == CBSS_PAINT_DRAW_TEXT) {
      char text[32];
      uint32_t text_bytes = cbss_paint_command_string(
          context, i, text, sizeof(text));
      if (command.owner == surface_node) {
        assert(text_bytes == 7);
        assert(strcmp(text, "Surface") == 0);
        found_surface_text = 1;
      } else {
        assert(text_bytes == 5);
        assert(strcmp(text, "C ABI") == 0);
        found_text = 1;
      }
    } else if (command.kind == CBSS_PAINT_FILL_LINEAR_GRADIENT) {
      assert(fabsf(command.value0 - 90.0f) < 0.01f);
      assert((uint32_t)command.value1 == 2);
      assert((uint32_t)command.value2 == CBSS_COLOR_INTERPOLATE_OKLAB);
      CbssGradientStop first_stop;
      CbssGradientStop second_stop;
      require_ok(context, cbss_paint_command_gradient_stop(
          context, i, 0, &first_stop));
      require_ok(context, cbss_paint_command_gradient_stop(
          context, i, 1, &second_stop));
      if (command.owner == surface_node) {
        assert(fabsf(first_stop.color.r - 0.1f) < 0.002f);
        assert(fabsf(second_stop.color.r - 0.3f) < 0.002f);
        found_surface_gradient = 1;
      } else {
        assert(fabsf(first_stop.color.r - expected_gradient_p3.r) < 0.002f);
        assert(fabsf(first_stop.color.g - expected_gradient_p3.g) < 0.002f);
        assert(fabsf(first_stop.color.b - expected_gradient_p3.b) < 0.002f);
        assert(fabsf(second_stop.color.r - 0.85f) < 0.002f);
        assert(fabsf(second_stop.color.g - 0.75f) < 0.002f);
        assert(fabsf(second_stop.color.b - 0.65f) < 0.002f);
        found_gradient = 1;
      }
    } else if (command.kind == CBSS_PAINT_PUSH_TRANSFORM) {
      CbssAffineTransform transform;
      require_ok(context, cbss_paint_command_transform(
          context, i, &transform));
      assert(fabsf(transform.m11 - 1.0f) < 0.001f);
      assert(fabsf(transform.m12) < 0.001f);
      assert(fabsf(transform.m21) < 0.001f);
      assert(fabsf(transform.m22 - 1.0f) < 0.001f);
      assert((fabsf(transform.tx - 1.0f) < 0.001f &&
              fabsf(transform.ty) < 0.001f) ||
             (fabsf(transform.tx - 2.0f) < 0.001f &&
              fabsf(transform.ty - 3.0f) < 0.001f));
      found_transform_push = 1;
    } else if (command.kind == CBSS_PAINT_POP_TRANSFORM) {
      CbssAffineTransform transform;
      assert(cbss_paint_command_transform(context, i, &transform) ==
             CBSS_INVALID_ARGUMENT);
      CbssPathSegment segment;
      assert(cbss_paint_command_path_segment_count(context, i) == 0);
      assert(cbss_paint_command_path_segment(context, i, 0, &segment) ==
             CBSS_INVALID_ARGUMENT);
      found_transform_pop = 1;
    } else if (command.kind == CBSS_PAINT_FILL_RECT &&
               command.owner == surface_node) {
      assert(fabsf(command.color.r - 1.0f) < 0.001f);
      found_surface_fill = 1;
    } else if (command.kind == CBSS_PAINT_STROKE_PATH &&
               command.owner == surface_node) {
      assert(cbss_paint_command_path_segment_count(context, i) == 2);
      found_surface_path = 1;
    } else if (command.kind == CBSS_PAINT_DRAW_IMAGE &&
               command.owner == surface_node) {
      char source[32];
      assert(cbss_paint_command_string(
          context, i, source, sizeof(source)) == 11);
      assert(strcmp(source, "surface.png") == 0);
      found_surface_image = 1;
    } else if (command.kind == CBSS_PAINT_PUSH_LAYER) {
      assert(fabsf(command.value0 - 0.75f) < 0.001f);
      found_surface_layer = 1;
    }
  }
  assert(found_text);
  assert(found_gradient);
  assert(found_transform_push);
  assert(found_transform_pop);
  assert(found_surface_fill);
  assert(found_surface_gradient);
  assert(found_surface_path);
  assert(found_surface_text);
  assert(found_surface_image);
  assert(found_surface_layer);

  require_ok(context, cbss_render_surface_canvas_clear(
      context, surface_state.surface));
  require_ok(context, cbss_render_surface_canvas_fill_rect(
      context, surface_state.surface,
      (CbssRect){0.0f, 0.0f, 10.0f, 10.0f},
      (CbssColor){0.0f, 0.0f, 1.0f, 1.0f}, 0.0f));
  require_ok(context, cbss_context_recompute(context));
  int old_surface_snapshot_still_visible = 0;
  command_count = cbss_context_paint_command_count(context);
  for (uint32_t i = 0; i < command_count; ++i) {
    CbssPaintCommand command;
    require_ok(context, cbss_context_paint_command(context, i, &command));
    if (command.kind == CBSS_PAINT_DRAW_IMAGE &&
        command.owner == surface_node) {
      old_surface_snapshot_still_visible = 1;
    }
  }
  assert(old_surface_snapshot_still_visible);
  require_ok(context, cbss_render_surface_canvas_commit(
      context, surface_state.surface, &canvas_revision));
  assert(canvas_revision == 8);
  assert(!cbss_context_needs_compute(context));
  int found_updated_surface_fill = 0;
  command_count = cbss_context_paint_command_count(context);
  for (uint32_t i = 0; i < command_count; ++i) {
    CbssPaintCommand command;
    require_ok(context, cbss_context_paint_command(context, i, &command));
    if (command.kind == CBSS_PAINT_FILL_RECT &&
        command.owner == surface_node && command.color.b > 0.99f) {
      found_updated_surface_fill = 1;
    }
    assert(!(command.kind == CBSS_PAINT_DRAW_IMAGE &&
             command.owner == surface_node));
  }
  assert(found_updated_surface_fill);

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

  CbssInputEvent pen_button = {
      .kind = CBSS_EVENT_PEN_BUTTON_DOWN,
      .flags = CBSS_INPUT_HAS_POSITION | CBSS_INPUT_HAS_BUTTON |
               CBSS_INPUT_HAS_POINTER,
      .button = 2,
      .x = 12.0f,
      .y = 12.0f,
      .timestamp = 9002,
      .pointer = {
          .device = CBSS_POINTER_PEN_DIRECT,
          .axes = CBSS_POINTER_AXIS_PRESSURE | CBSS_POINTER_AXIS_TILT_X,
          .device_id = 77,
          .pressure = 0.625f,
          .tilt_x = -18.0f,
          .buttons = 2,
          .contact = 1,
          .primary = 1,
          .in_proximity = 1
      }
  };
  require_ok(context, cbss_context_emit_event(
      context, child, &pen_button, &dispatch));
  assert(callback_state.pen_events == 1);

  CbssInputEvent invalid_pen = pen_button;
  invalid_pen.pointer.pressure = NAN;
  assert(cbss_context_emit_event(
      context, child, &invalid_pen, &dispatch) == CBSS_INVALID_ARGUMENT);

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
  require_ok(context, cbss_context_unregister_render_surface(
      context, surface_state.surface));
  assert(surface_state.unmounts == 1);
  assert(cbss_context_unregister_render_surface(
      context, surface_state.surface) == CBSS_OUT_OF_RANGE);
  cbss_style_destroy(surface_style);
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
