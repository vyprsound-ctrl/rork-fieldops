-- =============================================================================
-- Harbour South FieldOps — Founding 100 allocation suite
-- (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- Proves, against the real claim function and the real commercial-state read:
--
--   * the 99th, 100th and 101st qualifying companies get places 99, 100 and
--     none;
--   * an ineligible company (Stripe not charge-ready) never gets a place;
--   * a duplicate claim returns the company's existing place;
--   * a claimed place is never reissued after its company is deleted — before
--     or after the hundred are gone — and still counts as taken;
--   * an eligible non-member is offered the programme while places remain,
--     and is not once all hundred have been allocated;
--   * an existing member keeps its status after place 100 is allocated;
--   * an allocated place cannot be reassigned, un-claimed or deleted;
--   * the platform fee the state reports is still the configured rate.
--
-- Simultaneous claims need two real connections and are proved separately by
-- `founding-member-concurrency.sh`.
--
-- PRECONDITION: no founding place has been allocated yet (the suite claims
-- all hundred). It fails loudly rather than guessing if that is not so.
--
-- HOW TO RUN
-- ----------
-- Run the whole file as one batch. The runner always ends in `raise
-- exception`, so every fixture row and every claim is rolled back and the
-- report comes back in the error message. FAIL=0 is a pass.
-- =============================================================================

create or replace function pg_temp.run_founding_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  v_base      integer;
  v_ids       uuid[] := array[]::uuid[];
  v_id        uuid;
  v_ineligible uuid;
  v_n         integer;
  v_ok        boolean;
  v_numbers   integer[] := array[]::integer[];
  v_state     record;
  v_err       text;
  i           integer;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  select count(*) into v_base from public.founding_member_slots where claimed_at is not null;
  test_name := 'Precondition: no place allocated yet';
  passed := v_base = 0; detail := 'already allocated=' || v_base;
  return next;
  if v_base <> 0 then return; end if;

  -- 103 charge-ready companies and one that is not.
  for i in 1..103 loop
    insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('FOUNDSUITE Co ' || i, 'hvac', 'US', 'USD', 'America/New_York')
    returning id into v_id;
    insert into public.stripe_connect_accounts (company_id, stripe_account_id, charges_enabled, payouts_enabled, details_submitted)
    values (v_id, 'acct_FOUNDSUITE_' || i, true, true, true);
    v_ids := v_ids || v_id;
  end loop;

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('FOUNDSUITE Not Ready', 'hvac', 'US', 'USD', 'America/New_York')
  returning id into v_ineligible;
  insert into public.stripe_connect_accounts (company_id, stripe_account_id, charges_enabled)
  values (v_ineligible, 'acct_FOUNDSUITE_notready', false);

  -- ---- Qualification requirement unchanged
  v_n := public.claim_founding_member_slot(v_ineligible);
  test_name := 'A company Stripe has not made charge-ready gets no place';
  passed := v_n is null; detail := 'got=' || coalesce(v_n::text, 'null');
  return next;

  -- ---- Places 1..50 in order
  for i in 1..50 loop
    v_numbers := v_numbers || public.claim_founding_member_slot(v_ids[i]);
  end loop;
  select bool_and(v_numbers[k] = k) into v_ok from generate_series(1, 50) k;
  test_name := 'The first fifty qualifying companies take places 1-50 in order';
  passed := coalesce(v_ok, false); detail := 'last=' || coalesce(v_numbers[50]::text, 'null');
  return next;

  -- ---- Duplicate claim
  v_n := public.claim_founding_member_slot(v_ids[37]);
  select count(*) into i from public.founding_member_slots where company_id = v_ids[37];
  test_name := 'A duplicate claim returns the existing place and takes no other';
  passed := v_n = 37 and i = 1; detail := 'got=' || coalesce(v_n::text, 'null') || ' held=' || i;
  return next;

  -- ---- Deletion before the hundred are gone
  delete from public.companies where id = v_ids[10];
  select (company_id is null and claimed_at is not null) into v_ok
    from public.founding_member_slots where number = 10;
  test_name := 'Deleting place 10''s company leaves place 10 retired, not free';
  passed := coalesce(v_ok, false); detail := 'retired=' || coalesce(v_ok::text, 'null');
  return next;

  v_n := public.claim_founding_member_slot(v_ids[51]);
  test_name := 'The next qualifying company gets place 51, never the retired place 10';
  passed := v_n = 51; detail := 'got=' || coalesce(v_n::text, 'null');
  return next;

  select * into v_state from public.company_commercial_state(v_ids[101]);
  test_name := 'A deleted company''s place still counts as taken';
  passed := v_state.founding_places_claimed = 51 and v_state.founding_places_remaining = 49;
  detail := 'claimed=' || v_state.founding_places_claimed || ' remaining=' || v_state.founding_places_remaining;
  return next;

  -- ---- Up to 98
  for i in 52..98 loop
    perform public.claim_founding_member_slot(v_ids[i]);
  end loop;

  -- ---- Position 99
  v_n := public.claim_founding_member_slot(v_ids[99]);
  test_name := 'Position 99: the 99th allocation is place 99';
  passed := v_n = 99; detail := 'got=' || coalesce(v_n::text, 'null');
  return next;

  select * into v_state from public.company_commercial_state(v_ids[101]);
  test_name := 'While a place remains, an eligible non-member is offered the programme';
  passed := v_state.founding_member_number is null
            and v_state.founding_offer_open
            and v_state.founding_places_remaining = 1;
  detail := 'member=' || coalesce(v_state.founding_member_number::text, 'null')
         || ' offerOpen=' || v_state.founding_offer_open
         || ' remaining=' || v_state.founding_places_remaining;
  return next;

  -- ---- Position 100
  v_n := public.claim_founding_member_slot(v_ids[100]);
  test_name := 'Position 100: the 100th allocation is place 100';
  passed := v_n = 100; detail := 'got=' || coalesce(v_n::text, 'null');
  return next;

  -- ---- Position 101
  v_n := public.claim_founding_member_slot(v_ids[101]);
  test_name := 'Position 101: the 101st qualifying company gets no place';
  passed := v_n is null; detail := 'got=' || coalesce(v_n::text, 'null');
  return next;

  select * into v_state from public.company_commercial_state(v_ids[101]);
  test_name := 'After the hundredth allocation a non-member is not offered the programme';
  passed := v_state.founding_member_number is null
            and not v_state.founding_offer_open
            and not v_state.founding_benefit_active
            and v_state.founding_places_remaining = 0;
  detail := 'member=' || coalesce(v_state.founding_member_number::text, 'null')
         || ' offerOpen=' || v_state.founding_offer_open
         || ' remaining=' || v_state.founding_places_remaining;
  return next;

  -- ---- Retention
  select * into v_state from public.company_commercial_state(v_ids[1]);
  test_name := 'Member #1 keeps Founding Member status after place 100 is allocated';
  passed := v_state.founding_member_number = 1 and v_state.founding_claimed_at is not null;
  detail := 'member=' || coalesce(v_state.founding_member_number::text, 'null');
  return next;

  select * into v_state from public.company_commercial_state(v_ids[100]);
  test_name := 'Member #100 keeps Founding Member status too';
  passed := v_state.founding_member_number = 100;
  detail := 'member=' || coalesce(v_state.founding_member_number::text, 'null');
  return next;

  -- ---- Deletion after the hundred are gone
  delete from public.companies where id = v_ids[37];
  v_n := public.claim_founding_member_slot(v_ids[102]);
  test_name := 'After a member is deleted, place 37 is not reissued to company #102';
  passed := v_n is null; detail := 'got=' || coalesce(v_n::text, 'null');
  return next;

  select * into v_state from public.company_commercial_state(v_ids[103]);
  test_name := 'The offer stays closed after a member is deleted';
  passed := not v_state.founding_offer_open and v_state.founding_places_claimed = 100;
  detail := 'offerOpen=' || v_state.founding_offer_open || ' claimed=' || v_state.founding_places_claimed;
  return next;

  select count(*) into i from public.founding_member_slots where claimed_at is not null;
  test_name := 'Exactly 100 places were ever allocated';
  passed := i = 100; detail := 'allocated=' || i;
  return next;

  -- ---- The guard
  begin
    update public.founding_member_slots set company_id = v_ids[102] where number = 37;
    v_err := 'no error';
  exception when others then v_err := sqlstate;
  end;
  test_name := 'A retired place cannot be reassigned directly';
  passed := v_err = 'TD409'; detail := v_err;
  return next;

  begin
    update public.founding_member_slots set company_id = null, claimed_at = null where number = 5;
    v_err := 'no error';
  exception when others then v_err := sqlstate;
  end;
  test_name := 'An allocated place cannot be un-claimed';
  passed := v_err = 'TD409'; detail := v_err;
  return next;

  begin
    delete from public.founding_member_slots where number = 5;
    v_err := 'no error';
  exception when others then v_err := sqlstate;
  end;
  test_name := 'An allocated place cannot be deleted';
  passed := v_err = 'TD409'; detail := v_err;
  return next;

  -- ---- Fee unchanged
  select * into v_state from public.company_commercial_state(v_ids[1]);
  test_name := 'The platform fee reported is still the configured 30 basis points';
  passed := v_state.platform_fee_bps = (
    select (value #>> '{}')::integer from public.platform_settings where key = 'application_fee_bps'
  ) and v_state.platform_fee_bps = 30;
  detail := 'bps=' || v_state.platform_fee_bps;
  return next;
end;
$function$;

do $$
declare rec record; v_pass int := 0; v_fail int := 0; v_report text := '';
begin
  for rec in select * from pg_temp.run_founding_tests() loop
    if rec.passed then v_pass := v_pass + 1; else v_fail := v_fail + 1; end if;
    v_report := v_report || case when rec.passed then 'PASS  ' else 'FAIL  ' end
             || rec.test_name || '  [' || coalesce(rec.detail, '') || ']' || E'\n';
  end loop;
  raise exception E'FOUNDING SUITE — PASS=% FAIL=%\n%', v_pass, v_fail, v_report;
end $$;
