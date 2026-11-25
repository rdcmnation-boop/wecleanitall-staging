-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- WE CLEAN IT ALL — Contracts & Cleaning Jobs: credential-upload guard (run after contract_marketplace.sql)
-- Owner decision 2026-11-25 (staging finding): credential uploads only for APPROVED providers while the owner's
-- "provider_listings" switch is ON, enforced by the database and storage, never only by the screen.
--
--  1. Storage: a RESTRICTIVE insert rule on storage.objects. Files under worker-docs/<uid>/credentials/ are refused
--     before any object is created unless public.provider_can_upload_credentials() is true for the uploader.
--     Other worker-docs uploads (profile documents for approval) are unchanged.
--  2. provider_credential_precheck(): validates the switch, approval and every field BEFORE the app uploads anything.
--  3. submit_provider_insurance / submit_provider_compliance: same checks again, path must be the caller's own
--     <uid>/credentials/<file>, and the stored file must actually exist. The app deletes the file if this fails.
--  4. admin_orphan_credential_files(): owner backstop listing credential files with no record (older than 1 hour).
-- Existing credential rows and their documents are not touched. Re-runnable.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

begin;

-- Why this user may not upload credentials right now (null = may upload).
create or replace function contract_center._mp_upload_block_reason(p_uid uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers;
begin
  if p_uid is null then return 'provider_only'; end if;
  select * into w from public.workers where id = p_uid;
  if w.id is null then return 'provider_only'; end if;
  if not (contract_center._mp_flags()).provider_listings then return 'credentials_disabled'; end if;
  if w.status <> 'approved' then return 'not_approved'; end if;
  return null;
end $$;

-- Used by the storage rule and by the app. Anonymous sessions never qualify.
create or replace function public.provider_can_upload_credentials() returns boolean
language sql stable security definer set search_path = '' as $$
  select not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
     and contract_center._mp_upload_block_reason(auth.uid()) is null;
$$;

-- What the signed-in provider's screens may offer right now (lets the app hide forms that would be refused).
create or replace function public.provider_marketplace_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); f contract_center.marketplace_flags := contract_center._mp_flags(); r text;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  r := contract_center._mp_upload_block_reason(w.id);
  return jsonb_build_object('listings', f.provider_listings, 'applications', f.applications,
                            'uploads', r is null, 'upload_block_reason', r);
end $$;

-- File must be the caller's own credentials folder AND exist in storage (no record without a file).
create or replace function contract_center._mp_check_doc_path(p_path text) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_path is null or p_path !~ ('^' || auth.uid()::text || '/credentials/[A-Za-z0-9._-]{1,120}$') then
    raise exception 'bad_document_path';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'worker-docs' and o.name = p_path) then
    raise exception 'document_missing';
  end if;
end $$;

create or replace function contract_center._mp_validate_credential(p_type text, p_kind text, p_coverage_usd numeric, p_expires_on date) returns void
language plpgsql stable set search_path = '' as $$
begin
  if p_type = 'insurance' then
    if p_kind is null or p_kind not in ('general_liability', 'workers_comp', 'bond', 'auto') then raise exception 'bad_kind'; end if;
    if p_expires_on is null or p_expires_on < current_date then raise exception 'expired'; end if;
    if p_coverage_usd is null or p_coverage_usd <= 0 or p_coverage_usd > 100000000 then raise exception 'bad_coverage'; end if;
  elsif p_type = 'compliance' then
    if p_kind is null or p_kind not in ('background_check', 'business_license', 'w9', 'contractor_agreement', 'id_verification', 'other') then
      raise exception 'bad_requirement';
    end if;
    if p_expires_on is not null and p_expires_on < current_date then raise exception 'expired'; end if;
  else
    raise exception 'bad_kind';
  end if;
end $$;

-- Step 1 of an upload: everything is checked before the app sends any file. Returns the folder to upload into.
create or replace function public.provider_credential_precheck(p_type text, p_kind text, p_coverage_usd numeric, p_expires_on date) returns text
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); r text;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  r := contract_center._mp_upload_block_reason(w.id);
  if r is not null then raise exception '%', r; end if;
  perform contract_center._mp_validate_credential(p_type, p_kind, p_coverage_usd, p_expires_on);
  if p_type = 'insurance' and (select count(*) from public.insurance_policies where worker_id = w.id and status = 'submitted') >= 10 then
    raise exception 'too_many_pending';
  end if;
  if p_type = 'compliance' and (select count(*) from public.provider_compliance where worker_id = w.id and status = 'submitted') >= 10 then
    raise exception 'too_many_pending';
  end if;
  return w.id::text || '/credentials/';
