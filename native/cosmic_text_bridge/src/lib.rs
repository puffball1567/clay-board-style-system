use cosmic_text::{
    fontdb, Align, Attrs, Buffer, Cursor, Family, FeatureTag, FontFeatures, FontSystem, Metrics,
    Shaping, Stretch, Style, SwashCache, Weight, Wrap,
};
use std::ffi::CStr;
use std::os::raw::{c_char, c_float, c_uchar};
use std::ptr;
use std::slice;
use unicode_segmentation::UnicodeSegmentation;

macro_rules! ffi_guard {
    ($fallback:expr, $body:block) => {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| $body)).unwrap_or($fallback)
    };
}

pub struct CbssCosmicTextEngine {
    font_system: FontSystem,
    swash_cache: SwashCache,
    shape_cache: Vec<ShapeCacheEntry>,
    shape_cache_clock: u64,
}

/// Shaping the same (text, style, width) repeatedly dominates interactive
/// editing cost: one edit triggers measure + caret + caret-layout + render
/// against identical input. A tiny LRU of shaped buffers collapses those into
/// one shaping pass.
const SHAPE_CACHE_LIMIT: usize = 8;

#[derive(Clone, PartialEq, Eq)]
struct ShapeKey {
    text: String,
    family_csv: String,
    font_features: String,
    font_variations: String,
    font_size: u32,
    line_height: u32,
    max_width: u32,
    has_max_width: u8,
    font_weight: u32,
    font_style: u32,
    font_stretch: u32,
    letter_spacing: u32,
    word_spacing: u32,
    wrap: u32,
    text_indent: u32,
    text_align: u32,
}

struct PreparedSegment {
    buffer: Buffer,
    text: String,
    source_start: usize,
    x_offset: f32,
    y_offset: f32,
}

struct PreparedLayout {
    source_text: String,
    segments: Vec<PreparedSegment>,
    line_height: f32,
}

struct ShapeCacheEntry {
    key: ShapeKey,
    layout: PreparedLayout,
    last_used: u64,
}

fn shape_key(input: &CbssCosmicTextMeasureInput) -> ShapeKey {
    ShapeKey {
        text: cstr_or_empty(input.text),
        family_csv: cstr_or_empty(input.family_csv),
        font_features: cstr_or_empty(input.font_features),
        font_variations: cstr_or_empty(input.font_variations),
        font_size: input.font_size.to_bits(),
        line_height: input.line_height.to_bits(),
        max_width: input.max_width.to_bits(),
        has_max_width: input.has_max_width,
        font_weight: input.font_weight.to_bits(),
        font_style: input.font_style,
        font_stretch: input.font_stretch.to_bits(),
        letter_spacing: input.letter_spacing.to_bits(),
        word_spacing: input.word_spacing.to_bits(),
        wrap: input.wrap,
        text_indent: input.text_indent.to_bits(),
        text_align: input.text_align,
    }
}

fn shaped_cache_entry<'a>(
    font_system: &mut FontSystem,
    shape_cache: &'a mut Vec<ShapeCacheEntry>,
    shape_cache_clock: &mut u64,
    input: &CbssCosmicTextMeasureInput,
) -> &'a mut PreparedLayout {
    *shape_cache_clock += 1;
    let clock = *shape_cache_clock;
    let key = shape_key(input);
    if let Some(index) = shape_cache.iter().position(|entry| entry.key == key) {
        let entry = &mut shape_cache[index];
        entry.last_used = clock;
        return &mut entry.layout;
    }
    let layout = prepare_layout(font_system, input);
    if shape_cache.len() >= SHAPE_CACHE_LIMIT {
        let mut victim = 0usize;
        for index in 1..shape_cache.len() {
            if shape_cache[index].last_used < shape_cache[victim].last_used {
                victim = index;
            }
        }
        shape_cache.swap_remove(victim);
    }
    shape_cache.push(ShapeCacheEntry {
        key,
        layout,
        last_used: clock,
    });
    let entry = shape_cache.last_mut().expect("entry just pushed");
    &mut entry.layout
}

#[repr(C)]
pub struct CbssCosmicTextMeasureInput {
    pub text: *const c_char,
    pub family_csv: *const c_char,
    pub font_features: *const c_char,
    pub font_variations: *const c_char,
    pub font_size: c_float,
    pub line_height: c_float,
    pub max_width: c_float,
    pub has_max_width: u8,
    pub font_weight: c_float,
    pub font_style: u32,
    pub font_stretch: c_float,
    pub letter_spacing: c_float,
    pub word_spacing: c_float,
    pub wrap: u32,
    pub text_indent: c_float,
    pub text_align: u32,
}

#[repr(C)]
pub struct CbssCosmicTextMeasureResult {
    pub width: c_float,
    pub height: c_float,
    pub ok: u8,
}

#[repr(C)]
pub struct CbssCosmicTextFontMetricsResult {
    pub x_height: c_float,
    pub zero_advance: c_float,
    pub ok: u8,
}

#[repr(C)]
pub struct CbssCosmicTextBaselineMetricsResult {
    pub ascent: c_float,
    pub descent: c_float,
    pub ok: u8,
}

#[repr(C)]
pub struct CbssCosmicTextBitmapResult {
    pub width: u32,
    pub height: u32,
    pub offset_x: i32,
    pub offset_y: i32,
    pub len: usize,
    pub pixels: *mut u8,
    pub ok: u8,
}

#[repr(C)]
pub struct CbssCosmicTextCaretQuery {
    pub byte_index: usize,
}

