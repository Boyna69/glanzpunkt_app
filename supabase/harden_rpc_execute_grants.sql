-- Harden RPC execute grants:
-- - remove public/anon execution
-- - keep authenticated execution for app-facing RPCs
-- Run in Supabase SQL Editor as project owner.

begin;

-- Ensure no broad execution rights remain.
revoke all on function public.require_operator_or_owner() from public, anon;
revoke all on function public.reserve(integer) from public, anon;
revoke all on function public.cancel_reservation(integer) from public, anon;
revoke all on function public.activate(integer, integer) from public, anon;
revoke all on function public.activate_reward(integer) from public, anon;
revoke all on function public.stop(text) from public, anon;
revoke all on function public.status(integer) from public, anon;
revoke all on function public.recent_sessions(integer) from public, anon;
revoke all on function public.expire_active_sessions() from public, anon;
revoke all on function public.expire_active_sessions_internal() from public, anon;
revoke all on function public.top_up(integer) from public, anon;
revoke all on function public.loyalty_status() from public, anon;
revoke all on function public.record_purchase() from public, anon;
revoke all on function public.monitoring_snapshot() from public, anon;
revoke all on function public.kpi_export(text) from public, anon;
revoke all on function public.get_box_cleaning_plan(integer) from public, anon;
revoke all on function public.get_box_cleaning_history(integer, integer) from public, anon;
revoke all on function public.mark_box_cleaned(integer, text) from public, anon;
revoke all on function public.log_operator_action(text, text, integer, jsonb, text) from public, anon;
revoke all on function public.list_operator_actions(integer) from public, anon;
revoke all on function public.list_operator_actions_filtered(integer, integer, text, integer, text, timestamptz, timestamptz) from public, anon;
revoke all on function public.get_operator_threshold_settings() from public, anon;
revoke all on function public.set_operator_threshold_settings(integer, integer) from public, anon;
revoke all on function public.handle_new_auth_user_profile() from public, anon;
revoke all on function public.bump_box_cleaning_counter_on_session() from public, anon;
revoke all on function public.loyalty_derived_state(uuid) from public, anon, authenticated;

-- App-facing RPCs: authenticated only.
grant execute on function public.require_operator_or_owner() to authenticated;
grant execute on function public.reserve(integer) to authenticated;
grant execute on function public.cancel_reservation(integer) to authenticated;
grant execute on function public.activate(integer, integer) to authenticated;
grant execute on function public.activate_reward(integer) to authenticated;
grant execute on function public.stop(text) to authenticated;
grant execute on function public.status(integer) to authenticated;
grant execute on function public.recent_sessions(integer) to authenticated;
grant execute on function public.expire_active_sessions() to authenticated;
grant execute on function public.top_up(integer) to authenticated;
grant execute on function public.loyalty_status() to authenticated;
grant execute on function public.record_purchase() to authenticated;
grant execute on function public.monitoring_snapshot() to authenticated;
grant execute on function public.kpi_export(text) to authenticated;
grant execute on function public.get_box_cleaning_plan(integer) to authenticated;
grant execute on function public.get_box_cleaning_history(integer, integer) to authenticated;
grant execute on function public.mark_box_cleaned(integer, text) to authenticated;
grant execute on function public.log_operator_action(text, text, integer, jsonb, text) to authenticated;
grant execute on function public.list_operator_actions(integer) to authenticated;
grant execute on function public.list_operator_actions_filtered(integer, integer, text, integer, text, timestamptz, timestamptz) to authenticated;
grant execute on function public.get_operator_threshold_settings() to authenticated;
grant execute on function public.set_operator_threshold_settings(integer, integer) to authenticated;

commit;

notify pgrst, 'reload schema';
