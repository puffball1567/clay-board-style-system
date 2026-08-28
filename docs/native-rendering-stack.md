# Native Rendering And Color Capability Stack

Status: `Adopted architecture; implementation is staged`

CBSS uses four deliberately separate layers for native presentation. The
layers are selected because practical GUI adoption depends on detailed
capabilities such as portable input, high-quality vector output, optional GPU
compute, and color-managed CMYK preview. No one dependency owns the public UI
model.

```text
Application and component libraries
                |
                v
CBSS UI / Layout / Vector / Canvas / Events / State
          |                  |                  |
          v                  v                  v
SDL3 platform and       optional bgfx       optional Little CMS
CPU presentation        GPU execution       color transforms
```

## Layer Responsibilities

| Layer | Required responsibility | Explicit boundary |
| --- | --- | --- |
| SDL3 | Cross-platform windows, native handles, event delivery, keyboard, pointer, pen, touch and controller input, timing wakeups, and baseline CPU presentation | SDL3 does not define CBSS layout, vector geometry, component behavior, or color-management policy |
| CBSS | UI, layout, text integration, retained Canvas, Paint IR, high-quality CPU vector rasterization, hit testing, events, focus, accessibility semantics, state, invalidation, caching, and frame scheduling | CBSS does not expose renderer-specific handles in ordinary UI APIs and does not make a GPU mandatory |
| bgfx | Optional cross-platform GPU graphics and compute for games, visualization, motion graphics, image processing, particles, custom Canvas content, and bounded shader effects | bgfx is not a second layout, widget, text, or event implementation |
| Little CMS | Optional CMYK and ICC transforms, rendering intents, black preservation, gamut conversion, and display soft proofing | Little CMS does not own documents, printing, PDF export, UI controls, or application workflow |

SDL3 is the portability floor. A supported application can build and display
ordinary UI without bgfx or Little CMS. CBSS owns the canonical CPU behavior
needed to keep that floor useful rather than treating it as a diagnostic-only
fallback.

## Canonical CPU Vector Path

The baseline vector renderer is a CBSS implementation presented through SDL3.
It is not a set of repeated `SDL_RenderLine` calls and it is not delegated to a
third-party vector scene model.

```text
Path2D and resolved Paint IR
          |
adaptive curve subdivision, fill rules, stroke outlines,
coverage anti-aliasing, clipping, masks and compositing
          |
premultiplied CPU tiles and cached layers
          |
dirty texture upload and SDL3 presentation
```

The required vector scope includes non-zero and even-odd fills, quadratic and
cubic curves, arcs and ellipses, line caps and joins, miter limits, dashes,
gradients, masks, path clips, deterministic transforms, and subpixel coverage.
Static geometry, raster tiles, and uploaded textures are retained and rebuilt
only when their relevant input changes.

This CPU path is the deterministic reference for headless tests and devices
without an accepted GPU capability. A later GPU vector accelerator may consume
the same Path2D and Paint IR, but it must not replace or redefine the authored
model.

## Optional bgfx GPU Capability

