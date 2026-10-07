-- ============================================================================
-- GlattTrack — security self-test (run any time; changes NOTHING)
-- VERSION 8 — one statement, no temporary tables, nothing the Supabase SQL Editor
--             mistakes for a new table (so it shows no "RLS" window and adds nothing)
-- ============================================================================
-- Simulates requests exactly as they arrive through the API (PostgREST: the
-- "authenticator" login, role anon, request headers, JWT claims) and live
-- updates (role anon + JWT, no headers) from test tablets, a test team leader,
-- owner, manufacturer and workers, and checks the server's rules:
--   tablets (retired / unpaired / wrong station / forged id / fake key / old key
--   after a replacement), team-leader sessions (bound, 10 h, no ruling rights,
--   test mode), first claims, idempotent retries and command ids, who may
--   correct a ruling and when ("moved on" by time), the rabbinate screen, the
--   inner-check takeover, direct table writes (closed), reads (narrowed),
--   settings shapes, audit (device lifecycle + manufacturer), brakes, the daily
--   reset, the event chain, value rules, worker login, the archive, and the
--   ACTIVE security surface against the expected manifest.
-- The whole test is ONE statement (one DO block): every change it makes is
-- undone inside it, whatever tool runs it (SQL Editor, psql, a pooler).
-- While it runs (a few seconds) tablets writing to the board wait for it.
--
-- Where to run it:
--   plant server:  sudo bash /opt/glatttrack/tools/security-selftest.sh
--   by hand:       psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -f security-selftest.sql
--   Supabase:      SQL Editor (as superuser it logs in as the API login itself;
--                  otherwise it marks each test request as an API request)
-- Prints a PASS/FAIL table; ends with an ERROR if anything failed.
-- Needs schema step 46 or later (step 45: test-mode 8-hour limit, system health,
-- reasons for exceptional actions, chaos checks after takeovers and resets;
-- step 46: stage order, each station its own stage, kashrut configuration
-- locks, processing kept over several days with no skipping).
--   Supabase SQL Editor: paste the WHOLE file and Run (nothing selected).
-- ============================================================================
do $gt_selftest$
declare
  v_step text := 'start'; v_test text; v_ok boolean; v_detail text; v_n int; v_fail int; v_names text; v_line text;
begin
  -- an earlier result in this session is cleared
  if exists (select 1 from pg_prepared_statements where name = 'gt_selftest_result') then
    execute 'deallocate gt_selftest_result';
  end if;
  begin                                  -- everything in here is undone at the end
    v_step := 'set local client_min_messages = notice;';
    execute $gt0$
set local client_min_messages = notice;
$gt0$;
    v_step := 'set local search_path = public, extensions;';
    execute $gt1$
set local search_path = public, extensions;
$gt1$;
    v_step := 'results list';
    execute $gt2$
select set_config('gt_st.results', '[]', true)   -- the results (no temporary tables: undone with everything else)
$gt2$;
    v_step := 'fixture values';
    execute $gt3$
select set_config('gt_st.ready', 'on', true)      -- fixture values are kept as gt_st.<name> (see pg_temp.put)
$gt3$;
    v_step := 'call SQL as the API would (authenticator → anon + request headers + JWT';
    execute $gt4$
-- call SQL as the API would (authenticator → anon + request headers + JWT
-- claims); returns the jsonb result, or {"exception": message, "sqlstate": code}
create function pg_temp.api3(p_headers jsonb, p_claims jsonb, p_sql text) returns jsonb
language plpgsql as $$
declare r jsonb; e text; st text; v_su boolean;
begin
  perform set_config('request.headers', coalesce(p_headers, '{}'::jsonb)::text, true);
  perform set_config('request.jwt.claims', coalesce(p_claims, '{"role":"anon"}'::jsonb)::text, true);
  -- a superuser logs in as "authenticator" exactly like the API; without
  -- superuser (Supabase SQL Editor) the server's own API marker is used
  v_su := coalesce((select rolsuper from pg_roles where rolname = session_user), false);
  if v_su then execute 'set session authorization authenticator';
  else perform set_config('gt.as_api', 'on', true); end if;
  execute 'set role anon';
  begin
    execute p_sql into r;
  exception when others then
    get stacked diagnostics st = returned_sqlstate;
    e := sqlerrm;
  end;
  execute 'reset role';
  if v_su then execute 'reset session authorization';
  else perform set_config('gt.as_api', '', true); end if;
  perform set_config('request.headers', '{}', true);
  perform set_config('request.jwt.claims', '', true);
  if e is not null then return jsonb_build_object('exception', e, 'sqlstate', st); end if;
  return coalesce(r, 'null'::jsonb);
end $$;
$gt4$;
    v_step := 'create function pg_temp.api(p_headers jsonb, p_sql text) returns jsonb';
    execute $gt5$
create function pg_temp.api(p_headers jsonb, p_sql text) returns jsonb
language sql as $$ select pg_temp.api3(p_headers, '{"role":"anon"}'::jsonb, p_sql) $$;
$gt5$;
    v_step := 'a live-updates read (role anon + JWT, no request headers, not the API login)';
    execute $gt6$
-- a live-updates read (role anon + JWT, no request headers, not the API login)
create function pg_temp.rt(p_claims jsonb, p_sql text) returns jsonb
language plpgsql as $$
declare r jsonb; e text;
begin
  perform set_config('request.headers', '', true);
  perform set_config('request.jwt.claims', coalesce(p_claims, '{"role":"anon"}'::jsonb)::text, true);
  execute 'set role anon';
  begin
    execute p_sql into r;
  exception when others then e := sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  if e is not null then return jsonb_build_object('exception', e); end if;
  return coalesce(r, 'null'::jsonb);
end $$;
$gt6$;
    v_step := 'simulate a direct change to the event log (the append-only triggers off for';
    execute $gt7$
-- simulate a direct change to the event log (the append-only triggers off for
-- this one sub-block, always rolled back): as superuser by replica mode,
-- otherwise (Supabase SQL Editor, the table owner) by switching off the
-- table's own triggers
create function pg_temp.st_tamper() returns void
language plpgsql as $$
begin
  begin
    perform set_config('session_replication_role', 'replica', true);
  exception when others then
    execute 'alter table events_pilot disable trigger user';
  end;
end $$;
$gt7$;
    v_step := 'create function pg_temp.rec(p_test text, p_ok boolean, p_detail text default null) returns';
    execute $gt8$
create function pg_temp.rec(p_test text, p_ok boolean, p_detail text default null) returns void
language plpgsql as $$
begin
  perform set_config('gt_st.results',
    (coalesce(nullif(current_setting('gt_st.results', true), ''), '[]')::jsonb
       || jsonb_build_array(jsonb_build_object('test', p_test, 'ok', coalesce(p_ok, false), 'detail', p_detail)))::text, true);
end $$;
$gt8$;
    v_step := 'create function pg_temp.v(p_k text) returns text language sql stable as $$ select v from _';
    execute $gt9$
create function pg_temp.put(p_k text, p_v text) returns void language plpgsql as $$
begin perform set_config('gt_st.' || lower(p_k), coalesce(p_v, ''), true); end $$;
create function pg_temp.v(p_k text) returns text language sql stable as $$ select nullif(current_setting('gt_st.' || lower(p_k), true), '') $$;
$gt9$;
    v_step := 'create function pg_temp.dev(p_name text) returns jsonb language sql stable as $$';
    execute $gt10$
create function pg_temp.dev(p_name text) returns jsonb language sql stable as $$
  select jsonb_build_object('x-device-token', pg_temp.v('tok_' || p_name)) $$;
$gt10$;
    v_step := 'create function pg_temp.devid(p_name text) returns text language sql stable as $$ select v';
    execute $gt11$
create function pg_temp.devid(p_name text) returns text language sql stable as $$ select pg_temp.v('id_' || p_name) $$;
$gt11$;
    v_step := 'create function pg_temp.mgr(p_k text default ''mgr'') returns jsonb language sql stable as $';
    execute $gt12$
create function pg_temp.mgr(p_k text default 'mgr') returns jsonb language sql stable as $$
  select jsonb_build_object('x-manager-token', pg_temp.v(p_k)) $$;
$gt12$;
    v_step := 'create function pg_temp.ep() returns bigint language sql stable as $$ select _board_epoch(';
    execute $gt13$
create function pg_temp.ep() returns bigint language sql stable as $$ select _board_epoch() $$;
$gt13$;
    v_step := 'create function pg_temp.q_claim(p_id int, p_stage text, p_value text, p_actor text, p_dev ';
    execute $gt14$
create function pg_temp.q_claim(p_id int, p_stage text, p_value text, p_actor text, p_dev text) returns text
language sql stable as $$
  select format('select claim_animal_stage(%s, %L, %L, %L, %L, %s)', p_id, p_stage, p_value, p_actor, p_dev,
                coalesce(_board_epoch()::text, 'null')) $$;
$gt14$;
    v_step := 'create function pg_temp.q_claimc(p_id int, p_stage text, p_value text, p_cmd uuid) returns';
    execute $gt15$
create function pg_temp.q_claimc(p_id int, p_stage text, p_value text, p_cmd uuid) returns text
language sql stable as $$
  select format('select claim_animal_stage(%s, %L, %L, %L, %L, %s, %L::uuid)', p_id, p_stage, p_value, '', 'ignored',
                coalesce(_board_epoch()::text, 'null'), p_cmd) $$;
$gt15$;
    v_step := 'animal_push of one row (id + today''s board day + the given columns)';
    execute $gt16$
-- animal_push of one row (id + today's board day + the given columns)
create function pg_temp.q_push(p_id int, p_set jsonb, p_cmd uuid default null) returns text
language sql stable as $$
  select format('select animal_push(%L::jsonb, %L::uuid)',
                jsonb_build_object('id', p_id, 'board_epoch', _board_epoch()) || coalesce(p_set, '{}'::jsonb), p_cmd) $$;
$gt16$;
    v_step := 'create function pg_temp.q_ev(p_event jsonb) returns text language sql immutable as $$';
    execute $gt17$
create function pg_temp.q_ev(p_event jsonb) returns text language sql immutable as $$
  select format('select event_append(%L::jsonb)', p_event) $$;
$gt17$;
    v_step := 'create function pg_temp.ev(p_stage text, p_action text, p_animal int default null) returns';
    execute $gt18$
create function pg_temp.ev(p_stage text, p_action text, p_animal int default null) returns jsonb language sql volatile as $$
  select jsonb_build_object('event_id', gen_random_uuid(), 'stage', p_stage, 'action', p_action, 'animal_no', p_animal,
                            'payload', '{}'::jsonb, 'actor', 'x', 'device_id', 'x', 'occurred_at', now()::text) $$;
$gt18$;
    v_step := 'create function pg_temp.q_upd(p_id int, p_set text) returns text language sql immutable as';
    execute $gt19$
create function pg_temp.q_upd(p_id int, p_set text) returns text language sql immutable as $$
  select format('with u as (update animals_pilot set %s where id = %s returning 1) select jsonb_build_object(''rows'', count(*)) from u', p_set, p_id) $$;
$gt19$;
    v_step := 'create function pg_temp.exc(r jsonb) returns text language sql immutable as $$ select coal';
    execute $gt20$
create function pg_temp.exc(r jsonb) returns text language sql immutable as $$ select coalesce(r ->> 'exception', '') $$;
$gt20$;
    v_step := 'create function pg_temp.err(r jsonb) returns text language sql immutable as $$ select coal';
    execute $gt21$
create function pg_temp.err(r jsonb) returns text language sql immutable as $$ select coalesce(r ->> 'error', r ->> 'exception', '') $$;
$gt21$;
    v_step := 'create function pg_temp.ok(r jsonb) returns boolean language sql immutable as $$ select co';
    execute $gt22$
create function pg_temp.ok(r jsonb) returns boolean language sql immutable as $$ select coalesce((r ->> 'ok')::boolean, false) $$;
$gt22$;
    v_step := 'create function pg_temp.claimed(r jsonb) returns boolean language sql immutable as $$ sele';
    execute $gt23$
create function pg_temp.claimed(r jsonb) returns boolean language sql immutable as $$ select coalesce((r ->> 'claimed')::boolean, false) $$;
$gt23$;
    v_step := 'create function pg_temp.ar(p_id int) returns animals_pilot language sql stable as $$ selec';
    execute $gt24$
create function pg_temp.ar(p_id int) returns animals_pilot language sql stable as $$ select * from animals_pilot where id = p_id $$;
$gt24$;
    v_step := 'create function pg_temp.testmode(p_on boolean) returns void language sql as $$';
    execute $gt25$
create function pg_temp.testmode(p_on boolean) returns void language sql as $$
  update plant_state set value = case when p_on then 'on' else 'off' end where key = 'testMode' $$;
$gt25$;
    v_step := 'make an open lung check look 11 minutes old';
    execute $gt26$
-- make an open lung check look 11 minutes old
create function pg_temp.age_inner(p_id int) returns void language plpgsql as $$
begin
  perform set_config('gt.reset_in_progress', 'true', true);
  update animals_pilot set inner_time = inner_time - 660000 where id = p_id;
  perform set_config('gt.reset_in_progress', 'false', true);
end $$;
$gt26$;
    v_step := 'step 46: bring an animal (as the server, no checks) to the point where the';
    execute $gt27$
-- step 46: bring an animal (as the server, no checks) to the point where the
-- next station may act: 'slaughter' = slaughtered; 'inner' = inner confirmed
-- (ready for the outer inspector); 'outer' = ruled glatt by the outer inspector
-- an animal write that went through: claim_animal_stage → claimed, animal_push → ok
create function pg_temp.wrote(r jsonb) returns boolean language sql immutable as $$
  select coalesce((r ->> 'claimed')::boolean, false) or coalesce((r ->> 'ok')::boolean, false) $$;
$gt27$;
    v_step := 'create function pg_temp.prep(p_id int, p_upto text) returns void language plpgsql as $$';
    execute $gt28$
create function pg_temp.prep(p_id int, p_upto text) returns void language plpgsql as $$
declare t bigint := (extract(epoch from now()) * 1000)::bigint - 3600000;
begin
  perform set_config('gt.reset_in_progress', 'true', true);
  update animals_pilot set slaughter = 'slaughtered', slaughter_time = t, slaughter_by_device = 'gtselftest_fixture'
   where id = p_id and slaughter is null;
  if p_upto in ('inner', 'outer') then
    update animals_pilot set inner_status = 'confirmed', inner_time = t, inner_by_device = 'gtselftest_fixture'
     where id = p_id and inner_status is null;
  end if;
  if p_upto = 'outer' then
    update animals_pilot set outer_status = 'glatt', outer_time = t, outer_by_device = 'gtselftest_fixture'
     where id = p_id and outer_status is null;
  end if;
  perform set_config('gt.reset_in_progress', 'false', true);
end $$;
$gt28$;
    v_step := 'fixture: test tablets (slots 90+), team leader, owner, manufacturer, workers';
    execute $gt29$
-- ── fixture: test tablets (slots 90+), team leader, owner, manufacturer, workers ──
do $$
declare
  tok text; v_id text; mid uuid; oid_ uuid; fid uuid; mtok text; xtok text; otok text; ftok text; code text; fcode text;
  devs text[][] := array[
    array['SL1','slaughter','90','active'], array['SL2','slaughter','91','active'], array['ESO1','esophagus','90','active'],
    array['ESO2','esophagus','91','active'], array['IN1','inner','90','active'], array['IN2','inner','91','active'],
    array['OUT1','outer','90','active'], array['OUT2','outer','91','active'], array['LEGS','legs','90','active'],
    array['PARTS','parts','90','active'], array['STAMPS','stamps','90','active'], array['RET','outer','92','retired'],
    array['UNP','','','active'], array['BRK','slaughter','92','active'], array['DISP','display','90','active'],
    array['NEW','','','active']];
  i int;
begin
  perform set_config('app.device_admin', 'on', true);
  for i in 1 .. array_length(devs, 1) loop
    v_id := 'gtselftest_' || lower(devs[i][1]) || '_' || substr(md5(random()::text), 1, 6);
    tok := encode(gen_random_bytes(24), 'hex');
    insert into devices_pilot (id, device_name, assigned_role, assigned_index, device_status, paired_at, auth_uid)
    values (v_id, 'selftest ' || devs[i][1], nullif(devs[i][2], ''), nullif(devs[i][3], '')::int, devs[i][4],
            case when devs[i][2] <> '' then now() end, gen_random_uuid());
    if devs[i][1] <> 'NEW' then
      insert into device_credentials (device_id, token_hash) values (v_id, encode(digest(tok, 'sha256'), 'hex'));
    end if;
    perform pg_temp.put('id_' || devs[i][1], v_id);
    perform pg_temp.put('tok_' || devs[i][1], tok);
    perform pg_temp.put('uid_' || devs[i][1], (select auth_uid::text from devices_pilot where id = v_id));
  end loop;
  perform set_config('app.device_admin', '', true);

  code := 'st-' || encode(gen_random_bytes(8), 'hex');
  fcode := 'stf-' || encode(gen_random_bytes(8), 'hex');
  insert into plant_managers (name, code_hash, role) values ('selftest leader', crypt(code, gen_salt('bf')), 'manager') returning id into mid;
  insert into plant_managers (name, code_hash, role) values ('selftest owner', crypt(encode(gen_random_bytes(8), 'hex'), gen_salt('bf')), 'owner') returning id into oid_;
  insert into plant_managers (name, code_hash, role) values ('selftest maker', crypt(fcode, gen_salt('bf')), 'manufacturer') returning id into fid;
  insert into manager_sessions (manager_id) values (mid) returning token into mtok;
  insert into manager_sessions (manager_id, expires_at) values (mid, now() - interval '1 minute') returning token into xtok;
  insert into manager_sessions (manager_id) values (oid_) returning token into otok;
  insert into manager_sessions (manager_id) values (fid) returning token into ftok;
  perform pg_temp.put('mgr', mtok);
  perform pg_temp.put('mgr_expired', xtok);
  perform pg_temp.put('owner', otok);
  perform pg_temp.put('maker', ftok);
  perform pg_temp.put('mgr_code', code);
  perform pg_temp.put('maker_code', fcode);
  perform pg_temp.put('mgr_id', mid::text);

  update settings_pilot
     set settings = coalesce(settings, '{}'::jsonb)
       || jsonb_build_object(
            'users', coalesce(case when jsonb_typeof(settings -> 'users') = 'array' then settings -> 'users' end, '[]'::jsonb)
                     || jsonb_build_array(jsonb_build_object('name', 'Selftest Inspector', 'role', 'inner', 'code', '739104'),
                                          jsonb_build_object('name', 'Selftest Slaughterer', 'role', 'slaughter', 'code', '550913')),
            'loginModeByRole', coalesce(settings -> 'loginModeByRole', '{}'::jsonb)
                               || jsonb_build_object('inner', 'code', 'outer', 'code', 'slaughter', 'none'),
            -- the checks start from the same plant switches on every server (the
            -- step-46 checks switch the esophagus check on where they need it)
            'esophagusEnabled', false,
            'screenConfig', '1in1out')       -- (the shared-screen check switches it itself)
     - 'esoFromIdx'
   where id = 1;
  delete from login_attempts;
  delete from rate_events where kind in ('maker_login', 'correction_rejected');
  update plant_state set value = 'off' where key = 'testMode';
  insert into plant_state (key, value) values ('supportAccessUntil', (now() - interval '1 minute')::text)
    on conflict (key) do update set value = excluded.value;

  -- animals 900..999: empty, today's board
  perform set_config('gt.reset_in_progress', 'true', true);
  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false, maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null, not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null, weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false, weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null, eso_prev_slaughter = null, eso_by_device = null,
    legs_sorted = false, stamped = false, stamped_as = null, parts_print_count = 0, parts_printed_as = null,
    outer_open_by_device = null, outer_open_at = null, not_chalak_outer = false,
    board_epoch = _board_epoch()
  where id between 900 and 999;
  perform set_config('gt.reset_in_progress', 'false', true);
end $$;
$gt29$;
    v_step := 'step 46: this plant''s own team-leader devices are set aside for the test (rolled back';
    execute $gt30$
-- step 46: this plant's own team-leader devices are set aside for the test (rolled back
-- at the end) — the checks below start like a plant before its first team-leader
-- device; the team-leader-device rules have their own section
do $$ begin
  if coalesce(current_setting('gt_st.ready', true), '') <> 'on' then  -- not inside the test: change nothing
    raise exception 'GlattTrack self-test: run the WHOLE file at once (nothing selected); nothing was changed';
  end if;
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = null, assigned_index = null where assigned_role = 'leader';
  delete from plant_state where key = 'leaderDevicesRequired';
  perform set_config('app.device_admin', '', true);
end $$;
$gt30$;
    v_step := 'the plant''s switches';
    execute $gt31$
-- ── the plant's switches ─────────────────────────────────────────────────────
do $$ begin
  perform pg_temp.rec('switch: test mode is OFF (default)', coalesce((select value from plant_state where key = 'testMode'), 'off') = 'off');
  perform pg_temp.rec('protection cannot be switched off (flags ignored)', _device_auth_required());
end $$;
$gt31$;
    v_step := 'step 44: the app may only READ the test flag';
    execute $gt32$
-- ── step 44: the app may only READ the test flag ────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb;
begin
  r  := pg_temp.api('{}'::jsonb, 'select to_jsonb(server_test_mode())');
  perform pg_temp.testmode(true);
  r2 := pg_temp.api('{}'::jsonb, 'select to_jsonb(server_test_mode())');
  perform pg_temp.testmode(false);
  r3 := pg_temp.api('{}'::jsonb, 'select to_jsonb(server_test_mode())');
  perform pg_temp.rec('server_test_mode(): anyone may read it, answers the SQL-only flag (off/on/off)',
    r = 'false'::jsonb and r2 = 'true'::jsonb and r3 = 'false'::jsonb
    and not exists (select 1 from pg_proc where oid = 'server_test_mode()'::regprocedure and provolatile <> 's'),
    concat_ws(' | ', r::text, r2::text, r3::text));
end $$;
$gt32$;
    v_step := 'tablets: retired / unpaired / fake key / forged id / wrong station';
    execute $gt33$
-- ── tablets: retired / unpaired / fake key / forged id / wrong station ──────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; a animals_pilot;
begin
  r  := pg_temp.api(pg_temp.dev('RET'), pg_temp.q_claim(900, 'slaughter', 'slaughtered', 'x', pg_temp.devid('RET')));
  r2 := pg_temp.api(pg_temp.dev('RET'), pg_temp.q_push(900, '{"slaughter":"shot","slaughter_time":1}'));
  r3 := pg_temp.api(pg_temp.dev('RET'), pg_temp.q_ev(pg_temp.ev('slaughter', 'x')));
  a := pg_temp.ar(900);
  perform pg_temp.rec('retired tablet cannot mutate',
    r ->> 'error' = 'wrong_station' and r2 ->> 'error' = 'device_not_paired' and r3 ->> 'error' = 'device_not_paired' and a.slaughter is null,
    concat_ws(' | ', r::text, r2::text, r3::text));

  r  := pg_temp.api(pg_temp.dev('UNP'), pg_temp.q_claim(900, 'slaughter', 'slaughtered', 'x', pg_temp.devid('UNP')));
  r2 := pg_temp.api(pg_temp.dev('UNP'), pg_temp.q_push(900, '{"slaughter":"shot","slaughter_time":1}'));
  r3 := pg_temp.api(pg_temp.dev('UNP'), 'select push_settings(''{"problemReports":[]}''::jsonb, ''x'')');
  r4 := pg_temp.api(pg_temp.dev('DISP'), pg_temp.q_push(900, '{"slaughter":"shot","slaughter_time":1}'));
  a := pg_temp.ar(900);
  perform pg_temp.rec('unpaired tablet / counter screen cannot mutate',
    r ->> 'error' = 'wrong_station' and r2 ->> 'error' = 'device_not_paired' and r3 ->> 'error' = 'device_not_paired'
    and r4 ->> 'error' = 'wrong_station' and a.slaughter is null,
    concat_ws(' | ', r::text, r2::text, r3::text, r4::text));

  r  := pg_temp.api('{"x-device-token":"not-a-real-key-000000000000"}', 'select device_whoami()');
  r2 := pg_temp.api('{"x-device-token":"not-a-real-key-000000000000"}', pg_temp.q_claim(900, 'slaughter', 'slaughtered', 'x', pg_temp.devid('SL1')));
  r3 := pg_temp.api('{"x-device-token":"not-a-real-key-000000000000"}', pg_temp.q_push(900, '{"slaughter":"shot","slaughter_time":1}'));
  perform pg_temp.rec('invalid device key rejected (device_not_paired)',
    (r ->> 'device_id') is null and r2 ->> 'error' = 'device_not_paired' and r3 ->> 'error' = 'device_not_paired'
    and (pg_temp.ar(900)).slaughter is null,
    concat_ws(' | ', r::text, r2::text, r3::text));

  update device_credentials set revoked = true where device_id = pg_temp.devid('UNP');
  r := pg_temp.api(pg_temp.dev('UNP'), 'select device_whoami()');
  perform pg_temp.rec('revoked device key rejected', (r ->> 'device_id') is null, r::text);

  -- no key, only a device id (in the body and in headers): never authorizes
  r  := pg_temp.api(jsonb_build_object('x-device-id', pg_temp.devid('SL1'), 'x-device', pg_temp.devid('SL1')),
                    pg_temp.q_claim(901, 'slaughter', 'slaughtered', 'x', pg_temp.devid('SL1')));
  r2 := pg_temp.api(jsonb_build_object('x-device-id', pg_temp.devid('SL1')),
                    pg_temp.q_push(901, jsonb_build_object('slaughter', 'shot', 'slaughter_time', 1,
                                                           'slaughter_by_device', pg_temp.devid('SL1'), 'device_id', pg_temp.devid('SL1'))));
  r4 := pg_temp.api(jsonb_build_object('x-device-id', pg_temp.devid('ESO1')),
                    format('select eso_change(901, ''nevela'', %L, %s)', pg_temp.devid('ESO1'), pg_temp.ep()));
  -- a real tablet naming another tablet (id + actor + by-device): recorded as itself
  perform pg_temp.prep(957, 'inner');
  r3 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(957, 'outer', 'glatt', 'x', pg_temp.devid('OUT1')));
  a := pg_temp.ar(901);
  perform pg_temp.rec('forged device id cannot authorize (device_not_paired); a tablet is always itself',
    r ->> 'error' = 'device_not_paired' and r2 ->> 'error' = 'device_not_paired' and r4 ->> 'error' = 'device_not_paired'
    and a.slaughter is null and pg_temp.claimed(r3) and (pg_temp.ar(957)).outer_by_device = pg_temp.devid('OUT2')
    and (pg_temp.ar(957)).device_id = pg_temp.devid('OUT2'),
    concat_ws(' | ', r::text, r2::text, r4::text, left(r3::text, 120), a.outer_by_device));

  r  := pg_temp.api(pg_temp.dev('LEGS'), pg_temp.q_claim(902, 'slaughter', 'slaughtered', 'x', pg_temp.devid('LEGS')));
  r2 := pg_temp.api(pg_temp.dev('IN1'), format('select eso_change(902, ''nevela'', %L, %s)', pg_temp.devid('IN1'), pg_temp.ep()));
  r3 := pg_temp.api(pg_temp.dev('LEGS'), pg_temp.q_push(902, '{"outer_status":"glatt","outer_time":99,"slaughter":"shot","slaughter_time":99,"weight_right":100}'));
  r4 := pg_temp.api(pg_temp.dev('SL1'), 'select set_not_chalak_outer(902, ' || pg_temp.ep() || ')');
  a := pg_temp.ar(902);
  perform pg_temp.rec('wrong station cannot mutate',
    r ->> 'error' = 'wrong_station' and r2 ->> 'error' = 'wrong_station' and r4 ->> 'error' = 'wrong_station'
    and a.outer_status is null and a.slaughter is null and a.weight_right is null and not a.not_chalak_outer,
    concat_ws(' | ', r::text, r2::text, left(r3::text, 80), r4::text));
