-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- WE CLEAN IT ALL — Contracts & Cleaning Jobs marketplace
-- Staging only. NOT APPLIED to any project. Review + security retest before it is ever applied.
--
-- Builds on what wcia-staging already has (nothing is rebuilt):
--   contract_center.opportunities / opportunity_requirements / scope_items / opportunity_locations
--   contract_center.contracts / provider_assignments / events, contract_center._require_owner / _log / _alert_owner
--   contract_center.provider_contract_block_reason
--   public.workers (registration + owner approval), public.insurance_policies, public.provider_compliance,
--   public.provider_coverage, storage bucket worker-docs (per-user folders)
--
-- Access model (approved 2026-11-25):
--   Public      → sanitized summary only (public_* fields the owner writes on purpose)
--   Registered  → summary + the requirement lines the owner marks provider-visible; can prepare a draft application
--   Approved    → + approved-only / invited listings, scope lines marked provider-visible, city/ZIP/size (never the
--                 street address, site name or client), eligibility check, application submission
--   Selected    → owner turns the application into a *proposed* provider assignment on a signed contract.
--                 Nothing is awarded automatically; no payments.
--
-- Everything ships OFF. contract_center.marketplace_flags must be switched on by the owner, and the switch refuses
-- until a security retest has been recorded (admin_record_security_retest).
-- Re-runnable.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────── 1. Feature switches (default OFF) ─────────────────────────
create table if not exists contract_center.marketplace_flags (
  id int primary key default 1 check (id = 1),
  public_listings boolean not null default false,     -- public Contracts & Jobs board
  provider_listings boolean not null default false,   -- provider Opportunities tab + credential uploads
  applications boolean not null default false,        -- draft / submit / withdraw applications
  show_test_listings boolean not null default false,  -- staging only: let TEST — listings appear
  security_retest_passed_at timestamptz,
  security_retest_note text not null default '' check (char_length(security_retest_note) <= 1000),
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into contract_center.marketplace_flags (id) values (1) on conflict (id) do nothing;

-- ───────────────────────── 2. Listing fields on opportunities ─────────────────────────
alter table contract_center.opportunities drop constraint if exists opportunities_visibility_check;
alter table contract_center.opportunities add constraint opportunities_visibility_check
  check (visibility in ('internal', 'public_summary', 'approved_only', 'invite_only', 'marketplace'));
  -- 'marketplace' is kept only so existing Contract Center code that writes it keeps working; treated as approved_only.

alter table contract_center.opportunities
  add column if not exists listing_ref text,
  add column if not exists listing_status text not null default 'draft',
  add column if not exists public_title text,
  add column if not exists public_summary text not null default '',
  add column if not exists public_area text,
  add column if not exists public_facility_type text,
  add column if not exists public_size_band text,
  add column if not exists public_frequency text,
  add column if not exists public_schedule text,
  add column if not exists public_requirements text[] not null default '{}',
  add column if not exists public_start_month date,
  add column if not exists applications_due_at timestamptz,
  add column if not exists listed_at timestamptz,
  add column if not exists listed_by uuid;

update contract_center.opportunities
   set listing_ref = 'J-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
 where listing_ref is null;
alter table contract_center.opportunities
  alter column listing_ref set default ('J-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  alter column listing_ref set not null;
create unique index if not exists opportunities_listing_ref_key on contract_center.opportunities (listing_ref);

do $$ begin
  alter table contract_center.opportunities drop constraint if exists opportunities_listing_checks;
  alter table contract_center.opportunities add constraint opportunities_listing_checks check (
        listing_status in ('draft', 'open', 'filled', 'closed')
    and (public_title is null or char_length(public_title) between 3 and 120)
    and char_length(public_summary) <= 600
    and (public_area is null or char_length(public_area) between 2 and 80)
    and (public_facility_type is null or public_facility_type in
         ('office','medical','retail','warehouse','school','government','industrial','mixed','residential_common','other'))
    and (public_size_band is null or public_size_band in ('under_5k','5k_20k','20k_50k','50k_100k','over_100k'))
    and (public_frequency is null or public_frequency in
         ('daily','6x_week','weekdays','4x_week','3x_week','2x_week','weekly','biweekly','monthly','quarterly','one_time','on_call'))
    and (public_schedule is null or public_schedule in ('day','evening','overnight','weekend','flexible'))
    and public_requirements <@ array['general_liability','workers_comp','background_check','business_license','own_equipment',
         'own_transport','floor_care','robot_operation','bilingual','night_availability','experience_1y','experience_3y']::text[]
    and cardinality(public_requirements) <= 12);
end $$;

-- Which internal lines a provider may see. Default hidden: the owner opts each line in.
alter table contract_center.opportunity_requirements add column if not exists provider_visible boolean not null default false;
alter table contract_center.scope_items add column if not exists provider_visible boolean not null default false;

-- ───────────────────────── 3. Invitations + applications ─────────────────────────
create table if not exists contract_center.listing_invites (
  opportunity_id uuid not null references contract_center.opportunities(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  invited_at timestamptz not null default now(),
  invited_by uuid,
  primary key (opportunity_id, worker_id)
);

-- Provider → WCIA. Not the same thing as contract_center.proposals (WCIA → client).
create table if not exists contract_center.provider_applications (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references contract_center.opportunities(id) on delete cascade,
  worker_id uuid not null references public.workers(id) on delete cascade,
  status text not null default 'draft'
    check (status in ('draft','submitted','under_review','shortlisted','selected','declined','withdrawn')),
  availability text not null default '' check (char_length(availability) <= 500),
  crew_size int check (crew_size is null or crew_size between 1 and 500),
  proposed_rate numeric(10,2) check (proposed_rate is null or proposed_rate between 0 and 1000000),
  rate_basis text check (rate_basis is null or rate_basis in ('hourly','monthly','per_visit')),
  can_start_on date,
  robot_experience boolean not null default false,
  message text not null default '' check (char_length(message) <= 1500),
  submitted_at timestamptz,
  decided_at timestamptz,
  decided_by uuid,
  decision_note text not null default '' check (char_length(decision_note) <= 500),  -- internal, never shown to the provider
  assignment_id uuid references contract_center.provider_assignments(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (opportunity_id, worker_id)
);
create index if not exists provider_applications_worker_idx on contract_center.provider_applications (worker_id);

alter table contract_center.marketplace_flags enable row level security;
alter table contract_center.listing_invites enable row level security;
alter table contract_center.provider_applications enable row level security;
-- No policies: every read and write goes through the functions below.
revoke all on contract_center.marketplace_flags, contract_center.listing_invites, contract_center.provider_applications
  from public, anon, authenticated;

-- ───────────────────────── 4. Internal helpers ─────────────────────────
create or replace function contract_center._mp_flags() returns contract_center.marketplace_flags
language sql stable security definer set search_path = '' as $$
  select * from contract_center.marketplace_flags where id = 1;
$$;

-- The signed-in provider, or null (anonymous sessions never count).
create or replace function contract_center._mp_me() returns public.workers
language sql stable security definer set search_path = '' as $$
  select w.* from public.workers w
   where w.id = auth.uid() and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
$$;

create or replace function contract_center._mp_public_status(o contract_center.opportunities) returns text
language sql stable set search_path = '' as $$
  select case
    when o.listing_status = 'filled' then 'filled'
    when o.listing_status = 'open' and o.applications_due_at is not null and o.applications_due_at <= now() then 'closed'
    when o.listing_status = 'open' and o.applications_due_at is not null and o.applications_due_at <= now() + interval '7 days' then 'closing_soon'
    when o.listing_status = 'open' then 'open'
    else 'closed' end;
$$;

-- tier: 'public' (anyone), 'registered' (pending provider), 'approved'. Returns false when the listing must stay hidden.
create or replace function contract_center._mp_visible(o contract_center.opportunities, p_tier text, p_worker uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare f contract_center.marketplace_flags := contract_center._mp_flags();
begin
  if o.id is null or o.visibility = 'internal' then return false; end if;
  if contract_center._mp_public_status(o) not in ('open', 'closing_soon', 'filled') then return false; end if;
  if o.public_title is null or o.public_area is null or o.public_facility_type is null then return false; end if;
  if o.is_test then
    if not f.show_test_listings then return false; end if;
  elsif o.verification_status <> 'verified' then
    return false;  -- never publish an unverified opportunity
  end if;
  if o.visibility = 'public_summary' then return true; end if;
  if p_tier <> 'approved' then return false; end if;
  if o.visibility in ('approved_only', 'marketplace') then return true; end if;
  if o.visibility = 'invite_only' then
    return exists (select 1 from contract_center.listing_invites i where i.opportunity_id = o.id and i.worker_id = p_worker);
  end if;
  return false;
end $$;

create or replace function contract_center._mp_tier(w public.workers) returns text
language sql stable set search_path = '' as $$
  select case when w.id is null then 'public' when w.status = 'approved' then 'approved'
              when w.status = 'pending' then 'registered' else 'blocked' end;
$$;

-- Why this provider cannot submit to this listing right now (null = eligible).
create or replace function contract_center._mp_block_reason(p_worker uuid, p_opp uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers; o contract_center.opportunities; r text;
begin
  select * into w from public.workers where id = p_worker;
  select * into o from contract_center.opportunities where id = p_opp;
  if w.id is null or o.id is null then return 'not_found'; end if;
  if w.status <> 'approved' then return 'not_approved'; end if;
  if not contract_center._mp_visible(o, 'approved', w.id) then return 'not_available'; end if;
  if contract_center._mp_public_status(o) not in ('open', 'closing_soon') then return 'closed'; end if;
  if o.market_id is not null then
    if exists (select 1 from public.provider_coverage pc where pc.worker_id = w.id and pc.market_id = o.market_id and pc.status = 'suspended') then
      return 'suspended_in_market';
    end if;
    if not (exists (select 1 from public.provider_coverage pc where pc.worker_id = w.id and pc.market_id = o.market_id and pc.status = 'approved')
            or exists (select 1 from unnest(w.zips) z where public._market_of_zip(z) = o.market_id)) then
      return 'outside_service_area';
    end if;
  end if;
  foreach r in array o.public_requirements loop
    if r in ('general_liability', 'workers_comp') and not exists (
         select 1 from public.insurance_policies i where i.worker_id = w.id and i.kind = r
            and i.status = 'verified' and i.expires_on >= current_date) then
      return 'insurance_missing:' || r;
    end if;
    if r in ('background_check', 'business_license') and not exists (
         select 1 from public.provider_compliance pc where pc.worker_id = w.id and pc.requirement = r
            and pc.status = 'verified' and (pc.expires_on is null or pc.expires_on >= current_date)) then
      return 'compliance_missing:' || r;
    end if;
  end loop;
  return null;
end $$;

-- The provider-facing shape of one listing for a given tier. Only whitelisted fields ever leave this function.
create or replace function contract_center._mp_listing_json(o contract_center.opportunities, p_tier text, p_worker uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare j jsonb; a contract_center.provider_applications;
begin
  j := jsonb_build_object(
    'ref', o.listing_ref, 'title', o.public_title, 'summary', o.public_summary, 'area', o.public_area,
    'facility_type', o.public_facility_type, 'size_band', o.public_size_band, 'frequency', o.public_frequency,
    'schedule', o.public_schedule, 'requirements', to_jsonb(o.public_requirements), 'start_month', o.public_start_month,
    'status', contract_center._mp_public_status(o), 'applications_due_at', o.applications_due_at,
    'access', case when o.visibility = 'public_summary' then 'public' when o.visibility = 'invite_only' then 'invite' else 'approved' end,
    'tier', p_tier, 'is_test', o.is_test);
  if p_tier in ('registered', 'approved') then
    j := j || jsonb_build_object('requirement_details', coalesce((
      select jsonb_agg(jsonb_build_object('category', r.category, 'requirement', r.requirement, 'mandatory', r.mandatory) order by r.mandatory desc, r.category)
        from contract_center.opportunity_requirements r where r.opportunity_id = o.id and r.provider_visible), '[]'::jsonb));
    select * into a from contract_center.provider_applications where opportunity_id = o.id and worker_id = p_worker;
    if a.id is not null then
      j := j || jsonb_build_object('application', jsonb_build_object(
        'status', a.status, 'availability', a.availability, 'crew_size', a.crew_size, 'proposed_rate', a.proposed_rate,
        'rate_basis', a.rate_basis, 'can_start_on', a.can_start_on, 'robot_experience', a.robot_experience,
        'message', a.message, 'submitted_at', a.submitted_at, 'updated_at', a.updated_at));
    end if;
  end if;
  if p_tier = 'approved' then
    j := j || jsonb_build_object(
      'scope', coalesce((select jsonb_agg(jsonb_build_object('area', s.area_type, 'task', s.task, 'frequency', s.frequency,
                                                             'quantity', s.quantity, 'unit', s.unit) order by s.area_type, s.task)
                           from contract_center.scope_items s where s.opportunity_id = o.id and s.provider_visible), '[]'::jsonb),
      'sites', coalesce((select jsonb_agg(jsonb_build_object('city', l.city, 'zip', l.zip, 'building_type', l.building_type,
                                                             'sqft', l.sqft, 'floors', l.floors, 'restrooms', l.restrooms) order by l.is_primary desc)
                           from contract_center.opportunity_locations l where l.opportunity_id = o.id), '[]'::jsonb),
      'block_reason', contract_center._mp_block_reason(p_worker, o.id));
  end if;
  return j;
end $$;

-- ───────────────────────── 5. Public board (anon + signed in) ─────────────────────────
create or replace function public.contract_listings()
returns table (ref text, title text, summary text, area text, facility_type text, size_band text, frequency text,
               schedule text, requirements text[], start_month date, status text, applications_due_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (contract_center._mp_flags()).public_listings then return; end if;
  return query
    select o.listing_ref, o.public_title, o.public_summary, o.public_area, o.public_facility_type, o.public_size_band,
           o.public_frequency, o.public_schedule, o.public_requirements, o.public_start_month,
           contract_center._mp_public_status(o), o.applications_due_at
      from contract_center.opportunities o
     where o.visibility = 'public_summary' and contract_center._mp_visible(o, 'public', null)
     order by (contract_center._mp_public_status(o) = 'filled'), o.applications_due_at nulls last, o.listed_at desc
     limit 100;
end $$;

-- ───────────────────────── 6. Provider side ─────────────────────────
create or replace function public.provider_contract_listings() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); t text;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  if not (contract_center._mp_flags()).provider_listings then return '[]'::jsonb; end if;
  t := contract_center._mp_tier(w);
  if t = 'blocked' then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(contract_center._mp_listing_json(o, t, w.id)
                                    order by (contract_center._mp_public_status(o) = 'filled'), o.applications_due_at nulls last)
                     from contract_center.opportunities o where contract_center._mp_visible(o, t, w.id)), '[]'::jsonb);
end $$;

create or replace function public.provider_contract_listing(p_ref text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); t text; o contract_center.opportunities;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  if not (contract_center._mp_flags()).provider_listings then raise exception 'not_available'; end if;
  t := contract_center._mp_tier(w);
  select * into o from contract_center.opportunities where listing_ref = p_ref;
  if t = 'blocked' or not contract_center._mp_visible(o, t, w.id) then raise exception 'not_available'; end if;
  return contract_center._mp_listing_json(o, t, w.id);
end $$;

-- Registered (pending) and approved providers can prepare a draft. p jsonb keys: availability, crew_size, proposed_rate,
-- rate_basis, can_start_on, robot_experience, message.
create or replace function public.save_contract_application(p_ref text, p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); t text; o contract_center.opportunities; a contract_center.provider_applications;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  if not (contract_center._mp_flags()).applications then raise exception 'applications_disabled'; end if;
  t := contract_center._mp_tier(w);
  if t not in ('registered', 'approved') then raise exception 'not_allowed'; end if;
  select * into o from contract_center.opportunities where listing_ref = p_ref;
  if not contract_center._mp_visible(o, t, w.id) then raise exception 'not_available'; end if;
  if contract_center._mp_public_status(o) not in ('open', 'closing_soon') then raise exception 'closed'; end if;
  if jsonb_typeof(coalesce(p, '{}')) <> 'object' then raise exception 'bad_input'; end if;
  select * into a from contract_center.provider_applications where opportunity_id = o.id and worker_id = w.id for update;
  if a.id is not null and a.status not in ('draft', 'withdrawn') then raise exception 'already_submitted'; end if;
  if a.id is null and (select count(*) from contract_center.provider_applications x
                        where x.worker_id = w.id and x.status in ('draft','submitted','under_review','shortlisted')) >= 30 then
    raise exception 'too_many_open_applications';
  end if;
  insert into contract_center.provider_applications as pa
    (opportunity_id, worker_id, status, availability, crew_size, proposed_rate, rate_basis, can_start_on, robot_experience, message)
  values (o.id, w.id, 'draft', left(coalesce(p->>'availability', ''), 500), nullif(p->>'crew_size', '')::int,
          nullif(p->>'proposed_rate', '')::numeric, nullif(p->>'rate_basis', ''), nullif(p->>'can_start_on', '')::date,
          coalesce((p->>'robot_experience')::boolean, false), left(coalesce(p->>'message', ''), 1500))
  on conflict (opportunity_id, worker_id) do update set
    status = 'draft', availability = excluded.availability, crew_size = excluded.crew_size, proposed_rate = excluded.proposed_rate,
    rate_basis = excluded.rate_basis, can_start_on = excluded.can_start_on, robot_experience = excluded.robot_experience,
    message = excluded.message, submitted_at = null, updated_at = now();
  return 'draft';
exception when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or invalid_datetime_format then
  raise exception 'bad_input';
end $$;

-- Only approved, eligible providers can submit.
create or replace function public.submit_contract_application(p_ref text) returns text
language plpgsql security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); o contract_center.opportunities; a contract_center.provider_applications; why text;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  if not (contract_center._mp_flags()).applications then raise exception 'applications_disabled'; end if;
  select * into o from contract_center.opportunities where listing_ref = p_ref;
  if o.id is null then raise exception 'not_available'; end if;
  select * into a from contract_center.provider_applications where opportunity_id = o.id and worker_id = w.id for update;
  if a.id is null or a.status <> 'draft' then raise exception 'no_draft'; end if;
  why := contract_center._mp_block_reason(w.id, o.id);
  if why is not null then raise exception '%', why; end if;
  if char_length(btrim(a.availability)) < 3 then raise exception 'availability_required'; end if;
  update contract_center.provider_applications set status = 'submitted', submitted_at = now(), updated_at = now() where id = a.id;
  perform contract_center._log('provider', w.id::text, o.id, 'application.submitted', 'draft', 'submitted', 'system', null,
                               jsonb_build_object('application_id', a.id, 'ref', o.listing_ref));
  perform contract_center._alert_owner('contract_application_submitted', jsonb_build_object('ref', o.listing_ref, 'title', o.public_title));
  return 'submitted';
end $$;

create or replace function public.withdraw_contract_application(p_ref text) returns text
language plpgsql security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); o contract_center.opportunities; a contract_center.provider_applications;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  select * into o from contract_center.opportunities where listing_ref = p_ref;
  select * into a from contract_center.provider_applications where opportunity_id = o.id and worker_id = w.id for update;
  if a.id is null then raise exception 'not_found'; end if;
  if a.status not in ('draft', 'submitted', 'under_review', 'shortlisted') then raise exception 'cannot_withdraw'; end if;
  update contract_center.provider_applications set status = 'withdrawn', updated_at = now() where id = a.id;
  perform contract_center._log('provider', w.id::text, o.id, 'application.withdrawn', a.status, 'withdrawn', 'system', null,
                               jsonb_build_object('application_id', a.id));
  return 'withdrawn';
end $$;

-- The provider's own applications. Shows only public listing fields + status (never the internal decision note).
create or replace function public.my_contract_applications() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me();
begin
  if w.id is null then raise exception 'provider_only'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'ref', o.listing_ref, 'title', o.public_title, 'area', o.public_area, 'listing_status', contract_center._mp_public_status(o),
      'status', a.status, 'submitted_at', a.submitted_at, 'updated_at', a.updated_at, 'assigned', a.assignment_id is not null)
      order by a.updated_at desc)
    from contract_center.provider_applications a join contract_center.opportunities o on o.id = a.opportunity_id
   where a.worker_id = w.id), '[]'::jsonb);
