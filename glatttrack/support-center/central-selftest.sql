-- GlattTrack support center — self-test. Changes nothing (everything rolled back).
-- Expected last line: PASSED — N of N support-center checks (nothing was changed)
begin;
set local search_path = public, extensions;
create temp table sc_t (n serial, name text, ok boolean, detail text);
grant all on sc_t to public; grant usage, select on sequence sc_t_n_seq to public;
do $$
declare r jsonb; r2 jsonb; tok text; sec text; ok boolean; v int; cid bigint;
  procedure_dummy int;
begin
  insert into sc_staff (name, code_hash) values ('selftest staff', crypt('selftest-staff-code-1', gen_salt('bf', 6)));
  -- as the app (anon): no table, no internal function
  perform set_config('role', 'anon', true);
  begin perform 1 from sc_plants limit 1; ok := false; exception when insufficient_privilege then ok := true; end;
  begin perform 1 from sc_status limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform 1 from sc_staff limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform _sc_check_silent(); ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  insert into sc_t (name, ok) values ('the app reads no table and calls no internal function', ok);
  -- staff login
  r := sc_login('wrong'); r2 := sc_login('selftest-staff-code-1'); tok := r2 ->> 'token';
  insert into sc_t (name, ok, detail) values ('staff login: wrong code refused, right code → session', r ->> 'error' = 'code_invalid' and (r2 ->> 'ok')::boolean, r::text);
  r := sc_overview('nope');
  insert into sc_t (name, ok) values ('overview without a session refused', r ->> 'error' = 'unauthorized');
  -- a plant
  r := sc_plant_add(tok, '9001', 'Selftest plant'); sec := r ->> 'secret';
  r2 := sc_plant_add(tok, '9001', 'again');
  insert into sc_t (name, ok, detail) values ('a plant is added once; its secret is given once', (r ->> 'ok')::boolean and length(sec) = 36 and r2 ->> 'error' = 'code_taken', r::text);
  -- reports
  r := sc_report('9001', 'not-the-secret', '{"attention":[]}');
  r2 := sc_report('9001', sec, '{"attention":[],"appVersion":"v10.35","working":true,"tablets":[]}');
  insert into sc_t (name, ok, detail) values ('report: wrong secret refused; right one → green', r ->> 'error' = 'unauthorized' and r2 ->> 'level' = 'ok', r2::text);
  perform set_config('role', 'postgres', true);
  r := sc_report('9001', sec, '{"attention":["standby_down","devices_offline"],"working":false}');
  v := (select count(*) from sc_alerts where code = '9001' and resolved_at is null);
  r2 := sc_report('9001', sec, '{"attention":["standby_down","devices_offline"],"working":false}');
  insert into sc_t (name, ok, detail) values ('a new problem → red + one alert per problem (not again on the next report)',
    r ->> 'level' = 'bad' and v = 2 and (select count(*) from sc_alerts where code = '9001' and resolved_at is null) = 2
    and exists (select 1 from sc_alerts where code = '9001' and text = 'standby_down' and level = 'bad')
    and exists (select 1 from sc_alerts where code = '9001' and text = 'devices_offline' and level = 'warn'), r::text);
  r := sc_report('9001', sec, '{"attention":[],"working":true,"tablets":[{"role":"legs","online":false}]}');
  insert into sc_t (name, ok, detail) values ('a tablet offline while the plant works → orange', r ->> 'level' = 'warn', r::text);
  r := sc_report('9001', sec, '{"attention":[],"working":false}');
  insert into sc_t (name, ok) values ('the problem is gone → green, alerts closed', r ->> 'level' = 'ok'
    and not exists (select 1 from sc_alerts where code = '9001' and resolved_at is null));
  -- silent plant
  update sc_status set reported_at = now() - interval '20 minutes' where code = '9001';
  v := _sc_check_silent(); r := sc_overview(tok);
  insert into sc_t (name, ok, detail) values ('a plant silent 15 minutes → red "no_report" + one alert',
    v = 1 and _sc_check_silent() = 0 and (select p -> 'problems' ? 'no_report' from jsonb_array_elements(r -> 'plants') p where p ->> 'code' = '9001'), r::text);
  -- commands and release
  r := sc_command_add(tok, '9001', 'rm -rf /'); r2 := sc_command_add(tok, '9001', 'restart_standby'); cid := (r2 ->> 'id')::bigint;
  insert into sc_t (name, ok) values ('only known commands', r ->> 'error' = 'bad_value' and (r2 ->> 'ok')::boolean);
  r := sc_release_set(tok, 'v10.36', 'http://x/app.html', repeat('a', 64));
  r2 := sc_release_set(tok, 'v10.36', 'https://example.com/app.html', repeat('a', 64));
  insert into sc_t (name, ok) values ('a release needs https and a sha256', r ->> 'error' = 'bad_value' and (r2 ->> 'ok')::boolean);
  r := sc_report('9001', sec, '{"attention":[]}');
  r2 := sc_report('9001', sec, '{"attention":[]}');
  insert into sc_t (name, ok, detail) values ('the plant gets the command once and the release',
    jsonb_array_length(r -> 'commands') = 1 and r -> 'commands' -> 0 ->> 'cmd' = 'restart_standby' and jsonb_array_length(r2 -> 'commands') = 0
    and r -> 'release' ->> 'version' = 'v10.36' and r -> 'release' ->> 'appSha256' = repeat('a', 64), r::text);
  r := sc_command_done('9001', 'bad', cid, 'x'); r2 := sc_command_done('9001', sec, cid, 'restarted');
  insert into sc_t (name, ok) values ('command done only with the plant secret', r ->> 'error' = 'unauthorized'
    and (select result from sc_commands where id = cid) = 'restarted');
  -- notifications: e-mail / SMS / WhatsApp, each on or off
  r := sc_notify_set(tok, '{"email":{"on":true,"to":["not-an-email"]}}');
  r2 := sc_notify_set(tok, '{"email":{"on":true,"to":["support@example.com"]},"sms":{"on":false,"to":["+972501234567"]},"whatsapp":{"on":true,"to":["+972501234567"]},"minLevel":"warn"}');
  insert into sc_t (name, ok, detail) values ('notifications: each channel on / off; addresses checked',
    r ->> 'error' = 'bad_value' and (r2 -> 'settings' -> 'whatsapp' ->> 'on')::boolean and not (r2 -> 'settings' -> 'sms' ->> 'on')::boolean
    and r2 -> 'settings' ->> 'minLevel' = 'warn', r2::text);
  -- ── v10.38: the manufacturer center ──
  -- staff with roles (the admin adds them); the last admin cannot be removed
  r  := sc_staff_add(tok, 'Selftest support', 'selftest-support-code-1', 'support');
  r2 := sc_staff_add(tok, 'Selftest finance', 'selftest-finance-code-1', 'finance');
  perform sc_staff_add(tok, 'Selftest viewer', 'selftest-viewer-code-1', 'viewer');
  insert into sc_t (name, ok, detail) values ('staff: the admin adds a member with a role; a short code is refused; the last admin stays',
    (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean and sc_staff_add(tok, 'x', 'short', 'viewer') ->> 'error' = 'code_too_short'
    and sc_staff_set(tok, (select id from sc_staff where name = 'selftest staff'), 'viewer') ->> 'error' = 'last_admin', r::text);
  declare tsup text := sc_login('selftest-support-code-1') ->> 'token'; tfin text := sc_login('selftest-finance-code-1') ->> 'token';
          tview text := sc_login('selftest-viewer-code-1') ->> 'token';
  begin
    insert into sc_t (name, ok) values ('roles: finance sees billing only; viewer sees all and changes nothing; support no billing / staff',
      sc_overview(tfin) ->> 'error' = 'unauthorized' and (sc_billing(tfin) ->> 'ok')::boolean
      and (sc_overview(tview) ->> 'ok')::boolean and (sc_billing(tview) ->> 'ok')::boolean
      and sc_command_add(tview, '9001', 'reload_tablets') ->> 'error' = 'unauthorized' and sc_billing_set(tview, '9001', 'kg', 1) ->> 'error' = 'unauthorized'
      and sc_billing(tsup) ->> 'error' = 'unauthorized' and sc_staff_list(tsup) ->> 'error' = 'unauthorized' and sc_plant_add(tsup, '9002', 'x') ->> 'error' = 'unauthorized'
      and (sc_command_add(tsup, '9001', 'reload_tablets') ->> 'ok')::boolean and sc_staff_add(tfin, 'x', 'selftest-xxxx-code', 'admin') ->> 'error' = 'unauthorized');
    -- the plant's problem reports become tickets (once); the plant gets their status back
    r := sc_report('9001', sec, '{"attention":[],"issues":[{"key":"E17","at":"2026-10-15T10:00:00Z","source":"station","screen":"legs","message":"printer stuck"},{"key":"L3","source":"leader","message":"tablet 2 slow"}],"usage":[{"day":"2026-09-01","animals":100,"kg":30000},{"day":"2026-09-02","animals":50,"kg":15000.5}]}');
    r2 := sc_report('9001', sec, '{"attention":[],"issues":[{"key":"E17","message":"printer stuck"}],"usage":[{"day":"2026-09-02","animals":60,"kg":18000}]}');
    insert into sc_t (name, ok, detail) values ('reports: problem reports → tickets once; daily totals kept (the last one of a day wins); no issues / usage kept in the status',
      (select count(*) from sc_tickets where code = '9001') = 2 and jsonb_array_length(r2 -> 'tickets') = 2
      and (select sum(animals) from sc_usage where code = '9001') = 160 and not ((select report from sc_status where code = '9001') ? 'issues'), r2::text);
    r := sc_ticket_set(tview, '9001', 'E17', 'working');
    r2 := sc_ticket_set(tsup, '9001', 'E17', 'working', 'on it');
    insert into sc_t (name, ok, detail) values ('a ticket: support takes it (status, note, who); the viewer cannot; the plant sees the new status',
      r ->> 'error' = 'unauthorized' and (r2 ->> 'ok')::boolean
      and (select status = 'working' and assignee = 'Selftest support' and jsonb_array_length(notes) = 1 from sc_tickets where code = '9001' and key = 'E17')
      and exists (select 1 from jsonb_array_elements(sc_report('9001', sec, '{"attention":[]}') -> 'tickets') t where t ->> 'key' = 'E17' and t ->> 'status' = 'working'), r2::text);
    -- billing: by kg / by animal / monthly, with a monthly minimum; paid / not paid
    perform sc_billing_set(tfin, '9001', 'kg', 0.02);
    r := sc_billing(tfin, '2026-09');
    perform sc_billing_set(tfin, '9001', 'animal', 3, 1000);
    r2 := sc_billing(tfin, '2026-09');
    insert into sc_t (name, ok, detail) values ('billing: by kg (48,000 kg × 0.02 = 960), by animal with a minimum (160 × 3 = 480 → 1,000); bad values refused',
      (r -> 'rows' -> 0 ->> 'amount')::numeric = 960 and (r2 -> 'rows' -> 0 ->> 'amount')::numeric = 1000
      and sc_billing_set(tfin, '9001', 'hours', 1) ->> 'error' = 'bad_value' and sc_billing_set(tfin, '9001', 'kg', -1) ->> 'error' = 'bad_value', r::text || ' | ' || r2::text);
    perform sc_billing_set(tfin, '9001', 'monthly', 2500);
    r := sc_paid_set(tfin, '9001', '2026-09', true);
    r2 := sc_billing(tfin, '2026-09');
    insert into sc_t (name, ok, detail) values ('billing: a fixed monthly sum; marked paid by finance (audited)',
      (r2 -> 'rows' -> 0 ->> 'amount')::numeric = 2500 and (r2 -> 'rows' -> 0 ->> 'paid')::boolean
      and exists (select 1 from sc_audit where action = 'paid_set' and who = 'Selftest finance'), r2::text);
  end;
  perform set_config('role', 'anon', true);
  begin perform 1 from sc_tickets limit 1; ok := false; exception when insufficient_privilege then ok := true; end;
  begin perform 1 from sc_usage limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform 1 from sc_billing limit 1; ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  begin perform _sc_can('x', 'staff'); ok := ok and false; exception when insufficient_privilege then ok := ok and true; end;
  perform set_config('role', 'postgres', true);
  insert into sc_t (name, ok) values ('the app reads no ticket / usage / billing table and calls no internal role check', ok);
end $$;
do $$ declare t int; f int; lst text; begin
  select count(*), count(*) filter (where not ok) into t, f from sc_t;
  for lst in select '  ' || case when ok then 'PASS ' else 'FAIL ' end || name || coalesce('  :: ' || left(detail, 200), '') from sc_t order by n loop raise notice '%', lst; end loop;
  if f > 0 then raise exception 'support-center self-test FAILED — % of % checks', f, t; end if;
  raise notice 'PASSED — % of % support-center checks (nothing was changed)', t, t;
end $$;
rollback;
