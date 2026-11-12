BEGIN;

-- Running downgrade d5e6f7a8b9c0 -> a9b8c7d6e5f4

DROP POLICY IF EXISTS trip_expenses_insert_owner ON trip_expenses;

DROP POLICY IF EXISTS trip_expenses_update_owner ON trip_expenses;

DROP POLICY IF EXISTS weather_cache_owner ON weather_cache;

DROP POLICY IF EXISTS refresh_tokens_select ON user_refresh_tokens;

DROP POLICY IF EXISTS refresh_tokens_insert ON user_refresh_tokens;

DROP POLICY IF EXISTS refresh_tokens_update ON user_refresh_tokens;

DROP POLICY IF EXISTS refresh_tokens_delete_owner ON user_refresh_tokens;

DROP POLICY IF EXISTS activity_logs_select ON activity_logs;

DROP POLICY IF EXISTS activity_logs_insert_self ON activity_logs;

DROP POLICY IF EXISTS activity_logs_delete_owner ON activity_logs;

DROP POLICY IF EXISTS admin_mfa_auth_flow ON admin_mfa;

DROP POLICY IF EXISTS admin_mfa_delete_owner ON admin_mfa;

DROP POLICY IF EXISTS admin_recovery_codes_auth_flow ON admin_recovery_codes;

DROP POLICY IF EXISTS admin_recovery_codes_delete_owner ON admin_recovery_codes;

DROP POLICY IF EXISTS admin_sessions_auth_flow ON admin_sessions;

DROP POLICY IF EXISTS admin_sessions_delete_owner ON admin_sessions;

DROP POLICY IF EXISTS admin_audit_log_insert ON admin_audit_log;

DROP POLICY IF EXISTS admin_audit_log_select_admin ON admin_audit_log;

CREATE POLICY trip_expenses_insert_owner ON trip_expenses FOR INSERT WITH CHECK (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

CREATE POLICY trip_expenses_update_owner ON trip_expenses FOR UPDATE USING (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer) WITH CHECK (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

ALTER TABLE weather_cache NO FORCE ROW LEVEL SECURITY;

ALTER TABLE weather_cache DISABLE ROW LEVEL SECURITY;

ALTER TABLE user_refresh_tokens NO FORCE ROW LEVEL SECURITY;

ALTER TABLE user_refresh_tokens DISABLE ROW LEVEL SECURITY;

ALTER TABLE activity_logs NO FORCE ROW LEVEL SECURITY;

ALTER TABLE activity_logs DISABLE ROW LEVEL SECURITY;

ALTER TABLE admin_mfa NO FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_mfa DISABLE ROW LEVEL SECURITY;

ALTER TABLE admin_recovery_codes NO FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_recovery_codes DISABLE ROW LEVEL SECURITY;

ALTER TABLE admin_sessions NO FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_sessions DISABLE ROW LEVEL SECURITY;

ALTER TABLE admin_audit_log NO FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_audit_log DISABLE ROW LEVEL SECURITY;

UPDATE alembic_version SET version_num='a9b8c7d6e5f4' WHERE alembic_version.version_num = 'd5e6f7a8b9c0';

COMMIT;