end $$;

-- Credentials: reuse public.insurance_policies / provider_compliance and the worker-docs bucket (folder = own user id).
create or replace function public.my_provider_credentials() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me();
begin
  if w.id is null then raise exception 'provider_only'; end if;
  return jsonb_build_object(
    'insurance', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'kind', i.kind, 'carrier', i.carrier, 'coverage_usd', i.coverage_usd,
        'expires_on', i.expires_on, 'status', i.status, 'has_document', i.document_path <> '') order by i.created_at desc)
      from public.insurance_policies i where i.worker_id = w.id), '[]'::jsonb),
    'compliance', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'requirement', c.requirement, 'expires_on', c.expires_on,
        'status', c.status, 'has_document', c.document_path <> '') order by c.created_at desc)
      from public.provider_compliance c where c.worker_id = w.id), '[]'::jsonb));
end $$;

create or replace function contract_center._mp_check_doc_path(p_path text) returns void
language plpgsql stable set search_path = '' as $$
begin
  if p_path is null or p_path !~ ('^' || auth.uid()::text || '/[A-Za-z0-9._-]{1,120}$') then raise exception 'bad_document_path'; end if;
end $$;

create or replace function public.submit_provider_insurance(p_kind text, p_carrier text, p_policy_number text, p_coverage_usd numeric,
                                                            p_starts_on date, p_expires_on date, p_document_path text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); v bigint;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  if not (contract_center._mp_flags()).provider_listings then raise exception 'credentials_disabled'; end if;
  if w.status not in ('pending', 'approved') then raise exception 'not_allowed'; end if;
  if p_kind not in ('general_liability', 'workers_comp', 'bond', 'auto') then raise exception 'bad_kind'; end if;
  if p_expires_on is null or p_expires_on < current_date then raise exception 'expired'; end if;
  if p_coverage_usd is null or p_coverage_usd <= 0 or p_coverage_usd > 100000000 then raise exception 'bad_coverage'; end if;
  perform contract_center._mp_check_doc_path(p_document_path);
  if (select count(*) from public.insurance_policies where worker_id = w.id and status = 'submitted') >= 10 then raise exception 'too_many_pending'; end if;
  insert into public.insurance_policies (worker_id, kind, carrier, policy_number, coverage_usd, starts_on, expires_on, status, document_path)
  values (w.id, p_kind, left(coalesce(p_carrier, ''), 120), left(coalesce(p_policy_number, ''), 80), p_coverage_usd, p_starts_on,
          p_expires_on, 'submitted', p_document_path)
  returning id into v;
  perform contract_center._alert_owner('provider_credential_submitted', jsonb_build_object('kind', p_kind));
  return v;
