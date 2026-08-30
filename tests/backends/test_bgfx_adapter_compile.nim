when not defined(cbssGpuBgfx):
  {.error: "compile this fixture with -d:cbssGpuBgfx".}

{.compile: "bgfx_host_stub.c".}

import std/unittest

import bgfx

import clay_board_style_system/backends/bgfx/adapter
import clay_board_style_system/runtime/gpu_host

proc resetCounters() {.importc: "cbss_bgfx_stub_reset_counters", cdecl.}
proc shutdownCount(): uint32 {.importc: "cbss_bgfx_stub_shutdown_count", cdecl.}
proc frameCount(): uint32 {.importc: "cbss_bgfx_stub_frame_count", cdecl.}
proc resetCount(): uint32 {.importc: "cbss_bgfx_stub_reset_count", cdecl.}
proc stubWidth(): uint32 {.importc: "cbss_bgfx_stub_width", cdecl.}
proc stubHeight(): uint32 {.importc: "cbss_bgfx_stub_height", cdecl.}
proc submitCount(): uint32 {.importc: "cbss_bgfx_stub_submit_count", cdecl.}
proc dispatchCount(): uint32 {.importc: "cbss_bgfx_stub_dispatch_count", cdecl.}
proc viewRectCount(): uint32 {.
  importc: "cbss_bgfx_stub_view_rect_count", cdecl.}
proc viewScissorCount(): uint32 {.
  importc: "cbss_bgfx_stub_view_scissor_count", cdecl.}
proc viewClearCount(): uint32 {.
  importc: "cbss_bgfx_stub_view_clear_count", cdecl.}
proc viewFrameBufferCount(): uint32 {.
  importc: "cbss_bgfx_stub_view_frame_buffer_count", cdecl.}
proc vertexBindCount(): uint32 {.
  importc: "cbss_bgfx_stub_vertex_bind_count", cdecl.}
proc indexBindCount(): uint32 {.
  importc: "cbss_bgfx_stub_index_bind_count", cdecl.}
proc stateCount(): uint32 {.importc: "cbss_bgfx_stub_state_count", cdecl.}
proc lastViewId(): uint16 {.importc: "cbss_bgfx_stub_last_view_id", cdecl.}
proc lastState(): uint64 {.importc: "cbss_bgfx_stub_last_state", cdecl.}
proc programDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_program_destroy_count", cdecl.}
proc graphicsProgramCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_graphics_program_create_count", cdecl.}
proc computeProgramCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_compute_program_create_count", cdecl.}
proc shaderDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_shader_destroy_count", cdecl.}
proc shaderCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_shader_create_count", cdecl.}
proc shaderNameCount(): uint32 {.
  importc: "cbss_bgfx_stub_shader_name_count", cdecl.}
proc shaderDataBytes(): uint32 {.
  importc: "cbss_bgfx_stub_shader_data_bytes", cdecl.}
proc textureCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_texture_create_count", cdecl.}
proc textureDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_texture_destroy_count", cdecl.}
proc textureNameCount(): uint32 {.
  importc: "cbss_bgfx_stub_texture_name_count", cdecl.}
proc textureDataBytes(): uint32 {.
  importc: "cbss_bgfx_stub_texture_data_bytes", cdecl.}
proc textureWidth(): uint16 {.
  importc: "cbss_bgfx_stub_texture_width", cdecl.}
proc textureHeight(): uint16 {.
  importc: "cbss_bgfx_stub_texture_height", cdecl.}
proc textureFlags(): uint64 {.
  importc: "cbss_bgfx_stub_texture_flags", cdecl.}
proc textureFormat(): uint32 {.
  importc: "cbss_bgfx_stub_texture_format", cdecl.}
