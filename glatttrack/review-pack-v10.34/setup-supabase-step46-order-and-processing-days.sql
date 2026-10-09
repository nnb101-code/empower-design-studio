-- ============================================================================
-- GlattTrack — step 46: stage order on the server, each station its own stage,
-- kashrut configuration locks, and processing that continues over several days
-- ============================================================================
--   1. STAGE ORDER (server, every write path: claim_animal_stage, animal_push,
--      the offline esophagus path, carry_push / carry_claim):
--        slaughter → esophagus (when the plant uses the esophagus check)
--                  → inner (lungs) → outer (last ruling) → legs sort / parts /
--                  stamps / weights
--      A number that has not reached a station cannot be ruled there:
--        esophagus : the animal was slaughtered (slaughtered / not chalak) and
--                    no inner / outer ruling exists yet (a "nevela" from the
--                    esophagus after the lungs were checked is refused)
--        inner     : slaughtered (slaughtered / not chalak), not nevela / shot,
--                    and — when the esophagus check applies to this number —
--                    the esophagus check passed ("ok")
--        outer     : the inner check is confirmed
--        legs / head stickers : slaughtered (+ esophagus passed when it applies)
--        legs sort, parts, stamps : the outer inspector ruled
--        weights   : the outer inspector ruled (or the inner check was treif)
--      Refused: {claimed|ok:false, error:'out_of_order', reason:'not_slaughtered' |
--      'eso_not_passed' | 'later_stage_started' | 'inner_not_confirmed' | 'outer_not_ruled'}
--      (animal_push: GT:OUT_OF_ORDER → error 'out_of_order', reason, the server row).
--   2. EACH STATION RULES ONLY ITS OWN STAGE: an inner tablet rules inner only,
--      an outer tablet rules outer only (step ≤ 45 let either rule both).
--      The rabbinate send (set_not_chalak_outer): outer tablet only, as before —
--      and only for an animal that reached the outer inspector (inner confirmed).
--      It is routing to the rabbinate screen, not a ruling: there רבנות חלק / רבנות כשר /
--      טרף (v10.17, §25); a shochet / maw "not chalak" stays רבנות כשר / טרף only.
--   3. KASHRUT CONFIGURATION:
--      • the manufacturer (support access open) may change technical settings
--        only (printers, scanners, beep, language, weight capture, error log);
--        statuses, workers, login modes, screens … are ignored for him.
--      • the team leader may define statuses, but may not change whether a status
--        is kosher, or delete it, while an animal on an open board carries it —
--        that would change rulings already made (error 'status_in_use').
--   4. PROCESSING OVER SEVERAL DAYS (no skipping, ever):
--      The daily reset still empties the screens for a new slaughter day. Every
--      slaughter day whose processing is not finished (legs / parts / stamps)
--      is kept on the server in animals_carry (one "board" per reset, linked to
--      its daily_board_archive row). Each processing station works strictly in
--      order: its oldest unfinished board first; it cannot touch a newer board —
--      nor today's board — until the older one is done for that station
--      (error 'earlier_day_open'). A board done for every station is written
--      back into its archive row and leaves animals_carry.
--        processing_board(p_station)            the station's current board (oldest unfinished) + its rows
--        carry_push(p_board, p_rows, p_command_id)   like animal_push, processing columns only
--        carry_claim(p_board, p_id, p_stage, p_command_id)   legs sort / stamped first claim
--        processing_day_close(p_token, p_board, p_station, p_reason)   team leader: close a board
--                                               for a station (what is left will not be processed), audited
--        processing_status(p_token)             team leader / owner: every open board, pending per station
--   5. DAILY ROLLOVER: never empties a board while work is going on (the 3-hour
--      forced reset is gone), and waits while a slaughtered animal has not
--      reached its last ruling (status 'waiting_unfinished'; system_health:
--      attention 'rollover_waiting'). The team leader's manual reset (an
--      emergency tool) stops too while such animals exist:
--      {ok:false, error:'unfinished_animals', unfinished, numbers:[…]} — it goes
--      on only with a written reason (recorded with the numbers in admin_audit).
--      It counts as the day's rollover.
--   6. One processing board is changed by one transaction at a time (carry_push,
--      carry_claim, processing_day_close, the move back to the archive): a
--      per-board lock, so a station can't write into a board while it is being
--      closed or archived.
--   7. worker_login no longer accepts a worker code kept as plain text (the
--      settings trigger stores codes as hashes only since step 41).
--   8. A ruling's time changes only together with the ruling: a write that
--      changes only slaughter_time / inner_time (final) / outer_time keeps the
--      recorded time (animals_pilot_guard_corrections). Otherwise such a write
--      would move the device's "last animal" cursor back and open a correction
--      the "moved on" rule had closed.
--   9. Each archived day keeps the status definitions it was ruled with
--      (daily_board_archive.statuses; archive_days returns them).
--  10. Writes to today's board (claim / push / esophagus / rabbinate / outer open /
--      lung drawing) take a shared lock that the daily reset takes exclusively:
--      nothing is written between the reset's copy of the board and its clearing.
--  11. create_first_manager through the app needs the one-time setup code
--      (_set_setup_code, run once at installation); without one:
--      'setup_code_not_configured'. From the server (SQL) it still works.
--  12. New team-leader / owner codes: at least 6 characters.
--  13. customStatuses: two statuses with the same key are refused.
--  14. The team leader works only from a team-leader device: pairing role 'leader'
--      (no station, no ruling rights). manager_login for a team leader needs one once
--      the plant has one ('leader_device_required'); the first is registered at
--      installation from the device the first team leader logs in on. Once a plant
--      had a team-leader device the rule stays on (plant_state leaderDevicesRequired),
--      also if every such device is removed; only the server (SQL) can reopen the
--      first-device registration: select leader_device_recovery('reason'); — it also
--      disconnects every team-leader device (a lost one cannot be used afterwards).
--  15. Accounts: a team leader cannot add or remove a team leader — team-leader
--      accounts only on the server (leader_account_add / leader_account_remove).
--      The owner is view-only (no account changes either). The team leader adds /
--      removes owner (view-only) accounts. Every account change is a security event.
--  19. Billing currency (manufacturer): ₪ $ € £ or any 3-letter code (USD, CHF …).
--  18. One worker list per screen: slaughter, esophagus, legs, inner, outer, parts,
--      stamps (was 3 shared lists: slaughterers / inspectors / supervisors). A worker
--      logs in only at a screen whose list has his name / code (worker_login, the
--      'name' mode of _derive_actor); the same person may be on several lists. The
--      login mode (none / name / code / both) is set per screen. Existing workers of
--      the old shared lists are copied to every screen of their old list
--      (system_health info 'worker_lists_check' until the team leader saves the lists).
--  17. The owner and the manufacturer cannot log in from a station tablet
--      ('station_device'), and a view-only session (owner, manufacturer without repair
--      access) writes nothing even when it comes through a station device
--      (_session_view_only in _device_write_allowed and push_settings).
--  16. Installation: plant_setup_needed() tells a new device that the plant has no
--      team leader yet (so the app shows "first installation" instead of a pairing
--      code); the setup code is compared as printed (dashes / spaces / case ignored).
-- Safe to run more than once. Run after step 45.
-- ============================================================================

-- ── helpers: settings, kosher statuses, the esophagus rule ──────────────────
-- v10.32: running this file while tablets work. In the Supabase SQL Editor the whole file is ONE
-- transaction: it changes triggers and functions of tables the tablets read and write every few
-- seconds, so a tablet's request and this file could each wait for the other ("deadlock detected",
-- nothing is changed). The busy tables are locked here first, all together, so this file waits
-- for the tablets' running requests and then goes on alone (the tablets wait a few seconds and
-- carry on). Run on psql statement by statement, the lock ends at once — harmless.
do $$
declare t text; v_list text := '';
begin
  perform set_config('lock_timeout', '30s', true);
  foreach t in array array['settings_pilot', 'plant_state', 'devices_pilot', 'device_credentials', 'worker_sessions',
                           'processed_commands', 'animals_pilot', 'animals_carry', 'animal_holds', 'animal_changes',
                           'events_pilot', 'kashrut_seals'] loop
    if to_regclass('public.' || t) is not null then v_list := v_list || case when v_list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  if v_list <> '' then execute 'lock table ' || v_list || ' in access exclusive mode'; end if;
end $$;

-- v10.33: a "not chalak" animal that the outer inspector ruled plain כשר (not רבנות כשר).
-- "Not chalak" holds until the outer ruling; there it becomes רבנות כשר (outer_status 'kosher')
-- or כשר (outer_status 'kosher' + nc_plain). Only with a kosher ruling of a "not chalak" animal.
alter table animals_pilot add column if not exists nc_plain boolean not null default false;

do $$ begin
  if to_regclass('public.animals_carry') is not null then
    alter table animals_carry add column if not exists nc_plain boolean not null default false;
  end if;
end $$;

create or replace function _gt_settings() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select settings from settings_pilot where id = 1), '{}'::jsonb);
$$;
revoke execute on function _gt_settings() from public, anon, authenticated;

create or replace function _gt_flag(s jsonb, p_key text, p_default boolean) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when jsonb_typeof(s -> p_key) = 'boolean' then (s ->> p_key)::boolean else p_default end;
$$;
revoke execute on function _gt_flag(jsonb, text, boolean) from public, anon, authenticated;

-- the esophagus check applies to this number on TODAY's board (the app's _esoApplies)
create or replace function _eso_required(p_id integer) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare s jsonb := _gt_settings(); v_from int := 0;
begin
  if not _gt_flag(s, 'esophagusEnabled', false) then return false; end if;
  if jsonb_typeof(s -> 'esoFromIdx') = 'number' and (s ->> 'esoFromIdx')::numeric > 0
     and coalesce(s ->> 'esoFromReset', '') = coalesce(s ->> 'lastServerResetAt', '') then
    v_from := floor((s ->> 'esoFromIdx')::numeric)::int;
  end if;
  return p_id >= v_from;
end $$;
revoke execute on function _eso_required(integer) from public, anon, authenticated;

