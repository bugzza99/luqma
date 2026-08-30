-- A merchant may correct a placement they have asked for, until it starts.
--
-- `merchant_requests_promotion` grants insert and nothing else, so a merchant could ask
-- for a banner and never touch it again: a typo in the headline meant asking for a second
-- one and hoping somebody rejected the first. The admin could not help either — their
-- screen reads the *queue*, which is `status = 'requested'`, so a banner vanished from
-- their view the moment they approved it.
--
-- Two rules hold this together, and both are in the policy rather than in a screen.
--
-- **Only until it starts.** `start_at > now()` on the row as it is. A live banner is in
-- front of customers and a merchant editing one would either change what the city sees
-- without review, or — if the edit sent it back for review, which it does — take their
-- own running campaign dark mid-flight. Neither is something to offer.
--
-- **And it goes back to the queue.** `with check` forces `requested`, so an edit is a
-- fresh ask: a merchant cannot approve their own words by editing something already
-- approved. That single asymmetry is the whole promotions design — see `docs/10` — and
-- this is the place it would have leaked.
--
-- `using` judges the row that is there and `with check` the row arriving, which is why
-- both are spelled out. A policy with only `with check` would let a merchant edit
-- somebody else's banner into their own name; one with only `using` would let them write
-- `approved` straight back.
create policy merchant_edits_unstarted_promotion on promotions
  for update to authenticated
  using (
    public.is_merchant_owner(merchant_id)
    and status in ('requested', 'approved')
    and start_at > now()
  )
  with check (
    public.is_merchant_owner(merchant_id)
    and status = 'requested'
    and start_at > now()
  );
