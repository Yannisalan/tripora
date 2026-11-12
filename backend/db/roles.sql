-- ============================================================================
-- Tripora: least-privilege database roles (PostgreSQL 15+ / Neon)
-- ============================================================================
--
-- Two roles:
--
--   migrator (the existing owner, e.g. neondb_owner)
--       Owns every table. Runs `flask db upgrade` ONLY, from the release /
--       pre-deploy step. Never configured as the app's runtime credentials.
--
--   tripora_runtime
--       What the web app connects as (DB_USER / DB_PASSWORD on Render).
--       DML (SELECT/INSERT/UPDATE/DELETE) on application tables, sequence
--       usage. No DDL, no ownership, no BYPASSRLS, no role/database creation,
--       no access to alembic_version. Subject to every Row-Level Security
--       policy, including on `users` (which is not FORCEd for the owner).
--
-- HOW TO RUN (as the migrator/owner, AFTER `flask db upgrade`):
--
--   1. Create the login role with SQL, NOT via Neon Console/API: roles made
--      in the console become members of `neon_superuser` (which carries
--      BYPASSRLS and would defeat Row-Level Security). In the Neon SQL editor,
--      connected to the app database as the owner:
--         CREATE ROLE tripora_runtime LOGIN PASSWORD '<long random value>';
--      (or CREATE ROLE tripora_runtime LOGIN; then ALTER ROLE ... PASSWORD
--      later). Keep the password out of files and shell history.
--   2. psql "$OWNER_URL" -v migrator=neondb_owner -f backend/db/roles.sql
--   3. Re-run step 2 after migrations that add tables (idempotent); the
--      default privileges below cover tables created later by `migrator`.
--
-- Never run this against production without the owner's explicit approval.
-- ============================================================================

\set ON_ERROR_STOP on
\if :{?migrator}
\else
  \set migrator neondb_owner
\endif

-- CREATE ROLE tripora_runtime LOGIN PASSWORD :'runtime_password';

-- Hard limits on the runtime role. A role created with plain CREATE ROLE has
-- no SUPERUSER/REPLICATION/BYPASSRLS; Neon's owner is not allowed to even
-- mention those attributes, so they are verified by the report at the end
-- instead of being set here.
ALTER ROLE tripora_runtime NOCREATEDB NOCREATEROLE CONNECTION LIMIT 40;

-- Statement timeout: a runaway query cannot hold connections forever.
ALTER ROLE tripora_runtime SET statement_timeout = '30s';
ALTER ROLE tripora_runtime SET idle_in_transaction_session_timeout = '60s';

-- Nobody but the owner may create objects in the app schema.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM tripora_runtime;
GRANT USAGE ON SCHEMA public TO tripora_runtime;

-- Data access on existing tables and sequences.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
    TO tripora_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tripora_runtime;

-- Migration bookkeeping is not the app's business.
REVOKE ALL ON TABLE alembic_version FROM tripora_runtime;

-- The admin audit trail is append-only for the app. (ON DELETE SET NULL on
-- account deletion is a referential action run as the table owner.)
REVOKE UPDATE, DELETE ON TABLE admin_audit_log FROM tripora_runtime;

-- Tables created by future migrations get the same grants automatically.
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator" IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tripora_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator" IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO tripora_runtime;

-- Sanity report.
-- Expect tripora_runtime: f f f f f, and member_of empty.
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication,
       rolbypassrls
FROM pg_roles WHERE rolname IN ('tripora_runtime', :'migrator');
SELECT r.rolname AS member_of
FROM pg_auth_members m
JOIN pg_roles r ON r.oid = m.roleid
JOIN pg_roles u ON u.oid = m.member
WHERE u.rolname = 'tripora_runtime';
