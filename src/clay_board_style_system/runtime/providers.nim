import std/typetraits

type
  ProviderBox = ref object of RootObj

  ProviderValue[T] = ref object of ProviderBox
    value*: T

  Provider* = object
    key*: string
    value: ProviderBox

  ViewContext* = object
    providers*: seq[Provider]

proc providerKey*[T](_: typedesc[T]): string =
  name(T)

proc provide*[T](value: T): Provider =
  Provider(key: providerKey(T), value: ProviderValue[T](value: value))

proc providers*(items: openArray[Provider]): seq[Provider] =
  for item in items:
    result.add item

proc initViewContext*(items: openArray[Provider] = []): ViewContext =
  ViewContext(providers: @items)

proc addProvider*(ctx: var ViewContext; provider: Provider) =
  for item in ctx.providers.mitems:
    if item.key == provider.key:
      item = provider
      return
  ctx.providers.add provider

proc has*[T](ctx: ViewContext; _: typedesc[T]): bool =
  let key = providerKey(T)
  for provider in ctx.providers:
    if provider.key == key and provider.value of ProviderValue[T]:
      return true
  false

proc use*[T](ctx: ViewContext; _: typedesc[T]): T =
  let key = providerKey(T)
  for provider in ctx.providers:
    if provider.key == key and provider.value of ProviderValue[T]:
      return ProviderValue[T](provider.value).value
  raise newException(KeyError, "provider not found: " & key)
