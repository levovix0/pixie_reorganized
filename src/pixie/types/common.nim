import pkg/[chroma]

type
  PixieError* = object of CatchableError  ## Raised if an operation fails.

  BlendMode* = enum
    NormalBlend
    DarkenBlend
    MultiplyBlend
    # BlendLinearBurn
    ColorBurnBlend
    LightenBlend
    ScreenBlend
    # BlendLinearDodge
    ColorDodgeBlend
    OverlayBlend
    SoftLightBlend
    HardLightBlend
    DifferenceBlend
    ExclusionBlend
    HueBlend
    SaturationBlend
    ColorBlend
    LuminosityBlend

    MaskBlend         ## Special blend mode that is used for masking
    OverwriteBlend    ## Special blend mode that just copies pixels
    SubtractMaskBlend ## Inverse mask
    ExcludeMaskBlend

  ImageDimensions* = object
    width*, height*: int

  Image* = ref object
    ## Image object that holds bitmap data in premultiplied alpha RGBA format.
    width*, height*: int
    data*: seq[ColorRGBX]
