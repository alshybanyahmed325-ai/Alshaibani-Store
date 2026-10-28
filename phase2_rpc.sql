-- Phase 2: authenticated, role-checked, atomic RPCs.
-- Run after schema.sql in a dedicated NEW Supabase project.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

-- A project owner must assign the first owner role manually in SQL editor.
-- Example (replace UUID with the verified auth.users.id):
-- insert into public.app_profiles(user_id,display_name,role)
-- values ('USER-UUID','Owner','owner')
-- on conflict(user_id) do update set role='owner';

create or replace function private.current_can_write()
returns boolean
language sql stable security definer
set search_path = ''
as $$
 select exists (
   select 1 from public.app_profiles p
   where p.user_id = auth.uid()
     and p.role in ('owner','admin','accountant','operator')
 )
$$;
revoke all on function private.current_can_write() from public, anon;
grant execute on function private.current_can_write() to authenticated;

-- Keep product changes idempotent and reject stale versions rather than silently overwriting.
create or replace function public.sync_product_mutation(
 p_client_mutation_id uuid,
 p_device_id text,
 p_entity_id uuid,
 p_operation text,
 p_base_version integer,
 p_payload jsonb
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_existing public.products%rowtype;
  v_result public.products%rowtype;
  v_seen public.sync_operations%rowtype;
  v_next_version integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select role into v_role from public.app_profiles where user_id=v_user;
  if v_role is null or v_role not in ('owner','admin','accountant','operator') then
    raise exception 'INSUFFICIENT_ROLE';
  end if;
  if p_client_mutation_id is null or p_entity_id is null then raise exception 'MUTATION_ID_REQUIRED'; end if;
  if p_operation not in ('insert','upsert','delete') then raise exception 'INVALID_OPERATION'; end if;
  if p_payload->>'id' is distinct from p_entity_id::text then raise exception 'ENTITY_ID_MISMATCH'; end if;

  select * into v_seen from public.sync_operations where client_mutation_id=p_client_mutation_id;
  if found then
    if v_seen.status='applied' then
      select * into v_result from public.products where id=p_entity_id;
      return jsonb_build_object('status','already_applied','product',to_jsonb(v_result));
    end if;
    if v_seen.status='conflict' then
      select * into v_existing from public.products where id=p_entity_id;
      return jsonb_build_object('status','conflict','server_product',case when v_existing.id is null then null else to_jsonb(v_existing) end);
    end if;
  else
    insert into public.sync_operations(client_mutation_id,device_id,entity,entity_id,operation,payload,base_version,status,user_id)
    values(p_client_mutation_id,coalesce(nullif(p_device_id,''),'unknown'),'products',p_entity_id,p_operation,coalesce(p_payload,'{}'::jsonb),greatest(coalesce(p_base_version,0),0),'received',v_user);
  end if;

  select * into v_existing from public.products where id=p_entity_id for update;
  if p_operation='insert' and v_existing.id is not null then
    update public.sync_operations set status='conflict',server_version=v_existing.version,
      conflict_detail=jsonb_build_object('reason','id_exists','server',to_jsonb(v_existing)),processed_at=now()
      where client_mutation_id=p_client_mutation_id;
    return jsonb_build_object('status','conflict','reason','id_exists','server_product',to_jsonb(v_existing));
  end if;
  if p_operation in ('upsert','delete') then
    if v_existing.id is null then
      update public.sync_operations set status='conflict',conflict_detail=jsonb_build_object('reason','server_record_missing'),processed_at=now()
       where client_mutation_id=p_client_mutation_id;
      return jsonb_build_object('status','conflict','reason','server_record_missing');
    end if;
    if v_existing.version <> coalesce(p_base_version,0) then
      update public.sync_operations set status='conflict',server_version=v_existing.version,
        conflict_detail=jsonb_build_object('reason','stale_version','server',to_jsonb(v_existing),'local',p_payload),processed_at=now()
       where client_mutation_id=p_client_mutation_id;
      return jsonb_build_object('status','conflict','reason','stale_version','server_product',to_jsonb(v_existing),'local_product',p_payload);
    end if;
  end if;

  if p_operation='delete' then
    update public.products set deleted_at=coalesce(nullif(p_payload->>'deleted_at','')::timestamptz,now()),
      updated_at=now(),updated_by=v_user,version=version+1
      where id=p_entity_id returning * into v_result;
  elsif p_operation='insert' then
    insert into public.products(id,sku,name,category,base_unit_id,quantity,purchase_price,sale_price,currency,minimum_stock,notes,version,device_id,created_by,updated_by,created_at,updated_at)
    values(p_entity_id,nullif(p_payload->>'sku',''),coalesce(nullif(p_payload->>'name',''),'صنف جديد'),
      nullif(p_payload->>'category',''),null,
      greatest(coalesce(nullif(p_payload->>'quantity','')::numeric,0),0),
      greatest(coalesce(nullif(p_payload->>'purchase_price','')::numeric,0),0),
      greatest(coalesce(nullif(p_payload->>'sale_price','')::numeric,0),0),
      coalesce(nullif(p_payload->>'currency',''),'YER'),
      greatest(coalesce(nullif(p_payload->>'minimum_stock','')::numeric,0),0),
      nullif(p_payload->>'notes',''),1,nullif(p_device_id,''),v_user,v_user,now(),now())
    returning * into v_result;
  else
    update public.products set
      sku=nullif(p_payload->>'sku',''),name=coalesce(nullif(p_payload->>'name',''),name),
      category=nullif(p_payload->>'category',''),
      quantity=greatest(coalesce(nullif(p_payload->>'quantity','')::numeric,0),0),
      purchase_price=greatest(coalesce(nullif(p_payload->>'purchase_price','')::numeric,0),0),
      sale_price=greatest(coalesce(nullif(p_payload->>'sale_price','')::numeric,0),0),
      currency=coalesce(nullif(p_payload->>'currency',''),'YER'),
      minimum_stock=greatest(coalesce(nullif(p_payload->>'minimum_stock','')::numeric,0),0),
      notes=nullif(p_payload->>'notes',''),deleted_at=null,updated_at=now(),updated_by=v_user,device_id=nullif(p_device_id,''),version=version+1
      where id=p_entity_id returning * into v_result;
  end if;
  update public.sync_operations set status='applied',server_version=v_result.version,processed_at=now()
   where client_mutation_id=p_client_mutation_id;
  insert into public.audit_log(table_name,record_id,action,new_data,changed_by)
   values('products',p_entity_id,p_operation,to_jsonb(v_result),v_user);
  return jsonb_build_object('status','applied','product',to_jsonb(v_result));
exception when unique_violation then
  raise exception 'DUPLICATE_SKU_OR_MUTATION';
end $$;
revoke all on function public.sync_product_mutation(uuid,text,uuid,text,integer,jsonb) from public, anon;
grant execute on function public.sync_product_mutation(uuid,text,uuid,text,integer,jsonb) to authenticated;

-- Atomic sale posting: creates invoice + lines + stock movements + optional receipt in one transaction.
create or replace function public.post_sale_invoice(
 p_customer_id uuid,
 p_currency text,
 p_exchange_rate numeric,
 p_discount numeric,
 p_lines jsonb,
 p_paid numeric default 0,
 p_account_id uuid default null,
 p_notes text default null
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_role text; v_invoice public.sales_invoices%rowtype;
 v_line jsonb; v_product public.products%rowtype; v_qty numeric; v_price numeric; v_disc numeric;
 v_subtotal numeric:=0; v_total numeric:=0; v_line_total numeric; v_count int:=0;
begin
 select role into v_role from public.app_profiles where user_id=v_user;
 if v_user is null or v_role not in ('owner','admin','accountant','operator') then raise exception 'AUTH_REQUIRED_OR_ROLE'; end if;
 if p_currency not in ('YER','SAR','USD') or coalesce(p_exchange_rate,0)<=0 then raise exception 'INVALID_CURRENCY_OR_RATE'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'LINES_REQUIRED'; end if;
 if coalesce(p_paid,0)<0 or coalesce(p_discount,0)<0 then raise exception 'INVALID_AMOUNT'; end if;
 insert into public.sales_invoices(customer_id,status,currency,exchange_rate,discount,paid,notes,created_by)
 values(p_customer_id,'draft',p_currency,p_exchange_rate,coalesce(p_discount,0),coalesce(p_paid,0),p_notes,v_user)
 returning * into v_invoice;
 for v_line in select value from jsonb_array_elements(p_lines) loop
   v_count:=v_count+1;
   select * into v_product from public.products where id=(v_line->>'product_id')::uuid and deleted_at is null for update;
   if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
   v_qty:=coalesce(nullif(v_line->>'base_quantity','')::numeric,nullif(v_line->>'quantity','')::numeric);
   v_price:=coalesce(nullif(v_line->>'unit_price','')::numeric,0);
   v_disc:=coalesce(nullif(v_line->>'discount','')::numeric,0);
   if v_qty<=0 or v_price<0 or v_disc<0 then raise exception 'INVALID_LINE'; end if;
   if v_product.quantity<v_qty then raise exception 'INSUFFICIENT_STOCK: %',v_product.name; end if;
   v_line_total:=v_qty*v_price-v_disc;
   if v_line_total<0 then raise exception 'LINE_DISCOUNT_TOO_LARGE'; end if;
   v_subtotal:=v_subtotal+(v_qty*v_price);
   v_total:=v_total+v_line_total;
   insert into public.sales_invoice_lines(invoice_id,product_id,unit_name,quantity,unit_price,discount,line_total,base_quantity)
   values(v_invoice.id,v_product.id,coalesce(v_line->>'unit_name','unit'),coalesce(nullif(v_line->>'quantity','')::numeric,v_qty),v_price,v_disc,v_line_total,v_qty);
   update public.products set quantity=quantity-v_qty,version=version+1,updated_at=now(),updated_by=v_user where id=v_product.id;
   insert into public.stock_movements(product_id,movement_type,quantity_delta,reference_table,reference_id,created_by)
   values(v_product.id,'sale',-v_qty,'sales_invoices',v_invoice.id,v_user);
 end loop;
 v_total:=v_total-coalesce(p_discount,0);
 if v_total<0 then raise exception 'INVOICE_DISCOUNT_TOO_LARGE'; end if;
 if coalesce(p_paid,0)>v_total then raise exception 'PAID_EXCEEDS_TOTAL'; end if;
 update public.sales_invoices set status='posted',subtotal=v_subtotal,total=v_total,posted_at=now() where id=v_invoice.id returning * into v_invoice;
 if coalesce(p_paid,0)>0 then
   if p_account_id is null then raise exception 'ACCOUNT_REQUIRED_FOR_PAYMENT'; end if;
   if not exists(select 1 from public.financial_accounts a where a.id=p_account_id and a.currency=p_currency and a.active) then raise exception 'INVALID_FINANCIAL_ACCOUNT'; end if;
   insert into public.money_movements(direction,party_type,party_id,account_id,amount,currency,exchange_rate,reference_table,reference_id,client_mutation_id,created_by)
   values('receipt','customer',p_customer_id,p_account_id,p_paid,p_currency,p_exchange_rate,'sales_invoices',v_invoice.id,gen_random_uuid(),v_user);
 end if;
 insert into public.audit_log(table_name,record_id,action,new_data,changed_by)
 values('sales_invoices',v_invoice.id,'posted',to_jsonb(v_invoice),v_user);
 return jsonb_build_object('status','posted','invoice',to_jsonb(v_invoice));
end $$;
revoke all on function public.post_sale_invoice(uuid,text,numeric,numeric,jsonb,numeric,uuid,text) from public,anon;
grant execute on function public.post_sale_invoice(uuid,text,numeric,numeric,jsonb,numeric,uuid,text) to authenticated;

-- Atomic purchase posting: adds stock and records purchase invoice.
create or replace function public.post_purchase_invoice(
 p_supplier_id uuid,p_currency text,p_exchange_rate numeric,p_discount numeric,
 p_lines jsonb,p_paid numeric default 0,p_account_id uuid default null,p_notes text default null
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
 v_user uuid:=auth.uid();v_role text;v_invoice public.purchase_invoices%rowtype;v_line jsonb;v_product public.products%rowtype;
 v_qty numeric;v_cost numeric;v_disc numeric;v_subtotal numeric:=0;v_total numeric:=0;v_line_total numeric;
begin
 select role into v_role from public.app_profiles where user_id=v_user;
 if v_user is null or v_role not in ('owner','admin','accountant','operator') then raise exception 'AUTH_REQUIRED_OR_ROLE'; end if;
 if p_currency not in ('YER','SAR','USD') or coalesce(p_exchange_rate,0)<=0 then raise exception 'INVALID_CURRENCY_OR_RATE'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'LINES_REQUIRED'; end if;
 insert into public.purchase_invoices(supplier_id,status,currency,exchange_rate,discount,paid,notes,created_by)
 values(p_supplier_id,'draft',p_currency,p_exchange_rate,coalesce(p_discount,0),coalesce(p_paid,0),p_notes,v_user)
 returning * into v_invoice;
 for v_line in select value from jsonb_array_elements(p_lines) loop
   select * into v_product from public.products where id=(v_line->>'product_id')::uuid and deleted_at is null for update;
   if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
   v_qty:=coalesce(nullif(v_line->>'base_quantity','')::numeric,nullif(v_line->>'quantity','')::numeric);
   v_cost:=coalesce(nullif(v_line->>'unit_cost','')::numeric,0);v_disc:=coalesce(nullif(v_line->>'discount','')::numeric,0);
   if v_qty<=0 or v_cost<0 or v_disc<0 then raise exception 'INVALID_LINE'; end if;
   v_line_total:=v_qty*v_cost-v_disc;if v_line_total<0 then raise exception 'LINE_DISCOUNT_TOO_LARGE';end if;
   v_subtotal:=v_subtotal+v_qty*v_cost;v_total:=v_total+v_line_total;
   insert into public.purchase_invoice_lines(invoice_id,product_id,unit_name,quantity,unit_cost,discount,line_total,base_quantity)
   values(v_invoice.id,v_product.id,coalesce(v_line->>'unit_name','unit'),coalesce(nullif(v_line->>'quantity','')::numeric,v_qty),v_cost,v_disc,v_line_total,v_qty);
   update public.products set quantity=quantity+v_qty,purchase_price=v_cost,version=version+1,updated_at=now(),updated_by=v_user where id=v_product.id;
   insert into public.stock_movements(product_id,movement_type,quantity_delta,reference_table,reference_id,created_by)
   values(v_product.id,'purchase',v_qty,'purchase_invoices',v_invoice.id,v_user);
 end loop;
 v_total:=v_total-coalesce(p_discount,0);if v_total<0 then raise exception 'INVOICE_DISCOUNT_TOO_LARGE';end if;
 if coalesce(p_paid,0)<0 or p_paid>v_total then raise exception 'INVALID_PAID_AMOUNT';end if;
 update public.purchase_invoices set status='posted',subtotal=v_subtotal,total=v_total,posted_at=now() where id=v_invoice.id returning * into v_invoice;
 if coalesce(p_paid,0)>0 then
   if p_account_id is null then raise exception 'ACCOUNT_REQUIRED_FOR_PAYMENT';end if;
   if not exists(select 1 from public.financial_accounts a where a.id=p_account_id and a.currency=p_currency and a.active) then raise exception 'INVALID_FINANCIAL_ACCOUNT';end if;
   insert into public.money_movements(direction,party_type,party_id,account_id,amount,currency,exchange_rate,reference_table,reference_id,client_mutation_id,created_by)
   values('payment','supplier',p_supplier_id,p_account_id,p_paid,p_currency,p_exchange_rate,'purchase_invoices',v_invoice.id,gen_random_uuid(),v_user);
 end if;
 insert into public.audit_log(table_name,record_id,action,new_data,changed_by)
 values('purchase_invoices',v_invoice.id,'posted',to_jsonb(v_invoice),v_user);
 return jsonb_build_object('status','posted','invoice',to_jsonb(v_invoice));
end $$;
revoke all on function public.post_purchase_invoice(uuid,text,numeric,numeric,jsonb,numeric,uuid,text) from public,anon;
grant execute on function public.post_purchase_invoice(uuid,text,numeric,numeric,jsonb,numeric,uuid,text) to authenticated;

-- Add strict RLS for profile records; only self can read profile, role assignment remains owner-only/manual.
alter table public.app_profiles enable row level security;
drop policy if exists app_profiles_self_read on public.app_profiles;
create policy app_profiles_self_read on public.app_profiles for select to authenticated using (user_id=auth.uid());
revoke all on public.app_profiles from anon,authenticated;
grant select on public.app_profiles to authenticated;
