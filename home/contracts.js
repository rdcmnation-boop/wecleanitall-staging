// Contracts & Cleaning Jobs board (/contracts/ and /es/contracts/).
// Reads only public.contract_listings(): the sanitized summary the owner publishes on purpose. It returns nothing
// while the owner's "public listings" switch is off, and the page then shows the honest empty state (no made-up listings).
// The business request form opens the visitor's email app (no database), like the homepage site-assessment form.
(function () {
  "use strict";
  var es = document.documentElement.lang === "es";
  var cfg = window.WCIA_CONFIG || {};
  var TIME = window.WCIA_TIME;
  var JOIN = "/app/?join=provider";
  var L = es ? {
    facility: { office: "Oficinas", medical: "Centro médico", retail: "Comercio / showroom", warehouse: "Almacén / distribución", school: "Escuela",
      government: "Edificio público", industrial: "Industrial", mixed: "Uso mixto", residential_common: "Áreas comunes", other: "Otro" },
    size: { under_5k: "Menos de 5.000 pies²", "5k_20k": "5.000–20.000 pies²", "20k_50k": "20.000–50.000 pies²", "50k_100k": "50.000–100.000 pies²", over_100k: "Más de 100.000 pies²" },
    freq: { daily: "Diario", "6x_week": "6 veces por semana", weekdays: "Lunes a viernes", "4x_week": "4 veces por semana", "3x_week": "3 veces por semana",
      "2x_week": "2 veces por semana", weekly: "Semanal", biweekly: "Cada dos semanas", monthly: "Mensual", quarterly: "Trimestral", one_time: "Una sola vez", on_call: "A pedido" },
    sched: { day: "De día", evening: "Tarde / noche", overnight: "Madrugada", weekend: "Fines de semana", flexible: "Flexible" },
    req: { general_liability: "Seguro de responsabilidad civil", workers_comp: "Seguro de compensación laboral", background_check: "Verificación de antecedentes",
      business_license: "Licencia comercial", own_equipment: "Equipo propio", own_transport: "Transporte propio", floor_care: "Cuidado de pisos",
      robot_operation: "Operación de robots", bilingual: "Bilingüe", night_availability: "Disponible de noche", experience_1y: "1+ año de experiencia", experience_3y: "3+ años de experiencia" },
    status: { open: "Abierta", closing_soon: "Cierra pronto", filled: "Cubierta" },
    size_l: "Tamaño", freq_l: "Frecuencia", sched_l: "Horario", start_l: "Inicio", closes: "Cierra", apply: "Regístrate para postularte →", filled_note: "Ya no acepta postulaciones",
    all_types: "Todos los tipos", all_status: "Todos los estados", none_t: "No hay oportunidades abiertas en este momento.",
    none_b: "Publicamos solo oportunidades reales y verificadas. Regístrate como proveedor y te avisaremos cuando haya trabajo nuevo en tu zona.",
    none_cta: "Registrarme como proveedor", nomatch: "Ninguna oportunidad coincide con estos filtros.", locale: "es-US",
    need: "Completa los campos marcados.", contact: "Escribe un correo o un teléfono para responderte.", email: "Revisa el correo.",
    phone: "Revisa el teléfono (10 dígitos).", ok: "Abrimos tu app de correo con los datos. Envía el mensaje para completar la solicitud. ¿Prefieres llamar? (954) 320-9303.",
    subject: "Solicitud de limpieza comercial: ", intro: "Solicitud desde la web (Contratos y trabajos)"
  } : {
    facility: { office: "Office", medical: "Medical", retail: "Retail / showroom", warehouse: "Warehouse / distribution", school: "School",
      government: "Public building", industrial: "Industrial", mixed: "Mixed use", residential_common: "Common areas", other: "Other" },
    size: { under_5k: "Under 5,000 sq ft", "5k_20k": "5,000–20,000 sq ft", "20k_50k": "20,000–50,000 sq ft", "50k_100k": "50,000–100,000 sq ft", over_100k: "Over 100,000 sq ft" },
    freq: { daily: "Daily", "6x_week": "6× a week", weekdays: "Weekdays", "4x_week": "4× a week", "3x_week": "3× a week", "2x_week": "2× a week",
      weekly: "Weekly", biweekly: "Every two weeks", monthly: "Monthly", quarterly: "Quarterly", one_time: "One time", on_call: "On call" },
    sched: { day: "Daytime", evening: "Evening", overnight: "Overnight", weekend: "Weekends", flexible: "Flexible" },
    req: { general_liability: "General liability insurance", workers_comp: "Workers' comp insurance", background_check: "Background check",
      business_license: "Business license", own_equipment: "Own equipment", own_transport: "Own transportation", floor_care: "Floor care",
      robot_operation: "Robot operation", bilingual: "Bilingual", night_availability: "Night availability", experience_1y: "1+ year experience", experience_3y: "3+ years experience" },
    status: { open: "Open", closing_soon: "Closing soon", filled: "Filled" },
    size_l: "Size", freq_l: "Frequency", sched_l: "Schedule", start_l: "Start", closes: "Closes", apply: "Register to apply →", filled_note: "No longer accepting applications",
    all_types: "All facility types", all_status: "All statuses", none_t: "No open opportunities right now.",
    none_b: "We only publish real, verified opportunities. Register as a provider and we'll let you know when new work is posted in your area.",
    none_cta: "Register as a provider", nomatch: "No opportunities match these filters.", locale: "en-US",
    need: "Please fill in the highlighted fields.", contact: "Add an email or a phone number so we can reply.", email: "Please check the email address.",
    phone: "Please check the phone number (10 digits).", ok: "Your email app is opening with the details filled in. Send the message to complete your request. Prefer to call? (954) 320-9303.",
    subject: "Commercial cleaning request: ", intro: "Website request (Contracts & Jobs)"
  };

  var el = function (tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; };
  var board = document.getElementById("board"), fType = document.getElementById("f-type"), fStatus = document.getElementById("f-status");
  var items = [];

  var month = function (d) {
    if (!d) return "";
    var p = String(d).split("-");
    return new Date(+p[0], +p[1] - 1, 1).toLocaleDateString(L.locale, { month: "long", year: "numeric" });
  };
  var when = function (ts) { return TIME && ts ? TIME.dateTime(ts, L.locale) : ""; };

  var empty = function (title, body, cta) {
    var box = el("div", "board-empty");
    box.appendChild(el("strong", null, title));
    if (body) box.appendChild(el("p", "soft", body));
    if (cta) { var a = el("a", "btn btn-lime", L.none_cta); a.href = JOIN; box.appendChild(a); }
    return box;
  };

  var card = function (j) {
    var c = el("article", "job" + (j.status === "filled" ? " job-filled" : ""));
    var top = el("div", "job-top");
    var head = el("div");
    head.appendChild(el("h3", null, j.title));
    head.appendChild(el("p", "job-area", j.area + " · " + (L.facility[j.facility_type] || "")));
    top.appendChild(head);
    top.appendChild(el("span", "pill " + (j.status === "open" ? "pill-on" : j.status === "closing_soon" ? "pill-soon" : "pill-filled"), L.status[j.status] || ""));
    c.appendChild(top);
    if (j.summary) c.appendChild(el("p", "soft", j.summary));
    var dl = el("dl");
    [[L.size_l, L.size[j.size_band]], [L.freq_l, L.freq[j.frequency]], [L.sched_l, L.sched[j.schedule]], [L.start_l, month(j.start_month)]].forEach(function (r) {
      if (!r[1]) return; dl.appendChild(el("dt", null, r[0])); dl.appendChild(el("dd", null, r[1]));
    });
    c.appendChild(dl);
    if (j.requirements && j.requirements.length) {
      var ul = el("ul", "job-req");
      j.requirements.forEach(function (r) { if (L.req[r]) ul.appendChild(el("li", "pill", L.req[r])); });
      c.appendChild(ul);
    }
    var foot = el("div", "job-foot");
    var left = el("span");
    left.appendChild(el("span", "ref", j.ref));
    if (j.applications_due_at && j.status !== "filled") left.appendChild(document.createTextNode(" · " + L.closes + " " + when(j.applications_due_at)));
    foot.appendChild(left);
    if (j.status === "filled") foot.appendChild(el("span", null, L.filled_note));
    else { var a = el("a", null, L.apply); a.href = JOIN; foot.appendChild(a); }
    c.appendChild(foot);
    return c;
  };

  var render = function () {
    if (!board) return;
    board.textContent = "";
    if (!items.length) { board.className = ""; board.appendChild(empty(L.none_t, L.none_b, true)); return; }
    var t = fType ? fType.value : "", s = fStatus ? fStatus.value : "";
    var shown = items.filter(function (j) { return (!t || j.facility_type === t) && (!s || j.status === s); });
    if (!shown.length) { board.className = ""; board.appendChild(empty(L.nomatch)); return; }
    board.className = "board";
    shown.forEach(function (j) { board.appendChild(card(j)); });
  };

  var fillFilters = function () {
    if (!fType || !fStatus) return;
    var types = {};
    items.forEach(function (j) { types[j.facility_type] = 1; });
    fType.appendChild(new Option(L.all_types, ""));
    Object.keys(types).sort().forEach(function (k) { fType.appendChild(new Option(L.facility[k] || k, k)); });
    fStatus.appendChild(new Option(L.all_status, ""));
    ["open", "closing_soon", "filled"].forEach(function (k) { fStatus.appendChild(new Option(L.status[k], k)); });
    fType.addEventListener("change", render); fStatus.addEventListener("change", render);
    document.getElementById("filters").hidden = items.length < 2;
  };

  var load = function () {
    if (!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY || !window.fetch) { render(); return; }
    var ctl = window.AbortController ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctl) ctl.abort(); }, 8000);
    fetch(cfg.SUPABASE_URL + "/rest/v1/rpc/contract_listings", {
      method: "POST", signal: ctl ? ctl.signal : undefined, credentials: "omit",
      headers: { apikey: cfg.SUPABASE_ANON_KEY, Authorization: "Bearer " + cfg.SUPABASE_ANON_KEY, "Content-Type": "application/json" },
      body: "{}"
    }).then(function (r) { return r.ok ? r.json() : []; }).then(function (rows) {
      items = Array.isArray(rows) ? rows.filter(function (j) { return j && j.ref && j.title && L.status[j.status]; }) : [];
    }).catch(function () { items = []; }).then(function () { clearTimeout(timer); fillFilters(); render(); });
  };
  load();

  // ── business request form (email app, no database) ──
  var form = document.getElementById("request-form");
  if (!form) return;
  var msg = form.querySelector(".form-msg"), started = Date.now();
  var say = function (text, kind) { msg.textContent = text; msg.className = "form-msg" + (kind ? " " + kind : ""); };
  var mark = function (n, bad) { if (bad) n.setAttribute("aria-invalid", "true"); else n.removeAttribute("aria-invalid"); };
  form.addEventListener("submit", function (e) {
    e.preventDefault();
    if (form.website.value) return;
    if (Date.now() - started < 2500) return;
    var f = form.elements, bad = [];
    ["business", "name"].forEach(function (k) { var v = f[k].value.trim(); mark(f[k], !v); if (!v) bad.push(f[k]); });
    var email = f.email.value.trim(), phone = f.phone.value.replace(/\D/g, "");
    mark(f.email, false); mark(f.phone, false);
    if (bad.length) { say(L.need, "bad"); bad[0].focus(); return; }
    if (!email && !phone) { mark(f.email, true); mark(f.phone, true); say(L.contact, "bad"); f.email.focus(); return; }
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) { mark(f.email, true); say(L.email, "bad"); f.email.focus(); return; }
    if (phone && !(phone.length === 10 || (phone.length === 11 && phone[0] === "1"))) { mark(f.phone, true); say(L.phone, "bad"); f.phone.focus(); return; }
    var line = function (k) { var n = f[k], v = n.value.trim(); return v ? n.getAttribute("data-label") + ": " + v : ""; };
    var body = [L.intro, ""].concat(["business", "name", "email", "phone", "city", "facility", "area", "frequency", "notes"].map(line).filter(Boolean)).join("\n");
    say(L.ok, "ok");
    window.location.href = "mailto:" + (cfg.BUSINESS_EMAIL || "wecleanitallfl@gmail.com") + "?subject=" +
      encodeURIComponent(L.subject + f.business.value.trim() + " (" + f.city.value + ")") + "&body=" + encodeURIComponent(body);
  });
})();
