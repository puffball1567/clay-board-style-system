# Accessibility Architecture

CBSS owns accessibility semantics and behavior intrinsic to UI elements. It
does not own application business logic.

For example, a Button owns focus, keyboard activation, disabled behavior, and
the accessible `activate` action. The callback that saves a document, calls a
backend, or changes application data remains application code. A disclosure
owns arrow-key expansion because that is UI behavior.

## Layers

Accessibility support is split into independent layers:

1. `runtime/accessibility.nim` resolves the retained semantic tree. It exposes
   typed roles, names, descriptions, values, states, relations, and optional
   layout bounds.
2. `backends/atspi/adapter.nim` maps that tree to stable AT-SPI object paths,
   roles, state, interfaces, actions, and snapshot changes.
3. A Linux transport publishes the snapshot through the accessibility D-Bus.
   This transport is not implemented yet. UIA and NSAccessibility transports
   will be separate modules over the same semantic tree.

The AT-SPI adapter uses the specification root path
`/org/a11y/atspi/accessible/root`. Node paths are generated only from internal
`NodeId` values. User-provided IDs and codes may become `AccessibleId` values,
but never D-Bus object paths.

## Capability Advertising

An adapter must not advertise an interface before all methods required by that
interface have consumers. The current AT-SPI adapter advertises:

- `Accessible` for semantic objects;
- `Application` for the synthetic application root;
- `Component` where layout bounds are available; and
- `Action` where CBSS can route `activate` into the existing event registry.

Text, EditableText, and Value data already exist in the neutral snapshot, but
their AT-SPI interfaces remain unadvertised until their complete operation
surfaces are implemented. Disabled or insensitive nodes reject actions.

## Focus And Modal Behavior

Focus is a root-level mechanism shared by all controls. A modal Dialog installs
a focus scope, traps Tab and Shift-Tab traversal, blocks background pointer
activation, and restores the opening focus when closed. Event handlers queue a
focus request because they do not own `InteractionState`; hosts call
`reconcileFocus` after each event batch. The SDL3 demo and headless test driver
already perform this reconciliation.

## Security Boundary

Platform transports must:

- publish only to the platform accessibility channel;
- validate object paths and action names against the current snapshot;
- dispatch only explicitly advertised UI actions;
- avoid evaluating user strings or invoking external commands; and
- commit a new published snapshot only after transport success.

The platform-neutral adapter follows these rules and has no D-Bus, filesystem,
process, or network access of its own.
