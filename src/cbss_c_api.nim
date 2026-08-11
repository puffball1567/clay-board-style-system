{.warning[UnusedImport]: off.}

when compileOption("threads"):
  import clay_board_style_system/c_api
else:
  {.error: "CBSS C ABI requires --threads:on for cross-thread stream producers".}
