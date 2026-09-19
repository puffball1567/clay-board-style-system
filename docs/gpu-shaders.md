# GPU Shader Authoring And Packaging

CBSS separates shader authoring, compilation, packaging, and execution. The
runtime never invokes a shader compiler and does not interpret arbitrary shader
text.

```text
typed GpuShaderBuilder graph
  -> deterministic bgfx shader source
  -> build-only official bgfx shaderc process
  -> checked target-specific bytecode
  -> deterministic GpuShaderPackage
  -> retained GpuHost Shader and Pipeline resources
```

This boundary keeps `shaderc`, process-launch code, source files, and unrelated
renderer artifacts out of application binaries. A package contains only the
variants selected by the application build.

Shader-backed Custom Paint declarations use the backend-neutral typed material
parameters documented in [Custom Paint](custom-paint.md). Parameters are
validated and retained during style resolution, then delivered without
per-frame text parsing. Mapping those values to a concrete bgfx uniform or
storage binding remains the provider's responsibility until the production
shader-material compositor is complete.

## Build-Time Compilation

The build-only compiler module must be imported explicitly. It is deliberately
not re-exported by `clay_board_style_system`.

```nim
import std/os

import clay_board_style_system/build/gpu_shader_compiler
import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder,
    gpu_shader_package]

let builder = newGpuShaderBuilder(gssFragment, "accent-fragment")
builder.setColorOutput(
  builder.vector([0.12'f32, 0.48'f32, 0.92'f32, 1'f32])
)
let source = builder.emitGpuShaderSource()

let compiler = gpuShaderCompilerConfig(
  executable = "/path/to/bgfx/shaderc",
  includeDirectories = ["/path/to/bgfx/src"],
  workDirectory = getTempDir()
)
let linuxVulkan = gpuShaderCompileTarget(
  gsbtVulkan,
  gscpLinux,
  "spirv"
)

var package = gpuShaderPackage(source)
discard package.compileAndAddVariant(source, linuxVulkan, compiler)
writeFile("accent-fragment.cbsg", package.encodeGpuShaderPackageData())
```

`shaderc` is started with an argument array and without shell evaluation.
Compiler profiles are bounded tokens, include directories must already exist,
compiler diagnostics are bounded, and missing, empty, or oversized output is
rejected. Per-invocation source, varying, and output files live in an isolated
temporary directory that is removed after compilation.

