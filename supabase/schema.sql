-- Jintana Return Management: initial Supabase schema
-- Run in Supabase SQL Editor after creating a project.
create extension if not exists pgcrypto;

create type public.app_role as enum ('manager','employee');
create type public.store_work_status as enum ('waiting','in_progress','completed','cancelled');
create type public.group_status as enum ('active','cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.app_role not null default 'employee',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  storage_path text,
  imported_by uuid references public.profiles(id),
  imported_at timestamptz not null default now(),
  row_count integer not null default 0,
  store_count integer not null default 0,
  metadata jsonb not null default '{}'::jsonb
);

create table public.return_lines (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.import_batches(id),
  doc_code text,
  store_code text not null,
  store_name text,
  sku text not null,
  item_name text,
  category text,
  return_qty numeric not null default 0,
  source_row jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index return_lines_store_idx on public.return_lines(store_code);
create index return_lines_sku_idx on public.return_lines(sku);

create table public.return_groups (
  id uuid primary key default gen_random_uuid(),
  sku text not null,
  category text,
  box_capacity numeric,
  status public.group_status not null default 'active',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz
);

create table public.group_stores (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.return_groups(id),
  store_code text not null,
  store_name text,
  sku text not null,
  assigned_to uuid references public.profiles(id),
  status public.store_work_status not null default 'waiting',
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(group_id, store_code)
);
-- A store may belong to several SKU groups, but never twice in an active group for the same SKU.
-- Cancelled and completed work no longer blocks a later valid grouping.
create unique index one_active_group_per_store_sku on public.group_stores(store_code, sku)
  where status in ('waiting','in_progress');

create table public.box_capacities (
  id uuid primary key default gen_random_uuid(),
  category text,
  sku text unique,
  capacity numeric not null check (capacity > 0),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  check (category is not null or sku is not null)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.import_batches enable row level security;
alter table public.return_lines enable row level security;
alter table public.return_groups enable row level security;
alter table public.group_stores enable row level security;
alter table public.box_capacities enable row level security;
alter table public.audit_logs enable row level security;

-- Authenticated staff can view shared work data. Only managers mutate planning/configuration.
create or replace function public.is_manager()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager' and p.active=true) $$;

create policy "profiles read authenticated" on public.profiles for select to authenticated using (true);
create policy "profiles manager write" on public.profiles for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy "batches read authenticated" on public.import_batches for select to authenticated using (true);
create policy "batches manager write" on public.import_batches for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy "lines read authenticated" on public.return_lines for select to authenticated using (true);
create policy "lines manager write" on public.return_lines for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy "groups read authenticated" on public.return_groups for select to authenticated using (true);
create policy "groups manager write" on public.return_groups for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy "group stores read authenticated" on public.group_stores for select to authenticated using (true);
create policy "group stores manager update" on public.group_stores for update to authenticated using (public.is_manager()) with check (public.is_manager());
create policy "group stores manager insert delete" on public.group_stores for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy "employee complete own assigned store" on public.group_stores for update to authenticated
  using (assigned_to=auth.uid() or public.is_manager())
  with check (assigned_to=auth.uid() or public.is_manager());
create policy "capacities read authenticated" on public.box_capacities for select to authenticated using (true);
create policy "capacities manager write" on public.box_capacities for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy "audit read authenticated" on public.audit_logs for select to authenticated using (true);
create policy "audit insert authenticated" on public.audit_logs for insert to authenticated with check (actor_id=auth.uid());
alter publication supabase_realtime add table public.group_stores, public.return_groups, public.audit_logs;
