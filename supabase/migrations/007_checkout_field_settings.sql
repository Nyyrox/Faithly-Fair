-- Add admin-controlled checkout field visibility.
insert into public.site_settings(key,value,is_public)
values
  ('show_state','false',true),
  ('show_pincode','false',true)
on conflict (key)
do update set value=excluded.value, is_public=excluded.is_public;
