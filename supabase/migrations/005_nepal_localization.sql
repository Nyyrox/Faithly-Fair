-- Nepal localization for the existing Faithly Fair database.
-- Run this after the fresh database setup.

-- Nepal mobile numbers: 10 digits beginning with 97 or 98.
-- Accept either local form (98XXXXXXXX) or +977 form.
create or replace function public.create_guest_order(order_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c jsonb := order_payload->'customer';
  item jsonb;
  p public.products%rowtype;
  oid uuid;
  ono text;
  token uuid := gen_random_uuid();
  sum_total numeric := 0;
  method public.payment_method;
  mobile_clean text;
begin
  if jsonb_typeof(order_payload->'items') <> 'array'
     or jsonb_array_length(order_payload->'items') = 0 then
    raise exception 'Your gift bag is empty';
  end if;

  mobile_clean := regexp_replace(coalesce(c->>'mobile',''), '[^0-9+]', '', 'g');

  if mobile_clean ~ '^\\+9779[78][0-9]{8}$' then
    mobile_clean := substring(mobile_clean from 5);
  end if;

  if coalesce(c->>'name','') = ''
     or mobile_clean !~ '^9[78][0-9]{8}$'
     or coalesce(c->>'email','') = ''
     or position('@' in c->>'email') = 0
     or coalesce(c->>'address_line1','') = ''
     or coalesce(c->>'city','') = ''
     or coalesce(c->>'state','') = ''
     or (c->>'pincode') !~ '^[0-9]{5}$' then
    raise exception 'Please check the required Nepal delivery details';
  end if;

  method := (order_payload->>'payment_method')::public.payment_method;

  for item in select * from jsonb_array_elements(order_payload->'items') loop
    select * into p from public.products
    where id = (item->>'product_id')::uuid and active
    for update;

    if not found then
      raise exception 'A product is no longer available';
    end if;

    if (item->>'quantity')::int < 1
       or p.stock_quantity < (item->>'quantity')::int then
      raise exception 'Not enough stock for %', p.name;
    end if;

    sum_total := sum_total + p.price * (item->>'quantity')::int;
  end loop;

  ono := 'FF-' || to_char(current_date,'YYMMDD') || '-' ||
         lpad(nextval('public.order_number_seq')::text,5,'0');

  insert into public.orders (
    customer_id, order_number, customer_name, mobile, alternate_mobile,
    email, address_line1, address_line2, landmark, city, state, pincode,
    payment_method, payment_status, subtotal, total, upload_token
  )
  values (
    auth.uid(), ono, trim(c->>'name'), mobile_clean,
    nullif(c->>'alternate_mobile',''), c->>'email',
    c->>'address_line1', nullif(c->>'address_line2',''),
    nullif(c->>'landmark',''), c->>'city', c->>'state', c->>'pincode',
    method,
    case when method='cod'
      then 'cod_due'::public.payment_state
      else 'awaiting_proof'::public.payment_state end,
    sum_total, sum_total, token
  )
  returning id into oid;

  for item in select * from jsonb_array_elements(order_payload->'items') loop
    select * into p from public.products
    where id = (item->>'product_id')::uuid
    for update;

    insert into public.order_items (
      order_id, product_id, product_name, unit_price, quantity, line_total
    )
    values (
      oid, p.id, p.name, p.price, (item->>'quantity')::int,
      p.price * (item->>'quantity')::int
    );

    update public.products
    set stock_quantity = stock_quantity - (item->>'quantity')::int
    where id = p.id;
  end loop;

  return jsonb_build_object(
    'id', oid,
    'order_number', ono,
    'total', sum_total,
    'payment_method', method,
    'payment_status',
      case when method='cod' then 'cod_due' else 'awaiting_proof' end,
    'upload_token', token
  );
end;
$$;

revoke all on function public.create_guest_order(jsonb) from public;
grant execute on function public.create_guest_order(jsonb) to anon, authenticated;
