-- Simple eSewa QR + screenshot flow.
-- Uses the user's existing eSewa receive QR identity and keeps manual verification.
-- The amount is generated from the order total and displayed beside the QR.
-- A static personal eSewa QR cannot encode a dynamic amount without eSewa/Fonepay
-- merchant dynamic-QR infrastructure.

create or replace function public.submit_payment_proof(
  proof_token uuid,
  storage_path text,
  file_type text,
  file_size integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  oid uuid;
begin
  select id into oid
  from public.orders
  where upload_token = proof_token
    and payment_method = 'esewa'
    and payment_status in ('payment_pending','rejected')
    and proof_upload_expires_at > now()
  for update;

  if not found then
    raise exception 'This secure upload link is invalid or expired';
  end if;

  if storage_path not like proof_token::text || '/%' then
    raise exception 'Invalid storage path';
  end if;

  insert into public.payment_proofs(order_id,storage_path,file_type,file_size)
  values(oid,storage_path,file_type,file_size);

  update public.orders
  set payment_status = 'proof_submitted'
  where id = oid;
end;
$$;

revoke all on function public.submit_payment_proof(uuid,text,text,integer) from public;
grant execute on function public.submit_payment_proof(uuid,text,text,integer) to anon,authenticated;

create or replace function public.can_upload_proof_path(object_name text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists(
    select 1
    from public.orders o
    where o.upload_token::text = (storage.foldername(object_name))[1]
      and o.payment_method = 'esewa'
      and o.payment_status in ('payment_pending','rejected')
      and o.proof_upload_expires_at > now()
  );
$$;

revoke all on function public.can_upload_proof_path(text) from public;
grant execute on function public.can_upload_proof_path(text) to anon,authenticated;
