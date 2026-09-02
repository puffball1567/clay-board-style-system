#ifndef CBSS_H
#define CBSS_H

#include <stdint.h>

#if defined(_WIN32) && defined(CBSS_SHARED)
#  if defined(CBSS_BUILD)
#    define CBSS_API __declspec(dllexport)
#  else
#    define CBSS_API __declspec(dllimport)
#  endif
#else
#  define CBSS_API
#endif

#if defined(_MSC_VER)
#  define CBSS_DEPRECATED(message) __declspec(deprecated(message))
#elif defined(__clang__) || defined(__GNUC__)
#  define CBSS_DEPRECATED(message) __attribute__((deprecated(message)))
#else
#  define CBSS_DEPRECATED(message)
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* CBSS_GENERATED_DRIVER_CONTRACT_BEGIN */
#define CBSS_ABI_VERSION 0x0001001Bu
#define CBSS_DRIVER_CONTRACT_VERSION 0x00010000u

typedef enum CbssCapabilityId {
  CBSS_CAPABILITY_RETAINED_TREE = 1u,
  CBSS_CAPABILITY_TYPED_STYLE = 2u,
  CBSS_CAPABILITY_FLEX_LAYOUT = 3u,
  CBSS_CAPABILITY_PAINT_COMMANDS = 4u,
  CBSS_CAPABILITY_HIT_TEST = 5u,
  CBSS_CAPABILITY_STANDARD_EVENTS = 6u,
  CBSS_CAPABILITY_FOCUS = 7u,
  CBSS_CAPABILITY_ACCESSIBILITY_SEMANTICS = 8u,
  CBSS_CAPABILITY_RETAINED_SCROLL = 9u,
  CBSS_CAPABILITY_DECLARATIVE_MOTION = 10u,
  CBSS_CAPABILITY_RETAINED_CANVAS = 11u,
  CBSS_CAPABILITY_RENDER_SURFACE = 12u,
  CBSS_CAPABILITY_BLOB = 13u,
  CBSS_CAPABILITY_FORM_DATA = 14u,
  CBSS_CAPABILITY_STREAM = 15u,
  CBSS_CAPABILITY_CRAFT_STYLE = 16u,
  CBSS_CAPABILITY_CRAFT_PACK = 17u,
  CBSS_CAPABILITY_SUBTREE_LIFECYCLE = 18u,
  CBSS_CAPABILITY_VALIDATION_PATTERN = 19u,
  CBSS_CAPABILITY_RASTER_SURFACE = 20u,
  CBSS_CAPABILITY_SHADER_AUTHORING = 21u
} CbssCapabilityId;

enum {
  CBSS_CAPABILITY_AVAILABLE = 1u << 0
};

typedef struct CbssCapabilityInfo {
  uint32_t id;
  uint32_t version;
  uint32_t since_abi;
  uint32_t flags;
  uint32_t name_bytes;
} CbssCapabilityInfo;
/* CBSS_GENERATED_DRIVER_CONTRACT_END */
#define CBSS_NODE_NONE UINT32_MAX
#define CBSS_MAX_EAGER_BLOB_BYTES (64ull * 1024ull * 1024ull)
#define CBSS_MAX_FORM_DATA_ENTRIES 65536u
#define CBSS_MAX_FORM_DATA_NAME_BYTES 65536u
#define CBSS_MAX_FORM_DATA_TEXT_BYTES (16u * 1024u * 1024u)
#define CBSS_MAX_STREAM_ERROR_BYTES 65536u
#define CBSS_MAX_KEYFRAME_STEPS 16384u
#define CBSS_MAX_CRAFT_STYLE_SOURCE_BYTES (8u * 1024u * 1024u)
#define CBSS_MAX_CRAFT_PACK_SOURCE_BYTES (4u * 1024u * 1024u)
#define CBSS_MAX_VALIDATION_PATTERN_BYTES 65536u
#define CBSS_MAX_VALIDATION_VALUE_BYTES (16u * 1024u * 1024u)
#define CBSS_MAX_RASTER_SURFACE_BYTES (256u * 1024u * 1024u)

typedef struct CbssContext CbssContext;
typedef struct CbssStyle CbssStyle;
typedef struct CbssKeyframes CbssKeyframes;
typedef struct CbssColorValue CbssColorValue;
typedef struct CbssValidationPattern CbssValidationPattern;
typedef struct CbssBlob CbssBlob;
typedef struct CbssFormDataBuilder CbssFormDataBuilder;
typedef struct CbssFormData CbssFormData;
typedef struct CbssEventView CbssEventView;
typedef struct CbssBlobStream CbssBlobStream;
typedef struct CbssStreamProducer CbssStreamProducer;
typedef struct CbssRasterSurface CbssRasterSurface;
typedef struct CbssShaderBuilder CbssShaderBuilder;
typedef uint64_t CbssEventSubscription;
typedef uint32_t CbssShaderExpression;

typedef int32_t CbssStatus;
enum {
  CBSS_OK = 0,
  CBSS_INVALID_ARGUMENT = 1,
  CBSS_INVALID_HANDLE = 2,
  CBSS_OUT_OF_RANGE = 3,
  CBSS_STYLE_ERROR = 4,
  CBSS_INTERNAL_ERROR = 5,
  CBSS_NOT_AVAILABLE = 6
};

typedef enum CbssShaderStage {
  CBSS_SHADER_STAGE_VERTEX = 0,
  CBSS_SHADER_STAGE_FRAGMENT = 1,
  CBSS_SHADER_STAGE_COMPUTE = 2
} CbssShaderStage;

typedef enum CbssShaderValueType {
  CBSS_SHADER_VALUE_BOOL = 0,
  CBSS_SHADER_VALUE_FLOAT = 1,
  CBSS_SHADER_VALUE_VEC2 = 2,
  CBSS_SHADER_VALUE_VEC3 = 3,
  CBSS_SHADER_VALUE_VEC4 = 4,
  CBSS_SHADER_VALUE_MAT3 = 5,
  CBSS_SHADER_VALUE_MAT4 = 6
} CbssShaderValueType;

typedef enum CbssShaderInterfaceSlot {
  CBSS_SHADER_SLOT_POSITION = 0,
  CBSS_SHADER_SLOT_NORMAL = 1,
  CBSS_SHADER_SLOT_TANGENT = 2,
  CBSS_SHADER_SLOT_BITANGENT = 3,
  CBSS_SHADER_SLOT_COLOR0 = 4,
  CBSS_SHADER_SLOT_COLOR1 = 5,
  CBSS_SHADER_SLOT_COLOR2 = 6,
  CBSS_SHADER_SLOT_COLOR3 = 7,
  CBSS_SHADER_SLOT_TEXCOORD0 = 8,
  CBSS_SHADER_SLOT_TEXCOORD1 = 9,
  CBSS_SHADER_SLOT_TEXCOORD2 = 10,
  CBSS_SHADER_SLOT_TEXCOORD3 = 11,
  CBSS_SHADER_SLOT_TEXCOORD4 = 12,
  CBSS_SHADER_SLOT_TEXCOORD5 = 13,
  CBSS_SHADER_SLOT_TEXCOORD6 = 14,
  CBSS_SHADER_SLOT_TEXCOORD7 = 15
} CbssShaderInterfaceSlot;

typedef enum CbssShaderUnaryOperation {
  CBSS_SHADER_UNARY_NEGATE = 0,
  CBSS_SHADER_UNARY_SINE = 1,
  CBSS_SHADER_UNARY_COSINE = 2,
  CBSS_SHADER_UNARY_ABSOLUTE = 3,
  CBSS_SHADER_UNARY_FLOOR = 4,
  CBSS_SHADER_UNARY_CEIL = 5,
  CBSS_SHADER_UNARY_NORMALIZE = 6
} CbssShaderUnaryOperation;

typedef enum CbssShaderBinaryOperation {
  CBSS_SHADER_BINARY_ADD = 0,
  CBSS_SHADER_BINARY_SUBTRACT = 1,
  CBSS_SHADER_BINARY_MULTIPLY = 2,
  CBSS_SHADER_BINARY_DIVIDE = 3,
  CBSS_SHADER_BINARY_MINIMUM = 4,
  CBSS_SHADER_BINARY_MAXIMUM = 5,
  CBSS_SHADER_BINARY_DOT = 6,
  CBSS_SHADER_BINARY_POWER = 7
} CbssShaderBinaryOperation;

typedef enum CbssShaderTernaryOperation {
  CBSS_SHADER_TERNARY_MIX = 0,
  CBSS_SHADER_TERNARY_CLAMP = 1,
  CBSS_SHADER_TERNARY_SMOOTHSTEP = 2
} CbssShaderTernaryOperation;

typedef enum CbssCraftDiagnosticDomain {
  CBSS_CRAFT_DIAGNOSTIC_STYLE_PARSE = 0,
  CBSS_CRAFT_DIAGNOSTIC_STYLE_REPLACEMENT = 1,
  CBSS_CRAFT_DIAGNOSTIC_PACK = 2
} CbssCraftDiagnosticDomain;

