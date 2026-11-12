BEGIN;

-- Running downgrade a9b8c7d6e5f4 -> e1f2a3b4c5d6

DROP POLICY IF EXISTS trips_admin_select ON trips;

DROP POLICY IF EXISTS users_delete_owner ON users;

DROP POLICY IF EXISTS users_auth_flow_update ON users;

DROP POLICY IF EXISTS users_auth_flow_insert ON users;

DROP POLICY IF EXISTS users_auth_flow_select ON users;

DROP POLICY IF EXISTS trips_select_owner ON trips;

CREATE POLICY trips_select_owner ON trips FOR SELECT USING (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS trips_insert_owner ON trips;

CREATE POLICY trips_insert_owner ON trips FOR INSERT WITH CHECK (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS trips_update_owner ON trips;

CREATE POLICY trips_update_owner ON trips FOR UPDATE USING (user_id = current_setting('request.jwt.claims.sub', true)::integer) WITH CHECK (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS trips_delete_owner ON trips;

CREATE POLICY trips_delete_owner ON trips FOR DELETE USING (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS users_select_owner ON users;

CREATE POLICY users_select_owner ON users FOR SELECT USING (id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS users_update_owner ON users;

CREATE POLICY users_update_owner ON users FOR UPDATE USING (id = current_setting('request.jwt.claims.sub', true)::integer) WITH CHECK (id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS trip_expenses_select_owner ON trip_expenses;

CREATE POLICY trip_expenses_select_owner ON trip_expenses FOR SELECT USING (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS trip_expenses_insert_owner ON trip_expenses;

CREATE POLICY trip_expenses_insert_owner ON trip_expenses FOR INSERT WITH CHECK (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS trip_expenses_update_owner ON trip_expenses;

CREATE POLICY trip_expenses_update_owner ON trip_expenses FOR UPDATE USING (user_id = current_setting('request.jwt.claims.sub', true)::integer) WITH CHECK (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP POLICY IF EXISTS trip_expenses_delete_owner ON trip_expenses;

CREATE POLICY trip_expenses_delete_owner ON trip_expenses FOR DELETE USING (user_id = current_setting('request.jwt.claims.sub', true)::integer);

DROP INDEX ix_admin_audit_log_created_at;

DROP INDEX ix_admin_audit_log_action;

DROP INDEX ix_admin_audit_log_admin_user_id;

DROP TABLE admin_audit_log;

DROP INDEX ix_admin_sessions_expires_at;

DROP INDEX ix_admin_sessions_user_id;

DROP TABLE admin_sessions;

DROP INDEX ix_admin_recovery_codes_user_id;

DROP TABLE admin_recovery_codes;

DROP TABLE admin_mfa;

ALTER TABLE user_refresh_tokens DROP CONSTRAINT IF EXISTS user_refresh_tokens_user_id_fkey;

ALTER TABLE user_refresh_tokens ADD CONSTRAINT user_refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES users (id);

ALTER TABLE users DROP CONSTRAINT IF EXISTS ck_users_role;

ALTER TABLE users DROP COLUMN role;

ALTER TABLE users DROP COLUMN email_verification_sent_at;

ALTER TABLE users DROP COLUMN email_verification_attempts;

ALTER TABLE users DROP COLUMN email_verification_expires_at;

ALTER TABLE users DROP COLUMN email_verification_code_hash;

UPDATE alembic_version SET version_num='e1f2a3b4c5d6' WHERE alembic_version.version_num = 'a9b8c7d6e5f4';

-- Running downgrade e1f2a3b4c5d6 -> c8d2e3f4a5b6

DROP INDEX ix_user_refresh_tokens_expires_at;

UPDATE alembic_version SET version_num='c8d2e3f4a5b6' WHERE alembic_version.version_num = 'e1f2a3b4c5d6';

-- Running downgrade c8d2e3f4a5b6 -> b7c1d2e3f4a5

ALTER TABLE users DROP COLUMN token_version;

UPDATE alembic_version SET version_num='b7c1d2e3f4a5' WHERE alembic_version.version_num = 'c8d2e3f4a5b6';

-- Running downgrade b7c1d2e3f4a5 -> 0922f2fc8de9

DROP INDEX ix_user_refresh_tokens_family_id;

DROP INDEX ix_user_refresh_tokens_token_hash;

DROP INDEX ix_user_refresh_tokens_user_id;

DROP TABLE user_refresh_tokens;

UPDATE alembic_version SET version_num='0922f2fc8de9' WHERE alembic_version.version_num = 'b7c1d2e3f4a5';

COMMIT;

