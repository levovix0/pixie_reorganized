import std/[os, strutils]
import ./[common, fonts]
import ./fontformats/[opentype, svgfont]


proc parseOtf*(buf: string): Typeface {.raises: [PixieError].} =
  result = Typeface()
  result.opentype = parseOpenType(buf)

proc parseTtf*(buf: string): Typeface {.raises: [PixieError].} =
  parseOtf(buf)

proc parseSvgFont*(buf: string): Typeface {.raises: [PixieError].} =
  result = Typeface()
  result.svgFont = svgfont.parseSvgFont(buf)


proc readTypeface*(filePath: string): Typeface {.raises: [PixieError].} =
  ## Loads a typeface from a file.
  try:
    result =
      case splitFile(filePath).ext.toLowerAscii():
        of ".ttf":
          parseTtf(readFile(filePath))
        of ".otf":
          parseOtf(readFile(filePath))
        of ".svg":
          parseSvgFont(readFile(filePath))
        else:
          raise newException(PixieError, "Unsupported font format")
  except IOError as e:
    raise newException(PixieError, e.msg, e)

  result.filePath = filePath

proc readTypefaces*(filePath: string): seq[Typeface] {.raises: [PixieError].} =
  ## Loads a OpenType Collection (.ttc).
  try:
    for opentype in parseOpenTypeCollection(readFile(filePath)):
      let typeface = Typeface()
      typeface.opentype = opentype
      result.add(typeface)
  except IOError as e:
    raise newException(PixieError, e.msg, e)

proc readFont*(filePath: string): Font {.raises: [PixieError].} =
  ## Loads a font from a file.
  newFont(readTypeface(filePath))
