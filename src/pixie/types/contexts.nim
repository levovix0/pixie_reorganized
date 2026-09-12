import std/[tables]
import pkg/[vmath]
import ./[common, paints, paths, fonts]

type
  BaselineAlignment* = enum
    TopBaseline
    HangingBaseline
    MiddleBaseline
    AlphabeticBaseline
    IdeographicBaseline
    BottomBaseline

  Context* = ref object
    image*: Image
    fillStyle*, strokeStyle*: Paint
    globalAlpha*: float32
    lineWidth*: float32
    miterLimit*: float32
    lineCap*: LineCap
    lineJoin*: LineJoin
    font*: string ## File path to a .ttf or .otf file.
    fontSize*: float32
    textAlign*: HorizontalAlignment
    textBaseline*: BaselineAlignment
    lineDash*: seq[float32]
    path*: Path
    mat*: Mat3
    mask*, layer*: Image
    stateStack*: seq[ContextState]
    typefaces*: Table[string, Typeface]

  ContextState* = object
    fillStyle*, strokeStyle*: Paint
    globalAlpha*: float32
    lineWidth*: float32
    miterLimit*: float32
    lineCap*: LineCap
    lineJoin*: LineJoin
    font*: string
    fontSize*: float32
    textAlign*: HorizontalAlignment
    lineDash*: seq[float32]
    mat*: Mat3
    mask*, layer*: Image

  TextMetrics* = object
    width*: float32