#[repr(C)]
pub struct CbssCosmicTextPointQuery {
    pub x: c_float,
    pub y: c_float,
}

#[repr(C)]
pub struct CbssCosmicTextCaretResult {
    pub x: c_float,
    pub y: c_float,
    pub height: c_float,
    pub byte_index: usize,
    pub ok: u8,
}

#[repr(C)]
pub struct CbssCosmicTextCaretSample {
    pub x: c_float,
    pub y: c_float,
    pub height: c_float,
    pub byte_index: usize,
}

#[repr(C)]
pub struct CbssCosmicTextCaretLayoutResult {
    pub len: usize,
    pub samples: *mut CbssCosmicTextCaretSample,
    pub ok: u8,
}

#[derive(Clone, Copy)]
struct DrawSpan {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    color: cosmic_text::Color,
}

fn cstr_or_empty(value: *const c_char) -> String {
    if value.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(value) }
        .to_string_lossy()
        .into_owned()
}

fn parse_families(value: &str) -> Vec<String> {
    let mut families = Vec::new();
    for raw in value.split(',') {
        let family = raw.trim().trim_matches(|ch| ch == '"' || ch == '\'');
        if !family.is_empty() && !families.iter().any(|existing| existing == family) {
            families.push(family.to_owned());
        }
    }
    if families.is_empty() {
        families.push(String::from("sans-serif"));
    }
    families
}

fn family_from_name(value: &str) -> Family<'_> {
    match value {
        "serif" => Family::Serif,
        "sans-serif" | "system-ui" => Family::SansSerif,
        "monospace" => Family::Monospace,
        "cursive" => Family::Cursive,
        "fantasy" => Family::Fantasy,
        name => Family::Name(name),
    }
}

fn family_supports_text(
    font_system: &mut FontSystem,
    family: Family<'_>,
    attrs: &Attrs<'_>,
    text: &str,
) -> bool {
    let required = text.chars().filter(|ch| !ch.is_control()).count();
    if required == 0 {
        return true;
    }
    let id = font_system.db().query(&fontdb::Query {
        families: std::slice::from_ref(&family),
        weight: attrs.weight,
        stretch: attrs.stretch,
        style: attrs.style,
    });
    id.and_then(|id| font_system.get_font_supported_codepoints_in_word(id, attrs.weight, text))
        == Some(required)
}

fn set_text_with_fallbacks(
    buffer: &mut Buffer,
    font_system: &mut FontSystem,
    text: &str,
    family_names: &[String],
    attrs: &Attrs<'_>,
    letter_spacing_em: f32,
    word_spacing_em: f32,
    align: Option<Align>,
) {
    if (family_names.len() <= 1 && word_spacing_em == 0.0) || text.is_empty() {
        buffer.set_text(text, attrs, Shaping::Advanced, align);
        return;
    }

    let mut ranges = Vec::<(usize, usize, usize, bool)>::new();
    for (start, segment) in text.split_word_bound_indices() {
        let word_separator = segment
            .chars()
            .all(|ch| matches!(ch, '\t' | ' ' | '\u{00a0}'));
        let family_index = family_names
            .iter()
            .position(|family| {
                family_supports_text(font_system, family_from_name(family), attrs, segment)
            })
            .unwrap_or(0);
        let finish = start + segment.len();
        if let Some(last) = ranges.last_mut() {
            if last.1 == start && last.2 == family_index && last.3 == word_separator {
                last.1 = finish;
                continue;
            }
        }
        ranges.push((start, finish, family_index, word_separator));
    }

    let spans = ranges
        .iter()
        .map(|(start, finish, family_index, word_separator)| {
            let segment = &text[*start..*finish];
            let spacing = if *word_separator {
                letter_spacing_em + word_spacing_em
            } else {
                letter_spacing_em
            };
            let span_attrs = attrs
                .clone()
                .family(family_from_name(&family_names[*family_index]))
                .letter_spacing(spacing);
            (segment, span_attrs)
        });
    buffer.set_rich_text(spans, attrs, Shaping::Advanced, align);
}

fn align_from_u32(value: u32, has_width: bool) -> Option<Align> {
    if !has_width {
        return None;
    }
    match value {
        2 => Some(Align::Center),
        3 => Some(Align::Right),
        _ => Some(Align::Left),
    }
}

fn style_from_u32(value: u32) -> Style {
    match value {
        1 => Style::Italic,
        2 => Style::Oblique,
        _ => Style::Normal,
    }
}

fn stretch_from_percent(value: f32) -> Stretch {
    if value <= 56.25 {
        Stretch::UltraCondensed
    } else if value <= 68.75 {
        Stretch::ExtraCondensed
    } else if value <= 81.25 {
        Stretch::Condensed
    } else if value <= 93.75 {
        Stretch::SemiCondensed
    } else if value <= 106.25 {
        Stretch::Normal
    } else if value <= 118.75 {
        Stretch::SemiExpanded
    } else if value <= 137.5 {
        Stretch::Expanded
    } else if value <= 175.0 {
        Stretch::ExtraExpanded
    } else {
        Stretch::UltraExpanded
    }
}

fn parse_feature_tag(tag: &str) -> Option<[u8; 4]> {
    let bytes = tag.as_bytes();
    if bytes.len() != 4 {
        return None;
    }
    Some([bytes[0], bytes[1], bytes[2], bytes[3]])
}

