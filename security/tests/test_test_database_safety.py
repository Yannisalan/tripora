"""Tests for the P2 test-database safety policy.

These tests do not use the ``app``/``client`` fixtures on purpose: an unsafe
``TRIPORA_TEST_DB_URI`` must be rejected before any engine can run
``create_all()``/``drop_all()``.
"""

import pytest

from . import conftest as conftest_module


def _clear_db_env(monkeypatch):
    monkeypatch.delenv("TRIPORA_TEST_DB_URI", raising=False)
    monkeypatch.delenv(
        conftest_module.EXTERNAL_TEST_DB_OPT_IN_ENV,
        raising=False,
    )


def _opt_in(monkeypatch):
    monkeypatch.setenv(
        conftest_module.EXTERNAL_TEST_DB_OPT_IN_ENV,
        conftest_module.EXTERNAL_TEST_DB_OPT_IN_TOKEN,
    )


class TestTestDatabaseUriDefaults:
    def test_default_is_in_memory_sqlite(self, monkeypatch):
        _clear_db_env(monkeypatch)

        assert (
            conftest_module._test_database_uri()
            == "sqlite:///:memory:"
        )

    def test_missing_and_blank_overrides_use_in_memory(self, monkeypatch):
        _clear_db_env(monkeypatch)

        monkeypatch.setenv("TRIPORA_TEST_DB_URI", "")
        assert conftest_module._test_database_uri() == "sqlite:///:memory:"

        monkeypatch.setenv("TRIPORA_TEST_DB_URI", "   ")
        assert conftest_module._test_database_uri() == "sqlite:///:memory:"

    @pytest.mark.parametrize(
        "uri",
        (
            "sqlite:///:memory:",
            "sqlite://",
            "sqlite+pysqlite:///:memory:",
        ),
    )
    def test_in_memory_sqlite_is_allowed_without_opt_in(
        self, monkeypatch, uri
    ):
        _clear_db_env(monkeypatch)
        monkeypatch.setenv("TRIPORA_TEST_DB_URI", uri)

        assert conftest_module._test_database_uri() == uri


class TestExternalTestDatabaseRejection:
    @pytest.mark.parametrize(
        "uri",
        (
            "postgresql://tester:s3cr3t@db.example.com:5432/tripora_test",
            "mysql+pymysql://tester:s3cr3t@db.example.com:3306/tripora_test",
            "sqlite:///tripora_security_test.db",
        ),
    )
    def test_external_target_requires_explicit_opt_in(
        self, monkeypatch, uri
    ):
        _clear_db_env(monkeypatch)
        monkeypatch.setenv("TRIPORA_TEST_DB_URI", uri)

        with pytest.raises(RuntimeError) as excinfo:
            conftest_module._test_database_uri()

        message = str(excinfo.value)
        assert "external test database" in message.lower()
        # Credentials must never be echoed in configuration errors.
        assert "s3cr3t" not in message
        assert "tester:" not in message

    def test_vague_opt_in_value_is_rejected(self, monkeypatch):
        _clear_db_env(monkeypatch)
        monkeypatch.setenv(
            "TRIPORA_TEST_DB_URI",
            "postgresql://tester:s3cr3t@db.example.com:5432/tripora_test",
        )
        monkeypatch.setenv(
            conftest_module.EXTERNAL_TEST_DB_OPT_IN_ENV,
            "true",
        )

        with pytest.raises(RuntimeError):
            conftest_module._test_database_uri()

    @pytest.mark.parametrize(
        "database_name",
        (
            "tripora",
            "tripora_production",
            "tripora_staging",
            "shared",
            "primary",
            "master",
        ),
    )
    def test_opt_in_does_not_allow_non_disposable_names(
        self, monkeypatch, database_name
    ):
        _clear_db_env(monkeypatch)
        _opt_in(monkeypatch)
        monkeypatch.setenv(
            "TRIPORA_TEST_DB_URI",
            "postgresql://tester:s3cr3t@db.example.com:5432/{}".format(
                database_name
            ),
        )

        with pytest.raises(RuntimeError) as excinfo:
            conftest_module._test_database_uri()

        message = str(excinfo.value)
        assert "clearly disposable" in message
        assert "s3cr3t" not in message

    def test_invalid_url_is_rejected_without_echoing_credentials(
        self, monkeypatch
    ):
        _clear_db_env(monkeypatch)
        monkeypatch.setenv(
            "TRIPORA_TEST_DB_URI",
            "this is not a database url s3cr3t",
        )

        with pytest.raises(RuntimeError) as excinfo:
            conftest_module._test_database_uri()

        message = str(excinfo.value)
        assert "not a valid" in message
        assert "s3cr3t" not in message


class TestExternalDisposableDatabaseAcceptance:
    @pytest.mark.parametrize(
        "uri",
        (
            "postgresql://tester:s3cr3t@db.example.com:5432/tripora_test",
            "mysql+pymysql://tester:s3cr3t@db.example.com:3306/tripora_ci",
            "sqlite:///tripora_security_test.db",
        ),
    )
    def test_opt_in_plus_disposable_name_is_allowed(self, monkeypatch, uri):
        _clear_db_env(monkeypatch)
        _opt_in(monkeypatch)
        monkeypatch.setenv("TRIPORA_TEST_DB_URI", uri)

        assert conftest_module._test_database_uri() == uri
