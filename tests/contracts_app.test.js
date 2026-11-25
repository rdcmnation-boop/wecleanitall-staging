// Contracts & Cleaning Jobs app screens (app/contracts_app.js) and their API allow-list.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const SQL = read('marketplace/supabase/contract_marketplace.sql');

function load(over) {
  const calls = [];
  const win = {};
  const ctx = { window: win, console, setTimeout, URLSearchParams };
  vm.runInNewContext(read('app/contracts_app.js'), ctx);
  const S = Object.assign({ data: {}, me: { profile: { id: 'u1' }, worker: { status: 'approved' } } }, over && over.S);
  const API = Object.assign({ mode: 'live', cc: async (fn, args) => { calls.push([fn, args]); return over && over.ret ? over.ret(fn) : []; },
    uploadDoc: async (uid, f, sub) => { calls.push(['upload', sub]); return uid + '/' + (sub ? sub + '/' : '') + '1_' + f.name; },
    deleteDoc: async (path) => { calls.push(['delete', path]); return true; }, docUrl: async () => null, adminWorkers: async () => [] }, over && over.API);
  const toasts = [];
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const M = win.WCIA_CONTRACTS({ esc, icon: () => '', S, API, when: (x) => 'W(' + x + ')', money: (n) => '$' + n, empty: (i, t) => '<div class="empty">' + esc(t) + '</div>',
    loading: () => '<i>loading</i>', lang: () => (over && over.lang) || 'en', render: () => {}, loadTab: async () => {}, toast: (m, k) => toasts.push([m, k]) });
  return { M, S, calls, toasts };
}

const LISTING = { ref: 'J-ABC12345', title: 'Overnight warehouse floors', summary: 'Big floor', area: 'Sunrise, FL', facility_type: 'warehouse', size_band: '50k_100k',
  frequency: 'weekdays', schedule: 'overnight', requirements: ['general_liability'], status: 'open', access: 'public', tier: 'approved',
  requirement_details: [{ category: 'insurance', requirement: 'GL 1M', mandatory: true }], scope: [{ area: 'general', task: 'Autoscrub', frequency: 'weekdays', quantity: 60000, unit: 'sqft' }],
  sites: [{ city: 'Sunrise', zip: '33351', building_type: 'warehouse', sqft: 60000 }], block_reason: null };

