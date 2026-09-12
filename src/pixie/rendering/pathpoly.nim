import std/[fenv]
import pkg/[bumpy, chroma, vmath]
import ../[common, paths]

const
  pixelErrorMargin*: float32 = 0.2


when defined(release):
  {.push checks: off.}


proc commandsToShapes*(
  path: Path, closeSubpaths: bool, pixelScale: float32
): seq[Polygon] =
  ## Converts SVG-like commands to sequences of vectors.
  var
    start, at: Vec2
    shape: Polygon

  # Some commands use data from the previous command
  var
    prevCommandKind = Move
    prevCtrl, prevCtrl2: Vec2

  let errorMarginSq = pow(pixelErrorMargin / pixelScale, 2)

  proc addSegment(shape: var Polygon, at, to: Vec2) =
    # Don't add any 0 length lines
    if at - to != vec2(0, 0):
      # Don't double up points
      if shape.len == 0 or shape[^1] != at:
        shape.add(at)
      shape.add(to)

  proc addCubic(shape: var Polygon, at, ctrl1, ctrl2, to: Vec2) =
    ## Adds cubic segments to shape.
    proc compute(at, ctrl1, ctrl2, to: Vec2, t: float32): Vec2 {.inline.} =
      let
        t2 = t*t
        t3 = t2*t
      at * (-t3 + 3*t2 - 3*t + 1) +
      ctrl1 * (3*t3 - 6*t2 + 3*t) +
      ctrl2 * (-3*t3 + 3*t2) +
      to * (t3)

    proc computeDeriv(at, ctrl1, ctrl2, to: Vec2, t: float32): Vec2 {.inline.} =
      let t2 = t*t
      at * (-3*t2 + 6*t - 3) +
      ctrl1 * (9*t2 - 12*t + 3) +
      ctrl2 * (-9*t2 + 6*t) +
      to * (3 * t2)

    var
      t: float32       # Where we are at on the curve from [0, 1]
      step = 1.float32 # How far we want to try to move along the curve
      prev = at
      next = compute(at, ctrl1, ctrl2, to, t + step)
      halfway = compute(at, ctrl1, ctrl2, to, t + step / 2)
    while true:
      if step <= epsilon(float32):
        raise newException(PixieError, "Unable to discretize cubic")
      let
        midpoint = (prev + next) / 2
        lineTangent = midpoint - prev
        curveTangent = computeDeriv(at, ctrl1, ctrl2, to, t + step / 2)
        curveTangentScaled = curveTangent.normalize() * lineTangent.length()
        error = (midpoint - halfway).lengthSq
        errorTangent = (lineTangent - curveTangentScaled).lengthSq
      if error + errorTangent > errorMarginSq:
        next = halfway
        halfway = compute(at, ctrl1, ctrl2, to, t + step / 4)
        step /= 2
      else:
        shape.addSegment(prev, next)
        t += step
        if t == 1:
          break
        prev = next
        step = min(step * 2, 1 - t) # Optimistically attempt larger steps
        next = compute(at, ctrl1, ctrl2, to, t + step)
        halfway = compute(at, ctrl1, ctrl2, to, t + step / 2)

  proc addQuadratic(shape: var Polygon, at, ctrl, to: Vec2) =
    ## Adds quadratic segments to shape.
    proc compute(at, ctrl, to: Vec2, t: float32): Vec2 {.inline.} =
      let t2 = t*t
      at * (t2 - 2*t + 1) +
      ctrl * (-2*t2 + 2*t) +
      to * t2

    var
      t: float32       # Where we are at on the curve from [0, 1]
      step = 1.float32 # How far we want to try to move along the curve
      prev = at
      next = compute(at, ctrl, to, t + step)
      halfway = compute(at, ctrl, to, t + step / 2)
      halfStepping = false
    while true:
      if step <= epsilon(float32):
        raise newException(PixieError, "Unable to discretize quadratic")
      let
        midpoint = (prev + next) / 2
        error = (midpoint - halfway).lengthSq
      if error > errorMarginSq:
        next = halfway
        halfway = compute(at, ctrl, to, t + step / 4)
        halfStepping = true
        step /= 2
      else:
        shape.addSegment(prev, next)
        t += step
        if t == 1:
          break
        prev = next
        if halfStepping:
          step = min(step, 1 - t)
        else:
          step = min(step * 2, 1 - t) # Optimistically attempt larger steps
        next = compute(at, ctrl, to, t + step)
        halfway = compute(at, ctrl, to, t + step / 2)

  proc addArc(
    shape: var Polygon,
    at, radii: Vec2,
    rotation: float32,
    large, sweep: bool,
    to: Vec2
  ) =
    ## Adds arc segments to shape.
    type ArcParams = object
      radii: Vec2
      rotMat: Mat3
      center: Vec2
      theta, delta: float32

    proc endpointToCenterArcParams(
      at, radii: Vec2, rotation: float32, large, sweep: bool, to: Vec2
    ): ArcParams =
      var
        radii = vec2(abs(radii.x), abs(radii.y))
        radiiSq = vec2(radii.x * radii.x, radii.y * radii.y)

      let
        radians: float32 = rotation / 180 * PI
        d = vec2((at.x - to.x) / 2.0, (at.y - to.y) / 2.0)
        p = vec2(
          cos(radians) * d.x + sin(radians) * d.y,
          -sin(radians) * d.x + cos(radians) * d.y
        )
        pSq = vec2(p.x * p.x, p.y * p.y)

      let cr = pSq.x / radiiSq.x + pSq.y / radiiSq.y
      if cr > 1:
        radii *= sqrt(cr)
        radiiSq = vec2(radii.x * radii.x, radii.y * radii.y)

      let
        dq = radiiSq.x * pSq.y + radiiSq.y * pSq.x
        pq = (radiiSq.x * radiiSq.y - dq) / dq

      var q = sqrt(max(0, pq))
      if large == sweep:
        q = -q

      proc svgAngle(u, v: Vec2): float32 =
        let
          dot = dot(u, v)
          len = length(u) * length(v)
        result = arccos(clamp(dot / len, -1, 1))
        if (u.x * v.y - u.y * v.x) < 0:
          result = -result

      let
        cp = vec2(q * radii.x * p.y / radii.y, -q * radii.y * p.x / radii.x)
        center = vec2(
          cos(radians) * cp.x - sin(radians) * cp.y + (at.x + to.x) / 2,
          sin(radians) * cp.x + cos(radians) * cp.y + (at.y + to.y) / 2
        )
        theta = svgAngle(vec2(1, 0), vec2((p.x-cp.x) / radii.x, (p.y - cp.y) / radii.y))

      var delta = svgAngle(
          vec2((p.x - cp.x) / radii.x, (p.y - cp.y) / radii.y),
          vec2((-p.x - cp.x) / radii.x, (-p.y - cp.y) / radii.y)
        )
      delta = delta mod (PI * 2)

      if sweep and delta < 0:
        delta += 2 * PI
      elif not sweep and delta > 0:
        delta -= 2 * PI

      # Normalize the delta
      while delta > PI * 2:
        delta -= PI * 2
      while delta < -PI * 2:
        delta += PI * 2

      ArcParams(
        radii: radii,
        rotMat: rotate(radians),
        center: center,
        theta: theta,
        delta: delta
      )

    proc compute(arc: ArcParams, a: float32): Vec2 =
      result = vec2(cos(a) * arc.radii.x, sin(a) * arc.radii.y)
      result = arc.rotMat * result + arc.center

    let arc = endpointToCenterArcParams(at, radii, rotation, large, sweep, to)

    var
      t: float32       # Where we are at on the curve from [0, 1]
      step = 1.float32 # How far we want to try to move along the curve
      prev = at
    while t != 1:
      if step <= epsilon(float32):
        raise newException(PixieError, "Unable to discretize arc")
      let
        aPrev = arc.theta + arc.delta * t
        a = arc.theta + arc.delta * (t + step)
        next = arc.compute(a)
        halfway = arc.compute(aPrev + (a - aPrev) / 2)
        midpoint = (prev + next) / 2
        error = (midpoint - halfway).lengthSq
      if error > errorMarginSq:
        let
          quarterway = arc.compute(aPrev + (a - aPrev) / 4)
          midpoint = (prev + halfway) / 2
          halfwayError = (midpoint - quarterway).lengthSq
        if halfwayError < errorMarginSq:
          shape.addSegment(prev, halfway)
          prev = halfway
          t += step / 2
          step = min(step / 2, 1 - t) # Assume next steps hould be the same size
        else:
          step = step / 4 # We know a half-step is too big
      else:
        shape.addSegment(prev, next)
        prev = next
        t += step
        step = min(step * 2, 1 - t) # Optimistically attempt larger steps

  var i: int
  while i < path.commands.len:
    let kind = path.commands[i].PathCommandKind
    inc i

    case kind:
    of Move:
      if shape.len > 0:
        if closeSubpaths:
          shape.addSegment(at, start)
        result.add(shape)
        shape = newSeq[Vec2]()
      at.x = path.commands[i + 0]
      at.y = path.commands[i + 1]
      start = at

    of Line:
      let to = vec2(path.commands[i + 0], path.commands[i + 1])
      shape.addSegment(at, to)
      at = to

    of HLine:
      let to = vec2(path.commands[i + 0], at.y)
      shape.addSegment(at, to)
      at = to

    of VLine:
      let to = vec2(at.x, path.commands[i + 0])
      shape.addSegment(at, to)
      at = to

    of Cubic:
      let
        ctrl1 = vec2(path.commands[i + 0], path.commands[i + 1])
        ctrl2 = vec2(path.commands[i + 2], path.commands[i + 3])
        to = vec2(path.commands[i + 4], path.commands[i + 5])
      shape.addCubic(at, ctrl1, ctrl2, to)
      at = to
      prevCtrl2 = ctrl2

    of SCubic:
      let
        ctrl2 = vec2(path.commands[i + 0], path.commands[i + 1])
        to = vec2(path.commands[i + 2], path.commands[i + 3])
      if prevCommandKind in {Cubic, SCubic, RCubic, RSCubic}:
        let ctrl1 = at * 2 - prevCtrl2
        shape.addCubic(at, ctrl1, ctrl2, to)
      else:
        shape.addCubic(at, at, ctrl2, to)
      at = to
      prevCtrl2 = ctrl2

    of Quad:
      let
        ctrl = vec2(path.commands[i + 0], path.commands[i + 1])
        to = vec2(path.commands[i + 2], path.commands[i + 3])
      shape.addQuadratic(at, ctrl, to)
      at = to
      prevCtrl = ctrl

    of TQuad:
      let
        to = vec2(path.commands[i + 0], path.commands[i + 1])
        ctrl =
          if prevCommandKind in {Quad, TQuad, RQuad, RTQuad}:
            at * 2 - prevCtrl
          else:
            at
      shape.addQuadratic(at, ctrl, to)
      at = to
      prevCtrl = ctrl

    of Arc:
      let
        radii = vec2(path.commands[i + 0], path.commands[i + 1])
        rotation = path.commands[i + 2]
        large = path.commands[i + 3] == 1
        sweep = path.commands[i + 4] == 1
        to = vec2(path.commands[i + 5], path.commands[i + 6])
      shape.addArc(at, radii, rotation, large, sweep, to)
      at = to

    of RMove:
      if shape.len > 0:
        result.add(shape)
        shape = newSeq[Vec2]()
      at.x += path.commands[i + 0]
      at.y += path.commands[i + 1]
      start = at

    of RLine:
      let to = vec2(at.x + path.commands[i + 0], at.y + path.commands[i + 1])
      shape.addSegment(at, to)
      at = to

    of RHLine:
      let to = vec2(at.x + path.commands[i + 0], at.y)
      shape.addSegment(at, to)
      at = to

    of RVLine:
      let to = vec2(at.x, at.y + path.commands[i + 0])
      shape.addSegment(at, to)
      at = to

    of RCubic:
      let
        ctrl1 = vec2(at.x + path.commands[i + 0], at.y + path.commands[i + 1])
        ctrl2 = vec2(at.x + path.commands[i + 2], at.y + path.commands[i + 3])
        to = vec2(at.x + path.commands[i + 4], at.y + path.commands[i + 5])
      shape.addCubic(at, ctrl1, ctrl2, to)
      at = to
      prevCtrl2 = ctrl2

    of RSCubic:
      let
        ctrl2 = vec2(at.x + path.commands[i + 0], at.y + path.commands[i + 1])
        to = vec2(at.x + path.commands[i + 2], at.y + path.commands[i + 3])
        ctrl1 =
          if prevCommandKind in {Cubic, SCubic, RCubic, RSCubic}:
            at * 2 - prevCtrl2
          else:
            at
      shape.addCubic(at, ctrl1, ctrl2, to)
      at = to
      prevCtrl2 = ctrl2

    of RQuad:
      let
        ctrl = vec2(at.x + path.commands[i + 0], at.y + path.commands[i + 1])
        to = vec2(at.x + path.commands[i + 2], at.y + path.commands[i + 3])
      shape.addQuadratic(at, ctrl, to)
      at = to
      prevCtrl = ctrl

    of RTQuad:
      let
        to = vec2(at.x + path.commands[i + 0], at.y + path.commands[i + 1])
        ctrl =
          if prevCommandKind in {Quad, TQuad, RQuad, RTQuad}:
            at * 2 - prevCtrl
          else:
            at
      shape.addQuadratic(at, ctrl, to)
      at = to
      prevCtrl = ctrl

    of RArc:
      let
        radii = vec2(path.commands[i + 0], path.commands[i + 1])
        rotation = path.commands[i + 2]
        large = path.commands[i + 3] == 1
        sweep = path.commands[i + 4] == 1
        to = vec2(at.x + path.commands[i + 5], at.y + path.commands[i + 6])
      shape.addArc(at, radii, rotation, large, sweep, to)
      at = to

    of Close:
      if at != start:
        shape.addSegment(at, start)
        at = start
      if shape.len > 0:
        result.add(shape)
        shape = newSeq[Vec2]()

    i += kind.parameterCount()
    prevCommandKind = kind

  if shape.len > 0:
    if closeSubpaths:
      shape.addSegment(at, start)
    result.add(shape)

