BEGIN;

-- Running upgrade a9b8c7d6e5f4 -> d5e6f7a8b9c0

ALTER TABLE weather_cache ENABLE ROW LEVEL SECURITY;

ALTER TABLE weather_cache FORCE ROW LEVEL SECURITY;

ALTER TABLE user_refresh_tokens ENABLE ROW LEVEL SECURITY;

ALTER TABLE user_refresh_tokens FORCE ROW LEVEL SECURITY;

ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE activity_logs FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_mfa ENABLE ROW LEVEL SECURITY;

ALTER TABLE admin_mfa FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_recovery_codes ENABLE ROW LEVEL SECURITY;

ALTER TABLE admin_recovery_codes FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_sessions ENABLE ROW LEVEL SECURITY;

ALTER TABLE admin_sessions FORCE ROW LEVEL SECURITY;

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

ALTER TABLE admin_audit_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS trip_expenses_insert_owner ON trip_expenses;

CREATE POLICY trip_expenses_insert_owner ON trip_expenses FOR INSERT WITH CHECK (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer AND EXISTS (SELECT 1 FROM trips t WHERE t.id = trip_id AND t.user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer));

DROP POLICY IF EXISTS trip_expenses_update_owner ON trip_expenses;

CREATE POLICY trip_expenses_update_owner ON trip_expenses FOR UPDATE USING (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer) WITH CHECK (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer AND EXISTS (SELECT 1 FROM trips t WHERE t.id = trip_id AND t.user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer));

DROP POLICY IF EXISTS weather_cache_owner ON weather_cache;

CREATE POLICY weather_cache_owner ON weather_cache FOR ALL USING (EXISTS (SELECT 1 FROM trips t WHERE t.id = weather_cache.trip_id AND t.user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer)) WITH CHECK (EXISTS (SELECT 1 FROM trips t WHERE t.id = weather_cache.trip_id AND t.user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer));

DROP POLICY IF EXISTS refresh_tokens_select ON user_refresh_tokens;

CREATE POLICY refresh_tokens_select ON user_refresh_tokens FOR SELECT USING (current_setting('app.auth_flow', true) = 'on' OR user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS refresh_tokens_insert ON user_refresh_tokens;

CREATE POLICY refresh_tokens_insert ON user_refresh_tokens FOR INSERT WITH CHECK (current_setting('app.auth_flow', true) = 'on');

DROP POLICY IF EXISTS refresh_tokens_update ON user_refresh_tokens;

CREATE POLICY refresh_tokens_update ON user_refresh_tokens FOR UPDATE USING (current_setting('app.auth_flow', true) = 'on' OR user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer) WITH CHECK (current_setting('app.auth_flow', true) = 'on' OR user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS refresh_tokens_delete_owner ON user_refresh_tokens;

CREATE POLICY refresh_tokens_delete_owner ON user_refresh_tokens FOR DELETE USING (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS activity_logs_select ON activity_logs;

CREATE POLICY activity_logs_select ON activity_logs FOR SELECT USING (current_setting('app.admin_read', true) = 'on' OR user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS activity_logs_insert_self ON activity_logs;

CREATE POLICY activity_logs_insert_self ON activity_logs FOR INSERT WITH CHECK (user_id IS NOT DISTINCT FROM NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS activity_logs_delete_owner ON activity_logs;

CREATE POLICY activity_logs_delete_owner ON activity_logs FOR DELETE USING (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS admin_mfa_auth_flow ON admin_mfa;

CREATE POLICY admin_mfa_auth_flow ON admin_mfa FOR ALL USING (current_setting('app.auth_flow', true) = 'on') WITH CHECK (current_setting('app.auth_flow', true) = 'on');

DROP POLICY IF EXISTS admin_mfa_delete_owner ON admin_mfa;

CREATE POLICY admin_mfa_delete_owner ON admin_mfa FOR DELETE USING (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS admin_recovery_codes_auth_flow ON admin_recovery_codes;

CREATE POLICY admin_recovery_codes_auth_flow ON admin_recovery_codes FOR ALL USING (current_setting('app.auth_flow', true) = 'on') WITH CHECK (current_setting('app.auth_flow', true) = 'on');

DROP POLICY IF EXISTS admin_recovery_codes_delete_owner ON admin_recovery_codes;

CREATE POLICY admin_recovery_codes_delete_owner ON admin_recovery_codes FOR DELETE USING (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS admin_sessions_auth_flow ON admin_sessions;

CREATE POLICY admin_sessions_auth_flow ON admin_sessions FOR ALL USING (current_setting('app.auth_flow', true) = 'on') WITH CHECK (current_setting('app.auth_flow', true) = 'on');

DROP POLICY IF EXISTS admin_sessions_delete_owner ON admin_sessions;

CREATE POLICY admin_sessions_delete_owner ON admin_sessions FOR DELETE USING (user_id = NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer);

DROP POLICY IF EXISTS admin_audit_log_insert ON admin_audit_log;

CREATE POLICY admin_audit_log_insert ON admin_audit_log FOR INSERT WITH CHECK (current_setting('app.auth_flow', true) = 'on' OR current_setting('app.admin_read', true) = 'on');

DROP POLICY IF EXISTS admin_audit_log_select_admin ON admin_audit_log;

CREATE POLICY admin_audit_log_select_admin ON admin_audit_log FOR SELECT USING (current_setting('app.admin_read', true) = 'on');

UPDATE alembic_version SET version_num='d5e6f7a8b9c0' WHERE alembic_version.version_num = 'a9b8c7d6e5f4';

COMMIT;