fn parse_font_features(value: &str) -> FontFeatures {
    let mut features = FontFeatures::new();
    for item in value.split(',') {
        let item = item.trim().trim_matches('"').trim_matches('\'');
        if item.is_empty() || item == "normal" {
            continue;
        }
        let mut parts = item.split_whitespace();
        let Some(tag) = parts.next().and_then(parse_feature_tag) else {
            continue;
        };
        let enabled = parts
            .next()
            .and_then(|raw| raw.parse::<u32>().ok())
            .unwrap_or(1);
        features.set(FeatureTag::new(&tag), enabled);
    }
    features
}

fn parse_axis_item(item: &str) -> Option<(&str, f32)> {
    let item = item.trim().trim_matches('"').trim_matches('\'');
    if item.is_empty() || item == "normal" {
        return None;
    }
    let mut parts = item.split_whitespace();
    let tag = parts.next()?;
    let value = parts.next()?.parse::<f32>().ok()?;
    Some((tag, value))
}

fn apply_variations(value: &str, weight: &mut f32, stretch: &mut f32, style: &mut Style) {
    for item in value.split(',') {
        let Some((tag, axis_value)) = parse_axis_item(item) else {
            continue;
        };
        match tag {
            "wght" => *weight = axis_value,
            "wdth" => *stretch = axis_value,
            "ital" => {
                if axis_value >= 0.5 {
                    *style = Style::Italic;
                }
            }
            "slnt" => {
                if axis_value != 0.0 {
                    *style = Style::Oblique;
                }
            }
            _ => {}
        }
    }
}

fn apply_ttf_variations(face: &mut ttf_parser::Face<'_>, value: &str) {
    for item in value.split(',') {
        let Some((tag, axis_value)) = parse_axis_item(item) else {
            continue;
        };
        let bytes = tag.as_bytes();
        if bytes.len() != 4 {
            continue;
        }
        let axis = ttf_parser::Tag::from_bytes(&[bytes[0], bytes[1], bytes[2], bytes[3]]);
        let _ = face.set_variation(axis, axis_value);
    }
}

