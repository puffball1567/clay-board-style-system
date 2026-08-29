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
proc programDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_program_destroy_count", cdecl.}
proc shaderDestroyCount(): uint32 {.
  importc: "cbss_bgfx_stub_shader_destroy_count", cdecl.}
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
      GpuResourceBudget(persistentBytes: 1024, maxResources: 4)
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

    let token = host.beginGpuFrame()

    var shaderByte = 0x42'u8
    var shaderMemory = bgfx_memory_t(
      data: addr shaderByte,
      size: uint32(sizeof(shaderByte))
    )
    let vertexShader = BGFX.createShader(addr shaderMemory)
    let fragmentShader = BGFX.createShader(addr shaderMemory)
    let computeShader = BGFX.createShader(addr shaderMemory)
    check BGFX_HANDLE_IS_VALID(vertexShader)
    check BGFX_HANDLE_IS_VALID(fragmentShader)
    check BGFX_HANDLE_IS_VALID(computeShader)

    let graphicsProgram = BGFX.createProgram(
      vertexShader,
      fragmentShader,
      false
    )
    let computeProgram = BGFX.createComputeProgram(computeShader, false)
    check BGFX_HANDLE_IS_VALID(graphicsProgram)
    check BGFX_HANDLE_IS_VALID(computeProgram)

    BGFX.submit(0, graphicsProgram, 0, BGFX_DISCARD_ALL)
    BGFX.dispatch(1, computeProgram, 2, 3, 4, BGFX_DISCARD_ALL)
    host.endGpuFrame(token)
    check frameCount() == 1
    check submitCount() == 1
    check dispatchCount() == 1

    BGFX.destroyProgram(computeProgram)
    BGFX.destroyProgram(graphicsProgram)
    BGFX.destroyShader(computeShader)
    BGFX.destroyShader(fragmentShader)
    BGFX.destroyShader(vertexShader)
    check programDestroyCount() == 2
    check shaderDestroyCount() == 3

    host.resizeGpuHost(800, 600)
    check resetCount() == 1
    check stubWidth() == 800
    check stubHeight() == 600

    expect GpuHostError:
      discard openGpuHost(newBgfxBackend(), ghoBorrowed, config())

    check host.releaseGpuResource(renderTarget)
    check frameBufferDestroyCount() == 1
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
