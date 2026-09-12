import pkg/[vmath]

type
  WindingRule* = enum
    ## Winding rules.
    NonZero
    EvenOdd

  LineCap* = enum
    ## Line cap type for strokes.
    ButtCap, RoundCap, SquareCap

  LineJoin* = enum
    ## Line join type for strokes.
    MiterJoin, RoundJoin, BevelJoin

  PathCommandKind* = enum
    ## Type of path commands
    Close,
    Move, Line, HLine, VLine, Cubic, SCubic, Quad, TQuad, Arc,
    RMove, RLine, RHLine, RVLine, RCubic, RSCubic, RQuad, RTQuad, RArc

  Path* = ref object
    ## Used to hold paths and create paths.
    commands*: seq[float32]
    start*, at*: Vec2 # Maintained by moveTo, lineTo, etc. Used by arcTo.

  SomePath* = Path | string

