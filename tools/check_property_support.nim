import std/[os, sets, strutils, tables]

import clay_board_style_system/core/registry
import clay_board_style_system/generated/default_properties

const
  allowedStatuses = ["Runtime", "Computed", "Metadata", "Planned", "No plan"]
  priorityBands = ["P0", "P1", "P2", "P3", "P4", "P5", "P6"]

proc fail(message: string) {.noreturn.} =
  stderr.writeLine("Property support check failed: " & message)
  quit(QuitFailure)

proc tableCells(line: string): seq[string] =
  if not line.startsWith("|") or not line.endsWith("|"):
    return
  let parts = line.split('|')
  if parts.len < 3:
    return
  for index in 1 ..< parts.high:
    result.add(parts[index].strip())

proc codeValue(value: string): string =
  if value.len >= 2 and value[0] == '`' and value[^1] == '`':
    value[1 .. ^2]
  else:
    ""

proc parseCount(value, context: string): int =
  try:
    parseInt(value)
  except ValueError:
    fail(context & " has a non-integer count: " & value)

proc expectUnique(table: var Table[string, string]; name, value,
    context: string) =
  if table.hasKey(name):
    fail(context & " contains duplicate entry `" & name & "`")
  table[name] = value

proc readSupportMatrix(
    path: string;
    inventory, extensions, initial: var Table[string, string];
    summary: var Table[string, int]
) =
  var section = ""
  for line in readFile(path).splitLines():
    if line.startsWith("## "):
      section = line[3 .. ^1]
      continue

    let cells = tableCells(line)
    if cells.len < 2 or cells[0] in ["Property", "Status"] or
        cells[0].startsWith("---"):
      continue

    case section
    of "Summary":
      if cells.len >= 2 and
          (cells[0] in allowedStatuses or
           cells[0] in ["Target properties", "Total MDN entries"]):
        summary[cells[0]] = parseCount(cells[1], "support summary " & cells[0])
    of "Initial Implementation Properties", "CBSS-Specific Extensions",
        "Full Property Inventory":
      let name = codeValue(cells[0])
      if name.len == 0:
        continue
      let status = cells[1]
      if status notin allowedStatuses:
        fail("`" & name & "` has unknown status `" & status & "`")
      case section
      of "Initial Implementation Properties":
        initial.expectUnique(name, status, section)
      of "CBSS-Specific Extensions":
        extensions.expectUnique(name, status, section)
      else:
        inventory.expectUnique(name, status, section)
    else:
      discard

proc readImplementationOrder(
    path: string;
    ranked: var Table[string, string];
    bandSummary, statusSummary: var Table[string, int]
) =
  var section = ""
  var expectedRank = 1
  for line in readFile(path).splitLines():
    if line.startsWith("## "):
      section = line[3 .. ^1]
      continue

    let cells = tableCells(line)
    if cells.len < 2 or cells[0] in ["Band", "Rank"] or
        cells[0].startsWith("---"):
      continue

    case section
    of "Priority Bands":
      if cells[0] in priorityBands:
        bandSummary[cells[0]] = parseCount(cells[^1], "priority band " & cells[0])
      elif cells[0] in ["Total target", "Runtime", "Computed", "Metadata",
          "Remaining planned"]:
        statusSummary[cells[0]] = parseCount(cells[^1], "priority summary " &
            cells[0])
    of "Ranked Properties":
      if cells.len < 3:
        continue
      let rank = parseCount(cells[0], "ranked property")
      if rank != expectedRank:
        fail("rank sequence expected " & $expectedRank & " but found " & $rank)
      inc expectedRank
      let name = codeValue(cells[1])
      let band = cells[2]
      if name.len == 0 or band notin priorityBands:
        fail("invalid ranked property row at rank " & $rank)
      ranked.expectUnique(name, band, "ranked property table")
    else:
      discard

proc requireCount(summary: Table[string, int]; key: string; actual: int) =
  if not summary.hasKey(key):
    fail("summary is missing `" & key & "`")
  if summary[key] != actual:
    fail("summary `" & key & "` says " & $summary[key] &
      " but the table contains " & $actual)

