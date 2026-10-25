-- محلات الشيباني: مخطط قاعدة بيانات Supabase
-- نفّذ هذا الملف كاملاً في SQL Editor داخل مشروع Supabase.
create extension if not exists pgcrypto;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'متنوع',
  price numeric(12,2) not null default 0 check (price >= 0),
  unit text not null default 'وحدة',
  stock integer not null default 0 check (stock >= 0),
  emoji text not null default '🌿',
  description text not null default '',
  image_url text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.store_settings (
  id integer primary key check (id = 1),
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  customer_name text not null,
  phone text not null,
  city text not null,
  address text not null default '',
  fulfillment text not null default 'توصيل',
  notes text not null default '',
  items jsonb not null default '[]'::jsonb,
  total numeric(12,2) not null default 0 check (total >= 0),
  status text not null default 'new' check (status in ('new','confirmed','preparing','shipped','delivered','cancelled')),
  created_at timestamptz not null default now()
);

alter table public.products enable row level security;
alter table public.store_settings enable row level security;
alter table public.user_roles enable row level security;
alter table public.orders enable row level security;

create or replace function public.is_store_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$ select exists(select 1 from public.user_roles where user_id = auth.uid() and role = 'admin'); $$;
revoke all on function public.is_store_admin() from public;
grant execute on function public.is_store_admin() to anon, authenticated;

-- Avoid duplicate policy names when the script is re-run.
drop policy if exists "Public can read active products" on public.products;
drop policy if exists "Admins manage products" on public.products;
drop policy if exists "Public can read store settings" on public.store_settings;
drop policy if exists "Admins manage store settings" on public.store_settings;
drop policy if exists "Users can read their own role" on public.user_roles;
drop policy if exists "Admins can read orders" on public.orders;
drop policy if exists "Admins can update orders" on public.orders;
drop policy if exists "Admins can delete orders" on public.orders;

create policy "Public can read active products" on public.products
for select to anon, authenticated using (active = true or public.is_store_admin());
create policy "Admins manage products" on public.products
for all to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

create policy "Public can read store settings" on public.store_settings
for select to anon, authenticated using (true);
create policy "Admins manage store settings" on public.store_settings
for all to authenticated using (public.is_store_admin()) with check (public.is_store_admin());

create policy "Users can read their own role" on public.user_roles
for select to authenticated using (user_id = auth.uid());

create policy "Admins can read orders" on public.orders
for select to authenticated using (public.is_store_admin());
create policy "Admins can update orders" on public.orders
for update to authenticated using (public.is_store_admin()) with check (public.is_store_admin());
create policy "Admins can delete orders" on public.orders
for delete to authenticated using (public.is_store_admin());

insert into public.store_settings(id, settings) values (1, '{
  "name":"محلات الشيباني",
  "subtitle":"للبهارات والأعشاب الطبيعية",
  "whatsapp":"",
  "currency":"ر.ي",
  "heroTitle":"سرّ النكهة يبدأ من هنا 🌿",
  "heroText":"اختاروا من تشكيلتنا المتنوعة من البهارات والأعشاب الطبيعية، وأرسلوا طلبكم بسهولة من الجوال.",
  "footerText":"نسعد بخدمتكم ونرحب بطلباتكم."
}'::jsonb) on conflict (id) do nothing;

insert into public.products(name,category,price,unit,stock,emoji,description,active)
select x.name,x.category,x.price,x.unit,x.stock,x.emoji,x.description,true
from (values
 ('كركم مطحون','بهارات',500,'100 جرام',20,'🌕','لون ذهبي ونكهة مميزة.'),
 ('قرفة','بهارات',700,'100 جرام',20,'🪵','رائحة دافئة تناسب الحلويات والمشروبات.'),
 ('حبة البركة','أعشاب طبيعية',600,'100 جرام',20,'🌱','من المنتجات الطبيعية المحببة.'),
 ('يانسون','أعشاب طبيعية',500,'100 جرام',20,'🌿','رائحة عطرية لطيفة للمشروبات.'),
 ('كمون','بهارات',500,'100 جرام',20,'🟤','نكهة أساسية للعديد من الأطباق.'),
 ('زنجبيل مطحون','بهارات',600,'100 جرام',20,'🫚','نكهة قوية ودافئة.'),
 ('بابونج','أعشاب طبيعية',700,'100 جرام',20,'🌼','أزهار مجففة للمشروبات العشبية.'),
 ('سمسم','حبوب وبذور',400,'100 جرام',20,'🌾','مناسب للخبز والوصفات المتنوعة.')
) as x(name,category,price,unit,stock,emoji,description)
where not exists(select 1 from public.products p where p.name=x.name);