-- the statuses that count as kosher (the app's getKosherStatuses)
create or replace function _kosher_statuses() returns text[]
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select array['glatt', 'beit', 'kosher', 'mk', 'rabChalak']
         || coalesce((select array_agg(x ->> 'key') from jsonb_array_elements(
                        case when jsonb_typeof(_gt_settings() -> 'customStatuses') = 'array'
                             then _gt_settings() -> 'customStatuses' else '[]'::jsonb end) x
                       where jsonb_typeof(x) = 'object' and x -> 'kosher' = 'true'::jsonb
                         and coalesce(x ->> 'key', '') not in ('', 'treif')), '{}'::text[]);
$$;
revoke execute on function _kosher_statuses() from public, anon, authenticated;

create or replace function _is_nc(a animals_pilot) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select a.slaughter = 'notChalak' or coalesce(a.not_chalak_inner, false) or coalesce(a.not_chalak_outer, false);
$$;
revoke execute on function _is_nc(animals_pilot) from public, anon, authenticated;

-- ruled kosher and still kosher (the app's isKosherReady)
-- marked "not chalak" by the shochet or the inner inspector (not only sent to the rabbinate screen)
create or replace function _nc_fixed(a animals_pilot) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select a.slaughter = 'notChalak' or coalesce(a.not_chalak_inner, false);
$$;
revoke execute on function _nc_fixed(animals_pilot) from public, anon, authenticated;

-- may this outer ruling be given to this animal? A "not chalak" animal: רבנות כשר ('kosher') or
-- treif; one that was only sent to the rabbinate screen also רבנות חלק ('rabChalak'). (v10.17)
create or replace function _nc_outer_value_ok(a animals_pilot, v text) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select v is null or not coalesce(_is_nc(a), false) or v in ('kosher', 'treif')
         or (v = 'rabChalak' and not coalesce(_nc_fixed(a), false));
$$;
revoke execute on function _nc_outer_value_ok(animals_pilot, text) from public, anon, authenticated;

create or replace function _kosher_ready(a animals_pilot) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(a.outer_status is not null
                  and _nc_outer_value_ok(a, a.outer_status)
                  and a.outer_status = any(_kosher_statuses())
                  and coalesce(a.slaughter, '') not in ('nevela', 'shot')
                  and a.inner_status = 'confirmed', false);
$$;
revoke execute on function _kosher_ready(animals_pilot) from public, anon, authenticated;

-- what a parts sticker / stamp must say for this ruling (the app's _printedAsKey)
create or replace function _printed_as_key(a animals_pilot) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when a.outer_status is null then null
              when a.outer_status = 'kosher' and _is_nc(a) and not coalesce(a.nc_plain, false) then 'kosherRab'
              else a.outer_status end;
$$;
revoke execute on function _printed_as_key(animals_pilot) from public, anon, authenticated;

-- ── 1. stage order ───────────────────────────────────────────────────────────
-- Why a stage may NOT act on this animal yet (null = it may). p_stage:
-- 'eso', 'inner', 'outer', 'legs_stickers', 'legs', 'parts', 'stamped', 'weights'.
-- p_today: the row is on today's board (the esophagus rule of today applies).
-- (v10.26: replaced further down, §27–§29)
create or replace function _stage_order_error(p_stage text, a animals_pilot, p_today boolean default true) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_alive boolean := coalesce(a.slaughter in ('slaughtered', 'notChalak'), false);
        v_eso_ok boolean;
begin
  v_eso_ok := not v_alive
              or (coalesce(a.eso_checked, false) and a.eso_result = 'ok')
              or (p_today and not _eso_required(a.id))
              or (not p_today and (coalesce(a.eso_checked, false) or a.inner_status is not null));
  case p_stage
    when 'eso' then
      if not v_alive then return 'not_slaughtered'; end if;
      if a.inner_status is not null or a.outer_status is not null then return 'later_stage_started'; end if;
    when 'inner' then
      if not v_alive then return 'not_slaughtered'; end if;
      if not v_eso_ok then return 'eso_not_passed'; end if;
      if a.outer_status is not null then return 'later_stage_started'; end if;
    when 'outer' then
      if a.inner_status is distinct from 'confirmed' then return 'inner_not_confirmed'; end if;
    when 'legs_stickers' then
      if a.slaughter is null then return 'not_slaughtered'; end if;
      if not v_eso_ok then return 'eso_not_passed'; end if;
    when 'legs', 'parts', 'stamped' then
      if a.outer_status is null then return 'outer_not_ruled'; end if;
    when 'weights' then
      if a.outer_status is null and a.inner_status is distinct from 'treif' then return 'outer_not_ruled'; end if;
    else
      return null;
  end case;
  return null;
end $$;
revoke execute on function _stage_order_error(text, animals_pilot, boolean) from public, anon, authenticated;

-- ── 4a. processing boards kept after the daily reset ────────────────────────
create table if not exists animals_carry (like animals_pilot including defaults including constraints);
alter table animals_carry add column if not exists nc_plain boolean not null default false;
alter table animals_carry add column if not exists board_id bigint;
alter table animals_carry add column if not exists slaughter_day date;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'animals_carry'::regclass and contype = 'p') then
    alter table animals_carry alter column board_id set not null;
    alter table animals_carry alter column slaughter_day set not null;
    alter table animals_carry add constraint animals_carry_pkey primary key (board_id, id);
  end if;
end $$;
create index if not exists animals_carry_day_idx on animals_carry (slaughter_day, board_id);
alter table animals_carry enable row level security;
revoke all on animals_carry from public, anon, authenticated;

create table if not exists processing_day_closed (
  board_id     bigint not null,
  station      text not null check (station in ('legs', 'parts', 'stamps')),
  closed_at    timestamptz not null default now(),
  closed_by    text,
  reason       text,
  pending_left integer,
  primary key (board_id, station)
);
alter table processing_day_closed enable row level security;
-- Row security is already on for these tables; the line is repeated so that the
-- Supabase SQL Editor sees it and does not offer to append its own "enable RLS"
-- lines
alter table plant_state enable row level security;
revoke all on processing_day_closed from public, anon, authenticated;

-- the processing stations this plant uses (team-leader screen switches)
create or replace function _proc_stations() returns text[]
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select array_remove(array[
           case when _gt_flag(_gt_settings(), 'legsEnabled', true)   then 'legs' end,
           case when _gt_flag(_gt_settings(), 'partsEnabled', true)  then 'parts' end,
           case when _gt_flag(_gt_settings(), 'stampsEnabled', true) then 'stamps' end], null);
$$;
revoke execute on function _proc_stations() from public, anon, authenticated;

-- is there still work for this station on this animal? (the app's own "pending" tests)
-- (v10.26: replaced further down, §27–§29)
create or replace function _proc_pending(p_station text, a animals_pilot, p_today boolean default false) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if a.slaughter is null then return false; end if;
  case p_station
    when 'legs' then
      return (not coalesce(a.head_stickers, false) and _stage_order_error('legs_stickers', a, p_today) is null)
          or (_gt_flag(_gt_settings(), 'legsSortEnabled', false) and _kosher_ready(a) and not coalesce(a.legs_sorted, false));
    when 'parts' then
      return _kosher_ready(a)
         and ((not coalesce(a.parts_scanned, false) and coalesce(a.parts_print_count, 0) < 3)
              or (a.parts_printed_as is not null and a.parts_printed_as is distinct from _printed_as_key(a)));
    when 'stamps' then
      return _kosher_ready(a)
         and (not coalesce(a.stamped, false)
              or (a.stamped_as is not null and a.stamped_as is distinct from _printed_as_key(a)));
    else
      return false;
  end case;
end $$;
revoke execute on function _proc_pending(text, animals_pilot, boolean) from public, anon, authenticated;

create or replace function _carry_row(c animals_carry) returns animals_pilot
language sql immutable set search_path = public, extensions, pg_temp as $$
  select jsonb_populate_record(null::animals_pilot, to_jsonb(c));
$$;
revoke execute on function _carry_row(animals_carry) from public, anon, authenticated;

create or replace function _proc_board_pending(p_station text, p_board bigint) returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)::int from animals_carry c
   where c.board_id = p_board and _proc_pending(p_station, _carry_row(c), false)
     and not exists (select 1 from processing_day_closed z where z.board_id = p_board and z.station = p_station);
$$;
revoke execute on function _proc_board_pending(text, bigint) from public, anon, authenticated;

-- the oldest board this station has not finished (null = it works on today's board)
create or replace function _proc_open_board(p_station text) returns bigint
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select b.board_id from (select distinct board_id, slaughter_day from animals_carry) b
   where p_station = any(_proc_stations())
     and _proc_board_pending(p_station, b.board_id) > 0
   order by b.slaughter_day, b.board_id
   limit 1;
$$;
revoke execute on function _proc_open_board(text) from public, anon, authenticated;

-- one transaction at a time on a kept board (write / claim / close / archive)
create or replace function _proc_board_lock(p_board bigint) returns void
language sql volatile set search_path = public, extensions, pg_temp as $$
  select pg_advisory_xact_lock(hashtext('gt_proc_board:' || p_board::text));
$$;
revoke execute on function _proc_board_lock(bigint) from public, anon, authenticated;

-- a board no station needs any more: its final state goes back into its archive row
-- (v10.26: replaced further down, §27–§29)
create or replace function _proc_finalize(p_board bigint default null) returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare b record; n int := 0; v_open boolean; st text;
begin
  for b in select distinct board_id from animals_carry where p_board is null or board_id = p_board order by board_id loop
    perform _proc_board_lock(b.board_id);
    continue when not exists (select 1 from animals_carry where board_id = b.board_id);   -- archived meanwhile
    v_open := false;
    foreach st in array _proc_stations() loop
      if _proc_board_pending(st, b.board_id) > 0 then v_open := true; exit; end if;
    end loop;
    continue when v_open;
    update daily_board_archive d
       set board = coalesce((select jsonb_agg(to_jsonb(c) - 'board_id' - 'slaughter_day' order by c.id)
                               from animals_carry c where c.board_id = b.board_id), d.board)
     where d.id = b.board_id;
    delete from animals_carry where board_id = b.board_id;
    delete from processing_day_closed where board_id = b.board_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function _proc_finalize(bigint) from public, anon, authenticated;

-- which processing station a changed column belongs to
create or replace function _proc_station_of_group(p_group text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case p_group
           when 'legs' then 'legs'
           when 'parts' then 'parts'
           when 'weights' then 'stamps'
           when 'stamped' then case when _caller_device_role() = 'parts' then 'parts' else 'stamps' end
         end;
$$;
revoke execute on function _proc_station_of_group(text) from public, anon, authenticated;

-- ── 1b. the guard trigger on today's board ──────────────────────────────────
create or replace function _animals_stage_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_err text; v_stage text; g text; v_open bigint; v_day date; v_key text;
        v_groups text[] := '{}';
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then return new; end if;        -- a new row carries no rulings (see _animals_merge)

  -- first rulings: the earlier stages must be there
  if not coalesce(old.eso_checked, false) and coalesce(new.eso_checked, false) then
    v_stage := 'eso';
    v_err := _stage_order_error('eso', old, true);     -- v10.26: also a number with the shochet's open "?"
    if v_err is null and (new.inner_status is not null or new.outer_status is not null) then v_err := 'later_stage_started'; end if;
  end if;
  -- (a value that is not valid at all is left to the table's own checks: invalid_value)
  if v_err is null and old.inner_status is null and new.inner_status is not null and _gt_value_ok('inner', new.inner_status) then
    v_stage := 'inner'; v_err := _stage_order_error('inner', new, true);
  end if;
  if v_err is null and old.outer_status is null and new.outer_status is not null and _gt_value_ok('outer', new.outer_status) then
    v_stage := 'outer'; v_err := _stage_order_error('outer', new, true);
  end if;
  if v_err is null and not coalesce(old.not_chalak_outer, false) and coalesce(new.not_chalak_outer, false) then
    v_stage := 'outer'; v_err := _stage_order_error('outer', new, true);       -- sent to the rabbinate screen by the outer inspector
  end if;
  if v_err is null and ((not coalesce(old.head_stickers, false) and coalesce(new.head_stickers, false))
                        or (not coalesce(old.legs_stickers, false) and coalesce(new.legs_stickers, false))) then
    v_stage := 'legs_stickers'; v_err := _stage_order_error('legs_stickers', new, true); v_groups := v_groups || 'legs'::text;
  end if;
  if not coalesce(old.legs_sorted, false) and coalesce(new.legs_sorted, false) then
    v_groups := v_groups || 'legs'::text;
    if v_err is null then v_stage := 'legs'; v_err := _stage_order_error('legs', new, true); end if;
  end if;
  if (not coalesce(old.parts_scanned, false) and coalesce(new.parts_scanned, false))
     or (not coalesce(old.tongue_sticker, false) and coalesce(new.tongue_sticker, false))
     or (not coalesce(old.cheek_sticker, false) and coalesce(new.cheek_sticker, false))
     or coalesce(new.parts_print_count, 0) > coalesce(old.parts_print_count, 0)
     or new.parts_printed_as is distinct from old.parts_printed_as then
    v_groups := v_groups || 'parts'::text;
    if v_err is null and _gt_value_ok('printed', new.parts_printed_as) then v_stage := 'parts'; v_err := _stage_order_error('parts', new, true); end if;
  end if;
  if (not coalesce(old.stamped, false) and coalesce(new.stamped, false))
     or new.stamped_as is distinct from old.stamped_as then
    v_groups := v_groups || 'stamped'::text;
    if v_err is null then v_stage := 'stamped'; v_err := _stage_order_error('stamped', new, true); end if;
  end if;
  if (new.weight_right, new.weight_left, new.weight_stage2, new.weight_stage3) is distinct from
     (old.weight_right, old.weight_left, old.weight_stage2, old.weight_stage3)
     or (not coalesce(old.weight_right_skipped, false) and coalesce(new.weight_right_skipped, false))
     or (not coalesce(old.weight_left_skipped, false) and coalesce(new.weight_left_skipped, false))
     or (not coalesce(old.weight_stage2_skipped, false) and coalesce(new.weight_stage2_skipped, false))
     or (not coalesce(old.weight_stage3_skipped, false) and coalesce(new.weight_stage3_skipped, false)) then
    v_groups := v_groups || 'weights'::text;
    if v_err is null and coalesce(new.weight_right  > 0 and new.weight_right  < 2000, true)
                     and coalesce(new.weight_left   > 0 and new.weight_left   < 2000, true)
                     and coalesce(new.weight_stage2 > 0 and new.weight_stage2 < 2000, true)
                     and coalesce(new.weight_stage3 > 0 and new.weight_stage3 < 2000, true) then v_stage := 'weights'; v_err := _stage_order_error('weights', new, true); end if;
  end if;
  if v_err is not null then
    raise exception 'GT:OUT_OF_ORDER out-of-order: stage=% reason=%', v_stage, v_err using errcode = 'P0001';
  end if;

  -- processing: no skipping — an older slaughter day first
  foreach g in array v_groups loop
    v_open := _proc_open_board(_proc_station_of_group(g));
    if v_open is not null then
      select slaughter_day into v_day from animals_carry where board_id = v_open limit 1;
      raise exception 'GT:EARLIER_DAY_OPEN earlier-day-open: station=% board=% day=%', _proc_station_of_group(g), v_open, v_day
        using errcode = 'P0001';
    end if;
  end loop;

  -- a sticker / stamp that does not say the ruling: kept (it was printed), but recorded
  v_key := _printed_as_key(new);
  if new.parts_printed_as is distinct from old.parts_printed_as and new.parts_printed_as is not null
     and new.parts_printed_as is distinct from v_key then
    perform _security_event(new.id + 1, 'label_mismatch',
      jsonb_build_object('what', 'parts', 'printed', new.parts_printed_as, 'ruling', v_key), null, coalesce(_acting_device(), 'unknown'));
  end if;
  if new.stamped_as is distinct from old.stamped_as and new.stamped_as is not null and new.stamped_as is distinct from v_key then
    perform _security_event(new.id + 1, 'label_mismatch',
      jsonb_build_object('what', 'stamp', 'printed', new.stamped_as, 'ruling', v_key), null, coalesce(_acting_device(), 'unknown'));
  end if;
  return new;
end $$;
revoke execute on function _animals_stage_guard() from public, anon, authenticated;

drop trigger if exists b_animals_stage_guard on animals_pilot;
create trigger b_animals_stage_guard before update on animals_pilot
  for each row execute function _animals_stage_guard();

-- ── 2. each station rules only its own stage ────────────────────────────────
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
      when 'inner'     then v_role in ('inner')              -- step 46: inner tablet → inner only
      when 'outer'     then v_role in ('outer')              -- step 46: outer tablet → outer only
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
revoke execute on function _stage_allowed(text) from public, anon, authenticated;

-- ── 1c. claim_animal_stage: the order is checked before the first claim ─────
create or replace function claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint, p_command_id uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_rows integer := 0;
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_dev text;
  v_epoch bigint := _board_epoch();
  v_stage text := case when p_stage = 'inner_start' then 'inner' else p_stage end;
  v_actor text;
  v_res jsonb;
  v_dup boolean := false;
  v_order text; v_open bigint;
  v_plain boolean := false;
  a animals_pilot%rowtype;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('claimed', false, 'error', 'bad_id');
  end if;
  if p_stage is null or p_stage not in ('slaughter', 'inner_start', 'inner', 'outer', 'eso', 'legs', 'stamped') then
    return jsonb_build_object('claimed', false, 'error', 'bad_stage');
  end if;
  perform _board_write_lock();                      -- never in the middle of a daily reset
  v_epoch := _board_epoch();
  if (p_stage = 'slaughter' and (p_value is null or not _gt_value_ok('slaughter', p_value)))
     or (p_stage = 'inner' and coalesce(p_value, '') not in ('confirmed', 'treif'))
     or (p_stage = 'outer' and (p_value is null or (p_value <> 'kosherPlain' and not _gt_value_ok('outer', p_value))))
     or (p_stage = 'eso' and coalesce(p_value, '') not in ('ok', 'nevela')) then
    return jsonb_build_object('claimed', false, 'error', 'bad_value');
  end if;
  -- v10.33: 'kosherPlain' = plain כשר for a "not chalak" animal (outer_status 'kosher' + nc_plain)
  v_plain := (p_stage = 'outer' and p_value = 'kosherPlain');
  if v_plain then p_value := 'kosher'; end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('claimed', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  v_dev := _call_device(p_device_id);
  if v_dev is null then
    return jsonb_build_object('claimed', false, 'error', _no_device_error());
  end if;
  if not _stage_allowed(v_stage) then
    return jsonb_build_object('claimed', false, 'error', 'wrong_station');
  end if;
  v_res := _cmd_get(p_command_id, v_dev, 'claim_animal_stage');
  if v_res is not null then return v_res; end if;

  v_actor := _derive_actor(p_stage, p_actor);                 -- every stage: the server's name for the worker

  insert into animals_pilot (id, board_epoch) values (p_id, v_epoch) on conflict (id) do nothing;
  select * into a from animals_pilot where id = p_id for update;

  -- step 46: a number reaches a station only after the stages before it.
  -- (Checked only while the stage is still open — a retry of a claim this
  -- device already won is answered below as a duplicate.)
  if (p_stage = 'eso' and a.eso_checked is distinct from true)
     or (p_stage in ('inner_start', 'inner') and (a.inner_status is null or a.inner_status = 'in_progress'))
     or (p_stage = 'outer' and a.outer_status is null)
     or (p_stage = 'legs' and a.legs_sorted is distinct from true)
     or (p_stage = 'stamped' and a.stamped is distinct from true) then
    v_order := _stage_order_error(case when p_stage = 'inner_start' then 'inner' else p_stage end, a, true);
    if v_order is not null then
      v_res := jsonb_build_object('claimed', false, 'error', 'out_of_order', 'reason', v_order,
                                  'row', to_jsonb(a), 'serverNow', v_now);
      perform _cmd_put(p_command_id, v_dev, 'claim_animal_stage', v_res);
      return v_res;
    end if;
    -- v10.26: a USDA hold / the station's open "?" (a ruling of the station's own "?" goes ahead)
    v_order := _hold_block(coalesce(a.board_epoch, v_epoch), p_id,
                           case p_stage when 'inner_start' then 'inner' when 'stamped' then _proc_station_of_group('stamped') else p_stage end);
    if v_order is not null then
      v_res := jsonb_build_object('claimed', false, 'error', 'held', 'reason', v_order, 'row', to_jsonb(a), 'serverNow', v_now);
      perform _cmd_put(p_command_id, v_dev, 'claim_animal_stage', v_res);
      return v_res;
    end if;
    if p_stage in ('legs', 'stamped') then
      v_open := _proc_open_board(case when p_stage = 'legs' then 'legs' else _proc_station_of_group('stamped') end);
      if v_open is not null then
        v_res := jsonb_build_object('claimed', false, 'error', 'earlier_day_open', 'board', v_open,
                                    'day', (select slaughter_day from animals_carry where board_id = v_open limit 1),
                                    'row', to_jsonb(a), 'serverNow', v_now);
        perform _cmd_put(p_command_id, v_dev, 'claim_animal_stage', v_res);
        return v_res;
      end if;
    end if;
  end if;

  -- a "not chalak" animal: only רבנות כשר (kosher) or treif — one only SENT to the rabbinate
  -- screen may also be ruled רבנות חלק (§25)
  if p_stage = 'outer' and a.outer_status is null and not _nc_outer_value_ok(a, p_value) then
    v_res := jsonb_build_object('claimed', false, 'error', 'bad_value', 'reason', 'nc_kosher_or_treif_only',
                                'row', to_jsonb(a), 'serverNow', v_now);
    perform _cmd_put(p_command_id, v_dev, 'claim_animal_stage', v_res);
    return v_res;
  end if;

  if p_stage = 'slaughter' and a.slaughter is null and _hold_block(coalesce(a.board_epoch, v_epoch), p_id, 'slaughter') is not null then
    v_res := jsonb_build_object('claimed', false, 'error', 'held', 'reason', _hold_block(coalesce(a.board_epoch, v_epoch), p_id, 'slaughter'),
                                'row', to_jsonb(a), 'serverNow', v_now);
    perform _cmd_put(p_command_id, v_dev, 'claim_animal_stage', v_res);
    return v_res;
  end if;

  perform set_config('gt.claim', 'true', true);
  if p_stage = 'slaughter' then
    update animals_pilot
       set slaughter = p_value, slaughtered_by = v_actor, slaughter_by_device = v_dev, device_id = v_dev,
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), updated_at = now()
     where id = p_id and slaughter is null
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;
  elsif p_stage = 'inner_start' then
    update animals_pilot
       set inner_status = 'in_progress', inner_by = v_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id and (inner_status is null
                          or (inner_status = 'in_progress'
                              and (inner_by_device is null or inner_by_device = v_dev
                                   or inner_time < v_now - 600000)))   -- a check left open 10+ min can be taken over
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;
  elsif p_stage = 'inner' then
    update animals_pilot
       set inner_status = p_value, inner_by = v_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id
       and (inner_status is null
            or (inner_status = 'in_progress' and (inner_by_device is null or inner_by_device = v_dev
                                                  or inner_time < v_now - 600000)))
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;
  elsif p_stage = 'outer' then
    update animals_pilot
       set outer_status = p_value, outer_by = v_actor, outer_by_device = v_dev, device_id = v_dev,
           nc_plain = v_plain,
           outer_time = greatest(v_now, coalesce(outer_time, 0) + 1), updated_at = now()
     where id = p_id and outer_status is null
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;
  elsif p_stage = 'eso' then
    perform set_config('gt.eso_ruling', 'true', true);
    update animals_pilot
       set eso_checked = true,
           eso_result = p_value,
           eso_by_device = v_dev,
           eso_prev_slaughter = case when p_value = 'nevela' then slaughter else eso_prev_slaughter end,
           slaughter = case when p_value = 'nevela' then 'nevela' else slaughter end,
           slaughter_time = case when p_value = 'nevela' then greatest(v_now, coalesce(slaughter_time, 0) + 1) else slaughter_time end,
           slaughter_by_device = case when p_value = 'nevela' then v_dev else slaughter_by_device end,
           device_id = v_dev,
           updated_at = now()
     where id = p_id and (eso_checked is distinct from true)
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;
    perform set_config('gt.eso_ruling', '', true);
  elsif p_stage = 'legs' then
    update animals_pilot set legs_sorted = true, device_id = v_dev, updated_at = now()
     where id = p_id and (legs_sorted is distinct from true)
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;
  elsif p_stage = 'stamped' then
    update animals_pilot set stamped = true, device_id = v_dev, updated_at = now()
     where id = p_id and (stamped is distinct from true)
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;
  end if;
  perform set_config('gt.claim', '', true);

  select * into a from animals_pilot where id = p_id;
  if v_rows = 0 then
    -- a retry of a claim this device already won (same value) is not a conflict
    v_dup := coalesce(case p_stage
      when 'slaughter' then a.slaughter = p_value and a.slaughter_by_device = v_dev
      when 'inner'     then a.inner_status = p_value and a.inner_by_device = v_dev
      when 'outer'     then a.outer_status = p_value and a.outer_by_device = v_dev
                            and coalesce(a.nc_plain, false) = (v_plain and _is_nc(a))
      when 'eso'       then coalesce(a.eso_checked, false) and a.eso_result = p_value and a.eso_by_device = v_dev
      else false end, false);
    if not v_dup and p_stage in ('inner_start', 'inner') and a.inner_status = 'in_progress'
       and a.inner_by_device is distinct from v_dev then
      -- the lung check is held by another tablet (e.g. it took it over): refused and recorded
      perform _security_event(p_id + 1, 'inner_takeover_rejected',
        jsonb_build_object('holder', a.inner_by_device, 'tried', coalesce(p_value, p_stage), 'via', 'claim'), v_actor, v_dev);
    end if;
  end if;
  v_res := jsonb_build_object('claimed', v_rows = 1 or v_dup, 'row', to_jsonb(a), 'serverNow', v_now)
           || case when v_dup then jsonb_build_object('duplicate', true) else '{}'::jsonb end;
  perform _cmd_put(p_command_id, v_dev, 'claim_animal_stage', v_res);
  return v_res;
end $$;

-- ── 1d. animal_push: says why a row was refused (order / earlier day) ───────
create or replace function animal_push(p_rows jsonb, p_command_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $_$
declare
  cols constant text[] := array[
    'device_id','board_epoch',
    'slaughter','slaughter_time','slaughtered_by','slaughter_by_device',
    'legs_stickers','head_stickers','maw','rumen',
    'inner_status','inner_time','inner_by','inner_by_device',
    'outer_status','outer_time','outer_by','outer_by_device',
    'parts_scanned','tongue_sticker','cheek_sticker',
    'weight_right','weight_left','weight_stage2','weight_stage3',
    'weight_right_skipped','weight_left_skipped','weight_stage2_skipped','weight_stage3_skipped',
    'eso_checked','eso_result','legs_sorted','stamped','stamped_as',
    'not_chalak_inner','parts_print_count','parts_printed_as','nc_plain'];
  v_api boolean := _is_api_request() and not _request_is_service_role();
  v_rows jsonb; r jsonb; r2 jsonb; k text;
  v_cols text[]; v_ins text; v_sel text; v_set text;
  v_dev text; v_role text; v_wait int;
  v_out jsonb := '[]'::jsonb; v_row jsonb; v_ignored text[] := '{}';
  v_cur int; v_err text; v_state text; v_msg text; v_res jsonb;
begin
  if jsonb_typeof(p_rows) = 'object' then v_rows := jsonb_build_array(p_rows);
  elsif jsonb_typeof(p_rows) = 'array' then v_rows := p_rows;
  else return jsonb_build_object('ok', false, 'error', 'bad_rows');
  end if;
  if jsonb_array_length(v_rows) = 0 or jsonb_array_length(v_rows) > 50 then
    return jsonb_build_object('ok', false, 'error', 'bad_rows');
  end if;

  v_dev := _call_device(null);
  if v_dev is null then
    -- a team-leader session has no ruling rights (test mode aside)
    return jsonb_build_object('ok', false, 'error', _no_device_error());
  end if;
  if v_api then
    v_role := _caller_device_role();
    if v_role = 'display' then return jsonb_build_object('ok', false, 'error', 'wrong_station'); end if;
    if v_role is null and not (_test_mode_on() and _request_has_manager()) then
      return jsonb_build_object('ok', false, 'error', 'device_not_paired');
    end if;
  end if;

  perform _board_write_lock();                      -- never in the middle of a daily reset
  v_res := _cmd_get(p_command_id, v_dev, 'animal_push');
  if v_res is not null then return v_res; end if;

  if v_api then
    v_wait := _correction_braked(v_dev);
    if v_wait is not null and _push_is_correction(v_rows) then
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'retry_after', v_wait);
    end if;
  end if;

  begin
    for r in select value from jsonb_array_elements(v_rows) loop
      v_cur := null;
      if jsonb_typeof(r) <> 'object' or coalesce(r ->> 'id', '') !~ '^\d{1,3}$' then
        raise exception 'GT:BAD_ID bad row id' using errcode = '22023';
      end if;
      v_cur := (r ->> 'id')::int;
      if v_cur > 999 then raise exception 'GT:BAD_ID bad row id' using errcode = '22023'; end if;
      select coalesce(array_agg(key order by key), '{}') into v_cols from jsonb_object_keys(r) key where key = any(cols);
      for k in select key from jsonb_object_keys(r) key where key <> 'id' and not (key = any(cols)) loop
        if not (k = any(v_ignored)) then v_ignored := v_ignored || k; end if;
      end loop;
      select jsonb_object_agg(key, value) into r2 from jsonb_each(r) where key = 'id' or key = any(cols);
      v_ins := 'id'; v_sel := 'x.id'; v_set := '';
      foreach k in array v_cols loop
        v_ins := v_ins || ', ' || quote_ident(k);
        v_sel := v_sel || ', x.' || quote_ident(k);
        v_set := v_set || case when v_set = '' then '' else ', ' end || quote_ident(k) || ' = excluded.' || quote_ident(k);
      end loop;
      if v_set = '' then v_set := 'id = excluded.id'; end if;
      execute format('insert into animals_pilot as t (%s) select %s from jsonb_populate_record(null::animals_pilot, $1) x '
                     'on conflict (id) do update set %s returning to_jsonb(t.*)', v_ins, v_sel, v_set)
        into v_row using r2;
      v_out := v_out || jsonb_build_array(v_row);
    end loop;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    v_err := case
      when v_msg ~ 'GT:[A-Z_]+' then lower(substring(v_msg from 'GT:([A-Z_]+)'))
      when v_state in ('23514', '22P02', '22003', '22007', '22008', '22023', '23502', '22001') then 'invalid_value'
      when v_state = '42501' then 'device_not_paired'
      else 'server_error' end;
  end;

  if v_err is not null then
    if v_err in ('moved_on', 'correction_not_allowed', 'eso_locked', 'outer_ruled', 'next_station_done') then
      perform _log_correction_rejected(v_dev, v_cur, null, v_err, jsonb_build_object('via', 'animal_push'));
    end if;
    if v_err in ('out_of_order', 'earlier_day_open') then
      perform _security_event(case when v_cur is null then null else v_cur + 1 end, v_err,
        jsonb_build_object('via', 'animal_push', 'detail', left(v_msg, 200)), null, v_dev);
    end if;
    v_res := jsonb_build_object('ok', false, 'error', v_err)
             || case when v_cur is not null then jsonb_build_object('id', v_cur,
                     'row', (select to_jsonb(a) from animals_pilot a where a.id = v_cur)) else '{}'::jsonb end
             || case when v_err = 'out_of_order' then jsonb_build_object('reason', substring(v_msg from 'reason=([a-z_]+)')) else '{}'::jsonb end
             || case when v_err = 'held' then jsonb_build_object('reason', substring(v_msg from 'hold=([a-z_]+)')) else '{}'::jsonb end
             || case when v_err = 'earlier_day_open' then jsonb_build_object('board', substring(v_msg from 'board=(\d+)')::bigint,
                                                                             'day', substring(v_msg from 'day=([0-9-]+)')) else '{}'::jsonb end
             || case when v_err = 'server_error' then jsonb_build_object('message', left(v_msg, 200)) else '{}'::jsonb end;
  else
    v_res := jsonb_build_object('ok', true, 'rows', v_out)
             || case when array_length(v_ignored, 1) > 0 then jsonb_build_object('ignored', to_jsonb(v_ignored)) else '{}'::jsonb end;
  end if;
  perform _cmd_put(p_command_id, v_dev, 'animal_push', v_res);
  return v_res;
end $_$;

-- ── 1e. the rabbinate send: only for an animal that reached the outer inspector ──
create or replace function set_not_chalak_outer(p_id integer, p_epoch bigint, p_command_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := _board_epoch(); v_dev text; a animals_pilot%rowtype; v_res jsonb; v_order text;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  perform _board_write_lock();                      -- never in the middle of a daily reset
  v_epoch := _board_epoch();
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  v_dev := _call_device(null);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  if not _nc_outer_allowed() then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  v_res := _cmd_get(p_command_id, v_dev, 'set_not_chalak_outer');
  if v_res is not null then return v_res; end if;
  select * into a from animals_pilot where id = p_id for update;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  if coalesce(a.board_epoch, 0) > coalesce(v_epoch, 0) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', a.board_epoch);
  end if;
  v_order := _stage_order_error('outer', a, true);
  if coalesce(a.not_chalak_outer, false) then
    v_res := jsonb_build_object('ok', true, 'already', true, 'row', to_jsonb(a));
  elsif a.outer_status is not null then
    v_res := jsonb_build_object('ok', false, 'error', 'already_ruled', 'row', to_jsonb(a));
  elsif v_order is not null then                       -- step 46: it has not reached the outer inspector
    v_res := jsonb_build_object('ok', false, 'error', 'out_of_order', 'reason', v_order, 'row', to_jsonb(a));
  else
    perform set_config('gt.nc_outer', 'true', true);
    update animals_pilot set not_chalak_outer = true, updated_at = now() where id = p_id;
    perform set_config('gt.nc_outer', '', true);
    select * into a from animals_pilot where id = p_id;
    v_res := jsonb_build_object('ok', coalesce(a.not_chalak_outer, false), 'row', to_jsonb(a));
  end if;
  perform _cmd_put(p_command_id, v_dev, 'set_not_chalak_outer', v_res);
  return v_res;
end $$;

-- ── 3. kashrut configuration: manufacturer technical only; statuses in use locked ──
create or replace function _statuses_in_use() returns text[]
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(array_agg(distinct s), '{}'::text[]) from (
    select outer_status as s from animals_pilot where outer_status is not null
    union all select parts_printed_as from animals_pilot where parts_printed_as is not null
    union all select stamped_as from animals_pilot where stamped_as is not null
    union all select outer_status from animals_carry where outer_status is not null) x;
$$;
revoke execute on function _statuses_in_use() from public, anon, authenticated;

-- a custom status in use whose "kosher" mark changed or that disappeared (null = fine)
create or replace function _status_change_error(p_old jsonb, p_new jsonb) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare k text; o jsonb; n jsonb;
begin
  foreach k in array _statuses_in_use() loop
    select x into o from jsonb_array_elements(case when jsonb_typeof(p_old) = 'array' then p_old else '[]'::jsonb end) x
     where jsonb_typeof(x) = 'object' and x ->> 'key' = k limit 1;
    continue when o is null;                                   -- a built-in status: not defined here
    select x into n from jsonb_array_elements(case when jsonb_typeof(p_new) = 'array' then p_new else '[]'::jsonb end) x
     where jsonb_typeof(x) = 'object' and x ->> 'key' = k limit 1;
    if n is null or (coalesce(o -> 'kosher', 'false'::jsonb) = 'true'::jsonb) is distinct from (coalesce(n -> 'kosher', 'false'::jsonb) = 'true'::jsonb) then
      return k;
    end if;
    o := null; n := null;
  end loop;
  return null;
end $$;
revoke execute on function _status_change_error(jsonb, jsonb) from public, anon, authenticated;

-- step 46 (5th review): a session that may only watch — the owner, or the manufacturer
-- without repair access. It never writes, also not through the station device it
-- happens to be on (otherwise the device's own station rights would apply).
create or replace function _session_view_only(p_token text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text;
begin
  if p_token is null or p_token = '' then return false; end if;
  v_role := _session_role(p_token);
  return v_role = 'owner' or (v_role = 'manufacturer' and not _support_access_open());
end $$;
revoke execute on function _session_view_only(text) from public, anon, authenticated;

create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  list_keys text[] := array['reprintLog','problemReports'];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason','billing','forceReloadAt','supportAccessUntil',
                              'boardEpoch','testMode'];
  -- step 46: what the manufacturer may repair — technical settings only
  maker_keys text[] := array['printers','scanners','beepSeconds','beepVolume','beepFreq','beepType','beepFlash',
                             'lang','language','defaultLang','activeLangs','weightMethods','errorLog',
                             'problemReports','reprintLog','licenseRequestDismissed'];
  cur jsonb;
  incoming jsonb;
  k text;
  v_err text;
  ignored text[] := '{}';
  is_manager boolean := false;
  is_maker boolean := false;
  v_label text;
  v_used text;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
    is_maker := is_manager and coalesce(_session_role(p_token), '') = 'manufacturer';
  end if;
  -- the owner (and the manufacturer without repair access) only watch — never through a station device
  if _session_view_only(p_token) or _session_view_only(_request_headers() ->> 'x-manager-token') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  -- the manufacturer changes the plant's settings only with a reason (step 45)
  if is_maker and not _reason_ok(p_reason) then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  -- station keys: a paired station (or team leader); nobody anonymous
  if not is_manager and not _device_write_allowed() then
    return jsonb_build_object('ok', false, 'error', 'device_not_paired');
  end if;
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

  if not is_manager or is_maker then
    for k in select jsonb_object_keys(incoming) loop
      if not (k = any(case when is_maker then maker_keys else station_keys end)) then
        if (cur -> k) is distinct from (incoming -> k) then
          ignored := ignored || k;
        end if;
        incoming := incoming - k;
      end if;
    end loop;
  end if;

  -- step 46: a status an animal on an open board carries keeps its kosher mark
  if incoming ? 'customStatuses' then
    v_used := _status_change_error(cur -> 'customStatuses', incoming -> 'customStatuses');
    if v_used is not null then
      return jsonb_build_object('ok', false, 'error', 'status_in_use', 'key', v_used);
    end if;
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
    if (not is_manager or is_maker) and incoming ? k then
      incoming := jsonb_set(incoming, array[k], _merge_list(cur -> k, incoming -> k));
    end if;
  end loop;

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, v_label, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  if is_maker then
    perform _admin_audit(p_token, 'settings', 'settings_pilot',
                         jsonb_build_object('keys', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_object_keys(incoming) x),
                                            'ignored', to_jsonb(ignored),
                                            'reason', left(trim(p_reason), 200)));
  end if;
  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;
revoke execute on function push_settings(jsonb, text, text, text) from public;
grant execute on function push_settings(jsonb, text, text, text) to anon, authenticated;

-- ── 4b. the daily reset keeps unfinished processing ─────────────────────────
-- the plant date a board belongs to: the day its first animal was slaughtered
create or replace function _board_business_date() returns date
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare tz text := coalesce(nullif(_gt_settings() ->> 'plantTimezone', ''), 'UTC'); d date;
begin
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  select (min(to_timestamp(slaughter_time / 1000.0)) at time zone tz)::date into d
    from animals_pilot where slaughter_time is not null;
  return coalesce(d, (now() at time zone tz)::date);
end $$;
revoke execute on function _board_business_date() from public, anon, authenticated;

-- (v10.26: replaced further down, §27–§29)
create or replace function _do_board_reset(p_reason text, p_business_date date) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
        v_day date := coalesce(p_business_date, _board_business_date());
        v_board bigint; v_carry boolean := false; st text;
begin
  insert into daily_board_archive (business_date, reason, animals_count, board, statuses)
  select v_day, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb),
         jsonb_build_object('customStatuses', coalesce(_gt_settings() -> 'customStatuses', '[]'::jsonb),
                            'disabledStatuses', coalesce(_gt_settings() -> 'disabledStatuses', '[]'::jsonb),
                            'kosher', to_jsonb(_kosher_statuses()))
    from animals_pilot a
   where a.slaughter is not null or a.inner_status is not null or a.outer_status is not null
  returning id into v_board;

  -- step 46: processing not finished on this board stays (no skipping, no loss)
  foreach st in array _proc_stations() loop
    if exists (select 1 from animals_pilot a where _proc_pending(st, a, true)) then v_carry := true; exit; end if;
  end loop;
  if v_carry then
    insert into animals_carry          -- by column name (v10.33: columns added later sit after board_id)
    select (jsonb_populate_record(null::animals_carry,
              to_jsonb(a) || jsonb_build_object('board_id', v_board, 'slaughter_day', v_day))).*
      from animals_pilot a where a.slaughter is not null;
  end if;
  perform _proc_finalize(null);                               -- older boards nobody needs any more

  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);

  insert into plant_state (key, value) values ('boardEpoch', v_epoch::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false, not_chalak_outer = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null, nc_plain = false,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null, eso_prev_slaughter = null, eso_by_device = null,
    legs_sorted = false,
    stamped = false, stamped_as = null,
    parts_print_count = 0, parts_printed_as = null,
    board_epoch = v_epoch,
    updated_at = clock_timestamp()
  where true;

  delete from device_stage_cursor where true;
  update devices_pilot set cursor_slaughter = null, cursor_inner = null, cursor_outer = null, cursor_eso = null
   where cursor_slaughter is not null or cursor_inner is not null or cursor_outer is not null or cursor_eso is not null;

  perform set_config('gt.reset_in_progress', 'false', true);
  perform set_config('app.device_admin', '', true);

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason,
                                'boardEpoch', v_epoch, 'dailyIntake', '[]'::jsonb, 'activeUserByRole', '{}'::jsonb),
          'server', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb)
                   || jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason,
                                         'boardEpoch', v_epoch, 'dailyIntake', '[]'::jsonb, 'activeUserByRole', '{}'::jsonb),
        device_id = 'server',
        updated_at = now();
end $$;
revoke execute on function _do_board_reset(text, date) from public, anon, authenticated;

-- ── 5. daily rollover: never in the middle of work ──────────────────────────
-- slaughtered animals that have not reached their last ruling (lungs treif, or outer)
-- (v10.26: replaced further down, §27–§29)
create or replace function _board_unfinished() returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)::int from animals_pilot
   where slaughter in ('slaughtered', 'notChalak')
     and inner_status is distinct from 'treif' and outer_status is null;
$$;
revoke execute on function _board_unfinished() from public, anon, authenticated;

create or replace function request_daily_rollover() returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s jsonb; tz text; rt time; local_now timestamp; today date; last_date text;
  v_last_activity timestamptz; v_unfinished int;
begin
  perform pg_advisory_xact_lock(hashtext('glatttrack_daily_rollover'));

  select settings into s from settings_pilot where id = 1;
  tz := coalesce(nullif(s ->> 'plantTimezone', ''), 'UTC');
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  begin
    rt := coalesce(nullif(s ->> 'autoResetTime', ''), '00:00')::time;
  exception when others then rt := '00:00'::time;
  end;
  local_now := now() at time zone tz;
  today := local_now::date;

  select value into last_date from plant_state where key = 'lastRolloverDate';
  if last_date is null then
    insert into plant_state (key, value) values ('lastRolloverDate', today::text)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    return jsonb_build_object('ok', true, 'done', false, 'status', 'initialized', 'plantDate', today, 'timezone', tz);
  end if;
  if last_date = today::text then
    delete from plant_state where key = 'rolloverWaitingSince';
    return jsonb_build_object('ok', true, 'done', false, 'status', 'already', 'plantDate', today, 'timezone', tz);
  end if;
  if local_now::time < rt then
    return jsonb_build_object('ok', true, 'done', false, 'status', 'not_yet', 'plantDate', today, 'timezone', tz, 'resetTime', rt);
  end if;

  -- work still going on (a ruling in the last 20 minutes)? wait — step 46: however long it takes
  select max(to_timestamp(greatest(coalesce(slaughter_time,0), coalesce(inner_time,0), coalesce(outer_time,0)) / 1000.0))
    into v_last_activity from animals_pilot
   where slaughter_time is not null or inner_time is not null or outer_time is not null;
  if v_last_activity is not null and v_last_activity > now() - interval '20 minutes' then
    return jsonb_build_object('ok', true, 'done', false, 'status', 'busy', 'plantDate', today, 'timezone', tz);
  end if;
  -- step 46: a slaughtered animal without its last ruling is never wiped by the clock
  v_unfinished := _board_unfinished();
  if v_unfinished > 0 then
    insert into plant_state (key, value) values ('rolloverWaitingSince', now()::text)
      on conflict (key) do nothing;
    return jsonb_build_object('ok', true, 'done', false, 'status', 'waiting_unfinished', 'unfinished', v_unfinished,
                              'plantDate', today, 'timezone', tz);
  end if;

  perform _do_board_reset('daily-rollover', null);
  update plant_state set value = today::text, updated_at = now() where key = 'lastRolloverDate';
  delete from plant_state where key = 'rolloverWaitingSince';
  return jsonb_build_object('ok', true, 'done', true, 'status', 'rolled_over', 'plantDate', today, 'timezone', tz);
end $$;
revoke execute on function request_daily_rollover() from public;
grant execute on function request_daily_rollover() to anon, authenticated;

