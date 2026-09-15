-- ============================================================================
-- READ-ONLY PRODUCTION INSPECTION
-- Messaging image attachments + job visual evidence
-- ============================================================================
--
-- PURPOSE
--   Recover the real production security model for the tables that a future
--   migration would touch, so the migration is designed against fact rather
--   than against the migration files in this repository.
--
-- SAFETY
--   This script contains exactly ONE statement: a SELECT over the system
--   catalogues. It performs no ALTER, CREATE, DROP, INSERT, UPDATE, DELETE,
--   GRANT, or REVOKE. It writes nothing and locks nothing. It is safe to run
--   against production at any time.
--
-- OUTPUT
--   One single result set, so the whole thing can be copied out in one go.
--   Columns: sort_key | section | object | detail (jsonb)
--
-- SECTIONS
--   A  RLS policies on job_photos / office_threads / office_messages
--   B  RLS enabled + forced state (a policy is inert if RLS is off)
--   C  Columns: job_id nullability, defaults, whether thread_id exists
--   D  Constraints: primary key, foreign keys, unique, check
--   E  Indexes
--   F  storage.buckets row for 'job-media'
--   G  RLS policies on storage.objects (the storage policies)
--   H  Bodies of the helper functions the policies call
--   I  job_photo_kind enum labels (confirms whether migration 0010 is applied)
--   J  Table grants per role
-- ============================================================================

with target_tables as (
    select c.oid, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('job_photos', 'office_threads', 'office_messages')
)

-- A. RLS POLICIES ------------------------------------------------------------
select
    1                                              as sort_key,
    'A. RLS POLICY'                                as section,
    p.tablename || ' / ' || p.policyname           as object,
    jsonb_build_object(
        'schema',      p.schemaname,
        'table',       p.tablename,
        'policy',      p.policyname,
        'command',     p.cmd,
        'permissive',  p.permissive,
        'roles',       p.roles::text,
        'qual',        p.qual,
        'with_check',  p.with_check
    )                                              as detail
from pg_policies p
where p.schemaname = 'public'
  and p.tablename in ('job_photos', 'office_threads', 'office_messages')

union all

-- B. RLS ENABLED / FORCED ----------------------------------------------------
select
    2,
    'B. RLS STATE',
    c.relname,
    jsonb_build_object(
        'rls_enabled',  c.relrowsecurity,
        'rls_forced',   c.relforcerowsecurity,
        'table_owner',  pg_get_userbyid(c.relowner),
        'policy_count', (
            select count(*) from pg_policies p2
            where p2.schemaname = 'public' and p2.tablename = c.relname
        )
    )
from pg_class c
join target_tables t on t.oid = c.oid

union all

-- C. COLUMNS -----------------------------------------------------------------
select
    3,
    'C. COLUMN',
    t.relname || '.' || a.attname,
    jsonb_build_object(
        'ordinal',   a.attnum,
        'type',      format_type(a.atttypid, a.atttypmod),
        'not_null',  a.attnotnull,
        'default',   pg_get_expr(ad.adbin, ad.adrelid),
        'identity',  nullif(a.attidentity::text, '')
    )
from pg_attribute a
join target_tables t on t.oid = a.attrelid
left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
where a.attnum > 0
  and not a.attisdropped

union all

-- D. CONSTRAINTS -------------------------------------------------------------
select
    4,
    'D. CONSTRAINT',
    t.relname || ' / ' || con.conname,
    jsonb_build_object(
        'type', case con.contype
                    when 'p' then 'PRIMARY KEY'
                    when 'f' then 'FOREIGN KEY'
                    when 'u' then 'UNIQUE'
                    when 'c' then 'CHECK'
                    when 'x' then 'EXCLUDE'
                    else con.contype::text
                end,
        'definition',   pg_get_constraintdef(con.oid),
        'deferrable',   con.condeferrable,
        'validated',    con.convalidated
    )
from pg_constraint con
join target_tables t on t.oid = con.conrelid

union all

-- E. INDEXES -----------------------------------------------------------------
select
    5,
    'E. INDEX',
    i.tablename || ' / ' || i.indexname,
    jsonb_build_object('definition', i.indexdef)
from pg_indexes i
where i.schemaname = 'public'
  and i.tablename in ('job_photos', 'office_threads', 'office_messages')

union all

-- F. STORAGE BUCKET ----------------------------------------------------------
select
    6,
    'F. STORAGE BUCKET',
    b.id,
    to_jsonb(b) - 'owner' - 'owner_id'
from storage.buckets b
where b.id = 'job-media'

union all

-- G. STORAGE POLICIES --------------------------------------------------------
select
    7,
    'G. STORAGE POLICY',
    p.tablename || ' / ' || p.policyname,
    jsonb_build_object(
        'schema',      p.schemaname,
        'table',       p.tablename,
        'policy',      p.policyname,
        'command',     p.cmd,
        'permissive',  p.permissive,
        'roles',       p.roles::text,
        'qual',        p.qual,
        'with_check',  p.with_check
    )
from pg_policies p
where p.schemaname = 'storage'
  and p.tablename in ('objects', 'buckets')

union all

-- H. HELPER FUNCTION BODIES --------------------------------------------------
--    The policies above are only meaningful together with these.
select
    8,
    'H. FUNCTION',
    f.proname || '(' || pg_get_function_identity_arguments(f.oid) || ')',
    jsonb_build_object(
        'security_definer', f.prosecdef,
        'volatility',       f.provolatile::text,
        'search_path',      coalesce(array_to_string(f.proconfig, ' | '), '(not pinned)'),
        'definition',       pg_get_functiondef(f.oid)
    )
from pg_proc f
join pg_namespace n on n.oid = f.pronamespace
where n.nspname = 'public'
  and f.prokind = 'f'
  and f.proname in (
        'current_company_id',
        'has_perm',
        'is_assigned_to_job',
        'is_office_user',
        'send_office_message',
        'mark_office_thread_read'
      )

union all

-- I. job_photo_kind ENUM LABELS ----------------------------------------------
select
    9,
    'I. ENUM',
    ty.typname,
    jsonb_build_object(
        'labels', (
            select jsonb_agg(e.enumlabel order by e.enumsortorder)
            from pg_enum e
            where e.enumtypid = ty.oid
        )
    )
from pg_type ty
join pg_namespace n on n.oid = ty.typnamespace
where n.nspname = 'public'
  and ty.typname in ('job_photo_kind', 'app_permission')

union all

-- J. TABLE GRANTS ------------------------------------------------------------
select
    10,
    'J. GRANTS',
    g.table_name || ' / ' || g.grantee,
    jsonb_build_object(
        'privileges', string_agg(distinct g.privilege_type, ', ' order by g.privilege_type)
    )
from information_schema.role_table_grants g
where g.table_schema = 'public'
  and g.table_name in ('job_photos', 'office_threads', 'office_messages')
group by g.table_name, g.grantee

order by sort_key, object;
