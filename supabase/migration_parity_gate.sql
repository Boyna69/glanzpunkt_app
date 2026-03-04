-- Migration parity gate (hard fail on mismatch).
-- Run with database owner/service role connection.
-- Example:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migration_parity_gate.sql

do $$
declare
  v_exists boolean;
  v_secdef boolean;
  v_rls boolean;
  rec record;
begin
  -- 1) Required core functions and SECURITY DEFINER state.
  for rec in
    select *
    from (
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
    ) as t(function_name, identity_args, expect_security_definer)
  loop
    select
      p.oid is not null,
      coalesce(p.prosecdef, false)
    into
      v_exists,
      v_secdef
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = rec.function_name
      and pg_get_function_identity_arguments(p.oid) = rec.identity_args;

    if not coalesce(v_exists, false) then
      raise exception 'parity_fail: missing function %.%(%)',
        'public', rec.function_name, rec.identity_args;
    end if;

    if v_secdef is distinct from rec.expect_security_definer then
      raise exception 'parity_fail: SECURITY DEFINER mismatch for public.%(%) expected=% actual=%',
        rec.function_name, rec.identity_args, rec.expect_security_definer, v_secdef;
    end if;
  end loop;

  -- 2) Expected tables must exist with RLS enabled.
  for rec in
    select *
    from (
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
    ) as t(table_name)
  loop
    select
      c.oid is not null,
      coalesce(c.relrowsecurity, false)
    into
      v_exists,
      v_rls
    from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relname = rec.table_name
      and c.relkind = 'r';

    if not coalesce(v_exists, false) then
      raise exception 'parity_fail: missing table public.%', rec.table_name;
    end if;

    if not coalesce(v_rls, false) then
      raise exception 'parity_fail: RLS disabled on public.%', rec.table_name;
    end if;
  end loop;

  -- 3) Internal tables must not be directly exposed to anon/authenticated.
  for rec in
    select *
    from (
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
    ) as t(table_name)
  loop
    if has_table_privilege('anon', format('public.%I', rec.table_name), 'select')
       or has_table_privilege('authenticated', format('public.%I', rec.table_name), 'select')
       or has_table_privilege('anon', format('public.%I', rec.table_name), 'insert')
       or has_table_privilege('authenticated', format('public.%I', rec.table_name), 'insert') then
      raise exception 'parity_fail: unexpected table grant on public.% for anon/authenticated', rec.table_name;
    end if;
  end loop;

  -- 4) App-facing RPCs: authenticated execute must exist, anon execute must not.
  for rec in
    select *
    from (
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
    ) as t(function_signature)
  loop
    if not has_function_privilege('authenticated', rec.function_signature, 'EXECUTE') then
      raise exception 'parity_fail: missing authenticated EXECUTE on %', rec.function_signature;
    end if;

    if has_function_privilege('anon', rec.function_signature, 'EXECUTE') then
      raise exception 'parity_fail: anon EXECUTE unexpectedly granted on %', rec.function_signature;
    end if;
  end loop;

  -- 5) Required triggers.
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal
      and n.nspname = 'public'
      and c.relname = 'wash_sessions'
      and t.tgname = 'trg_bump_box_cleaning_counter_on_session'
      and t.tgenabled <> 'D'
  ) then
    raise exception 'parity_fail: missing/disabled trigger public.wash_sessions.trg_bump_box_cleaning_counter_on_session';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    where not t.tgisinternal
      and n.nspname = 'auth'
      and c.relname = 'users'
      and p.proname = 'handle_new_auth_user_profile'
      and t.tgenabled <> 'D'
  ) then
    raise exception 'parity_fail: missing/disabled trigger on auth.users for handle_new_auth_user_profile';
  end if;

  -- 6) Cron job check.
  if to_regclass('cron.job') is null then
    raise exception 'parity_fail: cron.job not found';
  end if;

  if not exists (
    select 1
    from cron.job
    where jobname = 'glanzpunkt_expire_active_sessions'
      and active
      and schedule = '* * * * *'
      and position('expire_active_sessions_internal' in command) > 0
  ) then
    raise exception 'parity_fail: cron job glanzpunkt_expire_active_sessions missing/inactive/mismatch';
  end if;

  raise notice 'MIGRATION_PARITY_GATE_OK';
end
$$;