-- the team leader's reset: recorded, and it is the day's rollover
drop function if exists reset_daily_board(text);
create or replace function reset_daily_board(p_token text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare tz text; v_unfinished int; v_carried int; v_numbers jsonb;
begin
  if not _manager_session_valid(p_token) or coalesce(_session_role(p_token), 'manager') = 'manufacturer' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('glatttrack_daily_rollover'));
  v_unfinished := _board_unfinished();
  -- an emergency tool: slaughtered animals without their last ruling would leave the
  -- screens for good — stop, say which, and go on only with a written reason
  if v_unfinished > 0 then
    select coalesce(jsonb_agg(id + 1 order by id), '[]'::jsonb) into v_numbers from animals_pilot
     where slaughter in ('slaughtered', 'notChalak') and inner_status is distinct from 'treif' and outer_status is null;
    if not _reason_ok(p_reason) then
      return jsonb_build_object('ok', false, 'error', 'unfinished_animals', 'unfinished', v_unfinished, 'numbers', v_numbers);
    end if;
  end if;
  perform _do_board_reset('manual', null);
  tz := coalesce(nullif(_gt_settings() ->> 'plantTimezone', ''), 'UTC');
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  insert into plant_state (key, value) values ('lastRolloverDate', ((now() at time zone tz)::date)::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  delete from plant_state where key = 'rolloverWaitingSince';
  select count(distinct board_id) into v_carried from animals_carry;
  perform _admin_audit(p_token, 'daily_reset', 'animals_pilot',
                       jsonb_build_object('reason', left(trim(coalesce(p_reason, '')), 200),
                                          'unfinished', v_unfinished, 'unfinishedNumbers', coalesce(v_numbers, '[]'::jsonb),
                                          'openProcessingBoards', v_carried));
  return jsonb_build_object('ok', true, 'unfinished', v_unfinished, 'openProcessingBoards', v_carried);
end $$;
revoke execute on function reset_daily_board(text, text) from public;
grant execute on function reset_daily_board(text, text) to anon, authenticated;

-- ── 4c. processing API ───────────────────────────────────────────────────────
-- the processing station of the caller (a paired legs / parts / stamps tablet;
-- the team leader only in test mode, naming the station)
create or replace function _proc_caller_station(p_station text) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text := _caller_device_role();
begin
  if v_role in ('legs', 'parts', 'stamps') then return v_role; end if;
  if v_role is null and _test_mode_on() and _request_has_manager() and p_station in ('legs', 'parts', 'stamps') then
    return p_station;
  end if;
  if not _is_api_request() or _request_is_service_role() then
    return case when p_station in ('legs', 'parts', 'stamps') then p_station end;
  end if;
  return null;
end $$;
revoke execute on function _proc_caller_station(text) from public, anon, authenticated;

create or replace function _proc_board_json(p_board bigint) returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when p_board is null then null else jsonb_build_object(
    'id', p_board,
    'day', (select slaughter_day from animals_carry where board_id = p_board limit 1),
    'pending', (select coalesce(jsonb_object_agg(st, _proc_board_pending(st, p_board)), '{}'::jsonb)
                  from unnest(_proc_stations()) st)) end;            -- the stations this plant uses
$$;
revoke execute on function _proc_board_json(bigint) from public, anon, authenticated;

-- What this processing station works on now: the oldest board it has not
-- finished (with all its rows), or null = today's board (animals_pilot).
-- Readers (team leader / owner / stations) may look at any station's board.
create or replace function processing_board(p_station text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_station text; v_board bigint;
begin
  if not _reader_ok() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  v_station := coalesce(_proc_caller_station(p_station),
                        case when p_station in ('legs', 'parts', 'stamps') then p_station end);
  if v_station is null then return jsonb_build_object('ok', false, 'error', 'bad_station'); end if;
  v_board := _proc_open_board(v_station);
  return jsonb_build_object(
    'ok', true, 'station', v_station,
    'board', _proc_board_json(v_board),
    'rows', case when v_board is null then '[]'::jsonb else coalesce((
              select jsonb_agg(to_jsonb(c) order by c.id) from animals_carry c where c.board_id = v_board), '[]'::jsonb) end,
    'queue', coalesce((select jsonb_agg(_proc_board_json(b.board_id) order by b.slaughter_day, b.board_id)
                         from (select distinct board_id, slaughter_day from animals_carry) b), '[]'::jsonb),
    'serverNow', (extract(epoch from clock_timestamp()) * 1000)::bigint);
end $$;
revoke execute on function processing_board(text) from public;
grant execute on function processing_board(text) to anon, authenticated;

-- Processing columns of rows on a kept board (like animal_push; the rulings
-- of a kept board never change). The board must be the station's current one.
create or replace function carry_push(p_board bigint, p_rows jsonb, p_command_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_rows jsonb; r jsonb; v_dev text; v_res jsonb; v_out jsonb := '[]'::jsonb; v_ignored text[] := '{}';
  c animals_carry%rowtype; n animals_carry%rowtype; a animals_pilot; k text; g text; v_open bigint;
  v_cur int; v_err text; v_reason text; v_groups text[]; v_key text; v_state text; v_msg text;
  legs_cols constant text[] := array['legs_stickers', 'head_stickers', 'legs_sorted'];
  parts_cols constant text[] := array['parts_scanned', 'tongue_sticker', 'cheek_sticker', 'parts_print_count', 'parts_printed_as'];
  stamp_cols constant text[] := array['stamped', 'stamped_as'];
  weight_cols constant text[] := array['weight_right', 'weight_left', 'weight_stage2', 'weight_stage3',
                                       'weight_right_skipped', 'weight_left_skipped', 'weight_stage2_skipped', 'weight_stage3_skipped'];
begin
  if jsonb_typeof(p_rows) = 'object' then v_rows := jsonb_build_array(p_rows);
  elsif jsonb_typeof(p_rows) = 'array' then v_rows := p_rows;
  else return jsonb_build_object('ok', false, 'error', 'bad_rows');
  end if;
  if jsonb_array_length(v_rows) = 0 or jsonb_array_length(v_rows) > 50 then
    return jsonb_build_object('ok', false, 'error', 'bad_rows');
  end if;
  v_dev := _call_device(null);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  if _is_api_request() and not _request_is_service_role()
     and not (_caller_device_role() in ('legs', 'parts', 'stamps') or (_test_mode_on() and _request_has_manager())) then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  v_res := _cmd_get(p_command_id, v_dev, 'carry_push');
  if v_res is not null then return v_res; end if;
  perform _proc_board_lock(p_board);              -- not while this board is being closed / archived
  if not exists (select 1 from animals_carry where board_id = p_board) then
    v_res := jsonb_build_object('ok', false, 'error', 'board_closed', 'board', p_board);
    perform _cmd_put(p_command_id, v_dev, 'carry_push', v_res);
    return v_res;
  end if;

  begin
    for r in select value from jsonb_array_elements(v_rows) loop
      v_cur := null; v_groups := '{}';
      if jsonb_typeof(r) <> 'object' or coalesce(r ->> 'id', '') !~ '^\d{1,3}$' then
        raise exception 'GT:BAD_ID bad row id' using errcode = '22023';
      end if;
      v_cur := (r ->> 'id')::int;
      select * into c from animals_carry where board_id = p_board and id = v_cur for update;
      if c.id is null then raise exception 'GT:BAD_ID no such animal on this board' using errcode = '22023'; end if;
      n := c;
      for k in select key from jsonb_object_keys(r) key where key <> 'id' loop
        if k = any(legs_cols) and _stage_allowed('legs') then v_groups := v_groups || 'legs'::text;
        elsif k = any(parts_cols) and _stage_allowed('parts') then v_groups := v_groups || 'parts'::text;
        elsif k = any(stamp_cols) and _stage_allowed('stamped') then v_groups := v_groups || 'stamped'::text;
        elsif k = any(weight_cols) and _stage_allowed('weights') then v_groups := v_groups || 'weights'::text;
        else
          if not (k = any(v_ignored)) then v_ignored := v_ignored || k; end if;
          continue;
        end if;
        -- once true stays true; a print count only grows; a weight is never cleared
        case k
          when 'legs_stickers' then n.legs_stickers := coalesce(c.legs_stickers, false) or coalesce((r ->> k)::boolean, false);
          when 'head_stickers' then n.head_stickers := coalesce(c.head_stickers, false) or coalesce((r ->> k)::boolean, false);
          when 'legs_sorted'   then n.legs_sorted   := coalesce(c.legs_sorted, false)   or coalesce((r ->> k)::boolean, false);
          when 'parts_scanned' then n.parts_scanned := coalesce(c.parts_scanned, false) or coalesce((r ->> k)::boolean, false);
          when 'tongue_sticker' then n.tongue_sticker := coalesce(c.tongue_sticker, false) or coalesce((r ->> k)::boolean, false);
          when 'cheek_sticker' then n.cheek_sticker := coalesce(c.cheek_sticker, false) or coalesce((r ->> k)::boolean, false);
          when 'parts_print_count' then n.parts_print_count := greatest(coalesce(c.parts_print_count, 0), coalesce((r ->> k)::int, 0));
          when 'parts_printed_as' then n.parts_printed_as := coalesce(r ->> k, c.parts_printed_as);
          when 'stamped'       then n.stamped       := coalesce(c.stamped, false)       or coalesce((r ->> k)::boolean, false);
          when 'stamped_as'    then n.stamped_as    := coalesce(r ->> k, c.stamped_as);
          when 'weight_right'  then n.weight_right  := coalesce((r ->> k)::numeric, c.weight_right);
          when 'weight_left'   then n.weight_left   := coalesce((r ->> k)::numeric, c.weight_left);
          when 'weight_stage2' then n.weight_stage2 := coalesce((r ->> k)::numeric, c.weight_stage2);
          when 'weight_stage3' then n.weight_stage3 := coalesce((r ->> k)::numeric, c.weight_stage3);
          when 'weight_right_skipped'  then n.weight_right_skipped  := coalesce(c.weight_right_skipped, false)  or coalesce((r ->> k)::boolean, false);
          when 'weight_left_skipped'   then n.weight_left_skipped   := coalesce(c.weight_left_skipped, false)   or coalesce((r ->> k)::boolean, false);
          when 'weight_stage2_skipped' then n.weight_stage2_skipped := coalesce(c.weight_stage2_skipped, false) or coalesce((r ->> k)::boolean, false);
          when 'weight_stage3_skipped' then n.weight_stage3_skipped := coalesce(c.weight_stage3_skipped, false) or coalesce((r ->> k)::boolean, false);
        end case;
      end loop;
      if to_jsonb(n) is distinct from to_jsonb(c) then
        a := _carry_row(n);
        -- the order: a processing step only after the last ruling
        foreach g in array (select array_agg(distinct x) from unnest(v_groups) x) loop
          v_reason := _stage_order_error(case g when 'legs' then (case when n.legs_sorted is distinct from c.legs_sorted then 'legs' else 'legs_stickers' end)
                                                else g end, a, false);
          if v_reason is not null then
            raise exception 'GT:OUT_OF_ORDER out-of-order: stage=% reason=%', g, v_reason using errcode = 'P0001';
          end if;
          -- v10.26: a USDA hold / an open "?" stops the station (a held half is not weighed)
          v_reason := _hold_block(c.board_epoch, v_cur, _proc_station_of_group(g));
          if v_reason is null and g = 'parts' then                    -- v10.32: a held part is not printed
            v_reason := _parts_print_block(c.board_epoch, v_cur, c.tongue_sticker, n.tongue_sticker, c.cheek_sticker,
                                           n.cheek_sticker, c.parts_print_count, n.parts_print_count);
          end if;
          if v_reason is null and g = 'weights' and n.weight_right is distinct from c.weight_right and n.weight_right is not null then
            v_reason := _hold_block(c.board_epoch, v_cur, 'stamps', 'right');
          end if;
          if v_reason is null and g = 'weights' and n.weight_left is distinct from c.weight_left and n.weight_left is not null then
            v_reason := _hold_block(c.board_epoch, v_cur, 'stamps', 'left');
          end if;
          if v_reason is not null then
            raise exception 'GT:HELD held: station=% hold=%', _proc_station_of_group(g), v_reason using errcode = 'P0001';
          end if;
          -- no skipping: this board must be the station's current one
          v_open := _proc_open_board(_proc_station_of_group(g));
          if v_open is distinct from p_board then
            if v_open is null or (select slaughter_day from animals_carry where board_id = v_open limit 1)
                                 > (select slaughter_day from animals_carry where board_id = p_board limit 1) then
              raise exception 'GT:BOARD_CLOSED board-closed: station=% board=%', _proc_station_of_group(g), p_board using errcode = 'P0001';
            end if;
            raise exception 'GT:EARLIER_DAY_OPEN earlier-day-open: station=% board=% day=%', _proc_station_of_group(g), v_open,
              (select slaughter_day from animals_carry where board_id = v_open limit 1) using errcode = 'P0001';
          end if;
        end loop;
        n.updated_at := clock_timestamp();
        n.device_id := v_dev;
        update animals_carry set
          legs_stickers = n.legs_stickers, head_stickers = n.head_stickers, legs_sorted = n.legs_sorted,
          parts_scanned = n.parts_scanned, tongue_sticker = n.tongue_sticker, cheek_sticker = n.cheek_sticker,
          parts_print_count = n.parts_print_count, parts_printed_as = n.parts_printed_as,
          stamped = n.stamped, stamped_as = n.stamped_as,
          weight_right = n.weight_right, weight_left = n.weight_left, weight_stage2 = n.weight_stage2, weight_stage3 = n.weight_stage3,
          weight_right_skipped = n.weight_right_skipped, weight_left_skipped = n.weight_left_skipped,
          weight_stage2_skipped = n.weight_stage2_skipped, weight_stage3_skipped = n.weight_stage3_skipped,
          updated_at = n.updated_at, device_id = n.device_id
         where board_id = p_board and id = v_cur;
        v_key := _printed_as_key(a);
        if n.parts_printed_as is distinct from c.parts_printed_as and n.parts_printed_as is distinct from v_key then
          perform _security_event(v_cur + 1, 'label_mismatch', jsonb_build_object('what', 'parts', 'printed', n.parts_printed_as,
                                  'ruling', v_key, 'board', p_board), null, v_dev);
        end if;
        if n.stamped_as is distinct from c.stamped_as and n.stamped_as is distinct from v_key then
          perform _security_event(v_cur + 1, 'label_mismatch', jsonb_build_object('what', 'stamp', 'printed', n.stamped_as,
                                  'ruling', v_key, 'board', p_board), null, v_dev);
        end if;
      end if;
      v_out := v_out || jsonb_build_array(to_jsonb(n));
    end loop;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    v_err := case
      when v_msg ~ 'GT:[A-Z_]+' then lower(substring(v_msg from 'GT:([A-Z_]+)'))
      when v_state in ('23514', '22P02', '22003', '22007', '22008', '22023', '23502', '22001') then 'invalid_value'
      else 'server_error' end;
  end;

  if v_err is not null then
    v_res := jsonb_build_object('ok', false, 'error', v_err, 'board', p_board)
             || case when v_cur is not null then jsonb_build_object('id', v_cur,
                     'row', (select to_jsonb(x) from animals_carry x where x.board_id = p_board and x.id = v_cur)) else '{}'::jsonb end
             || case when v_err = 'out_of_order' then jsonb_build_object('reason', substring(v_msg from 'reason=([a-z_]+)')) else '{}'::jsonb end
             || case when v_err = 'held' then jsonb_build_object('reason', substring(v_msg from 'hold=([a-z_]+)')) else '{}'::jsonb end
             || case when v_err = 'earlier_day_open' then jsonb_build_object('open_board', substring(v_msg from 'board=(\d+)')::bigint,
                                                                             'day', substring(v_msg from 'day=([0-9-]+)')) else '{}'::jsonb end
             || case when v_err = 'server_error' then jsonb_build_object('message', left(v_msg, 200)) else '{}'::jsonb end;
  else
    v_res := jsonb_build_object('ok', true, 'rows', v_out, 'board', p_board)
             || case when array_length(v_ignored, 1) > 0 then jsonb_build_object('ignored', to_jsonb(v_ignored)) else '{}'::jsonb end;
    if _proc_finalize(p_board) > 0 then v_res := v_res || jsonb_build_object('boardDone', true); end if;
  end if;
  perform _cmd_put(p_command_id, v_dev, 'carry_push', v_res);
  return v_res;
end $$;
revoke execute on function carry_push(bigint, jsonb, uuid) from public;
grant execute on function carry_push(bigint, jsonb, uuid) to anon, authenticated;

-- first claim of "legs sorted" / "stamped" on a kept board (two tablets: one wins)
create or replace function carry_claim(p_board bigint, p_id integer, p_stage text, p_command_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_res jsonb; v_rows int := 0; c animals_carry%rowtype; v_reason text; v_open bigint; v_station text;
        v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if p_stage is null or p_stage not in ('legs', 'stamped') then
    return jsonb_build_object('claimed', false, 'error', 'bad_stage');
  end if;
  v_dev := _call_device(null);
  if v_dev is null then return jsonb_build_object('claimed', false, 'error', _no_device_error()); end if;
  if not _stage_allowed(p_stage) then return jsonb_build_object('claimed', false, 'error', 'wrong_station'); end if;
  v_res := _cmd_get(p_command_id, v_dev, 'carry_claim');
  if v_res is not null then return v_res; end if;
  perform _proc_board_lock(p_board);              -- not while this board is being closed / archived
  select * into c from animals_carry where board_id = p_board and id = p_id for update;
  if c.id is null then
    v_res := jsonb_build_object('claimed', false, 'error', 'board_closed', 'board', p_board);
    perform _cmd_put(p_command_id, v_dev, 'carry_claim', v_res);
    return v_res;
  end if;
  if (p_stage = 'legs' and coalesce(c.legs_sorted, false)) or (p_stage = 'stamped' and coalesce(c.stamped, false)) then
    v_res := jsonb_build_object('claimed', false, 'row', to_jsonb(c), 'board', p_board, 'serverNow', v_now);
    perform _cmd_put(p_command_id, v_dev, 'carry_claim', v_res);
    return v_res;
  end if;
  v_reason := _stage_order_error(p_stage, _carry_row(c), false);
  v_station := case when p_stage = 'legs' then 'legs' else _proc_station_of_group('stamped') end;
  v_open := _proc_open_board(v_station);
  if v_reason is not null then
    v_res := jsonb_build_object('claimed', false, 'error', 'out_of_order', 'reason', v_reason, 'row', to_jsonb(c), 'board', p_board);
  elsif _hold_block(c.board_epoch, p_id, v_station) is not null then          -- v10.26: USDA hold / open "?"
    v_res := jsonb_build_object('claimed', false, 'error', 'held', 'reason', _hold_block(c.board_epoch, p_id, v_station),
                                'row', to_jsonb(c), 'board', p_board);
  elsif v_open is distinct from p_board then
    v_res := jsonb_build_object('claimed', false, 'error', case when v_open is null then 'board_closed' else 'earlier_day_open' end,
                                'board', p_board, 'open_board', v_open, 'row', to_jsonb(c));
  else
    update animals_carry set legs_sorted = case when p_stage = 'legs' then true else legs_sorted end,
                             stamped = case when p_stage = 'stamped' then true else stamped end,
                             device_id = v_dev, updated_at = clock_timestamp()
     where board_id = p_board and id = p_id;
    get diagnostics v_rows = row_count;
    select * into c from animals_carry where board_id = p_board and id = p_id;
    v_res := jsonb_build_object('claimed', v_rows = 1, 'row', to_jsonb(c), 'board', p_board, 'serverNow', v_now);
    if _proc_finalize(p_board) > 0 then v_res := v_res || jsonb_build_object('boardDone', true); end if;
  end if;
  perform _cmd_put(p_command_id, v_dev, 'carry_claim', v_res);
  return v_res;
end $$;
revoke execute on function carry_claim(bigint, integer, text, uuid) from public;
grant execute on function carry_claim(bigint, integer, text, uuid) to anon, authenticated;

-- The team leader closes a kept board for one station (what is left on it will
-- not be processed there — e.g. sold as is). A reason is required; audited.
create or replace function processing_day_close(p_token text, p_board bigint, p_station text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_left int; v_open bigint;
begin
  if not _is_real_manager(p_token) then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_station not in ('legs', 'parts', 'stamps') then return jsonb_build_object('ok', false, 'error', 'bad_station'); end if;
  if not _reason_ok(p_reason) then return jsonb_build_object('ok', false, 'error', 'reason_required'); end if;
  perform _proc_board_lock(p_board);              -- a write in progress on this board finishes first
  if not exists (select 1 from animals_carry where board_id = p_board) then
    return jsonb_build_object('ok', false, 'error', 'board_closed');
  end if;
  -- in order here too: the oldest board of that station first
  v_open := _proc_open_board(p_station);
  if v_open is distinct from p_board then
    return jsonb_build_object('ok', false, 'error', case when v_open is null then 'board_closed' else 'earlier_day_open' end,
                              'open_board', v_open);
  end if;
  v_left := _proc_board_pending(p_station, p_board);
  insert into processing_day_closed (board_id, station, closed_by, reason, pending_left)
  values (p_board, p_station, _session_name(p_token), left(trim(p_reason), 200), v_left)
  on conflict (board_id, station) do nothing;
  update animal_holds set resolved_at = now(), resolution = 'board_closed', resolved_by = _session_name(p_token)
   where resolved_at is null and station = p_station
     and board_epoch in (select distinct board_epoch from animals_carry where board_id = p_board);
  perform _admin_audit(p_token, 'processing_day_close', p_station,
                       jsonb_build_object('board', p_board, 'pendingLeft', v_left, 'reason', left(trim(p_reason), 200)));
  perform _proc_finalize(p_board);
  return jsonb_build_object('ok', true, 'pendingLeft', v_left);
end $$;
revoke execute on function processing_day_close(text, bigint, text, text) from public;
grant execute on function processing_day_close(text, bigint, text, text) to anon, authenticated;

create or replace function processing_status(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if coalesce(_session_role(p_token), '') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true,
    'stations', to_jsonb(_proc_stations()),
    'current', jsonb_build_object('legs', _proc_open_board('legs'), 'parts', _proc_open_board('parts'), 'stamps', _proc_open_board('stamps')),
    'boards', coalesce((select jsonb_agg(_proc_board_json(b.board_id)
                                         || jsonb_build_object('closed', coalesce((select jsonb_object_agg(z.station, z.reason)
                                                                                     from processing_day_closed z where z.board_id = b.board_id), '{}'::jsonb))
                                         order by b.slaughter_day, b.board_id)
                          from (select distinct board_id, slaughter_day from animals_carry) b), '[]'::jsonb),
    'rolloverWaitingSince', (select value from plant_state where key = 'rolloverWaitingSince'));
end $$;
revoke execute on function processing_status(text) from public;
grant execute on function processing_status(text) to anon, authenticated;

-- ── 7. worker codes: hashes only ─────────────────────────────────────────────
create or replace function worker_login(p_role text, p_code text, p_name text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_role text := _worker_role_norm(p_role);
  v_dev text := _current_device_id();
  v_mgr boolean := _request_has_manager() and _test_mode_on();      -- a team leader acts as a station only in test mode
  v_mt text := _request_headers() ->> 'x-manager-token';
  d devices_pilot%rowtype;
  v_ip text := 'w:' || _request_ip();
  v_key2 text;
  v_fails int; v_all int; v_last timestamptz;
  s jsonb; u jsonb; v_h1 text; v_h2 text;
  v_tok text; v_exp timestamptz;
begin
  if v_role is null then return jsonb_build_object('ok', false, 'error', 'bad_role'); end if;
  if v_dev is null and not v_mgr then return jsonb_build_object('ok', false, 'error', 'device_not_paired'); end if;
  if v_dev is not null then
    select * into d from devices_pilot where id = v_dev;
    if d.id is null or d.assigned_role is null or coalesce(d.device_status, 'active') = 'retired' then
      return jsonb_build_object('ok', false, 'error', 'device_not_paired');
    end if;
    if not v_mgr and _worker_role_norm(d.assigned_role) is distinct from v_role then
      return jsonb_build_object('ok', false, 'error', 'wrong_station');
    end if;
  end if;
  v_key2 := 'wdev:' || coalesce(v_dev, 'mgr');

  delete from login_attempts where at < now() - interval '1 day';
  select count(*), max(at) into v_fails, v_last from login_attempts
   where ip in (v_ip, v_key2) and not ok and at > now() - interval '15 minutes';
  if v_fails >= 8 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited',
                              'retry_after', ceil(extract(epoch from (v_last + interval '15 minutes' - now()))));
  end if;
  select count(*) into v_all from login_attempts where not ok and at > now() - interval '15 minutes';
  if v_all >= 30 then perform pg_sleep(least(3.0, v_all / 30.0)); end if;

  select settings into s from settings_pilot where id = 1;
  if p_code is not null and trim(p_code) <> '' and jsonb_typeof(s -> 'users') = 'array' then
    v_h1 := _worker_code_hash(trim(p_code));
    v_h2 := case when coalesce(s ->> 'codeSalt', '') <> ''
                 then encode(digest('gt1:' || (s ->> 'codeSalt') || ':' || trim(p_code), 'sha256'), 'hex') end;
    select x into u from jsonb_array_elements(s -> 'users') x
     where jsonb_typeof(x) = 'object'
       and _worker_role_norm(x ->> 'role') = v_role
       and (p_name is null or x ->> 'name' = p_name)
       and coalesce(x ->> 'name', '') <> ''
       and (x ->> 'codeHash' = v_h1 or (v_h2 is not null and x ->> 'codeHash' = v_h2))   -- step 46: hashes only
     limit 1;
  end if;
  if u is null then
    insert into login_attempts (ip, ok) values (v_ip, false), (v_key2, false);
    perform pg_sleep(0.3);
    return jsonb_build_object('ok', false, 'error', 'code_invalid', 'attempts_left', greatest(0, 7 - v_fails));
  end if;
  delete from login_attempts where ip in (v_ip, v_key2);

  update worker_sessions set revoked = true, revoked_at = now()
   where not revoked and ((v_dev is not null and device_id = v_dev)
                          or (v_dev is null and mgr_session_hash = encode(digest(v_mt, 'sha256'), 'hex')));
  delete from worker_sessions where expires_at < now() - interval '2 days';
  v_tok := encode(gen_random_bytes(24), 'hex');
  insert into worker_sessions (token_hash, device_id, mgr_session_hash, test_mode, name, role)
  values (encode(digest(v_tok, 'sha256'), 'hex'), v_dev,
          case when v_dev is null then encode(digest(v_mt, 'sha256'), 'hex') end,
          v_mgr and (v_dev is null or _worker_role_norm(d.assigned_role) is distinct from v_role),
          left(u ->> 'name', 60), v_role)
  returning expires_at into v_exp;

  perform _security_event(null, 'worker_login', jsonb_build_object('role', v_role, 'testMode', v_dev is null or v_mgr),
                          left(u ->> 'name', 60), coalesce(v_dev, 'team-leader'));
  return jsonb_build_object('ok', true, 'token', v_tok, 'name', left(u ->> 'name', 60), 'role', v_role, 'expires_at', v_exp);
end $$;
revoke execute on function worker_login(text, text, text) from public;
grant execute on function worker_login(text, text, text) to anon, authenticated;

-- ── 8. a ruling's time changes only with the ruling ───────────────────────────
-- (v10.26: replaced further down, §27–§29)
create or replace function animals_pilot_guard_corrections() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_eso boolean; v_inner_final boolean;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;
  v_eso := coalesce(current_setting('gt.eso_ruling', true), '') = 'true'
           or coalesce(current_setting('gt.eso_upsert_row', true), '') = new.id::text;
  if coalesce(current_setting('gt.eso_upsert_row', true), '') <> '' then
    perform set_config('gt.eso_upsert_row', '', true);
  end if;
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  v_dev := _acting_device();

  -- step 46: a ruling's time changes only with the ruling itself — a write that
  -- moves only the time keeps the recorded one (and so can't move the device's
  -- "last animal" cursor back to reopen a correction after it moved on)
  if not v_eso and old.slaughter is not null and new.slaughter_time is distinct from old.slaughter_time
     and (new.slaughter, new.slaughtered_by, new.slaughter_by_device)
         is not distinct from (old.slaughter, old.slaughtered_by, old.slaughter_by_device) then
    new.slaughter_time := old.slaughter_time;
  end if;
  if old.inner_status in ('confirmed', 'treif') and new.inner_time is distinct from old.inner_time
     and (new.inner_status, new.inner_by, new.inner_by_device, coalesce(new.not_chalak_inner, false))
         is not distinct from (old.inner_status, old.inner_by, old.inner_by_device, coalesce(old.not_chalak_inner, false)) then
    new.inner_time := old.inner_time;
  end if;
  if old.outer_status is not null and new.outer_time is distinct from old.outer_time
     and (new.outer_status, new.outer_by, new.outer_by_device)
         is not distinct from (old.outer_status, old.outer_by, old.outer_by_device) then
    new.outer_time := old.outer_time;
  end if;

  if old.eso_result = 'nevela' and new.slaughter is distinct from old.slaughter and not v_eso then
    raise exception 'GT:ESO_LOCKED correction-blocked: failed the esophagus check — only the esophagus screen can change it'
      using errcode = 'P0001';
  end if;
  if not v_eso and old.slaughter is not null
     and (new.slaughter, new.slaughtered_by, new.slaughter_by_device)
         is distinct from (old.slaughter, old.slaughtered_by, old.slaughter_by_device) then
    perform _raise_correction(_correction_check('slaughter', old, v_dev), 'slaughter');
  end if;
  if coalesce(old.eso_checked, false)
     and (new.eso_result is distinct from old.eso_result or new.eso_by_device is distinct from old.eso_by_device) then
    perform _raise_correction(_correction_check('eso', old, v_dev), 'esophagus');
  end if;
  v_inner_final := old.inner_status in ('confirmed', 'treif');
  if v_inner_final
     and ((new.inner_status, new.inner_by, new.inner_by_device) is distinct from (old.inner_status, old.inner_by, old.inner_by_device)
          or coalesce(new.not_chalak_inner, false) is distinct from coalesce(old.not_chalak_inner, false)
          or (old.maw is not null and new.maw is distinct from old.maw)
          or (old.rumen is not null and new.rumen is distinct from old.rumen)) then
    perform _raise_correction(_correction_check('inner', old, v_dev), 'inner');
  end if;
  if old.outer_status is not null
     and (new.outer_status, new.outer_by, new.outer_by_device) is distinct from (old.outer_status, old.outer_by, old.outer_by_device) then
    perform _raise_correction(_correction_check('outer', old, v_dev), 'outer');
  end if;
  return new;
end $$;
revoke execute on function animals_pilot_guard_corrections() from public, anon, authenticated;

-- ── 9. each archived day keeps the status definitions it was ruled with ──────
alter table daily_board_archive add column if not exists statuses jsonb;
create or replace function archive_days(p_token text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text := coalesce(_session_role(p_token), '');
begin
  if v_role not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    return jsonb_build_object('ok', false, 'error', 'bad_range');
  end if;
  return jsonb_build_object('ok', true, 'days', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', d.id,
             'date', coalesce(d.business_date, (d.archived_at at time zone 'UTC')::date),
             'at', d.archived_at,
             'reason', d.reason,
             'intake', coalesce(d.intake, '[]'::jsonb),
             'statuses', d.statuses,                                  -- step 46: the definitions that day was ruled with
             'animals', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'n',   (x ->> 'id')::int,
                        's',   x ->> 'slaughter',
                        'i',   x ->> 'inner_status',
                        'o',   x ->> 'outer_status',
                        'sb',  x ->> 'slaughtered_by',
                        'ib',  x ->> 'inner_by',
                        'ob',  x ->> 'outer_by',
                        'st',  (x ->> 'slaughter_time'),
                        'nci', coalesce((x ->> 'not_chalak_inner')::boolean, false),
                        'nco', coalesce((x ->> 'not_chalak_outer')::boolean, false),
                        'nc',  (coalesce((x ->> 'not_chalak_inner')::boolean, false) or coalesce((x ->> 'not_chalak_outer')::boolean, false)),
                        'ncp', coalesce((x ->> 'nc_plain')::boolean, false),
                        'wr',  coalesce(x -> 'weight_right', 'null'::jsonb),
                        'wl',  coalesce(x -> 'weight_left', 'null'::jsonb)
                      ) order by (x ->> 'id')::int)
                 from jsonb_array_elements(d.board) x
                where x ->> 'slaughter' is not null), '[]'::jsonb)
           ) order by d.archived_at)
      from daily_board_archive d
     where coalesce(d.business_date, (d.archived_at at time zone 'UTC')::date) between p_from and p_to
       and exists (select 1 from jsonb_array_elements(d.board) y where y ->> 'slaughter' is not null)
  ), '[]'::jsonb));
