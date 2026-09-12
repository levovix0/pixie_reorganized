import std/[tables, unicode, sets]
import ./[paths, common]

type
  EncodingRecord* = object
    platformID*: uint16
    encodingID*: uint16
    offset*: uint32

  CmapTable* = ref object
    version*: uint16
    numTables*: uint16
    encodingRecords*: seq[EncodingRecord]
    runeToGlyphId*: Table[Rune, uint16]
    glyphIdToRune*: Table[uint16, Rune]

  HeadTable* = ref object
    majorVersion*: uint16
    minorVersion*: uint16
    fontRevision*: float32
    checkSumAdjustment*: uint32
    magicNumber*: uint32
    flags*: uint16
    unitsPerEm*: uint16
    created*: float64
    modified*: float64
    xMin*: int16
    yMin*: int16
    xMax*: int16
    yMax*: int16
    macStyle*: uint16
    lowestRecPPEM*: uint16
    fontDirectionHint*: int16
    indexToLocFormat*: int16
    glyphDataFormat*: int16

  HheaTable* = ref object
    majorVersion*: uint16
    minorVersion*: uint16
    ascender*: int16
    descender*: int16
    lineGap*: int16
    advanceWidthMax*: uint16
    minLeftSideBearing*: int16
    minRightSideBearing*: int16
    xMaxExtent*: int16
    caretSlopeRise*: int16
    caretSlopeRun*: int16
    caretOffset*: int16
    metricDataFormat*: int16
    numberOfHMetrics*: uint16

  MaxpTable* = ref object
    version*: float32
    numGlyphs*: uint16
    maxPoints*: uint16
    maxContours*: uint16
    maxCompositePoints*: uint16
    maxCompositeContours*: uint16
    maxZones*: uint16
    maxTwilightPoints*: uint16
    maxStorage*: uint16
    maxFunctionDefs*: uint16
    maxInstructionDefs*: uint16
    maxStackElements*: uint16
    maxSizeOfInstructions*: uint16
    maxComponentElements*: uint16
    maxComponentDepth*: uint16

  LongHorMetricRecord* = object
    advanceWidth*: uint16
    leftSideBearing*: int16

  HmtxTable* = ref object
    hMetrics*: seq[LongHorMetricRecord]
    leftSideBearings*: seq[int16]

  NameRecord* = object
    platformID*: uint16
    encodingID*: uint16
    languageID*: uint16
    nameID*: uint16
    length*: uint16
    offset*: uint16
    text*: string

  NameTable* = ref object
    format*: uint16
    count*: uint16
    stringOffset*: uint16
    nameRecords*: seq[NameRecord]

  OS2Table* = ref object
    version*: uint16
    xAvgCharWidth*: int16
    usWeightClass*: uint16
    usWidthClass*: uint16
    fsType*: uint16
    ySubscriptXSize*: int16
    ySubscriptYSize*: int16
    ySubscriptXOffset*: int16
    ySubscriptYOffset*: int16
    ySuperscriptXSize*: int16
    ySuperscriptYSize*: int16
    ySuperscriptXOffset*: int16
    ySuperscriptYOffset*: int16
    yStrikeoutSize*: int16
    yStrikeoutPosition*: int16
    sFamilyClass*: int16
    panose*: array[10, uint8]
    ulUnicodeRange1*: uint32
    ulUnicodeRange2*: uint32
    ulUnicodeRange3*: uint32
    ulUnicodeRange4*: uint32
    achVendID*: string
    fsSelection*: uint16
    usFirstCharIndex*: uint16
    usLastCharIndex*: uint16
    sTypoAscender*: int16
    sTypoDescender*: int16
    sTypoLineGap*: int16
    usWinAscent*: uint16
    usWinDescent*: uint16
    ulCodePageRange1*: uint32
    ulCodePageRange2*: uint32
    sxHeight*: int16
    sCapHeight*: int16
    usDefaultChar*: uint16
    usBreakChar*: uint16
    usMaxContext*: uint16
    usLowerOpticalPointSize*: uint16
    usUpperOpticalPointSize*: uint16

  LocaTable* = ref object
    offsets*: seq[uint32]

  GlyfTable* = ref object
    offsets*: seq[uint32]

  KernPair* = object
    left*: uint16
    right*: uint16
    value*: int16

  KernSubTable* = object
    version*: uint16
    length*: uint16
    coverage*: uint16
    nPairs*: uint16
    searchRange*: uint16
    entrySelector*: uint16
    rangeShift*: uint16
    kernPairs*: seq[KernPair]

  KernTable* = ref object
    version*: uint16
    nTables*: uint16
    subTables*: seq[KernSubTable]
    kerningPairs*: Table[(uint16, uint16), float32]

  TableRecord* = object
    tag*: string
    checksum*: uint32
    offset*: uint32
    length*: uint32

  # LangSys* = object
  #   lookupOrderOffset*: uint16
  #   requiredFeatureIndex*: uint16
  #   featureIndexCount*: uint16
  #   featureIndices*: seq[uint16]

  # LangSysRecord* = object
  #   langSysTag*: string
  #   langSysOffset*: uint16
  #   langSys*: LangSys

  # Script* = object
  #   defaultLangSysOffset*: uint16
  #   langSysCount*: uint16
  #   langSysRecords*: seq[LangSysRecord]

  # ScriptRecord* = object
  #   scriptTag*: string
  #   scriptOffset*: uint16
  #   script*: Script

  # ScriptList* = object
  #   scriptCount*: uint16
  #   scriptRecords*: seq[ScriptRecord]

  # Feature* = object
  #   featureParamsOffset*: uint16
  #   lookupIndexCount*: uint16
  #   lookupListIndices*: seq[uint16]

  # FeatureRecord* = object
  #   featureTag*: string
  #   featureOffset*: uint16
  #   feature*: Feature

  # FeatureList* = object
  #   featureCount*: uint16
  #   featureRecords*: seq[FeatureRecord]

  RangeRecord* = object
    startGlyphID*: uint16
    endGlyphID*: uint16
    startCoverageIndex*: uint16

  Coverage* = object
    coverageFormat*: uint16
    glyphCount*: uint16
    glyphArray*: seq[uint16]
    rangeCount*: uint16
    rangeRecords*: seq[RangeRecord]
    coveredGlyphs*: HashSet[uint16]

  ValueRecord* = object
    xPlacement*: int16
    yPlacement*: int16
    xAdvance*: int16
    yAdvance*: int16
    xPlaDeviceOffset*: uint16
    yPlaDeviceOffset*: uint16
    xAdvDeviceOffset*: uint16
    yAdvDeviceOffset*: uint16

  PairValueRecord* = object
    secondGlyph*: uint16
    valueRecord1*: ValueRecord
    valueRecord2*: ValueRecord

  PairSet* = object
    pairValueCount*: uint16
    pairValueRecords*: seq[PairValueRecord]

  Class2Record* = object
    valueRecord1*: ValueRecord
    valueRecord2*: ValueRecord

  Class1Record* = object
    class2Records*: seq[Class2Record]

  ClassRangeRecord* = object
    startGlyphID*: uint16
    endGlyphID*: uint16
    class*: uint16

  ClassDef* = object
    classFormat*: uint16
    startGlyphID*: uint16
    glyphCount*: uint16
    classValueArray*: seq[uint16]
    classRangeCount*: uint16
    classRangeRecords*: seq[ClassRangeRecord]

  PairPos* = ref object
    posFormat*: uint16
    coverageOffset*: uint16
    valueFormat1*: uint16
    valueFormat2*: uint16
    pairSetCount*: uint16
    pairSetOffsets*: seq[uint16]
    pairSets*: seq[PairSet]
    classDef1Offset*: uint16
    classDef2Offset*: uint16
    class1Count*: uint16
    class2Count*: uint16
    class1Records*: seq[Class1Record]
    classDef1*: ClassDef
    classDef2*: ClassDef
    coverage*: Coverage
    glyphIdToClass1*: Table[uint16, uint16]
    glyphIdToClass2*: Table[uint16, uint16]
    classPairAdjustments*: Table[(uint16, uint16), int16]
    glyphPairAdjustments*: Table[(uint16, uint16), int16]

  Lookup* = object
    lookupType*: uint16
    lookupFlag*: uint16
    subTableCount*: uint16
    subTableOffsets*: seq[uint16]
    markFilteringSet*: uint16

  LookupList* = object
    lookupCount*: uint16
    lookupOffsets*: seq[uint16]
    lookups*: seq[Lookup]
    pairPosTables*: seq[PairPos]

  GposTable* = ref object
    majorVersion*: uint16
    minorVersion*: uint16
    scriptListOffset*: uint16
    featureListOffset*: uint16
    lookupListOffset*: uint16
    featureVariationsOffset*: uint32
    # scriptList*: ScriptList
    # featureList*: FeatureList
    lookupList*: LookupList

  PostTable* = ref object
    version*: float32
    italicAngle*: float32
    underlinePosition*: int16
    underlineThickness*: int16
    isFixedPitch*: uint32

  CFFHeader* = ref object
    formatMajor*: uint8
    formatMinor*: uint8
    size*: uint8
    offsetSize*: uint8

  CFFTopDict* = ref object
    charStrings*: int
    charset*: int
    charstringType*: int
    cidCount*: int
    cidFontRevision*: int
    cidFontType*: int
    cidFontVersion*: int
    copyright*: string
    encoding*: int
    familyName*: string

    fdArray*: int
    fdSelect*: int
    fdArraySeq*: seq[CFFTopDict]
    fdSelectSeq*: seq[int]

    fontBBox*: array[4, float32]
    fontMatrix*: array[6, float32]
    fontName*: string
    fullName*: string
    isFixedPitch*: int
    italicAngle*: int
    notice*: string
    paintType*: int
    private*: array[2, float32]
    subrs*: int
    subrsBias*: int
    subrIndex*: seq[string]
    defaultWidthX*: int
    nominalWidthX*: int
    ros*: array[3, string]
    strokeWidth*: int
    uidBase*: int
    underlinePosition*: int
    underlineThickness*: int
    uniqueId*: int
    version*: string
    weight*: string

  CFFTable* = ref object
    ## Contains the glyph outlines in PostScript format.
    header*: CFFHeader
    nameIndex*: seq[string]
    topDictIndex*: seq[string]
    stringIndex*: seq[string]
    globalSubrIndex*: seq[string]
    topDict*: CFFTopDict
    charIndex*: seq[(int, int)]
    isCID*: bool

  OpenType* = ref object
    buf*: string
    version*: uint32
    numTables*: uint16
    searchRange*: uint16
    entrySelector*: uint16
    rangeShift*: uint16
    tableRecords*: Table[string, TableRecord]
    cmap*: CmapTable
    head*: HeadTable
    hhea*: HheaTable
    maxp*: MaxpTable
    hmtx*: HmtxTable
    name*: NameTable
    os2*: OS2Table
    loca*: LocaTable
    glyf*: GlyfTable
    kern*: KernTable
    gpos*: GposTable
    post*: PostTable
    cff*: CFFTable
    glyphPaths*: Table[Rune, Path]


proc isCCW*(opentype: OpenType): bool {.inline.} =
  ## Returns the expected winding order of a font.
  ## Gyph - false - clockwise
  ## CFF - true - counterclockwise
  opentype.cff == nil


proc hasGlyph*(opentype: OpenType, rune: Rune): bool {.inline.} =
  rune in opentype.cmap.runeToGlyphId


proc fullName*(opentype: OpenType): string =
  ## Returns full name of the font if available.
  if opentype.cff != nil:
    return opentype.cff.topDict.fullName
  for record in opentype.name.nameRecords:
    if record.nameID == 6 and record.languageID == 1033:
      return record.text


# theese are needed for fonts to not depend on heavy ../fontformats/opentype, ../fontloading will import fontformats anyway

proc getGlyphPath*(opentype: OpenType, rune: Rune): Path {.importc: "pixie_opentype_get_glyph_path", raises: [PixieError].}
proc getAdvance*(opentype: OpenType, rune: Rune): float32 {.importc: "pixie_opentype_getAdvance", raises: [].}
proc getKerningAdjustment*(opentype: OpenType, left, right: Rune): float32 {.importc: "pixie_opentype_getKernelAdjustment", raises: [].}

