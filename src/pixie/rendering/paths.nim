import std/[fenv]
import pkg/[bumpy, chroma, vmath]
import ../[blends, common, images, internal, paints, simd, paths]
import ./[pathpoly, paints]

type
  PartitionEntry = object
    segment: Segment
    m, b: float32
    winding: int16

  Partition = object
    entries: seq[PartitionEntry]
    requiresAntiAliasing, twoNonintersectingSpanningSegments: bool
    top, bottom: int

  Fixed32 = int32 ## 24.8 fixed point

const
  epsilon: float32 = 0.0001 * PI ## Tiny value used for some computations.


when defined(release):
  {.push checks: off.}


proc initPartitionEntry*(segment: Segment, winding: int16): PartitionEntry =
  result.segment = segment
  result.winding = winding
  let d = segment.at.x - segment.to.x
  if d == 0:
    result.b = segment.at.x # Leave m = 0, store the x we want in b
  else:
    result.m = (segment.at.y - segment.to.y) / d
    result.b = segment.at.y - result.m * segment.at.x

proc solveX*(entry: PartitionEntry, y: float32): float32 {.inline.} =
  if entry.m == 0:
    entry.b
  else:
    (y - entry.b) / entry.m

proc solveY*(entry: PartitionEntry, x: float32): float32 {.inline.} =
  entry.m * x + entry.b

proc midpointX*(segment: Segment): float32 {.inline.} =
  (segment.at.x + segment.to.x) * 0.5

proc requiresAntiAliasing*(segment: Segment): bool {.inline.} =
  ## Returns true if the segment requires antialiasing.

  template hasFractional(v: float32): bool =
    v - trunc(v) != 0

  if segment.at.x != segment.to.x or
    segment.at.x.hasFractional() or # at.x and to.x are the same
    segment.at.y.hasFractional() or
    segment.to.y.hasFractional():
    # AA is required if all segments are not vertical or have fractional > 0
    return true

proc requiresAntiAliasing*(entries: var seq[PartitionEntry]): bool =
  ## Returns true if the fill requires antialiasing.
  for entry in entries:
    if entry.segment.requiresAntiAliasing:
      return true

proc partitionSegments*(
  segments: seq[(Segment, int16)], top, height: int
): seq[Partition] =
  ## Puts segments into the height partitions they intersect with.
  let
    maxPartitions = max(1, height div 4).uint32
    numPartitions = min(maxPartitions, max(1, segments.len div 2).uint32)

  result.setLen(numPartitions)

  let
    startY = top.uint32
    partitionHeight = height.uint32 div numPartitions

  # Set the bottom values for the partitions (y value where this partition ends)
  result[0].top = top
  result[0].bottom = top + partitionHeight.int
  for i in 1 ..< result.len:
    result[i].top = result[i - 1].bottom
    result[i].bottom = result[i - 1].bottom + partitionHeight.int

  # Ensure the final partition goes to the actual bottom
  # This is needed since the final partition includes
  # height - (height div numPartitions) * numPartitions
  result[^1].bottom = top + height

  var entries = newSeq[PartitionEntry](segments.len)
  for i, (segment, winding) in segments:
    entries[i] = initPartitionEntry(segment, winding)

  if numPartitions == 1:
    result[0].entries = move entries
  else:
    iterator partitionRange(
      segment: Segment,
      numPartitions, startY, partitionHeight: uint32
    ): uint32 =
      var
        atPartition = max(0, segment.at.y - startY.float32).uint32
        toPartition = max(0, segment.to.y - startY.float32).uint32
      atPartition = atPartition div partitionHeight
      toPartition = toPartition div partitionHeight
      atPartition = min(atPartition, numPartitions - 1)
      toPartition = min(toPartition, numPartitions - 1)
      for partitionIndex in atPartition .. toPartition:
        yield partitionIndex

    var entryCounts = newSeq[int](numPartitions)
    for (segment, _) in segments:
      for partitionIndex in segment.partitionRange(
        numPartitions, startY, partitionHeight
      ):
        inc entryCounts[partitionIndex]

    for partitionIndex, entryCounts in entryCounts:
      result[partitionIndex].entries.setLen(entryCounts)

    var indexes = newSeq[int](numPartitions)
    for i, (segment, winding) in segments:
      for partitionIndex in segment.partitionRange(
        numPartitions, startY, partitionHeight
      ):
        result[partitionIndex].entries[indexes[partitionIndex]] = entries[i]
        inc indexes[partitionIndex]

  for partition in result.mitems:
    partition.requiresAntiAliasing = requiresAntiAliasing(partition.entries)

    # Clip the entries to the parition bounds
    let
      top = partition.top.float32
      bottom = partition.bottom.float32
      topLine = line(vec2(0, top), vec2(1000, top))
      bottomLine = line(vec2(0, bottom), vec2(1000, bottom))
    for entry in partition.entries.mitems:
      if entry.segment.at.y <= top and entry.segment.to.y >= bottom:
        var at: Vec2
        discard intersects(entry.segment, topLine, at)
        entry.segment.at = at
        discard intersects(entry.segment, bottomLine, at)
        entry.segment.to = at

    if partition.entries.len == 2:
      let
        entry0 = partition.entries[0].segment
        entry1 = partition.entries[1].segment
      var at: Vec2
      if not intersectsInside(entry0, entry1, at):
        if entry0.at.y <= top and entry0.to.y >= bottom and
          entry1.at.y <= top and entry1.to.y >= bottom:
          # These two segments do not intersect and span the partition
          partition.twoNonintersectingSpanningSegments = true
          # Ensure entry[0] is on the left
          if entry0.midpointX > entry1.midpointX:
            swap partition.entries[1], partition.entries[0]

