# CSS Property Implementation Order

This document ranks every CSS property that is inside the CBSS implementation target.
The intent is to make implementation order explicit: work from the top down unless a specific backend or subsystem needs a different local order.

The first 68 entries correspond to the initial practical UI surface: properties that appear frequently in modern interface design and are needed to make CBSS demos look credible early.
Everything after that is still inside the CBSS target unless it is marked `No plan` in the support matrix.

See [css-property-support.md](css-property-support.md) for the full support matrix and `No plan` rationale.

Implementation should keep these properties loosely coupled. Each property
should have an obvious, localized implementation home so OSS contributors and
local LLMs can work on one property at a time with minimal merge conflicts.
Shared resolver code should stay small and stable; property-specific parsing,
validation, computed-style application, and tests should live near the property
module whenever practical.

## Priority Bands

| Band | Meaning | Count |
| --- | --- | ---: |
| P0 | Initial practical UI surface | 68 |
| P1 | Common modern UI and design fidelity | 150 |
| P2 | Text fidelity | 28 |
| P3 | Advanced visual, layout, scrolling, and input behavior | 119 |
| P4 | Animation, transition, timeline, and motion subsystems | 32 |
| P5 | Vector/SVG-style drawing properties | 29 |
| P6 | Optimization and engine hints | 1 |
| Total target | Runtime + computed + metadata + planned properties | 427 |
| Runtime | Currently affects layout, paint, hit testing, text rendering, or another runtime subsystem | 174 |
| Computed | Accepted and resolved, but full runtime behavior is still partial | 77 |
| Metadata | Preserved for later subsystems or design/tooling interchange | 176 |
| Remaining planned | Not accepted by the current default registry yet | 0 |

As of 2026-08-10, strict runtime completion is **174/427 (40.7%)**.
Runtime plus computed support is **251/427 (58.8%)**. Metadata-only properties
remain implementation work even though the default registry accepts them.

## Ranked Properties

