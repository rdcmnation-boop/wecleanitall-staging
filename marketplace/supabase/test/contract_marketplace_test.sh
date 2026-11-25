#!/usr/bin/env bash
# Security retest for contract_marketplace.sql on a throwaway local Postgres (never a Supabase project).
# Usage: PGHOST=... PGPORT=... ./contract_marketplace_test.sh
set -u
DB=wcia_cm_test
HERE="$(cd "$(dirname "$0")" && pwd)"
psql -U postgres -qtAc "drop database if exists $DB" >/dev/null
psql -U postgres -qtAc "create database $DB" >/dev/null
load() { psql -U postgres -d $DB -q -v ON_ERROR_STOP=1 -f "$1" >/dev/null 2>&1 || { echo "LOAD FAILED: $1"; exit 1; }; }
load "$HERE/supabase_stub.sql"; load "$HERE/../schema.sql"; load "$HERE/contract_center_fixture.sql"
load "$HERE/../contract_marketplace.sql"; load "$HERE/../contract_marketplace.sql"   # must be re-runnable
load "$HERE/../contract_marketplace_upload_guard.sql"; load "$HERE/../contract_marketplace_upload_guard.sql"
load "$HERE/../contract_marketplace_assignment_approval.sql"; load "$HERE/../contract_marketplace_assignment_approval.sql"

pass=0; fail=0
sq() { psql -U postgres -d $DB -qtA -c "$1" 2>&1; }
as() {
  local who="$1"; shift
  if [ "$who" = anon ]; then
    psql -U postgres -d $DB -qtA -c "begin; set local role anon; $1; commit;" 2>&1
  else
    local aal="${AAL:-aal2}"
    psql -U postgres -d $DB -qtA -c "begin; set local role authenticated; set local request.jwt.claim.sub = '$who'; set local request.jwt.claims = '{\"sub\":\"$who\",\"aal\":\"$aal\"}'; $1; commit;" 2>&1
  fi
}
check() { if [[ "$2" =~ $3 ]]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; echo "       got: $(echo "$2" | head -3 | tr '\n' ' ')"; echo "       want: $3"; fi; }
nocheck() { if [[ "$2" =~ $3 ]]; then fail=$((fail+1)); echo "  FAIL $1 (leaked: $3)"; else pass=$((pass+1)); echo "  ok   $1"; fi; }
mk() { sq "insert into auth.users(id,email,raw_user_meta_data) values ('$1','$2','$3')" >/dev/null; }

A=00000000-0000-0000-0000-0000000000a1; C1=00000000-0000-0000-0000-0000000000c1
W1=00000000-0000-0000-0000-0000000000b1; W2=00000000-0000-0000-0000-0000000000b2
W3=00000000-0000-0000-0000-0000000000b3; W4=00000000-0000-0000-0000-0000000000b4
mk $A owner@x.com '{"role":"customer","full_name":"Owner"}'
mk $C1 c1@x.com '{"role":"customer","full_name":"Ana Gomez"}'
mk $W1 w1@x.com '{"role":"worker","full_name":"Maria Perez","kind":"individual"}'
mk $W2 w2@x.com '{"role":"worker","full_name":"Luis Diaz","kind":"company","company_name":"Brillo LLC"}'
mk $W3 w3@x.com '{"role":"worker","full_name":"No Insurance","kind":"individual"}'
mk $W4 w4@x.com '{"role":"worker","full_name":"Suspended Sam","kind":"individual"}'
sq "insert into public.admins(user_id) values ('$A')" >/dev/null
sq "insert into public.workers(id) values ('$W1'),('$W2'),('$W3'),('$W4') on conflict do nothing" >/dev/null
sq "update public.workers set status='approved', zips='{33351}' where id in ('$W1','$W3');
    update public.workers set status='pending', zips='{33351}' where id='$W2';
    update public.workers set status='suspended', zips='{33351}' where id='$W4';
    insert into public.markets(id,name) values ('fl-broward','Broward');
    insert into public.insurance_policies(worker_id,kind,coverage_usd,expires_on,status) values ('$W1','general_liability',1000000,current_date+200,'verified');" >/dev/null