proc maxEntryCount*(partitions: var seq[Partition]): int =
  for i in 0 ..< partitions.len:
    result = max(result, partitions[i].entries.len)

proc fixed32*(f: float32): Fixed32 {.inline.} =
  Fixed32(f * 256)

proc integer*(p: Fixed32): int {.inline.} =
  p div 256

proc trunc*(p: Fixed32): Fixed32 {.inline.} =
  (p div 256) * 256

proc sortHits*(hits: var seq[(Fixed32, int16)], len: int) {.inline.} =
  ## Insertion sort
  for i in 1 ..< len:
    var
      j = i - 1
      k = i
    while j >= 0 and hits[j][0] > hits[k][0]:
      swap(hits[j + 1], hits[j])
      dec j
      dec k

proc shouldFill*(
  windingRule: WindingRule, count: int
): bool {.inline.} =
  ## Should we fill based on the current winding rule and count?
  case windingRule:
  of NonZero:
    count != 0
  of EvenOdd:
    count mod 2 != 0

iterator walk*(
  hits: seq[(Fixed32, int16)],
  numHits: int,
  windingRule: WindingRule,
  y: int,
  width: int
): (Fixed32, Fixed32, int) =
  var
    i, count: int
    prevAt: Fixed32
  while i < numHits:
    let (at, winding) = hits[i]
    if at > 0:
      if shouldFill(windingRule, count):
        if i < numHits - 1:
          # Look ahead to see if the next hit is in the same spot as this hit.
          # If it is, see if this hit and the next hit's windings cancel out.
          # If they do, skip the hits. It will be yielded later in a
          # larger chunk.
          let (nextAt, nextWinding) = hits[i + 1]
          if nextAt == at and winding + nextWinding == 0:
            i += 2
            continue
          # Shortcut: we only care about when we stop filling (or the last hit).
          # If we continue filling, move to next hit.
          if windingRule == NonZero and count + winding != 0:
            count += winding
            inc i
            continue
        yield (prevAt, at, count)
      prevAt = at
    count += winding
    inc i

  when defined(pixieLeakCheck):
    if prevAt != width.float32.fixed32 and count != 0:
      echo "Leak detected: ", count, " @ (", prevAt, ", ", y, ")"

iterator walkInteger*(
  hits: seq[(int32, int16)],
  numHits: int,
  windingRule: WindingRule,
  y, width: int
): (int, int) =
  for (prevAt, at, count) in hits.walk(numHits, windingRule, y, width):
    let
      fillStart = prevAt.integer
      fillLen = at.integer - fillStart
    if fillLen <= 0:
      continue
    yield (fillStart, fillLen)

