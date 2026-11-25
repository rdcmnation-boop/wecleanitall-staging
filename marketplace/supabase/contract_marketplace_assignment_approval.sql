-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- WE CLEAN IT ALL — Contracts & Cleaning Jobs: one approval path for assignments (run after the upload guard)
-- Owner decision 2026-11-25 (code review, section 3): a selected application becomes an assignment ONLY through the
-- existing Contract Center function public.ctr_propose_assignment, which
--   · requires the owner (2-step), · requires the contract to be open (onboarding / active / renewal_pending),
--   · re-checks contract-level eligibility (approval, service area, insurance valid on the start date, compliance),
--   · creates the assignment as 'proposed' and files a 'contract_center.assign_provider' approval request
--     that appears in the owner's normal approvals queue. Only public.ctr_decide can approve or reject it.
-- This file also re-checks the listing's required credentials and blocks duplicate assignments.
-- Nothing here activates a contract, creates a contract, or touches payments. Re-runnable.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

begin;

-- Credential requirements of a listing that this provider does not meet with VERIFIED, UNEXPIRED documents (null = all met).
create or replace function contract_center._mp_credential_gap(p_worker uuid, p_opp uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare reqs text[]; r text;
begin
  select public_requirements into reqs from contract_center.opportunities where id = p_opp;
  foreach r in array coalesce(reqs, '{}') loop
    if r in ('general_liability', 'workers_comp') and not exists (
         select 1 from public.insurance_policies i where i.worker_id = p_worker and i.kind = r
            and i.status = 'verified' and i.expires_on >= current_date) then
      return 'insurance_missing:' || r;
    end if;
    if r in ('background_check', 'business_license') and not exists (
         select 1 from public.provider_compliance pc where pc.worker_id = p_worker and pc.requirement = r
            and pc.status = 'verified' and (pc.expires_on is null or pc.expires_on >= current_date)) then
      return 'compliance_missing:' || r;
    end if;
  end loop;
  return null;
end $$;

-- Same rules as before; the credential part now lives in _mp_credential_gap so both paths share it.
create or replace function contract_center._mp_block_reason(p_worker uuid, p_opp uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare w public.workers; o contract_center.opportunities;
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
  return contract_center._mp_credential_gap(w.id, o.id);
end $$;

-- Selected application → proposed assignment + approval request, through the existing Contract Center path only.
create or replace function public.admin_application_to_assignment(p_app uuid, p_contract uuid, p_role text, p_pay_basis text,
                                                                  p_pay_rate numeric, p_start_date date) returns uuid
language plpgsql security definer set search_path = '' as $$
declare a contract_center.provider_applications; c contract_center.contracts; why text; v uuid;
begin
  perform contract_center._require_owner();
  -- row lock: a repeated or double-clicked request waits here and then sees the first one's link
  select * into a from contract_center.provider_applications where id = p_app for update;
  if a.id is null then raise exception 'not_found'; end if;
  if a.status <> 'selected' then raise exception 'not_selected'; end if;
  -- an earlier proposal that the owner REJECTED may be re-proposed; any other linked assignment blocks a duplicate
  if a.assignment_id is not null and exists (select 1 from contract_center.provider_assignments pa
                                              where pa.id = a.assignment_id and pa.status <> 'rejected') then
    raise exception 'already_assigned';
  end if;
  select * into c from contract_center.contracts where id = p_contract;
  if c.id is null then raise exception 'contract_not_found'; end if;
  if c.opportunity_id <> a.opportunity_id then raise exception 'contract_mismatch'; end if;
  if exists (select 1 from contract_center.provider_assignments pa where pa.contract_id = c.id and pa.worker_id = a.worker_id
              and pa.status in ('proposed', 'approved', 'active')) then
    raise exception 'already_assigned';
  end if;
  -- the listing's required credentials, verified and unexpired, re-checked at this moment
  why := contract_center._mp_credential_gap(a.worker_id, a.opportunity_id);
  if why is not null then raise exception 'provider_not_eligible:%', why; end if;
  -- the existing path: owner + 2-step, contract open, contract-level eligibility, 'proposed', approval request filed
  v := public.ctr_propose_assignment(c.id, jsonb_build_object(
         'worker_id', a.worker_id, 'role', coalesce(p_role, 'subcontractor'), 'pay_basis', p_pay_basis,
         'pay_rate', p_pay_rate, 'start_date', p_start_date));
  update contract_center.provider_assignments
     set eligibility = eligibility || jsonb_build_object('source', 'contract_application', 'application_id', a.id)
   where id = v;
  update contract_center.provider_applications set assignment_id = v, updated_at = now() where id = a.id;
  perform contract_center._log('provider', a.worker_id::text, a.opportunity_id, 'application.assignment_proposed', 'selected', 'selected', 'owner', null,
                               jsonb_build_object('application_id', a.id, 'assignment_id', v, 'contract_id', c.id));
  return v;
end $$;

revoke all on function contract_center._mp_credential_gap(uuid, uuid) from public, anon, authenticated;

commit;