# Real-looking private data that must never leak.
sq "insert into contract_center.buyers(id,name) values ('11111111-0000-0000-0000-000000000001','Sawgrass Logistics Park LLC');
insert into contract_center.opportunities(id,title,buyer_id,market_id,verification_status,incumbent_name,estimated_monthly_value) values
 ('22222222-0000-0000-0000-000000000001','Sawgrass Logistics Park warehouse floors','11111111-0000-0000-0000-000000000001','fl-broward','verified','Old Janitorial Inc',9876),
 ('22222222-0000-0000-0000-000000000002','Approved-only office job',null,'fl-broward','verified',null,null),
 ('22222222-0000-0000-0000-000000000003','Invite-only showroom',null,'fl-broward','verified',null,null),
 ('22222222-0000-0000-0000-000000000004','Unverified lead',null,'fl-broward','unverified',null,null),
 ('22222222-0000-0000-0000-000000000005','Internal only',null,'fl-broward','verified',null,null);
insert into contract_center.opportunities(id,title,is_test,verification_status) values ('22222222-0000-0000-0000-000000000006','TEST — demo listing',true,'unverified');
insert into contract_center.opportunity_locations(opportunity_id,name,address,city,zip,building_type,sqft,is_primary) values
 ('22222222-0000-0000-0000-000000000001','Sawgrass Logistics Park','1234 NW 136th Ave','Sunrise','33351','warehouse',60000,true);
insert into contract_center.opportunity_requirements(opportunity_id,category,requirement,provider_visible) values
 ('22222222-0000-0000-0000-000000000001','insurance','General liability insurance, 1M per occurrence',true),
 ('22222222-0000-0000-0000-000000000001','other','Badge access via dock manager HIDDENREQ',false);
insert into contract_center.scope_items(opportunity_id,task,frequency,quantity,unit,provider_visible) values
 ('22222222-0000-0000-0000-000000000001','Autoscrub warehouse floor','weekdays',60000,'sqft',true),
 ('22222222-0000-0000-0000-000000000001','Alarm code handling HIDDENSCOPE','weekdays',1,'each',false);
insert into contract_center.contracts(id,opportunity_id,title,monthly_value) values
 ('33333333-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000001','Warehouse floors',5000),
 ('33333333-0000-0000-0000-000000000002','22222222-0000-0000-0000-000000000002','Office',2000);" >/dev/null
O1=22222222-0000-0000-0000-000000000001; O2=22222222-0000-0000-0000-000000000002; O3=22222222-0000-0000-0000-000000000003
O4=22222222-0000-0000-0000-000000000004; O5=22222222-0000-0000-0000-000000000005; O6=22222222-0000-0000-0000-000000000006
ref() { sq "select listing_ref from contract_center.opportunities where id='$1'"; }
R1=$(ref $O1); R2=$(ref $O2); R3=$(ref $O3); R5=$(ref $O5); R6=$(ref $O6)
PUB='"listing_status":"open","public_area":"Sunrise, FL","public_facility_type":"warehouse","public_size_band":"50k_100k","public_frequency":"weekdays","public_schedule":"overnight"'

echo "── 1. Owner-only controls"
check "provider cannot publish" "$(as $W1 "select public.admin_publish_listing('$O1','{}')")" "admin_only"
check "anon cannot publish (no grant)" "$(as anon "select public.admin_publish_listing('$O1','{}')")" "permission denied"
check "owner without 2-step cannot publish" "$(AAL=aal1 as $A "select public.admin_publish_listing('$O1','{}')")" "admin_only"
check "provider cannot read flags" "$(as $W1 "select public.admin_marketplace_flags()")" "admin_only"
check "provider cannot record retest" "$(as $W1 "select public.admin_record_security_retest('looks fine to me')")" "admin_only"
check "provider cannot list applications" "$(as $W1 "select public.admin_listing_applications('$O1')")" "admin_only"
check "provider cannot verify own insurance" "$(as $W3 "select public.admin_verify_provider_credential('insurance',1,'verified')")" "admin_only"

