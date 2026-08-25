import std/[options, unicode]

import ../core/computed_style

type
  DisplayTextTransform* = object
    text*: string
    sourceBoundaries: seq[int]
    displayBoundaries: seq[int]

proc isAsciiDigit(value: int32): bool =
  value >= int32('0') and value <= int32('9')

proc isCombiningMark(value: int32): bool =
  (value >= 0x0300 and value <= 0x036F) or
    (value >= 0x1AB0 and value <= 0x1AFF) or
    (value >= 0x1DC0 and value <= 0x1DFF) or
    (value >= 0x20D0 and value <= 0x20FF) or
    (value >= 0xFE20 and value <= 0xFE2F)

proc keepsCapitalizationWord(rune: Rune): bool =
  let value = rune.int32
  rune.isAlpha or value.isAsciiDigit or value.isCombiningMark or
    value == 0x0027 or value == 0x2019

proc transformedRune(
    rune: Rune;
    transform: TextTransform;
    insideWord: var bool
): Rune =
  case transform
  of ttNone:
    result = rune
  of ttUppercase:
    result = rune.toUpper
  of ttLowercase:
    result = rune.toLower
  of ttCapitalize:
    if rune.isAlpha:
      result = if insideWord: rune else: rune.toUpper
      insideWord = true
    else:
      result = rune
      if not rune.keepsCapitalizationWord:
        insideWord = false

proc displayTextTransform*(
    source: string;
    style: ComputedTextStyle
): DisplayTextTransform =
  let transform = style.textTransform.get(ttNone)
  if transform == ttNone or source.len == 0:
    result.text = source
    return

  result.sourceBoundaries = @[0]
  result.displayBoundaries = @[0]
  var sourceIndex = 0
  var insideWord = false
  while sourceIndex < source.len:
    let rune = source.runeAt(sourceIndex)
    let sourceLength = source.runeLenAt(sourceIndex)
    result.text.add $transformedRune(rune, transform, insideWord)
    sourceIndex += sourceLength
    result.sourceBoundaries.add sourceIndex
    result.displayBoundaries.add result.text.len

proc boundaryIndexAtOrBefore(boundaries: openArray[int]; value: int): int =
  var low = 0
  var high = boundaries.len
  while low < high:
    let middle = low + (high - low) div 2
    if boundaries[middle] <= value:
      low = middle + 1
    else:
      high = middle
  max(0, low - 1)

proc displayByteIndex*(mapping: DisplayTextTransform; sourceByteIndex: int): int =
  if mapping.sourceBoundaries.len == 0:
    return min(max(0, sourceByteIndex), mapping.text.len)
  let sourceEnd = mapping.sourceBoundaries[^1]
  let bounded = min(max(0, sourceByteIndex), sourceEnd)
  mapping.displayBoundaries[
    boundaryIndexAtOrBefore(mapping.sourceBoundaries, bounded)
  ]

proc sourceByteIndex*(mapping: DisplayTextTransform; displayByteIndex: int): int =
  if mapping.displayBoundaries.len == 0:
    return min(max(0, displayByteIndex), mapping.text.len)
  let displayEnd = mapping.displayBoundaries[^1]
  let bounded = min(max(0, displayByteIndex), displayEnd)
  mapping.sourceBoundaries[
    boundaryIndexAtOrBefore(mapping.displayBoundaries, bounded)
  ]
