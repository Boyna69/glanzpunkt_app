-- Background scheduler for box/session reconciliation.
-- Run in Supabase SQL Editor as project owner.
--
-- Goal:
-- - execute reconciliation every minute
-- - avoid stale reserved/active states without manual quick-fix

begin;

create extension if not exists pg_cron with schema extensions;

do $$
declare
  v_job_id bigint;
begin
  select j.jobid
    into v_job_id
  from cron.job j
  where j.jobname = 'glanzpunkt_expire_active_sessions'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'glanzpunkt_expire_active_sessions',
    '* * * * *',
    $job$select public.expire_active_sessions_internal();$job$
  );
end $$;

commit;

-- ---------------------------------------------------------------------------
-- Optional verification queries
-- ---------------------------------------------------------------------------
-- select jobid, jobname, schedule, command, active
-- from cron.job
-- where jobname = 'glanzpunkt_expire_active_sessions';
--
-- select public.expire_active_sessions_internal();
