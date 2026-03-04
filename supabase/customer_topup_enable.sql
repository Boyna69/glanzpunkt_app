-- Enable customer top-up for testing (authenticated users).
-- Run in Supabase SQL Editor, then reload PostgREST schema cache.

begin;

create or replace function public.top_up(amount integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount integer := $1;
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_balance numeric;
  v_has_kind boolean;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  update public.profiles p
    set balance = coalesce(p.balance, 0) + v_amount
  where p.id = v_user_id
  returning coalesce(p.balance, 0) into v_balance;

  if not found then
    raise exception 'profile_not_found';
  end if;

  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'transactions'
      and c.column_name = 'kind'
  ) into v_has_kind;

  if v_has_kind then
    insert into public.transactions (user_id, amount, kind, created_at)
    values (v_user_id, v_amount, 'top_up', v_now);
  else
    insert into public.transactions (user_id, amount, created_at)
    values (v_user_id, v_amount, v_now);
  end if;

  return jsonb_build_object(
    'amount', v_amount,
    'balance', coalesce(v_balance, 0)
  );
end;
$$;

revoke all on function public.top_up(integer) from public;
grant execute on function public.top_up(integer) to authenticated;

commit;

notify pgrst, 'reload schema';
