## Shared real-renderer fixture for packed affine rounded-rectangle instances.
import clay_board_style_system/runtime/[gpu_host, gpu_shader_builder]

proc instancedRectVertexSource*(): GpuShaderSource =
  let builder = newGpuShaderBuilder(gssVertex, "instanced-rect-vertex")
  let corner = builder.vertexInput(gsisPosition, gsvtVec2)
  let rowX = builder.vertexInput(gsisInstance0, gsvtVec4)
  let rowY = builder.vertexInput(gsisInstance1, gsvtVec4)
  let shape = builder.vertexInput(gsisInstance2, gsvtVec4)
  let color = builder.vertexInput(gsisInstance3, gsvtVec4)
  let viewport = builder.vertexInput(gsisInstance4, gsvtVec4)
  let point = corner * builder.swizzle(shape, "xy")
  let local = builder.construct(gsvtVec4, [builder.swizzle(point, "x"), builder.swizzle(point, "y"), builder.scalar(1), builder.scalar(0)])
  let x = builder.binary(gsbDot, rowX, local) * builder.swizzle(viewport, "x") * builder.scalar(2) - builder.scalar(1)
  let y = builder.scalar(1) - builder.binary(gsbDot, rowY, local) * builder.swizzle(viewport, "y") * builder.scalar(2)
  builder.setPositionOutput(builder.construct(gsvtVec4, [x, y, builder.scalar(0), builder.scalar(1)]))
  builder.setVaryingOutput(gsisTexCoord0, point)
  builder.setVaryingOutput(gsisTexCoord1, builder.swizzle(shape, "xyz"))
  builder.setVaryingOutput(gsisColor0, color)
  builder.emitGpuShaderSource()

proc instancedRectFragmentSource*(): GpuShaderSource =
  GpuShaderSource(stage: gssFragment, label: "instanced-rect-fragment",
    source: """$input v_texcoord0, v_texcoord1, v_color0
#include "bgfx_shader.sh"
void main()
{
  vec2 halfSize = v_texcoord1.xy * 0.5;
  float radius = clamp(v_texcoord1.z, 0.0, min(halfSize.x, halfSize.y));
  vec2 q = abs(v_texcoord0 - halfSize) - halfSize + vec2(radius);
  float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  if (distance > 0.0) { discard; }
  gl_FragColor = v_color0;
}
""",
    varyingDefinitions: """vec2 v_texcoord0 : TEXCOORD0;
vec3 v_texcoord1 : TEXCOORD1;
vec4 v_color0 : COLOR0;
""",
    inputs: @[
      GpuShaderInterfaceEntry(slot: gsisTexCoord0, valueType: gsvtVec2),
      GpuShaderInterfaceEntry(slot: gsisTexCoord1, valueType: gsvtVec3),
      GpuShaderInterfaceEntry(slot: gsisColor0, valueType: gsvtVec4)])
