-- Harden legacy backup table exposed in public schema.
-- Run in Supabase SQL Editor as project owner.

begin;

do $$
begin
  if to_regclass('public.wash_sessions_legacy_backup') is not null then
    execute 'alter table public.wash_sessions_legacy_backup enable row level security';
    execute 'revoke all on table public.wash_sessions_legacy_backup from public';
    execute 'revoke all on table public.wash_sessions_legacy_backup from anon, authenticated';
  end if;
end
$$;

commit;
