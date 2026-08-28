use crate::{ffi, Error, Result, STATUS_INVALID_ARGUMENT};
use std::cell::RefCell;
use std::fmt;
use std::os::raw::{c_uint, c_void};
use std::ptr::NonNull;
use std::rc::Rc;

const MAX_PATTERN_BYTES: usize = 65_536;
const MAX_VALUE_BYTES: usize = 16 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ValidationReport {
    OnInput,
    OnBlur,
    OnSubmit,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ValidationTrigger {
    Input,
    Blur,
    Submit,
    Explicit,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ValidationRuleKind {
    Required,
    Optional,
    MinLength,
    MaxLength,
    ExactLength,
    NotBlank,
    Matches,
    Contains,
    StartsWith,
    EndsWith,
    Email,
    Url,
    Uuid,
    IpAddress,
    Date,
    Time,
    DateTime,
    Min,
    Max,
    Range,
    Integer,
    Positive,
    Negative,
    Finite,
    MultipleOf,
    EqualTo,
    NotEqualTo,
    OneOf,
    NotOneOf,
    SameAs,
    DifferentFrom,
    MinItems,
    MaxItems,
    ExactItems,
    UniqueItems,
    MaxFileSize,
    AllowedMimeTypes,
    AllowedExtensions,
    MaxFiles,
    Custom,
}

impl ValidationRuleKind {
    pub fn code(self) -> &'static str {
        match self {
            Self::Required => "required",
            Self::Optional => "optional",
            Self::MinLength => "minLength",
            Self::MaxLength => "maxLength",
            Self::ExactLength => "exactLength",
            Self::NotBlank => "notBlank",
            Self::Matches => "matches",
            Self::Contains => "contains",
            Self::StartsWith => "startsWith",
            Self::EndsWith => "endsWith",
            Self::Email => "email",
            Self::Url => "url",
            Self::Uuid => "uuid",
            Self::IpAddress => "ipAddress",
            Self::Date => "date",
            Self::Time => "time",
            Self::DateTime => "dateTime",
            Self::Min => "min",
            Self::Max => "max",
            Self::Range => "range",
            Self::Integer => "integer",
            Self::Positive => "positive",
            Self::Negative => "negative",
            Self::Finite => "finite",
            Self::MultipleOf => "multipleOf",
            Self::EqualTo => "equalTo",
            Self::NotEqualTo => "notEqualTo",
            Self::OneOf => "oneOf",
            Self::NotOneOf => "notOneOf",
            Self::SameAs => "sameAs",
            Self::DifferentFrom => "differentFrom",
            Self::MinItems => "minItems",
            Self::MaxItems => "maxItems",
            Self::ExactItems => "exactItems",
            Self::UniqueItems => "uniqueItems",
            Self::MaxFileSize => "maxFileSize",
            Self::AllowedMimeTypes => "allowedMimeTypes",
            Self::AllowedExtensions => "allowedExtensions",
            Self::MaxFiles => "maxFiles",
            Self::Custom => "custom",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidationIssue {
    pub code: String,
    pub message: String,
    pub rule_index: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidationResult {
    pub is_valid: bool,
    pub issue: Option<ValidationIssue>,
}

impl ValidationResult {
    pub fn valid() -> Self {
        Self {
            is_valid: true,
            issue: None,
        }
    }

    fn invalid(kind: ValidationRuleKind, message: &str, rule_index: usize) -> Self {
        Self {
            is_valid: false,
            issue: Some(ValidationIssue {
                code: kind.code().to_owned(),
                message: message.to_owned(),
                rule_index,
            }),
        }
    }

    pub fn code(&self) -> &str {
        self.issue.as_ref().map_or("", |issue| issue.code.as_str())
    }

    pub fn message(&self) -> &str {
        self.issue
            .as_ref()
            .map_or("", |issue| issue.message.as_str())
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidationFile {
    pub name: String,
    pub mime_type: String,
    pub size: u64,
}

impl ValidationFile {
    pub fn new(name: impl Into<String>, size: u64, mime_type: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            mime_type: mime_type.into(),
            size,
        }
    }
}

struct PatternInner(NonNull<ffi::CbssValidationPattern>);

impl Drop for PatternInner {
    fn drop(&mut self) {
        unsafe { ffi::cbss_validation_pattern_destroy(self.0.as_ptr()) };
    }
}

#[derive(Clone)]
pub struct ValidationPattern(Rc<PatternInner>);

impl fmt::Debug for ValidationPattern {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ValidationPattern")
            .finish_non_exhaustive()
    }
}

impl ValidationPattern {
    pub fn compile(source: &str) -> Result<Self> {
        if source.is_empty() || source.len() > MAX_PATTERN_BYTES {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "validation regular expression must contain 1 to 65536 bytes",
            ));
        }
        let mut output = std::ptr::null_mut();
        let mut error = vec![0_i8; 512];
        let status = unsafe {
            ffi::cbss_validation_pattern_compile(
                source.as_ptr().cast::<c_void>(),
                source.len() as c_uint,
                &mut output,
                error.as_mut_ptr(),
                error.len() as c_uint,
            )
        };
        if status != 0 {
            let bytes = error
                .iter()
                .take_while(|value| **value != 0)
                .map(|value| *value as u8)
                .collect::<Vec<_>>();
            let message = String::from_utf8_lossy(&bytes);
            return Err(Error::status(
                status,
                if message.is_empty() {
                    "invalid validation regular expression".to_owned()
                } else {
                    message.into_owned()
                },
            ));
        }
        let handle = NonNull::new(output).ok_or_else(|| {
            Error::status(
                STATUS_INVALID_ARGUMENT,
                "validation pattern compilation returned no handle",
            )
        })?;
        Ok(Self(Rc::new(PatternInner(handle))))
    }

    pub fn test(&self, value: &str) -> Result<bool> {
        if value.len() > MAX_VALUE_BYTES {
            return Ok(false);
        }
        let mut output = 0_u8;
        let pointer = if value.is_empty() {
            std::ptr::null()
        } else {
            value.as_ptr().cast::<c_void>()
        };
        let status = unsafe {
            ffi::cbss_validation_pattern_matches(
                self.0 .0.as_ptr(),
                pointer,
                value.len() as c_uint,
                &mut output,
            )
        };
        if status == 0 {
            Ok(output != 0)
        } else {
            Err(Error::status(
                status,
                "unable to evaluate validation pattern",
            ))
        }
    }
}

pub struct ValidationValue<T>(Rc<RefCell<T>>);

impl<T> Clone for ValidationValue<T> {
    fn clone(&self) -> Self {
        Self(Rc::clone(&self.0))
    }
}

impl<T> ValidationValue<T> {
    pub fn new(value: T) -> Self {
        Self(Rc::new(RefCell::new(value)))
    }

    pub fn set(&self, value: T) {
        *self.0.borrow_mut() = value;
    }

    pub fn with<R>(&self, read: impl FnOnce(&T) -> R) -> R {
        read(&self.0.borrow())
    }

    pub fn same_identity(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }

    pub fn identity(&self) -> usize {
        Rc::as_ptr(&self.0) as usize
    }
}

pub trait ValidationValueType {
    fn is_absent(&self) -> bool {
        false
    }
}

impl ValidationValueType for String {
    fn is_absent(&self) -> bool {
        self.is_empty()
    }
}

impl<T> ValidationValueType for Vec<T> {
    fn is_absent(&self) -> bool {
        self.is_empty()
    }
}

macro_rules! scalar_validation_values {
    ($($kind:ty),+ $(,)?) => {$(
        impl ValidationValueType for $kind {}
    )+};
}
scalar_validation_values!(i8, i16, i32, i64, isize, u8, u16, u32, u64, usize, f32, f64, bool);

type RuleTest<T> = dyn Fn(&T) -> bool;

struct Rule<T> {
    kind: ValidationRuleKind,
    message: String,
    test: Rc<RuleTest<T>>,
    peer: Option<ValidationValue<T>>,
}

impl<T> Clone for Rule<T> {
    fn clone(&self) -> Self {
        Self {
            kind: self.kind,
            message: self.message.clone(),
            test: Rc::clone(&self.test),
            peer: self.peer.clone(),
        }
    }
}

pub struct ValidationRules<T> {
    rules: Vec<Rule<T>>,
}

impl<T> Clone for ValidationRules<T> {
    fn clone(&self) -> Self {
        Self {
            rules: self.rules.clone(),
        }
    }
}

impl<T> Default for ValidationRules<T> {
    fn default() -> Self {
        Self { rules: Vec::new() }
    }
}

impl<T: ValidationValueType + 'static> ValidationRules<T> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn len(&self) -> usize {
        self.rules.len()
    }

    pub fn is_empty(&self) -> bool {
        self.rules.is_empty()
    }

    fn add(
        &self,
        kind: ValidationRuleKind,
        message: impl Into<String>,
        test: impl Fn(&T) -> bool + 'static,
    ) -> Self {
        let mut result = self.clone();
        result.rules.push(Rule {
            kind,
            message: message.into(),
            test: Rc::new(test),
            peer: None,
        });
        result
    }

    pub fn required(&self, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::Required, message, |value| {
            !value.is_absent()
        })
    }

    pub fn optional(&self) -> Self {
        self.add(ValidationRuleKind::Optional, "", |_| true)
    }

    pub fn custom(
        &self,
        validator: impl Fn(&T) -> bool + 'static,
        message: impl Into<String>,
    ) -> Self {
        self.add(ValidationRuleKind::Custom, message, validator)
    }

    pub fn validate(&self, value: &T) -> ValidationResult {
        let absent = value.is_absent();
        let mut optional = false;
        let mut required_index = None;
        for (index, rule) in self.rules.iter().enumerate() {
            match rule.kind {
                ValidationRuleKind::Optional => optional = true,
                ValidationRuleKind::Required => required_index = Some(index),
                _ => {}
            }
        }
        if absent {
            if let Some(index) = required_index {
                let rule = &self.rules[index];
                return ValidationResult::invalid(rule.kind, &rule.message, index);
            }
            if optional {
                return ValidationResult::valid();
            }
        }
        for (index, rule) in self.rules.iter().enumerate() {
            if matches!(
                rule.kind,
                ValidationRuleKind::Required | ValidationRuleKind::Optional
            ) {
                continue;
            }
            if !(rule.test)(value) {
                return ValidationResult::invalid(rule.kind, &rule.message, index);
            }
        }
        ValidationResult::valid()
    }

    pub fn dependency_references(&self) -> Vec<ValidationValue<T>> {
        let mut result: Vec<ValidationValue<T>> = Vec::new();
        for peer in self.rules.iter().filter_map(|rule| rule.peer.as_ref()) {
            if !result.iter().any(|existing| existing.same_identity(peer)) {
                result.push(peer.clone());
            }
        }
        result
    }
}

