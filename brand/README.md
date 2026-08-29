# Brand assets

Everything here is generated. Do not hand-edit the SVGs, the PNGs, or the Android
resources — edit the scripts and re-run them, or the next build silently reverts you.

## Regenerating

```
python brand/src/build_logo.py      # SVG masters
python brand/src/export_png.py      # PNG masters for the store and for print
python brand/src/build_android.py   # Android res/ tree, then copy into each app
python brand/src/build_alarm.py     # the new-order alarm, for MerchantApp
```

`build_logo.py` must run first: the other two import it for the flattened mark path.

## What is generated, and why it is generated

**The wordmark is outlines, not text.** Lemonada is shaped once with HarfBuzz and written
out as path data. Shipping the font instead would put a display face in the app for one
word, and would leave the diacritics at the mercy of whatever shaper runs on the device.

**The mark is one flat path.** It starts as a disc minus a bite minus Lemonada's own ل,
and those booleans are resolved at build time with skia-pathops. A mask-based version
collides on its mask id when two copies land on one page, and Android vector drawables
have no mask at all — one path renders identically in SVG, in a drawable, and in print.

**The carved letter is the font's ل, not a redrawing of it**, so the mark and the wordmark
are visibly the same hand.

**The bite is upper-left.** The ل's tall stem rises on the right; a bite there clips the
stem and the letter stops reading. A smaller right-hand bite and a bottom-left bite were
both built and compared, and each weakens the bite instead. Upper-left is the only
placement where the letter and the bite both survive at 32px.

## Files

| File | Use |
|---|---|
| `logo_mark.svg` | The mark, with the orange crumb. 48dp and up. |
| `logo_mark_small.svg` | The mark without the crumb. Below 48dp, where the crumb reads as dust. |
| `logo_mark_mono.svg` | `currentColor`, for single-colour print and stamps. |
| `logo_wordmark.svg` | The name alone. |
| `logo_lockup_horizontal.svg` | Mark and name. The general-purpose lockup. |
| `logo_lockup_appbar.svg` | Cream, sized for a 21dp mark in the app bar. |
| `logo_lockup_stacked.svg` | On its burgundy panel. Splash and store listing. |
| `app_icon.svg` | Legacy square icon. |
| `app_icon_foreground.svg` | Adaptive icon foreground on the 108dp grid. |
| `png/` | Raster masters. `app_icon_512.png` is the Play Store icon. |
| `android/res/` | Drop into each app's `android/app/src/main/res/`. |
| `audio/new_order.wav` | The new-order alarm. Goes in MerchantApp's `res/raw/`. Loops seamlessly, so the notification channel can repeat it until the order is opened. The reasoning behind every number in it is at the top of `src/build_alarm.py` — it is a kitchen sound, not a pleasant one. |

The Android tree carries the adaptive icon, the Android 13 themed (monochrome) icon, the
API 31+ system splash, the pre-31 launch window, and legacy mipmaps for API < 26.

## Sizes

The mark holds down to **22dp**; below that use the wordmark alone. Clear space around any
lockup is never less than the height of the ل.

## One thing still unverified

`LuqmaSplash.markSize` in `luqma_core` must match the size Android actually renders the
system splash drawable at, or the mark will jump when the system hands over to Flutter.
The drawable is authored for it, but the number can only be confirmed on a device. Check
it in Phase 3, when there is an app to run.