proc shapesToSegments*(
  shapes: seq[Polygon],
  skipHorizontal = true
): seq[(Segment, int16)] =
  ## Converts the shapes into a set of filtered segments with winding value.

  # Quantize the segment to prevent leaks
  template quantizeY(v: Vec2): Vec2 =
    vec2(v.x, v.y.quantize(1 / 256))

  for poly in shapes:
    var
      vec1 = poly[^1].quantizeY()
      vec2: Vec2
      segment: Segment
    for i in 0 ..< poly.len:
      vec2 = poly[i].quantizeY()
      if i == 0 and vec1 == vec2:
        continue
      segment = segment(vec1, vec2)
      vec1 = vec2

      if skipHorizontal and segment.at.y == segment.to.y: # Skip horizontal
        continue
      var
        segment = segment
        winding = 1.int16
      if segment.at.y > segment.to.y:
        swap(segment.at, segment.to)
        winding = -1

      result.add((segment, winding))

proc transform*(shapes: var seq[Polygon], transform: Mat3) =
  if transform != mat3():
    for shape in shapes.mitems:
      for vec in shape.mitems:
        vec = transform * vec

proc computeBounds*(segments: seq[(Segment, int16)]): Rect =
  ## Compute the bounds of the segments.
  var
    xMin = float32.high
    xMax = float32.low
    yMin = float32.high
    yMax = float32.low
  for i, (segment, _) in segments:
    xMin = min(xMin, min(segment.at.x, segment.to.x))
    xMax = max(xMax, max(segment.at.x, segment.to.x))
    yMin = min(yMin, segment.at.y)
    yMax = max(yMax, segment.to.y)

  if xMin.isNaN() or xMax.isNaN() or yMin.isNaN() or yMax.isNaN():
    discard
  else:
    result.x = xMin
    result.y = yMin
    result.w = xMax - xMin
    result.h = yMax - yMin

