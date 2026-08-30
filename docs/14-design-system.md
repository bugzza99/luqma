# Design System — لقمة

Platform: Flutter, Android-first, Arabic RTL only. All values are design tokens in
`luqma_core/theme`. No screen may hard-code a colour, size or duration.

## 1. Colour — measured, not assumed

The supplied palette was contrast-tested. It is strong, with three defects that must be
fixed before any screen is built.

### Verified pairs (WCAG AA needs 4.5:1 for text, 3:1 for meaningful non-text)
| Pair | Ratio | Verdict |
|---|---|---|
| White on Burgundy `#761812` | 11.0 | pass |
| Text `#130B07` on Cream `#F5EBE2` | 16.6 | pass |
| Text2 `#5A452B` on Cream | 7.7 | pass |
| Burgundy on Cream | 9.4 | pass |
| Dark text on Orange `#D67F2B` | 6.4 | pass |

### The three defects and their fixes
1. **Orange `#D67F2B` on the cream background scores 2.58:1 — it fails.** The palette
   assigns orange to prices and cream to the app background, so the two rules collide.
   Fix: prices live on **white cards only**, at **18sp bold or larger**, where `#D67F2B`
   scores 3.03 and passes the large-text threshold. For any orange text that is small, or
   that sits on cream, use the derived token **`priceStrong #995A1D`** (5.48 on white,
   4.66 on cream — passes AA outright). Same hue, deeper value.
2. **White text on an orange badge scores 3.03 — it fails for normal text.** Orange badges
   must carry **dark text `#130B07`** (6.42), never white. This is the single most common
   mistake this palette invites.
3. **Border `#D6BFA9` on cream scores 1.5:1**, far under the 3:1 required for meaningful
   boundaries. Keep it for decorative hairlines only. Interactive outlines — text fields,
   unselected chips, checkbox frames — use **`borderStrong #A5794F`** (3.28 on cream).

Also: **Surface `#E5D3C1` on cream is 1.24:1**, effectively invisible. Cards must be
**white with a soft shadow**, not surface-coloured. Surface belongs on white, as grouped
rows, skeletons, and section bands.

### Dark theme (derived and verified)
Android users on dark mode get an unusable app if this is skipped.
| Token | Value | Check |
|---|---|---|
| `bg` | `#150C08` | cream text 16.4 |
| `surface` | `#241610` | cream text 14.9 |
| `surface2` | `#33211A` | — |
| `textPrimary` | `#F5EBE2` | 14.9 on surface |
| `textSecondary` | `#C9B3A0` | 8.7 on surface |
| `accent` | `#E69B4A` | 7.6 on surface |
| `primary` (buttons) | `#8F2019` with white text | 8.8 |
| `borderStrong` | `#8A6A55` | 3.57 on surface |

### Distribution
60% cream · 25% burgundy · 10% orange · 5% dark. Orange is reserved for **prices, offers,
ratings and promotional highlights**. The moment orange becomes a general-purpose colour it
stops signalling value, and every price on every screen loses its pull.

## 2. Typography

**UI family: Cairo** (Google Fonts, Arabic + Latin, variable 200–1000). One family carries the
whole hierarchy through weight, which keeps the app coherent and the bundle small.

**Wordmark: Lemonada, as vector only.** The brand name is a `LuqmaLockup` widget backed by an
SVG asset — never a `Text('لقمة')`. That includes the app bar title on Home, which is the most
likely place for it to be typed as text by mistake. Lemonada is not a bundled font, so a text
widget could not render it correctly even if someone tried.

Arabic script sits taller and carries diacritics, so it needs more size and leading than a
Latin scale of the same rank.

| Role | Size | Weight | Line height |
|---|---|---|---|
| Screen title | 24sp | 700 | 1.35 |
| Section heading | 20sp | 700 | 1.4 |
| Card title | 17sp | 600 | 1.4 |
| Body | 15sp | 400 | 1.6 |
| Body small | 13sp | 400 | 1.6 |
| Caption | 12sp | 500 | 1.5 |
| Price | 18sp | 700 | 1.3 |
| Button | 16sp | 600 | 1.2 |

Minimum body size is **15sp, not 14** — Arabic loses legibility faster than Latin as it
shrinks. Numerals are Western (`150 ج`).

