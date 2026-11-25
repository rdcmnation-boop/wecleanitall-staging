-- Test-only stand-in for the parts of the wcia-staging Contract Center that contract_marketplace.sql uses.
-- Column names, defaults and checks copied from wcia-staging (read on 2026-11-25). Never run against a real project.
alter table public.workers add column if not exists provider_type text not null default 'individual'
  check (provider_type in ('wcia_team','individual','company'));

create table if not exists public.markets (id text primary key, name text not null default '');
create or replace function public._market_of_zip(p_zip text) returns text language sql stable as $$
  select case when p_zip like '333%' then 'fl-broward' when p_zip like '331%' then 'fl-miami-dade' end $$;
create table if not exists public.provider_coverage (
  worker_id uuid references public.workers(id) on delete cascade, market_id text references public.markets(id),
  status text not null default 'pending' check (status in ('pending','approved','suspended')), approved_at timestamptz, approved_by uuid);
create table if not exists public.insurance_policies (
  id bigint generated always as identity primary key, worker_id uuid references public.workers(id) on delete cascade,
  kind text check (kind in ('general_liability','workers_comp','bond','auto')), carrier text default '', policy_number text default '',
  coverage_usd numeric, starts_on date, expires_on date, status text default 'submitted' check (status in ('submitted','verified','rejected')),
  document_path text default '', verified_by uuid, verified_at timestamptz, created_at timestamptz default now());
create table if not exists public.provider_compliance (
  id bigint generated always as identity primary key, worker_id uuid references public.workers(id) on delete cascade,
  requirement text check (requirement in ('id_verification','background_check','business_license','contractor_agreement','w9','other')),
  state_code text default '', status text default 'submitted' check (status in ('submitted','verified','rejected','expired')),
  document_path text default '', expires_on date, verified_by uuid, verified_at timestamptz, created_at timestamptz default now());
alter table public.insurance_policies enable row level security;
alter table public.provider_compliance enable row level security;
alter table public.provider_coverage enable row level security;
revoke all on public.insurance_policies, public.provider_compliance, public.provider_coverage, public.markets from anon, authenticated;

create schema if not exists contract_center;
grant usage on schema contract_center to anon, authenticated;
create sequence if not exists contract_center.opportunity_code_seq;
create sequence if not exists contract_center.contract_code_seq;
create table contract_center.buyers (id uuid primary key default gen_random_uuid(), name text not null, is_test bool not null default false);
create table contract_center.opportunities (
  id uuid primary key default gen_random_uuid(), code text not null default ('OPP-' || nextval('contract_center.opportunity_code_seq')) unique,
  title text not null, summary text not null default '', sector text not null default 'commercial', buyer_id uuid references contract_center.buyers(id),
  status text not null default 'discovered', market_id text, incumbent_name text, estimated_monthly_value numeric,
  verification_status text not null default 'unverified' check (verification_status in ('unverified','auto_checked','verified','failed')),
  visibility text not null default 'internal', is_test bool not null default false, updated_at timestamptz not null default now(),
  constraint opportunities_visibility_check check (visibility in ('internal','marketplace')),
  constraint opportunities_check4 check ((not is_test) or (title like 'TEST — %')));
create table contract_center.opportunity_locations (
  id uuid primary key default gen_random_uuid(), opportunity_id uuid not null references contract_center.opportunities(id) on delete cascade,
  name text not null default '', address text not null default '', city text not null default '', county text not null default '',
  state_code text not null default '', zip text, building_type text not null default 'other', sqft int, floors int, restrooms int,
  is_primary bool not null default false);
create table contract_center.opportunity_requirements (
  id uuid primary key default gen_random_uuid(), opportunity_id uuid not null references contract_center.opportunities(id) on delete cascade,
  category text not null, requirement text not null, mandatory bool not null default true, source_excerpt text not null default '');
create table contract_center.scope_items (
  id uuid primary key default gen_random_uuid(), opportunity_id uuid not null references contract_center.opportunities(id) on delete cascade,
  area_type text not null default 'general', task text not null, frequency text not null, quantity numeric not null, unit text not null,
  notes text not null default '');
create table contract_center.contracts (
  id uuid primary key default gen_random_uuid(), code text not null default ('CTR-' || nextval('contract_center.contract_code_seq')),
  opportunity_id uuid not null unique references contract_center.opportunities(id), title text not null, status text not null default 'onboarding',
  start_date date, monthly_value numeric not null default 0, requires_provider_insurance bool not null default true,
  required_compliance text[] not null default '{}');
