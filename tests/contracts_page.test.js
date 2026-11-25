// Contracts & Cleaning Jobs page (/contracts/ and /es/contracts/): parity, privacy and safety rules.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const EN = read('contracts/index.html');
const ES = read('es/contracts/index.html');
const JS = read('home/contracts.js');
const CFG = read('app/config.js');
const all = (re, s) => [...s.matchAll(re)].map((m) => m[1]);

test('both languages declare themselves and link to each other', () => {
  assert.match(EN, /<html lang="en"/);
  assert.match(ES, /<html lang="es"/);
  assert.match(EN, /href="\/es\/contracts\/" hreflang="es"/);
  assert.match(ES, /href="\/contracts\/" hreflang="en"/);
});

test('English and Spanish have the same sections, fields and links', () => {
  const ids = (s) => all(/\sid="([^"]+)"/g, s);
  const names = (s) => all(/<(?:input|select|textarea)[^>]*\sname="([^"]+)"/g, s);
  const hrefs = (s) => all(/<a [^>]*href="([^"]+)"/g, s).map((h) => h.replace(/^\/es\//, '/'));
  assert.deepEqual(ids(ES), ids(EN));
  assert.deepEqual(names(ES), names(EN));
  assert.deepEqual(hrefs(ES), hrefs(EN));
});

test('staging only: noindex, and the page may only talk to the staging database', () => {
  const stagingUrl = /SUPABASE_URL:\s*"([^"]+)"/.exec(CFG)[1];
  assert.match(stagingUrl, /elzpvlpeypkcsvywwebl/);               // wcia-staging
  for (const s of [EN, ES]) {
    assert.match(s, /<meta name="robots" content="noindex, nofollow">/);
    const csp = /Content-Security-Policy" content="([^"]+)"/.exec(s)[1];
    assert.match(csp, new RegExp("connect-src 'self' " + stagingUrl.replace(/\./g, '\\.') + ';'));
    assert.doesNotMatch(csp, /fqajygzjteauxornipva/);              // production project
    assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
    assert.doesNotMatch(s, /\sstyle="|<script>(?!\s*$)|\son[a-z]+="/); // no inline styles, scripts or handlers (CSP)
  }
});

test('the board reads only the sanitized public listing function and never invents jobs', () => {
  const calls = all(/\/rest\/v1\/([a-z_/]+)/g, JS);
  assert.deepEqual(calls, ['rpc/contract_listings']);
  assert.doesNotMatch(JS, /innerHTML|insertAdjacentHTML|document\.write/);   // listing text is rendered as text
  assert.match(JS, /credentials: "omit"/);
  assert.doesNotMatch(JS + EN + ES, /sample job|demo job|lorem/i);
  for (const s of [EN, ES]) assert.match(s, /id="board"/);
  assert.match(JS, /none_t/);                                                 // honest empty state
});

test('a listing is clearly not a contract, in both languages', () => {
  assert.match(EN, /A listing is not a contract\./);
  assert.match(ES, /Una publicación no es un contrato\./);
});

test('times on the board use the shared 24-hour helper', () => {
  assert.match(JS, /TIME\.dateTime\(/);
  assert.doesNotMatch(JS, /hour12|AM|PM/);
});

test('register buttons go to the provider sign-up in the app', () => {
  for (const s of [EN, ES]) assert.ok(all(/href="(\/app\/\?join=provider)"/g, s).length >= 3);
});

test('both homepages link to the jobs page', () => {
  assert.match(read('index.html'), /href="\/contracts\/"/);
  assert.match(read('es/index.html'), /href="\/es\/contracts\/"/);
});
