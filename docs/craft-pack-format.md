# Craft Pack Manifest Format

Craft Pack Version 1 is the bounded, language-neutral manifest used to declare
a distributable set of Craft Components, Craft Styles, and assets. It is a
manifest and compatibility contract, not an executable plugin format and not a
second CBSS runtime.

The canonical schema is
[`schema/craft_pack_v1.schema.json`](../schema/craft_pack_v1.schema.json). The
reference fixture is
[`tests/fixtures/craft_pack/reference.json`](../tests/fixtures/craft_pack/reference.json).

## Document Shape

```json
{
  "format": "cbss-craft-pack",
  "version": 1,
  "id": "org.example.dashboard",
  "packVersion": "1.2.0",
  "compatibility": {
    "minimumAbi": 65558,
    "maximumAbi": 65558,
    "minimumDriverContract": 65536,
    "capabilities": [
      {"id": 16, "minimumVersion": 1},
      {"id": 17, "minimumVersion": 1}
    ]
  },
  "components": [
    {"name": "dashboard-card", "slots": ["root", "title", "body"]}
  ],
  "styles": [
    {
      "name": "dashboard-light",
      "path": "styles/dashboard-light.json",
      "sha256": "1111111111111111111111111111111111111111111111111111111111111111"
    }
  ],
  "assets": [
    {
      "id": "dashboard-logo",
      "kind": "image",
      "path": "assets/dashboard-logo.png",
      "mimeType": "image/png",
      "sha256": "2222222222222222222222222222222222222222222222222222222222222222"
    }
  ]
}
```

`format`, `version`, `id`, `packVersion`, `compatibility`, `components`,
`styles`, and `assets` are required. `profiles` and `platforms` are optional.
Unknown fields are rejected so a misspelling cannot silently weaken a declared
contract.

## Compatibility

`minimumAbi` and `minimumDriverContract` are required. `maximumAbi` and
`maximumDriverContract` are optional inclusive upper bounds. Every item in
`capabilities` contains a stable capability id and its minimum version.

CBSS validates this block before replacing an active Pack. A missing capability
or an incompatible version rejects the candidate atomically and leaves the
previous Pack with the same `id` active.

Feature `profiles` describe optional capability sets. They are metadata for a
host or installer to select deliberately; parsing a manifest does not activate
optional GPU, media, or platform features.

## Components And Public Slots

Each component entry declares its stable Craft name and public Style Slot
names. It does not reveal private node order or create global selectors. The
corresponding mounted component must expose those Slots through the public Slot
API before a Craft Style can target them.

## Styles And Assets

Style entries contain a unique name, a normalized relative path, and a
lowercase 64-character SHA-256 value. Asset entries additionally contain a
unique id, one of `font`, `image`, `shader`, or `binary`, an optional MIME type,
and an optional `required` flag that defaults to `true`.

Paths must be relative and normalized. Absolute paths, empty segments, `.`,
`..`, backslashes, drive/URI colons, duplicate paths, and NUL bytes are
rejected. A manifest cannot cause CBSS to read a file, follow a symlink, access
the network, or load native code.

Version 1 validates that SHA-256 metadata is syntactically well formed. The
manifest registry does not open asset paths or claim that asset bytes match the
declared digest. A host-authorized Pack resolver must enforce a Pack root,
prevent traversal and symlink escape, read bounded bytes, verify each digest,
and only then pass validated Style or asset data to the appropriate CBSS API.

## Limits And Diagnostics

The parser bounds source size, JSON depth, UTF-8 string byte size, and every
collection. JSON Schema `maxLength` counts Unicode code points, so bounded
string definitions also publish the authoritative runtime byte cap through
`x-cbss-maxUtf8Bytes`. The parser rejects duplicate JSON object keys before
normal JSON decoding, duplicate identities, malformed types, unsupported
versions, and invalid ranges.

Nim receives typed `CraftPackDiagnostic` values. The C ABI and high-level C++
and Rust Drivers expose a stable diagnostic domain/code pair plus copied path
and message strings. Diagnostic text is intended for people; programs should
branch on the numeric domain and code.

Replacement is atomic. A failed parse, compatibility check, or validation does
not partially register components, styles, or assets.

## Loading APIs

Nim applications use `parseCraftPack`, `CraftPackRegistry.replaceCraftPack`, or
the corresponding `UiRoot` source method. Registration accepts source text so
unvalidated programmatically constructed metadata cannot bypass the manifest
checks. The C ABI accepts an explicit byte pointer
and byte length through `cbss_context_replace_craft_pack_json`; it never assumes
NUL termination and copies the source during the call. C++ and Rust expose
`replaceCraftPack` / `replace_craft_pack` and typed active-Pack queries.

Craft Style loading and public Slot semantics are specified separately in
[Craft Style Exchange Format](craft-style-format.md).