proc computeCoverage*(
  coverages: ptr UncheckedArray[uint8],
  hits: var seq[(Fixed32, int16)],
  numHits: var int,
  width: int,
  y, startX: int,
  partitions: var seq[Partition],
  partitionIndex: int,
  entryIndices: seq[int],
  numEntryIndices: int,
  windingRule: WindingRule
) {.inline.} =
  let
    aa = partitions[partitionIndex].requiresAntiAliasing
    quality = if aa: 5 else: 1 # Must divide 255 cleanly (1, 3, 5, 15, 17, 51, 85)
    sampleCoverage = (255 div quality).uint8
    offset = 1 / quality.float32
    initialOffset = offset / 2 + epsilon

  var yLine = y.float32 + initialOffset - offset
  for m in 0 ..< quality:
    yLine += offset
    numHits = 0
    for i in 0 ..< numEntryIndices:
      let
        entryIndex = entryIndices[i]
        entry = partitions[partitionIndex].entries[entryIndex].addr
      if entry.segment.at.y <= yLine and entry.segment.to.y >= yLine:
        let x =
          if entry.m == 0:
            entry.b
          else:
            (yLine - entry.b) / entry.m

        hits[numHits] = (min(x, width.float32).fixed32, entry.winding)
        inc numHits

    if numHits > 0:
      sortHits(hits, numHits)

    if aa:
      for (prevAt, at, count) in hits.walk(numHits, windingRule, y, width):
        var fillStart = prevAt.integer

        let
          pixelCrossed = at.integer != prevAt.integer
          leftCover =
            if pixelCrossed:
              prevAt.trunc + 1.0.fixed32 - prevAt
            else:
              at - prevAt
        if leftCover != 0:
          inc fillStart
          coverages[prevAt.integer - startX] +=
            (leftCover * sampleCoverage.int32).integer.uint8

        if pixelCrossed:
          let rightCover = at - at.trunc
          if rightCover > 0:
            coverages[at.integer - startX] +=
              (rightCover * sampleCoverage.int32).integer.uint8

        let fillLen = at.integer - fillStart
        if fillLen > 0:
          var i = fillStart
          when allowSimd:
            when defined(amd64):
              let sampleCoverageVec = mm_set1_epi8(sampleCoverage)
              for _ in 0 ..< fillLen div 16:
                var coverageVec = mm_loadu_si128(coverages[i - startX].addr)
                coverageVec = mm_add_epi8(coverageVec, sampleCoverageVec)
                mm_storeu_si128(coverages[i - startX].addr, coverageVec)
                i += 16
            elif defined(arm64):
              let sampleCoverageVec = vmovq_n_u8(sampleCoverage)
              for _ in 0 ..< fillLen div 16:
                var coverageVec = vld1q_u8(coverages[i - startX].addr)
                coverageVec = vaddq_u8(coverageVec, sampleCoverageVec)
                vst1q_u8(coverages[i - startX].addr, coverageVec)
                i += 16
          for j in i ..< fillStart + fillLen:
            coverages[j - startX] += sampleCoverage

proc clearUnsafe*(image: Image, startX, startY, toX, toY: int) =
  ## Clears data from [start, to).
  if startX == image.width or startY == image.height:
    return
  let
    start = image.dataIndex(startX, startY)
    len = image.dataIndex(toX, toY) - start
  fillUnsafe(image.data, rgbx(0, 0, 0, 0), start, len)

proc blendLineCoverageOverwrite*(
  line: ptr UncheckedArray[ColorRGBX],
  coverages: ptr UncheckedArray[uint8],
  rgbx: ColorRGBX,
  len: int
 ) {.hasSimd.} =
  for i in 0 ..< len:
    let coverage = coverages[i]
    if coverage != 0:
      line[i] = rgbx * coverage

proc blendLineCoverageNormal*(
  line: ptr UncheckedArray[ColorRGBX],
  coverages: ptr UncheckedArray[uint8],
  rgbx: ColorRGBX,
  len: int
) {.hasSimd.} =
  for i in 0 ..< len:
    let coverage = coverages[i]
    if coverage == 0:
      discard
    else:
      line[i] = blendNormal(line[i], rgbx * coverage)

proc blendLineCoverageMask*(
  line: ptr UncheckedArray[ColorRGBX],
  coverages: ptr UncheckedArray[uint8],
  rgbx: ColorRGBX,
  len: int
) {.hasSimd.} =
  for i in 0 ..< len:
    let coverage = coverages[i]
    if coverage == 255:
      discard
    else:
      line[i] = blendMask(line[i], rgbx * coverage)

