# Data Model — Firestore Collections

All city-scoped documents carry `cityId`. All carry `createdAt` / `updatedAt`.
This model was simplified after the first pass; see `15-simplifications.md` for what merged and why.

## Identity & Geography
- **cities** — `{name, isActive}`. Launch contains only Edku.
- **zones** — `{cityId, name, defaultDeliveryFee, isActive, sortOrder}`. Zones are the
  addressing primitive. They replace map accuracy, which is poor in Edku.
- **landmarks** — `{cityId, zoneId, name, lat, lng, icon}`. Admin-defined named points
  rendered on the branded map so couriers do not circle. Stored in Firestore, not Google Places,
  so they cost nothing.
- **users** — `{googleUid, name, phone, isBlocked, rejectedOrdersCount, fcmTokens[], defaultAddressId}`.
  Auth is Google Sign-In; phone is captured at first order and unverified until OTP is switched on.
- **users/{uid}/addresses** — `{zoneId, street, landmarkId, landmarkNote, building, floor, apartment, label, lat, lng}`.
- **staff** — one collection for every non-customer account.
  `{uid, scope: platform|merchant, merchantId, role: admin|moderator|owner|courier, name, phone, isActive}`.
  A platform-scope courier serves home kitchens and merchants that do not deliver; a
  platform-scope admin is mirrored to a Firebase custom claim. Merging what were previously
  `merchantStaff` and `adminUsers` removes a duplicate identity shape and a duplicate rule set.

## Supply
- **merchants** — `{cityId, type: restaurant|homeKitchen, name, logoMediaId, coverMediaId, zoneId,
  servedZones[], phone, workingHours[], pausedUntil, status: pending|approved|suspended,
  ownerUid, deliversSelf, menuCategories[], planId, revenueModel{type, value}, walletBalance,
  deliveryFeeOverride, minOrder, ratingAvg, ratingCount}`.
  - `menuCategories` is an ordered inline array `[{id, name, sortOrder}]`, not a collection.
    A menu has five to ten categories; a separate collection bought one extra read per
    merchant screen and nothing else.
  - `pausedUntil` is a timestamp, not a boolean. A merchant who taps "busy" during a rush
    recovers automatically; a boolean produces merchants stuck closed for days and the
    support calls that follow.
  - Whether a merchant can take an order right now is **derived**, never stored:
    `approved && withinWorkingHours(now) && (pausedUntil == null || pausedUntil < now)`.
- **menuItems** — `{merchantId, categoryId, name, description, price, mediaId,
  isAvailable, options[], sortOrder}`.
- **dailyMeals** — home kitchen pre-order unit. `{merchantId, name, description, mediaId, price,
  date, totalQty, remainingQty, pickupWindowStart, pickupWindowEnd,
  deliveryOption: pickup|platformCourier|sellerArrangement, status}`.
- **media** — every uploaded image in the system, whatever it belongs to.
  `{ownerType: merchantLogo|merchantCover|menuItem|dailyMeal|promotion, ownerId, url, thumbUrl,
  width, height, bytes, status: pending|approved|rejected, uploadedBy, reviewedBy}`.
  One collection means one moderation queue, one compression trigger, and one security rule
  instead of an `imageStatus` field scattered across four collections.

## Demand
- **orders** — `{orderNumber, cityId, customerUid, customerName, customerPhone, isNewCustomer,
  merchantId, merchantName, type: instant|preorder, items[], subtotal, deliveryFee, discount, total,
  paymentMethod: cash, address{}, zoneId, status, statusHistory[], acceptDeadlineAt,
  courierUid, cancelReason, cancelledBy, couponCode,
  pricing{subtotal, deliveryFee, subtotalDiscount, deliveryDiscount, total,
  platformOwesMerchant}, revenueSnapshot{model, value, amount}}`.
  `revenueSnapshot` freezes the revenue model at order time so later admin changes never
  rewrite historical accounting.
