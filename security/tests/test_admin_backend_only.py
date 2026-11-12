"""Administration is backend-only: every admin route rejects non-admins.

Walks the live URL map instead of a hand-written list, so a newly added
``/api/admin/*`` route that forgets the guard fails here.
"""

import re

import pytest

from .helpers import auth_headers, create_logged_in_user

# Routes that are deliberately reachable without an admin credential:
#   * the page-view beacon (anonymous analytics, write-only),
#   * login-status (answers "is this credential valid?" with a boolean),
#   * the admin sign-in steps (they ARE the authentication),
#   * logout (idempotent: revokes only the caller's own session, returns no
#     data, always 200).
PUBLIC_ADMIN_ENDPOINTS = {
    "admin_auth.admin_logout",
    "admin.track_page_view",
    "admin.login_status",
    "admin_auth.admin_login",
    "admin_auth.admin_mfa_setup",
    "admin_auth.admin_mfa_activate",
    "admin_auth.admin_mfa_verify",
}


def _admin_routes(app):
    for rule in app.url_map.iter_rules():
        if not rule.rule.startswith("/api/admin"):
            continue
        if rule.endpoint in PUBLIC_ADMIN_ENDPOINTS:
            continue
        path = re.sub(r"<(?:[^:>]+:)?([^>]+)>", "1", rule.rule)
        for method in sorted(rule.methods - {"HEAD", "OPTIONS"}):
            yield rule.endpoint, method, path


def test_admin_route_inventory_is_not_empty(app):
    routes = list(_admin_routes(app))
    endpoints = {endpoint for endpoint, _, _ in routes}
    # Data endpoints and the session-bound admin auth endpoints.
    assert {"admin.stats", "admin.users_list", "admin.trips_list",
            "admin.logs", "admin_auth.admin_me"} <= endpoints


@pytest.mark.parametrize("credential", ["none", "user_jwt", "garbage"])
def test_every_protected_admin_route_rejects_non_admins(app, client, credential):
    headers = {}
    if credential == "user_jwt":
        headers = auth_headers(create_logged_in_user(client, name="Normal User"))
    elif credential == "garbage":
        headers = {"Authorization": "Bearer not-a-real-admin-session"}

    checked = 0
    for endpoint, method, path in _admin_routes(app):
        response = client.open(path, method=method, headers=headers, json={})
        assert response.status_code == 401, (endpoint, method, response.status_code)
        body = response.get_json() or {}
        # No admin data leaks in the error body.
        assert set(body) <= {"success", "message", "error"}, (endpoint, body)
        checked += 1
    assert checked >= 5