end $$;
revoke execute on function archive_days(text, date, date) from public;
grant execute on function archive_days(text, date, date) to anon, authenticated;

-- ── 10. writes to today's board never run in the middle of a daily reset ─────
-- Every function that writes to animals_pilot takes this SHARED lock first (writers
-- don't wait for each other); the daily reset (request_daily_rollover /
-- reset_daily_board) takes the same key EXCLUSIVELY. A write that was running
-- finishes before the reset copies the board; a write that arrives during the reset
-- waits and then finds the new day (stale_board) — nothing slips in between the
-- copy to the archive / kept day and the clearing of the board.
create or replace function _board_write_lock() returns void
language sql volatile set search_path = public, extensions, pg_temp as $$
  select pg_advisory_xact_lock_shared(hashtext('glatttrack_daily_rollover'));
$$;
revoke execute on function _board_write_lock() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  a animals_pilot%rowtype;
  v_rows integer := 0;
  v_epoch bigint := _board_epoch();
  v_dev text;
  v_err text;
  v_res jsonb;
  v_wait int;
begin
  if p_result is null or p_result not in ('ok','nevela') then
    return jsonb_build_object('ok', false, 'error', 'bad_result');
  end if;
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  perform _board_write_lock();                      -- step 46: never in the middle of a daily reset
  v_epoch := _board_epoch();
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  v_dev := _call_device(p_device_id);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  if not _stage_allowed('eso') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  v_res := _cmd_get(p_command_id, v_dev, 'eso_change');
  if v_res is not null then return v_res; end if;
  select * into a from animals_pilot where id = p_id for update;
  if a.id is null or a.eso_checked is distinct from true then
    v_res := jsonb_build_object('ok', false, 'error', 'not_checked');
    perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
    return v_res;
  end if;
  if coalesce(a.board_epoch, 0) > coalesce(v_epoch, 0) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', a.board_epoch);
  end if;
  if a.eso_result = p_result then
    v_res := jsonb_build_object('ok', true, 'row', to_jsonb(a));
    perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
    return v_res;
  end if;
  if _is_api_request() and not _request_is_service_role() then
    v_wait := _correction_braked(v_dev);
    if v_wait is not null then
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'retry_after', v_wait, 'row', to_jsonb(a));
    end if;
    v_err := _correction_check('eso', a, v_dev);
    if v_err is not null then
      perform _log_correction_rejected(v_dev, p_id, 'esophagus', v_err,
                                       jsonb_build_object('from', a.eso_result, 'to', p_result, 'via', 'eso_change'));
      v_res := jsonb_build_object('ok', false, 'error', v_err, 'row', to_jsonb(a));
      perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
      return v_res;
    end if;
  end if;
  perform set_config('gt.eso_ruling', 'true', true);
  if p_result = 'nevela' then
    update animals_pilot
       set eso_result = 'nevela', eso_prev_slaughter = slaughter, slaughter = 'nevela',
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev,
           eso_by_device = coalesce(eso_by_device, v_dev),
           device_id = v_dev, updated_at = now()
     where id = p_id and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  else
    update animals_pilot
       set eso_result = 'ok', slaughter = coalesce(eso_prev_slaughter, 'slaughtered'),
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev,
           eso_by_device = coalesce(eso_by_device, v_dev),
           device_id = v_dev, updated_at = now()
     where id = p_id and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  end if;
  get diagnostics v_rows = row_count;
  perform set_config('gt.eso_ruling', '', true);
  select * into a from animals_pilot where id = p_id;
  v_res := jsonb_build_object('ok', v_rows = 1, 'row', to_jsonb(a));
  perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
  return v_res;
end $$;

CREATE OR REPLACE FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text, p_command_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_epoch bigint := _board_epoch();
  v_dev text;
  v_rows integer;
  v_res jsonb;
  r record;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  perform _board_write_lock();                      -- step 46: never in the middle of a daily reset
  v_epoch := _board_epoch();
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  v_dev := _call_device(p_device_id);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  if not _stage_allowed('outer') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  v_res := _cmd_get(p_command_id, v_dev, 'outer_open');
  if v_res is not null then return v_res; end if;

  perform set_config('gt.outer_open', 'true', true);
  if coalesce(p_open, false) then
    update animals_pilot
       set outer_open_by_device = v_dev, outer_open_at = v_now, updated_at = now()
     where id = p_id
       and (outer_open_by_device is null or outer_open_by_device = v_dev
            or outer_open_at is null or outer_open_at < v_now - 120000)
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  else
    update animals_pilot
       set outer_open_by_device = null, outer_open_at = null, updated_at = now()
     where id = p_id and outer_open_by_device = v_dev
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  end if;
  get diagnostics v_rows = row_count;
  perform set_config('gt.outer_open', '', true);

  select outer_open_by_device, outer_open_at into r from animals_pilot where id = p_id;
  v_res := jsonb_build_object('ok', true, 'claimed', (coalesce(p_open, false) and v_rows = 1),
                              'by', r.outer_open_by_device, 'at', r.outer_open_at, 'serverNow', v_now);
  perform _cmd_put(p_command_id, v_dev, 'outer_open', v_res);
  return v_res;
end $$;

CREATE OR REPLACE FUNCTION public.lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare v_epoch bigint := _board_epoch(); v_dev text;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  perform _board_write_lock();                      -- step 46: never in the middle of a daily reset
  v_epoch := _board_epoch();
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  v_dev := _call_device(null);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  if not _stage_allowed('inner') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  if p_drawing is null or p_drawing = '' then
    delete from lung_drawings where id = p_id;
    return jsonb_build_object('ok', true, 'deleted', true);
  end if;
  if length(p_drawing) > 450000
     or p_drawing !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' then
    return jsonb_build_object('ok', false, 'error', 'bad_picture');
  end if;
  delete from lung_drawings where board_epoch is distinct from v_epoch;   -- yesterday's pictures
  insert into lung_drawings (id, board_epoch, drawing, device_id, updated_at)
       values (p_id, v_epoch, p_drawing, v_dev, now())
  on conflict (id) do update
     set board_epoch = excluded.board_epoch, drawing = excluded.drawing,
         device_id = excluded.device_id, updated_at = now();
  return jsonb_build_object('ok', true);
end $_$;