typedef enum CbssValidationStringFormat {
  CBSS_VALIDATION_FORMAT_EMAIL = 0,
  CBSS_VALIDATION_FORMAT_URL = 1,
  CBSS_VALIDATION_FORMAT_UUID = 2,
  CBSS_VALIDATION_FORMAT_IP_ADDRESS = 3,
  CBSS_VALIDATION_FORMAT_DATE = 4,
  CBSS_VALIDATION_FORMAT_TIME = 5,
  CBSS_VALIDATION_FORMAT_DATE_TIME = 6
} CbssValidationStringFormat;

typedef enum CbssCraftStyleParseDiagnosticCode {
  CBSS_CRAFT_STYLE_PARSE_INVALID_JSON = 0,
  CBSS_CRAFT_STYLE_PARSE_INVALID_DOCUMENT = 1,
  CBSS_CRAFT_STYLE_PARSE_UNSUPPORTED_VERSION = 2,
  CBSS_CRAFT_STYLE_PARSE_MISSING_FIELD = 3,
  CBSS_CRAFT_STYLE_PARSE_UNKNOWN_FIELD = 4,
  CBSS_CRAFT_STYLE_PARSE_INVALID_TYPE = 5,
  CBSS_CRAFT_STYLE_PARSE_INVALID_VALUE = 6,
  CBSS_CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY = 7,
  CBSS_CRAFT_STYLE_PARSE_DUPLICATE_FIELD = 8,
  CBSS_CRAFT_STYLE_PARSE_LIMIT_EXCEEDED = 9
} CbssCraftStyleParseDiagnosticCode;

typedef enum CbssCraftStyleReplacementDiagnosticCode {
  CBSS_CRAFT_STYLE_REPLACEMENT_UNSUPPORTED_RULE_TARGET = 0,
  CBSS_CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT = 1,
  CBSS_CRAFT_STYLE_REPLACEMENT_INVALID_STYLE_SLOT = 2,
  CBSS_CRAFT_STYLE_REPLACEMENT_INVALID_CRAFT_STYLE = 3
} CbssCraftStyleReplacementDiagnosticCode;

typedef enum CbssCraftPackDiagnosticCode {
  CBSS_CRAFT_PACK_INVALID_JSON = 0,
  CBSS_CRAFT_PACK_INVALID_DOCUMENT = 1,
  CBSS_CRAFT_PACK_UNSUPPORTED_VERSION = 2,
  CBSS_CRAFT_PACK_MISSING_FIELD = 3,
  CBSS_CRAFT_PACK_UNKNOWN_FIELD = 4,
  CBSS_CRAFT_PACK_INVALID_TYPE = 5,
  CBSS_CRAFT_PACK_INVALID_VALUE = 6,
  CBSS_CRAFT_PACK_DUPLICATE_FIELD = 7,
  CBSS_CRAFT_PACK_DUPLICATE_VALUE = 8,
  CBSS_CRAFT_PACK_LIMIT_EXCEEDED = 9,
  CBSS_CRAFT_PACK_INCOMPATIBLE_ABI = 10,
  CBSS_CRAFT_PACK_INCOMPATIBLE_DRIVER_CONTRACT = 11,
  CBSS_CRAFT_PACK_MISSING_CAPABILITY = 12
} CbssCraftPackDiagnosticCode;

typedef struct CbssCraftDiagnostic {
  uint32_t domain;
  uint32_t code;
  uint32_t path_bytes;
  uint32_t message_bytes;
} CbssCraftDiagnostic;

typedef enum CbssFormDataValueKind {
  CBSS_FORM_DATA_TEXT = 0,
  CBSS_FORM_DATA_BLOB = 1
} CbssFormDataValueKind;

typedef enum CbssStreamState {
  CBSS_STREAM_IDLE = 0,
  CBSS_STREAM_OPEN = 1,
  CBSS_STREAM_ENDED = 2,
  CBSS_STREAM_FAILED = 3,
  CBSS_STREAM_CANCELLED = 4,
  CBSS_STREAM_CLOSED = 5
} CbssStreamState;

typedef enum CbssStreamOfferResult {
  CBSS_STREAM_OFFER_ACCEPTED = 0,
  CBSS_STREAM_OFFER_BACKPRESSURE = 1,
  CBSS_STREAM_OFFER_INVALID_STATE = 2,
  CBSS_STREAM_OFFER_DISPOSED = 3,
  CBSS_STREAM_OFFER_INVALID_ARGUMENT = 4
} CbssStreamOfferResult;

typedef enum CbssStreamEventKind {
  CBSS_STREAM_EVENT_OPEN = 0,
  CBSS_STREAM_EVENT_DATA = 1,
  CBSS_STREAM_EVENT_PROGRESS = 2,
  CBSS_STREAM_EVENT_END = 3,
  CBSS_STREAM_EVENT_ERROR = 4,
  CBSS_STREAM_EVENT_CANCEL = 5,
  CBSS_STREAM_EVENT_CLOSE = 6
} CbssStreamEventKind;

enum {
  CBSS_STREAM_EVENT_HAS_TOTAL = 1u << 0
};

typedef enum CbssUnit {
  CBSS_UNIT_PX = 0,
  CBSS_UNIT_PERCENT = 1,
  CBSS_UNIT_EM = 2,
  CBSS_UNIT_REM = 3,
  CBSS_UNIT_FILL = 4,
  CBSS_UNIT_CONTENT = 5,
  CBSS_UNIT_MIN_CONTENT = 6,
  CBSS_UNIT_MAX_CONTENT = 7,
  CBSS_UNIT_FIT_CONTENT = 8,
  CBSS_UNIT_AUTO = 9,
  CBSS_UNIT_NONE = 10,
  CBSS_UNIT_VW = 11,
  CBSS_UNIT_VH = 12,
  CBSS_UNIT_VMIN = 13,
  CBSS_UNIT_VMAX = 14,
  CBSS_UNIT_LH = 15,
  CBSS_UNIT_RLH = 16,
  CBSS_UNIT_EX = 17,
  CBSS_UNIT_CH = 18,
  CBSS_UNIT_REX = 19,
  CBSS_UNIT_RCH = 20
} CbssUnit;

typedef enum CbssNodeState {
  CBSS_STATE_HOVER = 0,
  CBSS_STATE_ACTIVE = 1,
  CBSS_STATE_FOCUS = 2,
  CBSS_STATE_FOCUS_VISIBLE = 3,
  CBSS_STATE_DISABLED = 4,
  CBSS_STATE_CHECKED = 5,
  CBSS_STATE_SELECTED = 6,
  CBSS_STATE_OPEN = 7,
  CBSS_STATE_INVALID = 8
} CbssNodeState;

typedef enum CbssNodeKind {
  CBSS_NODE_BOX = 0,
  CBSS_NODE_TEXT = 1,
  CBSS_NODE_IMAGE = 2
} CbssNodeKind;

