-- Harden RPC execute grants:
-- - remove public/anon execution
-- - keep authenticated execution for app-facing RPCs
-- Run in Supabase SQL Editor as project owner.

begin;

do $$
declare
  fn text;
  revoke_public_anon text[] := array[
    'public.require_operator_or_owner()',
    'public.reserve(integer)',
    'public.cancel_reservation(integer)',
    'public.activate(integer,integer)',
    'public.activate_reward(integer)',
    'public.stop(text)',
    'public.status(integer)',
    'public.recent_sessions(integer)',
    'public.expire_active_sessions()',
    'public.expire_active_sessions_internal()',
    'public.top_up(integer)',
    'public.loyalty_status()',
    'public.record_purchase()',
    'public.monitoring_snapshot()',
    'public.kpi_export(text)',
    'public.get_box_cleaning_plan(integer)',
    'public.get_box_cleaning_history(integer,integer)',
    'public.mark_box_cleaned(integer,text)',
    'public.log_operator_action(text,text,integer,jsonb,text)',
    'public.list_operator_actions(integer)',
    'public.list_operator_actions_filtered(integer,integer,text,integer,text,timestamptz,timestamptz)',
    'public.set_uat_ticket_status(bigint,text,text)',
    'public.assign_uat_ticket_owner(bigint,text,text)',
    'public.get_operator_threshold_settings()',
    'public.set_operator_threshold_settings(integer,integer)',
    'public.handle_new_auth_user_profile()',
    'public.bump_box_cleaning_counter_on_session()'
  ];
  grant_authenticated text[] := array[
    'public.require_operator_or_owner()',
    'public.reserve(integer)',
    'public.cancel_reservation(integer)',
    'public.activate(integer,integer)',
    'public.activate_reward(integer)',
    'public.stop(text)',
    'public.status(integer)',
    'public.recent_sessions(integer)',
    'public.expire_active_sessions()',
    'public.top_up(integer)',
    'public.loyalty_status()',
    'public.record_purchase()',
    'public.monitoring_snapshot()',
    'public.kpi_export(text)',
    'public.get_box_cleaning_plan(integer)',
    'public.get_box_cleaning_history(integer,integer)',
    'public.mark_box_cleaned(integer,text)',
    'public.log_operator_action(text,text,integer,jsonb,text)',
    'public.list_operator_actions(integer)',
    'public.list_operator_actions_filtered(integer,integer,text,integer,text,timestamptz,timestamptz)',
    'public.set_uat_ticket_status(bigint,text,text)',
    'public.assign_uat_ticket_owner(bigint,text,text)',
    'public.get_operator_threshold_settings()',
    'public.set_operator_threshold_settings(integer,integer)'
  ];
begin
  foreach fn in array revoke_public_anon loop
    if to_regprocedure(fn) is not null then
      execute format('revoke all on function %s from public, anon', fn);
    end if;
  end loop;

  -- Optional legacy function: only revoke when present.
  if to_regprocedure('public.loyalty_derived_state(uuid)') is not null then
    execute 'revoke all on function public.loyalty_derived_state(uuid) from public, anon, authenticated';
  end if;

  foreach fn in array grant_authenticated loop
    if to_regprocedure(fn) is not null then
      execute format('grant execute on function %s to authenticated', fn);
    end if;
  end loop;
end
$$;

commit;

notify pgrst, 'reload schema';
