import std/[math, net, options, re, strutils, times, unicode, uri]

type
  ValidationReport* {.pure.} = enum
    onInput,
    onBlur,
    onSubmit

  ValidationTrigger* {.pure.} = enum
    input,
    blur,
    submit,
    explicit

  ValidationRuleKind* {.pure.} = enum
    required,
    optional,
    minLength,
    maxLength,
    exactLength,
    notBlank,
    matches,
    contains,
    startsWith,
    endsWith,
    email,
    url,
    uuid,
    ipAddress,
    date,
    time,
    dateTime,
    min,
    max,
    range,
    integer,
    positive,
    negative,
    finite,
    multipleOf,
    equalTo,
    notEqualTo,
    oneOf,
    notOneOf,
    sameAs,
    differentFrom,
    minItems,
    maxItems,
    exactItems,
    uniqueItems,
    maxFileSize,
    allowedMimeTypes,
    allowedExtensions,
    maxFiles,
    custom

  ValidationPattern* = object
    source*: string
    compiled: Regex

  ValidationFile* = object
    name*: string
    mimeType*: string
    size*: uint64

  ValidationIssue* = object
    code*: string
    message*: string
    ruleIndex*: int

  ValidationResult* = object
    isValid*: bool
    issue*: Option[ValidationIssue]

  ValidationCustomProc*[T] = proc(value: T): bool {.closure.}

  ValidationValueRef*[T] = ref object
    value: T

  ValidationRule*[T] = object
    kind*: ValidationRuleKind
    message*: string
    integerA: int
    sizeLimit: uint64
    textA: string
    texts: seq[string]
    values: seq[T]
    pattern: ValidationPattern
    expected: T
    expectedB: T
    peer: ValidationValueRef[T]
    customProc: ValidationCustomProc[T]

  ValidationRules*[T] = object
    rules: seq[ValidationRule[T]]

  ValidationBinding*[T] = ref object
    rules: ValidationRules[T]
    valueRef: ValidationValueRef[T]
    reportOn*: ValidationReport
    result*: ValidationResult
    hasReported*: bool

  ValidationCheckProc* = proc(report: bool): ValidationResult {.closure.}

  ValidationAdapter* = ref object
    checkProc: ValidationCheckProc
    currentProc: proc(): ValidationResult {.closure.}

proc compileRegex*(source: string): ValidationPattern =
  if source.len == 0:
    raise newException(ValueError, "validation regular expression cannot be empty")
  try:
    result = ValidationPattern(source: source, compiled: re(source))
  except RegexError as error:
    raise newException(ValueError, "invalid validation regular expression: " & error.msg)

proc validationFile*(name: string; size: uint64; mimeType = ""): ValidationFile =
  ValidationFile(name: name, mimeType: mimeType, size: size)

proc validValidationResult*(): ValidationResult =
  ValidationResult(isValid: true, issue: none(ValidationIssue))

proc invalidValidationResult*(code, message: string; ruleIndex = -1): ValidationResult =
  ValidationResult(
    isValid: false,
    issue: some(ValidationIssue(code: code, message: message, ruleIndex: ruleIndex))
  )

proc message*(validation: ValidationResult): string =
  if validation.issue.isSome: validation.issue.get.message else: ""

proc code*(validation: ValidationResult): string =
  if validation.issue.isSome: validation.issue.get.code else: ""

proc validationRules*[T](): ValidationRules[T] =
  ValidationRules[T](rules: @[])

proc len*[T](rules: ValidationRules[T]): int {.inline.} =
  rules.rules.len

proc initValidationBinding*[T](
    rules: ValidationRules[T];
    value: T;
    reportOn = ValidationReport.onBlur
): ValidationBinding[T] =
  ValidationBinding[T](
    rules: rules,
    valueRef: ValidationValueRef[T](value: value),
    reportOn: reportOn,
    result: rules.validate(value)
  )

proc shouldExpose*(binding: ValidationBinding): bool {.inline.} =
  not binding.isNil and binding.hasReported and not binding.result.isValid

