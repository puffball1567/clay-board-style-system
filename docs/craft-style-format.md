# Craft Style Exchange Format

Craft Style is the portable presentation boundary shared by CBSS and conforming
Craft Drivers. Version 1 uses strict JSON as its language-neutral exchange
format. It is CSS-inspired, but it is not CSS text, a CSS parser, a DOM
stylesheet, or a claim of CSS compatibility.

The JSON representation is deliberately separate from a future human-oriented
authoring syntax. A more concise syntax may compile into this format without
changing the runtime contract used by Nim, C++, Rust, or later Drivers.

## Document

Every document has exactly four top-level fields:

```json
{
  "format": "cbss-craft-style",
  "version": 1,
  "name": "midnight-controls",
  "rules": []
}
```

- `format` must be `cbss-craft-style`.
- `version` must be an integer supported by the runtime.
- `name` is a non-empty diagnostic and distribution name.
- `rules` is an ordered array. Its order participates in Style precedence.

Unknown and duplicate fields are errors rather than silently ignored
extensions. Duplicate detection happens before a JSON object is materialized,
so Drivers cannot diverge through first-key-wins or last-key-wins parser
behavior. New format versions must negotiate compatibility explicitly.

## Rules And Selectors

A rule contains a selector, an optional integer priority, and one or more
declarations:

```json
{
  "selector": {
    "element": "box",
    "id": "save-panel",
    "code": "primary-action",
    "groups": ["surface", "interactive"],
    "attributes": {"data-density": "compact", "aria-busy": null},
    "states": ["hover", "focus-visible"]
  },
  "priority": 10,
  "declarations": [
    {
      "property": "padding",
      "value": {"type": "length", "unit": "rem", "value": 1}
    }
  ]
}
```

Supported elements are `box`, `text`, and `image`. Attribute strings require
an exact value; `null` means that the attribute only needs to exist. Supported
states are `hover`, `active`, `focus`, `focus-visible`, `disabled`, `checked`,
`selected`, `open`, and `invalid`.

Craft Style selectors target public component slots and stable application
identifiers. They do not introduce descendant selectors, structural selectors,
or implicit access to private component structure.

## Declarations

The default operation is `overwrite`. `relative` also requires a value.
`inherit`, `initial`, and `unset` must omit `value`:

```json
{"property":"opacity","value":{"type":"number","value":0.8}}
{"property":"letter-spacing","operation":"relative","value":{"type":"length","unit":"em","value":0.05}}
{"property":"color","operation":"inherit"}
```

Property names must exist in the runtime property registry. The parser validates
the portable structure and compiles it into a `StyleSheet`; property consumers
remain authoritative for property-specific keyword and value semantics during
Style resolution.

## Typed Values

Every serialized value has an explicit `type`.

| Type | Required data |
| --- | --- |
| `length` | `unit`, and `value` for numeric units |
| `number` | finite numeric `value` |
| `keyword` | string `value` |
| `color` | CSS-inspired color string or `color-mix(...)` |
| `color-pair` | `first` and `second` color strings |
| `border` | optional `width`, `style`, and `color` |
| `shadow` | `offset-x`, `offset-y`; optional `blur`, `spread`, and `color` |
| `linear-gradient` | `angle`, two or more ordered `stops`; optional `space` |
| `transform` | ordered `translate`, `scale`, and `rotate` operations |

Numeric length units are `px`, `percent`, `em`, `rem`, `fill`, `vw`, `vh`,
`vmin`, `vmax`, `lh`, `rlh`, `ex`, `ch`, `rex`, and `rch`. Keyword-like
length units are `content`, `min-content`, `max-content`, `fit-content`, `auto`,
and `none`; their numeric value must be omitted or zero.

Gradient interpolation spaces are `srgb`, `srgb-linear`, and `oklab`. Stop
offsets are normalized numbers from zero through one. Transform translation
uses typed lengths, scale uses finite numbers, and rotation angles are degrees.

Arbitrary native procedures and `StyleValue` functions cannot be serialized.
Application behavior remains in typed host-language code and is connected
through events, Commands, Cue, and component APIs.

## Diagnostics And Atomicity

`parseCraftStyle` returns a `CraftStyleParseResult` containing structured
diagnostics with a stable code, JSON-style path, and message. A result is usable
only when `isOk` is true. Any diagnostic leaves `value` empty, so callers cannot
accidentally apply a partially parsed Style.

Successfully parsed documents also contain `normalizedJson`. Object keys are
sorted recursively while rule, declaration, gradient-stop, and transform order
is preserved. Drivers can use this representation as deterministic compiled
cache input without losing authored color strings or other exchange data.

The parser bounds source bytes, nesting depth, rules, declarations, selector
items, gradient stops, and transform operations before accepting a document.
The public limit constants are part of the Version 1 runtime contract. Craft
Pack loading must additionally validate capabilities, assets, and integrity
before atomically replacing an active Style.

## Reference Files

- Parser and compiler: `src/clay_board_style_system/craft/style.nim`
- Machine-readable schema: `schema/craft_style_v1.schema.json`
- Conformance fixture: `tests/fixtures/craft_style/reference.json`
- Positive and negative matrix: `tests/craft/test_craft_style.nim`
- Ecosystem and replacement rules: [Craft Ecosystem](craft.md)
