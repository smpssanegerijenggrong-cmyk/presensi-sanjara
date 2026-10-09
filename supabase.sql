-- Sistem Absensi Wajah Siswa Realtime / Presensi Sanjara
-- Jalankan seluruh skrip di Supabase Dashboard > SQL Editor.
-- Skrip ini tidak menghapus data; aman dijalankan ulang untuk skema aplikasi ini.
-- Gunakan proyek baru atau audit kebijakan lama: kebijakan RLS lain yang permisif
-- dapat memperluas akses. Kunci publik browser saja TIDAK memberikan akses data.

begin;

-- Validator untuk descriptor keluaran face-api.js: tepat 128 angka JSON.
create or replace function public.valid_face_descriptor(descriptor jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if jsonb_typeof(descriptor) <> 'array' then
    return false;
  end if;
  if jsonb_array_length(descriptor) <> 128 then
    return false;
  end if;
  return not exists (
    select 1
    from jsonb_array_elements(descriptor) as element(value)
    where jsonb_typeof(element.value) <> 'number'
  );
end;
$$;

create table if not exists public.school_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  nisn text not null unique,
  name text not null,
  class_name text not null,
  face_descriptor jsonb not null,
  -- Foto thumbnail tersimpan langsung sebagai data URL; tidak perlu bucket Storage.
  photo_url text,
  created_at timestamptz not null default now(),
  constraint students_nisn_format check (nisn ~ '^[0-9]{10}$'),
  constraint students_name_length check (char_length(btrim(name)) between 1 and 120),
  constraint students_class_name_length check (char_length(btrim(class_name)) between 1 and 80),
  constraint students_descriptor_valid check (public.valid_face_descriptor(face_descriptor)),
  constraint students_photo_valid check (
    photo_url is null or (
      octet_length(photo_url) <= 400000
      and photo_url ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$'
    )
  )
);

create table if not exists public.attendances (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_name text not null,
  -- Hari sekolah menggunakan WIB, tidak bergantung pada zona waktu browser/database.
  date date not null default ((now() at time zone 'Asia/Jakarta')::date),
  time time not null default ((now() at time zone 'Asia/Jakarta')::time(0)),
  status text not null default 'Hadir',
  constraint attendances_student_date_unique unique (student_id, date),
  constraint attendances_status_valid check (status = 'Hadir')
);

create index if not exists students_class_name_idx on public.students(class_name);
create index if not exists attendances_date_class_idx on public.attendances(date, class_name);

-- Keanggotaan guru dikelola hanya dari Dashboard/SQL Editor, bukan dari aplikasi.
-- SECURITY DEFINER menghindari rekursi kebijakan school_staff. UID selalu berasal
-- dari sesi Supabase Auth; fungsi tidak menerima parameter ID yang bisa dipalsukan.
create or replace function public.is_school_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.school_staff
    where user_id = (select auth.uid())
  );
$$;

-- Database menjadi sumber waktu dan kelas yang berwenang. date/time/class_name
-- kiriman browser selalu diganti, termasuk ketika dua perangkat mengabsen bersamaan.
create or replace function public.prepare_school_attendance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  student_class text;
  school_now timestamp;
begin
  select class_name into student_class
  from public.students
  where id = new.student_id;
  if not found then
    raise exception 'Siswa tidak ditemukan' using errcode = '23503';
  end if;
  school_now := statement_timestamp() at time zone 'Asia/Jakarta';
  new.class_name := student_class;
  new.date := school_now::date;
  new.time := school_now::time(0);
  new.status := 'Hadir';
  return new;
end;
$$;

drop trigger if exists presensi_prepare_attendance on public.attendances;
create trigger presensi_prepare_attendance
before insert on public.attendances
for each row execute function public.prepare_school_attendance();

alter table public.school_staff enable row level security;
alter table public.students enable row level security;
alter table public.attendances enable row level security;

-- Tidak ada kebijakan anon. Kunci anon/publishable baru dapat mengakses data
-- setelah login akun guru yang UUID-nya masuk school_staff.
revoke all on table public.school_staff, public.students, public.attendances
  from public, anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.school_staff to authenticated;
grant select, insert on public.students, public.attendances to authenticated;

revoke all on function public.valid_face_descriptor(jsonb) from public, anon;
grant execute on function public.valid_face_descriptor(jsonb) to authenticated;
revoke all on function public.is_school_staff() from public, anon;
grant execute on function public.is_school_staff() to authenticated;
revoke all on function public.prepare_school_attendance() from public, anon, authenticated;

drop policy if exists presensi_staff_read_self on public.school_staff;
create policy presensi_staff_read_self on public.school_staff
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists presensi_students_read on public.students;
create policy presensi_students_read on public.students
for select to authenticated
using ((select public.is_school_staff()));

drop policy if exists presensi_students_enroll on public.students;
create policy presensi_students_enroll on public.students
for insert to authenticated
with check ((select public.is_school_staff()));

drop policy if exists presensi_attendances_read on public.attendances;
create policy presensi_attendances_read on public.attendances
for select to authenticated
using ((select public.is_school_staff()));

drop policy if exists presensi_attendances_insert on public.attendances;
create policy presensi_attendances_insert on public.attendances
for insert to authenticated
with check ((select public.is_school_staff()));

-- Aktifkan Realtime presensi dan perubahan siswa sekali saja, termasuk saat rerun.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'attendances'
  ) then
    alter publication supabase_realtime add table public.attendances;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'students'
  ) then
    alter publication supabase_realtime add table public.students;
  end if;
end;
$$;

commit;

-- SETUP GURU: buat akun Email/Password melalui Dashboard > Authentication > Users
-- > Add user; salin User UID, lalu jalankan query berikut dengan UUID sebenarnya.
-- Jangan jalankan contoh UUID di bawah tanpa menggantinya.
-- insert into public.school_staff (user_id)
-- values ('UUID-AKUN-GURU') on conflict (user_id) do nothing;

-- Untuk mencabut akses akun guru, jalankan lewat SQL Editor:
-- delete from public.school_staff where user_id = 'UUID-AKUN-GURU';

-- Retensi/koreksi dikelola admin lewat SQL Editor. Menghapus siswa otomatis
-- menghapus presensinya melalui ON DELETE CASCADE: arsipkan laporan lebih dulu.