end $$;

create or replace function public.submit_provider_compliance(p_requirement text, p_expires_on date, p_document_path text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); v bigint;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  if not (contract_center._mp_flags()).provider_listings then raise exception 'credentials_disabled'; end if;
  if w.status not in ('pending', 'approved') then raise exception 'not_allowed'; end if;
  if p_requirement not in ('background_check', 'business_license', 'w9', 'contractor_agreement', 'id_verification', 'other') then
    raise exception 'bad_requirement';
  end if;
  if p_expires_on is not null and p_expires_on < current_date then raise exception 'expired'; end if;
  perform contract_center._mp_check_doc_path(p_document_path);
  if (select count(*) from public.provider_compliance where worker_id = w.id and status = 'submitted') >= 10 then raise exception 'too_many_pending'; end if;
  insert into public.provider_compliance (worker_id, requirement, status, document_path, expires_on)
  values (w.id, p_requirement, 'submitted', p_document_path, p_expires_on) returning id into v;
  perform contract_center._alert_owner('provider_credential_submitted', jsonb_build_object('kind', p_requirement));
  return v;
end $$;

-- ───────────────────────── 7. Owner side ─────────────────────────
create or replace function public.admin_marketplace_flags() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  return to_jsonb(contract_center._mp_flags()) - 'id';
end $$;

