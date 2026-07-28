import std/options

import ./config

{.passL: sdl3ImageBridgeLinkFlags.}

type
  RgbaImage* = object
    width*: int
    height*: int
    pixels*: seq[uint8]

proc cbssImageLoad(
    path: cstring;
    outPixels: ptr ptr uint8;
    outWidth: ptr uint32;
    outHeight: ptr uint32;
    outLen: ptr csize_t
): cint {.importc: "cbss_image_load", cdecl.}

proc cbssImageFree(
    pixels: ptr uint8;
    len: csize_t
) {.importc: "cbss_image_free", cdecl.}

proc loadRgbaImage*(path: string): Option[RgbaImage] =
  if path.len == 0:
    return none(RgbaImage)

  var raw: ptr uint8
  var width, height: uint32
  var rawLen: csize_t
  let status = cbssImageLoad(
    path.cstring,
    addr raw,
    addr width,
    addr height,
    addr rawLen
  )
  let expectedLen = width.uint64 * height.uint64 * 4'u64
  if status != 0 or raw.isNil or width == 0'u32 or height == 0'u32 or
      expectedLen > high(int).uint64 or rawLen.uint64 != expectedLen:
    if not raw.isNil:
      cbssImageFree(raw, rawLen)
    return none(RgbaImage)

  let pixelCount = int(expectedLen)
  var image = RgbaImage(
    width: int(width),
    height: int(height),
    pixels: newSeq[uint8](pixelCount)
  )
  copyMem(addr image.pixels[0], raw, pixelCount)
  cbssImageFree(raw, rawLen)
  some(image)
