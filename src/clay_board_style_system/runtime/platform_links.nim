import std/[options, os, strutils, uri]

import ./navigation

const defaultPlatformUrlMaxLength* = 8 * 1024

type
  PlatformUrlValidation* = enum
    puvValid,
    puvEmpty,
    puvTooLong,
    puvUnsafeText,
    puvMissingScheme,
    puvSchemeNotAllowed

  PlatformUrlPolicy* = object
    allowedSchemes*: seq[string]
    maxLength*: int

  ExternalUrlOpenProc* = proc(url: string): bool {.closure.}

  ExternalUrlAdapter* = object
    open*: ExternalUrlOpenProc

  ExternalUrlOpenStatus* = enum
    euosOpened,
    euosRejected,
    euosFailed

  ExternalUrlOpenResult* = object
    status*: ExternalUrlOpenStatus
    validation*: PlatformUrlValidation

  DeepLinkDecodeProc*[Destination] =
    proc(url: string): Option[Destination] {.closure.}
  DeepLinkEncodeProc*[Destination] =
    proc(destination: Destination): Option[string] {.closure.}

  DeepLinkCodec*[Destination] = object
    policy*: PlatformUrlPolicy
    decode*: DeepLinkDecodeProc[Destination]
    encode*: DeepLinkEncodeProc[Destination]

  DeepLinkSourceProc* = proc(): seq[string] {.closure.}

  DeepLinkSourceAdapter* = object
    takePending*: DeepLinkSourceProc

  DeepLinkNavigationMode* = enum
    dlnPush,
    dlnReplace

  DeepLinkStatus* = enum
    dlsNavigated,
    dlsRejected,
    dlsUnmatched,
    dlsNavigationDeclined

  DeepLinkResult*[Destination] = object
    status*: DeepLinkStatus
    validation*: PlatformUrlValidation
    destination*: Option[Destination]

proc validScheme(scheme: string): bool =
  if scheme.len == 0 or not scheme[0].isAlphaAscii:
    return false
  for character in scheme:
    if not (character.isAlphaNumeric or character in {'+', '-', '.'}):
      return false
  true

proc platformUrlPolicy*(
    allowedSchemes: openArray[string];
    maxLength = defaultPlatformUrlMaxLength
): PlatformUrlPolicy =
  if maxLength <= 0:
    raise newException(ValueError, "platform URL maximum length must be positive")
  if allowedSchemes.len == 0:
    raise newException(ValueError, "platform URL policy requires an allowed scheme")
  result.maxLength = maxLength
  for scheme in allowedSchemes:
    let normalized = scheme.toLowerAscii()
    if not normalized.validScheme():
      raise newException(ValueError, "platform URL policy contains an invalid scheme")
    if normalized notin result.allowedSchemes:
      result.allowedSchemes.add normalized

proc defaultExternalUrlPolicy*(): PlatformUrlPolicy =
  platformUrlPolicy(["https", "http"])

proc validatePlatformUrl*(
    url: string;
    policy: PlatformUrlPolicy
): PlatformUrlValidation =
  if url.len == 0:
    return puvEmpty
  if policy.maxLength <= 0 or url.len > policy.maxLength:
    return puvTooLong
  for character in url:
    if ord(character) <= 0x20 or ord(character) == 0x7f:
      return puvUnsafeText

  let parsed = parseUri(url)
  let scheme = parsed.scheme.toLowerAscii()
  if not scheme.validScheme():
    return puvMissingScheme
  if scheme notin policy.allowedSchemes:
    return puvSchemeNotAllowed
  puvValid

proc externalUrlAdapter*(open: ExternalUrlOpenProc): ExternalUrlAdapter =
  if open.isNil:
    raise newException(ValueError, "external URL adapter requires an open procedure")
  ExternalUrlAdapter(open: open)

proc openExternalUrl*(
    adapter: ExternalUrlAdapter;
    url: string;
    policy = defaultExternalUrlPolicy()
): ExternalUrlOpenResult =
  let validation = validatePlatformUrl(url, policy)
  if validation != puvValid:
    return ExternalUrlOpenResult(
      status: euosRejected,
      validation: validation
    )
  if adapter.open.isNil:
    return ExternalUrlOpenResult(
      status: euosFailed,
      validation: puvValid
    )
  ExternalUrlOpenResult(
    status: if adapter.open(url): euosOpened else: euosFailed,
    validation: puvValid
  )

proc deepLinkCodec*[Destination](
    allowedSchemes: openArray[string];
    decode: DeepLinkDecodeProc[Destination];
    encode: DeepLinkEncodeProc[Destination] = nil;
    maxLength = defaultPlatformUrlMaxLength
): DeepLinkCodec[Destination] =
  if decode.isNil:
    raise newException(ValueError, "deep-link codec requires a decode procedure")
  DeepLinkCodec[Destination](
    policy: platformUrlPolicy(allowedSchemes, maxLength),
    decode: decode,
    encode: encode
  )

proc deepLinkSourceAdapter*(takePending: DeepLinkSourceProc): DeepLinkSourceAdapter =
  if takePending.isNil:
    raise newException(ValueError, "deep-link source adapter requires a pending-link procedure")
  DeepLinkSourceAdapter(takePending: takePending)

proc commandLineDeepLinkAdapter*(
    arguments: openArray[string]
): DeepLinkSourceAdapter =
  var pending = @arguments
  deepLinkSourceAdapter(proc(): seq[string] =
    result = pending
    pending.setLen(0)
  )

proc commandLineDeepLinkAdapter*(): DeepLinkSourceAdapter =
  commandLineDeepLinkAdapter(commandLineParams())

proc decodeDeepLink*[Destination](
    codec: DeepLinkCodec[Destination];
    url: string
): DeepLinkResult[Destination] =
  let validation = validatePlatformUrl(url, codec.policy)
  if validation != puvValid:
    return DeepLinkResult[Destination](
      status: dlsRejected,
      validation: validation,
      destination: none(Destination)
    )
  let destination = codec.decode(url)
  DeepLinkResult[Destination](
    status: if destination.isSome: dlsNavigated else: dlsUnmatched,
    validation: puvValid,
    destination: destination
  )

proc encodeDeepLink*[Destination](
    codec: DeepLinkCodec[Destination];
    destination: Destination
): Option[string] =
  if codec.encode.isNil:
    return none(string)
  let encoded = codec.encode(destination)
  if encoded.isNone or validatePlatformUrl(encoded.get, codec.policy) != puvValid:
    return none(string)
  encoded

proc navigateDeepLink*[Destination](
    navigator: Navigator[Destination];
    codec: DeepLinkCodec[Destination];
    url: string;
    mode = dlnPush
): DeepLinkResult[Destination] =
  result = codec.decodeDeepLink(url)
  if result.status != dlsNavigated:
    return
  let changed =
    case mode
    of dlnPush:
      navigator.push(result.destination.get)
    of dlnReplace:
      navigator.replace(result.destination.get)
  if not changed:
    result.status = dlsNavigationDeclined

proc drainDeepLinks*[Destination](
    source: DeepLinkSourceAdapter;
    navigator: Navigator[Destination];
    codec: DeepLinkCodec[Destination];
    mode = dlnPush
): seq[DeepLinkResult[Destination]] =
  if source.takePending.isNil:
    return
  for url in source.takePending():
    result.add navigator.navigateDeepLink(codec, url, mode)