create table contract_center.provider_assignments (
  id uuid primary key default gen_random_uuid(), contract_id uuid not null references contract_center.contracts(id) on delete cascade,
  location_id uuid references contract_center.opportunity_locations(id) on delete set null, worker_id uuid not null references public.workers(id),
  role text not null default 'subcontractor' check (role in ('subcontractor','crew','backup','supervisor')),
  status text not null default 'proposed' check (status in ('proposed','approved','active','ended','rejected')),
  pay_basis text not null check (pay_basis in ('hourly','monthly','per_visit')), pay_rate numeric not null check (pay_rate >= 0),
  start_date date, end_date date, eligibility jsonb not null default '{}', approval_id uuid,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table contract_center.events (
  id bigint generated always as identity primary key, at timestamptz not null default now(), entity_type text not null, entity_id text,
  opportunity_id uuid, event text not null, from_status text, to_status text, actor_type text not null, actor_id uuid, agent text,
  data jsonb not null default '{}',
  check (entity_type in ('opportunity','prospect','proposal','contract','invoice','source','settings','territory','provider')),
  check (actor_type in ('owner','agent','system')), check (event ~ '^[a-z_]+(\.[a-z_]+)?$'));
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname = 'contract_center' loop
    execute format('alter table contract_center.%I enable row level security', t);
    execute format('revoke all on contract_center.%I from anon, authenticated', t);
  end loop; end $$;

-- Helpers copied from wcia-staging.
create or replace function contract_center._require_owner() returns uuid language plpgsql stable security definer set search_path = '' as $$
begin
if auth.uid() is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then raise exception 'admin_only'; end if;
if not public.is_admin() then raise exception 'admin_only'; end if;
return auth.uid();
end $$;
create or replace function contract_center._log(p_entity text, p_id text, p_opp uuid, p_event text, p_from text, p_to text, p_actor text, p_agent text, p_data jsonb)
returns void language sql security definer set search_path = '' as $$
insert into contract_center.events(entity_type, entity_id, opportunity_id, event, from_status, to_status, actor_type, actor_id, agent, data)
values (p_entity, p_id, p_opp, p_event, p_from, p_to, p_actor, case when p_actor = 'owner' then auth.uid() end, p_agent, coalesce(p_data, '{}'));
$$;
create or replace function contract_center._alert_owner(p_template text, p_payload jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
select user_id into v_owner from public.admins limit 1;
if v_owner is not null and exists (select 1 from public.profiles where id = v_owner) then perform public._notify(v_owner, p_template, coalesce(p_payload, '{}')); end if;
end $$;
create or replace function contract_center.provider_contract_block_reason(p_worker uuid, p_contract uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers; c contract_center.contracts;
begin
select * into w from public.workers where id = p_worker;
select * into c from contract_center.contracts where id = p_contract;
if w.id is null or c.id is null then return 'not_found'; end if;
if w.status <> 'approved' then return 'not_approved'; end if;
if c.requires_provider_insurance and not exists (select 1 from public.insurance_policies i where i.worker_id = w.id and i.kind = 'general_liability'
  and i.status = 'verified' and i.expires_on >= coalesce(c.start_date, current_date)) then return 'insurance_missing'; end if;
return null;
end $$;
revoke all on all functions in schema contract_center from public, anon, authenticated;

-- Minimal stand-in for Supabase Storage: storage.objects with wcia-staging's worker-docs rules (read 2026-11-25).
create schema if not exists storage;
grant usage on schema storage to anon, authenticated;
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text not null, name text not null, owner uuid default auth.uid(),
  created_at timestamptz not null default now(), unique (bucket_id, name));
create or replace function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:greatest(array_length(string_to_array(name, '/'), 1) - 1, 0)] $$;
grant execute on function storage.foldername(text) to anon, authenticated;
alter table storage.objects enable row level security;
grant select, insert, delete on storage.objects to authenticated;
create policy "worker docs own upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'worker-docs' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "worker docs own read" on storage.objects for select to authenticated
  using (bucket_id = 'worker-docs' and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin())));
create policy "worker docs own delete" on storage.objects for delete to authenticated
  using (bucket_id = 'worker-docs' and (storage.foldername(name))[1] = (select auth.uid())::text);
