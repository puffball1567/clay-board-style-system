version       = "0.3.2"
author        = "Clay Board Style System contributors"
description   = "A CSS-inspired primitive engine for native GUI toolkits"
license       = "Apache-2.0"
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
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_property_support_nimcache --out:/tmp/clay_board_style_system_property_support tools/check_property_support.nim"
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_event_generator_nimcache --out:/tmp/clay_board_style_system_event_generator tools/generate_events.nim --check"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim c -r --mm:arc --nimcache:/tmp/clay_board_style_system_test_runner_nimcache --out:/tmp/clay_board_style_system_test_runner tools/run_tests.nim"

task checkGeneratedEvents, "Verify generated Nim and C event surfaces":
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_event_generator_nimcache --out:/tmp/clay_board_style_system_event_generator tools/generate_events.nim --check"

task checkPropertySupport, "Verify CSS property support counts and registry coverage":
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_property_support_nimcache --out:/tmp/clay_board_style_system_property_support tools/check_property_support.nim"

task checkExplicitEventOutcomes, "Reject implicit boolean outcomes in first-party event handlers":
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_public src/clay_board_style_system.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_paint examples/paint_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_render examples/render_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_component examples/component_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_sdl3 -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/sdl3_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_navigation -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/navigation_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_v03_canvas -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/v03_canvas_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_loading_indicator -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/loading_indicator_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_door_button -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/door_button_canvas_demo.nim"
  exec "nim check --mm:arc -d:cbssStrictEventOutcomes --path:src --nimcache:/tmp/clay_board_style_system_strict_events_widget_lifecycle tests/memory/widget_lifecycle.nim"

task testOrc, "Run the test suite under ORC":
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim c -r --mm:orc --nimcache:/tmp/clay_board_style_system_orc_test_runner_nimcache --out:/tmp/clay_board_style_system_orc_test_runner tools/run_tests.nim --memory:orc"

task testMotionAsan, "Run declarative transition and keyframe tests under AddressSanitizer":
  let sanitizerRoot = thisDir() & "/nimcache"
  for memoryModel in ["arc", "orc"]:
    for testName in ["declarative_transition", "declarative_keyframes"]:
      let suffix = testName & "_" & memoryModel & "_asan"
      let nimcache = sanitizerRoot & "/clay_board_style_system_" & suffix & "_nimcache"
      let artifact = nimcache & "/clay_board_style_system_" & suffix
      let source = "tests/runtime/test_" & testName & ".nim"
      exec "nim c --forceBuild:on --cc:clang --mm:" & memoryModel & " -d:release -d:useMalloc --debugger:native --path:src --passC:-fsanitize=address --passC:-fno-omit-frame-pointer --passL:-fsanitize=address --nimcache:\"" & nimcache & "\" --out:\"" & artifact & "\" " & source
      when defined(windows):
        exec "\"" & artifact & ".exe\""
      elif defined(linux):
        exec "env ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:abort_on_error=1 \"" & artifact & "\""
      else:
        exec "env ASAN_OPTIONS=halt_on_error=1:abort_on_error=1 \"" & artifact & "\""

task testUbsan, "Run numeric, layout, transform, and motion tests under UndefinedBehaviorSanitizer":
  let sanitizerRoot = thisDir() & "/nimcache"
  let clangExe = getEnv("CBSS_CLANG", "clang")
  for memoryModel in ["arc", "orc"]:
    for test in [
      ("color_conversion", "tests/core/test_color_conversion.nim"),
      ("flex", "tests/layout/test_flex.nim"),
      ("transform_geometry", "tests/layout/test_transform_geometry.nim"),
      ("declarative_transition", "tests/runtime/test_declarative_transition.nim"),
      ("declarative_keyframes", "tests/runtime/test_declarative_keyframes.nim")
    ]:
      let testName = test[0]
      let testPath = test[1]
      let suffix = testName & "_" & memoryModel & "_ubsan"
      let nimcache = sanitizerRoot & "/clay_board_style_system_" & suffix & "_nimcache"
      let artifact = nimcache & "/clay_board_style_system_" & suffix
      exec "nim c --forceBuild:on --cc:clang --clang.exe:" & clangExe & " --mm:" & memoryModel & " -d:release -d:useMalloc --debugger:native --path:src --passC:-fsanitize=undefined --passC:-fno-sanitize-recover=all --passC:-fno-omit-frame-pointer --passL:-fsanitize=undefined --nimcache:\"" & nimcache & "\" --out:\"" & artifact & "\" " & testPath
      when defined(windows):
        exec "\"" & artifact & ".exe\""
      else:
        exec "env UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \"" & artifact & "\""

