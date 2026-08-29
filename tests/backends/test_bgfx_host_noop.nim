when not defined(cbssGpuBgfx):
  {.error: "compile this fixture with -d:cbssGpuBgfx".}

import bgfx

import clay_board_style_system/backends/bgfx/adapter
import clay_board_style_system/runtime/gpu_host

type Position = object
  x, y, z: cfloat

proc config(): GpuHostConfig =
  GpuHostConfig(width: 64, height: 64, presentation: true)

proc budget(): GpuResourceBudget =
  GpuResourceBudget(
    persistentBytes: 1024 * 1024,
    transientBytesPerFrame: 64 * 1024,
    readbackBytesPerFrame: 64 * 1024,
    workUnitsPerFrame: 128,
    maxResources: 32
  )

var options = defaultBgfxHostOptions()
options.rendererType = BGFX_RENDERER_TYPE_NOOP

let host = openGpuHost(newBgfxBackend(options), ghoOwned, config())

doAssert host.provider == gpkBgfx
doAssert host.backendInfo.rendererName.len > 0

let resourceNamespace = host.createGpuNamespace("noop-integration", budget())

let mappedVertexBuffer = host.createGpuBuffer(
  resourceNamespace,
  GpuBufferDescriptor(
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
    label: "CBSS NOOP mapped vertices"
  ),
  newSeq[byte](24)
)
let mappedIndexBuffer = host.createGpuBuffer(
  resourceNamespace,
  GpuBufferDescriptor(
    byteSize: 12,
    role: gbrIndex,
    access: gbaDynamic,
    indexFormat: gifUint16,
    label: "CBSS NOOP mapped indices"
  )
)
host.updateGpuBuffer(mappedIndexBuffer, 2, newSeq[byte](4))
doAssert host.isGpuResourceLive(mappedVertexBuffer)
doAssert host.isGpuResourceLive(mappedIndexBuffer)

var layout: bgfx_vertex_layout_t
discard BGFX.vertexLayoutBegin(addr layout, BGFX_RENDERER_TYPE_NOOP)
discard BGFX.vertexLayoutAdd(
  addr layout,
  BGFX_ATTRIB_POSITION,
  3,
  BGFX_ATTRIB_TYPE_FLOAT,
  false,
  false
)
BGFX.vertexLayoutEnd(addr layout)
doAssert layout.stride == uint16(sizeof(Position))

