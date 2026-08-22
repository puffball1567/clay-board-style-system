# Craft Ecosystem

`Craft` is the public umbrella term for reusable work built on Clay Board
Style System. The name follows the project model: CBSS is the board and shared
foundation; independent engineers use that foundation to craft components,
styles, design systems, and complete UI libraries.

This vocabulary describes distribution and composition. It does not add a DOM,
a global selector model, or a second runtime beside CBSS.

## Vocabulary

| Term | Responsibility |
| --- | --- |
| **Craft** | Any reusable CBSS artifact distributed for use by another application or library. |
| **Craft Component** | A retained, reusable UI component with its own structure, required behavior, and component-owned invariants. |
| **Craft Style** | A portable presentation definition that can be loaded and replaced independently of application business logic. |
| **Craft Pack** | A distributable collection of Craft Components, Craft Styles, assets, metadata, and compatibility requirements. |
| **Craft Driver** | The host-language or runtime adapter that loads Craft metadata and Style data, reports diagnostics, and connects them to CBSS. |

Use **Craft Style** in prose, `CraftStyle` in typed APIs, and `craft-style` in
package names or command-line identifiers where kebab case is required.

## Style Boundaries

CBSS keeps two authoring paths because they solve different problems:

- `Style` is ordinary typed host-language data. In Nim it can use functions,
  constants, parameters, dependency injection, and compile-time checks.
- `Craft Style` is an external, portable representation. The same definition
  should resolve to the same supported CBSS semantics through every conforming
  Craft Driver.

A Craft Style is CSS-inspired but is not CSS text, a browser cascade, or a
claim of CSS compatibility. Its eventual syntax may expose CBSS state
conditions, transitions, keyframes, typed values, and CBSS-specific visual
features. Portable files must not contain arbitrary native callbacks or
business logic. Applications attach `onClick`, `onChange`, Commands, and other
behavior through their host language.

## Component Contracts

Craft Components expose stable public style slots such as a component root,
label, icon, focus ring, selection marker, or validation message. A Craft Style
targets those declared slots instead of depending on a DOM tree, private node
order, or application-wide class names.

Component-owned Style remains the highest-precedence layer when both sides set
the same property. Component authors should reserve that layer for structure,
behavior, accessibility, and other declared invariants. Visual defaults should
be placed in replaceable public slots so a Craft Pack can provide a genuinely
different design without copying the component implementation.

Replacing a Craft Style or Craft Pack must:

- preserve mounted components, NodeIds, state, event handlers, focus, and
  accessibility identity;
- replace only declared public style and asset slots;
- invalidate only affected style, layout, paint, text, or hit domains; and
- apply atomically, leaving the previous Craft active if parsing, capability,
  or asset validation fails.

Version 0.6 implements this contract for Craft Style through
`CBSSComponent.craftName`, `publicStyleSlot`, and
`UiRoot.replaceCraftStyle`. Slot identity is independent of `id`, `code`,
groups, and node order. Replacement Style is kept below component-owned Style
in the cascade, and failed parsing or Slot validation does not mutate the active
Style.

## Distribution And Drivers

Nim modules and Nimble packages remain the reference native Craft authoring
path. A component package may privately bind another native library, but CBSS
does not require a dynamic foreign-plugin loader. Version 0.6 also makes the
component, Style, event, state, and lifecycle concepts available through
high-level host-language Craft Drivers, so using CBSS from another language is
not reduced to writing raw C ABI calls.

Craft Style is the language-neutral part of the model. Version 0.6 defines the
first versioned manifest and serialized Style representation so Nim, C, C++,
Rust, Zig, C#, Odin, and other C-interoperable hosts can load the same
presentation asset through a Craft Driver. Drivers adapt language ergonomics;
they must not reinterpret Style semantics or define backend-specific Style
behavior. Pixel output may still vary within documented platform, font, and
renderer contracts.

The Version 1 JSON exchange representation, typed values, parser diagnostics,
normalization, and safety limits are defined in
[Craft Style Exchange Format](craft-style-format.md). JSON is the stable Driver
boundary, not a commitment to the eventual human-oriented authoring syntax.

### High-Level Driver Contract

The C ABI is the shared engine protocol below a Craft Driver. Ordinary Driver
users should not need to manage Nim ARC/ORC, opaque node handles, explicit
parent handles, callback userdata, dirty domains, or manual status-code
translation.

Every conforming Driver provides language-appropriate access to:

- nested UI construction and Craft Component composition;
- typed Style values, Craft Style and Craft Pack loading, and public Style
  Slots;
- standard events, retained state updates, navigation, validation, Commands,
  and Cue triggers supported by its declared capability profile;
- deterministic lifetime, callback removal, cancellation, and UI-thread
  rules; and
- structured diagnostics and capability/version negotiation before a partial
  Craft is mounted.

Driver syntax does not need to be textually identical. Its observable nesting,
Style precedence, event order, focus, state retention, invalidation, error
handling, and resource lifetime must conform to shared fixtures. The canonical
metadata and tests are versioned independently from hand-written ergonomic
wrappers so another language can be added without modifying the CBSS engine.

Rust and C++ are the Version 0.6 reference Drivers because they exercise
different ownership and authoring idioms. Additional C-interoperable languages
can build on the same generated low-level bindings and conformance suite.

The reference Drivers expose `CraftComponent` as a stable retained root with
component-scoped construction and public Style Slots. Construction failure is
atomic: C++ exceptions and Rust `Err`/panic paths remove the incomplete
subtree. Retained Text, Image, attribute, group, and state mutations preserve
Node identity and event registrations. Host-language State or Store
implementations connect to those mutations; a Driver does not impose a second
virtual DOM or require one shared state-library implementation in every
language.

The Version 0.6 Craft Pack manifest foundation declares:

- its identity, version, CBSS compatibility range, and required capabilities;
- exported components and public style slots;
- included Craft Styles, fonts, images, shaders, and other bounded assets;
- optional feature profiles and platform limitations; and
- deterministic integrity and diagnostics metadata.

Parsing, validation, and compiled Style caching belong to CBSS and its drivers,
not to every application. Unused optional Craft capabilities must remain
eligible for compile-time exclusion from normal application artifacts.

The implemented Version 1 manifest parser, compatibility checks, security
limits, integrity-metadata boundary, and loading APIs are specified in
[Craft Pack Manifest Format](craft-pack-format.md).

## Non-Goals

- Serializing application business logic or arbitrary native procedures.
- Reintroducing DOM identity, descendant selectors, or structural selectors.
- Making a Craft Pack a second CBSS runtime or allowing it to vendor a private,
  incompatible runtime copy.
- Requiring dynamic loading when normal Nim imports and static composition are
  sufficient.
- Requiring users of a high-level Craft Driver to author raw C ABI glue.
- Treating `Craft` as a synonym for a finished widget toolkit. It is the
  ecosystem vocabulary for work built on the CBSS foundation.