task testLsan, "Run retained lifecycle tests under LeakSanitizer on Linux":
  when defined(linux):
    let sanitizerRoot = thisDir() & "/nimcache"
    let clangExe = getEnv("CBSS_CLANG", "clang")
    for memoryModel in ["arc", "orc"]:
      for test in [
        ("widget_lifecycle", "tests/memory/widget_lifecycle.nim"),
        ("event_lifecycle", "tests/memory/event_lifecycle.nim"),
        ("declarative_transition", "tests/runtime/test_declarative_transition.nim"),
        ("declarative_keyframes", "tests/runtime/test_declarative_keyframes.nim")
      ]:
        let testName = test[0]
        let testPath = test[1]
        let suffix = testName & "_" & memoryModel & "_lsan"
        let nimcache = sanitizerRoot & "/clay_board_style_system_" & suffix & "_nimcache"
        let artifact = nimcache & "/clay_board_style_system_" & suffix
        exec "nim c --forceBuild:on --cc:clang --clang.exe:" & clangExe & " --mm:" & memoryModel & " -d:release -d:useMalloc --debugger:native --path:src --passC:-fsanitize=leak --passC:-fno-omit-frame-pointer --passL:-fsanitize=leak --nimcache:\"" & nimcache & "\" --out:\"" & artifact & "\" " & testPath
        exec "env LSAN_OPTIONS=exitcode=99 \"" & artifact & "\""
  else:
    echo "Standalone LeakSanitizer is verified only in the Linux CI lane."

task testTsan, "Run worker-to-UI ownership races under ThreadSanitizer":
  when defined(linux) or defined(macosx):
    let sanitizerRoot = thisDir() & "/nimcache"
    let clangExe = getEnv("CBSS_CLANG", "clang")
    for memoryModel in ["arc", "orc"]:
      let suffix = "stream_mailbox_threaded_" & memoryModel & "_tsan"
      let nimcache = sanitizerRoot & "/clay_board_style_system_" & suffix & "_nimcache"
      let artifact = nimcache & "/clay_board_style_system_" & suffix
      let source = "tests/data/test_stream_mailbox_threaded.nim"
      exec "nim c --forceBuild:on --cc:clang --clang.exe:" & clangExe & " --threads:on --mm:" & memoryModel & " -d:release -d:useMalloc --debugger:native --path:src --passC:-fsanitize=thread --passC:-fno-omit-frame-pointer --passL:-fsanitize=thread --nimcache:\"" & nimcache & "\" --out:\"" & artifact & "\" " & source
      exec "env TSAN_OPTIONS=halt_on_error=1:second_deadlock_stack=1 \"" & artifact & "\""
  else:
    echo "ThreadSanitizer is not supported by LLVM Clang on this platform."

task checkExamples, "Type-check every example in each supported link configuration":
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_paint examples/paint_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_render examples/render_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_component examples/component_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_sdl3 -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/sdl3_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_sdl3_system -d:cbssSdl3LinkMode=system examples/sdl3_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_sdl3_custom -d:cbssSdl3LinkMode=custom -d:cbssRuntimeRoot=vendor/sdl3 examples/sdl3_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_navigation -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/navigation_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_navigation_system -d:cbssSdl3LinkMode=system examples/navigation_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_navigation_custom -d:cbssSdl3LinkMode=custom -d:cbssRuntimeRoot=vendor/sdl3 examples/navigation_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_v03_canvas -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/v03_canvas_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_v03_canvas_system -d:cbssSdl3LinkMode=system examples/v03_canvas_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_v03_canvas_custom -d:cbssSdl3LinkMode=custom -d:cbssRuntimeRoot=vendor/sdl3 examples/v03_canvas_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_loading_indicator -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/loading_indicator_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_loading_indicator_system -d:cbssSdl3LinkMode=system examples/loading_indicator_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_loading_indicator_custom -d:cbssSdl3LinkMode=custom -d:cbssRuntimeRoot=vendor/sdl3 examples/loading_indicator_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_door_button_canvas -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/door_button_canvas_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_door_button_canvas_system -d:cbssSdl3LinkMode=system examples/door_button_canvas_demo.nim"
  exec "nim check --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_check_door_button_canvas_custom -d:cbssSdl3LinkMode=custom -d:cbssRuntimeRoot=vendor/sdl3 examples/door_button_canvas_demo.nim"

