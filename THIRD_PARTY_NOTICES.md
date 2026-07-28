# Third-Party Notices

CBSS is distributed under the MIT license in [LICENSE](LICENSE). The project
also contains or links the following third-party software.

## SDL3

- Component: SDL3 headers and Linux x86_64 libraries
- Version: 3.5.0
- Upstream: <https://github.com/libsdl-org/SDL>
- Development-checkout location: `vendor/sdl3/` (not included in the installed
  CBSS Nimble package)
- License: zlib
- License text: [licenses/SDL3.txt](licenses/SDL3.txt)

The three `libSDL3.so*` paths are the ABI name, SONAME, and versioned filename
for the same Linux build. Applications using bundled setup statically link the
corresponding `libSDL3.a`. System and custom setup dynamically link an
installation supplied by the application or operating system instead.

## cosmic-text Bridge

- Component: `cbss_cosmic_text_bridge`
- Version: 0.1.0
- Source: `native/cosmic_text_bridge/`
- Direct text dependency: cosmic-text 0.19.0
- Upstream: <https://github.com/pop-os/cosmic-text>
- License: MIT OR Apache-2.0
- License texts:
  [MIT](licenses/cosmic-text-MIT.txt),
  [Apache-2.0](licenses/Apache-2.0.txt)

The complete, locked Rust dependency graph is recorded in
`native/cosmic_text_bridge/Cargo.lock`. Its dependencies use permissive
MIT, Apache-2.0, zlib, and Unicode licenses. CBSS distributes the common
license texts in `licenses/`; `unicode-ident` additionally uses the
[Unicode License v3](licenses/Unicode-3.0.txt).

## CBSS Image Bridge

- Component: `cbss_image_bridge`
- Version: 0.1.0
- Source: `native/image_bridge/`
- Purpose: C ABI image decoding bridge used by the SDL3 backend
- Direct image dependency: image 0.25.9
- Upstream: <https://github.com/image-rs/image>
- License: MIT
- License text: [licenses/image-rs.txt](licenses/image-rs.txt)

The bridge code itself is part of CBSS and is distributed under the repository
MIT license. Its complete, locked Rust dependency graph is recorded in
`native/image_bridge/Cargo.lock`.

## Generated SDL3 Nim Bindings

`src/clay_box_style_system/vendor/sdl3.nim` is generated from the vendored SDL3
headers. It describes the SDL3 C API and is used under the same SDL3 license
identified above.

## Updating This File

When a vendored binary, generated binding, or Rust dependency changes, update
its version, source, license, and lockfile in the same change. A release must
not contain an unexplained native binary.