proc fillCoverage*(
  image: Image,
  rgbx: ColorRGBX,
  startX, y: int,
  coverages: seq[uint8],
  blendMode: BlendMode
) =
  var
    x = startX
    dataIndex = image.dataIndex(x, y)

  case blendMode:
  of OverwriteBlend:
    blendLineCoverageOverwrite(
      image.getUncheckedArray(startX, y),
      cast[ptr UncheckedArray[uint8]](coverages[0].unsafeAddr),
      rgbx,
      coverages.len
    )

  of NormalBlend:
    blendLineCoverageNormal(
      image.getUncheckedArray(startX, y),
      cast[ptr UncheckedArray[uint8]](coverages[0].unsafeAddr),
      rgbx,
      coverages.len
    )

  of MaskBlend:
    {.linearScanEnd.}
    blendLineCoverageMask(
      image.getUncheckedArray(startX, y),
      cast[ptr UncheckedArray[uint8]](coverages[0].unsafeAddr),
      rgbx,
      coverages.len
    )

    image.clearUnsafe(0, y, startX, y)
    image.clearUnsafe(startX + coverages.len, y, image.width, y)

  else:
    let blender = blendMode.blender()
    for x in x ..< startX + coverages.len:
      let coverage = coverages[x - startX]
      if coverage != 0:
        let backdrop = image.data[dataIndex]
        image.data[dataIndex] = blender(backdrop, rgbx * coverage)
      inc dataIndex

proc blendLineNormal*(
  line: ptr UncheckedArray[ColorRGBX], rgbx: ColorRGBX, len: int
) {.hasSimd.} =
  for i in 0 ..< len:
    line[i] = blendNormal(line[i], rgbx)

proc blendLineMask*(
  line: ptr UncheckedArray[ColorRGBX], rgbx: ColorRGBX, len: int
) {.hasSimd.} =
  for i in 0 ..< len:
    line[i] = blendMask(line[i], rgbx)

proc fillHits*(
  image: Image,
  rgbx: ColorRGBX,
  startX, y: int,
  hits: seq[(Fixed32, int16)],
  numHits: int,
  windingRule: WindingRule,
  blendMode: BlendMode,
  maskClears = true
) =
  case blendMode:
  of OverwriteBlend:
    for (start, len) in hits.walkInteger(numHits, windingRule, y, image.width):
      fillUnsafe(image.data, rgbx, image.dataIndex(start, y), len)

  of NormalBlend:
    for (start, len) in hits.walkInteger(numHits, windingRule, y, image.width):
      if rgbx.a == 255:
        fillUnsafe(image.data, rgbx, image.dataIndex(start, y), len)
      else:
        blendLineNormal(image.getUncheckedArray(start, y), rgbx, len)

  of MaskBlend:
    {.linearScanEnd.}
    var filledTo = startX
    for (start, len) in hits.walkInteger(numHits, windingRule, y, image.width):
      if maskClears: # Clear any gap between this fill and the previous fill
        let gapBetween = start - filledTo
        if gapBetween > 0:
          fillUnsafe(
            image.data,
            rgbx(0, 0, 0, 0),
            image.dataIndex(filledTo, y),
            gapBetween
          )
      block: # Handle this fill
        if rgbx.a != 255:
          blendLineMask(image.getUncheckedArray(start, y), rgbx, len)
        filledTo = start + len

    if maskClears:
      image.clearUnsafe(0, y, startX, y)
      image.clearUnsafe(filledTo, y, image.width, y)

  else:
    let blender = blendMode.blender()
    for (start, len) in hits.walkInteger(numHits, windingRule, y, image.width):
      var dataIndex = image.dataIndex(start, y)
      for _ in 0 ..< len:
        let backdrop = image.data[dataIndex]
        image.data[dataIndex] = blender(backdrop, rgbx)
        inc dataIndex