create or replace function public.admin_record_security_retest(p_note text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  if char_length(btrim(coalesce(p_note, ''))) < 10 then raise exception 'note_required'; end if;
  update contract_center.marketplace_flags set security_retest_passed_at = now(), security_retest_note = left(p_note, 1000),
         updated_at = now(), updated_by = auth.uid() where id = 1;
  perform contract_center._log('settings', 'marketplace_flags', null, 'marketplace.security_retest', null, null, 'owner', null,
                               jsonb_build_object('note', left(p_note, 300)));
end $$;

create or replace function public.admin_set_marketplace_flags(p_public boolean, p_provider boolean, p_applications boolean, p_show_test boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f contract_center.marketplace_flags := contract_center._mp_flags();
begin
  perform contract_center._require_owner();
  if (coalesce(p_public, false) or coalesce(p_provider, false) or coalesce(p_applications, false)) and f.security_retest_passed_at is null then
    raise exception 'security_retest_required';
  end if;
  update contract_center.marketplace_flags set public_listings = coalesce(p_public, false), provider_listings = coalesce(p_provider, false),
         applications = coalesce(p_applications, false), show_test_listings = coalesce(p_show_test, false), updated_at = now(), updated_by = auth.uid()
   where id = 1;
  perform contract_center._log('settings', 'marketplace_flags', null, 'marketplace.flags', null, null, 'owner', null,
    jsonb_build_object('public', p_public, 'provider', p_provider, 'applications', p_applications, 'show_test', p_show_test));
  return public.admin_marketplace_flags();
end $$;

create or replace function public.admin_contract_listings() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'code', o.code, 'ref', o.listing_ref, 'title', o.title, 'status', o.status, 'verification_status', o.verification_status,
      'is_test', o.is_test, 'visibility', o.visibility, 'listing_status', o.listing_status, 'public_status', contract_center._mp_public_status(o),
      'public_title', o.public_title, 'public_summary', o.public_summary, 'public_area', o.public_area,
      'public_facility_type', o.public_facility_type, 'public_size_band', o.public_size_band, 'public_frequency', o.public_frequency,
      'public_schedule', o.public_schedule, 'public_requirements', to_jsonb(o.public_requirements), 'public_start_month', o.public_start_month,
      'applications_due_at', o.applications_due_at, 'listed_at', o.listed_at,
      'applications', (select jsonb_object_agg(s.status, s.n) from (select a.status, count(*) n from contract_center.provider_applications a
                         where a.opportunity_id = o.id and a.status <> 'draft' group by a.status) s))
      order by (o.listing_status = 'open') desc, o.updated_at desc)
    from contract_center.opportunities o where o.status not in ('rejected', 'disqualified', 'expired', 'lost')), '[]'::jsonb);
