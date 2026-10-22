-- ============================================================================
-- GlattTrack — step 45: system health, test-mode auto-off, reasons for
-- exceptional actions
-- ============================================================================
--   1. Test mode switches itself off 8 hours after it was switched on.
--      plant_state 'testModeOnAt' is written by a trigger whenever the owner
--      sets testMode = 'on' (SQL only, as before); every on/off is written to
--      admin_audit. Every server check treats an older switch-on as OFF and
--      puts the flag back to 'off' (with an audit row) the first time a
--      read-write request notices it.
--        server_test_mode()      → boolean  (unchanged signature; false after expiry)
--        server_test_mode_info() → {on, on_at, expires_at, remaining_s, serverTime}   read-only, anyone
--   2. system_health(p_token text) → jsonb   team leader / owner session only
--        {ok, schemaStep, serverTime, devices:{active, offline, retired, unpaired_requests},
--         testMode:{on, on_at, expires_at}, lastBackupVerifiedAt, lastBackupFailedAt, backup:{status, ageHours},
--         eventChain:{ok, checked, brokenAt, reason, total},
--         security:{revokedDeviceWrites24h, failedLogins24h, rejectedCorrections24h, rateLimited24h, chainBroken},
--         attention:[codes], info:[codes]}                         error: unauthorized
--      attention codes: backup_stale, chain_broken, test_mode_on, devices_offline,
--                       failed_logins, revoked_device_writes;  info: backup_unknown
--      Write attempts with a revoked / retired device key are now counted
--      (revoked_device_writes, one row per device per minute).
--   3. A reason (p_reason text) is REQUIRED for exceptional actions — without
--      one: {ok:false, error:'reason_required'}:
--        device_pair(p_token, p_code, p_role, p_index, p_replace, p_device_name, p_reason)   only when p_replace
--        device_manage(p_token, p_device_id, p_action, p_reason)    retire / reactivate (rename: p_reason = the new name)
--        device_unpair(p_token, p_device_id, p_reason)
--        support_access_set(p_token, p_hours, p_reason)             only when p_hours > 0
--        manufacturer_set_billing(p_token, p_enabled, p_price, p_currency, p_reason)
--        support_force_reload(p_token, p_reason)
--        push_settings(p_settings, p_device_id, p_token, p_reason)  only for a manufacturer session
--      p_reason is the LAST argument with default null, so old calls without
--      it still resolve (same grants as before). The reason is stored in
--      device_lifecycle_events.reason / admin_audit.detail.reason.
-- Safe to run more than once. Run after step 44.
-- Re-running an OLDER step file (33–44) after this one: first drop the five
-- step-45 signatures (see the "re-run guard" at the top of
-- glatttrack-schema-full.sql), then run step 45 again — otherwise step 43's
-- self-check finds two push_settings() and stops.
-- ============================================================================

-- ── 1. test mode: switched-on time, 8-hour limit, audit ─────────────────────
create or replace function _ts_or_null(p text) returns timestamptz
language plpgsql stable set search_path = public, extensions, pg_temp as $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}' then return null; end if;
  return p::timestamptz;
exception when others then return null;
end $$;
revoke execute on function _ts_or_null(text) from public, anon, authenticated;

create or replace function _test_mode_max() returns interval
language sql immutable set search_path = public, extensions, pg_temp as $$ select interval '8 hours' $$;
revoke execute on function _test_mode_max() from public, anon, authenticated;

-- the flag as the owner set it, and when (no side effects)
create or replace function _test_mode_flag() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select lower(trim(value)) from plant_state where key = 'testMode'), 'off') = 'on';
$$;
create or replace function _test_mode_on_at() returns timestamptz
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select _ts_or_null((select value from plant_state where key = 'testModeOnAt'));
$$;
-- in force: on, and switched on less than 8 hours ago (no side effects)
create or replace function _test_mode_active() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select _test_mode_flag() and coalesce(_test_mode_on_at() > now() - _test_mode_max(), false);
$$;

-- switch an expired flag back off (once per transaction; never in a read-only one)
create or replace function _test_mode_autooff() returns void
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
begin
  if coalesce(current_setting('transaction_read_only', true), 'off') = 'on' then return; end if;
  if coalesce(current_setting('gt.tm_autooff', true), '') = 'done' then return; end if;
  perform set_config('gt.tm_autooff', 'done', true);
  perform set_config('gt.test_mode_why', 'auto_expired', true);
  update plant_state set value = 'off', updated_at = now() where key = 'testMode' and lower(trim(value)) = 'on';
  perform set_config('gt.test_mode_why', '', true);
end $$;

-- every server check of test mode goes through this one
create or replace function _test_mode_on() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _test_mode_flag() then return false; end if;
  if _test_mode_active() then return true; end if;
  perform _test_mode_autooff();          -- on, but switched on more than 8 hours ago
  return false;
end $$;

create or replace function _plant_state_test_mode_trg() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_new text := lower(trim(coalesce(new.value, 'off'))); v_old text; v_why text; v_act text;
begin
  if tg_op = 'UPDATE' then v_old := lower(trim(coalesce(old.value, 'off'))); end if;
  v_why := coalesce(nullif(current_setting('gt.test_mode_why', true), ''), 'manual');
  if v_new = 'on' then
    insert into plant_state (key, value) values ('testModeOnAt', now()::text)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    v_act := case when v_old = 'on' then 'test_mode_renewed' else 'test_mode_on' end;
  elsif v_old = 'on' then
    v_act := 'test_mode_off';
  end if;
  if v_act is not null then
    insert into admin_audit (who, role, action, target, detail)
    values (case when v_why = 'auto_expired' then 'server (8-hour limit)' else coalesce(session_user::text, 'sql') end,
            'server', v_act, 'plant_state.testMode',
            jsonb_build_object('from', v_old, 'to', v_new, 'reason', v_why,
                               'onAt', (select value from plant_state where key = 'testModeOnAt')));
  end if;
  return null;
