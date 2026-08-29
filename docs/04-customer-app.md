# CustomerApp

Flutter Android app. Depends on `luqma_core`. Arabic RTL only.

## Navigation — 3 bottom tabs
`الرئيسية` (Home) · `طلباتي` (Orders) · `حسابي` (Account)

There is no Categories tab. Edku will have on the order of thirty merchants, which a
category tab cannot fill; categories become a chip row inside Home, and search covers the
rest. Three tabs give larger targets and one less place to be lost in.

Home Kitchen is a **large prominent section at the top of Home**, not a tab — it is the
differentiator and must be seen without a tap.

## Screens
- **Splash** — single continuous splash. The Android system splash shows the mark on the brand
  background; the Flutter first frame continues from that exact position and the wordmark fades in
  beneath it, forming the stacked lockup. Total ~1.5s, cut short as soon as the app is ready.
- **App bar** — the horizontal `LuqmaLockup` on the right, the selected delivery zone on the
  left. The lockup is the SVG asset, not text.
- **Home** — a fixed search bar, then every remaining block rendered from `homeSections`:
  `categoryChips`, `adSlot`, "أكل بيتي النهارده" (`homeKitchenToday`), `mostOrdered`,
  `merchantList`. Only the search bar is fixed chrome; everything below it is admin-ordered,
  including the category chips.
- **Merchant** — cover, rating (hidden below `minRatingsToShow`), working hours, menu by category.
- **Item detail** — options, quantity, notes.
- **Cart** — merchant-scoped, shows subtotal, delivery fee resolved from zone, minimum order check.
- **Address picker** — one `AddressPicker` component: zone, landmark, free-text note,
  building/floor/apt, optional branded map pin. Zone drives delivery fee and merchant
  availability.
- **Checkout** — cash only, order summary, place order.
- **Order tracking** — status timeline, merchant phone, "في مشكلة في الطلب" button creating an `orderIssue`.
- **Orders history**, **Ratings prompt** after delivery, **Account** with addresses, notification
  preferences (marketing only), WhatsApp support link.

## Auth
**Phone number and a password.** The number is the identity — it is what the courier calls
and what the admin searches — so it is what a customer types to sign in, plus a password of
their own. Signing up asks for a name as well, and nothing else. There is no email field
anywhere in CustomerApp, and no Google Sign-In: that was removed before launch rather than
carried, because it made the first screen of the app depend on a Play Console account, an
OAuth client keyed on a release fingerprint, and a Google account the customer may not have.

GoTrue's *phone* identity is not what carries this. It requires an SMS provider — the CLI
refuses to enable it without one, even where no code is ever sent — so the number is folded
into a synthetic address (`01012345678@phone.luqma.app`, `Phone.toAccountEmail`) and GoTrue
holds an ordinary email identity. That domain has no mailbox and nothing is ever sent to it.
The real number travels in the signup metadata, and `ensure_user_profile` copies it onto the
`users` row, where `place_order` reads it.

Every spelling of one number has to fold to one address, or a customer with an Arabic
keyboard gets a second account and loses their history. `Phone.normalize` is that one
spelling, and is shared with validation and with the admin's customer search.

**The number is captured, not verified.** Somebody can sign up with a number that is not
theirs; the password is what protects the account. That is the accepted trade at launch.
When `otpEnabled` flips on, OTP becomes a verification layer over the same account — no user
loses their history or addresses.

**A forgotten password has one way back: an admin.** There is no mailbox to send a link to
and no SMS to send a code by, so a customer calls the number on حول لقمة and an admin issues
a new password from the customers screen (`reset-customer-password`). It is generated rather
than typed, out of an alphabet with no `l`/`1`/`O`/`0`, because it is read down a phone line.

**Knowing the number must not be the proof.** Follow the two facts above to their
conclusion and this is an account takeover: the number is not verified at signup, and a
person who can name one gets a new password for it. What stands between the two is an
admin on a phone call, and an admin who asks for nothing is not a control.

Until `otpEnabled` flips on, the admin asks for something only the account holder can
know before resetting: **the last order — roughly when, and roughly what it cost** — or,
for an account that has never ordered, the saved address. Both are in front of the admin
on the customer's own screen, and neither is guessable from a phone number. This is a
procedure, not code, which is exactly its weakness; OTP replaces it rather than adding to
it, and the account survives the change with its history and addresses intact.

The function's own guards are separate from this and stay: the caller must be an active
platform admin, the new password is returned once and never stored, and a uid with a
`staff` row is refused outright — a support call must not become a way to reset another
admin.

## Promotions surface
Renders `promotions` in `adSlot` sections and boosted merchants in listings, through one
`PromotionBanner` component that switches on `renderMode`: `text` on a burgundy gradient,
`image` full-bleed, or `imageWithText` with a scrim. All three occupy the same 3:1 slot, so a
section's height never jumps as banners rotate. AdMob widgets exist behind `admobEnabled` and
render nothing while it is off.
