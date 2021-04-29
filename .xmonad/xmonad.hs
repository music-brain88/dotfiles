import XMonad
import XMonad.Hooks.DynamicLog

main :: IO()

main = do
  xmobar myConfig >>= xmonad

myConfig = defaultConfig
  {
    terminal = "alacritty",
    startupHook = sampleStartupHook,
    modMask = mod4Mask,
    borderWidth = myBorderWidth,
    normalBorderColor = myNormalBorderColor,
    focusedBorderColor = myFocusedBorderColor
  }

sampleStartupHook = do
  -- wallpaper setting
  spawn "feh --bg-scale ~/Pictures/wallpaper/archlinux_01.jpg"

-- border line width
myBorderWidth = 4
-- boder color
myNormalBorderColor  = "black"
myFocusedBorderColor = "#69DFFA"   --"#E39402"    #00F2FF
