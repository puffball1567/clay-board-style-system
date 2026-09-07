# GPU Surface Quality Matrix

Status: `Deterministic contract coverage implemented; visible real-GPU coverage pending`

This matrix is the release-quality contract for `GpuDirectSurface` and
`GpuDisplaySurface`. A row is complete only when its normal, failure, and edge
behavior is deterministic under ARC and ORC. Backend-neutral rows run in the
ordinary test suite. Hardware rows run only in explicitly qualified real-GPU
jobs and must not be replaced by a mock-only success.

| Area | Normal cases | Failure cases | Edge cases | Coverage |
| --- | --- | --- | --- | --- |
| Configuration | defaults, 2 and 8 buffers, maximum texture size | zero dimensions, invalid buffer count, oversized label | exact label and texture limits | Automated |
| Capability negotiation | Texture, RenderTarget, compute output, supported formats | missing feature, unsupported format, inconsistent backend declaration | independent Texture/RenderTarget support | Automated |
| Queueing | queue, complete, collect, acquire, release | duplicate resource, foreign namespace, wrong shape/format/usage/token | queue saturation and recovery | Automated |
| Frame selection | ordered publication and latest-ready coalescing | incomplete frame cannot publish | thousands of monotonic revisions | Automated |
| Lifetime | presented resources stay retained | write, destroy, namespace close, host close while retained | multiple leases and retirement after last release | Automated |
| Shutdown | close an idle or completed surface | incomplete work and active leases block close | completed pending work closes without collect; repeated close is harmless | Automated |
| Device loss | stale frames disappear and resources invalidate | stale generation cannot queue or acquire | loss with pending/presented resources | Automated mock; real GPU pending |
| Direct compositor | all compositor statuses propagate; SDL normal, text and layered paths invoke the bridge | callback exception releases lease | no frame, wrong command, nil compositor; per-frame bounded status counters | Automated |
| Readback fallback | R8, RGBA8 and BGRA8 paths | missing copy/readback support, unsupported float format | byte limit, label limit, dimension multiplication overflow | Automated |
| UI integration | standalone, underlay and overlay layout/paint | foreign or invalid owner, closed surface | safety styles override injected pointer/z-index values | Automated |
| Invalidation | completed frame invalidates paint owner | incomplete/failed collect does not invalidate | no style/layout invalidation | Automated |
| Memory models | deterministic ownership and teardown | sanitizer/Valgrind failures are fatal | ARC and ORC | Automated CI |
| Real compositor | visible direct Texture and RenderTarget | unsupported adapter falls back or fails closed | resize, DPI, opacity, clip and transform | Pending production compositor |
| Hardware stress | sustained bounded presentation | device loss, cancellation, teardown races | multiple surfaces and GPU-memory pressure | Pending real-GPU CI |

The primary executable matrix lives in
`tests/runtime/test_gpu_host.nim`. The same test unit is included in ARC, ORC,
ASan, UBSan, LSan, and Valgrind jobs where the toolchain supports them. The
optional bgfx jobs additionally compile the adapter and run its NOOP resource
integration. NOOP validates backend calls and ownership, but it does not count
as visible pixel conformance.

## Real-GPU Release Gate

The production direct compositor is not complete until a qualified Linux GPU
fixture proves all of the following:

- one SDL window, one GPU device/queue, and one presentation owner;
- direct Texture and RenderTarget output without CPU readback;
- deterministic pixels for clip, opacity, transform, stacking, alpha mode,
  resize, and DPI changes;
- bounded double/triple buffering under producer pressure;
- safe device loss, cancellation, namespace teardown, and shutdown ordering;
- multiple independent display surfaces without cross-surface corruption; and
- an explicit fallback or diagnostic for every unsupported capability.

Hardware-specific failures must be reported separately from contract-test,
compiler, linker, and sanitizer-runtime failures.
