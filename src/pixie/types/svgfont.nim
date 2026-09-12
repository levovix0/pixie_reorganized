import std/[tables, unicode]
import ./[paths]

type
  SvgFont* = ref object
    unitsPerEm*, ascent*, descent*: float32
    advances*: Table[Rune, float32]
    glyphPaths*: Table[Rune, Path]
    kerningPairs*: Table[(Rune, Rune), float32]
    missingGlyphAdvance*: float32
    missingGlyphPath*: Path


proc getGlyphPath*(svgFont: SvgFont, rune: Rune): Path {.raises: [].} =
  svgFont.glyphPaths.getOrDefault(rune, svgFont.missingGlyphPath)

proc hasGlyph*(svgFont: SvgFont, rune: Rune): bool {.inline.} =
  rune in svgFont.glyphPaths

proc getAdvance*(svgFont: SvgFont, rune: Rune): float32 {.raises: [].} =
  svgFont.advances.getOrDefault(rune, svgFont.missingGlyphAdvance)

proc getKerningAdjustment*(
  svgFont: SvgFont, left, right: Rune
): float32 {.raises: [].} =
  let pair = (left, right)
  result = svgFont.kerningPairs.getOrDefault(pair, 0)