end $$;
revoke execute on function _plant_state_test_mode_trg() from public, anon, authenticated;
drop trigger if exists zz_test_mode_audit on plant_state;
create trigger zz_test_mode_audit after insert or update on plant_state
  for each row when (new.key = 'testMode') execute function _plant_state_test_mode_trg();

-- a flag that was already on before this step: its 8 hours start now
insert into plant_state (key, value)
  select 'testModeOnAt', now()::text where _test_mode_flag()
  on conflict (key) do update set value = excluded.value, updated_at = now()
   where _ts_or_null(plant_state.value) is null;

create or replace function server_test_mode() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select _test_mode_active();
$$;
revoke execute on function server_test_mode() from public;
grant execute on function server_test_mode() to anon, authenticated;

create or replace function server_test_mode_info() returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_on boolean := _test_mode_active(); v_at timestamptz := _test_mode_on_at();
begin
  return jsonb_build_object(
    'on', v_on,
    'on_at', case when v_on then v_at end,
    'expires_at', case when v_on then v_at + _test_mode_max() end,
    'remaining_s', case when v_on then greatest(0, floor(extract(epoch from (v_at + _test_mode_max() - now()))))::bigint end,
    'serverTime', now());
end $$;
revoke execute on function server_test_mode_info() from public;
grant execute on function server_test_mode_info() to anon, authenticated;

-- ── 2a. write attempts with a revoked / retired device key: counted ─────────
create table if not exists revoked_device_writes (
  device_id text not null,
  minute    timestamptz not null,
  n         integer not null default 1,
  primary key (device_id, minute)
);
alter table revoked_device_writes enable row level security;
revoke all on revoked_device_writes from public, anon, authenticated;

-- p_dev: a device whose key is valid but which is retired; otherwise the key
-- in the request is looked up among the revoked ones. Once per transaction.
create or replace function _note_revoked_write(p_dev text default null) returns void
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_tok text; v_id text;
begin
  if coalesce(current_setting('transaction_read_only', true), 'off') = 'on' then return; end if;
  if coalesce(current_setting('gt.revoked_noted', true), '') = 'on' then return; end if;
  if p_dev is not null then
    select id into v_id from devices_pilot where id = p_dev and device_status = 'retired';
  else
    v_tok := _request_headers() ->> 'x-device-token';
    if coalesce(v_tok, '') = '' then return; end if;
    select device_id into v_id from device_credentials
     where token_hash = encode(digest(v_tok, 'sha256'), 'hex') and revoked limit 1;
  end if;
  if v_id is null then return; end if;
  perform set_config('gt.revoked_noted', 'on', true);
  insert into revoked_device_writes (device_id, minute, n) values (v_id, date_trunc('minute', now()), 1)
    on conflict (device_id, minute) do update set n = revoked_device_writes.n + 1;
  if random() < 0.02 then delete from revoked_device_writes where minute < now() - interval '3 days'; end if;
end $$;
revoke execute on function _note_revoked_write(text) from public, anon, authenticated;

create or replace function _device_write_allowed() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_ok boolean;
begin
  if not _is_api_request() then return true; end if;                    -- SQL editor / server jobs
  if _request_is_service_role() then return true; end if;                -- server-side code with the service key
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  if _request_has_manager() then return true; end if;                    -- team leader (events / settings only; rulings: _stage_allowed)
  v_dev := _current_device_id();
  if v_dev is null then perform _note_revoked_write(); return false; end if;
  v_ok := exists(select 1 from devices_pilot
                  where id = v_dev and assigned_role is not null
                    and assigned_role <> 'display'                       -- a counter screen only reads
                    and coalesce(device_status, 'active') <> 'retired');
  if not v_ok then perform _note_revoked_write(v_dev); end if;
  return v_ok;
end $$;

