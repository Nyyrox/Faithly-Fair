-- Faithly Fair: repair eSewa payment-proof storage setup.
-- Safe to run after the earlier eSewa migrations.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'payment-proofs',
  'payment-proofs',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Rebuild the guest upload policy so the current eSewa token function
-- is definitely the policy actually used by Storage.
drop policy if exists "guest upload proof with valid token" on storage.objects;

create policy "guest upload proof with valid token"
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'payment-proofs'
  and public.can_upload_proof_path(name)
);

-- Admins need to be able to view submitted screenshots.
drop policy if exists "admin read proof files" on storage.objects;

create policy "admin read proof files"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'payment-proofs'
  and public.is_admin()
);

-- Admins can remove an invalid/old proof.
drop policy if exists "admin delete proof files" on storage.objects;

create policy "admin delete proof files"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'payment-proofs'
  and public.is_admin()
);
