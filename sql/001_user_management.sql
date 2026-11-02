CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS authz;
CREATE SCHEMA IF NOT EXISTS config;
CREATE SCHEMA IF NOT EXISTS meter;
CREATE SCHEMA IF NOT EXISTS queue;

CREATE TABLE IF NOT EXISTS auth.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email citext UNIQUE NOT NULL,
    password_hash text NOT NULL,
    display_name text,
    mfa_secret text,
    mfa_enabled boolean NOT NULL DEFAULT false,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'pending')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth.sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE,
    ip_address inet,
    user_agent text,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sessions_active_idx ON auth.sessions(user_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS auth.password_reset_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS authz.resources (
    id text PRIMARY KEY,
    kind text NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS authz.relationships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    object_id text NOT NULL REFERENCES authz.resources(id) ON DELETE CASCADE,
    relation text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(subject_id, object_id, relation)
);

CREATE TABLE IF NOT EXISTS authz.role_hierarchy (
    parent_role text NOT NULL,
    child_role text NOT NULL,
    PRIMARY KEY(parent_role, child_role)
);

CREATE TABLE IF NOT EXISTS config.entries (
    scope text NOT NULL,
    key text NOT NULL,
    value jsonb NOT NULL DEFAULT '{}',
    version integer NOT NULL DEFAULT 1,
    updated_by uuid REFERENCES auth.users(id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(scope, key, version)
);

CREATE TABLE IF NOT EXISTS meter.period_usage (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    metric_name text NOT NULL,
    period text NOT NULL,
    quantity numeric NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(user_id, metric_name, period)
);

CREATE TABLE IF NOT EXISTS meter.reservations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    metric_name text NOT NULL,
    quantity numeric NOT NULL,
    period text NOT NULL,
    expires_at timestamptz NOT NULL,
    released_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS meter.quotas (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    metric_name text NOT NULL,
    period text NOT NULL,
    limit_quantity numeric NOT NULL,
    PRIMARY KEY(user_id, metric_name, period)
);

CREATE TABLE IF NOT EXISTS queue.jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_type text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}',
    status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'active', 'completed', 'retrying', 'dead')),
    attempts integer NOT NULL DEFAULT 0,
    max_attempts integer NOT NULL DEFAULT 5,
    run_at timestamptz NOT NULL DEFAULT now(),
    locked_by text,
    locked_at timestamptz,
    last_error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS jobs_ready_idx ON queue.jobs(run_at, status) WHERE status IN ('queued', 'retrying');

