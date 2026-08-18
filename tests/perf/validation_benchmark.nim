import std/[monotimes, strformat, times]

import clay_board_style_system

proc elapsedUs(started: MonoTime): float =
  (getMonoTime() - started).inNanoseconds.float / 1_000.0

proc benchmark[T](rules: ValidationRules[T]; value: T; count: int): float =
  var accepted = 0
  let started = getMonoTime()
  for _ in 0 ..< count:
    if rules.validate(value).isValid:
      inc accepted
  result = elapsedUs(started) / count.float
  doAssert accepted == count

proc benchmarkDependencyDispatch(unrelatedNodes, count: int): float =
  let ui = initUiRoot()
  let target = ui.box(code = "validation-benchmark-target")
  for _ in 0 ..< unrelatedNodes:
    discard ui.box()
  let source = initValidationValue("source")
  var refreshes = 0
  ui.registerValidationDependency(
    source.identity,
    target.nodeId,
    proc() = inc refreshes
  )

  let started = getMonoTime()
  for _ in 0 ..< count:
    ui.notifyValidationDependencies(source.identity)
  result = elapsedUs(started) / count.float
  doAssert refreshes == count

proc main() =
  let stringRules =
    validationRules[string]()
      .required()
      .minLength(3)
      .maxLength(64)
      .startsWith("account-")
      .endsWith("-active")
  let regexRules = validationRules[string]().matches(
    compileRegex("^account-[a-z0-9]+-active$")
  )
  let value = "account-user42-active"

  discard benchmark(stringRules, value, 1_000)
  discard benchmark(regexRules, value, 1_000)
  let stringSmall = benchmark(stringRules, value, 10_000)
  let stringLarge = benchmark(stringRules, value, 100_000)
  let regexSmall = benchmark(regexRules, value, 10_000)
  let regexLarge = benchmark(regexRules, value, 100_000)
  let dependencySmallTree = benchmarkDependencyDispatch(100, 100_000)
  let dependencyLargeTree = benchmarkDependencyDispatch(10_000, 100_000)

  echo "CBSS validation benchmark (release, ARC)"
  echo "workload\t10k us/op\t100k us/op"
  echo &"typed descriptors\t{stringSmall:.3f}\t{stringLarge:.3f}"
  echo &"compiled regex\t{regexSmall:.3f}\t{regexLarge:.3f}"
  echo &"one dependant (100 vs 10k tree)\t{dependencySmallTree:.3f}\t{dependencyLargeTree:.3f}"

  doAssert stringLarge <= stringSmall * 4.0 + 0.25,
    "typed validation scaled superlinearly"
  doAssert regexLarge <= regexSmall * 4.0 + 0.25,
    "compiled-regex validation scaled superlinearly"
  doAssert dependencyLargeTree <= dependencySmallTree * 4.0 + 0.25,
    "dependency dispatch scaled with unrelated tree size"

when isMainModule:
  main()
