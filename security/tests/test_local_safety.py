"""Local-only safety mode (backend/config/local_safety.py).

backend/.env may point at the production database. With TRIPORA_LOCAL_ONLY=1
the backend must never read it, must refuse any non-loopback DB_HOST before
connecting, and must never send e-mail.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest

from config import local_safety
from services import email_service

BACKEND = Path(__file__).resolve().parents[2] / "backend"
NEON_HOST = "ep-example-123456.eu-central-1.aws.neon.tech"


@pytest.fixture
def local_mode(monkeypatch):
    monkeypatch.setenv(local_safety.LOCAL_ONLY_VAR, "1")


class TestDatabaseHostGuard:
    @pytest.mark.parametrize("host", ["127.0.0.1", "localhost", "::1", "[::1]", " LOCALHOST "])
    def test_loopback_hosts_allowed(self, local_mode, host):
        local_safety.check_database_host(host)

    @pytest.mark.parametrize("host", [NEON_HOST, "db.example.com", "10.0.0.5", "", None])
    def test_other_hosts_refused(self, local_mode, host):
        with pytest.raises(local_safety.LocalSafetyError) as err:
            local_safety.check_database_host(host)
        assert "No connection was attempted" in str(err.value)

    def test_message_names_neon_without_leaking_host(self, local_mode):
        with pytest.raises(local_safety.LocalSafetyError) as err:
            local_safety.check_database_host(NEON_HOST)
        assert "a Neon host" in str(err.value)
        assert NEON_HOST not in str(err.value)

    def test_inactive_outside_local_mode(self, monkeypatch):
        monkeypatch.delenv(local_safety.LOCAL_ONLY_VAR, raising=False)
        local_safety.check_database_host(NEON_HOST)  # deployed behaviour unchanged

    @pytest.mark.parametrize("value", ["0", "false", "", "no"])
    def test_falsy_values_do_not_enable(self, monkeypatch, value):
        monkeypatch.setenv(local_safety.LOCAL_ONLY_VAR, value)
        assert local_safety.local_only() is False


class TestEnvironmentLoading:
    def test_normal_mode_loads_dotenv_as_before(self, monkeypatch):
        monkeypatch.delenv(local_safety.LOCAL_ONLY_VAR, raising=False)
        calls = []
        monkeypatch.setattr(local_safety, "load_dotenv", lambda *a, **k: calls.append((a, k)))
        local_safety.load_environment()
        assert calls == [((), {})]

    def test_local_mode_loads_only_local_file(self, local_mode, monkeypatch, tmp_path):
        env_file = tmp_path / ".env.local"
        env_file.write_text("X=1\n")
        monkeypatch.setenv(local_safety.ENV_FILE_VAR, str(env_file))
        calls = []
        monkeypatch.setattr(local_safety, "load_dotenv", lambda *a, **k: calls.append((a, k)))
        local_safety.load_environment()
        assert calls == [((env_file.resolve(),), {"override": False})]

    def test_local_mode_without_file_loads_nothing(self, local_mode, monkeypatch, tmp_path):
        monkeypatch.setenv(local_safety.ENV_FILE_VAR, str(tmp_path / "missing.env"))
        calls = []
        monkeypatch.setattr(local_safety, "load_dotenv", lambda *a, **k: calls.append((a, k)))
        local_safety.load_environment()
        assert calls == []

    def test_local_mode_refuses_backend_dotenv(self, local_mode, monkeypatch):
        monkeypatch.setenv(local_safety.ENV_FILE_VAR, str(BACKEND / ".env"))
        with pytest.raises(local_safety.LocalSafetyError):
            local_safety.load_environment()

    @pytest.mark.parametrize("argv0", [
        "C:/venv/Scripts/flask.exe", "/venv/bin/flask", "/lib/flask/__main__.py",
    ])
    def test_flask_cli_without_skip_dotenv_refused(self, local_mode, monkeypatch, argv0):
        # The flask CLI auto-loads backend/.env before the app is imported.
        monkeypatch.delenv("FLASK_SKIP_DOTENV", raising=False)
        monkeypatch.setattr(sys, "argv", [argv0, "run"])
        with pytest.raises(local_safety.LocalSafetyError) as err:
            local_safety.load_environment()
        assert "FLASK_SKIP_DOTENV" in str(err.value)

    def test_flask_cli_with_skip_dotenv_allowed(self, local_mode, monkeypatch, tmp_path):
        monkeypatch.setenv("FLASK_SKIP_DOTENV", "1")
        monkeypatch.setenv(local_safety.ENV_FILE_VAR, str(tmp_path / "none.env"))
        monkeypatch.setattr(sys, "argv", ["/venv/bin/flask", "run"])
        local_safety.load_environment()

    def test_flask_cli_check_inactive_outside_local_mode(self, monkeypatch):
        monkeypatch.delenv(local_safety.LOCAL_ONLY_VAR, raising=False)
        monkeypatch.delenv("FLASK_SKIP_DOTENV", raising=False)
        monkeypatch.setattr(sys, "argv", ["/venv/bin/flask", "run"])
        monkeypatch.setattr(local_safety, "load_dotenv", lambda *a, **k: None)
        local_safety.load_environment()  # deployed `flask db upgrade` unaffected


class TestEmail:
    def test_local_mode_never_sends(self, local_mode, monkeypatch):
        monkeypatch.setenv("MAIL_HOST", "smtp.example.com")
        monkeypatch.setenv("MAIL_USER", "user")
        monkeypatch.setenv("MAIL_PASSWORD", "pw")
        monkeypatch.setenv("RESEND_API_KEY", "re_test")

        def boom(*_a, **_k):
            raise AssertionError("a provider was called in local-only mode")

        monkeypatch.setattr(email_service, "_send_via_smtp", boom)
        monkeypatch.setattr(email_service, "_send_via_resend", boom)
        assert email_service.send_email("a@example.com", "s", "t") is True


def _import_settings(extra_env):
    """Import config.settings in a fresh interpreter with network calls trapped."""
    env = {
        k: v for k, v in os.environ.items()
        if not k.startswith(("DB_", "TRIPORA_"))
    }
    env.update({
        "DB_USER": "u", "DB_PASSWORD": "p", "DB_PORT": "5432", "DB_NAME": "d",
        "JWT_SECRET_KEY": "x" * 48,
    })
    env.update(extra_env)
    code = (
        "import socket, sys\n"
        "def trap(*a, **k):\n"
        "    print('NETWORK-ATTEMPT'); sys.exit(3)\n"
        "socket.getaddrinfo = trap\n"
        "socket.create_connection = trap\n"
        "socket.socket.connect = trap\n"
        "try:\n"
        "    import config.settings\n"
        "except Exception as e:\n"
        "    print(type(e).__name__ + ': ' + str(e)); sys.exit(2)\n"
        "print('IMPORTED')\n"
    )
    return subprocess.run(
        [sys.executable, "-c", code], cwd=BACKEND, env=env,
        capture_output=True, text=True, timeout=60,
    )


class TestSettingsIntegration:
    def test_neon_host_refused_before_any_network_call(self, tmp_path):
        result = _import_settings({
            "TRIPORA_LOCAL_ONLY": "1",
            "TRIPORA_ENV_FILE": str(tmp_path / "none.env"),
            "DB_HOST": NEON_HOST,
        })
        assert result.returncode == 2, result.stdout + result.stderr
        assert "LocalSafetyError" in result.stdout
        assert "NETWORK-ATTEMPT" not in result.stdout
        assert NEON_HOST not in result.stdout + result.stderr

    def test_local_host_accepted(self, tmp_path):
        result = _import_settings({
            "TRIPORA_LOCAL_ONLY": "1",
            "TRIPORA_ENV_FILE": str(tmp_path / "none.env"),
            "DB_HOST": "127.0.0.1",
        })
        assert result.returncode == 0, result.stdout + result.stderr
        assert "IMPORTED" in result.stdout

    def test_flask_cli_refused_without_skip_dotenv(self, tmp_path):
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(("DB_", "TRIPORA_", "FLASK_"))}
        env.update({"TRIPORA_LOCAL_ONLY": "1",
                    "TRIPORA_ENV_FILE": str(tmp_path / "none.env")})
        result = subprocess.run(
            [sys.executable, "-m", "flask", "--app", "app", "routes"],
            cwd=BACKEND, env=env, capture_output=True, text=True, timeout=120,
        )
        assert result.returncode != 0
        assert "FLASK_SKIP_DOTENV" in result.stdout + result.stderr

    def test_local_mode_ignores_backend_dotenv(self, tmp_path):
        # No DB_HOST anywhere except (possibly) backend/.env: local mode must
        # not pick it up, so configuration fails instead of using it.
        result = _import_settings({
            "TRIPORA_LOCAL_ONLY": "1",
            "TRIPORA_ENV_FILE": str(tmp_path / "none.env"),
        })
        assert result.returncode == 2, result.stdout + result.stderr
        assert "DB_HOST is not configured" in result.stdout
