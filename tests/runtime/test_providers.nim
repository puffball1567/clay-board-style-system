import std/unittest

import clay_board_style_system

suite "view context providers":
  type
    ThemeState = object
      density: float32

    RouteState = object
      screen: string

    AppStore = ref object
      saves: int

  test "ViewContext stores and retrieves multiple provider types":
    let ctx = initViewContext(providers([
      provide(ThemeState(density: 1.25)),
      provide(RouteState(screen: "home"))
    ]))

    check ctx.has(ThemeState)
    check ctx.has(RouteState)
    check ctx.use(ThemeState).density == 1.25'f32
    check ctx.use(RouteState).screen == "home"

  test "providers can carry mutable application-owned refs":
    let store = AppStore(saves: 0)
    let ctx = initViewContext(providers([
      provide(store)
    ]))

    let shared = ctx.use(AppStore)
    inc shared.saves

    check store.saves == 1

  test "addProvider replaces the same provider type":
    var ctx = initViewContext(providers([
      provide(ThemeState(density: 1.0))
    ]))

    ctx.addProvider(provide(ThemeState(density: 1.5)))

    check ctx.providers.len == 1
    check ctx.use(ThemeState).density == 1.5'f32