#[no_mangle]
pub extern "C" fn cbss_cosmic_text_engine_new(use_system_fonts: u8) -> *mut CbssCosmicTextEngine {
    ffi_guard!(ptr::null_mut(), {
        let font_system = if use_system_fonts != 0 {
            FontSystem::new()
        } else {
            FontSystem::new_with_locale_and_db(String::from("en-US"), fontdb::Database::new())
        };
        Box::into_raw(Box::new(CbssCosmicTextEngine {
            font_system,
            swash_cache: SwashCache::new(),
            shape_cache: Vec::new(),
            shape_cache_clock: 0,
        }))
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_engine_free(engine: *mut CbssCosmicTextEngine) {
    ffi_guard!((), {
        if !engine.is_null() {
            drop(Box::from_raw(engine));
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_add_font_file(
    engine: *mut CbssCosmicTextEngine,
    path: *const c_char,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || path.is_null() {
            return 0;
        }
        let path = cstr_or_empty(path);
        (*engine).shape_cache.clear();
        match (*engine).font_system.db_mut().load_font_file(path) {
            Ok(_) => 1,
            Err(_) => 0,
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_add_font_data(
    engine: *mut CbssCosmicTextEngine,
    data: *const c_uchar,
    len: usize,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || data.is_null() || len == 0 {
            return 0;
        }
        let bytes = slice::from_raw_parts(data, len).to_vec();
        (*engine).shape_cache.clear();
        (*engine).font_system.db_mut().load_font_data(bytes);
        1
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_measure(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    output: *mut CbssCosmicTextMeasureResult,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || input.is_null() || output.is_null() {
            return 0;
        }

        let input = &*input;
        let CbssCosmicTextEngine {
            font_system,
            shape_cache,
            shape_cache_clock,
            ..
        } = &mut *engine;
        let layout = shaped_cache_entry(font_system, shape_cache, shape_cache_clock, input);

        let mut width = 0.0f32;
        let mut height = 0.0f32;
        for segment in &layout.segments {
            let mut has_run = false;
            for run in segment.buffer.layout_runs() {
                has_run = true;
                if !run.glyphs.is_empty() {
                    width = width.max((segment.x_offset + run.line_w).max(0.0));
                }
                height = height.max(segment.y_offset + run.line_top + run.line_height);
            }
            if !has_run {
                height = height.max(segment.y_offset + layout.line_height);
            }
        }

        ptr::write(
            output,
            CbssCosmicTextMeasureResult {
                width,
                height,
                ok: 1,
            },
        );
        1
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_font_unit_metrics(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    output: *mut CbssCosmicTextFontMetricsResult,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || input.is_null() || output.is_null() {
            return 0;
        }

        let input = &*input;
        let font_size = if input.font_size > 0.0 {
            input.font_size
        } else {
            16.0
        };
        let families = parse_families(&cstr_or_empty(input.family_csv));
        let variations = cstr_or_empty(input.font_variations);
        let mut weight = input.font_weight;
        let mut stretch = input.font_stretch;
        let mut style = style_from_u32(input.font_style);
        apply_variations(&variations, &mut weight, &mut stretch, &mut style);

        let CbssCosmicTextEngine {
            font_system,
            shape_cache,
            shape_cache_clock,
            ..
        } = &mut *engine;
        let family = family_from_name(&families[0]);
        let face_id = font_system.db().query(&fontdb::Query {
            families: std::slice::from_ref(&family),
            weight: Weight(weight.clamp(1.0, 1000.0) as u16),
            stretch: stretch_from_percent(stretch),
            style,
        });
        let x_height = face_id
            .and_then(|id| {
                font_system.db().with_face_data(id, |data, index| {
                    ttf_parser::Face::parse(data, index)
                        .ok()
                        .and_then(|mut face| {
                            apply_ttf_variations(&mut face, &variations);
                            face.x_height().map(|height| {
                                height as f32 * font_size / face.units_per_em() as f32
                            })
                        })
                })
            })
            .flatten()
            .filter(|value| value.is_finite() && *value > 0.0)
            .unwrap_or(font_size * 0.5);

        let layout = shaped_cache_entry(font_system, shape_cache, shape_cache_clock, input);
        let zero_advance = layout
            .segments
            .iter()
            .flat_map(|segment| segment.buffer.layout_runs().map(|run| run.line_w))
            .fold(0.0f32, f32::max);
        let zero_advance = if zero_advance.is_finite() && zero_advance > 0.0 {
            zero_advance
        } else {
            font_size * 0.5
        };

        ptr::write(
            output,
            CbssCosmicTextFontMetricsResult {
                x_height,
                zero_advance,
                ok: 1,
            },
        );
        1
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_baseline_metrics(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    output: *mut CbssCosmicTextBaselineMetricsResult,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || input.is_null() || output.is_null() {
            return 0;
        }

        let input = &*input;
        let font_size = if input.font_size > 0.0 {
            input.font_size
        } else {
            16.0
        };
        let families = parse_families(&cstr_or_empty(input.family_csv));
        let variations = cstr_or_empty(input.font_variations);
        let mut weight = input.font_weight;
        let mut stretch = input.font_stretch;
        let mut style = style_from_u32(input.font_style);
        apply_variations(&variations, &mut weight, &mut stretch, &mut style);

        let font_system = &mut (*engine).font_system;
        let family = family_from_name(&families[0]);
        let face_id = font_system.db().query(&fontdb::Query {
            families: std::slice::from_ref(&family),
            weight: Weight(weight.clamp(1.0, 1000.0) as u16),
            stretch: stretch_from_percent(stretch),
            style,
        });
        let metrics = face_id
            .and_then(|id| {
                font_system.db().with_face_data(id, |data, index| {
                    ttf_parser::Face::parse(data, index).ok().map(|mut face| {
                        apply_ttf_variations(&mut face, &variations);
                        let scale = font_size / face.units_per_em() as f32;
                        (
                            face.ascender() as f32 * scale,
                            -(face.descender() as f32) * scale,
                        )
                    })
                })
            })
            .flatten();
        let (ascent, descent) = metrics
            .filter(|(ascent, descent)| {
                ascent.is_finite() && descent.is_finite() && *ascent >= 0.0 && *descent >= 0.0
            })
            .unwrap_or((font_size * 0.8, font_size * 0.2));

        ptr::write(
            output,
            CbssCosmicTextBaselineMetricsResult {
                ascent,
                descent,
                ok: 1,
            },
        );
        1
    })
}

fn prepare_buffer(
    font_system: &mut FontSystem,
    input: &CbssCosmicTextMeasureInput,
    text: &str,
    max_width: Option<f32>,
    wrap: u32,
) -> Buffer {
    let families = parse_families(&cstr_or_empty(input.family_csv));
    let features = cstr_or_empty(input.font_features);
    let variations = cstr_or_empty(input.font_variations);
    let font_size = if input.font_size > 0.0 {
        input.font_size
    } else {
        16.0
    };
    let line_height = if input.line_height > 0.0 {
        input.line_height
    } else {
        font_size * 1.2
    };
    let metrics = Metrics::new(font_size, line_height);
    let mut buffer = Buffer::new(font_system, metrics);
    {
        buffer.set_size(
            Some(max_width.unwrap_or(1_000_000.0).max(0.0)),
            Some(1_000_000.0),
        );
        buffer.set_wrap(match wrap {
            1 => Wrap::None,
            2 => Wrap::Glyph,
            _ => Wrap::Word,
        });
        let letter_spacing_em = if input.letter_spacing != 0.0 {
            input.letter_spacing / font_size
        } else {
            0.0
        };
        let word_spacing_em = if input.word_spacing.is_finite() && input.word_spacing != 0.0 {
            input.word_spacing / font_size
        } else {
            0.0
        };
        let mut weight = input.font_weight;
        let mut stretch = input.font_stretch;
        let mut style = style_from_u32(input.font_style);
        apply_variations(&variations, &mut weight, &mut stretch, &mut style);
        let attrs = Attrs::new()
            .family(family_from_name(&families[0]))
            .weight(Weight(weight.clamp(1.0, 1000.0) as u16))
            .style(style)
            .stretch(stretch_from_percent(stretch))
            .letter_spacing(letter_spacing_em)
            .font_features(parse_font_features(&features));
        let align = align_from_u32(input.text_align, max_width.is_some());
        set_text_with_fallbacks(
            &mut buffer,
            font_system,
            text,
            &families,
            &attrs,
            letter_spacing_em,
            word_spacing_em,
            align,
        );
    }
    buffer.shape_until_scroll(font_system, false);
    buffer
}

fn first_visual_line_end(
    font_system: &mut FontSystem,
    input: &CbssCosmicTextMeasureInput,
    paragraph: &str,
    available_width: Option<f32>,
) -> usize {
    if paragraph.is_empty() || input.wrap == 1 || available_width.is_none() {
        return paragraph.len();
    }
    let probe = prepare_buffer(font_system, input, paragraph, available_width, input.wrap);
    let mut runs = probe.layout_runs();
    let _first = runs.next();
    let Some(second) = runs.next() else {
        return paragraph.len();
    };
    second
        .glyphs
        .first()
        .map(|glyph| glyph.start.min(paragraph.len()))
        .unwrap_or(paragraph.len())
}

fn prepare_layout(
    font_system: &mut FontSystem,
    input: &CbssCosmicTextMeasureInput,
) -> PreparedLayout {
    let source_text = cstr_or_empty(input.text);
    let line_height = line_height_from_input(input);
    let maximum_width = if input.has_max_width != 0 {
        Some(input.max_width.max(0.0))
    } else {
        None
    };
    let indent = if input.text_indent.is_finite() {
        input.text_indent
    } else {
        0.0
    };

    if indent == 0.0 {
        return PreparedLayout {
            segments: vec![PreparedSegment {
                buffer: prepare_buffer(font_system, input, &source_text, maximum_width, input.wrap),
                text: source_text.clone(),
                source_start: 0,
                x_offset: 0.0,
                y_offset: 0.0,
            }],
            source_text,
            line_height,
        };
    }

    let explicit_end = source_text.find('\n').unwrap_or(source_text.len());
    let first_available = maximum_width.map(|width| (width - indent).max(0.0));
    let first_end = first_visual_line_end(
        font_system,
        input,
        &source_text[..explicit_end],
        first_available,
    );
    let mut remainder_start = first_end;
    if first_end == explicit_end && source_text.as_bytes().get(first_end) == Some(&b'\n') {
        remainder_start += 1;
    }

    let first_text = source_text[..first_end].to_string();
    let mut segments = vec![PreparedSegment {
        buffer: prepare_buffer(font_system, input, &first_text, first_available, 1),
        text: first_text,
        source_start: 0,
        x_offset: indent,
        y_offset: 0.0,
    }];
    if remainder_start < source_text.len() || source_text.ends_with('\n') {
        let remainder = source_text[remainder_start..].to_string();
        segments.push(PreparedSegment {
            buffer: prepare_buffer(font_system, input, &remainder, maximum_width, input.wrap),
            text: remainder,
            source_start: remainder_start,
            x_offset: 0.0,
            y_offset: line_height,
        });
    }

    PreparedLayout {
        source_text,
        segments,
        line_height,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn baseline_test_input(font_size: f32) -> CbssCosmicTextMeasureInput {
        CbssCosmicTextMeasureInput {
            text: ptr::null(),
            family_csv: ptr::null(),
            font_features: ptr::null(),
            font_variations: ptr::null(),
            font_size,
            line_height: font_size * 1.2,
            max_width: 0.0,
            has_max_width: 0,
            font_weight: 400.0,
            font_style: 0,
            font_stretch: 100.0,
            letter_spacing: 0.0,
            word_spacing: 0.0,
            wrap: 0,
            text_indent: 0.0,
            text_align: 0,
        }
    }

    #[test]
    fn overlapping_glyph_pixels_are_composited_instead_of_erased() {
        let mut opaque = [255, 255, 255, 255];
        composite_rgba(&mut opaque, [255, 255, 255, 48]);
        assert_eq!(opaque, [255, 255, 255, 255]);

        let mut antialiased = [255, 255, 255, 128];
        composite_rgba(&mut antialiased, [255, 255, 255, 128]);
        assert_eq!(antialiased, [255, 255, 255, 192]);
    }

    #[test]
    fn family_csv_keeps_order_and_removes_duplicates() {
        assert_eq!(
            parse_families("Inter, 'Noto Sans JP', Inter, sans-serif"),
            vec!["Inter", "Noto Sans JP", "sans-serif"]
        );
    }

    #[test]
    fn empty_family_csv_uses_sans_serif() {
        assert_eq!(parse_families(" , "), vec!["sans-serif"]);
    }

    #[test]
    fn hermetic_engine_starts_without_system_faces() {
        let engine = cbss_cosmic_text_engine_new(0);
        assert!(!engine.is_null());
        unsafe {
            assert_eq!((*engine).font_system.db().len(), 0);
            cbss_cosmic_text_engine_free(engine);
        }
    }

    #[test]
    fn baseline_metrics_reject_null_ffi_arguments() {
        let engine = cbss_cosmic_text_engine_new(0);
        let input = baseline_test_input(20.0);
        let mut output = CbssCosmicTextBaselineMetricsResult {
            ascent: 0.0,
            descent: 0.0,
            ok: 0,
        };
        unsafe {
            assert_eq!(
                cbss_cosmic_text_baseline_metrics(engine, ptr::null(), &mut output),
                0
            );
            assert_eq!(
                cbss_cosmic_text_baseline_metrics(engine, &input, ptr::null_mut()),
                0
            );
            assert_eq!(
                cbss_cosmic_text_baseline_metrics(ptr::null_mut(), &input, &mut output),
                0
            );
            cbss_cosmic_text_engine_free(engine);
        }
    }

    #[test]
    fn baseline_metrics_use_a_deterministic_fallback_without_fonts() {
        let engine = cbss_cosmic_text_engine_new(0);
        let input = baseline_test_input(20.0);
        let mut output = CbssCosmicTextBaselineMetricsResult {
            ascent: 0.0,
            descent: 0.0,
            ok: 0,
        };
        unsafe {
            assert_eq!(
                cbss_cosmic_text_baseline_metrics(engine, &input, &mut output),
                1
            );
            assert_eq!(output.ok, 1);
            assert_eq!(output.ascent, 16.0);
            assert_eq!(output.descent, 4.0);
            cbss_cosmic_text_engine_free(engine);
        }
    }

    #[test]
    fn bitmap_size_accepts_the_limit_and_rejects_larger_images() {
        assert_eq!(checked_bitmap_len(4096, 4096), Some(64 * 1024 * 1024));
        assert_eq!(checked_bitmap_len(4097, 4096), None);
        assert_eq!(checked_bitmap_len(u32::MAX, u32::MAX), None);
    }
}

fn flat_to_cursor(text: &str, byte_index: usize) -> Cursor {
    let target = byte_index.min(text.len());
    let mut line = 0usize;
    let mut line_start = 0usize;
    for (index, ch) in text.char_indices() {
        if index >= target {
            break;
        }
        if ch == '\n' {
            line += 1;
            line_start = index + ch.len_utf8();
        }
    }
    Cursor::new(line, target.saturating_sub(line_start))
}

fn cursor_to_flat(text: &str, cursor: Cursor) -> usize {
    let mut line = 0usize;
    let mut line_start = 0usize;
    for (index, ch) in text.char_indices() {
        if ch == '\n' {
            if line == cursor.line {
                return (line_start + cursor.index).min(index);
            }
            line += 1;
            line_start = index + ch.len_utf8();
        }
    }
    if line == cursor.line {
        (line_start + cursor.index).min(text.len())
    } else {
        text.len()
    }
}

fn collect_caret_samples(
    buffer: &Buffer,
    text: &str,
    line_height: f32,
) -> Vec<CbssCosmicTextCaretSample> {
    let mut samples = Vec::new();
    let mut line_starts = vec![0usize];
    for (index, ch) in text.char_indices() {
        if ch == '\n' {
            line_starts.push(index + ch.len_utf8());
        }
    }

    for run in buffer.layout_runs() {
        let line_start = line_starts.get(run.line_i).copied().unwrap_or(text.len());
        if run.glyphs.is_empty() {
            samples.push(CbssCosmicTextCaretSample {
                x: 0.0,
                y: run.line_top,
                height: line_height,
                byte_index: line_start.min(text.len()),
            });
            continue;
        }
        for glyph in run.glyphs {
            let cluster = &run.text[glyph.start..glyph.end];
            let total = cluster.grapheme_indices(true).count().max(1);
            let step = glyph.w / total as f32;
            let mut x = glyph.x;
            for (offset, grapheme) in cluster.grapheme_indices(true) {
                let start = line_start + glyph.start + offset;
                let end = start + grapheme.len();
                if glyph.level.is_rtl() {
                    samples.push(CbssCosmicTextCaretSample {
                        x: x + step,
                        y: run.line_top,
                        height: line_height,
                        byte_index: start.min(text.len()),
                    });
                    samples.push(CbssCosmicTextCaretSample {
                        x,
                        y: run.line_top,
                        height: line_height,
                        byte_index: end.min(text.len()),
                    });
                } else {
                    samples.push(CbssCosmicTextCaretSample {
                        x,
                        y: run.line_top,
                        height: line_height,
                        byte_index: start.min(text.len()),
                    });
                    samples.push(CbssCosmicTextCaretSample {
                        x: x + step,
                        y: run.line_top,
                        height: line_height,
                        byte_index: end.min(text.len()),
                    });
                }
                x += step;
            }
        }
    }
    // A trailing newline owns an empty final line; if layout produced no run
    // for it, synthesize the caret so end-of-text queries land below the last
    // glyph instead of at the origin.
    if text.ends_with('\n') && !samples.iter().any(|sample| sample.byte_index >= text.len()) {
        let bottom = samples
            .iter()
            .map(|sample| sample.y + sample.height)
            .fold(0.0f32, f32::max);
        samples.push(CbssCosmicTextCaretSample {
            x: 0.0,
            y: bottom,
            height: line_height,
            byte_index: text.len(),
        });
    }
    if samples.is_empty() {
        samples.push(CbssCosmicTextCaretSample {
            x: 0.0,
            y: 0.0,
            height: line_height,
            byte_index: 0,
        });
    }
    samples.sort_by(|a, b| {
        a.byte_index
            .cmp(&b.byte_index)
            .then_with(|| a.y.total_cmp(&b.y))
            .then_with(|| a.x.total_cmp(&b.x))
    });
    samples.dedup_by(|a, b| a.byte_index == b.byte_index && (a.y - b.y).abs() < 0.01);
    samples
}

fn collect_layout_caret_samples(layout: &PreparedLayout) -> Vec<CbssCosmicTextCaretSample> {
    let mut samples = Vec::new();
    for segment in &layout.segments {
        for mut sample in collect_caret_samples(&segment.buffer, &segment.text, layout.line_height)
        {
            sample.x += segment.x_offset;
            sample.y += segment.y_offset;
            sample.byte_index =
                (segment.source_start + sample.byte_index).min(layout.source_text.len());
            samples.push(sample);
        }
    }
    samples.sort_by(|a, b| {
        a.byte_index
            .cmp(&b.byte_index)
            .then_with(|| a.y.total_cmp(&b.y))
            .then_with(|| a.x.total_cmp(&b.x))
    });
    samples.dedup_by(|a, b| {
        a.byte_index == b.byte_index && (a.y - b.y).abs() < 0.01 && (a.x - b.x).abs() < 0.01
    });
    samples
}

fn segment_for_source_index(layout: &PreparedLayout, byte_index: usize) -> usize {
    let clamped = byte_index.min(layout.source_text.len());
    let mut selected = 0;
    for (index, segment) in layout.segments.iter().enumerate() {
        if segment.source_start <= clamped {
            selected = index;
        } else {
            break;
        }
    }
    selected
}

fn segment_for_y(layout: &PreparedLayout, y: f32) -> usize {
    let mut selected = 0;
    for (index, segment) in layout.segments.iter().enumerate() {
        if segment.y_offset <= y {
            selected = index;
        } else {
            break;
        }
    }
    selected
}

fn caret_sample_position(
    samples: &[CbssCosmicTextCaretSample],
    byte_index: usize,
) -> Option<(f32, f32)> {
    let mut best: Option<&CbssCosmicTextCaretSample> = None;
    for sample in samples {
        if sample.byte_index <= byte_index {
            best = Some(sample);
        } else {
            break;
        }
    }
    best.or_else(|| samples.first()).map(|s| (s.x, s.y))
}

fn line_height_from_input(input: &CbssCosmicTextMeasureInput) -> f32 {
    let font_size = if input.font_size > 0.0 {
        input.font_size
    } else {
        16.0
    };
    if input.line_height > 0.0 {
        input.line_height
    } else {
        font_size * 1.2
    }
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_caret_position(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    query: *const CbssCosmicTextCaretQuery,
    output: *mut CbssCosmicTextCaretResult,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || input.is_null() || query.is_null() || output.is_null() {
            return 0;
        }
        let input = &*input;
        let query = &*query;
        let line_height = line_height_from_input(input);
        let CbssCosmicTextEngine {
            font_system,
            shape_cache,
            shape_cache_clock,
            ..
        } = &mut *engine;
        let layout = shaped_cache_entry(font_system, shape_cache, shape_cache_clock, input);
        let source_index = query.byte_index.min(layout.source_text.len());
        let segment_index = segment_for_source_index(layout, source_index);
        let segment = &layout.segments[segment_index];
        let local_index = source_index
            .saturating_sub(segment.source_start)
            .min(segment.text.len());
        let cursor = flat_to_cursor(&segment.text, local_index);
        // `cursor_position` fails for cursors layout has no run/glyph for (for
        // example the empty line a trailing newline owns). Fall back to the
        // caret-layout samples so caret queries agree with hit testing.
        let position = segment.buffer.cursor_position(&cursor).or_else(|| {
            let samples = collect_caret_samples(&segment.buffer, &segment.text, line_height);
            caret_sample_position(&samples, local_index)
        });
        let (x, y) = position.unwrap_or((0.0, 0.0));
        ptr::write(
            output,
            CbssCosmicTextCaretResult {
                x: x + segment.x_offset,
                y: y + segment.y_offset,
                height: line_height,
                byte_index: source_index,
                ok: 1,
            },
        );
        1
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_caret_layout(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    output: *mut CbssCosmicTextCaretLayoutResult,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || input.is_null() || output.is_null() {
            return 0;
        }
        let input = &*input;
        let CbssCosmicTextEngine {
            font_system,
            shape_cache,
            shape_cache_clock,
            ..
        } = &mut *engine;
        let layout = shaped_cache_entry(font_system, shape_cache, shape_cache_clock, input);
        let samples = collect_layout_caret_samples(layout);

        let len = samples.len();
        let mut boxed = samples.into_boxed_slice();
        let ptr = boxed.as_mut_ptr();
        std::mem::forget(boxed);
        ptr::write(
            output,
            CbssCosmicTextCaretLayoutResult {
                len,
                samples: ptr,
                ok: 1,
            },
        );
        1
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_caret_layout_free(
    samples: *mut CbssCosmicTextCaretSample,
    len: usize,
) {
    if !samples.is_null() {
        drop(Vec::from_raw_parts(samples, len, len));
    }
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_hit_test(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    query: *const CbssCosmicTextPointQuery,
    output: *mut CbssCosmicTextCaretResult,
) -> u8 {
    ffi_guard!(0, {
        if engine.is_null() || input.is_null() || query.is_null() || output.is_null() {
            return 0;
        }
        let input = &*input;
        let query = &*query;
        let line_height = line_height_from_input(input);
        let CbssCosmicTextEngine {
            font_system,
            shape_cache,
            shape_cache_clock,
            ..
        } = &mut *engine;
        let layout = shaped_cache_entry(font_system, shape_cache, shape_cache_clock, input);
        let segment_index = segment_for_y(layout, query.y);
        let segment = &layout.segments[segment_index];
        let local_x = query.x - segment.x_offset;
        let local_y = query.y - segment.y_offset;
        let cursor = segment
            .buffer
            .hit(local_x, local_y)
            .unwrap_or_else(|| flat_to_cursor(&segment.text, segment.text.len()));
        let local_byte_index = cursor_to_flat(&segment.text, cursor);
        let byte_index = (segment.source_start + local_byte_index).min(layout.source_text.len());
        let (x, y) = segment
            .buffer
            .cursor_position(&cursor)
            .or_else(|| {
                let samples = collect_caret_samples(&segment.buffer, &segment.text, line_height);
                caret_sample_position(&samples, local_byte_index)
            })
            .unwrap_or((local_x.max(0.0), 0.0));
        ptr::write(
            output,
            CbssCosmicTextCaretResult {
                x: x + segment.x_offset,
                y: y + segment.y_offset,
                height: line_height,
                byte_index,
                ok: 1,
            },
        );
        1
    })
}

const MAX_TEXT_BITMAP_BYTES: usize = 64 * 1024 * 1024;

fn checked_bitmap_len(width: u32, height: u32) -> Option<usize> {
    (width as usize)
        .checked_mul(height as usize)
        .and_then(|value| value.checked_mul(4))
        .filter(|value| *value <= MAX_TEXT_BITMAP_BYTES)
}

fn composite_rgba(dst: &mut [u8], src: [u8; 4]) {
    let src_alpha = u32::from(src[3]);
    if src_alpha == 0 {
        return;
    }
    let dst_alpha = u32::from(dst[3]);
    let inverse_src_alpha = 255 - src_alpha;
    let alpha_numerator = src_alpha * 255 + dst_alpha * inverse_src_alpha;
    if alpha_numerator == 0 {
        return;
    }

    for channel in 0..3 {
        let color_numerator = u32::from(src[channel]) * src_alpha * 255
            + u32::from(dst[channel]) * dst_alpha * inverse_src_alpha;
        dst[channel] = ((color_numerator + alpha_numerator / 2) / alpha_numerator) as u8;
    }
    dst[3] = ((alpha_numerator + 127) / 255).min(255) as u8;
}

unsafe fn render_bitmap_impl(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    output: *mut CbssCosmicTextBitmapResult,
    region: Option<(f32, f32)>,
) -> u8 {
    if engine.is_null() || input.is_null() || output.is_null() {
        return 0;
    }

    let input = &*input;
    let CbssCosmicTextEngine {
        font_system,
        swash_cache,
        shape_cache,
        shape_cache_clock,
    } = &mut *engine;
    let layout = shaped_cache_entry(font_system, shape_cache, shape_cache_clock, input);
    if layout.source_text.is_empty() {
        ptr::write(
            output,
            CbssCosmicTextBitmapResult {
                width: 0,
                height: 0,
                offset_x: 0,
                offset_y: 0,
                len: 0,
                pixels: ptr::null_mut(),
                ok: 1,
            },
        );
        return 1;
    }

    let mut spans = Vec::<DrawSpan>::new();
    for segment in &mut layout.segments {
        segment.buffer.draw(
            font_system,
            swash_cache,
            cosmic_text::Color::rgba(255, 255, 255, 255),
            |x, y, w, h, color| {
                let shifted_x = x.saturating_add(segment.x_offset.round() as i32);
                let shifted_y = y.saturating_add(segment.y_offset.round() as i32);
                let intersects_region = region.map_or(true, |(top, height)| {
                    let bottom = top + height.max(0.0);
                    (shifted_y as f32) + (h as f32) > top && (shifted_y as f32) < bottom
                });
                if w > 0 && h > 0 && intersects_region {
                    spans.push(DrawSpan {
                        x: shifted_x,
                        y: shifted_y,
                        w,
                        h,
                        color,
                    });
                }
            },
        );
    }

    if spans.is_empty() {
        ptr::write(
            output,
            CbssCosmicTextBitmapResult {
                width: 0,
                height: 0,
                offset_x: 0,
                offset_y: 0,
                len: 0,
                pixels: ptr::null_mut(),
                ok: 1,
            },
        );
        return 1;
    }

    let min_x = spans.iter().map(|span| span.x).min().unwrap_or(0);
    let min_y = spans.iter().map(|span| span.y).min().unwrap_or(0);
    let max_x = spans
        .iter()
        .map(|span| span.x.saturating_add(span.w as i32))
        .max()
        .unwrap_or(0);
    let max_y = spans
        .iter()
        .map(|span| span.y.saturating_add(span.h as i32))
        .max()
        .unwrap_or(0);
    let width = max_x.saturating_sub(min_x).max(0) as u32;
    let height = max_y.saturating_sub(min_y).max(0) as u32;
    let len = match checked_bitmap_len(width, height) {
        Some(value) => value,
        _ => return 0,
    };
    let mut pixels = Vec::<u8>::new();
    if pixels.try_reserve_exact(len).is_err() {
        return 0;
    }
    pixels.resize(len, 0);

    for span in spans {
        let rgba = span.color.as_rgba();
        for py in 0..span.h {
            for px in 0..span.w {
                let tx = (span.x - min_x) as u32 + px;
                let ty = (span.y - min_y) as u32 + py;
                let index = (ty as usize * width as usize + tx as usize) * 4;
                composite_rgba(&mut pixels[index..index + 4], rgba);
            }
        }
    }

    let mut boxed = pixels.into_boxed_slice();
    let pixels_ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);

    ptr::write(
        output,
        CbssCosmicTextBitmapResult {
            width,
            height,
            offset_x: min_x,
            offset_y: min_y,
            len,
            pixels: pixels_ptr,
            ok: 1,
        },
    );
    1
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_render_bitmap(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    output: *mut CbssCosmicTextBitmapResult,
) -> u8 {
    ffi_guard!(0, { render_bitmap_impl(engine, input, output, None) })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_render_bitmap_region(
    engine: *mut CbssCosmicTextEngine,
    input: *const CbssCosmicTextMeasureInput,
    region_top: c_float,
    region_height: c_float,
    output: *mut CbssCosmicTextBitmapResult,
) -> u8 {
    ffi_guard!(0, {
        render_bitmap_impl(
            engine,
            input,
            output,
            Some((region_top, region_height.max(0.0))),
        )
    })
}

#[no_mangle]
pub unsafe extern "C" fn cbss_cosmic_text_bitmap_free(pixels: *mut u8, len: usize) {
    if !pixels.is_null() && len > 0 {
        drop(Vec::from_raw_parts(pixels, len, len));
    }
}
