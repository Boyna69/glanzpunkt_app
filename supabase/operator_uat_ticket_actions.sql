-- Operator UAT ticket actions (status + owner assignment) via append-only action log.
-- Run this in Supabase SQL Editor as project owner.
-- Requires:
--   - public.require_operator_or_owner()
--   - public.log_operator_action(...)
--   - public.operator_action_log

begin;

create or replace function public.set_uat_ticket_status(
  ticket_id bigint,
  uat_status text,
  note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ticket_id bigint := $1;
  v_uat_status text := lower(coalesce(trim($2), ''));
  v_note text := nullif(trim($3), '');
  v_ticket record;
  v_action_status text;
  v_payload jsonb;
  v_result jsonb;
begin
  perform public.require_operator_or_owner();

  if v_ticket_id is null or v_ticket_id <= 0 then
    raise exception 'invalid_ticket_id';
  end if;

  if v_uat_status not in ('open', 'in_progress', 'fixed', 'retest', 'closed') then
    raise exception 'invalid_uat_status';
  end if;

  select l.id, l.box_id, l.action_name, l.details
    into v_ticket
  from public.operator_action_log l
  where l.id = v_ticket_id
  limit 1;

  if not found then
    raise exception 'ticket_not_found';
  end if;

  v_action_status := case
    when v_uat_status in ('closed', 'fixed') then 'success'
    when v_uat_status in ('in_progress', 'retest') then 'partial'
    else 'failed'
  end;

  v_payload := jsonb_build_object(
    'ticket_id', v_ticket_id,
    'summary', coalesce(v_ticket.details->>'summary', v_ticket.action_name),
    'area', coalesce(v_ticket.details->>'area', 'operator_dashboard'),
    'target_build', coalesce(v_ticket.details->>'target_build', 'current'),
    'severity', coalesce(v_ticket.details->>'severity', 'medium'),
    'uat_status', v_uat_status
  );

  if v_note is not null then
    v_payload := v_payload || jsonb_build_object('note', v_note);
  end if;

  v_result := public.log_operator_action(
    'uat_ticket_status_updated',
    v_action_status,
    v_ticket.box_id,
    v_payload,
    'app'
  );

  return v_result || jsonb_build_object(
    'ticket_id', v_ticket_id,
    'uat_status', v_uat_status
  );
end;
$$;

create or replace function public.assign_uat_ticket_owner(
  ticket_id bigint,
  owner_email text default null,
  note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ticket_id bigint := $1;
  v_owner_email_input text := nullif(trim($2), '');
  v_owner_email text;
  v_note text := nullif(trim($3), '');
  v_ticket record;
  v_latest_status text;
  v_action_name text;
  v_payload jsonb;
  v_result jsonb;
begin
  perform public.require_operator_or_owner();

  if v_ticket_id is null or v_ticket_id <= 0 then
    raise exception 'invalid_ticket_id';
  end if;

  select l.id, l.box_id, l.action_name, l.details
    into v_ticket
  from public.operator_action_log l
  where l.id = v_ticket_id
  limit 1;

  if not found then
    raise exception 'ticket_not_found';
  end if;

  if v_owner_email_input is not null then
    select p.email
      into v_owner_email
    from public.profiles p
    where lower(p.email) = lower(v_owner_email_input)
      and p.role in ('operator', 'owner')
    limit 1;

    if v_owner_email is null then
      raise exception 'owner_not_found';
    end if;
  else
    v_owner_email := null;
  end if;

  select coalesce(
    (
      select nullif(l.details->>'uat_status', '')
      from public.operator_action_log l
      where l.action_name = 'uat_ticket_status_updated'
        and (l.details->>'ticket_id') ~ '^[0-9]+$'
        and (l.details->>'ticket_id')::bigint = v_ticket_id
      order by l.created_at desc, l.id desc
      limit 1
    ),
    nullif(v_ticket.details->>'uat_status', ''),
    'open'
  )
  into v_latest_status;

  v_action_name := case
    when v_owner_email is null then 'uat_ticket_owner_cleared'
    else 'uat_ticket_owner_assigned'
  end;

  v_payload := jsonb_build_object(
    'ticket_id', v_ticket_id,
    'summary', coalesce(v_ticket.details->>'summary', v_ticket.action_name),
    'area', coalesce(v_ticket.details->>'area', 'operator_dashboard'),
    'target_build', coalesce(v_ticket.details->>'target_build', 'current'),
    'severity', coalesce(v_ticket.details->>'severity', 'medium'),
    'uat_status', v_latest_status,
    'owner_email', v_owner_email
  );

  if v_note is not null then
    v_payload := v_payload || jsonb_build_object('note', v_note);
  end if;

  v_result := public.log_operator_action(
    v_action_name,
    'success',
    v_ticket.box_id,
    v_payload,
    'app'
  );

  return v_result || jsonb_build_object(
    'ticket_id', v_ticket_id,
    'owner_email', v_owner_email
  );
end;
$$;

revoke all on function public.set_uat_ticket_status(bigint, text, text) from public;
revoke all on function public.assign_uat_ticket_owner(bigint, text, text) from public;

grant execute on function public.set_uat_ticket_status(bigint, text, text) to authenticated;
grant execute on function public.assign_uat_ticket_owner(bigint, text, text) to authenticated;

commit;

notify pgrst, 'reload schema';