create or replace function _stage_allowed(p_stage text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text; v_ok boolean := false; v_dev text;
begin
  if _request_privileged() then return true; end if;
  v_role := _caller_device_role();
  if v_role is not null then
    v_ok := case p_stage
      when 'slaughter' then v_role in ('slaughter')
      when 'eso'       then v_role in ('esophagus','slaughter')
      when 'inner'     then v_role in ('inner','outer')
      when 'outer'     then v_role in ('outer','inner')
      when 'legs'      then v_role in ('legs')
      when 'stamped'   then v_role in ('stamps','parts')
      when 'parts'     then v_role in ('parts')
      when 'weights'   then v_role in ('stamps')        -- the scale is on the stamps screen
      else false end;
  end if;
  if v_ok then return true; end if;
  -- the team leader has NO ruling rights — except in test mode (SQL-only switch, 8 hours)
  if _test_mode_on() and _request_has_manager() then return true; end if;
  if v_role is null then                             -- a revoked / retired key: counted for the health screen
    v_dev := _current_device_id();
    if v_dev is null then perform _note_revoked_write(); else perform _note_revoked_write(v_dev); end if;
  end if;
  return false;
end $$;

create or replace function _nc_outer_allowed() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text;
begin
  if not _is_api_request() or _request_is_service_role() then return true; end if;
  v_dev := _current_device_id();
  if exists (select 1 from devices_pilot d
              where d.id = v_dev and d.assigned_role = 'outer' and d.device_status = 'active') then
    return true;
  end if;
  if _test_mode_on() and _request_has_manager() then return true; end if;
  if v_dev is null then perform _note_revoked_write(); else perform _note_revoked_write(v_dev); end if;
  return false;
end $$;

-- internal helpers: never callable by the app
do $$
declare s text;
begin
  foreach s in array array['_test_mode_flag()', '_test_mode_on_at()', '_test_mode_active()', '_test_mode_autooff()',
                           '_test_mode_on()', '_note_revoked_write(text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', s);
  end loop;
end $$;

-- the station role of the calling tablet (write paths only); a retired tablet is counted
create or replace function _caller_device_role() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_role text;
begin
  v_dev := _current_device_id();
  if v_dev is null then return null; end if;
  select assigned_role into v_role from devices_pilot
   where id = v_dev and coalesce(device_status, 'active') <> 'retired';
  if v_role is null then perform _note_revoked_write(v_dev); end if;
  return v_role;
end $$;

-- every "no device" answer of the ruling functions (a revoked key ends here too)
create or replace function _no_device_error() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if _request_has_manager() then return 'wrong_station'; end if;
  perform _note_revoked_write();
  return 'device_not_paired';
end $$;

-- ── 2b. system health for the team leader ───────────────────────────────────
-- the event chain, cheaply: count/positions of the whole chain + a full hash
-- check of the last p_limit events + the stored chain head
create or replace function _event_chain_recent(p_limit integer default 500) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare r events_pilot%rowtype; v_total bigint; v_max bigint; v_start bigint; v_prev text; n bigint := 0; v_gap bigint;
        h events_chain_head%rowtype;
begin
  select count(*), max(chain_pos) into v_total, v_max from events_pilot where server_chained;
  v_max := coalesce(v_max, 0);
  if v_total <> v_max then
    select min(e.chain_pos) + 1 into v_gap from events_pilot e
     where e.server_chained and e.chain_pos < v_max
       and not exists (select 1 from events_pilot x where x.server_chained and x.chain_pos = e.chain_pos + 1);
    return jsonb_build_object('ok', false, 'checked', 0, 'brokenAt', coalesce(v_gap, 1), 'reason', 'missing-event', 'total', v_total);
  end if;
  v_start := greatest(1, v_max - greatest(coalesce(p_limit, 500), 1) + 1);
  if v_start > 1 then
    select event_hash into v_prev from events_pilot where server_chained and chain_pos = v_start - 1;
  end if;
  for r in select * from events_pilot where server_chained and chain_pos >= v_start order by chain_pos loop
    if r.chain_pos <> v_start + n then
      return jsonb_build_object('ok', false, 'checked', n, 'brokenAt', v_start + n, 'reason', 'missing-event', 'total', v_total);
    end if;
    if r.prev_hash is distinct from v_prev then
      return jsonb_build_object('ok', false, 'checked', n, 'brokenAt', r.chain_pos, 'reason', 'prev-hash-mismatch', 'total', v_total);
    end if;
    if encode(digest(_event_canonical(r.event_id, r.animal_no, r.stage, r.action, r.payload, r.actor,
                                      r.device_id, r.occurred_at, r.prev_hash, r.chain_pos), 'sha256'), 'hex') <> r.event_hash then
      return jsonb_build_object('ok', false, 'checked', n, 'brokenAt', r.chain_pos, 'reason', 'hash-mismatch', 'total', v_total);
    end if;
    v_prev := r.event_hash;
    n := n + 1;
  end loop;
  select * into h from events_chain_head where id = 1;
  if v_max > 0 and h.id is not null and (h.pos is distinct from v_max or h.hash is distinct from v_prev) then
    return jsonb_build_object('ok', false, 'checked', n, 'brokenAt', v_max, 'reason', 'head-mismatch', 'total', v_total);
  end if;
  return jsonb_build_object('ok', true, 'checked', n, 'brokenAt', null, 'total', v_total);
end $$;
revoke execute on function _event_chain_recent(integer) from public, anon, authenticated;

create or replace function system_health(p_token text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_role text := coalesce(_session_role(p_token), '');
  v_tm boolean; v_on_at timestamptz; v_devs jsonb; v_chain jsonb; v_sec jsonb;
  v_ver timestamptz; v_fail timestamptz; v_plant boolean; v_backup text; v_age numeric;
  v_attn text[] := '{}'; v_info text[] := '{}';
  v_offline int; v_failed int; v_revoked int; v_brakes int; v_locks int;
begin
  if v_role not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  v_tm := _test_mode_on();                  -- also switches an expired flag off
  v_on_at := _test_mode_on_at();

  select jsonb_build_object(
           'active',  count(*) filter (where assigned_role is not null and coalesce(device_status, 'active') <> 'retired'),
           'offline', count(*) filter (where assigned_role is not null and coalesce(device_status, 'active') <> 'retired'
                                         and (last_seen is null or last_seen < now() - interval '3 minutes')),
           'retired', count(*) filter (where device_status = 'retired'),
           'unpaired_requests', (select count(*) from device_pairing where paired_at is null and expires_at > now()))
    into v_devs from devices_pilot;
  v_offline := (v_devs ->> 'offline')::int;

  v_chain := _event_chain_recent(500);

  v_failed  := (select count(*) from login_attempts where not ok and at > now() - interval '1 day');
  v_revoked := (select coalesce(sum(n), 0) from revoked_device_writes where minute > now() - interval '1 day');
  -- brakes hit in 24 h: devices / addresses that reached 10 refused corrections
  -- in 10 minutes or 8 wrong codes in 15 minutes
  select count(distinct key) into v_brakes from (
    select key, at - lag(at, 9) over (partition by key order by at, id) as span
      from rate_events where kind = 'correction_rejected' and at > now() - interval '1 day') a
   where span <= interval '10 minutes';
  select count(distinct ip) into v_locks from (
    select ip, at - lag(at, 7) over (partition by ip order by at, id) as span
      from login_attempts where not ok and at > now() - interval '1 day') b
   where span <= interval '15 minutes';
  v_sec := jsonb_build_object(
    'revokedDeviceWrites24h', v_revoked,
    'failedLogins24h', v_failed,
    'rejectedCorrections24h', (select count(*) from rate_events where kind = 'correction_rejected' and at > now() - interval '1 day'),
    'rateLimited24h', v_brakes + v_locks,
    'chainBroken', not coalesce((v_chain ->> 'ok')::boolean, false));

  -- backups (tools/backup.sh on a plant server writes these two keys)
  v_ver  := _ts_or_null((select value from plant_state where key = 'lastBackupVerifiedAt'));
  v_fail := _ts_or_null((select value from plant_state where key = 'lastBackupFailedAt'));
  v_plant := v_ver is not null or v_fail is not null
             or coalesce((select lower(value) from plant_state where key = 'plantServer'), '') in ('on', 'true', '1');
  v_age := case when v_ver is not null then round((extract(epoch from (now() - v_ver)) / 3600)::numeric, 1) end;
  v_backup := case when not v_plant then 'unknown'
                   when v_ver is null then 'never'
                   when v_fail is not null and v_fail > v_ver then 'failed'
                   when v_ver < now() - interval '26 hours' then 'stale'
                   else 'ok' end;
  if v_backup = 'unknown' then v_info := v_info || 'backup_unknown'::text;
  elsif v_backup <> 'ok' then v_attn := v_attn || 'backup_stale'::text; end if;
  if (v_sec ->> 'chainBroken')::boolean then v_attn := v_attn || 'chain_broken'::text; end if;
  if v_tm then v_attn := v_attn || 'test_mode_on'::text; end if;
  if v_offline > 0 then v_attn := v_attn || 'devices_offline'::text; end if;
  if v_failed >= 10 or v_locks > 0 then v_attn := v_attn || 'failed_logins'::text; end if;
  if v_revoked > 0 then v_attn := v_attn || 'revoked_device_writes'::text; end if;

  return jsonb_build_object(
    'ok', true,
    'schemaStep', (select value from plant_state where key = 'schemaStep'),
    'serverTime', now(),
    'devices', v_devs,
    'testMode', jsonb_build_object('on', v_tm, 'on_at', case when v_tm then v_on_at end,
                                   'expires_at', case when v_tm then v_on_at + _test_mode_max() end),
    'lastBackupVerifiedAt', v_ver,
    'lastBackupFailedAt', v_fail,
    'lastBackupFailReason', case when v_fail is not null then (select value from plant_state where key = 'lastBackupFailReason') end,
    'backup', jsonb_build_object('status', v_backup, 'ageHours', v_age),
    'eventChain', v_chain,
    'security', v_sec,
    'attention', to_jsonb(v_attn),
    'info', to_jsonb(v_info));
end $$;
revoke execute on function system_health(text) from public;
grant execute on function system_health(text) to anon, authenticated;
-- ── 3. a reason for exceptional actions ─────────────────────────────────────
-- p_reason is added as the LAST argument (default null) with the same grants
-- the function had: the grants are copied from the old signature first.
create or replace function _reason_ok(p text) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select nullif(trim(coalesce(p, '')), '') is not null;
$$;
revoke execute on function _reason_ok(text) from public, anon, authenticated;

create table if not exists _gt45_acl (fn text not null, grantee text not null, primary key (fn, grantee));
revoke all on _gt45_acl from public, anon, authenticated;
do $$
declare x record;
begin
  for x in select * from (values
      ('device_pair',              'device_pair(text,text,text,integer,boolean,text)',          'device_pair(text,text,text,integer,boolean,text,text)'),
      ('support_access_set',       'support_access_set(text,integer)',                          'support_access_set(text,integer,text)'),
      ('manufacturer_set_billing', 'manufacturer_set_billing(text,boolean,numeric,text)',       'manufacturer_set_billing(text,boolean,numeric,text,text)'),
      ('support_force_reload',     'support_force_reload(text)',                                'support_force_reload(text,text)'),
      ('push_settings',            'push_settings(jsonb,text,text)',                            'push_settings(jsonb,text,text,text)')) t(fn, old_sig, new_sig) loop
    insert into _gt45_acl (fn, grantee)
      select x.fn, a.grantee::regrole::text
        from pg_proc p, aclexplode(p.proacl) a
       where p.oid = coalesce(to_regprocedure('public.' || x.old_sig), to_regprocedure('public.' || x.new_sig))
         and a.privilege_type = 'EXECUTE' and a.grantee <> 0
      on conflict do nothing;
  end loop;
  -- nothing recorded (a function missing): the app roles, as before
  insert into _gt45_acl (fn, grantee)
    select f, g from unnest(array['device_pair','support_access_set','manufacturer_set_billing','support_force_reload','push_settings']) f,
                     unnest(array['anon','authenticated']) g
     where not exists (select 1 from _gt45_acl a where a.fn = f)
    on conflict do nothing;
end $$;

drop function if exists device_pair(text, text, text, integer, boolean, text);
create or replace function device_pair(p_token text, p_code text, p_role text, p_index integer default 0,
                                       p_replace boolean default false, p_device_name text default null,
                                       p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r device_pairing%rowtype; v_idx int; v_tok text; v_old record; v_repl uuid; v_actor text; v_why text;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_role not in ('slaughter','esophagus','legs','inner','outer','parts','stamps','display') then
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;
  v_idx := case when p_role in ('inner','outer','display') then coalesce(p_index, 0) else 0 end;
  if (p_role = 'display' and v_idx not between 0 and 3) or (p_role <> 'display' and v_idx not in (0, 1)) then
    return jsonb_build_object('ok', false, 'error', 'bad_slot');
  end if;
  if coalesce(p_replace, false) and not _reason_ok(p_reason) then        -- replacing a working device: why?
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  v_why := left(trim(p_reason), 160);

  perform pg_advisory_xact_lock(hashtext('device_slot:' || p_role || ':' || v_idx));

  select * into r from device_pairing
   where code = trim(p_code) and paired_at is null and expires_at > now()
   for update;
  if r.code is null then return jsonb_build_object('ok', false, 'error', 'code_invalid'); end if;

  v_actor := coalesce(_session_name(p_token), 'manager');
  perform set_config('gt.audit_actor', v_actor, true);
  perform set_config('app.device_admin', 'on', true);

  for v_old in select id, device_name from devices_pilot
                where assigned_role = p_role and coalesce(assigned_index, 0) = v_idx
                  and id <> r.device_id and coalesce(device_status, 'active') <> 'retired'
  loop
    if not p_replace then
      perform set_config('app.device_admin', '', true);
      perform set_config('gt.audit_actor', '', true);
      return jsonb_build_object('ok', false, 'error', 'slot_taken',
                                'device_name', coalesce(v_old.device_name, v_old.id));
    end if;
    -- one replacement id on the old and the new device's events
    if v_repl is null then v_repl := gen_random_uuid(); end if;
    perform set_config('gt.replacement_id', v_repl::text, true);
    perform set_config('gt.audit_reason', 'replaced by pairing: ' || v_why, true);
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
     where id = v_old.id;
    update device_credentials set revoked = true where device_id = v_old.id;   -- audited as KEY_REVOKED
    perform _audit_device_event(v_old.id, 'UNASSIGNED', p_role, v_idx, 'replaced by pairing: ' || v_why, r.device_id, v_repl, v_actor);
  end loop;

  v_tok := encode(gen_random_bytes(24), 'hex');

  insert into devices_pilot (id, device_name, assigned_role, assigned_index, device_status, paired_at, last_seen, updated_at)
  values (r.device_id, coalesce(nullif(left(trim(p_device_name), 60), ''), r.device_name), p_role, v_idx, 'active', now(), now(), now())
  on conflict (id) do update set
    device_name    = coalesce(nullif(left(trim(p_device_name), 60), ''), devices_pilot.device_name),
    assigned_role  = excluded.assigned_role,
    assigned_index = excluded.assigned_index,
    device_status  = 'active',
    retired_at = null, retired_by = null, retired_reason = null,
    paired_at = now(), updated_at = now();

  insert into device_credentials (device_id, token_hash, created_at, revoked)
  values (r.device_id, encode(digest(v_tok, 'sha256'), 'hex'), now(), false)
  on conflict (device_id) do update set token_hash = excluded.token_hash, created_at = now(), revoked = false;

  update device_pairing set paired_at = now(), token_plain = v_tok where code = r.code;

  perform set_config('app.device_admin', '', true);
  perform _audit_device_event(r.device_id, 'ASSIGNED', p_role, v_idx,
                              case when v_repl is not null then 'paired with code (replacement): ' || v_why else 'paired with code' end,
                              null, v_repl, v_actor);
  perform set_config('gt.replacement_id', '', true);
  perform set_config('gt.audit_reason', '', true);
  perform set_config('gt.audit_actor', '', true);
  return jsonb_build_object('ok', true, 'device_id', r.device_id)
         || case when v_repl is not null then jsonb_build_object('replacement_id', v_repl) else '{}'::jsonb end;
end $$;

create or replace function device_manage(p_token text, p_device_id text, p_action text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d devices_pilot%rowtype; v_actor text; v_name text; v_why text := left(trim(p_reason), 200);
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into d from devices_pilot where id = p_device_id;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_action not in ('retire', 'reactivate', 'rename') then
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;
  if p_action in ('retire', 'reactivate') and not _reason_ok(p_reason) then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  v_actor := coalesce(_session_name(p_token), 'manager');
  perform set_config('gt.audit_actor', v_actor, true);
  perform set_config('app.device_admin', 'on', true);
  if p_action = 'retire' then
    perform set_config('gt.audit_reason', v_why, true);
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null,
           device_status = 'retired', retired_at = now(), retired_by = 'manager',
           retired_reason = v_why, updated_at = now()
     where id = p_device_id;
    update device_credentials set revoked = true where device_id = p_device_id;
    perform _audit_device_event(p_device_id, 'DEVICE_RETIRED', d.assigned_role, d.assigned_index, v_why, null, null, v_actor);
  elsif p_action = 'reactivate' then
    update devices_pilot set device_status = 'active', retired_at = null, retired_by = null,
           retired_reason = null, updated_at = now()
     where id = p_device_id;
    perform _audit_device_event(p_device_id, 'DEVICE_REACTIVATED', null, null, v_why, null, null, v_actor);
  else
    v_name := coalesce(nullif(left(trim(p_reason), 60), ''), d.device_name);
    update devices_pilot set device_name = v_name, updated_at = now() where id = p_device_id;
    perform _audit_device_event(p_device_id, 'RENAMED', d.assigned_role, d.assigned_index,
                                coalesce(d.device_name, '') || ' → ' || coalesce(v_name, ''), null, null, v_actor);
  end if;
  perform set_config('app.device_admin', '', true);
  perform set_config('gt.audit_actor', '', true);
  perform set_config('gt.audit_reason', '', true);
  if coalesce(_session_role(p_token), '') = 'manufacturer' then
    perform _admin_audit(p_token, 'device_' || p_action, p_device_id, jsonb_build_object('reason', v_why));
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function device_unpair(p_token text, p_device_id text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d devices_pilot%rowtype; v_actor text; v_why text := left(trim(p_reason), 200);
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into d from devices_pilot where id = p_device_id;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not _reason_ok(p_reason) then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  v_actor := coalesce(_session_name(p_token), 'manager');
  perform set_config('gt.audit_actor', v_actor, true);
  perform set_config('gt.audit_reason', v_why, true);
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
   where id = p_device_id;
  update device_credentials set revoked = true where device_id = p_device_id;
  perform set_config('app.device_admin', '', true);
  perform _audit_device_event(p_device_id, 'UNASSIGNED', d.assigned_role, d.assigned_index, v_why, null, null, v_actor);
  if coalesce(_session_role(p_token), '') = 'manufacturer' then
    perform _admin_audit(p_token, 'device_unpair', p_device_id, jsonb_build_object('reason', v_why));
  end if;
  perform set_config('gt.audit_actor', '', true);
  perform set_config('gt.audit_reason', '', true);
  return jsonb_build_object('ok', true);
end $$;

drop function if exists support_access_set(text, integer);
create or replace function support_access_set(p_token text, p_hours integer, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_until timestamptz; v_name text; v_why text := left(trim(p_reason), 200);
begin
  if coalesce(_session_role(p_token), '') <> 'manager' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_hours is null or p_hours < 0 or p_hours > 168 then
    return jsonb_build_object('ok', false, 'error', 'bad_hours');
  end if;
  if p_hours > 0 and not _reason_ok(p_reason) then                 -- opening access: why? (closing: no reason needed)
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  v_name := _session_name(p_token);
  v_until := case when p_hours = 0 then now() else now() + make_interval(hours => p_hours) end;
  insert into plant_state (key, value) values ('supportAccessUntil', v_until::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  if p_hours = 0 then
    delete from manager_sessions where manager_id in (select id from plant_managers where role = 'manufacturer');
  end if;
  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  update settings_pilot
     set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('supportAccessUntil', v_until::text),
         device_id = 'server', updated_at = now()
   where id = 1;
  perform set_config('app.device_admin', 'on', true);
  insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
  values (gen_random_uuid(), null, 'support', case when p_hours = 0 then 'access_closed' else 'access_opened' end,
          jsonb_build_object('hours', p_hours, 'until', v_until) || case when v_why <> '' then jsonb_build_object('reason', v_why) else '{}'::jsonb end,
          v_name, 'server', now()::text);
  perform set_config('app.device_admin', '', true);
  perform _admin_audit(p_token, case when p_hours = 0 then 'support_access_closed' else 'support_access_opened' end,
                       'manufacturer', jsonb_build_object('hours', p_hours, 'until', v_until, 'reason', v_why));
  return jsonb_build_object('ok', true, 'until', v_until);
end $$;

drop function if exists manufacturer_set_billing(text, boolean, numeric, text);
create or replace function manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text,
                                                    p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_billing jsonb;
begin
  if not _manufacturer_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_price is null or p_price < 0 or p_price > 1000000 then
    return jsonb_build_object('ok', false, 'error', 'bad_price');
  end if;
  if p_currency not in ('₪','$','€') then
    return jsonb_build_object('ok', false, 'error', 'bad_currency');
  end if;
  if not _reason_ok(p_reason) then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  v_billing := jsonb_build_object('enabled', coalesce(p_enabled, false), 'price', round(p_price, 4),
                                  'currency', p_currency, 'updatedAt', now()::text);
  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('billing', v_billing), 'manufacturer', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('billing', v_billing),
        device_id = 'manufacturer', updated_at = now();
  perform _admin_audit(p_token, 'billing', 'settings_pilot.billing', v_billing || jsonb_build_object('reason', left(trim(p_reason), 200)));
  return jsonb_build_object('ok', true, 'billing', v_billing);
end $$;

drop function if exists support_force_reload(text);
create or replace function support_force_reload(p_token text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if not _reason_ok(p_reason) then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  update settings_pilot
     set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('forceReloadAt', now()::text),
         device_id = 'support', updated_at = now()
   where id = 1;
  perform _admin_audit(p_token, 'force_reload', 'all devices', jsonb_build_object('reason', left(trim(p_reason), 200)));
  return jsonb_build_object('ok', true);
end $$;

-- the same grants as before (again in part 3, for push_settings)
do $$
declare x record; v_new text; g text;
begin
  for x in select distinct fn from _gt45_acl loop
    v_new := case x.fn
      when 'device_pair'              then 'device_pair(text,text,text,integer,boolean,text,text)'
      when 'support_access_set'       then 'support_access_set(text,integer,text)'
      when 'manufacturer_set_billing' then 'manufacturer_set_billing(text,boolean,numeric,text,text)'
      when 'support_force_reload'     then 'support_force_reload(text,text)'
      when 'push_settings'            then 'push_settings(jsonb,text,text,text)' end;
    if v_new is null or to_regprocedure('public.' || v_new) is null then continue; end if;
    execute format('revoke execute on function %s from public', v_new);
    foreach g in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = g)
         and not exists (select 1 from _gt45_acl where fn = x.fn and grantee = g) then
        execute format('revoke execute on function %s from %I', v_new, g);
      end if;
    end loop;
  end loop;
end $$;
do $$
declare x record; v_sig text;
begin
  for x in select a.fn, a.grantee from _gt45_acl a join pg_roles r on r.rolname = a.grantee loop
    v_sig := case x.fn
      when 'device_pair'              then 'device_pair(text,text,text,integer,boolean,text,text)'
      when 'support_access_set'       then 'support_access_set(text,integer,text)'
      when 'manufacturer_set_billing' then 'manufacturer_set_billing(text,boolean,numeric,text,text)'
      when 'support_force_reload'     then 'support_force_reload(text,text)'
      when 'push_settings'            then 'push_settings(jsonb,text,text,text)' end;
    if v_sig is not null and to_regprocedure('public.' || v_sig) is not null then
      execute format('grant execute on function %s to %I', v_sig, x.grantee);
    end if;
  end loop;
end $$;
drop function if exists push_settings(jsonb, text, text);
create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  list_keys text[] := array['reprintLog','problemReports'];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason','billing','forceReloadAt','supportAccessUntil',
                              'boardEpoch','testMode'];
  cur jsonb;
  incoming jsonb;
  k text;
  v_err text;
  ignored text[] := '{}';
  is_manager boolean := false;
  is_maker boolean := false;
  v_label text;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
    is_maker := is_manager and coalesce(_session_role(p_token), '') = 'manufacturer';
  end if;
  -- the manufacturer changes the plant's settings only with a reason (step 45)
  if is_maker and not _reason_ok(p_reason) then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  -- station keys: a paired station (or team leader); nobody anonymous
  if not is_manager and not _device_write_allowed() then
    return jsonb_build_object('ok', false, 'error', 'device_not_paired');
  end if;
  -- settings_pilot.device_id is only the "who sent it" label the app uses to
  -- skip its own echo: the paired device key; for a team-leader browser without
  -- a paired device its own id (the team leader may change all settings anyway)
  v_label := coalesce(_current_device_id(),
                      case when is_manager or _request_has_manager() then nullif(left(p_device_id, 80), '') end,
                      case when is_manager then 'team-leader' end,
                      case when not _is_api_request() then nullif(left(p_device_id, 80), '') end,
                      'unknown');

  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  select coalesce(settings, '{}'::jsonb) into cur from settings_pilot where id = 1;
  cur := coalesce(cur, '{}'::jsonb);

  incoming := p_settings;
  foreach k in array server_keys loop
    if (incoming ? k) and (cur -> k) is distinct from (incoming -> k) then
      ignored := ignored || k;
    end if;
    incoming := incoming - k;
  end loop;

  if not is_manager then
    for k in select jsonb_object_keys(incoming) loop
      if not (k = any(station_keys)) then
        if (cur -> k) is distinct from (incoming -> k) then
          ignored := ignored || k;
        end if;
        incoming := incoming - k;
      end if;
    end loop;
  end if;

  -- the values that will be written must have the shape the app uses
  for k in select jsonb_object_keys(incoming) loop
    if length(k) > 80 then
      return jsonb_build_object('ok', false, 'error', 'bad_settings', 'key', left(k, 80), 'reason', 'key too long');
    end if;
    v_err := _settings_value_error(k, incoming -> k);
    if v_err is not null then
      return jsonb_build_object('ok', false, 'error', 'bad_settings', 'key', k, 'reason', v_err);
    end if;
  end loop;
  if length(incoming::text) > 4000000 then
    return jsonb_build_object('ok', false, 'error', 'bad_settings', 'key', '*', 'reason', 'too_large');
  end if;

  foreach k in array list_keys loop
    if not is_manager and incoming ? k then
      incoming := jsonb_set(incoming, array[k], _merge_list(cur -> k, incoming -> k));
    end if;
  end loop;

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, v_label, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  if coalesce(_session_role(p_token), '') = 'manufacturer' then
    perform _admin_audit(p_token, 'settings', 'settings_pilot',
                         jsonb_build_object('keys', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_object_keys(incoming) x),
                                            'reason', left(trim(p_reason), 200)));
  end if;
  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;

-- the same grants as before (copied from the old signatures above)
do $$
declare x record; v_new text; g text;
begin
  for x in select distinct fn from _gt45_acl loop
    v_new := case x.fn
      when 'device_pair'              then 'device_pair(text,text,text,integer,boolean,text,text)'
      when 'support_access_set'       then 'support_access_set(text,integer,text)'
      when 'manufacturer_set_billing' then 'manufacturer_set_billing(text,boolean,numeric,text,text)'
      when 'support_force_reload'     then 'support_force_reload(text,text)'
      when 'push_settings'            then 'push_settings(jsonb,text,text,text)' end;
    if v_new is null or to_regprocedure('public.' || v_new) is null then continue; end if;
    execute format('revoke execute on function %s from public', v_new);
    foreach g in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = g)
         and not exists (select 1 from _gt45_acl where fn = x.fn and grantee = g) then
        execute format('revoke execute on function %s from %I', v_new, g);
      end if;
    end loop;
  end loop;
end $$;
do $$
declare x record; v_sig text;
begin
  for x in select a.fn, a.grantee from _gt45_acl a join pg_roles r on r.rolname = a.grantee loop
    v_sig := case x.fn
      when 'device_pair'              then 'device_pair(text,text,text,integer,boolean,text,text)'
      when 'support_access_set'       then 'support_access_set(text,integer,text)'
      when 'manufacturer_set_billing' then 'manufacturer_set_billing(text,boolean,numeric,text,text)'
      when 'support_force_reload'     then 'support_force_reload(text,text)'
      when 'push_settings'            then 'push_settings(jsonb,text,text,text)' end;
    if v_sig is not null and to_regprocedure('public.' || v_sig) is not null then
      execute format('grant execute on function %s to %I', v_sig, x.grantee);
    end if;
  end loop;
end $$;
drop table if exists _gt45_acl;

insert into plant_state (key, value) values ('schemaStep', '45')
  on conflict (key) do update
    set value = case when plant_state.value ~ '^\d+$' and plant_state.value::int > 45 then plant_state.value else '45' end,
        updated_at = now();

-- ── self-check ──────────────────────────────────────────────────────────────
do $$
declare problems text[] := '{}'; v_prev text; v_prev_at text; s text; r jsonb;
begin
  foreach s in array array['server_test_mode()', 'server_test_mode_info()', 'system_health(text)',
                           'device_pair(text,text,text,integer,boolean,text,text)', 'device_manage(text,text,text,text)',
                           'device_unpair(text,text,text)', 'support_access_set(text,integer,text)',
                           'manufacturer_set_billing(text,boolean,numeric,text,text)', 'support_force_reload(text,text)',
                           'push_settings(jsonb,text,text,text)'] loop
    if to_regprocedure('public.' || s) is null then problems := problems || ('missing: ' || s);
    elsif not has_function_privilege('anon', s, 'execute') then problems := problems || ('not callable by the app: ' || s); end if;
  end loop;
  foreach s in array array['device_pair(text,text,text,integer,boolean,text)', 'support_access_set(text,integer)',
                           'manufacturer_set_billing(text,boolean,numeric,text)', 'support_force_reload(text)',
                           'push_settings(jsonb,text,text)'] loop
    if to_regprocedure('public.' || s) is not null then problems := problems || ('old signature still there: ' || s); end if;
  end loop;
  foreach s in array array['_test_mode_autooff()', '_note_revoked_write(text)', '_event_chain_recent(integer)'] loop
    if has_function_privilege('anon', s, 'execute') then problems := problems || ('internal function callable by the app: ' || s); end if;
  end loop;
  if exists (select 1 from pg_proc where oid in ('server_test_mode()'::regprocedure, 'server_test_mode_info()'::regprocedure)
                                     and provolatile <> 's') then
    problems := problems || 'server_test_mode / _info not read-only'::text; end if;
  if has_table_privilege('anon', 'revoked_device_writes', 'select') then problems := problems || 'revoked_device_writes readable by the app'::text; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'plant_state'::regclass and tgname = 'zz_test_mode_audit' and tgenabled <> 'D') then
    problems := problems || 'test-mode trigger missing'::text; end if;
  if system_health('not-a-session') ->> 'error' is distinct from 'unauthorized' then
    problems := problems || 'system_health without a session is not refused'::text; end if;

  select value into v_prev from plant_state where key = 'testMode';
  select value into v_prev_at from plant_state where key = 'testModeOnAt';
  begin
    update plant_state set value = 'on' where key = 'testMode';
    if server_test_mode() is not true or _test_mode_on() is not true then problems := problems || 'flag on → not on'::text; end if;
    r := server_test_mode_info();
    if not (r ->> 'on')::boolean or (r ->> 'remaining_s')::bigint < 28000 then problems := problems || ('info: ' || r::text); end if;
    update plant_state set value = (now() - interval '9 hours')::text where key = 'testModeOnAt';
    if server_test_mode() is not false then problems := problems || '9 hours old → still on'::text; end if;
    perform set_config('gt.tm_autooff', '', true);
    if _test_mode_on() is not false then problems := problems || '9 hours old → _test_mode_on still true'::text; end if;
    if (select value from plant_state where key = 'testMode') <> 'off' then problems := problems || 'expired flag not switched off'::text; end if;
    if not exists (select 1 from admin_audit where action = 'test_mode_off' and detail ->> 'reason' = 'auto_expired' and at >= now()) then
      problems := problems || 'auto-off not audited'::text; end if;
    raise exception 'gt_selftest45_rollback';
  exception when others then
    if sqlerrm <> 'gt_selftest45_rollback' then problems := problems || ('self-test error: ' || sqlerrm); end if;
  end;
  perform set_config('gt.tm_autooff', '', true);
  if (select value from plant_state where key = 'testMode') is distinct from v_prev
     or (select value from plant_state where key = 'testModeOnAt') is distinct from v_prev_at then
    problems := problems || 'self-check changed the test flag'::text; end if;
  if (select value from plant_state where key = 'schemaStep') !~ '^\d+$'
     or (select value from plant_state where key = 'schemaStep')::int < 45 then
    problems := problems || 'schemaStep not 45'::text; end if;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 45 self-check FAILED: %', array_to_string(problems, ' | ');
  end if;
  raise notice 'GlattTrack step 45 self-check OK';
end $$;

notify pgrst, 'reload schema';