CREATE OR REPLACE FUNCTION auth.sign_up(p_email text, p_password text, p_display_name text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_user_id uuid;
BEGIN
    IF length(p_password) < 12 THEN
        RETURN jsonb_build_object('error', 'Password must be at least 12 characters');
    END IF;
    INSERT INTO auth.users(email, password_hash, display_name)
    VALUES (p_email, crypt(p_password, gen_salt('bf')), p_display_name)
    RETURNING id INTO v_user_id;
    RETURN jsonb_build_object('user_id', v_user_id);
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Email is already registered');
END;
$$;

CREATE OR REPLACE FUNCTION auth.sign_in(p_email text, p_password text, p_ip inet DEFAULT NULL, p_user_agent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_user auth.users%ROWTYPE; v_token text; v_hash text; v_expires timestamptz;
BEGIN
    SELECT * INTO v_user FROM auth.users WHERE email = lower(p_email) AND status = 'active';
    IF v_user.id IS NULL OR NOT (v_user.password_hash = crypt(p_password, v_user.password_hash)) THEN
        RETURN jsonb_build_object('error', 'Invalid email or password');
    END IF;
    v_token := encode(gen_random_bytes(32), 'hex');
    v_hash := encode(digest(v_token, 'sha256'), 'hex');
    v_expires := now() + interval '7 days';
    INSERT INTO auth.sessions(user_id, token_hash, ip_address, user_agent, expires_at)
    VALUES (v_user.id, v_hash, p_ip, p_user_agent, v_expires);
    RETURN jsonb_build_object('user_id', v_user.id, 'email', v_user.email, 'session_token', v_token, 'expires_at', v_expires);
END;
$$;

CREATE OR REPLACE FUNCTION auth.validate_session(p_token text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_hash text; v_session auth.sessions%ROWTYPE; v_user auth.users%ROWTYPE;
BEGIN
    v_hash := encode(digest(p_token, 'sha256'), 'hex');
    SELECT * INTO v_session FROM auth.sessions WHERE token_hash = v_hash AND revoked_at IS NULL AND expires_at > now();
    IF v_session.id IS NULL THEN RETURN jsonb_build_object('error', 'Invalid session'); END IF;
    SELECT * INTO v_user FROM auth.users WHERE id = v_session.user_id AND status = 'active';
    IF v_user.id IS NULL THEN RETURN jsonb_build_object('error', 'Invalid session'); END IF;
    RETURN jsonb_build_object('user_id', v_user.id, 'email', v_user.email, 'display_name', v_user.display_name);
END;
$$;

CREATE OR REPLACE FUNCTION auth.logout(p_token text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE auth.sessions SET revoked_at = now()
    WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex') AND revoked_at IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION auth.reset_password(p_token text, p_password text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_reset auth.password_reset_tokens%ROWTYPE;
BEGIN
    SELECT * INTO v_reset FROM auth.password_reset_tokens
    WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex') AND used_at IS NULL AND expires_at > now();
    IF v_reset.id IS NULL THEN RETURN jsonb_build_object('error', 'Invalid or expired reset token'); END IF;
    IF length(p_password) < 12 THEN RETURN jsonb_build_object('error', 'Password must be at least 12 characters'); END IF;
    UPDATE auth.users SET password_hash = crypt(p_password, gen_salt('bf')), updated_at = now() WHERE id = v_reset.user_id;
    UPDATE auth.password_reset_tokens SET used_at = now() WHERE id = v_reset.id;
    UPDATE auth.sessions SET revoked_at = now() WHERE user_id = v_reset.user_id AND revoked_at IS NULL;
    RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION auth.verify_mfa(p_user_id uuid, p_code text)
RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object('verified', false, 'message', 'MFA enrollment required');
$$;

CREATE OR REPLACE FUNCTION authz.check_permission(p_user_id uuid, p_resource_id text, p_action text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM authz.relationships r
        JOIN authz.resources res ON res.id = r.object_id
        WHERE r.subject_id = p_user_id AND r.object_id = p_resource_id
          AND (r.relation = p_action OR r.relation = 'owner')
    ) OR EXISTS (
        SELECT 1 FROM authz.relationships r
        WHERE r.subject_id = p_user_id AND r.relation = 'admin'
    );
$$;

CREATE OR REPLACE FUNCTION authz.grant_role(p_subject_id uuid, p_resource_id text, p_relation text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO authz.resources(id, kind) VALUES (p_resource_id, 'resource')
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO authz.relationships(subject_id, object_id, relation)
    VALUES (p_subject_id, p_resource_id, p_relation)
    ON CONFLICT(subject_id, object_id, relation) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION config.get(p_scope text, p_key text, p_version integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT value FROM config.entries
    WHERE scope = p_scope AND key = p_key AND (p_version IS NULL OR version = p_version)
    ORDER BY version DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION config.set(p_scope text, p_key text, p_value jsonb, p_user_id uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_version integer;
BEGIN
    SELECT COALESCE(MAX(version), 0) + 1 INTO v_version FROM config.entries WHERE scope = p_scope AND key = p_key;
    INSERT INTO config.entries(scope, key, value, version, updated_by)
    VALUES (p_scope, p_key, p_value, v_version, p_user_id);
    RETURN v_version;
END;
$$;

CREATE OR REPLACE FUNCTION meter.track_usage(p_user_id uuid, p_metric_name text, p_quantity numeric)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE v_period text := to_char(now(), 'YYYY-MM'); v_total numeric;
BEGIN
    INSERT INTO meter.period_usage(user_id, metric_name, period, quantity)
    VALUES (p_user_id, p_metric_name, v_period, p_quantity)
    ON CONFLICT(user_id, metric_name, period)
    DO UPDATE SET quantity = meter.period_usage.quantity + EXCLUDED.quantity, updated_at = now()
    RETURNING quantity INTO v_total;
    RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION meter.check_quota(p_user_id uuid, p_metric_name text, p_quantity numeric DEFAULT 0)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH current_usage AS (
        SELECT COALESCE(quantity, 0) AS quantity FROM meter.period_usage
        WHERE user_id = p_user_id AND metric_name = p_metric_name AND period = to_char(now(), 'YYYY-MM')
    ), quota AS (
        SELECT limit_quantity FROM meter.quotas
        WHERE user_id = p_user_id AND metric_name = p_metric_name AND period = to_char(now(), 'YYYY-MM')
    )
    SELECT jsonb_build_object(
        'allowed', COALESCE((SELECT quantity FROM quota) >= COALESCE((SELECT quantity FROM current_usage), 0) + p_quantity, true),
        'used', COALESCE((SELECT quantity FROM current_usage), 0),
        'limit', (SELECT limit_quantity FROM quota)
    );
$$;

CREATE OR REPLACE FUNCTION meter.reserve(p_user_id uuid, p_metric_name text, p_quantity numeric)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_quota jsonb; v_id uuid;
BEGIN
    v_quota := meter.check_quota(p_user_id, p_metric_name, p_quantity);
    IF NOT (v_quota->>'allowed')::boolean THEN
        RETURN jsonb_build_object('error', 'Quota exceeded');
    END IF;
    INSERT INTO meter.reservations(user_id, metric_name, quantity, period, expires_at)
    VALUES (p_user_id, p_metric_name, p_quantity, to_char(now(), 'YYYY-MM'), now() + interval '15 minutes')
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('reservation_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION queue.enqueue(p_job_type text, p_payload jsonb, p_run_at timestamptz DEFAULT now(), p_max_attempts integer DEFAULT 5)
RETURNS uuid LANGUAGE sql AS $$
    INSERT INTO queue.jobs(job_type, payload, run_at, max_attempts)
    VALUES (p_job_type, p_payload, p_run_at, p_max_attempts)
    RETURNING id;
$$;

CREATE OR REPLACE FUNCTION queue.poll_next(p_worker text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_job queue.jobs%ROWTYPE;
BEGIN
    SELECT * INTO v_job FROM queue.jobs
    WHERE status IN ('queued', 'retrying') AND run_at <= now()
    ORDER BY run_at, created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF v_job.id IS NULL THEN RETURN NULL; END IF;
    UPDATE queue.jobs SET status = 'active', attempts = attempts + 1, locked_by = p_worker, locked_at = now(), updated_at = now()
    WHERE id = v_job.id;
    RETURN jsonb_build_object('id', v_job.id, 'job_type', v_job.job_type, 'payload', v_job.payload, 'attempts', v_job.attempts + 1);
END;
$$;