- **orderIssues** — `{orderId, customerUid, merchantId, type, description, status, adminNote}`.
- **ratings** — `{orderId, merchantId, customerUid, stars, comment, isCommentPublic}`.
  Stars aggregate publicly; comments stay private to merchant and admin until a flag opens them.

## Monetization
- **plans** — `{name, priceMonthly, features{maxItems, verifiedBadge, analytics, boostRank,
  homeBannerSlots, monthlyPromotionCount}, sortOrder, isActive}`. Three plans: Free, Basic, Premium.
- **subscriptions** — `{merchantId, planId, startAt, endAt, status, paidAmount, recordedByAdminUid}`.
- **promotions** — every paid placement a merchant buys, on any channel.
  `{merchantId, channel: homeBanner|categoryBanner|boost|push,
  renderMode: text|image|imageWithText, mediaId, title, body,
  targetMerchantId, sectionKey, audience{zoneIds|all}, startAt, endAt, priority, price,
  status: requested|approved|active|rejected|ended, requestedBy, approvedBy,
  impressions, clicks}`.
  - `renderMode` decides how a banner is drawn, so the same document covers a merchant with
    professional artwork and one with none:
    **`text`** — brand gradient plus `title` and `body`, no artwork needed;
    **`image`** — full-bleed artwork that carries its own message;
    **`imageWithText`** — artwork behind a burgundy scrim with `title` and `body` over it.
  - Any `mediaId` is a `media` document at a fixed **3:1** aspect ratio, and like every other
    image it is invisible until the admin approves it. Fixing the ratio and forcing the scrim
    on `imageWithText` is what keeps a merchant's own artwork from breaking the home screen —
    the two ways a self-serve banner slot normally ruins an app are wrong proportions and
    unreadable text over a busy photo.
  Banners, boosts and push campaigns were three shapes doing one job: a merchant buys a slot,
  the admin approves it, it runs between two dates for a price. One collection replaces two,
  along with one scheduler, one admin module and one merchant screen.
  Ad placement is expressed by the `adSlot` home section that renders it — there is no
  separate placements collection.

- **coupons** — discount codes.
  `{code, cityId, type: percentage|fixedAmount|freeDelivery, value, maxDiscount, minOrder,
  merchantId, firstOrderOnly, perUserLimit, totalLimit, usedCount, isActive,
  validFrom, validUntil, fundedBy: merchant|platform, createdByUid}`.
  - `value` is basis points for a percentage and piastres for a fixed amount. **All money
    in the system is integer piastres** — a discount computed in floating point eventually
    hands a courier a figure one piastre off the merchant's, and neither can prove which
    is right.
  - `maxDiscount` is **mandatory for a percentage**. Without it a 15% code applied to a
    2000 EGP party order costs the merchant 300 EGP against the 30 they had in mind. A
    percentage coupon with no ceiling is rejected rather than applied.
  - `fundedBy` exists because money here is collected in cash at the door: a discount is
    simply less cash reaching the merchant. A merchant-funded coupon settles itself; a
    platform-funded one is a **debt to the merchant from the moment the order is placed**,
    accrued onto the order as `pricing.platformOwesMerchant` rather than reconstructed at
    month end.
  - Codes are matched normalised — trimmed, upper-cased, and with Arabic-Indic digits
    folded to Western ones, because a phone with an Arabic keyboard types ٢٠٢٦ where the
    coupon was created as 2026 and the customer cannot see the difference.
- **couponRedemptions** — `{couponId, code, userUid, orderId, discount, at}`. One document
  per use, which is what makes `perUserLimit` enforceable server-side.

## Control plane
- **homeSections** — `{key, titleAr, type, sortOrder, isVisible, cityId, params{}}`.
  Drives the composition of the customer home screen from AdminApp. An `adSlot` section's
  `params` carry `maxAds` and `rotationSeconds`, so the section *is* the ad placement.
- **config/appConfig** — single document. Feature flags, numeric limits, support channel, force-update.
- **auditLog** — `{actorUid, action, targetPath, before, after, at}`. Every admin mutation writes here.
- **counters** — atomic sequence source for human-readable `orderNumber`.