proc validationMessage*(binding: ValidationBinding): string =
  if binding.shouldExpose(): binding.result.message else: ""

proc valueReference*[T](binding: ValidationBinding[T]): ValidationValueRef[T] =
  if binding.isNil:
    raise newException(ValueError, "validation binding is not initialized")
  binding.valueRef

proc identity*[T](value: ValidationValueRef[T]): pointer {.inline.} =
  cast[pointer](value)

proc dependencyReferences*[T](binding: ValidationBinding[T]): seq[ValidationValueRef[T]] =
  if binding.isNil:
    return @[]
  for rule in binding.rules.rules:
    if rule.kind notin {ValidationRuleKind.sameAs, ValidationRuleKind.differentFrom} or
        rule.peer.isNil:
      continue
    var duplicate = false
    for existing in result:
      if existing == rule.peer:
        duplicate = true
        break
    if not duplicate:
      result.add rule.peer

proc evaluate*[T](
    binding: ValidationBinding[T];
    value: T;
    trigger = ValidationTrigger.explicit;
    forceReport = false
): ValidationResult =
  if binding.isNil:
    return validValidationResult()
  binding.valueRef.value = value
  binding.result = binding.rules.validate(value)
  if forceReport or
      (trigger == ValidationTrigger.input and binding.reportOn == ValidationReport.onInput) or
      (trigger == ValidationTrigger.blur and binding.reportOn == ValidationReport.onBlur) or
      (trigger == ValidationTrigger.submit and binding.reportOn == ValidationReport.onSubmit):
    binding.hasReported = true
  binding.result

proc validationAdapter*(
    checkProc: ValidationCheckProc;
    currentProc: proc(): ValidationResult {.closure.}
): ValidationAdapter =
  if checkProc.isNil or currentProc.isNil:
    raise newException(ValueError, "validation adapter callbacks are required")
  ValidationAdapter(checkProc: checkProc, currentProc: currentProc)

proc check*(adapter: ValidationAdapter; report = false): ValidationResult =
  if adapter.isNil:
    return validValidationResult()
  adapter.checkProc(report)

proc current*(adapter: ValidationAdapter): ValidationResult =
  if adapter.isNil:
    return validValidationResult()
  adapter.currentProc()

proc initValidationValue*[T](value: T): ValidationValueRef[T] =
  ValidationValueRef[T](value: value)

proc get*[T](value: ValidationValueRef[T]): T =
  if value.isNil:
    raise newException(ValueError, "validation value reference is not initialized")
  value.value

proc set*[T](value: ValidationValueRef[T]; replacement: T) =
  if value.isNil:
    raise newException(ValueError, "validation value reference is not initialized")
  value.value = replacement

proc addRule[T](rules: ValidationRules[T]; rule: sink ValidationRule[T]): ValidationRules[T] =
  result.rules = newSeqOfCap[ValidationRule[T]](rules.rules.len + 1)
  for existing in rules.rules:
    result.rules.add existing
  result.rules.add rule

proc required*[T](rules: ValidationRules[T]; message = "This value is required"): ValidationRules[T] =
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.required, message: message))

proc optional*[T](rules: ValidationRules[T]): ValidationRules[T] =
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.optional))

proc minLength*[T](rules: ValidationRules[T]; length: int; message = "Value is too short"): ValidationRules[T] =
  if length < 0:
    raise newException(ValueError, "minimum length cannot be negative")
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.minLength, integerA: length, message: message))

proc maxLength*[T](rules: ValidationRules[T]; length: int; message = "Value is too long"): ValidationRules[T] =
  if length < 0:
    raise newException(ValueError, "maximum length cannot be negative")
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.maxLength, integerA: length, message: message))

proc exactLength*[T](rules: ValidationRules[T]; length: int; message = "Value has the wrong length"): ValidationRules[T] =
  if length < 0:
    raise newException(ValueError, "exact length cannot be negative")
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.exactLength, integerA: length, message: message))

