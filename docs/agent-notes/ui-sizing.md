# UI sizing

Text and spacing are calibrated to match the reference app (Spotify), not scaled by screen size.

- All font sizes live in `AppFontSize` (`lib/src/theme.dart`); list rows get their title/subtitle
  sizes from `listTileTheme`. Don't put numeric `fontSize:` literals in screens — add or reuse a
  named size there.
- No automatic scaling to screen width (e.g. `flutter_screenutil`) — decided with the user. Android
  dp/sp already account for density, so on the Huawei SNE-LX1 (~360 dp wide, density 480) everything
  is ~14% larger relative to the screen than on the Pixel 7a (~411 dp), exactly like in the
  reference app and the rest of the system. Scaling by width would make the app diverge from both
  and break the user's system font-size setting.
- Calibration method: screenshot the reference app and this app **on the same phone**
  (`adb exec-out screencap -p`), then compare ink heights/widths of the same labels and row pitch
  (e.g. bright-pixel row runs with PIL). Reference values measured this way: list title ~16 sp,
  subtitle ~13 sp, section heading ~20 sp, settings row ~60 dp, library row ~80 dp, drawer item
  ~56 dp, avatar 32 dp, Home cards 144 dp wide.
- Remaining visual difference is mostly the typeface: Roboto is wider than the reference app's
  font. Bundling a narrower font was considered and deferred.
