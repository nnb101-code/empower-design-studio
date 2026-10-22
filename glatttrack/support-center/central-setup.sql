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
-- (round-2 review P-up1) a release is signed by the manufacturer's key (release-sign.sh); the plants check it
alter table sc_release add column if not exists manifest text;
alter table sc_release add column if not exists sig text;
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
declare a jsonb := case when jsonb_typeof(p_report -> 'attention') = 'array' then p_report -> 'attention' else '[]'::jsonb end;   -- (round 23) a wrong type is no crash
        bad text[] := '{}'; warn text[] := '{}'; c text;
begin
  for c in select left(e #>> '{}', 60) from jsonb_array_elements(a) e where jsonb_typeof(e) = 'string' loop
    if c in ('chain_broken', 'standby_down', 'ups_on_battery', 'ups_low_battery', 'nightly_check_problems', 'nightly_check_missing', 'backup_stale')
      then bad := bad || c; else warn := warn || c; end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_report -> 'tablets') = 'array' then p_report -> 'tablets' else '[]'::jsonb end) t
              where jsonb_typeof(t) = 'object' and t -> 'online' = 'false'::jsonb and p_report -> 'working' = 'true'::jsonb) then
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
    from sc_commands where code = p_code and done_at is null
                       and (delivered_at is null or delivered_at < now() - interval '15 minutes');   -- (round-2 review C-cmd1) an answer lost on the way: sent again
  update sc_commands set delivered_at = now() where code = p_code and done_at is null
                       and (delivered_at is null or delivered_at < now() - interval '15 minutes');
  select * into r from sc_release where id = 1;
  return jsonb_build_object('ok', true, 'level', lv.level, 'commands', v_cmds,
    'release', case when r.version is not null then jsonb_build_object('version', r.version, 'appUrl', r.app_url, 'appSha256', r.app_sha256,
                                                                      'sqlUrl', r.sql_url, 'sqlSha256', r.sql_sha256, 'manifest', r.manifest, 'sig', r.sig) end);
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
    'commands', coalesce((select jsonb_agg(to_jsonb(c) - 'payload' order by c.id desc) from (select * from sc_commands where code = p_code order by id desc limit 10) c), '[]'::jsonb));
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
  if w is null or not _sc_can(p_token, 'plants_write') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;   -- v10.38: admin / support
  foreach ch in array array['email', 'sms', 'whatsapp'] loop
    e := coalesce(p_settings -> ch, '{}'::jsonb);
    if jsonb_typeof(e -> 'to') is distinct from 'array' and e ? 'to' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
    if e ? 'on' and jsonb_typeof(e -> 'on') <> 'boolean' then return jsonb_build_object('ok', false, 'error', 'bad_value', 'channel', ch); end if;   -- (full review C3)
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

-- "send an update to all plants": only a release signed on the manufacturer's computer (release-sign.sh). The center
-- keeps what was signed and the signature and gives both to the plants; each plant checks the signature with the
-- manufacturer's public key and every file's sha256 — the center itself cannot make a release the plants accept.
drop function if exists sc_release_set(text, text, text, text, text, text);
create or replace function sc_release_set(p_token text, p_version text, p_app_url text, p_app_sha256 text,
                                          p_sql_url text, p_sql_sha256 text, p_manifest text, p_sig text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); m jsonb;
begin
  if w is null or not _sc_can(p_token, 'plants_write') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;   -- v10.38: admin / support
  if p_version !~ '^[a-z][0-9][0-9A-Za-z._-]{0,18}$' or p_app_url !~ '^https://' or p_app_sha256 !~ '^[0-9a-f]{64}$'
     or (p_sql_url is not null and (p_sql_url !~ '^https://' or coalesce(p_sql_sha256, '') !~ '^[0-9a-f]{64}$'))
     or (p_sql_url is null and p_sql_sha256 is not null) then
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  begin m := p_manifest::jsonb; exception when others then m := null; end;
  if m is null or length(p_manifest) > 1000 or coalesce(p_sig, '') !~ '^[A-Za-z0-9+/]{86}==$'
     or m ->> 'version' is distinct from p_version or m ->> 'app' is distinct from p_app_sha256
     or m ->> 'sql' is distinct from p_sql_sha256 then
    return jsonb_build_object('ok', false, 'error', 'not_signed');
  end if;
  update sc_release set version = p_version, app_url = p_app_url, app_sha256 = p_app_sha256,
                        sql_url = p_sql_url, sql_sha256 = p_sql_sha256, manifest = p_manifest, sig = p_sig, set_at = now(), set_by = w where id = 1;
  insert into sc_audit (who, action, detail) values (w, 'release', jsonb_build_object('version', p_version, 'app', p_app_url, 'sql', p_sql_url, 'signed', true));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_release_set(text, text, text, text, text, text, text, text) from public;
grant execute on function sc_release_set(text, text, text, text, text, text, text, text) to anon, authenticated;