proc notBlank*(rules: ValidationRules[string]; message = "Value cannot be blank"): ValidationRules[string] =
  rules.addRule(ValidationRule[string](kind: ValidationRuleKind.notBlank, message: message))

proc matches*(rules: ValidationRules[string]; pattern: ValidationPattern; message = "Value has an invalid format"): ValidationRules[string] =
  rules.addRule(ValidationRule[string](kind: ValidationRuleKind.matches, pattern: pattern, message: message))

proc contains*(rules: ValidationRules[string]; text: string; message = "Value does not contain the required text"): ValidationRules[string] =
  rules.addRule(ValidationRule[string](kind: ValidationRuleKind.contains, textA: text, message: message))

proc startsWith*(rules: ValidationRules[string]; text: string; message = "Value has the wrong prefix"): ValidationRules[string] =
  rules.addRule(ValidationRule[string](kind: ValidationRuleKind.startsWith, textA: text, message: message))

proc endsWith*(rules: ValidationRules[string]; text: string; message = "Value has the wrong suffix"): ValidationRules[string] =
  rules.addRule(ValidationRule[string](kind: ValidationRuleKind.endsWith, textA: text, message: message))

template stringFormatRule(name: untyped; kindValue: ValidationRuleKind; defaultMessage: string) =
  proc name*(rules: ValidationRules[string]; message = defaultMessage): ValidationRules[string] =
    rules.addRule(ValidationRule[string](kind: kindValue, message: message))

stringFormatRule(email, ValidationRuleKind.email, "Value is not a valid email address")
stringFormatRule(url, ValidationRuleKind.url, "Value is not a valid URL")
stringFormatRule(uuid, ValidationRuleKind.uuid, "Value is not a valid UUID")
stringFormatRule(ipAddress, ValidationRuleKind.ipAddress, "Value is not a valid IP address")
stringFormatRule(date, ValidationRuleKind.date, "Value is not a valid date")
stringFormatRule(time, ValidationRuleKind.time, "Value is not a valid time")
stringFormatRule(dateTime, ValidationRuleKind.dateTime, "Value is not a valid date and time")

template numericRule(name: untyped; kindValue: ValidationRuleKind; defaultMessage: string) =
  proc name*[T: SomeNumber](rules: ValidationRules[T]; limit: T; message = defaultMessage): ValidationRules[T] =
    when T is SomeFloat:
      if classify(limit) == fcNan:
        raise newException(ValueError, "numeric validation limit cannot be NaN")
    rules.addRule(ValidationRule[T](kind: kindValue, expected: limit, message: message))

numericRule(min, ValidationRuleKind.min, "Value is below the minimum")
numericRule(max, ValidationRuleKind.max, "Value exceeds the maximum")

proc range*[T: SomeNumber](rules: ValidationRules[T]; minimum, maximum: T; message = "Value is outside the allowed range"): ValidationRules[T] =
  when T is SomeFloat:
    if classify(minimum) == fcNan or classify(maximum) == fcNan:
      raise newException(ValueError, "validation range limits cannot be NaN")
  if minimum > maximum:
    raise newException(ValueError, "validation range minimum cannot exceed maximum")
  rules.addRule(ValidationRule[T](
    kind: ValidationRuleKind.range,
    expected: minimum,
    expectedB: maximum,
    message: message
  ))

template numericFlagRule(name: untyped; kindValue: ValidationRuleKind; defaultMessage: string) =
  proc name*[T: SomeNumber](rules: ValidationRules[T]; message = defaultMessage): ValidationRules[T] =
    rules.addRule(ValidationRule[T](kind: kindValue, message: message))

numericFlagRule(integer, ValidationRuleKind.integer, "Value must be an integer")
numericFlagRule(positive, ValidationRuleKind.positive, "Value must be positive")
numericFlagRule(negative, ValidationRuleKind.negative, "Value must be negative")
numericFlagRule(finite, ValidationRuleKind.finite, "Value must be finite")

