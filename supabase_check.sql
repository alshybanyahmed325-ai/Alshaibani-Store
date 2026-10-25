-- فحوصات قراءة فقط: لا تغيّر أي بيانات
SELECT 'products' AS item, count(*)::text AS result FROM public.products
UNION ALL
SELECT 'orders', count(*)::text FROM public.orders
UNION ALL
SELECT 'admin roles', count(*)::text FROM public.user_roles WHERE role = 'admin';

SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'product-images';

SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE (schemaname = 'storage' AND tablename = 'objects')
   OR (schemaname = 'public' AND tablename IN ('products','orders','store_settings','user_roles'))
ORDER BY schemaname, tablename, policyname;

SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('products','orders','store_settings','user_roles')
ORDER BY table_name, ordinal_position;
