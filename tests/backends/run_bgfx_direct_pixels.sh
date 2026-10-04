#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

if [ "$#" -ne 4 ]; then
  echo "usage: $0 <bgfxim-dir> <bgfx-dir> <bx-dir> <bimg-dir>" >&2
  exit 2
fi

bgfxim_dir=$1
bgfx_dir=$2
bx_dir=$3
bimg_dir=$4

for required in \
  "$bgfxim_dir/bgfx.nim" \
  "$bgfx_dir/src/amalgamated.cpp" \
  "$bx_dir/src/amalgamated.cpp" \
  "$bimg_dir/src/image.cpp" \
  "$bimg_dir/3rdparty/astc-encoder/include/astcenc.h"
do
  test -f "$required" || {
    echo "missing bgfx pixel-test input: $required" >&2
    exit 2
  }
done

test -n "${CBSS_SHADERC:-}" && test -x "$CBSS_SHADERC" || {
  echo "CBSS_SHADERC must point to the official bgfx shaderc executable" >&2
  exit 2
}
test -n "${CBSS_BGFX_SHADER_INCLUDE:-}" && \
  test -d "$CBSS_BGFX_SHADER_INCLUDE" || {
  echo "CBSS_BGFX_SHADER_INCLUDE must point to the bgfx shader include directory" >&2
  exit 2
}
sdl_mode=${CBSS_GPU_PIXEL_SDL_MODE:-system}
case "$sdl_mode" in
  system)
    pkg-config --exists sdl3 || {
      echo "SDL3 development files were not found through pkg-config" >&2
      exit 2
    }
    sdl_cflags=$(pkg-config --cflags sdl3)
    sdl_libs=$(pkg-config --libs sdl3)
    ;;
  bundled)
    sdl_cflags=
    sdl_libs=
    test -f vendor/sdl3/linux-x86_64/libSDL3.a || {
      echo "bundled SDL3 runtime is missing" >&2
      exit 2
    }
    ;;
  *)
    echo "CBSS_GPU_PIXEL_SDL_MODE must be system or bundled" >&2
    exit 2
    ;;
esac

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/cbss-bgfx-pixels.XXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT HUP INT TERM

cxx=${CXX:-c++}
archiver=${AR:-ar}
simd_flag=
case $(uname -m) in
  x86_64|amd64) simd_flag=-msse4.1 ;;
esac

echo "Building the CBSS bgfx OpenGL pixel-conformance fixture..."

"$cxx" -std=c++20 -O2 -fPIC -pthread $simd_flag \
  -DBX_CONFIG_DEBUG=0 \
  -I"$bx_dir/include" -I"$bx_dir/3rdparty" \
  -c "$bx_dir/src/amalgamated.cpp" -o "$build_dir/bx.o"

"$cxx" -std=c++20 -O2 -fPIC -pthread $simd_flag \
  -DBX_CONFIG_DEBUG=0 -DBGFX_CONFIG_RENDERER_OPENGL=43 \
  -I"$bgfx_dir/include" -I"$bgfx_dir/src" -I"$bgfx_dir/3rdparty" \
  -I"$bgfx_dir/3rdparty/khronos" \
  -I"$bx_dir/include" -I"$bx_dir/3rdparty" -I"$bimg_dir/include" \
  -c "$bgfx_dir/src/amalgamated.cpp" -o "$build_dir/bgfx.o"

"$cxx" -std=c++20 -O2 -fPIC -pthread $simd_flag \
  -DBX_CONFIG_DEBUG=0 -DASTCENC_F16C=0 -DASTCENC_NEON=0 \
  -I"$bimg_dir/include" -I"$bimg_dir/3rdparty/astc-encoder/include" \
  -I"$bx_dir/include" -I"$bx_dir/3rdparty" \
  -c "$bimg_dir/src/image.cpp" -o "$build_dir/bimg.o"

for source in "$bimg_dir"/3rdparty/astc-encoder/source/*.cpp; do
  name=${source##*/}
  "$cxx" -std=c++20 -O2 -fPIC -pthread $simd_flag \
    -DASTCENC_F16C=0 -DASTCENC_NEON=0 \
    -I"$bimg_dir/3rdparty/astc-encoder/include" \
    -I"$bimg_dir/3rdparty/astc-encoder/source" \
    -c "$source" -o "$build_dir/${name%.cpp}.o"
done
"$archiver" rcs "$build_dir/libbimg.a" "$build_dir/bimg.o" \
  "$build_dir"/astcenc_*.o

for memory_model in arc orc; do
nim c -r --mm:"$memory_model" -d:release -d:cbssGpuBgfx \
  -d:cbssGpuCompositorDiagnostics \
  -d:cbssSdl3LinkMode="$sdl_mode" --path:src --path:"$bgfxim_dir" \
  -d:cbssRuntimeRoot="$PWD/vendor/sdl3" \
  --nimcache:"$build_dir/nim-$memory_model" \
  --out:"$build_dir/cbss-bgfx-pixels-$memory_model" \
  --passC:"-I$bgfx_dir/include" --passC:"-I$bx_dir/include" \
  --passC:"$sdl_cflags" \
  --passL:"$build_dir/bgfx.o" --passL:"$build_dir/libbimg.a" \
  --passL:"$build_dir/bx.o" --passL:-lstdc++ --passL:-pthread \
  --passL:-ldl --passL:-lm --passL:"$sdl_libs" \
  tests/backends/test_bgfx_direct_pixels.nim
done
