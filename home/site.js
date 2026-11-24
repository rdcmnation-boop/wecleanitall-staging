// Commercial homepage behaviour: phone menu and the site-assessment form.
// The form is not connected to a database yet: the public intake function is a new Contract Center module and stays
// off until it passes the security retest. Until then the form opens the visitor's email app with the details filled in.
(function () {
  var es = document.documentElement.lang === "es";
  var TO = "wecleanitallfl@gmail.com";

  // ── phone menu ──
  var btn = document.querySelector(".menu-btn"), panel = document.getElementById("menu");
  if (btn && panel) {
    var setOpen = function (open) {
      panel.classList.toggle("open", open);
      btn.setAttribute("aria-expanded", open ? "true" : "false");
      btn.setAttribute("aria-label", open ? (es ? "Cerrar menú" : "Close menu") : (es ? "Abrir menú" : "Open menu"));
    };
    btn.addEventListener("click", function () { setOpen(!panel.classList.contains("open")); });
    panel.addEventListener("click", function (e) { if (e.target.closest("a")) setOpen(false); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape" && panel.classList.contains("open")) { setOpen(false); btn.focus(); } });
  }

  // ── site-assessment form ──
  var form = document.getElementById("assess-form");
  if (!form) return;
  var msg = form.querySelector(".form-msg");
  var started = Date.now();
  var T = es ? {
    need: "Completa los campos marcados.", contact: "Escribe un correo o un teléfono para responderte.", email: "Revisa el correo.",
    phone: "Revisa el teléfono (10 dígitos).", ok: "Abrimos tu app de correo con los datos. Envía el mensaje para completar la solicitud. ¿Prefieres llamar? (954) 320-9303.",
    subject: "Solicitud de evaluación del sitio: ", intro: "Solicitud desde la web (evaluación del sitio)"
  } : {
    need: "Please fill in the highlighted fields.", contact: "Add an email or a phone number so we can reply.", email: "Please check the email address.",
    phone: "Please check the phone number (10 digits).", ok: "Your email app is opening with the details filled in. Send the message to complete your request. Prefer to call? (954) 320-9303.",
    subject: "Site assessment request: ", intro: "Website request (site assessment)"
  };
  var say = function (text, kind) { msg.textContent = text; msg.className = "form-msg" + (kind ? " " + kind : ""); };
  var mark = function (el, bad) { if (bad) el.setAttribute("aria-invalid", "true"); else el.removeAttribute("aria-invalid"); };

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    if (form.website.value) return;                       // honeypot: bots fill hidden fields
    if (Date.now() - started < 2500) return;              // filled faster than a person can
    var f = form.elements, bad = [];
    ["business", "name", "address"].forEach(function (k) { var v = f[k].value.trim(); mark(f[k], !v); if (!v) bad.push(f[k]); });
    var email = f.email.value.trim(), phone = f.phone.value.replace(/\D/g, "");
    mark(f.email, false); mark(f.phone, false);
    if (bad.length) { say(T.need, "bad"); bad[0].focus(); return; }
    if (!email && !phone) { mark(f.email, true); mark(f.phone, true); say(T.contact, "bad"); f.email.focus(); return; }
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) { mark(f.email, true); say(T.email, "bad"); f.email.focus(); return; }
    if (phone && !(phone.length === 10 || (phone.length === 11 && phone[0] === "1"))) { mark(f.phone, true); say(T.phone, "bad"); f.phone.focus(); return; }

    var line = function (k) { var el = f[k], v = el.value.trim(); return v ? el.getAttribute("data-label") + ": " + v : ""; };
    var body = [T.intro, ""].concat(["business", "name", "email", "phone", "address", "city", "facility", "area", "floor", "nights"].map(line).filter(Boolean)).join("\n");
    var href = "mailto:" + TO + "?subject=" + encodeURIComponent(T.subject + f.business.value.trim() + " (" + f.city.value + ")") + "&body=" + encodeURIComponent(body);
    say(T.ok, "ok");
    window.location.href = href;
  });
})();