end $$;
$gt33$;
    v_step := 'direct table writes are closed (only the RPCs write)';
    execute $gt34$
-- ── direct table writes are closed (only the RPCs write) ────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb;
begin
  r  := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_upd(903, 'slaughter = ''shot'', slaughter_time = 1'));
  r2 := pg_temp.api(pg_temp.dev('SL1'), format('with x as (insert into animals_pilot (id, board_epoch, slaughter) values (903, %s, ''shot'') on conflict (id) do update set slaughter = excluded.slaughter returning 1) select to_jsonb(count(*)) from x', pg_temp.ep()));
  r3 := pg_temp.api(pg_temp.dev('SL1'), 'with x as (insert into events_pilot (event_id, stage, action, occurred_at, event_hash) values (gen_random_uuid(), ''slaughter'', ''x'', now()::text, md5(random()::text)) returning 1) select to_jsonb(count(*)) from x');
  r4 := pg_temp.api(pg_temp.dev('SL1'), format('with u as (update devices_pilot set assigned_role = ''outer'' where id = %L returning 1) select to_jsonb(count(*)) from u', pg_temp.devid('SL1')));
  perform pg_temp.rec('direct INSERT/UPDATE on animals_pilot, INSERT on events_pilot, UPDATE devices_pilot: permission denied',
    r ->> 'sqlstate' = '42501' and r2 ->> 'sqlstate' = '42501' and r3 ->> 'sqlstate' = '42501' and r4 ->> 'sqlstate' = '42501'
    and (pg_temp.ar(903)).slaughter is null,
    concat_ws(' | ', r::text, r2::text, r3::text, r4::text));
  r  := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_push(903, '{"slaughter":"shot","slaughter_time":1,"bogus_column":1,"updated_at":"2000-01-01","not_chalak_outer":true}'));
  perform pg_temp.rec('animal_push applies whitelisted columns and reports the others',
    pg_temp.ok(r) and (r -> 'rows' -> 0 ->> 'slaughter') = 'shot' and (r -> 'rows' -> 0 ->> 'slaughter_by_device') = pg_temp.devid('SL1')
    and r -> 'ignored' ? 'bogus_column' and r -> 'ignored' ? 'not_chalak_outer' and not (pg_temp.ar(903)).not_chalak_outer,
    left(r::text, 300));
  r  := pg_temp.api(pg_temp.dev('SL1'), 'select animal_push(''[{"id":1000}]''::jsonb)');
  r2 := pg_temp.api(pg_temp.dev('SL1'), 'select animal_push(''"x"''::jsonb)');
  r3 := pg_temp.api(pg_temp.dev('STAMPS'), pg_temp.q_push(903, '{"weight_right":"heavy"}'));
  r4 := pg_temp.api(pg_temp.dev('SL1'), format('select animal_push(%L::jsonb)', jsonb_build_array(
          jsonb_build_object('id', 904, 'board_epoch', pg_temp.ep(), 'slaughter', 'slaughtered', 'slaughter_time', 5),
          jsonb_build_object('id', 905, 'board_epoch', pg_temp.ep(), 'slaughter', 'bogus', 'slaughter_time', 5))));
  perform pg_temp.rec('animal_push: bad id / bad rows / bad value; a failing batch applies nothing',
    r ->> 'error' = 'bad_id' and r2 ->> 'error' = 'bad_rows' and r3 ->> 'error' = 'invalid_value'
    and r4 ->> 'error' = 'invalid_value' and (r4 ->> 'id')::int = 905 and (pg_temp.ar(904)).slaughter is null,
    concat_ws(' | ', r::text, r2::text, r3::text, left(r4::text, 100)));
end $$;
$gt34$;
    v_step := 'team-leader sessions';
    execute $gt35$
-- ── team-leader sessions ─────────────────────────────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; t text; ok boolean;
begin
  r  := pg_temp.api('{}', format('select reset_daily_board(%L)', pg_temp.v('mgr_expired')));
  r2 := pg_temp.api('{}', format('select device_pair(%L, ''000000'', ''outer'', 0, true, null)', pg_temp.v('mgr_expired')));
  r3 := pg_temp.api(pg_temp.mgr('mgr_expired'), pg_temp.q_ev(pg_temp.ev('settings', 'update')));
  perform pg_temp.rec('expired team-leader session rejected',
    r ->> 'error' = 'unauthorized' and r2 ->> 'error' = 'unauthorized' and r3 ->> 'error' = 'device_not_paired',
    concat_ws(' | ', r::text, r2::text, r3::text));
  r := pg_temp.api('{}', 'select reset_daily_board(''not-a-real-session'')');
  perform pg_temp.rec('fake team-leader session rejected', r ->> 'error' = 'unauthorized', r::text);

  -- login: 10 hours, bound to the device key and the app session it was made with
  r := pg_temp.api3(pg_temp.dev('OUT1'), jsonb_build_object('role', 'authenticated', 'sub', pg_temp.v('uid_OUT1')),
                    format('select manager_login(%L)', pg_temp.v('mgr_code')));
  t := r ->> 'token';
  ok := pg_temp.ok(r) and (r ->> 'expires_at')::timestamptz <= now() + interval '10 hours 1 minute'
        and exists (select 1 from manager_sessions where token = t and device_id = pg_temp.devid('OUT1')
                                                    and auth_uid = pg_temp.v('uid_OUT1')::uuid);
  perform pg_temp.rec('team-leader login: 10 hours, device + app session recorded', ok, left(r::text, 200));
  r  := pg_temp.api3(pg_temp.dev('OUT1') || jsonb_build_object('x-manager-token', t),
                     jsonb_build_object('role', 'authenticated', 'sub', pg_temp.v('uid_OUT1')), format('select manager_session_check(%L)', t));
  r2 := pg_temp.api3(pg_temp.dev('OUT2') || jsonb_build_object('x-manager-token', t),
                     jsonb_build_object('role', 'authenticated', 'sub', pg_temp.v('uid_OUT1')), format('select manager_session_check(%L)', t));
  r3 := pg_temp.api3(jsonb_build_object('x-manager-token', t),
                     jsonb_build_object('role', 'authenticated', 'sub', pg_temp.v('uid_OUT1')), format('select manager_list(%L)', t));
  r4 := pg_temp.api3(pg_temp.dev('OUT1') || jsonb_build_object('x-manager-token', t),
                     jsonb_build_object('role', 'authenticated', 'sub', gen_random_uuid()), format('select reset_daily_board(%L)', t));
  perform pg_temp.rec('team-leader session from another device / no device / another app session: rejected',
    pg_temp.ok(r) and not pg_temp.ok(r2) and r3 ->> 'error' = 'unauthorized' and r4 ->> 'error' = 'unauthorized',
    concat_ws(' | ', r::text, r2::text, r3::text, r4::text));
  -- a session made before the app session existed is bound once, never re-bound
  r := pg_temp.api3(jsonb_build_object('x-manager-token', pg_temp.v('owner')),
                    jsonb_build_object('role', 'authenticated', 'sub', '11111111-1111-1111-1111-111111111111'),
                    format('select device_heartbeat(%L, null, null)', 'x'));
  r := pg_temp.api3(jsonb_build_object('x-manager-token', pg_temp.v('owner')),
                    jsonb_build_object('role', 'authenticated', 'sub', '22222222-2222-2222-2222-222222222222'),
                    format('select device_heartbeat(%L, null, null)', 'x'));
  r2 := pg_temp.api3('{}', jsonb_build_object('role', 'authenticated', 'sub', '22222222-2222-2222-2222-222222222222'),
                     format('select security_summary(%L)', pg_temp.v('owner')));
  r3 := pg_temp.api3('{}', jsonb_build_object('role', 'authenticated', 'sub', '11111111-1111-1111-1111-111111111111'),
                     format('select security_summary(%L)', pg_temp.v('owner')));
  perform pg_temp.rec('team-leader session: bound to the first app session, not re-bound by another',
    r2 ->> 'error' = 'unauthorized' and pg_temp.ok(r3), concat_ws(' | ', r2::text, left(r3::text, 80)));
  -- the switches that used to disable protection are ignored
  update system_flags set value = false where key in ('device_auth_required', 'manager_auth_required');
  r  := pg_temp.api('{}', 'select reset_daily_board(''not-a-real-session'')');
  r2 := pg_temp.api(pg_temp.dev('UNP'), pg_temp.q_push(906, '{"slaughter":"shot","slaughter_time":1}'));
  r3 := pg_temp.api('{}', pg_temp.q_ev(pg_temp.ev('slaughter', 'x')));
  update system_flags set value = true where key in ('device_auth_required', 'manager_auth_required');
  perform pg_temp.rec('fail closed: protection switches in system_flags are ignored',
    r ->> 'error' = 'unauthorized' and r2 ->> 'error' = 'device_not_paired' and r3 ->> 'error' = 'device_not_paired',
    concat_ws(' | ', r::text, r2::text, r3::text));
end $$;
$gt35$;
    v_step := 'the team leader never rules; test mode (SQL-only switch) lets him act as a station';
    execute $gt36$
-- ── the team leader never rules; test mode (SQL-only switch) lets him act as a station ──
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; r6 jsonb; ok boolean;
begin
  r  := pg_temp.api(pg_temp.mgr(), pg_temp.q_claim(907, 'slaughter', 'slaughtered', 'leader', 'leader-browser'));
  r2 := pg_temp.api(pg_temp.mgr(), pg_temp.q_push(907, '{"slaughter":"shot","slaughter_time":5}'));
  r3 := pg_temp.api(pg_temp.mgr(), format('select eso_change(907, ''nevela'', ''x'', %s)', pg_temp.ep()));
  r4 := pg_temp.api(pg_temp.mgr(), format('select set_not_chalak_outer(907, %s)', pg_temp.ep()));
  r5 := pg_temp.api(pg_temp.mgr(), format('select outer_open(907, %s, true, ''x'')', pg_temp.ep()));
  r6 := pg_temp.api(pg_temp.mgr(), format('select lung_drawing_set(907, %s, ''data:image/png;base64,AAAA'')', pg_temp.ep()));
  ok := r ->> 'error' = 'wrong_station' and r2 ->> 'error' = 'wrong_station' and r3 ->> 'error' = 'wrong_station'
        and r4 ->> 'error' = 'wrong_station' and r5 ->> 'error' = 'wrong_station' and r6 ->> 'error' = 'wrong_station'
        and (pg_temp.ar(907)).slaughter is null;
  perform pg_temp.rec('team leader, test mode OFF: no ruling anywhere (claim/push/eso/rabbinate/open/lung)', ok,
    concat_ws(' | ', r::text, r2::text, r3::text, r4::text, r5::text, r6::text));
  -- the owner and the manufacturer neither
  r  := pg_temp.api(pg_temp.mgr('owner'), pg_temp.q_claim(907, 'slaughter', 'slaughtered', 'x', 'x'));
  r2 := pg_temp.api(pg_temp.mgr('maker'), pg_temp.q_claim(907, 'slaughter', 'slaughtered', 'x', 'x'));
  perform pg_temp.rec('owner / manufacturer sessions: no ruling rights',
    pg_temp.err(r) in ('device_not_paired', 'wrong_station') and pg_temp.err(r2) in ('device_not_paired', 'wrong_station')
    and (pg_temp.ar(907)).slaughter is null, concat_ws(' | ', r::text, r2::text));
  -- the API can't turn test mode on
  r := pg_temp.api(pg_temp.mgr(), format('select push_settings(''{"testMode":"on"}''::jsonb, ''x'', %L)', pg_temp.v('mgr')));
  perform pg_temp.rec('test mode cannot be switched on through the API',
    coalesce((select value from plant_state where key = 'testMode'), 'off') = 'off' and r -> 'ignored' ? 'testMode', r::text);

  perform pg_temp.prep(908, 'inner'); perform pg_temp.prep(909, 'inner');
  perform pg_temp.testmode(true);
  r  := pg_temp.api(pg_temp.mgr(), pg_temp.q_claim(907, 'slaughter', 'slaughtered', 'leader', 'leader-browser'));
  r2 := pg_temp.api(pg_temp.mgr(), pg_temp.q_push(907, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(907)).slaughter_time + 5)));
  r3 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(908, 'outer', 'glatt', '', ''));
  r4 := pg_temp.api(pg_temp.mgr(), pg_temp.q_push(908, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(908)).outer_time + 5)));
  r5 := pg_temp.api(pg_temp.mgr(), format('select set_not_chalak_outer(909, %s)', pg_temp.ep()));
  perform pg_temp.testmode(false);
  ok := pg_temp.claimed(r) and (pg_temp.ar(907)).slaughter_by_device like 'mgr-%' and pg_temp.ok(r2) and (pg_temp.ar(907)).slaughter = 'shot'
        and r4 ->> 'error' = 'correction_not_allowed' and (pg_temp.ar(908)).outer_status = 'glatt' and pg_temp.ok(r5);
  perform pg_temp.rec('team leader, test mode ON: acts as a station (own rulings only, no override)', ok,
    concat_ws(' | ', left(r::text, 80), left(r2::text, 60), r4::text, r5 ->> 'ok'));
end $$;
$gt36$;
    v_step := 'first claims: exactly one wins; retries are idempotent';
    execute $gt37$