-- متجر الشيباني: تحديث آمن لمشروع Supabase موجود. لا يحذف المنتجات أو الطلبات.
create extension if not exists pgcrypto;

-- ضمان وجود سجل الإعدادات الافتراضي دون الكتابة فوق الإعدادات الحالية
insert into public.store_settings(id, settings) values (1, '{
  "name":"محلات الشيباني",
  "subtitle":"للبهارات والأعشاب الطبيعية",
  "whatsapp":"",
  "currency":"ر.ي",
  "heroTitle":"سرّ النكهة يبدأ من هنا 🌿",
  "heroText":"اختاروا من تشكيلتنا المتنوعة من البهارات والأعشاب الطبيعية، وأرسلوا طلبكم بسهولة من الجوال.",
  "footerText":"نسعد بخدمتكم ونرحب بطلباتكم."
}'::jsonb) on conflict (id) do nothing;

-- تحديثات آمنة لنسخة المتجر: العملات وصور المنتجات والطلبات
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'YER';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'YER';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'الدفع عند الاستلام';
UPDATE public.products SET currency = 'YER' WHERE currency IS NULL OR currency NOT IN ('YER','SAR','USD');
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_currency_check;
ALTER TABLE public.products ADD CONSTRAINT products_currency_check CHECK (currency IN ('YER','SAR','USD'));

-- فهارس لتحسين سرعة الفرز والبحث في لوحة الإدارة والواجهة
CREATE INDEX IF NOT EXISTS idx_products_active_created ON public.products (active, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders (status);

-- حاوية صور المنتجات (عامة للعرض، والرفع والتعديل والحذف للمدير فقط)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('product-images','product-images',true,5242880,array['image/jpeg','image/png','image/webp','image/gif','image/avif'])
ON CONFLICT (id) DO UPDATE SET public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif','image/avif'];

DROP POLICY IF EXISTS "Public can view product images" ON storage.objects;
CREATE POLICY "Public can view product images" ON storage.objects FOR SELECT TO public USING (bucket_id='product-images');
DROP POLICY IF EXISTS "Admins can upload product images" ON storage.objects;
CREATE POLICY "Admins can upload product images" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id='product-images' AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='admin'));
DROP POLICY IF EXISTS "Admins can update product images" ON storage.objects;
CREATE POLICY "Admins can update product images" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id='product-images' AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='admin')) WITH CHECK (bucket_id='product-images' AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='admin'));
DROP POLICY IF EXISTS "Admins can delete product images" ON storage.objects;
CREATE POLICY "Admins can delete product images" ON storage.objects FOR DELETE TO authenticated USING (bucket_id='product-images' AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='admin'));

-- تسجيل الطلب والتحقق من العملة والمخزون داخل معاملة واحدة آمنة
CREATE OR REPLACE FUNCTION public.submit_store_order(p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_item jsonb;
  v_product public.products%rowtype;
  v_product_id uuid;
  v_qty integer;
  v_total numeric(12,2) := 0;
  v_currency text := coalesce(nullif(p_order->>'currency',''), 'YER');
  v_lines jsonb := '[]'::jsonb;
  v_number text := coalesce(nullif(p_order->>'order_number',''), 'SH' || substr(replace(gen_random_uuid()::text,'-',''),1,8));
  v_name text := trim(coalesce(p_order->>'customer_name',''));
  v_phone text := trim(coalesce(p_order->>'phone',''));
  v_city text := trim(coalesce(p_order->>'city',''));
  v_address text := coalesce(p_order->>'address','');
  v_fulfillment text := coalesce(nullif(p_order->>'fulfillment',''),'توصيل');
  v_payment_method text := coalesce(nullif(p_order->>'payment_method',''),'الدفع عند الاستلام');
  v_notes text := coalesce(p_order->>'notes','');
BEGIN
  IF v_name = '' OR v_phone = '' OR v_city = '' THEN
    RAISE EXCEPTION 'الاسم والهاتف والمنطقة مطلوبة';
  END IF;
  IF v_currency NOT IN ('YER','SAR','USD') THEN
    RAISE EXCEPTION 'العملة المحددة غير مدعومة';
  END IF;
  IF jsonb_typeof(p_order->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(coalesce(p_order->'items','[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'الطلب لا يحتوي على منتجات';
  END IF;

  -- ضمان عدم تكرار رقم الطلب
  IF EXISTS (SELECT 1 FROM public.orders WHERE order_number = v_number) THEN
    v_number := 'SH' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_order->'items') LOOP
    BEGIN
      v_product_id := (v_item->>'product_id')::uuid;
      v_qty := (v_item->>'quantity')::integer;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'بيانات المنتج أو الكمية غير صحيحة';
    END;
    IF v_qty IS NULL OR v_qty < 1 THEN RAISE EXCEPTION 'كمية غير صالحة'; END IF;
    SELECT * INTO v_product FROM public.products WHERE id = v_product_id AND active = true FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'أحد المنتجات غير متوفر حالياً'; END IF;
    IF v_product.stock < v_qty THEN RAISE EXCEPTION 'الكمية المطلوبة من المنتج (%) غير متوفرة (المتبقي: %)', v_product.name, v_product.stock; END IF;
    IF coalesce(v_product.currency,'YER') <> v_currency THEN RAISE EXCEPTION 'العملة المحددة لا تطابق عملة المنتج (%)', v_product.name; END IF;
    v_total := v_total + (v_product.price * v_qty);
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'product_id',v_product.id,'name',v_product.name,'unit',v_product.unit,
      'price',v_product.price,'currency',v_product.currency,'quantity',v_qty
    ));
    UPDATE public.products SET stock = stock - v_qty WHERE id = v_product.id;
  END LOOP;

  INSERT INTO public.orders(order_number,customer_name,phone,city,address,fulfillment,notes,items,total,status,currency,payment_method)
  VALUES(v_number,v_name,v_phone,v_city,v_address,v_fulfillment,v_notes,v_lines,v_total,'new',v_currency,v_payment_method);
  RETURN jsonb_build_object('order_number',v_number,'total',v_total,'status','new','items',v_lines,'currency',v_currency,'payment_method',v_payment_method);
END;
$$;
REVOKE ALL ON FUNCTION public.submit_store_order(jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.submit_store_order(jsonb) TO anon, authenticated;


-- ============================================================
-- Hardened access control for the public storefront + admin panel
-- Safe to re-run. Replaces table policies on these four store tables
-- so an older permissive policy cannot override the rules below.
-- ============================================================
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_store_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  );
$$;
REVOKE ALL ON FUNCTION public.is_store_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_store_admin() TO anon, authenticated;

DO $$
DECLARE pol record;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('products','store_settings','user_roles','orders')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);
  END LOOP;