test('the app can call exactly the marketplace functions the database grants to signed-in users', () => {
  const api = read('app/api.js');
  const list = JSON.parse('[' + /const CC_FNS = \[([\s\S]*?)\];/.exec(api)[1] + ']');
  const grant = /grant execute on function ([\s\S]*?)\s+to authenticated;/.exec(SQL.split('grant execute on function public.contract_listings() to anon, authenticated;')[1])[1];
  const GUARD = read('marketplace/supabase/contract_marketplace_upload_guard.sql');
  const guardGrant = /grant execute on function ([\s\S]*?)\s+to authenticated;/.exec(GUARD)[1];
  const granted = [...new Set([...grant.matchAll(/public\.([a-z_]+)\(/g), ...guardGrant.matchAll(/public\.([a-z_]+)\(/g)].map((m) => m[1]))]
    .filter((n) => n !== 'provider_can_upload_credentials');   // used by the storage rule, not called by the app
  assert.deepEqual([...list].sort(), [...granted].sort());
  assert.match(api, /if \(!CC_FNS\.includes\(fn\)\) throw new ApiError\("not_allowed"\)/);
  assert.match(api, /\(function \(\) \{\n  "use strict";/);   // strict mode stays the first statement
});

test('provider listing renders text safely (no HTML injection)', () => {
  const { M, S } = load();
  S.data = { cc: [Object.assign({}, LISTING, { title: '<img src=x onerror=alert(1)>' })] };
  const html = M.views.opps();
  assert.doesNotMatch(html, /<img src=x/);
  assert.match(html, /&lt;img src=x/);
});

test('approved provider sees scope, site and a send button; selected work cannot be edited', () => {
  const { M, S } = load();
  S.data = { cc: [Object.assign({}, LISTING, { application: { status: 'draft' } })] };
  let html = M.views.opps();
  assert.match(html, /Autoscrub/);
  assert.match(html, /data-act="cc-send"/);
  assert.match(html, /exact address and client are shared with the selected provider/);
  S.data = { cc: [Object.assign({}, LISTING, { application: { status: 'selected' } })] };
  html = M.views.opps();
  assert.doesNotMatch(html, /cc-send|cc-open|cc-withdraw/);
});

test('registered (pending) provider can prepare but never gets a send button', () => {
  const { M, S } = load({ S: { me: { profile: { id: 'u1' }, worker: { status: 'pending' } } } });
  S.data = { cc: [Object.assign({}, LISTING, { tier: 'registered', scope: undefined, sites: undefined, application: { status: 'draft' } })] };
  const html = M.views.opps();
  assert.match(html, /waiting for approval/);
  assert.match(html, /data-act="cc-open"/);
  assert.doesNotMatch(html, /data-act="cc-send"/);
});

test('ineligible provider sees why and where to fix it', () => {
  const { M, S } = load();
  S.data = { cc: [Object.assign({}, LISTING, { block_reason: 'insurance_missing:general_liability', application: { status: 'draft' } })] };
  const html = M.views.opps();
  assert.match(html, /verified, current insurance certificate is required: General liability insurance/);
  assert.doesNotMatch(html, /data-act="cc-send"/);
  assert.match(html, /data-tab="creds"/);
});

test('empty board is honest and Spanish works', () => {
  const { M, S } = load({ lang: 'es' });
  S.data = { cc: [] };
  assert.match(M.views.opps(), /No hay oportunidades abiertas ahora/);
  assert.match(M.views.opps(), /Una publicación no es un contrato/);
});

test('saving a draft sends only the allowed fields to the database', async () => {
  const { M, calls } = load();
  const form = { dataset: { ref: 'J-ABC12345' } };
  await M.onSubmit('cc-app', { availability: ' Mon-Fri 22:00 ', crew_size: '2', proposed_rate: '', rate_basis: 'monthly', robot_experience: 'on', message: 'hi', extra: 'x' }, form);
  assert.equal(calls[0][0], 'save_contract_application');
  assert.deepEqual(Object.keys(calls[0][1].p).sort(), ['availability', 'can_start_on', 'crew_size', 'message', 'proposed_rate', 'rate_basis', 'robot_experience']);
  assert.equal(calls[0][1].p.availability, 'Mon-Fri 22:00');
  assert.equal(calls[0][1].p.proposed_rate, null);
  assert.equal(calls[0][1].p.robot_experience, true);
});

test('credential upload: database precheck first, then guarded folder, then record', async () => {
  const { M, calls } = load();
  const form = { querySelector: () => ({ files: [{ name: 'coi.pdf', size: 1000 }] }) };
  await M.onSubmit('cc-ins', { kind: 'general_liability', carrier: 'Acme', policy_number: '1', coverage_usd: '1000000', starts_on: '', expires_on: '2027-11-01' }, form);
  assert.deepEqual(calls.map((c) => c[0]), ['provider_credential_precheck', 'upload', 'submit_provider_insurance']);
  assert.equal(calls[0][1].p_type, 'insurance');
  assert.equal(calls[1][1], 'credentials');
  assert.equal(calls[2][1].p_document_path, 'u1/credentials/1_coi.pdf');
  assert.equal(calls[2][1].p_coverage_usd, 1000000);
});

test('credential upload refused by the precheck sends no file at all', async () => {
  const { M, calls, toasts } = load({ API: { cc: async (fn) => { calls.push([fn]); if (fn === 'provider_credential_precheck') throw new Error('credentials_disabled'); return 1; } } });
  const form = { querySelector: () => ({ files: [{ name: 'coi.pdf', size: 1000 }] }) };
  await M.onSubmit('cc-ins', { kind: 'general_liability', coverage_usd: '1', expires_on: '2027-11-01' }, form);
  assert.deepEqual(calls.map((c) => c[0]), ['provider_credential_precheck']);
  assert.match(toasts[0][0], /not open yet/);
});

test('if the record is refused after upload, the file is deleted', async () => {
  const { M, calls } = load({ API: { cc: async (fn, args) => { calls.push([fn, args]); if (fn.indexOf('submit_') === 0) throw new Error('document_missing'); return 'u1/credentials/'; } } });
  const form = { querySelector: () => ({ files: [{ name: 'bg.pdf', size: 1000 }] }) };
  await M.onSubmit('cc-comp', { requirement: 'background_check', expires_on: '' }, form);
  assert.deepEqual(calls.map((c) => c[0]), ['provider_credential_precheck', 'upload', 'submit_provider_compliance', 'delete']);
  assert.equal(calls[3][1], 'u1/credentials/1_bg.pdf');
});

test('upload forms are hidden unless the database says uploads are allowed', () => {
  const { M, S } = load();
  S.data = { cc: { insurance: [], compliance: [] }, ccStatus: { uploads: false, upload_block_reason: 'credentials_disabled' } };
  let html = M.views.creds();
  assert.doesNotMatch(html, /data-form="cc-ins"|data-form="cc-comp"|type="file"/);
  assert.match(html, /Credential uploads are not open yet/);
  S.data.ccStatus = { uploads: false, upload_block_reason: 'not_approved' };
  html = M.views.creds();
  assert.doesNotMatch(html, /type="file"/);
  assert.match(html, /once your provider account is approved/);
  S.data.ccStatus = null;
  assert.doesNotMatch(M.views.creds(), /type="file"/);
  S.data.ccStatus = { uploads: true, upload_block_reason: null };
  assert.match(M.views.creds(), /data-form="cc-ins"/);
});

test('error text prefers the exact code (provider_not_approved is not not_approved)', async () => {
  const { M, toasts } = load({ API: { cc: async () => { throw new Error('provider_not_approved'); } } });
  await M.onSubmit('cc-invite', { worker: 'w' }, { dataset: { id: 'o1' } });
  assert.match(toasts[0][0], /Only approved providers can be invited/);
});

test('owner sees a warning when credential files have no record', () => {
  const { M, S } = load();
  S.data = { flags: {}, list: [], creds: null, orphans: [{ path: 'x/credentials/1.pdf' }] };
  assert.match(M.views.cc(), /Credential files without a record: 1/);
});

test('owner screen: switches off by default, retest form shown, server errors explained', async () => {
  const { M, S, toasts } = load({ API: { cc: async () => { throw new Error('security_retest_required'); } } });
  S.data = { flags: { public_listings: false, provider_listings: false, applications: false, security_retest_passed_at: null }, list: [], creds: { insurance: [], compliance: [] } };
  const html = M.views.cc();
  assert.doesNotMatch(html, /name="public_listings" checked/);
  assert.match(html, /data-form="cc-retest"/);
  await M.onSubmit('cc-flags', { public_listings: 'on' }, {});
  assert.match(toasts[0][0], /Record the security retest/);
});

test('owner assignment needs a signed contract and creates a proposed assignment only', () => {
  const { M, S } = load();
  S.ccAppsFor = 'o1';
  S.data = { flags: {}, list: [{ id: 'o1', code: 'OPP-1', ref: 'J-1', title: 'T', status: 'awarded', verification_status: 'verified', visibility: 'approved_only', public_status: 'open', applications: { selected: 1 } }], creds: null };
  S.ccApps = { o1: [{ id: 'a1', status: 'selected', name: 'Maria', kind: 'individual', provider_status: 'approved', jobs_done: 3, contract_id: null }] };
  assert.match(M.views.cc(), /No signed contract for this opportunity yet/);
  S.ccApps.o1[0].contract_id = 'c1';
  const html = M.views.cc();
  assert.match(html, /data-form="cc-assign"/);
  assert.match(html, /PROPOSED assignment/);
});

test('owner publish converts month and 24h close time before sending', async () => {
  const { M, calls } = load();
  await M.onSubmit('cc-publish', { visibility: 'public_summary', listing_status: 'open', public_title: 'Warehouse floors', public_requirements: 'general_liability',
    public_start_month: '2027-01', applications_due_at: '2026-12-15T22:00' }, { dataset: { id: 'o1' } });
  const p = calls[0][1].p;
  assert.equal(calls[0][0], 'admin_publish_listing');
  assert.equal(p.public_start_month, '2027-01-01');
  assert.deepEqual([...p.public_requirements], ['general_liability']);
  assert.match(p.applications_due_at, /^2026-12-1[56]T\d\d:00:00\.000Z$/);
});

test('the app links the new screens and the provider sign-up deep link', () => {
  const app = read('app/app.js'), dash = read('app/dash.js'), html = read('app/index.html');
  assert.match(app, /"opps", "myapps", "creds"\]/);
  assert.match(app, /"connectors", "cc"\]/);
  assert.match(app, /join === "provider"/);
  assert.match(dash, /\["opps", "building", "m_opps"\]/);
  assert.match(html, /<script src="\/app\/contracts_app\.js\?v=[^"]+"><\/script>\n<script src="\/app\/app\.js/);
});