proc fillShapes*(
  image: Image,
  shapes: seq[Polygon],
  color: SomeColor,
  windingRule: WindingRule,
  blendMode: BlendMode
) =
  # Figure out the total bounds of all the shapes,
  # rasterize only within the total bounds
  let
    rgbx = color.asRgbx()
    segments = shapes.shapesToSegments()
    bounds = computeBounds(segments).snapToPixels()
    startX = max(0, bounds.x.int)
    startY = max(0, bounds.y.int)
    pathWidth =
      if startX < image.width:
        min(bounds.w.int, image.width - startX)
      else:
        0
    pathHeight = min(image.height, (bounds.y + bounds.h).int)

  if pathWidth == 0:
    return

  if pathWidth < 0:
    raise newException(PixieError, "Path int overflow detected")

  var
    partitions = partitionSegments(segments, startY, pathHeight - startY)
    partitionIndex: int
    entryIndices = newSeq[int](partitions.maxEntryCount)
    numEntryIndices: int
    trapezoidSegments = newSeq[Segment](entryIndices.len)
    coverages = newSeq[uint8](pathWidth)
    hits = newSeq[(Fixed32, int16)](entryIndices.len)
    numHits: int

  var y = startY
  while y < pathHeight:
    if y >= partitions[partitionIndex].bottom:
      inc partitionIndex

    let
      partition = partitions[partitionIndex].addr
      partitionTop = partition.top
      partitionBottom = partition.bottom
      partitionHeight = partitionBottom - partitionTop
    if partitionHeight == 0:
      continue

    if partition.twoNonintersectingSpanningSegments:
      if not partition.requiresAntiAliasing:
        # No AA required, must be 2 vertical pixel-aligned lines
        let
          left = partition.entries[0].segment.at.x.int
          right = partition.entries[1].segment.at.x.int
          minX = left.clamp(0, image.width)
          maxX = right.clamp(0, image.width)
          skipBlending =
            blendMode == OverwriteBlend or
            (blendMode == NormalBlend and rgbx.a == 255)
        if skipBlending and minX == 0 and maxX == image.width:
          # We can be greedy, just do one big mult-row fill
          let
            start = image.dataIndex(0, y)
            len = image.dataIndex(0, y + partitionHeight) - start
          fillUnsafe(image.data, rgbx, start, len)
        else:
          for r in 0 ..< partitionHeight:
            hits[0] = (cast[Fixed32](minX * 256), 1.int16)
            hits[1] = (cast[Fixed32](maxX * 256), -1.int16)
            image.fillHits(rgbx, 0, y + r, hits, 2, NonZero, blendMode)

        y += partitionHeight
        continue

    let
      scanTop = y.float32
      scanBottom = (y + 1).float32

    var allEntriesInScanlineSpanIt = true
    numEntryIndices = 0
    if partition.twoNonintersectingSpanningSegments:
      numEntryIndices = 2
      entryIndices[0] = 0
      entryIndices[1] = 1
    else:
      for i in 0 ..< partition.entries.len:
        if partition.entries[i].segment.to.y <= scanTop or
          partition.entries[i].segment.at.y >= scanBottom:
          continue
        if partition.entries[i].segment.at.y > scanTop or
          partition.entries[i].segment.to.y < scanBottom:
          allEntriesInScanlineSpanIt = false
        entryIndices[numEntryIndices] = i
        inc numEntryIndices

    if allEntriesInScanlineSpanIt and numEntryIndices mod 2 == 0:
      for i in 0 ..< numEntryIndices:
        let index = entryIndices[i]
        trapezoidSegments[index].at.y = scanTop
        trapezoidSegments[index].to.y = scanBottom
        trapezoidSegments[index].at.x =
          partition.entries[index].solveX(scanTop)
        trapezoidSegments[index].to.x =
          partition.entries[index].solveX(scanBottom)

      # Sort the segments by midpoint. If they intersect this will be wrong
      # but it will get caught when we check partial coverage overlap and we
      # won't take the shortcut.

      var noEntriesInScanlineOverlap = true

      for i in 1 ..< numEntryIndices:
        var
          j = i - 1
          k = i
        while j >= 0 and
          trapezoidSegments[entryIndices[j]].midpointX >
          trapezoidSegments[entryIndices[k]].midpointX:
          swap(entryIndices[j + 1], entryIndices[j])
          dec j
          dec k

      # Only take this shortcut if the partial coverage areas on the
      # left and the right do not overlap
      for i in 0 ..< numEntryIndices - 1:
        let
          left = trapezoidSegments[entryIndices[i]]
          right = trapezoidSegments[entryIndices[i + 1]]
          leftMaxX = max(left.at.x, left.to.x)
          rightMinX = min(right.at.x, right.to.x)
        if leftMaxX.ceil.int > rightMinX.int:
          noEntriesInScanlineOverlap = false
          break

      if noEntriesInScanlineOverlap:
        # Confirm the pairs of points represent simple fills between them
        var
          onlySimpleFillPairs = true
          i, windingCount: int
        while i < numEntryIndices:
          windingCount += partition.entries[entryIndices[i]].winding
          if not windingRule.shouldFill(windingCount):
            onlySimpleFillPairs = false
            break
          windingCount += partition.entries[entryIndices[i + 1]].winding
          if windingRule.shouldFill(windingCount):
            onlySimpleFillPairs = false
            break
          i += 2

        if onlySimpleFillPairs:
          var i, filledTo: int
          while i < numEntryIndices:
            let
              left = partition.entries[entryIndices[i]]
              right = partition.entries[entryIndices[i + 1]]
              trapLeft = trapezoidSegments[entryIndices[i]]
              trapRight = trapezoidSegments[entryIndices[i + 1]]

            # Use trapezoid coverage at the edges and fill in the middle

            when allowSimd and defined(amd64):
              let vecRgbx = mm_set_ps(
                rgbx.a.float32,
                rgbx.b.float32,
                rgbx.g.float32,
                rgbx.r.float32
              )

            let
              leftMaxX = max(trapLeft.at.x, trapLeft.to.x)
              rightMinX = min(trapRight.at.x, trapRight.to.x)
              leftCoverEnd = leftMaxX.ceil.int
              rightCoverBegin = rightMinX.trunc.int
              blender = blendMode.blender()

            block: # Left-side partial coverage
              let
                inverted = trapLeft.at.x < trapLeft.to.x
                sliverStart = min(trapLeft.at.x, trapLeft.to.x)
                rectStart = leftMaxX
              var
                pen = sliverStart
                prevPen = pen
                penY = if inverted: y.float32 else: (y + 1).float32
                prevPenY = penY
              for x in sliverStart.int ..< rectStart.ceil.int:
                prevPen = pen
                pen = (x + 1).float32
                var rightRectArea = 0.float32
                if pen > rectStart:
                  rightRectArea = pen - rectStart
                  pen = rectStart
                prevPenY = penY
                penY = left.solveY(pen)
                if x < 0 or x >= image.width:
                  continue
                let
                  run = pen - prevPen
                  triangleArea = 0.5.float32 * run * abs(penY - prevPenY)
                  rectArea =
                    if inverted:
                      (prevPenY - y.float32) * run
                    else:
                      ((y + 1).float32 - prevPenY) * run
                  area = triangleArea + rectArea + rightRectArea
                  dataIndex = image.dataIndex(x, y)
                  backdrop = image.data[dataIndex]
                  source =
                    when allowSimd and defined(amd64):
                      applyOpacity(vecRgbx, area)
                    else:
                      rgbx * area
                image.data[dataIndex] = blender(backdrop, source)

            block: # Right-side partial coverage
              let
                inverted = trapRight.at.x > trapRight.to.x
                rectEnd = rightMinX
                sliverEnd = max(trapRight.at.x, trapRight.to.x)
              var
                pen = rectEnd
                prevPen = pen
                penY = if inverted: (y + 1).float32 else: y.float32
                prevPenY = penY
              for x in rectEnd.int ..< sliverEnd.ceil.int:
                prevPen = pen
                pen = (x + 1).float32
                let leftRectArea = prevPen.fract
                if pen > sliverEnd:
                  pen = sliverEnd
                prevPenY = penY
                penY = right.solveY(pen)
                if x < 0 or x >= image.width:
                  continue
                let
                  run = pen - prevPen
                  triangleArea = 0.5.float32 * run * abs(penY - prevPenY)
                  rectArea =
                    if inverted:
                      (penY - y.float32) * run
                    else:
                      ((y + 1).float32 - penY) * run
                  area = leftRectArea + triangleArea + rectArea
                  dataIndex = image.dataIndex(x, y)
                  backdrop = image.data[dataIndex]
                  source =
                    when allowSimd and defined(amd64):
                      applyOpacity(vecRgbx, area)
                    else:
                      rgbx * area
                image.data[dataIndex] = blender(backdrop, source)

            let
              fillBegin = leftCoverEnd.clamp(0, image.width)
              fillEnd = rightCoverBegin.clamp(0, image.width)
            hits[0] = (fixed32(fillBegin.float32), 1.int16)
            hits[1] = (fixed32(fillEnd.float32), -1.int16)
            image.fillHits(rgbx, 0, y, hits, 2, NonZero, blendMode, false)

            if blendMode == MaskBlend:
              let clearTo = min(trapLeft.at.x, trapLeft.to.x).int
              image.clearUnsafe(
                min(filledTo, image.width),
                y,
                min(clearTo, image.width),
                y
              )

            filledTo = max(trapRight.at.x, trapRight.to.x).ceil.int
            i += 2

          if blendMode == MaskBlend:
            image.clearUnsafe(min(filledTo, image.width), y, image.width, y)

          inc y
          continue

    computeCoverage(
      cast[ptr UncheckedArray[uint8]](coverages[0].addr),
      hits,
      numHits,
      image.width,
      y,
      startX,
      partitions,
      partitionIndex,
      entryIndices,
      numEntryIndices,
      windingRule
    )

    if partitions[partitionIndex].requiresAntiAliasing:
      image.fillCoverage(
        rgbx,
        startX,
        y,
        coverages,
        blendMode
      )
      zeroMem(coverages[0].addr, coverages.len)
    else:
      image.fillHits(
        rgbx,
        startX,
        y,
        hits,
        numHits,
        windingRule,
        blendMode
      )

    inc y

  if blendMode == MaskBlend:
    image.clearUnsafe(0, 0, 0, startY)
    image.clearUnsafe(0, pathHeight, 0, image.height)