impl<T> ValidationRules<T>
where
    T: ValidationValueType + Clone + PartialEq + 'static,
{
    pub fn equal_to(&self, expected: T, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::EqualTo, message, move |value| {
            value == &expected
        })
    }

    pub fn not_equal_to(&self, expected: T, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::NotEqualTo, message, move |value| {
            value != &expected
        })
    }

    pub fn one_of(&self, values: Vec<T>, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::OneOf, message, move |value| {
            values.contains(value)
        })
    }

    pub fn not_one_of(&self, values: Vec<T>, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::NotOneOf, message, move |value| {
            !values.contains(value)
        })
    }

    pub fn same_as(&self, peer: ValidationValue<T>, message: impl Into<String>) -> Self {
        let captured = peer.clone();
        let mut result = self.add(ValidationRuleKind::SameAs, message, move |value| {
            captured.with(|expected| value == expected)
        });
        result.rules.last_mut().expect("rule was appended").peer = Some(peer);
        result
    }

    pub fn different_from(&self, peer: ValidationValue<T>, message: impl Into<String>) -> Self {
        let captured = peer.clone();
        let mut result = self.add(ValidationRuleKind::DifferentFrom, message, move |value| {
            captured.with(|expected| value != expected)
        });
        result.rules.last_mut().expect("rule was appended").peer = Some(peer);
        result
    }
}