echo "── 2. Publishing leak guards"
check "title naming the client is refused" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Sawgrass Logistics Park LLC floors\"}')")" "public_text_names_client"
check "street number is refused" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Warehouse at 1234 NW\"}')")" "public_text_has_numbers"
check "site name is refused" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Sawgrass Logistics Park floors\"}')")" "public_text_names_(client|site)"
check "incumbent name is refused" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Replace Old Janitorial Inc\"}')")" "public_text_names_incumbent"
check "email in summary is refused" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Warehouse floors\",\"public_summary\":\"write to boss@site.com\"}')")" "public_text_has_contact"
check "unknown requirement label is refused" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Warehouse floors\",\"public_requirements\":[\"client is Sawgrass\"]}')")" "opportunities_listing_checks"
check "open listing needs public fields" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",\"listing_status\":\"open\"}')")" "public_fields_required"
check "unverified opportunity cannot open" "$(as $A "select public.admin_publish_listing('$O4','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Lead\"}')")" "opportunity_not_verified"
check "failed publish changed nothing" "$(sq "select listing_status||'/'||visibility from contract_center.opportunities where id='$O4'")" "^draft/internal$"
check "valid public listing" "$(as $A "select public.admin_publish_listing('$O1','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"Overnight warehouse floor care\",\"public_summary\":\"Large open warehouse floor, autoscrubber friendly.\",\"public_requirements\":[\"general_liability\",\"night_availability\"]}')")" "\"listing_status\": \"open\""
check "approved-only listing" "$(as $A "select public.admin_publish_listing('$O2','{\"visibility\":\"approved_only\",$PUB,\"public_title\":\"Office cleaning, evenings\"}')")" "approved_only"
check "invite-only listing" "$(as $A "select public.admin_publish_listing('$O3','{\"visibility\":\"invite_only\",$PUB,\"public_title\":\"Showroom floors\"}')")" "invite_only"
check "test listing (staging)" "$(as $A "select public.admin_publish_listing('$O6','{\"visibility\":\"public_summary\",$PUB,\"public_title\":\"TEST demo listing\"}')")" "open"
as $A "select public.admin_invite_provider('$O3','$W1',true)" >/dev/null
check "cannot invite a pending provider" "$(as $A "select public.admin_invite_provider('$O3','$W2',true)")" "provider_not_approved"

echo "── 3. Everything is OFF until the retest is recorded"
check "anon board empty while off" "$(as anon "select count(*) from public.contract_listings()")" "^0$"
check "provider list empty while off" "$(as $W1 "select public.provider_contract_listings()")" "^\[\]$"
check "drafts refused while off" "$(as $W1 "select public.save_contract_application('$R1','{}')")" "applications_disabled"
check "credential upload refused while off" "$(as $W2 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date,current_date+100,'$W2/coi.pdf')")" "credentials_disabled"
check "switch-on refused before retest" "$(as $A "select public.admin_set_marketplace_flags(true,true,true,false)")" "security_retest_required"
check "retest note required" "$(as $A "select public.admin_record_security_retest('ok')")" "note_required"
as $A "select public.admin_record_security_retest('Local suite contract_marketplace_test.sh passed')" >/dev/null
check "switch-on allowed after retest" "$(as $A "select public.admin_set_marketplace_flags(true,true,true,false)")" "\"applications\": true"

echo "── 4. Direct table access is closed"
for t in opportunities provider_applications listing_invites marketplace_flags opportunity_locations buyers; do
  check "anon cannot read $t" "$(as anon "select count(*) from contract_center.$t")" "permission denied"
  check "provider cannot read $t" "$(as $W1 "select count(*) from contract_center.$t")" "permission denied"
done
check "provider cannot read insurance table" "$(as $W1 "select count(*) from public.insurance_policies")" "permission denied"
check "anon cannot call provider listing" "$(as anon "select public.provider_contract_listings()")" "permission denied"
check "anon cannot call internal helper" "$(as anon "select contract_center._mp_block_reason('$W1','$O1')")" "permission denied"
check "provider cannot call internal helper" "$(as $W1 "select contract_center._mp_listing_json(o,'approved','$W1') from contract_center.opportunities o")" "permission denied"

