# WE CLEAN IT ALL — staging replica

This repository is the **staging copy** of www.wecleanitallfl.com, served at https://staging.wecleanitallfl.com.
It is for testing only. It is not indexed by search engines and must never point at production.

## Source

An exact copy of the live site repository `rdcmnation-boop/wecleanitallfl`, branch `main`, commit `e2172d0` (2026-11-17).
No features were added and no behaviour was changed, apart from the staging-only differences below.

## Staging-only differences from the live site

| File | Live | Staging | Why |
|---|---|---|---|
| `CNAME` | `www.wecleanitallfl.com` | `staging.wecleanitallfl.com` | Staging address |
| `app/config.js` | Production Supabase (`fqajygzjteauxornipva`) URL + publishable key; `APP_URL` www | Staging Supabase (`elzpvlpeypkcsvywwebl`, `wcia-staging`) URL + publishable key; `APP_URL` staging | Staging uses only the staging database, API and sign-in |
| `app/owner.js` | WhatsApp webhook URL and dashboard link to the production project | Same, pointed at the staging project | Owner panel never shows or links production |
| `demo/app/owner.js` | Dashboard link to the production project | Staging project | Same reason |
| `robots.txt` | Allow all + sitemap | Disallow all | Keep staging out of search engines |
| `index.html`, `comercial/`, `privacy/`, `terms/`, `app/`, `demo/` | Some pages `noindex`, others indexable | All pages `noindex, nofollow` | Same reason |

Files left as they are on purpose: SQL and documentation that mention the production project ID (they are reference
material, not loaded by the site); `canonical` and Open Graph tags (they point to www, which also tells search engines
the live site is the real one); the Google verification file; `sitemap.xml` (blocked by robots.txt).

The `Supabase keep-alive` workflow reads `app/config.js`, so in this repository it pings the **staging** project only.

## Known behaviour differences caused by the staging database

The staging database is ahead of production (milestone1 work and the Contract Center foundation), while this site runs
the live app code. The 50 database functions the app calls exist in both projects with identical signatures, but:

- **Cleaner job flow:** staging requires a check-in before "Start job" and a check-out before "Complete job"
  (`a5_require_job_proof`). The live app has no check-in screen, so cleaners will see `check_in_required` /
  `check_out_required` errors on staging. The owner account is exempt.
- **Duplicate booking guard:** staging refuses the same booking (same customer, service, ZIP, time) within 10 minutes
  (`duplicate_booking`). Production has no such guard.
- **Extra booking tracking:** staging records workflow states and events for each booking. Invisible to the live app.

## Settings that must be made outside this repository

1. GitHub → this repo → Settings → Pages: Source "Deploy from a branch", branch `main`, folder `/ (root)`;
   custom domain `staging.wecleanitallfl.com`; tick "Enforce HTTPS" once the certificate is issued.
2. Supabase → project `wcia-staging` → Authentication → URL Configuration: Site URL `https://staging.wecleanitallfl.com`,
   and add it to Redirect URLs. Without this, sign-in and email links on staging go to the wrong address.

## Checkpoint A: commercial homepage (branch `homepage-checkpoint-a`)

Built from the frozen v1 desktop + phone artboards and the Homepage & Platform Implementation Plan. Staging only.

| Area | What changed |
|---|---|
| `/` | New static commercial homepage (`index.html`, `home/home.css`, `home/route.js`, `home/site.js`). Does not load the app. |
| `/es/` | Spanish twin with hreflang links. Spanish wording is a draft for native-speaker review. |
| `/app/` | The booking app moved here from `/` (old `/app/` redirect removed). Canonical, worker scope, manifest (`start_url`/`scope` `/app/`, `lang` en) and in-app logo link updated. |
| `app/config.js` | `APP_URL` → `https://staging.wecleanitallfl.com/app/` so new sign-in emails land in the app. |
| `/sw.js` | Now a cleanup worker that removes the old root worker and its caches from devices. The real worker is `/app/sw.js`. |
| Old sign-in links | `home/route.js` forwards any `/` address carrying a sign-in or reset token to `/app/`. |
| `/comercial/` | Redirect page to `/` (`#quote` → `#assess`). |
| Site-assessment form | Opens the visitor's email app with the details filled in (no database). The public intake function into `contract_center.prospects` is a new Contract Center module and stays off until it passes the security retest. |
| Tests | `tests/homepage.test.js` (11 tests); `tests/time24.test.js` now checks the app at its new path. |