fn string_format(kind: c_uint, value: &str) -> bool {
    if value.len() > MAX_VALUE_BYTES {
        return false;
    }
    let pointer = if value.is_empty() {
        std::ptr::null()
    } else {
        value.as_ptr().cast::<c_void>()
    };
    let mut output = 0_u8;
    let status = unsafe {
        ffi::cbss_validation_string_format(kind, pointer, value.len() as c_uint, &mut output)
    };
    status == 0 && output != 0
}

impl ValidationRules<String> {
    pub fn min_length(&self, length: usize, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::MinLength, message, move |value| {
            value.chars().count() >= length
        })
    }

    pub fn max_length(&self, length: usize, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::MaxLength, message, move |value| {
            value.chars().count() <= length
        })
    }

    pub fn exact_length(&self, length: usize, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::ExactLength, message, move |value| {
            value.chars().count() == length
        })
    }

    pub fn not_blank(&self, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::NotBlank, message, |value| {
            !value.trim().is_empty()
        })
    }

    pub fn matches(&self, pattern: ValidationPattern, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::Matches, message, move |value| {
            pattern.test(value).unwrap_or(false)
        })
    }

    pub fn contains(&self, text: impl Into<String>, message: impl Into<String>) -> Self {
        let text = text.into();
        self.add(ValidationRuleKind::Contains, message, move |value| {
            value.contains(&text)
        })
    }

    pub fn starts_with(&self, text: impl Into<String>, message: impl Into<String>) -> Self {
        let text = text.into();
        self.add(ValidationRuleKind::StartsWith, message, move |value| {
            value.starts_with(&text)
        })
    }

    pub fn ends_with(&self, text: impl Into<String>, message: impl Into<String>) -> Self {
        let text = text.into();
        self.add(ValidationRuleKind::EndsWith, message, move |value| {
            value.ends_with(&text)
        })
    }

    fn format_rule(
        &self,
        rule: ValidationRuleKind,
        format: c_uint,
        message: impl Into<String>,
    ) -> Self {
        self.add(rule, message, move |value| string_format(format, value))
    }

    pub fn email(&self, message: impl Into<String>) -> Self {
        self.format_rule(ValidationRuleKind::Email, 0, message)
    }
    pub fn url(&self, message: impl Into<String>) -> Self {
        self.format_rule(ValidationRuleKind::Url, 1, message)
    }
    pub fn uuid(&self, message: impl Into<String>) -> Self {
        self.format_rule(ValidationRuleKind::Uuid, 2, message)
    }
    pub fn ip_address(&self, message: impl Into<String>) -> Self {
        self.format_rule(ValidationRuleKind::IpAddress, 3, message)
    }
    pub fn date(&self, message: impl Into<String>) -> Self {
        self.format_rule(ValidationRuleKind::Date, 4, message)
    }
    pub fn time(&self, message: impl Into<String>) -> Self {
        self.format_rule(ValidationRuleKind::Time, 5, message)
    }
    pub fn date_time(&self, message: impl Into<String>) -> Self {
        self.format_rule(ValidationRuleKind::DateTime, 6, message)
    }
}