task checkExamplesOrc, "Type-check public examples under ORC":
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_public src/clay_board_style_system.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_paint examples/paint_demo.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_render examples/render_demo.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_component examples/component_demo.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_sdl3 -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/sdl3_demo.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_navigation -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/navigation_demo.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_v03_canvas -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/v03_canvas_demo.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_loading_indicator -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/loading_indicator_demo.nim"
  exec "nim check --mm:orc --path:src --nimcache:/tmp/clay_board_style_system_orc_check_door_button_canvas -d:cbssSdl3LinkMode=bundled -d:cbssRuntimeRoot=vendor/sdl3 examples/door_button_canvas_demo.nim"

task buildCAbiShared, "Build the shared CBSS C ABI library":
  exec "nim c --threads:on --app:lib --mm:arc -d:release --path:src --nimcache:/tmp/clay_board_style_system_c_api_shared_nimcache --out:/tmp/libcbss.so src/cbss_c_api.nim"

task buildCAbiStatic, "Build the static CBSS C ABI library":
  exec "nim c --threads:on --app:staticlib --mm:arc -d:release --path:src --nimcache:/tmp/clay_board_style_system_c_api_static_nimcache --out:/tmp/libcbss.a src/cbss_c_api.nim"

task testCAbi, "Build and exercise the shared and static C ABI from C":
  exec "nim c --threads:on --app:lib --mm:arc -d:release --path:src --nimcache:/tmp/clay_board_style_system_c_api_shared_nimcache --out:/tmp/libcbss.so src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude -fsyntax-only tests/c_api/header_consumer.c"
  exec "c++ -std=c++14 -Wall -Wextra -Werror -Iinclude -fsyntax-only tests/c_api/header_consumer.cpp"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/c_consumer.c -L/tmp -Wl,-rpath,/tmp -lcbss -lm -o /tmp/clay_board_style_system_c_consumer_shared"
  exec "/tmp/clay_board_style_system_c_consumer_shared"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/stream_consumer.c -L/tmp -Wl,-rpath,/tmp -lcbss -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_stream_consumer_shared"
  exec "/tmp/clay_board_style_system_c_stream_consumer_shared"
  exec "nim c --threads:on --app:staticlib --mm:arc -d:release --path:src --nimcache:/tmp/clay_board_style_system_c_api_static_nimcache --out:/tmp/libcbss.a src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/c_consumer.c /tmp/libcbss.a -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_consumer_static"
  exec "/tmp/clay_board_style_system_c_consumer_static"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/stream_consumer.c /tmp/libcbss.a -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_stream_consumer_static"
  exec "/tmp/clay_board_style_system_c_stream_consumer_static"

task testCAbiOrc, "Exercise cross-thread C ABI streams under ORC":
  exec "nim c --threads:on --app:lib --mm:orc -d:release --path:src --nimcache:/tmp/clay_board_style_system_c_api_orc_shared_nimcache --out:/tmp/libcbss_orc.so src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/stream_consumer.c -L/tmp -Wl,-rpath,/tmp -l:libcbss_orc.so -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_stream_consumer_orc_shared"
  exec "/tmp/clay_board_style_system_c_stream_consumer_orc_shared"
  exec "nim c --threads:on --app:staticlib --mm:orc -d:release --path:src --nimcache:/tmp/clay_board_style_system_c_api_orc_static_nimcache --out:/tmp/libcbss_orc.a src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/stream_consumer.c /tmp/libcbss_orc.a -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_stream_consumer_orc_static"
  exec "/tmp/clay_board_style_system_c_stream_consumer_orc_static"