proc parseSomePath*(
  path: SomePath, closeSubpaths: bool, pixelScale: float32
): seq[Polygon] {.inline.} =
  ## Given SomePath, parse it in different ways.
  when type(path) is string:
    parsePath(path).commandsToShapes(closeSubpaths, pixelScale)
  elif type(path) is Path:
    path.commandsToShapes(closeSubpaths, pixelScale)

proc fillPath*(
  image: Image,
  path: SomePath,
  paint: Paint,
  transform = mat3(),
  windingRule = NonZero
) {.raises: [PixieError].} =
  ## Fills a path.
  paint.opacity = clamp(paint.opacity, 0, 1)

  if paint.opacity == 0:
    return

  if paint.kind == SolidPaint:
    if paint.color.a > 0 or paint.blendMode == OverwriteBlend:
      var shapes = parseSomePath(path, true, transform.pixelScale())
      shapes.transform(transform)
      var color = paint.color
      color.a *= paint.opacity
      image.fillShapes(shapes, color, windingRule, paint.blendMode)
    return

  let
    mask = newImage(image.width, image.height)
    fill = newImage(image.width, image.height)

  mask.fillPath(path, color(1, 1, 1, 1), transform, windingRule)

  # Draw the image (maybe tiled) or gradients. Do this with opaque paint and
  # and then apply the paint's opacity to the mask.
  let savedOpacity = paint.opacity
  paint.opacity = 1

  case paint.kind:
    of SolidPaint:
      discard # Handled above
    of ImagePaint:
      fill.draw(paint.image, paint.imageMat)
    of TiledImagePaint:
      fill.drawTiled(paint.image, paint.imageMat)
    of LinearGradientPaint, RadialGradientPaint, AngularGradientPaint:
      fill.fillGradient(paint)

  paint.opacity = savedOpacity

  if paint.opacity != 1:
    mask.applyOpacity(paint.opacity)

  fill.draw(mask, blendMode = MaskBlend)
  image.draw(fill, blendMode = paint.blendMode)

