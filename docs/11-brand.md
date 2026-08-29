# Brand and Visual Identity

## Palette
| Role | HEX |
|---|---|
| Primary (Burgundy) | `#761812` |
| Primary Dark | `#451410` |
| Accent (Orange) | `#D67F2B` |
| Accent Light | `#E69B4A` |
| Background (Warm Cream) | `#F5EBE2` |
| Surface | `#E5D3C1` |
| Text Primary | `#130B07` |
| Text Secondary | `#5A452B` |
| Border | `#D6BFA9` |
| White | `#FFFFFF` |

Distribution: 60% cream, 25% burgundy, 10% orange, 5% dark. Orange is reserved for prices,
offers and ratings — it must never become a general-purpose colour or it stops signalling value.

## Logo — decided

**The mark** is a solid burgundy disc — the لقمة itself — with a bite taken from its upper
edge and the letter **ل** carved out of it in negative space, plus a single orange crumb.
This is the "engraved" direction, chosen over the outlined alternative because a solid colour
mass survives the launcher icon far better: at 48px an outlined letter thins into a scratch,
while a filled disc still reads as a shape from across a home screen.

**The wordmark** is **لُقْمَة** set in **Lemonada**, with full diacritics. Lemonada is a
rounded Arabic display face designed for food and consumer brands, which puts warmth into
the name itself rather than relying on the palette to supply it. The letterforms are
converted to outlines and refined by hand — the logo is lettering, not a font call.

**The lockup** pairs the two: mark on the right, wordmark to its left, separated by one
mark-width of clear space. A stacked version — mark above, wordmark below — is the splash
and app-store form. Clear space around any lockup is never less than the height of the ل.

Constraints the mark is held to: one silhouette, readable at 48px, and correct when flattened
to a single colour. The orange crumb is dropped in the 48px and single-colour versions.

## Splash
Android 12+ imposes a system splash that cannot be disabled, which is why most apps show two.
Luqma shows one continuous splash: the system splash renders the mark on the brand background,
and Flutter's first frame continues from that exact position while the **Lemonada wordmark
with its diacritics** fades in beneath it, forming the stacked lockup.
Target ~1.5s, exited early once the app is ready.

## Photography
Photography, not the logo, is what makes a food app read as premium. Every merchant photo passes
admin approval before becoming visible, and the first 10–15 merchants are shot personally by the
owner in daylight against simple backgrounds.

## Where the name appears, and how

The brand name is **never rendered as a text widget**. Everywhere the word لقمة appears as the
brand — the home app bar, the splash, the Play Store listing, any print — it is the lockup
**drawn from a vector asset**, so its shape, spacing and diacritics are identical every time
and do not depend on a font being present.

| Surface | Asset |
|---|---|
| Home app bar | `logo_lockup_horizontal.svg`, mark at 21dp, cream on burgundy |
| Splash | `logo_lockup_stacked.svg`, cream on burgundy |
| Launcher icon | `app_icon.svg` — cream disc on a burgundy rounded square |
| Empty states, About | mark alone, or the horizontal lockup |

Everything that is *not* the brand name — screen titles, merchant names, buttons, prices — is
Cairo, rendered as ordinary text.

## Typography and numerals
Arabic-first type. **Lemonada is a logo face only** — it is never bundled as an app font and
never used by a text widget. It exists inside the app solely as the outlined paths in the
lockup SVGs. Keeping the display face out of the UI is what stops the wordmark from becoming
ordinary.
Prices use **Western Arabic numerals (150 ج)** rather than Eastern (١٥٠) — faster to scan and
less error-prone, which matches how successful Egyptian apps present prices.
