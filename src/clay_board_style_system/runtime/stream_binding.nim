import ../data/[stream_bridge, stream_mailbox]
import ./[component, frame_scheduler, invalidation]

type
  ComponentStreamBinding*[T] = ref object of ComponentOwnedResource
    mailboxValue: StreamMailbox[T]
    streamValue: StreamBridge[T]
    dirtyDomainsValue: set[DirtyDomain]

proc releaseStreamBinding[T](resource: ComponentOwnedResource) {.raises: [].} =
  let binding = ComponentStreamBinding[T](resource)
  if not binding.mailboxValue.isNil:
    discard binding.mailboxValue.dispose()
  if not binding.streamValue.isNil:
    discard binding.streamValue.close()
    discard binding.streamValue.drain()
  binding.mailboxValue = nil
  binding.streamValue = nil

proc initComponentStreamBinding*[T](
    maxQueuedItems = 64;
    maxQueuedWeight = 4'i64 * 1024'i64 * 1024'i64;
    dirtyDomains: set[DirtyDomain] = {ddResource}
): ComponentStreamBinding[T] =
  result = ComponentStreamBinding[T](
    mailboxValue: initStreamMailbox[T](maxQueuedItems, maxQueuedWeight),
    streamValue: initStreamBridge[T](maxQueuedItems, maxQueuedWeight),
    dirtyDomainsValue: dirtyDomains
  )
  result.setReleaseCallback(releaseStreamBinding[T])

proc attachStream*[T](
    component: CBSSComponent;
    _: typedesc[T];
    maxQueuedItems = 64;
    maxQueuedWeight = 4'i64 * 1024'i64 * 1024'i64;
    dirtyDomains: set[DirtyDomain] = {ddResource}
): ComponentStreamBinding[T] =
  component.own(initComponentStreamBinding[T](
    maxQueuedItems,
    maxQueuedWeight,
    dirtyDomains
  ))

proc producer*[T](binding: ComponentStreamBinding[T]): StreamProducer[T] =
  if binding.isNil or binding.disposed:
    return
  binding.mailboxValue.producer()

proc dirtyDomains*[T](binding: ComponentStreamBinding[T]): set[DirtyDomain] =
  if not binding.isNil:
    result = binding.dirtyDomainsValue

proc setWakeCallback*[T](
    binding: ComponentStreamBinding[T];
    callback: StreamMailboxWakeProc;
    context: pointer = nil
) =
  if binding.isNil or binding.disposed:
    return
  binding.mailboxValue.setWakeCallback(callback, context)

proc pending*[T](binding: ComponentStreamBinding[T]): bool =
  not binding.isNil and not binding.disposed and
    (binding.mailboxValue.hasPending or binding.streamValue.hasPending)

proc pump*[T](
    binding: ComponentStreamBinding[T];
    scheduler: var FrameScheduler;
    maxMessages = high(int)
): StreamMailboxPumpResult =
  if binding.isNil or binding.disposed:
    return
  result = binding.mailboxValue.pumpInto(binding.streamValue, maxMessages)
  if result.changed and binding.dirtyDomainsValue != {}:
    scheduler.markDirty(binding.dirtyDomainsValue)

proc drain*[T](
    binding: ComponentStreamBinding[T];
    maxEvents = high(int)
): seq[StreamEvent[T]] =
  if binding.isNil or binding.disposed:
    return @[]
  binding.streamValue.drain(maxEvents)