CBSS uses the public command contract of the
[official bgfx shader compiler](https://bkaradzic.github.io/bgfx/tools.html).
It does not copy the compiler implementation or ship it in runtime artifacts.

## Runtime Loading

Applications may embed a package at compile time and select the variant that
matches the configured bgfx renderer.

```nim
import clay_board_style_system

const packagedShader = staticRead("accent-fragment.cbsg")

let package = decodeGpuShaderPackage(packagedShader)
let shader = gpuHost.createGpuShader(
  gpuNamespace,
  package,
  gsbtVulkan
)
```

Target selection is explicit. CBSS does not silently load OpenGL, Metal,
Direct3D, or SPIR-V bytecode into a different renderer. Build profiles should
package only their selected target and pass that same typed target to runtime
creation.

The package format contains:

- a versioned magic header;
- shader stage and bounded diagnostic label;
- typed Uniform, storage-buffer, and storage-image binding layouts when the
  shader was produced by `GpuShaderBuilder`;
- a deterministic source hash;
- at most 16 unique renderer targets;
- at most 16 MiB of bytecode per target and 128 MiB per package; and
- a checksum for every compiled variant.

Encoding sorts variants by target, so input order does not affect the package
bytes. Decoding rejects unknown stages or targets, duplicate targets,
truncation, trailing data, invalid reserved fields, oversized data, and checksum
failure before a backend resource is created.

Package version 3 preserves Uniform name identity, type, and array length in
addition to each storage binding's stage, format, and access direction. Version
2 packages remain readable with their storage-only layouts. Version 1 packages
remain readable and are treated as raw bytecode with an unknown binding layout.
Encoding always writes version 3. This distinction also represents a typed
shader that intentionally declares no resources: it rejects accidental
bindings, while raw bytecode continues to use the explicit low-level escape
hatch.

## Compute Authoring

Version 0.7 authoring emits typed Vertex, Fragment, and Compute source. Compute
graphs declare bounded work-group dimensions, typed storage buffers, and typed
2D storage images, then use explicit invocation builtins and load/store
operations:

```nim
let builder = newGpuShaderBuilder(gssCompute, "copy-compute")
builder.setComputeWorkGroupSize(64, 1, 1)
let input = builder.storageBuffer(
  "b_input", 0, gsbfFloat32x4, gsaRead
)
let output = builder.storageBuffer(
  "b_output", 1, gsbfFloat32x4, gsaWrite
)
let index = builder.swizzle(builder.globalInvocationId(), "x")
let count = builder.unsignedInteger(1_000)
builder.beginIf(greaterThanOrEqual(index, count))
builder.returnFromCompute()
builder.endIf()
builder.storeStorage(output, index, builder.loadStorage(input, index))

let source = builder.emitGpuShaderSource()
```

A compute kernel can write floating-point pixels without exposing a bgfx
handle or handwritten shader source:

```nim
let builder = newGpuShaderBuilder(gssCompute, "paint-surface")
builder.setComputeWorkGroupSize(8, 8, 1)
let output = builder.storageImage(
  "i_output", 0, gtfRgba32F, gsaWrite
)
let coordinates = builder.convertValue(
  gsvtIVec2,
  builder.swizzle(builder.globalInvocationId(), "xy")
)
builder.storeStorageImage(
  output,
  coordinates,
  builder.vector([0.25'f32, 0.5'f32, 0.75'f32, 1'f32])
)
let source = builder.emitGpuShaderSource()
```

Storage declarations require unique binding stages, exact scalar/vector
formats, and explicit read, write, or read-write access. Index expressions are
unsigned, values must match the declared element type, and a compute graph must
contain at least one output store. Scalar comparisons, boolean operations,
typed selection, integer modulo, nested `if`/`else`, and early return permit
bounded dispatches and fixed-neighbourhood kernels. Branch-local expressions
cannot be referenced after their branch closes. Work-group dimensions are
non-zero and bounded both per axis and by their total thread count. The runtime
continues to own Compute Pipeline creation, bindings, dispatch validation, and
retained resource lifetime; source compilation stays in the build-only layer.

### Bounded local control flow

Simulation and image-processing kernels can retain typed mutable scalar or
vector values and iterate literal signed or unsigned ranges:

```nim
let accumulated = builder.localValue(builder.scalar(0))
let row = builder.beginForRange(-1'i32, 2'i32, 1'i32)
let column = builder.beginForRange(-1'i32, 2'i32, 1'i32)

builder.beginIf(equalTo(column.loadLocal(), builder.signedInteger(0)))
builder.continueLoop()
builder.endIf()

accumulated.storeLocal(
  accumulated.loadLocal() + builder.convertValue(gsvtFloat, row.loadLocal())
)
builder.endForRange()
builder.endForRange()
```

`loadLocal()` captures the value at that graph position; a later store does
not retroactively change an earlier expression. A local is visible only in its
declaring scope and descendants. Loop variables cease to be visible after
`endForRange()`, while a root local may accumulate across nested loops.

Ranges are half-open. Signed steps may be positive or negative except for the
non-portable minimum `int32` magnitude; unsigned steps must be positive. A zero
step or more than 1,024 iterations is rejected before source generation, and
bounds are literal rather than data-dependent. This keeps authoring and
generated work bounded. Helper functions, local fixed-size arrays, and
data-dependent loops remain outside this increment and must not be assumed by
consumers.

The emitted binding layout travels with the compiled artifact and package into
the retained Compute Pipeline. Before a dispatch consumes frame budget or
calls the backend, CBSS requires Uniforms to match their declared name, type,
and array length, and storage buffers and images to match their declared count,
stage, format, and access direction. Names become stable numeric identities at
the authoring and resource boundaries, so per-frame validation does not compare
strings. Missing, extra, duplicated, cross-stage, wrongly typed, or overly
permissive bindings fail at the host boundary instead of becoming
driver-dependent GPU behavior.

Storage images share the compute binding-stage namespace with storage buffers.
Coordinates are explicitly converted to `ivec2`; reads return `vec4`, and
writes accept `vec4`. The portable authoring subset supports `R8`, `RGBA8`,
`R16F`, `R32F`, `RG16F`, `RGBA16F`, and `RGBA32F`. It rejects `BGRA8` and
`RG32F` because the official bgfx shader helper does not expose those image
format tokens consistently across its shader targets. This restriction applies
to typed authoring, not to general GPU Host texture creation.

Packed compute metadata can use typed unsigned integer bitwise operations:

```nim
let active = builder.unsignedInteger(1)
let pinned = builder.unsignedInteger(2)
let metadata = active.bitwiseOr(pinned)
let activeSet = metadata.bitwiseAnd(active)
```

`bitwiseNot`, `bitwiseAnd`, `bitwiseOr`, `bitwiseXor`, `shiftLeft`, and
`shiftRight` accept matching `uint` or `uvec` values. Signed integers, floating
values, and mixed vector widths fail while authoring rather than reaching the
backend compiler.

### Packed physical records

Large simulation and image-processing cells often mix floating fields with
integer identity or flag fields. CBSS maps these records onto a portable
`uint32` storage buffer instead of relying on backend-specific shader-structure
padding. Each field has a fixed word offset, float values preserve their exact
bits, and an optional explicit stride can reserve padding for an existing host
layout:

```nim
let cellLayout = gpuPackedRecordLayout([
  gpuPackedField("liquid", gsvtVec4),
  gpuPackedField("material", gsvtVec4),
  gpuPackedFieldAt("domainId", gsvtUint, 11)
], wordStride = 12)

let builder = newGpuShaderBuilder(gssCompute, "physical-cells")
builder.setComputeWorkGroupSize(64, 1, 1)
let cells = builder.packedRecordBuffer(
  "b_cells", 0, cellLayout, gsaReadWrite
)
let index = builder.swizzle(builder.globalInvocationId(), "x")
let liquid = cells.loadPackedField(index, "liquid")
let material = cells.loadPackedField(index, "material")
cells.storePackedField(index, "liquid", liquid + material)
```

`packedRecordBufferDescriptor()` derives the matching dynamic storage-buffer
size and format for a record count. Schemas reject duplicate or overlapping
fields, invalid identifiers, unsupported value types, undersized strides,
oversized buffers, foreign expressions, and access-direction violations before
source generation. The initial portable subset supports float and unsigned
integer scalars and vectors. It is sufficient for mixed physical fields while
keeping signed-offset loop variables in ordinary shader expressions.

`reinterpretValue()` emits only official shader-language bit intrinsics. The C
ABI exposes the same primitive as `cbss_shader_builder_bitcast`, so another
Craft Driver can generate the identical word layout without reproducing Nim
object memory or receiving a backend handle.

### Fixed local arrays

Compute builders can retain a bounded candidate set in an initialized local
array. Creation supplies one typed initial value for every element; reads are
captured as expression snapshots and later writes do not alter an earlier
expression:

```nim
let candidates = builder.localArray(builder.unsignedInteger(0), 8)
let slot = builder.beginForRange(0'u32, 8'u32, 1'u32)
let index = slot.loadLocal()
candidates.storeLocalArray(index, index + builder.unsignedInteger(1))
builder.endForRange()
let selected = candidates.loadLocalArray(builder.unsignedInteger(7))
```

Arrays contain numeric scalar values, are Compute-only, and are lexically
scoped. A builder accepts at most 64 arrays, 256 elements per array, and 1,024
total local-array elements. It rejects foreign handles and expressions, zero
lengths, mismatched value/index types, and statically known out-of-range literal
indices. Dynamic indices remain an explicit shader responsibility, matching
storage-buffer indexing; bounded ranges and guards should establish their valid
domain.

The authoring layer cannot infer an application's logical element count. A
dispatch must therefore add an explicit bounds guard as above, cover only valid
storage elements, or bind padded buffers large enough for every invocation in
the final work group. This keeps resource bounds explicit at the host boundary
instead of hiding an unchecked shader access.

### Drawing-engine compatibility fixture

The test suite builds one wet-supply-style Compute kernel entirely through the
public authoring API. It uses exact fixed-stride cell, edge, parameter, and
packed-output layouts; an initialized eight-entry candidate array; two bounded
neighbour passes; guarded flow scaling; pigment and binder transfer; and
unsigned metadata packing. The fixture deliberately contains no backend shader
source and no application-private hooks.

This is a compatibility floor, not a bundled paint simulation. It verifies that
the independently useful primitives compose into a realistic drawing-engine
workload under ARC and ORC, then sends the same generated source through the
official bgfx `shaderc` integration lane. Applications retain ownership of the
physical model, resource contents, dispatch schedule, and calibration.

## Verification

Portable unit tests run under ARC and ORC. They cover deterministic encoding,
version 1 compatibility, typed binding-layout round trips, target selection,
malformed headers and layout entries, truncation, trailing data, duplicate
targets, source, descriptor, and layout mismatches, payload mutation,
compiler launch failure, compiler failure, missing and empty output, bounded
diagnostics, and paths containing shell metacharacters.

The Linux bgfx CI lane additionally builds the pinned official `shaderc`,
compiles generated Vertex, Fragment, storage-buffer Compute, storage-image
Compute, packed-record Compute, bounded local-control-flow Compute, and fixed
local-array Compute shaders to SPIR-V. It also compiles the combined drawing-
engine compatibility fixture described above, packages the artifacts, and
decodes them through the runtime parser.
This test needs no GPU; real resource creation and submission remain covered by
the separate bgfx host integration lanes.