proc multipleOf*[T: SomeNumber](rules: ValidationRules[T]; divisor: T; message = "Value is not an allowed multiple"): ValidationRules[T] =
  when T is SomeFloat:
    if classify(divisor) in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "multipleOf divisor must be finite")
  if float64(divisor) == 0.0:
    raise newException(ValueError, "multipleOf divisor cannot be zero")
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.multipleOf, expected: divisor, message: message))

proc equalTo*[T](rules: ValidationRules[T]; expected: T; message = "Value does not match the expected value"): ValidationRules[T] =
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.equalTo, expected: expected, message: message))

proc notEqualTo*[T](rules: ValidationRules[T]; expected: T; message = "Value must differ from the rejected value"): ValidationRules[T] =
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.notEqualTo, expected: expected, message: message))

proc oneOf*[T](rules: ValidationRules[T]; values: openArray[T]; message = "Value is not an allowed choice"): ValidationRules[T] =
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.oneOf, values: @values, message: message))

proc notOneOf*[T](rules: ValidationRules[T]; values: openArray[T]; message = "Value is a rejected choice"): ValidationRules[T] =
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.notOneOf, values: @values, message: message))

proc sameAs*[T](rules: ValidationRules[T]; peer: ValidationValueRef[T]; message = "Values do not match"): ValidationRules[T] =
  if peer.isNil:
    raise newException(ValueError, "sameAs peer is not initialized")
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.sameAs, peer: peer, message: message))

proc differentFrom*[T](rules: ValidationRules[T]; peer: ValidationValueRef[T]; message = "Values must differ"): ValidationRules[T] =
  if peer.isNil:
    raise newException(ValueError, "differentFrom peer is not initialized")
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.differentFrom, peer: peer, message: message))

proc minItems*[T](rules: ValidationRules[seq[T]]; count: int; message = "Too few items are selected"): ValidationRules[seq[T]] =
  if count < 0:
    raise newException(ValueError, "minimum item count cannot be negative")
  rules.addRule(ValidationRule[seq[T]](kind: ValidationRuleKind.minItems, integerA: count, message: message))

proc maxItems*[T](rules: ValidationRules[seq[T]]; count: int; message = "Too many items are selected"): ValidationRules[seq[T]] =
  if count < 0:
    raise newException(ValueError, "maximum item count cannot be negative")
  rules.addRule(ValidationRule[seq[T]](kind: ValidationRuleKind.maxItems, integerA: count, message: message))

proc exactItems*[T](rules: ValidationRules[seq[T]]; count: int; message = "The wrong number of items is selected"): ValidationRules[seq[T]] =
  if count < 0:
    raise newException(ValueError, "exact item count cannot be negative")
  rules.addRule(ValidationRule[seq[T]](kind: ValidationRuleKind.exactItems, integerA: count, message: message))

proc uniqueItems*[T](rules: ValidationRules[seq[T]]; message = "Items must be unique"): ValidationRules[seq[T]] =
  rules.addRule(ValidationRule[seq[T]](kind: ValidationRuleKind.uniqueItems, message: message))

proc maxFileSize*(rules: ValidationRules[seq[ValidationFile]]; bytes: uint64; message = "A file exceeds the size limit"): ValidationRules[seq[ValidationFile]] =
  rules.addRule(ValidationRule[seq[ValidationFile]](
    kind: ValidationRuleKind.maxFileSize,
    sizeLimit: bytes,
    message: message
  ))

proc allowedMimeTypes*(rules: ValidationRules[seq[ValidationFile]]; mimeTypes: openArray[string]; message = "A file has a disallowed media type"): ValidationRules[seq[ValidationFile]] =
  var normalized: seq[string] = @[]
  for mimeType in mimeTypes:
    let value = mimeType.strip().toLowerAscii()
    let separator = value.find('/')
    if separator <= 0 or separator >= value.high or
        value.find('/', separator + 1) >= 0:
      raise newException(ValueError, "allowed MIME types must use type/subtype syntax")
    let mediaType = value[0 ..< separator]
    let subtype = value[separator + 1 .. ^1]
    if (mediaType.contains('*') and mediaType != "*") or
        (subtype.contains('*') and subtype != "*") or
        (mediaType == "*" and subtype != "*"):
      raise newException(ValueError, "MIME wildcards must be type/* or */*")
    normalized.add value
  rules.addRule(ValidationRule[seq[ValidationFile]](
    kind: ValidationRuleKind.allowedMimeTypes,
    texts: normalized,
    message: message
  ))

