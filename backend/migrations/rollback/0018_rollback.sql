-- =============================================================================
-- Rollback for 0018 - engineer invoicing/payment permissions
-- =============================================================================
-- Removes the engineer permission layer: every engineer_* RPC, the setter, the
-- grant helper and the grants table. Engineers immediately lose invoice and
-- payment tools; office invoicing, Stripe and every invoice/payment record are
-- untouched (0018 never changed them).
--
-- DELIBERATELY KEPT (data protection / fix):
--   * invoice_share_tokens.expires_at - dropping it would break online payment
--     again (invoice-payment selects it).
--   * vehicles table, jobs.vehicle_id, set_job_vehicle - holds customer data;
--     never deleted. Drop manually only after exporting it.
--   * app_trade values 'propertyServices' / 'automotive' - Postgres can't drop
--     enum values, and companies may already use them.
-- =============================================================================

begin;

drop function if exists public.engineer_invoice_payment_link(uuid);
drop function if exists public.engineer_invoice_email_settle(uuid, boolean, text, text);
drop function if exists public.engineer_invoice_email_prepare(uuid, text);
drop function if exists public.engineer_issue_invoice(uuid);
drop function if exists public.engineer_delete_invoice_line(uuid, uuid);
drop function if exists public.engineer_save_invoice_line(uuid, uuid, text, numeric, numeric);
drop function if exists public.engineer_create_invoice_from_job(uuid);
drop function if exists public.engineer_job_invoice(uuid);
drop function if exists public.engineer_share_token(uuid, uuid);
drop function if exists public.engineer_scoped_invoice(uuid);
drop function if exists public.has_engineer_financial_grant(text);
drop function if exists public.set_member_financial_permissions(uuid, boolean, boolean);
drop table if exists public.member_financial_permissions;

commit;
