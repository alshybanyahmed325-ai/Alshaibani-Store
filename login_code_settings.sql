-- إعداد رمز مستخدم مستقل عن كلمة مرور Supabase.
-- شغّل هذا الملف مرة واحدة في SQL Editor للمشروع.
create table if not exists public.system_login_settings (
  singleton boolean primary key default true check (singleton),
  login_code text not null check (login_code ~ '^[0-9]{6}$'),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
insert into public.system_login_settings(singleton, login_code)
values (true, '383280')
on conflict (singleton) do nothing;
revoke all on public.system_login_settings from anon, authenticated;

create or replace function public.check_shaybani_login_code(p_code text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.system_login_settings s
    where s.singleton = true and s.login_code = p_code
  );
$$;
revoke all on function public.check_shaybani_login_code(text) from public;
grant execute on function public.check_shaybani_login_code(text) to anon, authenticated;

create or replace function public.change_shaybani_login_code(p_new_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;
  if not exists (select 1 from public.app_profiles p where p.user_id = auth.uid() and p.role = 'owner') then
    raise exception 'غير مصرح: هذه العملية لمالك النظام فقط';
  end if;
  if p_new_code is null or p_new_code !~ '^[0-9]{6}$' then
    raise exception 'يجب أن يتكون الرمز من 6 أرقام';
  end if;
  update public.system_login_settings
     set login_code = p_new_code, updated_at = now(), updated_by = auth.uid()
   where singleton = true;
  if not found then
    raise exception 'إعداد رمز الدخول غير مهيأ';
  end if;
end;
$$;
revoke all on function public.change_shaybani_login_code(text) from public;
grant execute on function public.change_shaybani_login_code(text) to authenticated;