end $$;

-- p keys: visibility, listing_status, public_title, public_summary, public_area, public_facility_type, public_size_band,
-- public_frequency, public_schedule, public_requirements (array), public_start_month, applications_due_at
create or replace function public.admin_publish_listing(p_opp uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o contract_center.opportunities; b text; txt text; v_req text[];
begin
  perform contract_center._require_owner();
  select * into o from contract_center.opportunities where id = p_opp for update;
  if o.id is null then raise exception 'not_found'; end if;
  if jsonb_typeof(coalesce(p, '{}')) <> 'object' then raise exception 'bad_input'; end if;
  v_req := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'public_requirements', '[]'::jsonb)) x), '{}');
  update contract_center.opportunities set
    visibility = coalesce(nullif(p->>'visibility', ''), visibility),
    listing_status = coalesce(nullif(p->>'listing_status', ''), listing_status),
    public_title = nullif(btrim(p->>'public_title'), ''),
    public_summary = btrim(coalesce(p->>'public_summary', '')),
    public_area = nullif(btrim(p->>'public_area'), ''),
    public_facility_type = nullif(p->>'public_facility_type', ''),
    public_size_band = nullif(p->>'public_size_band', ''),
    public_frequency = nullif(p->>'public_frequency', ''),
    public_schedule = nullif(p->>'public_schedule', ''),
    public_requirements = v_req,
    public_start_month = nullif(p->>'public_start_month', '')::date,
    applications_due_at = nullif(p->>'applications_due_at', '')::timestamptz,
    listed_at = case when coalesce(nullif(p->>'listing_status', ''), listing_status) = 'open' and listed_at is null then now() else listed_at end,
    listed_by = auth.uid(), updated_at = now()
  where id = p_opp returning * into o;

  if o.listing_status = 'open' and o.visibility <> 'internal' then
    if o.public_title is null or o.public_area is null or o.public_facility_type is null then raise exception 'public_fields_required'; end if;
    if not o.is_test and o.verification_status <> 'verified' then raise exception 'opportunity_not_verified'; end if;
  end if;
  -- Leak guards on every public text field: no street numbers / ZIP-like digits, no client or incumbent name, no email or phone.
  txt := lower(coalesce(o.public_title, '') || ' ' || coalesce(o.public_summary, '') || ' ' || coalesce(o.public_area, ''));
  if txt ~ '[0-9]{3,}' then raise exception 'public_text_has_numbers'; end if;
  if txt ~ '@|https?://|www\.' then raise exception 'public_text_has_contact'; end if;
  select lower(name) into b from contract_center.buyers where id = o.buyer_id;
  if b is not null and char_length(b) >= 3 and position(b in txt) > 0 then raise exception 'public_text_names_client'; end if;
  if o.incumbent_name is not null and char_length(o.incumbent_name) >= 3 and position(lower(o.incumbent_name) in txt) > 0 then
    raise exception 'public_text_names_incumbent';
  end if;
  if exists (select 1 from contract_center.opportunity_locations l where l.opportunity_id = o.id and (
       (char_length(l.address) >= 5 and position(lower(l.address) in txt) > 0) or (char_length(l.name) >= 3 and position(lower(l.name) in txt) > 0))) then
    raise exception 'public_text_names_site';
  end if;
  perform contract_center._log('opportunity', o.id::text, o.id, 'listing.updated', null, o.listing_status, 'owner', null,
                               jsonb_build_object('visibility', o.visibility, 'ref', o.listing_ref));
  return jsonb_build_object('ref', o.listing_ref, 'visibility', o.visibility, 'listing_status', o.listing_status,
                            'public_status', contract_center._mp_public_status(o));
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  raise exception 'bad_input';
end $$;