Not in this checkpoint: the residential switch inside the booking flow (`RESIDENTIAL_PUBLIC`), the public intake function, real robot photography.

Setting needed outside the repo for this branch: Supabase → `wcia-staging` → Authentication → URL Configuration → add
`https://staging.wecleanitallfl.com/app/` to Redirect URLs (keep the existing `/` entry during the transition).

## Rules

- Never put production keys, service-role keys or any secret in this repository.
- Never change `app/config.js` to point at production.
- Production changes happen only in `rdcmnation-boop/wecleanitallfl`, after explicit owner approval.

## Contracts & Cleaning Jobs (branch `contracts-jobs-local`, local only, 2026-11-25)

Approved by the owner on 2026-11-25 for **staging only**. Migration applied to wcia-staging (as `contract_marketplace_1_schema` + `contract_marketplace_2_functions`, function code verified identical to the tested build). Deployed to staging.wecleanitallfl.com. **All marketplace switches OFF, no security retest recorded yet, payments untouched, production untouched.**

| Area | What changed |
|---|---|
| `/contracts/`, `/es/contracts/` | New public page: open-opportunity board (sanitized summaries only), "a listing is not a contract" pipeline, access table, provider registration, business request form (email app, no database). Same black-and-lime design as the homepage. |
| `index.html`, `es/index.html` | One new card in the Contracts section linking to the jobs page. Nav unchanged. |
| `app/contracts_app.js` + small hooks | Provider screens: Opportunities, My applications, Credentials. Owner screen: Contracts & jobs (switches, listings, provider-visible lines, invites, applications, credential review, proposed assignment). `/app/?join=provider` opens provider sign-up. |
| `app/api.js` | `API.cc()` can call only the 22 marketplace functions; `uploadDoc` now returns the stored path. |
| `marketplace/supabase/contract_marketplace.sql` | Migration (re-runnable). Reuses `contract_center.*`, `workers`, `insurance_policies`, `provider_compliance`, `provider_coverage`, `worker-docs`. Adds listing fields, `provider_applications`, `listing_invites`, `marketplace_flags` (all OFF) and the functions. |

**Safety design**
- Everything ships OFF. The owner can't switch anything on until a security retest is recorded in the database.
- Public board = only fields the owner writes on purpose. Publishing refuses client, site or incumbent names, street numbers / ZIPs, emails and links, and unverified opportunities.
- Internal requirement and scope lines are hidden from providers until the owner marks each one visible.
- Registered (pending) providers: summary + visible requirements, drafts only. Approved: + scope, city / ZIP / size, eligibility, submit. Never the street address, site name or client.
- Submitting checks approval, service area and verified, unexpired insurance / documents the listing requires.
- Selection is a human decision. "Propose assignment" creates a **proposed** provider assignment on an existing signed contract; activation stays in the Contract Center. No payments anywhere.
- No table is readable directly; everything goes through functions.

**Tests**
- `marketplace/supabase/test/contract_marketplace_test.sh`: 113 security checks on a throwaway Postgres, using `contract_center_fixture.sql`, which mirrors the staging tables.
- `tests/contracts_page.test.js` and `tests/contracts_app.test.js`, plus all existing tests: 112 JS tests.

**Before applying to wcia-staging:** owner review; a security retest on staging itself (the fixture mirrors staging, but triggers on staging tables were not reproduced); then apply; then record the retest and switch on one flag at a time.
