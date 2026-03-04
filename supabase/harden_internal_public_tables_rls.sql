-- Hardening for internal/legacy tables in public schema.
-- Run in Supabase SQL Editor as project owner.

begin;

do $$
declare
  v_table text;
  v_tables text[] := array[
    'box_reservations',
    'loyalty_wallets',
    'ops_runtime_state',
    'box_cleaning_state',
    'box_cleaning_events',
    'wash_sessions_legacy_backup',
    'sessions_backup'
  ];
begin
  foreach v_table in array v_tables loop
    if to_regclass(format('public.%I', v_table)) is not null then
      execute format('alter table public.%I enable row level security', v_table);
      execute format('revoke all on table public.%I from public', v_table);
      execute format('revoke all on table public.%I from anon, authenticated', v_table);
    end if;
  end loop;
end
$$;

commit;

notify pgrst, 'reload schema';
