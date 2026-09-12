import pkg/[chroma, vmath]
import ./[common]
import ./types/paints as paintsTypes

export paintsTypes


proc newPaint*(kind: PaintKind): Paint {.raises: [].} =
  ## Create a new Paint.
  result = Paint(kind: kind, opacity: 1, imageMat: mat3())

proc copy*(paint: Paint): Paint {.raises: [].} =
  ## Create a new Paint with the same properties.
  result = newPaint(paint.kind)
  result.blendMode = paint.blendMode
  result.opacity = paint.opacity
  result.color = paint.color
  result.image = paint.image
  result.imageMat = paint.imageMat
  result.gradientHandlePositions = paint.gradientHandlePositions
  result.gradientStops = paint.gradientStops

converter parseSomePaint*(paint: SomePaint): Paint {.inline.} =
  ## Given SomePaint, parse it in different ways.
  when type(paint) is string:
    result = newPaint(SolidPaint)
    try:
      result.color = parseHtmlColor(paint)
    except:
      raise newException(PixieError, "Unable to parse color " & paint)
  elif type(paint) is SomeColor:
    result = newPaint(SolidPaint)
    when type(paint) is Color:
      result.color = paint
    else:
      result.color = paint.color()
  elif type(paint) is Paint:
    paint

proc colorStop*(color: Color, position: float32): ColorStop =
  ColorStop(color: color, position: position)

