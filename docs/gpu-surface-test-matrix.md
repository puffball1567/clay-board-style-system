# GPU Surface Quality Matrix

Status: `Deterministic contract coverage implemented; Linux Mesa OpenGL pixel
fixture runs in CI under ARC and ORC; broader hardware qualification pending`

This matrix is the release-quality contract for `GpuDirectSurface` and
`GpuDisplaySurface`. A row is complete only when its normal, failure, and edge
behavior is deterministic under ARC and ORC. Backend-neutral rows run in the
ordinary test suite. Hardware rows run only in explicitly qualified real-GPU
jobs and must not be replaced by a mock-only success.

| Area | Normal cases | Failure cases | Edge cases | Coverage |
| --- | --- | --- | --- | --- |
| Configuration | defaults, 2 and 8 buffers, maximum texture size | zero dimensions, invalid buffer count, oversized label | exact label and texture limits | Automated |
| Capability negotiation | Texture, RenderTarget, compute output, supported formats and alpha modes; explicit qualified bgfx profile reaches retained direct submission | missing feature, unsupported format or alpha mode, inconsistent backend/profile/compositor declaration; typed limitation reasons drive fallback | independent Texture/RenderTarget support; buffer limits 2 and 8; exact, exceeded, and combined direct-display limits | Automated |
| Queueing | queue, complete, collect, acquire, release | duplicate resource, foreign namespace, wrong shape/format/usage/token | queue saturation and recovery | Automated |
| Frame selection | ordered publication and latest-ready coalescing | incomplete frame cannot publish | thousands of monotonic revisions | Automated |
| Lifetime | presented resources stay retained | write, destroy, namespace close, host close while retained | multiple leases and retirement after last release | Automated |
| Shutdown | close an idle or completed surface | incomplete work and active leases block close | completed pending work closes without collect; repeated close is harmless | Automated |
| Device loss | stale frames disappear and resources invalidate | stale generation cannot queue or acquire | loss with pending/presented resources | Automated mock; real GPU pending |
| Direct compositor | all compositor statuses propagate; SDL normal, text and layered paths invoke the bridge; standard same-host draw accepts retained Texture and RenderTarget sources across producer/compositor namespaces; bgfx resolves both to sampled textures; nested rounded clips use the masked pipeline; typed compositor-owned offscreen RenderTargets receive direct passes | callback exception releases lease; unretained source, duplicate stage, detached host, wrong provider, mismatched resource tag, invalid attachment, malformed masks, incomplete masked materials, foreign/stale offscreen targets, dimension mismatch, and source/target feedback fail closed | no active frame returns retry; rectangular clipping crops viewport and UV; exactly eight rounded masks are accepted and the ninth fails closed; nil compositor or submit, mismatched backend API; per-frame bounded status counters | Automated |
| Native-window data | X11, Wayland, Win32 and Cocoa map to typed bgfx platform data | missing window or required display fails before bgfx initialization | display is optional only for Win32 and Cocoa; non-Wayland systems use the default bgfx handle type | Automated portable mapping on Linux, Windows and macOS; SDL3 acquisition compiled on configured Linux backend |
| Readback fallback | R8, RGBA8 and BGRA8 paths | missing copy/readback support, unsupported float format | byte limit, label limit, dimension multiplication overflow | Automated |
| UI integration | standalone, underlay and overlay layout/paint | foreign or invalid owner, closed surface | safety styles override injected pointer/z-index values | Automated |
| Invalidation | completed frame invalidates paint owner | incomplete/failed collect does not invalidate | no style/layout invalidation | Automated |
| Memory models | deterministic ownership and teardown | sanitizer/Valgrind failures are fatal | ARC and ORC | Automated CI |
| Real compositor | direct Texture and RenderTarget through the same-host offscreen compositor; rectangular UV crop, straight/premultiplied/opaque alpha, opacity, rounded mask pixels, latest-ready coalescing, top-left row orientation, logical target origins, two-times pixel scale, ordered surface composition, a window pass and offscreen pixels after a native-window resize | unsupported adapter falls back or fails closed | transform and final-window pixel stacking | Linux Mesa OpenGL pixel CI under ARC and ORC; broader qualification pending |
| Partial texture upload pixels | tight and padded updates preserve row colors and untouched columns | malformed spans are rejected in the adapter contract matrix | unaligned 7-byte pitch; pitches 65534, 65535, 65536; a single row with UINT32_MAX stride | Linux Mesa OpenGL pixel CI under ARC and ORC |
| Hardware stress | sustained bounded presentation | device loss, cancellation, teardown races | multiple surfaces and GPU-memory pressure | Pending real-GPU CI |

The primary executable matrix lives in
`tests/runtime/test_gpu_host.nim`. The same test unit is included in ARC, ORC,
ASan, UBSan, LSan, and Valgrind jobs where the toolchain supports them. The
optional bgfx jobs additionally compile the adapter and run its NOOP resource
integration. The test observes Texture and RenderTarget attachment resolution,
callback metadata, rejection paths, and ARC/ORC teardown. NOOP validates backend
calls and ownership, but it does not count as visible pixel conformance.

`nimble testBgfxPixels` is the real-renderer lane. It builds the pinned
bgfx sources, compiles the standard compositor shaders with official `shaderc`,
draws into compositor-owned offscreen targets, reads RGBA pixels back
asynchronously, and checks Texture/RenderTarget sources, UV cropping,
rectangular clipping, all three alpha modes, opacity, rounded masks,
latest-ready surface coalescing, row orientation for both CPU-uploaded
textures and RenderTarget output, logical target origins, two-times pixel
scale, deterministic draw ordering, a direct window pass, and retained-source
composition after a native-window resize. Padded partial uploads additionally
check transferred row colors and untouched pixels through asynchronous readback.
The Linux bgfx CI job runs this fixture under both ARC and ORC with Xvfb,
Mesa software OpenGL, and the bundled SDL3 runtime. This exercises the actual
OpenGL renderer and compiled shaders, not a mock or NOOP renderer. It does not
qualify physical GPU drivers, other graphics APIs, or mixed SDL/GPU layers.

Local runs default to system SDL3 through `pkg-config`. Set
`CBSS_GPU_PIXEL_SDL_MODE=bundled` to use the repository runtime instead.
Both modes run ARC and ORC; missing prerequisites and pixel mismatches fail
the job rather than silently skipping conformance.

## Real-GPU Release Gate

The same-host draw path is implemented, but the production direct compositor is
not complete until a qualified Linux GPU fixture proves all of the following:

- one SDL window, one GPU device/queue, and one presentation owner;
- direct Texture and RenderTarget output without CPU readback;
- deterministic pixels for rectangular and rounded clip, opacity, transform, stacking, alpha mode,
  resize, and DPI changes;
- bounded double/triple buffering under producer pressure;
- safe device loss, cancellation, namespace teardown, and shutdown ordering;
- multiple independent display surfaces without cross-surface corruption; and
- an explicit fallback or diagnostic for every unsupported capability.

Hardware-specific failures must be reported separately from contract-test,
compiler, linker, and sanitizer-runtime failures.