/* CBSS_GENERATED_EVENT_KINDS_BEGIN */
typedef enum CbssEventKind {
  CBSS_EVENT_ABORT = 0,
  CBSS_EVENT_ANIMATION_END = 1,
  CBSS_EVENT_ANIMATION_ITERATION = 2,
  CBSS_EVENT_ANIMATION_START = 3,
  CBSS_EVENT_AUX_CLICK = 4,
  CBSS_EVENT_BEFORE_INPUT = 5,
  CBSS_EVENT_BLUR = 6,
  CBSS_EVENT_CANCEL = 7,
  CBSS_EVENT_CAN_PLAY = 8,
  CBSS_EVENT_CAN_PLAY_THROUGH = 9,
  CBSS_EVENT_CHANGE = 10,
  CBSS_EVENT_CLOSE = 11,
  CBSS_EVENT_POINTER_MOVE = 12,
  CBSS_EVENT_POINTER_DOWN = 13,
  CBSS_EVENT_POINTER_UP = 14,
  CBSS_EVENT_POINTER_CANCEL = 15,
  CBSS_EVENT_POINTER_ENTER = 16,
  CBSS_EVENT_POINTER_LEAVE = 17,
  CBSS_EVENT_POINTER_OVER = 18,
  CBSS_EVENT_POINTER_OUT = 19,
  CBSS_EVENT_CLICK = 20,
  CBSS_EVENT_CONTEXT_MENU = 21,
  CBSS_EVENT_CUE_CHANGE = 22,
  CBSS_EVENT_DOUBLE_CLICK = 23,
  CBSS_EVENT_COPY = 24,
  CBSS_EVENT_CUT = 25,
  CBSS_EVENT_PASTE = 26,
  CBSS_EVENT_COMPOSITION_END = 27,
  CBSS_EVENT_COMPOSITION_START = 28,
  CBSS_EVENT_COMPOSITION_UPDATE = 29,
  CBSS_EVENT_DRAG = 30,
  CBSS_EVENT_DRAG_END = 31,
  CBSS_EVENT_DRAG_ENTER = 32,
  CBSS_EVENT_DRAG_EXIT = 33,
  CBSS_EVENT_DRAG_LEAVE = 34,
  CBSS_EVENT_DRAG_OVER = 35,
  CBSS_EVENT_DRAG_START = 36,
  CBSS_EVENT_DROP = 37,
  CBSS_EVENT_DURATION_CHANGE = 38,
  CBSS_EVENT_EMPTIED = 39,
  CBSS_EVENT_ENCRYPTED = 40,
  CBSS_EVENT_ENDED = 41,
  CBSS_EVENT_ERROR = 42,
  CBSS_EVENT_FOCUS = 43,
  CBSS_EVENT_FULLSCREEN_CHANGE = 44,
  CBSS_EVENT_FULLSCREEN_ERROR = 45,
  CBSS_EVENT_GOT_POINTER_CAPTURE = 46,
  CBSS_EVENT_INPUT = 47,
  CBSS_EVENT_INVALID = 48,
  CBSS_EVENT_KEY_DOWN = 49,
  CBSS_EVENT_KEY_UP = 50,
  CBSS_EVENT_LOAD = 51,
  CBSS_EVENT_LOAD_END = 52,
  CBSS_EVENT_LOADED_DATA = 53,
  CBSS_EVENT_LOADED_METADATA = 54,
  CBSS_EVENT_LOAD_START = 55,
  CBSS_EVENT_LOST_POINTER_CAPTURE = 56,
  CBSS_EVENT_MOUSE_DOWN = 57,
  CBSS_EVENT_MOUSE_ENTER = 58,
  CBSS_EVENT_MOUSE_LEAVE = 59,
  CBSS_EVENT_MOUSE_MOVE = 60,
  CBSS_EVENT_MOUSE_OUT = 61,
  CBSS_EVENT_MOUSE_OVER = 62,
  CBSS_EVENT_MOUSE_UP = 63,
  CBSS_EVENT_PAUSE = 64,
  CBSS_EVENT_PLAY = 65,
  CBSS_EVENT_PLAYING = 66,
  CBSS_EVENT_PROGRESS = 67,
  CBSS_EVENT_RATE_CHANGE = 68,
  CBSS_EVENT_RESET = 69,
  CBSS_EVENT_RESIZE = 70,
  CBSS_EVENT_SCROLL = 71,
  CBSS_EVENT_SCROLL_END = 72,
  CBSS_EVENT_SEEKED = 73,
  CBSS_EVENT_SEEKING = 74,
  CBSS_EVENT_SELECT = 75,
  CBSS_EVENT_SHOW = 76,
  CBSS_EVENT_STALLED = 77,
  CBSS_EVENT_SUBMIT = 78,
  CBSS_EVENT_SUSPEND = 79,
  CBSS_EVENT_TEXT_INPUT = 80,
  CBSS_EVENT_TIME_UPDATE = 81,
  CBSS_EVENT_TOGGLE = 82,
  CBSS_EVENT_TOUCH_CANCEL = 83,
  CBSS_EVENT_TOUCH_END = 84,
  CBSS_EVENT_TOUCH_MOVE = 85,
  CBSS_EVENT_TOUCH_START = 86,
  CBSS_EVENT_TRANSITION_END = 87,
  CBSS_EVENT_VOLUME_CHANGE = 88,
  CBSS_EVENT_WAITING = 89,
  CBSS_EVENT_WHEEL = 90,
  CBSS_EVENT_PEN_PROXIMITY_IN = 91,
  CBSS_EVENT_PEN_PROXIMITY_OUT = 92,
  CBSS_EVENT_PEN_BUTTON_DOWN = 93,
  CBSS_EVENT_PEN_BUTTON_UP = 94,
  CBSS_EVENT_ANIMATION_CANCEL = 95,
  CBSS_EVENT_TRANSITION_RUN = 96,
  CBSS_EVENT_TRANSITION_START = 97,
  CBSS_EVENT_TRANSITION_CANCEL = 98
} CbssEventKind;
/* CBSS_GENERATED_EVENT_KINDS_END */

enum {
  CBSS_INPUT_HAS_POSITION = 1u << 0,
  CBSS_INPUT_HAS_DELTA = 1u << 1,
  CBSS_INPUT_HAS_BUTTON = 1u << 2,
  CBSS_INPUT_HAS_KEY = 1u << 3,
  CBSS_INPUT_HAS_TEXT = 1u << 4,
  CBSS_INPUT_HAS_POINTER = 1u << 5
};

typedef enum CbssPointerDeviceKind {
  CBSS_POINTER_MOUSE = 0,
  CBSS_POINTER_TOUCH = 1,
  CBSS_POINTER_PEN_UNKNOWN = 2,
  CBSS_POINTER_PEN_DIRECT = 3,
  CBSS_POINTER_PEN_INDIRECT = 4
} CbssPointerDeviceKind;

enum {
  CBSS_POINTER_AXIS_PRESSURE = 1u << 0,
  CBSS_POINTER_AXIS_TANGENTIAL_PRESSURE = 1u << 1,
  CBSS_POINTER_AXIS_TILT_X = 1u << 2,
  CBSS_POINTER_AXIS_TILT_Y = 1u << 3,
  CBSS_POINTER_AXIS_ROTATION = 1u << 4,
  CBSS_POINTER_AXIS_DISTANCE = 1u << 5,
  CBSS_POINTER_AXIS_SLIDER = 1u << 6
};

enum {
  CBSS_MODIFIER_CTRL = 1u << 0,
  CBSS_MODIFIER_ALT = 1u << 1,
  CBSS_MODIFIER_SHIFT = 1u << 2,
  CBSS_MODIFIER_META = 1u << 3
};

enum {
  CBSS_EVENT_HAS_LOCAL = 1u << 0,
  CBSS_EVENT_HAS_POSITION = 1u << 1,
  CBSS_EVENT_HAS_DELTA = 1u << 2,
  CBSS_EVENT_HAS_BUTTON = 1u << 3,
  CBSS_EVENT_HAS_KEY = 1u << 4,
  CBSS_EVENT_HAS_TEXT = 1u << 5,
  CBSS_EVENT_HAS_POINTER = 1u << 6,
  CBSS_EVENT_BUBBLES = 1u << 7,
  CBSS_EVENT_CANCELABLE = 1u << 8,
  CBSS_EVENT_PHASE_TARGET = 1u << 9,
  CBSS_EVENT_PHASE_BUBBLE = 1u << 10,
  CBSS_EVENT_HAS_MOTION = 1u << 11,
  CBSS_EVENT_PHASE_DEFAULT_ACTION = 1u << 12
};

typedef enum CbssDirtyDomain {
  CBSS_DIRTY_STYLE = 1u << 0,
  CBSS_DIRTY_LAYOUT = 1u << 1,
  CBSS_DIRTY_PAINT = 1u << 2,
  CBSS_DIRTY_HIT = 1u << 3,
  CBSS_DIRTY_TEXT = 1u << 4,
  CBSS_DIRTY_RESOURCE = 1u << 5,
  CBSS_DIRTY_ANIMATION = 1u << 6
} CbssDirtyDomain;

enum {
  CBSS_EVENT_OUTCOME_HANDLED = 1u << 0,
  CBSS_EVENT_OUTCOME_STOP_PROPAGATION = 1u << 1,
  CBSS_EVENT_OUTCOME_PREVENT_DEFAULT = 1u << 2
};

enum {
  CBSS_BORDER_HAS_WIDTH = 1u << 0,
  CBSS_BORDER_HAS_STYLE = 1u << 1,
  CBSS_BORDER_HAS_COLOR = 1u << 2
};

enum {
  CBSS_SHADOW_HAS_BLUR = 1u << 0,
  CBSS_SHADOW_HAS_SPREAD = 1u << 1,
  CBSS_SHADOW_HAS_COLOR = 1u << 2
};

typedef enum CbssTransformKind {
  CBSS_TRANSFORM_TRANSLATE = 0,
  CBSS_TRANSFORM_SCALE = 1,
  CBSS_TRANSFORM_ROTATE = 2
} CbssTransformKind;

enum {
  CBSS_TRANSFORM_HAS_X = 1u << 0,
  CBSS_TRANSFORM_HAS_Y = 1u << 1,
  CBSS_TRANSFORM_HAS_Z = 1u << 2
};

enum {
  CBSS_ACCESSIBLE_HAS_VALUE_NOW = 1u << 0,
  CBSS_ACCESSIBLE_HAS_VALUE_MIN = 1u << 1,
  CBSS_ACCESSIBLE_HAS_VALUE_MAX = 1u << 2
};

enum {
  CBSS_ACCESSIBLE_HAS_POSITION_IN_SET = 1u << 0,
  CBSS_ACCESSIBLE_HAS_SET_SIZE = 1u << 1
};

typedef enum CbssAccessibleRole {
  CBSS_ROLE_NONE = 0,
  CBSS_ROLE_APPLICATION = 1,
  CBSS_ROLE_GENERIC = 2,
  CBSS_ROLE_BUTTON = 3,
  CBSS_ROLE_CHECK_BOX = 4,
  CBSS_ROLE_RADIO = 5,
  CBSS_ROLE_TEXT_BOX = 6,
  CBSS_ROLE_TEXT_AREA = 7,
  CBSS_ROLE_COMBO_BOX = 8,
  CBSS_ROLE_OPTION = 9,
  CBSS_ROLE_SLIDER = 10,
  CBSS_ROLE_DISCLOSURE = 11,
  CBSS_ROLE_PROGRESS_BAR = 12,
  CBSS_ROLE_LIST_BOX = 13,
  CBSS_ROLE_LIST_ITEM = 14,
  CBSS_ROLE_TAB_LIST = 15,
  CBSS_ROLE_TAB = 16,
  CBSS_ROLE_DIALOG = 17,
  CBSS_ROLE_GROUP = 18,
  CBSS_ROLE_IMAGE = 19,
  CBSS_ROLE_STATIC_TEXT = 20,
  CBSS_ROLE_LINK = 21,
  CBSS_ROLE_SWITCH = 22,
  CBSS_ROLE_PASSWORD_TEXT = 23
} CbssAccessibleRole;

