import std/[hashes, math, options, os, strutils, tables]

import ../../assets/asset_resolver
import ../../core/[color, computed_style, geometry, gradient_sampling, node]
import ../../input/events
import ../../paint/[paint_command, path_geometry]
import ../../text/[cosmic_text_engine, font_registry, text_engine]
import ../../vendor/sdl3
import ./config
import ./image_loader
import ./text_debug

when sdl3CompileFlags.len > 0:
  {.passC: sdl3CompileFlags.}
{.passL: sdl3LinkFlags.}

const
  sdlHintImeImplementedUi = "SDL_IME_IMPLEMENTED_UI"
  sdlHintMouseFocusClickthrough = "SDL_MOUSE_FOCUS_CLICKTHROUGH"
  sdlHintVideoDriver = "SDL_VIDEO_DRIVER"
  sdlInitVideo = SDL_InitFlags(0x00000020'u32)
  sdlWindowHidden = SDL_WindowFlags(0x0000000000000008'u64)
  sdlWindowResizable = SDL_WindowFlags(0x0000000000000020'u64)
  sdlWindowHighPixelDensity = SDL_WindowFlags(0x0000000000002000'u64)
  sdlBlendModeNone = SDL_BlendMode(0x00000000'u32)
  sdlBlendModeBlend = SDL_BlendMode(0x00000001'u32)
  sdlBlendModeAdd = SDL_BlendMode(0x00000002'u32)
  sdlBlendModeBlendPremultiplied = SDL_BlendMode(0x00000010'u32)
  sdlBlendModeAddPremultiplied = SDL_BlendMode(0x00000020'u32)
  sdlTextureAccessStatic = SDL_TEXTUREACCESS_STATIC
  sdlTextureAccessTarget = SDL_TEXTUREACCESS_TARGET
  defaultTextCacheBytes = 64'u64 * 1024 * 1024
  defaultImageCacheBytes = 256'u64 * 1024 * 1024
  defaultRoundedTextureCacheBytes = 128'u64 * 1024 * 1024
  defaultShadowTextureCacheBytes = 128'u64 * 1024 * 1024
  defaultTransformTextureCacheBytes = 128'u64 * 1024 * 1024
  sdl3StreamWakeEventCode = 0x43425353'i32

var
  sdl3StreamWakeEventType: uint32
  nextSdl3StreamWakeToken = 1'u32

type
  Sdl3ImeUiMode* = enum
    siuNative,
    siuComposition,
    siuCompositionAndCandidates

  Sdl3TextCacheEntry = object
    key: string
    texture: pointer
    width, height: int
    offsetX, offsetY: int
    scale: float32
    lastUsed: uint64

  Sdl3ImageCacheEntry = object
    source: string
    texture: pointer
    width, height: float32
    lastUsed: uint64

  Sdl3RoundedTextureCacheEntry = object
    key: string
    texture: pointer
    width, height: int
    lastUsed: uint64

  Sdl3ShadowTextureCacheEntry = object
    key: string
    texture: pointer
    width, height: int
    lastUsed: uint64

  Sdl3TransformTextureCacheEntry = object
    texture: pointer
    width, height: int
    lastUsed: uint64
    inUse: bool

  Sdl3CapturedFrame* = object
    width*: int
    height*: int
    pixels*: seq[uint8]

  Sdl3CacheUsage* = object
    textBytes*, imageBytes*: uint64
    roundedTextureBytes*, shadowTextureBytes*: uint64
    transformTextureBytes*: uint64

  Sdl3ClipRegion = object
    rect: Rect
    radius: float32
    bounds: SDL_Rect

  Sdl3PreparedCommand = object
    command: PaintCommand
    roundedImageClipStack: seq[Sdl3ClipRegion]

  Sdl3TransformLayer = object
    texture: pointer
    previousTarget: pointer
    previousClips: seq[Sdl3ClipRegion]
    transform: Affine2D
    sourceBounds: Rect
    pixelWidth, pixelHeight: int
    textureCacheIndex: int
    opacity: float32
    compositeMode: LayerCompositeMode
    valid: bool
    hasContent: bool

  Sdl3ImageEventKind* = enum
    sieLoadStart,
    sieLoad,
    sieError,
    sieLoadEnd

  Sdl3ImageEvent* = object
    kind*: Sdl3ImageEventKind
    node*: NodeId
    source*: string

  Sdl3EventKind* = enum
    sekQuit,
    sekResize,
    sekExpose,
    sekFocus,
    sekBlur,
    sekPointerMove,
    sekPointerDown,
    sekPointerUp,
    sekKeyDown,
    sekKeyUp,
    sekTextInput,
    sekCompositionStart,
    sekCompositionUpdate,
    sekCompositionEnd,
    sekCompositionCandidates,
    sekWheel,
    sekTouchStart,
    sekTouchMove,
    sekTouchEnd,
    sekTouchCancel,
    sekPenProximityIn,
    sekPenProximityOut,
    sekPenButtonDown,
    sekPenButtonUp,
    sekStreamWake

  Sdl3Event* = object
    timestamp*: uint64
    pointer*: Option[PointerData]
    case kind*: Sdl3EventKind
    of sekQuit, sekExpose:
      discard
    of sekResize:
      width*, height*: int
    of sekFocus, sekBlur:
      discard
    of sekPointerMove:
      x*, y*: float32
    of sekPointerDown, sekPointerUp:
      button*: int
      buttonX*, buttonY*: float32
    of sekKeyDown, sekKeyUp:
      key*: string
      repeat*: bool
      ctrl*, alt*, shift*, meta*: bool
    of sekTextInput, sekCompositionStart, sekCompositionUpdate, sekCompositionEnd:
      text*: string
    of sekCompositionCandidates:
      candidates*: seq[string]
      selectedCandidate*: int
      horizontalCandidates*: bool
    of sekWheel:
      wheelX*, wheelY*, wheelMouseX*, wheelMouseY*: float32
    of sekTouchStart, sekTouchMove, sekTouchEnd, sekTouchCancel:
      touchX*, touchY*, touchDx*, touchDy*: float32
    of sekPenProximityIn, sekPenProximityOut:
      discard
    of sekPenButtonDown, sekPenButtonUp:
      penButton*: int
      penButtonX*, penButtonY*: float32
    of sekStreamWake:
      wakeToken*: uint32

  Sdl3PenDeviceState = object
    pointer: PointerData
    position: Vec2

  Sdl3Renderer* = object
    window*: pointer
    renderer*: pointer
    clipStack: seq[Sdl3ClipRegion]
    textCache: seq[Sdl3TextCacheEntry]
    textCacheIndex: Table[Hash, seq[int]]
    transientTextTextures: seq[pointer]
    imageCache: seq[Sdl3ImageCacheEntry]
    imageCacheIndex: Table[Hash, seq[int]]
    roundedTextureCache: seq[Sdl3RoundedTextureCacheEntry]
    roundedTextureCacheIndex: Table[Hash, seq[int]]
    shadowTextureCache: seq[Sdl3ShadowTextureCacheEntry]
    shadowTextureCacheIndex: Table[Hash, seq[int]]
    transformTextureCache: seq[Sdl3TransformTextureCacheEntry]

    staticLayerTexture: pointer
    staticLayerWidth, staticLayerHeight: int
    imageFailures: seq[string]
    imageEvents: seq[Sdl3ImageEvent]
    reportedImageEventKeys: seq[string]
    assetResolver: AssetResolver
    textCacheLimit: int
    imageCacheLimit: int
    roundedTextureCacheLimit: int
    shadowTextureCacheLimit: int
    textCacheByteLimit, imageCacheByteLimit: uint64
    roundedTextureCacheByteLimit, shadowTextureCacheByteLimit: uint64
    transformTextureCacheByteLimit: uint64
    textCacheBytes, imageCacheBytes: uint64
    roundedTextureCacheBytes, shadowTextureCacheBytes: uint64
    transformTextureCacheBytes: uint64
    frameId: uint64
    pendingEvents: seq[Sdl3Event]
    penStates: Table[SDL_PenID, Sdl3PenDeviceState]
    captureNextFrame: bool
    capturedFrame: Option[Sdl3CapturedFrame]
    composing: bool
    imeCandidatesEnabled: bool
    textInputRunning: bool
    textInputArea: Option[Rect]
    textInputCursor: int
    premultipliedLayerBlend: bool
    cursorCache: array[CursorKind, pointer]
    ownsCursor: array[CursorKind, bool]
    activeCursor: CursorKind

const DefaultWheelStepPixels* = 54.0'f32

proc textureBytes(width, height: int): uint64 =
  uint64(max(0, width)) * uint64(max(0, height)) * 4'u64

proc cacheUsage*(target: Sdl3Renderer): Sdl3CacheUsage =
  Sdl3CacheUsage(
    textBytes: target.textCacheBytes,
    imageBytes: target.imageCacheBytes,
    roundedTextureBytes: target.roundedTextureCacheBytes,
    shadowTextureBytes: target.shadowTextureCacheBytes,
    transformTextureBytes: target.transformTextureCacheBytes
  )

proc indexKey(index: var Table[Hash, seq[int]]; key: string; entryIndex: int) =
  index.mgetOrPut(hash(key), @[]).add entryIndex

proc rebuildTextCacheIndex(target: var Sdl3Renderer) =
  target.textCacheIndex.clear()
  for entryIndex, entry in target.textCache:
    target.textCacheIndex.indexKey(entry.key, entryIndex)

proc rebuildImageCacheIndex(target: var Sdl3Renderer) =
  target.imageCacheIndex.clear()
  for entryIndex, entry in target.imageCache:
    target.imageCacheIndex.indexKey(entry.source, entryIndex)

proc rebuildRoundedTextureCacheIndex(target: var Sdl3Renderer) =
  target.roundedTextureCacheIndex.clear()
  for entryIndex, entry in target.roundedTextureCache:
    target.roundedTextureCacheIndex.indexKey(entry.key, entryIndex)

proc rebuildShadowTextureCacheIndex(target: var Sdl3Renderer) =
  target.shadowTextureCacheIndex.clear()
  for entryIndex, entry in target.shadowTextureCache:
    target.shadowTextureCacheIndex.indexKey(entry.key, entryIndex)

proc normalizedWheelAxis*(value: float32; directionFlipped: bool): float32 =
  if directionFlipped: -value else: value

proc scrollDelta*(event: Sdl3Event; pixelsPerStep = DefaultWheelStepPixels): Vec2 =
  if event.kind != sekWheel:
    return vec2(0, 0)
  # SDL reports positive vertical values away from the user. UI scroll
  # offsets grow toward the document end, so the coordinate is inverted once.
  vec2(-event.wheelX * pixelsPerStep, -event.wheelY * pixelsPerStep)

proc pointerInputEvent*(event: Sdl3Event): Option[InputEvent] =
  ## Converts SDL pointer-family events without losing optional device axes.
  ## Keyboard, text, window, and wheel events remain explicit at the host.
  case event.kind
  of sekPointerMove:
    result = some(pointerMoveEvent(vec2(event.x, event.y), event.pointer))
  of sekPointerDown:
    result = some(pointerDownEvent(
      vec2(event.buttonX, event.buttonY), event.button, event.pointer
    ))
  of sekPointerUp:
    result = some(pointerUpEvent(
      vec2(event.buttonX, event.buttonY), event.button, event.pointer
    ))
  of sekTouchStart:
    result = some(InputEvent(
      kind: iekTouchStart,
      position: some(vec2(event.touchX, event.touchY)),
      pointer: event.pointer
    ))
  of sekTouchMove:
    result = some(InputEvent(
      kind: iekTouchMove,
      position: some(vec2(event.touchX, event.touchY)),
      delta: some(vec2(event.touchDx, event.touchDy)),
      pointer: event.pointer
    ))
  of sekTouchEnd:
    result = some(InputEvent(
      kind: iekTouchEnd,
      position: some(vec2(event.touchX, event.touchY)),
      pointer: event.pointer
    ))
  of sekTouchCancel:
    result = some(InputEvent(
      kind: iekTouchCancel,
      position: some(vec2(event.touchX, event.touchY)),
      pointer: event.pointer
    ))
  of sekPenProximityIn, sekPenProximityOut:
    if event.pointer.isSome:
      result = some(penProximityEvent(
        event.kind == sekPenProximityIn, event.pointer.get
      ))
    else:
      result = none(InputEvent)
  of sekPenButtonDown, sekPenButtonUp:
    if event.pointer.isSome:
      result = some(penButtonEvent(
        event.kind == sekPenButtonDown,
        vec2(event.penButtonX, event.penButtonY),
        event.penButton,
        event.pointer.get
      ))
    else:
      result = none(InputEvent)
  else:
    result = none(InputEvent)
  if result.isSome:
    var converted = result.get
    converted.timestamp = event.timestamp
    result = some(converted)

proc sdlError(message: string): ref CatchableError =
  let err = $SDL3.getError()
  if err.len == 0:
    newException(CatchableError, message)
  else:
    newException(CatchableError, message & ": " & err)

proc toByte(value: float32): uint8 =
  uint8(max(0, min(255, int(round(value * 255.0'f32)))))

proc toSdl(rect: Rect): SDL_FRect =
  SDL_FRect(x: cfloat(rect.x), y: cfloat(rect.y), w: cfloat(rect.w), h: cfloat(rect.h))

proc toSdlClip(rect: Rect): SDL_Rect =
  SDL_Rect(
    x: cint(floor(rect.x)),
    y: cint(floor(rect.y)),
    w: cint(ceil(rect.w)),
    h: cint(ceil(rect.h))
  )

proc intersect(a, b: SDL_Rect): SDL_Rect =
  let x1 = max(a.x, b.x)
  let y1 = max(a.y, b.y)
  let x2 = min(a.x + a.w, b.x + b.w)
  let y2 = min(a.y + a.h, b.y + b.h)
  SDL_Rect(x: x1, y: y1, w: max(0, x2 - x1), h: max(0, y2 - y1))

proc setColor(renderer: pointer; color: Color) =
  discard SDL3.setRenderDrawColor(
    renderer,
    color.r.toByte,
    color.g.toByte,
    color.b.toByte,
    color.a.toByte
  )

proc setColor(renderer: pointer; color: Color; alphaMultiplier: float32) =
  discard SDL3.setRenderDrawColor(
    renderer,
    color.r.toByte,
    color.g.toByte,
    color.b.toByte,
    (color.a * max(0.0'f32, min(1.0'f32, alphaMultiplier))).toByte
  )

proc setClip(renderer: pointer; clip: Option[SDL_Rect]) =
  if clip.isSome:
    var rect = clip.get
    discard SDL3.setRenderClipRect(renderer, addr rect)
  else:
    discard SDL3.setRenderClipRect(renderer, nil)

proc destroyTextCache(target: var Sdl3Renderer) =
  for entry in target.textCache:
    if not entry.texture.isNil:
      SDL3.destroyTexture(entry.texture)
  target.textCache.setLen(0)
  target.textCacheIndex.clear()
  target.textCacheBytes = 0
  for texture in target.transientTextTextures:
    if not texture.isNil:
      SDL3.destroyTexture(texture)
  target.transientTextTextures.setLen(0)

proc destroyTransientTextTextures(target: var Sdl3Renderer) =
  for texture in target.transientTextTextures:
    if not texture.isNil:
      SDL3.destroyTexture(texture)
  target.transientTextTextures.setLen(0)

proc destroyImageCache(target: var Sdl3Renderer) =
  for entry in target.imageCache:
    if not entry.texture.isNil:
      SDL3.destroyTexture(entry.texture)
  target.imageCache.setLen(0)
  target.imageCacheIndex.clear()
  target.imageCacheBytes = 0
  target.imageFailures.setLen(0)
  target.reportedImageEventKeys.setLen(0)

proc destroyRoundedTextureCache(target: var Sdl3Renderer) =
  for entry in target.roundedTextureCache:
    if not entry.texture.isNil:
      SDL3.destroyTexture(entry.texture)
  target.roundedTextureCache.setLen(0)
  target.roundedTextureCacheIndex.clear()
  target.roundedTextureCacheBytes = 0

proc destroyShadowTextureCache(target: var Sdl3Renderer) =
  for entry in target.shadowTextureCache:
    if not entry.texture.isNil:
      SDL3.destroyTexture(entry.texture)
  target.shadowTextureCache.setLen(0)
  target.shadowTextureCacheIndex.clear()
  target.shadowTextureCacheBytes = 0

proc destroyTransformTextureCache(target: var Sdl3Renderer) =
  for entry in target.transformTextureCache:
    if not entry.texture.isNil:
      SDL3.destroyTexture(entry.texture)
  target.transformTextureCache.setLen(0)
  target.transformTextureCacheBytes = 0

proc destroyStaticLayer(target: var Sdl3Renderer) =
  if not target.staticLayerTexture.isNil:
    SDL3.destroyTexture(target.staticLayerTexture)
    target.staticLayerTexture = nil
  target.staticLayerWidth = 0
  target.staticLayerHeight = 0

proc destroyCursorCache(target: var Sdl3Renderer) =
  for cursor in CursorKind:
    if target.ownsCursor[cursor] and not target.cursorCache[cursor].isNil:
      SDL3.destroyCursor(target.cursorCache[cursor])
    target.cursorCache[cursor] = nil
    target.ownsCursor[cursor] = false

proc imeImplementedUiHint*(mode: Sdl3ImeUiMode): string =
  case mode
  of siuNative:
    "none"
  of siuComposition:
    "composition"
  of siuCompositionAndCandidates:
    "composition,candidates"

proc initSdl3Renderer*(
    title: string;
    width, height: int;
    resizable = true;
    imeUi = siuNative
): Sdl3Renderer =
  when defined(linux):
    if sdl3PreferWaylandOnWaylandSession and
        getEnv("SDL_VIDEODRIVER").len == 0 and
        getEnv("WAYLAND_DISPLAY").len > 0:
      discard SDL3.setHint(sdlHintVideoDriver, "wayland")
  let imeHint = imeUi.imeImplementedUiHint()
  discard SDL3.setHint(sdlHintImeImplementedUi, imeHint.cstring)
  # Native CBSS controls should activate on the click that focuses the window,
  # matching the interaction users expect from browser form controls.
  discard SDL3.setHint(sdlHintMouseFocusClickthrough, "1")
  if not SDL3.init(sdlInitVideo):
    raise sdlError("SDL3 init failed")
  when defined(cbssTraceSdl3):
    let driver = SDL3.getCurrentVideoDriver()
    echo "[cbss sdl3] videoDriver=", (if driver.isNil: "" else: $driver)

  let flags =
    (if resizable: sdlWindowResizable else: SDL_WindowFlags(0)) or
    sdlWindowHighPixelDensity or
    sdlWindowHidden
  if not SDL3.createWindowAndRenderer(
      title.cstring,
      cint(width),
      cint(height),
      flags,
      addr result.window,
      addr result.renderer
  ):
    SDL3.quit()
    raise sdlError("SDL3 window and renderer creation failed")
  discard SDL3.setRenderDrawBlendMode(result.renderer, sdlBlendModeBlend)
  let rendererName = SDL3.getRendererName(result.renderer)
  result.premultipliedLayerBlend =
    not rendererName.isNil and $rendererName != "software"
  if not SDL3.showWindow(result.window):
    SDL3.destroyRenderer(result.renderer)
    SDL3.destroyWindow(result.window)
    SDL3.quit()
    raise sdlError("SDL3 window display failed")
  result.assetResolver = initAssetResolver([getCurrentDir()])
  result.textCacheIndex = initTable[Hash, seq[int]]()
  result.imageCacheIndex = initTable[Hash, seq[int]]()
  result.roundedTextureCacheIndex = initTable[Hash, seq[int]]()
  result.shadowTextureCacheIndex = initTable[Hash, seq[int]]()
  result.penStates = initTable[SDL_PenID, Sdl3PenDeviceState]()
  result.textCacheLimit = 256
  result.imageCacheLimit = 128
  result.roundedTextureCacheLimit = 128
  result.shadowTextureCacheLimit = 128
  result.textCacheByteLimit = defaultTextCacheBytes
  result.imageCacheByteLimit = defaultImageCacheBytes
  result.roundedTextureCacheByteLimit = defaultRoundedTextureCacheBytes
  result.shadowTextureCacheByteLimit = defaultShadowTextureCacheBytes
  result.transformTextureCacheByteLimit = defaultTransformTextureCacheBytes
  result.imeCandidatesEnabled = imeUi == siuCompositionAndCandidates
  result.activeCursor = ckDefault

proc close*(target: var Sdl3Renderer) =
  target.destroyCursorCache()
  target.destroyTextCache()
  target.destroyImageCache()
  target.destroyRoundedTextureCache()
  target.destroyShadowTextureCache()
  target.destroyTransformTextureCache()
  target.destroyStaticLayer()
  if not target.renderer.isNil:
    SDL3.destroyRenderer(target.renderer)
    target.renderer = nil
  if not target.window.isNil:
    discard SDL3.stopTextInput(target.window)
    SDL3.destroyWindow(target.window)
    target.window = nil
  SDL3.quit()

proc windowSize*(target: Sdl3Renderer): Size =
  var w, h: cint
  if SDL3.getWindowSize(target.window, addr w, addr h):
    size(w.float32, h.float32)
  else:
    size(0, 0)

proc setTextInputArea*(target: var Sdl3Renderer; area: Option[Rect]; cursor = 0): bool =
  if target.window.isNil:
    target.textInputArea = area
    target.textInputCursor = cursor
    target.textInputRunning = false
    return false
  if target.textInputArea == area and target.textInputCursor == cursor:
    return true
  target.textInputArea = area
  target.textInputCursor = cursor
  if area.isNone:
    discard SDL3.setTextInputArea(target.window, nil, cint(cursor))
    if target.textInputRunning:
      result = SDL3.stopTextInput(target.window)
      target.textInputRunning = false
      target.composing = false
    return true

  let rect = area.get
  var sdlRect = SDL_Rect(
    x: cint(round(rect.x)),
    y: cint(round(rect.y)),
    w: cint(max(0.0'f32, round(rect.w))),
    h: cint(max(0.0'f32, round(rect.h)))
  )
  discard SDL3.setTextInputArea(target.window, addr sdlRect, cint(cursor))
  if not target.textInputRunning:
    target.textInputRunning = SDL3.startTextInput(target.window)
  if target.textInputRunning:
    discard SDL3.setTextInputArea(target.window, addr sdlRect, cint(cursor))
  target.textInputRunning

proc textInputArea*(target: Sdl3Renderer): Option[Rect] =
  target.textInputArea

proc textInputCursor*(target: Sdl3Renderer): int =
  target.textInputCursor

proc textInputActive*(target: Sdl3Renderer): bool =
  target.textInputRunning

proc setImeCandidatesEnabled*(target: var Sdl3Renderer; enabled: bool) =
  target.imeCandidatesEnabled = enabled

proc interruptTextInput*(target: var Sdl3Renderer): bool =
  if target.window.isNil:
    return false
  var kept: seq[Sdl3Event] = @[]
  for event in target.pendingEvents:
    if event.kind notin {
      sekKeyDown,
      sekKeyUp,
      sekTextInput,
      sekCompositionStart,
      sekCompositionUpdate,
      sekCompositionEnd
    }:
      kept.add event
  target.pendingEvents = kept
  target.composing = false
  target.textInputArea = none(Rect)
  target.textInputCursor = 0
  discard SDL3.setTextInputArea(target.window, nil, 0)
  if target.textInputRunning:
    result = SDL3.stopTextInput(target.window)
    target.textInputRunning = false
  else:
    result = true
  SDL3.pumpEvents()
  SDL3.flushEvents(uint32(SDL_EVENT_KEY_DOWN), uint32(SDL_EVENT_TEXT_EDITING_CANDIDATES))

proc clearTextComposition*(target: var Sdl3Renderer): bool =
  if target.window.isNil:
    return false
  target.composing = false
  result = SDL3.clearComposition(target.window)
  SDL3.pumpEvents()

proc discardPendingTextInputEvents*(target: var Sdl3Renderer) =
  var kept: seq[Sdl3Event] = @[]
  for event in target.pendingEvents:
    if event.kind notin {
      sekTextInput,
      sekCompositionStart,
      sekCompositionUpdate,
      sekCompositionEnd,
      sekCompositionCandidates
    }:
      kept.add event
  target.pendingEvents = kept
  target.composing = false
  SDL3.pumpEvents()
  SDL3.flushEvents(uint32(SDL_EVENT_TEXT_EDITING), uint32(SDL_EVENT_TEXT_EDITING_CANDIDATES))

proc toSdlCursor(cursor: CursorKind): SDL_SystemCursor =
  case cursor
  of ckText:
    SDL_SYSTEM_CURSOR_TEXT
  of ckPointer:
    SDL_SYSTEM_CURSOR_POINTER
  of ckMove:
    SDL_SYSTEM_CURSOR_MOVE
  of ckNotAllowed:
    SDL_SYSTEM_CURSOR_NOT_ALLOWED
  of ckAuto, ckDefault:
    SDL_SYSTEM_CURSOR_DEFAULT

proc cursorPointer(target: var Sdl3Renderer; cursor: CursorKind): pointer =
  if cursor in {ckAuto, ckDefault}:
    return SDL3.getDefaultCursor()
  if target.cursorCache[cursor].isNil:
    target.cursorCache[cursor] = SDL3.createSystemCursor(cursor.toSdlCursor)
    target.ownsCursor[cursor] = not target.cursorCache[cursor].isNil
  target.cursorCache[cursor]

proc setCursor*(target: var Sdl3Renderer; cursor: CursorKind) =
  let effective = if cursor == ckAuto: ckDefault else: cursor
  if target.activeCursor == effective:
    return
  let sdlCursor = target.cursorPointer(effective)
  if not sdlCursor.isNil:
    discard SDL3.setCursor(sdlCursor)
    target.activeCursor = effective

proc reapplyActiveCursor(target: var Sdl3Renderer) =
  let effective =
    if target.activeCursor == ckAuto: ckDefault
    else: target.activeCursor
  let sdlCursor = target.cursorPointer(effective)
  if not sdlCursor.isNil:
    discard SDL3.setCursor(sdlCursor)

proc activeCursor*(target: Sdl3Renderer): CursorKind =
  target.activeCursor

proc renderOutputSize*(target: Sdl3Renderer): Size =
  var w, h: cint
  if SDL3.getRenderOutputSize(target.renderer, addr w, addr h):
    size(w.float32, h.float32)
  else:
    size(0, 0)

proc requestFrameCapture*(target: var Sdl3Renderer) =
  target.captureNextFrame = true
  target.capturedFrame = none(Sdl3CapturedFrame)

proc capturedFrame*(target: Sdl3Renderer): Option[Sdl3CapturedFrame] =
  target.capturedFrame

proc captureCurrentFrame(target: var Sdl3Renderer) =
  if not target.captureNextFrame:
    return
  target.captureNextFrame = false
  target.capturedFrame = none(Sdl3CapturedFrame)
  let output = target.renderOutputSize()
  let width = int(output.w)
  let height = int(output.h)
  if width <= 0 or height <= 0:
    return
  let surface = SDL3.renderReadPixels(target.renderer, nil)
  if surface.isNil:
    return
  defer:
    SDL3.destroySurface(surface)
  var frame = Sdl3CapturedFrame(width: width, height: height, pixels: newSeq[uint8](width * height * 3))
  for y in 0 ..< height:
    for x in 0 ..< width:
      var r, g, b, a: uint8
      let offset = (y * width + x) * 3
      if SDL3.readSurfacePixel(surface, cint(x), cint(y), addr r, addr g, addr b, addr a):
        frame.pixels[offset] = r
        frame.pixels[offset + 1] = g
        frame.pixels[offset + 2] = b
  target.capturedFrame = some(frame)

proc pixelScale*(target: Sdl3Renderer): float32 =
  let logical = target.windowSize()
  var pixelWidth, pixelHeight: cint
  if logical.w <= 0 or logical.h <= 0 or
      not SDL3.getWindowSizeInPixels(target.window, addr pixelWidth, addr pixelHeight):
    return 1.0'f32
  let scale = min(
    pixelWidth.float32 / logical.w,
    pixelHeight.float32 / logical.h
  )
  max(1.0'f32, round(scale * 100.0'f32) / 100.0'f32)

proc updateLogicalPresentation(target: Sdl3Renderer) =
  let logical = target.windowSize()
  if logical.w <= 0 or logical.h <= 0:
    return
  discard SDL3.setRenderLogicalPresentation(
    target.renderer,
    cint(round(logical.w)),
    cint(round(logical.h)),
    SDL_LOGICAL_PRESENTATION_STRETCH
  )

proc touchPoint(target: Sdl3Renderer; x, y: cfloat): Vec2 =
  let viewport = target.windowSize()
  vec2(x.float32 * viewport.w, y.float32 * viewport.h)

const
  sdlPenInputDown = 1'u32 shl 0
  sdlPenInputButtonMask = 0x1f'u32 shl 1
  sdlPenInputEraserTip = 1'u32 shl 30
  sdlPenInputInProximity = 1'u32 shl 31

proc penState(
    target: var Sdl3Renderer;
    deviceId: SDL_PenID
): var Sdl3PenDeviceState =
  target.penStates.mgetOrPut(
    deviceId,
    Sdl3PenDeviceState(pointer: PointerData(
      device: pdkPenUnknown,
      deviceId: uint64(deviceId),
      primary: true
    ))
  )

proc applyPenFlags*(pointer: var PointerData; flags: SDL_PenInputFlags) =
  let value = uint32(flags)
  pointer.contact = (value and sdlPenInputDown) != 0
  pointer.buttons = (value and sdlPenInputButtonMask) shr 1
  pointer.eraser = (value and sdlPenInputEraserTip) != 0
  pointer.inProximity = pointer.contact or
    (value and sdlPenInputInProximity) != 0

proc applyPenAxis*(pointer: var PointerData; axis: SDL_PenAxis; value: float32) =
  if value.classify in {fcNan, fcInf, fcNegInf}:
    return
  case axis
  of SDL_PEN_AXIS_PRESSURE:
    pointer.axes.incl paPressure
    pointer.pressure = clamp(value, 0.0'f32, 1.0'f32)
  of SDL_PEN_AXIS_XTILT:
    pointer.axes.incl paTiltX
    pointer.tiltX = clamp(value, -90.0'f32, 90.0'f32)
  of SDL_PEN_AXIS_YTILT:
    pointer.axes.incl paTiltY
    pointer.tiltY = clamp(value, -90.0'f32, 90.0'f32)
  of SDL_PEN_AXIS_DISTANCE:
    pointer.axes.incl paDistance
    pointer.distance = clamp(value, 0.0'f32, 1.0'f32)
  of SDL_PEN_AXIS_ROTATION:
    pointer.axes.incl paRotation
    pointer.rotation = clamp(value, -180.0'f32, 180.0'f32)
  of SDL_PEN_AXIS_SLIDER:
    pointer.axes.incl paSlider
    pointer.slider = clamp(value, 0.0'f32, 1.0'f32)
  of SDL_PEN_AXIS_TANGENTIAL_PRESSURE:
    pointer.axes.incl paTangentialPressure
    pointer.tangentialPressure = clamp(value, -1.0'f32, 1.0'f32)
  of SDL_PEN_AXIS_COUNT:
    discard

proc printableKey(keycode: SDL_Keycode): string =
  let value = int(keycode)
  case value
  of 8:
    "Backspace"
  of 9:
    "Tab"
  of 13:
    "Enter"
  of 27:
    "Escape"
  of 127:
    "Delete"
  of 0x4000003a:
    "F1"
  of 0x4000003b:
    "F2"
  of 0x4000003c:
    "F3"
  of 0x4000003d:
    "F4"
  of 0x4000003e:
    "F5"
  of 0x4000003f:
    "F6"
  of 0x40000040:
    "F7"
  of 0x40000041:
    "F8"
  of 0x40000042:
    "F9"
  of 0x40000043:
    "F10"
  of 0x40000044:
    "F11"
  of 0x40000045:
    "F12"
  of 0x4000004a:
    "Home"
  of 0x4000004d:
    "End"
  of 0x4000004f:
    "ArrowRight"
  of 0x40000050:
    "ArrowLeft"
  of 0x40000051:
    "ArrowDown"
  of 0x40000052:
    "ArrowUp"
  else:
    if value >= 32 and value <= 126:
      ($char(value)).toLowerAscii()
    else:
      $value

proc keyMod(raw: SDL_Keymod; mask: uint16): bool =
  (uint16(raw) and mask) != 0

proc pollEventFromRaw(
    target: var Sdl3Renderer;
    event: var Sdl3Event;
    firstRaw: ptr SDL_Event
): bool =
  const
    keymodLShift = 0x0001'u16
    keymodRShift = 0x0002'u16
    keymodLCtrl = 0x0040'u16
    keymodRCtrl = 0x0080'u16
    keymodLAlt = 0x0100'u16
    keymodRAlt = 0x0200'u16
    keymodLGui = 0x0400'u16
    keymodRGui = 0x0800'u16

  if target.pendingEvents.len > 0:
    event = target.pendingEvents[0]
    target.pendingEvents.delete(0)
    return true

  var raw: SDL_Event
  var hasRaw = not firstRaw.isNil
  if hasRaw:
    raw = firstRaw[]
  while hasRaw or SDL3.pollEvent(addr raw):
    hasRaw = false
    if sdl3StreamWakeEventType != 0 and
        raw.`type` == sdl3StreamWakeEventType and
        raw.user.code == sdl3StreamWakeEventCode:
      event = Sdl3Event(
        kind: sekStreamWake,
        timestamp: raw.user.timestamp,
        wakeToken: uint32(cast[uint](raw.user.data1))
      )
      return true
    case SDL_EventType(raw.`type`)
    of SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      event = Sdl3Event(kind: sekQuit, timestamp: raw.common.timestamp)
      return true
    of SDL_EVENT_WINDOW_EXPOSED:
      event = Sdl3Event(kind: sekExpose, timestamp: raw.window.timestamp)
      return true
    of SDL_EVENT_WINDOW_RESIZED, SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
      let current = target.windowSize()
      event = Sdl3Event(kind: sekResize, timestamp: raw.window.timestamp, width: int(current.w), height: int(current.h))
      return true
    of SDL_EVENT_WINDOW_FOCUS_GAINED:
      event = Sdl3Event(kind: sekFocus, timestamp: raw.window.timestamp)
      return true
    of SDL_EVENT_WINDOW_FOCUS_LOST:
      event = Sdl3Event(kind: sekBlur, timestamp: raw.window.timestamp)
      return true
    of SDL_EVENT_WINDOW_MOUSE_ENTER:
      # Client-side decorations own the cursor while it is over the frame.
      # Reapply the cached application cursor when control returns to content.
      target.reapplyActiveCursor()
    of SDL_EVENT_MOUSE_MOTION:
      if raw.motion.which in [SDL_TOUCH_MOUSEID, SDL_PEN_MOUSEID]:
        continue
      event = Sdl3Event(
        kind: sekPointerMove,
        timestamp: raw.motion.timestamp,
        x: raw.motion.x.float32,
        y: raw.motion.y.float32,
        pointer: some(PointerData(device: pdkMouse, primary: true))
      )
      return true
    of SDL_EVENT_MOUSE_BUTTON_DOWN:
      if raw.button.which in [SDL_TOUCH_MOUSEID, SDL_PEN_MOUSEID]:
        continue
      event = Sdl3Event(
        kind: sekPointerDown,
        timestamp: raw.button.timestamp,
        button: int(raw.button.button),
        buttonX: raw.button.x.float32,
        buttonY: raw.button.y.float32,
        pointer: some(PointerData(
          device: pdkMouse,
          buttons:
            if raw.button.button >= 1 and raw.button.button <= 32:
              1'u32 shl (uint32(raw.button.button) - 1)
            else:
              0'u32,
          contact: true,
          primary: true,
          inProximity: true
        ))
      )
      return true
    of SDL_EVENT_MOUSE_BUTTON_UP:
      if raw.button.which in [SDL_TOUCH_MOUSEID, SDL_PEN_MOUSEID]:
        continue
      event = Sdl3Event(
        kind: sekPointerUp,
        timestamp: raw.button.timestamp,
        button: int(raw.button.button),
        buttonX: raw.button.x.float32,
        buttonY: raw.button.y.float32,
        pointer: some(PointerData(
          device: pdkMouse,
          primary: true,
          inProximity: true
        ))
      )
      return true
    of SDL_EVENT_KEY_DOWN:
      event = Sdl3Event(
        kind: sekKeyDown,
        timestamp: raw.key.timestamp,
        key: printableKey(raw.key.key),
        repeat: raw.key.repeat,
        ctrl: raw.key.`mod`.keyMod(keymodLCtrl) or raw.key.`mod`.keyMod(keymodRCtrl),
        alt: raw.key.`mod`.keyMod(keymodLAlt) or raw.key.`mod`.keyMod(keymodRAlt),
        shift: raw.key.`mod`.keyMod(keymodLShift) or raw.key.`mod`.keyMod(keymodRShift),
        meta: raw.key.`mod`.keyMod(keymodLGui) or raw.key.`mod`.keyMod(keymodRGui)
      )
      return true
    of SDL_EVENT_KEY_UP:
      event = Sdl3Event(
        kind: sekKeyUp,
        timestamp: raw.key.timestamp,
        key: printableKey(raw.key.key),
        repeat: raw.key.repeat,
        ctrl: raw.key.`mod`.keyMod(keymodLCtrl) or raw.key.`mod`.keyMod(keymodRCtrl),
        alt: raw.key.`mod`.keyMod(keymodLAlt) or raw.key.`mod`.keyMod(keymodRAlt),
        shift: raw.key.`mod`.keyMod(keymodLShift) or raw.key.`mod`.keyMod(keymodRShift),
        meta: raw.key.`mod`.keyMod(keymodLGui) or raw.key.`mod`.keyMod(keymodRGui)
      )
      return true
    of SDL_EVENT_TEXT_EDITING:
      let text =
        if raw.edit.text.isNil: ""
        else: $raw.edit.text
      if not target.composing:
        target.composing = true
        target.pendingEvents.add Sdl3Event(kind: sekCompositionUpdate, timestamp: raw.edit.timestamp, text: text)
        event = Sdl3Event(kind: sekCompositionStart, timestamp: raw.edit.timestamp, text: text)
      else:
        event = Sdl3Event(kind: sekCompositionUpdate, timestamp: raw.edit.timestamp, text: text)
      return true
    of SDL_EVENT_TEXT_INPUT:
      let text =
        if raw.text.text.isNil: ""
        else: $raw.text.text
      if target.composing:
        target.composing = false
        target.pendingEvents.add Sdl3Event(kind: sekTextInput, timestamp: raw.text.timestamp, text: text)
        event = Sdl3Event(kind: sekCompositionEnd, timestamp: raw.text.timestamp, text: text)
        return true
      event = Sdl3Event(
        kind: sekTextInput,
        timestamp: raw.text.timestamp,
        text: text
      )
      return true
    of SDL_EVENT_TEXT_EDITING_CANDIDATES:
      if not target.imeCandidatesEnabled:
        continue
      var candidates: seq[string] = @[]
      let count = min(64, max(0, int(raw.edit_candidates.num_candidates)))
      if count > 0 and not raw.edit_candidates.candidates.isNil:
        for index in 0 ..< count:
          let item = raw.edit_candidates.candidates[index]
          candidates.add(if item.isNil: "" else: $item)
      event = Sdl3Event(
        kind: sekCompositionCandidates,
        timestamp: raw.edit_candidates.timestamp,
        candidates: candidates,
        selectedCandidate: int(raw.edit_candidates.selected_candidate),
        horizontalCandidates: raw.edit_candidates.horizontal
      )
      return true
    of SDL_EVENT_MOUSE_WHEEL:
      let directionFlipped = raw.wheel.direction == SDL_MOUSEWHEEL_FLIPPED
      event = Sdl3Event(
        kind: sekWheel,
        timestamp: raw.wheel.timestamp,
        wheelX: normalizedWheelAxis(raw.wheel.x.float32, directionFlipped),
        wheelY: normalizedWheelAxis(raw.wheel.y.float32, directionFlipped),
        wheelMouseX: raw.wheel.mouse_x.float32,
        wheelMouseY: raw.wheel.mouse_y.float32
      )
      return true
    of SDL_EVENT_FINGER_DOWN:
      if raw.tfinger.touchID in [SDL_MOUSE_TOUCHID, SDL_PEN_TOUCHID]:
        continue
      let point = target.touchPoint(raw.tfinger.x, raw.tfinger.y)
      event = Sdl3Event(
        kind: sekTouchStart,
        timestamp: raw.tfinger.timestamp,
        touchX: point.x,
        touchY: point.y,
        touchDx: 0,
        touchDy: 0,
        pointer: some(touchPointerData(
          uint64(raw.tfinger.fingerID), raw.tfinger.pressure, true
        ))
      )
      return true
    of SDL_EVENT_FINGER_MOTION:
      if raw.tfinger.touchID in [SDL_MOUSE_TOUCHID, SDL_PEN_TOUCHID]:
        continue
      let point = target.touchPoint(raw.tfinger.x, raw.tfinger.y)
      let delta = target.touchPoint(raw.tfinger.dx, raw.tfinger.dy)
      event = Sdl3Event(
        kind: sekTouchMove,
        timestamp: raw.tfinger.timestamp,
        touchX: point.x,
        touchY: point.y,
        touchDx: delta.x,
        touchDy: delta.y,
        pointer: some(touchPointerData(
          uint64(raw.tfinger.fingerID), raw.tfinger.pressure, true
        ))
      )
      return true
    of SDL_EVENT_FINGER_UP:
      if raw.tfinger.touchID in [SDL_MOUSE_TOUCHID, SDL_PEN_TOUCHID]:
        continue
      let point = target.touchPoint(raw.tfinger.x, raw.tfinger.y)
      event = Sdl3Event(
        kind: sekTouchEnd,
        timestamp: raw.tfinger.timestamp,
        touchX: point.x,
        touchY: point.y,
        touchDx: 0,
        touchDy: 0,
        pointer: some(touchPointerData(
          uint64(raw.tfinger.fingerID), 0, false
        ))
      )
      return true
    of SDL_EVENT_FINGER_CANCELED:
      if raw.tfinger.touchID in [SDL_MOUSE_TOUCHID, SDL_PEN_TOUCHID]:
        continue
      let point = target.touchPoint(raw.tfinger.x, raw.tfinger.y)
      event = Sdl3Event(
        kind: sekTouchCancel,
        timestamp: raw.tfinger.timestamp,
        touchX: point.x,
        touchY: point.y,
        touchDx: 0,
        touchDy: 0,
        pointer: some(touchPointerData(
          uint64(raw.tfinger.fingerID), 0, false
        ))
      )
      return true
    of SDL_EVENT_PEN_PROXIMITY_IN, SDL_EVENT_PEN_PROXIMITY_OUT:
      let deviceId = raw.pproximity.which
      var state = target.penState(deviceId)
      let inside = SDL_EventType(raw.`type`) == SDL_EVENT_PEN_PROXIMITY_IN
      state.pointer.inProximity = inside
      if not inside:
        state.pointer.contact = false
        state.pointer.pressure = 0
      else:
        target.penStates[deviceId] = state
      event = Sdl3Event(
        kind: if inside: sekPenProximityIn else: sekPenProximityOut,
        timestamp: raw.pproximity.timestamp,
        pointer: some(state.pointer)
      )
      if not inside:
        target.penStates.del(deviceId)
      return true
    of SDL_EVENT_PEN_DOWN, SDL_EVENT_PEN_UP:
      var state = target.penState(raw.ptouch.which)
      state.position = vec2(raw.ptouch.x, raw.ptouch.y)
      state.pointer.applyPenFlags(raw.ptouch.pen_state)
      state.pointer.contact = raw.ptouch.down
      state.pointer.eraser = raw.ptouch.eraser or state.pointer.eraser
      state.pointer.inProximity = true
      if not state.pointer.contact and paPressure in state.pointer.axes:
        state.pointer.pressure = 0
      target.penStates[raw.ptouch.which] = state
      if raw.ptouch.down:
        event = Sdl3Event(
          kind: sekPointerDown,
          timestamp: raw.ptouch.timestamp,
          button: 0,
          buttonX: state.position.x,
          buttonY: state.position.y,
          pointer: some(state.pointer)
        )
      else:
        event = Sdl3Event(
          kind: sekPointerUp,
          timestamp: raw.ptouch.timestamp,
          button: 0,
          buttonX: state.position.x,
          buttonY: state.position.y,
          pointer: some(state.pointer)
        )
      return true
    of SDL_EVENT_PEN_MOTION:
      var state = target.penState(raw.pmotion.which)
      state.position = vec2(raw.pmotion.x, raw.pmotion.y)
      state.pointer.applyPenFlags(raw.pmotion.pen_state)
      state.pointer.inProximity = true
      target.penStates[raw.pmotion.which] = state
      event = Sdl3Event(
        kind: sekPointerMove,
        timestamp: raw.pmotion.timestamp,
        x: state.position.x,
        y: state.position.y,
        pointer: some(state.pointer)
      )
      return true
    of SDL_EVENT_PEN_AXIS:
      var state = target.penState(raw.paxis.which)
      state.position = vec2(raw.paxis.x, raw.paxis.y)
      state.pointer.applyPenFlags(raw.paxis.pen_state)
      state.pointer.applyPenAxis(raw.paxis.axis, raw.paxis.value)
      state.pointer.inProximity = true
      target.penStates[raw.paxis.which] = state
      event = Sdl3Event(
        kind: sekPointerMove,
        timestamp: raw.paxis.timestamp,
        x: state.position.x,
        y: state.position.y,
        pointer: some(state.pointer)
      )
      return true
    of SDL_EVENT_PEN_BUTTON_DOWN, SDL_EVENT_PEN_BUTTON_UP:
      var state = target.penState(raw.pbutton.which)
      state.position = vec2(raw.pbutton.x, raw.pbutton.y)
      state.pointer.applyPenFlags(raw.pbutton.pen_state)
      state.pointer.inProximity = true
      target.penStates[raw.pbutton.which] = state
      if raw.pbutton.down:
        event = Sdl3Event(
          kind: sekPenButtonDown,
          timestamp: raw.pbutton.timestamp,
          penButton: int(raw.pbutton.button),
          penButtonX: state.position.x,
          penButtonY: state.position.y,
          pointer: some(state.pointer)
        )
      else:
        event = Sdl3Event(
          kind: sekPenButtonUp,
          timestamp: raw.pbutton.timestamp,
          penButton: int(raw.pbutton.button),
          penButtonX: state.position.x,
          penButtonY: state.position.y,
          pointer: some(state.pointer)
        )
      return true
    else:
      discard
  false

proc pollEvent*(target: var Sdl3Renderer; event: var Sdl3Event): bool =
  target.pollEventFromRaw(event, nil)

proc waitEventTimeout*(
    target: var Sdl3Renderer;
    event: var Sdl3Event;
    timeoutMs: int
): bool =
  ## Waits without changing SDL queue order. Pending synthetic events remain
  ## ahead of newly received platform events.
  if target.pendingEvents.len > 0:
    return target.pollEvent(event)

  var raw: SDL_Event
  let received =
    if timeoutMs < 0:
      SDL3.waitEvent(addr raw)
    else:
      SDL3.waitEventTimeout(addr raw, int32(min(timeoutMs, int(int32.high))))
  if not received:
    return false
  target.pollEventFromRaw(event, addr raw)

proc waitEvent*(target: var Sdl3Renderer; event: var Sdl3Event): bool =
  target.waitEventTimeout(event, -1)

proc registerSdl3StreamWake*(): uint32 =
  ## Registers one process-wide user event. Call this on the SDL/UI thread
  ## before handing the resulting callback to a worker-facing mailbox.
  if sdl3StreamWakeEventType == 0:
    sdl3StreamWakeEventType = SDL3.registerEvents(1)
  sdl3StreamWakeEventType

proc allocateSdl3StreamWakeToken*(): uint32 =
  ## Token allocation is intentionally UI-thread-owned. Only the immutable
  ## token crosses into worker callbacks.
  if registerSdl3StreamWake() == 0:
    return 0
  result = nextSdl3StreamWakeToken
  inc nextSdl3StreamWakeToken
  if nextSdl3StreamWakeToken == 0:
    nextSdl3StreamWakeToken = 1

proc postSdl3StreamWake*(token: uint32): bool {.gcsafe, raises: [].} =
  ## SDL copies the event. `data1` contains only an integer token, never a Nim
  ## object address or an ownership-bearing foreign pointer.
  if token == 0 or sdl3StreamWakeEventType == 0:
    return false
  var raw: SDL_Event
  raw.user.`type` = sdl3StreamWakeEventType
  raw.user.code = sdl3StreamWakeEventCode
  raw.user.data1 = cast[pointer](uint(token))
  SDL3.pushEvent(addr raw)

proc delay*(ms: int) =
  SDL3.delay(uint32(max(0, ms)))

proc clipboardText*(): string =
  let raw = SDL3.getClipboardText()
  if raw.isNil:
    return ""
  result = $raw
  SDL3.free(cast[pointer](raw))

proc clipboardText*(maxBytes: int): string =
  let raw = SDL3.getClipboardText()
  if raw.isNil:
    return ""
  defer: SDL3.free(cast[pointer](raw))
  if maxBytes <= 0:
    return ""

  var copied = 0
  while copied < maxBytes and raw[copied] != '\0':
    inc copied
  var stop = copied
  while stop > 0 and (ord(raw[stop]) and 0b1100_0000) == 0b1000_0000:
    dec stop
  if stop <= 0:
    return ""
  result = newString(stop)
  for index in 0 ..< stop:
    result[index] = raw[index]

proc setClipboardText*(text: string): bool =
  SDL3.setClipboardText(text.cstring)

proc textColorKey(color: Color): string =
  $color.r & "," & $color.g & "," & $color.b & "," & $color.a

proc scaleTextStyle(style: ComputedTextStyle; scale: float32): ComputedTextStyle =
  result = style
  if scale <= 0 or abs(scale - 1.0'f32) < 0.001'f32:
    return
  if result.fontSize.isSome:
    result.fontSize = some(result.fontSize.get * scale)
  if result.lineHeight.isSome:
    result.lineHeight = some(result.lineHeight.get * scale)
  if result.letterSpacing.isSome:
    result.letterSpacing = some(result.letterSpacing.get * scale)
  if result.wordSpacing.isSome:
    result.wordSpacing = some(result.wordSpacing.get * scale)
  if result.textDecorationThickness.isSome:
    result.textDecorationThickness = some(result.textDecorationThickness.get * scale)
  if result.textIndent.isSome:
    result.textIndent = some(result.textIndent.get * scale)

proc clearImageCache*(target: var Sdl3Renderer) =
  target.destroyImageCache()
  target.destroyRoundedTextureCache()

proc assetRoots*(target: Sdl3Renderer): seq[string] =
  target.assetResolver.roots

proc setAssetRoots*(target: var Sdl3Renderer; roots: openArray[string]) =
  target.assetResolver = initAssetResolver(roots)
  target.clearImageCache()

proc addAssetRoot*(target: var Sdl3Renderer; root: string) =
  target.assetResolver = target.assetResolver.withRoot(root)
  target.clearImageCache()

proc resolveAssetPath*(target: Sdl3Renderer; source: string): string =
  target.assetResolver.resolveAssetPath(source)

proc imageEventKey(node: NodeId; source: string; kind: Sdl3ImageEventKind): string =
  $node.nodeIndex & "|" & source & "|" & $kind

proc queueImageEvent(target: var Sdl3Renderer; node: NodeId; source: string; kind: Sdl3ImageEventKind) =
  let key = imageEventKey(node, source, kind)
  for reported in target.reportedImageEventKeys:
    if reported == key:
      return
  target.reportedImageEventKeys.add key
  target.imageEvents.add Sdl3ImageEvent(kind: kind, node: node, source: source)

proc takeImageEvents*(target: var Sdl3Renderer): seq[Sdl3ImageEvent] =
  result = target.imageEvents
  target.imageEvents.setLen(0)

proc roundedSpan(rect: Rect; radius, centerY: float32; x1, x2: var float32): bool
proc renderTextureClipped(target: Sdl3Renderer; texture: pointer; src, dst: SDL_FRect)
proc renderTextureClippedWith(
    target: Sdl3Renderer;
    texture: pointer;
    src, dst: SDL_FRect;
    clips: openArray[Sdl3ClipRegion]
)

proc clipRegion(command: PaintCommand): Sdl3ClipRegion =
  Sdl3ClipRegion(
    rect: command.clipRect,
    radius: command.clipRadius,
    bounds: command.clipRect.toSdlClip
  )

proc hasRoundedClip(clips: openArray[Sdl3ClipRegion]): bool =
  for clip in clips:
    if clip.radius > 0.001'f32:
      return true
  false

proc prepareRenderPlan(commands: openArray[PaintCommand]): seq[Sdl3PreparedCommand] =
  var clipStack: seq[Sdl3ClipRegion]
  var transformClipStacks: seq[seq[Sdl3ClipRegion]]
  for command in commands:
    case command.kind
    of pcPushTransform, pcPushLayer:
      result.add Sdl3PreparedCommand(command: command)
      transformClipStacks.add clipStack
      clipStack = @[]
    of pcPopTransform, pcPopLayer:
      result.add Sdl3PreparedCommand(command: command)
      if transformClipStacks.len > 0:
        clipStack = transformClipStacks.pop()
      else:
        clipStack = @[]
    of pcPushClip:
      clipStack.add command.clipRegion()
      result.add Sdl3PreparedCommand(command: command)
    of pcPopClip:
      result.add Sdl3PreparedCommand(command: command)
      if clipStack.len > 0:
        clipStack.setLen(clipStack.len - 1)
    of pcDrawImage:
      var roundedClips: seq[Sdl3ClipRegion]
      if clipStack.hasRoundedClip():
        for clip in clipStack:
          roundedClips.add clip
      result.add Sdl3PreparedCommand(command: command, roundedImageClipStack: roundedClips)
    else:
      result.add Sdl3PreparedCommand(command: command)

proc effectiveClipBounds(target: Sdl3Renderer): Option[SDL_Rect] =
  if target.clipStack.len == 0:
    return none(SDL_Rect)
  result = some(target.clipStack[0].bounds)
  for index in 1 ..< target.clipStack.len:
    result = some(intersect(result.get, target.clipStack[index].bounds))

proc hasRoundedClip(target: Sdl3Renderer): bool =
  target.clipStack.hasRoundedClip()

proc translated(command: PaintCommand; offset: Vec2): PaintCommand =
  result = command
  case result.kind
  of pcPushTransform:
    result.transformBounds = result.transformBounds.translated(offset)
  of pcPushLayer:
    result.layerBounds = result.layerBounds.translated(offset)
  of pcPopTransform, pcPopLayer, pcPopClip:
    discard
  of pcPushClip:
    result.clipRect = result.clipRect.translated(offset)
  of pcBoxShadow:
    result.shadowRect = result.shadowRect.translated(offset)
  of pcFillRect:
    result.rect = result.rect.translated(offset)
  of pcFillLinearGradient:
    result.gradientRect = result.gradientRect.translated(offset)
    result.gradientPaintRect = result.gradientPaintRect.translated(offset)
    result.gradientClipRect = result.gradientClipRect.translated(offset)
  of pcStrokeRect:
    result.strokeRect = result.strokeRect.translated(offset)
  of pcStrokePath:
    result.path = result.path.translated(offset)
  of pcDrawText:
    result.position = result.position.translated(offset)
  of pcDrawImage:
    result.imageRect = result.imageRect.translated(offset)

proc translated(region: Sdl3ClipRegion; offset: Vec2): Sdl3ClipRegion =
  result = region
  result.rect = result.rect.translated(offset)
  result.bounds = result.rect.toSdlClip

proc activeTransformOffset(layers: openArray[Sdl3TransformLayer]): Vec2 =
  for index in countdown(layers.high, 0):
    if layers[index].valid:
      return vec2(-layers[index].sourceBounds.x, -layers[index].sourceBounds.y)
  vec2(0, 0)

proc localPreparedCommand(
    prepared: Sdl3PreparedCommand;
    layers: openArray[Sdl3TransformLayer]
): Sdl3PreparedCommand =
  let offset = layers.activeTransformOffset()
  if offset.x == 0 and offset.y == 0:
    return prepared
  result.command = prepared.command.translated(offset)
  for clip in prepared.roundedImageClipStack:
    result.roundedImageClipStack.add clip.translated(offset)

proc acquireTransformTexture(
    target: var Sdl3Renderer;
    width, height: int
): tuple[texture: pointer, index: int] =
  for index in 0 ..< target.transformTextureCache.len:
    if not target.transformTextureCache[index].inUse and
        target.transformTextureCache[index].width == width and
        target.transformTextureCache[index].height == height:
      target.transformTextureCache[index].inUse = true
      target.transformTextureCache[index].lastUsed = target.frameId
      return (target.transformTextureCache[index].texture, index)

  let texture = SDL3.createTexture(
    target.renderer,
    SDL_PIXELFORMAT_RGBA32,
    sdlTextureAccessTarget,
    cint(width),
    cint(height)
  )
  if texture.isNil:
    return (nil, -1)
  discard SDL3.setTextureBlendMode(texture, sdlBlendModeBlend)
  discard SDL3.setTextureScaleMode(texture, SDL_SCALEMODE_LINEAR)
  target.transformTextureCache.add Sdl3TransformTextureCacheEntry(
    texture: texture,
    width: width,
    height: height,
    lastUsed: target.frameId,
    inUse: true
  )
  target.transformTextureCacheBytes += textureBytes(width, height)
  (texture, target.transformTextureCache.high)

proc releaseTransformTexture(target: var Sdl3Renderer; index: int) =
  if index >= 0 and index < target.transformTextureCache.len:
    target.transformTextureCache[index].inUse = false

proc evictTransformTextureCacheIfNeeded(target: var Sdl3Renderer) =
  while target.transformTextureCache.len > 64 or
      (target.transformTextureCache.len > 1 and
        target.transformTextureCacheBytes > target.transformTextureCacheByteLimit):
    var victim = -1
    for index in 0 ..< target.transformTextureCache.len:
      if target.transformTextureCache[index].inUse:
        continue
      if victim < 0 or
          target.transformTextureCache[index].lastUsed <
            target.transformTextureCache[victim].lastUsed:
        victim = index
    if victim < 0:
      return
    SDL3.destroyTexture(target.transformTextureCache[victim].texture)
    target.transformTextureCacheBytes -= textureBytes(
      target.transformTextureCache[victim].width,
      target.transformTextureCache[victim].height
    )
    target.transformTextureCache.delete(victim)

proc beginOffscreenLayer(
    target: var Sdl3Renderer;
    requestedBounds: Rect;
    transform: Affine2D;
    opacity: float32;
    compositeMode: LayerCompositeMode;
    padding: float32;
    layers: var seq[Sdl3TransformLayer]
) =
  for existing in layers:
    if not existing.valid:
      layers.add Sdl3TransformLayer(valid: false)
      return
  var sourceBounds = requestedBounds
  if sourceBounds.isEmpty:
    let viewport = target.windowSize()
    sourceBounds = rect(0, 0, viewport.w, viewport.h)
  sourceBounds = rect(
    floor(sourceBounds.x) - padding,
    floor(sourceBounds.y) - padding,
    ceil(sourceBounds.x + sourceBounds.w) - floor(sourceBounds.x) + padding * 2.0'f32,
    ceil(sourceBounds.y + sourceBounds.h) - floor(sourceBounds.y) + padding * 2.0'f32
  )
  let scale = target.pixelScale()
  let width = max(1, int(ceil(sourceBounds.w * scale)))
  let height = max(1, int(ceil(sourceBounds.h * scale)))
  let acquired = target.acquireTransformTexture(width, height)
  let texture = acquired.texture
  var layer = Sdl3TransformLayer(
    texture: texture,
    previousTarget: SDL3.getRenderTarget(target.renderer),
    previousClips: target.clipStack,
    transform: transform,
    sourceBounds: sourceBounds,
    pixelWidth: width,
    pixelHeight: height,
    textureCacheIndex: acquired.index,
    opacity: clamp(opacity, 0.0'f32, 1.0'f32),
    compositeMode: compositeMode,
    valid: not texture.isNil
  )
  layers.add layer
  if texture.isNil:
    return

  discard SDL3.setRenderTarget(target.renderer, texture)
  discard SDL3.setRenderLogicalPresentation(
    target.renderer, 0, 0, SDL_LOGICAL_PRESENTATION_DISABLED
  )
  discard SDL3.setRenderScale(target.renderer, cfloat(scale), cfloat(scale))
  target.clipStack.setLen(0)
  target.renderer.setClip(none(SDL_Rect))
  discard SDL3.setRenderDrawColor(target.renderer, 0, 0, 0, 0)
  discard SDL3.renderClear(target.renderer)

proc beginTransformLayer(
    target: var Sdl3Renderer;
    command: PaintCommand;
    layers: var seq[Sdl3TransformLayer]
) =
  target.beginOffscreenLayer(
    command.transformBounds,
    command.transform,
    1.0'f32,
    lcmSourceOver,
    1.0'f32,
    layers
  )

proc beginCompositeLayer(
    target: var Sdl3Renderer;
    command: PaintCommand;
    layers: var seq[Sdl3TransformLayer]
) =
  target.beginOffscreenLayer(
    command.layerBounds,
    identityAffine2D(),
    command.layerOpacity,
    command.layerCompositeMode,
    0.0'f32,
    layers
  )

proc markTransformContent(layers: var seq[Sdl3TransformLayer]) =
  for index in countdown(layers.high, 0):
    if layers[index].valid:
      layers[index].hasContent = true
      return

proc renderingSuppressed(layers: openArray[Sdl3TransformLayer]): bool =
  ## Allocation failure must not turn an isolated scope into direct drawing on
  ## its parent. That would silently change both opacity and composition.
  for layer in layers:
    if not layer.valid:
      return true
  false

proc supportsPremultipliedBlend(target: Sdl3Renderer): bool =
  target.premultipliedLayerBlend

proc sdlBlendMode(
    compositeMode: LayerCompositeMode;
    premultiplied: bool
): SDL_BlendMode =
  case compositeMode
  of lcmSourceOver:
    if premultiplied: sdlBlendModeBlendPremultiplied
    else: sdlBlendModeBlend
  of lcmCopy:
    sdlBlendModeNone
  of lcmAdditive:
    if premultiplied: sdlBlendModeAddPremultiplied
    else: sdlBlendModeAdd

proc configureLayerTexture(
    texture: pointer;
    opacity: float32;
    compositeMode: LayerCompositeMode;
    premultiplied: bool
) =
  let resolvedOpacity = clamp(opacity, 0.0'f32, 1.0'f32)
  let colorMultiplier = if premultiplied: resolvedOpacity else: 1.0'f32
  discard SDL3.setTextureColorModFloat(
    texture, cfloat(colorMultiplier), cfloat(colorMultiplier),
    cfloat(colorMultiplier)
  )
  discard SDL3.setTextureAlphaModFloat(texture, cfloat(resolvedOpacity))
  discard SDL3.setTextureBlendMode(
    texture, compositeMode.sdlBlendMode(premultiplied)
  )

proc resetLayerTexture(texture: pointer) =
  discard SDL3.setTextureColorModFloat(texture, 1, 1, 1)
  discard SDL3.setTextureAlphaModFloat(texture, 1)
  discard SDL3.setTextureBlendMode(texture, sdlBlendModeBlend)

proc renderAffineLayer(
    target: var Sdl3Renderer;
    texture: pointer;
    source: var SDL_FRect;
    origin, right, down: Vec2;
    opacity: float32;
    compositeMode: LayerCompositeMode
) =
  let premultiplied = target.supportsPremultipliedBlend()
  if not target.hasRoundedClip():
    var sdlOrigin = SDL_FPoint(x: cfloat(origin.x), y: cfloat(origin.y))
    var sdlRight = SDL_FPoint(x: cfloat(right.x), y: cfloat(right.y))
    var sdlDown = SDL_FPoint(x: cfloat(down.x), y: cfloat(down.y))
    texture.configureLayerTexture(opacity, compositeMode, premultiplied)
    discard SDL3.renderTextureAffine(
      target.renderer, texture, addr source,
      addr sdlOrigin, addr sdlRight, addr sdlDown
    )
    texture.resetLayerTexture()
    return

  let fourth = vec2(right.x + down.x - origin.x, right.y + down.y - origin.y)
  let left = floor(min(min(origin.x, right.x), min(down.x, fourth.x))) - 1.0'f32
  let top = floor(min(min(origin.y, right.y), min(down.y, fourth.y))) - 1.0'f32
  let bounds = rect(
    left,
    top,
    ceil(max(max(origin.x, right.x), max(down.x, fourth.x))) - left + 1.0'f32,
    ceil(max(max(origin.y, right.y), max(down.y, fourth.y))) - top + 1.0'f32
  )
  let scale = target.pixelScale()
  let width = max(1, int(ceil(bounds.w * scale)))
  let height = max(1, int(ceil(bounds.h * scale)))
  let clipped = target.acquireTransformTexture(width, height)
  let clippedTexture = clipped.texture
  if clippedTexture.isNil:
    var sdlOrigin = SDL_FPoint(x: cfloat(origin.x), y: cfloat(origin.y))
    var sdlRight = SDL_FPoint(x: cfloat(right.x), y: cfloat(right.y))
    var sdlDown = SDL_FPoint(x: cfloat(down.x), y: cfloat(down.y))
    texture.configureLayerTexture(opacity, compositeMode, premultiplied)
    discard SDL3.renderTextureAffine(
      target.renderer, texture, addr source,
      addr sdlOrigin, addr sdlRight, addr sdlDown
    )
    texture.resetLayerTexture()
    return

  let previousTarget = SDL3.getRenderTarget(target.renderer)
  discard SDL3.setRenderTarget(target.renderer, clippedTexture)
  discard SDL3.setRenderLogicalPresentation(
    target.renderer, 0, 0, SDL_LOGICAL_PRESENTATION_DISABLED
  )
  discard SDL3.setRenderScale(target.renderer, cfloat(scale), cfloat(scale))
  target.renderer.setClip(none(SDL_Rect))
  discard SDL3.setRenderDrawColor(target.renderer, 0, 0, 0, 0)
  discard SDL3.renderClear(target.renderer)

  var localOrigin = SDL_FPoint(
    x: cfloat(origin.x - bounds.x), y: cfloat(origin.y - bounds.y)
  )
  var localRight = SDL_FPoint(
    x: cfloat(right.x - bounds.x), y: cfloat(right.y - bounds.y)
  )
  var localDown = SDL_FPoint(
    x: cfloat(down.x - bounds.x), y: cfloat(down.y - bounds.y)
  )
  texture.configureLayerTexture(1.0'f32, lcmSourceOver, premultiplied)
  discard SDL3.renderTextureAffine(
    target.renderer, texture, addr source,
    addr localOrigin, addr localRight, addr localDown
  )
  texture.resetLayerTexture()

  discard SDL3.setRenderTarget(target.renderer, previousTarget)
  target.renderer.setClip(target.effectiveClipBounds())
  var clippedSource = SDL_FRect(
    x: 0, y: 0, w: cfloat(width), h: cfloat(height)
  )
  var destination = bounds.toSdl
  clippedTexture.configureLayerTexture(opacity, compositeMode, premultiplied)
  target.renderTextureClippedWith(
    clippedTexture, clippedSource, destination, target.clipStack
  )
  clippedTexture.resetLayerTexture()
  target.releaseTransformTexture(clipped.index)

proc endTransformLayer(
    target: var Sdl3Renderer;
    layers: var seq[Sdl3TransformLayer]
) =
  if layers.len == 0:
    return
  let layer = layers.pop()
  if not layer.valid:
    return

  discard SDL3.setRenderTarget(target.renderer, layer.previousTarget)
  target.clipStack = layer.previousClips
  target.renderer.setClip(target.effectiveClipBounds())
  if layer.hasContent or layer.compositeMode == lcmCopy:
    let destinationOffset = layers.activeTransformOffset()
    let topLeft = layer.transform.transformPoint(
      vec2(layer.sourceBounds.x, layer.sourceBounds.y)
    ).translated(destinationOffset)
    let topRight = layer.transform.transformPoint(
      vec2(layer.sourceBounds.x + layer.sourceBounds.w, layer.sourceBounds.y)
    ).translated(destinationOffset)
    let bottomLeft = layer.transform.transformPoint(
      vec2(layer.sourceBounds.x, layer.sourceBounds.y + layer.sourceBounds.h)
    ).translated(destinationOffset)
    var source = SDL_FRect(
      x: 0, y: 0, w: cfloat(layer.pixelWidth), h: cfloat(layer.pixelHeight)
    )
    target.renderAffineLayer(
      layer.texture, source, topLeft, topRight, bottomLeft,
      layer.opacity, layer.compositeMode
    )
    layers.markTransformContent()
  target.releaseTransformTexture(layer.textureCacheIndex)

proc closeTransformLayers(
    target: var Sdl3Renderer;
    layers: var seq[Sdl3TransformLayer]
) =
  while layers.len > 0:
    target.endTransformLayer(layers)
  target.evictTransformTextureCacheIfNeeded()

proc clippedHorizontalSpan(clips: openArray[Sdl3ClipRegion]; centerY: float32; x1, x2: var float32): bool =
  if x2 <= x1:
    return false
  for clip in clips:
    var cx1, cx2: float32
    if not roundedSpan(clip.rect, clip.radius, centerY, cx1, cx2):
      return false
    x1 = max(x1, cx1)
    x2 = min(x2, cx2)
    if x2 <= x1:
      return false
  true

proc clippedHorizontalSpan(target: Sdl3Renderer; centerY: float32; x1, x2: var float32): bool =
  target.clipStack.clippedHorizontalSpan(centerY, x1, x2)

proc drawTextTexture(target: Sdl3Renderer; command: PaintCommand; entry: Sdl3TextCacheEntry) =
  let scale =
    if entry.scale > 0: entry.scale
    else: 1.0'f32
  var dst = SDL_FRect(
    x: cfloat(round(command.position.x + entry.offsetX.float32 / scale)),
    y: cfloat(round(command.position.y + entry.offsetY.float32 / scale)),
    w: cfloat(entry.width.float32 / scale),
    h: cfloat(entry.height.float32 / scale)
  )
  var src = SDL_FRect(
    x: 0,
    y: 0,
    w: cfloat(entry.width.float32),
    h: cfloat(entry.height.float32)
  )
  if command.textMaxWidth.isSome:
    let maxLogicalWidth = max(0.0'f32, command.textMaxWidth.get)
    let maxTextureWidth = maxLogicalWidth * scale
    if maxTextureWidth < src.w.float32:
      src.w = cfloat(maxTextureWidth)
      dst.w = cfloat(maxLogicalWidth)
  let previousClip = target.effectiveClipBounds()
  var appliedTextClip = false
  if command.textMaxWidth.isSome:
    let textClip = Rect(
      x: command.position.x,
      y: min(command.position.y, dst.y.float32),
      w: max(0.0'f32, command.textMaxWidth.get),
      h: max(dst.h.float32, abs(dst.y.float32 - command.position.y) + dst.h.float32)
    ).toSdlClip()
    let combinedClip =
      if previousClip.isSome:
        some(intersect(previousClip.get, textClip))
      else:
        some(textClip)
    target.renderer.setClip(combinedClip)
    appliedTextClip = true
  if not target.hasRoundedClip():
    discard SDL3.renderTexture(target.renderer, entry.texture, addr src, addr dst)
    if appliedTextClip:
      target.renderer.setClip(previousClip)
    return
  target.renderTextureClipped(entry.texture, src, dst)
  if appliedTextClip:
    target.renderer.setClip(previousClip)

proc clampedRadius(rect: Rect; radius: float32): float32 =
  max(0.0'f32, min(radius, min(rect.w, rect.h) * 0.5'f32))

proc roundedSpan(rect: Rect; radius, centerY: float32; x1, x2: var float32): bool =
  if rect.w <= 0 or rect.h <= 0 or centerY < rect.y or centerY >= rect.y + rect.h:
    return false
  let r = rect.clampedRadius(radius)
  var inset = 0.0'f32
  if r > 0:
    if centerY < rect.y + r:
      let dy = rect.y + r - centerY
      inset = r - sqrt(max(0.0'f32, r * r - dy * dy))
    elif centerY >= rect.y + rect.h - r:
      let dy = centerY - (rect.y + rect.h - r)
      inset = r - sqrt(max(0.0'f32, r * r - dy * dy))
  x1 = rect.x + inset
  x2 = rect.x + rect.w - inset
  x2 > x1

proc fillHorizontal(target: Sdl3Renderer; x1, x2, y: float32; color: Color) =
  var left = x1
  var right = x2
  if not target.clippedHorizontalSpan(y + 0.5'f32, left, right):
    return
  let startPixel = int(floor(left))
  let endPixel = int(floor(right))
  let mainLeft = ceil(left)
  let mainRight = floor(right)

  if startPixel == endPixel:
    let coverage = min(1.0'f32, max(0.0'f32, right - left))
    if coverage > 0.001'f32:
      target.renderer.setColor(color, coverage)
      var edge = SDL_FRect(x: cfloat(startPixel.float32), y: cfloat(y), w: cfloat(1.0'f32), h: cfloat(1.0'f32))
      discard SDL3.renderFillRect(target.renderer, addr edge)
    return

  if mainRight > mainLeft:
    target.renderer.setColor(color)
    var line = SDL_FRect(x: cfloat(mainLeft), y: cfloat(y), w: cfloat(mainRight - mainLeft), h: cfloat(1.0'f32))
    discard SDL3.renderFillRect(target.renderer, addr line)

  let leftCoverage = min(1.0'f32, max(0.0'f32, ceil(left) - left))
  if leftCoverage > 0.001'f32:
    target.renderer.setColor(color, leftCoverage)
    var edge = SDL_FRect(x: cfloat(startPixel.float32), y: cfloat(y), w: cfloat(1.0'f32), h: cfloat(1.0'f32))
    discard SDL3.renderFillRect(target.renderer, addr edge)

  let rightCoverage = min(1.0'f32, max(0.0'f32, right - floor(right)))
  if rightCoverage > 0.001'f32 and endPixel != startPixel:
    target.renderer.setColor(color, rightCoverage)
    var edge = SDL_FRect(x: cfloat(endPixel.float32), y: cfloat(y), w: cfloat(1.0'f32), h: cfloat(1.0'f32))
    discard SDL3.renderFillRect(target.renderer, addr edge)

proc fillRoundedRect(target: Sdl3Renderer; rect: Rect; radius: float32; color: Color) =
  if rect.w <= 0 or rect.h <= 0:
    return
  let r = rect.clampedRadius(radius)
  if r <= 0.001'f32 and not target.hasRoundedClip():
    target.renderer.setColor(color)
    var sdlRect = rect.toSdl
    discard SDL3.renderFillRect(target.renderer, addr sdlRect)
    return
  let yStart = int(floor(rect.y))
  let yEnd = int(ceil(rect.y + rect.h)) - 1
  for y in yStart .. yEnd:
    let centerY = y.float32 + 0.5'f32
    var x1, x2: float32
    if roundedSpan(rect, r, centerY, x1, x2):
      target.fillHorizontal(x1, x2, y.float32, color)

proc cacheFloat(value: float32): string =
  $(round(value * 100.0'f32) / 100.0'f32)

proc gradientTextureCacheKey(rect: Rect; gradient: LinearGradient; radius, scale: float32): string =
  result = "gradient:" &
    cacheFloat(rect.w) & "," &
    cacheFloat(rect.h) & "," &
    cacheFloat(radius) & "," &
    cacheFloat(scale) & "," &
    cacheFloat(gradient.angle) & "," &
    $ord(gradient.interpolationSpace)
  for stop in gradient.stops:
    result.add "|"
    result.add cacheFloat(stop.offset)
    result.add ":"
    result.add cacheFloat(stop.color.r)
    result.add ","
    result.add cacheFloat(stop.color.g)
    result.add ","
    result.add cacheFloat(stop.color.b)
    result.add ","
    result.add cacheFloat(stop.color.a)

proc findGradientTextureCache(target: var Sdl3Renderer; key: string): Option[Sdl3RoundedTextureCacheEntry] =
  let keyHash = hash(key)
  if keyHash in target.roundedTextureCacheIndex:
    for entryIndex in target.roundedTextureCacheIndex[keyHash]:
      if entryIndex >= 0 and entryIndex < target.roundedTextureCache.len and
          target.roundedTextureCache[entryIndex].key == key:
        target.roundedTextureCache[entryIndex].lastUsed = target.frameId
        return some(target.roundedTextureCache[entryIndex])
  none(Sdl3RoundedTextureCacheEntry)

proc evictTextureCacheIfNeeded(target: var Sdl3Renderer) =
  let limit =
    if target.roundedTextureCacheLimit > 0: target.roundedTextureCacheLimit
    else: 128
  while target.roundedTextureCache.len > limit or
      (target.roundedTextureCache.len > 1 and
        target.roundedTextureCacheBytes > target.roundedTextureCacheByteLimit):
    var victim = 0
    for index in 1 ..< target.roundedTextureCache.len:
      if target.roundedTextureCache[index].lastUsed < target.roundedTextureCache[victim].lastUsed:
        victim = index
    if not target.roundedTextureCache[victim].texture.isNil:
      SDL3.destroyTexture(target.roundedTextureCache[victim].texture)
    target.roundedTextureCacheBytes -= textureBytes(
      target.roundedTextureCache[victim].width,
      target.roundedTextureCache[victim].height
    )
    target.roundedTextureCache.delete(victim)
    target.rebuildRoundedTextureCacheIndex()

proc createGradientTexture(
    target: var Sdl3Renderer;
    key: string;
    rect: Rect;
    gradient: LinearGradient;
    radius, scale: float32
): Option[Sdl3RoundedTextureCacheEntry] =
  let width = max(1, int(ceil(rect.w * scale)))
  let height = max(1, int(ceil(rect.h * scale)))
  if width > 4096 or height > 4096:
    return none(Sdl3RoundedTextureCacheEntry)

  let radians = (gradient.angle - 90.0'f32) * PI / 180.0'f32
  let dx = cos(radians)
  let dy = sin(radians)
  let logicalW = width.float32 / scale
  let logicalH = height.float32 / scale
  let corners = [
    vec2(0, 0),
    vec2(logicalW, 0),
    vec2(0, logicalH),
    vec2(logicalW, logicalH)
  ]
  var minProjection = corners[0].x * dx + corners[0].y * dy
  var maxProjection = minProjection
  for corner in corners:
    let projection = corner.x * dx + corner.y * dy
    minProjection = min(minProjection, projection)
    maxProjection = max(maxProjection, projection)
  let span = max(0.001'f32, maxProjection - minProjection)
  let localRect = Rect(x: 0, y: 0, w: logicalW, h: logicalH)
  let localRadius = localRect.clampedRadius(radius)
  let lookup = gradient.prepareGradientSampler.buildGradientLookup(
    (span * scale).gradientLookupSampleCount
  )
  var pixels = newSeq[uint8](width * height * 4)

  for y in 0 ..< height:
    let localY = (y.float32 + 0.5'f32) / scale
    var x1, x2: float32
    let insideRow = roundedSpan(localRect, localRadius, localY, x1, x2)
    for x in 0 ..< width:
      let localX = (x.float32 + 0.5'f32) / scale
      let index = (y * width + x) * 4
      if not insideRow or localX < x1 or localX >= x2:
        pixels[index + 3] = 0
        continue
      let projection = localX * dx + localY * dy
      let color = lookup.gradientColorAt((projection - minProjection) / span)
      pixels[index] = color.r.toByte
      pixels[index + 1] = color.g.toByte
      pixels[index + 2] = color.b.toByte
      pixels[index + 3] = color.a.toByte

  let texture = SDL3.createTexture(
    target.renderer,
    SDL_PIXELFORMAT_RGBA32,
    sdlTextureAccessStatic,
    cint(width),
    cint(height)
  )
  if texture.isNil:
    return none(Sdl3RoundedTextureCacheEntry)
  discard SDL3.setTextureBlendMode(texture, sdlBlendModeBlend)
  discard SDL3.setTextureScaleMode(texture, SDL_SCALEMODE_LINEAR)
  if pixels.len > 0:
    discard SDL3.updateTexture(texture, nil, unsafeAddr pixels[0], cint(width * 4))
  let entry = Sdl3RoundedTextureCacheEntry(
    key: key,
    texture: texture,
    width: width,
    height: height,
    lastUsed: target.frameId
  )
  target.roundedTextureCache.add entry
  target.roundedTextureCacheIndex.indexKey(key, target.roundedTextureCache.high)
  target.roundedTextureCacheBytes += textureBytes(width, height)
  target.evictTextureCacheIfNeeded()
  some(entry)

proc fillLinearGradient(target: var Sdl3Renderer; rect: Rect; gradient: LinearGradient; radius: float32) =
  if rect.w <= 0 or rect.h <= 0 or gradient.stops.len == 0:
    return
  if gradient.stops.len == 1:
    target.fillRoundedRect(rect, radius, gradient.stops[0].color)
    return
  let scale = target.pixelScale()
  let key = rect.gradientTextureCacheKey(gradient, radius, scale)
  let cached = target.findGradientTextureCache(key)
  let textureEntry =
    if cached.isSome:
      cached
    else:
      target.createGradientTexture(key, rect, gradient, radius, scale)
  if textureEntry.isSome:
    var src = SDL_FRect(
      x: 0,
      y: 0,
      w: cfloat(textureEntry.get.width),
      h: cfloat(textureEntry.get.height)
    )
    var dst = rect.toSdl
    target.renderTextureClipped(textureEntry.get.texture, src, dst)
    return

  let radians = (gradient.angle - 90.0'f32) * PI / 180.0'f32
  let dx = cos(radians)
  let dy = sin(radians)
  let corners = [
    vec2(rect.x, rect.y),
    vec2(rect.x + rect.w, rect.y),
    vec2(rect.x, rect.y + rect.h),
    vec2(rect.x + rect.w, rect.y + rect.h)
  ]
  var minProjection = corners[0].x * dx + corners[0].y * dy
  var maxProjection = minProjection
  for corner in corners:
    let projection = corner.x * dx + corner.y * dy
    minProjection = min(minProjection, projection)
    maxProjection = max(maxProjection, projection)
  let span = max(0.001'f32, maxProjection - minProjection)
  let lookup = gradient.prepareGradientSampler.buildGradientLookup(
    (span * scale).gradientLookupSampleCount
  )
  let r = rect.clampedRadius(radius)
  let yStart = int(floor(rect.y))
  let yEnd = int(ceil(rect.y + rect.h)) - 1
  for y in yStart .. yEnd:
    let centerY = y.float32 + 0.5'f32
    var x1, x2: float32
    if not roundedSpan(rect, r, centerY, x1, x2):
      continue
    var left = x1
    var right = x2
    if not target.clippedHorizontalSpan(centerY, left, right):
      continue
    let xStart = int(floor(left))
    let xEnd = int(ceil(right)) - 1
    for x in xStart .. xEnd:
      let centerX = x.float32 + 0.5'f32
      if centerX < left or centerX >= right:
        continue
      let projection = centerX * dx + centerY * dy
      let t = (projection - minProjection) / span
      var pixel = SDL_FRect(x: cfloat(x.float32), y: cfloat(y.float32), w: cfloat(1.0'f32), h: cfloat(1.0'f32))
      target.renderer.setColor(lookup.gradientColorAt(t))
      discard SDL3.renderFillRect(target.renderer, addr pixel)

proc firstRepeatedTile(anchor, extent, visibleStart: float32): float32 =
  anchor + floor((visibleStart - anchor) / extent) * extent

proc repeatedGradientCoordinate(value, start, extent: float32): float32 =
  start + (value - start) - floor((value - start) / extent) * extent

proc fillLinearGradientPatternPixels(
    target: Sdl3Renderer;
    tileRect, paintRect: Rect;
    gradient: LinearGradient;
    repeat: BackgroundRepeat
) =
  ## Allocation-failure fallback. Its work is bounded by visible pixels rather
  ## than by the number of tiles, including subpixel background sizes.
  let radians = (gradient.angle - 90.0'f32) * PI / 180.0'f32
  let dx = cos(radians)
  let dy = sin(radians)
  let corners = [
    vec2(tileRect.x, tileRect.y),
    vec2(tileRect.x + tileRect.w, tileRect.y),
    vec2(tileRect.x, tileRect.y + tileRect.h),
    vec2(tileRect.x + tileRect.w, tileRect.y + tileRect.h)
  ]
  var minProjection = corners[0].x * dx + corners[0].y * dy
  var maxProjection = minProjection
  for corner in corners:
    let projection = corner.x * dx + corner.y * dy
    minProjection = min(minProjection, projection)
    maxProjection = max(maxProjection, projection)
  let span = max(0.001'f32, maxProjection - minProjection)
  let lookup = gradient.prepareGradientSampler.buildGradientLookup(
    (span * target.pixelScale()).gradientLookupSampleCount
  )
  let repeatX = repeat in {bgRepeat, bgRepeatX}
  let repeatY = repeat in {bgRepeat, bgRepeatY}
  let clipBounds = target.effectiveClipBounds()
  let yStart = max(
    int(floor(paintRect.y)),
    if clipBounds.isSome: int(clipBounds.get.y) else: low(int)
  )
  let yEnd = min(
    int(ceil(paintRect.y + paintRect.h)) - 1,
    if clipBounds.isSome:
      int(clipBounds.get.y + clipBounds.get.h) - 1
    else:
      high(int)
  )
  if yEnd < yStart:
    return
  for y in yStart .. yEnd:
    let centerY = y.float32 + 0.5'f32
    var left = paintRect.x
    var right = paintRect.x + paintRect.w
    if not target.clippedHorizontalSpan(centerY, left, right):
      continue
    let xStart = int(floor(left))
    let xEnd = int(ceil(right)) - 1
    for x in xStart .. xEnd:
      let centerX = x.float32 + 0.5'f32
      if centerX < left or centerX >= right:
        continue
      if not repeatX and
          (centerX < tileRect.x or centerX >= tileRect.x + tileRect.w):
        continue
      if not repeatY and
          (centerY < tileRect.y or centerY >= tileRect.y + tileRect.h):
        continue
      let sourceX =
        if repeatX:
          repeatedGradientCoordinate(centerX, tileRect.x, tileRect.w)
        else:
          centerX
      let sourceY =
        if repeatY:
          repeatedGradientCoordinate(centerY, tileRect.y, tileRect.h)
        else:
          centerY
      let projection = sourceX * dx + sourceY * dy
      var pixel = SDL_FRect(
        x: cfloat(x.float32), y: cfloat(y.float32),
        w: cfloat(1.0'f32), h: cfloat(1.0'f32)
      )
      target.renderer.setColor(lookup.gradientColorAt(
        (projection - minProjection) / span
      ))
      discard SDL3.renderFillRect(target.renderer, addr pixel)

proc fillLinearGradientPattern(
    target: var Sdl3Renderer;
    tileRect, paintRect, clipRect: Rect;
    gradient: LinearGradient;
    repeat: BackgroundRepeat;
    radius: float32
) =
  if tileRect.isEmpty or paintRect.isEmpty or gradient.stops.len == 0:
    return
  let repeatX = repeat in {bgRepeat, bgRepeatX}
  let repeatY = repeat in {bgRepeat, bgRepeatY}
  let firstX =
    if repeatX:
      firstRepeatedTile(tileRect.x, tileRect.w, paintRect.x)
    else:
      tileRect.x
  let firstY =
    if repeatY:
      firstRepeatedTile(tileRect.y, tileRect.h, paintRect.y)
    else:
      tileRect.y

  let clipDepth = target.clipStack.len
  target.clipStack.add Sdl3ClipRegion(
    rect: clipRect,
    radius: radius,
    bounds: clipRect.toSdlClip
  )
  target.renderer.setClip(target.effectiveClipBounds())

  if gradient.stops.len == 1:
    target.fillRoundedRect(paintRect, 0, gradient.stops[0].color)
    target.clipStack.setLen(clipDepth)
    target.renderer.setClip(target.effectiveClipBounds())
    return

  if repeat != bgNoRepeat:
    let scale = target.pixelScale()
    let key = tileRect.gradientTextureCacheKey(gradient, 0, scale)
    let cached = target.findGradientTextureCache(key)
    let textureEntry =
      if cached.isSome:
        cached
      else:
        target.createGradientTexture(key, tileRect, gradient, 0, scale)
    if textureEntry.isSome:
      var source = SDL_FRect(
        x: 0,
        y: 0,
        w: cfloat(textureEntry.get.width),
        h: cfloat(textureEntry.get.height)
      )
      var destination = SDL_FRect(
        x: cfloat(firstX),
        y: cfloat(firstY),
        w: cfloat(paintRect.x + paintRect.w - firstX),
        h: cfloat(paintRect.y + paintRect.h - firstY)
      )
      if target.hasRoundedClip():
        let yStart = int(floor(paintRect.y))
        let yEnd = int(ceil(paintRect.y + paintRect.h)) - 1
        for row in yStart .. yEnd:
          let centerY = row.float32 + 0.5'f32
          var left = paintRect.x
          var right = paintRect.x + paintRect.w
          if not target.clippedHorizontalSpan(centerY, left, right):
            continue
          target.renderer.setClip(some(rect(
            left, row.float32, max(0.0'f32, right - left), 1
          ).toSdlClip))
          discard SDL3.renderTextureTiled(
            target.renderer,
            textureEntry.get.texture,
            addr source,
            cfloat(1.0'f32 / max(0.001'f32, scale)),
            addr destination
          )
      else:
        discard SDL3.renderTextureTiled(
          target.renderer,
          textureEntry.get.texture,
          addr source,
          cfloat(1.0'f32 / max(0.001'f32, scale)),
          addr destination
        )
      target.clipStack.setLen(clipDepth)
      target.renderer.setClip(target.effectiveClipBounds())
      return

  if repeat == bgNoRepeat:
    target.fillLinearGradient(tileRect, gradient, 0)
  else:
    target.fillLinearGradientPatternPixels(
      tileRect, paintRect, gradient, repeat
    )

  target.clipStack.setLen(clipDepth)
  target.renderer.setClip(target.effectiveClipBounds())

proc strokeRoundedRect(target: Sdl3Renderer; rect: Rect; radius, width: float32; color: Color) =
  if rect.w <= 0 or rect.h <= 0:
    return
  let strokeWidth = max(1.0'f32, width)
  let outerRadius = rect.clampedRadius(radius)
  if outerRadius <= 0.001'f32 and not target.hasRoundedClip():
    target.renderer.setColor(color)
    let lines = max(1, int(round(strokeWidth)))
    for offset in 0 ..< lines:
      var sdlRect = Rect(
        x: rect.x + offset.float32,
        y: rect.y + offset.float32,
        w: max(0.0'f32, rect.w - offset.float32 * 2.0'f32),
        h: max(0.0'f32, rect.h - offset.float32 * 2.0'f32)
      ).toSdl
      discard SDL3.renderRect(target.renderer, addr sdlRect)
    return

  let inner = Rect(
    x: rect.x + strokeWidth,
    y: rect.y + strokeWidth,
    w: rect.w - strokeWidth * 2.0'f32,
    h: rect.h - strokeWidth * 2.0'f32
  )
  if inner.w <= 0 or inner.h <= 0:
    target.fillRoundedRect(rect, outerRadius, color)
    return

  let innerRadius = max(0.0'f32, outerRadius - strokeWidth)
  let yStart = int(floor(rect.y))
  let yEnd = int(ceil(rect.y + rect.h)) - 1
  for y in yStart .. yEnd:
    let centerY = y.float32 + 0.5'f32
    var ox1, ox2: float32
    if not roundedSpan(rect, outerRadius, centerY, ox1, ox2):
      continue
    var ix1, ix2: float32
    if roundedSpan(inner, innerRadius, centerY, ix1, ix2):
      target.fillHorizontal(ox1, min(ix1, ox2), y.float32, color)
      target.fillHorizontal(max(ix2, ox1), ox2, y.float32, color)
    else:
      target.fillHorizontal(ox1, ox2, y.float32, color)

proc samePoint(a, b: Vec2): bool =
  abs(a.x - b.x) <= 0.0001'f32 and abs(a.y - b.y) <= 0.0001'f32

proc drawSolidTriangle(
    target: Sdl3Renderer;
    first, second, third: Vec2;
    color: Color
) =
  let vertexColor = SDL_FColor(
    r: cfloat(color.r), g: cfloat(color.g),
    b: cfloat(color.b), a: cfloat(color.a)
  )
  var vertices = [
    SDL_Vertex(position: SDL_FPoint(x: first.x, y: first.y), color: vertexColor),
    SDL_Vertex(position: SDL_FPoint(x: second.x, y: second.y), color: vertexColor),
    SDL_Vertex(position: SDL_FPoint(x: third.x, y: third.y), color: vertexColor)
  ]
  discard SDL3.renderGeometry(
    target.renderer, nil, addr vertices[0], 3, nil, 0
  )

proc strokeJoin(
    target: Sdl3Renderer;
    previous, point, following: Vec2;
    radius: float32;
    color: Color;
    lineJoin: StrokeLineJoin;
    miterLimit: float32
) =
  let previousDelta = vec2(point.x - previous.x, point.y - previous.y)
  let followingDelta = vec2(following.x - point.x, following.y - point.y)
  let previousLength = sqrt(
    previousDelta.x * previousDelta.x + previousDelta.y * previousDelta.y
  )
  let followingLength = sqrt(
    followingDelta.x * followingDelta.x + followingDelta.y * followingDelta.y
  )
  if previousLength <= 0.0001'f32 or followingLength <= 0.0001'f32:
    return
  let previousDirection = vec2(
    previousDelta.x / previousLength, previousDelta.y / previousLength
  )
  let followingDirection = vec2(
    followingDelta.x / followingLength, followingDelta.y / followingLength
  )
  let turn = previousDirection.x * followingDirection.y -
    previousDirection.y * followingDirection.x
  if abs(turn) <= 0.0001'f32:
    return
  if lineJoin == sljRound:
    target.fillRoundedRect(
      rect(point.x - radius, point.y - radius, radius * 2, radius * 2),
      radius,
      color
    )
    return

  let outerSign = if turn > 0: -1.0'f32 else: 1.0'f32
  let previousNormal = vec2(
    -previousDirection.y * outerSign,
    previousDirection.x * outerSign
  )
  let followingNormal = vec2(
    -followingDirection.y * outerSign,
    followingDirection.x * outerSign
  )
  let previousOuter = vec2(
    point.x + previousNormal.x * radius,
    point.y + previousNormal.y * radius
  )
  let followingOuter = vec2(
    point.x + followingNormal.x * radius,
    point.y + followingNormal.y * radius
  )
  if lineJoin == sljBevel:
    target.drawSolidTriangle(previousOuter, point, followingOuter, color)
    return

  let sum = vec2(
    previousNormal.x + followingNormal.x,
    previousNormal.y + followingNormal.y
  )
  let sumLength = sqrt(sum.x * sum.x + sum.y * sum.y)
  if sumLength <= 0.0001'f32:
    target.drawSolidTriangle(previousOuter, point, followingOuter, color)
    return
  let miterDirection = vec2(sum.x / sumLength, sum.y / sumLength)
  let denominator = miterDirection.x * followingNormal.x +
    miterDirection.y * followingNormal.y
  if abs(denominator) <= 0.0001'f32:
    target.drawSolidTriangle(previousOuter, point, followingOuter, color)
    return
  let miterLength = radius / denominator
  if abs(miterLength) > radius * max(1.0'f32, miterLimit):
    target.drawSolidTriangle(previousOuter, point, followingOuter, color)
    return
  let miterPoint = vec2(
    point.x + miterDirection.x * miterLength,
    point.y + miterDirection.y * miterLength
  )
  target.drawSolidTriangle(previousOuter, miterPoint, followingOuter, color)

proc strokePolyline(
    target: Sdl3Renderer;
    points: openArray[Vec2];
    width: float32;
    color: Color;
    closed: bool;
    lineCap: StrokeLineCap;
    lineJoin: StrokeLineJoin;
    miterLimit: float32
) =
  if points.len < 2 or width <= 0:
    return
  var normalized = newSeqOfCap[Vec2](points.len)
  for point in points:
    if normalized.len == 0 or not normalized[^1].samePoint(point):
      normalized.add point
  if closed and normalized.len > 1 and normalized[0].samePoint(normalized[^1]):
    normalized.setLen(normalized.len - 1)
  if normalized.len < 2:
    return

  target.renderer.setColor(color)
  let lanes = max(1, int(ceil(width)))
  let halfLane = (lanes - 1).float32 * 0.5'f32
  let radius = width * 0.5'f32
  let segmentCount = normalized.len - 1 + ord(closed)
  for index in 0 ..< segmentCount:
    var first = normalized[index mod normalized.len]
    var second = normalized[(index + 1) mod normalized.len]
    let dx = second.x - first.x
    let dy = second.y - first.y
    let length = sqrt(dx * dx + dy * dy)
    if length <= 0.0001'f32:
      continue
    let normalX = -dy / length
    let normalY = dx / length
    if not closed and lineCap == slcSquare:
      if index == 0:
        first.x -= dx / length * radius
        first.y -= dy / length * radius
      if index == segmentCount - 1:
        second.x += dx / length * radius
        second.y += dy / length * radius
    for lane in 0 ..< lanes:
      let offset = lane.float32 - halfLane
      discard SDL3.renderLine(
        target.renderer,
        cfloat(first.x + normalX * offset),
        cfloat(first.y + normalY * offset),
        cfloat(second.x + normalX * offset),
        cfloat(second.y + normalY * offset)
      )

  if closed:
    for index in 0 ..< normalized.len:
      target.strokeJoin(
        normalized[(index - 1 + normalized.len) mod normalized.len],
        normalized[index],
        normalized[(index + 1) mod normalized.len],
        radius, color, lineJoin, miterLimit
      )
  else:
    for index in 1 ..< normalized.len - 1:
      target.strokeJoin(
        normalized[index - 1], normalized[index], normalized[index + 1],
        radius, color, lineJoin, miterLimit
      )
    if lineCap == slcRound:
      for point in [normalized[0], normalized[^1]]:
        target.fillRoundedRect(
          rect(point.x - radius, point.y - radius, width, width),
          radius,
          color
        )

proc renderStrokePath(target: Sdl3Renderer; command: PaintCommand) =
  let tolerance = 0.25'f32 / max(1.0'f32, target.pixelScale())
  for contour in command.path.flattened(tolerance):
    target.strokePolyline(
      contour.points,
      command.pathWidth,
      command.pathColor,
      contour.closed,
      command.pathLineCap,
      command.pathLineJoin,
      command.pathMiterLimit
    )

proc shadowRect(command: PaintCommand; grow: float32): Rect =
  Rect(
    x: command.shadowRect.x + command.shadowOffsetX - grow,
    y: command.shadowRect.y + command.shadowOffsetY - grow,
    w: command.shadowRect.w + grow * 2.0'f32,
    h: command.shadowRect.h + grow * 2.0'f32
  )

proc shadowLayerColor(command: PaintCommand; alphaMultiplier: float32): Color =
  rgba(
    command.shadowColor.r,
    command.shadowColor.g,
    command.shadowColor.b,
    command.shadowColor.a * max(0.0'f32, min(1.0'f32, alphaMultiplier))
  )

proc shadowTextureRect(command: PaintCommand): Rect =
  let blur = max(0.0'f32, command.shadowBlur)
  let shapeGrow = command.shadowSpread
  Rect(
    x: command.shadowRect.x + command.shadowOffsetX - shapeGrow - blur,
    y: command.shadowRect.y + command.shadowOffsetY - shapeGrow - blur,
    w: command.shadowRect.w + shapeGrow * 2.0'f32 + blur * 2.0'f32,
    h: command.shadowRect.h + shapeGrow * 2.0'f32 + blur * 2.0'f32
  )

proc shadowCacheFloat(value: float32): string =
  $(round(value * 100.0'f32) / 100.0'f32)

proc shadowTextureCacheKey(command: PaintCommand; scale: float32): string =
  "box-shadow:" &
    shadowCacheFloat(command.shadowRect.w) & "," &
    shadowCacheFloat(command.shadowRect.h) & "," &
    shadowCacheFloat(command.shadowRadius) & "," &
    shadowCacheFloat(command.shadowBlur) & "," &
    shadowCacheFloat(command.shadowSpread) & "," &
    shadowCacheFloat(command.shadowColor.r) & "," &
    shadowCacheFloat(command.shadowColor.g) & "," &
    shadowCacheFloat(command.shadowColor.b) & "," &
    shadowCacheFloat(command.shadowColor.a) & "," &
    shadowCacheFloat(scale)

proc roundedBoxDistance(px, py, x, y, w, h, radius: float32): float32 =
  if w <= 0 or h <= 0:
    return 1.0'f32
  let r = max(0.0'f32, min(radius, min(w, h) * 0.5'f32))
  let halfW = w * 0.5'f32
  let halfH = h * 0.5'f32
  let qx = abs(px - (x + halfW)) - halfW + r
  let qy = abs(py - (y + halfH)) - halfH + r
  let outsideX = max(qx, 0.0'f32)
  let outsideY = max(qy, 0.0'f32)
  sqrt(outsideX * outsideX + outsideY * outsideY) + min(max(qx, qy), 0.0'f32) - r

proc findShadowTextureCache(
    target: var Sdl3Renderer;
    key: string
): Option[Sdl3ShadowTextureCacheEntry] =
  let keyHash = hash(key)
  if keyHash in target.shadowTextureCacheIndex:
    for entryIndex in target.shadowTextureCacheIndex[keyHash]:
      if entryIndex >= 0 and entryIndex < target.shadowTextureCache.len and
          target.shadowTextureCache[entryIndex].key == key:
        target.shadowTextureCache[entryIndex].lastUsed = target.frameId
        return some(target.shadowTextureCache[entryIndex])
  none(Sdl3ShadowTextureCacheEntry)

proc evictShadowTextureCacheIfNeeded(target: var Sdl3Renderer) =
  let limit =
    if target.shadowTextureCacheLimit > 0: target.shadowTextureCacheLimit
    else: 128
  while target.shadowTextureCache.len > limit or
      (target.shadowTextureCache.len > 1 and
        target.shadowTextureCacheBytes > target.shadowTextureCacheByteLimit):
    var victim = 0
    for index in 1 ..< target.shadowTextureCache.len:
      if target.shadowTextureCache[index].lastUsed < target.shadowTextureCache[victim].lastUsed:
        victim = index
    if not target.shadowTextureCache[victim].texture.isNil:
      SDL3.destroyTexture(target.shadowTextureCache[victim].texture)
    target.shadowTextureCacheBytes -= textureBytes(
      target.shadowTextureCache[victim].width,
      target.shadowTextureCache[victim].height
    )
    target.shadowTextureCache.delete(victim)
    target.rebuildShadowTextureCacheIndex()

proc createShadowTexture(
    target: var Sdl3Renderer;
    key: string;
    command: PaintCommand;
    scale: float32
): Option[Sdl3ShadowTextureCacheEntry] =
  let dst = command.shadowTextureRect()
  if dst.w <= 0 or dst.h <= 0:
    return none(Sdl3ShadowTextureCacheEntry)
  let width = max(1, int(ceil(dst.w * scale)))
  let height = max(1, int(ceil(dst.h * scale)))
  if width > 4096 or height > 4096:
    return none(Sdl3ShadowTextureCacheEntry)

  var pixels = newSeq[uint8](width * height * 4)
  let blur = max(0.0'f32, command.shadowBlur)
  let shapeGrow = command.shadowSpread
  let shapeX = blur
  let shapeY = blur
  let shapeW = command.shadowRect.w + shapeGrow * 2.0'f32
  let shapeH = command.shadowRect.h + shapeGrow * 2.0'f32
  let shapeRadius = max(0.0'f32, command.shadowRadius + shapeGrow)
  let red = command.shadowColor.r.toByte
  let green = command.shadowColor.g.toByte
  let blue = command.shadowColor.b.toByte

  for y in 0 ..< height:
    let py = (y.float32 + 0.5'f32) / scale
    for x in 0 ..< width:
      let px = (x.float32 + 0.5'f32) / scale
      let distance = roundedBoxDistance(px, py, shapeX, shapeY, shapeW, shapeH, shapeRadius)
      let coverage =
        if blur <= 0.001'f32:
          if distance <= 0: 1.0'f32 else: 0.0'f32
        elif distance <= 0:
          1.0'f32
        else:
          exp(-4.0'f32 * (distance / blur) * (distance / blur))
      let index = (y * width + x) * 4
      pixels[index] = red
      pixels[index + 1] = green
      pixels[index + 2] = blue
      pixels[index + 3] = (command.shadowColor.a * coverage).toByte

  let texture = SDL3.createTexture(
    target.renderer,
    SDL_PIXELFORMAT_RGBA32,
    sdlTextureAccessStatic,
    cint(width),
    cint(height)
  )
  if texture.isNil:
    return none(Sdl3ShadowTextureCacheEntry)
  discard SDL3.setTextureBlendMode(texture, sdlBlendModeBlend)
  discard SDL3.setTextureScaleMode(texture, SDL_SCALEMODE_LINEAR)
  if pixels.len > 0:
    discard SDL3.updateTexture(texture, nil, unsafeAddr pixels[0], cint(width * 4))
  let entry = Sdl3ShadowTextureCacheEntry(
    key: key,
    texture: texture,
    width: width,
    height: height,
    lastUsed: target.frameId
  )
  target.shadowTextureCache.add entry
  target.shadowTextureCacheIndex.indexKey(key, target.shadowTextureCache.high)
  target.shadowTextureCacheBytes += textureBytes(width, height)
  target.evictShadowTextureCacheIfNeeded()
  some(entry)

proc renderLayeredBoxShadow(target: Sdl3Renderer; command: PaintCommand) =
  if command.shadowRect.w <= 0 or command.shadowRect.h <= 0 or command.shadowColor.a <= 0:
    return
  let spread = command.shadowSpread
  let blur = max(0.0'f32, command.shadowBlur)
  if blur <= 0.001'f32:
    let hardRect = command.shadowRect(spread)
    if hardRect.w <= 0 or hardRect.h <= 0:
      return
    target.fillRoundedRect(hardRect, max(0.0'f32, command.shadowRadius + spread), command.shadowColor)
    return

  let layers = max(6, min(28, int(ceil(blur * 1.35'f32))))
  for index in countdown(layers, 0):
    let t = index.float32 / layers.float32
    let grow = spread + blur * t
    let falloff = 1.0'f32 - t
    let alpha = max(0.012'f32, (falloff * falloff) / max(1.0'f32, layers.float32 * 0.42'f32))
    let layerRect = command.shadowRect(grow)
    if layerRect.w <= 0 or layerRect.h <= 0:
      continue
    let layerRadius = max(0.0'f32, command.shadowRadius + grow)
    target.fillRoundedRect(layerRect, layerRadius, command.shadowLayerColor(alpha))

proc renderBoxShadow(target: var Sdl3Renderer; command: PaintCommand) =
  if command.shadowRect.w <= 0 or command.shadowRect.h <= 0 or command.shadowColor.a <= 0:
    return
  let dst = command.shadowTextureRect()
  if dst.w <= 0 or dst.h <= 0:
    return
  let scale = target.pixelScale()
  let key = command.shadowTextureCacheKey(scale)
  let cached = target.findShadowTextureCache(key)
  let shadow =
    if cached.isSome:
      cached
    else:
      target.createShadowTexture(key, command, scale)
  if shadow.isNone:
    target.renderLayeredBoxShadow(command)
    return

  var src = SDL_FRect(x: 0, y: 0, w: cfloat(shadow.get.width), h: cfloat(shadow.get.height))
  var sdlDst = dst.toSdl
  target.renderTextureClipped(shadow.get.texture, src, sdlDst)

proc loadImageTexture(target: var Sdl3Renderer; source: string): Option[Sdl3ImageCacheEntry] =
  if source.len == 0:
    return none(Sdl3ImageCacheEntry)
  let sourceHash = hash(source)
  if sourceHash in target.imageCacheIndex:
    for entryIndex in target.imageCacheIndex[sourceHash]:
      if entryIndex >= 0 and entryIndex < target.imageCache.len and
          target.imageCache[entryIndex].source == source:
        target.imageCache[entryIndex].lastUsed = target.frameId
        return some(target.imageCache[entryIndex])
  for failed in target.imageFailures:
    if failed == source:
      return none(Sdl3ImageCacheEntry)

  let resolvedSource = target.resolveAssetPath(source)
  let image = loadRgbaImage(resolvedSource)
  if image.isNone:
    target.imageFailures.add source
    return none(Sdl3ImageCacheEntry)
  let data = image.get
  let texture = SDL3.createTexture(
    target.renderer,
    SDL_PIXELFORMAT_RGBA32,
    sdlTextureAccessStatic,
    cint(data.width),
    cint(data.height)
  )
  if texture.isNil:
    return none(Sdl3ImageCacheEntry)
  discard SDL3.setTextureBlendMode(texture, sdlBlendModeBlend)
  if data.pixels.len > 0:
    discard SDL3.updateTexture(texture, nil, unsafeAddr data.pixels[0], cint(data.width * 4))
  else:
    SDL3.destroyTexture(texture)
    target.imageFailures.add source
    return none(Sdl3ImageCacheEntry)

  let entry = Sdl3ImageCacheEntry(
    source: source,
    texture: texture,
    width: max(0.0'f32, data.width.float32),
    height: max(0.0'f32, data.height.float32),
    lastUsed: target.frameId
  )
  target.imageCache.add entry
  target.imageCacheIndex.indexKey(source, target.imageCache.high)
  target.imageCacheBytes += textureBytes(data.width, data.height)
  some(entry)

proc imageFitRects(command: PaintCommand; textureWidth, textureHeight: float32): tuple[src, dst: SDL_FRect] =
  let box = command.imageRect
  let iw = max(0.0'f32, textureWidth)
  let ih = max(0.0'f32, textureHeight)
  if box.w <= 0 or box.h <= 0 or iw <= 0 or ih <= 0:
    return (
      SDL_FRect(x: 0, y: 0, w: 0, h: 0),
      SDL_FRect(x: cfloat(box.x), y: cfloat(box.y), w: 0, h: 0)
    )

  let fit =
    if command.imageStyle.objectFit.isSome: command.imageStyle.objectFit.get
    else: ofFill
  let position =
    if command.imageStyle.objectPosition.isSome: command.imageStyle.objectPosition.get
    else: ObjectPosition(x: 50, y: 50)
  let px = max(0.0'f32, min(100.0'f32, position.x)) / 100.0'f32
  let py = max(0.0'f32, min(100.0'f32, position.y)) / 100.0'f32

  var src = Rect(x: 0, y: 0, w: iw, h: ih)
  var dst = box

  case fit
  of ofFill:
    discard
  of ofContain:
    let scale = min(box.w / iw, box.h / ih)
    dst.w = iw * scale
    dst.h = ih * scale
    dst.x = box.x + (box.w - dst.w) * px
    dst.y = box.y + (box.h - dst.h) * py
  of ofCover:
    let scale = max(box.w / iw, box.h / ih)
    let visibleW = box.w / scale
    let visibleH = box.h / scale
    src.w = min(iw, visibleW)
    src.h = min(ih, visibleH)
    src.x = (iw - src.w) * px
    src.y = (ih - src.h) * py
  of ofNone:
    dst.w = iw
    dst.h = ih
    dst.x = box.x + (box.w - dst.w) * px
    dst.y = box.y + (box.h - dst.h) * py
  of ofScaleDown:
    if iw <= box.w and ih <= box.h:
      dst.w = iw
      dst.h = ih
      dst.x = box.x + (box.w - dst.w) * px
      dst.y = box.y + (box.h - dst.h) * py
    else:
      let scale = min(box.w / iw, box.h / ih)
      dst.w = iw * scale
      dst.h = ih * scale
      dst.x = box.x + (box.w - dst.w) * px
      dst.y = box.y + (box.h - dst.h) * py

  (
    SDL_FRect(x: cfloat(src.x), y: cfloat(src.y), w: cfloat(src.w), h: cfloat(src.h)),
    SDL_FRect(x: cfloat(dst.x), y: cfloat(dst.y), w: cfloat(dst.w), h: cfloat(dst.h))
  )

proc roundedCacheFloat(value: float32): string =
  $(round(value * 100.0'f32) / 100.0'f32)

proc roundedTextureCacheKey(
    source: string;
    src, dst: SDL_FRect;
    clips: openArray[Sdl3ClipRegion];
    scale: float32
): string =
  result = source &
    "|src:" & roundedCacheFloat(src.x.float32) & "," &
      roundedCacheFloat(src.y.float32) & "," &
      roundedCacheFloat(src.w.float32) & "," &
      roundedCacheFloat(src.h.float32) &
    "|dst:" & roundedCacheFloat(dst.w.float32) & "," &
      roundedCacheFloat(dst.h.float32) &
    "|scale:" & roundedCacheFloat(scale)
  for clip in clips:
    result.add "|clip:"
    result.add roundedCacheFloat(clip.rect.x - dst.x.float32)
    result.add ","
    result.add roundedCacheFloat(clip.rect.y - dst.y.float32)
    result.add ","
    result.add roundedCacheFloat(clip.rect.w)
    result.add ","
    result.add roundedCacheFloat(clip.rect.h)
    result.add ","
    result.add roundedCacheFloat(clip.radius)

proc localClipStack(clips: openArray[Sdl3ClipRegion]; dst: SDL_FRect): seq[Sdl3ClipRegion] =
  for clip in clips:
    let localRect = Rect(
      x: clip.rect.x - dst.x.float32,
      y: clip.rect.y - dst.y.float32,
      w: clip.rect.w,
      h: clip.rect.h
    )
    result.add Sdl3ClipRegion(
      rect: localRect,
      radius: clip.radius,
      bounds: localRect.toSdlClip
    )

proc renderTextureClippedWith(
    target: Sdl3Renderer;
    texture: pointer;
    src, dst: SDL_FRect;
    clips: openArray[Sdl3ClipRegion]
) =
  if dst.w <= 0 or dst.h <= 0 or src.w <= 0 or src.h <= 0:
    return
  if not clips.hasRoundedClip():
    var srcRect = src
    var dstRect = dst
    discard SDL3.renderTexture(target.renderer, texture, addr srcRect, addr dstRect)
    return

  let yStart = int(floor(dst.y.float32))
  let yEnd = int(ceil(dst.y.float32 + dst.h.float32)) - 1
  for y in yStart .. yEnd:
    let top = y.float32
    let bottom = top + 1.0'f32
    let centerY = top + 0.5'f32
    var left = dst.x.float32
    var right = dst.x.float32 + dst.w.float32
    if not clips.clippedHorizontalSpan(centerY, left, right):
      continue
    let visibleTop = max(top, dst.y.float32)
    let visibleBottom = min(bottom, dst.y.float32 + dst.h.float32)
    if visibleBottom <= visibleTop:
      continue
    let srcY = src.y.float32 + ((visibleTop - dst.y.float32) / dst.h.float32) * src.h.float32
    let srcH = ((visibleBottom - visibleTop) / dst.h.float32) * src.h.float32
    let srcX = src.x.float32 + ((left - dst.x.float32) / dst.w.float32) * src.w.float32
    let srcW = ((right - left) / dst.w.float32) * src.w.float32
    var srcSlice = SDL_FRect(x: cfloat(srcX), y: cfloat(srcY), w: cfloat(srcW), h: cfloat(srcH))
    var dstSlice = SDL_FRect(x: cfloat(left), y: cfloat(visibleTop), w: cfloat(right - left), h: cfloat(visibleBottom - visibleTop))
    discard SDL3.renderTexture(target.renderer, texture, addr srcSlice, addr dstSlice)

proc renderTextureClipped(target: Sdl3Renderer; texture: pointer; src, dst: SDL_FRect) =
  target.renderTextureClippedWith(texture, src, dst, target.clipStack)

proc findRoundedTextureCache(
    target: var Sdl3Renderer;
    key: string
): Option[Sdl3RoundedTextureCacheEntry] =
  let keyHash = hash(key)
  if keyHash in target.roundedTextureCacheIndex:
    for entryIndex in target.roundedTextureCacheIndex[keyHash]:
      if entryIndex >= 0 and entryIndex < target.roundedTextureCache.len and
          target.roundedTextureCache[entryIndex].key == key:
        target.roundedTextureCache[entryIndex].lastUsed = target.frameId
        return some(target.roundedTextureCache[entryIndex])
  none(Sdl3RoundedTextureCacheEntry)

proc evictRoundedTextureCacheIfNeeded(target: var Sdl3Renderer) =
  let limit =
    if target.roundedTextureCacheLimit > 0: target.roundedTextureCacheLimit
    else: 128
  while target.roundedTextureCache.len > limit or
      (target.roundedTextureCache.len > 1 and
        target.roundedTextureCacheBytes > target.roundedTextureCacheByteLimit):
    var victim = 0
    for index in 1 ..< target.roundedTextureCache.len:
      if target.roundedTextureCache[index].lastUsed < target.roundedTextureCache[victim].lastUsed:
        victim = index
    if not target.roundedTextureCache[victim].texture.isNil:
      SDL3.destroyTexture(target.roundedTextureCache[victim].texture)
    target.roundedTextureCacheBytes -= textureBytes(
      target.roundedTextureCache[victim].width,
      target.roundedTextureCache[victim].height
    )
    target.roundedTextureCache.delete(victim)
    target.rebuildRoundedTextureCacheIndex()

proc createRoundedImageTexture(
    target: var Sdl3Renderer;
    key: string;
    sourceTexture: pointer;
    src, dst: SDL_FRect;
    clips: openArray[Sdl3ClipRegion]
): Option[Sdl3RoundedTextureCacheEntry] =
  let width = max(1, int(ceil(dst.w.float32)))
  let height = max(1, int(ceil(dst.h.float32)))
  let texture = SDL3.createTexture(
    target.renderer,
    SDL_PIXELFORMAT_RGBA32,
    sdlTextureAccessTarget,
    cint(width),
    cint(height)
  )
  if texture.isNil:
    return none(Sdl3RoundedTextureCacheEntry)

  discard SDL3.setTextureBlendMode(texture, sdlBlendModeBlend)
  discard SDL3.setTextureScaleMode(texture, SDL_SCALEMODE_LINEAR)

  let previousTarget = SDL3.getRenderTarget(target.renderer)
  discard SDL3.setRenderTarget(target.renderer, texture)
  discard SDL3.setRenderLogicalPresentation(
    target.renderer,
    cint(width),
    cint(height),
    SDL_LOGICAL_PRESENTATION_STRETCH
  )
  target.renderer.setClip(none(SDL_Rect))
  discard SDL3.setRenderDrawColor(target.renderer, 0, 0, 0, 0)
  discard SDL3.renderClear(target.renderer)

  discard SDL3.setTextureAlphaModFloat(sourceTexture, 1.0)
  let localClips = localClipStack(clips, dst)
  var localDst = SDL_FRect(x: 0, y: 0, w: cfloat(dst.w.float32), h: cfloat(dst.h.float32))
  target.renderTextureClippedWith(sourceTexture, src, localDst, localClips)

  discard SDL3.setRenderTarget(target.renderer, previousTarget)
  target.updateLogicalPresentation()
  target.renderer.setClip(target.effectiveClipBounds())

  let entry = Sdl3RoundedTextureCacheEntry(
    key: key,
    texture: texture,
    width: width,
    height: height,
    lastUsed: target.frameId
  )
  target.roundedTextureCache.add entry
  target.roundedTextureCacheIndex.indexKey(key, target.roundedTextureCache.high)
  target.roundedTextureCacheBytes += textureBytes(width, height)
  target.evictRoundedTextureCacheIfNeeded()
  some(entry)

proc drawImageTexture(
    target: var Sdl3Renderer;
    command: PaintCommand;
    roundedImageClips: openArray[Sdl3ClipRegion] = []
) =
  target.queueImageEvent(command.imageNode, command.imageSource, sieLoadStart)
  let entry = target.loadImageTexture(command.imageSource)
  if entry.isNone:
    target.queueImageEvent(command.imageNode, command.imageSource, sieError)
    target.queueImageEvent(command.imageNode, command.imageSource, sieLoadEnd)
    return
  target.queueImageEvent(command.imageNode, command.imageSource, sieLoad)
  target.queueImageEvent(command.imageNode, command.imageSource, sieLoadEnd)
  let texture = entry.get.texture
  let alpha = max(0.0'f32, min(1.0'f32, command.imageOpacity))
  discard SDL3.setTextureAlphaModFloat(texture, cfloat(alpha))
  var rects = command.imageFitRects(entry.get.width, entry.get.height)
  if rects.src.w <= 0 or rects.src.h <= 0 or rects.dst.w <= 0 or rects.dst.h <= 0:
    return

  if roundedImageClips.hasRoundedClip():
    let key = roundedTextureCacheKey(command.imageSource, rects.src, rects.dst, roundedImageClips, target.pixelScale())
    let cached = target.findRoundedTextureCache(key)
    let rounded =
      if cached.isSome:
        cached
      else:
        target.createRoundedImageTexture(key, texture, rects.src, rects.dst, roundedImageClips)
    if rounded.isSome:
      let roundedEntry = rounded.get
      discard SDL3.setTextureAlphaModFloat(roundedEntry.texture, cfloat(alpha))
      var dst = rects.dst
      discard SDL3.renderTexture(target.renderer, roundedEntry.texture, nil, addr dst)
      return

  target.renderTextureClipped(texture, rects.src, rects.dst)

proc evictTextCacheIfNeeded(target: var Sdl3Renderer) =
  let limit =
    if target.textCacheLimit > 0: target.textCacheLimit
    else: 256
  while target.textCache.len > limit or
      (target.textCache.len > 1 and target.textCacheBytes > target.textCacheByteLimit):
    var victim = 0
    for index in 1 ..< target.textCache.len:
      if target.textCache[index].lastUsed < target.textCache[victim].lastUsed:
        victim = index
    if not target.textCache[victim].texture.isNil:
      SDL3.destroyTexture(target.textCache[victim].texture)
    target.textCacheBytes -= textureBytes(
      target.textCache[victim].width,
      target.textCache[victim].height
    )
    target.textCache.delete(victim)
    target.rebuildTextCacheIndex()

proc evictImageCacheIfNeeded(target: var Sdl3Renderer) =
  let limit =
    if target.imageCacheLimit > 0: target.imageCacheLimit
    else: 128
  while target.imageCache.len > limit or
      (target.imageCache.len > 1 and target.imageCacheBytes > target.imageCacheByteLimit):
    var victim = 0
    for index in 1 ..< target.imageCache.len:
      if target.imageCache[index].lastUsed < target.imageCache[victim].lastUsed:
        victim = index
    if not target.imageCache[victim].texture.isNil:
      SDL3.destroyTexture(target.imageCache[victim].texture)
    target.imageCacheBytes -= textureBytes(
      int(target.imageCache[victim].width),
      int(target.imageCache[victim].height)
    )
    target.imageCache.delete(victim)
    target.rebuildImageCacheIndex()

proc render*(target: var Sdl3Renderer; commands: openArray[PaintCommand]; clearColor = rgb(1, 1, 1)) =
  inc target.frameId
  target.updateLogicalPresentation()
  target.renderer.setColor(clearColor)
  discard SDL3.renderClear(target.renderer)
  target.clipStack.setLen(0)
  target.renderer.setClip(none(SDL_Rect))

  var transformLayers: seq[Sdl3TransformLayer]
  for sourcePrepared in prepareRenderPlan(commands):
    let sourceCommand = sourcePrepared.command
    if sourceCommand.kind == pcPushTransform:
      target.beginTransformLayer(sourceCommand, transformLayers)
      continue
    if sourceCommand.kind == pcPushLayer:
      target.beginCompositeLayer(sourceCommand, transformLayers)
      continue
    if sourceCommand.kind == pcPopTransform:
      target.endTransformLayer(transformLayers)
      continue
    if sourceCommand.kind == pcPopLayer:
      target.endTransformLayer(transformLayers)
      continue
    if transformLayers.renderingSuppressed():
      continue
    let prepared = sourcePrepared.localPreparedCommand(transformLayers)
    let command = prepared.command
    case command.kind
    of pcPushTransform, pcPopTransform, pcPushLayer, pcPopLayer:
      discard # Handled before localization.
    of pcPushClip:
      target.clipStack.add command.clipRegion()
      target.renderer.setClip(target.effectiveClipBounds())
    of pcPopClip:
      if target.clipStack.len > 0:
        target.clipStack.setLen(target.clipStack.len - 1)
      target.renderer.setClip(target.effectiveClipBounds())
    of pcBoxShadow:
      transformLayers.markTransformContent()
      target.renderBoxShadow(command)
    of pcFillRect:
      transformLayers.markTransformContent()
      target.fillRoundedRect(command.rect, command.radius, command.color)
    of pcFillLinearGradient:
      transformLayers.markTransformContent()
      target.fillLinearGradientPattern(
        command.gradientRect, command.gradientPaintRect,
        command.gradientClipRect,
        command.gradient, command.gradientRepeat, command.gradientRadius
      )
    of pcStrokeRect:
      transformLayers.markTransformContent()
      target.strokeRoundedRect(command.strokeRect, command.strokeRadius, command.strokeWidth, command.strokeColor)
    of pcStrokePath:
      transformLayers.markTransformContent()
      target.renderStrokePath(command)
    of pcDrawText:
      transformLayers.markTransformContent()
      target.renderer.drawDebugText(command)
    of pcDrawImage:
      transformLayers.markTransformContent()
      target.drawImageTexture(command, prepared.roundedImageClipStack)
      target.evictImageCacheIfNeeded()

  target.closeTransformLayers(transformLayers)

  target.captureCurrentFrame()
  discard SDL3.renderPresent(target.renderer)
  target.destroyTransientTextTextures()

proc drawCosmicText(
    target: var Sdl3Renderer;
    command: PaintCommand;
    cosmic: CosmicTextEngine;
    fonts: FontRegistry
) =
  if command.textStyle.textShadow.isSome:
    let shadow = command.textStyle.textShadow.get
    let shadowColor =
      if shadow.color.isSome: shadow.color.get
      else: rgba(0, 0, 0, 0.45)
    var shadowStyle = command.textStyle
    shadowStyle.textShadow = none(BoxShadow)
    var shadowCommand = command
    shadowCommand.textStyle = shadowStyle
    shadowCommand.textColor = shadowColor
    shadowCommand.position = vec2(command.position.x + shadow.offsetX, command.position.y + shadow.offsetY)
    let blur = max(0.0'f32, shadow.blur)
    if blur <= 0.001'f32:
      target.drawCosmicText(shadowCommand, cosmic, fonts)
    else:
      let samples = max(8, min(24, int(ceil(blur * 1.5'f32))))
      let rings = 2
      for ring in 1 .. rings:
        let radius = blur * ring.float32 / rings.float32
        let alpha = shadowColor.a / (samples.float32 * rings.float32 * 0.55'f32)
        shadowCommand.textColor = rgba(shadowColor.r, shadowColor.g, shadowColor.b, alpha)
        for index in 0 ..< samples:
          let angle = TAU * index.float32 / samples.float32
          shadowCommand.position = vec2(
            command.position.x + shadow.offsetX + cos(angle) * radius,
            command.position.y + shadow.offsetY + sin(angle) * radius
          )
          target.drawCosmicText(shadowCommand, cosmic, fonts)
      shadowCommand.textColor = rgba(shadowColor.r, shadowColor.g, shadowColor.b, shadowColor.a * 0.35'f32)
      shadowCommand.position = vec2(command.position.x + shadow.offsetX, command.position.y + shadow.offsetY)
      target.drawCosmicText(shadowCommand, cosmic, fonts)

  let input = TextMeasureInput(
    text: command.text,
    style: command.textStyle,
    maxWidth: command.textMaxWidth,
    fonts: fonts
  )
  let scale = target.pixelScale()
  var rasterInput = input
  rasterInput.style = command.textStyle.scaleTextStyle(scale)
  if rasterInput.maxWidth.isSome:
    rasterInput.maxWidth = some(rasterInput.maxWidth.get * scale)
  let key = rasterInput.cosmicTextRasterKey() &
    "|scale:" & $scale &
    "|color:" & command.textColor.textColorKey()
  let cacheable = command.text.len <= 256 and key.len <= 2048
  if cacheable:
    let keyHash = hash(key)
    if keyHash in target.textCacheIndex:
      for entryIndex in target.textCacheIndex[keyHash]:
        if entryIndex >= 0 and entryIndex < target.textCache.len and
            target.textCache[entryIndex].key == key:
          target.textCache[entryIndex].lastUsed = target.frameId
          target.drawTextTexture(command, target.textCache[entryIndex])
          return

  let bitmap =
    if not cacheable and target.effectiveClipBounds().isSome:
      let clip = target.effectiveClipBounds().get
      let lineHeight =
        if rasterInput.style.lineHeight.isSome: rasterInput.style.lineHeight.get
        elif rasterInput.style.fontSize.isSome: rasterInput.style.fontSize.get * 1.2'f32
        else: 19.2'f32 * scale
      let overscan = max(2.0'f32, lineHeight * 2.0'f32)
      let regionTop =
        (clip.y.float32 - command.position.y) * scale - overscan
      let regionHeight = clip.h.float32 * scale + overscan * 2.0'f32
      cosmic.renderCosmicTextBitmapRegion(
        rasterInput,
        regionTop,
        regionHeight
      )
    else:
      cosmic.renderCosmicTextBitmap(rasterInput)
  if bitmap.isNone or bitmap.get.width <= 0 or bitmap.get.height <= 0:
    target.renderer.drawDebugText(command)
    return
  var data = bitmap.get
  let red = command.textColor.r.toByte
  let green = command.textColor.g.toByte
  let blue = command.textColor.b.toByte
  let alphaScale = command.textColor.a
  for index in countup(0, data.pixels.high, 4):
    data.pixels[index] = red
    data.pixels[index + 1] = green
    data.pixels[index + 2] = blue
    data.pixels[index + 3] = uint8(max(0, min(255, int(round(data.pixels[index + 3].float32 * alphaScale)))))
  let texture = SDL3.createTexture(
    target.renderer,
    SDL_PIXELFORMAT_RGBA32,
    sdlTextureAccessStatic,
    cint(data.width),
    cint(data.height)
  )
  if texture.isNil:
    target.renderer.drawDebugText(command)
    return
  discard SDL3.setTextureBlendMode(texture, sdlBlendModeBlend)
  discard SDL3.setTextureScaleMode(texture, SDL_SCALEMODE_LINEAR)
  discard SDL3.updateTexture(texture, nil, unsafeAddr data.pixels[0], cint(data.width * 4))
  let entry = Sdl3TextCacheEntry(
    key: key,
    texture: texture,
    width: data.width,
    height: data.height,
    offsetX: data.offsetX,
    offsetY: data.offsetY,
    scale: scale,
    lastUsed: target.frameId
  )
  target.drawTextTexture(command, entry)
  if cacheable:
    target.textCache.add(entry)
    target.textCacheIndex.indexKey(key, target.textCache.high)
    target.textCacheBytes += textureBytes(data.width, data.height)
    target.evictTextCacheIfNeeded()
  else:
    target.transientTextTextures.add texture

proc render*(
    target: var Sdl3Renderer;
    commands: openArray[PaintCommand];
    cosmic: CosmicTextEngine;
    fonts: FontRegistry;
    clearColor = rgb(1, 1, 1)
) =
  inc target.frameId
  target.updateLogicalPresentation()
  target.renderer.setColor(clearColor)
  discard SDL3.renderClear(target.renderer)
  target.clipStack.setLen(0)
  target.renderer.setClip(none(SDL_Rect))

  var transformLayers: seq[Sdl3TransformLayer]
  for sourcePrepared in prepareRenderPlan(commands):
    let sourceCommand = sourcePrepared.command
    if sourceCommand.kind == pcPushTransform:
      target.beginTransformLayer(sourceCommand, transformLayers)
      continue
    if sourceCommand.kind == pcPushLayer:
      target.beginCompositeLayer(sourceCommand, transformLayers)
      continue
    if sourceCommand.kind == pcPopTransform:
      target.endTransformLayer(transformLayers)
      continue
    if sourceCommand.kind == pcPopLayer:
      target.endTransformLayer(transformLayers)
      continue
    if transformLayers.renderingSuppressed():
      continue
    let prepared = sourcePrepared.localPreparedCommand(transformLayers)
    let command = prepared.command
    case command.kind
    of pcPushTransform, pcPopTransform, pcPushLayer, pcPopLayer:
      discard # Handled before localization.
    of pcPushClip:
      target.clipStack.add command.clipRegion()
      target.renderer.setClip(target.effectiveClipBounds())
    of pcPopClip:
      if target.clipStack.len > 0:
        target.clipStack.setLen(target.clipStack.len - 1)
      target.renderer.setClip(target.effectiveClipBounds())
    of pcBoxShadow:
      transformLayers.markTransformContent()
      target.renderBoxShadow(command)
    of pcFillRect:
      transformLayers.markTransformContent()
      target.fillRoundedRect(command.rect, command.radius, command.color)
    of pcFillLinearGradient:
      transformLayers.markTransformContent()
      target.fillLinearGradientPattern(
        command.gradientRect, command.gradientPaintRect,
        command.gradientClipRect,
        command.gradient, command.gradientRepeat, command.gradientRadius
      )
    of pcStrokeRect:
      transformLayers.markTransformContent()
      target.strokeRoundedRect(command.strokeRect, command.strokeRadius, command.strokeWidth, command.strokeColor)
    of pcStrokePath:
      transformLayers.markTransformContent()
      target.renderStrokePath(command)
    of pcDrawText:
      transformLayers.markTransformContent()
      target.drawCosmicText(command, cosmic, fonts)
    of pcDrawImage:
      transformLayers.markTransformContent()
      target.drawImageTexture(command, prepared.roundedImageClipStack)
      target.evictImageCacheIfNeeded()

  target.closeTransformLayers(transformLayers)

  target.captureCurrentFrame()
  discard SDL3.renderPresent(target.renderer)
  target.destroyTransientTextTextures()

proc renderPreparedCommand(
    target: var Sdl3Renderer;
    prepared: Sdl3PreparedCommand;
    cosmic: CosmicTextEngine;
    fonts: FontRegistry;
    dynamicOnly: bool;
    skipDynamic: bool;
    dynamicNodeMask: openArray[bool];
    transformLayers: var seq[Sdl3TransformLayer]
) =
  let sourceCommand = prepared.command
  if sourceCommand.kind == pcPushTransform:
    target.beginTransformLayer(sourceCommand, transformLayers)
    return
  if sourceCommand.kind == pcPushLayer:
    target.beginCompositeLayer(sourceCommand, transformLayers)
    return
  if sourceCommand.kind == pcPopTransform:
    target.endTransformLayer(transformLayers)
    return
  if sourceCommand.kind == pcPopLayer:
    target.endTransformLayer(transformLayers)
    return
  if transformLayers.renderingSuppressed():
    return
  let localPrepared = prepared.localPreparedCommand(transformLayers)
  let command = localPrepared.command
  let isDynamic =
    command.owner.isSome and
      command.owner.get.nodeIndex >= 0 and
      command.owner.get.nodeIndex < dynamicNodeMask.len and
      dynamicNodeMask[command.owner.get.nodeIndex]
  let drawCommand =
    if dynamicOnly: isDynamic
    elif skipDynamic: not isDynamic
    else: true
  case command.kind
  of pcPushTransform, pcPopTransform, pcPushLayer, pcPopLayer:
    discard
  of pcPushClip:
    target.clipStack.add command.clipRegion()
    target.renderer.setClip(target.effectiveClipBounds())
  of pcPopClip:
    if target.clipStack.len > 0:
      target.clipStack.setLen(target.clipStack.len - 1)
      target.renderer.setClip(target.effectiveClipBounds())
  of pcBoxShadow:
    if drawCommand:
      transformLayers.markTransformContent()
      target.renderBoxShadow(command)
  of pcFillRect:
    if drawCommand:
      transformLayers.markTransformContent()
      target.fillRoundedRect(command.rect, command.radius, command.color)
  of pcFillLinearGradient:
    if drawCommand:
      transformLayers.markTransformContent()
      target.fillLinearGradientPattern(
        command.gradientRect, command.gradientPaintRect,
        command.gradientClipRect,
        command.gradient, command.gradientRepeat, command.gradientRadius
      )
  of pcStrokeRect:
    if drawCommand:
      transformLayers.markTransformContent()
      target.strokeRoundedRect(command.strokeRect, command.strokeRadius, command.strokeWidth, command.strokeColor)
  of pcStrokePath:
    if drawCommand:
      transformLayers.markTransformContent()
      target.renderStrokePath(command)
  of pcDrawText:
    if drawCommand:
      transformLayers.markTransformContent()
      target.drawCosmicText(command, cosmic, fonts)
  of pcDrawImage:
    if drawCommand:
      transformLayers.markTransformContent()
      target.drawImageTexture(command, localPrepared.roundedImageClipStack)
      target.evictImageCacheIfNeeded()

proc renderCommandPass(
    target: var Sdl3Renderer;
    commands: openArray[PaintCommand];
    cosmic: CosmicTextEngine;
    fonts: FontRegistry;
    dynamicOnly = false;
    skipDynamic = false;
    dynamicNodes: openArray[NodeId] = []
) =
  target.clipStack.setLen(0)
  target.renderer.setClip(none(SDL_Rect))
  var highestDynamicNode = -1
  for node in dynamicNodes:
    highestDynamicNode = max(highestDynamicNode, node.nodeIndex)
  var dynamicNodeMask = newSeq[bool](highestDynamicNode + 1)
  for node in dynamicNodes:
    if node.nodeIndex >= 0:
      dynamicNodeMask[node.nodeIndex] = true
  var transformLayers: seq[Sdl3TransformLayer]
  for prepared in prepareRenderPlan(commands):
    target.renderPreparedCommand(
      prepared, cosmic, fonts, dynamicOnly, skipDynamic, dynamicNodeMask,
      transformLayers
    )
  target.closeTransformLayers(transformLayers)

proc ensureStaticLayer(target: var Sdl3Renderer): bool =
  let output = target.windowSize()
  let width = int(max(1.0'f32, round(output.w)))
  let height = int(max(1.0'f32, round(output.h)))
  if not target.staticLayerTexture.isNil and
      target.staticLayerWidth == width and
      target.staticLayerHeight == height:
    return true

  target.destroyStaticLayer()
  target.staticLayerTexture = SDL3.createTexture(
    target.renderer,
    SDL_PIXELFORMAT_RGBA32,
    sdlTextureAccessTarget,
    cint(width),
    cint(height)
  )
  if target.staticLayerTexture.isNil:
    return false
  discard SDL3.setTextureBlendMode(target.staticLayerTexture, sdlBlendModeBlend)
  target.staticLayerWidth = width
  target.staticLayerHeight = height
  true

proc renderLayered*(
    target: var Sdl3Renderer;
    commands: openArray[PaintCommand];
    cosmic: CosmicTextEngine;
    fonts: FontRegistry;
    clearColor = rgb(1, 1, 1);
    rebuildStatic = true;
    dynamicNodes: openArray[NodeId] = [];
    dynamicCommands: openArray[PaintCommand] = []
) =
  if not target.ensureStaticLayer():
    target.render(commands, cosmic, fonts, clearColor)
    return

  inc target.frameId
  target.updateLogicalPresentation()

  if rebuildStatic:
    let previousTarget = SDL3.getRenderTarget(target.renderer)
    discard SDL3.setRenderTarget(target.renderer, target.staticLayerTexture)
    target.renderer.setColor(clearColor)
    discard SDL3.renderClear(target.renderer)
    target.renderCommandPass(
      commands,
      cosmic,
      fonts,
      dynamicOnly = false,
      skipDynamic = true,
      dynamicNodes = dynamicNodes
    )
    discard SDL3.setRenderTarget(target.renderer, previousTarget)

  target.renderer.setColor(clearColor)
  discard SDL3.renderClear(target.renderer)
  var src = SDL_FRect(
    x: 0,
    y: 0,
    w: cfloat(target.staticLayerWidth),
    h: cfloat(target.staticLayerHeight)
  )
  let logical = target.windowSize()
  var dst = SDL_FRect(x: 0, y: 0, w: cfloat(logical.w), h: cfloat(logical.h))
  discard SDL3.renderTexture(target.renderer, target.staticLayerTexture, addr src, addr dst)
  if dynamicCommands.len > 0:
    target.renderCommandPass(dynamicCommands, cosmic, fonts)
  else:
    target.renderCommandPass(
      commands,
      cosmic,
      fonts,
      dynamicOnly = true,
      skipDynamic = false,
      dynamicNodes = dynamicNodes
    )
  target.captureCurrentFrame()
  discard SDL3.renderPresent(target.renderer)
  target.destroyTransientTextTextures()
