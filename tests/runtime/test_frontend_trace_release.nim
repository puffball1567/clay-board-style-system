when defined(release) or defined(cbssFrontendTrace):
  import clay_board_style_system/frontend_runtime

  when defined(release) and not defined(cbssFrontendTrace):
    static:
      doAssert not compiles(initFrontendTrace())
      doAssert not compiles(initCueRuntime().enableTrace())
  elif defined(cbssFrontendTrace):
    static:
      doAssert compiles(initFrontendTrace())
      doAssert compiles(initCueRuntime().enableTrace())
