version       = "0.1.0"
author        = "Clay Board Style System contributors"
description   = "CSS-like primitive style and layout foundation for native GUI libraries"
license       = "MIT"
srcDir        = "src"
bin           = @["cbss_configure"]
installDirs   = @["include", "native", "licenses", "docs"]
installExt    = @["nim"]
skipDirs      = @["target"]

requires "nim >= 2.2.0"

before install:
  let packageRoot = thisDir()
  let stagedRoot = packageRoot & "/src"

  cpDir(packageRoot & "/licenses", stagedRoot & "/licenses")
  cpDir(packageRoot & "/docs", stagedRoot & "/docs")
  cpDir(packageRoot & "/include", stagedRoot & "/include")

  let bridgeSource = packageRoot & "/native/cosmic_text_bridge"
  let bridgeTarget = stagedRoot & "/native/cosmic_text_bridge"
  mkDir(bridgeTarget)
  cpFile(bridgeSource & "/Cargo.toml", bridgeTarget & "/Cargo.toml")
  cpFile(bridgeSource & "/Cargo.lock", bridgeTarget & "/Cargo.lock")
  cpDir(bridgeSource & "/src", bridgeTarget & "/src")

  let imageBridgeSource = packageRoot & "/native/image_bridge"
  let imageBridgeTarget = stagedRoot & "/native/image_bridge"
  mkDir(imageBridgeTarget)
  cpFile(imageBridgeSource & "/Cargo.toml", imageBridgeTarget & "/Cargo.toml")
  cpFile(imageBridgeSource & "/Cargo.lock", imageBridgeTarget & "/Cargo.lock")
  cpDir(imageBridgeSource & "/include", imageBridgeTarget & "/include")
  cpDir(imageBridgeSource & "/src", imageBridgeTarget & "/src")

task test, "Run the test suite":
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim c -r --mm:arc --nimcache:/tmp/clay_box_style_system_test_runner_nimcache --out:/tmp/clay_box_style_system_test_runner tools/run_tests.nim"

task checkExamples, "Type-check every example in each supported link configuration":
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_check_paint examples/paint_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_check_render examples/render_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_check_sdl3 -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/sdl3_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_check_sdl3_system -d:cbssSdl3LinkMode=system examples/sdl3_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_check_sdl3_custom -d:cbssSdl3LinkMode=custom -d:cbssRuntimeRoot=vendor/sdl3 examples/sdl3_demo.nim"

task buildCAbiShared, "Build the shared CBSS C ABI library":
  exec "nim c --app:lib --mm:arc -d:release --path:src --nimcache:/tmp/clay_box_style_system_c_api_shared_nimcache --out:/tmp/libcbss.so src/cbss_c_api.nim"

task buildCAbiStatic, "Build the static CBSS C ABI library":
  exec "nim c --app:staticlib --mm:arc -d:release --path:src --nimcache:/tmp/clay_box_style_system_c_api_static_nimcache --out:/tmp/libcbss.a src/cbss_c_api.nim"

task testCAbi, "Build and exercise the shared and static C ABI from C":
  exec "nim c --app:lib --mm:arc -d:release --path:src --nimcache:/tmp/clay_box_style_system_c_api_shared_nimcache --out:/tmp/libcbss.so src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/c_consumer.c -L/tmp -Wl,-rpath,/tmp -lcbss -lm -o /tmp/clay_box_style_system_c_consumer_shared"
  exec "/tmp/clay_box_style_system_c_consumer_shared"
  exec "nim c --app:staticlib --mm:arc -d:release --path:src --nimcache:/tmp/clay_box_style_system_c_api_static_nimcache --out:/tmp/libcbss.a src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/c_consumer.c /tmp/libcbss.a -lm -lpthread -ldl -o /tmp/clay_box_style_system_c_consumer_static"
  exec "/tmp/clay_box_style_system_c_consumer_static"

task setupBundled, "Use the repository development runtime for static SDL3 linking":
  exec "nim c -r --mm:arc --nimcache:/tmp/clay_box_style_system_setup_nimcache --out:/tmp/cbss_configure src/cbss_configure.nim bundled vendor/sdl3 ."

task setupSystem, "Dynamically link SDL3 and the image bridge from the system":
  exec "nim c -r --mm:arc --nimcache:/tmp/clay_box_style_system_setup_nimcache --out:/tmp/cbss_configure src/cbss_configure.nim system ."

task bench, "Run compiled pipeline benchmarks (not part of the product build)":
  exec "nim c -r -d:release --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_bench_nimcache --out:/tmp/clay_box_style_system_pipeline_benchmark tests/perf/pipeline_benchmark.nim"
  exec "nim c -r -d:release --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_dirty_bench_nimcache --out:/tmp/clay_box_style_system_dirty_subtree_benchmark tests/perf/dirty_subtree_benchmark.nim"

task demo, "Run the paint command demo":
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_nimcache --out:/tmp/clay_box_style_system_paint_demo examples/paint_demo.nim"

task renderDemo, "Render the demo to a PPM image":
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_nimcache --out:/tmp/clay_box_style_system_render_demo examples/render_demo.nim"

task buildSdl3Demo, "Build the SDL3 demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim c --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_sdl3_nimcache --out:/tmp/clay_box_style_system_sdl3_demo examples/sdl3_demo.nim"

task sdl3Demo, "Run the SDL3 demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_sdl3_nimcache --out:/tmp/clay_box_style_system_sdl3_demo examples/sdl3_demo.nim"

task buildCosmicTextBridge, "Build the Rust cosmic-text C ABI bridge":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"

task testCosmicTextBridge, "Run the cosmic-text bridge integration test":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_cosmic_text_nimcache --out:/tmp/clay_box_style_system_cosmic_text_test tests/text/test_cosmic_text_engine.nim"

task buildImageBridge, "Build the image-decoding C ABI bridge":
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"

task testImageBridge, "Run the image-decoding C ABI bridge tests":
  exec "cargo test --locked --release --manifest-path native/image_bridge/Cargo.toml"

task testSdl3Wayland, "Run the optional SDL3 Wayland real-window smoke test":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env CBSS_RUN_WAYLAND_E2E=1 LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_sdl3_wayland_nimcache --out:/tmp/clay_box_style_system_sdl3_wayland_smoke tests/integration/test_sdl3_wayland_smoke.nim"

task testSdl3LargePasteWayland, "Run the optional SDL3 Wayland large-paste regression test":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env CBSS_RUN_WAYLAND_E2E=1 LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_box_style_system_sdl3_large_paste_nimcache --out:/tmp/clay_box_style_system_sdl3_large_paste tests/integration/test_sdl3_large_paste.nim"
