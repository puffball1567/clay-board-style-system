import ./[command, cue]

type
  CommandInputFactory*[Input] = proc(): Input {.closure.}

proc cueCommand*[Input, Output, Failure](
    name: string;
    command: Command[Input, Output, Failure];
    inputFactory: CommandInputFactory[Input];
    failureMessage = "Command failed";
    cancelledMessage = "Command was cancelled"
): CueAction =
  if command.isNil or command.disposed:
    raise newException(ValueError, "Cue command is not active")
  if inputFactory.isNil:
    raise newException(ValueError, "Cue command input factory cannot be nil")
  if failureMessage.len == 0:
    raise newException(ValueError, "Cue command failure message cannot be empty")
  if cancelledMessage.len == 0:
    raise newException(ValueError, "Cue command cancellation message cannot be empty")

  cueAction(name, proc(completion: CueCompletion): CueCancel =
    var ticket: CommandTicket
    try:
      var input = inputFactory()
      ticket = command.run(move(input))
      when not defined(release) or defined(cbssFrontendTrace):
        completion.traceAdapter(ftkCommandStarted, name, ticket.id)
    except CatchableError as error:
      when not defined(release) or defined(cbssFrontendTrace):
        completion.traceAdapter(
          ftkCommandFailed,
          name,
          detail = "Command could not start: " & error.msg
        )
      completion.fail("Command could not start: " & error.msg)
      return nil

    let subscription = command.observeRun(
      ticket,
      proc(observed: CommandTicket; status: CommandStatus) {.raises: [].} =
        discard observed
        try:
          case status
          of csSucceeded:
            when not defined(release) or defined(cbssFrontendTrace):
              completion.traceAdapter(ftkCommandSucceeded, name, observed.id)
            completion.succeed()
          of csFailed:
            when not defined(release) or defined(cbssFrontendTrace):
              completion.traceAdapter(ftkCommandFailed, name, observed.id)
            completion.fail(failureMessage)
          of csCancelled:
            when not defined(release) or defined(cbssFrontendTrace):
              completion.traceAdapter(ftkCommandCancelled, name, observed.id)
            completion.fail(cancelledMessage)
          of csQueued, csRunning:
            discard
        except Exception:
          discard
    )

    return proc() {.raises: [].} =
      discard command.unsubscribeRun(subscription)
      try:
        discard command.cancel(ticket)
      except Exception:
        discard
  )