typedef enum CbssHitKind {
  CBSS_HIT_CONTENT = 0,
  CBSS_HIT_SCROLLBAR_TRACK_X = 1,
  CBSS_HIT_SCROLLBAR_THUMB_X = 2,
  CBSS_HIT_SCROLLBAR_TRACK_Y = 3,
  CBSS_HIT_SCROLLBAR_THUMB_Y = 4
} CbssHitKind;

typedef enum CbssCursor {
  CBSS_CURSOR_AUTO = 0,
  CBSS_CURSOR_DEFAULT = 1,
  CBSS_CURSOR_POINTER = 2,
  CBSS_CURSOR_TEXT = 3,
  CBSS_CURSOR_MOVE = 4,
  CBSS_CURSOR_NOT_ALLOWED = 5
} CbssCursor;

typedef enum CbssPaintKind {
  CBSS_PAINT_PUSH_CLIP = 0,
  CBSS_PAINT_POP_CLIP = 1,
  CBSS_PAINT_BOX_SHADOW = 2,
  CBSS_PAINT_FILL_RECT = 3,
  CBSS_PAINT_FILL_LINEAR_GRADIENT = 4,
  CBSS_PAINT_STROKE_RECT = 5,
  CBSS_PAINT_DRAW_TEXT = 6,
  CBSS_PAINT_DRAW_IMAGE = 7,
  CBSS_PAINT_STROKE_PATH = 8,
  CBSS_PAINT_PUSH_TRANSFORM = 9,
  CBSS_PAINT_POP_TRANSFORM = 10,
  CBSS_PAINT_PUSH_LAYER = 11,
  CBSS_PAINT_POP_LAYER = 12,
  CBSS_PAINT_DRAW_RASTER_SURFACE = 13
} CbssPaintKind;

typedef enum CbssLayerCompositeMode {
  CBSS_LAYER_SOURCE_OVER = 0,
  CBSS_LAYER_COPY = 1,
  CBSS_LAYER_ADDITIVE = 2
} CbssLayerCompositeMode;

typedef enum CbssPathSegmentKind {
  CBSS_PATH_MOVE_TO = 0,
  CBSS_PATH_LINE_TO = 1,
  CBSS_PATH_QUADRATIC_TO = 2,
  CBSS_PATH_CUBIC_TO = 3,
  CBSS_PATH_CLOSE = 4
} CbssPathSegmentKind;

typedef enum CbssStrokeLineCap {
  CBSS_STROKE_CAP_BUTT = 0,
  CBSS_STROKE_CAP_ROUND = 1,
  CBSS_STROKE_CAP_SQUARE = 2
} CbssStrokeLineCap;

typedef enum CbssStrokeLineJoin {
  CBSS_STROKE_JOIN_MITER = 0,
  CBSS_STROKE_JOIN_ROUND = 1,
  CBSS_STROKE_JOIN_BEVEL = 2
} CbssStrokeLineJoin;

typedef struct CbssRect {
  float x;
  float y;
  float w;
  float h;
} CbssRect;

typedef struct CbssRasterRegion {
  uint32_t x;
  uint32_t y;
  uint32_t width;
  uint32_t height;
} CbssRasterRegion;

typedef struct CbssColor {
  float r;
  float g;
  float b;
  float a;
} CbssColor;

typedef struct CbssAffineTransform {
  float m11;
  float m12;
  float m21;
  float m22;
  float tx;
  float ty;
} CbssAffineTransform;

typedef struct CbssPathSegment {
  uint32_t kind;
  float control1_x;
  float control1_y;
  float control2_x;
  float control2_y;
  float endpoint_x;
  float endpoint_y;
} CbssPathSegment;

typedef enum CbssColorSpace {
  CBSS_COLOR_SRGB = 0,
  CBSS_COLOR_SRGB_LINEAR = 1,
  CBSS_COLOR_DISPLAY_P3 = 2,
  CBSS_COLOR_A98_RGB = 3,
  CBSS_COLOR_PROPHOTO_RGB = 4,
  CBSS_COLOR_REC2020 = 5,
  CBSS_COLOR_XYZ_D50 = 6,
  CBSS_COLOR_XYZ_D65 = 7,
  CBSS_COLOR_HSL = 8,
  CBSS_COLOR_HWB = 9,
  CBSS_COLOR_LAB = 10,
  CBSS_COLOR_LCH = 11,
  CBSS_COLOR_OKLAB = 12,
  CBSS_COLOR_OKLCH = 13,
  CBSS_COLOR_DISPLAY_P3_LINEAR = 14
} CbssColorSpace;

typedef enum CbssColorInterpolationSpace {
  CBSS_COLOR_INTERPOLATE_SRGB = 0,
  CBSS_COLOR_INTERPOLATE_SRGB_LINEAR = 1,
  CBSS_COLOR_INTERPOLATE_OKLAB = 2
} CbssColorInterpolationSpace;

enum {
  CBSS_COLOR_MISSING_FIRST = 1u << 0,
  CBSS_COLOR_MISSING_SECOND = 1u << 1,
  CBSS_COLOR_MISSING_THIRD = 1u << 2,
  CBSS_COLOR_MISSING_ALPHA = 1u << 3
};

enum {
  CBSS_COLOR_MIX_HAS_FIRST_PERCENTAGE = 1u << 0,
  CBSS_COLOR_MIX_HAS_SECOND_PERCENTAGE = 1u << 1
};

typedef struct CbssLayoutBox {
  uint32_t node;
  CbssRect rect;
  int32_t z_index;
} CbssLayoutBox;

typedef struct CbssHitResult {
  uint32_t node;
  float local_x;
  float local_y;
  uint32_t kind;
  uint32_t cursor;
  uint8_t has_cursor;
} CbssHitResult;

/*
 * value fields depend on kind:
 * BOX_SHADOW: offset_x, offset_y, blur, spread
 * LINEAR_GRADIENT: angle, stop_count, interpolation_space
 * STROKE_RECT: width
 * STROKE_PATH: width, line_cap, line_join, miter_limit
 * DRAW_IMAGE: opacity
 * PUSH_LAYER: opacity, layer_composite_mode
 */
typedef struct CbssPaintCommand {
  uint32_t kind;
  uint32_t owner;
  CbssRect rect;
  CbssColor color;
  float radius;
  float value0;
  float value1;
  float value2;
  float value3;
  uint32_t string_bytes;
} CbssPaintCommand;

enum {
  CBSS_TEXT_HAS_FONT_SIZE = 1u << 0,
  CBSS_TEXT_HAS_LINE_HEIGHT = 1u << 1,
  CBSS_TEXT_HAS_FONT_WEIGHT = 1u << 2,
  CBSS_TEXT_HAS_LETTER_SPACING = 1u << 3,
  CBSS_TEXT_HAS_FONT_STYLE = 1u << 4
};

typedef struct CbssTextStyle {
  uint32_t flags;
  float font_size;
  float line_height;
  float font_weight;
  float letter_spacing;
  uint32_t font_style;
} CbssTextStyle;

typedef struct CbssGradientStop {
  CbssColor color;
  float offset;
} CbssGradientStop;

typedef struct CbssColorValueGradientStop {
  const CbssColorValue *color;
  float offset;
} CbssColorValueGradientStop;

typedef struct CbssTransformOperation {
  uint32_t kind;
  uint32_t flags;
  uint32_t x_unit;
  uint32_t y_unit;
  uint32_t z_unit;
  float x;
  float y;
  float z;
  float angle;
} CbssTransformOperation;

/* Axis bits distinguish an unsupported axis from a supported zero value. */
typedef struct CbssPointerData {
  uint32_t device;
  uint32_t axes;
  uint64_t device_id;
  float pressure;
  float tangential_pressure;
  float tilt_x;
  float tilt_y;
  float rotation;
  float distance;
  float slider;
  uint32_t buttons;
  uint8_t contact;
  uint8_t primary;
  uint8_t eraser;
  uint8_t in_proximity;
} CbssPointerData;

typedef struct CbssInputEvent {
  uint32_t kind;
  uint32_t flags;
  uint32_t modifiers;
  int32_t button;
  float x;
  float y;
  float delta_x;
  float delta_y;
  const char *key;
  const char *text;
  CbssPointerData pointer;
  uint64_t timestamp;
} CbssInputEvent;

/*
 * key, text, and motion_name point to CBSS-owned temporary memory. They are
 * valid only during the callback and must be copied if the host retains them.
 */
typedef struct CbssEvent {
  uint32_t kind;
  uint32_t target;
  uint32_t current_target;
  uint32_t flags;
  float local_x;
  float local_y;
  float x;
  float y;
  float delta_x;
  float delta_y;
  int32_t button;
  uint32_t modifiers;
  const char *key;
  const char *text;
  CbssPointerData pointer;
  uint64_t timestamp;
  const char *motion_name;
  double motion_elapsed_seconds;
  uint64_t motion_iteration;
} CbssEvent;

