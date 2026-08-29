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
