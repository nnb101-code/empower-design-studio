-- ============================================================================
-- GlattTrack — step 44: the app can ask whether the server test flag is on
-- ============================================================================
-- The plant owner's rule: the team leader never rules. Only when the owner's
-- single-phone test flag is on on the server (plant_state 'testMode' = 'on',
-- set with SQL / the service key only — see step 43) may a team-leader session
-- act as the stations. The app shows its "test mode: all stations on this
-- device" button ONLY when this function answers true.
--
--   server_test_mode() → boolean     (read-only; anyone may ask; changes nothing)
--
-- To switch the flag (SQL editor / plant server only, never through the app):
--   update plant_state set value = 'on'  where key = 'testMode';   -- owner's test
--   update plant_state set value = 'off' where key = 'testMode';   -- normal work
-- Safe to run more than once. Run after step 43.
-- ============================================================================

insert into plant_state (key, value) values ('testMode', 'off') on conflict (key) do nothing;

create or replace function server_test_mode() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select _test_mode_on();
$$;
revoke execute on function server_test_mode() from public;
grant execute on function server_test_mode() to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '44')
  on conflict (key) do update
    set value = case when plant_state.value ~ '^\d+$' and plant_state.value::int > 44 then plant_state.value else '44' end,
        updated_at = now();

-- ── self-check ──────────────────────────────────────────────────────────────
do $$
declare problems text[] := '{}'; v_prev text;
begin
  if not has_function_privilege('anon', 'server_test_mode()', 'execute') then
    problems := problems || 'server_test_mode() not callable by the app'::text; end if;
  if exists (select 1 from pg_proc where oid = 'server_test_mode()'::regprocedure and provolatile <> 's') then
    problems := problems || 'server_test_mode() is not read-only (stable)'::text; end if;
  select value into v_prev from plant_state where key = 'testMode';
  begin
    update plant_state set value = 'on' where key = 'testMode';
    if server_test_mode() is not true then problems := problems || 'flag on → not true'::text; end if;
    update plant_state set value = 'off' where key = 'testMode';
    if server_test_mode() is not false then problems := problems || 'flag off → not false'::text; end if;
    raise exception 'gt_selftest44_rollback';
  exception when others then
    if sqlerrm <> 'gt_selftest44_rollback' then problems := problems || ('self-test error: ' || sqlerrm); end if;
  end;
  if (select value from plant_state where key = 'testMode') is distinct from v_prev then
    problems := problems || 'self-check changed the test flag'::text; end if;
  if (select value from plant_state where key = 'schemaStep') !~ '^\d+$'
     or (select value from plant_state where key = 'schemaStep')::int < 44 then
    problems := problems || 'schemaStep not 44'::text; end if;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 44 self-check FAILED: %', array_to_string(problems, ' | ');
  end if;
  raise notice 'GlattTrack step 44 self-check OK';
end $$;

notify pgrst, 'reload schema';
