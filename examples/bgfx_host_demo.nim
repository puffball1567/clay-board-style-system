# SPDX-License-Identifier: Apache-2.0

when not defined(cbssGpuBgfx):
  {.error: "compile this demo with -d:cbssGpuBgfx".}

{.compile: "bgfx_host_window.c".}

import std/[math, os, strutils]
import bgfx

import clay_board_style_system/backends/bgfx/adapter
import clay_board_style_system/backends/sdl3/config
import clay_board_style_system/runtime/gpu_host

when sdl3CompileFlags.len > 0:
  {.passC: sdl3CompileFlags.}
{.passL: sdl3LinkFlags.}

type DemoVertex = object
  x, y, z: cfloat
  abgr: uint32

proc createWindow(title: cstring; width, height: cint): pointer
  {.importc: "cbss_bgfx_demo_create_window", cdecl.}
proc sdlError(): cstring {.importc: "cbss_bgfx_demo_sdl_error", cdecl.}
proc platformData(window: pointer; display, nativeWindow: ptr pointer;
    nativeWindowType: ptr cint): cint
  {.importc: "cbss_bgfx_demo_platform_data", cdecl.}
proc pollWindow(window: pointer; width, height: ptr cint): cint
  {.importc: "cbss_bgfx_demo_poll", cdecl.}
proc delay(milliseconds: uint32)
  {.importc: "cbss_bgfx_demo_delay", cdecl.}
proc destroyWindow(window: pointer)
  {.importc: "cbss_bgfx_demo_destroy_window", cdecl.}

proc loadShader(path, label: string): bgfx_shader_handle_t =
  let bytes = readFile(path)
  if bytes.len == 0 or uint64(bytes.len) > uint64(high(uint32)):
    raise newException(IOError, "invalid shader binary: " & path)
  let memory = BGFX.copy(unsafeAddr bytes[0], uint32(bytes.len))
  if memory.isNil:
    raise newException(IOError, "bgfx could not copy shader: " & path)
  result = BGFX.createShader(memory)
  if not BGFX_HANDLE_IS_VALID(result):
    raise newException(IOError, "bgfx could not create shader: " & path)
  BGFX.setShaderName(result, label.cstring, int32(label.len))

