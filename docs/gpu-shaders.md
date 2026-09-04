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
- a deterministic source hash;
- at most 16 unique renderer targets;
- at most 16 MiB of bytecode per target and 128 MiB per package; and
- a checksum for every compiled variant.

Encoding sorts variants by target, so input order does not affect the package
bytes. Decoding rejects unknown stages or targets, duplicate targets,
truncation, trailing data, invalid reserved fields, oversized data, and checksum
failure before a backend resource is created.

## Compute Authoring

Version 0.7 authoring emits typed Vertex, Fragment, and Compute source. Compute
graphs declare bounded work-group dimensions and typed storage buffers, then
use explicit invocation builtins and load/store operations:

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
builder.storeStorage(output, index, builder.loadStorage(input, index))

let source = builder.emitGpuShaderSource()
```

Storage declarations require unique binding stages, exact scalar/vector
formats, and explicit read, write, or read-write access. Index expressions are
unsigned, values must match the declared element type, and a compute graph must
contain at least one output store. Work-group dimensions are non-zero and
bounded both per axis and by their total thread count. The runtime continues to
own Compute Pipeline creation, bindings, dispatch validation, and retained
resource lifetime; source compilation stays in the build-only layer.

The authoring layer cannot infer an application's logical element count. A
dispatch must therefore cover only valid storage elements, or bind padded
buffers large enough for every invocation in the final work group. This keeps
resource bounds explicit at the host boundary instead of hiding an unchecked
shader access.

## Verification

Portable unit tests run under ARC and ORC. They cover deterministic encoding,
round trips, target selection, malformed headers, truncation, trailing data,
duplicate targets, source and descriptor mismatches, payload mutation,
compiler launch failure, compiler failure, missing and empty output, bounded
diagnostics, and paths containing shell metacharacters.

The Linux bgfx CI lane additionally builds the pinned official `shaderc`,
compiles generated Vertex, Fragment, and Compute shaders to SPIR-V, packages
the artifacts, and decodes them through the runtime parser. This test needs no
GPU; real resource creation and submission remain covered by the separate bgfx
host integration lanes.
