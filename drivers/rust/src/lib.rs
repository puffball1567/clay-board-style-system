//! High-level Rust Craft Driver for Clay Board Style System.

mod generated;

use std::ffi::{CString, NulError};
use std::fmt;
use std::marker::PhantomData;
use std::os::raw::{c_char, c_float, c_int, c_uint};
use std::ptr::NonNull;
use std::rc::Rc;

pub use generated::{
    CapabilityDefinition, ABI_VERSION, CAPABILITIES, CAPABILITY_ACCESSIBILITY_SEMANTICS,
    CAPABILITY_BLOB, CAPABILITY_DECLARATIVE_MOTION, CAPABILITY_FLEX_LAYOUT, CAPABILITY_FOCUS,
    CAPABILITY_FORM_DATA, CAPABILITY_HIT_TEST, CAPABILITY_PAINT_COMMANDS,
    CAPABILITY_RENDER_SURFACE, CAPABILITY_RETAINED_CANVAS, CAPABILITY_RETAINED_SCROLL,
    CAPABILITY_RETAINED_TREE, CAPABILITY_STANDARD_EVENTS, CAPABILITY_STREAM,
    CAPABILITY_TYPED_STYLE, DRIVER_CONTRACT_VERSION,
};

pub const STATUS_OK: i32 = 0;
pub const STATUS_INVALID_ARGUMENT: i32 = 1;
pub const STATUS_INVALID_HANDLE: i32 = 2;
pub const STATUS_OUT_OF_RANGE: i32 = 3;
pub const STATUS_STYLE_ERROR: i32 = 4;
pub const STATUS_INTERNAL_ERROR: i32 = 5;
pub const STATUS_NOT_AVAILABLE: i32 = 6;

const NODE_NONE: u32 = u32::MAX;

mod ffi {
    use super::{c_char, c_float, c_int, c_uint, Color, Rect};

    #[repr(C)]
    pub struct CbssContext {
        _private: [u8; 0],
    }

    #[repr(C)]
    pub struct CbssStyle {
        _private: [u8; 0],
    }

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
        pub fn cbss_context_node_count(context: *mut CbssContext) -> c_uint;
        pub fn cbss_node_parent(context: *mut CbssContext, node: c_uint) -> c_uint;
        pub fn cbss_node_child_count(context: *mut CbssContext, node: c_uint) -> c_uint;
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

pub struct Ui {
    context: NonNull<ffi::CbssContext>,
    _not_send: PhantomData<Rc<()>>,
}

impl Ui {
    pub fn new() -> Result<Self> {
        Contract::require_authoring()?;
        let context = NonNull::new(unsafe { ffi::cbss_context_create() })
            .ok_or_else(|| Error::status(STATUS_INTERNAL_ERROR, "unable to create UI"))?;
        Ok(Self {
            context,
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

    pub fn reset(&mut self) -> Result<()> {
        let status = unsafe { ffi::cbss_context_reset(self.context.as_ptr()) };
        self.check(status, "reset UI")
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

    fn parent_id(&self, parent: Option<Node>) -> Result<u32> {
        match parent {
            Some(node) => {
                self.require_node(node, "use parent Node")?;
                Ok(node.id)
            }
            None => Ok(NODE_NONE),
        }
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

fn check_status(status: i32, operation: &str) -> Result<()> {
    if status == STATUS_OK {
        Ok(())
    } else {
        Err(Error::status(status, operation))
    }
}