proc allowedExtensions*(rules: ValidationRules[seq[ValidationFile]]; extensions: openArray[string]; message = "A file has a disallowed extension"): ValidationRules[seq[ValidationFile]] =
  var normalized: seq[string] = @[]
  for extension in extensions:
    var value = extension.strip().toLowerAscii()
    if value.startsWith("."):
      value = value[1 .. ^1]
    if value.len == 0:
      raise newException(ValueError, "allowed extensions cannot contain an empty value")
    normalized.add value
  rules.addRule(ValidationRule[seq[ValidationFile]](
    kind: ValidationRuleKind.allowedExtensions,
    texts: normalized,
    message: message
  ))

proc maxFiles*(rules: ValidationRules[seq[ValidationFile]]; count: int; message = "Too many files are selected"): ValidationRules[seq[ValidationFile]] =
  if count < 0:
    raise newException(ValueError, "maximum file count cannot be negative")
  rules.addRule(ValidationRule[seq[ValidationFile]](kind: ValidationRuleKind.maxFiles, integerA: count, message: message))

proc custom*[T](rules: ValidationRules[T]; validator: ValidationCustomProc[T]; message = "Value is invalid"): ValidationRules[T] =
  if validator.isNil:
    raise newException(ValueError, "custom validation procedure is required")
  rules.addRule(ValidationRule[T](kind: ValidationRuleKind.custom, customProc: validator, message: message))

proc isAbsent[T](value: T): bool =
  when T is string:
    value.len == 0
  elif T is seq:
    value.len == 0
  elif compiles(value.isNone):
    value.isNone
  else:
    false

proc lengthOf[T](value: T): int =
  when T is string:
    value.runeLen
  elif compiles(value.len):
    value.len
  else:
    -1

proc exactPatternMatch(value: string; pattern: ValidationPattern): bool =
  value.matchLen(pattern.compiled) == value.len

proc validEmail(value: string): bool =
  if value.len < 3 or value.contains({' ', '\t', '\r', '\n'}):
    return false
  let separator = value.rfind('@')
  if separator <= 0 or separator != value.find('@') or separator >= value.high:
    return false
  let local = value[0 ..< separator]
  let domain = value[separator + 1 .. ^1]
  if local.startsWith(".") or local.endsWith(".") or local.contains(".."):
    return false
  if domain.startsWith(".") or domain.endsWith(".") or domain.contains(".."):
    return false
  var labelStart = 0
  for index in 0 .. domain.len:
    if index < domain.len and domain[index] != '.':
      continue
    if index == labelStart or domain[labelStart] == '-' or domain[index - 1] == '-':
      return false
    for position in labelStart ..< index:
      let ch = domain[position]
      if not (ch.isAlphaNumeric or ch == '-'):
        return false
    labelStart = index + 1
  true

proc validUrl(value: string): bool =
  if value.len == 0 or value.contains({' ', '\t', '\r', '\n'}):
    return false
  try:
    let parsed = parseUri(value)
    parsed.scheme.len > 0 and (parsed.hostname.len > 0 or parsed.path.len > 0)
  except ValueError:
    false

proc validUuid(value: string): bool =
  if value.len != 36:
    return false
  for index, ch in value:
    if index in [8, 13, 18, 23]:
      if ch != '-':
        return false
    elif ch notin {'0'..'9', 'a'..'f', 'A'..'F'}:
      return false
  true

proc validIpAddress(value: string): bool =
  try:
    discard parseIpAddress(value)
    true
  except ValueError:
    false

proc validDate(value: string): bool =
  if value.len != 10 or value[4] != '-' or value[7] != '-':
    return false
  try:
    discard parse(value, "yyyy-MM-dd", utc())
    true
  except TimeParseError:
    false