typedef struct CbssMotionState {
  uint32_t active_animations;
  uint32_t active_transitions;
  uint32_t sampled_animations;
  uint32_t sampled_transitions;
  uint32_t dirty_domains;
  uint8_t has_deadline;
  uint8_t reduced_motion;
  double next_deadline;
  double now_seconds;
} CbssMotionState;

typedef struct CbssDispatchSummary {
  uint32_t target;
  uint32_t dispatch_count;
  uint8_t handled;
  uint8_t outcome;
  uint8_t needs_compute;
  uint8_t paint_changed;
  uint8_t focus_changed;
} CbssDispatchSummary;

typedef struct CbssScrollMetrics {
  float offset_x;
  float offset_y;
  float viewport_width;
  float viewport_height;
  float content_width;
  float content_height;
  float max_offset_x;
  float max_offset_y;
  uint8_t enabled_x;
  uint8_t enabled_y;
  uint8_t scrolling;
} CbssScrollMetrics;

typedef struct CbssAccessibility {
  uint32_t role;
  uint32_t flags;
  float value_now;
  float value_min;
  float value_max;
  uint32_t labelled_by;
  uint32_t described_by;
  uint8_t hidden;
} CbssAccessibility;

typedef struct CbssAccessibleSetPosition {
  uint32_t flags;
  int64_t position_in_set;
  int64_t set_size;
} CbssAccessibleSetPosition;

typedef enum CbssRenderSurfaceEventKind {
  CBSS_SURFACE_MOUNT = 0,
  CBSS_SURFACE_UPDATE = 1,
  CBSS_SURFACE_RESIZE = 2,
  CBSS_SURFACE_INPUT = 3,
  CBSS_SURFACE_FRAME = 4,
  CBSS_SURFACE_VISIBILITY = 5,
  CBSS_SURFACE_DEVICE_LOST = 6,
  CBSS_SURFACE_DEVICE_RESTORED = 7,
  CBSS_SURFACE_UNMOUNT = 8
} CbssRenderSurfaceEventKind;

enum {
  CBSS_SURFACE_VISIBLE = 1u << 0,
  CBSS_SURFACE_INSIDE = 1u << 1,
  CBSS_SURFACE_CAPTURED = 1u << 2,
  CBSS_SURFACE_HAS_LOCAL_POSITION = 1u << 3
};

enum {
  CBSS_SURFACE_HANDLED = 1u << 0,
  CBSS_SURFACE_REQUEST_NEXT_FRAME = 1u << 1
};

typedef struct CbssRenderSurfacePlacement {
  CbssRect bounds;
  CbssRect clip;
  float pixel_scale;
  float opacity;
} CbssRenderSurfacePlacement;

typedef struct CbssRenderSurfaceEvent {
  uint32_t kind;
  uint32_t flags;
  uint64_t surface;
  uint32_t node;
  uint32_t api_version;
  uint64_t revision;
  uint64_t frame_number;
  double now_seconds;
  double delta_seconds;
  CbssRenderSurfacePlacement placement;
  float local_x;
  float local_y;
  float logical_width;
  float logical_height;
  float pixel_width;
  float pixel_height;
  CbssInputEvent input;
} CbssRenderSurfaceEvent;

typedef struct CbssStreamPumpResult {
  uint32_t processed;
  uint32_t rejected;
  uint8_t changed;
  uint8_t backpressured;
  uint8_t pending;
} CbssStreamPumpResult;

/*
 * A DATA event transfers one owning Blob reference to `blob`; release it with
 * cbss_blob_release. Other event kinds leave `blob` null.
 */
typedef struct CbssStreamEvent {
  uint32_t kind;
  uint32_t flags;
  CbssBlob *blob;
  uint64_t weight;
  uint64_t completed;
  uint64_t total;
  uint32_t message_bytes;
} CbssStreamEvent;

/* Return a bitwise combination of CBSS_EVENT_OUTCOME_* values. */
typedef uint8_t (*CbssEventCallback)(
    CbssContext *context, const CbssEvent *event, void *user_data);
/*
 * EventView is borrowed for the callback duration. Accessors return either a
 * borrowed base event or an explicitly retained payload handle.
 */
typedef uint8_t (*CbssEventViewCallback)(
    CbssContext *context, const CbssEventView *view, void *user_data);
typedef uint32_t (*CbssRenderSurfaceCallback)(
    CbssContext *context, const CbssRenderSurfaceEvent *event,
    void *user_data);
/* Post a host-loop wake only. Do not re-enter or destroy the stream. */
typedef void (*CbssStreamWakeCallback)(void *user_data);
/*
 * Reads at most capacity bytes and writes the actual count to output_read.
 * The callback is synchronous. CBSS serializes reads for one Blob, but it may
 * call different providers concurrently. Do not re-enter the same Blob from
 * its callback. Return a defined CbssStatus; unknown values become
 * CBSS_INTERNAL_ERROR.
 */
typedef CbssStatus (*CbssBlobProviderReadCallback)(
    void *user_data, uint64_t offset, uint8_t *output, uint32_t capacity,
    uint32_t *output_read);
typedef void (*CbssBlobProviderReleaseCallback)(void *user_data);

CBSS_API uint32_t cbss_abi_version(void);
/*
 * Craft Drivers should negotiate this contract before constructing a tree.
 * Capability names are stable diagnostics; numeric ids are the comparison key.
 */
CBSS_API uint32_t cbss_driver_contract_version(void);
CBSS_API uint32_t cbss_capability_count(void);
CBSS_API CbssStatus cbss_capability_at(
    uint32_t index, CbssCapabilityInfo *output);
CBSS_API uint8_t cbss_has_capability(
    uint32_t capability, uint32_t minimum_version);
CBSS_API uint32_t cbss_capability_name(
    uint32_t capability, char *buffer, uint32_t capacity);
/*
 * Foreign worker threads must attach before calling CBSS and detach before
 * exiting. Language wrappers should hide this pair in their worker adapter.
 */
CBSS_API void cbss_thread_attach(void);
CBSS_API void cbss_thread_detach(void);

/*
 * Build-time typed shader authoring. Expressions are builder-local ids; zero
 * is invalid. emit validates the graph and produces deterministic bgfx shader
 * source plus varying definitions. Applications compile those files during
 * their build and pass the resulting bytes through the GPU Host contract.
 * The ordinary runtime does not invoke or ship a shader compiler.
 */
CBSS_API CbssStatus cbss_shader_builder_create(
    CbssShaderStage stage, const char *label, CbssShaderBuilder **output);
CBSS_API void cbss_shader_builder_destroy(CbssShaderBuilder *builder);
CBSS_API uint32_t cbss_shader_builder_last_error(
    const CbssShaderBuilder *builder, char *buffer, uint32_t capacity);
