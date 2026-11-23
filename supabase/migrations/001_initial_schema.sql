-- GrowTrust initial schema.
-- Run only in the separate GrowTrust Supabase project (ref: sifaqjmvtgggyhqjbsqw).
-- No admin client access or payment processing is created here.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  account_type text not null default 'customer'
    check (account_type in ('customer', 'seller')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.seller_verifications (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  business_name text not null,
  evidence_note text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewer_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  category text not null default 'digital-marketing',
  price numeric(12,2) not null check (price >= 0),
  currency text not null default 'INR' check (currency = 'INR'),
  delivery_days integer not null default 7 check (delivery_days between 1 and 365),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'paused', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id),
  buyer_id uuid not null references auth.users(id),
  seller_id uuid not null references auth.users(id),
  requirements text not null default '',
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'INR' check (currency = 'INR'),
  status text not null default 'requested'
    check (status in ('requested', 'accepted', 'in_progress', 'delivered', 'completed', 'cancelled', 'disputed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (buyer_id <> seller_id)
);

create table if not exists public.retention_checkpoints (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  checkpoint_day integer not null check (checkpoint_day in (0, 7, 30)),
  metric_name text not null,
  baseline_value numeric,
  observed_value numeric,
  evidence_url text,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (order_id, checkpoint_day, metric_name)
);

create table if not exists public.disputes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  opened_by uuid not null references auth.users(id),
  reason text not null,
  details text not null default '',
  status text not null default 'open'
    check (status in ('open', 'under_review', 'resolved', 'closed')),
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  target_table text not null,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists seller_verifications_seller_id_idx on public.seller_verifications(seller_id);
create index if not exists services_seller_id_status_idx on public.services(seller_id, status);
create index if not exists orders_buyer_id_idx on public.orders(buyer_id);
create index if not exists orders_seller_id_idx on public.orders(seller_id);
create index if not exists disputes_order_id_idx on public.disputes(order_id);
create index if not exists retention_checkpoints_order_id_idx on public.retention_checkpoints(order_id);

alter table public.profiles enable row level security;
alter table public.seller_verifications enable row level security;
alter table public.services enable row level security;
alter table public.orders enable row level security;
alter table public.retention_checkpoints enable row level security;
alter table public.disputes enable row level security;
alter table public.admin_audit_logs enable row level security;

create policy "profiles_select_own" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "seller_verifications_select_own" on public.seller_verifications
  for select to authenticated using ((select auth.uid()) = seller_id);
create policy "seller_verifications_insert_own" on public.seller_verifications
  for insert to authenticated with check ((select auth.uid()) = seller_id);

create policy "services_public_read_active" on public.services
  for select to anon, authenticated using (status = 'active' or (select auth.uid()) = seller_id);
create policy "services_insert_own" on public.services
  for insert to authenticated with check ((select auth.uid()) = seller_id);
create policy "services_update_own" on public.services
  for update to authenticated using ((select auth.uid()) = seller_id)
  with check ((select auth.uid()) = seller_id);
create policy "services_delete_own" on public.services
  for delete to authenticated using ((select auth.uid()) = seller_id);

create policy "orders_select_participant" on public.orders
  for select to authenticated
  using ((select auth.uid()) = buyer_id or (select auth.uid()) = seller_id);
create policy "orders_insert_as_buyer" on public.orders
  for insert to authenticated
  with check (
    (select auth.uid()) = buyer_id
    and buyer_id <> seller_id
    and exists (
      select 1 from public.services s
      where s.id = service_id and s.seller_id = seller_id and s.status = 'active'
    )
  );

create policy "retention_select_participants" on public.retention_checkpoints
  for select to authenticated using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and ((select auth.uid()) = o.buyer_id or (select auth.uid()) = o.seller_id)
    )
  );

create policy "disputes_select_participants" on public.disputes
  for select to authenticated using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and ((select auth.uid()) = o.buyer_id or (select auth.uid()) = o.seller_id)
    )
  );
create policy "disputes_insert_order_participant" on public.disputes
  for insert to authenticated with check (
    (select auth.uid()) = opened_by
    and exists (
      select 1 from public.orders o
      where o.id = order_id
        and ((select auth.uid()) = o.buyer_id or (select auth.uid()) = o.seller_id)
    )
  );

-- admin_audit_logs intentionally has no client-facing policies.
-- Trusted server-side admin authorization will be added separately.