proc parseTwoDigits(value: string; offset: int): int =
  if offset < 0 or offset + 1 >= value.len or
      not value[offset].isDigit or not value[offset + 1].isDigit:
    return -1
  (ord(value[offset]) - ord('0')) * 10 + ord(value[offset + 1]) - ord('0')

proc validTime(value: string): bool =
  if value.len < 5 or value[2] != ':':
    return false
  let hour = value.parseTwoDigits(0)
  let minute = value.parseTwoDigits(3)
  if hour notin 0 .. 23 or minute notin 0 .. 59:
    return false
  if value.len == 5:
    return true
  if value.len < 8 or value[5] != ':':
    return false
  let second = value.parseTwoDigits(6)
  if second notin 0 .. 59:
    return false
  if value.len == 8:
    return true
  if value[8] != '.' or value.len == 9:
    return false
  for index in 9 .. value.high:
    if not value[index].isDigit:
      return false
  true

proc validDateTime(value: string): bool =
  if value.len < 16 or value[10] notin {'T', 't', ' '}:
    return false
  if not value[0 .. 9].validDate():
    return false
  var timeEnd = value.len
  if value.endsWith("Z") or value.endsWith("z"):
    dec timeEnd
  elif value.len >= 6 and value[^6] in {'+', '-'} and value[^3] == ':':
    let offsetHour = value.parseTwoDigits(value.len - 5)
    let offsetMinute = value.parseTwoDigits(value.len - 2)
    if offsetHour notin 0 .. 23 or offsetMinute notin 0 .. 59:
      return false
    timeEnd -= 6
  value[11 ..< timeEnd].validTime()

proc containsValue[T](values: openArray[T]; value: T): bool =
  for candidate in values:
    if candidate == value:
      return true
  false

proc hasUniqueItems[T](values: openArray[T]): bool =
  for first in 0 ..< values.len:
    for second in first + 1 ..< values.len:
      if values[first] == values[second]:
        return false
  true

proc fileExtension(name: string): string =
  let index = name.rfind('.')
  if index < 0 or index >= name.high:
    return ""
  name[index + 1 .. ^1].toLowerAscii()

proc mimeAllowed(mimeType: string; allowed: openArray[string]): bool =
  let normalized = mimeType.strip().toLowerAscii()
  for candidate in allowed:
    if candidate == "*/*":
      return true
    elif candidate.endsWith("/*"):
      let prefix = candidate[0 ..< candidate.len - 1]
      if normalized.startsWith(prefix):
        return true
    elif normalized == candidate:
      return true
  false

