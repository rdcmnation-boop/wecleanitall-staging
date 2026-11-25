// Contracts & Cleaning Jobs inside the app (staging). Provider screens: Opportunities, My applications, Credentials.
// Owner screen: Contracts & jobs (switches, listings, provider-visible lines, invites, applications, credentials).
// Every call goes through API.cc(), which only allows the marketplace functions. The database decides what each
// account may see; this file never filters private data itself.
(function () {
  "use strict";
  window.WCIA_CONTRACTS = function (X) {
    const { esc, icon, S, API } = X;
    const es = () => X.lang() === "es";
    const T = (en, sp) => (es() ? sp : en);
    const FAC = { office: ["Office", "Oficinas"], medical: ["Medical", "Centro médico"], retail: ["Retail / showroom", "Comercio / showroom"], warehouse: ["Warehouse", "Almacén"],
      school: ["School", "Escuela"], government: ["Public building", "Edificio público"], industrial: ["Industrial", "Industrial"], mixed: ["Mixed use", "Uso mixto"],
      residential_common: ["Common areas", "Áreas comunes"], other: ["Other", "Otro"] };
    const SIZE = { under_5k: ["Under 5,000 sq ft", "Menos de 5.000 pies²"], "5k_20k": ["5,000–20,000 sq ft", "5.000–20.000 pies²"], "20k_50k": ["20,000–50,000 sq ft", "20.000–50.000 pies²"],
      "50k_100k": ["50,000–100,000 sq ft", "50.000–100.000 pies²"], over_100k: ["Over 100,000 sq ft", "Más de 100.000 pies²"] };
    const FREQ = { daily: ["Daily", "Diario"], "6x_week": ["6× a week", "6 veces/semana"], weekdays: ["Weekdays", "Lunes a viernes"], "4x_week": ["4× a week", "4 veces/semana"],
      "3x_week": ["3× a week", "3 veces/semana"], "2x_week": ["2× a week", "2 veces/semana"], weekly: ["Weekly", "Semanal"], biweekly: ["Every two weeks", "Cada dos semanas"],
      monthly: ["Monthly", "Mensual"], quarterly: ["Quarterly", "Trimestral"], one_time: ["One time", "Una vez"], on_call: ["On call", "A pedido"] };
    const SCHED = { day: ["Daytime", "De día"], evening: ["Evening", "Tarde / noche"], overnight: ["Overnight", "Madrugada"], weekend: ["Weekends", "Fines de semana"], flexible: ["Flexible", "Flexible"] };
    const REQ = { general_liability: ["General liability insurance", "Seguro de responsabilidad civil"], workers_comp: ["Workers' comp", "Compensación laboral"],
      background_check: ["Background check", "Verificación de antecedentes"], business_license: ["Business license", "Licencia comercial"], own_equipment: ["Own equipment", "Equipo propio"],
      own_transport: ["Own transportation", "Transporte propio"], floor_care: ["Floor care", "Cuidado de pisos"], robot_operation: ["Robot operation", "Operación de robots"],
      bilingual: ["Bilingual", "Bilingüe"], night_availability: ["Night availability", "Disponible de noche"], experience_1y: ["1+ year experience", "1+ año de experiencia"],
      experience_3y: ["3+ years experience", "3+ años de experiencia"] };
    const LSTAT = { open: ["Open", "Abierta"], closing_soon: ["Closing soon", "Cierra pronto"], filled: ["Filled", "Cubierta"], closed: ["Closed", "Cerrada"] };
    const ASTAT = { draft: ["Draft", "Borrador"], submitted: ["Submitted", "Enviada"], under_review: ["Under review", "En revisión"], shortlisted: ["Shortlisted", "Preseleccionada"],
      selected: ["Selected", "Seleccionada"], declined: ["Not selected", "No seleccionada"], withdrawn: ["Withdrawn", "Retirada"] };
    const VIS = { internal: ["Internal (hidden)", "Interna (oculta)"], public_summary: ["Public summary", "Resumen público"], approved_only: ["Approved providers only", "Solo proveedores aprobados"],
      invite_only: ["Invite only", "Solo invitados"], marketplace: ["Approved providers only", "Solo proveedores aprobados"] };
    const INS = { general_liability: ["General liability", "Responsabilidad civil"], workers_comp: ["Workers' comp", "Compensación laboral"], bond: ["Bond", "Fianza"], auto: ["Auto", "Auto"] };
    const COMP = { background_check: ["Background check", "Verificación de antecedentes"], business_license: ["Business license", "Licencia comercial"], w9: ["W-9", "W-9"],
      contractor_agreement: ["Contractor agreement", "Acuerdo de contratista"], id_verification: ["ID verification", "Verificación de identidad"], other: ["Other", "Otro"] };
    const CSTAT = { submitted: ["Pending review", "En revisión"], verified: ["Verified", "Verificado"], rejected: ["Rejected", "Rechazado"], expired: ["Expired", "Vencido"] };
    const L = (m, k) => (m[k] ? m[k][es() ? 1 : 0] : k || "—");
    const ERR = {
      applications_disabled: ["Applications are not open yet.", "Las postulaciones aún no están abiertas."],
      credentials_disabled: ["Credential uploads are not open yet.", "La carga de credenciales aún no está abierta."],
      not_approved: ["Your provider account must be approved before you can send applications.", "Tu cuenta de proveedor debe estar aprobada para enviar postulaciones."],
      not_available: ["This opportunity is not available.", "Esta oportunidad no está disponible."], closed: ["This opportunity is closed.", "Esta oportunidad está cerrada."],
      outside_service_area: ["This work is outside your service area.", "Este trabajo está fuera de tu zona."], suspended_in_market: ["Your account is paused in this area.", "Tu cuenta está pausada en esta zona."],
      insurance_missing: ["A verified, current insurance certificate is required:", "Se requiere un certificado de seguro verificado y vigente:"],
      compliance_missing: ["A verified document is required:", "Se requiere un documento verificado:"],
      availability_required: ["Add your availability first.", "Primero escribe tu disponibilidad."], already_submitted: ["Already sent. Withdraw it first to change it.", "Ya la enviaste. Retírala primero para cambiarla."],
      too_many_open_applications: ["You have too many open applications.", "Tienes demasiadas postulaciones abiertas."], bad_input: ["Please check the fields.", "Revisa los campos."],
      bad_document_path: ["Upload the document again.", "Vuelve a subir el documento."], document_missing: ["The file did not arrive. Upload it again.", "El archivo no llegó. Vuelve a subirlo."],
      upload_failed: ["Upload refused or failed. Nothing was saved.", "La carga fue rechazada o falló. No se guardó nada."], bad_coverage: ["Check the coverage amount.", "Revisa el monto de cobertura."], expired: ["That date has already passed.", "Esa fecha ya pasó."],
      security_retest_required: ["Record the security retest before switching anything on.", "Registra la prueba de seguridad antes de activar algo."],
      public_text_has_numbers: ["Public text can't contain street numbers or ZIP codes.", "El texto público no puede tener números de calle ni códigos postales."],
      public_text_has_contact: ["Public text can't contain emails or links.", "El texto público no puede tener correos ni enlaces."],
      public_text_names_client: ["Public text names the client. Remove it.", "El texto público nombra al cliente. Quítalo."],
      public_text_names_incumbent: ["Public text names the current provider. Remove it.", "El texto público nombra al proveedor actual. Quítalo."],
      public_text_names_site: ["Public text names the site or address. Remove it.", "El texto público nombra el sitio o la dirección. Quítalo."],
      public_fields_required: ["An open listing needs a public title, area and facility type.", "Una publicación abierta necesita título público, zona y tipo de instalación."],
      opportunity_not_verified: ["Verify the opportunity before opening it.", "Verifica la oportunidad antes de abrirla."],
      bad_transition: ["That status change isn't allowed.", "Ese cambio de estado no está permitido."], provider_not_eligible: ["The provider doesn't meet the requirements:", "El proveedor no cumple los requisitos:"],
      contract_mismatch: ["That contract belongs to a different opportunity.", "Ese contrato es de otra oportunidad."],
      contract_not_open: ["That contract is not open (it must be onboarding, active or pending renewal).", "Ese contrato no está abierto (debe estar en incorporación, activo o por renovar)."],
      already_assigned: ["This provider already has a proposal or assignment on that contract.", "Este proveedor ya tiene una propuesta o asignación en ese contrato."], not_selected: ["Select the application first.", "Primero selecciona la postulación."],
      provider_not_approved: ["Only approved providers can be invited.", "Solo se puede invitar a proveedores aprobados."], note_required: ["Write what was tested (10+ characters).", "Escribe qué se probó (10+ caracteres)."],
      admin_only: ["Owner only (2-step verification required).", "Solo el dueño (requiere verificación en 2 pasos)."], demo: ["Not available in demo mode.", "No disponible en modo demo."]
    };
    const errText = (e) => {
      const m = String((e && (e.message || e.code)) || "");
      const keys = Object.keys(ERR);
      const k = keys.find((x) => m.indexOf(x) === 0) || keys.find((x) => m.indexOf(x) > -1);
      if (!k) return T("Something went wrong. Try again.", "Algo salió mal. Inténtalo de nuevo.");
      const tail = m.split(":")[1];
      return L(ERR, k) + (tail ? " " + (L(REQ, tail.trim()) || tail) : "");
    };
    const call = async (fn, args) => {
      if (!API.cc) throw new Error("demo");
      const r = await API.cc(fn, args || {});
      if (r === null && API.mode === "demo") throw new Error("demo");
      return r;
    };
    const say = (m, k) => X.toast(m, k);
    const busy = async (fn) => { if (S.busy) return; S.busy = true; try { return await fn(); } catch (e) { console.error(e); say(errText(e), "bad"); } finally { S.busy = false; } };
    const pill = (txt, cls) => '<span class="pill ' + (cls || "") + '">' + esc(txt) + "</span>";
    const tags = (arr) => '<p class="tags">' + arr.filter(Boolean).map((x) => "<span>" + esc(x) + "</span>").join("") + "</p>";
    const opt = (map, cur, blank) => (blank ? '<option value="">' + esc(blank) + "</option>" : "") + Object.keys(map).map((k) => '<option value="' + k + '"' + (k === cur ? " selected" : "") + ">" + esc(L(map, k)) + "</option>").join("");
    const fld = (name, label, type, val, attrs) => '<label class="field"><span>' + esc(label) + '</span><input name="' + name + '" type="' + type + '"' + (val != null && val !== "" ? ' value="' + esc(val) + '"' : "") + " " + (attrs || "") + "></label>";
    const sel = (name, label, inner) => '<label class="field"><span>' + esc(label) + '</span><select name="' + name + '">' + inner + "</select></label>";
    const area = (name, label, val, max) => '<label class="field"><span>' + esc(label) + '</span><textarea name="' + name + '" maxlength="' + max + '" rows="3">' + esc(val || "") + "</textarea></label>";
    const month = (d) => { if (!d) return ""; const p = String(d).split("-"); return new Date(+p[0], +p[1] - 1, 1).toLocaleDateString(es() ? "es-US" : "en-US", { month: "long", year: "numeric" }); };
    const isoLocal = (v) => { if (!v) return ""; const d = new Date(v); return isNaN(d) ? "" : d.toISOString(); };
    const toLocalInput = (iso) => { if (!iso) return ""; const d = new Date(iso); const p = (n) => String(n).padStart(2, "0"); return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "T" + p(d.getHours()) + ":" + p(d.getMinutes()); };
    const tier = () => { const w = S.me && S.me.worker; return !w ? "none" : w.status === "approved" ? "approved" : w.status === "pending" ? "registered" : "blocked"; };

    // ───────── data ─────────
    const loaders = {
      opps: async () => ({ cc: await call("provider_contract_listings").catch((e) => ({ error: errText(e) })) }),
      myapps: async () => ({ cc: await call("my_contract_applications").catch((e) => ({ error: errText(e) })) }),
      creds: async () => {
        const [cc, st] = await Promise.all([call("my_provider_credentials").catch((e) => ({ error: errText(e) })), call("provider_marketplace_status").catch(() => null)]);
        return { cc, ccStatus: st };
      },
      cc: async () => {
        const [flags, list, creds, orphans] = await Promise.all([call("admin_marketplace_flags"), call("admin_contract_listings"), call("admin_pending_provider_credentials"),
          call("admin_orphan_credential_files")].map((p) => p.catch((e) => ({ error: errText(e) }))));
        return { flags, list, creds, orphans };
      }
    };

    // ───────── provider: opportunities ─────────
    function oppCard(j) {
      const a = j.application, open = S.ccOpen === j.ref;
      const head = '<div class="row between"><div><b>' + esc(j.title) + "</b><small>" + esc(j.area + " · " + L(FAC, j.facility_type)) + " · " + esc(j.ref) + "</small></div>" +
        pill(L(LSTAT, j.status), j.status === "open" ? "st-approved" : j.status === "closing_soon" ? "st-pending" : "") + "</div>";
      const meta = tags([j.size_band && L(SIZE, j.size_band), j.frequency && L(FREQ, j.frequency), j.schedule && L(SCHED, j.schedule),
        j.start_month && T("Starts ", "Inicia ") + month(j.start_month), j.applications_due_at && T("Closes ", "Cierra ") + X.when(j.applications_due_at),
        j.access === "invite" && T("Invited", "Invitado")]);
      const req = (j.requirements || []).length ? '<p class="tags soft">' + j.requirements.map((r) => "<span>" + esc(L(REQ, r)) + "</span>").join("") + "</p>" : "";
      const details = (j.requirement_details || []).length ? '<p class="label">' + esc(T("Requirements", "Requisitos")) + '</p><ul class="cc-list">' +
        j.requirement_details.map((r) => "<li>" + esc(r.requirement) + (r.mandatory ? "" : " <small>(" + esc(T("preferred", "preferible")) + ")</small>") + "</li>").join("") + "</ul>" : "";
      const scope = (j.scope || []).length ? '<p class="label">' + esc(T("Scope", "Alcance")) + '</p><ul class="cc-list">' +
        j.scope.map((s) => "<li>" + esc(s.task + " · " + L(FREQ, s.frequency) + (s.quantity ? " · " + Number(s.quantity).toLocaleString() + " " + s.unit : "")) + "</li>").join("") + "</ul>" : "";
      const sites = (j.sites || []).length ? '<p class="label">' + esc(T("Site", "Sitio")) + "</p>" + j.sites.map((s) => tags([s.city, s.zip, L(FAC, s.building_type),
        s.sqft && Number(s.sqft).toLocaleString() + T(" sq ft", " pies²"), s.floors && s.floors + T(" floors", " pisos"), s.restrooms && s.restrooms + T(" restrooms", " baños")])).join("") +
        '<p class="fine">' + esc(T("The exact address and client are shared with the selected provider after approval.", "La dirección exacta y el cliente se comparten con el proveedor seleccionado tras la aprobación.")) + "</p>" : "";
      const block = j.block_reason ? '<p class="fine warn">' + esc(errText({ message: j.block_reason })) + (/insurance|compliance/.test(j.block_reason) ? ' <button class="link-btn" data-act="tab" data-tab="creds">' + esc(T("Upload credentials", "Subir credenciales")) + "</button>" : "") + "</p>" : "";
      const st = a ? '<p class="row gap">' + pill(L(ASTAT, a.status), "st-" + (a.status === "selected" ? "approved" : a.status === "declined" || a.status === "withdrawn" ? "rejected" : "pending")) +
        (a.submitted_at ? "<small>" + esc(T("Sent ", "Enviada ") + X.when(a.submitted_at)) + "</small>" : "") + "</p>" : "";
      const canEdit = (!a || a.status === "draft" || a.status === "withdrawn") && j.status !== "filled";
      const actions = '<div class="row gap wrap-row">' +
        (canEdit ? '<button class="btn ' + (a ? "ghost" : "solid") + ' small" data-act="cc-open" data-ref="' + esc(j.ref) + '">' + esc(a && a.status === "draft" ? T("Edit draft", "Editar borrador") : T("Prepare application", "Preparar postulación")) + "</button>" : "") +
        (a && a.status === "draft" && tier() === "approved" && !j.block_reason ? '<button class="btn solid small" data-act="cc-send" data-ref="' + esc(j.ref) + '">' + esc(T("Send application", "Enviar postulación")) + "</button>" : "") +
        (a && ["draft", "submitted", "under_review", "shortlisted"].includes(a.status) ? '<button class="btn ghost small" data-act="cc-withdraw" data-ref="' + esc(j.ref) + '">' + esc(T("Withdraw", "Retirar")) + "</button>" : "") + "</div>";
      const form = open ? '<form class="stack cc-form" data-form="cc-app" data-ref="' + esc(j.ref) + '" novalidate>' +
        area("availability", T("Your availability (days and hours)", "Tu disponibilidad (días y horas)"), a && a.availability, 500) +
        '<div class="grid2">' + fld("crew_size", T("Crew size", "Tamaño del equipo"), "number", a && a.crew_size, 'min="1" max="500"') +
        fld("can_start_on", T("Can start on", "Puedo empezar el"), "date", a && a.can_start_on) +
        fld("proposed_rate", T("Your price (optional)", "Tu precio (opcional)"), "number", a && a.proposed_rate, 'min="0" step="0.01"') +
        sel("rate_basis", T("Per", "Por"), opt({ monthly: ["Month", "Mes"], hourly: ["Hour", "Hora"], per_visit: ["Visit", "Visita"] }, (a && a.rate_basis) || "monthly")) + "</div>" +
        '<label class="switch-row"><span>' + esc(T("I have operated cleaning robots", "He operado robots de limpieza")) + '</span><input type="checkbox" role="switch" name="robot_experience"' + (a && a.robot_experience ? " checked" : "") + "><i aria-hidden=\"true\"></i></label>" +
        area("message", T("Message to WCIA (optional)", "Mensaje para WCIA (opcional)"), a && a.message, 1500) +
        '<button class="btn solid" type="submit">' + esc(T("Save draft", "Guardar borrador")) + "</button>" +
        '<p class="fine">' + esc(tier() === "approved" ? T("Save, then tap Send application. Applying does not guarantee work.", "Guarda y luego toca Enviar postulación. Postularte no garantiza trabajo.")
          : T("You can send it once your account is approved.", "Podrás enviarla cuando tu cuenta esté aprobada.")) + "</p></form>" : "";
      return '<article class="card cc">' + head + meta + req + (j.summary ? '<p class="bio">' + esc(j.summary) + "</p>" : "") + details + scope + sites + block + st + actions + form + "</article>";
    }
    function vOpps() {
      const d = S.data.cc;
      const top = '<h1 class="title">' + esc(T("Opportunities", "Oportunidades")) + "</h1>" +
        (tier() === "registered" ? '<p class="banner warn">' + esc(T("Your account is waiting for approval. You can see requirements and prepare drafts now.", "Tu cuenta espera aprobación. Ya puedes ver requisitos y preparar borradores.")) + "</p>" : "") +
        '<p class="fine">' + esc(T("A listing is not a contract. Work starts only after selection, a signed agreement and an approved work order.", "Una publicación no es un contrato. El trabajo empieza solo tras la selección, un acuerdo firmado y una orden de trabajo aprobada.")) + "</p>";
      if (S.data.loading && !d) return top + X.loading();
      if (d && d.error) return top + X.empty("file", d.error);
      if (!d || !d.length) return top + X.empty("file", T("No open opportunities right now", "No hay oportunidades abiertas ahora"), T("We'll notify you when new work is published.", "Te avisaremos cuando publiquemos trabajo nuevo."));
      return top + d.map(oppCard).join("");
    }
    function vMyApps() {
      const d = S.data.cc, top = '<h1 class="title">' + esc(T("My applications", "Mis postulaciones")) + "</h1>";
      if (S.data.loading && !d) return top + X.loading();
      if (d && d.error) return top + X.empty("list", d.error);
      if (!d || !d.length) return top + X.empty("list", T("No applications yet", "Aún no tienes postulaciones"), "", '<button class="btn solid" data-act="tab" data-tab="opps">' + esc(T("See opportunities", "Ver oportunidades")) + "</button>");
      return top + d.map((a) => '<article class="card"><div class="row between"><div><b>' + esc(a.title || a.ref) + "</b><small>" + esc((a.area || "") + " · " + a.ref) + "</small></div>" +
        pill(L(ASTAT, a.status), "st-" + (a.status === "selected" ? "approved" : a.status === "declined" || a.status === "withdrawn" ? "rejected" : "pending")) + "</div>" +
        tags([a.submitted_at && T("Sent ", "Enviada ") + X.when(a.submitted_at), T("Listing: ", "Publicación: ") + L(LSTAT, a.listing_status), a.assigned && T("Assignment proposed", "Asignación propuesta")]) + "</article>").join("");
    }
    function vCreds() {
      const d = S.data.cc, top = '<h1 class="title">' + esc(T("Credentials", "Credenciales")) + "</h1>" +
        '<p class="fine">' + esc(T("Upload your insurance certificate and documents. Our team verifies them before they count toward an application.", "Sube tu certificado de seguro y documentos. Nuestro equipo los verifica antes de que cuenten para una postulación.")) + "</p>";
      if (S.data.loading && !d) return top + X.loading();
      if (d && d.error) return top + X.empty("shield", d.error);
      const row = (name, c) => '<li class="row between"><span>' + esc(name) + (c.expires_on ? " · " + esc(T("expires ", "vence ") + c.expires_on) : "") + "</span>" + pill(L(CSTAT, c.status), "st-" + (c.status === "verified" ? "approved" : c.status === "submitted" ? "pending" : "rejected")) + "</li>";
      const list = (d && (d.insurance.length || d.compliance.length)) ? '<ul class="cc-list plain">' + d.insurance.map((c) => row(L(INS, c.kind) + (c.carrier ? " · " + c.carrier : ""), c)).join("") + d.compliance.map((c) => row(L(COMP, c.requirement), c)).join("") + "</ul>"
        : '<p class="muted">' + esc(T("Nothing uploaded yet.", "Aún no has subido nada.")) + "</p>";
      const f1 = '<form class="card stack" data-form="cc-ins" novalidate><p class="label">' + icon("shield") + esc(T("Insurance certificate", "Certificado de seguro")) + "</p>" +
        '<div class="grid2">' + sel("kind", T("Type", "Tipo"), opt(INS, "general_liability")) + fld("carrier", T("Insurance company", "Aseguradora"), "text", "", 'maxlength="120" required') +
        fld("policy_number", T("Policy number", "Número de póliza"), "text", "", 'maxlength="80"') + fld("coverage_usd", T("Coverage ($)", "Cobertura ($)"), "number", "", 'min="1" required') +
        fld("starts_on", T("Starts", "Inicio"), "date", "") + fld("expires_on", T("Expires", "Vence"), "date", "", "required") + "</div>" +
        fld("file", T("Certificate (PDF or photo)", "Certificado (PDF o foto)"), "file", "", 'accept=".pdf,image/*" required') +
        '<button class="btn solid" type="submit">' + esc(T("Upload for review", "Subir para revisión")) + "</button></form>";
      const f2 = '<form class="card stack" data-form="cc-comp" novalidate><p class="label">' + icon("file") + esc(T("Other documents", "Otros documentos")) + "</p>" +
        '<div class="grid2">' + sel("requirement", T("Document", "Documento"), opt(COMP, "business_license")) + fld("expires_on", T("Expires (if any)", "Vence (si aplica)"), "date", "") + "</div>" +
        fld("file", T("File (PDF or photo)", "Archivo (PDF o foto)"), "file", "", 'accept=".pdf,image/*" required') +
        '<button class="btn solid" type="submit">' + esc(T("Upload for review", "Subir para revisión")) + "</button></form>";
      // Upload forms only when the database says this provider may upload right now (approved + switch on).
      // The storage rule and the database refuse anyway; hiding the forms avoids a refused upload.
      const st = S.data.ccStatus;
      const closed = '<p class="banner warn">' + esc(!st ? T("Uploads are not available right now.", "La carga no está disponible ahora.")
        : st.upload_block_reason === "not_approved" ? T("You can upload credentials once your provider account is approved. For approval, use the documents section of your profile.", "Podrás subir credenciales cuando tu cuenta de proveedor esté aprobada. Para la aprobación, usa la sección de documentos de tu perfil.")
        : T("Credential uploads are not open yet.", "La carga de credenciales aún no está abierta.")) + "</p>";
      return top + '<article class="card">' + list + "</article>" + (st && st.uploads ? f1 + f2 : closed);
    }

    // ───────── owner ─────────
    function vOwner() {
      const d = S.data, top = '<h1 class="title">' + esc(T("Contracts & jobs", "Contratos y trabajos")) + "</h1>";
      if (d.loading && !d.list) return top + X.loading();
      const f = d.flags || {};
      if (f.error) return top + X.empty("shield", f.error);
      const sw = (k, label) => '<label class="switch-row"><span>' + esc(label) + '</span><input type="checkbox" role="switch" name="' + k + '"' + (f[k] ? " checked" : "") + '><i aria-hidden="true"></i></label>';
      const flags = '<form class="card stack" data-form="cc-flags" novalidate><p class="label">' + icon("plug") + esc(T("Switches (all off until you turn them on)", "Interruptores (todo apagado hasta que los actives)")) + "</p>" +
        sw("public_listings", T("Public board on the website", "Tablero público en la web")) + sw("provider_listings", T("Provider opportunities + credential uploads", "Oportunidades para proveedores + carga de credenciales")) +
        sw("applications", T("Provider applications", "Postulaciones de proveedores")) + sw("show_test_listings", T("Show TEST listings (staging only)", "Mostrar publicaciones TEST (solo staging)")) +
        '<p class="fine">' + esc(f.security_retest_passed_at ? T("Security retest recorded ", "Prueba de seguridad registrada ") + X.when(f.security_retest_passed_at) + " · " + (f.security_retest_note || "")
          : T("No security retest recorded yet. Switches stay off until you record one.", "Aún no hay prueba de seguridad registrada. Los interruptores siguen apagados hasta registrarla.")) + "</p>" +
        '<button class="btn solid" type="submit">' + esc(T("Save switches", "Guardar interruptores")) + "</button></form>" +
        (f.security_retest_passed_at ? "" : '<form class="card stack" data-form="cc-retest" novalidate><p class="label">' + icon("shield") + esc(T("Record security retest", "Registrar prueba de seguridad")) + "</p>" +
          area("note", T("What was tested and by whom", "Qué se probó y quién lo probó"), "", 1000) + '<button class="btn ghost" type="submit">' + esc(T("Record retest", "Registrar prueba")) + "</button></form>");
      const list = d.list && !d.list.error ? d.list : [];
      const cards = list.length ? list.map(ownerCard).join("") : X.empty("file", T("No opportunities in the Contract Center yet", "Aún no hay oportunidades en el Contract Center"));
      const orph = d.orphans && !d.orphans.error && d.orphans.length ? '<p class="banner warn">' + esc(T("Credential files without a record: ", "Archivos de credenciales sin registro: ") + d.orphans.length + T(". Review them in Supabase Storage (worker-docs).", ". Revísalos en Supabase Storage (worker-docs).")) + "</p>" : "";
      return top + flags + orph + credsCard(d.creds) + '<h2 class="sub">' + esc(T("Opportunities", "Oportunidades")) + "</h2>" + cards;
    }
    function ownerCard(o) {
      const n = o.applications || {}, sum = Object.keys(n).reduce((s, k) => s + n[k], 0);
      const head = '<div class="row between"><div><b>' + esc(o.title) + "</b><small>" + esc(o.code + " · " + o.ref + " · " + o.status + " · " + o.verification_status + (o.is_test ? " · TEST" : "")) + "</small></div>" +
        pill(L(VIS, o.visibility) + (o.visibility !== "internal" ? " · " + L(LSTAT, o.public_status) : ""), o.visibility === "internal" ? "" : "st-approved") + "</div>" +
        (o.public_title ? '<p class="fine">' + esc(T("Public: ", "Público: ") + o.public_title + " · " + (o.public_area || "")) + "</p>" : "");
      const btns = '<div class="row gap wrap-row"><button class="btn ghost small" data-act="cc-edit" data-id="' + o.id + '">' + esc(S.ccEdit === o.id ? T("Close", "Cerrar") : T("Edit listing", "Editar publicación")) + "</button>" +
        '<button class="btn ghost small" data-act="cc-apps" data-id="' + o.id + '">' + esc(T("Applications", "Postulaciones") + " (" + sum + ")") + "</button></div>";
      return '<article class="card cc">' + head + btns + (S.ccEdit === o.id ? editForm(o) : "") + (S.ccAppsFor === o.id ? appsPanel(o) : "") + "</article>";
    }
    function editForm(o) {
      const lines = (S.ccLines || {})[o.id];
      const reqChecks = Object.keys(REQ).map((k) => '<label class="chip"><input type="checkbox" name="public_requirements" value="' + k + '"' + ((o.public_requirements || []).includes(k) ? " checked" : "") + "><span>" + esc(L(REQ, k)) + "</span></label>").join("");
      const lineRow = (kind, x, text) => '<p class="row between gap"><span>' + esc(text) + '</span><button class="btn ' + (x.provider_visible ? "solid" : "ghost") + ' small" data-act="cc-line" data-kind="' + kind + '" data-id="' + x.id + '" data-o="' + o.id + '" data-v="' + (x.provider_visible ? "0" : "1") + '">' +
        esc(x.provider_visible ? T("Visible", "Visible") : T("Hidden", "Oculta")) + "</button></p>";
      const linesHtml = !lines ? X.loading() : '<p class="label">' + esc(T("Lines providers may see (registered: requirements; approved: + scope)", "Líneas que ven los proveedores (registrados: requisitos; aprobados: + alcance)")) + "</p>" +
        (lines.requirements.map((r) => lineRow("requirement", r, "[" + r.category + "] " + r.requirement)).join("") || '<p class="muted">—</p>') +
        lines.scope.map((s) => lineRow("scope", s, "[" + s.area + "] " + s.task + " · " + L(FREQ, s.frequency))).join("") +
        (o.visibility === "invite_only" ? '<p class="label">' + esc(T("Invited providers", "Proveedores invitados")) + "</p>" + (lines.invites.map((i) => '<p class="row between"><span>' + esc(i.name) + '</span><button class="btn ghost small" data-act="cc-uninvite" data-id="' + o.id + '" data-w="' + i.worker_id + '">' + esc(T("Remove", "Quitar")) + "</button></p>").join("") || '<p class="muted">—</p>') +
          '<form class="row gap" data-form="cc-invite" data-id="' + o.id + '" novalidate><select name="worker">' + (S.ccWorkers || []).filter((w) => w.status === "approved").map((w) => '<option value="' + w.id + '">' + esc(w.full_name + (w.company_name ? " · " + w.company_name : "")) + "</option>").join("") +
          '</select><button class="btn ghost small" type="submit">' + esc(T("Invite", "Invitar")) + "</button></form>" : "");
      return '<form class="stack cc-form" data-form="cc-publish" data-id="' + o.id + '" novalidate>' +
        '<p class="fine warn">' + esc(T("Public text: no client or site names, no addresses, numbers, emails or links. The database refuses them.", "Texto público: sin nombres de cliente o sitio, direcciones, números, correos ni enlaces. La base de datos los rechaza.")) + "</p>" +
        '<div class="grid2">' + sel("visibility", T("Who can see it", "Quién la ve"), opt({ internal: VIS.internal, public_summary: VIS.public_summary, approved_only: VIS.approved_only, invite_only: VIS.invite_only }, o.visibility === "marketplace" ? "approved_only" : o.visibility)) +
        sel("listing_status", T("Listing status", "Estado"), opt({ draft: ["Draft", "Borrador"], open: ["Open", "Abierta"], filled: ["Filled", "Cubierta"], closed: ["Closed", "Cerrada"] }, o.listing_status)) + "</div>" +
        fld("public_title", T("Public title", "Título público"), "text", o.public_title, 'maxlength="120"') + area("public_summary", T("Public summary", "Resumen público"), o.public_summary, 600) +
        '<div class="grid2">' + fld("public_area", T("General area (e.g. Sunrise, FL)", "Zona general (ej. Sunrise, FL)"), "text", o.public_area, 'maxlength="80"') +
        sel("public_facility_type", T("Facility type", "Tipo de instalación"), opt(FAC, o.public_facility_type, "—")) + sel("public_size_band", T("Size", "Tamaño"), opt(SIZE, o.public_size_band, "—")) +
        sel("public_frequency", T("Frequency", "Frecuencia"), opt(FREQ, o.public_frequency, "—")) + sel("public_schedule", T("Schedule", "Horario"), opt(SCHED, o.public_schedule, "—")) +
        fld("public_start_month", T("Start month", "Mes de inicio"), "month", o.public_start_month ? String(o.public_start_month).slice(0, 7) : "") +
        fld("applications_due_at", T("Applications close (24h)", "Cierre de postulaciones (24h)"), "datetime-local", toLocalInput(o.applications_due_at)) + "</div>" +
        '<p class="label">' + esc(T("Public requirements", "Requisitos públicos")) + '</p><div class="chips">' + reqChecks + "</div>" +
        '<button class="btn solid" type="submit">' + esc(T("Save listing", "Guardar publicación")) + "</button></form>" + linesHtml;
    }
    function appsPanel(o) {
      const apps = (S.ccApps || {})[o.id];
      if (!apps) return X.loading();
      if (!apps.length) return '<p class="muted">' + esc(T("No applications yet.", "Aún no hay postulaciones.")) + "</p>";
      const dec = (a, s, label, solid) => '<button class="btn ' + (solid ? "solid" : "ghost") + ' small" data-act="cc-decide" data-id="' + a.id + '" data-o="' + o.id + '" data-s="' + s + '">' + esc(label) + "</button>";
      return apps.map((a) => {
        const next = { submitted: [["under_review", T("Review", "Revisar")], ["shortlisted", T("Shortlist", "Preseleccionar")], ["declined", T("Decline", "Rechazar")]],
          under_review: [["shortlisted", T("Shortlist", "Preseleccionar")], ["selected", T("Select", "Seleccionar"), 1], ["declined", T("Decline", "Rechazar")]],
          shortlisted: [["selected", T("Select", "Seleccionar"), 1], ["under_review", T("Back to review", "Volver a revisión")], ["declined", T("Decline", "Rechazar")]],
          selected: a.assignment_id ? [] : [["declined", T("Undo selection", "Deshacer selección")]] }[a.status] || [];
        const assign = a.status === "selected" && !a.assignment_id ? (a.contract_id ? '<form class="row gap wrap-row" data-form="cc-assign" data-id="' + a.id + '" data-c="' + a.contract_id + '" data-o="' + o.id + '" novalidate>' +
          '<select name="pay_basis">' + opt({ monthly: ["Monthly", "Mensual"], hourly: ["Hourly", "Por hora"], per_visit: ["Per visit", "Por visita"] }, a.rate_basis || "monthly") + "</select>" +
          '<input name="pay_rate" type="number" min="0" step="0.01" required placeholder="$" value="' + esc(a.proposed_rate || "") + '"><input name="start_date" type="date">' +
          '<button class="btn solid small" type="submit">' + esc(T("Propose assignment", "Proponer asignación")) + "</button></form>" +
          '<p class="fine">' + esc(T("Creates a PROPOSED assignment on the signed contract and sends an approval request to your Contract Center approvals queue. Nothing is active until you approve it there. No payment is made.", "Crea una asignación PROPUESTA en el contrato firmado y envía una solicitud a tu cola de aprobaciones del Contract Center. Nada queda activo hasta que la apruebes allí. No se hace ningún pago.")) + "</p>"
          : '<p class="fine warn">' + esc(T("No signed contract for this opportunity yet. Record the award and contract in the Contract Center first.", "Aún no hay contrato firmado para esta oportunidad. Registra primero la adjudicación y el contrato en el Contract Center.")) + "</p>") : "";
        return '<div class="cc-app"><div class="row between"><div><b>' + esc(a.name + (a.company_name ? " · " + a.company_name : "")) + "</b><small>" + esc(a.kind + " · " + a.provider_status + (a.rating_count ? " · " + Number(a.rating_avg).toFixed(1) + "★ (" + a.rating_count + ")" : "") + " · " + T("jobs ", "trabajos ") + a.jobs_done) + "</small></div>" +
          pill(L(ASTAT, a.status), "st-" + (a.status === "selected" ? "approved" : a.status === "declined" ? "rejected" : "pending")) + "</div>" +
          tags([a.availability, a.crew_size && T("Crew ", "Equipo ") + a.crew_size, a.proposed_rate != null && X.money(a.proposed_rate) + " / " + (a.rate_basis || ""), a.can_start_on && T("Start ", "Inicio ") + a.can_start_on, a.robot_experience && T("Robot experience", "Experiencia con robots")]) +
          tags((a.verified_insurance || []).map((k) => "✓ " + L(INS, k)).concat((a.verified_compliance || []).map((k) => "✓ " + L(COMP, k)))) +
          (a.message ? '<p class="bio">' + esc(a.message) + "</p>" : "") +
          (a.block_reason && a.block_reason !== "closed" ? '<p class="fine warn">' + esc(errText({ message: a.block_reason })) + "</p>" : "") +
          (a.decision_note ? '<p class="fine">' + esc(T("Internal note: ", "Nota interna: ") + a.decision_note) + "</p>" : "") +
          (a.assignment_id ? '<p class="fine">' + esc(T("Assignment proposed: waiting for your decision in the Contract Center approvals queue.", "Asignación propuesta: espera tu decisión en la cola de aprobaciones del Contract Center.")) + "</p>" : "") +
          '<div class="row gap wrap-row">' + next.map(([s, label, solid]) => dec(a, s, label, solid)).join("") + "</div>" + assign + "</div>";
      }).join("");
    }
    function credsCard(c) {
      if (!c || c.error || (!c.insurance.length && !c.compliance.length)) return "";
      const row = (kind, x, name) => '<div class="row between wrap-row"><span>' + esc(x.name + " · " + name + (x.coverage_usd ? " · " + X.money(x.coverage_usd) : "") + (x.expires_on ? " · " + T("exp. ", "vence ") + x.expires_on : "")) + "</span>" +
        '<span class="row gap">' + (x.document_path ? '<button class="btn ghost small" data-act="cc-doc" data-path="' + esc(x.document_path) + '">' + icon("file") + esc(T("View", "Ver")) + "</button>" : "") +
        '<button class="btn solid small" data-act="cc-verify" data-kind="' + kind + '" data-id="' + x.id + '" data-s="verified">' + esc(T("Verify", "Verificar")) + "</button>" +
        '<button class="btn ghost small" data-act="cc-verify" data-kind="' + kind + '" data-id="' + x.id + '" data-s="rejected">' + esc(T("Reject", "Rechazar")) + "</button></span></div>";
      return '<article class="card stack"><p class="label">' + icon("shield") + esc(T("Credentials waiting for review", "Credenciales por revisar")) + "</p>" +
        c.insurance.map((x) => row("insurance", x, L(INS, x.kind) + (x.carrier ? " (" + x.carrier + ")" : ""))).join("") + c.compliance.map((x) => row("compliance", x, L(COMP, x.requirement))).join("") + "</article>";
    }

    // ───────── actions ─────────
    const reloadApps = async (opp) => { S.ccApps = Object.assign({}, S.ccApps, { [opp]: await call("admin_listing_applications", { p_opp: opp }) }); X.render(); };
    const reloadLines = async (opp) => { S.ccLines = Object.assign({}, S.ccLines, { [opp]: await call("admin_listing_lines", { p_opp: opp }) }); X.render(); };
    async function onClick(a, el) {
      if (a === "cc-open") { S.ccOpen = S.ccOpen === el.dataset.ref ? null : el.dataset.ref; X.render(); return true; }
      if (a === "cc-send") { await busy(async () => { await call("submit_contract_application", { p_ref: el.dataset.ref }); say(T("Application sent", "Postulación enviada")); await X.loadTab(true); }); return true; }
      if (a === "cc-withdraw") { if (!window.confirm(T("Withdraw this application?", "¿Retirar esta postulación?"))) return true; await busy(async () => { await call("withdraw_contract_application", { p_ref: el.dataset.ref }); say(T("Withdrawn", "Retirada")); await X.loadTab(true); }); return true; }
      if (a === "cc-edit") { const id = el.dataset.id; S.ccEdit = S.ccEdit === id ? null : id; X.render(); if (S.ccEdit) await busy(async () => { if (!S.ccWorkers) S.ccWorkers = await API.adminWorkers().catch(() => []); await reloadLines(id); }); return true; }
      if (a === "cc-apps") { const id = el.dataset.id; S.ccAppsFor = S.ccAppsFor === id ? null : id; X.render(); if (S.ccAppsFor) await busy(() => reloadApps(id)); return true; }
      if (a === "cc-decide") {
        const s = el.dataset.s, note = s === "declined" || s === "selected" ? window.prompt(T("Internal note (optional, never shown to the provider)", "Nota interna (opcional, el proveedor no la ve)"), "") : "";
        if (note === null) return true;
        await busy(async () => { await call("admin_decide_application", { p_app: el.dataset.id, p_status: s, p_note: note || "" }); say(T("Saved", "Guardado")); await reloadApps(el.dataset.o); }); return true;
      }
      if (a === "cc-line") { await busy(async () => { await call("admin_set_listing_line_visibility", { p_kind: el.dataset.kind, p_id: el.dataset.id, p_visible: el.dataset.v === "1" }); await reloadLines(el.dataset.o); }); return true; }
      if (a === "cc-uninvite") { await busy(async () => { await call("admin_invite_provider", { p_opp: el.dataset.id, p_worker: el.dataset.w, p_invite: false }); await reloadLines(el.dataset.id); }); return true; }
      if (a === "cc-verify") { await busy(async () => { await call("admin_verify_provider_credential", { p_kind: el.dataset.kind, p_id: Number(el.dataset.id), p_status: el.dataset.s }); say(T("Saved", "Guardado")); await X.loadTab(true); }); return true; }
      if (a === "cc-doc") { const u = await API.docUrl(el.dataset.path).catch(() => null); if (u) window.open(u, "_blank", "noopener"); else say(T("Can't open the file", "No se puede abrir el archivo"), "bad"); return true; }
      return false;
    }
    async function onSubmit(kind, d, form) {
      const num = (v) => (v === "" || v == null ? null : Number(v));
      if (kind === "cc-app") {
        await busy(async () => {
          await call("save_contract_application", { p_ref: form.dataset.ref, p: { availability: (d.availability || "").trim(), crew_size: num(d.crew_size), proposed_rate: num(d.proposed_rate),
            rate_basis: d.rate_basis || null, can_start_on: d.can_start_on || null, robot_experience: !!d.robot_experience, message: (d.message || "").trim() } });
          say(T("Draft saved", "Borrador guardado")); S.ccOpen = null; await X.loadTab(true);
        });
      } else if (kind === "cc-ins" || kind === "cc-comp") {
        const file = form.querySelector('input[type="file"]').files[0];
        if (!file) { say(T("Choose a file", "Elige un archivo"), "bad"); return; }
        if (file.size > 10 * 1024 * 1024) { say(T("File is larger than 10 MB", "El archivo pesa más de 10 MB"), "bad"); return; }
        await busy(async () => {
          // 1) the database checks permission and every field before any file is sent
          const ins = kind === "cc-ins";
          await call("provider_credential_precheck", { p_type: ins ? "insurance" : "compliance", p_kind: ins ? d.kind : d.requirement,
            p_coverage_usd: ins ? num(d.coverage_usd) : null, p_expires_on: d.expires_on || null });
          // 2) upload into the guarded credentials folder (the storage rule refuses it unless allowed)
          const path = await API.uploadDoc(S.me.profile.id, file, "credentials");
          // 3) record it; if the record is refused, remove the file so nothing is left behind
          try {
            if (ins) await call("submit_provider_insurance", { p_kind: d.kind, p_carrier: d.carrier, p_policy_number: d.policy_number, p_coverage_usd: num(d.coverage_usd), p_starts_on: d.starts_on || null, p_expires_on: d.expires_on || null, p_document_path: path });
            else await call("submit_provider_compliance", { p_requirement: d.requirement, p_expires_on: d.expires_on || null, p_document_path: path });
          } catch (e) { await API.deleteDoc(path).catch(() => false); throw e; }
          say(T("Sent for review", "Enviado para revisión")); await X.loadTab(true);
        });
      } else if (kind === "cc-flags") {
        await busy(async () => { await call("admin_set_marketplace_flags", { p_public: !!d.public_listings, p_provider: !!d.provider_listings, p_applications: !!d.applications, p_show_test: !!d.show_test_listings }); say(T("Saved", "Guardado")); await X.loadTab(true); });
      } else if (kind === "cc-retest") {
        await busy(async () => { await call("admin_record_security_retest", { p_note: (d.note || "").trim() }); say(T("Retest recorded", "Prueba registrada")); await X.loadTab(true); });
      } else if (kind === "cc-publish") {
        const p = Object.assign({}, d, { public_requirements: [].concat(d.public_requirements || []), public_start_month: d.public_start_month ? d.public_start_month + "-01" : "", applications_due_at: isoLocal(d.applications_due_at) });
        await busy(async () => { await call("admin_publish_listing", { p_opp: form.dataset.id, p }); say(T("Listing saved", "Publicación guardada")); await X.loadTab(true); });
      } else if (kind === "cc-invite") {
        if (!d.worker) return;
        await busy(async () => { await call("admin_invite_provider", { p_opp: form.dataset.id, p_worker: d.worker, p_invite: true }); await reloadLines(form.dataset.id); });
      } else if (kind === "cc-assign") {
        await busy(async () => { await call("admin_application_to_assignment", { p_app: form.dataset.id, p_contract: form.dataset.c, p_role: "subcontractor", p_pay_basis: d.pay_basis, p_pay_rate: num(d.pay_rate), p_start_date: d.start_date || null });
          say(T("Assignment proposed", "Asignación propuesta")); await reloadApps(form.dataset.o); });
      } else return false;
      return true;
    }
    return { loaders, views: { opps: vOpps, myapps: vMyApps, creds: vCreds, cc: vOwner }, onClick, onSubmit };
  };
})();