task testCAbiValgrind, "Run shared and static C ABI consumers under Valgrind":
  exec "nim c --threads:on --app:lib --mm:arc -d:release -d:useMalloc --path:src --nimcache:/tmp/clay_board_style_system_c_api_valgrind_shared_nimcache --out:/tmp/libcbss.so src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/c_consumer.c -L/tmp -Wl,-rpath,/tmp -lcbss -lm -o /tmp/clay_board_style_system_c_consumer_shared"
  exec "valgrind --vgdb=no --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/clay_board_style_system_c_consumer_shared"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/stream_consumer.c -L/tmp -Wl,-rpath,/tmp -lcbss -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_stream_consumer_shared"
  exec "valgrind --vgdb=no --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/clay_board_style_system_c_stream_consumer_shared"
  exec "nim c --threads:on --app:staticlib --mm:arc -d:release -d:useMalloc --path:src --nimcache:/tmp/clay_board_style_system_c_api_valgrind_static_nimcache --out:/tmp/libcbss.a src/cbss_c_api.nim"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/c_consumer.c /tmp/libcbss.a -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_consumer_static"
  exec "valgrind --vgdb=no --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/clay_board_style_system_c_consumer_static"
  exec "cc -std=c11 -Wall -Wextra -Werror -Iinclude tests/c_api/stream_consumer.c /tmp/libcbss.a -lm -lpthread -ldl -o /tmp/clay_board_style_system_c_stream_consumer_static"
  exec "valgrind --vgdb=no --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/clay_board_style_system_c_stream_consumer_static"

task testWidgetLifecycleValgrind, "Run ARC widget lifecycle checks under Valgrind":
  exec "nim c --mm:arc -d:release -d:useMalloc --path:src --nimcache:/tmp/clay_board_style_system_widget_lifecycle_nimcache --out:/tmp/clay_board_style_system_widget_lifecycle tests/memory/widget_lifecycle.nim"
  exec "valgrind --vgdb=no --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/clay_board_style_system_widget_lifecycle"

task testEventLifecycleValgrind, "Run ARC event lifecycle checks under Valgrind":
  exec "nim c --mm:arc -d:release -d:useMalloc --path:src --nimcache:/tmp/clay_board_style_system_event_lifecycle_nimcache --out:/tmp/clay_board_style_system_event_lifecycle tests/memory/event_lifecycle.nim"
  exec "valgrind --vgdb=no --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/clay_board_style_system_event_lifecycle"

task testStreamMailboxValgrind, "Run the threaded ARC stream mailbox under Valgrind":
  exec "nim c --threads:on --mm:arc -d:release -d:useMalloc --path:src --nimcache:/tmp/clay_board_style_system_stream_mailbox_nimcache --out:/tmp/clay_board_style_system_stream_mailbox tests/data/test_stream_mailbox_threaded.nim"
  exec "valgrind --vgdb=no --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=99 /tmp/clay_board_style_system_stream_mailbox"

task setupBundled, "Use the repository development runtime for static SDL3 linking":
  exec "nim c -r --mm:arc --nimcache:/tmp/clay_board_style_system_setup_nimcache --out:/tmp/cbss_configure src/cbss_configure.nim bundled vendor/sdl3 ."

task setupSystem, "Dynamically link SDL3 and the image bridge from the system":
  exec "nim c -r --mm:arc --nimcache:/tmp/clay_board_style_system_setup_nimcache --out:/tmp/cbss_configure src/cbss_configure.nim system ."

