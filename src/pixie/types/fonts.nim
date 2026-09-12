import std/[unicode]
import pkg/[vmath, bumpy]
import ./[svgfont, opentype, paints]

type
  Typeface* = ref object
    opentype*: OpenType
    svgFont*: SvgFont
    filePath*: string
    fallbacks*: seq[Typeface]

  Font* = ref object
    typeface*: Typeface
    size*: float32              ## Font size in pixels.
    lineHeight*: float32 ## The line height in pixels or autoLineHeight for the font's default line height.
    paints*: seq[Paint]
    textCase*: TextCase
    underline*: bool            ## Apply an underline.
    strikethrough*: bool        ## Apply a strikethrough.
    noKerningAdjustments*: bool ## Optionally disable kerning pair adjustments

  Span* = ref object
    text*: string
    font*: Font

  Arrangement* = ref object
    lines*: seq[(int, int)]    ## The (start, stop) of the lines of text.
    spans*: seq[(int, int)]    ## The (start, stop) of the spans in the text.
    fonts*: seq[Font]          ## The font for each span.
    runes*: seq[Rune]          ## The runes of the text.
    positions*: seq[Vec2]      ## The positions of the glyphs for each rune.
    selectionRects*: seq[Rect] ## The selection rects for each glyph.

  HorizontalAlignment* = enum
    LeftAlign
    CenterAlign
    RightAlign

  VerticalAlignment* = enum
    TopAlign
    MiddleAlign
    BottomAlign

  TextCase* = enum
    NormalCase
    UpperCase
    LowerCase
    TitleCase
    # tcSmallCaps
    # tcSmallCapsForced
