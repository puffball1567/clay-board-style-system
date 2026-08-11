import ../../data/stream_mailbox
import ../../runtime/[frame_scheduler, stream_binding]
import ./renderer

type
  Sdl3StreamWakeError* = object of CatchableError

  Sdl3StreamWake* = object
    tokenValue: uint32

proc postStreamWake(context: pointer) {.cdecl, gcsafe, raises: [].} =
  discard postSdl3StreamWake(uint32(cast[uint](context)))

proc valid*(wake: Sdl3StreamWake): bool {.inline.} =
  wake.tokenValue != 0

proc attachSdl3Wake*[T](binding: ComponentStreamBinding[T]): Sdl3StreamWake =
  ## Must be called on the SDL/UI thread before the producer starts. The
  ## mailbox callback only posts a copied SDL event and never enters UI code.
  if binding.isNil or binding.disposed:
    raise newException(
      Sdl3StreamWakeError,
      "SDL3 wake attachment requires a live component stream binding"
    )
  let token = allocateSdl3StreamWakeToken()
  if token == 0:
    raise newException(
      Sdl3StreamWakeError,
      "SDL3 could not allocate a stream wake event"
    )
  result.tokenValue = token
  binding.setWakeCallback(postStreamWake, cast[pointer](uint(token)))

proc detachSdl3Wake*[T](binding: ComponentStreamBinding[T]) =
  if not binding.isNil and not binding.disposed:
    binding.setWakeCallback(nil)

proc matches*(wake: Sdl3StreamWake; event: Sdl3Event): bool {.inline.} =
  wake.valid and event.kind == sekStreamWake and
    event.wakeToken == wake.tokenValue

proc pumpSdl3Wake*[T](
    binding: ComponentStreamBinding[T];
    wake: Sdl3StreamWake;
    event: Sdl3Event;
    scheduler: var FrameScheduler;
    maxMessages = high(int)
): StreamMailboxPumpResult =
  ## Returns an inert result for unrelated SDL events. If a bounded pump leaves
  ## work pending, the host should call `binding.pump` again before waiting.
  if not wake.matches(event):
    return
  binding.pump(scheduler, maxMessages)