proc computeBounds*(
  path: Path, transform = mat3()
): Rect {.raises: [PixieError].} =
  ## Compute the bounds of the path.
  var shapes = path.commandsToShapes(true, pixelScale(transform))
  shapes.transform(transform)
  computeBounds(shapes.shapesToSegments(skipHorizontal = false))


proc miterLimitToAngle*(limit: float32): float32 {.inline.} =
  ## Converts miter-limit-ratio to miter-limit-angle.
  arcsin(1 / limit) * 2

proc angleToMiterLimit*(angle: float32): float32 {.inline.} =
  ## Converts miter-limit-angle to miter-limit-ratio.
  1 / sin(angle / 2)

proc strokeShapes*(
  shapes: seq[Polygon],
  strokeWidth: float32,
  lineCap: LineCap,
  lineJoin: LineJoin,
  miterLimit: float32,
  dashes: seq[float32],
  pixelScale: float32
): seq[Polygon] =
  if strokeWidth <= 0:
    return

  let
    halfStroke = strokeWidth / 2
    miterAngleLimit = miterLimitToAngle(miterLimit)

  proc makeCircle(at: Vec2): Polygon =
    let path = newPath()
    path.ellipse(at, halfStroke, halfStroke)
    path.commandsToShapes(true, pixelScale)[0]

  proc makeRect(at, to: Vec2): Polygon =
    # Rectangle corners
    let
      tangent = (to - at).normalize()
      normal = vec2(tangent.y, tangent.x)
      a = vec2(
        at.x + normal.x * halfStroke,
        at.y - normal.y * halfStroke
      )
      b = vec2(
        to.x + normal.x * halfStroke,
        to.y - normal.y * halfStroke
      )
      c = vec2(
        to.x - normal.x * halfStroke,
        to.y + normal.y * halfStroke
      )
      d = vec2(
        at.x - normal.x * halfStroke,
        at.y + normal.y * halfStroke
      )

    @[a, b, c, d, a]

  proc addJoin(shape: var seq[Polygon], prevPos, pos, nextPos: Vec2) =
    let minArea = pixelErrorMargin / pixelScale

    if lineJoin == RoundJoin:
      let area = PI.float32 * halfStroke * halfStroke
      if area > minArea:
        shape.add makeCircle(pos)
      return

    let angle = fixAngle(angle(nextPos - pos) - angle(prevPos - pos))
    if abs(abs(angle) - PI) > epsilon:
      var
        a = (pos - prevPos).normalize() * halfStroke
        b = (pos - nextPos).normalize() * halfStroke
      if angle >= 0:
        a = vec2(-a.y, a.x)
        b = vec2(b.y, -b.x)
      else:
        a = vec2(a.y, -a.x)
        b = vec2(-b.y, b.x)

      var lineJoin = lineJoin
      if lineJoin == MiterJoin and abs(angle) < miterAngleLimit:
        lineJoin = BevelJoin

      case lineJoin:
      of MiterJoin:
        let
          la = line(prevPos + a, pos + a)
          lb = line(nextPos + b, pos + b)
        var at: Vec2
        if la.intersects(lb, at):
          let
            bisectorLengthSq = (at - pos).lengthSq
            areaSq = 0.25.float32 * (
              a.lengthSq * bisectorLengthSq + b.lengthSq * bisectorLengthSq
            )
          if areaSq > (minArea * minArea):
            shape.add @[pos + a, at, pos + b, pos, pos + a]

      of BevelJoin:
        let areaSq = 0.25.float32 * a.lengthSq * b.lengthSq
        if areaSq > (minArea * minArea):
          shape.add @[a + pos, b + pos, pos, a + pos]

      of RoundJoin:
        discard # Handled above, skipping angle calculation

  for shape in shapes:
    var shapeStroke: seq[Polygon]

    if shape[0] != shape[^1]:
      # This shape does not end at the same point it starts so draw the
      # first line cap.
      case lineCap:
      of ButtCap:
        discard
      of RoundCap:
        shapeStroke.add(makeCircle(shape[0]))
      of SquareCap:
        let tangent = (shape[1] - shape[0]).normalize()
        shapeStroke.add(makeRect(
          shape[0] - tangent * halfStroke,
          shape[0]
        ))

    var dashes = dashes
    if dashes.len mod 2 != 0:
      dashes.add(dashes)
    # Make sure gaps and dashes are more then zero, otherwise it will hang.
    for d in dashes:
      if d <= 0.0:
        raise newException(PixieError, "Invalid line dash value")

    for i in 1 ..< shape.len:
      let
        pos = shape[i]
        prevPos = shape[i - 1]

      if dashes.len > 0:
        var distance = dist(prevPos, pos)
        let dir = dir(pos, prevPos)
        var currPos = prevPos
        block dashLoop:
          while true:
            for i, d in dashes:
              if i mod 2 == 0:
                let d = min(distance, d)
                shapeStroke.add(makeRect(currPos, currPos + dir * d))
              currPos += dir * d
              distance -= d
              if distance <= 0:
                break dashLoop
      else:
        shapeStroke.add(makeRect(prevPos, pos))

      # If we need a line join
      if i < shape.len - 1:
        shapeStroke.addJoin(prevPos, pos, shape[i + 1])

    if shape[0] == shape[^1]:
      shapeStroke.addJoin(shape[^2], shape[^1], shape[1])
    else:
      case lineCap:
      of ButtCap:
        discard
      of RoundCap:
        shapeStroke.add(makeCircle(shape[^1]))
      of SquareCap:
        let tangent = (shape[^1] - shape[^2]).normalize()
        shapeStroke.add(makeRect(
          shape[^1] + tangent * halfStroke,
          shape[^1]
        ))

    result.add(shapeStroke)

when defined(release):
  {.pop.}
