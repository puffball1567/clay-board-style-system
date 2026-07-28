# Runtime Linking and Packaging

CBSS keeps application code independent from the way native runtime libraries
are linked and supplied. The Nimble package contains CBSS source code and
native-bridge source code, but no SDL3 or bridge binaries. Applications or
build environments supply those artifacts separately.

Setup writes an application-local `.cbss/link-mode` and, for bundled/custom
setup, `.cbss/runtime-root`. The SDL3 backend reads these files at compile
time. Bundled and custom modes use the same runtime directory layout.

The `.cbss/` directory is intentionally ignored by Git. Two applications using
the same CBSS installation may therefore choose different runtime layouts.

## Bundled Setup

```sh
nimble install clay_box_style_system
cbss_configure bundled /path/to/cbss-runtime
```

Prepare the runtime directory before running setup:

```text
/path/to/cbss-runtime/
  include/
    SDL3/
      SDL.h
  lib/
    libSDL3.a
    libcbss_image_bridge.so
    libcbss_cosmic_text_bridge.so
```

The compiler resolves the SDL3 headers and `libSDL3.a` from that directory and
links SDL3 statically. The image and cosmic-text C ABI bridges remain dynamic
libraries so they can be updated or rebuilt independently.

The executable records two runtime search locations:

1. `$ORIGIN/cbss-libs`, for a relocatable application bundle.
2. The configured runtime directory, for development and controlled builds.

For distribution, place the executable next to a `cbss-libs/` directory:

```text
application
cbss-libs/
  libcbss_image_bridge.so
  libcbss_cosmic_text_bridge.so
```

Both native bridges can be built from the source shipped with CBSS:

```sh
cargo build --locked --release \
  --manifest-path native/image_bridge/Cargo.toml
cargo build --locked --release \
  --manifest-path native/cosmic_text_bridge/Cargo.toml
```

Copy `native/image_bridge/target/release/libcbss_image_bridge.so` and
`native/cosmic_text_bridge/target/release/libcbss_cosmic_text_bridge.so`
into `cbss-libs/` when packaging an application.

## System Dynamic-Link Setup

```sh
nimble install clay_box_style_system
cbss_configure system
```

This mode emits `-lSDL3` and `-lcbss_image_bridge` without a CBSS vendor
search path. The build environment must provide:

- SDL3 headers containing `SDL3/SDL.h`
- A linker-visible `libSDL3`
- A linker-visible `libcbss_image_bridge`
- A loader-visible `libcbss_cosmic_text_bridge`
- Loader-visible copies of all three libraries at runtime

The exact installation mechanism belongs to the application or OS package.
CBSS does not write to `/usr`, `/usr/local`, or another global location.
Unlike bundled mode, SDL3 is dynamically linked in this setup.

## Custom Runtime Prefix

Select a private runtime prefix when an application owns its native SDK:

```sh
nimble install clay_box_style_system
cbss_configure custom /opt/my-runtime /path/to/application
```

The prefix uses the same layout as bundled setup:

```text
/opt/my-runtime/
  include/
    SDL3/
      SDL.h
  lib/
    libSDL3.so
    libcbss_image_bridge.so
    libcbss_cosmic_text_bridge.so
```

The custom mode records the absolute prefix in `.cbss/runtime-root` and links
SDL3 dynamically. Packaged applications should copy the required shared
libraries to `$ORIGIN/cbss-libs`; the absolute prefix is primarily for
controlled SDK or enterprise build environments.

Bundled and custom setup share the same runtime-root layout resolver. The
difference is linkage: bundled setup selects `libSDL3.a`, while custom setup
selects `libSDL3.so`. Neither mode obtains binaries from the CBSS Nimble
package.

## Build-System Override

CI and advanced build systems may bypass setup files:

```sh
nim c -d:cbssSdl3LinkMode=system app.nim

nim c \
  -d:cbssSdl3LinkMode=bundled \
  -d:cbssRuntimeRoot=/opt/my-runtime \
  app.nim

nim c \
  -d:cbssSdl3LinkMode=custom \
  -d:cbssRuntimeRoot=/opt/my-runtime \
  app.nim
```

Accepted modes are `bundled`, `system`, and `custom`. Invalid modes, missing
runtime roots, incomplete layouts, and missing static/dynamic SDL3 libraries
fail at compile time with named diagnostics.

The `cbss_configure` executable is a setup tool installed by Nimble. It is not
linked into applications. In a CBSS source checkout, maintainers may use the
equivalent `nimble setupBundled` and `nimble setupSystem` shortcuts.

Native runtime artifacts remain separate from CBSS packages on every platform.

## CBSS C ABI Artifacts

The C ABI is built separately from the Nimble source installation:

```sh
nimble buildCAbiShared
nimble buildCAbiStatic
```

Applications using the shared ABI place `libcbss.so` in their own native
library directory, such as `cbss-libs/`. Static consumers link `libcbss.a` into
the executable. Neither artifact is prebuilt or embedded in the published
Nimble package. The same `include/cbss.h` declares both forms.

## Security and Updates

- Do not load native libraries from the current working directory or a
  world-writable directory.
- Preserve SDL3 SONAME links when packaging a dynamic system/custom runtime.
- Treat native-library replacement as executable-code replacement.
- Update [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), lockfiles, and
  platform validation records whenever a runtime library changes.
- Production packagers should verify checksums or signatures for runtime
  artifacts supplied outside this repository.
