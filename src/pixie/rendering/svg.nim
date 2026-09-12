import std/[strutils, tables]
import pkg/[vmath, chroma]
import ../fileformats/[svg]
import ../[common, images, paints, internal]
import ./[paths]


proc newImage*(svg: Svg): Image {.raises: [PixieError].} =
  ## Render SVG and return the image.
  result = newImage(svg.width, svg.height)

  try:
    var blendMode = OverwriteBlend # Start as overwrite
    for (path, props) in svg.elements:
      if props.display and props.opacity > 0:
        if props.fill != "none":
          var paint: Paint
          if props.fill.startsWith("url("):
            let closingParen = props.fill.find(")", 5)
            if closingParen == -1:
              raise newException(PixieError, "Malformed fill: " & props.fill)
            let id = props.fill[5 .. closingParen - 1]
            if id in svg.linearGradients:
              let linearGradient = svg.linearGradients[id]
              paint = newPaint(LinearGradientPaint)
              paint.gradientHandlePositions = @[
                props.transform * vec2(linearGradient.x1, linearGradient.y1),
                props.transform * vec2(linearGradient.x2, linearGradient.y2)
              ]
              paint.gradientStops = linearGradient.stops
            else:
              raise newException(PixieError, "Missing SVG resource " & id)
          else:
            paint = parseHtmlColor(props.fill).rgbx

          paint.opacity = props.fillOpacity * props.opacity
          paint.blendMode = blendMode

          result.fillPath(path, paint, props.transform, props.fillRule)

        blendMode = NormalBlend # Switch to normal when compositing multiple paths

        if props.stroke != rgbx(0, 0, 0, 0) and props.strokeWidth > 0:
          let paint = props.stroke.copy()
          paint.color.a *= (props.opacity * props.strokeOpacity)
          result.strokePath(
            path,
            paint,
            props.transform,
            props.strokeWidth,
            props.strokeLineCap,
            props.strokeLineJoin,
            miterLimit = props.strokeMiterLimit,
            dashes = props.strokeDashArray
          )
  except PixieError as e:
    raise e
  except:
    raise currentExceptionAsPixieError()
