-- Allow eSewa payment screenshots to be uploaded before an order exists.
-- The client uploads to pending/<temporary-id>/..., then creates the order,
-- moves the object into <upload_token>/..., and submits the proof.

create or replace function public.can_upload_proof_path(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (
      object_name ~ '^pending/[A-Za-z0-9_-]{8,}/[^/]+\\.(jpg|jpeg|png|webp)$'
    )
    or exists (
      select 1
      from public.orders o
      where o.upload_token::text = (storage.foldername(object_name))[1]
        and o.payment_method = 'esewa'
        and o.payment_status in ('payment_pending','rejected')
        and o.proof_upload_expires_at > now()
    );
$$;

revoke all on function public.can_upload_proof_path(text) from public;
grant execute on function public.can_upload_proof_path(text) to anon, authenticated;

-- Storage MOVE is performed by the client after the order exists.
-- Permit moving an eSewa pending proof into that order's token folder.
drop policy if exists "guest move proof after order" on storage.objects;

create policy "guest move proof after order"
on storage.objects
for update
to anon, authenticated
using (
  bucket_id = 'payment-proofs'
  and name ~ '^pending/[A-Za-z0-9_-]{8,}/[^/]+\\.(jpg|jpeg|png|webp)$'
)
with check (
  bucket_id = 'payment-proofs'
  and exists (
    select 1
    from public.orders o
    where o.upload_token::text = (storage.foldername(name))[1]
      and o.payment_method = 'esewa'
      and o.payment_status in ('payment_pending','rejected')
      and o.proof_upload_expires_at > now()
  )
);
