-- ============================================================
-- VOVINAM DZ — Migration 001
-- جدول clubs + الفهارس + updated_at + الأمان (Row Level Security)
-- نفّذ هذا الملف كاملاً داخل Supabase SQL Editor
-- ============================================================

-- gen_random_uuid() يحتاج امتداد pgcrypto (مفعّل افتراضيًا في Supabase غالبًا،
-- لكن هذا السطر آمن حتى لو كان مفعّلاً مسبقًا)
create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1) الجدول الرئيسي
-- ------------------------------------------------------------
create table if not exists clubs (
  id              uuid primary key default gen_random_uuid(),

  club_name       text not null,
  wilaya          text not null,
  commune         text not null,
  address         text,
  coach_name      text not null,
  phone           text not null,
  whatsapp        text,
  training_days   text,               -- مثال: "السبت، الاثنين، الأربعاء"
  training_hours  text,               -- مثال: "18:00 - 20:00"
  latitude        double precision not null,
  longitude       double precision not null,
  image_url       text,

  status          text not null default 'pending'
                  check (status in ('pending', 'approved', 'rejected')),

  -- تمهيدًا لربط النادي بحساب مدرب/مسؤول لاحقًا. اختياري حاليًا، لا Auth بعد.
  submitted_by    uuid null,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table clubs is 'أندية وقاعات تدريب الفوفينام في الجزائر — VOVINAM DZ';
comment on column clubs.status is 'pending | approved | rejected — يُفرض pending على أي إدخال عام عبر trigger';
comment on column clubs.submitted_by is 'مرجع مستقبلي لحساب المدرب/المسؤول عن النادي — NULL مسموح حاليًا';

-- ------------------------------------------------------------
-- 2) الفهارس (Indexes) — لتسريع البحث والفلترة
-- ------------------------------------------------------------
create index if not exists idx_clubs_status  on clubs (status);
create index if not exists idx_clubs_wilaya  on clubs (wilaya);
create index if not exists idx_clubs_commune on clubs (commune);

-- ------------------------------------------------------------
-- 3) تحديث updated_at تلقائيًا عند أي UPDATE
-- ------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_clubs_updated_at on clubs;
create trigger trg_clubs_updated_at
before update on clubs
for each row
execute function set_updated_at();

-- ------------------------------------------------------------
-- 4) فرض status = 'pending' على أي INSERT — على مستوى قاعدة البيانات
--    (طبقة حماية إضافية فوق RLS: حتى لو أرسل العميل status مختلفًا
--    في الـ payload، يتم تجاهله واستبداله بـ 'pending' دائمًا)
-- ------------------------------------------------------------
create or replace function force_pending_on_insert()
returns trigger
language plpgsql
as $$
begin
  new.status     := 'pending';
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_clubs_force_pending on clubs;
create trigger trg_clubs_force_pending
before insert on clubs
for each row
execute function force_pending_on_insert();

-- ------------------------------------------------------------
-- 5) Row Level Security (RLS)
-- ------------------------------------------------------------
alter table clubs enable row level security;

-- أي عملية بدون Policy صريحة = مرفوضة تلقائيًا (هذا يغطي UPDATE و DELETE
-- للعامة دون الحاجة لكتابة "policy رفض" — عدم وجود Policy يعني منعًا تلقائيًا)

-- (أ) القراءة العامة: فقط الأندية المعتمدة
drop policy if exists "public_select_approved" on clubs;
create policy "public_select_approved"
on clubs
for select
to anon, authenticated
using (status = 'approved');

-- (ب) الإضافة العامة: مسموحة، لكن status يُفرض pending عبر الـ trigger أعلاه
-- (هذا الشرط هنا طبقة حماية ثانية على مستوى RLS أيضًا)
drop policy if exists "public_insert_pending" on clubs;
create policy "public_insert_pending"
on clubs
for insert
to anon, authenticated
with check (status = 'pending');

-- لا توجد أي policy لـ UPDATE أو DELETE لأدوار anon/authenticated.
-- عمليات الإدارة (قراءة pending، اعتماد، رفض، تعديل، حذف) تتم حصريًا
-- عبر مفتاح service_role من جهة خادم آمنة (Edge Function) — هذا المفتاح
-- يتجاوز RLS تلقائيًا ولا يُستخدم أبدًا داخل كود المتصفح.

-- ============================================================
-- نهاية Migration 001
-- ============================================================