-- ── 11. the first team leader: through the app only with the setup code ──────
-- the setup code is stored and compared the same way: letters and digits only,
-- upper case ('ABCD-1234-XY' = 'abcd 1234 xy' = 'ABCD1234XY')
create or replace function _setup_code_norm(p text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g'));
$$;
revoke execute on function _setup_code_norm(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._set_setup_code(p_code text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if length(_setup_code_norm(p_code)) < 8 then raise exception 'setup code too short (at least 8 letters / digits)'; end if;
  insert into plant_state (key, value) values ('setupCodeHash', crypt(_setup_code_norm(p_code), gen_salt('bf')))
    on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;
revoke execute on function _set_setup_code(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_first_manager(p_name text, p_code text, p_setup_code text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_id uuid; v_hash text; v_ip text := _request_ip(); v_fails int;
begin
  perform pg_advisory_xact_lock(hashtext('glatttrack_first_manager'));
  if exists(select 1 from plant_managers where role = 'manager' and active) then
    return jsonb_build_object('ok', false, 'error', 'a manager already exists — use manager_add instead');
  end if;
  select value into v_hash from plant_state where key = 'setupCodeHash';
  -- step 46: through the app only with the one-time setup code; a plant whose
  -- installation set none creates its first team leader from the server (SQL)
  if v_hash is null and _is_api_request() and not _request_is_service_role() then
    return jsonb_build_object('ok', false, 'error', 'setup_code_not_configured');
  end if;
  if v_hash is not null then
    select count(*) into v_fails from login_attempts where ip = v_ip and not ok and at > now() - interval '15 minutes';
    if v_fails >= 8 then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
    if p_setup_code is null or p_setup_code = '' then
      return jsonb_build_object('ok', false, 'error', 'setup_code_required');
    end if;
    -- the code as printed (dashes / spaces / case do not matter); a hash made by the
    -- old _set_setup_code (dashes kept) is still accepted
    if crypt(_setup_code_norm(p_setup_code), v_hash) <> v_hash and crypt(upper(p_setup_code), v_hash) <> v_hash then
      insert into login_attempts (ip, ok) values (v_ip, false);
      perform pg_sleep(0.4);
      return jsonb_build_object('ok', false, 'error', 'setup_code_wrong');
    end if;
  end if;
  if p_code is null or length(p_code) < 6 then                       -- step 46: 6 characters
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 6 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'manager')
    returning id into v_id;
  delete from plant_state where key = 'setupCodeHash';          -- one time only
  perform set_config('app.device_admin', 'on', true);
  insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
  values (gen_random_uuid(), null, 'security', 'first_manager_created',
          jsonb_build_object('ip', v_ip, 'withSetupCode', v_hash is not null), left(trim(p_name), 60), 'server', now()::text);
  perform set_config('app.device_admin', '', true);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ── 12. team-leader / owner codes: at least 6 characters (new codes) ─────────
CREATE OR REPLACE FUNCTION public.manager_add(p_token text, p_name text, p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_id uuid;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_code is null or length(p_code) < 6 then                       -- step 46: 6 characters
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 6 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'manager')
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

CREATE OR REPLACE FUNCTION public.manager_add_owner(p_token text, p_name text, p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_id uuid;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if coalesce(trim(p_name), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'name required');
  end if;
  if p_code is null or length(p_code) < 6 then                       -- step 46: 6 characters
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 6 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'owner')
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ── 13. statuses: no two with the same key ────────────────────────────────────
CREATE OR REPLACE FUNCTION public._settings_value_error(p_key text, v jsonb) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare t text := jsonb_typeof(v); e jsonb; s text;
begin
  if v is null or t = 'null' then return null; end if;
  if length(v::text) > 1500000 then return 'too_large'; end if;
  -- times
  if p_key = 'autoResetTime' then
    if t = 'string' and ((v #>> '{}') = '' or (v #>> '{}') ~ '^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$') then return null; end if;
    return 'expected HH:MM';
  end if;
  if p_key = 'plantTimezone' then
    s := v #>> '{}';
    if t = 'string' and (s = '' or (length(s) <= 64 and exists (select 1 from pg_timezone_names where name = s))) then return null; end if;
    return 'unknown time zone';
  end if;
  -- whole numbers in sane ranges
  if p_key in ('beepSeconds', 'legStickerCount', 'headStickerCount', 'partsStickerCount', 'numInspectors', 'inspectorMode', 'maxAnimals',
               'dailyTarget', 'archiveDays', 'esoFromIdx') then
    if _jint_ok(v, case p_key when 'numInspectors' then 1 when 'inspectorMode' then 1 when 'maxAnimals' then 1
                              when 'archiveDays' then 1 when 'beepSeconds' then 1 else 0 end,
                   case p_key when 'beepSeconds' then 3600 when 'legStickerCount' then 999 when 'headStickerCount' then 999 when 'partsStickerCount' then 999
                              when 'numInspectors' then 20 when 'inspectorMode' then 10 when 'maxAnimals' then 1000
                              when 'dailyTarget' then 100000 when 'archiveDays' then 3650 when 'esoFromIdx' then 1000 end) then
      return null;
    end if;
    return 'expected a whole number in range';
  end if;
  if p_key = 'beepVolume' then
    if _jnum_ok(v, 0, 100) then return null; end if; return 'expected 0..100';
  end if;
  if p_key = 'beepFreq' then
    if _jnum_ok(v, 20, 20000) then return null; end if; return 'expected 20..20000';
  end if;
  if p_key = 'beepType' then
    if t = 'string' and (v #>> '{}') ~ '^[a-z]{0,20}$' then return null; end if; return 'expected a sound type';
  end if;
  -- on / off switches
  if p_key in ('rumenCheck', 'legsMode', 'licenseRequestDismissed', 'slaughterExternalOnly', 'beepFlash')
     or p_key ~ '^[a-z][A-Za-z0-9]*Enabled$' then
    if t = 'boolean' then return null; end if; return 'expected true/false';
  end if;
  -- languages
  if p_key = 'activeLangs' then
    if t = 'array' and jsonb_array_length(v) <= 3
       and not exists (select 1 from jsonb_array_elements(v) x where jsonb_typeof(x) <> 'string' or (x #>> '{}') not in ('he', 'en', 'es')) then
      return null;
    end if;
    return 'expected a list of he / en / es';
  end if;
  if p_key in ('lang', 'language', 'defaultLang') then
    if t = 'string' and (v #>> '{}') in ('he', 'en', 'es') then return null; end if; return 'expected he / en / es';
  end if;
  -- worker login modes
  if p_key = 'loginMode' then
    if t = 'string' and (v #>> '{}') in ('none', 'name', 'code', 'both') then return null; end if; return 'expected none/name/code/both';
  end if;
  if p_key = 'loginModeByRole' then
    if t = 'object' and not exists (select 1 from jsonb_each(v) x
                                     where length(x.key) > 30
                                        or not (jsonb_typeof(x.value) = 'null'
                                                or (jsonb_typeof(x.value) = 'string' and (x.value #>> '{}') in ('none', 'name', 'code', 'both')))) then
      return null;
    end if;
    return 'expected {role: none/name/code/both}';
  end if;
  if p_key = 'screenConfig' then
    if t = 'string' and (v #>> '{}') ~ '^[0-9A-Za-z_]{1,16}$' then return null; end if; return 'expected a screen layout';
  end if;
  -- lists of objects with the expected fields
  if p_key = 'users' then
    if t <> 'array' or jsonb_array_length(v) > 500 then return 'expected a list of workers'; end if;
    for e in select value from jsonb_array_elements(v) loop
      if jsonb_typeof(e) <> 'object'
         or jsonb_typeof(e -> 'name') is distinct from 'string' or length(trim(e ->> 'name')) = 0 or length(e ->> 'name') > 100
         or (e ? 'role' and not _jstr_ok(e -> 'role', 40))
         or (e ? 'role' and _worker_role_norm(e ->> 'role') is null and e ->> 'role' <> 'manager')   -- step 46: one list per screen
         or (e ? 'code' and not (jsonb_typeof(e -> 'code') in ('string', 'number', 'null') and length(e ->> 'code') <= 40))
         or (e ? 'codeHash' and not _jstr_ok(e -> 'codeHash', 128)) then
        return 'expected workers {name, role, code/codeHash}';
      end if;
    end loop;
    return null;
  end if;
  if p_key = 'dailyIntake' then
    if t <> 'array' or jsonb_array_length(v) > 300 then return 'expected a list of intake lines'; end if;
    for e in select value from jsonb_array_elements(v) loop
      if jsonb_typeof(e) <> 'object'
         or not _jint_ok(e -> 'qty', 0, 1000)
         or (e ? 'farm' and not (jsonb_typeof(e -> 'farm') in ('string', 'number', 'null') and length(e ->> 'farm') <= 120))
         or (e ? 'type' and not (jsonb_typeof(e -> 'type') in ('string', 'number', 'null') and length(e ->> 'type') <= 120)) then
        return 'expected intake lines {farm, type, qty 0..1000}';
      end if;
    end loop;
    return null;
  end if;
  if p_key = 'customStatuses' then
    if t <> 'array' or jsonb_array_length(v) > 200 then return 'expected a list of statuses'; end if;
    if (select count(*) <> count(distinct x ->> 'key') from jsonb_array_elements(v) x) then   -- step 46
      return 'two statuses with the same key';
    end if;
    for e in select value from jsonb_array_elements(v) loop
      if jsonb_typeof(e) <> 'object'
         or jsonb_typeof(e -> 'key') is distinct from 'string' or (e ->> 'key') !~ '^[A-Za-z0-9_-]{1,60}$'
         or (e ? 'he' and not _jstr_ok(e -> 'he', 80)) or (e ? 'en' and not _jstr_ok(e -> 'en', 80))
         or (e ? 'es' and not _jstr_ok(e -> 'es', 80)) or (e ? 'color' and not _jstr_ok(e -> 'color', 40))
         or (e ? 'kosher' and jsonb_typeof(e -> 'kosher') not in ('boolean', 'null'))
         or (e ? 'removed' and jsonb_typeof(e -> 'removed') not in ('boolean', 'null')) then
        return 'expected statuses {key, he, en, es, color, kosher}';
      end if;
    end loop;
    return null;
  end if;
  if p_key in ('disabledStatuses', 'removedDefaults', 'statusOptIn') then
    if t = 'array' and jsonb_array_length(v) <= 500
       and not exists (select 1 from jsonb_array_elements(v) x where not _jstr_ok(x, 80) or jsonb_typeof(x) = 'null') then
      return null;
    end if;
    return 'expected a list of status keys';
  end if;
  if p_key in ('reprintLog', 'problemReports', 'errorLog') then
    if t = 'array' and jsonb_array_length(v) <= 5000
       and not exists (select 1 from jsonb_array_elements(v) x where jsonb_typeof(x) <> 'object') then
      return null;
    end if;
    return 'expected a list of records';
  end if;
  if p_key in ('loginModeByRole', 'activeUserByRole', 'statusColorOverrides', 'slaughterKeys', 'screenDevices',
               'weightMethods', 'archiveSettings') then
    if t = 'object' then return null; end if; return 'expected an object';
  end if;
  if p_key = 'currentUser' then
    if t in ('object', 'string') then return null; end if; return 'expected a worker';
  end if;
  return null;
end $_$;

-- ── 14. the team leader only from a team-leader device ───────────────────────
-- A new pairing role 'leader' (slots 0..3): a device of the team leader. It has no
-- station, so it has no ruling rights. manager_login for a team leader succeeds only
-- on such a device once the plant has one ('leader_device_required' otherwise —
-- counted as a failed login and recorded). Until the first one exists (installation)
-- any device may log in, and the app pairs that device as the first team-leader
-- device (the session moves onto it). Owner and manufacturer logins are unchanged.
alter table devices_pilot drop constraint if exists devices_pilot_role_ok;
alter table devices_pilot add constraint devices_pilot_role_ok check (assigned_role is null or assigned_role = any (array[
  'slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps', 'display', 'leader']));

create or replace function _is_leader_device(p_dev text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select p_dev is not null and exists (
    select 1 from devices_pilot d join device_credentials c on c.device_id = d.id and not c.revoked
     where d.id = p_dev and d.assigned_role = 'leader' and coalesce(d.device_status, 'active') <> 'retired');
$$;
revoke execute on function _is_leader_device(text) from public, anon, authenticated;

-- true once the plant has (or ever had) a team-leader device: the rule never
-- switches itself off when the last one is removed (only leader_device_recovery())
create or replace function _leader_devices_exist() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (select 1 from devices_pilot d join device_credentials c on c.device_id = d.id and not c.revoked
                  where d.assigned_role = 'leader' and coalesce(d.device_status, 'active') <> 'retired')
      or coalesce((select value from plant_state where key = 'leaderDevicesRequired'), '') = '1';
$$;
revoke execute on function _leader_devices_exist() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public._gt_value_ok(p_kind text, v text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
  select v is null or case p_kind
    when 'slaughter' then v in ('slaughtered', 'shot', 'nevela', 'notChalak')
    when 'inner'     then v in ('in_progress', 'confirmed', 'treif')
    when 'outer'     then v in ('glatt', 'beit', 'kosher', 'mk', 'treif', 'rabChalak') or v ~ '^custom_[A-Za-z0-9_-]{1,40}$'
    when 'printed'   then v in ('glatt', 'beit', 'kosher', 'mk', 'treif', 'rabChalak', 'kosherRab') or v ~ '^custom_[A-Za-z0-9_-]{1,40}$'
    when 'eso'       then v in ('ok', 'nevela')
    when 'maw'       then v in ('kosher', 'treif')
    when 'device_role' then v in ('slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps', 'display', 'leader')
    else false end;
$_$;

CREATE OR REPLACE FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer DEFAULT 0, p_replace boolean DEFAULT false, p_device_name text DEFAULT NULL::text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare r device_pairing%rowtype; v_idx int; v_tok text; v_old record; v_repl uuid; v_actor text; v_why text;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_role not in ('slaughter','esophagus','legs','inner','outer','parts','stamps','display','leader') then
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;
  v_idx := case when p_role in ('inner','outer','display','leader') then coalesce(p_index, 0) else 0 end;
  if (p_role in ('display', 'leader') and v_idx not between 0 and 3) or (p_role not in ('display', 'leader') and v_idx not in (0, 1)) then
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
  -- step 46: the first team-leader device of a plant — the session that pairs it (made
  -- before any team-leader device existed, so bound to no device) moves onto that device
  if p_role = 'leader' then
    update manager_sessions set device_id = r.device_id
     where token = p_token and device_id is null and expires_at > now();
    insert into plant_state (key, value) values ('leaderDevicesRequired', '1')
      on conflict (key) do update set value = '1', updated_at = now();
  end if;

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

CREATE OR REPLACE FUNCTION public.manager_login(p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare
  v_manager plant_managers%rowtype;
  v_token text;
  v_expires timestamptz;
  v_ip text := _request_ip();
  v_fails int;
  v_all int;
  v_last timestamptz;
begin
  delete from login_attempts where at < now() - interval '1 day';
  select count(*), max(at) into v_fails, v_last from login_attempts
   where ip = v_ip and not ok and at > now() - interval '15 minutes';
  if v_fails >= 8 then
    return jsonb_build_object('ok', false, 'reason', 'locked',
                              'retry_after', ceil(extract(epoch from (v_last + interval '15 minutes' - now()))));
  end if;
  select count(*) into v_all from login_attempts where not ok and at > now() - interval '15 minutes';
  if v_all >= 30 then perform pg_sleep(least(3.0, v_all / 30.0)); end if;

  if length(p_code) > 200 then p_code := null; end if;          -- (a code is never that long)
  select * into v_manager from plant_managers
    where active and code_hash = crypt(p_code, code_hash)
    order by (role = 'manager') desc
    limit 1;
  if v_manager.id is null then
    if not exists(select 1 from plant_managers where role = 'manager' and active) then
      return jsonb_build_object('ok', false, 'reason', 'no_managers');
    end if;
    insert into login_attempts (ip, ok) values (v_ip, false);
    perform pg_sleep(0.4);
    return jsonb_build_object('ok', false, 'reason', 'wrong_code', 'attempts_left', greatest(0, 7 - v_fails));
  end if;
  -- step 46: the team leader works only from a team-leader device (paired with the role
  -- 'leader'). Until the plant has one (installation) any device may log in — the app
  -- then registers that device as the first team-leader device.
  if v_manager.role = 'manager' and _is_api_request() and not _request_is_service_role()
     and _leader_devices_exist() and not _is_leader_device(_current_device_id()) then
    insert into login_attempts (ip, ok) values (v_ip, false);
    perform _security_event(null, 'leader_device_required', jsonb_build_object('ip', v_ip, 'device', _current_device_id()),
                            v_manager.name, coalesce(_current_device_id(), 'unpaired'));
    return jsonb_build_object('ok', false, 'reason', 'leader_device_required');
  end if;
  -- step 46 (5th review): a station tablet is only for its station — the owner and the
  -- manufacturer watch from any other device, never from a station tablet
  if v_manager.role in ('owner', 'manufacturer') and _is_api_request() and not _request_is_service_role()
     and exists (select 1 from devices_pilot where id = _current_device_id()
                   and assigned_role in ('slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps')
                   and coalesce(device_status, 'active') <> 'retired') then
    perform _security_event(null, 'login_on_station_device', jsonb_build_object('ip', v_ip, 'device', _current_device_id(), 'role', v_manager.role),
                            v_manager.name, _current_device_id());
    return jsonb_build_object('ok', false, 'reason', 'station_device');
  end if;
  -- the manufacturer's code opens every plant: while wrong codes are being tried
  -- here, or after 6 manufacturer logins in an hour, it is locked for a while
  if v_manager.role = 'manufacturer' then
    if v_all >= 20 or _rate_count('maker_login', null, interval '1 hour') >= 6 then
      return jsonb_build_object('ok', false, 'reason', 'locked', 'retry_after', 900);
    end if;
    perform _rate_hit('maker_login', v_ip);
  end if;
  delete from login_attempts where ip = v_ip;
  -- bound to the device key and the app session it is made with
  insert into manager_sessions (manager_id, auth_uid, device_id, expires_at)
  values (v_manager.id, _auth_uid_safe(), _current_device_id(), now() + interval '10 hours')
    returning token, expires_at into v_token, v_expires;
  if v_manager.role = 'manufacturer' then
    v_expires := _maker_session_end();
    update manager_sessions set expires_at = v_expires where token = v_token;
    perform _admin_audit(v_token, 'login', 'plant', jsonb_build_object('ip', v_ip));
  end if;
  return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name,
                            'role', v_manager.role, 'expires_at', v_expires,
                            'repairAccess', _support_access_open(),
                            'leaderDevice', _is_leader_device(_current_device_id()),
                            'registerLeaderDevice', v_manager.role = 'manager' and not _leader_devices_exist());
end $$;

CREATE OR REPLACE FUNCTION public._device_write_allowed() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_dev text; v_ok boolean;
begin
  if not _is_api_request() then return true; end if;                    -- SQL editor / server jobs
  if _request_is_service_role() then return true; end if;                -- server-side code with the service key
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  -- step 46 (5th review): an owner / view-only manufacturer session writes nothing, also not
  -- through the station device it is on
  if _session_view_only(_request_headers() ->> 'x-manager-token') then perform _note_revoked_write(_current_device_id()); return false; end if;
  if _request_has_manager() then return true; end if;                    -- team leader (events / settings only; rulings: _stage_allowed)
  v_dev := _current_device_id();
  if v_dev is null then perform _note_revoked_write(); return false; end if;
  v_ok := exists(select 1 from devices_pilot
                  where id = v_dev and assigned_role is not null
                    and assigned_role not in ('display', 'leader')       -- a counter screen only reads; a team-leader device writes only with the team leader's session
                    and coalesce(device_status, 'active') <> 'retired');
  if not v_ok then perform _note_revoked_write(v_dev); end if;
  return v_ok;
end $$;


-- a plant that already has a team-leader device keeps the rule from now on
insert into plant_state (key, value)
  select 'leaderDevicesRequired', '1'
   where exists (select 1 from devices_pilot d join device_credentials c on c.device_id = d.id and not c.revoked
                  where d.assigned_role = 'leader' and coalesce(d.device_status, 'active') <> 'retired')
  on conflict (key) do update set value = '1', updated_at = now();

-- every team-leader device lost / broken: only from the server (SQL editor, by the
-- installer). Every team-leader device is disconnected (key revoked, its team-leader
-- sessions ended — a lost phone cannot be used afterwards), and the next team leader
-- to log in registers his device as the first one again.
drop function if exists leader_device_recovery();
create or replace function leader_device_recovery(p_reason text default 'team-leader device lost / broken')
returns text
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d record; n int := 0; v_why text := left(coalesce(nullif(trim(p_reason), ''), 'team-leader device lost / broken'), 200);
begin
  if _is_api_request() then raise exception 'server only'; end if;
  perform set_config('gt.audit_actor', 'server', true);
  perform set_config('gt.audit_reason', v_why, true);
  perform set_config('app.device_admin', 'on', true);
  for d in select id, assigned_role, assigned_index from devices_pilot where assigned_role = 'leader' loop
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now() where id = d.id;
    update device_credentials set revoked = true, revoked_at = coalesce(revoked_at, now()) where device_id = d.id and not revoked;
    delete from manager_sessions where device_id = d.id;
    perform _audit_device_event(d.id, 'UNASSIGNED', d.assigned_role, d.assigned_index, v_why, null, null, 'server');
    n := n + 1;
  end loop;
  perform set_config('app.device_admin', '', true);
  perform set_config('gt.audit_actor', '', true);
  perform set_config('gt.audit_reason', '', true);
  delete from plant_state where key = 'leaderDevicesRequired';
  perform _security_event(null, 'leader_device_recovery', jsonb_build_object('disconnected', n, 'reason', v_why), 'server', 'server');
  return format('ok — %s team-leader device(s) disconnected. The next team leader to log in registers his device as the team-leader device.', n);
end $$;
revoke execute on function leader_device_recovery(text) from public, anon, authenticated;

-- ── 15. accounts: team leaders only from the server; owners by the team leader ──
-- The team leader cannot add (or remove) a team leader. The owner only watches —
-- he changes nothing, accounts included. Team-leader accounts are added / removed
-- only on the server (SQL editor, by the installer):
--   select leader_account_add('name', 'code-of-6-or-more');
--   select leader_account_remove('name');
-- Owner (view-only) accounts: the team leader adds / removes them in the app.
CREATE OR REPLACE FUNCTION public.manager_add(p_token text, p_name text, p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if _session_role(p_token) is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', false, 'error', 'server_only');   -- leader_account_add() on the server
end $$;

create or replace function leader_account_add(p_name text, p_code text) returns text
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if _is_api_request() then raise exception 'server only'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name required'; end if;
  if p_code is null or length(p_code) < 6 then raise exception 'code too short (minimum 6 characters)'; end if;
  if _code_in_use(p_code) then raise exception 'this code is already in use — choose another'; end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'manager')
    returning id into v_id;
  perform _security_event(null, 'account_added', jsonb_build_object('role', 'manager', 'id', v_id, 'name', left(trim(p_name), 60)), 'server', 'server');
  return 'ok — team leader "' || left(trim(p_name), 60) || '" added. He logs in only from a team-leader device (an existing team leader pairs one for him).';
end $$;
revoke execute on function leader_account_add(text, text) from public, anon, authenticated;

create or replace function leader_account_remove(p_name text) returns text
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid; n int;
begin
  if _is_api_request() then raise exception 'server only'; end if;
  select count(*), min(id::text)::uuid into n, v_id from plant_managers where role = 'manager' and active and name = trim(p_name);
  if n = 0 then raise exception 'no active team leader named "%"', p_name; end if;
  if n > 1 then raise exception 'more than one team leader named "%" — remove by id in plant_managers', p_name; end if;
  if (select count(*) from plant_managers where role = 'manager' and active) <= 1 then
    raise exception 'this is the last team leader — add another one first';
  end if;
  update plant_managers set active = false where id = v_id;
  delete from manager_sessions where manager_id = v_id;
  perform _security_event(null, 'account_removed', jsonb_build_object('role', 'manager', 'id', v_id, 'name', trim(p_name)), 'server', 'server');
  return 'ok — team leader "' || trim(p_name) || '" removed; his sessions ended.';
end $$;
revoke execute on function leader_account_remove(text) from public, anon, authenticated;

-- owner accounts (view-only): the team leader adds them
CREATE OR REPLACE FUNCTION public.manager_add_owner(p_token text, p_name text, p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_id uuid;
begin
  if not _is_real_manager(p_token) then                               -- the team leader only (never the owner)
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if coalesce(trim(p_name), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'name required');
  end if;
  if p_code is null or length(p_code) < 6 then
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 6 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'owner')
    returning id into v_id;
  perform _security_event(null, 'account_added', jsonb_build_object('role', 'owner', 'id', v_id, 'name', left(trim(p_name), 60)),
                          _session_name(p_token), 'team-leader');
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- the team leader removes owner accounts (e.g. an owner's phone was lost: remove,
-- add again with a new code — his sessions end at once); team leaders: server only
CREATE OR REPLACE FUNCTION public.manager_deactivate(p_token text, p_manager_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_role text; v_name text;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select role, name into v_role, v_name from plant_managers where id = p_manager_id and active;
  if v_role is null or v_role = 'manufacturer' then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_role = 'manager' then                                          -- a team leader: leader_account_remove() on the server
    return jsonb_build_object('ok', false, 'error', 'server_only');
  end if;
  update plant_managers set active = false where id = p_manager_id;
  delete from manager_sessions where manager_id = p_manager_id;
  perform _security_event(null, 'account_removed', jsonb_build_object('role', v_role, 'id', p_manager_id, 'name', v_name),
                          _session_name(p_token), 'team-leader');
  return jsonb_build_object('ok', true);
end $$;
-- the owner sees everything, the account list too (read only)
CREATE OR REPLACE FUNCTION public.manager_list(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not (_manager_session_valid(p_token) or coalesce(_session_role(p_token), '') = 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'accounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', role, 'active', active, 'created_at', created_at)
                     order by role, created_at)
    from plant_managers where active and role <> 'manufacturer'), '[]'::jsonb));
end $$;
revoke execute on function manager_list(text) from public;
grant execute on function manager_list(text) to anon, authenticated;
revoke execute on function manager_add(text, text, text) from public;
revoke execute on function manager_add_owner(text, text, text) from public;
revoke execute on function manager_deactivate(text, uuid) from public;
grant execute on function manager_add(text, text, text) to anon, authenticated;
grant execute on function manager_add_owner(text, text, text) to anon, authenticated;
grant execute on function manager_deactivate(text, uuid) to anon, authenticated;

-- ── 16. installation: does this plant still need its first team leader? ──────
-- (anyone may ask; the answer is only "yes / no" — manager_login says the same)
create or replace function plant_setup_needed() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when exists (select 1 from plant_managers where role = 'manager' and active)
              then jsonb_build_object('ok', true, 'needed', false)
              else jsonb_build_object('ok', true, 'needed', true,
                                      'setupCode', exists (select 1 from plant_state where key = 'setupCodeHash')) end;
$$;
revoke execute on function plant_setup_needed() from public;
grant execute on function plant_setup_needed() to anon, authenticated;


-- ── 18. one worker list per screen ───────────────────────────────────────────
create or replace function _worker_role_norm(p text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case lower(trim(coalesce(p, '')))
    when 'slaughter' then 'slaughter' when 'שוחט' then 'slaughter' when 'שוחטים' then 'slaughter'
    when 'esophagus' then 'esophagus' when 'וושט' then 'esophagus' when 'בדיקת וושט' then 'esophagus'
    when 'legs' then 'legs' when 'רגלים' then 'legs' when 'רגלים / ראש' then 'legs'
    when 'inner' then 'inner' when 'בודק פנים' then 'inner' when 'בודקי פנים' then 'inner'
    when 'outer' then 'outer' when 'בודק חוץ' then 'outer' when 'בודקי חוץ' then 'outer'
    when 'parts' then 'parts' when 'חלקים' then 'parts' when 'חלקים קטנים' then 'parts'
    when 'stamps' then 'stamps' when 'חותמות' then 'stamps'
    else null end;                         -- the old shared lists ('inspector', 'supervisor') no longer log in anywhere
$$;
revoke execute on function _worker_role_norm(text) from public, anon, authenticated;

-- the screen (worker list) that rules a stage
create or replace function _stage_worker_role(p_stage text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case p_stage when 'slaughter' then 'slaughter'
                      when 'eso' then 'esophagus' when 'esophagus' then 'esophagus'
                      when 'inner' then 'inner' when 'inner_start' then 'inner'
                      when 'outer' then 'outer' when 'not_chalak_outer' then 'outer'
                      when 'legs' then 'legs' when 'parts' then 'parts'
                      when 'stamped' then 'stamps' when 'stamps' then 'stamps' when 'weight' then 'stamps'
                      else (select _worker_role_norm(assigned_role) from devices_pilot where id = _current_device_id()) end;
$$;
revoke execute on function _stage_worker_role(text) from public, anon, authenticated;

-- worker sessions carry the screen
delete from worker_sessions where role not in ('slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps');
alter table worker_sessions drop constraint if exists worker_sessions_role_check;
alter table worker_sessions add constraint worker_sessions_role_check
  check (role in ('slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps'));

-- the old shared lists → one list per screen (copied to every screen of the old list)
do $$
declare st jsonb; u jsonb; out_users jsonb := '[]'::jsonb; modes jsonb; r text; legacy boolean := false; k text;
        inspector text[] := array['inner', 'outer'];
        supervisor text[] := array['esophagus', 'legs', 'parts', 'stamps'];
begin
  select settings into st from settings_pilot where id = 1;
  if st is null then return; end if;
  if jsonb_typeof(st -> 'users') = 'array' then
    for u in select value from jsonb_array_elements(st -> 'users') loop
      r := lower(trim(coalesce(u ->> 'role', '')));
      if r in ('inspector', 'בודק', 'בודקים') then
        legacy := true; foreach k in array inspector loop out_users := out_users || jsonb_build_array(jsonb_set(u, '{role}', to_jsonb(k))); end loop;
      elsif r in ('supervisor', 'משגיח', 'משגיחים') then
        legacy := true; foreach k in array supervisor loop out_users := out_users || jsonb_build_array(jsonb_set(u, '{role}', to_jsonb(k))); end loop;
      elsif jsonb_typeof(u) = 'object' and _worker_role_norm(u ->> 'role') is not null and u ->> 'role' <> _worker_role_norm(u ->> 'role') then
        out_users := out_users || jsonb_build_array(jsonb_set(u, '{role}', to_jsonb(_worker_role_norm(u ->> 'role'))));
      else
        out_users := out_users || jsonb_build_array(u);
      end if;
    end loop;
  end if;
  modes := case when jsonb_typeof(st -> 'loginModeByRole') = 'object' then st -> 'loginModeByRole' else '{}'::jsonb end;
  if modes ? 'inspector' then
    foreach k in array inspector loop if not modes ? k then modes := modes || jsonb_build_object(k, modes -> 'inspector'); end if; end loop;
    modes := modes - 'inspector'; legacy := true;
  end if;
  if modes ? 'supervisor' then
    foreach k in array supervisor loop if not modes ? k then modes := modes || jsonb_build_object(k, modes -> 'supervisor'); end if; end loop;
    modes := modes - 'supervisor'; legacy := true;
  end if;
  if legacy or jsonb_typeof(st -> 'users') = 'array' then
    update settings_pilot
       set settings = settings || jsonb_build_object('loginModeByRole', modes)
                    || case when jsonb_typeof(st -> 'users') = 'array' then jsonb_build_object('users', out_users) else '{}'::jsonb end
     where id = 1 and settings is distinct from (settings || jsonb_build_object('loginModeByRole', modes)
                    || case when jsonb_typeof(st -> 'users') = 'array' then jsonb_build_object('users', out_users) else '{}'::jsonb end);
  end if;
  if legacy then
    insert into plant_state (key, value) values ('workerListsCheck', '1') on conflict (key) do update set value = '1', updated_at = now();
  end if;
end $$;

-- the team leader saved the worker lists → the "check the lists" notice goes away
create or replace function _worker_lists_saved() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if _is_api_request() and new.settings -> 'users' is distinct from old.settings -> 'users' then
    delete from plant_state where key = 'workerListsCheck';
  end if;
  return new;
end $$;
revoke execute on function _worker_lists_saved() from public, anon, authenticated;
drop trigger if exists zz_worker_lists_saved on settings_pilot;
create trigger zz_worker_lists_saved after update on settings_pilot for each row execute function _worker_lists_saved();

-- ── 19. billing currency: ₪ $ € £ or any 3-letter code ────────────────────────
CREATE OR REPLACE FUNCTION public.manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare v_billing jsonb;
begin
  if not _manufacturer_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_price is null or p_price < 0 or p_price > 1000000 then
    return jsonb_build_object('ok', false, 'error', 'bad_price');
  end if;
  -- step 46: ₪ $ € £, or any 3-letter currency code (USD, CHF …) — not tied to the language
  p_currency := upper(trim(coalesce(p_currency, '')));
  if not (p_currency in ('₪','$','€','£') or p_currency ~ '^[A-Z]{3}$') then
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
end $_$;
revoke execute on function manufacturer_set_billing(text, boolean, numeric, text, text) from public;
grant execute on function manufacturer_set_billing(text, boolean, numeric, text, text) to anon, authenticated;

-- ── 22. the plant's resilience: standby server, UPS ─────────────────────────────
-- A plant server can run with a HOT STANDBY (a second server that receives every
-- change at once, Postgres streaming replication) behind one floating address,
-- and on a UPS. The tools in plant-server/ (outside the database) write what they
-- see into plant_state: standbyExpected, upsStatus / upsAt, lastFailoverAt — and
-- the server names itself with the setting gt.server_name ('A' / 'B').
--   plant_server_status(p_token) → {ok, server, role primary|standby, standbyExpected,
--        standbys:[{name, state, sync, lagSeconds}], syncMode, ups:{status, at}, lastFailoverAt}
--   system_health attention: standby_down, standby_lag, ups_on_battery, ups_low_battery;
--                 info: standby_async (the standby is down and the server works alone), failover_recent
create or replace function _gt_standbys() returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', application_name, 'state', state, 'sync', sync_state,
           'lagSeconds', round(coalesce(extract(epoch from replay_lag), 0)::numeric, 1))), '[]'::jsonb)
    into v from pg_stat_replication r
   where not exists (select 1 from pg_replication_slots s       -- a logical sender (Supabase Realtime, CDC) is not a standby
                      where s.active_pid = r.pid and s.slot_type = 'logical');
  return v;
exception when others then
  return '[]'::jsonb;                          -- no right to see the replication view (cloud test server)
end $$;
revoke execute on function _gt_standbys() from public, anon, authenticated;

create or replace function plant_server_status(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if coalesce(_session_role(p_token), '') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true,
    'server', nullif(current_setting('gt.server_name', true), ''),
    'role', case when pg_is_in_recovery() then 'standby' else 'primary' end,
    'standbyExpected', coalesce((select value from plant_state where key = 'standbyExpected'), '') = '1',
    'standbys', _gt_standbys(),
    'syncMode', current_setting('synchronous_standby_names', true),
    'ups', jsonb_build_object('status', (select value from plant_state where key = 'upsStatus'),
                              'at', (select value from plant_state where key = 'upsAt')),
    'lastFailoverAt', (select value from plant_state where key = 'lastFailoverAt'));
end $$;
revoke execute on function plant_server_status(text) from public;
grant execute on function plant_server_status(text) to anon, authenticated;
revoke execute on function _gt_standbys() from public, anon, authenticated;

-- ── system_health: processing boards waiting, rollover waiting, label mismatches ──
create or replace function system_health(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_role text := coalesce(_session_role(p_token), '');
  v_tm boolean; v_on_at timestamptz; v_devs jsonb; v_chain jsonb; v_sec jsonb;
  v_ver timestamptz; v_fail timestamptz; v_plant boolean; v_backup text; v_age numeric;
  v_attn text[] := '{}'; v_info text[] := '{}';
  v_offline int; v_failed int; v_revoked int; v_brakes int; v_locks int;
  v_boards int; v_oldest date; v_wait timestamptz; v_mismatch int; v_order int; v_leaders int;
  v_stb jsonb; v_ups text; v_ups_at timestamptz; v_fo timestamptz;
  v_night jsonb; v_night_at timestamptz;
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
  select count(distinct key) into v_brakes from (
    select key, at - lag(at, 9) over (partition by key order by at, id) as span
      from rate_events where kind = 'correction_rejected' and at > now() - interval '1 day') a
   where span <= interval '10 minutes';
  select count(distinct ip) into v_locks from (
    select ip, at - lag(at, 7) over (partition by ip order by at, id) as span
      from login_attempts where not ok and at > now() - interval '1 day') b
   where span <= interval '15 minutes';
  v_mismatch := (select count(*) from events_pilot where stage = 'security' and action = 'label_mismatch'
                                                     and created_at > now() - interval '1 day');
  v_order := (select count(*) from events_pilot where stage = 'security' and action in ('out_of_order', 'earlier_day_open')
                                                  and created_at > now() - interval '1 day');
  v_sec := jsonb_build_object(
    'revokedDeviceWrites24h', v_revoked,
    'failedLogins24h', v_failed,
    'rejectedCorrections24h', (select count(*) from rate_events where kind = 'correction_rejected' and at > now() - interval '1 day'),
    'rateLimited24h', v_brakes + v_locks,
    'labelMismatch24h', v_mismatch,
    'outOfOrder24h', v_order,
    'chainBroken', not coalesce((v_chain ->> 'ok')::boolean, false));

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
  select count(distinct board_id), min(slaughter_day) into v_boards, v_oldest from animals_carry;
  v_wait := _ts_or_null((select value from plant_state where key = 'rolloverWaitingSince'));

  if v_backup = 'unknown' then v_info := v_info || 'backup_unknown'::text;
  elsif v_backup <> 'ok' then v_attn := v_attn || 'backup_stale'::text; end if;
  if (v_sec ->> 'chainBroken')::boolean then v_attn := v_attn || 'chain_broken'::text; end if;
  if v_tm then v_attn := v_attn || 'test_mode_on'::text; end if;
  if v_offline > 0 then v_attn := v_attn || 'devices_offline'::text; end if;
  if v_failed >= 10 or v_locks > 0 then v_attn := v_attn || 'failed_logins'::text; end if;
  if v_revoked > 0 then v_attn := v_attn || 'revoked_device_writes'::text; end if;
  if v_mismatch > 0 then v_attn := v_attn || 'label_mismatch'::text; end if;
  if v_wait is not null then v_attn := v_attn || 'rollover_waiting'::text; end if;
  if v_boards > 0 then v_info := v_info || 'processing_days_open'::text; end if;
  v_leaders := (select count(*) from devices_pilot d where d.assigned_role = 'leader' and coalesce(d.device_status, 'active') <> 'retired'
                   and exists (select 1 from device_credentials c where c.device_id = d.id and not c.revoked));
  if v_leaders > 0 and not exists (select 1 from plant_state where key = 'leaderRecoveryHash') then
    v_attn := v_attn || 'leader_recovery_missing'::text;            -- without it a lost team-leader device needs the server
  end if;
  if exists (select 1 from plant_state where key = 'workerListsCheck') then v_info := v_info || 'worker_lists_check'::text; end if;
  -- §22 the plant's standby server and UPS (written by the plant-server tools)
  v_stb := _gt_standbys();
  if not pg_is_in_recovery() and coalesce((select value from plant_state where key = 'standbyExpected'), '') = '1' then
    if not exists (select 1 from jsonb_array_elements(v_stb) x where x ->> 'state' = 'streaming') then
      v_attn := v_attn || 'standby_down'::text;
      if coalesce(current_setting('synchronous_standby_names', true), '') = '' then v_info := v_info || 'standby_async'::text; end if;
    elsif exists (select 1 from jsonb_array_elements(v_stb) x where (x ->> 'lagSeconds')::numeric > 30) then
      v_attn := v_attn || 'standby_lag'::text;
    end if;
  end if;
  v_ups := (select value from plant_state where key = 'upsStatus');
  v_ups_at := _ts_or_null((select value from plant_state where key = 'upsAt'));
  if v_ups_at > now() - interval '1 day' then
    if v_ups = 'lowbattery' then v_attn := v_attn || 'ups_low_battery'::text;
    elsif v_ups = 'onbattery' then v_attn := v_attn || 'ups_on_battery'::text; end if;
  end if;
  v_fo := _ts_or_null((select value from plant_state where key = 'lastFailoverAt'));
  if v_fo > now() - interval '7 days' then v_info := v_info || 'failover_recent'::text; end if;
  -- v10.16: the nightly check (plant-server/nightly-check.sh, before work) — its problems, what it
  -- fixed by itself, and a warning when it did not run (on a plant server only)
  begin v_night := (select value from plant_state where key = 'nightlyCheck')::jsonb; exception when others then v_night := null; end;
  v_night_at := _ts_or_null(v_night ->> 'at');
  if v_night_at is not null and v_night_at > now() - interval '30 hours' then
    if jsonb_typeof(v_night -> 'problems') = 'array' and jsonb_array_length(v_night -> 'problems') > 0 then
      v_attn := v_attn || 'nightly_check_problems'::text;
    end if;
    if jsonb_typeof(v_night -> 'fixed') = 'array' and jsonb_array_length(v_night -> 'fixed') > 0 then
      v_info := v_info || 'nightly_check_fixed'::text;
    end if;
  elsif v_plant or v_night_at is not null then
    v_attn := v_attn || 'nightly_check_missing'::text;
  end if;

  return jsonb_build_object(
    'ok', true,
    'schemaStep', (select value from plant_state where key = 'schemaStep'),
    'serverTime', now(),
    'devices', v_devs || jsonb_build_object('leader', v_leaders),
    'server', jsonb_build_object('name', nullif(current_setting('gt.server_name', true), ''),
                                 'role', case when pg_is_in_recovery() then 'standby' else 'primary' end,
                                 'standbys', v_stb, 'ups', v_ups, 'lastFailoverAt', v_fo),
    'testMode', jsonb_build_object('on', v_tm, 'on_at', case when v_tm then v_on_at end,
                                   'expires_at', case when v_tm then v_on_at + _test_mode_max() end),
    'lastBackupVerifiedAt', v_ver,
    'lastBackupFailedAt', v_fail,
    'lastBackupFailReason', case when v_fail is not null then (select value from plant_state where key = 'lastBackupFailReason') end,
    'backup', jsonb_build_object('status', v_backup, 'ageHours', v_age),
    'eventChain', v_chain,
    'security', v_sec,
    'processing', jsonb_build_object('openBoards', v_boards, 'oldestDay', v_oldest,
                                     'rolloverWaitingSince', v_wait, 'unfinishedOnBoard', _board_unfinished()),
    'nightly', case when v_night is not null then jsonb_build_object('at', v_night -> 'at', 'ok', v_night -> 'ok',
                     'problems', v_night -> 'problems', 'fixed', v_night -> 'fixed', 'checks', v_night -> 'checks') end,
    'attention', to_jsonb(v_attn),
    'info', to_jsonb(v_info));
end $$;
revoke execute on function system_health(text) from public;
grant execute on function system_health(text) to anon, authenticated;

-- ── 20. one shared screen for the inner AND the outer check (screenConfig '1both') ──
-- The plant may choose one inspector screen for both checks. Only then the inner
-- tablet may also rule the outer check (and send to the rabbinate); every other
-- configuration keeps "each station its own stage". One screen = ONE worker list
-- ("inspectors" — kept under the inner screen's key): whoever is on it logs in on
-- the shared screen and is the name on both its inner and its outer rulings.
create or replace function _gt_one_inspection() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select settings ->> 'screenConfig' from settings_pilot where id = 1), '') = '1both';
$$;
revoke execute on function _gt_one_inspection() from public, anon, authenticated;

-- v10.16 (review A1): a screen whose workers log in with a code (loginModeByRole = code / both)
-- writes ONLY with a live worker session of that screen's own list (x-worker-token) — the device
-- key alone is not enough. Raises GTW01 'GT:WORKER_LOGIN_REQUIRED': nothing is changed, the tablet
-- keeps the change and asks for the login. A name-only screen has no secret to check (the name is
-- recorded). One shared inner + outer screen: its device is 'inner', so its one list is checked.
create or replace function _worker_gate(p_device_role text) returns void
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text := _worker_role_norm(p_device_role);
begin
  if v_role is null then return; end if;
  if coalesce((select settings from settings_pilot where id = 1) -> 'loginModeByRole' ->> v_role, 'none') not in ('code', 'both') then return; end if;
  if exists (select 1 from _current_worker() w where w.role = v_role) then return; end if;
  raise exception 'GT:WORKER_LOGIN_REQUIRED worker login required (%)', v_role using errcode = 'GTW01';
end $$;
revoke execute on function _worker_gate(text) from public, anon, authenticated;

-- a refused "log in first" answer is never kept as the command's answer: the same command,
-- sent again after the worker logs in, is carried out
create or replace function _cmd_put(p_cmd uuid, p_dev text, p_fn text, p_result jsonb) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_cmd is null or p_result is null then return; end if;
  if coalesce(p_result ->> 'error', '') in ('rate_limited', 'command_id_conflict', 'server_error', 'worker_login_required') then return; end if;
  delete from processed_commands where at < now() - interval '3 days';
  insert into processed_commands (command_id, device_id, fn, result) values (p_cmd, coalesce(p_dev, '?'), p_fn, p_result)
    on conflict (command_id) do nothing;
end $$;
revoke execute on function _cmd_put(uuid, text, text, jsonb) from public, anon, authenticated;

create or replace function _stage_allowed(p_stage text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text; v_ok boolean := false; v_dev text;
begin
  if _request_privileged() then return true; end if;
  v_role := _caller_device_role();
  if v_role is not null then
    perform _worker_gate(v_role);                    -- v10.16 (review A1): a code screen needs its worker's login
    v_ok := case p_stage
      when 'slaughter' then v_role in ('slaughter')
      when 'eso'       then v_role in ('esophagus','slaughter')
      when 'inner'     then v_role in ('inner')              -- step 46: inner tablet → inner only
      when 'outer'     then v_role in ('outer')              -- step 46: outer tablet → outer only
                             or (v_role = 'inner' and _gt_one_inspection())   -- one shared screen (the plant's choice)
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
              where d.id = v_dev and d.device_status = 'active'
                and (d.assigned_role = 'outer' or (d.assigned_role = 'inner' and _gt_one_inspection()))) then
    perform _worker_gate((select assigned_role from devices_pilot where id = v_dev));   -- v10.16 (A1)
    return true;
  end if;
  if _test_mode_on() and _request_has_manager() then return true; end if;
  if v_dev is null then perform _note_revoked_write(); else perform _note_revoked_write(v_dev); end if;
  return false;
end $$;

create or replace function _derive_actor(p_stage text, p_client text) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  w record; v_role text; v_mode text; v_def text; c text; s jsonb;
  defaults text[] := array['שוחט', 'בודק פנים', 'בודק חוץ', 'בודק', 'משגיח'];
begin
  if not _is_api_request() or _request_is_service_role() then return p_client; end if;   -- the server itself
  c := left(nullif(trim(regexp_replace(coalesce(p_client, ''), '\s*\(\?\)\s*$', '')), ''), 60);
  v_role := _stage_worker_role(p_stage);
  if v_role = 'outer' and _gt_one_inspection() then v_role := 'inner'; end if;   -- one shared screen: its one list
  v_def := case p_stage when 'slaughter' then 'שוחט' when 'inner' then 'בודק פנים' when 'inner_start' then 'בודק פנים'
                        when 'outer' then 'בודק חוץ' else 'משגיח' end;
  select settings into s from settings_pilot where id = 1;
  select * into w from _current_worker() limit 1;
  if w.name is not null and w.role = v_role and (c is null or c = w.name or c = any(defaults)) then
    return w.name;
  end if;
  v_mode := coalesce(s -> 'loginModeByRole' ->> v_role, 'none');
  if v_mode not in ('name', 'code', 'both') then
    return case when c = any(defaults) then c else v_def end;
  end if;
  if v_mode = 'name' and c is not null and exists (
       select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'users') = 'array' then s -> 'users' else '[]'::jsonb end) u
        where u ->> 'name' = c and _worker_role_norm(u ->> 'role') = v_role) then
    return c;
  end if;
  return coalesce(c, v_def) || ' (?)';
end $$;
revoke execute on function _derive_actor(text, text) from public, anon, authenticated;

create or replace function worker_login(p_role text, p_code text, p_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_role text := _worker_role_norm(p_role);
  v_dev text := _current_device_id();
  v_mgr boolean := _request_has_manager() and _test_mode_on();      -- a team leader acts as a station only in test mode
  v_mt text := _request_headers() ->> 'x-manager-token';
  d devices_pilot%rowtype;
  v_ip text := 'w:' || _request_ip();
  v_key2 text;
  v_fails int; v_all int; v_last timestamptz;
  s jsonb; u jsonb; v_h1 text; v_h2 text;
  v_tok text; v_exp timestamptz;
begin
  if v_role is null then return jsonb_build_object('ok', false, 'error', 'bad_role'); end if;
  if v_dev is null and not v_mgr then return jsonb_build_object('ok', false, 'error', 'device_not_paired'); end if;
  if v_dev is not null then
    select * into d from devices_pilot where id = v_dev;
    if d.id is null or d.assigned_role is null or coalesce(d.device_status, 'active') = 'retired' then
      return jsonb_build_object('ok', false, 'error', 'device_not_paired');
    end if;
    if not v_mgr and _worker_role_norm(d.assigned_role) is distinct from v_role then
      return jsonb_build_object('ok', false, 'error', 'wrong_station');
    end if;
  end if;
  v_key2 := 'wdev:' || coalesce(v_dev, 'mgr');

  delete from login_attempts where at < now() - interval '1 day';
  select count(*), max(at) into v_fails, v_last from login_attempts
   where ip in (v_ip, v_key2) and not ok and at > now() - interval '15 minutes';
  if v_fails >= 8 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited',
                              'retry_after', ceil(extract(epoch from (v_last + interval '15 minutes' - now()))));
  end if;
  select count(*) into v_all from login_attempts where not ok and at > now() - interval '15 minutes';
  if v_all >= 30 then perform pg_sleep(least(3.0, v_all / 30.0)); end if;

  select settings into s from settings_pilot where id = 1;
  if p_code is not null and trim(p_code) <> '' and jsonb_typeof(s -> 'users') = 'array' then
    v_h1 := _worker_code_hash(trim(p_code));
    v_h2 := case when coalesce(s ->> 'codeSalt', '') <> ''
                 then encode(digest('gt1:' || (s ->> 'codeSalt') || ':' || trim(p_code), 'sha256'), 'hex') end;
    select x into u from jsonb_array_elements(s -> 'users') x
     where jsonb_typeof(x) = 'object'
       and _worker_role_norm(x ->> 'role') = v_role
       and (p_name is null or x ->> 'name' = p_name)
       and coalesce(x ->> 'name', '') <> ''
       and (x ->> 'codeHash' = v_h1 or (v_h2 is not null and x ->> 'codeHash' = v_h2))   -- step 46: hashes only
     limit 1;
  end if;
  if u is null then
    insert into login_attempts (ip, ok) values (v_ip, false), (v_key2, false);
    perform pg_sleep(0.3);
    return jsonb_build_object('ok', false, 'error', 'code_invalid', 'attempts_left', greatest(0, 7 - v_fails));
  end if;
  delete from login_attempts where ip in (v_ip, v_key2);

  update worker_sessions set revoked = true, revoked_at = now()
   where not revoked and ((v_dev is not null and device_id = v_dev)
                          or (v_dev is null and mgr_session_hash = encode(digest(v_mt, 'sha256'), 'hex')));
  delete from worker_sessions where expires_at < now() - interval '2 days';
  v_tok := encode(gen_random_bytes(24), 'hex');
  insert into worker_sessions (token_hash, device_id, mgr_session_hash, test_mode, name, role)
  values (encode(digest(v_tok, 'sha256'), 'hex'), v_dev,
          case when v_dev is null then encode(digest(v_mt, 'sha256'), 'hex') end,
          v_mgr and (v_dev is null or _worker_role_norm(d.assigned_role) is distinct from v_role),
          left(u ->> 'name', 60), v_role)
  returning expires_at into v_exp;

  perform _security_event(null, 'worker_login', jsonb_build_object('role', v_role, 'testMode', v_dev is null or v_mgr),
                          left(u ->> 'name', 60), coalesce(v_dev, 'team-leader'));
  return jsonb_build_object('ok', true, 'token', v_tok, 'name', left(u ->> 'name', 60), 'role', v_role, 'expires_at', v_exp);
end $function$;
revoke execute on function worker_login(text, text, text) from public;
grant execute on function worker_login(text, text, text) to anon, authenticated;

-- ── 21. a lost / broken team-leader device: replaced by the team leader himself ──
-- No manufacturer and no SQL. When the plant is installed the team leader gets a
-- RECOVERY CODE (shown once, to print or keep). If the team-leader device is lost:
-- on any new device (not a station tablet) → "team-leader device lost?" → the
-- team-leader code + the recovery code. Every old team-leader device is then
-- disconnected (keys revoked, sessions ended), this device registers itself as the
-- team-leader device (as at installation), and the recovery code is used up — the
-- team leader makes a new one. Wrong codes are braked (5 per hour per address).
--   leader_recovery_code_new(p_token)  → {ok, code}          team leader only (shown once)
--   leader_recovery_status(p_token)    → {ok, exists, at}    team leader / owner
--   leader_device_replace(p_code, p_recovery) → the answer of manager_login (+ replaced)
create or replace function _leader_recovery_norm(p text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g'));
$$;
revoke execute on function _leader_recovery_norm(text) from public, anon, authenticated;

create or replace function leader_recovery_code_new(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; c text := ''; i int; b bytea := gen_random_bytes(12);
begin
  if coalesce(_session_role(p_token), '') <> 'manager' or not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  for i in 0 .. 11 loop
    c := c || substr(a, 1 + (get_byte(b, i) % length(a)), 1);
    if i in (3, 7) then c := c || '-'; end if;
  end loop;
  insert into plant_state (key, value) values ('leaderRecoveryHash', crypt(_leader_recovery_norm(c), gen_salt('bf')))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  insert into plant_state (key, value) values ('leaderRecoveryAt', now()::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  perform _security_event(null, 'leader_recovery_code_made', '{}'::jsonb, coalesce(_session_name(p_token), 'manager'), coalesce(_current_device_id(), 'team-leader'));
  return jsonb_build_object('ok', true, 'code', c);
end $$;
revoke execute on function leader_recovery_code_new(text) from public;
grant execute on function leader_recovery_code_new(text) to anon, authenticated;

create or replace function leader_recovery_status(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if coalesce(_session_role(p_token), '') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true,
    'exists', exists (select 1 from plant_state where key = 'leaderRecoveryHash'),
    'at', (select value from plant_state where key = 'leaderRecoveryAt'));
end $$;
revoke execute on function leader_recovery_status(text) from public;
grant execute on function leader_recovery_status(text) to anon, authenticated;

create or replace function leader_device_replace(p_code text, p_recovery text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_ip text := 'lrec:' || coalesce(_request_ip(), '?');
  v_fails int; v_last timestamptz; v_hash text; v_ok boolean; d record; n int := 0; v_dev text := _current_device_id();
  r jsonb;
begin
  -- v10.16 (review A2): one replacement at a time — a second request with the same codes waits
  -- here, then finds the recovery code already used up (no_recovery_code)
  perform pg_advisory_xact_lock(hashtext('glatttrack_leader_device_replace'));
  -- a station tablet serves only its station
  if v_dev is not null and exists (select 1 from devices_pilot where id = v_dev
       and assigned_role in ('slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps', 'display')) then
    return jsonb_build_object('ok', false, 'reason', 'station_device');
  end if;
  select count(*), max(at) into v_fails, v_last from login_attempts
   where ip = v_ip and not ok and at > now() - interval '1 hour';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'locked',
                              'retry_after', ceil(extract(epoch from (v_last + interval '1 hour' - now()))));
  end if;
  select value into v_hash from plant_state where key = 'leaderRecoveryHash';
  v_ok := v_hash is not null and _leader_recovery_norm(p_recovery) <> ''
          and crypt(_leader_recovery_norm(p_recovery), v_hash) = v_hash
          and exists (select 1 from plant_managers m where m.role = 'manager' and m.active
                         and m.code_hash = crypt(coalesce(p_code, ''), m.code_hash));
  if not v_ok then
    insert into login_attempts (ip, ok) values (v_ip, false);
    perform _security_event(null, 'leader_device_replace_refused', jsonb_build_object('ip', v_ip), 'anonymous', coalesce(v_dev, '-'));
    perform pg_sleep(0.3);
    return jsonb_build_object('ok', false, 'reason', case when v_hash is null then 'no_recovery_code' else 'code_invalid' end,
                              'attempts_left', greatest(0, 4 - v_fails));
  end if;
  delete from login_attempts where ip = v_ip;
  -- every old team-leader device is disconnected; the recovery code is used up
  perform set_config('gt.audit_actor', 'team leader (recovery code)', true);
  perform set_config('gt.audit_reason', 'team-leader device replaced with the recovery code', true);
  perform set_config('app.device_admin', 'on', true);
  for d in select id, assigned_role, assigned_index from devices_pilot where assigned_role = 'leader' loop
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now() where id = d.id;
    update device_credentials set revoked = true, revoked_at = coalesce(revoked_at, now()) where device_id = d.id and not revoked;
    delete from manager_sessions where device_id = d.id;
    perform _audit_device_event(d.id, 'UNASSIGNED', d.assigned_role, d.assigned_index, 'replaced with the recovery code', null, null, 'team leader');
    n := n + 1;
  end loop;
  perform set_config('app.device_admin', '', true);
  perform set_config('gt.audit_actor', '', true);
  perform set_config('gt.audit_reason', '', true);
  delete from plant_state where key in ('leaderDevicesRequired', 'leaderRecoveryHash', 'leaderRecoveryAt');
  perform _security_event(null, 'leader_device_replaced', jsonb_build_object('disconnected', n, 'ip', v_ip), 'team leader', coalesce(v_dev, '-'));
  -- as at installation: this login registers this device as the team-leader device
  r := manager_login(p_code);
  return coalesce(r, '{}'::jsonb) || jsonb_build_object('replaced', true, 'disconnected', n);
end $$;
revoke execute on function leader_device_replace(text, text) from public;
grant execute on function leader_device_replace(text, text) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '46')
  on conflict (key) do update
    set value = case when plant_state.value ~ '^\d+$' and plant_state.value::int > 46 then plant_state.value else '46' end,
        updated_at = now();

-- ── 23. review v10.15 → v10.16 ───────────────────────────────────────────────
-- (A1 worker login gate: _worker_gate in §20 · A2 recovery serialized: §21)
-- B2: the event log takes from a tablet only events of its own station
create or replace function event_append(p_event jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_id uuid; v_stage text; v_action text; v_payload jsonb; v_animal int; v_occ text; v_actor text;
  v_pos bigint; v_state text; v_msg text; v_err text; v_maker boolean;
begin
  if p_event is null or jsonb_typeof(p_event) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_event');
  end if;
  begin
    v_id := (p_event ->> 'event_id')::uuid;
  exception when others then v_id := null;
  end;
  v_stage := p_event ->> 'stage';
  v_action := p_event ->> 'action';
  v_payload := coalesce(case when jsonb_typeof(p_event -> 'payload') = 'object' then p_event -> 'payload' end, '{}'::jsonb);
  v_occ := coalesce(nullif(left(p_event ->> 'occurred_at', 64), ''), now()::text);
  v_actor := left(p_event ->> 'actor', 80);
  if v_id is null
     or v_stage is null or v_stage !~ '^[a-z_]{1,40}$'
     or v_action is null or v_action !~ '^[A-Za-z0-9_:.-]{1,80}$'
     or (p_event ? 'payload' and jsonb_typeof(p_event -> 'payload') not in ('object', 'null'))
     or length(v_payload::text) > 16384
     or (p_event ->> 'animal_no' is not null and (p_event ->> 'animal_no') !~ '^\d{1,4}$') then
    return jsonb_build_object('ok', false, 'error', 'bad_event');
  end if;
  v_animal := (p_event ->> 'animal_no')::int;
  if v_animal is not null and (v_animal < 1 or v_animal > 1000) then
    return jsonb_build_object('ok', false, 'error', 'bad_event');
  end if;
  v_maker := _request_has_manufacturer();
  if not _device_write_allowed() and not v_maker then
    return jsonb_build_object('ok', false, 'error', 'device_not_paired');
  end if;
  -- v10.16 (review B2): a tablet writes events only for its own work. The server's own logs
  -- ('security', 'admin' …) are written by the server alone; a station tablet only its station's
  -- stages (and 'correction'); the team leader's device 'settings'. Test mode keeps the old freedom.
  if _is_api_request() and not _request_is_service_role() then
    if v_stage in ('security', 'admin', 'audit', 'support', 'system', 'device', 'manufacturer', 'leader') then
      return jsonb_build_object('ok', false, 'error', 'reserved_stage');
    end if;
    if not (_test_mode_on() and _request_has_manager()) and not v_maker then
      declare v_role text := _caller_device_role();
      begin
        if v_role is not null and not (v_stage = 'correction' or case v_role
             when 'slaughter' then v_stage in ('slaughter')
             when 'esophagus' then v_stage in ('esophagus')
             when 'inner'     then v_stage in ('inner') or (v_stage = 'outer' and _gt_one_inspection())
             when 'outer'     then v_stage in ('outer')
             when 'legs'      then v_stage in ('legs')
             when 'parts'     then v_stage in ('parts')
             when 'stamps'    then v_stage in ('stamps', 'weight')
             when 'leader'    then v_stage in ('settings')
             else false end) then
          return jsonb_build_object('ok', false, 'error', 'wrong_station');
        end if;
      end;
    end if;
  end if;
  if exists (select 1 from events_pilot where event_id = v_id) then
    return jsonb_build_object('ok', true, 'duplicate', true, 'event_id', v_id);
  end if;
  begin
    insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
    values (v_id, v_animal, v_stage, v_action, v_payload, v_actor,
            case when not _is_api_request() then left(p_event ->> 'device_id', 80) end, v_occ)
    returning chain_pos into v_pos;
  exception
    when unique_violation then
      return jsonb_build_object('ok', true, 'duplicate', true, 'event_id', v_id);
    when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
      v_err := case when v_msg ~ 'GT:[A-Z_]+' then lower(substring(v_msg from 'GT:([A-Z_]+)'))
                    when v_state = '42501' then 'device_not_paired'
                    else 'server_error' end;
      return jsonb_build_object('ok', false, 'error', v_err);
  end;
  if v_maker then
    perform _admin_audit(_request_headers() ->> 'x-manager-token', 'event_append', v_stage || '/' || v_action,
                         jsonb_build_object('event_id', v_id));
  end if;
  return jsonb_build_object('ok', true, 'event_id', v_id, 'chain_pos', v_pos);
end $$;
revoke execute on function event_append(jsonb) from public;
grant execute on function event_append(jsonb) to anon, authenticated;

-- ── 24. animal card (v10.16): everything about one animal, for the team leader / owner ──
-- animal_card(p_token, p_date, p_n) — p_n = the board row id (number − 1); p_date null = today's
-- live board. The full row (every stage, device and time), its processing row while that day is
-- still in processing, the day's intake (farm / type) and the event log of that number during the
-- day. Read-only.
create or replace function animal_card(p_token text, p_date date, p_n integer) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_role text := coalesce(_session_role(p_token), '');
  d daily_board_archive%rowtype; v_row jsonb; v_carry jsonb; v_from timestamptz; v_to timestamptz; v_live boolean := p_date is null;
begin
  if v_role not in ('manager', 'owner') then return jsonb_build_object('ok', false, 'error', 'unauthorized'); end if;
  if p_n is null or p_n < 0 or p_n > 999 then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  if v_live then
    select to_jsonb(a) into v_row from animals_pilot a where a.id = p_n and a.slaughter is not null;
    v_from := coalesce(to_timestamp(_board_epoch() / 1000.0), now() - interval '1 day'); v_to := now();
  else
    select * into d from daily_board_archive x
     where coalesce(x.business_date, (x.archived_at at time zone 'UTC')::date) = p_date
       and exists (select 1 from jsonb_array_elements(x.board) y where (y ->> 'id')::int = p_n and y ->> 'slaughter' is not null)
     order by x.archived_at desc limit 1;
    if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    select y into v_row from jsonb_array_elements(d.board) y where (y ->> 'id')::int = p_n limit 1;
    select to_jsonb(c) into v_carry from animals_carry c where c.board_id = d.id and c.id = p_n;
    select coalesce(to_timestamp(min((y ->> 'slaughter_time')::bigint) / 1000.0) - interval '1 hour', d.archived_at - interval '1 day')
      into v_from from jsonb_array_elements(d.board) y where y ->> 'slaughter_time' ~ '^\d+$';
    v_to := d.archived_at + interval '1 minute';
  end if;
  if v_row is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'live', v_live, 'date', p_date, 'board', d.id, 'archivedAt', d.archived_at,
    'row', v_row, 'carry', v_carry,
    'intake', case when v_live then coalesce((select settings -> 'dailyIntake' from settings_pilot where id = 1), '[]'::jsonb) else coalesce(d.intake, '[]'::jsonb) end,
    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'stage', e.stage, 'action', e.action, 'actor', e.actor,
                                                            'device', e.device_id, 'reason', e.payload ->> 'reason') order by e.created_at)
                        from (select * from events_pilot e
                               where e.animal_no = p_n + 1
                                 and ((e.created_at between v_from and v_to)
                                      or (not v_live and e.payload ->> 'slaughterDay' = p_date::text))
                               order by e.created_at limit 300) e), '[]'::jsonb));
end $$;
revoke execute on function animal_card(text, date, integer) from public;
grant execute on function animal_card(text, date, integer) to anon, authenticated;

-- ── 25. the rabbinate screen (v10.17) ─────────────────────────────────────────
-- "Send to the rabbinate screen" (set_not_chalak_outer) is routing from the glatt outer screen to the
-- rabbinate outer screen, not a ruling. There the animal is ruled רבנות חלק, רבנות כשר or טרף.
-- An animal marked "לא חלק" by the shochet or at the maw check stays רבנות כשר or טרף only.
-- The same rule on every write path: claim_animal_stage (above) and any push / correction (this trigger).
create or replace function _animals_nc_outer_value() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  if new.outer_status is not null
     and (tg_op = 'INSERT' or new.outer_status is distinct from old.outer_status)
     and not _nc_outer_value_ok(new, new.outer_status) then
    raise exception 'GT:INVALID_VALUE a "not chalak" animal can only be ruled kosher or treif (nc_kosher_or_treif_only)'
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function _animals_nc_outer_value() from public, anon, authenticated;

-- ── 26. kashrut seals on the server (v10.22) ───────────────────────────────────
-- Every kosher sticker (parts, stamps) carries the plant's kashrut seal for its ruling. The team
-- leader uploads one picture per status; it is kept HERE so every printing tablet has it (before
-- v10.22 the picture stayed on the team leader's own device only).
create table if not exists kashrut_seals (
  key        text primary key,
  image      text not null,
  updated_at timestamptz not null default now(),
  updated_by text
);
alter table kashrut_seals enable row level security;
revoke all on kashrut_seals from public, anon, authenticated;

-- a status key a seal may belong to (the built-in rulings, רבנות כשר, or a plant's own status)
create or replace function _seal_key_ok(k text) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select k in ('glatt', 'beit', 'kosher', 'mk', 'rabChalak', 'kosherRab') or k ~ '^custom_[A-Za-z0-9_-]{1,40}$';
$$;
revoke execute on function _seal_key_ok(text) from public, anon, authenticated;

-- the team leader sets (or, with an empty picture, removes) the seal of one status
create or replace function seal_set(p_token text, p_key text, p_image text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_ver bigint;
begin
  if coalesce(_session_role(p_token), '') <> 'manager' or not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_key is null or not _seal_key_ok(p_key) then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  if coalesce(p_image, '') = '' then
    delete from kashrut_seals where key = p_key;
  else
    if length(p_image) > 400000 or p_image !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$' then
      return jsonb_build_object('ok', false, 'error', 'bad_picture');
    end if;
    insert into kashrut_seals (key, image, updated_at, updated_by) values (p_key, p_image, now(), _session_name(p_token))
      on conflict (key) do update set image = excluded.image, updated_at = now(), updated_by = excluded.updated_by;
  end if;
  v_ver := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  insert into plant_state (key, value) values ('sealsVersion', v_ver::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  perform _security_event(null, case when coalesce(p_image, '') = '' then 'kashrut_seal_removed' else 'kashrut_seal_set' end,
                          jsonb_build_object('status', p_key), coalesce(_session_name(p_token), 'manager'), coalesce(_current_device_id(), 'team-leader'));
  return jsonb_build_object('ok', true, 'version', v_ver);
end $$;
revoke execute on function seal_set(text, text, text) from public;
grant execute on function seal_set(text, text, text) to anon, authenticated;

-- the seals, for a paired tablet (it prints) or a team leader / owner; only when they changed
-- since p_version (then only {ok, version, same:true})
create or replace function seals_get(p_token text default null, p_version bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_ver bigint := coalesce((select value from plant_state where key = 'sealsVersion')::bigint, 0);
begin
  if _current_device_id() is null and coalesce(_session_role(p_token), '') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_version is not null and p_version = v_ver then
    return jsonb_build_object('ok', true, 'version', v_ver, 'same', true);
  end if;
  return jsonb_build_object('ok', true, 'version', v_ver,
    'seals', coalesce((select jsonb_object_agg(key, image) from kashrut_seals), '{}'::jsonb));
end $$;
revoke execute on function seals_get(text, bigint) from public;
grant execute on function seals_get(text, bigint) to anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- §27–§29 (v10.26): "?" question and USDA hold on every station; a ruling can
-- always be changed (after a warning in the app); changes made after the next
-- station already worked are recorded for the team leader ("⚠ השתנה").
-- ════════════════════════════════════════════════════════════════════════════
--   HOLDS (animal_holds), per slaughter-day board (board_epoch) and number:
--     kind 'question' — the station's own question ("?"): the station goes on to
--       the next number; the number waits for that station's ruling.
--         slaughter : the number has no slaughter ruling yet. The esophagus may
--                     still rule it, and legs / head stickers may be printed (the
--                     scanners show "?" until the ruling). Inner / outer wait.
--                     When the shochet rules it — or the esophagus rules it nevela —
--                     the question is closed ('ruled'). A later slaughter ruling of
--                     nevela / shot makes the animal nevela / shot, whatever the
--                     esophagus said.
--         esophagus / inner / outer : the number waits for that station's ruling;
--                     the ruling closes the question.
--         legs / parts / stamps : the number waits at that station until the
--                     station answers it ('answered').
--     kind 'usda' — a USDA hold; part: whole | right | left (half) | cheek1 |
--       cheek2 | tongue. A WHOLE-animal hold stops the animal at every station
--       (no ruling, no sticker, no stamp, no weight). A part / half hold stops
--       only that part: parts stickers of the other parts print; a held half is
--       not weighed. Only the station that put the hold releases it ('released':
--       back in line, first) or condemns it ('condemned': that meat does not go
--       on; the kashrut ruling does not change; reported apart from treif).
--     Who: a paired tablet of that station, for its own station only.
--     A held / condemned number does not hold a processing station on an older
--     day (it moves on); the day stays on the server until every hold on it is
--     closed. The daily rollover waits for an open slaughter question.
--   CHANGES: a ruling can be changed by any tablet of the same station, at any
--     time (no more "moved on" / "only the tablet that ruled" / "the next
--     station already started"). The braking of many changes stays. A change made
--     after a later station already worked (esophagus, lungs, outer, stickers,
--     stamps, weights) is written to animal_changes; every screen shows the number
--     with "⚠ השתנה" until the team leader marks it handled (change_ack).
--   RPCs: hold_set, hold_resolve, board_flags, change_ack.
-- ════════════════════════════════════════════════════════════════════════════

-- an event in the animals' chain (any stage)
create or replace function _gt_event(p_animal_no integer, p_stage text, p_action text, p_payload jsonb, p_actor text, p_device text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_prev text := coalesce(current_setting('app.device_admin', true), '');
begin
  perform set_config('app.device_admin', 'on', true);
  insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
  values (gen_random_uuid(), p_animal_no, p_stage, p_action, coalesce(p_payload, '{}'::jsonb), p_actor,
          coalesce(p_device, 'server'), now()::text);
  perform set_config('app.device_admin', v_prev, true);
end $$;
revoke execute on function _gt_event(integer, text, text, jsonb, text, text) from public, anon, authenticated;

-- ── §27 holds ───────────────────────────────────────────────────────────────
create table if not exists animal_holds (
  id                 bigserial primary key,
  board_epoch        bigint  not null,
  animal_id          integer not null check (animal_id between 0 and 999),
  station            text    not null check (station in ('slaughter', 'eso', 'inner', 'outer', 'legs', 'parts', 'stamps')),
  kind               text    not null check (kind in ('question', 'usda')),
  part               text    not null default 'whole' check (part in ('whole', 'right', 'left', 'cheek1', 'cheek2', 'tongue', 'rumen', 'maw', 'lung')),
  created_at         timestamptz not null default now(),
  created_by         text,
  created_by_device  text,
  resolved_at        timestamptz,
  resolution         text check (resolution in ('ruled', 'answered', 'released', 'condemned', 'cancelled', 'board_closed')),
  resolved_by        text,
  resolved_by_device text,
  note               text
);
-- v10.32: the window of an inner "?" (rumen / maw / lung) — for a server made before it
alter table animal_holds drop constraint if exists animal_holds_part_check;
alter table animal_holds add constraint animal_holds_part_check
  check (part in ('whole', 'right', 'left', 'cheek1', 'cheek2', 'tongue', 'rumen', 'maw', 'lung'));
create unique index if not exists animal_holds_open_uq on animal_holds (board_epoch, animal_id, station, kind, part) where resolved_at is null;
create index if not exists animal_holds_board_idx on animal_holds (board_epoch, animal_id);
alter table animal_holds enable row level security;
revoke all on animal_holds from public, anon, authenticated;
revoke all on sequence animal_holds_id_seq from public, anon, authenticated;   -- Supabase grants new sequences to the app roles

-- the station a paired tablet works at (null: none / team leader / display)
create or replace function _hold_station_of_role(p_role text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case p_role when 'slaughter' then 'slaughter' when 'esophagus' then 'eso' when 'inner' then 'inner'
                     when 'outer' then 'outer' when 'legs' then 'legs' when 'parts' then 'parts' when 'stamps' then 'stamps' end;
$$;
revoke execute on function _hold_station_of_role(text) from public, anon, authenticated;

-- v10.32 (review A1 + F1): may this caller put / close a hold of p_station?
--   * a paired tablet of that station — and, on a screen whose workers log in with a code
--     (loginModeByRole = code / both), only with a live worker session (same gate as a ruling)
--   * one shared inner + outer screen (the plant's choice): its inner tablet also holds for outer
--   * test mode: the team leader acts as every station
-- returns null (allowed) or the error code
create or replace function _hold_caller_error(p_station text) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text := _caller_device_role();
begin
  if v_role is not null and (_hold_station_of_role(v_role) = p_station
                             or (p_station = 'outer' and v_role = 'inner' and _gt_one_inspection())) then
    begin
      perform _worker_gate(v_role);
    exception when sqlstate 'GTW01' then
      return 'worker_login_required';
    end;
    return null;
  end if;
  if _test_mode_on() and _request_has_manager() then return null; end if;
  return 'wrong_station';
end $$;
revoke execute on function _hold_caller_error(text) from public, anon, authenticated;

-- v10.32 (review A2): which small part was really printed. tongue_sticker = the tongue sticker is
-- out; cheek_sticker = both cheek stickers are out; parts_print_count = how many stickers are out.
-- A part on USDA hold (open or condemned) is not printed: its flag may not turn on, and the count
-- may not reach the full set (3) while one is held.
create or replace function _parts_print_block(p_epoch bigint, p_id integer, o_tongue boolean, n_tongue boolean,
                                              o_cheek boolean, n_cheek boolean, o_count integer, n_count integer) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v text;
begin
  if not coalesce(o_tongue, false) and coalesce(n_tongue, false) then
    v := _hold_block(p_epoch, p_id, 'parts', 'tongue'); if v is not null then return v; end if;
  end if;
  if not coalesce(o_cheek, false) and coalesce(n_cheek, false) then
    v := coalesce(_hold_block(p_epoch, p_id, 'parts', 'cheek1'), _hold_block(p_epoch, p_id, 'parts', 'cheek2'));
    if v is not null then return v; end if;
  end if;
  if coalesce(n_count, 0) > coalesce(o_count, 0) and coalesce(n_count, 0) >= 3 then
    v := coalesce(_hold_block(p_epoch, p_id, 'parts', 'tongue'), _hold_block(p_epoch, p_id, 'parts', 'cheek1'),
                  _hold_block(p_epoch, p_id, 'parts', 'cheek2'));
    if v is not null then return v; end if;
  end if;
  return null;
end $$;
revoke execute on function _parts_print_block(bigint, integer, boolean, boolean, boolean, boolean, integer, integer) from public, anon, authenticated;

-- a USDA hold belongs to ONE station at a time — v10.34 (owner): the station the animal is at
-- on the line (see _usda_zone below)
create or replace function _gt_screen_used(p_screen text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when jsonb_typeof(_gt_settings() #> '{screensPlan,screens}') = 'array'
              then (_gt_settings() #> '{screensPlan,screens}') ? p_screen else true end;
$$;
revoke execute on function _gt_screen_used(text) from public, anon, authenticated;
create or replace function _usda_zone(a animals_pilot) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
-- v10.34 (owner): the USDA hold belongs to the station the animal is AT on the line:
--   slaughtered, esophagus not yet   → esophagus
--   checked at the esophagus         → legs
--   legs / head stickers printed     → inner (also while the inner check is open)
--   inner check done                 → outer (whole or halves)
--   outer ruling                     → stamps (whole or halves); without a stamps screen: outer
--   (the head: cheeks + tongue — the small-parts station, its own parts)
-- a screen the plant does not use is skipped
declare v_alive boolean := a.slaughter in ('slaughtered', 'notChalak');
        v_eso boolean := coalesce(a.eso_checked, false) or _eso_required(a.id);
        v_legs boolean := _gt_screen_used('legs');
begin
  if a.slaughter is null then return null; end if;
  if a.outer_status is not null then
    return case when _gt_screen_used('stamps') then 'stamps' else 'outer' end;
  end if;
  if a.inner_status in ('confirmed', 'treif') then return 'outer'; end if;
  if a.inner_status is not null or a.rumen is not null or a.maw is not null then return 'inner'; end if;
  if not v_alive then return null; end if;
  if v_legs and (coalesce(a.head_stickers, false) or coalesce(a.legs_stickers, false)) then return 'inner'; end if;
  if coalesce(a.eso_checked, false) then return case when v_legs then 'legs' else 'inner' end; end if;
  if v_eso then return 'eso'; end if;
  return case when v_legs then 'legs' else 'inner' end;
end $$;
revoke execute on function _usda_zone(animals_pilot) from public, anon, authenticated;

-- an open "?" of the shochet on this number (the esophagus and the legs stickers may go on)
create or replace function _slaughter_q_open(a animals_pilot) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select a.slaughter is null and exists (
    select 1 from animal_holds h
     where h.board_epoch = coalesce(a.board_epoch, _board_epoch()) and h.animal_id = a.id
       and h.station = 'slaughter' and h.kind = 'question' and h.resolved_at is null);
$$;
revoke execute on function _slaughter_q_open(animals_pilot) from public, anon, authenticated;

-- may this station work on this number (part)? null = yes; 'held' / 'condemned'
create or replace function _hold_block(p_epoch bigint, p_id integer, p_station text, p_part text default null) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case
    when exists (select 1 from animal_holds h where h.board_epoch = p_epoch and h.animal_id = p_id and h.kind = 'usda'
                    and h.part = 'whole' and h.resolved_at is null) then 'held'
    when exists (select 1 from animal_holds h where h.board_epoch = p_epoch and h.animal_id = p_id and h.kind = 'usda'
                    and h.part = 'whole' and h.resolution = 'condemned') then 'condemned'
    when p_station in ('legs', 'parts', 'stamps')
         and exists (select 1 from animal_holds h where h.board_epoch = p_epoch and h.animal_id = p_id and h.station = p_station
                        and h.kind = 'question' and h.resolved_at is null) then 'held'
    when p_part is not null and p_part <> 'whole'
         and exists (select 1 from animal_holds h where h.board_epoch = p_epoch and h.animal_id = p_id and h.kind = 'usda'
                        and h.part = p_part and h.resolved_at is null) then 'held'
    when p_part is not null and p_part <> 'whole'
         and exists (select 1 from animal_holds h where h.board_epoch = p_epoch and h.animal_id = p_id and h.kind = 'usda'
                        and h.part = p_part and h.resolution = 'condemned') then 'condemned'
  end;
$$;
revoke execute on function _hold_block(bigint, integer, text, text) from public, anon, authenticated;

-- open holds on a board (a board with one is not archived)
create or replace function _holds_open(p_epoch bigint) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists (select 1 from animal_holds where board_epoch = p_epoch and resolved_at is null);
$$;
revoke execute on function _holds_open(bigint) from public, anon, authenticated;

-- v10.34: the plant chose its screens and the legs screen is one of them (no choice yet → not required)
create or replace function _gt_legs_first() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_typeof(_gt_settings() #> '{screensPlan,screens}') = 'array'
         and (_gt_settings() #> '{screensPlan,screens}') ? 'legs';
$$;
revoke execute on function _gt_legs_first() from public, anon, authenticated;

-- stage order: a number with an open slaughter "?" may be checked at the esophagus and
-- get its legs / head stickers (inner and outer wait for the shochet)
create or replace function _stage_order_error(p_stage text, a animals_pilot, p_today boolean default true) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_alive boolean := coalesce(a.slaughter in ('slaughtered', 'notChalak'), false);
        v_q boolean := false;
        v_eso_ok boolean;
begin
  if p_stage in ('eso', 'legs_stickers') and a.slaughter is null then v_q := _slaughter_q_open(a); end if;
  v_eso_ok := not (v_alive or v_q)
              or (coalesce(a.eso_checked, false) and a.eso_result = 'ok')
              or (p_today and not _eso_required(a.id))
              or (not p_today and (coalesce(a.eso_checked, false) or a.inner_status is not null));
  case p_stage
    when 'eso' then
      if not (v_alive or v_q) then return 'not_slaughtered'; end if;
      if a.inner_status is not null or a.outer_status is not null then return 'later_stage_started'; end if;
    when 'inner' then
      if not v_alive then return 'not_slaughtered'; end if;
      if not v_eso_ok then return 'eso_not_passed'; end if;
      if a.outer_status is not null then return 'later_stage_started'; end if;
      -- v10.34 (owner): the inner inspector works AFTER legs / head — on a plant whose screen choice
      -- has the legs screen, the stickers come first (today's board; an earlier day is not held back)
      if p_today and _gt_legs_first()
         and not (coalesce(a.legs_stickers, false) or coalesce(a.head_stickers, false)) then
        return 'legs_not_done';
      end if;
    when 'outer' then
      if a.inner_status is distinct from 'confirmed' then return 'inner_not_confirmed'; end if;
    when 'legs_stickers' then
      if a.slaughter is null and not v_q then return 'not_slaughtered'; end if;
      if not v_eso_ok then return 'eso_not_passed'; end if;
    when 'legs', 'parts', 'stamped' then
      if a.outer_status is null then return 'outer_not_ruled'; end if;
    when 'weights' then
      if a.outer_status is null and a.inner_status is distinct from 'treif' then return 'outer_not_ruled'; end if;
    else
      return null;
  end case;
  return null;
end $$;
revoke execute on function _stage_order_error(text, animals_pilot, boolean) from public, anon, authenticated;

-- processing work left: a held / condemned number does not hold the station
create or replace function _proc_pending(p_station text, a animals_pilot, p_today boolean default false) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v boolean;
begin
  if a.slaughter is null then return false; end if;
  case p_station
    when 'legs' then
      v := (not coalesce(a.head_stickers, false) and _stage_order_error('legs_stickers', a, p_today) is null)
          or (_gt_flag(_gt_settings(), 'legsSortEnabled', false) and _kosher_ready(a) and not coalesce(a.legs_sorted, false));
    when 'parts' then
      v := _kosher_ready(a)
         and ((not coalesce(a.parts_scanned, false) and coalesce(a.parts_print_count, 0) < 3)
              or (a.parts_printed_as is not null and a.parts_printed_as is distinct from _printed_as_key(a)));
    when 'stamps' then
      v := _kosher_ready(a)
         and (not coalesce(a.stamped, false)
              or (a.stamped_as is not null and a.stamped_as is distinct from _printed_as_key(a)));
    else
      return false;
  end case;
  if v and _hold_block(coalesce(a.board_epoch, _board_epoch()), a.id, p_station) is not null then return false; end if;
  return v;
end $$;
revoke execute on function _proc_pending(text, animals_pilot, boolean) from public, anon, authenticated;

-- a kept board leaves animals_carry only when no station needs it AND no hold on it is open
create or replace function _proc_finalize(p_board bigint default null) returns integer
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare b record; n int := 0; v_open boolean; st text;
begin
  for b in select distinct board_id from animals_carry where p_board is null or board_id = p_board order by board_id loop
    perform _proc_board_lock(b.board_id);
    continue when not exists (select 1 from animals_carry where board_id = b.board_id);   -- archived meanwhile
    v_open := false;
    foreach st in array _proc_stations() loop
      if _proc_board_pending(st, b.board_id) > 0 then v_open := true; exit; end if;
    end loop;
    continue when v_open;
    continue when exists (select 1 from animals_carry c join animal_holds h
                            on h.board_epoch = c.board_epoch and h.animal_id = c.id and h.resolved_at is null
                           where c.board_id = b.board_id);
    update daily_board_archive d
       set board = coalesce((select jsonb_agg(to_jsonb(c) - 'board_id' - 'slaughter_day' order by c.id)
                               from animals_carry c where c.board_id = b.board_id), d.board)
     where d.id = b.board_id;
    delete from animals_carry where board_id = b.board_id;
    delete from processing_day_closed where board_id = b.board_id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function _proc_finalize(bigint) from public, anon, authenticated;

-- the daily rollover also waits for an open slaughter "?"
create or replace function _board_unfinished() returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select (select count(*)::int from animals_pilot
           where slaughter in ('slaughtered', 'notChalak')
             and inner_status is distinct from 'treif' and outer_status is null)
       + (select count(*)::int from animals_pilot a where a.slaughter is null and _slaughter_q_open(a));
$$;
revoke execute on function _board_unfinished() from public, anon, authenticated;

-- a question is closed by the station's own ruling (the slaughter one also by an esophagus nevela)
create or replace function _animals_close_questions() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_ep bigint := coalesce(new.board_epoch, _board_epoch()); v_dev text := coalesce(new.device_id, 'server');
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if new.slaughter is not null and (tg_op = 'INSERT' or old.slaughter is null) then
    update animal_holds set resolved_at = now(), resolution = 'ruled', resolved_by_device = v_dev,
           note = case when new.eso_result = 'nevela' then 'eso_nevela' else new.slaughter end
     where board_epoch = v_ep and animal_id = new.id and station = 'slaughter' and kind = 'question' and resolved_at is null;
  end if;
  if coalesce(new.eso_checked, false) and (tg_op = 'INSERT' or not coalesce(old.eso_checked, false)) then
    update animal_holds set resolved_at = now(), resolution = 'ruled', resolved_by_device = v_dev, note = new.eso_result
     where board_epoch = v_ep and animal_id = new.id and station = 'eso' and kind = 'question' and resolved_at is null;
  end if;
  if new.inner_status in ('confirmed', 'treif') and (tg_op = 'INSERT' or old.inner_status is distinct from new.inner_status) then
    update animal_holds set resolved_at = now(), resolution = 'ruled', resolved_by_device = v_dev, note = new.inner_status
     where board_epoch = v_ep and animal_id = new.id and station = 'inner' and kind = 'question' and resolved_at is null;
  end if;
  if new.outer_status is not null and (tg_op = 'INSERT' or old.outer_status is null) then
    update animal_holds set resolved_at = now(), resolution = 'ruled', resolved_by_device = v_dev, note = new.outer_status
     where board_epoch = v_ep and animal_id = new.id and station = 'outer' and kind = 'question' and resolved_at is null;
  end if;
  return new;
end $$;
revoke execute on function _animals_close_questions() from public, anon, authenticated;
drop trigger if exists zzzzz_close_questions on animals_pilot;
create trigger zzzzz_close_questions after insert or update on animals_pilot
  for each row execute function _animals_close_questions();

-- a hold stops the station's writes on today's board (checked with the order rules)
create or replace function _animals_hold_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_ep bigint := coalesce(old.board_epoch, _board_epoch()); v_b text; v_st text;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then return new; end if;
  -- first rulings (a change of a ruling is not stopped: it does not touch the meat)
  if old.slaughter is null and new.slaughter is not null and new.eso_result is distinct from 'nevela' then
    v_st := 'slaughter'; v_b := _hold_block(v_ep, old.id, 'slaughter');
  end if;
  if v_b is null and not coalesce(old.eso_checked, false) and coalesce(new.eso_checked, false) then
    v_st := 'eso'; v_b := _hold_block(v_ep, old.id, 'eso');
  end if;
  if v_b is null and old.inner_status is null and new.inner_status is not null then
    v_st := 'inner'; v_b := _hold_block(v_ep, old.id, 'inner');
  end if;
  if v_b is null and old.outer_status is null and new.outer_status is not null then
    v_st := 'outer'; v_b := _hold_block(v_ep, old.id, 'outer');
  end if;
  if v_b is null and ((not coalesce(old.head_stickers, false) and coalesce(new.head_stickers, false))
                      or (not coalesce(old.legs_stickers, false) and coalesce(new.legs_stickers, false))
                      or (not coalesce(old.legs_sorted, false) and coalesce(new.legs_sorted, false))) then
    v_st := 'legs'; v_b := _hold_block(v_ep, old.id, 'legs');
  end if;
  if v_b is null and (coalesce(new.parts_print_count, 0) > coalesce(old.parts_print_count, 0)
                      or (not coalesce(old.parts_scanned, false) and coalesce(new.parts_scanned, false))) then
    v_st := 'parts'; v_b := _hold_block(v_ep, old.id, 'parts');
  end if;
  if v_b is null then                                                  -- v10.32: a held part is not printed
    v_st := 'parts'; v_b := _parts_print_block(v_ep, old.id, old.tongue_sticker, new.tongue_sticker, old.cheek_sticker,
                                               new.cheek_sticker, old.parts_print_count, new.parts_print_count);
  end if;
  if v_b is null and not coalesce(old.stamped, false) and coalesce(new.stamped, false) then
    v_st := 'stamps'; v_b := _hold_block(v_ep, old.id, 'stamps');
  end if;
  if v_b is null and (new.weight_right is distinct from old.weight_right and new.weight_right is not null) then
    v_st := 'stamps'; v_b := coalesce(_hold_block(v_ep, old.id, 'stamps'), _hold_block(v_ep, old.id, 'stamps', 'right'));
  end if;
  if v_b is null and (new.weight_left is distinct from old.weight_left and new.weight_left is not null) then
    v_st := 'stamps'; v_b := coalesce(_hold_block(v_ep, old.id, 'stamps'), _hold_block(v_ep, old.id, 'stamps', 'left'));
  end if;
  if v_b is not null then
    raise exception 'GT:HELD held: station=% hold=%', v_st, v_b using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function _animals_hold_guard() from public, anon, authenticated;
drop trigger if exists b_animals_hold_guard on animals_pilot;
create trigger b_animals_hold_guard before update on animals_pilot
  for each row execute function _animals_hold_guard();

-- put a hold. p_board: a kept (older) board; null = today's board.
create or replace function hold_set(p_id integer, p_station text, p_kind text, p_part text default 'whole',
                                    p_board bigint default null, p_command_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_role text; v_ep bigint; v_res jsonb; a animals_pilot; v_id bigint; v_part text := coalesce(nullif(p_part, ''), 'whole');
        v_actor text; v_order text;
begin
  if p_id is null or p_id < 0 or p_id > 999 then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  if p_kind is null or p_kind not in ('question', 'usda') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if p_station is null or p_station not in ('slaughter', 'eso', 'inner', 'outer', 'legs', 'parts', 'stamps') then
    return jsonb_build_object('ok', false, 'error', 'bad_station');
  end if;
  if (p_kind = 'question' and not (v_part = 'whole'
                                   or (p_station = 'inner' and v_part in ('rumen', 'maw', 'lung'))))   -- v10.32: the window of an inner "?"
     or (p_kind = 'usda' and not (v_part = 'whole'
                                  or (p_station = 'parts' and v_part in ('cheek1', 'cheek2', 'tongue'))
                                  or (p_station in ('outer', 'stamps') and v_part in ('right', 'left')))) then   -- v10.32: halves only after the inner check
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  v_dev := _call_device(null);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  v_role := _hold_caller_error(p_station);                          -- v10.32: worker login + shared screen
  if v_role is not null then return jsonb_build_object('ok', false, 'error', v_role); end if;
  v_res := _cmd_get(p_command_id, v_dev, 'hold_set');
  if v_res is not null then return v_res; end if;
  if p_board is null then
    perform _board_write_lock();
    v_ep := _board_epoch();
    insert into animals_pilot (id, board_epoch) values (p_id, v_ep) on conflict (id) do nothing;
    select * into a from animals_pilot where id = p_id;
  else
    perform _proc_board_lock(p_board);
    if p_station not in ('legs', 'parts', 'stamps') then return jsonb_build_object('ok', false, 'error', 'bad_station'); end if;
    select _carry_row(c) into a from animals_carry c where c.board_id = p_board and c.id = p_id;
    if a.id is null then return jsonb_build_object('ok', false, 'error', 'board_closed'); end if;
    v_ep := a.board_epoch;
  end if;
  if v_ep is null then return jsonb_build_object('ok', false, 'error', 'stale_board'); end if;
  -- v10.34 (owner): every station (not slaughter) may put a USDA hold on any number; the hold shows the
  -- station that put it, and only that station releases or condemns it. One open whole-animal USDA hold
  -- per number: another station is told where it is held.
  if p_kind = 'usda' and p_station = 'slaughter' then
    return jsonb_build_object('ok', false, 'error', 'bad_station');
  end if;
  if p_kind = 'usda' and v_part = 'whole' then
    select station into v_order from animal_holds
     where board_epoch = v_ep and animal_id = p_id and kind = 'usda' and part = 'whole' and resolved_at is null
       and station <> p_station limit 1;
    if v_order is not null then
      return jsonb_build_object('ok', false, 'error', 'usda_held_elsewhere', 'station', v_order);
    end if;
  end if;
  -- v10.34 (owner): the esophagus may turn its own "ok" into a "?" while the number has not reached the
  -- next station (no legs / head stickers, no inner / outer ruling): the check is opened again and the
  -- number waits for the "?" like any other (nevela: change it to ok first)
  if p_kind = 'question' and p_station = 'eso' and p_board is null and coalesce(a.eso_checked, false)
     and a.eso_result = 'ok' and _cmd_get(p_command_id, v_dev, 'hold_set') is null
     and not (coalesce(a.legs_stickers, false) or coalesce(a.head_stickers, false)
              or a.inner_status is not null or a.outer_status is not null) then
    perform set_config('gt.reset_in_progress', 'true', true);
    update animals_pilot set eso_checked = false, eso_result = null, eso_by_device = null, updated_at = now() where id = p_id;
    perform set_config('gt.reset_in_progress', 'false', true);
    perform _gt_event(p_id + 1, 'eso', 'reopened_question', jsonb_build_object('was', 'ok'), null, v_dev);
    select * into a from animals_pilot where id = p_id;
  end if;
  -- a question only while the station has not ruled the number
  if p_kind = 'question' and ((p_station = 'slaughter' and a.slaughter is not null)
                              or (p_station = 'eso' and coalesce(a.eso_checked, false))
                              or (p_station = 'inner' and a.inner_status in ('confirmed', 'treif'))
                              or (p_station = 'outer' and a.outer_status is not null)) then
    v_res := jsonb_build_object('ok', false, 'error', 'already_ruled', 'row', to_jsonb(a));
    perform _cmd_put(p_command_id, v_dev, 'hold_set', v_res);
    return v_res;
  end if;
  v_actor := _derive_actor(case p_station when 'eso' then 'eso' when 'stamps' then 'stamped' else p_station end, null);
  -- v10.32: an inner "?" is kept with the window it was asked in (rumen / maw / lung), so every inner
  -- tablet shows it and opens that window. One open inner "?" per number: asked again in another
  -- window, the open one moves to that window.
  if p_kind = 'question' and p_station = 'inner' then
    update animal_holds set part = v_part
     where board_epoch = v_ep and animal_id = p_id and station = 'inner' and kind = 'question' and resolved_at is null
       and part <> v_part
    returning id into v_id;
    if v_id is not null then
      perform _gt_event(p_id + 1, p_station, 'hold_moved', jsonb_build_object('kind', p_kind, 'part', v_part, 'hold', v_id), v_actor, v_dev);
      v_res := jsonb_build_object('ok', true, 'hold', (select to_jsonb(h) from animal_holds h where h.id = v_id));
      perform _cmd_put(p_command_id, v_dev, 'hold_set', v_res);
      return v_res;
    end if;
  end if;
  insert into animal_holds (board_epoch, animal_id, station, kind, part, created_by, created_by_device)
  values (v_ep, p_id, p_station, p_kind, v_part, v_actor, v_dev)
  on conflict (board_epoch, animal_id, station, kind, part) where resolved_at is null do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from animal_holds where board_epoch = v_ep and animal_id = p_id and station = p_station
       and kind = p_kind and part = v_part and resolved_at is null;
  else
    perform _gt_event(p_id + 1, p_station, 'hold_set', jsonb_build_object('kind', p_kind, 'part', v_part, 'hold', v_id, 'board', p_board), v_actor, v_dev);
  end if;
  v_res := jsonb_build_object('ok', true, 'hold', (select to_jsonb(h) from animal_holds h where h.id = v_id));
  perform _cmd_put(p_command_id, v_dev, 'hold_set', v_res);
  return v_res;
end $$;
revoke execute on function hold_set(integer, text, text, text, bigint, uuid) from public;
grant execute on function hold_set(integer, text, text, text, bigint, uuid) to anon, authenticated;

-- close a hold, by a tablet of the station that put it:
--   usda     → 'released' (back in line) or 'condemned'
--   question → 'answered' (legs / parts / stamps; inner — the window of its "?" was decided, the lungs
--               are still to come) or 'cancelled' (a "?" put by mistake)
create or replace function hold_resolve(p_hold bigint, p_resolution text, p_command_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_res jsonb; h animal_holds%rowtype; v_actor text;
begin
  v_dev := _call_device(null);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  v_res := _cmd_get(p_command_id, v_dev, 'hold_resolve');
  if v_res is not null then return v_res; end if;
  select * into h from animal_holds where id = p_hold for update;
  if h.id is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  v_actor := _hold_caller_error(h.station);                         -- v10.32: worker login + shared screen
  if v_actor is not null then return jsonb_build_object('ok', false, 'error', v_actor); end if;
  if h.resolved_at is not null then
    return jsonb_build_object('ok', true, 'hold', to_jsonb(h), 'already', true);
  end if;
  if not ((h.kind = 'usda' and p_resolution in ('released', 'condemned'))
          or (h.kind = 'question' and (p_resolution = 'cancelled'
                                       or (p_resolution = 'answered' and h.station in ('legs', 'parts', 'stamps', 'inner'))))) then   -- v10.32: inner — the window of the "?" was decided
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  v_actor := _derive_actor(case h.station when 'eso' then 'eso' when 'stamps' then 'stamped' else h.station end, null);
  update animal_holds set resolved_at = now(), resolution = p_resolution, resolved_by = v_actor, resolved_by_device = v_dev
   where id = h.id returning * into h;
  perform _gt_event(h.animal_id + 1, h.station, 'hold_' || p_resolution,
                    jsonb_build_object('kind', h.kind, 'part', h.part, 'hold', h.id), v_actor, v_dev);
  -- a board kept only for this hold may now be archived
  perform _proc_finalize(c.board_id) from (select distinct board_id from animals_carry where board_epoch = h.board_epoch) c;
  v_res := jsonb_build_object('ok', true, 'hold', to_jsonb(h));
  perform _cmd_put(p_command_id, v_dev, 'hold_resolve', v_res);
  return v_res;
end $$;
revoke execute on function hold_resolve(bigint, text, uuid) from public;
grant execute on function hold_resolve(bigint, text, uuid) to anon, authenticated;

-- ── §28 a change after the next station worked ──────────────────────────────
create table if not exists animal_changes (
  id          bigserial primary key,
  board_epoch bigint  not null,
  animal_id   integer not null,
  stage       text    not null,
  old_value   text,
  new_value   text,
  done        jsonb   not null default '{}'::jsonb,   -- what the later stations had already done
  by_device   text,
  at          timestamptz not null default now(),
  ack_at      timestamptz,
  ack_by      text
);
create index if not exists animal_changes_board_idx on animal_changes (board_epoch, animal_id);
alter table animal_changes enable row level security;
revoke all on animal_changes from public, anon, authenticated;
revoke all on sequence animal_changes_id_seq from public, anon, authenticated;

-- what the stations after p_stage already did on this animal (empty = nothing)
create or replace function _gt_done_after(p_stage text, a animals_pilot) returns jsonb
language sql immutable set search_path = public, extensions, pg_temp as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'eso',     case when p_stage = 'slaughter' and coalesce(a.eso_checked, false) then a.eso_result end,
    'inner',   case when p_stage in ('slaughter', 'eso') and a.inner_status in ('confirmed', 'treif') then a.inner_status end,
    'outer',   case when p_stage in ('slaughter', 'eso', 'inner') then a.outer_status end,
    'legsStickers', case when p_stage in ('slaughter', 'eso') and (coalesce(a.legs_stickers, false) or coalesce(a.head_stickers, false)) then true end,
    'legsSorted', case when coalesce(a.legs_sorted, false) then true end,
    'partsPrinted', case when coalesce(a.parts_print_count, 0) > 0 then a.parts_print_count end,
    'partsAs', a.parts_printed_as,
    'stamped', case when coalesce(a.stamped, false) then true end,
    'stampedAs', a.stamped_as,
    'weighed', case when a.weight_right is not null or a.weight_left is not null then true end));
$$;
revoke execute on function _gt_done_after(text, animals_pilot) from public, anon, authenticated;

create or replace function _gt_note_change(p_stage text, o animals_pilot, p_old text, p_new text, p_dev text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_done jsonb := _gt_done_after(p_stage, o);
begin
  if p_old is not distinct from p_new or v_done = '{}'::jsonb then return; end if;
  insert into animal_changes (board_epoch, animal_id, stage, old_value, new_value, done, by_device)
  values (coalesce(o.board_epoch, _board_epoch()), o.id, p_stage, p_old, p_new, v_done, p_dev);
  perform _gt_event(o.id + 1, p_stage, 'changed_after_next',
                    jsonb_build_object('from', p_old, 'to', p_new, 'done', v_done), null, p_dev);
end $$;
revoke execute on function _gt_note_change(text, animals_pilot, text, text, text) from public, anon, authenticated;

-- a change: any tablet of the station, at any time (the app warns first)
create or replace function _correction_check(p_stage text, a animals_pilot, p_dev text) returns text
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_by text; v_role text;
begin
  -- v10.32 (owner): a station changes its ruling only until the number reached the next station —
  -- then it belongs to that station's department:
  --   slaughter: until the esophagus checked it (or legs / inner / outer acted on it)
  --   esophagus: until the legs / head stickers were printed (or inner / outer acted on it)
  --   inner    : until the outer inspector ruled
  if p_stage = 'slaughter' and (coalesce(a.eso_checked, false) or coalesce(a.legs_stickers, false) or coalesce(a.head_stickers, false)
                                or a.inner_status is not null or a.outer_status is not null) then return 'next_station_done'; end if;
  if p_stage = 'eso' and (coalesce(a.legs_stickers, false) or coalesce(a.head_stickers, false)
                          or a.inner_status is not null or a.outer_status is not null) then return 'next_station_done'; end if;
  if p_stage = 'inner' and a.outer_status is not null then return 'outer_ruled'; end if;
  if p_dev is null then return 'correction_not_allowed'; end if;
  v_by := case p_stage when 'slaughter' then a.slaughter_by_device when 'eso' then a.eso_by_device
                       when 'inner' then a.inner_by_device when 'outer' then a.outer_by_device end;
  if v_by is not distinct from p_dev then return null; end if;
  select assigned_role into v_role from devices_pilot where id = p_dev and coalesce(device_status, 'active') <> 'retired';
  if coalesce((case p_stage
       when 'slaughter' then v_role = 'slaughter'
       when 'eso'       then v_role in ('esophagus', 'slaughter')
       when 'inner'     then v_role = 'inner' or (v_role = 'outer' and _gt_one_inspection())
       when 'outer'     then v_role = 'outer' or (v_role = 'inner' and _gt_one_inspection())
       else false end), false) then
    return null;
  end if;
  return 'correction_not_allowed';
end $$;
revoke execute on function _correction_check(text, animals_pilot, text) from public, anon, authenticated;

create or replace function _raise_correction(p_err text, p_stage text) returns void
language plpgsql set search_path = public, extensions, pg_temp as $$
begin
  if p_err is null then return; end if;
  if p_err = 'moved_on' then
    raise exception 'GT:MOVED_ON correction-blocked: already moved on — % status is locked', p_stage using errcode = 'P0001';
  end if;
  if p_err = 'next_station_done' then  -- v10.32
    raise exception 'GT:NEXT_STATION_DONE next_station_done: the number already reached the next station — the % ruling can no longer be changed', p_stage
      using errcode = 'P0001';
  end if;
  if p_err = 'outer_ruled' then        -- v10.32
    raise exception 'GT:OUTER_RULED outer_ruled: the outer inspector already ruled — the % ruling can no longer be changed', p_stage
      using errcode = 'P0001';
  end if;
  raise exception 'GT:CORRECTION_NOT_ALLOWED correction-blocked: only the station that made this % ruling can change it, right away, before the next stage', p_stage
    using errcode = 'P0001';
end $$;
revoke execute on function _raise_correction(text, text) from public, anon, authenticated;

-- the correction trigger: the station rule above; a change after a later station worked is recorded
create or replace function animals_pilot_guard_corrections() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_eso boolean; v_inner_final boolean;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;
  v_eso := coalesce(current_setting('gt.eso_ruling', true), '') = 'true'
           or coalesce(current_setting('gt.eso_upsert_row', true), '') = new.id::text;
  if coalesce(current_setting('gt.eso_upsert_row', true), '') <> '' then
    perform set_config('gt.eso_upsert_row', '', true);
  end if;
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  v_dev := _acting_device();

  -- a ruling's time changes only with the ruling itself (step 46)
  if not v_eso and old.slaughter is not null and new.slaughter_time is distinct from old.slaughter_time
     and (new.slaughter, new.slaughtered_by, new.slaughter_by_device)
         is not distinct from (old.slaughter, old.slaughtered_by, old.slaughter_by_device) then
    new.slaughter_time := old.slaughter_time;
  end if;
  if old.inner_status in ('confirmed', 'treif') and new.inner_time is distinct from old.inner_time
     and (new.inner_status, new.inner_by, new.inner_by_device, coalesce(new.not_chalak_inner, false))
         is not distinct from (old.inner_status, old.inner_by, old.inner_by_device, coalesce(old.not_chalak_inner, false)) then
    new.inner_time := old.inner_time;
  end if;
  if old.outer_status is not null and new.outer_time is distinct from old.outer_time
     and (new.outer_status, new.outer_by, new.outer_by_device, coalesce(new.nc_plain, false))
         is not distinct from (old.outer_status, old.outer_by, old.outer_by_device, coalesce(old.nc_plain, false)) then
    new.outer_time := old.outer_time;
  end if;

  if old.eso_result = 'nevela' and new.slaughter is distinct from old.slaughter and not v_eso then
    raise exception 'GT:ESO_LOCKED correction-blocked: failed the esophagus check — only the esophagus screen can change it'
      using errcode = 'P0001';
  end if;
  if not v_eso and old.slaughter is not null
     and (new.slaughter, new.slaughtered_by, new.slaughter_by_device)
         is distinct from (old.slaughter, old.slaughtered_by, old.slaughter_by_device) then
    perform _raise_correction(_correction_check('slaughter', old, v_dev), 'slaughter');
    perform _gt_note_change('slaughter', old, old.slaughter, new.slaughter, v_dev);
  end if;
  if coalesce(old.eso_checked, false)
     and (new.eso_result is distinct from old.eso_result or new.eso_by_device is distinct from old.eso_by_device) then
    perform _raise_correction(_correction_check('eso', old, v_dev), 'esophagus');
    perform _gt_note_change('eso', old, old.eso_result, new.eso_result, v_dev);
  end if;
  v_inner_final := old.inner_status in ('confirmed', 'treif');
  if v_inner_final
     and ((new.inner_status, new.inner_by, new.inner_by_device) is distinct from (old.inner_status, old.inner_by, old.inner_by_device)
          or coalesce(new.not_chalak_inner, false) is distinct from coalesce(old.not_chalak_inner, false)
          or (old.maw is not null and new.maw is distinct from old.maw)
          or (old.rumen is not null and new.rumen is distinct from old.rumen)) then
    perform _raise_correction(_correction_check('inner', old, v_dev), 'inner');
    perform _gt_note_change('inner', old,
      old.inner_status || case when coalesce(old.not_chalak_inner, false) then '/notChalak' else '' end,
      new.inner_status || case when coalesce(new.not_chalak_inner, false) then '/notChalak' else '' end, v_dev);
  end if;
  if old.outer_status is not null
     and ((new.outer_status, new.outer_by, new.outer_by_device) is distinct from (old.outer_status, old.outer_by, old.outer_by_device)
          or coalesce(new.nc_plain, false) is distinct from coalesce(old.nc_plain, false)) then
    perform _raise_correction(_correction_check('outer', old, v_dev), 'outer');
    perform _gt_note_change('outer', old, _printed_as_key(old), _printed_as_key(new), v_dev);
  end if;
  return new;
end $$;
revoke execute on function animals_pilot_guard_corrections() from public, anon, authenticated;

-- the esophagus change: any esophagus tablet, any time; back to "ok" for a number the
-- shochet had not ruled yet (an open "?") gives it back its "?"
create or replace function eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  a animals_pilot%rowtype;
  v_rows integer := 0;
  v_epoch bigint := _board_epoch();
  v_dev text;
  v_err text;
  v_res jsonb;
  v_wait int;
  v_q boolean;
begin
  if p_result is null or p_result not in ('ok','nevela') then
    return jsonb_build_object('ok', false, 'error', 'bad_result');
  end if;
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  perform _board_write_lock();
  v_epoch := _board_epoch();
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  v_dev := _call_device(p_device_id);
  if v_dev is null then return jsonb_build_object('ok', false, 'error', _no_device_error()); end if;
  if not _stage_allowed('eso') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  v_res := _cmd_get(p_command_id, v_dev, 'eso_change');
  if v_res is not null then return v_res; end if;
  select * into a from animals_pilot where id = p_id for update;
  if a.id is null or a.eso_checked is distinct from true then
    v_res := jsonb_build_object('ok', false, 'error', 'not_checked');
    perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
    return v_res;
  end if;
  if coalesce(a.board_epoch, 0) > coalesce(v_epoch, 0) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', a.board_epoch);
  end if;
  if a.eso_result = p_result then
    v_res := jsonb_build_object('ok', true, 'row', to_jsonb(a));
    perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
    return v_res;
  end if;
  if _is_api_request() and not _request_is_service_role() then
    v_wait := _correction_braked(v_dev);
    if v_wait is not null then
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'retry_after', v_wait, 'row', to_jsonb(a));
    end if;
    v_err := _correction_check('eso', a, v_dev);
    if v_err is not null then
      perform _log_correction_rejected(v_dev, p_id, 'esophagus', v_err,
                                       jsonb_build_object('from', a.eso_result, 'to', p_result, 'via', 'eso_change'));
      v_res := jsonb_build_object('ok', false, 'error', v_err, 'row', to_jsonb(a));
      perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
      return v_res;
    end if;
  end if;
  -- the shochet's "?" was closed by this esophagus nevela: back to ok → the "?" is open again
  v_q := p_result = 'ok' and a.eso_prev_slaughter is null and exists (
           select 1 from animal_holds h where h.board_epoch = coalesce(a.board_epoch, v_epoch) and h.animal_id = a.id
              and h.station = 'slaughter' and h.kind = 'question' and h.resolution = 'ruled' and h.note = 'eso_nevela');
  perform _gt_note_change('eso', a, a.eso_result, p_result, v_dev);
  perform set_config('gt.eso_ruling', 'true', true);
  if p_result = 'nevela' then
    update animals_pilot
       set eso_result = 'nevela', eso_prev_slaughter = slaughter, slaughter = 'nevela',
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev,
           eso_by_device = coalesce(eso_by_device, v_dev),
           device_id = v_dev, updated_at = now()
     where id = p_id and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  elsif v_q then
    -- the slaughter columns go back to "not ruled yet" (the merge rules never clear a ruling, so
    -- this one row is written past them; nothing else on it changes)
    perform set_config('gt.reset_in_progress', 'true', true);
    update animals_pilot
       set eso_result = 'ok', slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
           eso_prev_slaughter = null, eso_by_device = coalesce(eso_by_device, v_dev),
           device_id = v_dev, updated_at = clock_timestamp()
     where id = p_id and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    perform set_config('gt.reset_in_progress', 'false', true);
    insert into animal_holds (board_epoch, animal_id, station, kind, part, created_by, created_by_device, note)
    select coalesce(a.board_epoch, v_epoch), a.id, 'slaughter', 'question', 'whole', h.created_by, h.created_by_device, 'reopened'
      from animal_holds h where h.board_epoch = coalesce(a.board_epoch, v_epoch) and h.animal_id = a.id
       and h.station = 'slaughter' and h.kind = 'question' and h.note = 'eso_nevela'
     order by h.id desc limit 1
    on conflict do nothing;
  else
    update animals_pilot
       set eso_result = 'ok', slaughter = coalesce(eso_prev_slaughter, 'slaughtered'),
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev,
           eso_by_device = coalesce(eso_by_device, v_dev),
           device_id = v_dev, updated_at = now()
     where id = p_id and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  end if;
  get diagnostics v_rows = row_count;
  perform set_config('gt.eso_ruling', '', true);
  select * into a from animals_pilot where id = p_id;
  v_res := jsonb_build_object('ok', v_rows = 1, 'row', to_jsonb(a));
  perform _cmd_put(p_command_id, v_dev, 'eso_change', v_res);
  return v_res;
end $$;
revoke execute on function eso_change(integer, text, text, bigint, uuid) from public;
grant execute on function eso_change(integer, text, text, bigint, uuid) to anon, authenticated;

-- the team leader marks a change handled (the stickers were collected, …)
create or replace function change_ack(p_token text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c animal_changes%rowtype;
begin
  if coalesce(_session_role(p_token), '') <> 'manager' or not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  update animal_changes set ack_at = now(), ack_by = _session_name(p_token)
   where id = p_id and ack_at is null returning * into c;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'bad_id'); end if;
  perform _gt_event(c.animal_id + 1, c.stage, 'change_handled', jsonb_build_object('change', c.id), _session_name(p_token),
                    coalesce(_current_device_id(), 'team-leader'));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function change_ack(text, bigint) from public;
grant execute on function change_ack(text, bigint) to anon, authenticated;

-- ── §29 what every screen shows: open holds, closed ones of the day, changes not handled ──
create or replace function board_flags(p_token text default null) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_ep bigint := _board_epoch();
begin
  if _current_device_id() is null and coalesce(_session_role(p_token), '') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'boardEpoch', v_ep,
    'holds', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', h.id, 'epoch', h.board_epoch, 'n', h.animal_id, 'station', h.station, 'kind', h.kind, 'part', h.part,
                 'at', h.created_at, 'by', h.created_by, 'open', h.resolved_at is null, 'resolution', h.resolution,
                 'resolvedAt', h.resolved_at, 'note', h.note,
                 'board', (select c.board_id from animals_carry c where c.board_epoch = h.board_epoch limit 1),
                 'day', (select c.slaughter_day from animals_carry c where c.board_epoch = h.board_epoch limit 1))
               order by h.id)
             from animal_holds h
            where h.resolved_at is null
               or (h.board_epoch = v_ep)
               or (h.resolution = 'condemned' and exists (select 1 from animals_carry c where c.board_epoch = h.board_epoch))
               or (h.resolution = 'released' and h.resolved_at > now() - interval '2 days'
                   and exists (select 1 from animals_carry c where c.board_epoch = h.board_epoch))), '[]'::jsonb),
    'changes', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', c.id, 'epoch', c.board_epoch, 'n', c.animal_id, 'stage', c.stage, 'from', c.old_value, 'to', c.new_value,
                 'done', c.done, 'at', c.at, 'ackAt', c.ack_at, 'ackBy', c.ack_by) order by c.id)
             from animal_changes c
            where c.ack_at is null or (c.board_epoch = v_ep and c.ack_at > now() - interval '1 day')), '[]'::jsonb));
end $$;
revoke execute on function board_flags(text) from public;
grant execute on function board_flags(text) to anon, authenticated;

-- the daily reset: a board with an open hold is kept for processing; holds of a
-- board that is not kept are closed ('board_closed')
create or replace function _do_board_reset(p_reason text, p_business_date date) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
        v_old_epoch bigint := _board_epoch();
        v_day date := coalesce(p_business_date, _board_business_date());
        v_board bigint; v_carry boolean := false; st text;
begin
  insert into daily_board_archive (business_date, reason, animals_count, board, statuses)
  select v_day, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb),
         jsonb_build_object('customStatuses', coalesce(_gt_settings() -> 'customStatuses', '[]'::jsonb),
                            'disabledStatuses', coalesce(_gt_settings() -> 'disabledStatuses', '[]'::jsonb),
                            'kosher', to_jsonb(_kosher_statuses()))
    from animals_pilot a
   where a.slaughter is not null or a.inner_status is not null or a.outer_status is not null
  returning id into v_board;

  foreach st in array _proc_stations() loop
    if exists (select 1 from animals_pilot a where _proc_pending(st, a, true)) then v_carry := true; exit; end if;
  end loop;
  -- v10.26: an open processing hold (USDA / "?") keeps the board too
  if not v_carry and v_old_epoch is not null and exists (
       select 1 from animal_holds h join animals_pilot a on a.id = h.animal_id and a.slaughter is not null
        where h.board_epoch = v_old_epoch and h.resolved_at is null) then
    v_carry := true;
  end if;
  if v_carry then
    insert into animals_carry          -- by column name (v10.33: columns added later sit after board_id)
    select (jsonb_populate_record(null::animals_carry,
              to_jsonb(a) || jsonb_build_object('board_id', v_board, 'slaughter_day', v_day))).*
      from animals_pilot a where a.slaughter is not null;
  end if;
  if v_old_epoch is not null then
    update animal_holds set resolved_at = now(), resolution = 'board_closed'
     where board_epoch = v_old_epoch and resolved_at is null
       and (not v_carry or not exists (select 1 from animals_carry c where c.board_id = v_board and c.id = animal_holds.animal_id));
  end if;
  perform _proc_finalize(null);

  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);

  insert into plant_state (key, value) values ('boardEpoch', v_epoch::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false, not_chalak_outer = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null, nc_plain = false,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null, eso_prev_slaughter = null, eso_by_device = null,
    legs_sorted = false,
    stamped = false, stamped_as = null,
    parts_print_count = 0, parts_printed_as = null,
    board_epoch = v_epoch,
    updated_at = clock_timestamp()
  where true;

  delete from device_stage_cursor where true;
  update devices_pilot set cursor_slaughter = null, cursor_inner = null, cursor_outer = null, cursor_eso = null
   where cursor_slaughter is not null or cursor_inner is not null or cursor_outer is not null or cursor_eso is not null;

  perform set_config('gt.reset_in_progress', 'false', true);
  perform set_config('app.device_admin', '', true);

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason,
                                'boardEpoch', v_epoch, 'dailyIntake', '[]'::jsonb, 'activeUserByRole', '{}'::jsonb),
          'server', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb)
                   || jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason,
                                         'boardEpoch', v_epoch, 'dailyIntake', '[]'::jsonb, 'activeUserByRole', '{}'::jsonb),
        device_id = 'server',
        updated_at = now();
end $$;
revoke execute on function _do_board_reset(text, date) from public, anon, authenticated;

-- ── §30 "not chalak" at the outer ruling: רבנות כשר or כשר (v10.33) ──────────
-- "Not chalak" holds until the outer ruling. There the animal is ruled רבנות כשר
-- (outer_status 'kosher') or plain כשר (outer_status 'kosher' + nc_plain) or treif
-- (רבנות חלק too when it was only sent to the rabbinate screen). nc_plain moves only with
-- the outer ruling itself: a write whose outer ruling the merge did not take keeps the
-- server's flag, and the flag is cleared on anything but a kosher ruling of a
-- "not chalak" animal.
create or replace function _animals_nc_plain() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if tg_op = 'UPDATE' and current_setting('gt.reset_in_progress', true) is distinct from 'true'
     and coalesce(current_setting('gt.claim', true), '') <> 'true'
     and (new.outer_status, new.outer_time, new.outer_by, new.outer_by_device)
         is not distinct from (old.outer_status, old.outer_time, old.outer_by, old.outer_by_device) then
    new.nc_plain := old.nc_plain;
  end if;
  if new.outer_status is distinct from 'kosher' or not coalesce(_is_nc(new), false) then
    new.nc_plain := false;
  end if;
  new.nc_plain := coalesce(new.nc_plain, false);
  return new;
end $$;
revoke execute on function _animals_nc_plain() from public, anon, authenticated;
drop trigger if exists a_animals_nc_plain on animals_pilot;
create trigger a_animals_nc_plain before insert or update on animals_pilot
  for each row execute function _animals_nc_plain();

-- ── self-check ──────────────────────────────────────────────────────────────
do $$
declare problems text[] := '{}';
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'animals_pilot'::regclass and tgname = 'b_animals_stage_guard' and tgenabled <> 'D') then
    problems := problems || 'stage guard trigger missing'::text; end if;
  if has_table_privilege('anon', 'animals_carry', 'select') or has_table_privilege('anon', 'processing_day_closed', 'select') then
    problems := problems || 'processing tables readable by the app directly'::text; end if;
  if to_regprocedure('public.reset_daily_board(text)') is not null then
    problems := problems || 'old reset_daily_board(text) still there'::text; end if;
  if (select count(*) from pg_proc where proname = 'push_settings' and pronamespace = 'public'::regnamespace) <> 1 then
    problems := problems || 'more than one push_settings()'::text; end if;
  if _stage_order_error('outer', jsonb_populate_record(null::animals_pilot, '{"id":5,"slaughter":"slaughtered"}')) is distinct from 'inner_not_confirmed' then
    problems := problems || 'order rule outer'::text; end if;
  if exists (select 1 from unnest(array['animal_push(jsonb,uuid)', 'claim_animal_stage(integer,text,text,text,text,bigint,uuid)',
                                       'eso_change(integer,text,text,bigint,uuid)', 'set_not_chalak_outer(integer,bigint,uuid)',
                                       'outer_open(integer,bigint,boolean,text,uuid)', 'lung_drawing_set(integer,bigint,text)']) f
              where pg_get_functiondef(f::regprocedure) !~ '_board_write_lock\(\)') then
    problems := problems || 'a board writer without the reset lock'::text; end if;
  if pg_get_functiondef('worker_login(text,text,text)'::regprocedure) ~ 'x \? ''code''' then
    problems := problems || 'worker_login still accepts a plain-text code'::text; end if;
  if has_function_privilege('anon', 'leader_device_recovery(text)', 'execute') then
    problems := problems || 'leader_device_recovery callable by the app'::text; end if;
  if pg_get_functiondef('manager_add(text,text,text)'::regprocedure) !~ 'server_only' then
    problems := problems || 'manager_add still open through the app'::text; end if;
  if has_function_privilege('anon', 'leader_account_add(text,text)', 'execute') then
    problems := problems || 'leader_account_add callable by the app'::text; end if;
  if has_function_privilege('anon', '_gt_one_inspection()', 'execute') or has_function_privilege('anon', '_leader_recovery_norm(text)', 'execute') then
    problems := problems || 'an internal function callable by the app'::text; end if;
  if has_function_privilege('anon', '_gt_standbys()', 'execute') then
    problems := problems || '_gt_standbys callable by the app'::text; end if;
  if pg_get_functiondef('_stage_allowed(text)'::regprocedure) !~ '_worker_gate' then
    problems := problems || '_stage_allowed does not check the worker login (v10.16 A1)'::text; end if;
  if pg_get_functiondef('leader_device_replace(text,text)'::regprocedure) !~ 'pg_advisory_xact_lock' then
    problems := problems || 'leader_device_replace is not serialized (v10.16 A2)'::text; end if;
  if has_function_privilege('anon', '_worker_gate(text)', 'execute') then
    problems := problems || '_worker_gate callable by the app'::text; end if;
  if pg_get_functiondef('_stage_allowed(text)'::regprocedure) !~ '_gt_one_inspection' then
    problems := problems || 'shared inner + outer screen missing in _stage_allowed'::text; end if;
  if not _nc_outer_value_ok(jsonb_populate_record(null::animals_pilot, '{"id":5,"slaughter":"slaughtered","not_chalak_outer":true}'), 'rabChalak')
     or _nc_outer_value_ok(jsonb_populate_record(null::animals_pilot, '{"id":5,"slaughter":"notChalak"}'), 'rabChalak')
     or _nc_outer_value_ok(jsonb_populate_record(null::animals_pilot, '{"id":5,"slaughter":"slaughtered","not_chalak_outer":true}'), 'glatt') then
    problems := problems || 'rabbinate screen rulings (v10.17)'::text; end if;
  if has_table_privilege('anon', 'kashrut_seals', 'select') or has_function_privilege('anon', '_seal_key_ok(text)', 'execute') then
    problems := problems || 'kashrut seals readable directly by the app (v10.22)'::text; end if;
  if has_table_privilege('anon', 'animal_holds', 'select') or has_table_privilege('anon', 'animal_changes', 'select')
     or has_function_privilege('anon', '_hold_block(bigint,integer,text,text)', 'execute') then
    problems := problems || 'holds / changes readable directly by the app (v10.26)'::text; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'animals_pilot'::regclass and tgname = 'b_animals_hold_guard' and tgenabled <> 'D')
     or not exists (select 1 from pg_trigger where tgrelid = 'animals_pilot'::regclass and tgname = 'zzzzz_close_questions' and tgenabled <> 'D') then
    problems := problems || 'hold triggers missing (v10.26)'::text; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'animals_pilot'::regclass and tgname = 'a_animals_nc_plain' and tgenabled <> 'D')
     or _printed_as_key(jsonb_populate_record(null::animals_pilot, '{"id":5,"slaughter":"notChalak","outer_status":"kosher","nc_plain":true}')) <> 'kosher'
     or _printed_as_key(jsonb_populate_record(null::animals_pilot, '{"id":5,"slaughter":"notChalak","outer_status":"kosher"}')) <> 'kosherRab' then
    problems := problems || '"not chalak" plain kosher at the outer ruling (v10.33)'::text; end if;
  if (select value from plant_state where key = 'schemaStep')::int < 46 then
    problems := problems || 'schemaStep not 46'::text; end if;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 46 self-check FAILED: %', array_to_string(problems, ' | ');
  end if;
  raise notice 'GlattTrack step 46 self-check OK';
end $$;

notify pgrst, 'reload schema';