proc vertexBufferCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_vertex_buffer_create_count", cdecl.}
proc vertexBufferDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_vertex_buffer_destroy_count", cdecl.}
proc indexBufferCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_index_buffer_create_count", cdecl.}
proc indexBufferDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_index_buffer_destroy_count", cdecl.}
proc dynamicVertexBufferCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_dynamic_vertex_buffer_create_count", cdecl.}
proc dynamicVertexBufferDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_dynamic_vertex_buffer_destroy_count", cdecl.}
proc dynamicIndexBufferCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_dynamic_index_buffer_create_count", cdecl.}
proc dynamicIndexBufferDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_dynamic_index_buffer_destroy_count", cdecl.}
proc dynamicIndexBufferUpdateCount(): uint32 {.
  importc: "cbss_bgfx_stub_dynamic_index_buffer_update_count", cdecl.}
proc bufferNameCount(): uint32 {.
  importc: "cbss_bgfx_stub_buffer_name_count", cdecl.}
proc lastBufferDataBytes(): uint32 {.
  importc: "cbss_bgfx_stub_last_buffer_data_bytes", cdecl.}
proc lastBufferUpdateStart(): uint32 {.
  importc: "cbss_bgfx_stub_last_buffer_update_start", cdecl.}
proc lastBufferFlags(): uint16 {.
  importc: "cbss_bgfx_stub_last_buffer_flags", cdecl.}
proc lastVertexStride(): uint16 {.
  importc: "cbss_bgfx_stub_last_vertex_stride", cdecl.}
proc frameBufferCreateCount(): uint32 {.
  importc: "cbss_bgfx_stub_frame_buffer_create_count", cdecl.}
proc frameBufferDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_frame_buffer_destroy_count", cdecl.}
proc frameBufferNameCount(): uint32 {.
  importc: "cbss_bgfx_stub_frame_buffer_name_count", cdecl.}
proc frameBufferWidth(): uint16 {.
  importc: "cbss_bgfx_stub_frame_buffer_width", cdecl.}
proc frameBufferHeight(): uint16 {.
  importc: "cbss_bgfx_stub_frame_buffer_height", cdecl.}
proc frameBufferFlags(): uint64 {.
  importc: "cbss_bgfx_stub_frame_buffer_flags", cdecl.}
proc frameBufferFormat(): uint32 {.
  importc: "cbss_bgfx_stub_frame_buffer_format", cdecl.}

proc config(): GpuHostConfig =
  GpuHostConfig(width: 640, height: 480, presentation: true)

