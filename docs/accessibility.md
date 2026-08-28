# Accessibility Architecture

CBSS owns accessibility semantics and behavior intrinsic to UI elements. It
does not own application business logic.

For example, a Button owns focus, keyboard activation, disabled behavior, and
the accessible `activate` action. The callback that saves a document, calls a
backend, or changes application data remains application code. A disclosure
owns arrow-key expansion because that is UI behavior.

A Link similarly owns focusability, Enter-key activation, disabled behavior,
and its accessible `activate` action. Its destination is a typed application
value; accessibility activation uses the same event path as pointer input and
does not require a browser URL.

## Layers

Accessibility support is split into independent layers:

1. `runtime/accessibility.nim` resolves the retained semantic tree. It exposes
   typed roles, names, descriptions, values, states, relations, logical set
   position/size, and optional layout bounds.
2. `backends/atspi/adapter.nim` maps that tree to stable AT-SPI object paths,
   roles, state, interfaces, actions, and snapshot changes.
3. `backends/atspi/linux_dbus.nim` publishes the snapshot through the Linux
   accessibility D-Bus when compiled with `-d:cbssLinuxAtspi`. UIA and
   NSAccessibility transports remain separate future modules over the same
   semantic tree.

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

Retained navigation screens use inherited runtime `inert` state while
inactive. Their semantic nodes remain retained with stable IDs, but are marked
hidden, cannot receive accessibility actions through the UI event path, and do
not participate in focus traversal. Reactivation restores semantics without
reconstructing the screen subtree.

## Virtual Collections

Viewport virtualization must not make a bounded materialized window appear to
be the complete collection. `setAccessibleSetPosition` assigns a one-based
`positionInSet` and optional logical `setSize` to an item. `VirtualNodePool`
sets both values automatically from each item geometry and the range plan's
logical item count, including when a retained stable key moves after data
reordering.

These values describe an item; they do not infer whether the author intended a
List, Grid, Tree, or another collection. Components must still assign the
appropriate accessible role. A position must be positive, a set size cannot be
negative, and a known position cannot exceed a known size. Invalid combinations
are rejected without changing the previous semantic value.

The platform-neutral AT-SPI snapshot carries the same fields and emits an
`ackSetPosition` change when either value changes. The C ABI adds a separate
`CbssAccessibleSetPosition` structure and setter/getter pair so the fixed-size
`CbssAccessibility` ABI remains unchanged.

## Security Boundary

Platform transports must:

- publish only to the platform accessibility channel;
- validate object paths and action names against the current snapshot;
- dispatch only explicitly advertised UI actions;
- avoid evaluating user strings or invoking external commands; and
- commit a new published snapshot only after transport success.

The platform-neutral adapter follows these rules and has no D-Bus, filesystem,
process, or network access of its own.

## Linux AT-SPI Transport

The Linux transport dynamically loads GLib, GObject, and GIO only in builds
compiled with `-d:cbssLinuxAtspi`. Ordinary builds and non-Linux builds do not
import or link this module. The host creates one transport for its `UiRoot`,
publishes snapshots through the neutral adapter, dispatches its GLib context
from the UI thread, and closes it before disposing the root:

```nim
let linuxAtspi = initLinuxAtspiTransport(ui)
if linuxAtspi.connected():
  let accessibility = initAtspiAdapter(linuxAtspi.atspiTransport())
  discard accessibility.refresh(ui, layout, "Application name")

# Integrate this with the host event loop and after accessibility mutations.
discard linuxAtspi.poll()

linuxAtspi.close()
```

Publishing rejects malformed, duplicate, or disconnected object paths without
replacing the last valid snapshot. D-Bus callbacks validate every path,
interface, method, property, and action against that snapshot. Callbacks run on
the same explicitly polled GLib context as the UI thread; they do not mutate the
retained tree from a background D-Bus thread.

Linux CI starts an isolated accessibility bus and uses an external `gdbus`
client to inspect Application, Accessible, Action, and Component behavior under
ARC and ORC. The same lifecycle runs under Valgrind. This protocol integration
does not replace manual validation with Orca and other assistive technologies.