var vertices = [
  Position(x: -1.0, y: -1.0, z: 0.0),
  Position(x: 1.0, y: -1.0, z: 0.0),
  Position(x: 0.0, y: 1.0, z: 0.0)
]
var indices = [0'u16, 1'u16, 2'u16]

let vertexMemory = BGFX.copy(addr vertices[0], uint32(sizeof(vertices)))
let indexMemory = BGFX.copy(addr indices[0], uint32(sizeof(indices)))
doAssert not vertexMemory.isNil
doAssert not indexMemory.isNil

let vertexBuffer = BGFX.createVertexBuffer(
  vertexMemory,
  addr layout,
  BGFX_BUFFER_NONE
)
let indexBuffer = BGFX.createIndexBuffer(indexMemory, BGFX_BUFFER_NONE)
doAssert BGFX_HANDLE_IS_VALID(vertexBuffer)
doAssert BGFX_HANDLE_IS_VALID(indexBuffer)

let vertexResource = host.reserveGpuResource(
  resourceNamespace,
  grkBuffer,
  uint64(sizeof(vertices))
)
let indexResource = host.reserveGpuResource(
  resourceNamespace,
  grkBuffer,
  uint64(sizeof(indices))
)

let dynamicBuffer = BGFX.createDynamicVertexBuffer(
  3,
  addr layout,
  BGFX_BUFFER_ALLOW_RESIZE
)
doAssert BGFX_HANDLE_IS_VALID(dynamicBuffer)
let dynamicMemory = BGFX.copy(addr vertices[0], uint32(sizeof(vertices)))
doAssert not dynamicMemory.isNil
BGFX.updateDynamicVertexBuffer(dynamicBuffer, 0, dynamicMemory)
let dynamicResource = host.reserveGpuResource(
  resourceNamespace,
  grkBuffer,
  uint64(sizeof(vertices))
)

var pixels = [
  0x20'u8, 0x60'u8, 0xa0'u8, 0xff'u8,
  0x40'u8, 0x80'u8, 0xc0'u8, 0xff'u8,
  0x60'u8, 0xa0'u8, 0xe0'u8, 0xff'u8,
  0x80'u8, 0xc0'u8, 0xff'u8, 0xff'u8
]
let mappedTextureResource = host.createGpuTexture(
  resourceNamespace,
  GpuTextureDescriptor(
    width: 2,
    height: 2,
    format: gtfRgba8,
    usage: {gtuSampled},
    label: "CBSS NOOP mapped texture"
  ),
  @pixels
)
doAssert host.isGpuResourceLive(mappedTextureResource)
let textureMemory = BGFX.copy(addr pixels[0], uint32(sizeof(pixels)))
doAssert not textureMemory.isNil
let textureFlags = BGFX_TEXTURE_BLIT_DST or BGFX_TEXTURE_READ_BACK
let texture = BGFX.createTexture2D(
  2,
  2,
  false,
  1,
  BGFX_TEXTURE_FORMAT_RGBA8,
  textureFlags,
  textureMemory,
  0
)
doAssert BGFX_HANDLE_IS_VALID(texture)
let textureResource = host.reserveGpuResource(
  resourceNamespace,
  grkTexture,
  uint64(sizeof(pixels))
)

let sourceMemory = BGFX.copy(addr pixels[0], uint32(sizeof(pixels)))
doAssert not sourceMemory.isNil
let sourceTexture = BGFX.createTexture2D(
  2,
  2,
  false,
  1,
  BGFX_TEXTURE_FORMAT_RGBA8,
  BGFX_TEXTURE_NONE,
  sourceMemory,
  0
)
doAssert BGFX_HANDLE_IS_VALID(sourceTexture)
let sourceTextureResource = host.reserveGpuResource(
  resourceNamespace,
  grkTexture,
  uint64(sizeof(pixels))
)

var replacement = [
  0xff'u8, 0x20'u8, 0x40'u8, 0xff'u8,
  0xff'u8, 0x40'u8, 0x60'u8, 0xff'u8,
  0xff'u8, 0x60'u8, 0x80'u8, 0xff'u8,
  0xff'u8, 0x80'u8, 0xa0'u8, 0xff'u8
]
let replacementMemory = BGFX.copy(
  addr replacement[0],
  uint32(sizeof(replacement))
)
doAssert not replacementMemory.isNil
BGFX.updateTexture2D(texture, 0, 0, 0, 0, 2, 2, replacementMemory, 8)

let frameBuffer = BGFX.createFrameBuffer(
  2,
  2,
  BGFX_TEXTURE_FORMAT_RGBA8,
  BGFX_TEXTURE_RT
)
doAssert BGFX_HANDLE_IS_VALID(frameBuffer)
let frameBufferResource = host.reserveGpuResource(
  resourceNamespace,
  grkRenderTarget,
  0
)

let uniform = BGFX.createUniform("u_cbssNoop", BGFX_UNIFORM_TYPE_VEC4, 1)
doAssert BGFX_HANDLE_IS_VALID(uniform)
let uniformResource = host.reserveGpuResource(
  resourceNamespace,
  grkUniform,
  0
)

let token = host.beginGpuFrame()
host.reserveGpuFrameWork(
  resourceNamespace,
  transientBytes = uint64(sizeof(vertices) + sizeof(replacement)),
  readbackBytes = uint64(sizeof(replacement)),
  workUnits = 8
)
BGFX.setViewRect(0, 0, 0, 64, 64)
BGFX.setViewClear(0, BGFX_CLEAR_COLOR, 0x102030ff'u32, 1.0, 0)
BGFX.setViewFrameBuffer(0, frameBuffer)

let encoder = BGFX.encoderBegin(true)
doAssert not encoder.isNil
BGFX.encoderSetMarker(encoder, "CBSS NOOP integration", 21)
discard BGFX.encoderSetScissor(encoder, 0, 0, 64, 64)
BGFX.encoderTouch(encoder, 0)
BGFX.encoderEnd(encoder)

BGFX.blit(
  0,
  texture,
  0,
  0,
  0,
  0,
  sourceTexture,
  0,
  0,
  0,
  0,
  2,
  2,
  1
)

var readback: array[16, uint8]
let readbackFrame = BGFX.readTexture(texture, addr readback[0], 0, 0)
doAssert readbackFrame > 0
host.endGpuFrame(token)

BGFX.destroyUniform(uniform)
BGFX.destroyFrameBuffer(frameBuffer)
BGFX.destroyTexture(sourceTexture)
BGFX.destroyTexture(texture)
BGFX.destroyDynamicVertexBuffer(dynamicBuffer)
BGFX.destroyIndexBuffer(indexBuffer)
BGFX.destroyVertexBuffer(vertexBuffer)

doAssert host.releaseGpuResource(uniformResource)
doAssert host.releaseGpuResource(frameBufferResource)
doAssert host.releaseGpuResource(sourceTextureResource)
doAssert host.releaseGpuResource(textureResource)
doAssert host.releaseGpuResource(mappedTextureResource)
doAssert host.releaseGpuResource(dynamicResource)
doAssert host.releaseGpuResource(indexResource)
doAssert host.releaseGpuResource(vertexResource)
doAssert host.releaseGpuResource(mappedIndexBuffer)
doAssert host.releaseGpuResource(mappedVertexBuffer)

let retirement = host.beginGpuFrame()
host.endGpuFrame(retirement)
doAssert host.gpuNamespaceUsage(resourceNamespace).resourceCount == 0
doAssert host.closeGpuNamespace(resourceNamespace)
host.close()

echo "CBSS bgfx NOOP resource integration passed"