END $$;

-- Store only explicitly public display fields in the JSON read by visitors.
-- Any legacy admin PIN/password or unknown internal key is dropped from public settings.
UPDATE public.store_settings
SET settings = jsonb_strip_nulls(jsonb_build_object(
  'name', settings->'name',
  'subtitle', settings->'subtitle',
  'whatsapp', settings->'whatsapp',
  'contacts', settings->'contacts',
  'paymentMethods', settings->'paymentMethods',
  'theme', settings->'theme',
  'shareUrl', settings->'shareUrl',
  'heroImageUrl', settings->'heroImageUrl',
  'currency', settings->'currency',
  'announcement', settings->'announcement',
  'heroTitle', settings->'heroTitle',
  'heroText', settings->'heroText',
  'footerText', settings->'footerText'
));

-- Clear explicit privileges, then grant only the operations required by the app.
REVOKE ALL ON TABLE public.products, public.store_settings, public.user_roles, public.orders FROM anon, authenticated;
GRANT SELECT ON TABLE public.products, public.store_settings TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.products, public.store_settings TO authenticated;
GRANT SELECT ON TABLE public.user_roles TO authenticated;
GRANT SELECT, UPDATE, DELETE ON TABLE public.orders TO authenticated;

-- Catalog: visitors may read active products only; admins may manage all products.
CREATE POLICY "Public can read active products" ON public.products
  FOR SELECT TO anon, authenticated
  USING (active = true OR public.is_store_admin());
CREATE POLICY "Admins manage products" ON public.products
  FOR ALL TO authenticated
  USING (public.is_store_admin()) WITH CHECK (public.is_store_admin());

-- Storefront configuration is public display content only. Do not store secrets here.
CREATE POLICY "Public can read store settings" ON public.store_settings
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Admins manage store settings" ON public.store_settings
  FOR ALL TO authenticated
  USING (public.is_store_admin()) WITH CHECK (public.is_store_admin());

-- A signed-in user can read only their own role row; no client can assign roles.
CREATE POLICY "Users can read their own role" ON public.user_roles
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Customer orders are inaccessible to the public. New orders are submitted only
-- through the validated SECURITY DEFINER RPC submit_store_order(jsonb).
CREATE POLICY "Admins can read orders" ON public.orders
  FOR SELECT TO authenticated USING (public.is_store_admin());
CREATE POLICY "Admins can update orders" ON public.orders
  FOR UPDATE TO authenticated
  USING (public.is_store_admin()) WITH CHECK (public.is_store_admin());
CREATE POLICY "Admins can delete orders" ON public.orders
  FOR DELETE TO authenticated USING (public.is_store_admin());

-- ===== تفعيل إعجابات وتعليقات العملاء =====
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