echo "── 5. Public board shows the sanitized summary only"
PUBOUT="$(as anon "select row_to_json(l) from public.contract_listings() l")"
check "anon sees exactly one listing" "$(as anon "select count(*) from public.contract_listings()")" "^1$"
check "summary fields present" "$PUBOUT" "Overnight warehouse floor care.*Sunrise, FL.*warehouse"
for leak in Sawgrass 1234 "NW 136" HIDDENREQ HIDDENSCOPE Janitorial 9876 33351 "$O1" OPP-; do nocheck "public board hides '$leak'" "$PUBOUT" "$leak"; done
nocheck "approved-only not public" "$PUBOUT" "Office cleaning"
nocheck "invite-only not public" "$PUBOUT" "Showroom"
nocheck "test listing hidden by default" "$PUBOUT" "TEST"

echo "── 6. Tiered provider views"
P2="$(as $W2 "select public.provider_contract_listings()")"
check "pending provider sees public listing" "$(as $W2 "select jsonb_array_length(public.provider_contract_listings())")" "^1$"
check "pending provider sees visible requirement" "$P2" "General liability insurance"
nocheck "pending provider: no scope" "$P2" "\"scope\""
nocheck "pending provider: no sites" "$P2" "\"sites\""
check "approved provider sees 3 (public+approved+invite)" "$(as $W1 "select jsonb_array_length(public.provider_contract_listings())")" "^3$"
check "approved, not invited, sees 2" "$(as $W3 "select jsonb_array_length(public.provider_contract_listings())")" "^2$"
check "suspended provider sees none" "$(as $W4 "select public.provider_contract_listings()")" "^\[\]$"
check "customer is not a provider" "$(as $C1 "select public.provider_contract_listings()")" "provider_only"
P1="$(as $W1 "select public.provider_contract_listing('$R1')")"
check "approved provider sees visible scope + city/ZIP" "$P1" "Autoscrub warehouse floor.*Sunrise|Sunrise.*Autoscrub"
for leak in Sawgrass "1234 NW" HIDDENREQ HIDDENSCOPE Janitorial 9876; do nocheck "approved view hides '$leak'" "$P1" "$leak"; done
check "not-invited provider cannot open invite listing" "$(as $W3 "select public.provider_contract_listing('$R3')")" "not_available"
check "nobody can open an internal opportunity" "$(as $W1 "select public.provider_contract_listing('$R5')")" "not_available"
check "pending provider cannot open approved-only" "$(as $W2 "select public.provider_contract_listing('$R2')")" "not_available"

echo "── 7. Applications"
check "pending provider can draft" "$(as $W2 "select public.save_contract_application('$R1','{\"availability\":\"Mon-Fri nights\"}')")" "draft"
check "pending provider cannot submit" "$(as $W2 "select public.submit_contract_application('$R1')")" "not_approved"
as $W3 "select public.save_contract_application('$R1','{\"availability\":\"nights\"}')" >/dev/null
check "uninsured provider cannot submit" "$(as $W3 "select public.submit_contract_application('$R1')")" "insurance_missing:general_liability"
check "draft on internal opp refused" "$(as $W1 "select public.save_contract_application('$R5','{}')")" "not_available"
check "bad input refused" "$(as $W1 "select public.save_contract_application('$R1','{\"crew_size\":\"lots\"}')")" "bad_input"
check "availability required" "$(as $W1 "select public.save_contract_application('$R1','{}'); select public.submit_contract_application('$R1')")" "availability_required"
check "eligible provider submits" "$(as $W1 "select public.save_contract_application('$R1','{\"availability\":\"Mon-Fri 22:00-06:00\",\"crew_size\":2,\"proposed_rate\":3800,\"rate_basis\":\"monthly\"}'); select public.submit_contract_application('$R1')")" "submitted"
check "cannot edit after submitting" "$(as $W1 "select public.save_contract_application('$R1','{\"availability\":\"x\"}')")" "already_submitted"
check "owner was alerted" "$(sq "select count(*) from public.notifications where user_id='$A' and template='contract_application_submitted' and channel='inapp'")" "^1$"
check "event logged" "$(sq "select count(*) from contract_center.events where event='application.submitted'")" "^1$"
check "provider sees only own applications" "$(as $W3 "select jsonb_array_length(public.my_contract_applications())")" "^1$"
check "owner sees submitted, not drafts" "$(as $A "select jsonb_array_length(public.admin_listing_applications('$O1'))")" "^1$"

