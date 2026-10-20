-- GlattTrack support center — self-test. Changes nothing (every change is undone inside it).
-- Expected result (one row): PASSED — 32 of 32 support-center checks (nothing was changed)
-- ONE statement (one DO block), no temporary table: the Supabase SQL Editor runs it like psql does
-- (the same way as the plant's 03). Works on an empty center and on one that already has plants and staff.
do $$
declare r jsonb; r2 jsonb; tok text; sec text; ok boolean; v int; cid bigint;
  res jsonb := '[]'; me text := current_user; n_all int; n_bad int; x jsonb;
begin
  perform set_config('search_path', 'public, extensions, pg_temp', true);
  execute $f$create function pg_temp.rec(p_name text, p_ok boolean, p_detail text default null) returns void language plpgsql as $b$
    begin perform set_config('gt_sc.results', (coalesce(nullif(current_setting('gt_sc.results', true), ''), '[]')::jsonb
            || jsonb_build_array(jsonb_build_object('name', p_name, 'ok', coalesce(p_ok, false), 'detail', p_detail)))::text, true); end $b$ $f$;
  perform set_config('gt_sc.results', '[]', true);
  begin   -- everything in this block is undone at its end
  -- other admins are put aside for the test (undone), so "the last admin" can be checked on a center in use too
  update sc_staff set active = false where role = 'admin' and active;
  insert into sc_staff (name, code_hash) values ('selftest staff', crypt('selftest-staff-code-1', gen_salt('bf', 6)));
  -- as the app (anon): no table, no internal function
  perform set_config('role', 'anon', true);
  begin perform 1 from sc_plants limit 1; ok := false; exception when insufficient_privilege then ok := true; end;
  begin perform 1 from sc_status limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform 1 from sc_staff limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform _sc_check_silent(); ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  perform pg_temp.rec('the app reads no table and calls no internal function', ok);
  -- staff login
  r := sc_login('wrong'); r2 := sc_login('selftest-staff-code-1'); tok := r2 ->> 'token';
  perform pg_temp.rec('staff login: wrong code refused, right code → session', r ->> 'error' = 'code_invalid' and (r2 ->> 'ok')::boolean, r::text);
  r := sc_overview('nope');
  perform pg_temp.rec('overview without a session refused', r ->> 'error' = 'unauthorized');
  -- a plant
  r := sc_plant_add(tok, '9001', 'Selftest plant'); sec := r ->> 'secret';
  r2 := sc_plant_add(tok, '9001', 'again');
  perform pg_temp.rec('a plant is added once; its secret is given once', (r ->> 'ok')::boolean and length(sec) = 36 and r2 ->> 'error' = 'code_taken', r::text);
  r2 := sc_plant_add(tok, '9003', E'Plant\nURGENT: call +1 555');
  perform pg_temp.rec('round-3 C-L1: a plant name with a new line / control character is refused (it goes into the alerts)', r2 ->> 'error' = 'bad_value', r2::text);
  -- reports
  r := sc_report('9001', 'not-the-secret', '{"attention":[]}');
  r2 := sc_report('9001', sec, '{"attention":[],"appVersion":"v10.35","working":true,"tablets":[]}');
  perform pg_temp.rec('report: wrong secret refused; right one → green', r ->> 'error' = 'unauthorized' and r2 ->> 'level' = 'ok', r2::text);
  perform set_config('role', me, true);
  r := sc_report('9001', sec, '{"attention":["standby_down","devices_offline"],"working":false}');
  v := (select count(*) from sc_alerts where code = '9001' and resolved_at is null);
  r2 := sc_report('9001', sec, '{"attention":["standby_down","devices_offline"],"working":false}');
  perform pg_temp.rec('a new problem → red + one alert per problem (not again on the next report)',
    r ->> 'level' = 'bad' and v = 2 and (select count(*) from sc_alerts where code = '9001' and resolved_at is null) = 2
    and exists (select 1 from sc_alerts where code = '9001' and text = 'standby_down' and level = 'bad')
    and exists (select 1 from sc_alerts where code = '9001' and text = 'devices_offline' and level = 'warn'), r::text);
  r := sc_report('9001', sec, '{"attention":[],"working":true,"tablets":[{"role":"legs","online":false}]}');
  perform pg_temp.rec('a tablet offline while the plant works → orange', r ->> 'level' = 'warn', r::text);
  r := sc_report('9001', sec, '{"attention":[],"working":false}');
  perform pg_temp.rec('the problem is gone → green, alerts closed', r ->> 'level' = 'ok'
    and not exists (select 1 from sc_alerts where code = '9001' and resolved_at is null));
  -- silent plant
  update sc_status set reported_at = now() - interval '20 minutes' where code = '9001';
  v := _sc_check_silent(); r := sc_overview(tok);
  perform pg_temp.rec('a plant silent 15 minutes → red "no_report" + one alert',
    v >= 1 and _sc_check_silent() = 0 and (select p -> 'problems' ? 'no_report' from jsonb_array_elements(r -> 'plants') p where p ->> 'code' = '9001'), r::text);
  -- commands and release
  r := sc_command_add(tok, '9001', 'rm -rf /'); r2 := sc_command_add(tok, '9001', 'restart_standby'); cid := (r2 ->> 'id')::bigint;
  perform pg_temp.rec('only known commands', r ->> 'error' = 'bad_value' and (r2 ->> 'ok')::boolean);
  r := sc_release_set(tok, 'v10.36', 'http://x/app.html', repeat('a', 64), null, null, '{"v":1,"version":"v10.36","app":"' || repeat('a', 64) || '","sql":null}', repeat('A', 86) || '==');
  r2 := sc_release_set(tok, 'v10.36', 'https://example.com/app.html', repeat('a', 64), null, null, '{"v":1,"version":"v10.36","app":"' || repeat('a', 64) || '","sql":null}', repeat('A', 86) || '==');
  -- (round-2 review P-up1) no signature / a signed text that does not match the release → refused
  x := sc_release_set(tok, 'v10.36', 'https://example.com/app.html', repeat('a', 64), null, null, null, null);
  ok := x ->> 'error' = 'not_signed'
        and sc_release_set(tok, 'v10.36', 'https://example.com/app.html', repeat('a', 64), null, null, '{"v":1,"version":"v10.36","app":"' || repeat('b', 64) || '","sql":null}', repeat('A', 86) || '==') ->> 'error' = 'not_signed'
        and sc_release_set(tok, 'v10.37', 'https://example.com/app.html', repeat('a', 64), null, null, '{"v":1,"version":"v10.36","app":"' || repeat('a', 64) || '","sql":null}', repeat('A', 86) || '==') ->> 'error' = 'not_signed';
  perform pg_temp.rec('a release needs https, a sha256 and the manufacturer''s signature (the signed text must match it)', r ->> 'error' = 'bad_value' and (r2 ->> 'ok')::boolean and ok);
  r := sc_report('9001', sec, '{"attention":[]}');
  r2 := sc_report('9001', sec, '{"attention":[]}');
  perform pg_temp.rec('the plant gets the command once and the release',
    jsonb_array_length(r -> 'commands') = 1 and r -> 'commands' -> 0 ->> 'cmd' = 'restart_standby' and jsonb_array_length(r2 -> 'commands') = 0
    and r -> 'release' ->> 'version' = 'v10.36' and r -> 'release' ->> 'appSha256' = repeat('a', 64)
    and r -> 'release' ->> 'sig' = repeat('A', 86) || '==' and (r -> 'release' ->> 'manifest')::jsonb ->> 'version' = 'v10.36', r::text);
  r := sc_command_done('9001', 'bad', cid, 'x'); r2 := sc_command_done('9001', sec, cid, 'restarted');
  perform pg_temp.rec('command done only with the plant secret', r ->> 'error' = 'unauthorized'
    and (select result from sc_commands where id = cid) = 'restarted');
  -- (round-2 review C-cmd1) a command whose answer was lost is sent again after 15 minutes; a done one never
  r2 := sc_command_add(tok, '9001', 'reload_tablets'); v := (r2 ->> 'id')::bigint;
  perform sc_report('9001', sec, '{"attention":[]}');
  update sc_commands set delivered_at = now() - interval '20 minutes' where id in (v, cid);
  r := sc_report('9001', sec, '{"attention":[]}');
  perform pg_temp.rec('round-2 review: a command not answered is sent again after 15 minutes; a done one is not',
    exists (select 1 from jsonb_array_elements(r -> 'commands') c where (c ->> 'id')::bigint = v)
    and not exists (select 1 from jsonb_array_elements(r -> 'commands') c where (c ->> 'id')::bigint = cid), r::text);
  perform sc_command_done('9001', sec, v, 'ok');
  -- notifications: e-mail / SMS / WhatsApp, each on or off
  r := sc_notify_set(tok, '{"email":{"on":true,"to":["not-an-email"]}}');
  r2 := sc_notify_set(tok, '{"email":{"on":true,"to":["support@example.com"]},"sms":{"on":false,"to":["+972501234567"]},"whatsapp":{"on":true,"to":["+972501234567"]},"minLevel":"warn"}');
  perform pg_temp.rec('notifications: each channel on / off; addresses checked',
    r ->> 'error' = 'bad_value' and (r2 -> 'settings' -> 'whatsapp' ->> 'on')::boolean and not (r2 -> 'settings' -> 'sms' ->> 'on')::boolean
    and r2 -> 'settings' ->> 'minLevel' = 'warn', r2::text);
  -- ── v10.38: the manufacturer center ──
  -- staff with roles (the admin adds them); the last admin cannot be removed
  r  := sc_staff_add(tok, 'Selftest support', 'selftest-support-code-1', 'support');
  r2 := sc_staff_add(tok, 'Selftest finance', 'selftest-finance-code-1', 'finance');
  perform sc_staff_add(tok, 'Selftest viewer', 'selftest-viewer-code-1', 'viewer');
  perform pg_temp.rec('staff: the admin adds a member with a role; a short code is refused; the last admin stays',
    (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean and sc_staff_add(tok, 'x', 'short', 'viewer') ->> 'error' = 'code_too_short'
    and sc_staff_set(tok, (select id from sc_staff where name = 'selftest staff'), 'viewer') ->> 'error' = 'last_admin', r::text);
  declare tsup text := sc_login('selftest-support-code-1') ->> 'token'; tfin text := sc_login('selftest-finance-code-1') ->> 'token';
          tview text := sc_login('selftest-viewer-code-1') ->> 'token';
  begin
    perform pg_temp.rec('roles: finance sees billing only; viewer sees all and changes nothing; support no billing / staff',
      sc_overview(tfin) ->> 'error' = 'unauthorized' and (sc_billing(tfin) ->> 'ok')::boolean
      and (sc_overview(tview) ->> 'ok')::boolean and (sc_billing(tview) ->> 'ok')::boolean
      and sc_command_add(tview, '9001', 'reload_tablets') ->> 'error' = 'unauthorized' and sc_billing_set(tview, '9001', 'kg', 1) ->> 'error' = 'unauthorized'
      and sc_billing(tsup) ->> 'error' = 'unauthorized' and sc_staff_list(tsup) ->> 'error' = 'unauthorized' and sc_plant_add(tsup, '9002', 'x') ->> 'error' = 'unauthorized'
      and (sc_command_add(tsup, '9001', 'reload_tablets') ->> 'ok')::boolean and sc_staff_add(tfin, 'x', 'selftest-xxxx-code', 'admin') ->> 'error' = 'unauthorized');
    -- (owner) a forgotten code: A. the admin gives a new code (the old one stops); B. an admin's one-time recovery code
    declare rr jsonb; rc text; sid uuid := (select id from sc_staff where name = 'Selftest viewer');
    begin
      rr := sc_staff_add(tok, 'Selftest admin2', 'selftest-admin2-code-1', 'admin'); rc := rr ->> 'recovery';
      perform pg_temp.rec('owner A: the admin gives a staff member a new code — the old code stops, the new one works; only the admin; at least 10 characters',
        sc_staff_set_code(tok, sid, 'short') ->> 'error' = 'code_too_short'
        and sc_staff_set_code(tsup, sid, 'selftest-viewer-code-2') ->> 'error' = 'unauthorized'
        and (sc_staff_set_code(tok, sid, 'selftest-viewer-code-2') ->> 'ok')::boolean
        and sc_login('selftest-viewer-code-1') ->> 'error' = 'code_invalid' and (sc_login('selftest-viewer-code-2') ->> 'ok')::boolean
        and sc_overview(tview) ->> 'error' = 'unauthorized', rr::text);
      perform pg_temp.rec('owner B: a new admin gets a recovery code once; with it (any case, with or without dashes) they set a new code — once only; a wrong one counts as a wrong try',
        rc ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$'
        and sc_recover('AAAA-BBBB-CCCC-DDDD', 'selftest-admin2-code-2') ->> 'error' = 'code_invalid'
        and sc_recover(rc, 'short') ->> 'error' = 'code_too_short'
        and (sc_recover(lower(replace(rc, '-', '')), 'selftest-admin2-code-2') ->> 'ok')::boolean
        and sc_recover(rc, 'selftest-admin2-code-3') ->> 'error' = 'code_invalid'
        and sc_login('selftest-admin2-code-1') ->> 'error' = 'code_invalid' and (sc_login('selftest-admin2-code-2') ->> 'ok')::boolean
        and (sc_staff_add(tok, 'Selftest support2', 'selftest-support2-code', 'support') ? 'recovery') is false, rc);
      rr := sc_recovery_new(tok);
      perform pg_temp.rec('owner B: an admin makes their own recovery code (shown once); not support / finance',
        (rr ->> 'recovery') ~ '^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$' and (sc_recovery_status(tok) ->> 'has')::boolean
        and sc_recovery_new(tsup) ->> 'error' = 'unauthorized' and sc_recovery_new(tfin) ->> 'error' = 'unauthorized'
        and not has_function_privilege('anon', '_sc_recovery_code()', 'execute'), rr::text);
    end;
    -- the plant's problem reports become tickets (once); the plant gets their status back
    r := sc_report('9001', sec, '{"attention":[],"issues":[{"key":"E17","at":"2026-10-15T10:00:00Z","source":"station","screen":"legs","message":"printer stuck"},{"key":"L3","source":"leader","message":"tablet 2 slow"}],"usage":[{"day":"2026-09-01","animals":100,"kg":30000},{"day":"2026-09-02","animals":50,"kg":15000.5}]}');
    r2 := sc_report('9001', sec, '{"attention":[],"issues":[{"key":"E17","message":"printer stuck"}],"usage":[{"day":"2026-09-02","animals":60,"kg":18000}]}');
    perform pg_temp.rec('reports: problem reports → tickets once; daily totals kept (the last one of a day wins); no issues / usage kept in the status',
      (select count(*) from sc_tickets where code = '9001') = 2 and jsonb_array_length(r2 -> 'tickets') = 2
      and (select sum(animals) from sc_usage where code = '9001') = 160 and not ((select report from sc_status where code = '9001') ? 'issues'), r2::text);
    r := sc_ticket_set(tview, '9001', 'E17', 'working');
    r2 := sc_ticket_set(tsup, '9001', 'E17', 'working', 'on it');
    perform pg_temp.rec('a ticket: support takes it (status, note, who); the viewer cannot; the plant sees the new status',
      r ->> 'error' = 'unauthorized' and (r2 ->> 'ok')::boolean
      and (select status = 'working' and assignee = 'Selftest support' and jsonb_array_length(notes) = 1 from sc_tickets where code = '9001' and key = 'E17')
      and exists (select 1 from jsonb_array_elements(sc_report('9001', sec, '{"attention":[]}') -> 'tickets') t where t ->> 'key' = 'E17' and t ->> 'status' = 'working'), r2::text);
    -- billing: by kg / by animal / monthly, with a monthly minimum; paid / not paid
    perform sc_billing_set(tfin, '9001', 'kg', 0.02);
    r := sc_billing(tfin, '2026-09');
    perform sc_billing_set(tfin, '9001', 'animal', 3, 1000);
    r2 := sc_billing(tfin, '2026-09');
    perform pg_temp.rec('billing: by kg (48,000 kg × 0.02 = 960), by animal with a minimum (160 × 3 = 480 → 1,000); bad values refused',
      (select y ->> 'amount' from jsonb_array_elements(r -> 'rows') y where y ->> 'code' = '9001')::numeric = 960 and (select y ->> 'amount' from jsonb_array_elements(r2 -> 'rows') y where y ->> 'code' = '9001')::numeric = 1000
      and sc_billing_set(tfin, '9001', 'hours', 1) ->> 'error' = 'bad_value' and sc_billing_set(tfin, '9001', 'kg', -1) ->> 'error' = 'bad_value', r::text || ' | ' || r2::text);
    perform sc_billing_set(tfin, '9001', 'monthly', 2500);
    r := sc_paid_set(tfin, '9001', '2026-09', true);
    r2 := sc_billing(tfin, '2026-09');
    perform pg_temp.rec('billing: a fixed monthly sum; marked paid by finance (audited)',
      (select y ->> 'amount' from jsonb_array_elements(r2 -> 'rows') y where y ->> 'code' = '9001')::numeric = 2500 and (select y ->> 'paid' from jsonb_array_elements(r2 -> 'rows') y where y ->> 'code' = '9001')::boolean
      and exists (select 1 from sc_audit where action = 'paid_set' and who = 'Selftest finance'), r2::text);
  end;
  -- (round 23) a report with wrong types (a bad date, a word for a number, attention not a list) is still taken
  r := sc_report('9001', sec, '{"attention":"x","working":"yes","tablets":"none","issues":[{"key":"E900","at":"not-a-date","message":"bad date"},{"key":"E901","message":"good one"}],"usage":[{"day":"2026-08-01","animals":"many","kg":1},{"day":"2026-08-02","animals":7,"kg":70}]}');
  perform pg_temp.rec('a report with wrong types is still taken: a bad date → the time it arrived; a bad number line is skipped; the rest kept',
    (r ->> 'ok')::boolean and exists (select 1 from sc_tickets where code = '9001' and key = 'E901')
    and exists (select 1 from sc_tickets where code = '9001' and key = 'E900' and at > now() - interval '1 minute')
    and (select animals from sc_usage where code = '9001' and day = '2026-08-02') = 7, r::text);
  -- (review) a month that does not exist is refused, not a crash; wrong codes lock only their own address
  perform pg_temp.rec('a month that does not exist (2026-13) is refused',
    sc_billing(tok, '2026-13') ->> 'error' = 'bad_value' and sc_paid_set(tok, '9001', '2026-00', true) ->> 'error' = 'bad_value');
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.9"}', true);
  perform sc_login('selftest-wrong-code') from generate_series(1, 11);
  r := sc_login('selftest-staff-code-1');
  perform set_config('request.headers', '{"x-forwarded-for":"198.51.100.7, 10.0.0.1"}', true);
  r2 := sc_login('selftest-staff-code-1');
  perform set_config('request.headers', '', true);
  perform pg_temp.rec('wrong codes lock only the address that typed them; the rest of the team still logs in',
    r ->> 'error' = 'rate_limited' and (r2 ->> 'ok')::boolean, r::text || ' | ' || r2::text);
  -- (full review C2) the address is the platform's, not the one the caller wrote first
  perform set_config('request.headers', '{"x-forwarded-for":"1.1.1.1, 192.0.2.44"}', true);
  perform sc_login('selftest-wrong-code') from generate_series(1, 11);
  perform set_config('request.headers', '{"x-forwarded-for":"2.2.2.2, 192.0.2.44"}', true);
  r := sc_login('selftest-staff-code-1');
  perform set_config('request.headers', '{"cf-connecting-ip":"192.0.2.45","x-forwarded-for":"192.0.2.44"}', true);
  r2 := sc_login('selftest-staff-code-1');
  perform set_config('request.headers', '', true);
  perform pg_temp.rec('full review C2: a made-up first x-forwarded-for address does not escape the limit; the platform address counts',
    r ->> 'error' = 'rate_limited' and (r2 ->> 'ok')::boolean, r::text || ' | ' || r2::text);
  -- (full review C3) a plant that never reported (added 3 days ago) → "no_report"; "on" must be true / false
  insert into sc_plants (code, name, secret_hash, created_at) values ('9077', 'selftest silent', 'x', now() - interval '3 days');
  v := _sc_check_silent();
  r := sc_notify_set(tok, '{"email":{"on":"yes","to":[]}}');
  perform pg_temp.rec('full review C3: a plant that never reported gets "no_report"; a non-boolean "on" is bad_value',
    exists (select 1 from sc_alerts where code = '9077' and text = 'no_report' and resolved_at is null) and r ->> 'error' = 'bad_value', r::text);
  -- (full review C4) a plant held out of the automatic release gets it only with "update this plant now"
  r := sc_plant_hold(tok, '9001', true);
  r2 := sc_report('9001', sec, '{"attention":[]}');
  perform sc_command_add(tok, '9001', 'update_now');
  x := sc_report('9001', sec, '{"attention":[]}');
  perform sc_plant_hold(tok, '9001', false);
  perform pg_temp.rec('full review C4: a held plant gets no automatic release; "update this plant now" brings it',
    (r ->> 'ok')::boolean and (r2 -> 'release' is null or r2 -> 'release' = 'null'::jsonb) and x -> 'release' ->> 'version' is not null,
    concat_ws(' | ', r::text, left(r2::text, 120), left(x::text, 160)));
  perform set_config('role', 'anon', true);
  begin perform 1 from sc_tickets limit 1; ok := false; exception when insufficient_privilege then ok := true; end;
  begin perform 1 from sc_usage limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform 1 from sc_billing limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform _sc_can('x', 'staff'); ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  perform set_config('role', me, true);
  perform pg_temp.rec('the app reads no ticket / usage / billing table and calls no internal role check', ok);
    res := coalesce(nullif(current_setting('gt_sc.results', true), ''), '[]')::jsonb;
    raise exception using errcode = 'GTUND', message = 'undo the self-test';
  exception when sqlstate 'GTUND' then null;
  end;
  select count(*), count(*) filter (where not (e ->> 'ok')::boolean) into n_all, n_bad from jsonb_array_elements(res) e;
  for x in select e from jsonb_array_elements(res) e loop
    raise notice '%', '  ' || case when (x ->> 'ok')::boolean then 'PASS ' else 'FAIL ' end || (x ->> 'name') || coalesce('  :: ' || left(x ->> 'detail', 200), '');
  end loop;
  if n_all = 0 then raise exception 'support-center self-test did not run'; end if;
  if n_bad > 0 then
    raise exception 'support-center self-test FAILED — % of % checks: %  (nothing was changed)', n_bad, n_all,
      (select string_agg(e ->> 'name', ' | ') from jsonb_array_elements(res) e where not (e ->> 'ok')::boolean);
  end if;
  raise notice 'PASSED — % of % support-center checks (nothing was changed)', n_all, n_all;
  if exists (select 1 from pg_prepared_statements where name = 'gt_sc_selftest_result') then deallocate gt_sc_selftest_result; end if;
  execute format('prepare gt_sc_selftest_result as select %L::text', format('PASSED — %s of %s support-center checks (nothing was changed)', n_all, n_all));
end $$;

-- the result as one row (the Supabase SQL Editor shows no notices); PASSED only when the
-- block above passed in this session — a failure is the ERROR above
select coalesce((select substring(statement from $p$'(PASSED[^']*)'$p$) from pg_prepared_statements where name = 'gt_sc_selftest_result'),
                'NOT PASSED — see the error above') as "GlattTrack support-center self-test";
