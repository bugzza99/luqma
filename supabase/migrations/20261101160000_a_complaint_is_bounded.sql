-- A complaint has an upper bound, as every other free text a customer writes now does.
--
-- `order_issues.reason` took any length. The app caps what it sends, but the table is
-- written through PostgREST with a customer's own token, and a client that ignores the
-- app's cap could put a megabyte per complaint into the admin's queue — the same cheap
-- way to fill a free-tier database that the order note's bound and the name's (A5)
-- already close. A thousand characters holds the topic line the assistant puts first and
-- the 500 the complaint field takes, with room to spare; and an empty complaint is not
-- one. The admin's note gets the same kind of bound. Production's longest complaint was
-- 22 characters when this was written.

alter table public.order_issues
  add constraint order_issues_reason_is_a_complaint
    check (char_length(btrim(reason)) between 1 and 1000),
  add constraint order_issues_admin_note_is_bounded
    check (admin_note is null or char_length(admin_note) <= 4000);
