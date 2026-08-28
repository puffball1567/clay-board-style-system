# Third-Party Notices

CBSS is distributed under the Apache License 2.0 in [LICENSE](LICENSE). The
project also contains or links the following third-party software.

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
- License: MIT OR Apache-2.0 (CBSS elects MIT for this dependency)
- License text: [licenses/image-rs.txt](licenses/image-rs.txt)

The bridge code itself is part of CBSS and is distributed under the repository
Apache License 2.0. Its complete, locked Rust dependency graph is recorded in
`native/image_bridge/Cargo.lock`. The following catalogue records the resolved
dependency licenses used by the enabled BMP, GIF, JPEG, PNG, PNM, TIFF, and
WebP features. No GPL or LGPL dependency is enabled in this bridge.

| License selected or declared | Locked dependencies |
| --- | --- |
| MIT | `byteorder-lite 0.1.0`, `color_quant 1.1.0`, `crunchy 0.2.4`, `fax 0.2.6`, `fax_derive 0.2.0`, `simd-adler32 0.3.8`, `tiff 0.10.3` |
| MIT OR Apache-2.0 | `autocfg 1.5.0`, `bitflags 2.13.0`, `cfg-if 1.0.4`, `crc32fast 1.5.0`, `fdeflate 0.3.7`, `flate2 1.1.9`, `gif 0.14.1`, `half 2.7.1`, `image-webp 0.2.4`, `num-traits 0.2.19`, `png 0.18.1`, `proc-macro2 1.0.106`, `quick-error 2.0.1`, `quote 1.0.46`, `syn 2.0.118`, `weezl 0.1.12` |
| MIT OR Apache-2.0 OR Zlib | `bytemuck 1.25.0`, `miniz_oxide 0.8.9`, `zune-core 0.4.12`, `zune-core 0.5.1`, `zune-jpeg 0.4.21`, `zune-jpeg 0.5.12` |
| BSD-3-Clause OR Apache-2.0 | `moxcms 0.7.11`, `pxfm 0.1.27` |
| BSD-2-Clause OR Apache-2.0 OR MIT | `zerocopy 0.8.39`, `zerocopy-derive 0.8.39` |
| 0BSD OR MIT OR Apache-2.0 | `adler2 2.0.1` |
| (MIT OR Apache-2.0) AND Unicode-3.0 | `unicode-ident 1.0.24`; the Unicode text is in [licenses/Unicode-3.0.txt](licenses/Unicode-3.0.txt) |

For dependencies offering alternatives, CBSS uses the MIT or Apache-2.0 option
as applicable. The cargo lockfile is the authoritative version record; any
update to it must update this catalogue and the corresponding license notices.

## Generated SDL3 Nim Bindings

`src/clay_board_style_system/vendor/sdl3.nim` is generated from the vendored SDL3
headers. It describes the SDL3 C API and is used under the same SDL3 license
identified above.

## Updating This File

When a vendored binary, generated binding, or Rust dependency changes, update
its version, source, license, and lockfile in the same change. A release must
not contain an unexplained native binary.
