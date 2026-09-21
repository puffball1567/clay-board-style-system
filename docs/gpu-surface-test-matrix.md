# GPU Surface Quality Matrix

Status: `Deterministic contract coverage implemented; opt-in Linux real-GPU
pixel fixture implemented; broader hardware qualification pending`

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
| Real compositor | direct Texture and RenderTarget through the same-host offscreen compositor; rectangular UV crop, straight/premultiplied/opaque alpha, opacity, rounded mask pixels, latest-ready coalescing, top-left row orientation, logical target origins, two-times pixel scale and ordered surface composition | unsupported adapter falls back or fails closed | resize, transform and final-window stacking | Opt-in Linux OpenGL pixel fixture; broader qualification pending |
| Hardware stress | sustained bounded presentation | device loss, cancellation, teardown races | multiple surfaces and GPU-memory pressure | Pending real-GPU CI |

The primary executable matrix lives in
`tests/runtime/test_gpu_host.nim`. The same test unit is included in ARC, ORC,
ASan, UBSan, LSan, and Valgrind jobs where the toolchain supports them. The
optional bgfx jobs additionally compile the adapter and run its NOOP resource
integration. The test observes Texture and RenderTarget attachment resolution,
callback metadata, rejection paths, and ARC/ORC teardown. NOOP validates backend
calls and ownership, but it does not count as visible pixel conformance.

`nimble testBgfxPixels` is the opt-in real-renderer lane. It builds the pinned
bgfx sources, compiles the standard compositor shaders with official `shaderc`,
draws into compositor-owned offscreen targets, reads RGBA pixels back
asynchronously, and checks Texture/RenderTarget sources, UV cropping,
rectangular clipping, all three alpha modes, opacity, rounded masks,
latest-ready surface coalescing, row orientation for both CPU-uploaded
textures and RenderTarget output, logical target origins, two-times pixel
scale, and deterministic draw ordering. It deliberately remains
outside the default hosted CI matrix because a runner without a qualified GPU
or software OpenGL stack cannot provide meaningful pixel evidence.

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
