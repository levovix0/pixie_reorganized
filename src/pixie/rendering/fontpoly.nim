import pkg/[bumpy, vmath]
import ../[common, paths, fonts]
import ./[pathpoly]


when defined(release):
  {.push checks: off.}


proc computeBounds*(
  arrangement: Arrangement,
  transform = mat3()
): Rect {.raises: [PixieError].} =
  let fullPath = newPath()
  for path in arrangement.computePaths():
    fullPath.addPath(path)
  fullPath.transform(transform)
  fullPath.computeBounds()


when defined(release):
  {.pop.}
