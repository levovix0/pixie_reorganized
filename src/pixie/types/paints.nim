import pkg/[chroma, vmath]
import ./[common]

type
  PaintKind* = enum
    SolidPaint
    ImagePaint
    TiledImagePaint
    LinearGradientPaint
    RadialGradientPaint
    AngularGradientPaint

  Paint* = ref object
    ## Paint used to fill paths.
    kind*: PaintKind
    blendMode*: BlendMode               ## Blend mode.
    opacity*: float32
    # SolidPaint
    color*: Color                       ## Color to fill with.
    # ImagePaint, TiledImagePaint:
    image*: Image                       ## Image to fill with.
    imageMat*: Mat3                     ## Matrix of the filled image.
    # LinearGradientPaint, RadialGradientPaint, AngularGradientPaint:
    gradientHandlePositions*: seq[Vec2] ## Gradient positions (image space).
    gradientStops*: seq[ColorStop]      ## Color stops (gradient space).

  ColorStop* = object
    ## Color stop on a gradient curve.
    color*: Color      ## Color of the stop.
    position*: float32 ## Gradient stop position 0..1.

  SomePaint* = string | Paint | SomeColor
