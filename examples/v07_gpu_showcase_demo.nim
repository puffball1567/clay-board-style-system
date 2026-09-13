# SPDX-License-Identifier: Apache-2.0

when not defined(cbssGpuBgfx):
  {.error: "compile this demo with -d:cbssGpuBgfx".}

{.compile: "bgfx_host_window.c".}

import std/[os, strutils, times]
import bgfx

import clay_board_style_system/backends/bgfx/adapter
import clay_board_style_system/backends/bgfx/sdl3_platform_data
import clay_board_style_system/backends/sdl3/config
import clay_board_style_system/runtime/gpu_host

when sdl3CompileFlags.len > 0:
  {.passC: sdl3CompileFlags.}
{.passL: sdl3LinkFlags.}

type ShowcaseVertex = object
  x, y, z: cfloat
  u, v: cfloat

const
  initialWidth = 1280.cint
  initialHeight = 760.cint
  sceneNames = [
    "Fluid Field",
    "Heart Particles",
    "Mechanical Core",
    "Image Lab",
    "GPU Material"
  ]

proc createWindow(title: cstring; width, height: cint): pointer
  {.importc: "cbss_bgfx_demo_create_window", cdecl.}
proc sdlError(): cstring {.importc: "cbss_bgfx_demo_sdl_error", cdecl.}
proc pollWindow(window: pointer; width, height: ptr cint): cint
  {.importc: "cbss_bgfx_demo_poll", cdecl.}
proc selectedScene(pointerX, pointerY: ptr cfloat): cint
  {.importc: "cbss_bgfx_demo_scene", cdecl.}
proc setWindowTitle(window: pointer; title: cstring)
  {.importc: "cbss_bgfx_demo_set_title", cdecl.}
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

proc hostBudget(): GpuResourceBudget =
  GpuResourceBudget(
    persistentBytes: 512 * 1024,
    transientBytesPerFrame: 16 * 1024,
    readbackBytesPerFrame: 0,
    workUnitsPerFrame: 32,
    maxResources: 16
  )

proc sceneTitle(index: int): string =
  "Clay Board Style System - GPU " & $(index + 1) & "/5 - " & sceneNames[index]

if paramCount() < 1 or paramCount() > 2:
  raise newException(
    ValueError,
    "usage: v07_gpu_showcase_demo <shader directory> [frames; 0 until closed]"
  )

let shaderDirectory = paramStr(1)
let maxFrames = if paramCount() == 2: parseInt(paramStr(2)) else: 0
if maxFrames < 0:
  raise newException(ValueError, "frame count must be non-negative")

let initialTitle = sceneTitle(0)
let window = createWindow(initialTitle.cstring, initialWidth, initialHeight)
if window.isNil:
  raise newException(IOError, "SDL3 window creation failed: " & $sdlError())

var host: GpuHost
var vertexBuffer = invalidHandle(bgfx_vertex_buffer_handle_t)
var indexBuffer = invalidHandle(bgfx_index_buffer_handle_t)
var vertexShader = invalidHandle(bgfx_shader_handle_t)
var fragmentShader = invalidHandle(bgfx_shader_handle_t)
var program = invalidHandle(bgfx_program_handle_t)
var sceneUniform = invalidHandle(bgfx_uniform_handle_t)
var pointerUniform = invalidHandle(bgfx_uniform_handle_t)
var resourceNamespace: GpuNamespaceId
var namespaceOpen = false
var resources: seq[GpuResourceHandle]