pub trait ValidationNumber: ValidationValueType + Copy + PartialOrd + 'static {
    fn to_f64(self) -> f64;
    fn is_integer(self) -> bool;
    fn is_finite_value(self) -> bool;
}

macro_rules! integer_validation_numbers {
    ($($kind:ty),+ $(,)?) => {$(
        impl ValidationNumber for $kind {
            fn to_f64(self) -> f64 { self as f64 }
            fn is_integer(self) -> bool { true }
            fn is_finite_value(self) -> bool { true }
        }
    )+};
}
integer_validation_numbers!(i8, i16, i32, i64, isize, u8, u16, u32, u64, usize);

macro_rules! float_validation_numbers {
    ($($kind:ty),+ $(,)?) => {$(
        impl ValidationNumber for $kind {
            fn to_f64(self) -> f64 { self as f64 }
            fn is_integer(self) -> bool { self.is_finite() && self.fract() == 0.0 }
            fn is_finite_value(self) -> bool { self.is_finite() }
        }
    )+};
}
float_validation_numbers!(f32, f64);

impl<T: ValidationNumber> ValidationRules<T> {
    pub fn min(&self, limit: T, message: impl Into<String>) -> Result<Self> {
        if limit.to_f64().is_nan() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "numeric validation limit cannot be NaN",
            ));
        }
        Ok(self.add(ValidationRuleKind::Min, message, move |value| {
            *value >= limit
        }))
    }

    pub fn max(&self, limit: T, message: impl Into<String>) -> Result<Self> {
        if limit.to_f64().is_nan() {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "numeric validation limit cannot be NaN",
            ));
        }
        Ok(self.add(ValidationRuleKind::Max, message, move |value| {
            *value <= limit
        }))
    }

    pub fn range(&self, minimum: T, maximum: T, message: impl Into<String>) -> Result<Self> {
        if minimum.to_f64().is_nan() || maximum.to_f64().is_nan() || minimum > maximum {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "invalid validation range",
            ));
        }
        Ok(self.add(ValidationRuleKind::Range, message, move |value| {
            *value >= minimum && *value <= maximum
        }))
    }

    pub fn integer(&self, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::Integer, message, |value| {
            value.is_integer()
        })
    }

    pub fn positive(&self, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::Positive, message, |value| {
            value.to_f64() > 0.0
        })
    }

    pub fn negative(&self, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::Negative, message, |value| {
            value.to_f64() < 0.0
        })
    }

    pub fn finite(&self, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::Finite, message, |value| {
            value.is_finite_value()
        })
    }

    pub fn multiple_of(&self, divisor: T, message: impl Into<String>) -> Result<Self> {
        let divisor = divisor.to_f64();
        if !divisor.is_finite() || divisor == 0.0 {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "multipleOf divisor must be finite and nonzero",
            ));
        }
        Ok(
            self.add(ValidationRuleKind::MultipleOf, message, move |value| {
                let quotient = value.to_f64() / divisor;
                quotient.is_finite()
                    && (quotient - quotient.round()).abs() <= 1.0e-9 * 1.0_f64.max(quotient.abs())
            }),
        )
    }
}