suite "optional bgfxim adapter":
  test "owned mode initializes frames resizes and shuts down":
    resetCounters()
    let backend = newBgfxBackend()

    check backend.provider == gpkBgfx
    check backend.apiVersion == gpuHostApiVersion
    check not backend.context.isNil

    let host = openGpuHost(backend, ghoOwned, config())
    check host.backendInfo.rendererName == "CBSS bgfx stub"
    check host.backendInfo.computeSupported
    check host.backendInfo.homogeneousDepth
    check host.backendInfo.maxTextureSize == 16384
    check stubWidth() == 640
    check stubHeight() == 480

    let resourceNamespace = host.createGpuNamespace(
      "adapter-textures",
      GpuResourceBudget(
        persistentBytes: 1024,
        workUnitsPerFrame: 4,
        maxResources: 12
      )
    )
    let pixels = newSeq[byte](4 * 2 * 4)
    let texture = host.createGpuTexture(
      resourceNamespace,
      GpuTextureDescriptor(
        width: 4,
        height: 2,
        format: gtfRgba8,
        usage: {gtuSampled, gtuBlitDestination},
        label: "adapter-texture"
      ),
      pixels
    )
    check host.isGpuResourceLive(texture)
    check textureCreateCount() == 1
    check textureNameCount() == 1
    check textureDataBytes() == uint32(pixels.len)
    check textureWidth() == 4
    check textureHeight() == 2
    check textureFormat() == uint32(BGFX_TEXTURE_FORMAT_RGBA8)
    check textureFlags() == BGFX_TEXTURE_BLIT_DST

    let vertexDescriptor = GpuBufferDescriptor(
      byteSize: 24,
      role: gbrVertex,
      access: gbaStatic,
      vertexLayout: @[
        GpuVertexAttribute(
          semantic: gvsPosition,
          components: 2,
          componentType: gvctFloat
        ),
        GpuVertexAttribute(
          semantic: gvsColor0,
          components: 4,
          componentType: gvctUint8,
          normalized: true
        )
      ],
      label: "adapter-vertices"
    )
    let vertexBuffer = host.createGpuBuffer(
      resourceNamespace,
      vertexDescriptor,
      newSeq[byte](24)
    )
    check host.isGpuResourceLive(vertexBuffer)
    check vertexBufferCreateCount() == 1
    check bufferNameCount() == 1
    check lastBufferDataBytes() == 24
    check lastVertexStride() == 12
    check lastBufferFlags() == BGFX_BUFFER_NONE

    var dynamicVertexDescriptor = vertexDescriptor
    dynamicVertexDescriptor.access = gbaDynamic
    dynamicVertexDescriptor.label = "adapter-dynamic-vertices"
    let dynamicVertexBuffer = host.createGpuBuffer(
      resourceNamespace,
      dynamicVertexDescriptor
    )
    check host.isGpuResourceLive(dynamicVertexBuffer)
    check dynamicVertexBufferCreateCount() == 1

    let indexBuffer = host.createGpuBuffer(
      resourceNamespace,
      GpuBufferDescriptor(
        byteSize: 12,
        role: gbrIndex,
        access: gbaStatic,
        indexFormat: gifUint16,
        label: "adapter-static-indices"
      ),
      newSeq[byte](12)
    )
    check host.isGpuResourceLive(indexBuffer)
    check indexBufferCreateCount() == 1

    let dynamicIndexBuffer = host.createGpuBuffer(
      resourceNamespace,
      GpuBufferDescriptor(
        byteSize: 16,
        role: gbrIndex,
        access: gbaDynamic,
        indexFormat: gifUint32,
        label: "adapter-indices"
      )
    )
    check host.isGpuResourceLive(dynamicIndexBuffer)
    check dynamicIndexBufferCreateCount() == 1
    check lastBufferDataBytes() == 16
    check lastBufferFlags() == BGFX_BUFFER_INDEX32
    host.updateGpuBuffer(dynamicIndexBuffer, 4, newSeq[byte](8))
    check dynamicIndexBufferUpdateCount() == 1
    check lastBufferUpdateStart() == 1
    check lastBufferDataBytes() == 8

    let renderTarget = host.createGpuRenderTarget(
      resourceNamespace,
      GpuRenderTargetDescriptor(
        width: 16,
        height: 8,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "adapter-render-target"
      )
    )
    check host.isGpuResourceLive(renderTarget)
    check frameBufferCreateCount() == 1
    check frameBufferNameCount() == 1
    check frameBufferWidth() == 16
    check frameBufferHeight() == 8
    check frameBufferFormat() == uint32(BGFX_TEXTURE_FORMAT_RGBA8)
    check frameBufferFlags() == BGFX_TEXTURE_RT

    let mappedFragmentShader = host.createGpuShader(
      resourceNamespace,
      GpuShaderDescriptor(stage: gssFragment, label: "adapter-fragment"),
      @[0x43'u8, 0x42'u8, 0x53'u8, 0x53'u8]
    )
    let mappedVertexShader = host.createGpuShader(
      resourceNamespace,
      GpuShaderDescriptor(stage: gssVertex, label: "adapter-vertex"),
      @[0x56'u8]
    )
    let mappedComputeShader = host.createGpuShader(
      resourceNamespace,
      GpuShaderDescriptor(stage: gssCompute, label: "adapter-compute"),
      @[0x43'u8]
    )
    check host.isGpuResourceLive(mappedFragmentShader)
    check shaderCreateCount() == 3
    check shaderNameCount() == 3
    check shaderDataBytes() == 1

    let mappedGraphicsPipeline = host.createGpuGraphicsPipeline(
      resourceNamespace,
      GpuGraphicsPipelineDescriptor(
        vertexShader: mappedVertexShader,
        fragmentShader: mappedFragmentShader,
        vertexLayout: vertexDescriptor.vertexLayout,
        colorFormat: gtfRgba8,
        topology: gptTriangleList,
        cullMode: gcmBack,
        frontFace: gffCounterClockwise,
        blend: alphaGpuBlendState(),
        label: "adapter-graphics"
      )
    )
    let mappedComputePipeline = host.createGpuComputePipeline(
      resourceNamespace,
      GpuComputePipelineDescriptor(
        computeShader: mappedComputeShader,
        label: "adapter-compute-pipeline"
      )
    )
    check host.isGpuResourceLive(mappedGraphicsPipeline)
    check host.isGpuResourceLive(mappedComputePipeline)
    check graphicsProgramCreateCount() == 1
    check computeProgramCreateCount() == 1

    let token = host.beginGpuFrame()
    host.submitGpuDraws(
      resourceNamespace,
      GpuGraphicsPassDescriptor(
        viewport: GpuViewport(width: 16, height: 8),
        scissorEnabled: true,
        scissor: GpuViewport(x: 1, y: 1, width: 14, height: 6),
        clearColorEnabled: true,
        clearColor: GpuClearColor(
          red: 0.25,
          green: 0.5,
          blue: 0.75,
          alpha: 1
        ),
        renderTarget: renderTarget
      ),
      [
        GpuDrawCommand(
          pipeline: mappedGraphicsPipeline,
          vertexBuffer: vertexBuffer,
          vertexCount: 2,
          indexBuffer: dynamicIndexBuffer,
          indexCount: 4
        ),
        GpuDrawCommand(
          pipeline: mappedGraphicsPipeline,
          vertexBuffer: dynamicVertexBuffer,
          vertexCount: 2,
          indexBuffer: indexBuffer,
          indexCount: 4
        )
      ]
    )
    host.dispatchGpuCompute(
      resourceNamespace,
      GpuComputeCommand(
        pipeline: mappedComputePipeline,
        groupsX: 2,
        groupsY: 3,
        groupsZ: 4
      )
    )
    host.endGpuFrame(token)
    check frameCount() == 1
    check submitCount() == 2
    check dispatchCount() == 1
    check viewRectCount() == 1
    check viewScissorCount() == 1
    check viewClearCount() == 1
    check viewFrameBufferCount() == 1
    check vertexBindCount() == 2
    check indexBindCount() == 2
    check stateCount() == 2
    check lastViewId() == 0
    check (lastState() and BGFX_STATE_WRITE_RGB) == BGFX_STATE_WRITE_RGB
    check (lastState() and BGFX_STATE_WRITE_A) == BGFX_STATE_WRITE_A
    check (lastState() and BGFX_STATE_CULL_CW) == BGFX_STATE_CULL_CW

    check host.releaseGpuResource(mappedComputePipeline)
    check host.releaseGpuResource(mappedGraphicsPipeline)
    check programDestroyCount() == 2
    check host.releaseGpuResource(mappedComputeShader)
    check host.releaseGpuResource(mappedVertexShader)
    check host.releaseGpuResource(mappedFragmentShader)
    check shaderDestroyCount() == 3

    host.resizeGpuHost(800, 600)
    check resetCount() == 1
    check stubWidth() == 800
    check stubHeight() == 600

    expect GpuHostError:
      discard openGpuHost(newBgfxBackend(), ghoBorrowed, config())

    check host.releaseGpuResource(renderTarget)
    check frameBufferDestroyCount() == 1
    check host.releaseGpuResource(indexBuffer)
    check indexBufferDestroyCount() == 1
    check host.releaseGpuResource(dynamicVertexBuffer)
    check dynamicVertexBufferDestroyCount() == 1
    check host.releaseGpuResource(dynamicIndexBuffer)
    check dynamicIndexBufferDestroyCount() == 1
    check host.releaseGpuResource(vertexBuffer)
    check vertexBufferDestroyCount() == 1
    check host.releaseGpuResource(texture)
    check textureDestroyCount() == 1
    host.close()
    check shutdownCount() == 1

  test "borrowed mode detaches without shutting down the runtime":
    resetCounters()
    let host = openGpuHost(newBgfxBackend(), ghoBorrowed, config())
    check host.backendInfo.rendererName == "CBSS bgfx stub"
    host.close()
    check shutdownCount() == 0