echo "── 8. Human selection, no automatic award"
APP=$(sq "select id from contract_center.provider_applications where worker_id='$W1' and opportunity_id='$O1'")
check "cannot jump submitted→selected" "$(as $A "select public.admin_decide_application('$APP','selected','')")" "bad_transition"
check "shortlist" "$(as $A "select public.admin_decide_application('$APP','shortlisted','strong fit INTERNALNOTE')")" "shortlisted"
check "select" "$(as $A "select public.admin_decide_application('$APP','selected','INTERNALNOTE')")" "selected"
check "provider notified" "$(sq "select count(*) from public.notifications where user_id='$W1' and template='contract_application_selected' and channel='inapp'")" "^1$"
nocheck "internal note hidden from provider" "$(as $W1 "select public.my_contract_applications()")" "INTERNALNOTE"
check "selected cannot be withdrawn by provider" "$(as $W1 "select public.withdraw_contract_application('$R1')")" "cannot_withdraw"
check "no assignment exists yet" "$(sq "select count(*) from contract_center.provider_assignments")" "^0$"
check "wrong contract refused" "$(as $A "select public.admin_application_to_assignment('$APP','33333333-0000-0000-0000-000000000002','subcontractor','monthly',3800,null)")" "contract_mismatch"
check "provider cannot create assignment" "$(as $W1 "select public.admin_application_to_assignment('$APP','33333333-0000-0000-0000-000000000001','subcontractor','monthly',3800,null)")" "admin_only"
K1=33333333-0000-0000-0000-000000000001; K2=33333333-0000-0000-0000-000000000002
assign() { as $A "select (public.admin_application_to_assignment('$APP','$K1','subcontractor','monthly',3800,null) is not null)::text"; }
sq "update contract_center.contracts set status='ended' where id='$K1'" >/dev/null
check "ended contract refused (existing contract-open rule)" "$(assign)" "contract_not_open"
sq "update contract_center.contracts set status='onboarding' where id='$K1'" >/dev/null
sq "update public.insurance_policies set expires_on=current_date-1 where worker_id='$W1'" >/dev/null
check "expired insurance refused at assignment" "$(assign)" "provider_not_eligible:insurance_missing:general_liability"
sq "update public.insurance_policies set expires_on=current_date+200, status='rejected' where worker_id='$W1'" >/dev/null
check "rejected (unverified) insurance refused at assignment" "$(assign)" "provider_not_eligible:insurance_missing"
sq "update public.insurance_policies set status='verified' where worker_id='$W1'" >/dev/null
check "nothing created by refused attempts" "$(sq "select (select count(*) from contract_center.provider_assignments)||'/'||(select count(*) from public.approvals)")" "^0/0$"
check "owner proposes through the existing Contract Center path" "$(assign)" "^true$"
check "assignment is PROPOSED with a pending assign_provider approval" "$(sq "select pa.status||'/'||ap.action||'/'||ap.status from contract_center.provider_assignments pa join public.approvals ap on ap.id = pa.approval_id")" "^proposed/contract_center.assign_provider/pending$"
check "approval request names this assignment" "$(sq "select (ap.payload->>'assignment_id') = pa.id::text from contract_center.provider_assignments pa join public.approvals ap on ap.id = pa.approval_id")" "^t$"
check "approval appears in owner's queue (owner alerted)" "$(sq "select count(*) from public.notifications where user_id='$A' and template='ctr_approval' and channel='inapp'")" "^1$"
check "application linked to the assignment" "$(sq "select a.assignment_id = pa.id from contract_center.provider_applications a join contract_center.provider_assignments pa on pa.id = a.assignment_id where a.id='$APP'")" "^t$"
check "assignment records its source application" "$(sq "select eligibility->>'source' from contract_center.provider_assignments")" "^contract_application$"
check "repeated request refused (no duplicate)" "$(assign)" "already_assigned"
check "still exactly one assignment and one approval" "$(sq "select (select count(*) from contract_center.provider_assignments)||'/'||(select count(*) from public.approvals)")" "^1/1$"
check "contract not activated, nothing billed" "$(sq "select status||'/'||coalesce(activated_at::text,'none') from contract_center.contracts where id='$K1'")" "^onboarding/none$"
APPR=$(sq "select approval_id from contract_center.provider_assignments")
check "provider cannot decide approvals" "$(as $W1 "select public.ctr_decide('$APPR','approved',null)")" "admin_only"
check "owner without 2-step cannot decide" "$(AAL=aal1 as $A "select public.ctr_decide('$APPR','approved',null)")" "admin_only"
check "rejection requires a reason" "$(as $A "select public.ctr_decide('$APPR','rejected','')")" "reason_required"
as $A "select public.ctr_decide('$APPR','rejected','Test: pay rate too high')" >/dev/null
check "failed approval: assignment becomes rejected" "$(sq "select status from contract_center.provider_assignments where approval_id='$APPR'")" "^rejected$"
check "decided approval cannot be changed" "$(as $A "select public.ctr_decide('$APPR','approved',null)")" "not_pending"
check "after a rejection the owner may re-propose" "$(as $A "select (public.admin_application_to_assignment('$APP','$K1','subcontractor','monthly',3500,null) is not null)::text")" "^true$"
check "re-proposal filed a new pending approval" "$(sq "select count(*) filter (where status='pending')||'/'||count(*) from public.approvals")" "^1/2$"
APPR2=$(sq "select approval_id from contract_center.provider_assignments where status='proposed'")
as $A "select public.ctr_decide('$APPR2','approved',null)" >/dev/null
check "owner approval moves it to approved (not active)" "$(sq "select status from contract_center.provider_assignments where approval_id='$APPR2'")" "^approved$"
check "approval did not activate the contract" "$(sq "select status||'/'||coalesce(activated_at::text,'none') from contract_center.contracts where id='$K1'")" "^onboarding/none$"
check "existing direct workflow still works" "$(as $A "select (public.ctr_propose_assignment('$K2', jsonb_build_object('worker_id','$W1','pay_basis','monthly','pay_rate',100)) is not null)::text")" "^true$"
check "direct workflow also files an approval" "$(sq "select count(*) from public.approvals where status='pending'")" "^1$"

