# Simplification Pass

Applied to the design after the dependency graph exposed three weakly-cohesive clusters and
thirty thinly-connected nodes. Nothing here changes what the product does; every item removes
work, a moving part, or a step.

## Merged

**`merchantStaff` + `adminUsers` → `staff`.** Two collections existed to attach a role to a
uid. One collection with `scope` and `role` replaces both, along with a duplicated set of
security rules and two near-identical admin screens.

**`ads` + `pushCampaigns` → `promotions`.** Both were: a merchant buys a slot, the admin
approves it, it runs between two dates for a price. A push campaign is a promotion whose
channel is a notification. One collection removes a second admin queue, a second merchant
request screen, and a second expiry pass.

**Three daily schedulers → one `dailyMaintenance`.** Subscription expiry, ad expiry and meal
rollover were three functions waking at the same hour to make three independent passes.

**Two menu editors → one `MenuEditor` in `luqma_core`.** MerchantApp and AdminApp were
specified to edit the same data through separate implementations. They now share one widget
and differ only in where `merchantId` comes from.

**`ZonePicker` + `LandmarkPicker` + `AddressCard` → `AddressPicker`.** One address, one
component.

## Removed

**`adPlacements`.** An `adSlot` home section already defines where ads appear and in what
order. The placements collection restated that in a second place, which is how the two drift
apart. Rotation and the max-ads cap moved into the section's `params`.

**`categories` collection.** A menu has five to ten categories. As an inline ordered array on
`merchants` it costs one fewer read on every merchant screen and one fewer collection to
secure.

**The Categories tab.** Edku will have on the order of thirty merchants — not enough to fill
a tab. Categories became a chip row inside Home. Three tabs instead of four means larger
targets and one less place to get lost.

**The one-minute accept-timeout cron.** It would have run roughly 43,000 times a month to
service perhaps fifty orders a day. One delayed task enqueued per order runs exactly as often
as there are orders. The countdown the merchant watches is client-side arithmetic on
`acceptDeadlineAt` and never needed a server tick.

## Generalized

**`imageStatus` on four collections → a `media` collection.** Moderation was specified only
for menu photos, but logos, covers, meal photos and promotion banners are images too. Adding
a status field to each one would have meant four rules, four triggers and four queues. One
`media` collection gives one of each — and it means the moderation gate cannot be bypassed by
uploading through a path nobody remembered to guard.

**`isOpen` + `isTemporarilyClosed` + `workingHours` → a derived predicate plus `pausedUntil`.**
Three fields expressed one question: can this merchant take an order right now? It is now
computed, never stored, so the three can never disagree. And `pausedUntil` is a timestamp
rather than a boolean, so a merchant who taps "busy" during a rush reopens automatically
instead of staying invisible until they remember.

## Flagged, not changed

**The `prepaid` revenue branch.** All three revenue models stay switchable per merchant, as
decided. But `subscription` and `commission` are a few lines each, while `prepaid` needs a
wallet balance, top-up recording and intake suspension — and nothing uses it until online
payment exists. The recommendation is to ship it as a stub behind the same switch and fill it
in when it is actually needed. This is a call for the owner, not a change made unilaterally.
