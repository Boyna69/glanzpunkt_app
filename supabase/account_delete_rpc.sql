-- Deprecated.
-- Account deletion now runs via Edge Function:
--   /functions/v1/delete-account
-- This SQL cleanup removes an older RPC variant if present.

begin;

drop function if exists public.delete_my_account();
notify pgrst, 'reload schema';

commit;
