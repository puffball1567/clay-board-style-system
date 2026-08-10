# CSS Property Support Matrix

This document tracks CSS property names against CBSS support intent.
CBSS is CSS-like, not CSS-compatible, so this is not a promise to implement the browser platform.
It is an inventory for deciding which property-shaped features belong in CBSS.
See [css-property-implementation-order.md](css-property-implementation-order.md)
for the planned implementation order of properties inside the CBSS target.

Source inventory: MDN `mdn/data`
[`css/properties.json`](https://github.com/mdn/data/blob/main/css/properties.json).

## Status

- `Runtime`: accepted by the style resolver and currently affects layout, paint,
  hit testing, text rendering, or another visible/runtime subsystem.
- `Computed`: accepted by the style resolver and stored in computed style, but
  full runtime behavior is still partial.
- `Metadata`: accepted and preserved as typed or raw metadata for a later
  subsystem, design-source interchange, animation, vector, transform, or
  platform integration layer.
- `Planned`: intended for CBSS, but not accepted by the current default property
  registry yet.
- `No plan`: not in the current implementation target because it is browser-specific, document-specific, vendor-specific, obsolete, effectively deprecated, or outside the current CBSS model.

In short, every property not marked `No plan` is intended to be implemented.
`Runtime` is the only status that means the property currently changes rendered
or interactive behavior. `Computed` and `Metadata` are useful implementation
steps, but should not be presented as complete visual/runtime support.
`Planned` means unsupported today, but inside the CBSS implementation target.
`No plan` is a current project boundary, not necessarily a permanent rejection.
After CBSS has shipped and the core model is proven, some `No plan` properties
may be reconsidered if they make sense for native GUI work. Obsolete, legacy, or
effectively deprecated CSS features should generally remain `No plan`.

Anything other than `Runtime`, `Computed`, or `Metadata` is currently unsupported
by the default property registry. Runtime support still may be intentionally
simpler than browser CSS when the browser behavior is document-specific or a
legacy compatibility burden.

Obsolete, legacy, or effectively deprecated CSS features should generally stay
`No plan` even when browsers still carry them for compatibility. CBSS should spend
implementation effort on modern native GUI behavior, not web compatibility debt.

Keyframe animation is not excluded. The principal `animation-*` longhands and
transition property, duration, delay, and timing function now drive the first
paint-only runtime slices. Remaining animation and transition metadata
preserves typed intent for later runtime work.

## Summary

| Status | Count |
| --- | ---: |
| Runtime | 174 |
| Computed | 77 |
| Metadata | 176 |
| Planned | 0 |
| No plan | 238 |
| Target properties | 427 |
| Total MDN entries | 665 |

As of 2026-08-10, strict runtime completion is **174 of 427 target
properties (40.7%)**. A further 77 properties reach computed style, so
**251 of 427 (58.8%)** have runtime or computed support. All 427 target names
are accepted by the default registry, but metadata-only acceptance is not
counted as completed behavior. The 238 `No plan` entries are excluded from the
implementation target and from both percentages.

The counts above come only from the canonical Full Property Inventory. The
curated table below repeats frequently used runtime properties for readability
and must not be added to the totals a second time.

These are property-level counts. Adding another accepted unit, keyword, color
syntax, or value form improves the listed property's fidelity but does not add
another property to the numerator. Likewise, Canvas APIs, components, events,
forms, navigation, and data contracts are CBSS capabilities but are not CSS
properties and are excluded here. The 2026-08-08 audit reviewed the current
default registry and the viewport-relative, percentage-spacing,
line-height-relative, and font-metric-relative unit work using this rule.

## Initial Implementation Properties

This convenience table contains the 68 P0 properties plus the four
side-specific border-style variants. All 72 entries also appear in the canonical
inventory below; they are not additional properties.

| Property | Status | Note |
| --- | --- | --- |
| `align-items` | Runtime | Initial CBSS runtime surface. |
| `background-color` | Runtime | Initial CBSS runtime surface. |
| `border` | Runtime | Initial CBSS runtime surface. |
| `border-bottom` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-color` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-left-radius` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-right-radius` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-bottom-width` | Runtime | Initial CBSS runtime surface. |
| `border-color` | Runtime | Initial CBSS runtime surface. |
| `border-left` | Runtime | Initial CBSS runtime surface. |
| `border-left-color` | Runtime | Initial CBSS runtime surface. |
| `border-left-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-left-width` | Runtime | Initial CBSS runtime surface. |
| `border-radius` | Runtime | Initial CBSS runtime surface. |
| `border-right` | Runtime | Initial CBSS runtime surface. |
| `border-right-color` | Runtime | Initial CBSS runtime surface. |
| `border-right-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-right-width` | Runtime | Initial CBSS runtime surface. |
| `border-style` | Runtime | Initial CBSS runtime surface. |
| `border-top` | Runtime | Initial CBSS runtime surface. |
| `border-top-color` | Runtime | Initial CBSS runtime surface. |
| `border-top-left-radius` | Runtime | Initial CBSS runtime surface. |
| `border-top-right-radius` | Runtime | Initial CBSS runtime surface. |
| `border-top-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-top-width` | Runtime | Initial CBSS runtime surface. |
| `border-width` | Runtime | Initial CBSS runtime surface. |
| `bottom` | Runtime | Supports signed px and percentage offsets against the containing content height. |
| `color` | Runtime | Initial CBSS runtime surface. |
| `column-gap` | Runtime | Supports px and percentage spacing against the container content width. |
| `display` | Runtime | Initial CBSS runtime surface. |
| `flex-basis` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `flex-direction` | Runtime | Initial CBSS runtime surface. |
| `flex-grow` | Runtime | Initial CBSS runtime surface. |
| `flex-shrink` | Runtime | Initial CBSS runtime surface. |
| `font-family` | Runtime | Ordered family fallback is resolved across the cosmic-text bridge; registered-only rendering is available with `useSystemFonts = false`. |
| `font-size` | Runtime | Initial CBSS runtime surface. |
| `font-style` | Runtime | Initial CBSS runtime surface. |
| `font-weight` | Runtime | Initial CBSS runtime surface. |
| `gap` | Runtime | Supports px and percentage spacing on the active layout axis. |
| `height` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `justify-content` | Runtime | Initial CBSS runtime surface. |
| `left` | Runtime | Supports signed px and percentage offsets against the containing content width. |
| `line-height` | Runtime | Initial CBSS runtime surface. |
| `margin` | Runtime | Initial CBSS runtime surface. |
| `margin-bottom` | Runtime | Initial CBSS runtime surface. |
| `margin-left` | Runtime | Initial CBSS runtime surface. |
| `margin-right` | Runtime | Initial CBSS runtime surface. |
| `margin-top` | Runtime | Initial CBSS runtime surface. |
| `max-height` | Runtime | Supports px, percentage, none, and intrinsic sizing values. |
| `max-width` | Runtime | Supports px, percentage, none, and intrinsic sizing values. |
| `min-height` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `min-width` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `object-fit` | Runtime | Initial CBSS runtime surface. |
| `object-position` | Runtime | Initial CBSS runtime surface. |
| `opacity` | Runtime | Initial CBSS runtime surface. |
| `overflow` | Runtime | Supports `visible`, `hidden`, `clip`, `auto`, and `scroll`; retained offsets affect paint and hit testing without relayout. |
| `overflow-x` | Runtime | Resolves and clips the horizontal axis independently; `auto` and `scroll` enable horizontal offset updates. |
| `overflow-y` | Runtime | Resolves and clips the vertical axis independently; `auto` and `scroll` enable vertical offset updates. |
| `padding` | Runtime | Initial CBSS runtime surface. |
| `padding-bottom` | Runtime | Initial CBSS runtime surface. |
| `padding-left` | Runtime | Initial CBSS runtime surface. |
| `padding-right` | Runtime | Initial CBSS runtime surface. |
| `padding-top` | Runtime | Initial CBSS runtime surface. |
| `position` | Runtime | `static`, `relative`, and `absolute` are implemented; `fixed` and `sticky` produce diagnostics. Positioned-ancestor chaining is still pending. |
| `right` | Runtime | Supports signed px and percentage offsets against the containing content width. |
| `row-gap` | Runtime | Supports px and percentage spacing against the container content height. |
| `text-align` | Runtime | Initial CBSS runtime surface. |
| `top` | Runtime | Supports signed px and percentage offsets against the containing content height. |
| `white-space` | Runtime | Initial CBSS runtime surface. |
| `width` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `z-index` | Runtime | Initial CBSS runtime surface. |

## CBSS-Specific Extensions

These properties are native CBSS extensions and are excluded from the MDN-based
427-property target and its completion percentages.

| Property | Status | Note |
| --- | --- | --- |
| `scrollbar-visibility` | Runtime | Controls whether retained scrollbars are always visible or visible only while scrolling. |

## Full Property Inventory

| Property | Status | Note |
| --- | --- | --- |
| `--*` | No plan | Nim `var`/`let`/`const`, typed theme values, and Style DI are the value-indirection model; CBSS does not add a parallel CSS variable system. |
| `-moz-appearance` | No plan | Vendor-specific browser property. |
| `-moz-binding` | No plan | Vendor-specific browser property. |
| `-moz-border-bottom-colors` | No plan | Vendor-specific browser property. |
| `-moz-border-left-colors` | No plan | Vendor-specific browser property. |
| `-moz-border-right-colors` | No plan | Vendor-specific browser property. |
| `-moz-border-top-colors` | No plan | Vendor-specific browser property. |
| `-moz-context-properties` | No plan | Vendor-specific browser property. |
| `-moz-float-edge` | No plan | Vendor-specific browser property. |
| `-moz-force-broken-image-icon` | No plan | Vendor-specific browser property. |
| `-moz-orient` | No plan | Vendor-specific browser property. |
| `-moz-outline-radius` | No plan | Vendor-specific browser property. |
| `-moz-outline-radius-bottomleft` | No plan | Vendor-specific browser property. |
| `-moz-outline-radius-bottomright` | No plan | Vendor-specific browser property. |
| `-moz-outline-radius-topleft` | No plan | Vendor-specific browser property. |
| `-moz-outline-radius-topright` | No plan | Vendor-specific browser property. |
| `-moz-stack-sizing` | No plan | Vendor-specific browser property. |
| `-moz-text-blink` | No plan | Vendor-specific browser property. |
| `-moz-user-focus` | No plan | Vendor-specific browser property. |
| `-moz-user-input` | No plan | Vendor-specific browser property. |
| `-moz-user-modify` | No plan | Vendor-specific browser property. |
| `-moz-window-dragging` | No plan | Vendor-specific browser property. |
| `-moz-window-shadow` | No plan | Vendor-specific browser property. |
| `-ms-accelerator` | No plan | Vendor-specific browser property. |
| `-ms-block-progression` | No plan | Vendor-specific browser property. |
| `-ms-content-zoom-chaining` | No plan | Vendor-specific browser property. |
| `-ms-content-zoom-limit` | No plan | Vendor-specific browser property. |
| `-ms-content-zoom-limit-max` | No plan | Vendor-specific browser property. |
| `-ms-content-zoom-limit-min` | No plan | Vendor-specific browser property. |
| `-ms-content-zoom-snap` | No plan | Vendor-specific browser property. |
| `-ms-content-zoom-snap-points` | No plan | Vendor-specific browser property. |
| `-ms-content-zoom-snap-type` | No plan | Vendor-specific browser property. |
| `-ms-content-zooming` | No plan | Vendor-specific browser property. |
| `-ms-filter` | No plan | Vendor-specific browser property. |
| `-ms-flow-from` | No plan | Vendor-specific browser property. |
| `-ms-flow-into` | No plan | Vendor-specific browser property. |
| `-ms-grid-columns` | No plan | Vendor-specific browser property. |
| `-ms-grid-rows` | No plan | Vendor-specific browser property. |
| `-ms-high-contrast-adjust` | No plan | Vendor-specific browser property. |
| `-ms-hyphenate-limit-chars` | No plan | Vendor-specific browser property. |
| `-ms-hyphenate-limit-lines` | No plan | Vendor-specific browser property. |
| `-ms-hyphenate-limit-zone` | No plan | Vendor-specific browser property. |
| `-ms-ime-align` | No plan | Vendor-specific browser property. |
| `-ms-overflow-style` | No plan | Vendor-specific browser property. |
| `-ms-scroll-chaining` | No plan | Vendor-specific browser property. |
| `-ms-scroll-limit` | No plan | Vendor-specific browser property. |
| `-ms-scroll-limit-x-max` | No plan | Vendor-specific browser property. |
| `-ms-scroll-limit-x-min` | No plan | Vendor-specific browser property. |
| `-ms-scroll-limit-y-max` | No plan | Vendor-specific browser property. |
| `-ms-scroll-limit-y-min` | No plan | Vendor-specific browser property. |
| `-ms-scroll-rails` | No plan | Vendor-specific browser property. |
| `-ms-scroll-snap-points-x` | No plan | Vendor-specific browser property. |
| `-ms-scroll-snap-points-y` | No plan | Vendor-specific browser property. |
| `-ms-scroll-snap-type` | No plan | Vendor-specific browser property. |
| `-ms-scroll-snap-x` | No plan | Vendor-specific browser property. |
| `-ms-scroll-snap-y` | No plan | Vendor-specific browser property. |
| `-ms-scroll-translation` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-3dlight-color` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-arrow-color` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-base-color` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-darkshadow-color` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-face-color` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-highlight-color` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-shadow-color` | No plan | Vendor-specific browser property. |
| `-ms-scrollbar-track-color` | No plan | Vendor-specific browser property. |
| `-ms-text-autospace` | No plan | Vendor-specific browser property. |
| `-ms-touch-select` | No plan | Vendor-specific browser property. |
| `-ms-user-select` | No plan | Vendor-specific browser property. |
| `-ms-wrap-flow` | No plan | Vendor-specific browser property. |
| `-ms-wrap-margin` | No plan | Vendor-specific browser property. |
| `-ms-wrap-through` | No plan | Vendor-specific browser property. |
| `-webkit-appearance` | No plan | Vendor-specific browser property. |
| `-webkit-border-after` | No plan | Vendor-specific browser property. |
| `-webkit-border-after-color` | No plan | Vendor-specific browser property. |
| `-webkit-border-after-style` | No plan | Vendor-specific browser property. |
| `-webkit-border-after-width` | No plan | Vendor-specific browser property. |
| `-webkit-border-before` | No plan | Vendor-specific browser property. |
| `-webkit-border-before-color` | No plan | Vendor-specific browser property. |
| `-webkit-border-before-style` | No plan | Vendor-specific browser property. |
| `-webkit-border-before-width` | No plan | Vendor-specific browser property. |
| `-webkit-border-end` | No plan | Vendor-specific browser property. |
| `-webkit-border-end-color` | No plan | Vendor-specific browser property. |
| `-webkit-border-end-style` | No plan | Vendor-specific browser property. |
| `-webkit-border-end-width` | No plan | Vendor-specific browser property. |
| `-webkit-border-start` | No plan | Vendor-specific browser property. |
| `-webkit-border-start-color` | No plan | Vendor-specific browser property. |
| `-webkit-border-start-style` | No plan | Vendor-specific browser property. |
| `-webkit-border-start-width` | No plan | Vendor-specific browser property. |
| `-webkit-box-reflect` | No plan | Vendor-specific browser property. |
| `-webkit-line-clamp` | No plan | Vendor-specific browser property. |
| `-webkit-mask` | No plan | Vendor-specific browser property. |
| `-webkit-mask-attachment` | No plan | Vendor-specific browser property. |
| `-webkit-mask-clip` | No plan | Vendor-specific browser property. |
| `-webkit-mask-composite` | No plan | Vendor-specific browser property. |
| `-webkit-mask-image` | No plan | Vendor-specific browser property. |
| `-webkit-mask-origin` | No plan | Vendor-specific browser property. |
| `-webkit-mask-position` | No plan | Vendor-specific browser property. |
| `-webkit-mask-position-x` | No plan | Vendor-specific browser property. |
| `-webkit-mask-position-y` | No plan | Vendor-specific browser property. |
| `-webkit-mask-repeat` | No plan | Vendor-specific browser property. |
| `-webkit-mask-repeat-x` | No plan | Vendor-specific browser property. |
| `-webkit-mask-repeat-y` | No plan | Vendor-specific browser property. |
| `-webkit-mask-size` | No plan | Vendor-specific browser property. |
| `-webkit-overflow-scrolling` | No plan | Vendor-specific browser property. |
| `-webkit-tap-highlight-color` | No plan | Vendor-specific browser property. |
| `-webkit-text-fill-color` | No plan | Vendor-specific browser property. |
| `-webkit-text-stroke` | No plan | Vendor-specific browser property. |
| `-webkit-text-stroke-color` | No plan | Vendor-specific browser property. |
| `-webkit-text-stroke-width` | No plan | Vendor-specific browser property. |
| `-webkit-touch-callout` | No plan | Vendor-specific browser property. |
| `-webkit-user-modify` | No plan | Vendor-specific browser property. |
| `-webkit-user-select` | No plan | Vendor-specific browser property. |
| `accent-color` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `align-content` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `align-items` | Runtime | Initial CBSS runtime surface. |
| `align-self` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `align-tracks` | Metadata | Stored as computed layout metadata. |
| `alignment-baseline` | Metadata | Stored as computed baseline metadata. |
| `all` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `anchor-name` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `anchor-scope` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `animation` | Metadata | Stored as animation metadata; runtime subsystem is not complete yet. |
| `animation-composition` | Metadata | Stored as animation metadata; runtime subsystem is not complete yet. |
| `animation-delay` | Runtime | Drives named paint keyframes, including negative delays; list cycling remains planned. |
| `animation-direction` | Runtime | Controls normal, reverse, alternate, and alternate-reverse named keyframe playback. |
| `animation-duration` | Runtime | Drives the active interval for named paint keyframes. |
| `animation-fill-mode` | Runtime | Controls backwards sampling and retained forwards presentation for named paint keyframes. |
| `animation-iteration-count` | Runtime | Supports finite counts and infinite named paint-keyframe playback. |
| `animation-name` | Runtime | Binds a node to a typed keyframe definition registered on its `UiRoot`; multiple animation names remain planned. |
| `animation-play-state` | Runtime | Pauses and resumes named paint keyframes without restarting their timeline. |
| `animation-range` | Metadata | Stored as animation metadata; runtime subsystem is not complete yet. |
| `animation-range-end` | Metadata | Stored as animation metadata; runtime subsystem is not complete yet. |
| `animation-range-start` | Metadata | Stored as animation metadata; runtime subsystem is not complete yet. |
| `animation-timeline` | Metadata | Stored as animation metadata; runtime subsystem is not complete yet. |
| `animation-timing-function` | Runtime | Supports named timing functions, step start/end, and valid cubic Bezier curves for named paint keyframes. |
| `animation-trigger` | Metadata | Stored as animation metadata; runtime subsystem is not complete yet. |
| `appearance` | Metadata | Stored as computed visual metadata. |
| `aspect-ratio` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `backdrop-filter` | Metadata | Stored as visual effect metadata; renderer application is a later runtime layer. |
| `backface-visibility` | Metadata | Stored as computed transform metadata. |
| `background` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-attachment` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-blend-mode` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-clip` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-color` | Runtime | Initial CBSS runtime surface. |
| `background-image` | Runtime | Linear gradients are emitted into paint commands; other image forms are still partial. |
| `background-origin` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-position` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-position-x` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-position-y` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-repeat` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `background-size` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `baseline-shift` | Metadata | Stored as computed baseline metadata. |
| `baseline-source` | Metadata | Stored as computed baseline metadata. |
| `block-size` | Runtime | Logical height alias with percentage, auto, and intrinsic sizing in horizontal LTR mode. |
| `border` | Runtime | Initial CBSS runtime surface. |
| `border-block` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-color` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-end` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-end-color` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-end-style` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-end-width` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-start` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-start-color` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-start-style` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-start-width` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-style` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-block-width` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-bottom` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-color` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-left-radius` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-right-radius` | Runtime | Initial CBSS runtime surface. |
| `border-bottom-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-bottom-width` | Runtime | Initial CBSS runtime surface. |
| `border-collapse` | Metadata | Stored as computed border metadata. |
| `border-color` | Runtime | Initial CBSS runtime surface. |
| `border-end-end-radius` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-end-start-radius` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-image` | Metadata | Stored as computed border image metadata. |
| `border-image-outset` | Metadata | Stored as computed border image metadata. |
| `border-image-repeat` | Metadata | Stored as computed border image metadata. |
| `border-image-slice` | Metadata | Stored as computed border image metadata. |
| `border-image-source` | Metadata | Stored as computed border image metadata. |
| `border-image-width` | Metadata | Stored as computed border image metadata. |
| `border-inline` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-color` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-end` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-end-color` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-end-style` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-end-width` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-start` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-start-color` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-start-style` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-start-width` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-style` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-inline-width` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-left` | Runtime | Initial CBSS runtime surface. |
| `border-left-color` | Runtime | Initial CBSS runtime surface. |
| `border-left-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-left-width` | Runtime | Initial CBSS runtime surface. |
| `border-radius` | Runtime | Initial CBSS runtime surface. |
| `border-right` | Runtime | Initial CBSS runtime surface. |
| `border-right-color` | Runtime | Initial CBSS runtime surface. |
| `border-right-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-right-width` | Runtime | Initial CBSS runtime surface. |
| `border-shape` | Metadata | Stored as computed border metadata. |
| `border-spacing` | Metadata | Stored as computed border metadata. |
| `border-start-end-radius` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-start-start-radius` | Runtime | Logical alias for physical border edges or corners in the initial horizontal LTR writing mode. |
| `border-style` | Runtime | Initial CBSS runtime surface. |
| `border-top` | Runtime | Initial CBSS runtime surface. |
| `border-top-color` | Runtime | Initial CBSS runtime surface. |
| `border-top-left-radius` | Runtime | Initial CBSS runtime surface. |
| `border-top-right-radius` | Runtime | Initial CBSS runtime surface. |
| `border-top-style` | Runtime | Side-specific border style; supports solid, none, and hidden. |
| `border-top-width` | Runtime | Initial CBSS runtime surface. |
| `border-width` | Runtime | Initial CBSS runtime surface. |
| `bottom` | Runtime | Supports signed px and percentage offsets against the containing content height. |
| `box-align` | Metadata | Stored as legacy box layout metadata. |
| `box-decoration-break` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `box-direction` | Metadata | Stored as legacy box layout metadata. |
| `box-flex` | Metadata | Stored as legacy box layout metadata. |
| `box-flex-group` | Metadata | Stored as legacy box layout metadata. |
| `box-lines` | Metadata | Stored as legacy box layout metadata. |
| `box-ordinal-group` | Metadata | Stored as legacy box layout metadata. |
| `box-orient` | Metadata | Stored as legacy box layout metadata. |
| `box-pack` | Metadata | Stored as legacy box layout metadata. |
| `box-shadow` | Runtime | Emits box shadow paint commands in the SDL3 renderer. |
| `box-sizing` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `break-after` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `break-before` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `break-inside` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `caption-side` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `caret` | Metadata | Stored as computed visual metadata. |
| `caret-animation` | Metadata | Stored as computed visual metadata. |
| `caret-color` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `caret-shape` | Metadata | Stored as computed visual metadata. |
| `clear` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `clip` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `clip-path` | Runtime | Supports `inset(...)` px clipping in the paint pipeline; other values are preserved as clipping metadata. |
| `clip-rule` | Metadata | Stored as computed clipping metadata. |
| `color` | Runtime | Initial CBSS runtime surface. |
| `color-interpolation-filters` | Metadata | Stored as computed vector metadata. |
| `color-scheme` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `column-count` | Metadata | Stores positive number values and `auto` as computed column metadata. |
| `column-fill` | Metadata | Stored as computed column metadata. |
| `column-gap` | Runtime | Supports px and percentage spacing against the container content width. |
| `column-height` | Metadata | Stores px values as computed column metadata. |
| `column-rule` | Metadata | Stored as computed column metadata. |
| `column-rule-color` | Metadata | Stores color values as computed column metadata. |
| `column-rule-style` | Metadata | Stored as computed column metadata. |
| `column-rule-width` | Metadata | Stores px values as computed column metadata. |
| `column-span` | Metadata | Stored as computed column metadata. |
| `column-width` | Metadata | Stores px values as computed column metadata. |
| `column-wrap` | Metadata | Stored as computed column metadata. |
| `columns` | Metadata | Stored as computed column metadata. |
| `contain` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `contain-intrinsic-block-size` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `contain-intrinsic-height` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `contain-intrinsic-inline-size` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `contain-intrinsic-size` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `contain-intrinsic-width` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `container` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `container-name` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `container-type` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `content` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `content-visibility` | Runtime | `hidden` suppresses descendant paint and hit regions while keeping the element's own box paint and hit region; other values are preserved as visual metadata. |
| `corner-block-end-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-block-start-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-bottom-left-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-bottom-right-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-bottom-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-end-end-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-end-start-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-inline-end-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-inline-start-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-left-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-right-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-start-end-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-start-start-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-top-left-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-top-right-shape` | Metadata | Stored as computed corner shape metadata. |
| `corner-top-shape` | Metadata | Stored as computed corner shape metadata. |
| `counter-increment` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `counter-reset` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `counter-set` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `cursor` | Runtime | Resolves standard cursor keywords; styled hit regions expose cursor metadata and the SDL3 demo maps them to system cursors. |
| `cx` | Metadata | Stores number and px length values as computed vector geometry metadata. |
| `cy` | Metadata | Stores number and px length values as computed vector geometry metadata. |
| `d` | Metadata | Stored as computed vector path metadata. |
| `direction` | Metadata | Stored in computed text style; rendering/layout integration can deepen with writing-mode support. |
| `display` | Runtime | Initial CBSS runtime surface. |
| `dominant-baseline` | Metadata | Stored as computed baseline metadata. |
| `dynamic-range-limit` | Metadata | Stored as computed visual metadata. |
| `empty-cells` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `field-sizing` | Metadata | Stored as computed visual metadata. |
| `fill` | Metadata | Stores color values and keyword metadata for vector drawing. |
| `fill-opacity` | Metadata | Stores number values as computed vector metadata. |
| `fill-rule` | Metadata | Stored as computed vector metadata. |
| `filter` | Metadata | Stored as visual effect metadata; renderer application is a later runtime layer. |
| `flex` | Runtime | Supports common single-value shorthand forms: number, sizing basis, `none`, `auto`, and `initial`. |
| `flex-basis` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `flex-direction` | Runtime | Initial CBSS runtime surface. |
| `flex-flow` | Computed | Supports direction/wrap keyword metadata such as `column wrap`; runtime wrapping is still partial. |
| `flex-grow` | Runtime | Initial CBSS runtime surface. |
| `flex-shrink` | Runtime | Initial CBSS runtime surface. |
| `flex-wrap` | Computed | Supports `nowrap`, `wrap`, and `wrap-reverse` metadata; runtime wrapping is still partial. |
| `float` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `flood-color` | Metadata | Stores color values as computed vector metadata. |
| `flood-opacity` | Metadata | Stores number values as computed vector metadata. |
| `font` | Metadata | Stored as raw computed text metadata; detailed shorthand expansion can be added later. |
| `font-family` | Runtime | Ordered family fallback is resolved across the cosmic-text bridge; registered-only rendering is available with `useSystemFonts = false`. |
| `font-feature-settings` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-kerning` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-language-override` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-optical-sizing` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-palette` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-size` | Runtime | Initial CBSS runtime surface. |
| `font-size-adjust` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-smooth` | Metadata | Stored as computed text metadata. |
| `font-stretch` | Computed | Stored for native text engines and cosmic-text font matching. |
| `font-style` | Runtime | Initial CBSS runtime surface. |
| `font-synthesis` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-synthesis-position` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-synthesis-small-caps` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-synthesis-style` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-synthesis-weight` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant-alternates` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant-caps` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant-east-asian` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant-emoji` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant-ligatures` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant-numeric` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variant-position` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-variation-settings` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `font-weight` | Runtime | Initial CBSS runtime surface. |
| `font-width` | Metadata | Stores percent values and standard width keywords as computed metadata. |
| `forced-color-adjust` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `gap` | Runtime | Supports px and percentage spacing on the active layout axis. |
| `grid` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-area` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-auto-columns` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-auto-flow` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-auto-rows` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-column` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-column-end` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-column-gap` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `grid-column-start` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-gap` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `grid-row` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-row-end` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-row-gap` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `grid-row-start` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-template` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-template-areas` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-template-columns` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `grid-template-rows` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `hanging-punctuation` | Metadata | Stored as computed text metadata. |
| `height` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `hyphenate-character` | Metadata | Stored as computed text metadata. |
| `hyphenate-limit-chars` | Metadata | Stored as computed text metadata. |
| `hyphens` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `image-orientation` | Metadata | Stored as computed image metadata. |
| `image-rendering` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `image-resolution` | Metadata | Stored as computed image metadata. |
| `ime-mode` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `initial-letter` | Metadata | Stored as computed text metadata. |
| `initial-letter-align` | Metadata | Stored as computed text metadata. |
| `inline-size` | Runtime | Logical width alias with percentage, auto, and intrinsic sizing in horizontal LTR mode. |
| `inset` | Runtime | One-value shorthand supporting signed px, percentage, and auto offsets. |
| `inset-block` | Runtime | Logical signed px/percentage alias mapped to top/bottom in the current physical model. |
| `inset-block-end` | Runtime | Logical signed px/percentage alias mapped to bottom. |
| `inset-block-start` | Runtime | Logical signed px/percentage alias mapped to top. |
| `inset-inline` | Runtime | Logical signed px/percentage alias mapped to left/right in the current physical model. |
| `inset-inline-end` | Runtime | Logical signed px/percentage alias mapped to right. |
| `inset-inline-start` | Runtime | Logical signed px/percentage alias mapped to left. |
| `interactivity` | Metadata | Stored as computed visual metadata. |
| `interest-delay` | Metadata | Stored as computed visual interaction metadata. |
| `interest-delay-end` | Metadata | Stored as computed visual interaction metadata. |
| `interest-delay-start` | Metadata | Stored as computed visual interaction metadata. |
| `interpolate-size` | Metadata | Stored as computed visual metadata. |
| `isolation` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `justify-content` | Runtime | Initial CBSS runtime surface. |
| `justify-items` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `justify-self` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `justify-tracks` | Metadata | Stored as computed layout metadata. |
| `left` | Runtime | Supports signed px and percentage offsets against the containing content width. |
| `letter-spacing` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `lighting-color` | Metadata | Stores color values as computed vector metadata. |
| `line-break` | No plan |  |
| `line-clamp` | No plan |  |
| `line-height` | Runtime | Initial CBSS runtime surface. |
| `line-height-step` | No plan |  |
| `list-style` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `list-style-image` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `list-style-position` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `list-style-type` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `margin` | Runtime | Initial CBSS runtime surface. |
| `margin-block` | Runtime | Logical alias for vertical margins in the initial horizontal LTR writing mode. |
| `margin-block-end` | Runtime | Logical alias for bottom margin in the initial horizontal LTR writing mode. |
| `margin-block-start` | Runtime | Logical alias for top margin in the initial horizontal LTR writing mode. |
| `margin-bottom` | Runtime | Initial CBSS runtime surface. |
| `margin-inline` | Runtime | Logical alias for horizontal margins in the initial horizontal LTR writing mode. |
| `margin-inline-end` | Runtime | Logical alias for right margin in the initial horizontal LTR writing mode. |
| `margin-inline-start` | Runtime | Logical alias for left margin in the initial horizontal LTR writing mode. |
| `margin-left` | Runtime | Initial CBSS runtime surface. |
| `margin-right` | Runtime | Initial CBSS runtime surface. |
| `margin-top` | Runtime | Initial CBSS runtime surface. |
| `margin-trim` | Metadata | Stored as computed layout metadata. |
| `marker` | Metadata | Stored as computed vector metadata. |
| `marker-end` | No plan |  |
| `marker-mid` | No plan |  |
| `marker-start` | No plan |  |
| `mask` | Metadata | Stored as computed mask metadata; renderer application is a later runtime layer. |
| `mask-border` | Metadata | Stored as computed mask metadata. |
| `mask-border-mode` | Metadata | Stored as computed mask metadata. |
| `mask-border-outset` | Metadata | Stored as computed mask metadata. |
| `mask-border-repeat` | Metadata | Stored as computed mask metadata. |
| `mask-border-slice` | Metadata | Stored as computed mask metadata. |
| `mask-border-source` | Metadata | Stored as computed mask metadata. |
| `mask-border-width` | Metadata | Stored as computed mask metadata. |
| `mask-clip` | Metadata | Stored as computed mask metadata. |
| `mask-composite` | Metadata | Stored as computed mask metadata. |
| `mask-image` | Metadata | Stored as computed mask metadata. |
| `mask-mode` | Metadata | Stored as computed mask metadata. |
| `mask-origin` | Metadata | Stored as computed mask metadata. |
| `mask-position` | Metadata | Stored as computed mask metadata. |
| `mask-repeat` | Metadata | Stored as computed mask metadata. |
| `mask-size` | Metadata | Stored as computed mask metadata. |
| `mask-type` | Metadata | Stored as computed mask metadata. |
| `masonry-auto-flow` | No plan | Full CSS Grid/Masonry is not an initial CBSS layout goal. |
| `math-depth` | No plan |  |
| `math-shift` | No plan |  |
| `math-style` | No plan |  |
| `max-block-size` | Runtime | Logical alias for `max-height` in the initial horizontal LTR writing mode. |
| `max-height` | Runtime | Supports px, percentage, none, and intrinsic sizing values. |
| `max-inline-size` | Runtime | Logical alias for `max-width` in the initial horizontal LTR writing mode. |
| `max-lines` | Runtime | Limits explicit multiline text during layout measurement and paint command emission. |
| `max-width` | Runtime | Supports px, percentage, none, and intrinsic sizing values. |
| `min-block-size` | Runtime | Logical alias for `min-height` in the initial horizontal LTR writing mode. |
| `min-height` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `min-inline-size` | Runtime | Logical alias for `min-width` in the initial horizontal LTR writing mode. |
| `min-width` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `mix-blend-mode` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `object-fit` | Runtime | Initial CBSS runtime surface. |
| `object-position` | Runtime | Initial CBSS runtime surface. |
| `object-view-box` | Metadata | Stored as computed image metadata. |
| `offset` | No plan |  |
| `offset-anchor` | No plan |  |
| `offset-distance` | No plan |  |
| `offset-path` | No plan |  |
| `offset-position` | No plan |  |
| `offset-rotate` | No plan |  |
| `opacity` | Runtime | Initial CBSS runtime surface. |
| `order` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `orphans` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `outline` | Runtime | Emits outline stroke paint commands outside the border box. |
| `outline-color` | Runtime | Emits outline stroke paint commands outside the border box. |
| `outline-offset` | Runtime | Emits outline stroke paint commands outside the border box. |
| `outline-style` | Runtime | Emits outline stroke paint commands outside the border box. |
| `outline-width` | Runtime | Emits outline stroke paint commands outside the border box. |
| `overflow` | Runtime | Supports `visible`, `hidden`, `clip`, `auto`, and `scroll`; retained offsets affect paint and hit testing without relayout. |
| `overflow-anchor` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `overflow-block` | Runtime | `hidden` and `clip` participate in paint clipping. |
| `overflow-clip-box` | Metadata | Stored as computed overflow metadata. |
| `overflow-clip-margin` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `overflow-inline` | Runtime | `hidden` and `clip` participate in paint clipping. |
| `overflow-wrap` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `overflow-x` | Runtime | Resolves and clips the horizontal axis independently; `auto` and `scroll` enable horizontal offset updates. |
| `overflow-y` | Runtime | Resolves and clips the vertical axis independently; `auto` and `scroll` enable vertical offset updates. |
| `overlay` | Metadata | Stored as computed visual metadata. |
| `overscroll-behavior` | Runtime | `contain` and `none` stop nested wheel chaining on both axes at a scroll boundary. |
| `overscroll-behavior-block` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `overscroll-behavior-inline` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `overscroll-behavior-x` | Runtime | `contain` and `none` stop horizontal wheel chaining at a scroll boundary. |
| `overscroll-behavior-y` | Runtime | `contain` and `none` stop vertical wheel chaining at a scroll boundary. |
| `padding` | Runtime | Initial CBSS runtime surface. |
| `padding-block` | Runtime | Logical alias for vertical padding in the initial horizontal LTR writing mode. |
| `padding-block-end` | Runtime | Logical alias for bottom padding in the initial horizontal LTR writing mode. |
| `padding-block-start` | Runtime | Logical alias for top padding in the initial horizontal LTR writing mode. |
| `padding-bottom` | Runtime | Initial CBSS runtime surface. |
| `padding-inline` | Runtime | Logical alias for horizontal padding in the initial horizontal LTR writing mode. |
| `padding-inline-end` | Runtime | Logical alias for right padding in the initial horizontal LTR writing mode. |
| `padding-inline-start` | Runtime | Logical alias for left padding in the initial horizontal LTR writing mode. |
| `padding-left` | Runtime | Initial CBSS runtime surface. |
| `padding-right` | Runtime | Initial CBSS runtime surface. |
| `padding-top` | Runtime | Initial CBSS runtime surface. |
| `page` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `page-break-after` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `page-break-before` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `page-break-inside` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `paint-order` | Metadata | Stored as computed vector metadata. |
| `perspective` | Metadata | Stores length values and `none` as computed transform metadata. |
| `perspective-origin` | Computed | Accepts single-value length/percent/keyword input mirrored to x/y. |
| `place-content` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `place-items` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `place-self` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `pointer-events` | Runtime | `none` removes nodes from hit testing; `auto` keeps normal hit behavior. |
| `position` | Runtime | `static`, `relative`, and `absolute` are implemented; `fixed` and `sticky` produce diagnostics. Positioned-ancestor chaining is still pending. |
| `position-anchor` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `position-area` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `position-try` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `position-try-fallbacks` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `position-try-order` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `position-visibility` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `print-color-adjust` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `quotes` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `r` | Metadata | Stores number and px length values as computed vector geometry metadata. |
| `reading-flow` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `reading-order` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `resize` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `right` | Runtime | Supports signed px and percentage offsets against the containing content width. |
| `rotate` | Runtime | Resolves into the shared 2D affine paint, hit-test, clip, and surface-input contract. |
| `row-gap` | Runtime | Supports px and percentage spacing against the container content height. |
| `ruby-align` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `ruby-merge` | Metadata | Stored as computed text metadata. |
| `ruby-overhang` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `ruby-position` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `rx` | Metadata | Stores number and px length values as computed vector geometry metadata. |
| `ry` | Metadata | Stores number and px length values as computed vector geometry metadata. |
| `scale` | Runtime | Resolves into the shared 2D affine paint, hit-test, clip, and surface-input contract. |
| `scroll-behavior` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `scroll-initial-target` | Metadata | Stored as computed scroll metadata. |
| `scroll-margin` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-block` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-block-end` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-block-start` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-bottom` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-inline` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-inline-end` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-inline-start` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-left` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-right` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-margin-top` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-marker-group` | Metadata | Stored as computed scroll metadata. |
| `scroll-padding` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-block` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-block-end` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-block-start` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-bottom` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-inline` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-inline-end` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-inline-start` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-left` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-right` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-padding-top` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-snap-align` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-snap-coordinate` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `scroll-snap-destination` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `scroll-snap-points-x` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `scroll-snap-points-y` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `scroll-snap-stop` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-snap-type` | No plan | Browser scrolling model property; no initial CBSS support. |
| `scroll-snap-type-x` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `scroll-snap-type-y` | No plan | MDN marks this property obsolete; CBSS should not implement obsolete or effectively deprecated CSS. |
| `scroll-target-group` | Metadata | Stored as computed scroll metadata. |
| `scroll-timeline` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `scroll-timeline-axis` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `scroll-timeline-name` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `scrollbar-color` | Runtime | Applies thumb and track colors to interactive CBSS overlay scrollbars. |
| `scrollbar-gutter` | Runtime | `stable` reserves one scrollbar edge and `stable both-edges` reserves symmetric content space. `auto` keeps overlay behavior. |
| `scrollbar-width` | Runtime | `auto`, `thin`, and `none` control interactive CBSS overlay scrollbar paint and hit geometry. |
| `shape-image-threshold` | No plan |  |
| `shape-margin` | No plan |  |
| `shape-outside` | No plan |  |
| `shape-rendering` | No plan |  |
| `speak-as` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `stop-color` | Metadata | Stores color values as computed vector metadata. |
| `stop-opacity` | Metadata | Stores number values as computed vector metadata. |
| `stroke` | Metadata | Stores color values and keyword metadata for vector drawing. |
| `stroke-color` | Metadata | Stores color values as computed vector metadata. |
| `stroke-dasharray` | Metadata | Stored as computed vector metadata. |
| `stroke-dashoffset` | Metadata | Stores number and px length values as computed vector metadata. |
| `stroke-linecap` | Metadata | Stored as computed vector metadata. |
| `stroke-linejoin` | Metadata | Stored as computed vector metadata. |
| `stroke-miterlimit` | Metadata | Stores number values as computed vector metadata. |
| `stroke-opacity` | Metadata | Stores number values as computed vector metadata. |
| `stroke-width` | Metadata | Stores number and px length values as computed vector metadata. |
| `tab-size` | Metadata | Stored in computed text style; accepts number and px values. |
| `table-layout` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `text-align` | Runtime | Initial CBSS runtime surface. |
| `text-align-last` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `text-anchor` | Metadata | Stored as computed text metadata. |
| `text-autospace` | Metadata | Stored as computed text metadata. |
| `text-box` | Metadata | Stored as computed text metadata. |
| `text-box-edge` | Metadata | Stored as computed text metadata. |
| `text-box-trim` | Metadata | Stored as computed text metadata. |
| `text-combine-upright` | Metadata | Stored as computed text metadata. |
| `text-decoration` | Runtime | Emits text decoration paint commands; advanced browser skip behavior remains partial. |
| `text-decoration-color` | Runtime | Emits text decoration paint commands; advanced browser skip behavior remains partial. |
| `text-decoration-inset` | Runtime | Emits text decoration paint commands; advanced browser skip behavior remains partial. |
| `text-decoration-line` | Runtime | Emits text decoration paint commands; advanced browser skip behavior remains partial. |
| `text-decoration-skip` | Metadata | Stored as computed text metadata. |
| `text-decoration-skip-ink` | Metadata | Stored as computed text metadata. |
| `text-decoration-style` | Runtime | Emits text decoration paint commands; advanced browser skip behavior remains partial. |
| `text-decoration-thickness` | Runtime | Emits text decoration paint commands; advanced browser skip behavior remains partial. |
| `text-emphasis` | Metadata | Stored as computed text metadata. |
| `text-emphasis-color` | Metadata | Stores color values as computed text metadata. |
| `text-emphasis-position` | Metadata | Stored as computed text metadata. |
| `text-emphasis-style` | Metadata | Stored as computed text metadata. |
| `text-indent` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `text-justify` | Metadata | Stored as computed text metadata. |
| `text-orientation` | Metadata | Stored as computed text metadata. |
| `text-overflow` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `text-rendering` | Metadata | Stored as computed text metadata. |
| `text-shadow` | Runtime | Emits shadow text before foreground text; blur is still approximate. |
| `text-size-adjust` | Metadata | Stored as computed text length metadata. |
| `text-spacing-trim` | Metadata | Stored as computed text metadata. |
| `text-transform` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `text-underline-offset` | Runtime | Emits text decoration paint commands; advanced browser skip behavior remains partial. |
| `text-underline-position` | Metadata | Stored as computed text metadata. |
| `text-wrap` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `text-wrap-mode` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `text-wrap-style` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `timeline-scope` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `timeline-trigger` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-activation-range` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-activation-range-end` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-activation-range-start` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-active-range` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-active-range-end` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-active-range-start` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-name` | Metadata | Stored as computed timeline trigger metadata. |
| `timeline-trigger-source` | Metadata | Stored as computed timeline trigger metadata. |
| `top` | Runtime | Supports signed px and percentage offsets against the containing content height. |
| `touch-action` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `transform` | Runtime | Structured 2D transform operations resolve into shared SDL3/headless paint, exact hit-test, clip, and surface-input coordinates. Unsupported raw operations remain diagnostic metadata rather than silently changing paint. |
| `transform-box` | Runtime | Selects the source box used to resolve the 2D transform origin. |
| `transform-origin` | Runtime | Resolves length, percentage, and keyword origins for the shared 2D affine contract. |
| `transform-style` | Metadata | Supports `flat` and `preserve-3d` metadata. |
| `transition` | Metadata | Stored as transition metadata; runtime subsystem is not complete yet. |
| `transition-behavior` | Metadata | Stored as transition metadata; runtime subsystem is not complete yet. |
| `transition-delay` | Runtime | Drives the paint-transition runtime, including negative delay; list cycling remains planned. |
| `transition-duration` | Runtime | Drives paint transitions for the currently supported interpolable properties. |
| `transition-property` | Runtime | Selects `opacity`, `color`, and `background-color`, or `all`; additional values remain planned. |
| `transition-timing-function` | Runtime | Supports the named timing functions, step start/end, and valid cubic Bezier curves for paint transitions. |
| `translate` | Runtime | Resolves into the shared 2D affine paint, hit-test, clip, and surface-input contract. |
| `trigger-scope` | Metadata | Stored as computed timeline trigger metadata. |
| `unicode-bidi` | Metadata | Stored in computed text style; full bidi shaping remains text-engine dependent. |
| `user-select` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `vector-effect` | Metadata | Stored as computed vector metadata. |
| `vertical-align` | Metadata | Stored as computed text metadata. |
| `view-timeline` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `view-timeline-axis` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `view-timeline-inset` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `view-timeline-name` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `view-transition-class` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `view-transition-name` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `view-transition-scope` | Metadata | Stored as computed transition metadata. |
| `visibility` | Runtime | `hidden` suppresses paint and hit behavior. |
| `white-space` | Runtime | Initial CBSS runtime surface. |
| `white-space-collapse` | Metadata | Stored as computed text metadata. |
| `widows` | No plan | Browser, document, generated-content, table, print, or web-specific behavior. |
| `width` | Runtime | Supports px, percentage, auto, and intrinsic sizing values. |
| `will-change` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `word-break` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `word-spacing` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `word-wrap` | Computed | Accepted and resolved into computed style; full runtime behavior may still be partial. |
| `writing-mode` | Metadata | Stored in computed text style; logical property remapping still uses the initial horizontal LTR mode. |
| `x` | Metadata | Stores number and px length values as computed vector geometry metadata. |
| `y` | Metadata | Stores number and px length values as computed vector geometry metadata. |
| `z-index` | Runtime | Initial CBSS runtime surface. |
| `zoom` | Runtime | Supports numeric and percent values; scales the computed layout subtree and returned natural size. |