-- ── first claims: exactly one wins; retries are idempotent ──────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; ok boolean := true; det text := ''; c uuid := gen_random_uuid(); c2 uuid := gen_random_uuid();
begin
  r  := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(910, 'slaughter', 'slaughtered', '', pg_temp.devid('SL1')));
  r2 := pg_temp.api(pg_temp.dev('SL2'), pg_temp.q_claim(910, 'slaughter', 'shot', '', pg_temp.devid('SL2')));
  ok := ok and pg_temp.claimed(r) and not pg_temp.claimed(r2)
           and (pg_temp.ar(910)).slaughter = 'slaughtered' and (pg_temp.ar(910)).slaughter_by_device = pg_temp.devid('SL1');
  det := det || 'slaughter ' || (r ->> 'claimed') || '/' || (r2 ->> 'claimed');
  r  := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(910, 'inner_start', 'in_progress', '', pg_temp.devid('IN1')));
  r2 := pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_claim(910, 'inner_start', 'in_progress', '', pg_temp.devid('IN2')));
  ok := ok and pg_temp.claimed(r) and not pg_temp.claimed(r2) and (pg_temp.ar(910)).inner_by_device = pg_temp.devid('IN1');
  perform pg_temp.prep(911, 'inner');
  r  := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(911, 'outer', 'glatt', '', pg_temp.devid('OUT1')));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(911, 'outer', 'treif', '', pg_temp.devid('OUT2')));
  ok := ok and pg_temp.claimed(r) and not pg_temp.claimed(r2) and (pg_temp.ar(911)).outer_status = 'glatt';
  perform pg_temp.prep(958, 'slaughter');
  r  := pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(958, 'eso', 'ok', '', pg_temp.devid('ESO1')));
  r2 := pg_temp.api(pg_temp.dev('ESO2'), pg_temp.q_claim(958, 'eso', 'nevela', '', pg_temp.devid('ESO2')));
  ok := ok and pg_temp.claimed(r) and not pg_temp.claimed(r2) and (pg_temp.ar(958)).eso_result = 'ok'
           and (pg_temp.ar(958)).eso_by_device = pg_temp.devid('ESO1');
  perform pg_temp.rec('conflicting claims from two devices: exactly one wins', ok, det);

  -- the same device sending the same claim again (lost answer): claimed, not a conflict
  r  := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(910, 'slaughter', 'slaughtered', '', 'x'));
  r2 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(911, 'outer', 'glatt', '', 'x'));
  r3 := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(910, 'slaughter', 'shot', '', 'x'));
  perform pg_temp.rec('same-device same-value retry → claimed:true duplicate; another value → not claimed',
    pg_temp.claimed(r) and (r ->> 'duplicate')::boolean and pg_temp.claimed(r2) and not pg_temp.claimed(r3)
    and (pg_temp.ar(910)).slaughter = 'slaughtered', concat_ws(' | ', left(r::text, 60), left(r2::text, 60), left(r3::text, 60)));

  -- command ids: the same command from the same device is answered, not re-run
  r  := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claimc(912, 'slaughter', 'slaughtered', c));
  r2 := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claimc(912, 'slaughter', 'slaughtered', c));
  r3 := pg_temp.api(pg_temp.dev('SL2'), pg_temp.q_claimc(912, 'slaughter', 'slaughtered', c));
  ok := pg_temp.claimed(r) and pg_temp.claimed(r2) and (r2 ->> 'replayed')::boolean and r3 ->> 'error' = 'command_id_conflict';
  r  := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_push(912, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(912)).slaughter_time + 5), c2));
  r2 := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_push(912, jsonb_build_object('slaughter', 'nevela', 'slaughter_time', (pg_temp.ar(912)).slaughter_time + 5), c2));
  ok := ok and pg_temp.ok(r) and (r2 ->> 'replayed')::boolean and (pg_temp.ar(912)).slaughter = 'shot'
        and exists (select 1 from processed_commands where command_id = c2 and device_id = pg_temp.devid('SL1') and fn = 'animal_push');
  perform pg_temp.rec('duplicate retry with the same command id: stored answer, not executed again; other device: conflict', ok,
    concat_ws(' | ', left(r::text, 60), left(r2::text, 80), r3::text));
  -- stale / future board day
  r  := pg_temp.api(pg_temp.dev('SL1'), format('select claim_animal_stage(913, ''slaughter'', ''slaughtered'', '''', ''x'', %s)', pg_temp.ep() - 1));
  r2 := pg_temp.api(pg_temp.dev('SL1'), format('select animal_push(%L::jsonb)', jsonb_build_object('id', 913, 'board_epoch', pg_temp.ep() - 1, 'slaughter', 'shot', 'slaughter_time', 1)));
  r3 := pg_temp.api(pg_temp.dev('SL1'), format('select animal_push(%L::jsonb)', jsonb_build_object('id', 913, 'board_epoch', pg_temp.ep() + 86400000, 'legs_stickers', true)));
  perform pg_temp.rec('stale board day refused; a future day is stored as today''s',
    r ->> 'error' = 'stale_board' and r2 ->> 'error' = 'stale_board' and (pg_temp.ar(913)).slaughter is null
    and (pg_temp.ar(913)).board_epoch = pg_temp.ep(), concat_ws(' | ', r::text, r2::text, left(r3::text, 80)));
end $$;
$gt37$;
    v_step := 'corrections';
    execute $gt38$
-- ── corrections ──────────────────────────────────────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean;
begin
  -- same tablet, right away → allowed (all four stages; inner reopen too)
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(914, 'slaughter', 'slaughtered', '', ''));
  r := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_push(914, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(914)).slaughter_time + 5)));
  perform pg_temp.prep(959, 'slaughter');
  perform pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(959, 'eso', 'ok', '', ''));
  r2 := pg_temp.api(pg_temp.dev('ESO1'), format('select eso_change(959, ''nevela'', ''x'', %s)', pg_temp.ep()));
  perform pg_temp.prep(915, 'slaughter');
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(915, 'inner_start', 'in_progress', '', ''));
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(915, 'inner', 'confirmed', '', ''));
  r3 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(915, jsonb_build_object('inner_status', 'in_progress', 'inner_time', (pg_temp.ar(915)).inner_time + 5)));
  r3 := r3 || jsonb_build_object('reclaim', pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(915, 'inner', 'treif', '', '')) -> 'claimed');
  -- (step 46: an animal treif inside never reaches the outer inspector — the outer correction uses #960)
  perform pg_temp.prep(960, 'inner');
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(960, 'outer', 'glatt', '', ''));
  r4 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(960, jsonb_build_object('outer_status', 'beit', 'outer_time', (pg_temp.ar(960)).outer_time + 5)));
  ok := pg_temp.ok(r) and (pg_temp.ar(914)).slaughter = 'shot'
        and (pg_temp.ar(959)).slaughter = 'nevela' and (pg_temp.ar(959)).eso_prev_slaughter = 'slaughtered'
        and pg_temp.ok(r2) and pg_temp.ok(r3) and (r3 ->> 'reclaim')::boolean and (pg_temp.ar(915)).inner_status = 'treif'
        and pg_temp.ok(r4) and (pg_temp.ar(960)).outer_status = 'beit';
  perform pg_temp.rec('correction by the same tablet right away: allowed', ok,
    concat_ws(' | ', left(r::text, 60), left(r2::text, 60), left(r3::text, 60), left(r4::text, 60)));

  -- the tablet moved on (ruled another animal after this one) → refused
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(916, 'slaughter', 'slaughtered', '', ''));
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(917, 'slaughter', 'slaughtered', '', ''));
  r := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_push(916, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(916)).slaughter_time + 5)));
  perform pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(916, 'eso', 'ok', '', ''));
  perform pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(917, 'eso', 'ok', '', ''));
  r2 := pg_temp.api(pg_temp.dev('ESO1'), format('select eso_change(916, ''nevela'', ''x'', %s)', pg_temp.ep()));
  perform pg_temp.prep(918, 'slaughter'); perform pg_temp.prep(919, 'slaughter');
  perform pg_temp.prep(920, 'inner'); perform pg_temp.prep(921, 'inner');
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(918, 'inner', 'confirmed', '', ''));
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(919, 'inner_start', 'in_progress', '', ''));
  r3 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(918, jsonb_build_object('inner_status', 'treif', 'inner_time', (pg_temp.ar(918)).inner_time + 5)));
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(920, 'outer', 'glatt', '', ''));
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(921, 'outer', 'glatt', '', ''));
  r4 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(920, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(920)).outer_time + 5)));
  ok := r ->> 'error' = 'moved_on' and r2 ->> 'error' = 'moved_on' and r3 ->> 'error' = 'moved_on' and r4 ->> 'error' = 'moved_on'
        and (pg_temp.ar(916)).slaughter = 'slaughtered' and (pg_temp.ar(916)).eso_result = 'ok'
        and (pg_temp.ar(918)).inner_status = 'confirmed' and (pg_temp.ar(920)).outer_status = 'glatt'
        and r -> 'row' ->> 'slaughter' = 'slaughtered';
  perform pg_temp.rec('correction after the tablet moved on: refused (moved_on, server row returned)', ok,
    concat_ws(' | ', r ->> 'error', r2 ->> 'error', r3 ->> 'error', r4 ->> 'error'));

  -- judged by TIME, not by number: a late (lower-numbered) animal
  perform pg_temp.prep(922, 'inner'); perform pg_temp.prep(923, 'inner'); perform pg_temp.prep(924, 'inner');
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(923, 'outer', 'kosher', '', ''));
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(924, 'outer', 'kosher', '', ''));
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(922, 'outer', 'kosher', '', ''));        -- #922 arrives late
  r  := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(922, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(922)).outer_time + 5)));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(924, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(924)).outer_time + 5)));
  perform pg_temp.api(pg_temp.dev('SL2'), pg_temp.q_claim(926, 'slaughter', 'slaughtered', '', ''));
  perform pg_temp.api(pg_temp.dev('SL2'), pg_temp.q_claim(925, 'slaughter', 'slaughtered', '', ''));
  r3 := pg_temp.api(pg_temp.dev('SL2'), pg_temp.q_push(925, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(925)).slaughter_time + 5)));
  r4 := pg_temp.api(pg_temp.dev('SL2'), pg_temp.q_push(926, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(926)).slaughter_time + 5)));
  ok := pg_temp.ok(r) and (pg_temp.ar(922)).outer_status = 'treif' and r2 ->> 'error' = 'moved_on' and (pg_temp.ar(924)).outer_status = 'kosher'
        and pg_temp.ok(r3) and (pg_temp.ar(925)).slaughter = 'shot' and r4 ->> 'error' = 'moved_on'
        and (select animal_id from device_stage_cursor where device_id = pg_temp.devid('OUT2') and stage = 'outer') = 922;
  perform pg_temp.rec('moved on is judged by time: a late animal can be ruled and corrected right away; the higher one is locked', ok,
    concat_ws(' | ', left(r::text, 40), r2 ->> 'error', left(r3::text, 40), r4 ->> 'error'));

  -- another tablet / another station → refused
  r  := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(921, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(921)).outer_time + 5, 'outer_by_device', pg_temp.devid('OUT1'))));
  r2 := pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_push(921, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(921)).outer_time + 5)));
  r3 := pg_temp.api(pg_temp.dev('SL2'), pg_temp.q_push(917, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(917)).slaughter_time + 5)));
  r4 := pg_temp.api(pg_temp.dev('ESO2'), format('select eso_change(917, ''nevela'', %L, %s)', pg_temp.devid('ESO1'), pg_temp.ep()));
  -- (step 46: an inner tablet has no outer rights at all — its outer value is simply not applied)
  ok := r ->> 'error' = 'correction_not_allowed' and pg_temp.ok(r2)
        and r3 ->> 'error' = 'correction_not_allowed' and r4 ->> 'error' = 'correction_not_allowed'
        and (pg_temp.ar(921)).outer_status = 'glatt' and (pg_temp.ar(917)).slaughter = 'slaughtered' and (pg_temp.ar(917)).eso_result = 'ok';
  perform pg_temp.rec('correction by another tablet / station: refused (correction_not_allowed)', ok,
    concat_ws(' | ', r ->> 'error', r2 ->> 'error', r3 ->> 'error', r4 ->> 'error'));
  perform pg_temp.rec('refused corrections are logged (event log + brake counter)',
    exists (select 1 from events_pilot where stage = 'security' and action = 'correction_rejected' and animal_no = 919
                                           and device_id = pg_temp.devid('IN1'))
    and exists (select 1 from events_pilot where stage = 'security' and action = 'correction_rejected' and animal_no = 921
                                           and device_id = pg_temp.devid('OUT1'))
    and (select count(*) from rate_events where kind = 'correction_rejected' and key = pg_temp.devid('OUT2')) >= 1);

  -- a later stage already acted → refused, even for the tablet that ruled
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(927, 'slaughter', 'slaughtered', '', ''));
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(927, 'inner_start', 'in_progress', '', ''));
  r := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_push(927, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(927)).slaughter_time + 5)));
  perform pg_temp.prep(928, 'slaughter'); perform pg_temp.prep(929, 'slaughter');
  perform pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(928, 'eso', 'ok', '', ''));
  perform pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_claim(928, 'inner_start', 'in_progress', '', ''));
  r2 := pg_temp.api(pg_temp.dev('ESO1'), format('select eso_change(928, ''nevela'', ''x'', %s)', pg_temp.ep()));
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(929, 'inner', 'confirmed', '', ''));
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(929, 'outer', 'kosher', '', ''));
  r3 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(929, jsonb_build_object('inner_status', 'in_progress', 'inner_time', (pg_temp.ar(929)).inner_time + 5)));
  r4 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(929, jsonb_build_object('maw', 'treif', 'not_chalak_inner', true, 'inner_time', (pg_temp.ar(929)).inner_time + 6)));
  ok := r ->> 'error' = 'correction_not_allowed' and r2 ->> 'error' = 'correction_not_allowed'
        and r3 ->> 'error' = 'correction_not_allowed' and r4 ->> 'error' = 'correction_not_allowed'
        and (pg_temp.ar(927)).slaughter = 'slaughtered' and (pg_temp.ar(929)).inner_status = 'confirmed';
  perform pg_temp.rec('correction after a later stage acted: refused', ok,
    concat_ws(' | ', r ->> 'error', r2 ->> 'error', r3 ->> 'error', r4 ->> 'error'));

  -- outer ruling after parts print / stamp / legs sort → refused; stickers only → allowed
  perform pg_temp.prep(930, 'inner'); perform pg_temp.prep(931, 'inner'); perform pg_temp.prep(932, 'inner'); perform pg_temp.prep(933, 'inner');
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(930, 'outer', 'glatt', '', ''));
  perform pg_temp.api(pg_temp.dev('PARTS'), pg_temp.q_push(930, '{"parts_print_count":1,"parts_printed_as":"glatt"}'));
  r := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(930, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(930)).outer_time + 5)));
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(931, 'outer', 'glatt', '', ''));
  perform pg_temp.api(pg_temp.dev('STAMPS'), pg_temp.q_claim(931, 'stamped', 'true', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(931, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(931)).outer_time + 5)));
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(932, 'outer', 'glatt', '', ''));
  perform pg_temp.api(pg_temp.dev('LEGS'), pg_temp.q_claim(932, 'legs', 'true', '', ''));
  r3 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(932, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(932)).outer_time + 5)));
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(933, 'outer', 'glatt', '', ''));
  perform pg_temp.api(pg_temp.dev('LEGS'), pg_temp.q_push(933, '{"legs_stickers":true,"head_stickers":true}'));
  r4 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(933, jsonb_build_object('outer_status', 'beit', 'outer_time', (pg_temp.ar(933)).outer_time + 5)));
  ok := r ->> 'error' = 'correction_not_allowed' and r2 ->> 'error' = 'correction_not_allowed'
        and r3 ->> 'error' = 'correction_not_allowed' and pg_temp.ok(r4)
        and (pg_temp.ar(930)).outer_status = 'glatt' and (pg_temp.ar(931)).stamped and (pg_temp.ar(932)).legs_sorted
        and (pg_temp.ar(933)).outer_status = 'beit';
  perform pg_temp.rec('outer correction after print / stamp / legs sort: refused (stickers only: allowed)', ok,
    concat_ws(' | ', r ->> 'error', r2 ->> 'error', r3 ->> 'error', left(r4::text, 40)));

  -- lung check: abandoned only by the tablet that opened it; 10-minute takeover still works
  perform pg_temp.prep(934, 'slaughter'); perform pg_temp.prep(935, 'slaughter'); perform pg_temp.prep(936, 'slaughter');
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(934, 'inner_start', 'in_progress', '', ''));
  perform pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_push(934, jsonb_build_object('inner_status', null, 'inner_time', (pg_temp.ar(934)).inner_time + 5)));
  ok := (pg_temp.ar(934)).inner_status = 'in_progress';
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(934, jsonb_build_object('inner_status', null, 'inner_time', (pg_temp.ar(934)).inner_time + 5)));
  ok := ok and (pg_temp.ar(934)).inner_status is null;
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(935, 'inner_start', 'in_progress', '', ''));
  perform pg_temp.age_inner(935);
  r := pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_claim(935, 'inner_start', 'in_progress', '', ''));
  ok := ok and pg_temp.claimed(r) and (pg_temp.ar(935)).inner_by_device = pg_temp.devid('IN2');
  perform pg_temp.rec('lung check: abandon by its tablet only; 10-minute takeover works', ok, r ->> 'claimed');

  -- inner takeover: A opens, 10+ min, B takes over, A submits → refused, B's check kept, refusal recorded
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(936, 'inner_start', 'in_progress', '', ''));
  perform pg_temp.age_inner(936);
  r  := pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_claim(936, 'inner_start', 'in_progress', '', ''));
  r2 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(936, 'inner', 'confirmed', '', ''));
  r3 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(936, jsonb_build_object('inner_status', 'treif', 'inner_time', (pg_temp.ar(936)).inner_time + 50, 'maw', 'treif')));
  ok := pg_temp.claimed(r) and not pg_temp.claimed(r2) and pg_temp.ok(r3)
        and (pg_temp.ar(936)).inner_status = 'in_progress' and (pg_temp.ar(936)).inner_by_device = pg_temp.devid('IN2')
        and (pg_temp.ar(936)).maw is null
        and (select count(*) from events_pilot where stage = 'security' and action = 'inner_takeover_rejected'
                                                and animal_no = 937 and device_id = pg_temp.devid('IN1')) >= 2;
  r4 := pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_claim(936, 'inner', 'confirmed', '', ''));
  ok := ok and pg_temp.claimed(r4) and (pg_temp.ar(936)).inner_status = 'confirmed';
  perform pg_temp.rec('inner takeover: the tablet that lost the check is refused (claim + push), B''s state kept, refusal recorded', ok,
    concat_ws(' | ', r ->> 'claimed', r2 ->> 'claimed', left(r3::text, 60), r4 ->> 'claimed'));
end $$;
$gt38$;
    v_step := 'the rabbinate outer screen ("not chalak")';
    execute $gt39$
-- ── the rabbinate outer screen ("not chalak") ────────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; ok boolean; c uuid := gen_random_uuid();
begin
  perform set_config('gt.reset_in_progress', 'true', true);
  update animals_pilot set slaughter = 'slaughtered', slaughter_time = 1, inner_status = 'confirmed', inner_time = 1 where id between 938 and 943;
  update animals_pilot set slaughter = 'notChalak' where id = 941;
  update animals_pilot set not_chalak_inner = true where id = 942;
  perform set_config('gt.reset_in_progress', 'false', true);
  r  := pg_temp.api(pg_temp.dev('IN1'), format('select set_not_chalak_outer(938, %s)', pg_temp.ep()));
  r2 := pg_temp.api(pg_temp.dev('SL1'), format('select set_not_chalak_outer(938, %s)', pg_temp.ep()));
  r3 := pg_temp.api(pg_temp.mgr(), format('select set_not_chalak_outer(938, %s)', pg_temp.ep()));
  r4 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(938, '{"not_chalak_outer":true}'));
  ok := r ->> 'error' = 'wrong_station' and r2 ->> 'error' = 'wrong_station' and r3 ->> 'error' = 'wrong_station'
        and not (pg_temp.ar(938)).not_chalak_outer;
  perform pg_temp.rec('rabbinate send by inner / slaughter / team leader / a plain push: refused', ok,
    concat_ws(' | ', r::text, r2::text, r3::text, left(r4::text, 60)));
  r  := pg_temp.api(pg_temp.dev('OUT1'), format('select set_not_chalak_outer(938, %s, %L::uuid)', pg_temp.ep(), c));
  r2 := pg_temp.api(pg_temp.dev('OUT1'), format('select set_not_chalak_outer(938, %s, %L::uuid)', pg_temp.ep(), c));
  r3 := pg_temp.api(pg_temp.dev('OUT1'), format('select set_not_chalak_outer(938, %s)', pg_temp.ep() - 1));
  r4 := pg_temp.api(pg_temp.dev('OUT1'), format('select set_not_chalak_outer(1000, %s)', pg_temp.ep()));
  ok := pg_temp.ok(r) and (pg_temp.ar(938)).not_chalak_outer and (r2 ->> 'replayed')::boolean
        and r3 ->> 'error' = 'stale_board' and r4 ->> 'error' = 'bad_id';
  perform pg_temp.rec('rabbinate send by an outer station: allowed (command id replay, stale day, bad id)', ok,
    concat_ws(' | ', left(r::text, 40), left(r2::text, 60), r3::text, r4::text));
  -- then only kosher / treif — for every kind of "not chalak" animal
  r  := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(938, 'outer', 'glatt', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(941, 'outer', 'rabChalak', '', ''));
  r3 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(942, 'outer', 'beit', '', ''));
  r4 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(938, 'outer', 'kosher', '', ''));
  r5 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(938, jsonb_build_object('outer_status', 'mk', 'outer_time', (pg_temp.ar(938)).outer_time + 5)));
  ok := r ->> 'error' = 'bad_value' and r2 ->> 'error' = 'bad_value' and r3 ->> 'error' = 'bad_value'
        and pg_temp.claimed(r4) and r5 ->> 'error' = 'invalid_value' and (pg_temp.ar(938)).outer_status = 'kosher';
  r := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(942, 'outer', 'treif', '', ''));
  ok := ok and pg_temp.claimed(r);
  -- after the ruling it can't be sent any more
  r := pg_temp.api(pg_temp.dev('OUT1'), format('select set_not_chalak_outer(939, %s)', pg_temp.ep()));
  perform pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(940, 'outer', 'glatt', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT1'), format('select set_not_chalak_outer(940, %s)', pg_temp.ep()));
  ok := ok and pg_temp.ok(r) and r2 ->> 'error' = 'already_ruled';
  perform pg_temp.rec('a "not chalak" animal (slaughter / inner / outer) can only be ruled kosher or treif; ruled → can''t be sent', ok,
    concat_ws(' | ', left(r::text, 40), r2 ->> 'error', r5 ->> 'error'));
end $$;
$gt39$;
    v_step := 'identity chaos: old key after a replacement, fake actor / role';
    execute $gt40$
-- ── identity chaos: old key after a replacement, fake actor / role ──────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; v_code text := lpad((floor(random() * 900000) + 100000)::text, 6, '0'); ok boolean; v_repl uuid;
begin
  -- OUT1 takes outer slot 0 for this test (a real device there is set aside — rolled back at the end)
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = null, assigned_index = null
   where assigned_role = 'outer' and assigned_index = 0 and device_status = 'active' and id not like 'gtselftest\_%';
  update devices_pilot set assigned_index = 0 where id = pg_temp.devid('OUT1');
  perform set_config('app.device_admin', '', true);
  insert into device_pairing (code, device_id, device_name, secret_hash) values (v_code, pg_temp.devid('NEW'), 'selftest new', 'x');
  r2 := pg_temp.api('{}', format('select device_pair(%L, %L, ''outer'', 0, false, null)', pg_temp.v('mgr'), v_code));
  r := pg_temp.api('{}', format('select device_pair(%L, %L, ''outer'', 0, true, null, ''selftest broken screen'')', pg_temp.v('mgr'), v_code));
  perform pg_temp.rec('pairing into a taken slot without replace: slot_taken', r2 ->> 'error' = 'slot_taken', r2::text);
  v_repl := (r ->> 'replacement_id')::uuid;
  r2 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(944, 'outer', 'glatt', '', pg_temp.devid('OUT1')));
  r3 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_push(921, jsonb_build_object('outer_status', 'treif', 'outer_time', (pg_temp.ar(921)).outer_time + 9)));
  ok := pg_temp.ok(r) and r2 ->> 'error' = 'device_not_paired' and r3 ->> 'error' = 'device_not_paired'
        and (pg_temp.ar(944)).outer_status is null
        and (select count(*) from device_lifecycle_events where replacement_id = v_repl) >= 3
        and exists (select 1 from device_lifecycle_events where replacement_id = v_repl and device_id = pg_temp.devid('OUT1') and action = 'UNASSIGNED')
        and exists (select 1 from device_lifecycle_events where replacement_id = v_repl and device_id = pg_temp.devid('OUT1') and action = 'KEY_REVOKED')
        and exists (select 1 from device_lifecycle_events where replacement_id = v_repl and device_id = pg_temp.devid('NEW') and action = 'ASSIGNED'
                                                               and actor = 'selftest leader');
  perform pg_temp.rec('replacement: the old key is dead; old + new device events share one replacement_id', ok,
    concat_ws(' | ', left(r::text, 120), r2::text, r3::text));
  -- the pairing token of the new device works in the replaced slot
  r := pg_temp.api(jsonb_build_object('x-device-token', (select token_plain from device_pairing where code = v_code)), 'select device_whoami()');
  perform pg_temp.rec('device_pair with p_replace still works (new device holds the slot)',
    r ->> 'device_id' = pg_temp.devid('NEW') and r ->> 'role' = 'outer', r::text);
  -- two active devices on one slot are impossible
  begin
    perform set_config('app.device_admin', 'on', true);
    update devices_pilot set assigned_role = 'inner', assigned_index = 90 where id = pg_temp.devid('IN2');
    ok := false;
  exception when unique_violation then ok := true;
  end;
  perform set_config('app.device_admin', '', true);
  perform pg_temp.rec('one device per station slot (unique index)', ok);
  -- an event names the server's device and worker, whatever the tablet wrote
  r := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_ev(jsonb_build_object('event_id', gen_random_uuid(), 'stage', 'slaughter', 'action', 'slaughtered',
          'animal_no', 945, 'payload', jsonb_build_object('actor', 'Chief Rabbi'), 'actor', 'Chief Rabbi', 'device_id', pg_temp.devid('OUT2'),
          'occurred_at', now()::text)));
  ok := pg_temp.ok(r) and exists (select 1 from events_pilot where event_id = (r ->> 'event_id')::uuid
                                   and device_id = pg_temp.devid('SL1') and actor = 'שוחט' and payload ->> 'actor' = 'שוחט');
  r2 := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_ev(jsonb_build_object('event_id', r ->> 'event_id', 'stage', 'slaughter', 'action', 'slaughtered',
          'occurred_at', now()::text)));
  r3 := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_ev('{"stage":"slaughter","action":"x"}'::jsonb));
  ok := ok and pg_temp.ok(r2) and (r2 ->> 'duplicate')::boolean and r3 ->> 'error' = 'bad_event';
  perform pg_temp.rec('event_append: device + worker from the server, duplicate event id = ok, bad event refused', ok,
    concat_ws(' | ', left(r::text, 80), r2::text, r3::text));
end $$;
$gt40$;
    v_step := 'reads';
    execute $gt41$
-- ── reads ────────────────────────────────────────────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; r6 jsonb; ok boolean;
begin
  r  := pg_temp.api(pg_temp.dev('SL1'), 'select jsonb_build_object(''n'', count(*), ''own'', count(*) filter (where id = ' || quote_literal(pg_temp.devid('SL1')) || ')) from devices_pilot');
  r2 := pg_temp.api(pg_temp.mgr(), 'select to_jsonb(count(*)) from devices_pilot');
  r3 := pg_temp.api(pg_temp.dev('SL1'), 'select to_jsonb(count(*)) from events_pilot');
  r4 := pg_temp.api(pg_temp.mgr(), 'select to_jsonb(count(*)) from events_pilot');
  r5 := pg_temp.api(pg_temp.mgr('maker'), 'select to_jsonb(count(*)) from events_pilot');
  update plant_state set value = (now() + interval '1 hour')::text where key = 'supportAccessUntil';
  r6 := pg_temp.api(pg_temp.mgr('maker'), 'select to_jsonb(count(*)) from events_pilot');
  update plant_state set value = (now() - interval '1 minute')::text where key = 'supportAccessUntil';
  ok := (r ->> 'n')::int = 1 and (r ->> 'own')::int = 1 and (r2 #>> '{}')::int >= 15
        and (r3 #>> '{}')::int = 0 and (r4 #>> '{}')::int > 0 and (r5 #>> '{}')::int = 0 and (r6 #>> '{}')::int > 0;
  perform pg_temp.rec('reads: a station sees only its own device row and no events; team leader all; manufacturer only with support access',
    ok, concat_ws(' | ', r::text, r2::text, r3::text, r4::text, r5::text, r6::text));
  r  := pg_temp.api3(pg_temp.mgr('owner'), jsonb_build_object('role', 'authenticated', 'sub', '11111111-1111-1111-1111-111111111111'),   -- (bound above)
                     'select jsonb_build_object(''d'', (select count(*) from devices_pilot), ''e'', (select count(*) from events_pilot), ''l'', (select count(*) from device_lifecycle_events))');
  r2 := pg_temp.api(pg_temp.dev('IN1'), 'select to_jsonb(count(*)) from device_lifecycle_events');
  r3 := pg_temp.api(pg_temp.dev('IN1'), 'select to_jsonb(count(*)) from animals_pilot where id between 900 and 999');
  ok := (r ->> 'd')::int >= 15 and (r ->> 'e')::int > 0 and (r ->> 'l')::int > 0 and (r2 #>> '{}')::int = 0 and (r3 #>> '{}')::int = 100;
  perform pg_temp.rec('reads: owner sees devices / events / device log; a station still sees the whole board', ok,
    concat_ws(' | ', r::text, r2::text, r3::text));
  -- live updates (no request headers, only the app session)
  r  := pg_temp.rt(jsonb_build_object('role', 'authenticated', 'sub', pg_temp.v('uid_IN1')),
                   'select jsonb_build_object(''n'', count(*), ''own'', count(*) filter (where id = ' || quote_literal(pg_temp.devid('IN1')) || ')) from devices_pilot');
  r2 := pg_temp.rt(jsonb_build_object('role', 'anon'), 'select to_jsonb(count(*)) from devices_pilot');
  r3 := pg_temp.rt(jsonb_build_object('role', 'authenticated', 'sub', pg_temp.v('uid_IN1')), 'select to_jsonb(count(*)) from events_pilot');
  ok := (r ->> 'n')::int = 1 and (r ->> 'own')::int = 1 and (r2 #>> '{}')::int = 0 and (r3 #>> '{}')::int = 0;
  perform pg_temp.rec('live updates: a station''s app session sees only its own device row; anonymous nothing', ok,
    concat_ws(' | ', r::text, r2::text, r3::text));
  -- legacy multi-plant tables
  r := pg_temp.api(pg_temp.dev('SL1'), 'select to_jsonb(count(*)) from plants');
  r2 := case when to_regclass('public.profiles') is not null then pg_temp.api(pg_temp.dev('SL1'), 'select to_jsonb(count(*)) from profiles') else '{"sqlstate":"42501"}' end;
  r3 := case when to_regclass('public.animals') is not null then pg_temp.api(pg_temp.dev('SL1'), 'select to_jsonb(count(*)) from animals') else '{"sqlstate":"42501"}' end;
  perform pg_temp.rec('legacy tables: no access (plants: an empty answer for the start-up probe)',
    (r #>> '{}')::int = 0 and r2 ->> 'sqlstate' = '42501' and r3 ->> 'sqlstate' = '42501', concat_ws(' | ', r::text, r2::text, r3::text));
end $$;
$gt41$;
    v_step := 'settings: value shapes';
    execute $gt42$
-- ── settings: value shapes ───────────────────────────────────────────────────
do $$
declare r jsonb; ok boolean := true; det text := ''; t text[];
begin
  for t in select * from (values
      (array['autoResetTime', '"25:61"']), (array['autoResetTime', '7']), (array['plantTimezone', '"Mars/Olympus"']),
      (array['beepSeconds', '"loud"']), (array['beepSeconds', '99999']), (array['dailyTarget', '-4']),
      (array['archiveDays', '2.5']), (array['notChalakEnabled', '"yes"']), (array['activeLangs', '["he","fr"]']),
      (array['loginModeByRole', '{"inspector":"face-id"}']), (array['users', '[{"role":"inspector"}]']),
      (array['users', '"moshe"']), (array['dailyIntake', '[{"farm":"A","type":"B","qty":5000}]']),
      (array['dailyIntake', '[3]']), (array['customStatuses', '[{"he":"x"}]']), (array['lang', '"fr"']),
      (array['legStickerCount', 'true']), (array['headStickerCount', '5000'])) x(a) loop
    r := pg_temp.api(pg_temp.mgr(), format('select push_settings(%L::jsonb, ''x'', %L)', jsonb_build_object(t[1], t[2]::jsonb), pg_temp.v('mgr')));
    ok := ok and r ->> 'error' = 'bad_settings' and r ->> 'key' = t[1];
    det := det || t[1] || '=' || t[2] || '→' || coalesce(r ->> 'error', 'accepted') || '; ';
  end loop;
  perform pg_temp.rec('push_settings rejects wrong value shapes (bad_settings + key)', ok, det);
  -- the shapes the app really writes still go through
  r := pg_temp.api(pg_temp.mgr(), format('select push_settings(%L::jsonb, ''x'', %L)', jsonb_build_object(
         'autoResetTime', '04:30', 'plantTimezone', 'Asia/Jerusalem', 'beepSeconds', 25, 'beepVolume', 70, 'beepFreq', 880,
         'beepType', 'square', 'legStickerCount', 2, 'numInspectors', 2, 'dailyTarget', 120, 'archiveDays', 30,
         'activeLangs', jsonb_build_array('he', 'en', 'es'), 'loginMode', 'code',
         'loginModeByRole', jsonb_build_object('slaughter', 'none', 'inner', 'code', 'outer', 'code', 'legs', 'name'),
         'screenConfig', '1in1out', 'notChalakEnabled', true, 'esophagusEnabled', false, 'legsMode', true,
         'users', (select coalesce(settings -> 'users', '[]'::jsonb) from settings_pilot where id = 1)
                  || jsonb_build_array(jsonb_build_object('name', 'Selftest New', 'role', 'רגלים'),
                                       jsonb_build_object('name', 'Selftest Hash', 'role', 'inner', 'codeHash', repeat('a', 64), 'hv', 2)),
         'dailyIntake', jsonb_build_array(jsonb_build_object('farm', 'Farm A', 'type', 'Bull', 'qty', 40)),
         'customStatuses', jsonb_build_array(jsonb_build_object('key', 'custom_1727000000000', 'he', 'x', 'en', 'x', 'es', 'x', 'color', '#FF6B35', 'kosher', false)),
         'disabledStatuses', jsonb_build_array('mk'), 'statusColorOverrides', jsonb_build_object('glatt', '#00ff00'),
         'weightMethods', jsonb_build_object('qr', false, 'barcode', true, 'ocr', true),
         'archiveSettings', jsonb_build_object('slaughter', true, 'lungs', false, 'log', true),
         'farmNames', jsonb_build_array('Farm A'), 'cattleTypes', jsonb_build_array('Bull'), 'dailyIntakeNote', null),
       pg_temp.v('mgr')));
  perform pg_temp.rec('push_settings accepts the value shapes the app writes', pg_temp.ok(r), r::text);
  r := pg_temp.api(pg_temp.dev('OUT2'), 'select push_settings(''{"problemReports":[{"id":"st1","text":"x"}],"reprintLog":[{"id":"r1"}]}''::jsonb, ''x'')');
  perform pg_temp.rec('a station''s own keys (problem reports / reprint log) still go through', pg_temp.ok(r), r::text);
end $$;
$gt42$;
    v_step := 'audit: device lifecycle (never swallowed), manufacturer actions';
    execute $gt43$
-- ── audit: device lifecycle (never swallowed), manufacturer actions ─────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean; n0 bigint;
begin
  n0 := (select count(*) from device_lifecycle_events);
  r  := pg_temp.api('{}', format('select device_manage(%L, %L, ''rename'', ''Selftest renamed'')', pg_temp.v('mgr'), pg_temp.devid('LEGS')));
  r2 := pg_temp.api('{}', format('select device_manage(%L, %L, ''retire'', ''selftest'')', pg_temp.v('mgr'), pg_temp.devid('DISP')));
  r3 := pg_temp.api('{}', format('select device_manage(%L, %L, ''reactivate'', ''selftest'')', pg_temp.v('mgr'), pg_temp.devid('DISP')));
  r4 := pg_temp.api('{}', format('select device_unpair(%L, %L, ''selftest'')', pg_temp.v('mgr'), pg_temp.devid('ESO2')));
  ok := pg_temp.ok(r) and pg_temp.ok(r2) and pg_temp.ok(r3) and pg_temp.ok(r4)
        and exists (select 1 from device_lifecycle_events where device_id = pg_temp.devid('LEGS') and action = 'RENAMED' and actor = 'selftest leader')
        and exists (select 1 from device_lifecycle_events where device_id = pg_temp.devid('DISP') and action = 'DEVICE_RETIRED')
        and exists (select 1 from device_lifecycle_events where device_id = pg_temp.devid('DISP') and action = 'KEY_REVOKED')
        and exists (select 1 from device_lifecycle_events where device_id = pg_temp.devid('DISP') and action = 'DEVICE_REACTIVATED')
        and exists (select 1 from device_lifecycle_events where device_id = pg_temp.devid('ESO2') and action = 'UNASSIGNED')
        and exists (select 1 from device_lifecycle_events where device_id = pg_temp.devid('ESO2') and action = 'KEY_REVOKED');
  perform pg_temp.rec('device lifecycle audited: rename / retire / reactivate / unpair / key revoke (with who)', ok,
    concat_ws(' | ', r::text, r2::text, r3::text, r4::text));
  -- if the audit row can't be written, the operation fails (nothing changes)
  create function pg_temp.st_audit_down() returns trigger language plpgsql as $f$ begin raise exception 'audit down'; end $f$;
  create trigger st_audit_down before insert on device_lifecycle_events for each row execute function pg_temp.st_audit_down();
  r  := pg_temp.api('{}', format('select device_unpair(%L, %L, ''selftest'')', pg_temp.v('mgr'), pg_temp.devid('SL2')));
  r2 := pg_temp.api('{}', format('select device_manage(%L, %L, ''rename'', ''X'')', pg_temp.v('mgr'), pg_temp.devid('SL2')));
  drop trigger st_audit_down on device_lifecycle_events;
  ok := pg_temp.exc(r) like '%audit down%' and pg_temp.exc(r2) like '%audit down%'
        and (select assigned_role from devices_pilot where id = pg_temp.devid('SL2')) = 'slaughter'
        and not (select revoked from device_credentials where device_id = pg_temp.devid('SL2'))
        and (select device_name from devices_pilot where id = pg_temp.devid('SL2')) = 'selftest SL2';
  perform pg_temp.rec('device audit write fails → the operation fails (unpair / rename undone)', ok, concat_ws(' | ', r::text, r2::text));
  -- manufacturer actions
  update plant_state set value = (now() + interval '1 hour')::text where key = 'supportAccessUntil';
  r  := pg_temp.api('{}', format('select manufacturer_set_billing(%L, true, 12.5, ''$'', ''selftest'')', pg_temp.v('maker')));
  r2 := pg_temp.api('{}', format('select support_force_reload(%L, ''selftest'')', pg_temp.v('maker')));
  r3 := pg_temp.api('{}', format('select support_diagnostics(%L)', pg_temp.v('maker')));
  r4 := pg_temp.api(pg_temp.mgr('maker'), format('select push_settings(''{"beepSeconds":30}''::jsonb, ''x'', %L, ''selftest'')', pg_temp.v('maker')));
  update plant_state set value = (now() - interval '1 minute')::text where key = 'supportAccessUntil';
  ok := pg_temp.ok(r) and pg_temp.ok(r2) and pg_temp.ok(r3) and pg_temp.ok(r4)
        and (select count(distinct action) from admin_audit where who = 'selftest maker' and role = 'manufacturer'
                                                          and action in ('billing', 'force_reload', 'diagnostics', 'settings')) = 4;
  r := pg_temp.api('{}', format('select support_access_set(%L, 2, ''selftest'')', pg_temp.v('mgr')));
  ok := ok and exists (select 1 from admin_audit where who = 'selftest leader' and action = 'support_access_opened');
  perform pg_temp.rec('manufacturer / support actions write an audit row (who, action, target, time)', ok,
    concat_ws(' | ', left(r2::text, 40), left(r3::text, 40), left(r4::text, 40)));
  -- step 46: the billing currency — ₪ $ € £ or a 3-letter code (not tied to the language)
  update plant_state set value = (now() + interval '1 hour')::text where key = 'supportAccessUntil';
  r  := pg_temp.api('{}', format('select manufacturer_set_billing(%L, true, 3.2, ''chf'', ''selftest'')', pg_temp.v('maker')));
  r2 := pg_temp.api('{}', format('select manufacturer_set_billing(%L, true, 3.2, ''£'', ''selftest'')', pg_temp.v('maker')));
  r3 := pg_temp.api('{}', format('select manufacturer_set_billing(%L, true, 3.2, ''X1'', ''selftest'')', pg_temp.v('maker')));
  r4 := pg_temp.api('{}', format('select manufacturer_set_billing(%L, true, 3.2, ''USD'', ''selftest'')', pg_temp.v('mgr')));
  update plant_state set value = (now() - interval '1 minute')::text where key = 'supportAccessUntil';
  perform pg_temp.rec('step 46 billing currency: ₪ $ € £ or a 3-letter code; anything else refused; only the manufacturer',
    r #>> '{billing,currency}' = 'CHF' and r2 #>> '{billing,currency}' = '£' and r3 ->> 'error' = 'bad_currency' and not pg_temp.ok(r4),
    concat_ws(' | ', r::text, r2::text, r3::text, r4::text));
end $$;
$gt43$;
    v_step := 'brakes';
    execute $gt44$
-- ── brakes ───────────────────────────────────────────────────────────────────
do $$
declare r jsonb; r2 jsonb; i int; ok boolean; v_last jsonb;
begin
  -- a tablet that keeps trying refused corrections is braked (first rulings still go)
  perform pg_temp.api(pg_temp.dev('BRK'), pg_temp.q_claim(946, 'slaughter', 'slaughtered', '', ''));
  perform pg_temp.api(pg_temp.dev('BRK'), pg_temp.q_claim(947, 'slaughter', 'slaughtered', '', ''));
  for i in 1 .. 10 loop
    v_last := pg_temp.api(pg_temp.dev('BRK'), pg_temp.q_push(946, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(946)).slaughter_time + i)));
  end loop;
  r  := pg_temp.api(pg_temp.dev('BRK'), pg_temp.q_push(946, jsonb_build_object('slaughter', 'shot', 'slaughter_time', (pg_temp.ar(946)).slaughter_time + 99)));
  r2 := pg_temp.api(pg_temp.dev('BRK'), pg_temp.q_claim(948, 'slaughter', 'slaughtered', '', ''));
  ok := v_last ->> 'error' = 'moved_on' and r ->> 'error' = 'rate_limited' and (r ->> 'retry_after')::int > 0 and pg_temp.claimed(r2);
  perform pg_temp.rec('refused corrections: logged and braked per device (10 in 10 min → rate_limited)', ok,
    concat_ws(' | ', v_last ->> 'error', r::text, r2 ->> 'claimed'));
  -- manufacturer logins: at most 6 an hour
  for i in 1 .. 6 loop
    r := pg_temp.api('{}', format('select manager_login(%L)', pg_temp.v('maker_code')));
  end loop;
  r2 := pg_temp.api('{}', format('select manager_login(%L)', pg_temp.v('maker_code')));
  ok := pg_temp.ok(r) and r2 ->> 'reason' = 'locked'
        and (select count(*) from admin_audit where who = 'selftest maker' and action = 'login') = 6;
  r := pg_temp.api('{}', format('select manager_login(%L)', pg_temp.v('mgr_code')));
  ok := ok and pg_temp.ok(r);
  perform pg_temp.rec('manufacturer login: braked (6 per hour) and audited; team-leader login unaffected', ok,
    concat_ws(' | ', r2::text, left(r::text, 40)));
end $$;
$gt44$;
    v_step := 'value rules';
    execute $gt45$
-- ── value rules ──────────────────────────────────────────────────────────────
do $$
declare r jsonb; ok boolean := true; det text := ''; t text[];
begin
  for t in select * from (values
      (array['SL1',    '{"slaughter":"bogus","slaughter_time":1}']),
      (array['IN1',    '{"inner_status":"maybe","inner_time":1}']),
      (array['OUT2',   '{"outer_status":"almost_kosher","outer_time":1}']),
      (array['IN1',    '{"maw":"sort-of"}']),
      (array['STAMPS', '{"weight_right":5000}']),
      (array['STAMPS', '{"weight_left":-3}']),
      (array['PARTS',  '{"parts_printed_as":"whatever"}'])) x(a) loop
    r := pg_temp.api(pg_temp.dev(t[1]), pg_temp.q_push(949, t[2]::jsonb));
    ok := ok and r ->> 'error' = 'invalid_value';
    det := det || t[2] || '→' || coalesce(r ->> 'error', 'accepted') || '; ';
  end loop;
  for t in select * from (values
      (array['SL1',  'slaughter', 'kosherish', 'bad_value']),
      (array['IN1',  'inner',     'maybe',     'bad_value']),
      (array['OUT2', 'outer',     'bogus',     'bad_value']),
      (array['ESO1', 'eso',       'fine',      'bad_value']),
      (array['SL1',  'nonsense',  'x',         'bad_stage'])) x(a) loop
    r := pg_temp.api(pg_temp.dev(t[1]), pg_temp.q_claim(950, t[2], t[3], '', pg_temp.devid(t[1])));
    ok := ok and r ->> 'error' = t[4];
    det := det || t[2] || '=' || t[3] || '→' || coalesce(r ->> 'error', r::text) || '; ';
  end loop;
  r := pg_temp.api(pg_temp.dev('ESO1'), format('select eso_change(950, ''maybe'', ''x'', %s)', pg_temp.ep()));
  ok := ok and r ->> 'error' = 'bad_result';
  r := pg_temp.api('{}', format('select device_pair(%L, ''000000'', ''boss'', 0, true, null)', pg_temp.v('mgr')));
  ok := ok and r ->> 'error' = 'bad_role';
  r := pg_temp.api(pg_temp.dev('IN1'), 'select worker_login(''astronaut'', ''1'')');
  ok := ok and r ->> 'error' = 'bad_role';
  begin
    update devices_pilot set assigned_role = 'boss' where id = pg_temp.devid('LEGS');
    ok := false; det := det || 'device role boss accepted; ';
  exception when check_violation then null;
  end;
  perform pg_temp.prep(950, 'inner');
  r := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(950, 'outer', 'custom_1727000000000', '', ''));
  ok := ok and pg_temp.claimed(r);
  perform pg_temp.rec('invalid slaughter / inner / outer / eso / role / weight values rejected', ok, det);
end $$;
$gt45$;
    v_step := 'workers: login, session, the name on the ruling';
    execute $gt46$
-- ── workers: login, session, the name on the ruling ──────────────────────────
do $$
declare r jsonb; r2 jsonb; tok text; h jsonb; i int;
begin
  perform pg_temp.rec('worker codes are stored only as hashes',
    not exists (select 1 from settings_pilot s, jsonb_array_elements(s.settings -> 'users') u where u ? 'code')
    and exists (select 1 from settings_pilot s, jsonb_array_elements(s.settings -> 'users') u
                 where u ->> 'name' = 'Selftest Inspector' and u ->> 'codeHash' = encode(digest('gt-worker:739104', 'sha256'), 'hex')));
  r := pg_temp.api(pg_temp.mgr(),
         format('select push_settings(%L::jsonb, ''leader'', %L)',
                (select jsonb_build_object('users', (s.settings -> 'users') || jsonb_build_array(jsonb_build_object('name', 'Selftest Supervisor', 'role', 'legs', 'code', '81818')))
                   from settings_pilot s where id = 1),
                pg_temp.v('mgr')));
  perform pg_temp.rec('push_settings stores a worker code hashed',
    pg_temp.ok(r) and exists (select 1 from settings_pilot s, jsonb_array_elements(s.settings -> 'users') u
                               where u ->> 'name' = 'Selftest Supervisor' and not (u ? 'code')
                                 and u ->> 'codeHash' = encode(digest('gt-worker:81818', 'sha256'), 'hex')), r::text);
  r := pg_temp.api(pg_temp.dev('IN1'), 'select worker_login(''inner'', ''000000'')');
  perform pg_temp.rec('worker login: wrong code rejected', r ->> 'error' = 'code_invalid' and r ->> 'token' is null, r::text);
  r := pg_temp.api(pg_temp.dev('SL1'), 'select worker_login(''inner'', ''739104'')');
  r2 := pg_temp.api(jsonb_build_object('x-device-id', pg_temp.devid('IN1')), 'select worker_login(''inner'', ''739104'')');
  perform pg_temp.rec('worker login: wrong station / unpaired tablet rejected',
    r ->> 'error' = 'wrong_station' and r2 ->> 'error' = 'device_not_paired', r::text || ' | ' || r2::text);
  r2 := pg_temp.api(pg_temp.mgr(), 'select worker_login(''inner'', ''739104'')');
  perform pg_temp.rec('worker login through a team-leader session: only in test mode', r2 ->> 'error' = 'device_not_paired', r2::text);
  r := pg_temp.api(pg_temp.dev('IN1'), 'select worker_login(''inner'', ''739104'')');
  tok := r ->> 'token';
  perform pg_temp.rec('worker login: right code gives a session',
    pg_temp.ok(r) and tok is not null and r ->> 'name' = 'Selftest Inspector'
    and exists (select 1 from worker_sessions where token_hash = encode(digest(tok, 'sha256'), 'hex') and device_id = pg_temp.devid('IN1')),
    left(r::text, 200));
  h := pg_temp.dev('IN1') || jsonb_build_object('x-worker-token', tok);
  r := pg_temp.api(h, 'select worker_session_check()');
  perform pg_temp.prep(951, 'slaughter'); perform pg_temp.prep(952, 'slaughter');
  perform pg_temp.prep(953, 'slaughter'); perform pg_temp.prep(954, 'slaughter');
  perform pg_temp.api(h, pg_temp.q_claim(951, 'inner_start', 'in_progress', '', ''));
  perform pg_temp.api(h, pg_temp.q_claim(951, 'inner', 'confirmed', 'בודק פנים', ''));
  perform pg_temp.api(h, pg_temp.q_claim(952, 'inner', 'confirmed', 'Somebody Else', ''));
  perform pg_temp.rec('ruling records the verified worker name (another name → marked (?))',
    (pg_temp.ar(951)).inner_by = 'Selftest Inspector' and r ->> 'name' = 'Selftest Inspector'
    and (pg_temp.ar(952)).inner_by = 'Somebody Else (?)',
    concat_ws(' | ', (pg_temp.ar(951)).inner_by, (pg_temp.ar(952)).inner_by, r::text));
  h := pg_temp.dev('IN2') || jsonb_build_object('x-worker-token', tok);
  perform pg_temp.api(h, pg_temp.q_claim(953, 'inner', 'confirmed', 'Selftest Inspector', ''));
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(954, 'inner', 'confirmed', 'Moshe', ''));
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(955, 'slaughter', 'slaughtered', 'Claimed Name', ''));
  perform pg_temp.rec('unverified names are marked (?) / default name when no login',
    (pg_temp.ar(953)).inner_by = 'Selftest Inspector (?)' and (pg_temp.ar(954)).inner_by = 'Moshe (?)'
    and (pg_temp.ar(955)).slaughtered_by = 'שוחט',
    concat_ws(' | ', (pg_temp.ar(953)).inner_by, (pg_temp.ar(954)).inner_by, (pg_temp.ar(955)).slaughtered_by));
  perform pg_temp.api('{}', format('select worker_logout(%L)', tok));
  r := pg_temp.api(pg_temp.dev('IN1') || jsonb_build_object('x-worker-token', tok), 'select worker_session_check()');
  perform pg_temp.rec('worker logout ends the session', r ->> 'error' = 'session_invalid', r::text);
  r := pg_temp.api(pg_temp.dev('IN2'), 'select worker_login(''inner'', ''739104'')');
  tok := r ->> 'token';
  perform pg_temp.api('{}', format('select device_unpair(%L, %L, ''selftest'')', pg_temp.v('mgr'), pg_temp.devid('IN2')));
  perform pg_temp.rec('unpairing a tablet ends its worker sessions',
    tok is not null and not exists (select 1 from worker_sessions where token_hash = encode(digest(tok, 'sha256'), 'hex') and not revoked));
  for i in 1 .. 8 loop
    r := pg_temp.api(pg_temp.dev('OUT2'), format('select worker_login(''outer'', %L)', 'wrong' || i));
  end loop;
  r := pg_temp.api(pg_temp.dev('OUT2'), 'select worker_login(''outer'', ''739104'')');
  perform pg_temp.rec('worker login: guessing is rate-limited', r ->> 'error' = 'rate_limited', r::text);
end $$;
$gt46$;
    v_step := 'event log chain: changed / deleted / reordered events are detected';
    execute $gt47$
-- ── event log chain: changed / deleted / reordered events are detected ──────
do $$
declare r jsonb; v0 jsonb; v1 jsonb; v2 jsonb; v3 jsonb; p1 bigint; p2 bigint; i int;
begin
  for i in 1 .. 3 loop
    r := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_ev(jsonb_build_object('event_id', gen_random_uuid(), 'animal_no', 956, 'stage', 'slaughter',
            'action', 'selftest', 'payload', jsonb_build_object('n', i), 'actor', 'x', 'occurred_at', now()::text)));
    if i = 1 then p1 := (r ->> 'chain_pos')::bigint; end if;
    if i = 2 then p2 := (r ->> 'chain_pos')::bigint; end if;
  end loop;
  v0 := verify_event_chain();
  perform pg_temp.rec('event chain intact before the test', (v0 ->> 'ok')::boolean and p1 is not null, v0::text);
  r := pg_temp.api(pg_temp.dev('SL1'), format('with u as (update events_pilot set payload = ''{}'' where chain_pos = %s returning 1) select jsonb_build_object(''rows'', count(*)) from u', p1));
  perform pg_temp.rec('event log: a tablet cannot change an event', pg_temp.exc(r) like 'GT:APPEND_ONLY%' or pg_temp.exc(r) like '%permission denied%', r::text);
  r := pg_temp.api(pg_temp.dev('SL1'), 'select verify_event_chain()');
  perform pg_temp.rec('event log: a tablet cannot run the full chain check', r ->> 'error' = 'unauthorized', r::text);
  begin
    perform pg_temp.st_tamper();
    update events_pilot set payload = '{"n":99}' where chain_pos = p1;
    v1 := verify_event_chain();
    raise exception 'st_undo';
  exception when others then if sqlerrm <> 'st_undo' then v1 := jsonb_build_object('error', sqlerrm); end if;
  end;
  begin
    perform pg_temp.st_tamper();
    delete from events_pilot where chain_pos = p2;
    v2 := verify_event_chain();
    raise exception 'st_undo';
  exception when others then if sqlerrm <> 'st_undo' then v2 := jsonb_build_object('error', sqlerrm); end if;
  end;
  begin
    perform pg_temp.st_tamper();
    update events_pilot set chain_pos = -1 where chain_pos = p1;
    update events_pilot set chain_pos = p1 where chain_pos = p2;
    update events_pilot set chain_pos = p2 where chain_pos = -1;
    v3 := verify_event_chain();
    raise exception 'st_undo';
  exception when others then if sqlerrm <> 'st_undo' then v3 := jsonb_build_object('error', sqlerrm); end if;
  end;
  perform pg_temp.rec('event chain: a modified event is detected', not coalesce((v1 ->> 'ok')::boolean, true) and v1 ->> 'reason' = 'hash-mismatch', v1::text);
  perform pg_temp.rec('event chain: a deleted event is detected', not coalesce((v2 ->> 'ok')::boolean, true) and v2 ? 'brokenAt', v2::text);
  perform pg_temp.rec('event chain: reordered events are detected', not coalesce((v3 ->> 'ok')::boolean, true) and v3 ? 'brokenAt', v3::text);
end $$;
$gt47$;
    v_step := 'archive: "not chalak" inner / outer apart';
    execute $gt48$
-- ── archive: "not chalak" inner / outer apart ────────────────────────────────
do $$
declare r jsonb; v_id bigint; x jsonb;
begin
  insert into daily_board_archive (business_date, reason, animals_count, board)
  values (date '1999-01-01', 'selftest', 3, jsonb_build_array(
    jsonb_build_object('id', 1, 'slaughter', 'slaughtered', 'not_chalak_inner', true, 'not_chalak_outer', false),
    jsonb_build_object('id', 2, 'slaughter', 'slaughtered', 'not_chalak_inner', false, 'not_chalak_outer', true),
    jsonb_build_object('id', 3, 'slaughter', 'slaughtered')))
  returning id into v_id;
  r := pg_temp.api('{}', format('select archive_days(%L, date ''1999-01-01'', date ''1999-01-01'')', pg_temp.v('mgr')));
  x := r -> 'days' -> 0 -> 'animals';
  perform pg_temp.rec('archive_days: nci / nco apart, nc = either',
    (x -> 0 ->> 'nci')::boolean and not (x -> 0 ->> 'nco')::boolean and (x -> 0 ->> 'nc')::boolean
    and not (x -> 1 ->> 'nci')::boolean and (x -> 1 ->> 'nco')::boolean and (x -> 1 ->> 'nc')::boolean
    and not (x -> 2 ->> 'nc')::boolean, left(r::text, 300));
end $$;
$gt48$;
    v_step := 'step 45 chaos: inner takeover, then the old tablet comes back';
    execute $gt49$
-- ── step 45 chaos: inner takeover, then the old tablet comes back ────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean; c1 uuid := gen_random_uuid(); cq uuid := gen_random_uuid();
        cq2 uuid := gen_random_uuid(); v_time bigint;
begin
  -- IN2 was unpaired by an earlier check: back on its station for these
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = 'inner', assigned_index = 91, paired_at = now() where id = pg_temp.devid('IN2');
  update device_credentials set revoked = false where device_id = pg_temp.devid('IN2');
  perform set_config('app.device_admin', '', true);
  perform pg_temp.prep(980, 'slaughter'); perform pg_temp.prep(981, 'slaughter');
  -- A (IN1) opens #980 with a command id; its tablet also queues a ruling (new command ids) while offline
  r := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claimc(980, 'inner_start', 'in_progress', c1));
  v_time := (pg_temp.ar(980)).inner_time;
  perform pg_temp.age_inner(980);
  r2 := pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_claim(980, 'inner_start', 'in_progress', '', ''));     -- B takes over
  -- (a) A's queued commands (made before the takeover) arrive: refused, B's check kept, refusal recorded
  r3 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(980, jsonb_build_object('inner_status', 'treif', 'inner_time', v_time + 50, 'maw', 'treif'), cq));
  r4 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claimc(980, 'inner', 'confirmed', cq2));
  ok := pg_temp.claimed(r) and pg_temp.claimed(r2) and not pg_temp.claimed(r4)
        and (pg_temp.ar(980)).inner_status = 'in_progress' and (pg_temp.ar(980)).inner_by_device = pg_temp.devid('IN2')
        and (pg_temp.ar(980)).maw is null
        and (select count(*) from events_pilot where stage = 'security' and action = 'inner_takeover_rejected'
                                                and animal_no = 981 and device_id = pg_temp.devid('IN1')) >= 2;
  perform pg_temp.rec('chaos (a): after an inner takeover, the old tablet''s queued commands (old command ids) are refused, B''s check kept', ok,
    concat_ws(' | ', r ->> 'claimed', r2 ->> 'claimed', left(r3::text, 80), left(r4::text, 80)));
  -- (b) A resends the SAME command id it used before the takeover: the stored original answer, nothing changes
  r := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claimc(980, 'inner_start', 'in_progress', c1));
  ok := pg_temp.claimed(r) and coalesce((r ->> 'replayed')::boolean, false)
        and (pg_temp.ar(980)).inner_status = 'in_progress' and (pg_temp.ar(980)).inner_by_device = pg_temp.devid('IN2');
  r2 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(980, jsonb_build_object('inner_status', 'treif', 'inner_time', v_time + 50, 'maw', 'treif'), cq));
  ok := ok and coalesce((r2 ->> 'replayed')::boolean, false) and (pg_temp.ar(980)).maw is null
        and (pg_temp.ar(980)).inner_by_device = pg_temp.devid('IN2');
  perform pg_temp.rec('chaos (b): the old tablet resending a command id it already used gets the stored answer; nothing changes', ok,
    concat_ws(' | ', left(r::text, 120), left(r2::text, 80)));
  -- for (c) / (e) after the daily reset: a takeover and an open outer lock left on the board, and the old day
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(981, 'inner_start', 'in_progress', '', ''));
  perform pg_temp.age_inner(981);
  perform pg_temp.api(pg_temp.dev('IN2'), pg_temp.q_claim(981, 'inner_start', 'in_progress', '', ''));
  perform pg_temp.api(pg_temp.dev('OUT2'), format('select outer_open(982, %s, true, ''x'')', pg_temp.ep()));
  perform pg_temp.put('c1_before_reset', c1::text);
  perform pg_temp.put('epoch_before_reset', pg_temp.ep()::text);
  perform pg_temp.put('c1_answer', r::text);
end $$;
$gt49$;
    v_step := 'step 45: test mode switches itself off after 8 hours';
    execute $gt50$
-- ── step 45: test mode switches itself off after 8 hours ─────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean;
begin
  perform pg_temp.testmode(true);
  r := pg_temp.api('{}'::jsonb, 'select server_test_mode_info()');
  ok := (r ->> 'on')::boolean and (r ->> 'remaining_s')::bigint between 28700 and 28800
        and _ts_or_null((select value from plant_state where key = 'testModeOnAt')) > now() - interval '1 minute'
        and exists (select 1 from admin_audit where action = 'test_mode_on' and target = 'plant_state.testMode');
  perform pg_temp.rec('test mode ON: switch-on time recorded + audited; info answers 8 hours left', ok, r::text);
  -- (f) switched on 9 hours ago
  update plant_state set value = (now() - interval '9 hours')::text where key = 'testModeOnAt';
  perform set_config('gt.tm_autooff', '', true);
  r  := pg_temp.api('{}'::jsonb, 'select to_jsonb(server_test_mode())');
  r2 := pg_temp.api('{}'::jsonb, 'select server_test_mode_info()');
  r3 := pg_temp.api(pg_temp.mgr(), pg_temp.q_claim(983, 'slaughter', 'slaughtered', 'leader', 'leader-browser'));
  r4 := pg_temp.api(pg_temp.mgr(), format('select set_not_chalak_outer(983, %s)', pg_temp.ep()));
  ok := r = 'false'::jsonb and not (r2 ->> 'on')::boolean and r3 ->> 'error' = 'wrong_station' and r4 ->> 'error' = 'wrong_station'
        and (pg_temp.ar(983)).slaughter is null
        and (select value from plant_state where key = 'testMode') = 'off'
        and exists (select 1 from admin_audit where action = 'test_mode_off' and detail ->> 'reason' = 'auto_expired');
  perform pg_temp.rec('chaos (f): test mode switched on 9 hours ago → off: the team leader cannot rule, server_test_mode false, flag set off + audited', ok,
    concat_ws(' | ', r::text, left(r2::text, 60), r3::text, r4::text, (select value from plant_state where key = 'testMode')));
  perform pg_temp.testmode(false);
end $$;
$gt50$;
    v_step := 'step 45: a reason is required for exceptional actions';
    execute $gt51$
-- ── step 45: a reason is required for exceptional actions ────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; r6 jsonb; ok boolean; det text;
begin
  -- replacing a device / retire / reactivate / unpair: no reason → refused, nothing changes
  r  := pg_temp.api('{}', format('select device_pair(%L, ''000000'', ''outer'', 1, true, null)', pg_temp.v('mgr')));
  r2 := pg_temp.api('{}', format('select device_pair(%L, ''000000'', ''outer'', 1, true, null, ''   '')', pg_temp.v('mgr')));
  r3 := pg_temp.api('{}', format('select device_pair(%L, ''000000'', ''outer'', 1, false, null)', pg_temp.v('mgr')));
  r4 := pg_temp.api('{}', format('select device_manage(%L, %L, ''retire'', null)', pg_temp.v('mgr'), pg_temp.devid('PARTS')));
  r5 := pg_temp.api('{}', format('select device_manage(%L, %L, ''reactivate'', '''')', pg_temp.v('mgr'), pg_temp.devid('RET')));
  r6 := pg_temp.api('{}', format('select device_unpair(%L, %L)', pg_temp.v('mgr'), pg_temp.devid('STAMPS')));
  ok := r ->> 'error' = 'reason_required' and r2 ->> 'error' = 'reason_required' and r3 ->> 'error' = 'code_invalid'
        and r4 ->> 'error' = 'reason_required' and r5 ->> 'error' = 'reason_required' and r6 ->> 'error' = 'reason_required'
        and (select device_status from devices_pilot where id = pg_temp.devid('PARTS')) = 'active'
        and (select device_status from devices_pilot where id = pg_temp.devid('RET')) = 'retired'
        and (select assigned_role from devices_pilot where id = pg_temp.devid('STAMPS')) = 'stamps'
        and not (select revoked from device_credentials where device_id = pg_temp.devid('STAMPS'));
  det := concat_ws(' | ', r::text, r2::text, r3::text, r4::text, r5::text, r6::text);
  -- rename needs no reason; the replacement reason is in the device log
  r := pg_temp.api('{}', format('select device_manage(%L, %L, ''rename'', ''Selftest parts'')', pg_temp.v('mgr'), pg_temp.devid('PARTS')));
  ok := ok and pg_temp.ok(r)
        and exists (select 1 from device_lifecycle_events where action = 'UNASSIGNED' and reason = 'replaced by pairing: selftest broken screen')
        and exists (select 1 from device_lifecycle_events where action = 'ASSIGNED' and reason = 'paired with code (replacement): selftest broken screen');
  perform pg_temp.rec('reason_required: device replace / retire / reactivate / unpair without a reason are refused (normal pairing + rename need none); the reason is logged', ok, det);
  -- support access, billing, force reload, manufacturer settings
  update plant_state set value = (now() + interval '1 hour')::text where key = 'supportAccessUntil';
  r  := pg_temp.api('{}', format('select support_access_set(%L, 4)', pg_temp.v('mgr')));
  r2 := pg_temp.api('{}', format('select manufacturer_set_billing(%L, true, 10, ''$'')', pg_temp.v('maker')));
  r3 := pg_temp.api('{}', format('select support_force_reload(%L)', pg_temp.v('maker')));
  r4 := pg_temp.api(pg_temp.mgr('maker'), format('select push_settings(''{"beepSeconds":31}''::jsonb, ''x'', %L)', pg_temp.v('maker')));
  r5 := pg_temp.api(pg_temp.mgr('maker'), format('select push_settings(''{"beepSeconds":31}''::jsonb, ''x'', %L, ''selftest: customer asked'')', pg_temp.v('maker')));
  r6 := pg_temp.api('{}', format('select support_access_set(%L, 4, ''selftest: printer fault'')', pg_temp.v('mgr')));
  ok := r ->> 'error' = 'reason_required' and r2 ->> 'error' = 'reason_required' and r3 ->> 'error' = 'reason_required'
        and r4 ->> 'error' = 'reason_required' and pg_temp.ok(r5) and pg_temp.ok(r6)
        and exists (select 1 from admin_audit where action = 'settings' and detail ->> 'reason' = 'selftest: customer asked')
        and exists (select 1 from admin_audit where action = 'support_access_opened' and detail ->> 'reason' = 'selftest: printer fault');
  det := concat_ws(' | ', r::text, r2::text, r3::text, r4::text, left(r5::text, 40), left(r6::text, 40));
  r := pg_temp.api('{}', format('select support_access_set(%L, 0)', pg_temp.v('mgr')));             -- closing: no reason needed
  ok := ok and pg_temp.ok(r);
  update plant_state set value = (now() - interval '1 minute')::text where key = 'supportAccessUntil';
  perform pg_temp.rec('reason_required: support access open / billing / force reload / manufacturer settings without a reason are refused (closing access needs none); the reason is audited', ok, det);
