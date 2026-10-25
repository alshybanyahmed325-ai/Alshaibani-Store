-- محلات الشيباني: الإعجابات وتعليقات العملاء (آمن لإعادة التشغيل ولا يعدّل المنتجات أو الطلبات الحالية)
create extension if not exists pgcrypto;

create table if not exists public.product_likes (
  product_id uuid not null references public.products(id) on delete cascade,
  visitor_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (product_id, visitor_id)
);

create table if not exists public.product_comments (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  visitor_id uuid not null,
  customer_name varchar(60) not null check (char_length(trim(customer_name)) between 2 and 60),
  body text not null check (char_length(trim(body)) between 2 and 600),
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_product_comments_product_approved_created
  on public.product_comments (product_id, approved, created_at desc);
create index if not exists idx_product_comments_created
  on public.product_comments (created_at desc);

alter table public.product_likes enable row level security;
alter table public.product_comments enable row level security;

revoke all on table public.product_likes from public, anon, authenticated;
revoke all on table public.product_comments from public, anon, authenticated;
grant select, insert on table public.product_comments to anon, authenticated;
grant update, delete on table public.product_comments to authenticated;

drop policy if exists "Public can read approved product comments" on public.product_comments;
drop policy if exists "Visitors submit pending product comments" on public.product_comments;
drop policy if exists "Admins manage product comments" on public.product_comments;
create policy "Public can read approved product comments" on public.product_comments
  for select to anon, authenticated
  using (approved = true or public.is_store_admin());
create policy "Visitors submit pending product comments" on public.product_comments
  for insert to anon, authenticated
  with check (
    approved = false
    and char_length(trim(customer_name)) between 2 and 60
    and char_length(trim(body)) between 2 and 600
    and exists (select 1 from public.products p where p.id = product_id and p.active = true)
  );
create policy "Admins manage product comments" on public.product_comments
  for all to authenticated
  using (public.is_store_admin())
  with check (public.is_store_admin());

create or replace function public.get_product_social_stats(p_visitor_id uuid default null)
returns table (product_id uuid, likes_count bigint, comments_count bigint, has_liked boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id,
    (select count(*) from public.product_likes l where l.product_id = p.id) as likes_count,
    (select count(*) from public.product_comments c where c.product_id = p.id and c.approved = true) as comments_count,
    case when p_visitor_id is null then false else exists (
      select 1 from public.product_likes l where l.product_id = p.id and l.visitor_id = p_visitor_id
    ) end as has_liked
  from public.products p
  where p.active = true;
$$;

create or replace function public.toggle_product_like(p_product_id uuid, p_visitor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_liked boolean;
  v_count bigint;
begin
  if p_product_id is null or p_visitor_id is null then
    raise exception 'معرّف المنتج والزائر مطلوبان';
  end if;
  if not exists (select 1 from public.products p where p.id = p_product_id and p.active = true) then
    raise exception 'المنتج غير متاح';
  end if;
  if exists (select 1 from public.product_likes l where l.product_id = p_product_id and l.visitor_id = p_visitor_id) then
    delete from public.product_likes where product_id = p_product_id and visitor_id = p_visitor_id;
    v_liked := false;
  else
    insert into public.product_likes(product_id, visitor_id)
    values (p_product_id, p_visitor_id)
    on conflict (product_id, visitor_id) do nothing;
    v_liked := true;
  end if;
  select count(*) into v_count from public.product_likes where product_id = p_product_id;
  return jsonb_build_object('liked', v_liked, 'likes_count', v_count);
end;
$$;

revoke all on function public.get_product_social_stats(uuid) from public;
revoke all on function public.toggle_product_like(uuid, uuid) from public;
grant execute on function public.get_product_social_stats(uuid) to anon, authenticated;
grant execute on function public.toggle_product_like(uuid, uuid) to anon, authenticated;

comment on table public.product_likes is 'إعجابات العملاء بالمنتجات؛ لا يمكن للعميل قراءة معرفات الزوار مباشرة.';
comment on table public.product_comments is 'تعليقات العملاء؛ لا تظهر علناً قبل موافقة المشرف.';