create or replace function public.admin_set_listing_line_visibility(p_kind text, p_id uuid, p_visible boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  if p_kind = 'requirement' then
    update contract_center.opportunity_requirements set provider_visible = coalesce(p_visible, false) where id = p_id;
  elsif p_kind = 'scope' then
    update contract_center.scope_items set provider_visible = coalesce(p_visible, false) where id = p_id;
  else raise exception 'bad_kind'; end if;
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.admin_listing_lines(p_opp uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  return jsonb_build_object(
    'requirements', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'category', r.category, 'requirement', r.requirement,
        'mandatory', r.mandatory, 'provider_visible', r.provider_visible) order by r.category) from contract_center.opportunity_requirements r
        where r.opportunity_id = p_opp), '[]'::jsonb),
    'scope', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'area', s.area_type, 'task', s.task, 'frequency', s.frequency,
        'provider_visible', s.provider_visible) order by s.area_type, s.task) from contract_center.scope_items s
        where s.opportunity_id = p_opp), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('worker_id', i.worker_id, 'name', p.full_name) order by p.full_name)
        from contract_center.listing_invites i join public.profiles p on p.id = i.worker_id where i.opportunity_id = p_opp), '[]'::jsonb));
end $$;

create or replace function public.admin_invite_provider(p_opp uuid, p_worker uuid, p_invite boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  if coalesce(p_invite, true) then
    if not exists (select 1 from public.workers where id = p_worker and status = 'approved') then raise exception 'provider_not_approved'; end if;
    insert into contract_center.listing_invites (opportunity_id, worker_id, invited_by) values (p_opp, p_worker, auth.uid())
    on conflict do nothing;
  else
    delete from contract_center.listing_invites where opportunity_id = p_opp and worker_id = p_worker;
  end if;
end $$;

create or replace function public.admin_listing_applications(p_opp uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'status', a.status, 'worker_id', a.worker_id, 'name', p.full_name, 'kind', w.kind, 'company_name', w.company_name,
      'provider_status', w.status, 'rating_avg', w.rating_avg, 'rating_count', w.rating_count, 'jobs_done', w.jobs_done,
      'team_size', w.team_size, 'availability', a.availability, 'crew_size', a.crew_size, 'proposed_rate', a.proposed_rate,
      'rate_basis', a.rate_basis, 'can_start_on', a.can_start_on, 'robot_experience', a.robot_experience, 'message', a.message,
      'submitted_at', a.submitted_at, 'decided_at', a.decided_at, 'decision_note', a.decision_note, 'assignment_id', a.assignment_id,
      'contract_id', (select c.id from contract_center.contracts c where c.opportunity_id = a.opportunity_id),
      'block_reason', contract_center._mp_block_reason(a.worker_id, a.opportunity_id),
      'verified_insurance', (select coalesce(jsonb_agg(distinct i.kind), '[]') from public.insurance_policies i
                              where i.worker_id = w.id and i.status = 'verified' and i.expires_on >= current_date),
      'verified_compliance', (select coalesce(jsonb_agg(distinct c.requirement), '[]') from public.provider_compliance c
                               where c.worker_id = w.id and c.status = 'verified' and (c.expires_on is null or c.expires_on >= current_date)))
      order by case a.status when 'shortlisted' then 0 when 'under_review' then 1 when 'submitted' then 2 when 'selected' then 3 else 4 end,
               a.submitted_at)
    from contract_center.provider_applications a join public.workers w on w.id = a.worker_id join public.profiles p on p.id = w.id
   where a.opportunity_id = p_opp and a.status <> 'draft'), '[]'::jsonb);