end $$;
$gt51$;
    v_step := 'step 45: system health for the team leader';
    execute $gt52$
-- ── step 45: system health for the team leader ───────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean; det text; n0 bigint; v_pos bigint;
begin
  delete from plant_state where key in ('lastBackupVerifiedAt', 'lastBackupFailedAt', 'lastBackupFailReason', 'plantServer');
  r  := pg_temp.api('{}', format('select system_health(%L)', pg_temp.v('mgr')));
  r2 := pg_temp.api3('{}', jsonb_build_object('role', 'authenticated', 'sub', '11111111-1111-1111-1111-111111111111'),   -- (owner bound above)
                     format('select system_health(%L)', pg_temp.v('owner')));
  r3 := pg_temp.api('{}', format('select system_health(%L)', pg_temp.v('maker')));
  r4 := pg_temp.api(pg_temp.dev('SL1'), 'select system_health(''x'')');
  ok := pg_temp.ok(r) and pg_temp.ok(r2) and r3 ->> 'error' = 'unauthorized' and r4 ->> 'error' = 'unauthorized'
        and r ? 'schemaStep' and r ? 'serverTime' and r -> 'devices' ? 'offline' and r -> 'devices' ? 'unpaired_requests'
        and r -> 'eventChain' ? 'checked' and r -> 'security' ? 'revokedDeviceWrites24h' and r -> 'security' ? 'rateLimited24h'
        and (r -> 'eventChain' ->> 'ok')::boolean
        and r -> 'info' ? 'backup_unknown' and not (r -> 'attention' ? 'backup_stale')
        and not (r -> 'attention' ? 'test_mode_on') and not (r -> 'attention' ? 'chain_broken');
  perform pg_temp.rec('system_health: team leader / owner only; all sections; no backup ever on this server = info backup_unknown (not attention)', ok,
    concat_ws(' | ', left(r::text, 300), r3::text, r4::text));
  -- backups on a plant server
  insert into plant_state (key, value) values ('plantServer', 'on');
  r := system_health(pg_temp.v('mgr'));
  insert into plant_state (key, value) values ('lastBackupVerifiedAt', now()::text);
  r2 := system_health(pg_temp.v('mgr'));
  update plant_state set value = (now() - interval '27 hours')::text where key = 'lastBackupVerifiedAt';
  r3 := system_health(pg_temp.v('mgr'));
  update plant_state set value = (now() - interval '1 hour')::text where key = 'lastBackupVerifiedAt';
  insert into plant_state (key, value) values ('lastBackupFailedAt', now()::text), ('lastBackupFailReason', 'selftest');
  r4 := system_health(pg_temp.v('mgr'));
  ok := r -> 'attention' ? 'backup_stale' and r -> 'backup' ->> 'status' = 'never'
        and not (r2 -> 'attention' ? 'backup_stale') and r2 -> 'backup' ->> 'status' = 'ok'
        and r3 -> 'attention' ? 'backup_stale' and r3 -> 'backup' ->> 'status' = 'stale'
        and r4 -> 'attention' ? 'backup_stale' and r4 -> 'backup' ->> 'status' = 'failed' and r4 ->> 'lastBackupFailReason' = 'selftest';
  perform pg_temp.rec('system_health: backup never / verified / older than 26 h / failed after the last good one', ok,
    concat_ws(' | ', r -> 'backup', r2 -> 'backup', r3 -> 'backup', r4 -> 'backup'));
  delete from plant_state where key in ('lastBackupVerifiedAt', 'lastBackupFailedAt', 'lastBackupFailReason', 'plantServer');
  -- test mode, revoked keys, a broken chain
  perform pg_temp.testmode(true);
  r := system_health(pg_temp.v('mgr'));
  perform pg_temp.testmode(false);
  n0 := (select coalesce(sum(n), 0) from revoked_device_writes);
  perform set_config('gt.revoked_noted', '', true);
  r2 := pg_temp.api(pg_temp.dev('RET'), pg_temp.q_push(984, '{"slaughter":"shot","slaughter_time":1}'));
  perform set_config('gt.revoked_noted', '', true);
  r3 := pg_temp.api(pg_temp.dev('OUT1'), pg_temp.q_claim(984, 'outer', 'glatt', '', ''));    -- OUT1's key was revoked by the replacement
  perform set_config('gt.revoked_noted', '', true);
  ok := r -> 'attention' ? 'test_mode_on' and (r -> 'testMode' ->> 'on')::boolean and r -> 'testMode' ->> 'expires_at' is not null
        and (select coalesce(sum(n), 0) from revoked_device_writes) = n0 + 2
        and (select count(*) from revoked_device_writes where device_id in (pg_temp.devid('RET'), pg_temp.devid('OUT1'))) = 2;
  r4 := system_health(pg_temp.v('mgr'));
  ok := ok and r4 -> 'attention' ? 'revoked_device_writes' and (r4 -> 'security' ->> 'revokedDeviceWrites24h')::int >= 2
        and not (r4 -> 'attention' ? 'test_mode_on');
  det := concat_ws(' | ', r -> 'attention', r2 ->> 'error', r3 ->> 'error', r4 -> 'security');
  v_pos := (select max(chain_pos) from events_pilot where server_chained);
  begin
    perform pg_temp.st_tamper();
    update events_pilot set payload = '{"n":98}' where chain_pos = v_pos;
    r := system_health(pg_temp.v('mgr'));
    raise exception 'st_undo';
  exception when others then if sqlerrm <> 'st_undo' then r := jsonb_build_object('error', sqlerrm); end if;
  end;
  ok := ok and r -> 'attention' ? 'chain_broken' and (r -> 'security' ->> 'chainBroken')::boolean
        and (r -> 'eventChain' ->> 'brokenAt')::bigint = v_pos and r -> 'eventChain' ->> 'reason' = 'hash-mismatch';
  perform pg_temp.rec('system_health: test mode on / writes with a revoked or retired key (counted) / a changed event → attention', ok,
    det || ' | ' || coalesce(r -> 'eventChain', r)::text);
