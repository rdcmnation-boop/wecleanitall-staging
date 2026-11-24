// Commercial homepage (/ and /es/): structure, links, language parity, 24-hour times and routing safety.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const EN = read('index.html');
const ES = read('es/index.html');
const all = (re, s) => [...s.matchAll(re)].map((m) => m[1]);

test('both pages declare their language and link to each other (hreflang + switch)', () => {
  assert.match(EN, /<html lang="en"/);
  assert.match(ES, /<html lang="es"/);
  for (const s of [EN, ES]) {
    assert.match(s, /hreflang="en" href="https:\/\/www\.wecleanitallfl\.com\/"/);
    assert.match(s, /hreflang="es" href="https:\/\/www\.wecleanitallfl\.com\/es\/"/);
  }
  assert.match(EN, /href="\/es\/" hreflang="es"/);
  assert.match(ES, /href="\/" hreflang="en"/);
});

test('English and Spanish pages have the same sections, anchors, links and form fields', () => {
  const ids = (s) => all(/\sid="([^"]+)"/g, s);
  const names = (s) => all(/\sname="([^"]+)"/g, s).filter((n) => !['viewport', 'referrer', 'description', 'theme-color', 'robots'].includes(n) && !n.startsWith('twitter:'));
  const hrefs = (s) => all(/<a [^>]*href="([^"]+)"/g, s).map((h) => h.replace(/^\/es\//, '/').replace(/subject=.*/, 'subject='));
  assert.deepEqual(ids(ES), ids(EN));
  assert.deepEqual(names(ES), names(EN));
  assert.deepEqual(hrefs(ES).filter((h) => h !== '/'), hrefs(EN).filter((h) => h !== '/es/' && h !== '/'));
  assert.equal(all(/<option>/g, ES).length, all(/<option>/g, EN).length);
});

test('every in-page link points at a section that exists', () => {
  for (const s of [EN, ES]) {
    const ids = new Set(all(/\sid="([^"]+)"/g, s));
    for (const h of all(/href="#([^"]+)"/g, s)) assert.ok(ids.has(h), 'missing #' + h);
  }
});

test('every local link and asset exists in the repository', () => {
  for (const s of [EN, ES]) {
    const refs = [...all(/(?:href|src)="(\/[^"#?]*)/g, s), ...all(/srcset="([^"]+)"/g, s).flatMap((v) => v.split(',').map((x) => x.trim().split(' ')[0]))];
    for (const r of refs) {
      const p = r.endsWith('/') ? r + 'index.html' : r;
      assert.ok(fs.existsSync(path.join(ROOT, p)), 'missing ' + r);
    }
  }
});

test('no 12-hour clock times (AM/PM) anywhere on the homepage', () => {
  for (const s of [EN, ES, read('home/site.js')]) {
    assert.doesNotMatch(s.replace(/<[^>]+>/g, ' '), /\b\d{1,2}(:\d{2})?\s?(am|pm|a\.m\.|p\.m\.)(?![a-z])/i);
  }
});

test('no residential wording on the commercial homepage', () => {
  for (const s of [EN, ES]) assert.doesNotMatch(s.replace(/<[^>]+>/g, ' '), /\b(residential|home cleaning|homes?|apartment|casa|hogar|apartamento|residencial)\b/i);
});

test('strict security policy: same-site scripts only, no inline scripts or inline styles', () => {
  for (const s of [EN, ES]) {
    const csp = s.match(/Content-Security-Policy" content="([^"]+)"/)[1];
    assert.match(csp, /script-src 'self'(;|$)/);
    assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
    const inline = all(/<script(?![^>]*\bsrc=)([^>]*)>/g, s).filter((a) => !/application\/ld\+json/.test(a));
    assert.deepEqual(inline, []);
    assert.doesNotMatch(s, /\sstyle="/);
    assert.doesNotMatch(s, /\son[a-z]+="/i);
  }
});

test('the site-assessment form does not send data anywhere except the visitor\'s own email app', () => {
  const js = read('home/site.js');
  assert.doesNotMatch(js, /fetch\(|XMLHttpRequest|sendBeacon|supabase/i);
  assert.match(js, /mailto:/);
  for (const s of [EN, ES]) assert.doesNotMatch(s, /<form[^>]*\saction=/);
});

test('JSON-LD is valid and commercial only', () => {
  for (const s of [EN, ES]) {
    const ld = JSON.parse(s.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
    assert.equal(ld['@type'], 'ProfessionalService');
    assert.equal(ld.telephone, '+1-954-320-9303');
    assert.doesNotMatch(JSON.stringify(ld), /residential|residencial/i);
  }
});

test('sign-in links that still point at / are forwarded to the app at /app/', () => {
  const src = read('home/route.js');
  const run = (hash, search) => {
    let replaced = null;
    const cls = new Set(['no-js']);
    const window = {}; window.top = window; window.self = window;
    const ctx = { window, location: { hash, search, href: 'https://x/', replace: (u) => { replaced = u; } },
      document: { documentElement: { classList: { remove: (c) => cls.delete(c), add: (c) => cls.add(c) }, style: {} } } };
    new Function('window', 'location', 'document', src)(ctx.window, ctx.location, ctx.document);
    return { replaced, cls };
  };
  assert.equal(run('#access_token=a&refresh_token=b&type=recovery', '').replaced, '/app/#access_token=a&refresh_token=b&type=recovery');
  assert.equal(run('#error=access_denied&error_description=x', '').replaced, '/app/#error=access_denied&error_description=x');
  assert.equal(run('', '?code=abc').replaced, '/app/?code=abc');
  const plain = run('#assess', '');
  assert.equal(plain.replaced, null);
  assert.ok(plain.cls.has('js') && !plain.cls.has('no-js'));
});

test('app moved to /app/: shell, worker scope, manifest and old-page cleanup are consistent', () => {
  const shell = read('app/index.html');
  assert.match(shell, /<script src="\/app\/app\.js\?v=/);
  assert.match(shell, /rel="canonical" href="https:\/\/www\.wecleanitallfl\.com\/app\/"/);
  const app = read('app/app.js');
  assert.match(app, /serviceWorker\.register\("\/app\/sw\.js", \{ scope: "\/app\/" \}\)/);
  assert.match(app, /class="brand" href="\/app\/"/);
  const m = JSON.parse(read('app/manifest.webmanifest'));
  assert.equal(m.start_url, '/app/'); assert.equal(m.scope, '/app/'); assert.equal(m.lang, 'en');
  assert.match(read('app/sw.js'), /caches\.match\("\/app\/"\)/);
  assert.match(read('sw.js'), /registration\.unregister\(\)/);
  assert.match(read('app/config.js'), /APP_URL: "https:\/\/[a-z.]+\/app\/"/);
  assert.match(read('comercial/index.html'), /url=\//);
});
