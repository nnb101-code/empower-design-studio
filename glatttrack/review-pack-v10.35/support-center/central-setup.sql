-- ══════════════════════════════════════════════════════════════════════════════
-- GlattTrack — the manufacturer's SUPPORT CENTER (central database), v10.35
-- Runs in the manufacturer's OWN Supabase / Postgres project (not in a plant's database).
-- Every plant server reports here every few minutes (plant-server/report-to-center.sh).
-- The support-center page (index.html) shows all plants; notify.sh sends the alerts
-- (e-mail / SMS / WhatsApp — each one on or off, chosen on the page).
-- Re-runnable. The app tables are closed to anon / authenticated: only the RPCs below.
-- ══════════════════════════════════════════════════════════════════════════════
create extension if not exists pgcrypto with schema extensions;
set search_path = public, extensions;

create table if not exists sc_staff (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code_hash text not null,              -- bcrypt
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists sc_sessions (
  token text primary key default encode(gen_random_bytes(24), 'hex'),
  staff_id uuid not null references sc_staff(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '12 hours'
);
create table if not exists sc_login_attempts (ip text, ok boolean, at timestamptz not null default now());
create table if not exists sc_plants (
  code text primary key check (code ~ '^[0-9]{3,8}$'),
  name text not null,
  secret_hash text not null,            -- bcrypt of the plant's secret (given once when the plant is added)
  created_at timestamptz not null default now()
);
create table if not exists sc_status (
  code text primary key references sc_plants(code) on delete cascade,
  level text not null check (level in ('ok', 'warn', 'bad')),
  problems jsonb not null default '[]'::jsonb,   -- what makes it red / orange (codes)
  report jsonb not null,
  app_version text,
  working boolean,
  reported_at timestamptz not null default now()
);
create table if not exists sc_alerts (
  id bigserial primary key,
  code text not null references sc_plants(code) on delete cascade,
  level text not null check (level in ('warn', 'bad')),
  text text not null,
  created_at timestamptz not null default now(),
  sent jsonb not null default '{}'::jsonb,       -- {"email": "...time", "sms": ..., "whatsapp": ...}
  resolved_at timestamptz
);
create table if not exists sc_notify (
  id int primary key check (id = 1),
  settings jsonb not null default '{"email":{"on":true,"to":[]},"sms":{"on":false,"to":[]},"whatsapp":{"on":false,"to":[]},"minLevel":"bad"}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into sc_notify (id) values (1) on conflict do nothing;
create table if not exists sc_release (
  id int primary key check (id = 1),
  version text, app_url text, app_sha256 text, sql_url text, sql_sha256 text,
  set_at timestamptz, set_by text
);
insert into sc_release (id) values (1) on conflict do nothing;
create table if not exists sc_commands (
  id bigserial primary key,
  code text not null references sc_plants(code) on delete cascade,
  cmd text not null check (cmd in ('restart_standby', 'reload_tablets', 'update_now', 'run_nightly_check')),
  created_at timestamptz not null default now(), created_by text,
  delivered_at timestamptz, done_at timestamptz, result text
);
create table if not exists sc_audit (id bigserial primary key, at timestamptz not null default now(), who text, action text, detail jsonb);

do $$ declare t text; begin
  foreach t in array array['sc_staff','sc_sessions','sc_login_attempts','sc_plants','sc_status','sc_alerts','sc_notify','sc_release','sc_commands','sc_audit'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
  end loop;
end $$;

-- ── helpers (not callable from outside) ──
create or replace function _sc_staff(p_token text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select s.name from sc_sessions x join sc_staff s on s.id = x.staff_id
   where p_token is not null and x.token = p_token and x.expires_at > now() and s.active limit 1;
$$;
revoke execute on function _sc_staff(text) from public, anon, authenticated;

-- red / orange from a plant's report (the same codes as the plant's system health)
create or replace function _sc_level(p_report jsonb, out level text, out problems jsonb) language plpgsql immutable as $$
declare a jsonb := coalesce(p_report -> 'attention', '[]'::jsonb); bad text[] := '{}'; warn text[] := '{}'; c text;
begin
  for c in select jsonb_array_elements_text(a) loop
    if c in ('chain_broken', 'standby_down', 'ups_on_battery', 'ups_low_battery', 'nightly_check_problems', 'nightly_check_missing', 'backup_stale')
      then bad := bad || c; else warn := warn || c; end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(coalesce(p_report -> 'tablets', '[]'::jsonb)) t
              where (t ->> 'online')::boolean is false and coalesce((p_report ->> 'working')::boolean, false)) then
    warn := warn || 'tablet_offline_while_working'::text;
  end if;
  level := case when cardinality(bad) > 0 then 'bad' when cardinality(warn) > 0 then 'warn' else 'ok' end;
  problems := to_jsonb(bad || warn);
end $$;

-- ── the plant server reports (anon key + the plant's code and secret) ──
create or replace function sc_report(p_code text, p_secret text, p_report jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare p sc_plants; old sc_status; lv record; v_cmds jsonb; r sc_release; c text;
begin
  select * into p from sc_plants where code = p_code;
  if p.code is null or p_secret is null or crypt(p_secret, p.secret_hash) <> p.secret_hash then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_report) <> 'object' or length(p_report::text) > 200000 then
    return jsonb_build_object('ok', false, 'error', 'bad_report');
  end if;
  select * into old from sc_status where code = p_code for update;
  select * into lv from _sc_level(p_report);
  insert into sc_status (code, level, problems, report, app_version, working, reported_at)
  values (p_code, lv.level, lv.problems, p_report, left(p_report ->> 'appVersion', 20), (p_report ->> 'working')::boolean, now())
  on conflict (code) do update set level = excluded.level, problems = excluded.problems, report = excluded.report,
    app_version = excluded.app_version, working = excluded.working, reported_at = now();
  -- a new problem → an alert (once per problem until it is gone)
  for c in select jsonb_array_elements_text(lv.problems) loop
    if old.code is null or not (coalesce(old.problems, '[]'::jsonb) ? c) then
      insert into sc_alerts (code, level, text)
      values (p_code, case when c in ('chain_broken', 'standby_down', 'ups_on_battery', 'ups_low_battery', 'nightly_check_problems',
                                      'nightly_check_missing', 'backup_stale') then 'bad' else 'warn' end, c);
    end if;
  end loop;
  -- problems that are gone close their alerts
  update sc_alerts set resolved_at = now() where code = p_code and resolved_at is null and not (lv.problems ? text) and text <> 'no_report';
  update sc_alerts set resolved_at = now() where code = p_code and resolved_at is null and text = 'no_report';
  -- what the plant should do: the current release, and commands from the support center
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'cmd', cmd) order by id), '[]'::jsonb) into v_cmds
    from sc_commands where code = p_code and delivered_at is null;
  update sc_commands set delivered_at = now() where code = p_code and delivered_at is null;
  select * into r from sc_release where id = 1;
  return jsonb_build_object('ok', true, 'level', lv.level, 'commands', v_cmds,
    'release', case when r.version is not null then jsonb_build_object('version', r.version, 'appUrl', r.app_url, 'appSha256', r.app_sha256,
                                                                      'sqlUrl', r.sql_url, 'sqlSha256', r.sql_sha256) end);
end $$;
revoke execute on function sc_report(text, text, jsonb) from public;
grant execute on function sc_report(text, text, jsonb) to anon, authenticated;

create or replace function sc_command_done(p_code text, p_secret text, p_id bigint, p_result text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare p sc_plants;
begin
  select * into p from sc_plants where code = p_code;
  if p.code is null or p_secret is null or crypt(p_secret, p.secret_hash) <> p.secret_hash then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  update sc_commands set done_at = now(), result = left(p_result, 500) where id = p_id and code = p_code;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_command_done(text, text, bigint, text) from public;
grant execute on function sc_command_done(text, text, bigint, text) to anon, authenticated;

-- ── the support staff ──
create or replace function sc_login(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s sc_staff; v_tok text; v_ip text := coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', 'local');
begin
  delete from sc_login_attempts where at < now() - interval '1 day';
  if (select count(*) from sc_login_attempts where not ok and at > now() - interval '15 minutes') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  select * into s from sc_staff where active and p_code is not null and crypt(p_code, code_hash) = code_hash limit 1;
  if s.id is null then
    insert into sc_login_attempts (ip, ok) values (v_ip, false); perform pg_sleep(0.5);
    return jsonb_build_object('ok', false, 'error', 'code_invalid');
  end if;
  insert into sc_sessions (staff_id) values (s.id) returning token into v_tok;
  insert into sc_audit (who, action) values (s.name, 'login');
  return jsonb_build_object('ok', true, 'token', v_tok, 'name', s.name);
end $$;
revoke execute on function sc_login(text) from public;
grant execute on function sc_login(text) to anon, authenticated;

-- all plants (a plant silent for 15 minutes is shown red: "no report")
create or replace function sc_overview(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); r sc_release;
begin
  if w is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  select * into r from sc_release where id = 1;
  return jsonb_build_object('ok', true, 'release', r.version, 'plants', coalesce((
    select jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name,
             'level', case when s.reported_at is null or s.reported_at < now() - interval '15 minutes' then 'bad' else s.level end,
             'problems', case when s.reported_at is null or s.reported_at < now() - interval '15 minutes' then '["no_report"]'::jsonb else s.problems end,
             'appVersion', s.app_version, 'working', s.working, 'reportedAt', s.reported_at,
             'openAlerts', (select count(*) from sc_alerts a where a.code = p.code and a.resolved_at is null))
           order by case when s.reported_at is null or s.reported_at < now() - interval '15 minutes' or s.level = 'bad' then 0
                         when s.level = 'warn' then 1 else 2 end, p.code)
      from sc_plants p left join sc_status s on s.code = p.code), '[]'::jsonb));
end $$;
revoke execute on function sc_overview(text) from public;
grant execute on function sc_overview(text) to anon, authenticated;

create or replace function sc_plant(p_token text, p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); p sc_plants; s sc_status;
begin
  if w is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  select * into p from sc_plants where code = p_code;
  if p.code is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  select * into s from sc_status where code = p_code;
  return jsonb_build_object('ok', true, 'code', p.code, 'name', p.name, 'level', s.level, 'problems', s.problems,
    'report', s.report, 'reportedAt', s.reported_at,
    'alerts', coalesce((select jsonb_agg(to_jsonb(a) - 'sent' order by a.id desc) from (select * from sc_alerts where code = p_code order by id desc limit 30) a), '[]'::jsonb),
    'commands', coalesce((select jsonb_agg(to_jsonb(c) order by c.id desc) from (select * from sc_commands where code = p_code order by id desc limit 10) c), '[]'::jsonb));
end $$;
revoke execute on function sc_plant(text, text) from public;
grant execute on function sc_plant(text, text) to anon, authenticated;

-- a new plant: its secret is shown ONCE (it goes into the plant server's gt-plant.conf)
create or replace function sc_plant_add(p_token text, p_code text, p_name text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); v_secret text := encode(gen_random_bytes(18), 'hex');
begin
  if w is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_code is null or p_code !~ '^[0-9]{3,8}$' or coalesce(trim(p_name), '') = '' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if exists (select 1 from sc_plants where code = p_code) then return jsonb_build_object('ok', false, 'error', 'code_taken'); end if;
  insert into sc_plants (code, name, secret_hash) values (p_code, left(trim(p_name), 60), crypt(v_secret, gen_salt('bf', 8)));
  insert into sc_audit (who, action, detail) values (w, 'plant_add', jsonb_build_object('code', p_code, 'name', p_name));
  return jsonb_build_object('ok', true, 'code', p_code, 'secret', v_secret);
end $$;
revoke execute on function sc_plant_add(text, text, text) from public;
grant execute on function sc_plant_add(text, text, text) to anon, authenticated;

-- how the alerts are sent: e-mail / SMS / WhatsApp, each one on or off, with its addresses
create or replace function sc_notify_get(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if _sc_staff(p_token) is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  return jsonb_build_object('ok', true, 'settings', (select settings from sc_notify where id = 1));
end $$;
revoke execute on function sc_notify_get(text) from public;
grant execute on function sc_notify_get(text) to anon, authenticated;

create or replace function sc_notify_set(p_token text, p_settings jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); ch text; v jsonb := '{}'::jsonb; e jsonb;
begin
  if w is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  foreach ch in array array['email', 'sms', 'whatsapp'] loop
    e := coalesce(p_settings -> ch, '{}'::jsonb);
    if jsonb_typeof(e -> 'to') is distinct from 'array' and e ? 'to' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(e -> 'to', '[]'::jsonb)) t
                where length(t) > 120 or (ch = 'email' and t !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') or (ch <> 'email' and t !~ '^\+[0-9]{8,15}$')) then
      return jsonb_build_object('ok', false, 'error', 'bad_value', 'channel', ch);
    end if;
    v := v || jsonb_build_object(ch, jsonb_build_object('on', coalesce((e ->> 'on')::boolean, false), 'to', coalesce(e -> 'to', '[]'::jsonb)));
  end loop;
  v := v || jsonb_build_object('minLevel', case when p_settings ->> 'minLevel' = 'warn' then 'warn' else 'bad' end);
  update sc_notify set settings = v, updated_at = now() where id = 1;
  insert into sc_audit (who, action, detail) values (w, 'notify_set', v);
  return jsonb_build_object('ok', true, 'settings', v);
end $$;
revoke execute on function sc_notify_set(text, jsonb) from public;
grant execute on function sc_notify_set(text, jsonb) to anon, authenticated;

-- "send an update to all plants" (each plant checks the file's sha256 before installing)
create or replace function sc_release_set(p_token text, p_version text, p_app_url text, p_app_sha256 text,
                                          p_sql_url text default null, p_sql_sha256 text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token);
begin
  if w is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_version !~ '^[a-z][0-9][0-9A-Za-z._-]{0,18}$' or p_app_url !~ '^https://' or p_app_sha256 !~ '^[0-9a-f]{64}$'
     or (p_sql_url is not null and (p_sql_url !~ '^https://' or coalesce(p_sql_sha256, '') !~ '^[0-9a-f]{64}$')) then
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  update sc_release set version = p_version, app_url = p_app_url, app_sha256 = p_app_sha256,
                        sql_url = p_sql_url, sql_sha256 = p_sql_sha256, set_at = now(), set_by = w where id = 1;
  insert into sc_audit (who, action, detail) values (w, 'release', jsonb_build_object('version', p_version, 'app', p_app_url, 'sql', p_sql_url));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_release_set(text, text, text, text, text, text) from public;
grant execute on function sc_release_set(text, text, text, text, text, text) to anon, authenticated;

-- a fix from far: restart the backup server / reload the tablets / update now / run the nightly check
create or replace function sc_command_add(p_token text, p_code text, p_cmd text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); v_id bigint;
begin
  if w is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_cmd not in ('restart_standby', 'reload_tablets', 'update_now', 'run_nightly_check') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if not exists (select 1 from sc_plants where code = p_code) then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  insert into sc_commands (code, cmd, created_by) values (p_code, p_cmd, w) returning id into v_id;
  insert into sc_audit (who, action, detail) values (w, 'command', jsonb_build_object('code', p_code, 'cmd', p_cmd));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function sc_command_add(text, text, text) from public;
grant execute on function sc_command_add(text, text, text) to anon, authenticated;

-- ── for notify.sh (runs with the database owner, never the app) ──
-- a plant that stopped reporting gets one "no_report" alert
create or replace function _sc_check_silent() returns integer language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare n int := 0; p record;
begin
  for p in select pl.code from sc_plants pl left join sc_status s on s.code = pl.code
            where s.reported_at < now() - interval '15 minutes'
              and not exists (select 1 from sc_alerts a where a.code = pl.code and a.text = 'no_report' and a.resolved_at is null) loop
    insert into sc_alerts (code, level, text) values (p.code, 'bad', 'no_report'); n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function _sc_check_silent() from public, anon, authenticated;

-- the first staff member (run once by the manufacturer in the SQL editor):
--   insert into sc_staff (name, code_hash) values ('Support 1', crypt('<a long code>', gen_salt('bf', 8)));
notify pgrst, 'reload schema';