end $$;
$gt52$;
    v_step := 'the daily reset (last: it empties the whole board)';
    execute $gt53$
-- ── the daily reset (last: it empties the whole board) ──────────────────────
do $$
declare r1 jsonb; r2 jsonb; e0 bigint := _board_epoch(); e1 bigint; e2 bigint; n_arch int; r jsonb; ok boolean;
        rr1 jsonb; rr2 jsonb;
begin
  n_arch := (select count(*) from daily_board_archive);
  r1 := pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  e1 := _board_epoch();
  ok := (r1 ->> 'ok')::boolean and e1 > coalesce(e0, 0)
        and not exists (select 1 from animals_pilot where slaughter is not null or inner_status is not null or outer_status is not null
                                                      or eso_checked or stamped or legs_sorted or parts_print_count > 0 or not_chalak_outer)
        and not exists (select 1 from device_stage_cursor);
  perform pg_sleep(0.01);
  r2 := pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  e2 := _board_epoch();
  ok := ok and (r2 ->> 'ok')::boolean and e2 > e1
        and (select count(*) from daily_board_archive) = n_arch + 2
        and (select animals_count from daily_board_archive order by archived_at desc, id desc limit 1) = 0;
  r := pg_temp.api(pg_temp.dev('SL1'), format('select claim_animal_stage(971, ''slaughter'', ''slaughtered'', '''', ''x'', %s)', e1));
  ok := ok and r ->> 'error' = 'stale_board';
  r := pg_temp.api(pg_temp.dev('SL1'), format('select animal_push(%L::jsonb)', jsonb_build_object('id', 971, 'board_epoch', e1, 'slaughter', 'shot', 'slaughter_time', 1)));
  ok := ok and r ->> 'error' = 'stale_board';
  perform pg_temp.rec('daily reset twice: each ok, new day each time, board + cursors empty, old day refused', ok,
    concat_ws(' | ', r1::text, r2::text, e0, e1, e2, r::text));
  rr1 := pg_temp.api('{}', 'select request_daily_rollover()');
  rr2 := pg_temp.api('{}', 'select request_daily_rollover()');
  perform pg_temp.rec('automatic rollover runs at most once per plant day',
    not coalesce((rr2 ->> 'done')::boolean, true) and (rr2 ->> 'status') in ('already', 'not_yet', 'busy', 'initialized'),
    rr1::text || ' | ' || rr2::text);
  r := pg_temp.api(pg_temp.dev('SL1'), format('select reset_daily_board(%L)', 'x'));
  perform pg_temp.rec('a tablet cannot reset the day', r ->> 'error' = 'unauthorized', r::text);
end $$;
$gt53$;
    v_step := 'step 45 chaos: after the daily reset';
    execute $gt54$
-- ── step 45 chaos: after the daily reset ─────────────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; ok boolean; e_old bigint := pg_temp.v('epoch_before_reset')::bigint;
begin
  -- (c) the reset after a takeover: board, cursors and the takeover state are gone
  ok := (pg_temp.ar(980)).inner_status is null and (pg_temp.ar(980)).inner_by_device is null
        and (pg_temp.ar(981)).inner_status is null and (pg_temp.ar(981)).inner_by_device is null and (pg_temp.ar(981)).inner_time is null
        and (pg_temp.ar(982)).outer_open_by_device is null and (pg_temp.ar(982)).outer_open_at is null
        and not exists (select 1 from device_stage_cursor)
        and not exists (select 1 from devices_pilot where cursor_slaughter is not null or cursor_inner is not null
                                                     or cursor_outer is not null or cursor_eso is not null)
        and (pg_temp.ar(981)).board_epoch = pg_temp.ep() and pg_temp.ep() > e_old;
  -- the tablet that lost the check can open it again on the new day (once #981 is slaughtered that day)
  perform pg_temp.prep(981, 'slaughter');
  r := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(981, 'inner_start', 'in_progress', '', ''));
  ok := ok and pg_temp.claimed(r) and (pg_temp.ar(981)).inner_by_device = pg_temp.devid('IN1');
  perform pg_temp.rec('chaos (c): the daily reset after a takeover: board, cursors, takeover state and outer locks are gone', ok, left(r::text, 120));
  -- (e) commands queued on the old day arrive after the reset: stale_board, nothing written
  r  := pg_temp.api(pg_temp.dev('SL1'), format('select animal_push(%L::jsonb, %L::uuid)',
                    jsonb_build_object('id', 985, 'board_epoch', e_old, 'slaughter', 'shot', 'slaughter_time', 1), gen_random_uuid()));
  r2 := pg_temp.api(pg_temp.dev('SL1'), format('select claim_animal_stage(985, ''slaughter'', ''slaughtered'', '''', ''x'', %s, %L::uuid)', e_old, gen_random_uuid()));
  r3 := pg_temp.api(pg_temp.dev('ESO1'), format('select eso_change(985, ''nevela'', ''x'', %s, %L::uuid)', e_old, gen_random_uuid()));
  r4 := pg_temp.api(pg_temp.dev('OUT2'), format('select outer_open(985, %s, true, ''x'', %L::uuid)', e_old, gen_random_uuid()));
  r5 := pg_temp.api(pg_temp.dev('OUT2'), format('select set_not_chalak_outer(985, %s, %L::uuid)', e_old, gen_random_uuid()));
  ok := r ->> 'error' = 'stale_board' and r2 ->> 'error' = 'stale_board' and r3 ->> 'error' = 'stale_board'
        and r4 ->> 'error' = 'stale_board' and r5 ->> 'error' = 'stale_board'
        and (pg_temp.ar(985)).slaughter is null and (pg_temp.ar(985)).outer_open_by_device is null and not (pg_temp.ar(985)).not_chalak_outer;
  -- (b) after the reset: the old command id still answers its stored result and changes nothing
  r := pg_temp.api(pg_temp.dev('IN1'), format('select claim_animal_stage(980, ''inner_start'', ''in_progress'', '''', ''x'', %s, %L::uuid)',
                   pg_temp.ep(), pg_temp.v('c1_before_reset')));
  ok := ok and coalesce((r ->> 'replayed')::boolean, false) and (pg_temp.ar(980)).inner_status is null;
  perform pg_temp.rec('chaos (e): commands queued with the previous day (claim / push / eso / open / rabbinate) → stale_board; an old command id changes nothing', ok,
    concat_ws(' | ', r ->> 'replayed', r2 ->> 'error', r3 ->> 'error', r4 ->> 'error', r5 ->> 'error'));
end $$;
$gt54$;
    v_step := '(d) two automatic rollovers for the same plant date → one new day; two manual resets → two';
    execute $gt55$
-- (d) two automatic rollovers for the same plant date → one new day; two manual resets → two days, each archived
do $$
declare rr1 jsonb; rr2 jsonb; r jsonb; e0 bigint; e1 bigint; e2 bigint; e3 bigint; n0 int; ok boolean; a1 daily_board_archive; a2 daily_board_archive;
begin
  update settings_pilot set settings = coalesce(settings, '{}'::jsonb) || '{"plantTimezone":"UTC","autoResetTime":"00:00"}'::jsonb where id = 1;
  perform set_config('gt.reset_in_progress', 'true', true);
  update animals_pilot set inner_status = null, inner_time = null, inner_by_device = null,             -- nothing "busy" on the board
                           slaughter = null, slaughter_time = null, slaughter_by_device = null where id = 981;   -- (step 46: nothing unfinished)
  perform set_config('gt.reset_in_progress', 'false', true);
  insert into plant_state (key, value) values ('lastRolloverDate', ((now() at time zone 'UTC')::date - 1)::text)
    on conflict (key) do update set value = excluded.value;
  e0 := _board_epoch(); n0 := (select count(*) from daily_board_archive);
  rr1 := pg_temp.api('{}', 'select request_daily_rollover()');
  e1 := _board_epoch();
  perform pg_sleep(0.01);
  rr2 := pg_temp.api('{}', 'select request_daily_rollover()');
  ok := (rr1 ->> 'done')::boolean and rr1 ->> 'status' = 'rolled_over' and e1 > e0
        and not (rr2 ->> 'done')::boolean and rr2 ->> 'status' = 'already' and _board_epoch() = e1
        and (select count(*) from daily_board_archive) = n0 + 1;
  -- manual resets: each one is a new day and archives the board it ends
  r := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(986, 'slaughter', 'slaughtered', '', ''));
  ok := ok and pg_temp.claimed(r);
  perform pg_sleep(0.01);
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  e2 := _board_epoch();
  select * into a1 from daily_board_archive order by id desc limit 1;
  perform pg_sleep(0.01);
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  e3 := _board_epoch();
  select * into a2 from daily_board_archive order by id desc limit 1;
  ok := ok and e2 > e1 and e3 > e2 and (select count(*) from daily_board_archive) = n0 + 3
        and a1.reason = 'manual' and a1.animals_count = 1 and a1.board @> '[{"id": 986, "slaughter": "slaughtered"}]'::jsonb
        and a2.reason = 'manual' and a2.animals_count = 0 and a2.id > a1.id;
  perform pg_temp.rec('chaos (d): two automatic rollovers for one plant date → one new day; two manual resets → two new days, each archives its board', ok,
    concat_ws(' | ', rr1::text, rr2::text, e0, e1, e2, e3, a1.animals_count, a2.animals_count));
end $$;
$gt55$;
    v_step := 'step 46: the order of the stages';
    execute $gt56$
-- ── step 46: the order of the stages ─────────────────────────────────────────
-- (tablets still paired at this point of the test: SL1, ESO1, IN1, OUT2, LEGS, PARTS, STAMPS)
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; r6 jsonb; ok boolean; s0 jsonb;
begin
  delete from animals_carry; delete from processing_day_closed;
  select settings into s0 from settings_pilot where id = 1;
  perform pg_temp.put('settings_before_46', s0::text);
  update settings_pilot set settings = settings || '{"esophagusEnabled":false}'::jsonb where id = 1;
  -- nothing before the slaughter: no inner / outer / esophagus / rabbinate / processing on an empty number
  r  := pg_temp.api(pg_temp.dev('IN1'),  pg_temp.q_claim(961, 'inner_start', 'in_progress', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(961, 'outer', 'glatt', '', ''));
  r3 := pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(961, 'eso', 'ok', '', ''));
  r4 := pg_temp.api(pg_temp.dev('OUT2'), format('select set_not_chalak_outer(961, %s)', pg_temp.ep()));
  r5 := pg_temp.api(pg_temp.dev('STAMPS'), pg_temp.q_claim(961, 'stamped', 'true', '', ''));
  r6 := pg_temp.api(pg_temp.dev('LEGS'), pg_temp.q_push(961, '{"legs_stickers":true,"head_stickers":true}'));
  ok := r ->> 'error' = 'out_of_order' and r ->> 'reason' = 'not_slaughtered'
        and r2 ->> 'error' = 'out_of_order' and r2 ->> 'reason' = 'inner_not_confirmed'
        and r3 ->> 'error' = 'out_of_order' and r4 ->> 'error' = 'out_of_order'
        and r5 ->> 'error' = 'out_of_order' and r6 ->> 'error' = 'out_of_order'
        and (pg_temp.ar(961)).inner_status is null and (pg_temp.ar(961)).outer_status is null
        and not (pg_temp.ar(961)).not_chalak_outer and not (pg_temp.ar(961)).stamped and not (pg_temp.ar(961)).head_stickers;
  perform pg_temp.rec('step 46 order: a number not slaughtered reaches no station (inner / outer / esophagus / rabbinate / stamps / legs)', ok,
    concat_ws(' | ', r::text, r2 ->> 'reason', r3 ->> 'reason', r4 ->> 'reason', r5 ->> 'reason', r6 ->> 'error'));

  -- slaughtered → the outer inspector still has nothing until the inner check is confirmed (claim and push)
  r  := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(961, 'slaughter', 'slaughtered', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(961, 'outer', 'glatt', '', ''));
  r3 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(961, '{"outer_status":"glatt","outer_time":1}'));
  r4 := pg_temp.api(pg_temp.dev('PARTS'), pg_temp.q_push(961, '{"parts_print_count":1,"parts_printed_as":"glatt"}'));
  ok := pg_temp.claimed(r) and r2 ->> 'reason' = 'inner_not_confirmed' and r3 ->> 'error' = 'out_of_order'
        and r3 ->> 'reason' = 'inner_not_confirmed' and r4 ->> 'error' = 'out_of_order' and r4 ->> 'reason' = 'outer_not_ruled'
        and (pg_temp.ar(961)).outer_status is null and coalesce((pg_temp.ar(961)).parts_print_count, 0) = 0;
  -- inner confirmed → outer may rule; inner treif → the outer inspector never gets it
  r  := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(961, 'inner', 'confirmed', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(961, 'outer', 'glatt', '', ''));
  perform pg_temp.prep(962, 'slaughter');
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(962, 'inner', 'treif', '', ''));
  r3 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(962, 'outer', 'glatt', '', ''));
  -- nevela / shot: no esophagus, no lungs
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(963, 'slaughter', 'shot', '', ''));
  r4 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(963, 'inner_start', 'in_progress', '', ''));
  r5 := pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(963, 'eso', 'ok', '', ''));
  ok := ok and pg_temp.claimed(r) and pg_temp.claimed(r2) and r3 ->> 'reason' = 'inner_not_confirmed'
        and r4 ->> 'reason' = 'not_slaughtered' and r5 ->> 'reason' = 'not_slaughtered'
        and (pg_temp.ar(961)).outer_status = 'glatt' and (pg_temp.ar(962)).outer_status is null;
  perform pg_temp.rec('step 46 order: slaughter → inner confirmed → outer; treif inside / nevela / shot go no further (claim + push)', ok,
    concat_ws(' | ', r2 ->> 'claimed', r3 ->> 'reason', r4 ->> 'reason', r5 ->> 'reason'));

  -- the esophagus check: when the plant uses it, the lungs wait for it; after the lungs it is closed
  update settings_pilot set settings = settings || '{"esophagusEnabled":true}'::jsonb - 'esoFromIdx' where id = 1;
  perform pg_temp.prep(964, 'slaughter');
  r  := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(964, 'inner_start', 'in_progress', '', ''));
  r2 := pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(964, 'eso', 'ok', '', ''));
  r3 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(964, 'inner_start', 'in_progress', '', ''));
  r4 := pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(965, 'eso', 'nevela', '', ''));        -- 965 not slaughtered
  perform pg_temp.prep(966, 'slaughter');
  perform pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(966, 'eso', 'nevela', '', ''));
  r5 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(966, 'inner_start', 'in_progress', '', ''));
  -- a "nevela" from the esophagus after the lungs were checked: refused (claim and the offline push path)
  r6 := pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_claim(964, 'eso', 'nevela', '', ''));
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(964, 'inner', 'confirmed', '', ''));
  perform pg_temp.prep(967, 'inner');
  ok := r ->> 'reason' = 'eso_not_passed' and pg_temp.claimed(r2) and pg_temp.claimed(r3)
        and r4 ->> 'reason' = 'not_slaughtered' and r5 ->> 'reason' = 'not_slaughtered'
        and not pg_temp.claimed(r6) and (pg_temp.ar(964)).slaughter = 'slaughtered' and (pg_temp.ar(964)).eso_result = 'ok';
  r  := pg_temp.api(pg_temp.dev('ESO1'), pg_temp.q_push(967, '{"eso_result":"nevela","eso_checked":true}'));
  ok := ok and r ->> 'error' = 'out_of_order' and r ->> 'reason' = 'later_stage_started' and (pg_temp.ar(967)).slaughter = 'slaughtered';
  perform pg_temp.rec('step 46 order: esophagus on → lungs wait for it; a nevela from the esophagus after the lungs is refused (claim + offline push)', ok,
    concat_ws(' | ', r ->> 'reason', r6::text));
  update settings_pilot set settings = settings || '{"esophagusEnabled":false}'::jsonb where id = 1;

  -- each station its own stage: an inner tablet does not rule outer, an outer tablet does not rule inner
  perform pg_temp.prep(968, 'inner'); perform pg_temp.prep(969, 'slaughter');
  r  := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(968, 'outer', 'glatt', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(969, 'inner_start', 'in_progress', '', ''));
  r3 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(969, 'inner', 'confirmed', '', ''));
  r4 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(968, '{"outer_status":"glatt","outer_time":1}'));
  ok := r ->> 'error' = 'wrong_station' and r2 ->> 'error' = 'wrong_station' and r3 ->> 'error' = 'wrong_station'
        and pg_temp.ok(r4) and (pg_temp.ar(968)).outer_status is null and (pg_temp.ar(969)).inner_status is null;
  -- the rabbinate send: only once the animal reached the outer inspector
  r  := pg_temp.api(pg_temp.dev('OUT2'), format('select set_not_chalak_outer(969, %s)', pg_temp.ep()));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), format('select set_not_chalak_outer(968, %s)', pg_temp.ep()));
  ok := ok and r ->> 'error' = 'out_of_order' and pg_temp.ok(r2) and (pg_temp.ar(968)).not_chalak_outer;
  perform pg_temp.rec('step 46 stations: inner tablet → inner only, outer tablet → outer only; rabbinate send only after the lungs', ok,
    concat_ws(' | ', r::text, r2 ->> 'ok'));
end $$;
$gt56$;
    v_step := 'step 46: kashrut configuration';
    execute $gt57$
-- ── step 46: kashrut configuration ───────────────────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; ok boolean; v_users jsonb; v_mk text;
begin
  update settings_pilot set settings = settings || jsonb_build_object('customStatuses',
           '[{"key":"custom_st46","he":"מהדרין","kosher":true},{"key":"custom_free46","he":"x","kosher":true}]'::jsonb) where id = 1;
  perform pg_temp.prep(970, 'inner');
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(970, 'outer', 'custom_st46', '', ''));
  -- the team leader may not make a status in use non-kosher or delete it; other changes are fine
  r  := pg_temp.api(pg_temp.mgr(), format('select push_settings(%L::jsonb, ''x'', %L)',
          '{"customStatuses":[{"key":"custom_st46","he":"מהדרין","kosher":false},{"key":"custom_free46","he":"x","kosher":true}]}', pg_temp.v('mgr')));
  r2 := pg_temp.api(pg_temp.mgr(), format('select push_settings(%L::jsonb, ''x'', %L)',
          '{"customStatuses":[{"key":"custom_free46","he":"x","kosher":true}]}', pg_temp.v('mgr')));
  r3 := pg_temp.api(pg_temp.mgr(), format('select push_settings(%L::jsonb, ''x'', %L)',
          '{"customStatuses":[{"key":"custom_st46","he":"מהדרין חדש","color":"#123456","kosher":true},{"key":"custom_free46","he":"x","kosher":false}]}', pg_temp.v('mgr')));
  ok := r ->> 'error' = 'status_in_use' and r ->> 'key' = 'custom_st46' and r2 ->> 'error' = 'status_in_use' and pg_temp.ok(r3)
        and (select settings -> 'customStatuses' -> 0 ->> 'color' from settings_pilot where id = 1) = '#123456';
  perform pg_temp.rec('step 46 team leader: a status an animal carries keeps its kosher mark and cannot be deleted; names / colors / unused statuses change', ok,
    concat_ws(' | ', r::text, r2::text, left(r3::text, 60)));

  -- the manufacturer (support access open, with a reason): technical settings only
  -- (closing support access earlier ended the manufacturer's session: a new one)
  update plant_state set value = (now() + interval '1 hour')::text where key = 'supportAccessUntil';
  insert into manager_sessions (manager_id)
    select id from plant_managers where role = 'manufacturer' and name = 'selftest maker' and active limit 1
    returning token into v_mk;
  perform pg_temp.put('maker46', v_mk);
  select settings -> 'users' into v_users from settings_pilot where id = 1;
  r := pg_temp.api(pg_temp.mgr('maker46'), format('select push_settings(%L::jsonb, ''x'', %L, ''printer repair'')',
         '{"printers":{"parts":"zebra-46"},"customStatuses":[],"users":[],"loginModeByRole":{"inspector":"none"},"notChalakEnabled":false}',
         pg_temp.v('maker46')));
  ok := pg_temp.ok(r) and r -> 'ignored' ? 'customStatuses' and r -> 'ignored' ? 'users' and r -> 'ignored' ? 'loginModeByRole'
        and (select settings -> 'printers' ->> 'parts' from settings_pilot where id = 1) = 'zebra-46'
        and (select settings -> 'users' from settings_pilot where id = 1) = v_users
        and jsonb_array_length((select settings -> 'customStatuses' from settings_pilot where id = 1)) = 2;
  update plant_state set value = (now() - interval '1 minute')::text where key = 'supportAccessUntil';
  perform pg_temp.rec('step 46 manufacturer: printers yes; statuses / workers / login modes / kashrut switches ignored', ok, r::text);
end $$;
$gt57$;
    v_step := 'step 46: processing over several days, strictly in order';
    execute $gt58$
-- ── step 46: processing over several days, strictly in order ─────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean; b1 bigint; b2 bigint; n0 int; arch jsonb;
begin
  update settings_pilot set settings = settings || '{"legsEnabled":false,"partsEnabled":true,"stampsEnabled":true,
                                                     "plantTimezone":"UTC","autoResetTime":"00:00"}'::jsonb where id = 1;
  delete from animals_carry; delete from processing_day_closed;
  -- day A: a clean board, two animals ruled kosher, one not yet printed / stamped
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  delete from animals_carry;
  perform pg_temp.prep(987, 'outer'); perform pg_temp.prep(988, 'outer');
  perform pg_temp.api(pg_temp.dev('PARTS'), pg_temp.q_push(988, '{"parts_print_count":3,"parts_printed_as":"glatt"}'));
  perform pg_temp.api(pg_temp.dev('STAMPS'), pg_temp.q_claim(988, 'stamped', 'true', '', ''));
  n0 := (select count(*) from daily_board_archive);
  r := pg_temp.api('{}', format('select reset_daily_board(%L, ''end of day A'')', pg_temp.v('mgr')));
  select board_id into b1 from animals_carry limit 1;
  ok := pg_temp.ok(r) and b1 = (select max(id) from daily_board_archive) and (select count(*) from daily_board_archive) = n0 + 1
        and (select count(*) from animals_carry where board_id = b1) = 2
        and (select parts_print_count from animals_carry where board_id = b1 and id = 988) = 3
        and (pg_temp.ar(987)).slaughter is null
        and exists (select 1 from admin_audit where action = 'daily_reset' and detail ->> 'reason' = 'end of day A');
  -- the screens start the new day; the parts / stamps stations get day A first
  r  := pg_temp.api(pg_temp.dev('PARTS'), 'select processing_board()');
  r2 := pg_temp.api(pg_temp.dev('STAMPS'), 'select processing_board()');
  ok := ok and (r -> 'board' ->> 'id')::bigint = b1 and jsonb_array_length(r -> 'rows') = 2 and (r -> 'board' -> 'pending' ->> 'parts')::int = 1
        and (r2 -> 'board' ->> 'id')::bigint = b1 and (r2 -> 'board' -> 'pending' ->> 'stamps')::int = 1;
  perform pg_temp.rec('step 46 days: the reset empties the screens and keeps day A''s unfinished processing (board, archive link, audit)', ok,
    concat_ws(' | ', r::text, left(r2::text, 80)));

  -- day B on the slaughter line; parts can't skip to it while day A is open
  perform pg_temp.prep(989, 'outer');
  r  := pg_temp.api(pg_temp.dev('PARTS'), pg_temp.q_push(989, '{"parts_print_count":1,"parts_printed_as":"glatt"}'));
  r2 := pg_temp.api(pg_temp.dev('STAMPS'), pg_temp.q_claim(989, 'stamped', 'true', '', ''));
  ok := r ->> 'error' = 'earlier_day_open' and (r ->> 'board')::bigint = b1 and r2 ->> 'error' = 'earlier_day_open'
        and coalesce((pg_temp.ar(989)).parts_print_count, 0) = 0 and not (pg_temp.ar(989)).stamped;
  -- work on day A: only processing columns, only the right station, rulings untouched
  r  := pg_temp.api(pg_temp.dev('OUT2'), format('select carry_push(%s, %L::jsonb)', b1, '{"id":987,"parts_print_count":1}'));
  r2 := pg_temp.api(pg_temp.dev('PARTS'), format('select carry_push(%s, %L::jsonb)', b1, '{"id":987,"outer_status":"treif","parts_print_count":3,"parts_printed_as":"glatt"}'));
  ok := ok and r ->> 'error' = 'wrong_station' and pg_temp.ok(r2) and r2 -> 'ignored' ? 'outer_status'
        and (select outer_status from animals_carry where board_id = b1 and id = 987) = 'glatt'
        and (select parts_print_count from animals_carry where board_id = b1 and id = 987) = 3;
  -- parts done with day A → parts moves to day B (today); stamps still on day A
  r  := pg_temp.api(pg_temp.dev('PARTS'), 'select processing_board()');
  r3 := pg_temp.api(pg_temp.dev('PARTS'), pg_temp.q_push(989, '{"parts_print_count":1,"parts_printed_as":"glatt"}'));
  r4 := pg_temp.api(pg_temp.dev('STAMPS'), 'select processing_board()');
  ok := ok and (r -> 'board') = 'null'::jsonb and pg_temp.ok(r3) and (pg_temp.ar(989)).parts_print_count = 1
        and (r4 -> 'board' ->> 'id')::bigint = b1;
  perform pg_temp.rec('step 46 days: no skipping — today waits until day A is done for that station; each station moves on by itself', ok,
    concat_ws(' | ', r::text, left(r3::text, 60), left(r4::text, 80)));

  -- a second kept day: stamps still must finish day A first
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  select max(board_id) into b2 from animals_carry;
  r  := pg_temp.api(pg_temp.dev('STAMPS'), format('select carry_claim(%s, 989, ''stamped'')', b2));
  r2 := pg_temp.api(pg_temp.dev('STAMPS'), format('select carry_claim(%s, 987, ''stamped'')', b1));
  ok := b2 > b1 and r ->> 'error' = 'earlier_day_open' and pg_temp.claimed(r2) and coalesce((r2 ->> 'boardDone')::boolean, false)
        and not exists (select 1 from animals_carry where board_id = b1)
        and (select board from daily_board_archive where id = b1) @> '[{"id":987,"stamped":true,"parts_print_count":3}]'::jsonb;
  r3 := pg_temp.api(pg_temp.dev('STAMPS'), format('select carry_claim(%s, 989, ''stamped'')', b2));
  ok := ok and pg_temp.claimed(r3);
  perform pg_temp.rec('step 46 days: two kept days in order; a day done for every station goes back into its archive row', ok,
    concat_ws(' | ', r::text, left(r2::text, 80), left(r3::text, 60)));

  -- the team leader can close a kept day for a station (a reason is required; audited)
  perform pg_temp.prep(990, 'outer');
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  select max(board_id) into b2 from animals_carry;
  r  := pg_temp.api('{}', format('select processing_day_close(%L, %s, ''stamps'')', pg_temp.v('mgr'), b2));
  r2 := pg_temp.api(pg_temp.dev('STAMPS'), format('select processing_day_close(%L, %s, ''stamps'', ''x'')', 'x', b2));
  r3 := pg_temp.api('{}', format('select processing_day_close(%L, %s, ''stamps'', ''sold unstamped'')', pg_temp.v('mgr'), b2));
  r4 := pg_temp.api('{}', format('select processing_status(%L)', pg_temp.v('mgr')));
  ok := r ->> 'error' = 'reason_required' and r2 ->> 'error' = 'unauthorized' and pg_temp.ok(r3) and (r3 ->> 'pendingLeft')::int = 1
        and exists (select 1 from admin_audit where action = 'processing_day_close' and detail ->> 'reason' = 'sold unstamped')
        and pg_temp.ok(r4);
  perform pg_temp.rec('step 46 days: the team leader closes a kept day for a station only with a reason (audited); a tablet cannot', ok,
    concat_ws(' | ', r::text, r2::text, r3::text));
  delete from animals_carry; delete from processing_day_closed;
end $$;
$gt58$;
    v_step := 'step 46: the daily rollover never empties a board in the middle of work';
    execute $gt59$
-- ── step 46: the daily rollover never empties a board in the middle of work ──
do $$
declare rr jsonb; ok boolean; e0 bigint;
begin
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  delete from animals_carry;
  insert into plant_state (key, value) values ('lastRolloverDate', ((now() at time zone 'UTC')::date - 1)::text)
    on conflict (key) do update set value = excluded.value;
  perform pg_temp.prep(991, 'slaughter');                       -- slaughtered an hour ago, lungs not checked
  e0 := _board_epoch();
  rr := pg_temp.api('{}', 'select request_daily_rollover()');
  ok := rr ->> 'status' = 'waiting_unfinished' and (rr ->> 'unfinished')::int = 1 and _board_epoch() = e0
        and (pg_temp.ar(991)).slaughter = 'slaughtered'
        and (select system_health(pg_temp.v('mgr'))) -> 'attention' ? 'rollover_waiting';
  -- ruling in the last 20 minutes: wait, however late it is
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(992, 'slaughter', 'shot', '', ''));
  perform pg_temp.prep(991, 'outer');
  rr := pg_temp.api('{}', 'select request_daily_rollover()');
  ok := ok and rr ->> 'status' = 'busy' and _board_epoch() = e0;
  perform pg_temp.rec('step 46 rollover: never during work, never with a slaughtered animal short of its last ruling (health: rollover_waiting)', ok, rr::text);
  update settings_pilot set settings = pg_temp.v('settings_before_46')::jsonb where id = 1;
end $$;
$gt59$;
    v_step := 'step 46 (review fixes): the manual reset stops for unfinished animals; worker codes hashes';
    execute $gt60$
-- ── step 46 (review fixes): the manual reset stops for unfinished animals; worker codes hashes only; board lock ──
do $$
declare r jsonb; r2 jsonb; ok boolean; e0 bigint; v_tok text; s0 jsonb;
begin
  delete from animals_carry; delete from processing_day_closed;
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  delete from animals_carry;
  perform pg_temp.prep(993, 'inner'); perform pg_temp.prep(994, 'slaughter'); perform pg_temp.prep(995, 'outer');
  e0 := _board_epoch();
  r  := pg_temp.api('{}', format('select reset_daily_board(%L)', pg_temp.v('mgr')));
  r2 := pg_temp.api('{}', format('select reset_daily_board(%L, ''  '')', pg_temp.v('mgr')));
  ok := r ->> 'error' = 'unfinished_animals' and (r ->> 'unfinished')::int = 2 and r -> 'numbers' = '[994, 995]'::jsonb
        and r2 ->> 'error' = 'unfinished_animals' and _board_epoch() = e0
        and (pg_temp.ar(993)).inner_status = 'confirmed' and (pg_temp.ar(994)).slaughter = 'slaughtered';
  r  := pg_temp.api('{}', format('select reset_daily_board(%L, ''carcasses 994/995 condemned'')', pg_temp.v('mgr')));
  ok := ok and pg_temp.ok(r) and _board_epoch() > e0 and (pg_temp.ar(993)).slaughter is null
        and exists (select 1 from admin_audit where action = 'daily_reset' and detail ->> 'reason' = 'carcasses 994/995 condemned'
                                                and detail -> 'unfinishedNumbers' = '[994, 995]'::jsonb);
  perform pg_temp.rec('step 46 manual reset: stops while slaughtered animals lack their last ruling (numbers given); only with a written reason, audited', ok,
    concat_ws(' | ', r::text, r2::text));

  -- a worker code left as plain text in the settings (written past the trigger) no longer logs in
  select settings into s0 from settings_pilot where id = 1;
  alter table settings_pilot disable trigger zz_settings_hash_worker_codes;
  update settings_pilot set settings = jsonb_set(settings, '{users}', coalesce(settings -> 'users', '[]'::jsonb)
           || '[{"name":"Plain Legacy","role":"inner","code":"481516"}]'::jsonb) where id = 1;
  alter table settings_pilot enable trigger zz_settings_hash_worker_codes;
  delete from login_attempts;
  r := pg_temp.api(pg_temp.dev('IN1'), 'select worker_login(''inner'', ''481516'')');
  update settings_pilot set settings = s0 where id = 1;
  delete from login_attempts;
  perform pg_temp.rec('step 46 worker login: a code kept as plain text is not accepted (hashes only)', r ->> 'error' = 'code_invalid', r::text);

  -- one transaction at a time on a kept board: every path takes the board lock
  perform pg_temp.rec('step 46 kept boards: write / claim / close / archive all take the per-board lock',
    pg_get_functiondef('carry_push(bigint,jsonb,uuid)'::regprocedure) ~ '_proc_board_lock\(p_board\)'
    and pg_get_functiondef('carry_claim(bigint,integer,text,uuid)'::regprocedure) ~ '_proc_board_lock\(p_board\)'
    and pg_get_functiondef('processing_day_close(text,bigint,text,text)'::regprocedure) ~ '_proc_board_lock\(p_board\)'
    and pg_get_functiondef('_proc_finalize(bigint)'::regprocedure) ~ '_proc_board_lock\(b.board_id\)');
end $$;
$gt60$;
    v_step := 'step 46 (2nd review): a ruling''s time changes only with the ruling; archived status defini';
    execute $gt61$
-- ── step 46 (2nd review): a ruling's time changes only with the ruling; archived status definitions ──
do $$
declare r jsonb; r2 jsonb; r3 jsonb; ok boolean; t0 bigint; t1 bigint; t2 bigint; t3 bigint; a jsonb;
begin
  -- outer: OUT2 rules 972, then 973 (moved on). A time-only write on 972 keeps the time and the cursor,
  -- so the correction of 972 after moving on stays refused (the bypass)
  perform pg_temp.prep(972, 'inner'); perform pg_temp.prep(973, 'inner');
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(972, 'outer', 'glatt', '', ''));
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(973, 'outer', 'glatt', '', ''));
  t0 := (pg_temp.ar(972)).outer_time;
  r  := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(972, jsonb_build_object('outer_time', t0 + 5)));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(972, jsonb_build_object('outer_status', 'treif', 'outer_time', t0 + 10)));
  ok := pg_temp.ok(r) and (pg_temp.ar(972)).outer_time = t0
        and (select animal_id from device_stage_cursor where device_id = pg_temp.devid('OUT2') and stage = 'outer') = 973
        and r2 ->> 'error' = 'moved_on' and (pg_temp.ar(972)).outer_status = 'glatt';
  perform pg_temp.rec('step 46 time-only: moving a ruling''s time keeps it and the "last animal" cursor — the correction after moving on stays refused', ok,
    concat_ws(' | ', left(r::text, 80), r2 ->> 'error'));

  -- outer after parts printed; another station (inner) on the outer time; slaughter after the lungs; inner after outer
  perform pg_temp.api(pg_temp.dev('PARTS'), pg_temp.q_push(973, '{"parts_print_count":1,"parts_printed_as":"glatt"}'));
  t1 := (pg_temp.ar(973)).outer_time;
  r  := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(973, jsonb_build_object('outer_time', t1 + 5)));
  r2 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(973, jsonb_build_object('outer_time', t1 + 7)));
  ok := pg_temp.ok(r) and pg_temp.ok(r2) and (pg_temp.ar(973)).outer_time = t1;
  perform pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_claim(974, 'slaughter', 'slaughtered', '', ''));
  perform pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(974, 'inner', 'confirmed', '', ''));
  t2 := (pg_temp.ar(974)).slaughter_time;
  r3 := pg_temp.api(pg_temp.dev('SL1'), pg_temp.q_push(974, jsonb_build_object('slaughter_time', t2 + 5)));
  ok := ok and (pg_temp.ar(974)).slaughter_time = t2 and (pg_temp.ar(974)).slaughter = 'slaughtered';
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(974, 'outer', 'glatt', '', ''));
  t3 := (pg_temp.ar(974)).inner_time;
  r  := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_push(974, jsonb_build_object('inner_time', t3 + 5)));
  ok := ok and (pg_temp.ar(974)).inner_time = t3 and (pg_temp.ar(974)).inner_status = 'confirmed'
        and (select animal_id from device_stage_cursor where device_id = pg_temp.devid('IN1') and stage = 'inner') = 974;
  -- a real correction (ruling + time) right away still works
  perform pg_temp.prep(975, 'inner');
  perform pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_claim(975, 'outer', 'glatt', '', ''));
  r2 := pg_temp.api(pg_temp.dev('OUT2'), pg_temp.q_push(975, jsonb_build_object('outer_status', 'beit', 'outer_time', (pg_temp.ar(975)).outer_time + 5)));
  ok := ok and pg_temp.ok(r2) and (pg_temp.ar(975)).outer_status = 'beit';
  perform pg_temp.rec('step 46 time-only: outer after print, from another station, slaughter after the lungs, inner after outer — time kept; a real correction right away still works', ok,
    concat_ws(' | ', left(r3::text, 60), left(r::text, 60), left(r2::text, 60)));

  -- every archived day keeps the status definitions it was ruled with
  update settings_pilot set settings = settings || '{"customStatuses":[{"key":"custom_arch46","he":"x","kosher":true}]}'::jsonb where id = 1;
  perform pg_temp.api('{}', format('select reset_daily_board(%L, ''selftest'')', pg_temp.v('mgr')));
  a := pg_temp.api('{}', format('select archive_days(%L, %L::date, %L::date)', pg_temp.v('mgr'), (now() - interval '300 days')::date, (now() + interval '1 day')::date));
  perform pg_temp.rec('step 46 archive: each archived day keeps the status definitions it was ruled with',
    (select statuses -> 'customStatuses' -> 0 ->> 'key' from daily_board_archive order by id desc limit 1) = 'custom_arch46'
    and (select statuses -> 'kosher' from daily_board_archive order by id desc limit 1) ? 'custom_arch46'
    and exists (select 1 from jsonb_array_elements(a -> 'days') d where d ? 'statuses'),
    left(a::text, 200));
end $$;
$gt61$;
    v_step := 'step 46 (3rd review): first team leader needs the setup code; 6-character codes; unique st';
    execute $gt62$
-- ── step 46 (3rd review): first team leader needs the setup code; 6-character codes; unique status keys; reset lock ──
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean; v_hash text; v_ids uuid[];
begin
  -- no team leader yet and no setup code configured: the app cannot create one
  select array_agg(id) into v_ids from plant_managers where role = 'manager' and active;
  update plant_managers set active = false where id = any(v_ids);
  select value into v_hash from plant_state where key = 'setupCodeHash';
  delete from plant_state where key = 'setupCodeHash';
  delete from login_attempts;
  r  := pg_temp.api('{}', 'select create_first_manager(''Intruder'', ''intruder-code-1'', null)');
  r2 := pg_temp.api('{}', 'select plant_setup_needed()');
  ok := (r2 ->> 'needed')::boolean and not (r2 ->> 'setupCode')::boolean;
  perform _set_setup_code('ABCD-1234-XY');                                   -- as in the installation note
  r2 := pg_temp.api('{}', 'select create_first_manager(''Intruder'', ''intruder-code-1'', ''WRONGCODE1'')');
  r3 := pg_temp.api('{}', 'select create_first_manager(''Plant leader'', ''12345'', ''ABCD-1234-XY'')');
  r4 := pg_temp.api('{}', 'select create_first_manager(''Plant leader'', ''leader-46-code'', ''abcd-1234-xy'')');   -- typed in lower case
  r  := r || jsonb_build_object('afterInstall', pg_temp.api('{}', 'select plant_setup_needed()'));
  ok := ok and not (r #>> '{afterInstall,needed}')::boolean
        and r ->> 'error' = 'setup_code_not_configured' and r2 ->> 'error' = 'setup_code_wrong'
        and r3 ->> 'error' like 'code too short%' and pg_temp.ok(r4)
        and not exists (select 1 from plant_managers where name = 'Intruder')
        and not exists (select 1 from plant_state where key = 'setupCodeHash');          -- one time only
  delete from plant_managers where name = 'Plant leader';
  update plant_managers set active = true where id = any(v_ids);
  if v_hash is not null then insert into plant_state (key, value) values ('setupCodeHash', v_hash) on conflict (key) do update set value = excluded.value; end if;
  delete from login_attempts;
  perform pg_temp.rec('step 46 first team leader: through the app only with the setup code (none configured → refused; dashes / case do not matter); 6 characters; one time', ok,
    concat_ws(' | ', r::text, r2::text, r3::text, left(r4::text, 40)));

  -- new team-leader / owner codes: at least 6 characters
  r  := pg_temp.api('{}', 'select 1');
  begin perform leader_account_add('Short', '12345'); r := jsonb_build_object('error', 'accepted');
  exception when others then r := jsonb_build_object('error', sqlerrm); end;
  r2 := pg_temp.api('{}', format('select manager_add_owner(%L, ''Short Owner'', ''abcde'')', pg_temp.v('mgr')));
  perform pg_temp.rec('step 46 team-leader / owner codes: fewer than 6 characters refused',
    r ->> 'error' like 'code too short%' and r2 ->> 'error' like 'code too short%'
    and not exists (select 1 from plant_managers where name in ('Short', 'Short Owner')), concat_ws(' | ', r::text, r2::text));

  -- statuses: two with the same key are refused
  r := pg_temp.api(pg_temp.mgr(), format('select push_settings(%L::jsonb, ''x'', %L)',
         '{"customStatuses":[{"key":"custom_dup46","he":"a","kosher":true},{"key":"custom_dup46","he":"b","kosher":false}]}', pg_temp.v('mgr')));
  perform pg_temp.rec('step 46 statuses: two statuses with the same key are refused',
    r ->> 'error' = 'bad_settings' and r ->> 'key' = 'customStatuses', r::text);

  -- every writer of today's board takes the reset lock (shared; the reset takes it exclusively)
  perform pg_temp.rec('step 46 reset lock: every writer of today''s board takes the shared reset lock; the reset takes it exclusively',
    not exists (select 1 from unnest(array['animal_push(jsonb,uuid)', 'claim_animal_stage(integer,text,text,text,text,bigint,uuid)',
                                           'eso_change(integer,text,text,bigint,uuid)', 'set_not_chalak_outer(integer,bigint,uuid)',
                                           'outer_open(integer,bigint,boolean,text,uuid)', 'lung_drawing_set(integer,bigint,text)']) f
                 where pg_get_functiondef(f::regprocedure) !~ '_board_write_lock\(\)')
    and pg_get_functiondef('_board_write_lock()'::regprocedure) ~ 'pg_advisory_xact_lock_shared'
    and pg_get_functiondef('request_daily_rollover()'::regprocedure) ~ 'pg_advisory_xact_lock\(hashtext\(''glatttrack_daily_rollover''\)\)'
    and pg_get_functiondef('reset_daily_board(text,text)'::regprocedure) ~ 'pg_advisory_xact_lock\(hashtext\(''glatttrack_daily_rollover''\)\)');
end $$;
$gt62$;
    v_step := 'step 46: the team leader only from a team-leader device';
    execute $gt63$
-- ── step 46: the team leader only from a team-leader device ──────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; ok boolean; v_id text; v_tok text; t text; v_code text;
        v_id2 text; v_s text;
begin
  delete from login_attempts;
  -- before the plant has a team-leader device: a team leader may log in anywhere (installation)
  r := pg_temp.api('{}', format('select manager_login(%L)', pg_temp.v('mgr_code')));
  ok := pg_temp.ok(r) and (r ->> 'registerLeaderDevice')::boolean;
  -- the first team-leader device is paired from that session; the session moves onto it
  v_id := 'gtselftest_leader_' || substr(md5(random()::text), 1, 6);
  v_code := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  insert into device_pairing (code, device_id, device_name, secret_hash) values (v_code, v_id, 'selftest leader', 'x');
  r2 := pg_temp.api('{}', format('select device_pair(%L, %L, ''leader'', 0, false, ''TL phone'')', r ->> 'token', v_code));
  v_tok := (select token_plain from device_pairing where code = v_code);
  perform pg_temp.put('id_LEADER', v_id);
  perform pg_temp.put('tok_LEADER', v_tok);
  ok := ok and pg_temp.ok(r2) and (select assigned_role from devices_pilot where id = v_id) = 'leader'
        and (select device_id from manager_sessions where token = r ->> 'token') = v_id;
  perform pg_temp.rec('step 46 team-leader device: before the first one any device may log in; the first is paired from that session, which moves onto it', ok,
    concat_ws(' | ', left(r::text, 80), r2::text));

  -- from now on: only from a team-leader device (not unpaired, not a station); owner unchanged
  delete from login_attempts;
  r  := pg_temp.api('{}', format('select manager_login(%L)', pg_temp.v('mgr_code')));
  r2 := pg_temp.api(pg_temp.dev('SL1'), format('select manager_login(%L)', pg_temp.v('mgr_code')));
  ok := (select count(*) from login_attempts la where not la.ok) >= 2;
  r3 := pg_temp.api(pg_temp.dev('LEADER'), format('select manager_login(%L)', pg_temp.v('mgr_code')));
  ok := ok and r ->> 'reason' = 'leader_device_required' and r2 ->> 'reason' = 'leader_device_required' and pg_temp.ok(r3)
        and (select device_id from manager_sessions where token = r3 ->> 'token') = v_id
        and exists (select 1 from events_pilot where stage = 'security' and action = 'leader_device_required');
  t := r3 ->> 'token';
  r4 := pg_temp.api(pg_temp.dev('LEADER') || jsonb_build_object('x-manager-token', t), format('select manager_session_check(%L)', t));
  r5 := pg_temp.api(jsonb_build_object('x-manager-token', t), format('select manager_session_check(%L)', t));
  ok := ok and pg_temp.ok(r4) and not pg_temp.ok(r5);
  perform pg_temp.rec('step 46 team-leader device: a team leader logs in only on a team-leader device (unpaired / station refused, counted, recorded); the session works only there', ok,
    concat_ws(' | ', r::text, r2::text, left(r3::text, 60), r5::text));

  -- a team-leader device has no ruling rights and writes nothing without the session
  perform pg_temp.prep(976, 'inner');
  r  := pg_temp.api(pg_temp.dev('LEADER'), pg_temp.q_claim(976, 'outer', 'glatt', '', ''));
  r2 := pg_temp.api(pg_temp.dev('LEADER'), pg_temp.q_push(976, '{"outer_status":"glatt","outer_time":1}'));
  r3 := pg_temp.api(pg_temp.dev('LEADER'), 'select push_settings(''{"printers":{"x":1}}''::jsonb, ''x'')');
  r4 := pg_temp.api(pg_temp.dev('LEADER'), 'select worker_login(''inner'', ''739104'')');
  ok := r ->> 'error' = 'wrong_station' and (pg_temp.ar(976)).outer_status is null
        and r3 ->> 'error' = 'device_not_paired' and r4 ->> 'error' = 'wrong_station';
  perform pg_temp.rec('step 46 team-leader device: no ruling, no station writes, no worker login on its own', ok,
    concat_ws(' | ', r::text, left(r2::text, 60), r3::text, r4::text));

  -- a second team-leader device (slot 1); unpairing a team-leader device ends its sessions
  v_id2 := 'gtselftest_leader2_' || substr(md5(random()::text), 1, 6);
  v_code := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  insert into device_pairing (code, device_id, device_name, secret_hash) values (v_code, v_id2, 'selftest leader 2', 'x');
  r := pg_temp.api(pg_temp.dev('LEADER') || jsonb_build_object('x-manager-token', t),
                   format('select device_pair(%L, %L, ''leader'', 1, false, ''TL office PC'')', t, v_code));
  r2 := pg_temp.api(pg_temp.dev('LEADER') || jsonb_build_object('x-manager-token', t),
                    format('select device_unpair(%L, %L, ''selftest: phone lost'')', t, v_id));
  r3 := pg_temp.api(pg_temp.dev('LEADER') || jsonb_build_object('x-manager-token', t), format('select manager_session_check(%L)', t));
  ok := pg_temp.ok(r) and (select assigned_index from devices_pilot where id = v_id2) = 1 and pg_temp.ok(r2) and not pg_temp.ok(r3);
  perform pg_temp.rec('step 46 team-leader device: more than one may be paired; unpairing one ends the sessions made on it', ok,
    concat_ws(' | ', r::text, r2::text, r3::text));

  -- removing every team-leader device does not reopen the door
  delete from login_attempts;
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = null, assigned_index = null where assigned_role = 'leader' and id <> v_id2;
  perform set_config('app.device_admin', '', true);
  -- the last one (v_id2, still paired, a session on it) is "lost": only the server recovers —
  -- it disconnects it (key revoked, session ended) and reopens the first-device registration
  r4 := pg_temp.api(jsonb_build_object('x-device-token', (select token_plain from device_pairing where device_id = v_id2 order by created_at desc limit 1)),
                    format('select manager_login(%L)', pg_temp.v('mgr_code')));
  r  := pg_temp.api('{}', format('select manager_login(%L)', pg_temp.v('mgr_code')));
  r2 := pg_temp.api('{}', 'select leader_device_recovery(''phone lost'')');
  v_s := leader_device_recovery('selftest: phone lost');
  delete from login_attempts;
  r3 := pg_temp.api('{}', format('select manager_login(%L)', pg_temp.v('mgr_code')));
  ok := pg_temp.ok(r4) and r ->> 'reason' = 'leader_device_required' and not pg_temp.ok(r2) and v_s like 'ok — 1 %'
        and (select assigned_role from devices_pilot where id = v_id2) is null
        and not exists (select 1 from device_credentials where device_id = v_id2 and not revoked)
        and not exists (select 1 from manager_sessions where token = r4 ->> 'token')
        and pg_temp.ok(r3) and (r3 ->> 'registerLeaderDevice')::boolean
        and exists (select 1 from events_pilot where stage = 'security' and action = 'leader_device_recovery');
  perform pg_temp.rec('step 46 team-leader device: removing every one does not reopen the door; the last one lost → only leader_device_recovery() from the server, which disconnects it (key, sessions)', ok,
    concat_ws(' | ', left(r4::text, 60), r::text, r2::text, v_s, left(r3::text, 80)));
  delete from login_attempts;
  insert into plant_state (key, value) values ('leaderDevicesRequired', '1') on conflict (key) do update set value = '1';
end $$;
$gt63$;
    v_step := 'step 46: accounts — team leaders only from the server; the owner changes nothing';
    execute $gt64$
-- ── step 46: accounts — team leaders only from the server; the owner changes nothing ──
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; ok boolean; v_s text; v_new uuid; v_own uuid := (select id from plant_managers where name = 'selftest owner');
begin
  -- a team leader cannot add or remove a team leader; nor can the owner / manufacturer
  r  := pg_temp.api('{}', format('select manager_add(%L, ''ST second leader'', ''st-lead-2-code'')', pg_temp.v('mgr')));
  r2 := pg_temp.api3('{}', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}', format('select manager_add(%L, ''ST second leader'', ''st-lead-2-code'')', pg_temp.v('owner')));
  r3 := pg_temp.api('{}', format('select manager_add(%L, ''ST second leader'', ''st-lead-2-code'')', pg_temp.v('maker')));
  r4 := pg_temp.api('{}', format('select manager_deactivate(%L, %L)', pg_temp.v('mgr'), (pg_temp.v('mgr_id'))::uuid));
  r5 := pg_temp.api('{}', 'select leader_account_add(''ST second leader'', ''st-lead-2-code'')');
  ok := r ->> 'error' = 'server_only' and r2 ->> 'error' = 'server_only' and not pg_temp.ok(r3)
        and r4 ->> 'error' = 'server_only' and not pg_temp.ok(r5)
        and not exists (select 1 from plant_managers where name = 'ST second leader')
        and (select active from plant_managers where id = (pg_temp.v('mgr_id'))::uuid);
  perform pg_temp.rec('step 46 accounts: no team leader is added or removed through the app (team leader, owner, manufacturer)', ok,
    concat_ws(' | ', r::text, r2::text, r3::text, r4::text, r5::text));

  -- on the server (installer): add / remove a team leader, recorded; never the last one
  v_s := leader_account_add('ST second leader', 'st-lead-2-code');
  v_new := (select id from plant_managers where name = 'ST second leader' and active);
  ok := v_s like 'ok%' and v_new is not null
        and exists (select 1 from events_pilot where stage = 'security' and action = 'account_added' and payload ->> 'id' = v_new::text);
  v_s := leader_account_remove('ST second leader');
  ok := ok and v_s like 'ok%' and not (select active from plant_managers where id = v_new)
        and exists (select 1 from events_pilot where stage = 'security' and action = 'account_removed' and payload ->> 'id' = v_new::text);
  begin
    update plant_managers set active = false where role = 'manager' and active and id <> (pg_temp.v('mgr_id'))::uuid;
    perform leader_account_remove('selftest leader');
    ok := false;                                                    -- must not get here
  exception when others then
    ok := ok and sqlerrm like '%last team leader%';
  end;
  perform pg_temp.rec('step 46 accounts: team leaders added / removed only on the server (recorded); never the last one', ok, v_s);
  delete from plant_managers where name = 'ST second leader';

  -- owner accounts: the team leader adds / removes them; the owner cannot
  r  := pg_temp.api('{}', format('select manager_add_owner(%L, ''ST owner 2'', ''st-owner-2-code'')', pg_temp.v('mgr')));
  v_new := (r ->> 'id')::uuid;
  r2 := pg_temp.api3('{}', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}', format('select manager_add_owner(%L, ''ST owner 3'', ''st-owner-3-code'')', pg_temp.v('owner')));
  r3 := pg_temp.api3('{}', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}', format('select manager_deactivate(%L, %L)', pg_temp.v('owner'), v_new));
  r4 := pg_temp.api('{}', format('select manager_deactivate(%L, %L)', pg_temp.v('mgr'), v_new));
  r5 := pg_temp.api3('{}', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}', format('select manager_list(%L)', pg_temp.v('owner')));
  ok := pg_temp.ok(r) and r2 ->> 'error' = 'unauthorized' and r3 ->> 'error' = 'unauthorized' and pg_temp.ok(r4)
        and not (select active from plant_managers where id = v_new)
        and not exists (select 1 from plant_managers where name = 'ST owner 3')
        and pg_temp.ok(r5);                                          -- he may see the list
  perform pg_temp.rec('step 46 accounts: the team leader adds / removes owner accounts; the owner cannot (he only sees the list)', ok,
    concat_ws(' | ', left(r::text, 60), r2::text, r3::text, r4::text, left(r5::text, 40)));
  delete from plant_managers where name = 'ST owner 2';
end $$;
$gt64$;
    v_step := 'step 46: the owner only watches — every changing function refuses his session';
    execute $gt65$
-- ── step 46: the owner only watches — every changing function refuses his session ──
do $$
declare q text; r jsonb; bad text[] := '{}'; v_set jsonb := (select settings from settings_pilot where id = 1);
        o text := pg_temp.v('owner'); d text := pg_temp.devid('LEGS');
begin
  foreach q in array array[
    format('select push_settings(%L::jsonb, ''x'', %L)', '{"dailyTarget":7}', o),
    format('select reset_daily_board(%L, ''owner try'')', o),
    format('select processing_day_close(%L, 1, ''parts'', ''owner try'')', o),
    format('select support_access_set(%L, 2, ''owner try'')', o),
    format('select device_unpair(%L, %L, ''owner try'')', o, d),
    format('select device_manage(%L, %L, ''retire'', ''owner try'')', o, d),
    format('select device_pair(%L, ''123456'', ''parts'', 0, false, ''x'')', o),
    format('select device_auth_set(%L, true)', o),
    format('select manager_add(%L, ''x'', ''xxxxxxxx'')', o),
    format('select manager_add_owner(%L, ''x'', ''xxxxxxxx'')', o),
    format('select manager_deactivate(%L, %L)', o, pg_temp.v('mgr_id')),
    format('select support_force_reload(%L, ''owner try'')', o),
    pg_temp.q_claim(977, 'slaughter', 'slaughtered', 'x', 'x'),
    pg_temp.q_push(977, '{"slaughter":"slaughtered","slaughter_time":1}')]
  loop
    r := pg_temp.api3(jsonb_build_object('x-manager-token', o), '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}', q);
    if pg_temp.ok(r) then bad := bad || left(q, 60); end if;
  end loop;
  if (select settings from settings_pilot where id = 1) is distinct from v_set then bad := bad || 'settings changed'::text; end if;
  if (pg_temp.ar(977)).slaughter is not null then bad := bad || 'animal 977 written'::text; end if;
  perform pg_temp.rec('step 46 owner: view only — every changing function refuses an owner session (settings, reset, processing day, support access, devices, accounts, rulings)',
    array_length(bad, 1) is null, array_to_string(bad, ' | '));
end $$;
$gt65$;
    v_step := 'step 46: one worker list per screen';
    execute $gt66$
-- ── step 46: one worker list per screen ─────────────────────────────────────
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; ok boolean; s0 jsonb;
begin
  select settings into s0 from settings_pilot where id = 1;
  delete from login_attempts;
  update settings_pilot set settings = settings || jsonb_build_object(
      'users', coalesce(settings -> 'users', '[]'::jsonb) || jsonb_build_array(
         jsonb_build_object('name', 'Only Inner', 'role', 'inner', 'codeHash', encode(digest('gt-worker:620001', 'sha256'), 'hex')),
         jsonb_build_object('name', 'Both Sides', 'role', 'inner', 'codeHash', encode(digest('gt-worker:620002', 'sha256'), 'hex')),
         jsonb_build_object('name', 'Both Sides', 'role', 'outer', 'codeHash', encode(digest('gt-worker:620002', 'sha256'), 'hex')),
         jsonb_build_object('name', 'Legs Man', 'role', 'legs', 'codeHash', encode(digest('gt-worker:620003', 'sha256'), 'hex'))),
      'loginModeByRole', coalesce(settings -> 'loginModeByRole', '{}'::jsonb) || '{"inner":"code","outer":"code","legs":"code","stamps":"code"}'::jsonb)
   where id = 1;
  r  := pg_temp.api(pg_temp.dev('OUT2'), 'select worker_login(''outer'', ''620001'')');     -- an inner inspector at the outer screen
  r2 := pg_temp.api(pg_temp.dev('IN1'),  'select worker_login(''inner'', ''620001'')');
  r3 := pg_temp.api(pg_temp.dev('OUT2'), 'select worker_login(''outer'', ''620002'')');     -- on both lists, the same code
  r4 := pg_temp.api(pg_temp.dev('STAMPS'), 'select worker_login(''stamps'', ''620003'')');  -- legs worker at the stamps screen
  r5 := pg_temp.api(pg_temp.dev('OUT2'), 'select worker_login(''inner'', ''620001'')');     -- asking for another screen than the tablet's
  ok := r ->> 'error' = 'code_invalid' and pg_temp.ok(r2) and pg_temp.ok(r3) and r3 ->> 'name' = 'Both Sides'
        and r4 ->> 'error' = 'code_invalid' and r5 ->> 'error' = 'wrong_station';
  perform pg_temp.rec('step 46 worker lists per screen: an inner inspector cannot log in at the outer screen, a legs worker not at stamps; the same person on two lists can',
    ok, concat_ws(' | ', r::text, left(r2::text, 50), left(r3::text, 60), r4::text, r5::text));
  -- the old shared lists are refused when saved again
  r := pg_temp.api(pg_temp.mgr(), format('select push_settings(%L::jsonb, ''x'', %L)', '{"users":[{"name":"Old","role":"inspector"}]}', pg_temp.v('mgr')));
  ok := r ->> 'error' = 'bad_settings' and not exists (select 1 from settings_pilot s, jsonb_array_elements(s.settings -> 'users') u where u ->> 'name' = 'Old');
  perform pg_temp.rec('step 46 worker lists: the old shared lists (inspector / supervisor) are refused', ok, r::text);
  update settings_pilot set settings = s0 where id = 1;
  delete from login_attempts;
end $$;
$gt66$;
    v_step := 'step 46 (5th review): the owner / view-only manufacturer on a STATION tablet';
    execute $gt67$
-- ── step 46 (5th review): the owner / view-only manufacturer on a STATION tablet ──
-- A station tablet writes for its station on its own; a view-only session that comes
-- through it must not borrow those rights (and cannot log in there at all).
do $$
declare
  spec text[][] := array[
    array['SL1','950','none','slaughter','slaughtered'], array['ESO1','951','slaughter','eso','ok'],
    array['IN1','952','slaughter','inner_start','in_progress'], array['OUT2','953','inner','outer','glatt'],
    array['LEGS','954','slaughter','push','{"legs_stickers":true,"head_stickers":true}'],
    array['PARTS','955','outer','push','{"parts_print_count":1,"parts_printed_as":"glatt"}'],
    array['STAMPS','956','outer','stamped','true']];
  i int; v_id int; q text; r jsonb; r2 jsonb; r3 jsonb; bad text[] := '{}'; before jsonb; s0 jsonb;
  oid_ uuid := (select id from plant_managers where name = 'selftest owner');
  fid uuid := (select id from plant_managers where role = 'manufacturer' and name = 'selftest maker');
  ot text; ft text; dev text;
begin
  update settings_pilot set settings = settings || '{"esophagusEnabled":true}'::jsonb where id = 1;
  update plant_state set value = (now() - interval '1 minute')::text where key = 'supportAccessUntil';
  perform set_config('gt.reset_in_progress', 'true', true);
  update animals_pilot set slaughter = null, slaughter_time = null, inner_status = null, inner_time = null, outer_status = null, outer_time = null,
         eso_result = null, eso_checked = false, legs_stickers = false, head_stickers = false, parts_print_count = 0, stamped = false
   where id between 950 and 956;
  update animals_pilot set eso_result = 'ok', eso_checked = true where id in (952, 953, 954, 955, 956);   -- esophagus passed
  perform set_config('gt.reset_in_progress', 'false', true);
  delete from animals_carry; delete from processing_day_closed;                                  -- no earlier day waiting
  for i in 1 .. array_length(spec, 1) loop
    v_id := spec[i][2]::int; dev := spec[i][1];
    if spec[i][3] <> 'none' then perform pg_temp.prep(v_id, spec[i][3]); end if;
    q := case when spec[i][4] = 'push' then pg_temp.q_push(v_id, spec[i][5]::jsonb)
              else pg_temp.q_claim(v_id, spec[i][4], spec[i][5], '', '') end;
    insert into manager_sessions (manager_id, device_id) values (oid_, pg_temp.devid(dev)) returning token into ot;
    insert into manager_sessions (manager_id, device_id) values (fid, pg_temp.devid(dev)) returning token into ft;
    s0 := (select settings from settings_pilot where id = 1);
    before := to_jsonb(pg_temp.ar(v_id));
    -- owner session on this station tablet: the station write, a station settings key (header and p_token)
    r  := pg_temp.api(pg_temp.dev(dev) || jsonb_build_object('x-manager-token', ot), q);
    r2 := pg_temp.api(pg_temp.dev(dev) || jsonb_build_object('x-manager-token', ot),
                      format('select push_settings(''{"printers":{"owner_on_station":1}}''::jsonb, ''x'', %L)', ot));
    r3 := pg_temp.api(pg_temp.dev(dev), format('select push_settings(''{"printers":{"owner_on_station":1}}''::jsonb, ''x'', %L)', ot));
    if pg_temp.wrote(r) or pg_temp.ok(r2) or pg_temp.ok(r3) then bad := bad || ('owner on ' || dev); end if;
    -- view-only manufacturer session on this station tablet
    r  := pg_temp.api(pg_temp.dev(dev) || jsonb_build_object('x-manager-token', ft), q);
    r2 := pg_temp.api(pg_temp.dev(dev) || jsonb_build_object('x-manager-token', ft),
                      format('select push_settings(''{"printers":{"maker_on_station":1}}''::jsonb, ''x'', %L)', ft));
    if pg_temp.wrote(r) or pg_temp.ok(r2) then bad := bad || ('manufacturer on ' || dev); end if;
    if to_jsonb(pg_temp.ar(v_id)) is distinct from before then bad := bad || ('row changed at ' || dev); end if;
    if (select settings from settings_pilot where id = 1) is distinct from s0 then bad := bad || ('settings changed at ' || dev); end if;
    -- control: the same station write from the tablet alone is accepted (the test is not vacuous)
    r := pg_temp.api(pg_temp.dev(dev), q);
    if not pg_temp.wrote(r) then bad := bad || ('control failed at ' || dev || ': ' || left((r - 'row')::text, 160)); end if;
  end loop;
  perform pg_temp.rec('step 46 owner / view-only manufacturer on every station tablet: no ruling, no station write, no settings (the tablet alone still works)',
    array_length(bad, 1) is null, array_to_string(bad, ' | '));
end $$;
$gt67$;
    v_step := 'the owner / manufacturer cannot log in from a station tablet at all';
    execute $gt68$
-- the owner / manufacturer cannot log in from a station tablet at all
do $$
declare r jsonb; r2 jsonb; r3 jsonb; ok boolean;
begin
  insert into plant_managers (name, code_hash, role) values ('ST station owner', crypt('st-station-owner-1', gen_salt('bf')), 'owner');
  delete from login_attempts;
  r  := pg_temp.api(pg_temp.dev('OUT2'), 'select manager_login(''st-station-owner-1'')');
  r2 := pg_temp.api(pg_temp.dev('SL1'), format('select manager_login(%L)', pg_temp.v('maker_code')));
  r3 := pg_temp.api('{}', 'select manager_login(''st-station-owner-1'')');
  ok := r ->> 'reason' = 'station_device' and r2 ->> 'reason' = 'station_device' and pg_temp.ok(r3)
        and exists (select 1 from events_pilot where stage = 'security' and action = 'login_on_station_device');
  perform pg_temp.rec('step 46 the owner / manufacturer cannot log in from a station tablet (elsewhere the owner can)', ok,
    concat_ws(' | ', r::text, r2::text, left(r3::text, 60)));
  delete from manager_sessions where manager_id = (select id from plant_managers where name = 'ST station owner');
  delete from plant_managers where name = 'ST station owner';
  delete from login_attempts;
end $$;
$gt68$;
    v_step := 'a pairing request alone never makes a station; recovery disconnects every team-leader devi';
    execute $gt69$
-- a pairing request alone never makes a station; recovery disconnects every team-leader device
do $$
declare r jsonb; ok boolean; v_new text := 'gtselftest_req_' || substr(md5(random()::text), 1, 6); a text; b text; ta text; tb text; v_s text;
begin
  r := pg_temp.api('{}', format('select device_request_pairing(%L, ''selftest-secret-123456'', ''req only'')', v_new));
  ok := pg_temp.ok(r) and not exists (select 1 from devices_pilot where id = v_new and assigned_role is not null)
        and not exists (select 1 from device_credentials where device_id = v_new);
  -- two team-leader devices, a session on each → recovery clears both
  a := 'gtselftest_ldA_' || substr(md5(random()::text), 1, 6); b := 'gtselftest_ldB_' || substr(md5(random()::text), 1, 6);
  perform set_config('app.device_admin', 'on', true);
  insert into devices_pilot (id, device_name, assigned_role, assigned_index, device_status, paired_at) values
    (a, 'ld A', 'leader', 0, 'active', now()), (b, 'ld B', 'leader', 1, 'active', now());
  insert into device_credentials (device_id, token_hash) values (a, md5(a)), (b, md5(b));
  perform set_config('app.device_admin', '', true);
  insert into manager_sessions (manager_id, device_id) values ((pg_temp.v('mgr_id'))::uuid, a) returning token into ta;
  insert into manager_sessions (manager_id, device_id) values ((pg_temp.v('mgr_id'))::uuid, b) returning token into tb;
  v_s := leader_device_recovery('selftest: both lost');
  ok := ok and v_s like 'ok — 2 %'
        and not exists (select 1 from devices_pilot where id in (a, b) and assigned_role is not null)
        and not exists (select 1 from device_credentials where device_id in (a, b) and not revoked)
        and not exists (select 1 from manager_sessions where token in (ta, tb))
        and not exists (select 1 from plant_state where key = 'leaderDevicesRequired');
  perform pg_temp.rec('step 46 a pairing request alone makes no station; recovery disconnects every team-leader device (keys, sessions, flag)', ok,
    concat_ws(' | ', left(r::text, 60), v_s));
  insert into plant_state (key, value) values ('leaderDevicesRequired', '1') on conflict (key) do update set value = '1';
end $$;
$gt69$;
    v_step := 'shared inner + outer screen';
    execute $gtn0$
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean; s0 jsonb; tok text;
begin
  -- ── one shared screen for the inner and the outer check ──
  select settings into s0 from settings_pilot where id = 1;
  delete from login_attempts;
  update settings_pilot set settings = settings || jsonb_build_object('screenConfig', '1both', 'esophagusEnabled', false,
      'users', coalesce(settings -> 'users', '[]'::jsonb) || jsonb_build_array(
         jsonb_build_object('name', 'Inspector 1b', 'role', 'inner', 'codeHash', encode(digest('gt-worker:620101', 'sha256'), 'hex')),
         jsonb_build_object('name', 'Outer Only 1b', 'role', 'outer', 'codeHash', encode(digest('gt-worker:620102', 'sha256'), 'hex'))),
      'loginModeByRole', coalesce(settings -> 'loginModeByRole', '{}'::jsonb) || '{"inner":"code","outer":"code"}'::jsonb) where id = 1;
  perform pg_temp.prep(997, 'inner'); perform pg_temp.prep(998, 'inner'); perform pg_temp.prep(996, 'inner');
  r  := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(997, 'outer', 'glatt', '', ''));
  r2 := pg_temp.api(pg_temp.dev('IN1'), format('select set_not_chalak_outer(998, %s)', pg_temp.ep()));
  r3 := pg_temp.api(pg_temp.dev('IN1'), 'select worker_login(''inner'', ''620102'')');      -- not on the shared screen's list
  r4 := pg_temp.api(pg_temp.dev('IN1'), 'select worker_login(''inner'', ''620101'')');      -- on it: inner + outer
  tok := r4 ->> 'token';
  perform pg_temp.api(pg_temp.dev('IN1') || jsonb_build_object('x-worker-token', tok), pg_temp.q_claim(996, 'outer', 'glatt', '', ''));
  ok := pg_temp.claimed(r) and (pg_temp.ar(997)).outer_status = 'glatt' and pg_temp.ok(r2) and (pg_temp.ar(998)).not_chalak_outer
        and r3 ->> 'error' = 'code_invalid' and pg_temp.ok(r4) and (pg_temp.ar(996)).outer_by = 'Inspector 1b';
  -- any other configuration: each station its own stage again
  update settings_pilot set settings = settings || '{"screenConfig":"1in1out"}'::jsonb where id = 1;
  perform pg_temp.prep(999, 'inner');
  r2 := pg_temp.api(pg_temp.dev('IN1'), pg_temp.q_claim(999, 'outer', 'glatt', '', ''));
  ok := ok and r2 ->> 'error' = 'wrong_station' and (pg_temp.ar(999)).outer_status is null;
  perform pg_temp.rec('shared inner + outer screen (the plant''s choice): the inner tablet rules outer and sends to the rabbinate; one worker list for the one screen, its worker named on the outer ruling; otherwise inner tablet → inner only', ok,
    concat_ws(' | ', left(r::text, 60), r3::text, left(r4::text, 50), (pg_temp.ar(996)).outer_by, r2::text));
  update settings_pilot set settings = s0 where id = 1;
  delete from login_attempts;
end $$;
$gtn0$;
    v_step := 'team-leader device replacement';
    execute $gtn1$
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; ok boolean; v_code text; a text; ta text; i int;
begin
  -- ── a lost team-leader device: replaced with the team-leader code + the recovery code ──
  delete from login_attempts;
  r  := pg_temp.api3('{}', '{"role":"authenticated","sub":"11111111-1111-1111-1111-111111111111"}', format('select leader_recovery_code_new(%L)', pg_temp.v('owner')));
  r2 := pg_temp.api('{}', format('select leader_recovery_code_new(%L)', pg_temp.v('mgr')));
  v_code := r2 ->> 'code';
  r3 := pg_temp.api('{}', format('select leader_recovery_status(%L)', pg_temp.v('mgr')));
  ok := r ->> 'error' = 'unauthorized' and pg_temp.ok(r2) and v_code ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$'
        and (r3 ->> 'exists')::boolean and (select value from plant_state where key = 'leaderRecoveryHash') !~ v_code;
  -- the team leader's (lost) device, still paired, a session on it
  a := 'gtselftest_ldR_' || substr(md5(random()::text), 1, 6);
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = null, assigned_index = null where assigned_role = 'leader';
  insert into devices_pilot (id, device_name, assigned_role, assigned_index, device_status, paired_at) values (a, 'lost TL phone', 'leader', 0, 'active', now());
  insert into device_credentials (device_id, token_hash) values (a, md5(a));
  perform set_config('app.device_admin', '', true);
  insert into plant_state (key, value) values ('leaderDevicesRequired', '1') on conflict (key) do update set value = '1';
  insert into manager_sessions (manager_id, device_id) values ((pg_temp.v('mgr_id'))::uuid, a) returning token into ta;
  r  := pg_temp.api(pg_temp.dev('SL1'), format('select leader_device_replace(%L, %L)', pg_temp.v('mgr_code'), v_code));     -- from a station tablet
  r2 := pg_temp.api('{}', format('select leader_device_replace(%L, %L)', pg_temp.v('mgr_code'), 'AAAA-BBBB-CCCC'));          -- wrong recovery code
  r3 := pg_temp.api('{}', format('select leader_device_replace(%L, %L)', 'not-the-leader-code', v_code));                   -- wrong team-leader code
  r4 := pg_temp.api('{}', format('select leader_device_replace(%L, %L)', pg_temp.v('mgr_code'), lower(v_code)));           -- right (case / dashes do not matter)
  r5 := pg_temp.api('{}', format('select leader_device_replace(%L, %L)', pg_temp.v('mgr_code'), v_code));                  -- used up
  ok := ok and r ->> 'reason' = 'station_device' and r2 ->> 'reason' = 'code_invalid' and r3 ->> 'reason' = 'code_invalid'
        and pg_temp.ok(r4) and (r4 ->> 'replaced')::boolean and (r4 ->> 'registerLeaderDevice')::boolean
        and (select assigned_role from devices_pilot where id = a) is null
        and not exists (select 1 from device_credentials where device_id = a and not revoked)
        and not exists (select 1 from manager_sessions where token = ta)
        and not exists (select 1 from plant_state where key = 'leaderRecoveryHash')
        and r5 ->> 'reason' = 'no_recovery_code'
        and exists (select 1 from events_pilot where stage = 'security' and action = 'leader_device_replaced');
  -- guessing is braked: 5 wrong tries an hour
  delete from login_attempts;
  perform pg_temp.api('{}', format('select leader_recovery_code_new(%L)', pg_temp.v('mgr')));
  for i in 1 .. 5 loop r := pg_temp.api('{}', format('select leader_device_replace(%L, %L)', pg_temp.v('mgr_code'), 'WRONG' || i)); end loop;
  r := pg_temp.api('{}', format('select leader_device_replace(%L, %L)', pg_temp.v('mgr_code'), 'WRONG6'));
  ok := ok and r ->> 'reason' = 'locked';
  perform pg_temp.rec('team-leader device lost: replaced with the team-leader code + the recovery code (team leader makes it; not from a station tablet; wrong codes refused and braked; old device disconnected; the code is used once)', ok,
    concat_ws(' | ', r2::text, r3::text, left(r4::text, 80), r5::text, r::text));
  delete from login_attempts;
  insert into plant_state (key, value) values ('leaderDevicesRequired', '1') on conflict (key) do update set value = '1';
end $$;
$gtn1$;
    v_step := 'standby server and UPS';
    execute $gtn9$
do $$
declare r jsonb; r2 jsonb; r3 jsonb; r4 jsonb; ok boolean;
begin
  -- the plant-server tools report: a standby is expected but none streams; the UPS runs on battery
  insert into plant_state (key, value) values ('standbyExpected', '1'), ('upsStatus', 'onbattery'), ('upsAt', now()::text), ('lastFailoverAt', now()::text)
    on conflict (key) do update set value = excluded.value;
  r  := pg_temp.api('{}', format('select system_health(%L)', pg_temp.v('mgr')));
  r2 := pg_temp.api('{}', format('select plant_server_status(%L)', pg_temp.v('mgr')));
  r3 := pg_temp.api(pg_temp.dev('SL1'), 'select plant_server_status(''x'')');
  update plant_state set value = 'lowbattery' where key = 'upsStatus';
  r4 := pg_temp.api('{}', format('select system_health(%L)', pg_temp.v('mgr')));
  ok := r -> 'attention' ? 'standby_down' and r -> 'attention' ? 'ups_on_battery' and r -> 'info' ? 'failover_recent'
        and pg_temp.ok(r2) and r2 ->> 'role' = 'primary' and (r2 ->> 'standbyExpected')::boolean and r2 #>> '{ups,status}' = 'onbattery'
        and r3 ->> 'error' = 'unauthorized' and r4 -> 'attention' ? 'ups_low_battery' and not (r4 -> 'attention' ? 'ups_on_battery');
  delete from plant_state where key in ('standbyExpected', 'upsStatus', 'upsAt', 'lastFailoverAt');
  r := pg_temp.api('{}', format('select system_health(%L)', pg_temp.v('mgr')));
  ok := ok and not (r -> 'attention' ? 'standby_down') and not (r -> 'attention' ? 'ups_on_battery');
  perform pg_temp.rec('standby server and UPS: health warns (standby expected but not streaming, UPS on battery / low battery, a recent failover); the status only for team leader / owner', ok,
    concat_ws(' | ', r2::text, r3::text));
end $$
$gtn9$;
    v_step := 'the ACTIVE security surface against the expected manifest';
    execute $gt70$
-- ── the ACTIVE security surface against the expected manifest ───────────────
-- (the same queries print the whole surface in tools/active-security-manifest.sql)
do $$
declare x record; problems text[] := '{}';
begin
  -- 1. guard triggers that must exist and be enabled
  for x in select * from (values
      ('animals_pilot', 'a_animals_merge', '_animals_merge'),
      ('animals_pilot', 'a_animals_merge_ins', '_animals_merge'),
      ('animals_pilot', 'b_animals_stage_guard', '_animals_stage_guard'),
      ('animals_pilot', 'trg_animals_pilot_guard_corrections', 'animals_pilot_guard_corrections'),
      ('animals_pilot', 'trg_animals_pilot_advance_cursor', 'animals_pilot_advance_cursor'),
      ('animals_pilot', 'zz_device_write_guard', '_device_write_guard'),
      ('animals_pilot', 'zzz_nc_outer_guard', '_animals_nc_outer_guard'),
      ('animals_pilot', 'zzz_outer_open_guard', '_animals_outer_open_guard'),
      ('animals_pilot', 'zzzz_nc_outer_value', '_animals_nc_outer_value'),
      ('events_pilot', 'a0_events_maker_guard', '_events_maker_guard'),
      ('events_pilot', 'a1_events_actor', '_events_actor'),
      ('events_pilot', 'aa_events_chain_link', '_events_chain_link'),
      ('events_pilot', 'ab_events_append_only', '_events_append_only'),
      ('events_pilot', 'zz_device_write_guard', '_device_write_guard'),
      ('devices_pilot', 'zz_devices_assignment_guard', '_devices_assignment_guard'),
      ('devices_pilot', 'zz_worker_sessions_revoke', '_worker_sessions_revoke_on_device'),
      ('device_credentials', 'credential_revoked_at', '_credential_revoked_at'),
      ('device_credentials', 'zz_worker_sessions_revoke', '_worker_sessions_revoke_on_credential'),
      ('device_credentials', 'zz_credential_audit', '_credential_audit'),
      ('settings_pilot', 'zz_settings_hash_worker_codes', '_settings_hash_worker_codes'),
      ('plant_state', 'zz_test_mode_audit', '_plant_state_test_mode_trg')) t(tbl, trg, fn) loop
    if not exists (select 1 from pg_trigger g join pg_proc p on p.oid = g.tgfoid
                    where g.tgrelid = ('public.' || x.tbl)::regclass and g.tgname = x.trg and p.proname = x.fn and g.tgenabled <> 'D') then
      problems := array_append(problems, 'trigger missing/disabled: ' || x.tbl || '.' || x.trg);
    end if;
  end loop;
  -- 2. row security on, and exactly the expected policies on the app's tables
  for x in select * from (values ('animals_pilot'), ('settings_pilot'), ('events_pilot'), ('daily_board_archive'),
                                 ('devices_pilot'), ('device_lifecycle_events'), ('plants')) t(tbl) loop
    if to_regclass('public.' || x.tbl) is not null and not (select relrowsecurity from pg_class where oid = ('public.' || x.tbl)::regclass) then
      problems := array_append(problems, 'row security off: ' || x.tbl);
    end if;
  end loop;
  for x in select p.tablename, p.policyname, p.cmd, p.qual, e.want
             from pg_policies p
             left join (values ('animals_pilot', 'read animals_pilot', '_reader_ok()'),
                               ('settings_pilot', 'read settings_pilot', '_reader_ok()'),
                               ('daily_board_archive', 'read daily_board_archive', '_reader_ok()'),
                               ('events_pilot', 'read events_pilot', 'gt_rls.events_reader_ok()'),
                               ('device_lifecycle_events', 'read device_lifecycle_events', 'gt_rls.events_reader_ok()'),
                               ('devices_pilot', 'read devices_pilot', 'gt_rls.devices_read_own_ids()'),
                               ('plants', 'plants probe: no rows', 'false')) e(tbl, pol, want)
                    on e.tbl = p.tablename and e.pol = p.policyname
            where p.schemaname = 'public'
              and p.tablename in ('animals_pilot','settings_pilot','daily_board_archive','events_pilot','device_lifecycle_events','devices_pilot','plants') loop
    if x.want is null or x.cmd <> 'SELECT' or position(x.want in x.qual) = 0 then
      problems := array_append(problems, 'unexpected policy: ' || x.tablename || ' / ' || x.policyname || ' / ' || x.cmd);
    end if;
  end loop;
  for x in select * from (values ('animals_pilot', 'read animals_pilot'), ('settings_pilot', 'read settings_pilot'),
                                 ('daily_board_archive', 'read daily_board_archive'), ('events_pilot', 'read events_pilot'),
                                 ('device_lifecycle_events', 'read device_lifecycle_events'), ('devices_pilot', 'read devices_pilot')) t(tbl, pol) loop
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = x.tbl and policyname = x.pol) then
      problems := array_append(problems, 'policy missing: ' || x.tbl || ' / ' || x.pol);
    end if;
  end loop;
  -- 3. table rights of the app roles: exactly these (anything else = unexpected grant)
  for x in select ro.r as grantee, c.relname as table_name, pv.p as privilege_type
             from pg_class c join pg_namespace n on n.oid = c.relnamespace
             cross join (values ('anon'), ('authenticated')) ro(r)
             cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) pv(p)
            where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
              and has_table_privilege(ro.r, c.oid, pv.p)
              and not (pv.p = 'SELECT' and c.relname in ('animals_pilot','settings_pilot','daily_board_archive','events_pilot',
                                                         'device_lifecycle_events','devices_pilot','plants')) loop
    problems := array_append(problems, 'unexpected table grant: ' || x.grantee || ' ' || x.privilege_type || ' ' || x.table_name);
  end loop;
  for x in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'S'
              and (has_sequence_privilege('anon', c.oid, 'USAGE') or has_sequence_privilege('authenticated', c.oid, 'USAGE')) loop
    problems := array_append(problems, 'unexpected sequence grant: ' || x.relname);
  end loop;
  -- server-only functions (credentials, accounts, recovery): never callable by the app roles
  for x in select f from unnest(array['manufacturer_set_code(text,text)', 'leader_account_add(text,text)', 'leader_account_remove(text)',
                                      'leader_device_recovery(text)', '_set_setup_code(text)']) f loop
    if to_regprocedure(x.f) is null then problems := array_append(problems, 'server-only function missing: ' || x.f);
    elsif has_function_privilege('anon', x.f, 'execute') or has_function_privilege('authenticated', x.f, 'execute') then
      problems := array_append(problems, 'server-only function callable by the app: ' || x.f); end if;
  end loop;
  -- 4. functions the app roles may run: exactly the API (extension functions aside)
  for x in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'gt_rls')
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
              and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
              and p.oid::regprocedure::text not in (
                'animal_push(jsonb,uuid)', 'archive_days(text,date,date)', 'claim_animal_stage(integer,text,text,text,text,bigint)',
                'claim_animal_stage(integer,text,text,text,text,bigint,uuid)', 'create_first_manager(text,text,text)',
                'device_auth_set(text,boolean)', 'device_heartbeat(text,text,jsonb)', 'device_manage(text,text,text,text)',
                'device_pair(text,text,text,integer,boolean,text,text)', 'device_paired_list(text)', 'device_pairing_status(text,text,text)',
                'device_request_pairing(text,text,text)', 'device_unpair(text,text,text)', 'device_whoami()',
                'eso_change(integer,text,text,bigint)', 'eso_change(integer,text,text,bigint,uuid)', 'event_append(jsonb)',
                'lung_drawing_get(integer)', 'lung_drawing_set(integer,bigint,text)', 'manager_add(text,text,text)',
                'manager_add_owner(text,text,text)', 'manager_deactivate(text,uuid)', 'manager_list(text)', 'manager_login(text)',
                'manager_logout(text)', 'manager_session_check(text)', 'leader_recovery_code_new(text)', 'leader_recovery_status(text)', 'leader_device_replace(text,text)', 'plant_server_status(text)', 'manufacturer_set_billing(text,boolean,numeric,text,text)',
                'outer_open(integer,bigint,boolean,text)', 'outer_open(integer,bigint,boolean,text,uuid)', 'plant_status_snapshot()', 'plant_setup_needed()',
                'push_settings(jsonb,text,text,text)', 'request_daily_rollover()', 'reset_daily_board(text,text)', 'security_summary(text)',
                'processing_board(text)', 'carry_push(bigint,jsonb,uuid)', 'carry_claim(bigint,integer,text,uuid)',
                'processing_day_close(text,bigint,text,text)', 'processing_status(text)',
                'server_now_ms()', 'server_schema_step()', 'server_test_mode()', 'server_test_mode_info()', 'set_not_chalak_outer(integer,bigint,uuid)', 'support_access_set(text,integer,text)',
                'support_diagnostics(text)', 'support_force_reload(text,text)', 'system_health(text)', 'verify_event_chain()', 'worker_login(text,text,text)',
                'worker_logout(text)', 'worker_session_check()', '_reader_ok()',
                'gt_rls.devices_read_all()', 'gt_rls.devices_read_own_ids()', 'gt_rls.events_reader_ok()') loop
    problems := array_append(problems, 'unexpected function grant: ' || x.sig);
  end loop;
  for x in select * from (values ('animal_push(jsonb,uuid)'), ('event_append(jsonb)'), ('set_not_chalak_outer(integer,bigint,uuid)'),
                                 ('claim_animal_stage(integer,text,text,text,text,bigint)'), ('gt_rls.devices_read_own_ids()'),
                                 ('gt_rls.events_reader_ok()'), ('gt_rls.devices_read_all()'), ('_reader_ok()')) t(sig) loop
    if not has_function_privilege('anon', x.sig, 'execute') then problems := array_append(problems, 'API function not callable: ' || x.sig); end if;
  end loop;
  -- 5. every security-definer function has a fixed search_path; none owned by an app role
  for x in select p.oid::regprocedure::text as sig, p.proconfig, pg_get_userbyid(p.proowner) as owner
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'gt_rls') and p.prosecdef
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') loop
    if not coalesce(array_to_string(x.proconfig, ',') like '%search_path=%', false) then
      problems := array_append(problems, 'security definer without search_path: ' || x.sig); end if;
    if x.owner in ('anon', 'authenticated', 'authenticator') then
      problems := array_append(problems, 'owned by an app role: ' || x.sig); end if;
  end loop;
  -- 6. no function still falls back to the tablet's own word for its identity
  for x in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f'
              and pg_get_functiondef(p.oid) ~ 'coalesce\(_current_device_id\(\),\s*(nullif\()?(left\()?p_device_id' loop
    problems := array_append(problems, 'device-id fallback left in: ' || x.sig);
  end loop;
  perform pg_temp.rec('ACTIVE security surface matches the expected manifest (triggers, policies, grants, definer settings)',
    array_length(problems, 1) is null, array_to_string(problems, ' ; '));
end $$;
$gt70$;

    -- the result (read before everything is undone)
    v_step := 'result';
    raise notice '%', rpad('=', 100, '=');
    raise notice 'GlattTrack security self-test  (schema step %)', (select value from plant_state where key = 'schemaStep');
    raise notice '%', rpad('=', 100, '=');
    for v_test, v_ok, v_detail in
        select e ->> 'test', (e ->> 'ok')::boolean, e ->> 'detail'
          from jsonb_array_elements(current_setting('gt_st.results')::jsonb) e loop
      if v_ok then raise notice 'PASS  %', v_test;
      else raise notice 'FAIL  %   ::  %', v_test, left(coalesce(v_detail, ''), 600); end if;
    end loop;
    select count(*), count(*) filter (where not (e ->> 'ok')::boolean)
      into v_n, v_fail from jsonb_array_elements(current_setting('gt_st.results')::jsonb) e;
    select string_agg(f.t, ' | ' order by f.k) into v_names
      from (select e ->> 'test' as t, k from jsonb_array_elements(current_setting('gt_st.results')::jsonb) with ordinality x(e, k)
             where not (e ->> 'ok')::boolean order by k limit 8) f;
    raise notice '%', rpad('-', 100, '-');
    raise notice '% checks, % passed, % failed  (nothing was changed — all undone)', v_n, v_n - v_fail, v_fail;
    raise exception 'gt_selftest_undo';
  exception when others then
    if sqlerrm <> 'gt_selftest_undo' then
      raise exception 'GlattTrack security self-test stopped at "%": %  (nothing was changed)', v_step, sqlerrm;
    end if;
  end;
  if v_fail > 0 then
    raise exception 'GlattTrack security self-test FAILED — % of % checks: %  (nothing was changed)', v_fail, v_n, v_names;
  end if;
  execute format('prepare gt_selftest_result as select %L::text', format('PASSED — %s of %s security checks (nothing was changed)', v_n, v_n));
end $gt_selftest$;

-- the result as one row (the SQL Editor shows no notices); PASSED only when the
-- statement above passed in this session — a failure is the ERROR above
select coalesce((select substring(statement from $p$'(PASSED[^']*)'$p$) from pg_prepared_statements where name = 'gt_selftest_result'),
                'NOT PASSED — see the error above') as "GlattTrack security self-test";