echo "── 9. Credentials (upload guard: approved providers only, switch on, enforced by storage + database)"
put() { as "$1" "insert into storage.objects(bucket_id,name) values ('worker-docs','$2') returning name"; }
files() { sq "select count(*) from storage.objects where name like '$1'"; }
check "status: pending provider may not upload" "$(as $W2 "select public.provider_marketplace_status()")" '"uploads": false.*not_approved|not_approved.*"uploads": false'
check "status: approved provider may upload" "$(as $W3 "select public.provider_marketplace_status()")" '"uploads": true'
check "precheck: pending refused" "$(as $W2 "select public.provider_credential_precheck('insurance','general_liability',1000000,current_date+300)")" "not_approved"
check "storage: pending upload refused before the file exists" "$(put $W2 "$W2/credentials/coi.pdf")" "row-level security"
check "storage: suspended upload refused" "$(put $W4 "$W4/credentials/bg.pdf")" "row-level security"
check "no file left by refused uploads" "$(files '%/credentials/%')" "^0$"
check "database: pending submit refused" "$(as $W2 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date,current_date+100,'$W2/credentials/coi.pdf')")" "not_approved"
check "suspended submit refused" "$(as $W4 "select public.submit_provider_compliance('background_check',null,'$W4/credentials/bg.pdf')")" "not_approved"
check "profile documents (approval process) still upload" "$(put $W2 "$W2/1_license.pdf")" "license.pdf"
check "precheck: expired refused before upload" "$(as $W3 "select public.provider_credential_precheck('insurance','general_liability',1000000,current_date-1)")" "expired"
check "precheck: bad coverage refused before upload" "$(as $W3 "select public.provider_credential_precheck('insurance','general_liability',0,current_date+300)")" "bad_coverage"
check "precheck: approved gets own folder" "$(as $W3 "select public.provider_credential_precheck('insurance','general_liability',1000000,current_date+300)")" "^$W3/credentials/$"
check "storage: approved upload into own credentials folder" "$(put $W3 "$W3/credentials/1_coi.pdf")" "1_coi.pdf"
check "storage: upload into another provider's folder refused" "$(put $W3 "$W1/credentials/1_coi.pdf")" "row-level security"
check "database: path in another folder refused" "$(as $W3 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date,current_date+100,'$W1/credentials/1_coi.pdf')")" "bad_document_path"
check "database: path traversal refused" "$(as $W3 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date,current_date+100,'$W3/credentials/../../$W1/x.pdf')")" "bad_document_path"
check "database: file outside credentials folder refused" "$(as $W3 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date,current_date+100,'$W3/1_coi.pdf')")" "bad_document_path"
check "database: record without a stored file refused" "$(as $W3 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date,current_date+100,'$W3/credentials/never_uploaded.pdf')")" "document_missing"
check "database: expired refused" "$(as $W3 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date-400,current_date-1,'$W3/credentials/1_coi.pdf')")" "expired"
check "approved upload accepted as pending review" "$(as $W3 "select public.submit_provider_insurance('general_liability','Acme Mutual','GL-1',1000000,current_date,current_date+300,'$W3/credentials/1_coi.pdf') > 0")" "^t$"
check "provider sees own credential pending" "$(as $W3 "select public.my_provider_credentials()")" "\"status\": \"submitted\""
check "self-uploaded, unverified insurance still does not unlock submit" "$(as $W3 "select public.submit_contract_application('$R1')")" "insurance_missing|already|closed|no_draft"
check "existing verified credential untouched" "$(sq "select count(*) from public.insurance_policies where worker_id='$W1' and status='verified'")" "^1$"
sq "insert into storage.objects(bucket_id,name,owner,created_at) values ('worker-docs','$W3/credentials/2_orphan.pdf','$W3',now()-interval '2 hours')" >/dev/null
check "owner orphan report lists stray credential file" "$(as $A "select public.admin_orphan_credential_files()")" "2_orphan.pdf"
nocheck "orphan report ignores files that have a record" "$(as $A "select public.admin_orphan_credential_files()")" "1_coi.pdf"
check "provider cannot read orphan report" "$(as $W3 "select public.admin_orphan_credential_files()")" "admin_only"
check "anon cannot call upload functions" "$(as anon "select public.provider_credential_precheck('insurance','general_liability',1,current_date+1)")" "permission denied"
sq "delete from storage.objects where name like '%/2_orphan.pdf'" >/dev/null

