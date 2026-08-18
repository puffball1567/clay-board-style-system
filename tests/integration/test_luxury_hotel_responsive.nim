import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/testing/test_driver
import ../../examples/luxury_hotel_demo

proc responsiveHotel(viewport: Size): CbssTestDriver =
  let ui = initUiRoot()
  let nodes = ui.buildLuxuryHotelDemo()
  ui.applyLuxuryHotelLayout(nodes, viewport)
  initCbssTestDriver(ui, viewport)

proc contains(outerRect, innerRect: Rect; tolerance = 0.5'f32): bool =
  innerRect.x >= outerRect.x - tolerance and
    innerRect.y >= outerRect.y - tolerance and
    innerRect.x + innerRect.w <= outerRect.x + outerRect.w + tolerance and
    innerRect.y + innerRect.h <= outerRect.y + outerRect.h + tolerance

suite "luxury hotel responsive layout":
  test "desktop keeps the primary and supporting columns side by side":
    let driver = responsiveHotel(size(1200, 760))
    let main = driver.rectFor(byId("hotel-main"))
    let primary = driver.rectFor(byId("hotel-primary"))
    let aside = driver.rectFor(byId("hotel-aside"))
    let reservation = driver.rectFor(byId("hotel-reservation"))
    let evening = driver.rectFor(byId("hotel-evening"))

    check main.isSome
    check primary.isSome
    check aside.isSome
    check reservation.isSome
    check evening.isSome
    check primary.get.x + primary.get.w < aside.get.x
    check reservation.get.x + reservation.get.w < evening.get.x
    check main.get.contains(primary.get)
    check main.get.contains(aside.get)

  test "compact layout removes the secondary evening card without leaving a gap":
    let driver = responsiveHotel(size(900, 760))
    let main = driver.rectFor(byId("hotel-main"))
    let primary = driver.rectFor(byId("hotel-primary"))
    let aside = driver.rectFor(byId("hotel-aside"))
    let reservation = driver.rectFor(byId("hotel-reservation"))
    let evening = driver.rectFor(byId("hotel-evening"))

    check main.isSome
    check primary.isSome
    check aside.isSome
    check reservation.isSome
    check evening.isNone
    check primary.get.x + primary.get.w < aside.get.x
    check abs(reservation.get.w - primary.get.w) <= 0.5'f32
    check main.get.contains(primary.get)
    check main.get.contains(aside.get)

  test "mobile stacks the concierge after the primary content":
    let driver = responsiveHotel(size(480, 760))
    let main = driver.rectFor(byId("hotel-main"))
    let primary = driver.rectFor(byId("hotel-primary"))
    let aside = driver.rectFor(byId("hotel-aside"))
    let hero = driver.rectFor(byId("hotel-hero"))
    let reservation = driver.rectFor(byId("hotel-reservation"))
    let concierge = driver.rectFor(byId("hotel-concierge"))

    check main.isSome
    check primary.isSome
    check aside.isSome
    check hero.isSome
    check reservation.isSome
    check concierge.isSome
    check aside.get.y >= primary.get.y + primary.get.h
    check abs(primary.get.w - main.get.w) <= 0.5'f32
    check abs(aside.get.w - main.get.w) <= 0.5'f32
    check primary.get.contains(hero.get)
    check primary.get.contains(reservation.get)
    check aside.get.contains(concierge.get)
    check main.get.contains(primary.get)
    check main.get.contains(aside.get)
