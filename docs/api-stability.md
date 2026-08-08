# API Stability And Deprecation

Clay Board Style System is still before Version 1.0. Its Nim API may require
breaking changes while the component, event, data, and rendering contracts are
being completed. Pre-1.0 does not mean that existing code is changed without a
migration path when one can reasonably be provided.

## Product Version Policy

CBSS follows these rules for the Nim-facing package:

- Patch releases do not intentionally break documented public APIs.
- A pre-1.0 minor release may contain a necessary breaking change.
- Prefer an additive replacement when it keeps the API coherent and does not
  preserve an unsafe ownership or behavior contract.
- Once a replacement is complete, update first-party examples and
  documentation before marking the old API deprecated.
- Keep a deprecated API for at least two subsequent minor release lines when
  practical. For example, an API deprecated in Version 0.4 is not normally
  removed before Version 0.6.
- Every removal identifies the replacement and migration steps in the release
  notes. Version 1.0 and later follow ordinary major-version compatibility.

An API is not deprecated merely because a newer API supports more data. The
compact event callback and payload-aware EventView callback, for example,
serve different valid use cases and can coexist.

Security flaws, memory unsafety, data corruption, or an API that cannot be
implemented correctly may require a shorter migration window. Such an
exception must be called out explicitly in the security notice and release
notes rather than being treated as an ordinary refactor.

## Nim Deprecation

Use Nim's standard `deprecated` pragma and name the direct replacement:

```nim
proc oldApi*() {.deprecated: "Use newApi() instead.".} =
  newApi()
```

The old implementation should normally delegate to the maintained path so the
two APIs do not drift. Do not add a second CBSS-specific deprecation annotation.
Tests and examples must use the replacement API unless they specifically test
the migration bridge.

## C ABI Deprecation

The C ABI has its own version number and stronger binary constraints. Product
Version 0.x does not weaken the ABI rule: existing struct layout, enum values,
function signatures, and ownership remain frozen within one C ABI major.

`include/cbss.h` provides `CBSS_DEPRECATED(message)` for functions that have a
complete replacement. It maps to the supported compiler's deprecation
attribute and becomes a no-op on an unknown compiler:

```c
CBSS_DEPRECATED("Use cbss_new_api instead")
CBSS_API CbssStatus cbss_old_api(CbssContext *context);
```

Deprecating a C function does not remove its exported symbol. Removing that
symbol, changing a fixed struct, reassigning an enum value, or changing
ownership requires a new C ABI major. During an ABI-major transition, bindings
must check `cbss_abi_version()` before constructing a context, and release notes
must document source and ownership migration separately.

## Review Checklist

Before deprecating or breaking a public API, record:

1. Why the old contract cannot remain the preferred API.
2. The exact replacement and a minimal migration example.
3. Whether the change affects Nim source compatibility, C source
   compatibility, C binary compatibility, serialized data, or ownership.
4. The release where deprecation begins and the earliest planned removal.
5. Tests proving that the compatibility bridge and replacement behave
   consistently during the migration window.