end $$;

create or replace function public.submit_provider_insurance(p_kind text, p_carrier text, p_policy_number text, p_coverage_usd numeric,
                                                            p_starts_on date, p_expires_on date, p_document_path text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); v bigint; r text;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  r := contract_center._mp_upload_block_reason(w.id);
  if r is not null then raise exception '%', r; end if;
  perform contract_center._mp_validate_credential('insurance', p_kind, p_coverage_usd, p_expires_on);
  if (select count(*) from public.insurance_policies where worker_id = w.id and status = 'submitted') >= 10 then raise exception 'too_many_pending'; end if;
  perform contract_center._mp_check_doc_path(p_document_path);
  insert into public.insurance_policies (worker_id, kind, carrier, policy_number, coverage_usd, starts_on, expires_on, status, document_path)
  values (w.id, p_kind, left(coalesce(p_carrier, ''), 120), left(coalesce(p_policy_number, ''), 80), p_coverage_usd, p_starts_on,
          p_expires_on, 'submitted', p_document_path)
  returning id into v;
  perform contract_center._alert_owner('provider_credential_submitted', jsonb_build_object('kind', p_kind));
  return v;
end $$;

create or replace function public.submit_provider_compliance(p_requirement text, p_expires_on date, p_document_path text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare w public.workers := contract_center._mp_me(); v bigint; r text;
begin
  if w.id is null then raise exception 'provider_only'; end if;
  r := contract_center._mp_upload_block_reason(w.id);
  if r is not null then raise exception '%', r; end if;
  perform contract_center._mp_validate_credential('compliance', p_requirement, null, p_expires_on);
  if (select count(*) from public.provider_compliance where worker_id = w.id and status = 'submitted') >= 10 then raise exception 'too_many_pending'; end if;
  perform contract_center._mp_check_doc_path(p_document_path);
  insert into public.provider_compliance (worker_id, requirement, status, document_path, expires_on)
  values (w.id, p_requirement, 'submitted', p_document_path, p_expires_on) returning id into v;
  perform contract_center._alert_owner('provider_credential_submitted', jsonb_build_object('kind', p_requirement));
  return v;
end $$;

-- Owner backstop: credential files with no matching record, older than an hour (e.g. a browser closed mid-upload).
create or replace function public.admin_orphan_credential_files() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform contract_center._require_owner();
  return coalesce((select jsonb_agg(jsonb_build_object('path', o.name, 'created_at', o.created_at) order by o.created_at)
    from storage.objects o
   where o.bucket_id = 'worker-docs' and (storage.foldername(o.name))[2] = 'credentials'
     and o.created_at < now() - interval '1 hour'
     and not exists (select 1 from public.insurance_policies i where i.document_path = o.name)
     and not exists (select 1 from public.provider_compliance c where c.document_path = o.name)), '[]'::jsonb);
end $$;

-- Storage rule: refuse credential-folder uploads before the object exists. RESTRICTIVE = applies on top of
-- the existing "worker docs own upload" rule (own folder), so both must pass.
drop policy if exists "worker docs credentials gate" on storage.objects;
create policy "worker docs credentials gate" on storage.objects as restrictive for insert to authenticated
  with check (bucket_id <> 'worker-docs'
              or coalesce((storage.foldername(name))[2], '') <> 'credentials'
              or (select public.provider_can_upload_credentials()));

revoke all on function contract_center._mp_upload_block_reason(uuid), contract_center._mp_check_doc_path(text),
  contract_center._mp_validate_credential(text, text, numeric, date) from public, anon, authenticated;
revoke all on function public.provider_can_upload_credentials(), public.provider_marketplace_status(),
  public.provider_credential_precheck(text, text, numeric, date), public.admin_orphan_credential_files() from public, anon, authenticated;
grant execute on function public.provider_can_upload_credentials(), public.provider_marketplace_status(),
  public.provider_credential_precheck(text, text, numeric, date), public.admin_orphan_credential_files() to authenticated;

commit;