proc main() =
  let repoRoot = currentSourcePath().parentDir().parentDir()
  var inventory, extensions, initial, ranked: Table[string, string]
  var summary, bandSummary, orderSummary: Table[string, int]

  readSupportMatrix(
    repoRoot / "docs" / "css-property-support.md",
    inventory,
    extensions,
    initial,
    summary
  )
  readImplementationOrder(
    repoRoot / "docs" / "css-property-implementation-order.md",
    ranked,
    bandSummary,
    orderSummary
  )

  var statusCounts: CountTable[string]
  var target = initHashSet[string]()
  for name, status in inventory:
    statusCounts.inc(status)
    if status != "No plan":
      target.incl(name)

  if inventory.len != 665:
    fail("full MDN inventory must contain 665 unique properties, found " &
        $inventory.len)
  for status in allowedStatuses:
    summary.requireCount(status, statusCounts[status])
  summary.requireCount("Target properties", target.len)
  summary.requireCount("Total MDN entries", inventory.len)

  for name, status in initial:
    if not inventory.hasKey(name):
      fail("initial property `" & name & "` is missing from the full inventory")
    if inventory[name] != status:
      fail("initial property `" & name & "` disagrees with the full inventory")
  if initial.len != 72:
    fail("initial convenience table must contain 72 unique properties, found " &
      $initial.len)

  if ranked.len != target.len:
    fail("ranked table contains " & $ranked.len &
      " properties but the implementation target contains " & $target.len)
  for name in target:
    if not ranked.hasKey(name):
      fail("target property `" & name & "` is missing from the ranked table")
  for name in ranked.keys:
    if name notin target:
      fail("ranked property `" & name & "` is outside the implementation target")

  var actualBandCounts: CountTable[string]
  for band in ranked.values:
    actualBandCounts.inc(band)
  for band in priorityBands:
    bandSummary.requireCount(band, actualBandCounts[band])
  orderSummary.requireCount("Total target", target.len)
  orderSummary.requireCount("Runtime", statusCounts["Runtime"])
  orderSummary.requireCount("Computed", statusCounts["Computed"])
  orderSummary.requireCount("Metadata", statusCounts["Metadata"])
  orderSummary.requireCount("Remaining planned", statusCounts["Planned"])

  let registry = defaultProperties()
  var documentedRegistry = target
  for name, status in extensions:
    if status == "No plan" or status == "Planned":
      fail("CBSS extension `" & name & "` must be accepted by the registry")
    documentedRegistry.incl(name)

  if registry.properties.len != documentedRegistry.len:
    fail("default registry contains " & $registry.properties.len &
      " properties but documentation declares " & $documentedRegistry.len)
  for name in documentedRegistry:
    if not registry.hasProperty(name):
      fail("documented property `" & name & "` is missing from the default registry")
  for name in registry.properties.keys:
    if name notin documentedRegistry:
      fail("registered property `" & name & "` is absent from the support matrix")

  let runtimeCount = statusCounts["Runtime"]
  let computedCount = statusCounts["Computed"]
  echo "Property support matrix is consistent."
  echo "  MDN inventory: " & $inventory.len
  echo "  Current target: " & $target.len
  echo "  Runtime: " & $runtimeCount
  echo "  Computed: " & $computedCount
  echo "  Metadata: " & $statusCounts["Metadata"]
  echo "  Planned: " & $statusCounts["Planned"]
  echo "  No plan: " & $statusCounts["No plan"]
  echo "  CBSS extensions: " & $extensions.len
  echo "  Runtime completion: " & formatFloat(
    runtimeCount.float / target.len.float * 100.0,
    ffDecimal,
    1
  ) & "%"
  echo "  Runtime or computed: " & formatFloat(
    (runtimeCount + computedCount).float / target.len.float * 100.0,
    ffDecimal,
    1
  ) & "%"

when isMainModule:
  main()