impl<T> ValidationRules<Vec<T>>
where
    T: Clone + PartialEq + 'static,
{
    pub fn min_items(&self, count: usize, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::MinItems, message, move |value| {
            value.len() >= count
        })
    }
    pub fn max_items(&self, count: usize, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::MaxItems, message, move |value| {
            value.len() <= count
        })
    }
    pub fn exact_items(&self, count: usize, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::ExactItems, message, move |value| {
            value.len() == count
        })
    }
    pub fn unique_items(&self, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::UniqueItems, message, |values| {
            values.iter().enumerate().all(|(first, value)| {
                !values[first + 1..]
                    .iter()
                    .any(|candidate| candidate == value)
            })
        })
    }
}

fn normalized(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn mime_allowed(value: &str, allowed: &[String]) -> bool {
    let value = normalized(value);
    allowed.iter().any(|candidate| {
        candidate == "*/*"
            || candidate == &value
            || candidate
                .strip_suffix("/*")
                .is_some_and(|prefix| value.starts_with(&format!("{prefix}/")))
    })
}

fn extension(name: &str) -> &str {
    name.rsplit_once('.').map_or("", |(_, extension)| extension)
}

impl ValidationRules<Vec<ValidationFile>> {
    pub fn max_file_size(&self, bytes: u64, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::MaxFileSize, message, move |files| {
            files.iter().all(|file| file.size <= bytes)
        })
    }

    pub fn allowed_mime_types(
        &self,
        values: impl IntoIterator<Item = impl Into<String>>,
        message: impl Into<String>,
    ) -> Result<Self> {
        let values = values
            .into_iter()
            .map(|value| normalized(&value.into()))
            .collect::<Vec<_>>();
        for value in &values {
            let Some((media_type, subtype)) = value.split_once('/') else {
                return Err(Error::status(
                    STATUS_INVALID_ARGUMENT,
                    "allowed MIME types must use type/subtype syntax",
                ));
            };
            if media_type.is_empty()
                || subtype.is_empty()
                || subtype.contains('/')
                || (media_type.contains('*') && media_type != "*")
                || (subtype.contains('*') && subtype != "*")
                || (media_type == "*" && subtype != "*")
            {
                return Err(Error::status(
                    STATUS_INVALID_ARGUMENT,
                    "invalid MIME wildcard",
                ));
            }
        }
        Ok(self.add(
            ValidationRuleKind::AllowedMimeTypes,
            message,
            move |files| {
                files
                    .iter()
                    .all(|file| mime_allowed(&file.mime_type, &values))
            },
        ))
    }

    pub fn allowed_extensions(
        &self,
        values: impl IntoIterator<Item = impl Into<String>>,
        message: impl Into<String>,
    ) -> Result<Self> {
        let values = values
            .into_iter()
            .map(|value| normalized(&value.into()).trim_start_matches('.').to_owned())
            .collect::<Vec<_>>();
        if values.iter().any(String::is_empty) {
            return Err(Error::status(
                STATUS_INVALID_ARGUMENT,
                "allowed extensions cannot contain an empty value",
            ));
        }
        Ok(self.add(
            ValidationRuleKind::AllowedExtensions,
            message,
            move |files| {
                files.iter().all(|file| {
                    values
                        .iter()
                        .any(|value| value == &normalized(extension(&file.name)))
                })
            },
        ))
    }

    pub fn max_files(&self, count: usize, message: impl Into<String>) -> Self {
        self.add(ValidationRuleKind::MaxFiles, message, move |files| {
            files.len() <= count
        })
    }
}

