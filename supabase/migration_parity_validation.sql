-- Migration parity validation pack (read-only).
-- Run in Supabase SQL Editor as project owner.
-- Ziel: pruefen, ob Live-DB zum Repo-Sollstand passt.

-- 1) Core function existence + security definer
with expected_functions(function_name, identity_args, expect_security_definer) as (
  values
    ('require_operator_or_owner', '', true),
    ('reserve', 'box_id integer', true),
    ('cancel_reservation', 'box_id integer', true),
    ('activate', 'box_id integer, amount integer', true),
    ('stop', 'session_id text', true),
    ('status', 'box_id integer', true),
    ('recent_sessions', 'max_rows integer', true),
    ('expire_active_sessions_internal', '', true),
    ('expire_active_sessions', '', true),
    ('monitoring_snapshot', '', true),
    ('top_up', 'amount integer', true),
    ('loyalty_status', '', true),
    ('record_purchase', '', true),
    ('activate_reward', 'box_id integer', true),
    ('get_box_cleaning_plan', 'cleaning_interval integer', true),
    ('get_box_cleaning_history', 'box_id integer, max_rows integer', true),
    ('mark_box_cleaned', 'box_id integer, note text', true),
    ('list_operator_actions_filtered', 'max_rows integer, offset_rows integer, filter_status text, filter_box_id integer, search_query text, from_ts timestamp with time zone, until_ts timestamp with time zone', true),
    ('get_operator_threshold_settings', '', true),
    ('set_operator_threshold_settings', 'cleaning_interval_washes integer, long_active_minutes integer', true),
    ('kpi_export', 'period text', true)
),
resolved as (
  select
    e.function_name,
    e.identity_args,
    e.expect_security_definer,
    p.oid is not null as exists_in_db,
    coalesce(p.prosecdef, false) as is_security_definer
  from expected_functions e
  left join pg_proc p
    on p.pronamespace = 'public'::regnamespace
   and p.proname = e.function_name
   and pg_get_function_identity_arguments(p.oid) = e.identity_args
)
select
  function_name,
  identity_args,
  exists_in_db,
  is_security_definer,
  (exists_in_db and is_security_definer = expect_security_definer) as ok
from resolved
order by function_name, identity_args;

-- 2) Table RLS state (public schema)
with expected_tables(table_name) as (
  values
    ('profiles'),
    ('boxes'),
    ('wash_sessions'),
    ('transactions'),
    ('box_reservations'),
    ('loyalty_wallets'),
    ('ops_runtime_state'),
    ('box_cleaning_state'),
    ('box_cleaning_events'),
    ('operator_action_log'),
    ('operator_threshold_settings'),
    ('wash_sessions_legacy_backup'),
    ('sessions_backup')
)
select
  e.table_name,
  c.oid is not null as exists_in_db,
  coalesce(c.relrowsecurity, false) as rls_enabled
from expected_tables e
left join pg_class c
  on c.relnamespace = 'public'::regnamespace
 and c.relname = e.table_name
 and c.relkind = 'r'
order by e.table_name;

-- 3) Internal table privileges should be blocked for anon/authenticated
with internal_tables(table_name) as (
  values
    ('box_reservations'),
    ('loyalty_wallets'),
    ('ops_runtime_state'),
    ('box_cleaning_state'),
    ('box_cleaning_events'),
    ('wash_sessions_legacy_backup'),
    ('sessions_backup'),
    ('operator_action_log'),
    ('operator_threshold_settings')
)
select
  table_name,
  has_table_privilege('anon', format('public.%I', table_name), 'select') as anon_select,
  has_table_privilege('authenticated', format('public.%I', table_name), 'select') as authenticated_select,
  has_table_privilege('anon', format('public.%I', table_name), 'insert') as anon_insert,
  has_table_privilege('authenticated', format('public.%I', table_name), 'insert') as authenticated_insert
from internal_tables
order by table_name;

-- 4) Public app-facing RPC execute grants
with expected_exec(function_signature) as (
  values
    ('public.reserve(integer)'),
    ('public.cancel_reservation(integer)'),
    ('public.activate(integer,integer)'),
    ('public.stop(text)'),
    ('public.status(integer)'),
    ('public.recent_sessions(integer)'),
    ('public.expire_active_sessions()'),
    ('public.top_up(integer)'),
    ('public.loyalty_status()'),
    ('public.record_purchase()'),
    ('public.activate_reward(integer)'),
    ('public.kpi_export(text)'),
    ('public.monitoring_snapshot()')
)
select
  e.function_signature,
  has_function_privilege('authenticated', e.function_signature, 'EXECUTE') as authenticated_execute,
  has_function_privilege('anon', e.function_signature, 'EXECUTE') as anon_execute
from expected_exec e
order by e.function_signature;

-- 5) Trigger checks
select
  n.nspname as schema_name,
  c.relname as table_name,
  t.tgname as trigger_name,
  p.proname as function_name,
  t.tgenabled as enabled_flag
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where not t.tgisinternal
  and (
    (n.nspname = 'public' and c.relname = 'wash_sessions' and t.tgname = 'trg_bump_box_cleaning_counter_on_session')
    or
    (n.nspname = 'auth' and c.relname = 'users' and p.proname = 'handle_new_auth_user_profile')
  )
order by schema_name, table_name, trigger_name;

-- 6) Cron job presence (pg_cron)
select
  jobid,
  jobname,
  schedule,
  command,
  active
from cron.job
where jobname = 'glanzpunkt_expire_active_sessions';
