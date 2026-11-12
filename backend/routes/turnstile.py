"""Public Turnstile endpoints.

GET /api/turnstile/config
    Whether bot protection is on and the PUBLIC site key. Never the secret.

GET /api/turnstile/challenge?action=<register|forgot_password>&theme=<light|dark>
    A minimal page that renders the Turnstile widget. Used by the Android app
    inside a WebView (Turnstile has no native Flutter SDK). The page posts the
    token to the app through the ``TriporaTurnstile`` JavaScript channel and
    nowhere else. Served from the API host, which must therefore be one of the
    widget's allowed hostnames in Cloudflare and in TURNSTILE_ALLOWED_HOSTNAMES.

Neither endpoint touches the database.
"""

import json
import secrets

from flask import Blueprint, Response, jsonify, request

from services import turnstile

turnstile_bp = Blueprint("turnstile", __name__, url_prefix="/api/turnstile")

CHALLENGE_PATH = "/api/turnstile/challenge"
_SCRIPT_URL = (
    "https://challenges.cloudflare.com/turnstile/v0/api.js"
    "?render=explicit&onload=onTurnstileLoad"
)
_THEMES = {"light", "dark"}


@turnstile_bp.route("/config", methods=["GET"])
def turnstile_config():
    enabled = turnstile.is_enabled()
    return jsonify({
        "success": True,
        "enabled": enabled,
        "siteKey": (turnstile.site_key() or None) if enabled else None,
        "challengePath": CHALLENGE_PATH,
    }), 200


def _js_literal(value):
    """JSON for embedding in an inline script; cannot close the tag."""
    return (
        json.dumps(value)
        .replace("<", "\\u003c")
        .replace(">", "\\u003e")
        .replace("&", "\\u0026")
    )


_PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Tripora verification</title>
<style nonce="{nonce}">
html, body {{ margin: 0; height: 100%; background: #F8FAFC; color: #0F172A;
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
body.dark {{ background: #0D0D14; color: #E5E7EB; }}
main {{ min-height: 100%; box-sizing: border-box; padding: 24px 16px;
  display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: 16px; text-align: center; }}
p {{ margin: 0; font-size: 15px; line-height: 1.4; }}
</style>
</head>
<body class="{theme}">
<main>
<p>Confirm you&#39;re human to continue.</p>
<div id="turnstile"></div>
</main>
<script nonce="{nonce}">
(function () {{
  var cfg = {config};
  function send(message) {{
    try {{
      if (window.TriporaTurnstile && window.TriporaTurnstile.postMessage) {{
        window.TriporaTurnstile.postMessage(JSON.stringify(message));
      }}
    }} catch (e) {{}}
  }}
  window.onTurnstileLoad = function () {{
    window.turnstile.render("#turnstile", {{
      sitekey: cfg.siteKey,
      action: cfg.action,
      theme: cfg.theme,
      callback: function (token) {{ send({{ type: "token", token: token }}); }},
      "expired-callback": function () {{ send({{ type: "expired" }}); }},
      "timeout-callback": function () {{ send({{ type: "expired" }}); }},
      "error-callback": function (code) {{
        send({{ type: "error", code: String(code || "") }});
        return true;
      }}
    }});
    send({{ type: "ready" }});
  }};
}})();
</script>
<script nonce="{nonce}" src="{script_url}" async defer></script>
</body>
</html>
"""


@turnstile_bp.route("/challenge", methods=["GET"])
def turnstile_challenge():
    action = (request.args.get("action") or "").strip()
    if action not in turnstile.KNOWN_ACTIONS:
        return jsonify({"success": False, "message": "Unknown action."}), 400

    key = turnstile.site_key()
    if not turnstile.is_enabled() or not key:
        return jsonify({
            "success": False,
            "message": "Verification is not available.",
        }), 503

    theme = (request.args.get("theme") or "light").strip().lower()
    if theme not in _THEMES:
        theme = "light"

    nonce = secrets.token_urlsafe(16)
    html = _PAGE.format(
        nonce=nonce,
        theme=theme,
        script_url=_SCRIPT_URL,
        config=_js_literal({"siteKey": key, "action": action, "theme": theme}),
    )

    response = Response(html, status=200, mimetype="text/html")
    # Strict, page-specific policy. The global after_request hook keeps a CSP
    # that a route already set, and adds the other security headers.
    response.headers["Content-Security-Policy"] = (
        "default-src 'none'; "
        "script-src 'nonce-{n}' https://challenges.cloudflare.com; "
        "style-src 'nonce-{n}'; "
        "frame-src https://challenges.cloudflare.com; "
        "connect-src https://challenges.cloudflare.com; "
        "img-src data:; "
        "base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    ).format(n=nonce)
    response.headers["Cache-Control"] = "no-store"
    return response
