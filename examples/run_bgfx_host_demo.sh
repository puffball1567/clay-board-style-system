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
  "$bgfx_dir/examples/runtime/shaders/glsl/vs_cubes.bin" \
  "$bgfx_dir/examples/runtime/shaders/glsl/fs_cubes.bin" \
  "$bx_dir/src/amalgamated.cpp" \
  "$bimg_dir/src/image.cpp" \
  "$bimg_dir/3rdparty/astc-encoder/include/astcenc.h"
do
  test -f "$required" || {
    echo "missing bgfx demo input: $required" >&2
    exit 2
  }
done

if ! pkg-config --exists sdl3; then
  echo "SDL3 development files were not found through pkg-config" >&2
  exit 2
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/cbss-bgfx-demo.XXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT HUP INT TERM

cxx=${CXX:-c++}
archiver=${AR:-ar}
simd_flag=
case $(uname -m) in
  x86_64|amd64) simd_flag=-msse4.1 ;;
esac
sdl_cflags=$(pkg-config --cflags sdl3)
sdl_libs=$(pkg-config --libs sdl3)

echo "Building the optional CBSS bgfx OpenGL demo..."

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

nim c -r --mm:arc -d:release -d:cbssGpuBgfx \
  -d:cbssSdl3LinkMode=system --path:src --path:"$bgfxim_dir" \
  --nimcache:"$build_dir/nim" --out:"$build_dir/cbss-bgfx-host-demo" \
  --passC:"-I$bgfx_dir/include" --passC:"-I$bx_dir/include" \
  --passC:"$sdl_cflags" \
  --passL:"$build_dir/bgfx.o" --passL:"$build_dir/libbimg.a" \
  --passL:"$build_dir/bx.o" --passL:-lstdc++ --passL:-pthread \
  --passL:-ldl --passL:-lm --passL:"$sdl_libs" \
  examples/bgfx_host_demo.nim \
  "$bgfx_dir/examples/runtime/shaders/glsl"
