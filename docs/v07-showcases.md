# Version 0.7 Showcases

Version 0.7 includes two focused showcase applications. They are development
examples and are not linked into applications that import the CBSS package.

## Design Showcase

`v07DesignShowcase` contains five original visual systems in one native SDL3
window:

1. **Heart Parade** - two-column editorial composition with continuously
   scrolling heart ribbons.
2. **Candy Radio** - a saturated media-player layout with an animated signal
   and retained playback progress.
3. **Sticker Studio** - a paper pinboard built from transformed retained Canvas
   layers.
4. **Tiny Planet** - a quiet monitoring dashboard with orbiting status marks.
5. **Neon Dream** - a high-contrast live-visual dashboard with animated level
   bars.

Run it from the repository root:

```sh
nimble setupBundled
nimble v07DesignShowcase
```

Select the tabs with the pointer, the left/right arrow keys, or number keys
1 through 5. `CBSS_DESIGN_SCENE` accepts `heart`, `radio`, `sticker`, `planet`,
or `neon` for deterministic capture runs.

The showcase uses `Canvas2D`, the retained RenderSurface lifecycle, Cosmic Text,
clips, gradients, path fills and strokes, affine transforms, and the CBSS frame
scheduler. Animated scenes request frames explicitly; closing the showcase
releases the request and the window.

## GPU Showcase

`runV07GpuShowcase` renders five full-screen fragment workloads through the
optional bgfx adapter:

1. **Fluid Field** - a pointer-reactive layered wave field.
2. **Heart Particles** - a procedural field of independently moving hearts.
3. **Mechanical Core** - panel seams, rotating fasteners, an energy core, and a
   scanning light.
4. **Image Lab** - pixel sampling, channel separation, a moving lens, and a
   monochrome/color split.
5. **GPU Material** - a rounded UI material with animated shimmer and a
   pointer-relative ripple.

The demo owns one CBSS `GpuHost`, one bgfx device/queue, one window presentation
path, bounded resources, and one retained full-screen mesh. It does not use CPU
readback. The official bgfx `shaderc` is a build-time tool only; it is not linked
into the demo or a CBSS application.

Run it on the current Linux SDL3 host with compatible pinned source checkouts:

```sh
CBSS_BGFXIM_PATH=/path/to/bgfxim \
CBSS_BGFX_PATH=/path/to/bgfx \
CBSS_BX_PATH=/path/to/bx \
CBSS_BIMG_PATH=/path/to/bimg \
CBSS_SHADERC=/path/to/bgfx/tools/bin/linux/shaderc \
nimble runV07GpuShowcase
```

Use the number keys 1 through 5, the left/right arrow keys, or the five equal
regions at the top of the window. The current scene is reported in the native
window title.

The standard example checker excludes this source because it deliberately
requires the optional `cbssGpuBgfx` profile and external bgfx development
sources. Dedicated CI type-checks the compatible binding, compiles these shader
sources with the official compiler, and qualifies the backend separately.