-- a fix from far: restart the backup server / reload the tablets / update now / run the nightly check
create or replace function sc_command_add(p_token text, p_code text, p_cmd text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); v_id bigint;
begin
  if w is null or not _sc_can(p_token, 'plants_write') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;   -- v10.38: admin / support
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
            where (s.reported_at < now() - interval '15 minutes'
                   or (s.code is null and pl.created_at < now() - interval '2 days'))   -- (full review C3) never reported at all
              and not exists (select 1 from sc_alerts a where a.code = pl.code and a.text = 'no_report' and a.resolved_at is null) loop
    insert into sc_alerts (code, level, text) values (p.code, 'bad', 'no_report'); n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function _sc_check_silent() from public, anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════════
-- v10.38 (owner): THE MANUFACTURER CENTER — staff roles, tickets, usage and billing
--   roles: admin (everything, staff, rates) · support (plants, tickets, commands, updates) ·
--          finance (billing only) · viewer (sees everything, changes nothing). Every action is audited.
--   tickets: every problem report of every plant (the ⚠ on a screen, the team leader's "report to support"),
--            status new / working / closed, who handles it, notes; the plant sees the status.
--   usage:   each plant sends ONLY a daily total (animals, kg) — no numbers, no rulings, no names.
--   billing: per plant — by kg, by animal or a fixed monthly sum (+ a monthly minimum); paid / not paid.
-- ══════════════════════════════════════════════════════════════════════════════
alter table sc_staff add column if not exists role text not null default 'admin';
alter table sc_plants add column if not exists hold_updates boolean not null default false;   -- (full review C4) out of the automatic release
alter table sc_staff drop constraint if exists sc_staff_role_ok;
alter table sc_staff add constraint sc_staff_role_ok check (role in ('admin', 'support', 'finance', 'viewer'));

create table if not exists sc_tickets (
  code text not null references sc_plants(code) on delete cascade,
  key text not null check (key ~ '^[A-Za-z0-9:_-]{1,40}$'),
  at timestamptz not null,
  source text not null check (source in ('station', 'leader')),
  screen text, message text not null,
  status text not null default 'new' check (status in ('new', 'working', 'closed')),
  assignee text, notes jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (code, key));
create table if not exists sc_usage (
  code text not null references sc_plants(code) on delete cascade,
  day date not null, animals integer not null default 0 check (animals between 0 and 100000),
  kg numeric not null default 0 check (kg >= 0 and kg < 100000000),
  updated_at timestamptz not null default now(),
  primary key (code, day));
create table if not exists sc_billing (
  code text primary key references sc_plants(code) on delete cascade,
  mode text not null default 'kg' check (mode in ('kg', 'animal', 'monthly')),
  rate numeric not null default 0 check (rate >= 0 and rate < 1000000),
  monthly_min numeric not null default 0 check (monthly_min >= 0 and monthly_min < 100000000),
  currency text not null default '₪' check (length(currency) between 1 and 5),
  updated_at timestamptz not null default now(), updated_by text);
create table if not exists sc_paid (
  code text not null references sc_plants(code) on delete cascade,
  month text not null check (month ~ '^[0-9]{4}-[0-9]{2}$'),
  paid boolean not null default false, at timestamptz not null default now(), by text,
  primary key (code, month));
do $$ declare t text; begin
  foreach t in array array['sc_tickets','sc_usage','sc_billing','sc_paid'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
  end loop;
end $$;

-- the staff member's role (null = not logged in)
create or replace function _sc_role(p_token text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select s.role from sc_sessions x join sc_staff s on s.id = x.staff_id
   where p_token is not null and x.token = p_token and x.expires_at > now() and s.active limit 1;
$$;
revoke execute on function _sc_role(text) from public, anon, authenticated;
-- may this role do this? plants (see plants / tickets) · plants_write (commands, updates, alerts, tickets) ·
-- plant_add · billing (see) · billing_write · staff
create or replace function _sc_can(p_token text, p_what text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(case p_what
    when 'plants'        then _sc_role(p_token) in ('admin', 'support', 'viewer')
    when 'plants_write'  then _sc_role(p_token) in ('admin', 'support')
    when 'plant_add'     then _sc_role(p_token) = 'admin'
    when 'billing'       then _sc_role(p_token) in ('admin', 'finance', 'viewer')
    when 'billing_write' then _sc_role(p_token) in ('admin', 'finance')
    when 'staff'         then _sc_role(p_token) = 'admin'
  end, false);
$$;
revoke execute on function _sc_can(text, text) from public, anon, authenticated;

-- the plant's report also carries its problem reports and its daily totals; the answer carries the
-- status of its tickets (what the team leader sees)
-- (round 23) a date that cannot be read → null (the ticket keeps the time it arrived)
create or replace function _sc_ts(p text) returns timestamptz language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin return p::timestamptz; exception when others then return null; end $$;
revoke execute on function _sc_ts(text) from public, anon, authenticated;

create or replace function _sc_take_report_extras(p_code text, p_report jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare x jsonb;
begin
  for x in select e from jsonb_array_elements(case when jsonb_typeof(p_report -> 'issues') = 'array' then p_report -> 'issues' else '[]'::jsonb end) e limit 300 loop
    continue when coalesce(x ->> 'key', '') !~ '^[A-Za-z0-9:_-]{1,40}$' or coalesce(trim(x ->> 'message'), '') = '';
    begin   -- (round 23) one bad value (a date, a number) skips that line only, not the whole report
    insert into sc_tickets (code, key, at, source, screen, message)
    values (p_code, x ->> 'key', coalesce(least(_sc_ts(x ->> 'at'), now()), now()),
            case when x ->> 'source' = 'leader' then 'leader' else 'station' end, left(x ->> 'screen', 40), left(x ->> 'message', 1000))
    on conflict (code, key) do nothing;
    exception when others then null; end;
  end loop;
  for x in select e from jsonb_array_elements(case when jsonb_typeof(p_report -> 'usage') = 'array' then p_report -> 'usage' else '[]'::jsonb end) e limit 60 loop
    continue when coalesce(x ->> 'day', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';
    begin
    insert into sc_usage (code, day, animals, kg)
    values (p_code, (x ->> 'day')::date, least(greatest(coalesce((x ->> 'animals')::int, 0), 0), 100000), least(greatest(coalesce((x ->> 'kg')::numeric, 0), 0), 99999999))
    on conflict (code, day) do update set animals = excluded.animals, kg = excluded.kg, updated_at = now();
    exception when others then null; end;
  end loop;
  delete from sc_tickets where code = p_code and status = 'closed' and updated_at < now() - interval '1 year';   -- (review)
  delete from sc_usage where code = p_code and day < current_date - 1100;
  return coalesce((select jsonb_agg(jsonb_build_object('key', t.key, 'status', t.status, 'at', t.updated_at, 'reply', left(t.notes -> -1 ->> 'text', 300)) order by t.at desc)
                     from (select * from sc_tickets where code = p_code and at > now() - interval '30 days' order by at desc limit 100) t), '[]'::jsonb);
end $$;
revoke execute on function _sc_take_report_extras(text, jsonb) from public, anon, authenticated;

create or replace function sc_report(p_code text, p_secret text, p_report jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare p sc_plants; old sc_status; lv record; v_cmds jsonb; r sc_release; c text; v_tickets jsonb;
begin
  select * into p from sc_plants where code = p_code;
  if p.code is null or p_secret is null or crypt(p_secret, p.secret_hash) <> p.secret_hash then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if jsonb_typeof(p_report) <> 'object' or length(p_report::text) > 400000 then
    return jsonb_build_object('ok', false, 'error', 'bad_report');
  end if;
  select * into old from sc_status where code = p_code for update;
  select * into lv from _sc_level(p_report);
  insert into sc_status (code, level, problems, report, app_version, working, reported_at)
  values (p_code, lv.level, lv.problems, p_report - 'issues' - 'usage', left(p_report ->> 'appVersion', 20), case when jsonb_typeof(p_report -> 'working') = 'boolean' then (p_report -> 'working')::boolean end, now())
  on conflict (code) do update set level = excluded.level, problems = excluded.problems, report = excluded.report,
    app_version = excluded.app_version, working = excluded.working, reported_at = now();
  for c in select jsonb_array_elements_text(lv.problems) loop
    if old.code is null or not (coalesce(old.problems, '[]'::jsonb) ? c) then
      insert into sc_alerts (code, level, text)
      values (p_code, case when c in ('chain_broken', 'standby_down', 'ups_on_battery', 'ups_low_battery', 'nightly_check_problems',
                                      'nightly_check_missing', 'backup_stale') then 'bad' else 'warn' end, c);
    end if;
  end loop;
  update sc_alerts set resolved_at = now() where code = p_code and resolved_at is null and not (lv.problems ? text) and text <> 'no_report';
  update sc_alerts set resolved_at = now() where code = p_code and resolved_at is null and text = 'no_report';
  v_tickets := _sc_take_report_extras(p_code, p_report);
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'cmd', cmd) || case when payload is not null then jsonb_build_object('payload', payload) else '{}'::jsonb end order by id), '[]'::jsonb) into v_cmds
    from sc_commands where code = p_code and done_at is null
                       and (delivered_at is null or delivered_at < now() - interval '15 minutes');   -- (round-2 review C-cmd1) an answer lost on the way: sent again
  update sc_commands set delivered_at = now() where code = p_code and done_at is null
                       and (delivered_at is null or delivered_at < now() - interval '15 minutes');
  select * into r from sc_release where id = 1;
  return jsonb_build_object('ok', true, 'level', lv.level, 'commands', v_cmds, 'tickets', v_tickets,
    -- (full review C4) a plant held out of the automatic release gets it only by "update this plant now" (the release is sent with that command)
    'release', case when r.version is not null and (not p.hold_updates or exists (select 1 from jsonb_array_elements(v_cmds) cm where cm ->> 'cmd' = 'update_now')) then jsonb_build_object('version', r.version, 'appUrl', r.app_url, 'appSha256', r.app_sha256,
                                                                      'sqlUrl', r.sql_url, 'sqlSha256', r.sql_sha256, 'manifest', r.manifest, 'sig', r.sig) end);
end $$;
revoke execute on function sc_report(text, text, jsonb) from public;
grant execute on function sc_report(text, text, jsonb) to anon, authenticated;

-- the login says the role (the page shows only what the role may see)
create or replace function sc_login(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s sc_staff; v_tok text; v_ip text := coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', 'local');
begin
  delete from sc_login_attempts where at < now() - interval '1 day';
  delete from sc_sessions where expires_at < now() - interval '1 day';   -- (review) old sessions do not pile up
  -- (review) counted per address: someone typing wrong codes locks only himself out, not the whole team;
  -- a high limit for everyone together still stops a flood (the codes are long and bcrypt — not guessable anyway)
  -- (full review C2) the address the platform saw: Cloudflare's / the proxy's own header, else the LAST address of
  -- x-forwarded-for (the one the proxy added) — the first one is whatever the caller wrote
  v_ip := left(trim(coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'cf-connecting-ip',
                             nullif(current_setting('request.headers', true), '')::json ->> 'x-real-ip',
                             (regexp_split_to_array(v_ip, '\s*,\s*'))[cardinality(regexp_split_to_array(v_ip, '\s*,\s*'))])), 64);
  -- (audit) one attempt at a time from the same address: many at the same moment cannot pass the limit of 10
  perform pg_advisory_xact_lock(hashtext('sc_login:' || coalesce(v_ip, '')));
  if (select count(*) from sc_login_attempts where not ok and ip = v_ip and at > now() - interval '15 minutes') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  -- a flood from many addresses slows every attempt down, but never locks the whole team out
  if (select count(*) from sc_login_attempts where not ok and at > now() - interval '15 minutes') >= 500 then perform pg_sleep(2); end if;
  select * into s from sc_staff where active and p_code is not null and crypt(p_code, code_hash) = code_hash limit 1;
  if s.id is null then
    insert into sc_login_attempts (ip, ok) values (v_ip, false); perform pg_sleep(0.5);
    return jsonb_build_object('ok', false, 'error', 'code_invalid');
  end if;
  insert into sc_sessions (staff_id) values (s.id) returning token into v_tok;
  insert into sc_audit (who, action) values (s.name, 'login');
  return jsonb_build_object('ok', true, 'token', v_tok, 'name', s.name, 'role', s.role);
end $$;
revoke execute on function sc_login(text) from public;
grant execute on function sc_login(text) to anon, authenticated;

create or replace function sc_whoami(p_token text) returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when _sc_staff(p_token) is null then jsonb_build_object('ok', false, 'error', 'unauthorized')
              else jsonb_build_object('ok', true, 'name', _sc_staff(p_token), 'role', _sc_role(p_token)) end;
$$;
revoke execute on function sc_whoami(text) from public;
grant execute on function sc_whoami(text) to anon, authenticated;

-- the existing screens, now by role
create or replace function sc_overview(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r sc_release;
begin
  if not _sc_can(p_token, 'plants') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  select * into r from sc_release where id = 1;
  return jsonb_build_object('ok', true, 'release', r.version, 'plants', coalesce((
    select jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name,
             'level', case when s.reported_at is null or s.reported_at < now() - interval '15 minutes' then 'bad' else s.level end,
             'problems', case when s.reported_at is null or s.reported_at < now() - interval '15 minutes' then '["no_report"]'::jsonb else s.problems end,
             'appVersion', s.app_version, 'working', s.working, 'reportedAt', s.reported_at,
             'openAlerts', (select count(*) from sc_alerts a where a.code = p.code and a.resolved_at is null),
             'openTickets', (select count(*) from sc_tickets t where t.code = p.code and t.status <> 'closed'))
           order by case when s.reported_at is null or s.reported_at < now() - interval '15 minutes' or s.level = 'bad' then 0
                         when s.level = 'warn' then 1 else 2 end, p.code)
      from sc_plants p left join sc_status s on s.code = p.code), '[]'::jsonb));
end $$;
revoke execute on function sc_overview(text) from public;
grant execute on function sc_overview(text) to anon, authenticated;

-- one month's bill of one plant
create or replace function _sc_bill(p_code text, p_month text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare b sc_billing; v_an int; v_kg numeric; v_amt numeric; d0 date := (p_month || '-01')::date;
begin
  select * into b from sc_billing where code = p_code;
  select coalesce(sum(animals), 0), coalesce(sum(kg), 0) into v_an, v_kg from sc_usage
   where code = p_code and day >= d0 and day < (d0 + interval '1 month')::date;
  v_amt := case coalesce(b.mode, 'kg') when 'kg' then v_kg * coalesce(b.rate, 0) when 'animal' then v_an * coalesce(b.rate, 0) else coalesce(b.rate, 0) end;
  v_amt := round(greatest(v_amt, coalesce(b.monthly_min, 0)), 2);
  return jsonb_build_object('code', p_code, 'month', p_month, 'animals', v_an, 'kg', round(v_kg, 1),
    'mode', coalesce(b.mode, 'kg'), 'rate', coalesce(b.rate, 0), 'monthlyMin', coalesce(b.monthly_min, 0), 'currency', coalesce(b.currency, '₪'),
    'amount', v_amt, 'paid', coalesce((select paid from sc_paid where code = p_code and month = p_month), false));
end $$;
revoke execute on function _sc_bill(text, text) from public, anon, authenticated;

create or replace function sc_plant(p_token text, p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare p sc_plants; s sc_status;
begin
  if not _sc_can(p_token, 'plants') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  select * into p from sc_plants where code = p_code;
  if p.code is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  select * into s from sc_status where code = p_code;
  return jsonb_build_object('ok', true, 'code', p.code, 'name', p.name, 'level', s.level, 'problems', s.problems,
    'report', s.report, 'reportedAt', s.reported_at,
    'alerts', coalesce((select jsonb_agg(to_jsonb(a) - 'sent' order by a.id desc) from (select * from sc_alerts where code = p_code order by id desc limit 30) a), '[]'::jsonb),
    'commands', coalesce((select jsonb_agg(to_jsonb(c) - 'payload' order by c.id desc) from (select * from sc_commands where code = p_code order by id desc limit 10) c), '[]'::jsonb),
    'openTickets', (select count(*) from sc_tickets t where t.code = p_code and t.status <> 'closed'),
    'holdUpdates', p.hold_updates,
    'bill', case when _sc_can(p_token, 'billing') then _sc_bill(p_code, to_char(now(), 'YYYY-MM')) end);
end $$;
revoke execute on function sc_plant(text, text) from public;
grant execute on function sc_plant(text, text) to anon, authenticated;

create or replace function sc_plant_add(p_token text, p_code text, p_name text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); v_secret text := encode(gen_random_bytes(18), 'hex');
begin
  if not _sc_can(p_token, 'plant_add') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_code is null or p_code !~ '^[0-9]{3,8}$' or coalesce(trim(p_name), '') = '' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  -- (round-3 review C-L1) the name goes into alerts (e-mail subject / SMS / WhatsApp lines): no new line or control character
  if p_name ~ '[[:cntrl:]]' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if exists (select 1 from sc_plants where code = p_code) then return jsonb_build_object('ok', false, 'error', 'code_taken'); end if;
  insert into sc_plants (code, name, secret_hash) values (p_code, left(trim(p_name), 60), crypt(v_secret, gen_salt('bf', 8)));
  insert into sc_audit (who, action, detail) values (w, 'plant_add', jsonb_build_object('code', p_code, 'name', p_name));
  return jsonb_build_object('ok', true, 'code', p_code, 'secret', v_secret);
end $$;
revoke execute on function sc_plant_add(text, text, text) from public;
grant execute on function sc_plant_add(text, text, text) to anon, authenticated;

create or replace function sc_notify_get(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _sc_can(p_token, 'plants') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  return jsonb_build_object('ok', true, 'settings', (select settings from sc_notify where id = 1));
end $$;
revoke execute on function sc_notify_get(text) from public;
grant execute on function sc_notify_get(text) to anon, authenticated;

-- the writes of the support center: admin / support only (finance and viewer get 'unauthorized')

-- tickets
create or replace function sc_tickets(p_token text, p_status text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _sc_can(p_token, 'plants') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  return jsonb_build_object('ok', true, 'tickets', coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'plant', p.name, 'key', t.key, 'at', t.at,
           'source', t.source, 'screen', t.screen, 'message', t.message, 'status', t.status, 'assignee', t.assignee, 'notes', t.notes, 'updatedAt', t.updated_at)
           order by case t.status when 'new' then 0 when 'working' then 1 else 2 end, t.at desc)
      from (select * from sc_tickets where (p_status is null or status = p_status) and (status <> 'closed' or updated_at > now() - interval '30 days')
             order by at desc limit 500) t join sc_plants p on p.code = t.code), '[]'::jsonb));
end $$;
revoke execute on function sc_tickets(text, text) from public;
grant execute on function sc_tickets(text, text) to anon, authenticated;

create or replace function sc_ticket_set(p_token text, p_code text, p_key text, p_status text default null, p_note text default null, p_assignee text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); t sc_tickets;
begin
  if not _sc_can(p_token, 'plants_write') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_status is not null and p_status not in ('new', 'working', 'closed') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into t from sc_tickets where code = p_code and key = p_key for update;
  if t.code is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  update sc_tickets set status = coalesce(p_status, status),
         assignee = coalesce(nullif(left(trim(p_assignee), 60), ''), case when p_status = 'working' and assignee is null then w else assignee end),
         notes = case when coalesce(trim(p_note), '') = '' then notes else notes || jsonb_build_array(jsonb_build_object('at', now(), 'by', w, 'text', left(trim(p_note), 1000))) end,
         updated_at = now()
   where code = p_code and key = p_key;
  insert into sc_audit (who, action, detail) values (w, 'ticket', jsonb_build_object('code', p_code, 'key', p_key, 'status', p_status, 'note', left(p_note, 200)));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_ticket_set(text, text, text, text, text, text) from public;
grant execute on function sc_ticket_set(text, text, text, text, text, text) to anon, authenticated;

-- billing
create or replace function sc_billing(p_token text, p_month text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_m text := coalesce(p_month, to_char(now(), 'YYYY-MM'));
begin
  if not _sc_can(p_token, 'billing') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if v_m !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  return jsonb_build_object('ok', true, 'month', v_m, 'rows', coalesce((select jsonb_agg(_sc_bill(p.code, v_m) || jsonb_build_object('name', p.name) order by p.code) from sc_plants p), '[]'::jsonb));
end $$;
revoke execute on function sc_billing(text, text) from public;
grant execute on function sc_billing(text, text) to anon, authenticated;

create or replace function sc_billing_set(p_token text, p_code text, p_mode text, p_rate numeric, p_monthly_min numeric default 0, p_currency text default '₪') returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token);
begin
  if not _sc_can(p_token, 'billing_write') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_mode not in ('kg', 'animal', 'monthly') or p_rate is null or p_rate < 0 or p_rate >= 1000000
     or coalesce(p_monthly_min, 0) < 0 or coalesce(p_monthly_min, 0) >= 100000000 or coalesce(length(p_currency), 0) not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  if not exists (select 1 from sc_plants where code = p_code) then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  insert into sc_billing (code, mode, rate, monthly_min, currency, updated_at, updated_by)
  values (p_code, p_mode, p_rate, coalesce(p_monthly_min, 0), p_currency, now(), w)
  on conflict (code) do update set mode = excluded.mode, rate = excluded.rate, monthly_min = excluded.monthly_min,
                                   currency = excluded.currency, updated_at = now(), updated_by = w;
  insert into sc_audit (who, action, detail) values (w, 'billing_set', jsonb_build_object('code', p_code, 'mode', p_mode, 'rate', p_rate, 'min', p_monthly_min, 'currency', p_currency));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_billing_set(text, text, text, numeric, numeric, text) from public;
grant execute on function sc_billing_set(text, text, text, numeric, numeric, text) to anon, authenticated;

create or replace function sc_paid_set(p_token text, p_code text, p_month text, p_paid boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token);
begin
  if not _sc_can(p_token, 'billing_write') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' or p_paid is null then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if not exists (select 1 from sc_plants where code = p_code) then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  insert into sc_paid (code, month, paid, at, by) values (p_code, p_month, p_paid, now(), w)
  on conflict (code, month) do update set paid = excluded.paid, at = now(), by = w;
  insert into sc_audit (who, action, detail) values (w, 'paid_set', jsonb_build_object('code', p_code, 'month', p_month, 'paid', p_paid));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_paid_set(text, text, text, boolean) from public;
grant execute on function sc_paid_set(text, text, text, boolean) to anon, authenticated;

-- staff (admin only)
create or replace function sc_staff_list(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _sc_can(p_token, 'staff') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  return jsonb_build_object('ok', true, 'staff', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', role, 'active', active, 'createdAt', created_at) order by created_at) from sc_staff), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(to_jsonb(a) order by a.id desc) from (select * from sc_audit order by id desc limit 100) a), '[]'::jsonb));
end $$;
revoke execute on function sc_staff_list(text) from public;
grant execute on function sc_staff_list(text) to anon, authenticated;

create or replace function sc_staff_add(p_token text, p_name text, p_code text, p_role text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); v_id uuid;
begin
  if not _sc_can(p_token, 'staff') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if coalesce(trim(p_name), '') = '' or length(p_name) > 60 or p_role not in ('admin', 'support', 'finance', 'viewer') then
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  if p_code is null or length(p_code) < 10 then return jsonb_build_object('ok', false, 'error', 'code_too_short'); end if;
  if exists (select 1 from sc_staff where active and crypt(p_code, code_hash) = code_hash) then return jsonb_build_object('ok', false, 'error', 'code_taken'); end if;
  insert into sc_staff (name, code_hash, role) values (trim(p_name), crypt(p_code, gen_salt('bf', 8)), p_role) returning id into v_id;
  insert into sc_audit (who, action, detail) values (w, 'staff_add', jsonb_build_object('name', trim(p_name), 'role', p_role));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function sc_staff_add(text, text, text, text) from public;
grant execute on function sc_staff_add(text, text, text, text) to anon, authenticated;

create or replace function sc_staff_set(p_token text, p_id uuid, p_role text default null, p_active boolean default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); s sc_staff;
begin
  if not _sc_can(p_token, 'staff') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_role is not null and p_role not in ('admin', 'support', 'finance', 'viewer') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  perform pg_advisory_xact_lock(hashtext('sc_staff_admins'));   -- (round-2 review C-adm1) two admins at the same moment: one after the other
  select * into s from sc_staff where id = p_id for update;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  -- the last active admin stays an active admin (nobody locks the center out)
  if s.role = 'admin' and s.active and (coalesce(p_role, 'admin') <> 'admin' or p_active is false)
     and (select count(*) from sc_staff where role = 'admin' and active) <= 1 then
    return jsonb_build_object('ok', false, 'error', 'last_admin');
  end if;
  update sc_staff set role = coalesce(p_role, role), active = coalesce(p_active, active) where id = p_id;
  if p_active is false then delete from sc_sessions where staff_id = p_id; end if;
  insert into sc_audit (who, action, detail) values (w, 'staff_set', jsonb_build_object('name', s.name, 'role', p_role, 'active', p_active));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_staff_set(text, uuid, text, boolean) from public;
grant execute on function sc_staff_set(text, uuid, text, boolean) to anon, authenticated;

-- (full review C4) hold one plant out of the automatic release (it updates only by "update this plant now")
create or replace function sc_plant_hold(p_token text, p_code text, p_hold boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token);
begin
  if not _sc_can(p_token, 'plants_write') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_hold is null then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  update sc_plants set hold_updates = p_hold where code = p_code;
  if not found then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  insert into sc_audit (who, action, detail) values (w, 'plant_hold', jsonb_build_object('code', p_code, 'hold', p_hold));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_plant_hold(text, text, boolean) from public;
grant execute on function sc_plant_hold(text, text, boolean) to anon, authenticated;

-- ── v10.38 (owner): a forgotten code — an admin gives a new code; an admin's one-time recovery code ──────────
-- A code is kept only as a bcrypt hash: nobody can read it back, it can only be replaced.
alter table sc_staff add column if not exists recovery_hash text;

-- the address the platform saw (the same rule as sc_login)
create or replace function _sc_client_ip() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare h json := nullif(current_setting('request.headers', true), '')::json; v text := coalesce(h ->> 'x-forwarded-for', 'local'); a text[];
begin
  a := regexp_split_to_array(v, '\s*,\s*');
  return left(trim(coalesce(h ->> 'cf-connecting-ip', h ->> 'x-real-ip', a[cardinality(a)])), 64);
end $$;
revoke execute on function _sc_client_ip() from public, anon, authenticated;

-- 16 letters / digits that cannot be mixed up (no 0/O, 1/I/L), shown as XXXX-XXXX-XXXX-XXXX
create or replace function _sc_recovery_code() returns text
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare al text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; b bytea := gen_random_bytes(16); v text := ''; i int;
begin
  for i in 0 .. 15 loop
    v := v || substr(al, 1 + (get_byte(b, i) % length(al)), 1) || case when i in (3, 7, 11) then '-' else '' end;
  end loop;
  return v;
end $$;
revoke execute on function _sc_recovery_code() from public, anon, authenticated;
create or replace function _sc_recovery_norm(p text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g'));
$$;
revoke execute on function _sc_recovery_norm(text) from public, anon, authenticated;

-- A. an admin gives a staff member a new code (the old one stops; that person's open sessions end)
create or replace function sc_staff_set_code(p_token text, p_id uuid, p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); s sc_staff;
begin
  if not _sc_can(p_token, 'staff') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_code is null or length(p_code) < 10 then return jsonb_build_object('ok', false, 'error', 'code_too_short'); end if;
  select * into s from sc_staff where id = p_id for update;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  if exists (select 1 from sc_staff where active and id <> p_id and crypt(p_code, code_hash) = code_hash) then
    return jsonb_build_object('ok', false, 'error', 'code_taken');
  end if;
  update sc_staff set code_hash = crypt(p_code, gen_salt('bf', 8)) where id = p_id;
  delete from sc_sessions where staff_id = p_id and token is distinct from p_token;
  insert into sc_audit (who, action, detail) values (w, 'staff_code', jsonb_build_object('name', s.name));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function sc_staff_set_code(text, uuid, text) from public;
grant execute on function sc_staff_set_code(text, uuid, text) to anon, authenticated;

-- B. an admin makes their own recovery code: shown ONCE (written on paper, kept in a safe); a new one replaces the old
create or replace function sc_recovery_new(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); v_id uuid; v text := _sc_recovery_code();
begin
  if w is null or _sc_role(p_token) is distinct from 'admin' then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  select x.staff_id into v_id from sc_sessions x where x.token = p_token;
  update sc_staff set recovery_hash = crypt(_sc_recovery_norm(v), gen_salt('bf', 8)) where id = v_id;
  insert into sc_audit (who, action) values (w, 'recovery_new');
  return jsonb_build_object('ok', true, 'recovery', v);
end $$;
revoke execute on function sc_recovery_new(text) from public;
grant execute on function sc_recovery_new(text) to anon, authenticated;
create or replace function sc_recovery_status(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if _sc_staff(p_token) is null then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  return jsonb_build_object('ok', true, 'has', exists (select 1 from sc_sessions x join sc_staff s on s.id = x.staff_id
                                                       where x.token = p_token and s.recovery_hash is not null));
end $$;
revoke execute on function sc_recovery_status(text) from public;
grant execute on function sc_recovery_status(text) to anon, authenticated;

-- B. the forgotten code: the recovery code + a new code. The recovery code works once; wrong tries count like
-- wrong logins (the same limit per address)
create or replace function sc_recover(p_recovery text, p_new_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_ip text := _sc_client_ip(); s sc_staff; v text := _sc_recovery_norm(p_recovery);
begin
  perform pg_advisory_xact_lock(hashtext('sc_login:' || coalesce(v_ip, '')));
  if (select count(*) from sc_login_attempts where not ok and ip = v_ip and at > now() - interval '15 minutes') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  if p_new_code is null or length(p_new_code) < 10 then return jsonb_build_object('ok', false, 'error', 'code_too_short'); end if;
  select * into s from sc_staff where active and role = 'admin' and recovery_hash is not null and length(v) = 16
                                  and crypt(v, recovery_hash) = recovery_hash limit 1 for update;
  if s.id is null then
    insert into sc_login_attempts (ip, ok) values (v_ip, false); perform pg_sleep(0.5);
    return jsonb_build_object('ok', false, 'error', 'code_invalid');
  end if;
  if exists (select 1 from sc_staff where active and id <> s.id and crypt(p_new_code, code_hash) = code_hash) then
    return jsonb_build_object('ok', false, 'error', 'code_taken');
  end if;
  update sc_staff set code_hash = crypt(p_new_code, gen_salt('bf', 8)), recovery_hash = null where id = s.id;
  delete from sc_sessions where staff_id = s.id;
  insert into sc_audit (who, action, detail) values (s.name, 'recovered', jsonb_build_object('ip', v_ip));
  return jsonb_build_object('ok', true, 'name', s.name);
end $$;
revoke execute on function sc_recover(text, text) from public;
grant execute on function sc_recover(text, text) to anon, authenticated;

-- a new admin gets their recovery code at once (shown once to the admin who adds them)
create or replace function sc_staff_add(p_token text, p_name text, p_code text, p_role text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); v_id uuid; v_rec text;
begin
  if not _sc_can(p_token, 'staff') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if coalesce(trim(p_name), '') = '' or length(p_name) > 60 or p_role not in ('admin', 'support', 'finance', 'viewer') then
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  if p_code is null or length(p_code) < 10 then return jsonb_build_object('ok', false, 'error', 'code_too_short'); end if;
  if exists (select 1 from sc_staff where active and crypt(p_code, code_hash) = code_hash) then return jsonb_build_object('ok', false, 'error', 'code_taken'); end if;
  if p_role = 'admin' then v_rec := _sc_recovery_code(); end if;
  insert into sc_staff (name, code_hash, role, recovery_hash)
  values (trim(p_name), crypt(p_code, gen_salt('bf', 8)), p_role, case when v_rec is not null then crypt(_sc_recovery_norm(v_rec), gen_salt('bf', 8)) end)
  returning id into v_id;
  insert into sc_audit (who, action, detail) values (w, 'staff_add', jsonb_build_object('name', trim(p_name), 'role', p_role));
  return jsonb_build_object('ok', true, 'id', v_id) || case when v_rec is not null then jsonb_build_object('recovery', v_rec) else '{}'::jsonb end;
end $$;
revoke execute on function sc_staff_add(text, text, text, text) from public;
grant execute on function sc_staff_add(text, text, text, text) to anon, authenticated;

-- ── v10.38 (owner): a new manufacturer code for one plant, signed by the manufacturer ──────────────────────
-- The page makes the bcrypt hash of the new code in the browser (the code never leaves it), the manufacturer signs
-- the request with the release key on its own computer (maker-code-sign.sh). The center only carries it: it can
-- not make or change one — the plant server checks the signature, the plant number and the time.
alter table sc_commands add column if not exists payload jsonb;
alter table sc_commands drop constraint if exists sc_commands_cmd_check;
alter table sc_commands add constraint sc_commands_cmd_check
  check (cmd in ('restart_standby', 'reload_tablets', 'update_now', 'run_nightly_check', 'set_maker_code'));
create or replace function sc_maker_code_send(p_token text, p_code text, p_manifest text, p_sig text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare w text := _sc_staff(p_token); m jsonb; v_id bigint;
begin
  if w is null or _sc_role(p_token) is distinct from 'admin' then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if not exists (select 1 from sc_plants where code = p_code) then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  begin m := p_manifest::jsonb; exception when others then return jsonb_build_object('ok', false, 'error', 'bad_value'); end;
  if length(p_manifest) > 1000 or jsonb_typeof(m) <> 'object' or m ->> 'kind' is distinct from 'maker_code' or m ->> 'plant' is distinct from p_code
     or coalesce(m ->> 'hash', '') !~ '^\$2[ab]\$1[0-2]\$[./A-Za-z0-9]{53}$' or coalesce(m ->> 'at', '') !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
     or coalesce(p_sig, '') !~ '^[A-Za-z0-9+/]{86}==$' then
    return jsonb_build_object('ok', false, 'error', 'not_signed');
  end if;
  -- one open request per plant: a newer one replaces the one not yet carried out
  update sc_commands set done_at = now(), result = 'replaced by a newer request' where code = p_code and cmd = 'set_maker_code' and done_at is null;
  insert into sc_commands (code, cmd, created_by, payload) values (p_code, 'set_maker_code', w, jsonb_build_object('manifest', p_manifest, 'sig', p_sig))
  returning id into v_id;
  insert into sc_audit (who, action, detail) values (w, 'maker_code_send', jsonb_build_object('code', p_code, 'at', m ->> 'at'));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function sc_maker_code_send(text, text, text, text) from public;
grant execute on function sc_maker_code_send(text, text, text, text) to anon, authenticated;

-- the first staff member (run once by the manufacturer in the SQL editor):
--   insert into sc_staff (name, code_hash, role) values ('Admin 1', extensions.crypt('<a long code>', extensions.gen_salt('bf', 8)), 'admin');
notify pgrst, 'reload schema';