task bench, "Run compiled pipeline benchmarks (not part of the product build)":
  exec "nim c -r -d:release --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_color_bench_nimcache --out:/tmp/clay_board_style_system_color_conversion_benchmark tests/perf/color_conversion_benchmark.nim"
  exec "nim c -r -d:release --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_bench_nimcache --out:/tmp/clay_board_style_system_pipeline_benchmark tests/perf/pipeline_benchmark.nim"
  exec "nim c -r -d:release --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_dirty_bench_nimcache --out:/tmp/clay_board_style_system_dirty_subtree_benchmark tests/perf/dirty_subtree_benchmark.nim"
  exec "nim c -r -d:release --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_navigation_bench_nimcache --out:/tmp/clay_board_style_system_navigation_screen_host_benchmark tests/perf/navigation_screen_host_benchmark.nim"
  exec "nim c -r -d:release --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_render_surface_bench_nimcache --out:/tmp/clay_board_style_system_render_surface_benchmark tests/perf/render_surface_benchmark.nim"

task demo, "Run the paint command demo":
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_nimcache --out:/tmp/clay_board_style_system_paint_demo examples/paint_demo.nim"

task renderDemo, "Render the demo to a PPM image":
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_nimcache --out:/tmp/clay_board_style_system_render_demo examples/render_demo.nim"

task componentDemo, "Run the typed component authoring demo":
  exec "nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_component_demo_nimcache --out:/tmp/clay_board_style_system_component_demo examples/component_demo.nim"

task buildSdl3Demo, "Build the SDL3 demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "nim c --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_sdl3_nimcache --out:/tmp/clay_board_style_system_sdl3_demo examples/sdl3_demo.nim"

task sdl3Demo, "Run the SDL3 demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_sdl3_nimcache --out:/tmp/clay_board_style_system_sdl3_demo examples/sdl3_demo.nim"

task navigationDemo, "Run the Version 0.2 native navigation demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_navigation_demo_nimcache --out:/tmp/clay_board_style_system_navigation_demo examples/navigation_demo.nim"

task v03CanvasDemo, "Run the Version 0.3 Canvas and color demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_v03_canvas_demo_nimcache --out:/tmp/clay_board_style_system_v03_canvas_demo examples/v03_canvas_demo.nim"

task loadingIndicatorDemo, "Run the Canvas loading indicator demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_loading_indicator_demo_nimcache --out:/tmp/clay_board_style_system_loading_indicator_demo examples/loading_indicator_demo.nim"

task doorButtonCanvasDemo, "Run the font-relative Canvas door button demo":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_door_button_canvas_demo_nimcache --out:/tmp/clay_board_style_system_door_button_canvas_demo examples/door_button_canvas_demo.nim"

task buildCosmicTextBridge, "Build the Rust cosmic-text C ABI bridge":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"

task testCosmicTextBridge, "Run the cosmic-text bridge integration test":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "env LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_cosmic_text_nimcache --out:/tmp/clay_board_style_system_cosmic_text_test tests/text/test_cosmic_text_engine.nim"

task buildImageBridge, "Build the image-decoding C ABI bridge":
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"

task testImageBridge, "Run the image-decoding C ABI bridge tests":
  exec "cargo test --locked --release --manifest-path native/image_bridge/Cargo.toml"

task testSdl3Wayland, "Run the optional SDL3 Wayland real-window smoke test":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env CBSS_RUN_WAYLAND_E2E=1 LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_sdl3_wayland_nimcache --out:/tmp/clay_board_style_system_sdl3_wayland_smoke tests/integration/test_sdl3_wayland_smoke.nim"

task testSdl3LargePasteWayland, "Run the optional SDL3 Wayland large-paste regression test":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env CBSS_RUN_WAYLAND_E2E=1 LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_sdl3_large_paste_nimcache --out:/tmp/clay_board_style_system_sdl3_large_paste tests/integration/test_sdl3_large_paste.nim"

task testSdl3NavigationWayland, "Run the optional SDL3 Wayland navigation scenario":
  exec "cargo build --locked --release --manifest-path native/cosmic_text_bridge/Cargo.toml"
  exec "cargo build --locked --release --manifest-path native/image_bridge/Cargo.toml"
  exec "env CBSS_RUN_WAYLAND_E2E=1 LD_LIBRARY_PATH=native/cosmic_text_bridge/target/release:native/image_bridge/target/release nim c -r --mm:arc --path:src --nimcache:/tmp/clay_board_style_system_sdl3_navigation_nimcache --out:/tmp/clay_board_style_system_sdl3_navigation tests/integration/test_sdl3_navigation.nim"