proc updateShape(vertices: var array[9, DemoVertex]; frame: int) =
  let time = float32(frame) * 0.018'f32
  let pulse = 0.54'f32 + sin(time * 1.7'f32) * 0.055'f32
  let rotation = time * 0.42'f32
  vertices[0] = DemoVertex(x: 0, y: 0, z: 0, abgr: 0xfff7f2ec'u32)

  const colors = [
    0xffff7568'u32, 0xffffb15e'u32, 0xfff5e86f'u32, 0xff7fe39d'u32,
    0xff66d8e8'u32, 0xff7398ff'u32, 0xffb879ef'u32, 0xffff79b8'u32
  ]
  for index in 0 .. 7:
    let angle = rotation + float32(index) * PI.float32 / 4'f32
    let radius = pulse * (if index mod 2 == 0: 1'f32 else: 0.78'f32)
    vertices[index + 1] = DemoVertex(
      x: cos(angle) * radius,
      y: sin(angle) * radius,
      z: 0,
      abgr: colors[index]
    )

proc hostBudget(): GpuResourceBudget =
  GpuResourceBudget(
    persistentBytes: 1024 * 1024,
    transientBytesPerFrame: 64 * 1024,
    readbackBytesPerFrame: 0,
    workUnitsPerFrame: 64,
    maxResources: 16
  )

if paramCount() < 1 or paramCount() > 2:
  raise newException(
    ValueError,
    "usage: bgfx_host_demo <OpenGL shader directory> [frames; 0 until closed]"
  )

const initialWidth = 1040.cint
const initialHeight = 680.cint
let shaderDirectory = paramStr(1)
let maxFrames = if paramCount() == 2: parseInt(paramStr(2)) else: 0
if maxFrames < 0:
  raise newException(ValueError, "frame count must be non-negative")
let window = createWindow(
  "Clay Board Style System - bgfx GPU Host",
  initialWidth,
  initialHeight
)
if window.isNil:
  raise newException(IOError, "SDL3 window creation failed: " & $sdlError())

var host: GpuHost
var vertexBuffer = invalidHandle(bgfx_dynamic_vertex_buffer_handle_t)
var indexBuffer = invalidHandle(bgfx_index_buffer_handle_t)
var vertexShader = invalidHandle(bgfx_shader_handle_t)
var fragmentShader = invalidHandle(bgfx_shader_handle_t)
var program = invalidHandle(bgfx_program_handle_t)
var resourceNamespace: GpuNamespaceId
var namespaceOpen = false
var resources: seq[GpuResourceHandle]

try:
  var options = defaultBgfxHostOptions()
  options.rendererType = BGFX_RENDERER_TYPE_OPENGL
  var nativeWindowType: cint
  if platformData(
      window,
      addr options.platformData.ndt,
      addr options.platformData.nwh,
      addr nativeWindowType
  ) == 0:
    raise newException(IOError, "native window lookup failed: " & $sdlError())
  options.platformData.type = bgfx_native_window_handle_type_t(nativeWindowType)

  host = openGpuHost(
    newBgfxBackend(options),
    ghoOwned,
    GpuHostConfig(
      width: uint32(initialWidth),
      height: uint32(initialHeight),
      resetFlags: BGFX_RESET_VSYNC,
      presentation: true
    )
  )
  resourceNamespace = host.createGpuNamespace("bgfx-host-demo", hostBudget())
  namespaceOpen = true

  var layout: bgfx_vertex_layout_t
  discard BGFX.vertexLayoutBegin(addr layout, BGFX_RENDERER_TYPE_OPENGL)
  discard BGFX.vertexLayoutAdd(
    addr layout, BGFX_ATTRIB_POSITION, 3, BGFX_ATTRIB_TYPE_FLOAT, false, false)
  discard BGFX.vertexLayoutAdd(
    addr layout, BGFX_ATTRIB_COLOR0, 4, BGFX_ATTRIB_TYPE_UINT8, true, false)
  BGFX.vertexLayoutEnd(addr layout)

  vertexBuffer = BGFX.createDynamicVertexBuffer(
    9, addr layout, BGFX_BUFFER_ALLOW_RESIZE)
  if not BGFX_HANDLE_IS_VALID(vertexBuffer):
    raise newException(IOError, "bgfx dynamic vertex buffer creation failed")

  var indices: array[24, uint16]
  for index in 0 .. 7:
    indices[index * 3] = 0
    indices[index * 3 + 1] = uint16(index + 1)
    indices[index * 3 + 2] = uint16((index + 1) mod 8 + 1)
  let indexMemory = BGFX.copy(addr indices[0], uint32(sizeof(indices)))
  if indexMemory.isNil:
    raise newException(IOError, "bgfx index memory allocation failed")
  indexBuffer = BGFX.createIndexBuffer(indexMemory, BGFX_BUFFER_NONE)
  if not BGFX_HANDLE_IS_VALID(indexBuffer):
    raise newException(IOError, "bgfx index buffer creation failed")

  vertexShader = loadShader(
    shaderDirectory / "vs_cubes.bin",
    "CBSS demo vertex"
  )
  fragmentShader = loadShader(
    shaderDirectory / "fs_cubes.bin",
    "CBSS demo fragment"
  )
  program = BGFX.createProgram(vertexShader, fragmentShader, false)
  if not BGFX_HANDLE_IS_VALID(program):
    raise newException(IOError, "bgfx graphics program creation failed")

  resources.add host.reserveGpuResource(
    resourceNamespace,
    grkBuffer,
    9 * uint64(sizeof(DemoVertex))
  )
  resources.add host.reserveGpuResource(
    resourceNamespace,
    grkBuffer,
    uint64(sizeof(indices))
  )
  resources.add host.reserveGpuResource(resourceNamespace, grkShader, 0)
  resources.add host.reserveGpuResource(resourceNamespace, grkShader, 0)
  resources.add host.reserveGpuResource(resourceNamespace, grkPipeline, 0)

  echo "CBSS GPU host renderer: ", host.backendInfo.rendererName
  echo "Close the window or press Escape to exit."

  var width = initialWidth
  var height = initialHeight
  var previousWidth = width
  var previousHeight = height
  var vertices: array[9, DemoVertex]
  var frame = 0

  while pollWindow(window, addr width, addr height) != 0 and
      (maxFrames == 0 or frame < maxFrames):
    if width > 0 and height > 0 and
        (width != previousWidth or height != previousHeight):
      host.resizeGpuHost(uint32(width), uint32(height))
      previousWidth = width
      previousHeight = height

    updateShape(vertices, frame)
    let vertexMemory = BGFX.copy(addr vertices[0], uint32(sizeof(vertices)))
    if vertexMemory.isNil:
      raise newException(IOError, "bgfx vertex update allocation failed")
    BGFX.updateDynamicVertexBuffer(vertexBuffer, 0, vertexMemory)

    let token = host.beginGpuFrame()
    host.reserveGpuFrameWork(
      resourceNamespace,
      transientBytes = uint64(sizeof(vertices)),
      workUnits = 3
    )
    BGFX.setViewRect(0, 0, 0, uint16(width), uint16(height))
    BGFX.setViewClear(0, BGFX_CLEAR_COLOR, 0x111820ff'u32, 1.0, 0)
    BGFX.setDynamicVertexBuffer(0, vertexBuffer, 0, uint32(vertices.len))
    BGFX.setIndexBuffer(indexBuffer, 0, uint32(indices.len))
    BGFX.setState(BGFX_STATE_WRITE_RGB or BGFX_STATE_WRITE_A, 0)
    BGFX.submit(0, program, 0, BGFX_DISCARD_ALL)
    host.endGpuFrame(token)
    delay(8)
    inc frame
finally:
  if not host.isNil:
    if BGFX_HANDLE_IS_VALID(program):
      BGFX.destroyProgram(program)
    if BGFX_HANDLE_IS_VALID(fragmentShader):
      BGFX.destroyShader(fragmentShader)
    if BGFX_HANDLE_IS_VALID(vertexShader):
      BGFX.destroyShader(vertexShader)
    if BGFX_HANDLE_IS_VALID(indexBuffer):
      BGFX.destroyIndexBuffer(indexBuffer)
    if BGFX_HANDLE_IS_VALID(vertexBuffer):
      BGFX.destroyDynamicVertexBuffer(vertexBuffer)
    for resource in resources:
      discard host.releaseGpuResource(resource)
    let retirement = host.beginGpuFrame()
    host.endGpuFrame(retirement)
    if namespaceOpen:
      discard host.closeGpuNamespace(resourceNamespace)
    host.close()
  destroyWindow(window)
