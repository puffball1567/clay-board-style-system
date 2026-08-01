import std/[options, unittest]

import clay_board_style_system

type LinkScreen = enum
  lsHome,
  lsSettings,
  lsAccount

suite "platform URL and deep-link contracts":
  test "URL policy normalizes schemes and rejects invalid configuration":
    let policy = platformUrlPolicy(["HTTPS", "my-app", "https"], 128)
    check policy.allowedSchemes == @["https", "my-app"]
    check policy.maxLength == 128

    expect ValueError:
      discard platformUrlPolicy([], 128)
    expect ValueError:
      discard platformUrlPolicy(["https"], 0)
    expect ValueError:
      discard platformUrlPolicy(["1invalid"], 128)
    expect ValueError:
      discard platformUrlPolicy(["bad_scheme"], 128)

  test "URL validation rejects unsafe ambiguous and disallowed input":
    let policy = platformUrlPolicy(["https", "my-app"], 32)

    check validatePlatformUrl("", policy) == puvEmpty
    check validatePlatformUrl("relative/path", policy) == puvMissingScheme
    check validatePlatformUrl("1app://settings", policy) == puvMissingScheme
    check validatePlatformUrl("ftp://example.test", policy) == puvSchemeNotAllowed
    check validatePlatformUrl("https://example.test\nattack", policy) == puvUnsafeText
    check validatePlatformUrl("https://example.test/this-is-too-long", policy) == puvTooLong
    check validatePlatformUrl("HTTPS://example.test", policy) == puvValid
    check validatePlatformUrl("my-app://settings", policy) == puvValid

  test "external URL adapter is not called for rejected input":
    var opened: seq[string]
    let adapter = externalUrlAdapter(proc(url: string): bool =
      opened.add url
      true
    )

    let rejected = adapter.openExternalUrl("file:///etc/passwd")
    check rejected.status == euosRejected
    check rejected.validation == puvSchemeNotAllowed
    check opened.len == 0

    let accepted = adapter.openExternalUrl("https://example.test/docs")
    check accepted.status == euosOpened
    check accepted.validation == puvValid
    check opened == @["https://example.test/docs"]

  test "external URL adapter reports platform failure without widening policy":
    let adapter = externalUrlAdapter(proc(url: string): bool = false)
    let customPolicy = platformUrlPolicy(["mailto"])

    check adapter.openExternalUrl("mailto:team@example.test").status == euosRejected
    let failed = adapter.openExternalUrl(
      "mailto:team@example.test",
      customPolicy
    )
    check failed.status == euosFailed
    check failed.validation == puvValid

    let missing = ExternalUrlAdapter().openExternalUrl("https://example.test")
    check missing.status == euosFailed
    expect ValueError:
      discard externalUrlAdapter(nil)

  test "deep-link codec validates before invoking application decoding":
    var decodeCalls = 0
    let codec = deepLinkCodec[LinkScreen](
      ["cbss-demo"],
      proc(url: string): Option[LinkScreen] =
        inc decodeCalls
        case url
        of "cbss-demo://settings": some(lsSettings)
        of "cbss-demo://account": some(lsAccount)
        else: none(LinkScreen)
    )

    let rejected = codec.decodeDeepLink("https://example.test/settings")
    check rejected.status == dlsRejected
    check rejected.validation == puvSchemeNotAllowed
    check rejected.destination.isNone
    check decodeCalls == 0

    let unmatched = codec.decodeDeepLink("cbss-demo://unknown")
    check unmatched.status == dlsUnmatched
    check unmatched.validation == puvValid
    check unmatched.destination.isNone
    check decodeCalls == 1

    let matched = codec.decodeDeepLink("cbss-demo://settings")
    check matched.status == dlsNavigated
    check matched.destination == some(lsSettings)
    check decodeCalls == 2

  test "deep-link encoding is optional and rejects invalid codec output":
    let decodeOnly = deepLinkCodec[LinkScreen](
      ["cbss-demo"],
      proc(url: string): Option[LinkScreen] = none(LinkScreen)
    )
    check decodeOnly.encodeDeepLink(lsHome).isNone

    let codec = deepLinkCodec[LinkScreen](
      ["cbss-demo"],
      proc(url: string): Option[LinkScreen] = none(LinkScreen),
      proc(destination: LinkScreen): Option[string] =
        case destination
        of lsHome: some("cbss-demo://home")
        of lsSettings: some("https://example.test/settings")
        of lsAccount: some("cbss-demo://account with-space")
    )
    check codec.encodeDeepLink(lsHome) == some("cbss-demo://home")
    check codec.encodeDeepLink(lsSettings).isNone
    check codec.encodeDeepLink(lsAccount).isNone

  test "decoded links push or replace typed navigator entries":
    let codec = deepLinkCodec[LinkScreen](
      ["cbss-demo"],
      proc(url: string): Option[LinkScreen] =
        case url
        of "cbss-demo://settings": some(lsSettings)
        of "cbss-demo://account": some(lsAccount)
        else: none(LinkScreen)
    )
    let navigator = initStackNavigator(lsHome)

    let pushed = navigator.navigateDeepLink(codec, "cbss-demo://settings")
    check pushed.status == dlsNavigated
    check pushed.destination == some(lsSettings)
    check navigator.currentDestination() == some(lsSettings)
    check navigator.snapshot().entries.len == 2

    let replaced = navigator.navigateDeepLink(
      codec,
      "cbss-demo://account",
      dlnReplace
    )
    check replaced.status == dlsNavigated
    check navigator.currentDestination() == some(lsAccount)
    check navigator.snapshot().entries.len == 2

    let unmatched = navigator.navigateDeepLink(codec, "cbss-demo://missing")
    check unmatched.status == dlsUnmatched
    check navigator.currentDestination() == some(lsAccount)

  test "deep-link navigation reports a driver that declines valid input":
    proc snapshot(): NavigationSnapshot[LinkScreen] =
      NavigationSnapshot[LinkScreen](entries: @[], currentIndex: -1)
    proc noDestination(
        destination: LinkScreen
    ): Option[NavigationChange[LinkScreen]] =
      none(NavigationChange[LinkScreen])
    proc noStep(): Option[NavigationChange[LinkScreen]] =
      none(NavigationChange[LinkScreen])
    let navigator = initNavigator(NavigationDriver[LinkScreen](
      snapshot: snapshot,
      push: noDestination,
      replace: noDestination,
      back: noStep,
      forward: noStep
    ))
    let codec = deepLinkCodec[LinkScreen](
      ["cbss-demo"],
      proc(url: string): Option[LinkScreen] = some(lsSettings)
    )

    let result = navigator.navigateDeepLink(codec, "cbss-demo://settings")
    check result.status == dlsNavigationDeclined
    check result.destination == some(lsSettings)

  test "deep-link construction rejects a missing decoder":
    expect ValueError:
      discard deepLinkCodec[LinkScreen](["cbss-demo"], nil)

  test "command-line source drains launch links exactly once in order":
    let navigator = initStackNavigator(lsHome)
    let codec = deepLinkCodec[LinkScreen](
      ["cbss-demo"],
      proc(url: string): Option[LinkScreen] =
        case url
        of "cbss-demo://settings": some(lsSettings)
        of "cbss-demo://account": some(lsAccount)
        else: none(LinkScreen)
    )
    let source = commandLineDeepLinkAdapter([
      "--ordinary-option",
      "cbss-demo://settings",
      "cbss-demo://account"
    ])

    let first = source.drainDeepLinks(navigator, codec)
    check first.len == 3
    check first[0].status == dlsRejected
    check first[1].status == dlsNavigated
    check first[2].status == dlsNavigated
    check navigator.currentDestination() == some(lsAccount)
    check source.drainDeepLinks(navigator, codec).len == 0

  test "custom source adapters support deferred platform delivery":
    var pending = @["cbss-demo://settings"]
    let source = deepLinkSourceAdapter(proc(): seq[string] =
      result = pending
      pending.setLen(0)
    )
    let navigator = initStackNavigator(lsHome)
    let codec = deepLinkCodec[LinkScreen](
      ["cbss-demo"],
      proc(url: string): Option[LinkScreen] = some(lsSettings)
    )

    let drained = source.drainDeepLinks(navigator, codec, dlnReplace)
    check drained.len == 1
    check drained[0].status == dlsNavigated
    check navigator.currentDestination() == some(lsSettings)
    check navigator.snapshot().entries.len == 1

    expect ValueError:
      discard deepLinkSourceAdapter(nil)
    let missing = DeepLinkSourceAdapter()
    check missing.drainDeepLinks(navigator, codec).len == 0