CBSS_API CbssStatus cbss_shader_builder_literal(
    CbssShaderBuilder *builder, float value, CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_vector_literal(
    CbssShaderBuilder *builder, const float *values, uint32_t count,
    CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_vertex_input(
    CbssShaderBuilder *builder, CbssShaderInterfaceSlot slot,
    CbssShaderValueType value_type, CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_varying_input(
    CbssShaderBuilder *builder, CbssShaderInterfaceSlot slot,
    CbssShaderValueType value_type, CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_uniform(
    CbssShaderBuilder *builder, const char *name,
    CbssShaderValueType value_type, CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_construct(
    CbssShaderBuilder *builder, CbssShaderValueType value_type,
    const CbssShaderExpression *expressions, uint32_t count,
    CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_swizzle(
    CbssShaderBuilder *builder, CbssShaderExpression expression,
    const char *components, CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_unary(
    CbssShaderBuilder *builder, CbssShaderUnaryOperation operation,
    CbssShaderExpression expression, CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_binary(
    CbssShaderBuilder *builder, CbssShaderBinaryOperation operation,
    CbssShaderExpression left, CbssShaderExpression right,
    CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_ternary(
    CbssShaderBuilder *builder, CbssShaderTernaryOperation operation,
    CbssShaderExpression first, CbssShaderExpression second,
    CbssShaderExpression third, CbssShaderExpression *output);
CBSS_API CbssStatus cbss_shader_builder_set_position_output(
    CbssShaderBuilder *builder, CbssShaderExpression expression);
CBSS_API CbssStatus cbss_shader_builder_set_color_output(
    CbssShaderBuilder *builder, CbssShaderExpression expression,
    uint32_t index);
CBSS_API CbssStatus cbss_shader_builder_set_varying_output(
    CbssShaderBuilder *builder, CbssShaderInterfaceSlot slot,
    CbssShaderExpression expression);
CBSS_API CbssStatus cbss_shader_builder_emit(CbssShaderBuilder *builder);
CBSS_API CbssStatus cbss_shader_builder_validate_graphics(
    CbssShaderBuilder *vertex, CbssShaderBuilder *fragment);
CBSS_API uint32_t cbss_shader_builder_source(
    const CbssShaderBuilder *builder, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_shader_builder_varying_definitions(
    const CbssShaderBuilder *builder, char *buffer, uint32_t capacity);

/*
 * Retained, UI-owned RGBA8/sRGB/straight-alpha pixels. Updates copy caller
 * bytes into pending storage. publish makes all pending regions visible as one
 * revision. source_stride is measured in bytes; zero selects width * 4.
 */
CBSS_API CbssStatus cbss_raster_surface_create(
    uint32_t width, uint32_t height, const uint8_t *initial_rgba,
    CbssRasterSurface **output);
CBSS_API void cbss_raster_surface_destroy(CbssRasterSurface *surface);
CBSS_API uint32_t cbss_raster_surface_width(
    const CbssRasterSurface *surface);
CBSS_API uint32_t cbss_raster_surface_height(
    const CbssRasterSurface *surface);
CBSS_API uint64_t cbss_raster_surface_revision(
    const CbssRasterSurface *surface);
CBSS_API CbssStatus cbss_raster_surface_update_region(
    CbssRasterSurface *surface, CbssRasterRegion region,
    const uint8_t *bytes, uint64_t byte_length, uint32_t source_stride);
CBSS_API CbssStatus cbss_raster_surface_publish(
    CbssRasterSurface *surface, uint64_t *output_revision);
CBSS_API uint32_t cbss_raster_surface_dirty_region_count(
    const CbssRasterSurface *surface);
CBSS_API CbssStatus cbss_raster_surface_dirty_region_at(
    const CbssRasterSurface *surface, uint32_t index,
    CbssRasterRegion *output);

CBSS_API CbssStatus cbss_blob_create(
    const uint8_t *bytes, uint64_t length, const char *mime_type,
    CbssBlob **output);
/*
 * Defines a host-authorized, fixed-size Blob without eagerly copying its data.
 * Takes ownership of user_data on success only. The release callback runs
 * exactly once after the last Blob reference and may run on the thread that
 * releases that reference. Provider reads are serialized by CBSS. Callbacks
 * must not release or otherwise re-enter the same Blob.
 */
CBSS_API CbssStatus cbss_blob_create_provider(
    uint64_t length, const char *mime_type,
    CbssBlobProviderReadCallback read_callback,
    CbssBlobProviderReleaseCallback release_callback, void *user_data,
    CbssBlob **output);
CBSS_API CbssStatus cbss_blob_retain(CbssBlob *blob);
CBSS_API void cbss_blob_release(CbssBlob *blob);
CBSS_API uint64_t cbss_blob_size(const CbssBlob *blob);
CBSS_API uint32_t cbss_blob_mime_type(
    const CbssBlob *blob, char *buffer, uint32_t capacity);
CBSS_API CbssStatus cbss_blob_read(
    const CbssBlob *blob, uint64_t offset, uint8_t *output,
    uint32_t capacity, uint32_t *output_read);

/*
 * Blob streams are UI-owned. Producer handles are atomically retained and may
 * cross thread boundaries. Build the C ABI library with Nim thread support.
 */
CBSS_API CbssStatus cbss_blob_stream_create(
    uint32_t max_queued_items, uint64_t max_queued_weight,
    CbssBlobStream **output);
CBSS_API void cbss_blob_stream_destroy(CbssBlobStream *stream);
CBSS_API CbssStatus cbss_blob_stream_producer(
    CbssBlobStream *stream, CbssStreamProducer **output);
CBSS_API CbssStatus cbss_stream_producer_retain(
    CbssStreamProducer *producer);
CBSS_API void cbss_stream_producer_release(CbssStreamProducer *producer);
/*
 * Replacing or clearing a wake callback waits for an in-flight callback before
 * returning. The host may then release the previous user_data safely.
 */
CBSS_API CbssStatus cbss_blob_stream_set_wake_callback(
    CbssBlobStream *stream, CbssStreamWakeCallback callback,
    void *user_data);
CBSS_API uint32_t cbss_stream_producer_state(
    const CbssStreamProducer *producer);
CBSS_API uint32_t cbss_stream_producer_open(CbssStreamProducer *producer);
CBSS_API uint32_t cbss_stream_producer_push_blob(
    CbssStreamProducer *producer, CbssBlob *blob, uint64_t weight);
CBSS_API uint32_t cbss_stream_producer_progress(
    CbssStreamProducer *producer, uint64_t completed, uint64_t total,
    uint8_t has_total);
CBSS_API uint32_t cbss_stream_producer_finish(
    CbssStreamProducer *producer);
CBSS_API uint32_t cbss_stream_producer_fail(
    CbssStreamProducer *producer, const char *message);
CBSS_API uint32_t cbss_stream_producer_cancel(
    CbssStreamProducer *producer);
CBSS_API uint32_t cbss_stream_producer_close(
    CbssStreamProducer *producer);
/* Pump and next must be called by the stream's owning UI thread. */
CBSS_API CbssStatus cbss_blob_stream_pump(
    CbssBlobStream *stream, uint32_t max_messages,
    CbssStreamPumpResult *output);
CBSS_API CbssStatus cbss_blob_stream_next(
    CbssBlobStream *stream, CbssStreamEvent *output);
CBSS_API uint32_t cbss_blob_stream_error_message(
    const CbssBlobStream *stream, char *buffer, uint32_t capacity);
CBSS_API uint8_t cbss_blob_stream_has_pending(
    const CbssBlobStream *stream);

CBSS_API CbssFormDataBuilder *cbss_form_data_builder_create(void);
CBSS_API void cbss_form_data_builder_destroy(CbssFormDataBuilder *builder);
CBSS_API CbssStatus cbss_form_data_builder_add_text(
    CbssFormDataBuilder *builder, const char *name, const char *value);
CBSS_API CbssStatus cbss_form_data_builder_add_blob(
    CbssFormDataBuilder *builder, const char *name, CbssBlob *blob,
    const char *file_name);
CBSS_API CbssStatus cbss_form_data_builder_finish(
    CbssFormDataBuilder *builder, CbssFormData **output);
CBSS_API CbssStatus cbss_form_data_retain(CbssFormData *data);
CBSS_API void cbss_form_data_release(CbssFormData *data);
CBSS_API uint32_t cbss_form_data_length(const CbssFormData *data);
CBSS_API CbssStatus cbss_form_data_entry_kind(
    const CbssFormData *data, uint32_t index, uint32_t *output);
CBSS_API uint32_t cbss_form_data_entry_name(
    const CbssFormData *data, uint32_t index, char *buffer,
    uint32_t capacity);
CBSS_API uint32_t cbss_form_data_entry_text(
    const CbssFormData *data, uint32_t index, char *buffer,
    uint32_t capacity);
CBSS_API uint32_t cbss_form_data_entry_file_name(
    const CbssFormData *data, uint32_t index, char *buffer,
    uint32_t capacity);
/* The returned Blob owns one retained reference and must be released. */
CBSS_API CbssStatus cbss_form_data_entry_blob(
    const CbssFormData *data, uint32_t index, CbssBlob **output);

/* The returned event pointer is borrowed for the callback duration. */
CBSS_API const CbssEvent *cbss_event_view_event(
    const CbssEventView *view);
/* The returned FormData owns one retained reference and must be released. */
CBSS_API CbssStatus cbss_event_view_form_data(
    const CbssEventView *view, CbssFormData **output);

CBSS_API CbssContext *cbss_context_create(void);
CBSS_API void cbss_context_destroy(CbssContext *context);
CBSS_API CbssStatus cbss_context_reset(CbssContext *context);
CBSS_API uint32_t cbss_context_last_error(
    CbssContext *context, char *buffer, uint32_t capacity);
/*
 * Craft Style and Craft Pack sources are borrowed for the call duration and
 * copied into CBSS-owned values on success. Failed replacements leave the
 * previous retained Style or Pack active. Diagnostics remain owned by the
 * context until the next Craft operation or reset.
 */
CBSS_API uint32_t cbss_context_craft_diagnostic_count(
    CbssContext *context);
CBSS_API CbssStatus cbss_context_craft_diagnostic_at(
    CbssContext *context, uint32_t index, CbssCraftDiagnostic *output);
CBSS_API uint32_t cbss_context_craft_diagnostic_path(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_context_craft_diagnostic_message(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API CbssStatus cbss_node_expose_craft_style_slot(
    CbssContext *context, uint32_t owner, uint32_t target,
    const char *component, const char *slot);
CBSS_API CbssStatus cbss_context_replace_craft_style_json(
    CbssContext *context, const uint8_t *bytes, uint32_t length);
CBSS_API CbssStatus cbss_context_remove_craft_style(
    CbssContext *context, const char *name, uint8_t *output_removed);
CBSS_API uint32_t cbss_context_active_craft_style_count(
    CbssContext *context);
CBSS_API uint32_t cbss_context_active_craft_style_name(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API CbssStatus cbss_context_replace_craft_pack_json(
    CbssContext *context, const uint8_t *bytes, uint32_t length);
CBSS_API CbssStatus cbss_context_remove_craft_pack(
    CbssContext *context, const char *id, uint8_t *output_removed);
CBSS_API uint32_t cbss_context_active_craft_pack_count(
    CbssContext *context);
CBSS_API uint32_t cbss_context_active_craft_pack_id(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_context_active_craft_pack_version(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_context_node_count(CbssContext *context);
CBSS_API uint32_t cbss_node_kind(
    CbssContext *context, uint32_t node);
CBSS_API uint32_t cbss_node_parent(
    CbssContext *context, uint32_t node);
CBSS_API uint32_t cbss_node_child_count(
    CbssContext *context, uint32_t node);
CBSS_API uint32_t cbss_node_child(
    CbssContext *context, uint32_t node, uint32_t index);
CBSS_API uint32_t cbss_node_identifier(
    CbssContext *context, uint32_t node, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_node_text(
    CbssContext *context, uint32_t node, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_node_image_source(
    CbssContext *context, uint32_t node, char *buffer, uint32_t capacity);
/*
 * Atomically removes node and all descendants from the retained tree. Event,
 * interaction, Style, motion, scroll, Craft Style Slot, and Render Surface
 * state owned by the removed subtree is released before the Node IDs become
 * invalid. output_removed_count is required and receives zero on rejection.
 */
CBSS_API CbssStatus cbss_context_remove_subtree(
    CbssContext *context, uint32_t node, uint32_t *output_removed_count);

CBSS_API uint32_t cbss_context_add_box(
    CbssContext *context, uint32_t parent, const char *identifier);
CBSS_API uint32_t cbss_context_add_text(
    CbssContext *context, uint32_t parent, const char *text,
    const char *identifier);
CBSS_API uint32_t cbss_context_add_image(
    CbssContext *context, uint32_t parent, const char *source,
    float width, float height, const char *identifier);
CBSS_API CbssStatus cbss_context_register_render_surface(
    CbssContext *context, const char *name,
    CbssRenderSurfaceCallback callback, void *user_data,
    uint64_t *output_surface);
CBSS_API CbssStatus cbss_context_unregister_render_surface(
    CbssContext *context, uint64_t surface);
CBSS_API uint32_t cbss_context_add_render_surface(
    CbssContext *context, uint32_t parent, uint64_t surface,
    const char *identifier);
CBSS_API CbssStatus cbss_render_surface_update(
    CbssContext *context, uint64_t surface, uint64_t revision);
CBSS_API CbssStatus cbss_render_surface_request_frame(
    CbssContext *context, uint64_t surface);
CBSS_API CbssStatus cbss_context_run_render_surface_frames(
    CbssContext *context, double now_seconds, uint32_t *output_count);
CBSS_API uint8_t cbss_context_needs_render_surface_frame(
    CbssContext *context);
CBSS_API CbssStatus cbss_render_surface_set_device_available(
    CbssContext *context, uint64_t surface, uint8_t available);
CBSS_API CbssStatus cbss_render_surface_canvas_clear(
    CbssContext *context, uint64_t surface);
CBSS_API CbssStatus cbss_render_surface_canvas_save(
    CbssContext *context, uint64_t surface);
CBSS_API CbssStatus cbss_render_surface_canvas_restore(
    CbssContext *context, uint64_t surface);
CBSS_API CbssStatus cbss_render_surface_canvas_transform(
    CbssContext *context, uint64_t surface,
    CbssAffineTransform transform);
CBSS_API CbssStatus cbss_render_surface_canvas_push_clip(
    CbssContext *context, uint64_t surface,
    CbssRect bounds, float radius);
CBSS_API CbssStatus cbss_render_surface_canvas_pop_clip(
    CbssContext *context, uint64_t surface);
CBSS_API CbssStatus cbss_render_surface_canvas_begin_layer(
    CbssContext *context, uint64_t surface, CbssRect bounds,
    float opacity, uint32_t composite_mode);
CBSS_API CbssStatus cbss_render_surface_canvas_end_layer(
    CbssContext *context, uint64_t surface);
CBSS_API CbssStatus cbss_render_surface_canvas_fill_rect(
    CbssContext *context, uint64_t surface, CbssRect bounds,
    CbssColor color, float radius);
CBSS_API CbssStatus cbss_render_surface_canvas_fill_linear_gradient(
    CbssContext *context, uint64_t surface, CbssRect bounds,
    float angle, uint32_t interpolation_space,
    const CbssGradientStop *stops, uint32_t stop_count, float radius);
CBSS_API CbssStatus cbss_render_surface_canvas_stroke_rect(
    CbssContext *context, uint64_t surface, CbssRect bounds,
    CbssColor color, float width, float radius);
CBSS_API CbssStatus cbss_render_surface_canvas_stroke_path(
    CbssContext *context, uint64_t surface,
    const CbssPathSegment *segments, uint32_t segment_count,
    CbssColor color, float width, uint32_t line_cap,
    uint32_t line_join, float miter_limit);
CBSS_API CbssStatus cbss_render_surface_canvas_draw_text(
    CbssContext *context, uint64_t surface, const char *text,
    float x, float y, CbssColor color, const CbssTextStyle *style,
    const char *font_family, float max_width, uint8_t has_max_width);
CBSS_API CbssStatus cbss_render_surface_canvas_draw_image(
    CbssContext *context, uint64_t surface, const char *source,
    CbssRect bounds, float opacity);
CBSS_API CbssStatus cbss_render_surface_canvas_draw_raster_surface(
    CbssContext *context, uint64_t surface,
    CbssRasterSurface *raster_surface, CbssRect bounds, float opacity);
CBSS_API CbssStatus cbss_render_surface_canvas_commit(
    CbssContext *context, uint64_t surface, uint64_t *output_revision);
CBSS_API CbssStatus cbss_context_set_pixel_scale(
    CbssContext *context, float pixel_scale);

CBSS_API CbssStatus cbss_node_set_text(
    CbssContext *context, uint32_t node, const char *text);
CBSS_API CbssStatus cbss_node_set_image(
    CbssContext *context, uint32_t node, const char *source,
    float width, float height);
CBSS_API CbssStatus cbss_node_add_group(
    CbssContext *context, uint32_t node, const char *group);
CBSS_API CbssStatus cbss_node_set_attribute(
    CbssContext *context, uint32_t node, const char *name, const char *value);
CBSS_API CbssStatus cbss_node_set_state(
    CbssContext *context, uint32_t node, uint32_t state, uint8_t enabled);
CBSS_API CbssStatus cbss_node_set_accessibility(
    CbssContext *context, uint32_t node, uint32_t role,
    const char *name, const char *description);
CBSS_API CbssStatus cbss_node_set_accessible_value(
    CbssContext *context, uint32_t node, const char *value);
CBSS_API CbssStatus cbss_node_set_accessible_range(
    CbssContext *context, uint32_t node, uint32_t flags,
    float value_now, float value_min, float value_max);
CBSS_API CbssStatus cbss_node_set_accessible_set_position(
    CbssContext *context, uint32_t node, uint32_t flags,
    int64_t position_in_set, int64_t set_size);
CBSS_API CbssStatus cbss_node_set_accessible_relations(
    CbssContext *context, uint32_t node,
    uint32_t labelled_by, uint32_t described_by);
CBSS_API CbssStatus cbss_node_set_accessible_hidden(
    CbssContext *context, uint32_t node, uint8_t hidden);
CBSS_API CbssStatus cbss_node_accessibility(
    CbssContext *context, uint32_t node, CbssAccessibility *output);
CBSS_API CbssStatus cbss_node_accessible_set_position(
    CbssContext *context, uint32_t node,
    CbssAccessibleSetPosition *output);
CBSS_API uint32_t cbss_node_accessible_name(
    CbssContext *context, uint32_t node, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_node_accessible_description(
    CbssContext *context, uint32_t node, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_node_accessible_value(
    CbssContext *context, uint32_t node, char *buffer, uint32_t capacity);
CBSS_API CbssStatus cbss_node_set_focusable(
    CbssContext *context, uint32_t node, uint8_t focusable,
    int32_t tab_index);
CBSS_API CbssStatus cbss_node_set_inert(
    CbssContext *context, uint32_t node, uint8_t inert);
CBSS_API uint8_t cbss_node_inert(CbssContext *context, uint32_t node);
CBSS_API CbssStatus cbss_node_set_event_handler(
    CbssContext *context, uint32_t node, uint32_t kind,
    CbssEventCallback callback, void *user_data);
CBSS_API CbssStatus cbss_node_set_default_action(
    CbssContext *context, uint32_t node, uint32_t kind,
    CbssEventCallback callback, void *user_data);
CBSS_API CbssStatus cbss_node_subscribe_event(
    CbssContext *context, uint32_t node, uint32_t kind,
    CbssEventCallback callback, void *user_data,
    CbssEventSubscription *output_subscription);
CBSS_API CbssStatus cbss_node_set_event_view_handler(
    CbssContext *context, uint32_t node, uint32_t kind,
    CbssEventViewCallback callback, void *user_data);
CBSS_API CbssStatus cbss_node_subscribe_event_view(
    CbssContext *context, uint32_t node, uint32_t kind,
    CbssEventViewCallback callback, void *user_data,
    CbssEventSubscription *output_subscription);
CBSS_API CbssStatus cbss_context_unsubscribe_event(
    CbssContext *context, CbssEventSubscription subscription);

CBSS_API CbssStatus cbss_color_value_create(
    uint32_t space, float first, float second, float third, float alpha,
    uint32_t missing_mask, CbssColorValue **output);
CBSS_API CbssStatus cbss_color_value_current(CbssColorValue **output);
CBSS_API CbssStatus cbss_color_value_parse(
    const char *input, CbssColorValue **output,
    char *error_buffer, uint32_t error_capacity);
CBSS_API CbssStatus cbss_color_mix_parse(
    const char *input, CbssColorValue **output,
    char *error_buffer, uint32_t error_capacity);
CBSS_API CbssStatus cbss_color_mix_create(
    const CbssColorValue *first, const CbssColorValue *second,
    uint32_t interpolation_space, uint32_t flags,
    float first_percentage, float second_percentage,
    CbssColorValue **output);
CBSS_API CbssStatus cbss_color_value_resolve(
    const CbssColorValue *value, CbssColor current, CbssColor *output);
CBSS_API void cbss_color_value_destroy(CbssColorValue *value);

/* Compiled validation patterns use the canonical CBSS regex engine. */
CBSS_API CbssStatus cbss_validation_pattern_compile(
    const void *source,
    uint32_t length,
    CbssValidationPattern **output,
    char *error_buffer,
    uint32_t error_capacity);
CBSS_API CbssStatus cbss_validation_pattern_matches(
    const CbssValidationPattern *pattern,
    const void *value,
    uint32_t length,
    uint8_t *output);
CBSS_API void cbss_validation_pattern_destroy(CbssValidationPattern *pattern);
CBSS_API CbssStatus cbss_validation_string_format(
    CbssValidationStringFormat format,
    const void *value,
    uint32_t length,
    uint8_t *output);

CBSS_API CbssStyle *cbss_style_create(void);
CBSS_API void cbss_style_destroy(CbssStyle *style);
CBSS_API CbssStatus cbss_style_clear(CbssStyle *style);
CBSS_API CbssStatus cbss_keyframes_create(
    const char *name, CbssKeyframes **output);
CBSS_API void cbss_keyframes_destroy(CbssKeyframes *keyframes);
CBSS_API CbssStatus cbss_keyframes_clear(CbssKeyframes *keyframes);
/* The step declarations are copied; the source style may be reused or freed. */
CBSS_API CbssStatus cbss_keyframes_add_step(
    CbssKeyframes *keyframes, double offset, const CbssStyle *style);
/* Registration copies the complete definition into the context. */
CBSS_API CbssStatus cbss_context_register_keyframes(
    CbssContext *context, const CbssKeyframes *keyframes);
CBSS_API CbssStatus cbss_context_unregister_keyframes(
    CbssContext *context, const char *name);
CBSS_API uint8_t cbss_context_has_keyframes(
    const CbssContext *context, const char *name);
CBSS_API CbssStatus cbss_style_set_length(
    CbssStyle *style, const char *property, uint32_t unit, float value);
CBSS_API CbssStatus cbss_style_set_number(
    CbssStyle *style, const char *property, float value);
CBSS_API CbssStatus cbss_style_set_keyword(
    CbssStyle *style, const char *property, const char *value);
CBSS_API CbssStatus cbss_style_set_color(
    CbssStyle *style, const char *property, CbssColor color);
CBSS_API CbssStatus cbss_style_set_color_value(
    CbssStyle *style, const char *property, const CbssColorValue *value);
CBSS_API CbssStatus cbss_style_set_color_pair(
    CbssStyle *style, const char *property,
    CbssColor first, CbssColor second);
CBSS_API CbssStatus cbss_style_set_border(
    CbssStyle *style, const char *property, uint32_t flags,
    uint32_t width_unit, float width, const char *line_style,
    CbssColor color);
CBSS_API CbssStatus cbss_style_set_shadow(
    CbssStyle *style, const char *property,
    uint32_t offset_x_unit, float offset_x,
    uint32_t offset_y_unit, float offset_y,
    uint32_t flags, uint32_t blur_unit, float blur,
    uint32_t spread_unit, float spread, CbssColor color);
CBSS_API CbssStatus cbss_style_set_linear_gradient(
    CbssStyle *style, const char *property, float angle,
    const CbssGradientStop *stops, uint32_t stop_count);
CBSS_API CbssStatus cbss_style_set_linear_gradient_in(
    CbssStyle *style, const char *property, float angle,
    uint32_t interpolation_space,
    const CbssGradientStop *stops, uint32_t stop_count);
CBSS_API CbssStatus cbss_style_set_linear_gradient_color_values(
    CbssStyle *style, const char *property, float angle,
    uint32_t interpolation_space,
    const CbssColorValueGradientStop *stops, uint32_t stop_count);
CBSS_API CbssStatus cbss_style_set_transform_operation(
    CbssStyle *style, const char *property,
    CbssTransformOperation operation);
CBSS_API CbssStatus cbss_style_set_transform(
    CbssStyle *style, const char *property,
    const CbssTransformOperation *operations, uint32_t operation_count);
CBSS_API CbssStatus cbss_node_apply_style(
    CbssContext *context, uint32_t node, CbssStyle *style,
    uint32_t state_mask, int32_t priority);
CBSS_API CbssStatus cbss_node_clear_style(
    CbssContext *context, uint32_t node, uint32_t state_mask,
    int32_t priority);

CBSS_API CbssStatus cbss_context_compute(
    CbssContext *context, float width, float height);
CBSS_API CbssStatus cbss_context_compute_at(
    CbssContext *context, float width, float height, double now_seconds);
CBSS_API uint8_t cbss_context_needs_compute(CbssContext *context);
CBSS_API CbssStatus cbss_context_recompute(CbssContext *context);
CBSS_API CbssStatus cbss_context_recompute_at(
    CbssContext *context, double now_seconds);
CBSS_API CbssStatus cbss_context_advance_motion(
    CbssContext *context, double now_seconds, CbssMotionState *output);
CBSS_API CbssStatus cbss_context_motion_state(
    const CbssContext *context, CbssMotionState *output);
CBSS_API CbssStatus cbss_context_set_reduced_motion(
    CbssContext *context, uint8_t enabled);
CBSS_API uint32_t cbss_context_layout_box_count(CbssContext *context);
CBSS_API CbssStatus cbss_context_layout_box(
    CbssContext *context, uint32_t index, CbssLayoutBox *output);
CBSS_API CbssStatus cbss_node_layout_rect(
    CbssContext *context, uint32_t node, CbssRect *output);

CBSS_API uint32_t cbss_context_paint_command_count(CbssContext *context);
CBSS_API CbssStatus cbss_context_paint_command(
    CbssContext *context, uint32_t index, CbssPaintCommand *output);
CBSS_API uint32_t cbss_paint_command_string(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API CbssStatus cbss_paint_command_transform(
    CbssContext *context, uint32_t index, CbssAffineTransform *output);
CBSS_API uint32_t cbss_paint_command_path_segment_count(
    CbssContext *context, uint32_t index);
CBSS_API CbssStatus cbss_paint_command_path_segment(
    CbssContext *context, uint32_t command_index, uint32_t segment_index,
    CbssPathSegment *output);
CBSS_API CbssStatus cbss_paint_command_text_style(
    CbssContext *context, uint32_t index, CbssTextStyle *output);
CBSS_API uint32_t cbss_paint_command_font_family(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_paint_command_gradient_stop_count(
    CbssContext *context, uint32_t index);
CBSS_API CbssStatus cbss_paint_command_gradient_stop(
    CbssContext *context, uint32_t command_index, uint32_t stop_index,
    CbssGradientStop *output);

CBSS_API CbssStatus cbss_context_hit_test(
    CbssContext *context, float x, float y, CbssHitResult *output);

CBSS_API CbssStatus cbss_context_dispatch_input(
    CbssContext *context, const CbssInputEvent *input,
    CbssDispatchSummary *output);
CBSS_API CbssStatus cbss_context_emit_event(
    CbssContext *context, uint32_t node, const CbssInputEvent *event,
    CbssDispatchSummary *output);
CBSS_API CbssStatus cbss_context_emit_submit(
    CbssContext *context, uint32_t node, const CbssFormData *form_data,
    CbssDispatchSummary *output);
CBSS_API uint32_t cbss_context_focused_node(CbssContext *context);
CBSS_API uint32_t cbss_context_first_focusable(
    CbssContext *context, uint32_t root);
CBSS_API CbssStatus cbss_context_set_focus(
    CbssContext *context, uint32_t node, uint8_t focus_visible);
CBSS_API CbssStatus cbss_context_move_focus(
    CbssContext *context, int32_t direction);
CBSS_API CbssStatus cbss_context_set_focus_scope(
    CbssContext *context, uint32_t node);
CBSS_API CbssStatus cbss_context_capture_pointer(
    CbssContext *context, uint32_t node);
CBSS_API CbssStatus cbss_context_release_pointer(CbssContext *context);

CBSS_API CbssStatus cbss_node_scroll_metrics(
    CbssContext *context, uint32_t node, CbssScrollMetrics *output);
CBSS_API CbssStatus cbss_node_scroll_to(
    CbssContext *context, uint32_t node, float x, float y);
CBSS_API CbssStatus cbss_node_scroll_by(
    CbssContext *context, uint32_t node, float delta_x, float delta_y);
CBSS_API CbssStatus cbss_node_set_scrolling(
    CbssContext *context, uint32_t node, uint8_t scrolling);

CBSS_API uint32_t cbss_context_diagnostic_count(CbssContext *context);
CBSS_API uint32_t cbss_context_diagnostic_severity(
    CbssContext *context, uint32_t index);
CBSS_API uint32_t cbss_context_diagnostic_property(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);
CBSS_API uint32_t cbss_context_diagnostic_message(
    CbssContext *context, uint32_t index, char *buffer, uint32_t capacity);

#ifdef __cplusplus
}
#endif

#endif