proc rulePasses[T](rule: ValidationRule[T]; value: T): bool =
  case rule.kind
  of ValidationRuleKind.required:
    not value.isAbsent()
  of ValidationRuleKind.optional:
    true
  of ValidationRuleKind.minLength:
    value.lengthOf() >= rule.integerA
  of ValidationRuleKind.maxLength:
    let length = value.lengthOf()
    length >= 0 and length <= rule.integerA
  of ValidationRuleKind.exactLength:
    value.lengthOf() == rule.integerA
  of ValidationRuleKind.notBlank:
    when T is string: value.strip().len > 0 else: false
  of ValidationRuleKind.matches:
    when T is string: value.exactPatternMatch(rule.pattern) else: false
  of ValidationRuleKind.contains:
    when T is string: value.contains(rule.textA) else: false
  of ValidationRuleKind.startsWith:
    when T is string: value.startsWith(rule.textA) else: false
  of ValidationRuleKind.endsWith:
    when T is string: value.endsWith(rule.textA) else: false
  of ValidationRuleKind.email:
    when T is string: value.validEmail() else: false
  of ValidationRuleKind.url:
    when T is string: value.validUrl() else: false
  of ValidationRuleKind.uuid:
    when T is string: value.validUuid() else: false
  of ValidationRuleKind.ipAddress:
    when T is string: value.validIpAddress() else: false
  of ValidationRuleKind.date:
    when T is string: value.validDate() else: false
  of ValidationRuleKind.time:
    when T is string: value.validTime() else: false
  of ValidationRuleKind.dateTime:
    when T is string: value.validDateTime() else: false
  of ValidationRuleKind.min:
    when T is SomeNumber: value >= rule.expected else: false
  of ValidationRuleKind.max:
    when T is SomeNumber: value <= rule.expected else: false
  of ValidationRuleKind.range:
    when T is SomeNumber:
      value >= rule.expected and value <= rule.expectedB
    else:
      false
  of ValidationRuleKind.integer:
    when T is SomeInteger: true
    elif T is SomeFloat:
      classify(value) notin {fcNan, fcInf, fcNegInf} and floor(value) == value
    else: false
  of ValidationRuleKind.positive:
    when T is SomeNumber: value > T(0) else: false
  of ValidationRuleKind.negative:
    when T is SomeNumber: value < T(0) else: false
  of ValidationRuleKind.finite:
    when T is SomeFloat: classify(value) notin {fcNan, fcInf, fcNegInf}
    elif T is SomeInteger: true
    else: false
  of ValidationRuleKind.multipleOf:
    when T is SomeInteger:
      value mod rule.expected == T(0)
    elif T is SomeFloat:
      if classify(value) in {fcNan, fcInf, fcNegInf}:
        false
      else:
        let quotient = float64(value) / float64(rule.expected)
        abs(quotient - round(quotient)) <= 1.0e-9 * max(1.0, abs(quotient))
    else:
      false
  of ValidationRuleKind.equalTo:
    value == rule.expected
  of ValidationRuleKind.notEqualTo:
    value != rule.expected
  of ValidationRuleKind.oneOf:
    rule.values.containsValue(value)
  of ValidationRuleKind.notOneOf:
    not rule.values.containsValue(value)
  of ValidationRuleKind.sameAs:
    not rule.peer.isNil and value == rule.peer.value
  of ValidationRuleKind.differentFrom:
    not rule.peer.isNil and value != rule.peer.value
  of ValidationRuleKind.minItems:
    when T is seq: value.len >= rule.integerA else: false
  of ValidationRuleKind.maxItems:
    when T is seq: value.len <= rule.integerA else: false
  of ValidationRuleKind.exactItems:
    when T is seq: value.len == rule.integerA else: false
  of ValidationRuleKind.uniqueItems:
    when T is seq: value.hasUniqueItems() else: false
  of ValidationRuleKind.maxFileSize:
    when T is seq[ValidationFile]:
      for file in value:
        if file.size > rule.sizeLimit:
          return false
      true
    else:
      false
  of ValidationRuleKind.allowedMimeTypes:
    when T is seq[ValidationFile]:
      for file in value:
        if not file.mimeType.mimeAllowed(rule.texts):
          return false
      true
    else:
      false
  of ValidationRuleKind.allowedExtensions:
    when T is seq[ValidationFile]:
      for file in value:
        if not rule.texts.containsValue(file.name.fileExtension()):
          return false
      true
    else:
      false
  of ValidationRuleKind.maxFiles:
    when T is seq[ValidationFile]: value.len <= rule.integerA else: false
  of ValidationRuleKind.custom:
    not rule.customProc.isNil and rule.customProc(value)

proc validate*[T](rules: ValidationRules[T]; value: T): ValidationResult =
  let absent = value.isAbsent()
  var optional = false
  var requiredIndex = -1
  for index, rule in rules.rules:
    if rule.kind == ValidationRuleKind.optional:
      optional = true
    elif rule.kind == ValidationRuleKind.required:
      requiredIndex = index

  if absent:
    if requiredIndex >= 0:
      let rule = rules.rules[requiredIndex]
      return invalidValidationResult($rule.kind, rule.message, requiredIndex)
    if optional:
      return validValidationResult()

  for index, rule in rules.rules:
    if rule.kind in {ValidationRuleKind.required, ValidationRuleKind.optional}:
      continue
    if not rule.rulePasses(value):
      return invalidValidationResult($rule.kind, rule.message, index)
  validValidationResult()