proc strokePath*(
  image: Image,
  path: SomePath,
  paint: Paint,
  transform = mat3(),
  strokeWidth: float32 = 1.0,
  lineCap = ButtCap,
  lineJoin = MiterJoin,
  miterLimit = defaultMiterLimit,
  dashes: seq[float32] = @[]
) {.raises: [PixieError].} =
  ## Strokes a path.
  paint.opacity = clamp(paint.opacity, 0, 1)

  if paint.opacity == 0:
    return

  if paint.kind == SolidPaint:
    if paint.color.a > 0 or paint.blendMode == OverwriteBlend:
      var strokeShapes = strokeShapes(
        parseSomePath(path, false, transform.pixelScale()),
        strokeWidth,
        lineCap,
        lineJoin,
        miterLimit,
        dashes,
        pixelScale(transform)
      )
      strokeShapes.transform(transform)
      var color = paint.color
      color.a *= paint.opacity
      image.fillShapes(strokeShapes, color, NonZero, paint.blendMode)
    return

  let
    mask = newImage(image.width, image.height)
    fill = newImage(image.width, image.height)

  mask.strokePath(
    path,
    color(1, 1, 1, 1),
    transform,
    strokeWidth,
    lineCap,
    lineJoin,
    miterLimit,
    dashes
  )

  # Draw the image (maybe tiled) or gradients. Do this with opaque paint and
  # and then apply the paint's opacity to the mask.
  let savedOpacity = paint.opacity
  paint.opacity = 1

  case paint.kind:
    of SolidPaint:
      discard # Handled above
    of ImagePaint:
      fill.draw(paint.image, paint.imageMat)
    of TiledImagePaint:
      fill.drawTiled(paint.image, paint.imageMat)
    of LinearGradientPaint, RadialGradientPaint, AngularGradientPaint:
      fill.fillGradient(paint)

  paint.opacity = savedOpacity

  if paint.opacity != 1:
    mask.applyOpacity(paint.opacity)

  fill.draw(mask, blendMode = MaskBlend)
  image.draw(fill, blendMode = paint.blendMode)

