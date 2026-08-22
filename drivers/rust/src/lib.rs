//! High-level Rust Craft Driver for Clay Board Style System.

mod generated;
mod store;

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString, NulError};
use std::fmt;
use std::marker::PhantomData;
use std::os::raw::{c_char, c_float, c_int, c_uint, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr::NonNull;
use std::rc::{Rc, Weak};

pub use generated::{
    CapabilityDefinition, EventKind, ABI_VERSION, CAPABILITIES, CAPABILITY_ACCESSIBILITY_SEMANTICS,
    CAPABILITY_BLOB, CAPABILITY_CRAFT_PACK, CAPABILITY_CRAFT_STYLE, CAPABILITY_DECLARATIVE_MOTION,
    CAPABILITY_FLEX_LAYOUT, CAPABILITY_FOCUS, CAPABILITY_FORM_DATA, CAPABILITY_HIT_TEST,
    CAPABILITY_PAINT_COMMANDS, CAPABILITY_RENDER_SURFACE, CAPABILITY_RETAINED_CANVAS,
    CAPABILITY_RETAINED_SCROLL, CAPABILITY_RETAINED_TREE, CAPABILITY_STANDARD_EVENTS,
    CAPABILITY_STREAM, CAPABILITY_SUBTREE_LIFECYCLE, CAPABILITY_TYPED_STYLE,
    DRIVER_CONTRACT_VERSION,
};
pub use store::{Selector, Store, StoreSubscription};

pub const STATUS_OK: i32 = 0;
pub const STATUS_INVALID_ARGUMENT: i32 = 1;
pub const STATUS_INVALID_HANDLE: i32 = 2;
pub const STATUS_OUT_OF_RANGE: i32 = 3;
pub const STATUS_STYLE_ERROR: i32 = 4;
pub const STATUS_INTERNAL_ERROR: i32 = 5;
pub const STATUS_NOT_AVAILABLE: i32 = 6;
pub const CRAFT_DIAGNOSTIC_STYLE_PARSE: u32 = 0;
pub const CRAFT_DIAGNOSTIC_STYLE_REPLACEMENT: u32 = 1;
pub const CRAFT_DIAGNOSTIC_PACK: u32 = 2;
pub const CRAFT_STYLE_PARSE_INVALID_JSON: u32 = 0;
pub const CRAFT_STYLE_PARSE_INVALID_DOCUMENT: u32 = 1;
pub const CRAFT_STYLE_PARSE_UNSUPPORTED_VERSION: u32 = 2;
pub const CRAFT_STYLE_PARSE_MISSING_FIELD: u32 = 3;
pub const CRAFT_STYLE_PARSE_UNKNOWN_FIELD: u32 = 4;
pub const CRAFT_STYLE_PARSE_INVALID_TYPE: u32 = 5;
pub const CRAFT_STYLE_PARSE_INVALID_VALUE: u32 = 6;
pub const CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY: u32 = 7;
pub const CRAFT_STYLE_PARSE_DUPLICATE_FIELD: u32 = 8;
pub const CRAFT_STYLE_PARSE_LIMIT_EXCEEDED: u32 = 9;
pub const CRAFT_STYLE_REPLACEMENT_UNSUPPORTED_RULE_TARGET: u32 = 0;
pub const CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT: u32 = 1;
pub const CRAFT_STYLE_REPLACEMENT_INVALID_STYLE_SLOT: u32 = 2;
pub const CRAFT_STYLE_REPLACEMENT_INVALID_CRAFT_STYLE: u32 = 3;
pub const CRAFT_PACK_INVALID_JSON: u32 = 0;
pub const CRAFT_PACK_INVALID_DOCUMENT: u32 = 1;
pub const CRAFT_PACK_UNSUPPORTED_VERSION: u32 = 2;
pub const CRAFT_PACK_MISSING_FIELD: u32 = 3;
pub const CRAFT_PACK_UNKNOWN_FIELD: u32 = 4;
pub const CRAFT_PACK_INVALID_TYPE: u32 = 5;
pub const CRAFT_PACK_INVALID_VALUE: u32 = 6;
pub const CRAFT_PACK_DUPLICATE_FIELD: u32 = 7;
pub const CRAFT_PACK_DUPLICATE_VALUE: u32 = 8;
pub const CRAFT_PACK_LIMIT_EXCEEDED: u32 = 9;
pub const CRAFT_PACK_INCOMPATIBLE_ABI: u32 = 10;
pub const CRAFT_PACK_INCOMPATIBLE_DRIVER_CONTRACT: u32 = 11;
pub const CRAFT_PACK_MISSING_CAPABILITY: u32 = 12;

const NODE_NONE: u32 = u32::MAX;
const INPUT_HAS_POSITION: u32 = 1 << 0;
const INPUT_HAS_DELTA: u32 = 1 << 1;
const INPUT_HAS_BUTTON: u32 = 1 << 2;
const INPUT_HAS_KEY: u32 = 1 << 3;
const INPUT_HAS_TEXT: u32 = 1 << 4;
const INPUT_HAS_POINTER: u32 = 1 << 5;
const EVENT_HAS_LOCAL: u32 = 1 << 0;
const EVENT_HAS_POSITION: u32 = 1 << 1;
const EVENT_HAS_DELTA: u32 = 1 << 2;
const EVENT_HAS_BUTTON: u32 = 1 << 3;
const EVENT_HAS_KEY: u32 = 1 << 4;
const EVENT_HAS_TEXT: u32 = 1 << 5;
const EVENT_HAS_POINTER: u32 = 1 << 6;
const EVENT_HAS_MOTION: u32 = 1 << 11;
const OUTCOME_HANDLED: u8 = 1 << 0;
const OUTCOME_STOP_PROPAGATION: u8 = 1 << 1;
const OUTCOME_PREVENT_DEFAULT: u8 = 1 << 2;
const MAX_CRAFT_STYLE_SOURCE_BYTES: usize = 8 * 1024 * 1024;
const MAX_CRAFT_PACK_SOURCE_BYTES: usize = 4 * 1024 * 1024;

mod ffi {
    use super::{c_char, c_float, c_int, c_uint, c_void, Color, Rect};

    #[repr(C)]
    pub struct CbssContext {
        _private: [u8; 0],
    }

    #[repr(C)]
    pub struct CbssStyle {
        _private: [u8; 0],
    }

    #[repr(C)]
    #[derive(Clone, Copy, Debug, Default)]
    pub struct CbssPointerData {
        pub device: c_uint,
        pub axes: c_uint,
        pub device_id: u64,
        pub pressure: c_float,
        pub tangential_pressure: c_float,
        pub tilt_x: c_float,
        pub tilt_y: c_float,
        pub rotation: c_float,
        pub distance: c_float,
        pub slider: c_float,
        pub buttons: c_uint,
        pub contact: u8,
        pub primary: u8,
        pub eraser: u8,
        pub in_proximity: u8,
    }

    #[repr(C)]
    pub struct CbssInputEvent {
        pub kind: c_uint,
        pub flags: c_uint,
        pub modifiers: c_uint,
        pub button: c_int,
        pub x: c_float,
        pub y: c_float,
        pub delta_x: c_float,
        pub delta_y: c_float,
        pub key: *const c_char,
        pub text: *const c_char,
        pub pointer: CbssPointerData,
        pub timestamp: u64,
    }

    #[repr(C)]
    pub struct CbssEvent {
        pub kind: c_uint,
        pub target: c_uint,
        pub current_target: c_uint,
        pub flags: c_uint,
        pub local_x: c_float,
        pub local_y: c_float,
        pub x: c_float,
        pub y: c_float,
        pub delta_x: c_float,
        pub delta_y: c_float,
        pub button: c_int,
        pub modifiers: c_uint,
        pub key: *const c_char,
        pub text: *const c_char,
        pub pointer: CbssPointerData,
        pub timestamp: u64,
        pub motion_name: *const c_char,
        pub motion_elapsed_seconds: f64,
        pub motion_iteration: u64,
    }

    #[repr(C)]
    #[derive(Clone, Copy, Debug, Default)]
    pub struct CbssDispatchSummary {
        pub target: c_uint,
        pub dispatch_count: c_uint,
        pub handled: u8,
        pub outcome: u8,
        pub needs_compute: u8,
        pub paint_changed: u8,
        pub focus_changed: u8,
    }

    #[repr(C)]
    #[derive(Clone, Copy, Debug, Default)]
    pub struct CbssCraftDiagnostic {
        pub domain: c_uint,
        pub code: c_uint,
        pub path_bytes: c_uint,
        pub message_bytes: c_uint,
    }

    pub type CbssEventCallback = unsafe extern "C" fn(
        context: *mut CbssContext,
        event: *const CbssEvent,
        user_data: *mut c_void,
    ) -> u8;

    extern "C" {
        pub fn cbss_abi_version() -> c_uint;
        pub fn cbss_driver_contract_version() -> c_uint;
        pub fn cbss_has_capability(capability: c_uint, minimum_version: c_uint) -> u8;

        pub fn cbss_context_create() -> *mut CbssContext;
        pub fn cbss_context_destroy(context: *mut CbssContext);
        pub fn cbss_context_reset(context: *mut CbssContext) -> c_int;
        pub fn cbss_context_last_error(
            context: *mut CbssContext,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_context_craft_diagnostic_count(context: *mut CbssContext) -> c_uint;
        pub fn cbss_context_craft_diagnostic_at(
            context: *mut CbssContext,
            index: c_uint,
            output: *mut CbssCraftDiagnostic,
        ) -> c_int;
        pub fn cbss_context_craft_diagnostic_path(
            context: *mut CbssContext,
            index: c_uint,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_context_craft_diagnostic_message(
            context: *mut CbssContext,
            index: c_uint,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_node_expose_craft_style_slot(
            context: *mut CbssContext,
            owner: c_uint,
            target: c_uint,
            component: *const c_char,
            slot: *const c_char,
        ) -> c_int;
        pub fn cbss_context_replace_craft_style_json(
            context: *mut CbssContext,
            bytes: *const u8,
            length: c_uint,
        ) -> c_int;
        pub fn cbss_context_remove_craft_style(
            context: *mut CbssContext,
            name: *const c_char,
            output_removed: *mut u8,
        ) -> c_int;
        pub fn cbss_context_active_craft_style_count(context: *mut CbssContext) -> c_uint;
        pub fn cbss_context_active_craft_style_name(
            context: *mut CbssContext,
            index: c_uint,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_context_replace_craft_pack_json(
            context: *mut CbssContext,
            bytes: *const u8,
            length: c_uint,
        ) -> c_int;
        pub fn cbss_context_remove_craft_pack(
            context: *mut CbssContext,
            id: *const c_char,
            output_removed: *mut u8,
        ) -> c_int;
        pub fn cbss_context_active_craft_pack_count(context: *mut CbssContext) -> c_uint;
        pub fn cbss_context_active_craft_pack_id(
            context: *mut CbssContext,
            index: c_uint,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_context_active_craft_pack_version(
            context: *mut CbssContext,
            index: c_uint,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_context_node_count(context: *mut CbssContext) -> c_uint;
        pub fn cbss_node_parent(context: *mut CbssContext, node: c_uint) -> c_uint;
        pub fn cbss_node_child_count(context: *mut CbssContext, node: c_uint) -> c_uint;
        pub fn cbss_node_child(context: *mut CbssContext, node: c_uint, index: c_uint) -> c_uint;
        pub fn cbss_node_text(
            context: *mut CbssContext,
            node: c_uint,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_node_image_source(
            context: *mut CbssContext,
            node: c_uint,
            buffer: *mut c_char,
            capacity: c_uint,
        ) -> c_uint;
        pub fn cbss_context_remove_subtree(
            context: *mut CbssContext,
            node: c_uint,
            output_removed_count: *mut c_uint,
        ) -> c_int;
        pub fn cbss_context_add_box(
            context: *mut CbssContext,
            parent: c_uint,
            identifier: *const c_char,
        ) -> c_uint;
        pub fn cbss_context_add_text(
            context: *mut CbssContext,
            parent: c_uint,
            text: *const c_char,
            identifier: *const c_char,
        ) -> c_uint;
        pub fn cbss_context_add_image(
            context: *mut CbssContext,
            parent: c_uint,
            source: *const c_char,
            width: c_float,
            height: c_float,
            identifier: *const c_char,
        ) -> c_uint;
        pub fn cbss_node_set_text(
            context: *mut CbssContext,
            node: c_uint,
            text: *const c_char,
        ) -> c_int;
        pub fn cbss_node_set_image(
            context: *mut CbssContext,
            node: c_uint,
            source: *const c_char,
            width: c_float,
            height: c_float,
        ) -> c_int;
        pub fn cbss_node_add_group(
            context: *mut CbssContext,
            node: c_uint,
            group: *const c_char,
        ) -> c_int;
        pub fn cbss_node_set_attribute(
            context: *mut CbssContext,
            node: c_uint,
            name: *const c_char,
            value: *const c_char,
        ) -> c_int;
        pub fn cbss_node_set_state(
            context: *mut CbssContext,
            node: c_uint,
            state: c_uint,
            enabled: u8,
        ) -> c_int;

        pub fn cbss_style_create() -> *mut CbssStyle;
        pub fn cbss_style_destroy(style: *mut CbssStyle);
        pub fn cbss_style_clear(style: *mut CbssStyle) -> c_int;
        pub fn cbss_style_set_length(
            style: *mut CbssStyle,
            property: *const c_char,
            unit: c_uint,
            value: c_float,
        ) -> c_int;
        pub fn cbss_style_set_number(
            style: *mut CbssStyle,
            property: *const c_char,
            value: c_float,
        ) -> c_int;
        pub fn cbss_style_set_keyword(
            style: *mut CbssStyle,
            property: *const c_char,
            value: *const c_char,
        ) -> c_int;
        pub fn cbss_style_set_color(
            style: *mut CbssStyle,
            property: *const c_char,
            color: Color,
        ) -> c_int;
        pub fn cbss_node_apply_style(
            context: *mut CbssContext,
            node: c_uint,
            style: *mut CbssStyle,
            state_mask: c_uint,
            priority: i32,
        ) -> c_int;
        pub fn cbss_context_compute(
            context: *mut CbssContext,
            width: c_float,
            height: c_float,
        ) -> c_int;
        pub fn cbss_node_layout_rect(
            context: *mut CbssContext,
            node: c_uint,
            output: *mut Rect,
        ) -> c_int;
        pub fn cbss_node_set_event_handler(
            context: *mut CbssContext,
            node: c_uint,
            kind: c_uint,
            callback: Option<CbssEventCallback>,
            user_data: *mut c_void,
        ) -> c_int;
        pub fn cbss_node_subscribe_event(
            context: *mut CbssContext,
            node: c_uint,
            kind: c_uint,
            callback: Option<CbssEventCallback>,
            user_data: *mut c_void,
            output_subscription: *mut u64,
        ) -> c_int;
        pub fn cbss_context_unsubscribe_event(
            context: *mut CbssContext,
            subscription: u64,
        ) -> c_int;
        pub fn cbss_context_emit_event(
            context: *mut CbssContext,
            node: c_uint,
            event: *const CbssInputEvent,
            output: *mut CbssDispatchSummary,
        ) -> c_int;
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ErrorKind {
    Contract,
    Status(i32),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Error {
    kind: ErrorKind,
    message: String,
}

impl Error {
    fn contract(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::Contract,
            message: message.into(),
        }
    }

    fn status(status: i32, message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::Status(status),
            message: message.into(),
        }
    }

    pub fn kind(&self) -> ErrorKind {
        self.kind
    }

    pub fn status_code(&self) -> Option<i32> {
        match self.kind {
            ErrorKind::Contract => None,
            ErrorKind::Status(status) => Some(status),
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CraftDiagnostic {
    pub domain: u32,
    pub code: u32,
    pub path: String,
    pub message: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CraftPackInfo {
    pub id: String,
    pub version: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CapabilityRequirement {
    pub id: u32,
    pub minimum_version: u32,
}

pub struct Contract;

impl Contract {
    pub fn abi_version() -> u32 {
        unsafe { ffi::cbss_abi_version() }
    }

    pub fn driver_version() -> u32 {
        unsafe { ffi::cbss_driver_contract_version() }
    }

    pub fn has(capability: u32, minimum_version: u32) -> bool {
        unsafe { ffi::cbss_has_capability(capability, minimum_version) != 0 }
    }

    pub fn require(capabilities: &[CapabilityRequirement]) -> Result<()> {
        let runtime_abi = Self::abi_version();
        if runtime_abi != ABI_VERSION {
            return Err(Error::contract(format!(
                "CBSS ABI mismatch: Rust Driver expects {ABI_VERSION}, runtime provides {runtime_abi}"
            )));
        }
        let runtime_contract = Self::driver_version();
        if runtime_contract != DRIVER_CONTRACT_VERSION {
            return Err(Error::contract(format!(
                "Craft Driver contract mismatch: Rust Driver expects {DRIVER_CONTRACT_VERSION}, runtime provides {runtime_contract}"
            )));
        }
        for requirement in capabilities {
            if !Self::has(requirement.id, requirement.minimum_version) {
                return Err(Error::contract(format!(
                    "CBSS capability {} version {} is unavailable",
                    requirement.id, requirement.minimum_version
                )));
            }
        }
        Ok(())
    }

    pub fn require_authoring() -> Result<()> {
        Self::require(&[
            CapabilityRequirement {
                id: CAPABILITY_RETAINED_TREE,
                minimum_version: 1,
            },
            CapabilityRequirement {
                id: CAPABILITY_TYPED_STYLE,
                minimum_version: 1,
            },
            CapabilityRequirement {
                id: CAPABILITY_FLEX_LAYOUT,
                minimum_version: 1,
            },
        ])
    }
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Unit {
    Px = 0,
    Percent = 1,
    Em = 2,
    Rem = 3,
    Fill = 4,
    Content = 5,
    MinContent = 6,
    MaxContent = 7,
    FitContent = 8,
    Auto = 9,
    None = 10,
    Vw = 11,
    Vh = 12,
    Vmin = 13,
    Vmax = 14,
    Lh = 15,
    Rlh = 16,
    Ex = 17,
    Ch = 18,
    Rex = 19,
    Rch = 20,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Length {
    pub unit: Unit,
    pub value: f32,
}

pub fn px(value: f32) -> Length {
    Length {
        unit: Unit::Px,
        value,
    }
}

pub fn percent(value: f32) -> Length {
    Length {
        unit: Unit::Percent,
        value,
    }
}

pub fn em(value: f32) -> Length {
    Length {
        unit: Unit::Em,
        value,
    }
}

pub fn rem(value: f32) -> Length {
    Length {
        unit: Unit::Rem,
        value,
    }
}

pub fn fill(value: f32) -> Length {
    Length {
        unit: Unit::Fill,
        value,
    }
}

pub fn content() -> Length {
    Length {
        unit: Unit::Content,
        value: 0.0,
    }
}

pub fn automatic() -> Length {
    Length {
        unit: Unit::Auto,
        value: 0.0,
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Keyword(String);

pub fn keyword(value: impl Into<String>) -> Keyword {
    Keyword(value.into())
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Color {
    pub red: f32,
    pub green: f32,
    pub blue: f32,
    pub alpha: f32,
}

pub fn rgb(red: f32, green: f32, blue: f32) -> Color {
    Color {
        red,
        green,
        blue,
        alpha: 1.0,
    }
}

pub fn rgba(red: f32, green: f32, blue: f32, alpha: f32) -> Color {
    Color {
        red,
        green,
        blue,
        alpha,
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum StyleValue {
    Length(Length),
    Keyword(Keyword),
    Color(Color),
}

impl From<Length> for StyleValue {
    fn from(value: Length) -> Self {
        Self::Length(value)
    }
}

impl From<Keyword> for StyleValue {
    fn from(value: Keyword) -> Self {
        Self::Keyword(value)
    }
}

impl From<Color> for StyleValue {
    fn from(value: Color) -> Self {
        Self::Color(value)
    }
}

pub struct Style {
    handle: NonNull<ffi::CbssStyle>,
    _not_send: PhantomData<Rc<()>>,
}

impl Style {
    pub fn new() -> Result<Self> {
        let handle = NonNull::new(unsafe { ffi::cbss_style_create() })
            .ok_or_else(|| Error::status(STATUS_INTERNAL_ERROR, "unable to create Style"))?;
        Ok(Self {
            handle,
            _not_send: PhantomData,
        })
    }

    pub fn set(&mut self, property: &str, value: impl Into<StyleValue>) -> Result<&mut Self> {
        let property = c_string(property, "Style property")?;
        let status = match value.into() {
            StyleValue::Length(value) => unsafe {
                ffi::cbss_style_set_length(
                    self.handle.as_ptr(),
                    property.as_ptr(),
                    value.unit as u32,
                    value.value,
                )
            },
            StyleValue::Keyword(value) => {
                let value = c_string(&value.0, "Style keyword")?;
                unsafe {
                    ffi::cbss_style_set_keyword(
                        self.handle.as_ptr(),
                        property.as_ptr(),
                        value.as_ptr(),
                    )
                }
            }
            StyleValue::Color(value) => unsafe {
                ffi::cbss_style_set_color(self.handle.as_ptr(), property.as_ptr(), value)
            },
        };
        check_status(status, "unable to set Style property")?;
        Ok(self)
    }

    pub fn number(&mut self, property: &str, value: f32) -> Result<&mut Self> {
        let property = c_string(property, "Style property")?;
        let status =
            unsafe { ffi::cbss_style_set_number(self.handle.as_ptr(), property.as_ptr(), value) };
        check_status(status, "unable to set numeric Style property")?;
        Ok(self)
    }

    pub fn clear(&mut self) -> Result<&mut Self> {
        let status = unsafe { ffi::cbss_style_clear(self.handle.as_ptr()) };
        check_status(status, "unable to clear Style")?;
        Ok(self)
    }
}

impl Drop for Style {
    fn drop(&mut self) {
        unsafe { ffi::cbss_style_destroy(self.handle.as_ptr()) }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Node {
    owner: NonNull<ffi::CbssContext>,
    id: u32,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NodeState {
    Hover = 0,
    Active = 1,
    Focus = 2,
    FocusVisible = 3,
    Disabled = 4,
    Checked = 5,
    Selected = 6,
    Open = 7,
    Invalid = 8,
}

#[derive(Debug)]
pub struct CraftComponent {
    root: Option<Node>,
    craft_name: String,
}

impl CraftComponent {
    pub fn active(&self) -> bool {
        self.root.is_some()
    }

    pub fn root(&self) -> Result<Node> {
        self.root.ok_or_else(|| {
            Error::status(
                STATUS_INVALID_HANDLE,
                "access Craft Component: component is not mounted",
            )
        })
    }

    pub fn craft_name(&self) -> &str {
        &self.craft_name
    }
}

impl Node {
    pub fn native_id(self) -> u32 {
        self.id
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PointerData {
    pub device: u32,
    pub axes: u32,
    pub device_id: u64,
    pub pressure: f32,
    pub tangential_pressure: f32,
    pub tilt_x: f32,
    pub tilt_y: f32,
    pub rotation: f32,
    pub distance: f32,
    pub slider: f32,
    pub buttons: u32,
    pub contact: bool,
    pub primary: bool,
    pub eraser: bool,
    pub in_proximity: bool,
}

impl From<PointerData> for ffi::CbssPointerData {
    fn from(value: PointerData) -> Self {
        Self {
            device: value.device,
            axes: value.axes,
            device_id: value.device_id,
            pressure: value.pressure,
            tangential_pressure: value.tangential_pressure,
            tilt_x: value.tilt_x,
            tilt_y: value.tilt_y,
            rotation: value.rotation,
            distance: value.distance,
            slider: value.slider,
            buttons: value.buttons,
            contact: value.contact as u8,
            primary: value.primary as u8,
            eraser: value.eraser as u8,
            in_proximity: value.in_proximity as u8,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct EventOutcome(u8);

impl EventOutcome {
    pub const CONTINUE: Self = Self(0);
    pub const HANDLED: Self = Self(OUTCOME_HANDLED);

    pub const fn new(handled: bool, stop_propagation: bool, prevent_default: bool) -> Self {
        Self(
            (if handled { OUTCOME_HANDLED } else { 0 })
                | (if stop_propagation {
                    OUTCOME_STOP_PROPAGATION
                } else {
                    0
                })
                | (if prevent_default {
                    OUTCOME_PREVENT_DEFAULT
                } else {
                    0
                }),
        )
    }

    pub const fn handled(self) -> bool {
        self.0 & OUTCOME_HANDLED != 0
    }

    pub const fn stops_propagation(self) -> bool {
        self.0 & OUTCOME_STOP_PROPAGATION != 0
    }

    pub const fn prevents_default(self) -> bool {
        self.0 & OUTCOME_PREVENT_DEFAULT != 0
    }

    const fn bits(self) -> u8 {
        self.0
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Event {
    pub kind: EventKind,
    pub target: u32,
    pub current_target: u32,
    pub flags: u32,
    pub local_position: Option<(f32, f32)>,
    pub position: Option<(f32, f32)>,
    pub delta: Option<(f32, f32)>,
    pub button: Option<i32>,
    pub modifiers: u32,
    pub key: Option<String>,
    pub text: Option<String>,
    pub pointer: Option<PointerData>,
    pub timestamp: u64,
    pub motion_name: Option<String>,
    pub motion_elapsed_seconds: f64,
    pub motion_iteration: u64,
}

impl Event {
    unsafe fn from_raw(raw: &ffi::CbssEvent) -> Self {
        Self {
            kind: EventKind::from_code(raw.kind),
            target: raw.target,
            current_target: raw.current_target,
            flags: raw.flags,
            local_position: (raw.flags & EVENT_HAS_LOCAL != 0)
                .then_some((raw.local_x, raw.local_y)),
            position: (raw.flags & EVENT_HAS_POSITION != 0).then_some((raw.x, raw.y)),
            delta: (raw.flags & EVENT_HAS_DELTA != 0).then_some((raw.delta_x, raw.delta_y)),
            button: (raw.flags & EVENT_HAS_BUTTON != 0).then_some(raw.button),
            modifiers: raw.modifiers,
            key: copy_callback_string(raw.key, raw.flags & EVENT_HAS_KEY != 0),
            text: copy_callback_string(raw.text, raw.flags & EVENT_HAS_TEXT != 0),
            pointer: (raw.flags & EVENT_HAS_POINTER != 0).then_some(PointerData {
                device: raw.pointer.device,
                axes: raw.pointer.axes,
                device_id: raw.pointer.device_id,
                pressure: raw.pointer.pressure,
                tangential_pressure: raw.pointer.tangential_pressure,
                tilt_x: raw.pointer.tilt_x,
                tilt_y: raw.pointer.tilt_y,
                rotation: raw.pointer.rotation,
                distance: raw.pointer.distance,
                slider: raw.pointer.slider,
                buttons: raw.pointer.buttons,
                contact: raw.pointer.contact != 0,
                primary: raw.pointer.primary != 0,
                eraser: raw.pointer.eraser != 0,
                in_proximity: raw.pointer.in_proximity != 0,
            }),
            timestamp: raw.timestamp,
            motion_name: copy_callback_string(raw.motion_name, raw.flags & EVENT_HAS_MOTION != 0),
            motion_elapsed_seconds: raw.motion_elapsed_seconds,
            motion_iteration: raw.motion_iteration,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct InputEvent {
    pub kind: EventKind,
    pub modifiers: u32,
    pub button: Option<i32>,
    pub position: Option<(f32, f32)>,
    pub delta: Option<(f32, f32)>,
    pub key: Option<String>,
    pub text: Option<String>,
    pub pointer: Option<PointerData>,
    pub timestamp: u64,
}

impl InputEvent {
    pub fn new(kind: EventKind) -> Self {
        Self {
            kind,
            modifiers: 0,
            button: None,
            position: None,
            delta: None,
            key: None,
            text: None,
            pointer: None,
            timestamp: 0,
        }
    }

    pub fn position(mut self, x: f32, y: f32) -> Self {
        self.position = Some((x, y));
        self
    }

    pub fn delta(mut self, x: f32, y: f32) -> Self {
        self.delta = Some((x, y));
        self
    }

    pub fn button(mut self, button: i32) -> Self {
        self.button = Some(button);
        self
    }

    pub fn key(mut self, key: impl Into<String>) -> Self {
        self.key = Some(key.into());
        self
    }

    pub fn text(mut self, text: impl Into<String>) -> Self {
        self.text = Some(text.into());
        self
    }

    pub fn pointer(mut self, pointer: PointerData) -> Self {
        self.pointer = Some(pointer);
        self
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct DispatchSummary {
    pub target: u32,
    pub dispatch_count: u32,
    pub handled: bool,
    pub outcome: EventOutcome,
    pub needs_compute: bool,
    pub paint_changed: bool,
    pub focus_changed: bool,
}

type EventCallback = dyn FnMut(&Event) -> EventOutcome;

struct EventCallbackState {
    callback: RefCell<Box<EventCallback>>,
    panicked: Cell<bool>,
}

unsafe extern "C" fn event_trampoline(
    _context: *mut ffi::CbssContext,
    event: *const ffi::CbssEvent,
    user_data: *mut c_void,
) -> u8 {
    if event.is_null() || user_data.is_null() {
        return EventOutcome::new(true, true, true).bits();
    }
    let pointer = user_data.cast::<EventCallbackState>();
    Rc::increment_strong_count(pointer);
    let holder = Rc::from_raw(pointer);
    let event = Event::from_raw(&*event);
    match catch_unwind(AssertUnwindSafe(|| {
        let mut callback = holder.callback.borrow_mut();
        callback(&event)
    })) {
        Ok(outcome) => outcome.bits(),
        Err(_) => {
            holder.panicked.set(true);
            EventOutcome::new(true, true, true).bits()
        }
    }
}

struct EventSubscriptionState {
    node: u32,
    callback: Rc<EventCallbackState>,
}

struct DriverEventState {
    context: Cell<*mut ffi::CbssContext>,
    handlers: RefCell<HashMap<u32, HashMap<u32, Rc<EventCallbackState>>>>,
    subscriptions: RefCell<HashMap<u64, EventSubscriptionState>>,
    subscriptions_by_node: RefCell<HashMap<u32, HashSet<u64>>>,
}

impl DriverEventState {
    fn new(context: *mut ffi::CbssContext) -> Self {
        Self {
            context: Cell::new(context),
            handlers: RefCell::new(HashMap::new()),
            subscriptions: RefCell::new(HashMap::new()),
            subscriptions_by_node: RefCell::new(HashMap::new()),
        }
    }

    fn unsubscribe(&self, subscription: u64) -> i32 {
        let context = self.context.get();
        if context.is_null() || !self.subscriptions.borrow().contains_key(&subscription) {
            return STATUS_INVALID_HANDLE;
        }
        let status = unsafe { ffi::cbss_context_unsubscribe_event(context, subscription) };
        if status == STATUS_OK {
            let node = self
                .subscriptions
                .borrow_mut()
                .remove(&subscription)
                .map(|entry| entry.node);
            if let Some(node) = node {
                let mut index = self.subscriptions_by_node.borrow_mut();
                if let Some(ids) = index.get_mut(&node) {
                    ids.remove(&subscription);
                    if ids.is_empty() {
                        index.remove(&node);
                    }
                }
            }
        }
        status
    }

    fn has_subscription(&self, subscription: u64) -> bool {
        self.subscriptions
            .try_borrow()
            .map(|subscriptions| subscriptions.contains_key(&subscription))
            .unwrap_or(false)
    }

    fn release_nodes(&self, nodes: &HashSet<u32>) {
        let mut handlers = self.handlers.borrow_mut();
        let mut subscriptions = self.subscriptions.borrow_mut();
        let mut index = self.subscriptions_by_node.borrow_mut();
        for node in nodes {
            handlers.remove(node);
            if let Some(ids) = index.remove(node) {
                for id in ids {
                    subscriptions.remove(&id);
                }
            }
        }
    }

    fn clear_after_reset(&self) {
        self.handlers.borrow_mut().clear();
        self.subscriptions.borrow_mut().clear();
        self.subscriptions_by_node.borrow_mut().clear();
    }

    fn shutdown(&self) {
        self.context.set(std::ptr::null_mut());
        self.clear_after_reset();
    }

    fn callback_panicked(&self) -> bool {
        let handlers = self.handlers.borrow();
        if handlers
            .values()
            .any(|node| node.values().any(|holder| holder.panicked.get()))
        {
            return true;
        }
        self.subscriptions
            .borrow()
            .values()
            .any(|subscription| subscription.callback.panicked.get())
    }
}

pub struct EventSubscription {
    state: Weak<DriverEventState>,
    id: u64,
    active: bool,
    _not_send: PhantomData<Rc<()>>,
}

impl EventSubscription {
    pub fn active(&self) -> bool {
        self.active
            && self
                .state
                .upgrade()
                .map(|state| state.has_subscription(self.id))
                .unwrap_or(false)
    }

    pub fn close(&mut self) -> Result<()> {
        if !self.active {
            return Ok(());
        }
        let Some(state) = self.state.upgrade() else {
            self.active = false;
            return Ok(());
        };
        let status = state.unsubscribe(self.id);
        if status != STATUS_OK && status != STATUS_INVALID_HANDLE {
            return Err(Error::status(status, "unable to unsubscribe event"));
        }
        self.active = false;
        Ok(())
    }
}

impl Drop for EventSubscription {
    fn drop(&mut self) {
        let _ = self.close();
    }
}

unsafe fn copy_callback_string(pointer: *const c_char, present: bool) -> Option<String> {
    if !present || pointer.is_null() {
        return None;
    }
    Some(CStr::from_ptr(pointer).to_string_lossy().into_owned())
}

pub struct Ui {
    context: NonNull<ffi::CbssContext>,
    events: Rc<DriverEventState>,
    _not_send: PhantomData<Rc<()>>,
}

impl Ui {
    pub fn new() -> Result<Self> {
        Contract::require_authoring()?;
        let context = NonNull::new(unsafe { ffi::cbss_context_create() })
            .ok_or_else(|| Error::status(STATUS_INTERNAL_ERROR, "unable to create UI"))?;
        Ok(Self {
            context,
            events: Rc::new(DriverEventState::new(context.as_ptr())),
            _not_send: PhantomData,
        })
    }

    pub fn box_node(&mut self, identifier: &str, style: Option<&Style>) -> Result<Node> {
        self.add_box(None, identifier, style)
    }

    pub fn box_with<F>(
        &mut self,
        identifier: &str,
        style: Option<&Style>,
        children: F,
    ) -> Result<Node>
    where
        F: FnOnce(&mut Scope<'_>) -> Result<()>,
    {
        let node = self.add_box(None, identifier, style)?;
        let mut scope = Scope {
            ui: self,
            parent: node,
        };
        children(&mut scope)?;
        Ok(node)
    }

    pub fn within<F>(&mut self, parent: Node, children: F) -> Result<()>
    where
        F: FnOnce(&mut Scope<'_>) -> Result<()>,
    {
        self.require_node(parent, "enter parent scope")?;
        let mut scope = Scope { ui: self, parent };
        children(&mut scope)
    }

    pub fn text(&mut self, value: &str, identifier: &str, style: Option<&Style>) -> Result<Node> {
        self.add_text(None, value, identifier, style)
    }

    pub fn image(
        &mut self,
        source: &str,
        width: f32,
        height: f32,
        identifier: &str,
        style: Option<&Style>,
    ) -> Result<Node> {
        self.add_image(None, source, width, height, identifier, style)
    }

    pub fn component_with<F>(
        &mut self,
        craft_name: &str,
        identifier: &str,
        owned_style: Option<&Style>,
        children: F,
    ) -> Result<CraftComponent>
    where
        F: FnOnce(&mut ComponentScope<'_>) -> Result<()>,
    {
        self.add_component(None, craft_name, identifier, owned_style, children)
    }

    pub fn unmount(&mut self, component: &mut CraftComponent) -> Result<u32> {
        let root = component.root()?;
        self.require_node(root, "unmount Craft Component")?;
        let removed = self.remove_subtree(root)?;
        component.root = None;
        Ok(removed)
    }

    pub fn set_text(&mut self, node: Node, value: &str) -> Result<()> {
        self.require_node(node, "set Text value")?;
        let value = c_string(value, "Text value")?;
        let status =
            unsafe { ffi::cbss_node_set_text(self.context.as_ptr(), node.id, value.as_ptr()) };
        self.check(status, "set Text value")
    }

    pub fn text_value(&mut self, node: Node) -> Result<String> {
        self.require_node(node, "read Text value")?;
        Ok(read_context_string(|buffer, capacity| unsafe {
            ffi::cbss_node_text(self.context.as_ptr(), node.id, buffer, capacity)
        }))
    }

    pub fn set_image(&mut self, node: Node, source: &str, width: f32, height: f32) -> Result<()> {
        self.require_node(node, "set Image value")?;
        let source = c_string(source, "Image source")?;
        let status = unsafe {
            ffi::cbss_node_set_image(
                self.context.as_ptr(),
                node.id,
                source.as_ptr(),
                width,
                height,
            )
        };
        self.check(status, "set Image value")
    }

    pub fn image_source(&mut self, node: Node) -> Result<String> {
        self.require_node(node, "read Image source")?;
        Ok(read_context_string(|buffer, capacity| unsafe {
            ffi::cbss_node_image_source(self.context.as_ptr(), node.id, buffer, capacity)
        }))
    }

    pub fn add_group(&mut self, node: Node, group: &str) -> Result<()> {
        self.require_node(node, "add group")?;
        let group = c_string(group, "group")?;
        let status =
            unsafe { ffi::cbss_node_add_group(self.context.as_ptr(), node.id, group.as_ptr()) };
        self.check(status, "add group")
    }

    pub fn set_attribute(&mut self, node: Node, name: &str, value: &str) -> Result<()> {
        self.require_node(node, "set attribute")?;
        let name = c_string(name, "attribute name")?;
        let value = c_string(value, "attribute value")?;
        let status = unsafe {
            ffi::cbss_node_set_attribute(
                self.context.as_ptr(),
                node.id,
                name.as_ptr(),
                value.as_ptr(),
            )
        };
        self.check(status, "set attribute")
    }

    pub fn set_state(&mut self, node: Node, state: NodeState, enabled: bool) -> Result<()> {
        self.require_node(node, "set retained state")?;
        let status = unsafe {
            ffi::cbss_node_set_state(
                self.context.as_ptr(),
                node.id,
                state as u32,
                u8::from(enabled),
            )
        };
        self.check(status, "set retained state")
    }

    pub fn apply(
        &mut self,
        node: Node,
        style: &Style,
        state_mask: u32,
        priority: i32,
    ) -> Result<()> {
        self.require_node(node, "apply Style")?;
        let status = unsafe {
            ffi::cbss_node_apply_style(
                self.context.as_ptr(),
                node.id,
                style.handle.as_ptr(),
                state_mask,
                priority,
            )
        };
        self.check(status, "apply Style")
    }

    pub fn expose_style_slot(
        &mut self,
        owner: Node,
        target: Node,
        component: &str,
        slot: &str,
    ) -> Result<()> {
        Contract::require(&[CapabilityRequirement {
            id: CAPABILITY_CRAFT_STYLE,
            minimum_version: 1,
        }])?;
        self.require_node(owner, "expose Craft Style Slot owner")?;
        self.require_node(target, "expose Craft Style Slot target")?;
        let component = c_string(component, "Craft component name")?;
        let slot = c_string(slot, "Craft Style Slot name")?;
        let status = unsafe {
            ffi::cbss_node_expose_craft_style_slot(
                self.context.as_ptr(),
                owner.id,
                target.id,
                component.as_ptr(),
                slot.as_ptr(),
            )
        };
        self.check(status, "expose Craft Style Slot")
    }

    pub fn replace_craft_style(&mut self, source: &str) -> Result<()> {
        Contract::require(&[CapabilityRequirement {
            id: CAPABILITY_CRAFT_STYLE,
            minimum_version: 1,
        }])?;
        let length =
            checked_source_length(source, MAX_CRAFT_STYLE_SOURCE_BYTES, "replace Craft Style")?;
        let status = unsafe {
            ffi::cbss_context_replace_craft_style_json(
                self.context.as_ptr(),
                source.as_ptr(),
                length,
            )
        };
        self.check(status, "replace Craft Style")
    }

    pub fn remove_craft_style(&mut self, name: &str) -> Result<bool> {
        let name = c_string(name, "Craft Style name")?;
        let mut removed = 0_u8;
        let status = unsafe {
            ffi::cbss_context_remove_craft_style(self.context.as_ptr(), name.as_ptr(), &mut removed)
        };
        self.check(status, "remove Craft Style")?;
        Ok(removed != 0)
    }

    pub fn active_craft_styles(&self) -> Vec<String> {
        let count = unsafe { ffi::cbss_context_active_craft_style_count(self.context.as_ptr()) };
        (0..count)
            .map(|index| {
                read_context_string(|buffer, capacity| unsafe {
                    ffi::cbss_context_active_craft_style_name(
                        self.context.as_ptr(),
                        index,
                        buffer,
                        capacity,
                    )
                })
            })
            .collect()
    }

    pub fn replace_craft_pack(&mut self, source: &str) -> Result<()> {
        Contract::require(&[CapabilityRequirement {
            id: CAPABILITY_CRAFT_PACK,
            minimum_version: 1,
        }])?;
        let length =
            checked_source_length(source, MAX_CRAFT_PACK_SOURCE_BYTES, "replace Craft Pack")?;
        let status = unsafe {
            ffi::cbss_context_replace_craft_pack_json(
                self.context.as_ptr(),
                source.as_ptr(),
                length,
            )
        };
        self.check(status, "replace Craft Pack")
    }

    pub fn remove_craft_pack(&mut self, id: &str) -> Result<bool> {
        let id = c_string(id, "Craft Pack id")?;
        let mut removed = 0_u8;
        let status = unsafe {
            ffi::cbss_context_remove_craft_pack(self.context.as_ptr(), id.as_ptr(), &mut removed)
        };
        self.check(status, "remove Craft Pack")?;
        Ok(removed != 0)
    }

    pub fn active_craft_packs(&self) -> Vec<CraftPackInfo> {
        let count = unsafe { ffi::cbss_context_active_craft_pack_count(self.context.as_ptr()) };
        (0..count)
            .map(|index| CraftPackInfo {
                id: read_context_string(|buffer, capacity| unsafe {
                    ffi::cbss_context_active_craft_pack_id(
                        self.context.as_ptr(),
                        index,
                        buffer,
                        capacity,
                    )
                }),
                version: read_context_string(|buffer, capacity| unsafe {
                    ffi::cbss_context_active_craft_pack_version(
                        self.context.as_ptr(),
                        index,
                        buffer,
                        capacity,
                    )
                }),
            })
            .collect()
    }

    pub fn craft_diagnostics(&self) -> Result<Vec<CraftDiagnostic>> {
        let count = unsafe { ffi::cbss_context_craft_diagnostic_count(self.context.as_ptr()) };
        let mut result = Vec::with_capacity(count as usize);
        for index in 0..count {
            let mut native = ffi::CbssCraftDiagnostic::default();
            let status = unsafe {
                ffi::cbss_context_craft_diagnostic_at(self.context.as_ptr(), index, &mut native)
            };
            self.check(status, "read Craft diagnostic")?;
            result.push(CraftDiagnostic {
                domain: native.domain,
                code: native.code,
                path: read_context_string(|buffer, capacity| unsafe {
                    ffi::cbss_context_craft_diagnostic_path(
                        self.context.as_ptr(),
                        index,
                        buffer,
                        capacity,
                    )
                }),
                message: read_context_string(|buffer, capacity| unsafe {
                    ffi::cbss_context_craft_diagnostic_message(
                        self.context.as_ptr(),
                        index,
                        buffer,
                        capacity,
                    )
                }),
            });
        }
        Ok(result)
    }

    pub fn compute(&mut self, width: f32, height: f32) -> Result<()> {
        let status = unsafe { ffi::cbss_context_compute(self.context.as_ptr(), width, height) };
        self.check(status, "compute layout")
    }

    pub fn rect(&mut self, node: Node) -> Result<Rect> {
        self.require_node(node, "read layout rectangle")?;
        let mut result = Rect::default();
        let status =
            unsafe { ffi::cbss_node_layout_rect(self.context.as_ptr(), node.id, &mut result) };
        self.check(status, "read layout rectangle")?;
        Ok(result)
    }

    pub fn node_count(&mut self) -> u32 {
        unsafe { ffi::cbss_context_node_count(self.context.as_ptr()) }
    }

    pub fn parent(&mut self, node: Node) -> Result<Option<Node>> {
        self.require_node(node, "read parent")?;
        let parent = unsafe { ffi::cbss_node_parent(self.context.as_ptr(), node.id) };
        Ok(self.owned_node(parent))
    }

    pub fn child_count(&mut self, node: Node) -> Result<u32> {
        self.require_node(node, "read child count")?;
        Ok(unsafe { ffi::cbss_node_child_count(self.context.as_ptr(), node.id) })
    }

    pub fn remove_subtree(&mut self, root: Node) -> Result<u32> {
        Contract::require(&[CapabilityRequirement {
            id: CAPABILITY_SUBTREE_LIFECYCLE,
            minimum_version: 1,
        }])?;
        self.require_node(root, "remove subtree")?;
        let nodes = self.collect_subtree(root)?;
        let mut removed = 0_u32;
        let status = unsafe {
            ffi::cbss_context_remove_subtree(self.context.as_ptr(), root.id, &mut removed)
        };
        self.check(status, "remove subtree")?;
        self.events.release_nodes(&nodes);
        Ok(removed)
    }

    pub fn on<F>(&mut self, node: Node, kind: EventKind, callback: F) -> Result<()>
    where
        F: FnMut(&Event) -> EventOutcome + 'static,
    {
        self.require_event_capability()?;
        self.require_node(node, "set event handler")?;
        let holder = Rc::new(EventCallbackState {
            callback: RefCell::new(Box::new(callback)),
            panicked: Cell::new(false),
        });
        let status = unsafe {
            ffi::cbss_node_set_event_handler(
                self.context.as_ptr(),
                node.id,
                kind.code(),
                Some(event_trampoline),
                Rc::as_ptr(&holder).cast_mut().cast(),
            )
        };
        self.check(status, "set event handler")?;
        if self.events.handlers.try_borrow_mut().is_err() {
            unsafe {
                ffi::cbss_node_set_event_handler(
                    self.context.as_ptr(),
                    node.id,
                    kind.code(),
                    None,
                    std::ptr::null_mut(),
                );
            }
            return Err(Error::status(
                STATUS_INTERNAL_ERROR,
                "set event handler: callback registry is already borrowed",
            ));
        }
        self.events
            .handlers
            .borrow_mut()
            .entry(node.id)
            .or_default()
            .insert(kind.code(), holder);
        Ok(())
    }

    pub fn clear_handler(&mut self, node: Node, kind: EventKind) -> Result<()> {
        self.require_node(node, "clear event handler")?;
        let status = unsafe {
            ffi::cbss_node_set_event_handler(
                self.context.as_ptr(),
                node.id,
                kind.code(),
                None,
                std::ptr::null_mut(),
            )
        };
        self.check(status, "clear event handler")?;
        let mut handlers = self.events.handlers.borrow_mut();
        if let Some(node_handlers) = handlers.get_mut(&node.id) {
            node_handlers.remove(&kind.code());
            if node_handlers.is_empty() {
                handlers.remove(&node.id);
            }
        }
        Ok(())
    }

    pub fn subscribe<F>(
        &mut self,
        node: Node,
        kind: EventKind,
        callback: F,
    ) -> Result<EventSubscription>
    where
        F: FnMut(&Event) -> EventOutcome + 'static,
    {
        self.require_event_capability()?;
        self.require_node(node, "subscribe event")?;
        let holder = Rc::new(EventCallbackState {
            callback: RefCell::new(Box::new(callback)),
            panicked: Cell::new(false),
        });
        let mut subscription = 0_u64;
        let status = unsafe {
            ffi::cbss_node_subscribe_event(
                self.context.as_ptr(),
                node.id,
                kind.code(),
                Some(event_trampoline),
                Rc::as_ptr(&holder).cast_mut().cast(),
                &mut subscription,
            )
        };
        self.check(status, "subscribe event")?;
        if let (Ok(mut subscriptions), Ok(mut index)) = (
            self.events.subscriptions.try_borrow_mut(),
            self.events.subscriptions_by_node.try_borrow_mut(),
        ) {
            subscriptions.insert(
                subscription,
                EventSubscriptionState {
                    node: node.id,
                    callback: holder,
                },
            );
            index.entry(node.id).or_default().insert(subscription);
        } else {
            unsafe {
                ffi::cbss_context_unsubscribe_event(self.context.as_ptr(), subscription);
            }
            return Err(Error::status(
                STATUS_INTERNAL_ERROR,
                "subscribe event: callback registry is already borrowed",
            ));
        }
        Ok(EventSubscription {
            state: Rc::downgrade(&self.events),
            id: subscription,
            active: true,
            _not_send: PhantomData,
        })
    }

    pub fn emit(&mut self, node: Node, input: &InputEvent) -> Result<DispatchSummary> {
        self.require_event_capability()?;
        self.require_node(node, "emit event")?;
        let key = input
            .key
            .as_deref()
            .map(|value| c_string(value, "event key"))
            .transpose()?;
        let text = input
            .text
            .as_deref()
            .map(|value| c_string(value, "event text"))
            .transpose()?;
        let mut flags = 0_u32;
        let (x, y) = input.position.unwrap_or((0.0, 0.0));
        if input.position.is_some() {
            flags |= INPUT_HAS_POSITION;
        }
        let (delta_x, delta_y) = input.delta.unwrap_or((0.0, 0.0));
        if input.delta.is_some() {
            flags |= INPUT_HAS_DELTA;
        }
        if input.button.is_some() {
            flags |= INPUT_HAS_BUTTON;
        }
        if key.is_some() {
            flags |= INPUT_HAS_KEY;
        }
        if text.is_some() {
            flags |= INPUT_HAS_TEXT;
        }
        if input.pointer.is_some() {
            flags |= INPUT_HAS_POINTER;
        }
        let raw = ffi::CbssInputEvent {
            kind: input.kind.code(),
            flags,
            modifiers: input.modifiers,
            button: input.button.unwrap_or(0),
            x,
            y,
            delta_x,
            delta_y,
            key: key
                .as_ref()
                .map_or(std::ptr::null(), |value| value.as_ptr()),
            text: text
                .as_ref()
                .map_or(std::ptr::null(), |value| value.as_ptr()),
            pointer: input.pointer.unwrap_or_default().into(),
            timestamp: input.timestamp,
        };
        let mut summary = ffi::CbssDispatchSummary::default();
        let status = unsafe {
            ffi::cbss_context_emit_event(self.context.as_ptr(), node.id, &raw, &mut summary)
        };
        self.check(status, "emit event")?;
        Ok(DispatchSummary {
            target: summary.target,
            dispatch_count: summary.dispatch_count,
            handled: summary.handled != 0,
            outcome: EventOutcome(summary.outcome),
            needs_compute: summary.needs_compute != 0,
            paint_changed: summary.paint_changed != 0,
            focus_changed: summary.focus_changed != 0,
        })
    }

    pub fn callback_panicked(&self) -> bool {
        self.events.callback_panicked()
    }

    pub fn reset(&mut self) -> Result<()> {
        let status = unsafe { ffi::cbss_context_reset(self.context.as_ptr()) };
        self.check(status, "reset UI")?;
        self.events.clear_after_reset();
        Ok(())
    }

    fn add_box(
        &mut self,
        parent: Option<Node>,
        identifier: &str,
        style: Option<&Style>,
    ) -> Result<Node> {
        let parent = self.parent_id(parent)?;
        let identifier = c_string(identifier, "Box identifier")?;
        let raw = unsafe {
            ffi::cbss_context_add_box(self.context.as_ptr(), parent, identifier.as_ptr())
        };
        let node = self.added_node(raw, "add Box")?;
        if let Some(style) = style {
            self.apply(node, style, 0, 0)?;
        }
        Ok(node)
    }

    fn add_text(
        &mut self,
        parent: Option<Node>,
        value: &str,
        identifier: &str,
        style: Option<&Style>,
    ) -> Result<Node> {
        let parent = self.parent_id(parent)?;
        let value = c_string(value, "Text value")?;
        let identifier = c_string(identifier, "Text identifier")?;
        let raw = unsafe {
            ffi::cbss_context_add_text(
                self.context.as_ptr(),
                parent,
                value.as_ptr(),
                identifier.as_ptr(),
            )
        };
        let node = self.added_node(raw, "add Text")?;
        if let Some(style) = style {
            self.apply(node, style, 0, 0)?;
        }
        Ok(node)
    }

    fn add_image(
        &mut self,
        parent: Option<Node>,
        source: &str,
        width: f32,
        height: f32,
        identifier: &str,
        style: Option<&Style>,
    ) -> Result<Node> {
        let parent = self.parent_id(parent)?;
        let source = c_string(source, "Image source")?;
        let identifier = c_string(identifier, "Image identifier")?;
        let raw = unsafe {
            ffi::cbss_context_add_image(
                self.context.as_ptr(),
                parent,
                source.as_ptr(),
                width,
                height,
                identifier.as_ptr(),
            )
        };
        let node = self.added_node(raw, "add Image")?;
        if let Some(style) = style {
            self.apply(node, style, 0, 0)?;
        }
        Ok(node)
    }

    fn add_component<F>(
        &mut self,
        parent: Option<Node>,
        craft_name: &str,
        identifier: &str,
        owned_style: Option<&Style>,
        children: F,
    ) -> Result<CraftComponent>
    where
        F: FnOnce(&mut ComponentScope<'_>) -> Result<()>,
    {
        if craft_name.is_empty() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "mount Craft Component: craft name is empty",
            ));
        }
        let root = self.add_box(parent, identifier, owned_style)?;
        let component = CraftComponent {
            root: Some(root),
            craft_name: craft_name.to_owned(),
        };
        if let Err(error) = self.expose_style_slot(root, root, craft_name, "root") {
            let _ = self.remove_subtree(root);
            return Err(error);
        }

        let result = catch_unwind(AssertUnwindSafe(|| {
            let scope = Scope {
                ui: self,
                parent: root,
            };
            let mut component_scope = ComponentScope {
                scope,
                root,
                craft_name: craft_name.to_owned(),
            };
            children(&mut component_scope)
        }));
        match result {
            Ok(Ok(())) => {}
            Ok(Err(error)) => {
                let _ = self.remove_subtree(root);
                return Err(error);
            }
            Err(payload) => {
                let _ = self.remove_subtree(root);
                std::panic::resume_unwind(payload);
            }
        }
        Ok(component)
    }

    fn parent_id(&self, parent: Option<Node>) -> Result<u32> {
        match parent {
            Some(node) => {
                self.require_node(node, "use parent Node")?;
                Ok(node.id)
            }
            None => Ok(NODE_NONE),
        }
    }

    fn collect_subtree(&self, root: Node) -> Result<HashSet<u32>> {
        let mut result = HashSet::new();
        let mut pending = vec![root.id];
        while let Some(node) = pending.pop() {
            if !result.insert(node) {
                continue;
            }
            let count = unsafe { ffi::cbss_node_child_count(self.context.as_ptr(), node) };
            for index in 0..count {
                let child = unsafe { ffi::cbss_node_child(self.context.as_ptr(), node, index) };
                if child == NODE_NONE {
                    return Err(Error::status(
                        STATUS_INTERNAL_ERROR,
                        "remove subtree: unable to enumerate child Node",
                    ));
                }
                pending.push(child);
            }
        }
        Ok(result)
    }

    fn owned_node(&self, id: u32) -> Option<Node> {
        (id != NODE_NONE).then_some(Node {
            owner: self.context,
            id,
        })
    }

    fn added_node(&self, id: u32, operation: &str) -> Result<Node> {
        self.owned_node(id).ok_or_else(|| {
            Error::status(
                STATUS_INTERNAL_ERROR,
                format!("{operation}: {}", self.context_error_message()),
            )
        })
    }

    fn require_node(&self, node: Node, operation: &str) -> Result<()> {
        if node.owner != self.context {
            return Err(Error::status(
                STATUS_INVALID_HANDLE,
                format!("{operation}: Node belongs to another Ui"),
            ));
        }
        Ok(())
    }

    fn check(&self, status: i32, operation: &str) -> Result<()> {
        if status == STATUS_OK {
            return Ok(());
        }
        Err(Error::status(
            status,
            format!("{operation}: {}", self.context_error_message()),
        ))
    }

    fn require_event_capability(&self) -> Result<()> {
        Contract::require(&[CapabilityRequirement {
            id: CAPABILITY_STANDARD_EVENTS,
            minimum_version: 1,
        }])
    }

    fn context_error_message(&self) -> String {
        let mut buffer = [0_u8; 512];
        let length = unsafe {
            ffi::cbss_context_last_error(
                self.context.as_ptr(),
                buffer.as_mut_ptr().cast(),
                buffer.len() as u32,
            )
        };
        if length == 0 {
            return "no diagnostic was provided".to_owned();
        }
        let end = buffer
            .iter()
            .position(|byte| *byte == 0)
            .unwrap_or(buffer.len());
        String::from_utf8_lossy(&buffer[..end]).into_owned()
    }
}

impl Drop for Ui {
    fn drop(&mut self) {
        unsafe { ffi::cbss_context_destroy(self.context.as_ptr()) }
        self.events.shutdown();
    }
}

pub struct Scope<'ui> {
    ui: &'ui mut Ui,
    parent: Node,
}

impl Scope<'_> {
    pub fn box_node(&mut self, identifier: &str, style: Option<&Style>) -> Result<Node> {
        self.ui.add_box(Some(self.parent), identifier, style)
    }

    pub fn box_with<F>(
        &mut self,
        identifier: &str,
        style: Option<&Style>,
        children: F,
    ) -> Result<Node>
    where
        F: FnOnce(&mut Scope<'_>) -> Result<()>,
    {
        let node = self.ui.add_box(Some(self.parent), identifier, style)?;
        let mut scope = Scope {
            ui: self.ui,
            parent: node,
        };
        children(&mut scope)?;
        Ok(node)
    }

    pub fn text(&mut self, value: &str, identifier: &str, style: Option<&Style>) -> Result<Node> {
        self.ui
            .add_text(Some(self.parent), value, identifier, style)
    }

    pub fn image(
        &mut self,
        source: &str,
        width: f32,
        height: f32,
        identifier: &str,
        style: Option<&Style>,
    ) -> Result<Node> {
        self.ui
            .add_image(Some(self.parent), source, width, height, identifier, style)
    }

    pub fn component_with<F>(
        &mut self,
        craft_name: &str,
        identifier: &str,
        owned_style: Option<&Style>,
        children: F,
    ) -> Result<CraftComponent>
    where
        F: FnOnce(&mut ComponentScope<'_>) -> Result<()>,
    {
        self.ui.add_component(
            Some(self.parent),
            craft_name,
            identifier,
            owned_style,
            children,
        )
    }
}

pub struct ComponentScope<'ui> {
    scope: Scope<'ui>,
    root: Node,
    craft_name: String,
}

impl ComponentScope<'_> {
    pub fn root(&self) -> Node {
        self.root
    }

    pub fn craft_name(&self) -> &str {
        &self.craft_name
    }

    pub fn box_node(&mut self, identifier: &str, style: Option<&Style>) -> Result<Node> {
        self.scope.box_node(identifier, style)
    }

    pub fn box_with<F>(
        &mut self,
        identifier: &str,
        style: Option<&Style>,
        children: F,
    ) -> Result<Node>
    where
        F: FnOnce(&mut Scope<'_>) -> Result<()>,
    {
        self.scope.box_with(identifier, style, children)
    }

    pub fn text(&mut self, value: &str, identifier: &str, style: Option<&Style>) -> Result<Node> {
        self.scope.text(value, identifier, style)
    }

    pub fn image(
        &mut self,
        source: &str,
        width: f32,
        height: f32,
        identifier: &str,
        style: Option<&Style>,
    ) -> Result<Node> {
        self.scope.image(source, width, height, identifier, style)
    }

    pub fn public_style_slot(&mut self, slot: &str, target: Option<Node>) -> Result<()> {
        self.scope.ui.expose_style_slot(
            self.root,
            target.unwrap_or(self.root),
            &self.craft_name,
            slot,
        )
    }

    pub fn on<F>(&mut self, node: Node, kind: EventKind, callback: F) -> Result<()>
    where
        F: FnMut(&Event) -> EventOutcome + 'static,
    {
        self.scope.ui.on(node, kind, callback)
    }

    pub fn on_root<F>(&mut self, kind: EventKind, callback: F) -> Result<()>
    where
        F: FnMut(&Event) -> EventOutcome + 'static,
    {
        self.scope.ui.on(self.root, kind, callback)
    }
}

fn c_string(value: &str, label: &str) -> Result<CString> {
    CString::new(value).map_err(|error: NulError| {
        Error::status(
            STATUS_INVALID_ARGUMENT,
            format!(
                "{label} contains an interior NUL byte at {}",
                error.nul_position()
            ),
        )
    })
}

fn checked_source_length(source: &str, maximum: usize, operation: &str) -> Result<u32> {
    if source.is_empty() {
        return Err(Error::status(
            STATUS_INVALID_ARGUMENT,
            format!("{operation}: source is empty"),
        ));
    }
    if source.len() > maximum || source.len() > u32::MAX as usize {
        return Err(Error::status(
            STATUS_OUT_OF_RANGE,
            format!("{operation}: source is too large"),
        ));
    }
    Ok(source.len() as u32)
}

fn read_context_string<F>(mut reader: F) -> String
where
    F: FnMut(*mut c_char, u32) -> u32,
{
    let length = reader(std::ptr::null_mut(), 0);
    if length == 0 {
        return String::new();
    }

    let mut buffer = vec![0_u8; length as usize + 1];
    let written = reader(buffer.as_mut_ptr().cast(), buffer.len() as u32);
    let used = usize::min(length as usize, written as usize);
    String::from_utf8_lossy(&buffer[..used]).into_owned()
}

fn check_status(status: i32, operation: &str) -> Result<()> {
    if status == STATUS_OK {
        Ok(())
    } else {
        Err(Error::status(status, operation))
    }
}