end $$;

-- Human decision on an application. Selecting does NOT award anything: it marks who WCIA intends to use.
create or replace function public.admin_decide_application(p_app uuid, p_status text, p_note text) returns text
language plpgsql security definer set search_path = '' as $$
declare a contract_center.provider_applications; o contract_center.opportunities; why text;
begin
  perform contract_center._require_owner();
  select * into a from contract_center.provider_applications where id = p_app for update;
  if a.id is null then raise exception 'not_found'; end if;
  if not ((a.status = 'submitted' and p_status in ('under_review', 'shortlisted', 'declined'))
       or (a.status = 'under_review' and p_status in ('shortlisted', 'selected', 'declined'))
       or (a.status = 'shortlisted' and p_status in ('under_review', 'selected', 'declined'))
       or (a.status = 'selected' and p_status = 'declined' and a.assignment_id is null)) then
    raise exception 'bad_transition';
  end if;
  if p_status = 'selected' then
    why := contract_center._mp_block_reason(a.worker_id, a.opportunity_id);
    if why is not null and why <> 'closed' then raise exception 'provider_not_eligible:%', why; end if;
  end if;
  update contract_center.provider_applications set status = p_status, decided_at = now(), decided_by = auth.uid(),
         decision_note = left(coalesce(p_note, ''), 500), updated_at = now() where id = a.id;
  select * into o from contract_center.opportunities where id = a.opportunity_id;
  perform contract_center._log('provider', a.worker_id::text, a.opportunity_id, 'application.' || p_status, a.status, p_status, 'owner', null,
                               jsonb_build_object('application_id', a.id));
  if p_status in ('shortlisted', 'selected', 'declined') then
    perform public._notify(a.worker_id, 'contract_application_' || p_status, jsonb_build_object('ref', o.listing_ref, 'title', o.public_title));
  end if;
  return p_status;
end $$;

-- Selected application → PROPOSED provider assignment on an existing contract for the same opportunity.
-- Uses the existing contract eligibility check. Approval/activation stays in the existing Contract Center workflow.
create or replace function public.admin_application_to_assignment(p_app uuid, p_contract uuid, p_role text, p_pay_basis text,
                                                                  p_pay_rate numeric, p_start_date date) returns uuid
