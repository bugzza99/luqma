# Third-party notices

## Fonts

Two typefaces are redistributed with this repository. Both are licensed under the
**SIL Open Font License, Version 1.1**, which permits bundling and redistribution and
requires that this notice and the licence text travel with them.

| Font | Where | Used for | Licence |
|---|---|---|---|
| **Cairo** | `packages/luqma_core/assets/fonts/Cairo.ttf` | The entire app interface | `Cairo-OFL.txt` beside it |
| **Lemonada** | `brand/src/Lemonada.ttf` | The logo wordmark only | `brand/src/Lemonada-OFL.txt` beside it |

Copyright 2009 The Cairo Project Authors (https://github.com/Gue3bara/Cairo).
Copyright 2011 The Lemonada Project Authors (https://github.com/Gue3bara/Lemonada).

Lemonada is **not shipped in the app**. It is checked in only so
`brand/src/build_logo.py` can reproduce the wordmark outlines; what reaches a phone is the
SVG path data those outlines became. Cairo is bundled and does reach the phone.

The OFL forbids selling the fonts on their own and requires that any modified version be
renamed. Neither applies here: they are used unmodified, and the logo is vector artwork
derived from Lemonada's outlines rather than a modified font.
