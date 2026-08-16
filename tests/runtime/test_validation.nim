import std/[math, unittest]

import clay_board_style_system/runtime/validation

suite "validation rules":
  template checkOutcomes(
      rulesExpression, acceptedValue, rejectedValue, expectedCode: untyped
  ) =
    block:
      let rulesUnderTest = rulesExpression
      let acceptedResult = rulesUnderTest.validate(acceptedValue)
      let rejectedResult = rulesUnderTest.validate(rejectedValue)
      check acceptedResult.isValid
      check not rejectedResult.isValid
      check rejectedResult.code == expectedCode

  test "the first release exposes exactly forty built-in operations":
    check ord(high(ValidationRuleKind)) - ord(low(ValidationRuleKind)) + 1 == 40

  test "presence and string rules preserve explicit units of validation":
    let pattern = compileRegex("^[A-Za-z0-9_]+$")
    let rules =
      validationRules[string]()
        .required("required")
        .minLength(3, "minimum")
        .maxLength(8, "maximum")
        .matches(pattern, "pattern")
        .contains("_", "contains")
        .startsWith("ab", "prefix")
        .endsWith("cd", "suffix")

    check not rules.validate("").isValid
    check rules.validate("").code == "required"
    check rules.validate("a_").code == "minLength"
    check rules.validate("abc-def_cd").code == "maxLength"
    check rules.validate("abc-cd").code == "matches"
    check rules.validate("abcd").code == "contains"
    check rules.validate("zz_cd").code == "startsWith"
    check rules.validate("ab_zz").code == "endsWith"
    check rules.validate("ab_cd").isValid

  test "length counts Unicode runes rather than UTF-8 bytes":
    let rules = validationRules[string]().exactLength(2)
    check rules.validate("日本").isValid
    check not rules.validate("日本語").isValid

  test "optional short-circuits absent values but not present values":
    let rules = validationRules[string]().optional().email()
    check rules.validate("").isValid
    check not rules.validate("invalid").isValid
    check rules.validate("user@example.com").isValid

  test "required takes precedence over optional regardless of declaration order":
    check not validationRules[string]().optional().required().validate("").isValid
    check not validationRules[string]().required().optional().validate("").isValid

  test "notBlank differs from required":
    let requiredRules = validationRules[string]().required()
    let blankRules = validationRules[string]().notBlank()
    check requiredRules.validate("   ").isValid
    check not blankRules.validate("   ").isValid

  test "exactLength and invalid length descriptors are checked":
    check validationRules[string]().exactLength(3).validate("abc").isValid
    expect ValueError:
      discard validationRules[string]().minLength(-1)
    expect ValueError:
      discard validationRules[string]().maxLength(-1)
    expect ValueError:
      discard validationRules[string]().exactLength(-1)

  test "regular expressions compile once and reject malformed patterns":
    let rules = validationRules[string]().matches(compileRegex("^a+$"))
    check rules.validate("aaa").isValid
    check not rules.validate("aaab").isValid
    expect ValueError:
      discard compileRegex("")
    expect ValueError:
      discard compileRegex("[")

  test "rule chains do not mutate their source descriptors":
    let base = validationRules[string]().required()
    let extended = base.minLength(3)
    check base.len == 1
    check base.validate("a").isValid
    check extended.len == 2
    check not extended.validate("a").isValid

  test "format validators accept representative valid values":
    check validationRules[string]().email().validate("person+tag@example.co.jp").isValid
    check validationRules[string]().url().validate("https://example.com/path?q=1").isValid
    check validationRules[string]().uuid().validate("550e8400-e29b-41d4-a716-446655440000").isValid
    check validationRules[string]().ipAddress().validate("2001:db8::1").isValid
    check validationRules[string]().date().validate("2024-02-29").isValid
    check validationRules[string]().time().validate("23:59:58.125").isValid
    check validationRules[string]().dateTime().validate("2024-02-29T23:59:58Z").isValid
    check validationRules[string]().dateTime().validate("2024-02-29T23:59+09:00").isValid

  test "format validators reject malformed and out-of-range values":
    check not validationRules[string]().email().validate("two@@example.com").isValid
    check not validationRules[string]().email().validate("user@-example.com").isValid
    check not validationRules[string]().url().validate("not a url").isValid
    check not validationRules[string]().uuid().validate("550e8400-e29b-41d4-a716").isValid
    check not validationRules[string]().ipAddress().validate("999.1.1.1").isValid
    check not validationRules[string]().date().validate("2023-02-29").isValid
    check not validationRules[string]().time().validate("24:00").isValid
    check not validationRules[string]().dateTime().validate("2024-01-01T12:30+99:00").isValid

  test "numeric bounds and finite rules cover integer and float values":
    let integerRules =
      validationRules[int]()
        .min(2)
        .max(10)
        .range(2, 10)
        .integer()
        .positive()
        .finite()
        .multipleOf(2)
    check integerRules.validate(4).isValid
    check not integerRules.validate(1).isValid
    check not integerRules.validate(11).isValid
    check not integerRules.validate(5).isValid

    check validationRules[int]().negative().validate(-1).isValid
    check not validationRules[int]().positive().validate(0).isValid
    check validationRules[float64]().integer().validate(4.0).isValid
    check not validationRules[float64]().integer().validate(4.5).isValid
    check not validationRules[float64]().finite().validate(Inf).isValid
    check not validationRules[float64]().finite().validate(NaN).isValid
    check validationRules[float64]().multipleOf(0.1).validate(0.3).isValid

  test "invalid numeric descriptors fail at construction":
    expect ValueError:
      discard validationRules[int]().range(5, 4)
    expect ValueError:
      discard validationRules[int]().multipleOf(0)
    expect ValueError:
      discard validationRules[float64]().min(NaN)
    expect ValueError:
      discard validationRules[float64]().max(NaN)
    expect ValueError:
      discard validationRules[float64]().range(NaN, 1.0)
    expect ValueError:
      discard validationRules[float64]().multipleOf(Inf)

  test "comparison and selection rules are typed":
    check validationRules[string]().equalTo("yes").validate("yes").isValid
    check not validationRules[string]().notEqualTo("no").validate("no").isValid
    check validationRules[int]().oneOf([1, 2, 3]).validate(2).isValid
    check not validationRules[int]().oneOf([1, 2, 3]).validate(4).isValid
    check validationRules[int]().notOneOf([1, 2, 3]).validate(4).isValid

  test "cross-value comparison reads the current peer value":
    let password = initValidationValue("first")
    let confirmation = validationRules[string]().sameAs(password)
    let alternative = validationRules[string]().differentFrom(password)
    check confirmation.validate("first").isValid
    check alternative.validate("second").isValid
    password.set("changed")
    check not confirmation.validate("first").isValid
    check confirmation.validate("changed").isValid
    expect ValueError:
      discard validationRules[string]().sameAs(nil)

  test "collection rules enforce count and uniqueness":
    let rules =
      validationRules[seq[int]]()
        .minItems(2)
        .maxItems(4)
        .exactItems(3)
        .uniqueItems()
    check rules.validate(@[1, 2, 3]).isValid
    check not rules.validate(@[1]).isValid
    check not rules.validate(@[1, 2, 3, 4, 5]).isValid
    check not rules.validate(@[1, 2]).isValid
    check not rules.validate(@[1, 1, 2]).isValid
    expect ValueError:
      discard validationRules[seq[int]]().maxItems(-1)

  test "file rules inspect metadata without reading file contents":
    let files = @[
      validationFile("photo.PNG", 512, "image/png"),
      validationFile("icon.svg", 1024, "image/svg+xml")
    ]
    let rules =
      validationRules[seq[ValidationFile]]()
        .maxFileSize(1024)
        .allowedMimeTypes(["image/*"])
        .allowedExtensions([".png", "svg"])
        .maxFiles(2)
    check rules.validate(files).isValid
    check not rules.validate(@[validationFile("large.png", 1025, "image/png")]).isValid
    check not rules.validate(@[validationFile("note.txt", 10, "text/plain")]).isValid
    check not rules.validate(@[validationFile("photo.jpg", 10, "image/jpeg")]).isValid
    check not rules.validate(files & @[validationFile("third.png", 1, "image/png")]).isValid
    expect ValueError:
      discard validationRules[seq[ValidationFile]]().allowedMimeTypes([""])
    expect ValueError:
      discard validationRules[seq[ValidationFile]]().allowedExtensions(["."])

  test "custom rules are explicit and return their configured issue":
    let rules = validationRules[string]().custom(
      proc(value: string): bool = value == "approved",
      "custom message"
    )
    check rules.validate("approved").isValid
    let rejected = rules.validate("rejected")
    check not rejected.isValid
    check rejected.code == "custom"
    check rejected.message == "custom message"
    expect ValueError:
      discard validationRules[string]().custom(nil)

  test "empty rule sets are valid":
    let result = validationRules[string]().validate("anything")
    check result.isValid
    check result.message.len == 0
    check result.code.len == 0

  test "reporting policy is separate from current validity":
    let rules = validationRules[string]().required("required")
    let binding = initValidationBinding(rules, "", ValidationReport.onBlur)
    check not binding.result.isValid
    check not binding.shouldExpose()
    check binding.validationMessage.len == 0

    discard binding.evaluate("", ValidationTrigger.input)
    check not binding.shouldExpose()
    discard binding.evaluate("", ValidationTrigger.blur)
    check binding.shouldExpose()
    check binding.validationMessage == "required"

    discard binding.evaluate("valid", ValidationTrigger.input)
    check binding.result.isValid
    check not binding.shouldExpose()

  test "onInput and onSubmit policies expose only at their boundaries":
    let rules = validationRules[string]().required()
    let live = initValidationBinding(rules, "", ValidationReport.onInput)
    let submitOnly = initValidationBinding(rules, "", ValidationReport.onSubmit)
    discard live.evaluate("", ValidationTrigger.input)
    discard submitOnly.evaluate("", ValidationTrigger.blur)
    check live.shouldExpose()
    check not submitOnly.shouldExpose()
    discard submitOnly.evaluate("", ValidationTrigger.submit)
    check submitOnly.shouldExpose()

  test "every built-in operation has an explicit outcome matrix":
    let alpha = compileRegex("^[a-z]+$")
    let peer = initValidationValue("peer")
    let files = @[validationFile("icon.png", 8, "image/png")]

    checkOutcomes(validationRules[string]().required(), "value", "", "required")
    check validationRules[string]().optional().validate("").isValid
    check validationRules[string]().optional().validate("value").isValid
    checkOutcomes(validationRules[string]().minLength(2), "ab", "a", "minLength")
    checkOutcomes(validationRules[string]().maxLength(2), "ab", "abc", "maxLength")
    checkOutcomes(validationRules[string]().exactLength(2), "ab", "a", "exactLength")
    checkOutcomes(validationRules[string]().notBlank(), " a ", " \t", "notBlank")
    checkOutcomes(validationRules[string]().matches(alpha), "abc", "123", "matches")
    checkOutcomes(validationRules[string]().contains("bc"), "abcd", "ac", "contains")
    checkOutcomes(validationRules[string]().startsWith("ab"), "abcd", "zabcd", "startsWith")
    checkOutcomes(validationRules[string]().endsWith("cd"), "abcd", "abcdz", "endsWith")
    checkOutcomes(validationRules[string]().email(), "a@example.com", "a@", "email")
    checkOutcomes(validationRules[string]().url(), "https://example.com", "example", "url")
    checkOutcomes(
      validationRules[string]().uuid(),
      "550e8400-e29b-41d4-a716-446655440000",
      "550e8400-e29b",
      "uuid"
    )
    checkOutcomes(validationRules[string]().ipAddress(), "127.0.0.1", "300.0.0.1", "ipAddress")
    checkOutcomes(validationRules[string]().date(), "2024-02-29", "2023-02-29", "date")
    checkOutcomes(validationRules[string]().time(), "00:00", "24:00", "time")
    checkOutcomes(
      validationRules[string]().dateTime(),
      "2024-01-01T00:00:00Z",
      "2024-01-01T00:00+25:00",
      "dateTime"
    )
    checkOutcomes(validationRules[int]().min(2), 2, 1, "min")
    checkOutcomes(validationRules[int]().max(2), 2, 3, "max")
    checkOutcomes(validationRules[int]().range(2, 4), 3, 5, "range")
    checkOutcomes(validationRules[float64]().integer(), 2.0, 2.5, "integer")
    checkOutcomes(validationRules[int]().positive(), 1, 0, "positive")
    checkOutcomes(validationRules[int]().negative(), -1, 0, "negative")
    checkOutcomes(validationRules[float64]().finite(), 1.0, Inf, "finite")
    checkOutcomes(validationRules[int]().multipleOf(3), 6, 7, "multipleOf")
    checkOutcomes(validationRules[string]().equalTo("yes"), "yes", "no", "equalTo")
    checkOutcomes(validationRules[string]().notEqualTo("no"), "yes", "no", "notEqualTo")
    checkOutcomes(validationRules[int]().oneOf([1, 2]), 2, 3, "oneOf")
    checkOutcomes(validationRules[int]().notOneOf([1, 2]), 3, 2, "notOneOf")
    checkOutcomes(validationRules[string]().sameAs(peer), "peer", "other", "sameAs")
    checkOutcomes(
      validationRules[string]().differentFrom(peer),
      "other",
      "peer",
      "differentFrom"
    )
    checkOutcomes(validationRules[seq[int]]().minItems(2), @[1, 2], @[1], "minItems")
    checkOutcomes(validationRules[seq[int]]().maxItems(2), @[1, 2], @[1, 2, 3], "maxItems")
    checkOutcomes(validationRules[seq[int]]().exactItems(2), @[1, 2], @[1], "exactItems")
    checkOutcomes(validationRules[seq[int]]().uniqueItems(), @[1, 2], @[1, 1], "uniqueItems")
    checkOutcomes(
      validationRules[seq[ValidationFile]]().maxFileSize(8),
      files,
      @[validationFile("large.png", 9, "image/png")],
      "maxFileSize"
    )
    checkOutcomes(
      validationRules[seq[ValidationFile]]().allowedMimeTypes(["image/*"]),
      files,
      @[validationFile("note.txt", 8, "text/plain")],
      "allowedMimeTypes"
    )
    check validationRules[seq[ValidationFile]]()
      .allowedMimeTypes(["*/*"])
      .validate(@[validationFile("data.bin", 8, "application/octet-stream")])
      .isValid
    checkOutcomes(
      validationRules[seq[ValidationFile]]().allowedExtensions(["png"]),
      files,
      @[validationFile("icon.jpg", 8, "image/jpeg")],
      "allowedExtensions"
    )
    checkOutcomes(
      validationRules[seq[ValidationFile]]().maxFiles(1),
      files,
      files & files,
      "maxFiles"
    )
    checkOutcomes(
      validationRules[string]().custom(proc(value: string): bool = value == "ok"),
      "ok",
      "bad",
      "custom"
    )

  test "descriptor boundary matrix rejects invalid configuration":
    expect ValueError:
      discard validationRules[seq[int]]().minItems(-1)
    expect ValueError:
      discard validationRules[seq[int]]().maxItems(-1)
    expect ValueError:
      discard validationRules[seq[int]]().exactItems(-1)
    expect ValueError:
      discard validationRules[seq[ValidationFile]]().maxFiles(-1)
    expect ValueError:
      discard validationRules[seq[ValidationFile]]().allowedMimeTypes(["image"])
    expect ValueError:
      discard validationRules[seq[ValidationFile]]().allowedMimeTypes(["*/png"])
    expect ValueError:
      discard validationRules[seq[ValidationFile]]().allowedMimeTypes(["image/p*"])
    expect ValueError:
      discard validationRules[int]().range(2, 1)
    expect ValueError:
      discard validationRules[float64]().range(0.0, NaN)
    expect ValueError:
      discard validationRules[float64]().multipleOf(NaN)
    expect ValueError:
      discard validationRules[float64]().multipleOf(0.0)
    expect ValueError:
      discard validationRules[string]().differentFrom(nil)
