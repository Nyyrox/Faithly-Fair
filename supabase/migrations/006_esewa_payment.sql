-- 🇳🇵 Faithly Fair: replace UPI/manual proof with eSewa ePay

alter table public.orders drop constraint if exists orders_pincode_check;
alter table public.orders add constraint orders_pincode_check
  check (pincode ~ '^[0-9]{5}$');

alter type public.payment_method rename value 'upi' to 'esewa';

alter type public.payment_state rename value 'awaiting_proof' to 'payment_pending';

-- eSewa transaction state lives on the order so it can be verified server-side.
alter table public.orders
  add column if not exists payment_transaction_uuid text unique,
  add column if not exists payment_reference text;

create index if not exists orders_payment_transaction_idx
  on public.orders(payment_transaction_uuid);

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

  mobile_clean := regexp_replace(
    coalesce(c->>'mobile',''),
    '[^0-9+]',
    '',
    'g'
  );

  if mobile_clean ~ '^\+9779[78][0-9]{8}$' then
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
    select * into p
    from public.products
    where id = (item->>'product_id')::uuid
      and active
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

  ono :=
    'FF-' ||
    to_char(current_date,'YYMMDD') ||
    '-' ||
    lpad(nextval('public.order_number_seq')::text,5,'0');

  insert into public.orders (
    customer_id,
    order_number,
    customer_name,
    mobile,
    alternate_mobile,
    email,
    address_line1,
    address_line2,
    landmark,
    city,
    state,
    pincode,
    payment_method,
    payment_status,
    subtotal,
    total,
    upload_token,
    payment_transaction_uuid
  )
  values (
    auth.uid(),
    ono,
    trim(c->>'name'),
    mobile_clean,
    nullif(c->>'alternate_mobile',''),
    c->>'email',
    c->>'address_line1',
    nullif(c->>'address_line2',''),
    nullif(c->>'landmark',''),
    c->>'city',
    c->>'state',
    c->>'pincode',
    method,
    case
      when method = 'cod' then 'cod_due'::public.payment_state
      else 'payment_pending'::public.payment_state
    end,
    sum_total,
    sum_total,
    token,
    case when method = 'esewa' then ono else null end
  )
  returning id into oid;

  for item in select * from jsonb_array_elements(order_payload->'items') loop
    select * into p
    from public.products
    where id = (item->>'product_id')::uuid
    for update;

    insert into public.order_items (
      order_id, product_id, product_name,
      unit_price, quantity, line_total
    )
    values (
      oid, p.id, p.name, p.price,
      (item->>'quantity')::int,
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
      case
        when method = 'cod' then 'cod_due'
        else 'payment_pending'
      end,
    'upload_token', token
  );
end;
$$;

revoke all on function public.create_guest_order(jsonb) from public;
grant execute on function public.create_guest_order(jsonb) to anon, authenticated;

-- The old screenshot-proof flow is no longer used by eSewa.
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
begin
  raise exception 'Manual payment proof is disabled. Complete payment through eSewa.';
end;
$$;

revoke all on function public.submit_payment_proof(uuid,text,text,integer) from public;
grant execute on function public.submit_payment_proof(uuid,text,text,integer) to anon,authenticated;


-- Disable the legacy screenshot-proof upload path now that eSewa is verified server-side.
create or replace function public.can_upload_proof_path(object_name text)
returns boolean
language sql stable security definer set search_path = public as $$
  select false;
$$;

revoke all on function public.can_upload_proof_path(text) from public;
grant execute on function public.can_upload_proof_path(text) to anon, authenticated;

-- Remove legacy India/UPI public settings if they exist.
delete from public.site_settings
where key in ('upi_id','upi_payee_name','whatsapp')
  and value is not null;