try:
  var options = defaultBgfxHostOptions()
  options.rendererType = BGFX_RENDERER_TYPE_OPENGL
  options.platformData = bgfxPlatformDataFromSdl3Window(window)
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
  resourceNamespace = host.createGpuNamespace("v07-gpu-showcase", hostBudget())
  namespaceOpen = true

  var layout: bgfx_vertex_layout_t
  discard BGFX.vertexLayoutBegin(addr layout, BGFX_RENDERER_TYPE_OPENGL)
  discard BGFX.vertexLayoutAdd(
    addr layout, BGFX_ATTRIB_POSITION, 3, BGFX_ATTRIB_TYPE_FLOAT, false, false)
  discard BGFX.vertexLayoutAdd(
    addr layout, BGFX_ATTRIB_TEXCOORD0, 2, BGFX_ATTRIB_TYPE_FLOAT, false, false)
  BGFX.vertexLayoutEnd(addr layout)

  var vertices = [
    ShowcaseVertex(x: -1, y: -1, z: 0, u: 0, v: 1),
    ShowcaseVertex(x: 1, y: -1, z: 0, u: 1, v: 1),
    ShowcaseVertex(x: 1, y: 1, z: 0, u: 1, v: 0),
    ShowcaseVertex(x: -1, y: 1, z: 0, u: 0, v: 0)
  ]
  var indices = [0'u16, 1, 2, 0, 2, 3]
  let vertexMemory = BGFX.copy(addr vertices[0], uint32(sizeof(vertices)))
  let indexMemory = BGFX.copy(addr indices[0], uint32(sizeof(indices)))
  if vertexMemory.isNil or indexMemory.isNil:
    raise newException(IOError, "bgfx showcase geometry allocation failed")
  vertexBuffer = BGFX.createVertexBuffer(vertexMemory, addr layout, BGFX_BUFFER_NONE)
  indexBuffer = BGFX.createIndexBuffer(indexMemory, BGFX_BUFFER_NONE)
  if not BGFX_HANDLE_IS_VALID(vertexBuffer) or not BGFX_HANDLE_IS_VALID(indexBuffer):
    raise newException(IOError, "bgfx showcase geometry creation failed")

  vertexShader = loadShader(shaderDirectory / "vs_showcase.bin", "CBSS showcase vertex")
  fragmentShader = loadShader(shaderDirectory / "fs_showcase.bin", "CBSS showcase fragment")
  program = BGFX.createProgram(vertexShader, fragmentShader, false)
  if not BGFX_HANDLE_IS_VALID(program):
    raise newException(IOError, "bgfx showcase program creation failed")
  sceneUniform = BGFX.createUniform("u_scene", BGFX_UNIFORM_TYPE_VEC4, 1)
  pointerUniform = BGFX.createUniform("u_pointer", BGFX_UNIFORM_TYPE_VEC4, 1)
  if not BGFX_HANDLE_IS_VALID(sceneUniform) or not BGFX_HANDLE_IS_VALID(pointerUniform):
    raise newException(IOError, "bgfx showcase uniform creation failed")

  resources.add host.reserveGpuResource(resourceNamespace, grkBuffer, uint64(
      sizeof(vertices)))
  resources.add host.reserveGpuResource(resourceNamespace, grkBuffer, uint64(
      sizeof(indices)))
  resources.add host.reserveGpuResource(resourceNamespace, grkShader, 0)
  resources.add host.reserveGpuResource(resourceNamespace, grkShader, 0)
  resources.add host.reserveGpuResource(resourceNamespace, grkPipeline, 0)
  resources.add host.reserveGpuResource(resourceNamespace, grkUniform, 16)
  resources.add host.reserveGpuResource(resourceNamespace, grkUniform, 16)

  echo "CBSS GPU showcase renderer: ", host.backendInfo.rendererName
  echo "Scenes: 1 fluid, 2 hearts, 3 mechanical, 4 image lab, 5 material"

  let startedAt = epochTime()
  var width = initialWidth
  var height = initialHeight
  var previousWidth = width
  var previousHeight = height
  var previousScene = -1
  var frame = 0

  while pollWindow(window, addr width, addr height) != 0 and
      (maxFrames == 0 or frame < maxFrames):
    if width > 0 and height > 0 and
        (width != previousWidth or height != previousHeight):
      host.resizeGpuHost(uint32(width), uint32(height))
      previousWidth = width
      previousHeight = height

    var pointerX = 0.0'f32
    var pointerY = 0.0'f32
    let scene = clamp(selectedScene(addr pointerX, addr pointerY).int, 0, 4)
    if scene != previousScene:
      let title = sceneTitle(scene)
      setWindowTitle(window, title.cstring)
      previousScene = scene

    var sceneData = [
      cfloat(epochTime() - startedAt),
      cfloat(scene),
      cfloat(if height > 0: width.float32 / height.float32 else: 1),
      0.cfloat
    ]
    var pointerData = [cfloat(pointerX), cfloat(pointerY), 0.cfloat, 0.cfloat]

    let token = host.beginGpuFrame()
    host.reserveGpuFrameWork(resourceNamespace, transientBytes = 32, workUnits = 2)
    BGFX.setViewRect(0, 0, 0, uint16(width), uint16(height))
    BGFX.setViewClear(0, BGFX_CLEAR_COLOR, 0x090816ff'u32, 1.0, 0)
    BGFX.setUniform(sceneUniform, addr sceneData[0], 1)
    BGFX.setUniform(pointerUniform, addr pointerData[0], 1)
    BGFX.setVertexBuffer(0, vertexBuffer, 0, uint32(vertices.len))
    BGFX.setIndexBuffer(indexBuffer, 0, uint32(indices.len))
    BGFX.setState(BGFX_STATE_WRITE_RGB or BGFX_STATE_WRITE_A, 0)
    BGFX.submit(0, program, 0, BGFX_DISCARD_ALL)
    host.endGpuFrame(token)
    delay(4)
    inc frame
finally:
  if not host.isNil:
    if BGFX_HANDLE_IS_VALID(pointerUniform): BGFX.destroyUniform(pointerUniform)
    if BGFX_HANDLE_IS_VALID(sceneUniform): BGFX.destroyUniform(sceneUniform)
    if BGFX_HANDLE_IS_VALID(program): BGFX.destroyProgram(program)
    if BGFX_HANDLE_IS_VALID(fragmentShader): BGFX.destroyShader(fragmentShader)
    if BGFX_HANDLE_IS_VALID(vertexShader): BGFX.destroyShader(vertexShader)
    if BGFX_HANDLE_IS_VALID(indexBuffer): BGFX.destroyIndexBuffer(indexBuffer)
    if BGFX_HANDLE_IS_VALID(vertexBuffer): BGFX.destroyVertexBuffer(vertexBuffer)
    for resource in resources:
      discard host.releaseGpuResource(resource)
    let retirement = host.beginGpuFrame()
    host.endGpuFrame(retirement)
    if namespaceOpen:
      discard host.closeGpuNamespace(resourceNamespace)
    host.close()
  destroyWindow(window)
