type
  DiagnosticSeverity* = enum
    dsError,
    dsWarning

  Diagnostic* = object
    severity*: DiagnosticSeverity
    property*: string
    message*: string

  Diagnostics* = object
    items*: seq[Diagnostic]

proc addError*(diagnostics: var Diagnostics; property, message: string) =
  diagnostics.items.add Diagnostic(severity: dsError, property: property, message: message)

proc hasErrors*(diagnostics: Diagnostics): bool =
  for item in diagnostics.items:
    if item.severity == dsError:
      return true
  false