language plpgsql security definer set search_path = '' as $$
declare a contract_center.provider_applications; c contract_center.contracts; why text; v uuid;
begin
  perform contract_center._require_owner();
  select * into a from contract_center.provider_applications where id = p_app for update;
  if a.id is null then raise exception 'not_found'; end if;
  if a.status <> 'selected' then raise exception 'not_selected'; end if;
  if a.assignment_id is not null then raise exception 'already_assigned'; end if;
  select * into c from contract_center.contracts where id = p_contract;
  if c.id is null then raise exception 'contract_not_found'; end if;
  if c.opportunity_id <> a.opportunity_id then raise exception 'contract_mismatch'; end if;
  why := contract_center.provider_contract_block_reason(a.worker_id, c.id);
  if why is not null then raise exception 'provider_not_eligible:%', why; end if;
  insert into contract_center.provider_assignments (contract_id, worker_id, role, status, pay_basis, pay_rate, start_date, eligibility)
  values (c.id, a.worker_id, coalesce(p_role, 'subcontractor'), 'proposed', p_pay_basis, p_pay_rate, p_start_date,
          jsonb_build_object('source', 'contract_application', 'application_id', a.id, 'checked_at', now()))
  returning id into v;
  update contract_center.provider_applications set assignment_id = v, updated_at = now() where id = a.id;
  perform contract_center._log('contract', c.id::text, c.opportunity_id, 'assignment.proposed', null, 'proposed', 'owner', null,
                               jsonb_build_object('application_id', a.id, 'assignment_id', v));
  return v;
end $$;

create or replace function public.admin_verify_provider_credential(p_kind text, p_id bigint, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  if p_status not in ('verified', 'rejected') then raise exception 'bad_status'; end if;
  if p_kind = 'insurance' then
    update public.insurance_policies set status = p_status, verified_by = auth.uid(), verified_at = now() where id = p_id;
  elsif p_kind = 'compliance' then
    update public.provider_compliance set status = p_status, verified_by = auth.uid(), verified_at = now() where id = p_id;
  else raise exception 'bad_kind'; end if;
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.admin_pending_provider_credentials() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  return jsonb_build_object(
    'insurance', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'worker_id', i.worker_id, 'name', p.full_name, 'kind', i.kind,
        'carrier', i.carrier, 'policy_number', i.policy_number, 'coverage_usd', i.coverage_usd, 'expires_on', i.expires_on,
        'document_path', i.document_path, 'created_at', i.created_at) order by i.created_at)
      from public.insurance_policies i join public.profiles p on p.id = i.worker_id where i.status = 'submitted'), '[]'::jsonb),
    'compliance', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'worker_id', c.worker_id, 'name', p.full_name,
        'requirement', c.requirement, 'expires_on', c.expires_on, 'document_path', c.document_path, 'created_at', c.created_at) order by c.created_at)
      from public.provider_compliance c join public.profiles p on p.id = c.worker_id where c.status = 'submitted'), '[]'::jsonb));
end $$;

-- ───────────────────────── 8. Grants ─────────────────────────
revoke all on function contract_center._mp_flags(), contract_center._mp_me(), contract_center._mp_public_status(contract_center.opportunities),
  contract_center._mp_visible(contract_center.opportunities, text, uuid), contract_center._mp_tier(public.workers),
  contract_center._mp_block_reason(uuid, uuid), contract_center._mp_listing_json(contract_center.opportunities, text, uuid),
  contract_center._mp_check_doc_path(text)
  from public, anon, authenticated;

revoke all on function public.contract_listings(), public.provider_contract_listings(), public.provider_contract_listing(text),
  public.save_contract_application(text, jsonb), public.submit_contract_application(text), public.withdraw_contract_application(text),
  public.my_contract_applications(), public.my_provider_credentials(),
  public.submit_provider_insurance(text, text, text, numeric, date, date, text), public.submit_provider_compliance(text, date, text),
  public.admin_marketplace_flags(), public.admin_record_security_retest(text), public.admin_set_marketplace_flags(boolean, boolean, boolean, boolean),
  public.admin_contract_listings(), public.admin_publish_listing(uuid, jsonb), public.admin_set_listing_line_visibility(text, uuid, boolean),
  public.admin_listing_lines(uuid), public.admin_invite_provider(uuid, uuid, boolean), public.admin_listing_applications(uuid),
  public.admin_decide_application(uuid, text, text), public.admin_application_to_assignment(uuid, uuid, text, text, numeric, date),
  public.admin_verify_provider_credential(text, bigint, text), public.admin_pending_provider_credentials()
  from public, anon, authenticated;

grant execute on function public.contract_listings() to anon, authenticated;
grant execute on function public.provider_contract_listings(), public.provider_contract_listing(text),
  public.save_contract_application(text, jsonb), public.submit_contract_application(text), public.withdraw_contract_application(text),
  public.my_contract_applications(), public.my_provider_credentials(),
  public.submit_provider_insurance(text, text, text, numeric, date, date, text), public.submit_provider_compliance(text, date, text),
  public.admin_marketplace_flags(), public.admin_record_security_retest(text), public.admin_set_marketplace_flags(boolean, boolean, boolean, boolean),
  public.admin_contract_listings(), public.admin_publish_listing(uuid, jsonb), public.admin_set_listing_line_visibility(text, uuid, boolean),
  public.admin_listing_lines(uuid), public.admin_invite_provider(uuid, uuid, boolean), public.admin_listing_applications(uuid),
  public.admin_decide_application(uuid, text, text), public.admin_application_to_assignment(uuid, uuid, text, text, numeric, date),
  public.admin_verify_provider_credential(text, bigint, text), public.admin_pending_provider_credentials()
  to authenticated;

commit;
