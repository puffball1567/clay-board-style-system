# Typed Component Authoring

CBSS provides a typed Nim authoring layer for GUI libraries and application
components. It is ordinary Nim: component types, render procedures, event
handlers, and lifecycle methods remain visible to the compiler and language
server. No TSX parser, untyped component macro, virtual DOM, or hidden global
`UiRoot` is involved.

## Basic component

```nim
import clay_board_style_system

type SaveButton* = ref object of CBSSComponent
  label*: string

proc saveButtonStyle(): UiStyle =
  uiStyle([
    decl("width", px(96)),
    decl("height", px(40)),
    decl("background-color", colorValue(rgb(0.10, 0.35, 0.60)))
  ])

proc render(self: SaveButton) =
  proc onSave(event: DispatchResult): bool =
    echo "Saved"
    return true

  ui.box(self, ownedStyle = saveButtonStyle()):
    ui.text(self.label)

  self.onClick = onSave
```

The component type contains only the parameters and state that belong to that
component. Its `render(self)` procedure creates one component root. Passing
`self` to `ui.box()` registers that box as the root, retains the component for
the root's lifetime, and makes later event assignments target that box.

`ui` is available only during a synchronous component render. It resolves to
the current `UiRoot`, supports nested component mounts, and restores the prior
root after a nested render. Using it outside that scope raises
`ComponentContextError` instead of mutating an unrelated root.

## Composition

```nim
type Toolbar* = ref object of CBSSComponent
  saveButton*: SaveButton

proc render(self: Toolbar) =
  ui.box(self, ownedStyle = toolbarStyle()):
    ui.text("Project")
    ui.mount(self.saveButton)

let app = initUiRoot()
app.mount(
  Toolbar(
    saveButton: SaveButton(label: "Save")
  )
)
```

`ui.mount()` returns the same statically typed instance, but callers do not
need to retain that return value. `UiRoot` owns mounted component instances
until their root subtree is disposed. Nested component roots are regular tree
nodes, so parent disposal unmounts children before their parent.

## Style injection

Every `CBSSComponent` has an optional public `style` field for caller-provided
Style DI. The component supplies its own declarations through `ownedStyle`:

```nim
ui.mount(
  SaveButton(
    label: "Save",
    style: uiStyle([
      decl("height", px(48)),
      decl("background-color", colorValue(rgb(0.20, 0.20, 0.20)))
    ])
  )
)
```

CBSS merges the injected style first and `ownedStyle` second. A property that
appears in both is therefore controlled by the component. Properties that the
component does not own remain injectable. Component authors do not need to
write a merge expression in each render procedure.

## Events and lifecycle

Components expose the same standard event-property names as `NodeHandle`,
including `onClick`, `onChange`, `onInput`, `onKeyDown`, pointer, touch, pen,
composition, drag, scroll, and media-related slots. Assignment replaces the
existing user handler for that event slot; it does not add an invisible second
listener.

Events normally stay inside the component that owns the interactive element.
A parent mounts the finished component rather than receiving and forwarding an
event bundle.

Lifecycle hooks are optional methods because they are invoked after the
component has been retained and again through the base component type during
subtree disposal:

```nim
method onMount(self: SaveButton) =
  echo "mounted"

method onUnmount(self: SaveButton) =
  echo "unmounted"
```

`render(self)` is retained initial construction, not a React-style replay
contract. State changes should update stable handles and mark the affected
dirty domains. CBSS does not rebuild every component after an event.

## Failure behavior

Mount is transactional. If `render(self)` or `onMount(self)` raises, CBSS
removes the partially built subtree, unregisters its styles and events,
unmounts any nested components, and restores the prior render context. A
component must declare exactly one root through `ui.box(self, ...)`; missing or
duplicate roots produce `ComponentContextError`.