bgfx is the planned standard GPU adapter. Its low-level Nim C99 binding,
[bgfxim](https://github.com/puffball1567/bgfxim), is an independent package so
games and visualization libraries may use it without CBSS. CBSS depends on
that package only when the bgfx capability is selected. `bgfxim` is already
available; the CBSS adapter, ownership integration, and real-GPU release gates
remain planned work rather than part of the current standard profile.

CBSS supplies bgfx with bounded scene data, textures, render targets, graphics
or compute work, and composition metadata. SDL3 supplies the native window and
input lifecycle. One component owns acquisition and presentation for each
window; SDL's high-level renderer and bgfx must not independently present to
the same swapchain.

The build includes only renderers appropriate to its target. A typical policy
is D3D12 with an optional D3D11 fallback on Windows, Metal on Apple targets,
and Vulkan with an optional OpenGL ES fallback on Linux and Android. Console
support is claimed only after validation with the licensed platform toolchain
and backend.

bgfx-specific handles remain private to the adapter. Public Canvas, scene,
resource, frame-scheduling, device-loss, and diagnostics contracts use
CBSS-owned types. An additional GPU adapter may be implemented later, but it
does not change the standard profile or require duplicate GPU runtimes.

## Optional Little CMS Color Management

CMYK support is not a four-number shortcut converted permanently to RGB.
Color-managed documents retain their authored values and profile identity.

```text
canonical document color
  - CMYK or other authored channels
  - ICC profile identity and version
  - rendering intent
  - black, spot and overprint metadata where supported
                |
                +--> print/export adapter receives preserved source data
                |
                `--> Little CMS soft-proof transform
                               |
                               v
                     monitor-profile RGB preview
                               |
                               v
                        SDL3 or bgfx display
```

The final monitor texture is RGB because a monitor is an RGB device. It is a
derived preview cache, not the document's canonical color. A CMYK-capable
Canvas must therefore keep K-channel and profile information after preview
generation and must not use the preview texture as print source data.

The color-management capability provides profile registration, bounded profile
loading, transform caching, rendering-intent selection, soft proofing, gamut
diagnostics, and C/M/Y/K separation inspection. PDF/X, TIFF, printer spooling,
bleed, crop marks, and application-specific preflight remain adapter or
application concerns built on preserved color data.

ICC profiles are untrusted data inputs even though they are not executable
programs. Profile size, channel count, transform allocation, dimensions, and
cache budgets are bounded and malformed profiles fail without changing the
active transform.

## Images And Codecs

Image decoding is separate from rendering. Decoders produce a bounded image
buffer plus color-profile metadata; CPU and GPU backends consume the same
result.

- PNG is the first standard lossless and alpha-capable image capability.
- JPEG is an optional photographic-image capability.
- WebP and other codecs are separate opt-ins.
- SVG remains a vector import concern and does not replace CBSS Path2D.
- A decoded preview must not erase an embedded source profile needed by export.

Decoder limits cover encoded size, dimensions, decoded bytes, channel count,
integer overflow, allocation failure, and malformed inputs. Unselected codecs
are absent from the dependency closure.

## Build And Distribution Profiles

Capability selection occurs at compile and package time, not only through a
runtime flag.

| Profile | Contents |
| --- | --- |
| `standard` | SDL3, ordinary CBSS UI, text, Canvas, and the canonical CPU vector renderer |
| `gpu-bgfx` | `standard` plus bgfx and only the target's selected GPU renderers and shader assets |
| `color-managed` | `standard` plus Little CMS and ICC/CMYK authoring and soft-proof support |
| `full` | Target-supported bgfx, Little CMS, and selected image codecs in addition to `standard` |

Release artifacts are produced per operating system and architecture. They do
not contain Metal on Windows, D3D on Linux, or unrelated GPU backends. Build
tools such as shader compilers, examples, tests, and converters are not part of
runtime artifacts.

CI records stripped executable size and native dependency closure for every
representative profile. A capability may not silently enter `standard`, and a
size increase beyond its recorded budget is a release regression until
reviewed.

## Capability Release Gates

Individual unit tests are necessary but not sufficient. The stack is qualified
through applications that need the detailed capability rather than only a
successful library call.

- A CMYK-capable vector or drawing application can preserve authored CMYK and
  ICC data, display an ICC soft proof, inspect separations, and hand preserved
  data to a print/export adapter without modifying CBSS internals.
- A GPU Canvas can be placed between ordinary Boxes, clipped and transformed,
  receive local input, render graphics and compute work through bgfx, and have
  ordinary CBSS UI composed above it.
- The same public Canvas and component code runs through the SDL3 CPU baseline
  on every supported desktop target, with platform-specific integration tests
  for mobile and other targets as they are qualified.
- Static content returns to event-driven idle behavior, while active vector or
  GPU animation requests only the frames it needs.
- Applications that do not select GPU, color management, or a codec do not
  link or distribute those native dependencies.

This stack is a capability boundary, not a promise that CBSS itself is a
drawing application, print product, game engine, or motion-graphics editor.
It ensures that such products are not blocked by a missing UI, rendering,
input, GPU, or color-management primitive.
