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
    echo "missing bgfx integration input: $required" >&2
    exit 2
  }
done

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/cbss-bgfx-noop.XXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT HUP INT TERM

cxx=${CXX:-c++}
archiver=${AR:-ar}
simd_flag=
case $(uname -m) in
  x86_64|amd64) simd_flag=-msse4.1 ;;
esac

set --
cxx_runtime=-lstdc++
dynamic_link_arg=--passL:-ldl
frameworks=
if [ "$(uname -s)" = Darwin ]; then
  set -- "-I$bx_dir/include/compat/osx"
  cxx_runtime=-lc++
  dynamic_link_arg=
  frameworks="--passL:-framework --passL:Foundation --passL:-framework --passL:CoreFoundation --passL:-lobjc"
fi

"$cxx" -std=c++20 -O2 -fPIC -pthread -DBX_CONFIG_DEBUG=0 "$@" \
  -I"$bx_dir/include" -I"$bx_dir/3rdparty" \
  -c "$bx_dir/src/amalgamated.cpp" -o "$build_dir/bx.o"

"$cxx" -std=c++20 -O2 -fPIC -pthread \
  -DBX_CONFIG_DEBUG=0 -DBGFX_CONFIG_RENDERER_VULKAN=0 "$@" \
  -I"$bgfx_dir/include" -I"$bgfx_dir/src" -I"$bgfx_dir/3rdparty" \
  -I"$bx_dir/include" -I"$bx_dir/3rdparty" -I"$bimg_dir/include" \
  -c "$bgfx_dir/src/amalgamated.cpp" -o "$build_dir/bgfx.o"

"$cxx" -std=c++20 -O2 -fPIC -pthread $simd_flag \
  -DBX_CONFIG_DEBUG=0 -DASTCENC_F16C=0 -DASTCENC_NEON=0 "$@" \
  -I"$bimg_dir/include" -I"$bimg_dir/3rdparty/astc-encoder/include" \
  -I"$bx_dir/include" -I"$bx_dir/3rdparty" \
  -c "$bimg_dir/src/image.cpp" -o "$build_dir/bimg.o"

for source in "$bimg_dir"/3rdparty/astc-encoder/source/*.cpp; do
  name=${source##*/}
  "$cxx" -std=c++20 -O2 -fPIC -pthread $simd_flag \
    -DASTCENC_F16C=0 -DASTCENC_NEON=0 "$@" \
    -I"$bimg_dir/3rdparty/astc-encoder/include" \
    -I"$bimg_dir/3rdparty/astc-encoder/source" \
    -c "$source" -o "$build_dir/${name%.cpp}.o"
done
"$archiver" rcs "$build_dir/libbimg.a" "$build_dir/bimg.o" \
  "$build_dir"/astcenc_*.o

for memory_model in arc orc; do
  nim c -r --mm:"$memory_model" -d:cbssGpuBgfx --path:src \
    --path:"$bgfxim_dir" \
    --nimcache:"$build_dir/nim-$memory_model" \
    --out:"$build_dir/test-$memory_model" \
    --passC:"-I$bgfx_dir/include" --passC:"-I$bx_dir/include" \
    --passL:"$build_dir/bgfx.o" --passL:"$build_dir/libbimg.a" \
    --passL:"$build_dir/bx.o" --passL:"$cxx_runtime" \
    --passL:-pthread --passL:-lm $dynamic_link_arg \
    $frameworks tests/backends/test_bgfx_host_noop.nim
done
