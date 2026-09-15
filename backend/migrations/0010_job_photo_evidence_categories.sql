-- =============================================================================
-- 0010 — Job photo evidence categories
-- =============================================================================
--
-- WHY
-- Field service photographs are evidence, and the category is part of the
-- evidence. "This is what the property looked like before we attended" and
-- "this is the damage we found" answer different questions, and a property
-- management customer disputing an invoice cares which one they are looking at.
--
-- The original enum carried only before / after / part / proof (+ signature,
-- added by 0002). That covers the work but not the condition: there was nowhere
-- to file damage, existing property condition, equipment identification, or
-- work in progress.
--
-- WHAT THIS DOES
-- Adds five labels to `public.job_photo_kind`:
--     during             work in progress
--     equipment          plant, rating plates, serial numbers
--     damage             damage discovered or caused
--     property_condition the state of the property, typically on arrival
--     other              deliberately uncategorised
--
-- WHAT THIS DOES NOT DO
-- No column changes, no data rewrite, no policy changes, no new table. Existing
-- rows keep their existing labels and every current RLS policy on `job_photos`
-- and on the `job-media` storage bucket continues to apply unchanged — company
-- scoping for photographs is unaffected by this migration.
--
-- SAFETY
-- `alter type ... add value` is additive and non-blocking, and each statement is
-- guarded so re-running this file is harmless. Adding an enum value cannot
-- invalidate existing rows.
--
-- COMPATIBILITY
-- An app build that predates this migration will not know the new labels. The
-- client decodes an unrecognised `job_photo_kind` as "Other" rather than failing
-- the record, so an older build reading a newer row degrades to a sensible
-- label instead of dropping a job's photo list. In the other direction, a newer
-- app writing to a database where this has not yet been applied retries the
-- insert with a label the enum has always contained, so a photograph is never
-- lost to a schema lag.
--
-- Run this against the project database before relying on the new categories.
-- =============================================================================

do $$
declare
  v_label text;
begin
  foreach v_label in array array['during', 'equipment', 'damage', 'property_condition', 'other']
  loop
    if not exists (
      select 1
      from pg_enum e
      join pg_type t on t.oid = e.enumtypid
      where t.typname = 'job_photo_kind'
        and e.enumlabel = v_label
    ) then
      execute format('alter type public.job_photo_kind add value %L', v_label);
    end if;
  end loop;
end $$;

comment on type public.job_photo_kind is
  'What a job photograph is evidence of. before/during/after describe the work; equipment, damage and property_condition describe what was found; part and proof support the invoice; signature is written by the completion flow only; other is deliberately uncategorised.';
