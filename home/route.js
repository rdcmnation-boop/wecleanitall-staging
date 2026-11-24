// Runs first on the commercial homepage (/ and /es/).
(function () {
  // Refuse to run inside another site's frame (clickjacking); GitHub Pages can't send frame-ancestors.
  if (window.top !== window.self) {
    try { window.top.location = window.location.href; } catch (e) { /* cross-origin */ }
    document.documentElement.style.display = "none";
    return;
  }
  // The app used to live at /. Sign-in, sign-up and password-reset links that still point at / carry their
  // token in the address; send those straight to the app at /app/ so they keep working.
  var h = location.hash || "", q = location.search || "";
  var auth = /(^#|&)(access_token|refresh_token|error|error_code|error_description)=/.test(h) || /(^#|&)type=(recovery|signup|invite|magiclink|email_change)/.test(h) ||
    /[?&](code|token_hash|error_description)=/.test(q);
  if (auth) { location.replace("/app/" + q + h); return; }
  document.documentElement.classList.remove("no-js");
  document.documentElement.classList.add("js");
})();