proc overlaps*(
  shapes: seq[Polygon],
  test: Vec2,
  windingRule: WindingRule
): bool =
  var hits: seq[(Fixed32, int16)]

  let
    scanline = line(vec2(0, test.y), vec2(1000, test.y))
    segments = shapes.shapesToSegments()
  for (segment, winding) in segments:
    if segment.at.y <= scanline.a.y and segment.to.y >= scanline.a.y:
      var at: Vec2
      if scanline.intersects(segment, at):
        if segment.to != at:
          hits.add((at.x.fixed32, winding))

  sortHits(hits, hits.len)

  let testX = test.x.fixed32

  var count: int
  for (at, winding) in hits:
    if at > testX:
      return shouldFill(windingRule, count)
    count += winding

proc fillOverlaps*(
  path: Path,
  test: Vec2,
  transform = mat3(), ## Applied to the path, not the test point.
  windingRule = NonZero
): bool {.raises: [PixieError].} =
  ## Returns whether or not the specified point is contained in the current path.
  var shapes = path.commandsToShapes(true, transform.pixelScale())
  shapes.transform(transform)
  shapes.overlaps(test, windingRule)

proc strokeOverlaps*(
  path: Path,
  test: Vec2,
  transform = mat3(), ## Applied to the path, not the test point.
  strokeWidth: float32 = 1.0,
  lineCap = ButtCap,
  lineJoin = MiterJoin,
  miterLimit = defaultMiterLimit,
  dashes: seq[float32] = @[],
): bool {.raises: [PixieError].} =
  ## Returns whether or not the specified point is inside the area contained
  ## by the stroking of a path.
  let pixelScale = transform.pixelScale()
  var strokeShapes = strokeShapes(
    path.commandsToShapes(false, pixelScale),
    strokeWidth,
    lineCap,
    lineJoin,
    miterLimit,
    dashes,
    pixelScale
  )
  strokeShapes.transform(transform)
  strokeShapes.overlaps(test, NonZero)

proc fill*(image: Image, paint: Paint) {.raises: [PixieError].} =
  ## Fills the image with the paint.
  case paint.kind:
  of SolidPaint:
    fillUnsafe(image.data, paint.color, 0, image.data.len)
  of ImagePaint, TiledImagePaint:
    fillUnsafe(image.data, rgbx(0, 0, 0, 0), 0, image.data.len)
    let path = newPath()
    path.rect(0, 0, image.width.float32, image.height.float32)
    image.fillPath(path, paint)
  of LinearGradientPaint, RadialGradientPaint, AngularGradientPaint:
    image.fillGradient(paint)

when defined(release):
  {.pop.}