echo "── 10. Listing timing, test listings, switch-off"
sq "update contract_center.opportunities set applications_due_at = now() + interval '3 days' where id='$O1'" >/dev/null
check "closing soon shown" "$(as anon "select status from public.contract_listings()")" "closing_soon"
sq "update contract_center.opportunities set applications_due_at = now() - interval '1 hour' where id='$O1'" >/dev/null
check "past due drops off the board" "$(as anon "select count(*) from public.contract_listings()")" "^0$"
check "past due refuses new drafts" "$(as $W3 "select public.save_contract_application('$R1','{\"availability\":\"x\"}')")" "not_available|closed"
as $A "select public.admin_set_marketplace_flags(true,true,true,true)" >/dev/null
check "test listing appears only when staging flag on" "$(as anon "select title from public.contract_listings()")" "TEST demo listing"
as $A "select public.admin_set_marketplace_flags(false,false,false,false)" >/dev/null
check "switched off: board empty again" "$(as anon "select count(*) from public.contract_listings()")" "^0$"
check "switched off: submissions refused" "$(as $W1 "select public.submit_contract_application('$R2')")" "applications_disabled"
check "switched off: approved provider status shows no uploads" "$(as $W3 "select public.provider_marketplace_status()")" '"uploads": false'
check "switched off: precheck refused" "$(as $W3 "select public.provider_credential_precheck('insurance','general_liability',1000000,current_date+300)")" "credentials_disabled"
check "switched off: storage refuses credential upload" "$(put $W3 "$W3/credentials/3_off.pdf")" "row-level security"
check "switched off: database refuses credential record" "$(as $W3 "select public.submit_provider_insurance('general_liability','X','1',1000000,current_date,current_date+100,'$W3/credentials/1_coi.pdf')")" "credentials_disabled"
check "switched off: no file left behind" "$(files '%/3_off.pdf')" "^0$"
check "switched off: profile documents still upload" "$(put $W2 "$W2/2_id.pdf")" "2_id.pdf"

echo
echo "passed: $pass  failed: $fail"
[ $fail -eq 0 ]