| Rank | Property | Band | Reason |
| ---: | --- | --- | --- |
| 1 | `display` | P0 | Initial practical UI surface |
| 2 | `width` | P0 | Initial practical UI surface |
| 3 | `height` | P0 | Initial practical UI surface |
| 4 | `min-width` | P0 | Initial practical UI surface |
| 5 | `max-width` | P0 | Initial practical UI surface |
| 6 | `min-height` | P0 | Initial practical UI surface |
| 7 | `max-height` | P0 | Initial practical UI surface |
| 8 | `padding` | P0 | Initial practical UI surface |
| 9 | `padding-top` | P0 | Initial practical UI surface |
| 10 | `padding-right` | P0 | Initial practical UI surface |
| 11 | `padding-bottom` | P0 | Initial practical UI surface |
| 12 | `padding-left` | P0 | Initial practical UI surface |
| 13 | `margin` | P0 | Initial practical UI surface |
| 14 | `margin-top` | P0 | Initial practical UI surface |
| 15 | `margin-right` | P0 | Initial practical UI surface |
| 16 | `margin-bottom` | P0 | Initial practical UI surface |
| 17 | `margin-left` | P0 | Initial practical UI surface |
| 18 | `gap` | P0 | Initial practical UI surface |
| 19 | `row-gap` | P0 | Initial practical UI surface |
| 20 | `column-gap` | P0 | Initial practical UI surface |
| 21 | `flex-direction` | P0 | Initial practical UI surface |
| 22 | `flex-grow` | P0 | Initial practical UI surface |
| 23 | `flex-shrink` | P0 | Initial practical UI surface |
| 24 | `flex-basis` | P0 | Initial practical UI surface |
| 25 | `align-items` | P0 | Initial practical UI surface |
| 26 | `justify-content` | P0 | Initial practical UI surface |
| 27 | `background-color` | P0 | Initial practical UI surface |
| 28 | `border-width` | P0 | Initial practical UI surface |
| 29 | `border-style` | P0 | Initial practical UI surface |
| 30 | `border-color` | P0 | Initial practical UI surface |
| 31 | `border` | P0 | Initial practical UI surface |
| 32 | `border-top-width` | P0 | Initial practical UI surface |
| 33 | `border-right-width` | P0 | Initial practical UI surface |
| 34 | `border-bottom-width` | P0 | Initial practical UI surface |
| 35 | `border-left-width` | P0 | Initial practical UI surface |
| 36 | `border-top-color` | P0 | Initial practical UI surface |
| 37 | `border-right-color` | P0 | Initial practical UI surface |
| 38 | `border-bottom-color` | P0 | Initial practical UI surface |
| 39 | `border-left-color` | P0 | Initial practical UI surface |
| 40 | `border-top` | P0 | Initial practical UI surface |
| 41 | `border-right` | P0 | Initial practical UI surface |
| 42 | `border-bottom` | P0 | Initial practical UI surface |
| 43 | `border-left` | P0 | Initial practical UI surface |
| 44 | `border-radius` | P0 | Initial practical UI surface |
| 45 | `border-top-left-radius` | P0 | Initial practical UI surface |
| 46 | `border-top-right-radius` | P0 | Initial practical UI surface |
| 47 | `border-bottom-right-radius` | P0 | Initial practical UI surface |
| 48 | `border-bottom-left-radius` | P0 | Initial practical UI surface |
| 49 | `color` | P0 | Initial practical UI surface |
| 50 | `font-family` | P0 | Initial practical UI surface |
| 51 | `font-size` | P0 | Initial practical UI surface |
| 52 | `font-weight` | P0 | Initial practical UI surface |
| 53 | `font-style` | P0 | Initial practical UI surface |
| 54 | `line-height` | P0 | Initial practical UI surface |
| 55 | `text-align` | P0 | Initial practical UI surface |
| 56 | `white-space` | P0 | Initial practical UI surface |
| 57 | `overflow` | P0 | Initial practical UI surface |
| 58 | `overflow-x` | P0 | Initial practical UI surface |
| 59 | `overflow-y` | P0 | Initial practical UI surface |
| 60 | `position` | P0 | Initial practical UI surface |
| 61 | `top` | P0 | Initial practical UI surface |
| 62 | `right` | P0 | Initial practical UI surface |
| 63 | `bottom` | P0 | Initial practical UI surface |
| 64 | `left` | P0 | Initial practical UI surface |
| 65 | `z-index` | P0 | Initial practical UI surface |
| 66 | `object-fit` | P0 | Initial practical UI surface |
| 67 | `object-position` | P0 | Initial practical UI surface |
| 68 | `opacity` | P0 | Initial practical UI surface |
| 69 | `box-sizing` | P1 | Common modern UI and design fidelity |
| 70 | `aspect-ratio` | P1 | Common modern UI and design fidelity |
| 71 | `visibility` | P1 | Common modern UI and design fidelity |
| 72 | `pointer-events` | P1 | Common modern UI and design fidelity |
| 73 | `cursor` | P1 | Common modern UI and design fidelity |
| 74 | `user-select` | P1 | Common modern UI and design fidelity |
| 75 | `background` | P1 | Common modern UI and design fidelity |
| 76 | `background-image` | P1 | Common modern UI and design fidelity |
| 77 | `background-size` | P1 | Common modern UI and design fidelity |
| 78 | `background-position` | P1 | Common modern UI and design fidelity |
| 79 | `background-position-x` | P1 | Common modern UI and design fidelity |
| 80 | `background-position-y` | P1 | Common modern UI and design fidelity |
| 81 | `background-repeat` | P1 | Common modern UI and design fidelity |
| 82 | `background-clip` | P1 | Common modern UI and design fidelity |
| 83 | `background-origin` | P1 | Common modern UI and design fidelity |
| 84 | `background-attachment` | P1 | Common modern UI and design fidelity |
| 85 | `background-blend-mode` | P1 | Common modern UI and design fidelity |
| 86 | `box-shadow` | P1 | Common modern UI and design fidelity |
| 87 | `outline` | P1 | Common modern UI and design fidelity |
| 88 | `outline-width` | P1 | Common modern UI and design fidelity |
| 89 | `outline-style` | P1 | Common modern UI and design fidelity |
| 90 | `outline-color` | P1 | Common modern UI and design fidelity |
| 91 | `outline-offset` | P1 | Common modern UI and design fidelity |
| 92 | `text-overflow` | P1 | Common modern UI and design fidelity |
| 93 | `overflow-wrap` | P1 | Common modern UI and design fidelity |
| 94 | `word-break` | P1 | Common modern UI and design fidelity |
| 95 | `word-wrap` | P1 | Common modern UI and design fidelity |
| 96 | `hyphens` | P1 | Common modern UI and design fidelity |
| 97 | `letter-spacing` | P1 | Common modern UI and design fidelity |
| 98 | `word-spacing` | P1 | Common modern UI and design fidelity |
| 99 | `text-decoration` | P1 | Common modern UI and design fidelity |
| 100 | `text-decoration-line` | P1 | Common modern UI and design fidelity |
| 101 | `text-decoration-color` | P1 | Common modern UI and design fidelity |
| 102 | `text-decoration-style` | P1 | Common modern UI and design fidelity |
| 103 | `text-decoration-thickness` | P1 | Common modern UI and design fidelity |
| 104 | `text-shadow` | P1 | Common modern UI and design fidelity |
| 105 | `text-transform` | P1 | Common modern UI and design fidelity |
| 106 | `text-indent` | P1 | Common modern UI and design fidelity |
| 107 | `text-wrap` | P1 | Common modern UI and design fidelity |
| 108 | `text-wrap-mode` | P1 | Common modern UI and design fidelity |
| 109 | `text-wrap-style` | P1 | Common modern UI and design fidelity |
| 110 | `caret-color` | P1 | Common modern UI and design fidelity |
| 111 | `accent-color` | P1 | Common modern UI and design fidelity |
| 112 | `resize` | P1 | Common modern UI and design fidelity |
| 113 | `order` | P1 | Common modern UI and design fidelity |
| 114 | `align-content` | P1 | Common modern UI and design fidelity |
| 115 | `align-self` | P1 | Common modern UI and design fidelity |
| 116 | `justify-items` | P1 | Common modern UI and design fidelity |
| 117 | `justify-self` | P1 | Common modern UI and design fidelity |
| 118 | `place-content` | P1 | Common modern UI and design fidelity |
| 119 | `place-items` | P1 | Common modern UI and design fidelity |
| 120 | `place-self` | P1 | Common modern UI and design fidelity |
| 121 | `inset` | P1 | Common modern UI and design fidelity |
| 122 | `inset-block` | P1 | Common modern UI and design fidelity |
| 123 | `inset-block-start` | P1 | Common modern UI and design fidelity |
| 124 | `inset-block-end` | P1 | Common modern UI and design fidelity |
| 125 | `inset-inline` | P1 | Common modern UI and design fidelity |
| 126 | `inset-inline-start` | P1 | Common modern UI and design fidelity |
| 127 | `inset-inline-end` | P1 | Common modern UI and design fidelity |
| 128 | `inline-size` | P1 | Common modern UI and design fidelity |
| 129 | `block-size` | P1 | Common modern UI and design fidelity |
| 130 | `min-inline-size` | P1 | Common modern UI and design fidelity |
| 131 | `max-inline-size` | P1 | Common modern UI and design fidelity |
| 132 | `min-block-size` | P1 | Common modern UI and design fidelity |
| 133 | `max-block-size` | P1 | Common modern UI and design fidelity |
| 134 | `padding-inline` | P1 | Common modern UI and design fidelity |
| 135 | `padding-inline-start` | P1 | Common modern UI and design fidelity |
| 136 | `padding-inline-end` | P1 | Common modern UI and design fidelity |
| 137 | `padding-block` | P1 | Common modern UI and design fidelity |
| 138 | `padding-block-start` | P1 | Common modern UI and design fidelity |
| 139 | `padding-block-end` | P1 | Common modern UI and design fidelity |
| 140 | `margin-inline` | P1 | Common modern UI and design fidelity |
| 141 | `margin-inline-start` | P1 | Common modern UI and design fidelity |
| 142 | `margin-inline-end` | P1 | Common modern UI and design fidelity |
| 143 | `margin-block` | P1 | Common modern UI and design fidelity |
| 144 | `margin-block-start` | P1 | Common modern UI and design fidelity |
| 145 | `margin-block-end` | P1 | Common modern UI and design fidelity |
| 146 | `border-inline` | P1 | Common modern UI and design fidelity |
| 147 | `border-inline-width` | P1 | Common modern UI and design fidelity |
| 148 | `border-inline-style` | P1 | Common modern UI and design fidelity |
| 149 | `border-inline-color` | P1 | Common modern UI and design fidelity |
| 150 | `border-inline-start` | P1 | Common modern UI and design fidelity |
| 151 | `border-inline-start-width` | P1 | Common modern UI and design fidelity |
| 152 | `border-inline-start-style` | P1 | Common modern UI and design fidelity |
| 153 | `border-inline-start-color` | P1 | Common modern UI and design fidelity |
| 154 | `border-inline-end` | P1 | Common modern UI and design fidelity |
| 155 | `border-inline-end-width` | P1 | Common modern UI and design fidelity |
| 156 | `border-inline-end-style` | P1 | Common modern UI and design fidelity |
| 157 | `border-inline-end-color` | P1 | Common modern UI and design fidelity |
| 158 | `border-block` | P1 | Common modern UI and design fidelity |
| 159 | `border-block-width` | P1 | Common modern UI and design fidelity |
| 160 | `border-block-style` | P1 | Common modern UI and design fidelity |
| 161 | `border-block-color` | P1 | Common modern UI and design fidelity |
| 162 | `border-block-start` | P1 | Common modern UI and design fidelity |
| 163 | `border-block-start-width` | P1 | Common modern UI and design fidelity |
| 164 | `border-block-start-style` | P1 | Common modern UI and design fidelity |
| 165 | `border-block-start-color` | P1 | Common modern UI and design fidelity |
| 166 | `border-block-end` | P1 | Common modern UI and design fidelity |
| 167 | `border-block-end-width` | P1 | Common modern UI and design fidelity |
| 168 | `border-block-end-style` | P1 | Common modern UI and design fidelity |
| 169 | `border-block-end-color` | P1 | Common modern UI and design fidelity |
| 170 | `border-start-start-radius` | P1 | Common modern UI and design fidelity |
| 171 | `border-start-end-radius` | P1 | Common modern UI and design fidelity |
| 172 | `border-end-start-radius` | P1 | Common modern UI and design fidelity |
| 173 | `border-end-end-radius` | P1 | Common modern UI and design fidelity |
| 174 | `transform` | P1 | Common modern UI and design fidelity |
| 175 | `transform-origin` | P1 | Common modern UI and design fidelity |
| 176 | `transform-box` | P1 | Common modern UI and design fidelity |
| 177 | `transform-style` | P1 | Common modern UI and design fidelity |
| 178 | `translate` | P1 | Common modern UI and design fidelity |
| 179 | `rotate` | P1 | Common modern UI and design fidelity |
| 180 | `scale` | P1 | Common modern UI and design fidelity |
| 181 | `filter` | P1 | Common modern UI and design fidelity |
| 182 | `backdrop-filter` | P1 | Common modern UI and design fidelity |
| 183 | `mix-blend-mode` | P1 | Common modern UI and design fidelity |
| 184 | `isolation` | P1 | Common modern UI and design fidelity |
| 185 | `scrollbar-width` | P1 | Common modern UI and design fidelity |
| 186 | `scrollbar-color` | P1 | Common modern UI and design fidelity |
| 187 | `scrollbar-gutter` | P1 | Common modern UI and design fidelity |
| 188 | `scroll-behavior` | P1 | Common modern UI and design fidelity |
| 189 | `overscroll-behavior` | P1 | Common modern UI and design fidelity |
| 190 | `overscroll-behavior-x` | P1 | Common modern UI and design fidelity |
| 191 | `overscroll-behavior-y` | P1 | Common modern UI and design fidelity |
| 192 | `overflow-anchor` | P1 | Common modern UI and design fidelity |
| 193 | `overflow-clip-margin` | P1 | Common modern UI and design fidelity |
| 194 | `font` | P1 | Common modern UI and design fidelity |
| 195 | `font-feature-settings` | P1 | Common modern UI and design fidelity |
| 196 | `font-kerning` | P1 | Common modern UI and design fidelity |
| 197 | `font-optical-sizing` | P1 | Common modern UI and design fidelity |
| 198 | `font-size-adjust` | P1 | Common modern UI and design fidelity |
| 199 | `font-variation-settings` | P1 | Common modern UI and design fidelity |
| 200 | `font-variant` | P1 | Common modern UI and design fidelity |
| 201 | `font-variant-ligatures` | P1 | Common modern UI and design fidelity |
| 202 | `font-variant-caps` | P1 | Common modern UI and design fidelity |
| 203 | `font-variant-numeric` | P1 | Common modern UI and design fidelity |
| 204 | `font-variant-east-asian` | P1 | Common modern UI and design fidelity |
| 205 | `font-variant-position` | P1 | Common modern UI and design fidelity |
| 206 | `font-variant-alternates` | P1 | Common modern UI and design fidelity |
| 207 | `font-variant-emoji` | P1 | Common modern UI and design fidelity |
| 208 | `font-language-override` | P1 | Common modern UI and design fidelity |
| 209 | `font-palette` | P1 | Common modern UI and design fidelity |
| 210 | `font-synthesis` | P1 | Common modern UI and design fidelity |
| 211 | `font-synthesis-small-caps` | P1 | Common modern UI and design fidelity |
| 212 | `font-synthesis-style` | P1 | Common modern UI and design fidelity |
| 213 | `font-synthesis-weight` | P1 | Common modern UI and design fidelity |
| 214 | `direction` | P1 | Common modern UI and design fidelity |
| 215 | `unicode-bidi` | P1 | Common modern UI and design fidelity |
| 216 | `writing-mode` | P1 | Common modern UI and design fidelity |
| 217 | `tab-size` | P1 | Common modern UI and design fidelity |
| 218 | `font-stretch` | P1 | Common modern UI and design fidelity |
| 219 | `animation` | P4 | Animation subsystem |
| 220 | `animation-name` | P4 | Animation subsystem |
| 221 | `animation-duration` | P4 | Animation subsystem |
| 222 | `animation-delay` | P4 | Animation subsystem |
| 223 | `animation-timing-function` | P4 | Animation subsystem |
| 224 | `animation-iteration-count` | P4 | Animation subsystem |
| 225 | `animation-direction` | P4 | Animation subsystem |
| 226 | `animation-fill-mode` | P4 | Animation subsystem |
| 227 | `animation-play-state` | P4 | Animation subsystem |
| 228 | `animation-composition` | P4 | Animation subsystem |
| 229 | `animation-range` | P4 | Animation subsystem |
| 230 | `animation-range-start` | P4 | Animation subsystem |
| 231 | `animation-range-end` | P4 | Animation subsystem |
| 232 | `animation-timeline` | P4 | Animation subsystem |
| 233 | `animation-trigger` | P4 | Animation subsystem |
| 234 | `transition` | P4 | Animation subsystem |
| 235 | `transition-property` | P4 | Animation subsystem |
| 236 | `transition-duration` | P4 | Animation subsystem |
| 237 | `transition-delay` | P4 | Animation subsystem |
| 238 | `transition-timing-function` | P4 | Animation subsystem |
| 239 | `transition-behavior` | P4 | Animation subsystem |
| 240 | `alignment-baseline` | P2 | Text and vector alignment |
| 241 | `baseline-shift` | P2 | Text and vector alignment |
| 242 | `dominant-baseline` | P2 | Text and vector alignment |
| 243 | `font-smooth` | P2 | Text fidelity |
| 244 | `font-synthesis-position` | P2 | Text fidelity |
| 245 | `font-width` | P2 | Text fidelity |
| 246 | `text-align-last` | P2 | Text fidelity |
| 247 | `text-anchor` | P2 | Text fidelity |
| 248 | `text-autospace` | P2 | Text fidelity |
| 249 | `text-box` | P2 | Text fidelity |
| 250 | `text-box-edge` | P2 | Text fidelity |
| 251 | `text-box-trim` | P2 | Text fidelity |
| 252 | `text-combine-upright` | P2 | Text fidelity |
| 253 | `text-decoration-inset` | P2 | Text fidelity |
| 254 | `text-decoration-skip` | P2 | Text fidelity |
| 255 | `text-decoration-skip-ink` | P2 | Text fidelity |
| 256 | `text-emphasis` | P2 | Text fidelity |
| 257 | `text-emphasis-color` | P2 | Text fidelity |
| 258 | `text-emphasis-position` | P2 | Text fidelity |
| 259 | `text-emphasis-style` | P2 | Text fidelity |
| 260 | `text-justify` | P2 | Text fidelity |
| 261 | `text-orientation` | P2 | Text fidelity |
| 262 | `text-rendering` | P2 | Text fidelity |
| 263 | `text-size-adjust` | P2 | Text fidelity |
| 264 | `text-spacing-trim` | P2 | Text fidelity |
| 265 | `text-underline-offset` | P2 | Text fidelity |
| 266 | `text-underline-position` | P2 | Text fidelity |
| 267 | `white-space-collapse` | P2 | Text fidelity |
| 268 | `align-tracks` | P3 | Later visual or layout fidelity |
| 269 | `appearance` | P3 | Later visual or layout fidelity |
| 270 | `backface-visibility` | P3 | Later visual or layout fidelity |
| 271 | `baseline-source` | P3 | Later visual or layout fidelity |
| 272 | `border-bottom-style` | P3 | Later visual or layout fidelity |
| 273 | `border-collapse` | P3 | Later visual or layout fidelity |
| 274 | `border-image` | P3 | Advanced border rendering |
| 275 | `border-image-outset` | P3 | Advanced border rendering |
| 276 | `border-image-repeat` | P3 | Advanced border rendering |
| 277 | `border-image-slice` | P3 | Advanced border rendering |
| 278 | `border-image-source` | P3 | Advanced border rendering |
| 279 | `border-image-width` | P3 | Advanced border rendering |
| 280 | `border-left-style` | P3 | Later visual or layout fidelity |
| 281 | `border-right-style` | P3 | Later visual or layout fidelity |
| 282 | `border-shape` | P3 | Later visual or layout fidelity |
| 283 | `border-spacing` | P3 | Later visual or layout fidelity |
| 284 | `border-top-style` | P3 | Later visual or layout fidelity |
| 285 | `box-align` | P3 | Later visual or layout fidelity |
| 286 | `box-decoration-break` | P3 | Later visual or layout fidelity |
| 287 | `box-direction` | P3 | Later visual or layout fidelity |
| 288 | `box-flex` | P3 | Later visual or layout fidelity |
| 289 | `box-flex-group` | P3 | Later visual or layout fidelity |
| 290 | `box-lines` | P3 | Later visual or layout fidelity |
| 291 | `box-ordinal-group` | P3 | Later visual or layout fidelity |
| 292 | `box-orient` | P3 | Later visual or layout fidelity |
| 293 | `box-pack` | P3 | Later visual or layout fidelity |
| 294 | `caret` | P3 | Later visual or layout fidelity |
| 295 | `caret-animation` | P3 | Later visual or layout fidelity |
| 296 | `caret-shape` | P3 | Later visual or layout fidelity |
| 297 | `clip-path` | P3 | Advanced clipping and masking |
| 298 | `clip-rule` | P3 | Advanced clipping and masking |
| 299 | `column-count` | P3 | Later visual or layout fidelity |
| 300 | `column-fill` | P3 | Later visual or layout fidelity |
| 301 | `column-height` | P3 | Later visual or layout fidelity |
| 302 | `column-rule` | P3 | Later visual or layout fidelity |
| 303 | `column-rule-color` | P3 | Later visual or layout fidelity |
| 304 | `column-rule-style` | P3 | Later visual or layout fidelity |
| 305 | `column-rule-width` | P3 | Later visual or layout fidelity |
| 306 | `column-span` | P3 | Later visual or layout fidelity |
| 307 | `column-width` | P3 | Later visual or layout fidelity |
| 308 | `column-wrap` | P3 | Later visual or layout fidelity |
| 309 | `columns` | P3 | Later visual or layout fidelity |
| 310 | `content-visibility` | P3 | Later visual or layout fidelity |
| 311 | `corner-block-end-shape` | P3 | Later visual or layout fidelity |
| 312 | `corner-block-start-shape` | P3 | Later visual or layout fidelity |
| 313 | `corner-bottom-left-shape` | P3 | Later visual or layout fidelity |
| 314 | `corner-bottom-right-shape` | P3 | Later visual or layout fidelity |
| 315 | `corner-bottom-shape` | P3 | Later visual or layout fidelity |
| 316 | `corner-end-end-shape` | P3 | Later visual or layout fidelity |
| 317 | `corner-end-start-shape` | P3 | Later visual or layout fidelity |
| 318 | `corner-inline-end-shape` | P3 | Later visual or layout fidelity |
| 319 | `corner-inline-start-shape` | P3 | Later visual or layout fidelity |
| 320 | `corner-left-shape` | P3 | Later visual or layout fidelity |
| 321 | `corner-right-shape` | P3 | Later visual or layout fidelity |
| 322 | `corner-shape` | P3 | Later visual or layout fidelity |
| 323 | `corner-start-end-shape` | P3 | Later visual or layout fidelity |
| 324 | `corner-start-start-shape` | P3 | Later visual or layout fidelity |
| 325 | `corner-top-left-shape` | P3 | Later visual or layout fidelity |
| 326 | `corner-top-right-shape` | P3 | Later visual or layout fidelity |
| 327 | `corner-top-shape` | P3 | Later visual or layout fidelity |
| 328 | `dynamic-range-limit` | P3 | Later visual or layout fidelity |
| 329 | `field-sizing` | P3 | Later visual or layout fidelity |
| 330 | `flex` | P3 | Later visual or layout fidelity |
| 331 | `flex-flow` | P3 | Later visual or layout fidelity |
| 332 | `flex-wrap` | P3 | Later visual or layout fidelity |
| 333 | `forced-color-adjust` | P3 | Later visual or layout fidelity |
| 334 | `hanging-punctuation` | P3 | Later visual or layout fidelity |
| 335 | `hyphenate-character` | P3 | Later visual or layout fidelity |
| 336 | `hyphenate-limit-chars` | P3 | Later visual or layout fidelity |
| 337 | `image-orientation` | P3 | Later visual or layout fidelity |
| 338 | `image-rendering` | P3 | Later visual or layout fidelity |
| 339 | `image-resolution` | P3 | Later visual or layout fidelity |
| 340 | `initial-letter` | P3 | Later visual or layout fidelity |
| 341 | `initial-letter-align` | P3 | Later visual or layout fidelity |
| 342 | `interactivity` | P3 | Later visual or layout fidelity |
| 343 | `interest-delay` | P3 | Later visual or layout fidelity |
| 344 | `interest-delay-end` | P3 | Later visual or layout fidelity |
| 345 | `interest-delay-start` | P3 | Later visual or layout fidelity |
| 346 | `interpolate-size` | P3 | Later visual or layout fidelity |
| 347 | `justify-tracks` | P3 | Later visual or layout fidelity |
| 348 | `margin-trim` | P3 | Later visual or layout fidelity |
| 349 | `mask` | P3 | Advanced clipping and masking |
| 350 | `mask-border` | P3 | Advanced clipping and masking |
| 351 | `mask-border-mode` | P3 | Advanced clipping and masking |
| 352 | `mask-border-outset` | P3 | Advanced clipping and masking |
| 353 | `mask-border-repeat` | P3 | Advanced clipping and masking |
| 354 | `mask-border-slice` | P3 | Advanced clipping and masking |
| 355 | `mask-border-source` | P3 | Advanced clipping and masking |
| 356 | `mask-border-width` | P3 | Advanced clipping and masking |
| 357 | `mask-clip` | P3 | Advanced clipping and masking |
| 358 | `mask-composite` | P3 | Advanced clipping and masking |
| 359 | `mask-image` | P3 | Advanced clipping and masking |
| 360 | `mask-mode` | P3 | Advanced clipping and masking |
| 361 | `mask-origin` | P3 | Advanced clipping and masking |
| 362 | `mask-position` | P3 | Advanced clipping and masking |
| 363 | `mask-repeat` | P3 | Advanced clipping and masking |
| 364 | `mask-size` | P3 | Advanced clipping and masking |
| 365 | `mask-type` | P3 | Advanced clipping and masking |
| 366 | `max-lines` | P3 | Later visual or layout fidelity |
| 367 | `object-view-box` | P3 | Later visual or layout fidelity |
| 368 | `overflow-block` | P3 | Later visual or layout fidelity |
| 369 | `overflow-clip-box` | P3 | Later visual or layout fidelity |
| 370 | `overflow-inline` | P3 | Later visual or layout fidelity |
| 371 | `overlay` | P3 | Later visual or layout fidelity |
| 372 | `overscroll-behavior-block` | P3 | Scrolling and viewport behavior |
| 373 | `overscroll-behavior-inline` | P3 | Scrolling and viewport behavior |
| 374 | `paint-order` | P3 | Later visual or layout fidelity |
| 375 | `perspective` | P3 | Later visual or layout fidelity |
| 376 | `perspective-origin` | P3 | Later visual or layout fidelity |
| 377 | `print-color-adjust` | P3 | Later visual or layout fidelity |
| 378 | `reading-flow` | P3 | Later visual or layout fidelity |
| 379 | `reading-order` | P3 | Later visual or layout fidelity |
| 380 | `ruby-merge` | P3 | Later visual or layout fidelity |
| 381 | `scroll-initial-target` | P3 | Scrolling and viewport behavior |
| 382 | `scroll-marker-group` | P3 | Scrolling and viewport behavior |
| 383 | `scroll-target-group` | P3 | Scrolling and viewport behavior |
| 384 | `touch-action` | P3 | Input behavior |
| 385 | `vertical-align` | P3 | Later visual or layout fidelity |
| 386 | `zoom` | P3 | Later visual or layout fidelity |
| 387 | `timeline-trigger` | P4 | Timeline and transition subsystem |
| 388 | `timeline-trigger-activation-range` | P4 | Timeline and transition subsystem |
| 389 | `timeline-trigger-activation-range-end` | P4 | Timeline and transition subsystem |
| 390 | `timeline-trigger-activation-range-start` | P4 | Timeline and transition subsystem |
| 391 | `timeline-trigger-active-range` | P4 | Timeline and transition subsystem |
| 392 | `timeline-trigger-active-range-end` | P4 | Timeline and transition subsystem |
| 393 | `timeline-trigger-active-range-start` | P4 | Timeline and transition subsystem |
| 394 | `timeline-trigger-name` | P4 | Timeline and transition subsystem |
| 395 | `timeline-trigger-source` | P4 | Timeline and transition subsystem |
| 396 | `trigger-scope` | P4 | Timeline and transition subsystem |
| 397 | `view-transition-scope` | P4 | Timeline and transition subsystem |
| 398 | `color-interpolation-filters` | P5 | Vector/SVG-style drawing |
| 399 | `color-scheme` | P5 | Vector/SVG-style drawing |
| 400 | `cx` | P5 | Vector/SVG-style drawing |
| 401 | `cy` | P5 | Vector/SVG-style drawing |
| 402 | `d` | P5 | Vector/SVG-style drawing |
| 403 | `fill` | P5 | Vector/SVG-style drawing |
| 404 | `fill-opacity` | P5 | Vector/SVG-style drawing |
| 405 | `fill-rule` | P5 | Vector/SVG-style drawing |
| 406 | `flood-color` | P5 | Vector/SVG-style drawing |
| 407 | `flood-opacity` | P5 | Vector/SVG-style drawing |
| 408 | `lighting-color` | P5 | Vector/SVG-style drawing |
| 409 | `marker` | P5 | Vector/SVG-style drawing |
| 410 | `r` | P5 | Vector/SVG-style drawing |
| 411 | `rx` | P5 | Vector/SVG-style drawing |
| 412 | `ry` | P5 | Vector/SVG-style drawing |
| 413 | `stop-color` | P5 | Vector/SVG-style drawing |
| 414 | `stop-opacity` | P5 | Vector/SVG-style drawing |
| 415 | `stroke` | P5 | Vector/SVG-style drawing |
| 416 | `stroke-color` | P5 | Vector/SVG-style drawing |
| 417 | `stroke-dasharray` | P5 | Vector/SVG-style drawing |
| 418 | `stroke-dashoffset` | P5 | Vector/SVG-style drawing |
| 419 | `stroke-linecap` | P5 | Vector/SVG-style drawing |
| 420 | `stroke-linejoin` | P5 | Vector/SVG-style drawing |
| 421 | `stroke-miterlimit` | P5 | Vector/SVG-style drawing |
| 422 | `stroke-opacity` | P5 | Vector/SVG-style drawing |
| 423 | `stroke-width` | P5 | Vector/SVG-style drawing |
| 424 | `vector-effect` | P5 | Vector/SVG-style drawing |
| 425 | `x` | P5 | Vector/SVG-style drawing |
| 426 | `y` | P5 | Vector/SVG-style drawing |
| 427 | `will-change` | P6 | Optimization hint |