pub struct ValidationBinding<T> {
    rules: ValidationRules<T>,
    value: ValidationValue<T>,
    report_on: ValidationReport,
    result: ValidationResult,
    has_reported: bool,
}

impl<T: ValidationValueType + 'static> ValidationBinding<T> {
    pub fn new(rules: ValidationRules<T>, value: T, report_on: ValidationReport) -> Self {
        let value = ValidationValue::new(value);
        let result = value.with(|current| rules.validate(current));
        Self {
            rules,
            value,
            report_on,
            result,
            has_reported: false,
        }
    }

    pub fn evaluate(
        &mut self,
        value: T,
        trigger: ValidationTrigger,
        force_report: bool,
    ) -> &ValidationResult {
        self.value.set(value);
        self.result = self.value.with(|current| self.rules.validate(current));
        if force_report
            || (trigger == ValidationTrigger::Input && self.report_on == ValidationReport::OnInput)
            || (trigger == ValidationTrigger::Blur && self.report_on != ValidationReport::OnSubmit)
            || (trigger == ValidationTrigger::Submit
                && self.report_on == ValidationReport::OnSubmit)
        {
            self.has_reported = true;
        }
        &self.result
    }

    pub fn current(&self) -> &ValidationResult {
        &self.result
    }

    pub fn should_expose(&self) -> bool {
        self.has_reported && !self.result.is_valid
    }

    pub fn validation_message(&self) -> &str {
        if self.should_expose() {
            self.result.message()
        } else {
            ""
        }
    }

    pub fn value_reference(&self) -> ValidationValue<T> {
        self.value.clone()
    }
}
