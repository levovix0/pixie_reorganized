import pkg/[vmath]
import ../[common, paths, fonts]
import ./[pathpoly, paths]


proc textUber(
  target: Image,
  arrangement: Arrangement,
  transform = mat3(),
  strokeWidth: float32 = 1.0,
  lineCap = ButtCap,
  lineJoin = MiterJoin,
  miterLimit = defaultMiterLimit,
  dashes: seq[float32] = @[],
  stroke: static[bool] = false
) =
  let spanPaths = arrangement.computePaths()
  for spanIndex in 0 ..< arrangement.spans.len:
    let path = spanPaths[spanIndex]
    when stroke:
      let font = arrangement.fonts[spanIndex]
      for paint in font.paints:
        target.strokePath(
          path,
          paint,
          transform,
          strokeWidth,
          lineCap,
          lineJoin,
          miterLimit,
          dashes
        )
    else:
      let font = arrangement.fonts[spanIndex]
      for paint in font.paints:
        target.fillPath(path, paint, transform)


proc fillText*(
  target: Image,
  arrangement: Arrangement,
  transform = mat3()
) {.inline, raises: [PixieError].} =
  ## Fills the text arrangement.
  textUber(
    target,
    arrangement,
    transform
  )

proc fillText*(
  target: Image,
  font: Font,
  text: sink string,
  transform = mat3(),
  bounds = vec2(0, 0),
  hAlign = LeftAlign,
  vAlign = TopAlign
) {.inline, raises: [PixieError].} =
  ## Typesets and fills the text. Optional parameters:
  ## transform: translation or matrix to apply
  ## bounds: width determines wrapping and hAlign, height for vAlign
  ## hAlign: horizontal alignment of the text
  ## vAlign: vertical alignment of the text
  fillText(target, font.typeset(text, bounds, hAlign, vAlign), transform)

proc strokeText*(
  target: Image,
  arrangement: Arrangement,
  transform = mat3(),
  strokeWidth: float32 = 1.0,
  lineCap = ButtCap,
  lineJoin = MiterJoin,
  miterLimit = defaultMiterLimit,
  dashes: seq[float32] = @[]
) {.inline, raises: [PixieError].} =
  ## Strokes the text arrangement.
  textUber(
    target,
    arrangement,
    transform,
    strokeWidth,
    lineCap,
    lineJoin,
    miterLimit,
    dashes,
    true
  )

proc strokeText*(
  target: Image,
  font: Font,
  text: sink string,
  transform = mat3(),
  strokeWidth: float32 = 1.0,
  bounds = vec2(0, 0),
  hAlign = LeftAlign,
  vAlign = TopAlign,
  lineCap = ButtCap,
  lineJoin = MiterJoin,
  miterLimit = defaultMiterLimit,
  dashes: seq[float32] = @[]
) {.inline, raises: [PixieError].} =
  ## Typesets and strokes the text. Optional parameters:
  ## transform: translation or matrix to apply
  ## bounds: width determines wrapping and hAlign, height for vAlign
  ## hAlign: horizontal alignment of the text
  ## vAlign: vertical alignment of the text
  ## lineCap: stroke line cap shape
  ## lineJoin: stroke line join shape
  strokeText(
    target,
    font.typeset(text, bounds, hAlign, vAlign),
    transform,
    strokeWidth,
    lineCap,
    lineJoin,
    miterLimit,
    dashes
  )