## 3. Space, shape, elevation
Spacing rhythm 4 / 8 / 12 / 16 / 24 / 32 / 48. Screen gutter 16, section gap 24.
Radius: card 12 · input and chip 10 · pill 999 · bottom sheet 16 top corners · image 12.
Elevation: cards are white on cream with `y2 blur8 rgba(19,11,7,0.06)`; pressed drops to
`y1 blur4`. No heavy Material shadows — they read as cheap against a warm palette.

> **These radii supersede the hi-fi handoff**, which asks for card 16 · field 12 · sheet
> 24. Both documents are real; this one is later and is what `Radii` implements. Checked
> again on 2026-08-30 against `design_handoff_luqma_platform/` — the two also differ on
> four dark-theme and status colours, and in every case the value here is the one carrying
> a measured contrast ratio in §1 while the handoff's carries none. Nothing was changed to
> match the handoff for that reason: it would trade verified contrast for a number nobody
> has checked. If the handoff is ever reinstated as the authority, §1's ratios have to be
> re-measured first, not assumed.

## 4. Motion
Tap ripple 100ms · page transition 300ms easeOutCubic · bottom sheet 250ms ·
list stagger 40ms per item, capped at 6 items · new-order alert pulse 800ms loop.
Every non-essential animation is skipped when the OS reports reduced motion.
Durations are tokens; one duration reused everywhere is what makes an app feel mechanical.

**Where each one lives.** The tokens are `Motion` in `luqma_core`, and until 2026-08-30
three of the five were read by nothing — the numbers were published and every screen used
Material's platform defaults instead. The page transition is
`luqmaPageTransitionsTheme`, set on the theme so no screen has to ask; the stagger is
`LuqmaEntrance`, which takes a row's index and caps the delay itself; the tap ripple is
`animationDuration` on the three button themes.

Reduced motion is honoured in two different places for one reason: `buildTransitions`
can read a `BuildContext`, but a route's `transitionDuration` is asked for before one
exists, so that reads the binding directly. Skipping only the painting would hold the
screen still for 300ms — worse than the slide it was meant to spare somebody.

## 5. Touch and feedback
Minimum target 48×48dp (Android), 8dp minimum spacing between targets. Every tappable
element shows pressed feedback within 100ms, and pressed states never change layout bounds.
Icons come from one family at one stroke width; **no emoji is ever used as an icon**.

## 6. Component inventory
`LuqmaButton` (primary/secondary/text/destructive) · `MerchantCard` · `MenuItemRow` ·
`DailyMealCard` (with remaining-quantity meter) · `PriceText` (enforces the orange rules) ·
`RatingStars` (hidden below the display threshold) · `AddressPicker` (zone, landmark and note
in one component rather than three) · `OrderStatusTimeline` · `SectionHeader` ·
`PromotionBanner` (text / image / imageWithText, one fixed 3:1 slot) · `EmptyState` ·
`LuqmaSkeleton` · `QuantityStepper` · `OrderCard` ·
`CriticalOrderSheet` · `MenuEditor` (shared by MerchantApp and AdminApp).

## 7. Screen-specific direction

**CustomerApp home** renders from `homeSections`, so the visual system must survive any
order of sections. Every section type therefore shares one header treatment and one card
width, and no section may assume it is first.
The home-kitchen section is the widest, warmest block on the screen: full-bleed horizontal
cards with the cook's name, the meal photo, the pickup window, and a remaining-quantity
meter in orange. It reads as a different kind of thing from the restaurant rows, because it is.

**MerchantApp order inbox** is an alerting surface, not a browsing surface. A new order takes
the full screen as `CriticalOrderSheet` with a burgundy field, the order total large,
a visible countdown ring, and two targets sized far above the minimum — accept and reject —
placed apart so neither is hit by accident. It stays loud until acted on.

**Courier screen** shows five things and nothing else: zone and address, landmark, customer
call button, cash to collect, and the two state buttons. It is used one-handed, outdoors,
in sunlight, so type is large and contrast is maximal.

**AdminApp** is the only dense surface: tables, filters, counts, 8dp rhythm. It is a tool,
not a storefront, and should not borrow the storefront's generosity.

## 8. Accessibility commitments
Text contrast 4.5:1 in both themes · meaningful icons and outlines 3:1 · colour is never the
only signal (order states carry an icon and a label as well as a colour) · every control has
an accessible name · dynamic text size supported without layout breakage · reduced motion
respected · safe areas respected for the bottom nav and any sticky CTA bar.
