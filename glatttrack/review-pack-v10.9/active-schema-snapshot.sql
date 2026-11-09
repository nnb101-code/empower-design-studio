--
-- PostgreSQL database dump
--

\restrict hTvBLK3WHyccmIUz1chRGp0lp11GLTZSjcn8d6uhDvh4NKlvxF14WM0JxnFjiHX

-- Dumped from database version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: gt_rls; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA gt_rls;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: devices_read_all(); Type: FUNCTION; Schema: gt_rls; Owner: -
--

CREATE FUNCTION gt_rls.devices_read_all() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_uid uuid;
begin
  if not _is_app_caller() or _request_is_service_role() then return true; end if;
  if coalesce(_session_role(_request_headers() ->> 'x-manager-token'), '') in ('manager', 'owner', 'manufacturer') then
    return true;
  end if;
  if _is_api_request() then return false; end if;
  -- live updates carry only the app session: a live team-leader / owner session of it
  v_uid := _auth_uid_safe();
  if v_uid is null then return false; end if;
  return exists(select 1 from manager_sessions s join plant_managers m on m.id = s.manager_id
                 where s.auth_uid = v_uid and s.expires_at > now() and m.active and m.role in ('manager', 'owner'));
end $$;


--
-- Name: devices_read_own_ids(); Type: FUNCTION; Schema: gt_rls; Owner: -
--

CREATE FUNCTION gt_rls.devices_read_own_ids() RETURNS text[]
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v text; v_uid uuid;
begin
  v := _current_device_id();
  if v is not null then return array[v]; end if;
  if _is_api_request() then return '{}'::text[]; end if;
  v_uid := _auth_uid_safe();
  if v_uid is null then return '{}'::text[]; end if;
  return coalesce((select array_agg(d.id) from devices_pilot d join device_credentials c on c.device_id = d.id
                    where d.auth_uid = v_uid and not c.revoked), '{}'::text[]);
end $$;


--
-- Name: events_reader_ok(); Type: FUNCTION; Schema: gt_rls; Owner: -
--

CREATE FUNCTION gt_rls.events_reader_ok() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_role text;
begin
  if not _is_app_caller() or _request_is_service_role() then return true; end if;
  v_role := coalesce(_session_role(_request_headers() ->> 'x-manager-token'), '');
  if v_role in ('manager', 'owner') then return true; end if;
  if v_role = 'manufacturer' and _support_access_open() then return true; end if;
  return false;
end $$;


--
-- Name: _acting_device(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._acting_device() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v text; t text;
begin
  v := _current_device_id();
  if v is not null then return v; end if;
  if _test_mode_on() and _request_has_manager() then
    t := _request_headers() ->> 'x-manager-token';
    return 'mgr-' || left(encode(digest(t, 'sha256'), 'hex'), 16);
  end if;
  return null;
end $$;


--
-- Name: _admin_audit(text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._admin_audit(p_token text, p_action text, p_target text, p_detail jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  insert into admin_audit (who, role, action, target, detail)
  values (_session_name(p_token), _session_role(p_token), p_action, p_target, coalesce(p_detail, '{}'::jsonb));
end $$;


--
-- Name: _animals_merge(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._animals_merge() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare
  v_epoch bigint := _board_epoch();
  v_api   boolean := _is_api_request() and not _request_is_service_role();
  v_dev   text;
  v_priv  boolean;
  v_now   bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_cap   bigint;
  v_eso   boolean := coalesce(current_setting('gt.eso_ruling', true), '') = 'true';
  v_claim boolean := coalesce(current_setting('gt.claim', true), '') = 'true';
  v_admin boolean := coalesce(current_setting('app.device_admin', true), '') = 'on';
  v_eso_upsert boolean := false;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;
  v_dev := case when v_api then _acting_device() else _current_device_id() end;

  if v_epoch is not null and _is_api_request() and (new.board_epoch is null or new.board_epoch < v_epoch) then
    raise exception 'GT:STALE_BOARD stale-board: this device still has the previous day''s board' using errcode = 'P0001';
  end if;

  new.updated_at := clock_timestamp();
  if v_api and not v_admin then new.device_id := v_dev; end if;          -- the server's identity, never the tablet's word

  if tg_op = 'INSERT' then
    new.board_epoch := coalesce(v_epoch, new.board_epoch);
    if _is_api_request() and not exists (select 1 from animals_pilot x where x.id = new.id) then
      new.slaughter := null; new.slaughtered_by := null; new.slaughter_time := null; new.slaughter_by_device := null;
      new.inner_status := null; new.inner_by := null; new.inner_time := null; new.inner_by_device := null;
      new.outer_status := null; new.outer_by := null; new.outer_time := null; new.outer_by_device := null;
      new.maw := null; new.rumen := null; new.not_chalak_inner := false;
      new.legs_stickers := false; new.head_stickers := false; new.legs_sorted := false;
      new.parts_scanned := false; new.tongue_sticker := false; new.cheek_sticker := false;
      new.parts_print_count := 0; new.parts_printed_as := null;
      new.stamped := false; new.stamped_as := null;
      new.weight_right := null; new.weight_left := null; new.weight_stage2 := null; new.weight_stage3 := null;
      new.weight_right_skipped := false; new.weight_left_skipped := false;
      new.weight_stage2_skipped := false; new.weight_stage3_skipped := false;
      new.eso_checked := false; new.eso_result := null; new.eso_prev_slaughter := null; new.eso_by_device := null;
    end if;
    return new;
  end if;
  new.board_epoch := coalesce(v_epoch, new.board_epoch, old.board_epoch);
  v_priv := _request_privileged();

  if _is_api_request() then
    v_cap := v_now + 60000;
    if new.slaughter_time is distinct from old.slaughter_time and new.slaughter_time > v_cap then new.slaughter_time := v_cap; end if;
    if new.inner_time     is distinct from old.inner_time     and new.inner_time     > v_cap then new.inner_time     := v_cap; end if;
    if new.outer_time     is distinct from old.outer_time     and new.outer_time     > v_cap then new.outer_time     := v_cap; end if;
  end if;

  -- esophagus: only through the ruling itself — except a "nevela" sent by an
  -- esophagus tablet that was offline, which is applied whole
  if not v_eso then
    if new.eso_result = 'nevela' and old.eso_result is distinct from 'nevela' and _stage_allowed('eso')
       and (v_dev is not null or not v_api) then
      v_eso_upsert := true;
      new.eso_checked := true;
      new.eso_by_device := coalesce(v_dev, old.eso_by_device);
      new.eso_prev_slaughter := case when old.slaughter = 'nevela' then coalesce(old.eso_prev_slaughter, 'slaughtered')
                                     else old.slaughter end;
      new.slaughter := 'nevela';
      new.slaughtered_by := old.slaughtered_by;
      new.slaughter_time := greatest(v_now, coalesce(old.slaughter_time, 0) + 1);
      new.slaughter_by_device := coalesce(v_dev, old.slaughter_by_device);
      perform set_config('gt.eso_upsert_row', new.id::text, true);
    else
      new.eso_result := old.eso_result;
      new.eso_checked := old.eso_checked;
      new.eso_prev_slaughter := old.eso_prev_slaughter;
      new.eso_by_device := old.eso_by_device;
    end if;
  end if;

  if not (v_eso or v_eso_upsert) and old.slaughter_time is not null
     and (new.slaughter_time is null or new.slaughter_time < old.slaughter_time) then
    new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
    new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
  end if;
  if old.inner_time is not null and (new.inner_time is null or new.inner_time < old.inner_time) then
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
    new.not_chalak_inner := old.not_chalak_inner;
  end if;
  if old.outer_time is not null and (new.outer_time is null or new.outer_time < old.outer_time) then
    new.outer_status := old.outer_status; new.outer_time := old.outer_time;
    new.outer_by := old.outer_by; new.outer_by_device := old.outer_by_device;
  end if;
  if new.slaughter is null and old.slaughter is not null
     and (not v_priv or new.slaughter_time is null) then
    new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
    new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
  end if;
  if new.outer_status is null and old.outer_status is not null and new.outer_time is null then new.outer_status := old.outer_status; end if;

  if new.inner_status is null and old.inner_status is not null then
    if old.inner_status in ('confirmed', 'treif')
       or (old.inner_status = 'in_progress' and not v_priv and old.inner_by_device is distinct from v_dev) then
      new.inner_status := old.inner_status; new.inner_time := old.inner_time;
      new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
      new.not_chalak_inner := old.not_chalak_inner;
    end if;
  end if;

  -- an open lung check belongs to the tablet holding it (10-minute takeover
  -- aside): another tablet's write — e.g. the one that lost the check after a
  -- takeover — can't replace it. The refusal is recorded.
  if v_api and not v_claim and not v_admin
     and old.inner_status = 'in_progress' and old.inner_by_device is distinct from v_dev
     and coalesce(old.inner_time, 0) >= v_now - 600000
     and ((new.inner_status, new.inner_time, new.inner_by, new.inner_by_device, coalesce(new.not_chalak_inner, false))
          is distinct from (old.inner_status, old.inner_time, old.inner_by, old.inner_by_device, coalesce(old.not_chalak_inner, false))
          or coalesce(new.maw, old.maw) is distinct from old.maw
          or coalesce(new.rumen, old.rumen) is distinct from old.rumen) then
    perform _security_event(new.id + 1, 'inner_takeover_rejected',
      jsonb_build_object('holder', old.inner_by_device, 'tried', new.inner_status, 'via', 'push'), null, coalesce(v_dev, 'unknown'));
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
    new.not_chalak_inner := old.not_chalak_inner;
    new.maw := old.maw; new.rumen := old.rumen;
  end if;

  if not (v_eso or v_eso_upsert)
     and (new.slaughter, new.slaughter_time, new.slaughtered_by, new.slaughter_by_device)
         is distinct from (old.slaughter, old.slaughter_time, old.slaughtered_by, old.slaughter_by_device)
     and not _stage_allowed('slaughter') then
    new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
    new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
  end if;
  if (new.inner_status, new.inner_time, new.inner_by, new.inner_by_device, coalesce(new.not_chalak_inner, false))
     is distinct from (old.inner_status, old.inner_time, old.inner_by, old.inner_by_device, coalesce(old.not_chalak_inner, false))
     and not _stage_allowed('inner') then
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
    new.not_chalak_inner := old.not_chalak_inner;
  end if;
  if (new.outer_status, new.outer_time, new.outer_by, new.outer_by_device)
     is distinct from (old.outer_status, old.outer_time, old.outer_by, old.outer_by_device)
     and not _stage_allowed('outer') then
    new.outer_status := old.outer_status; new.outer_time := old.outer_time;
    new.outer_by := old.outer_by; new.outer_by_device := old.outer_by_device;
  end if;

  -- which device made a ruling: always the server's identity of the caller
  if v_api and not v_admin then
    if (new.slaughter, new.slaughter_time) is distinct from (old.slaughter, old.slaughter_time) then new.slaughter_by_device := v_dev;
    else new.slaughter_by_device := old.slaughter_by_device; end if;
    if (new.inner_status, new.inner_time) is distinct from (old.inner_status, old.inner_time) then new.inner_by_device := v_dev;
    else new.inner_by_device := old.inner_by_device; end if;
    if (new.outer_status, new.outer_time) is distinct from (old.outer_status, old.outer_time) then new.outer_by_device := v_dev;
    else new.outer_by_device := old.outer_by_device; end if;
  end if;

  if v_api and not v_claim then
    if not (v_eso or v_eso_upsert) and new.slaughter is not null
       and (new.slaughter, new.slaughter_time, new.slaughtered_by) is distinct from (old.slaughter, old.slaughter_time, old.slaughtered_by) then
      new.slaughtered_by := _derive_actor('slaughter', case when new.slaughtered_by is distinct from old.slaughtered_by then new.slaughtered_by end);
    end if;
    if new.inner_status is not null
       and (new.inner_status, new.inner_time, new.inner_by) is distinct from (old.inner_status, old.inner_time, old.inner_by) then
      new.inner_by := _derive_actor('inner', case when new.inner_by is distinct from old.inner_by then new.inner_by end);
    end if;
    if new.outer_status is not null
       and (new.outer_status, new.outer_time, new.outer_by) is distinct from (old.outer_status, old.outer_time, old.outer_by) then
      new.outer_by := _derive_actor('outer', case when new.outer_by is distinct from old.outer_by then new.outer_by end);
    end if;
  end if;

  if not _stage_allowed('inner') then
    new.maw := old.maw; new.rumen := old.rumen;
  end if;
  if not _stage_allowed('legs') then
    new.legs_sorted := old.legs_sorted; new.legs_stickers := old.legs_stickers; new.head_stickers := old.head_stickers;
  end if;
  if not _stage_allowed('stamped') then
    new.stamped := old.stamped; new.stamped_as := old.stamped_as;
  end if;
  if not _stage_allowed('parts') then
    new.parts_scanned := old.parts_scanned; new.tongue_sticker := old.tongue_sticker; new.cheek_sticker := old.cheek_sticker;
    new.parts_print_count := old.parts_print_count; new.parts_printed_as := old.parts_printed_as;
  end if;
  if not _stage_allowed('weights') then
    new.weight_right := old.weight_right; new.weight_left := old.weight_left;
    new.weight_stage2 := old.weight_stage2; new.weight_stage3 := old.weight_stage3;
    new.weight_right_skipped := old.weight_right_skipped; new.weight_left_skipped := old.weight_left_skipped;
    new.weight_stage2_skipped := old.weight_stage2_skipped; new.weight_stage3_skipped := old.weight_stage3_skipped;
  end if;

  new.legs_stickers         := coalesce(old.legs_stickers, false)         or coalesce(new.legs_stickers, false);
  new.head_stickers         := coalesce(old.head_stickers, false)         or coalesce(new.head_stickers, false);
  new.parts_scanned         := coalesce(old.parts_scanned, false)         or coalesce(new.parts_scanned, false);
  new.tongue_sticker        := coalesce(old.tongue_sticker, false)        or coalesce(new.tongue_sticker, false);
  new.cheek_sticker         := coalesce(old.cheek_sticker, false)         or coalesce(new.cheek_sticker, false);
  new.stamped               := coalesce(old.stamped, false)               or coalesce(new.stamped, false);
  new.weight_right_skipped  := coalesce(old.weight_right_skipped, false)  or coalesce(new.weight_right_skipped, false);
  new.weight_left_skipped   := coalesce(old.weight_left_skipped, false)   or coalesce(new.weight_left_skipped, false);
  new.weight_stage2_skipped := coalesce(old.weight_stage2_skipped, false) or coalesce(new.weight_stage2_skipped, false);
  new.weight_stage3_skipped := coalesce(old.weight_stage3_skipped, false) or coalesce(new.weight_stage3_skipped, false);
  new.eso_checked           := coalesce(old.eso_checked, false)           or coalesce(new.eso_checked, false);
  new.legs_sorted           := coalesce(old.legs_sorted, false)           or coalesce(new.legs_sorted, false);
  new.not_chalak_inner      := coalesce(new.not_chalak_inner, false);

  new.maw           := coalesce(new.maw, old.maw);
  new.rumen         := coalesce(new.rumen, old.rumen);
  new.weight_right  := coalesce(new.weight_right, old.weight_right);
  new.weight_left   := coalesce(new.weight_left, old.weight_left);
  new.weight_stage2 := coalesce(new.weight_stage2, old.weight_stage2);
  new.weight_stage3 := coalesce(new.weight_stage3, old.weight_stage3);
  new.eso_result    := coalesce(new.eso_result, old.eso_result);

  new.parts_print_count := greatest(coalesce(old.parts_print_count, 0), coalesce(new.parts_print_count, 0));
  return new;
end $$;


--
-- Name: _animals_nc_outer_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._animals_nc_outer_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    new.not_chalak_outer := false; return new;
  end if;
  if not _is_api_request() or _request_is_service_role() then return new; end if;   -- plant server / SQL editor
  if tg_op = 'INSERT' then
    if not exists(select 1 from animals_pilot where id = new.id) then new.not_chalak_outer := false; end if;
    return new;
  end if;
  if new.not_chalak_outer is distinct from old.not_chalak_outer then
    if not (coalesce(current_setting('gt.nc_outer', true), '') = 'true'
            and coalesce(new.not_chalak_outer, false) = true
            and coalesce(old.not_chalak_outer, false) = false
            and old.outer_status is null
            and _nc_outer_allowed()) then
      new.not_chalak_outer := old.not_chalak_outer;               -- set once, by an outer station, before the ruling
    end if;
  end if;
  return new;
end $$;


--
-- Name: _animals_nc_outer_value(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._animals_nc_outer_value() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  if new.outer_status is not null and new.outer_status not in ('kosher', 'treif')
     and (tg_op = 'INSERT' or new.outer_status is distinct from old.outer_status)
     and (new.slaughter = 'notChalak' or coalesce(new.not_chalak_inner, false) or coalesce(new.not_chalak_outer, false)) then
    raise exception 'GT:INVALID_VALUE a "not chalak" animal can only be ruled kosher or treif (nc_kosher_or_treif_only)'
      using errcode = '23514';
  end if;
  return new;
end $$;


--
-- Name: _animals_outer_open_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._animals_outer_open_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if coalesce(current_setting('gt.outer_open', true), '') = 'true' then return new; end if;
  if tg_op = 'INSERT' then
    new.outer_open_by_device := null; new.outer_open_at := null;
    return new;
  end if;
  new.outer_open_by_device := old.outer_open_by_device; new.outer_open_at := old.outer_open_at;
  if current_setting('gt.reset_in_progress', true) = 'true'
     or (new.outer_status is distinct from old.outer_status) then
    new.outer_open_by_device := null; new.outer_open_at := null;
  end if;
  return new;
end $$;


--
-- Name: _animals_stage_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._animals_stage_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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
    v_err := case when old.slaughter not in ('slaughtered', 'notChalak') or old.slaughter is null then 'not_slaughtered'
                  when new.inner_status is not null or new.outer_status is not null then 'later_stage_started' end;
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


--
-- Name: _archive_keep_intake(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._archive_keep_intake() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if new.intake is null then
    select coalesce(settings -> 'dailyIntake', '[]'::jsonb) into new.intake from settings_pilot where id = 1;
  end if;
  return new;
end $$;


--
-- Name: _audit_device_event(text, text, text, integer, text, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._audit_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text, p_replacement_id uuid, p_actor text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  insert into device_lifecycle_events (device_id, action, station_id, station_slot, actor, reason, replacement_device_id, replacement_id)
  values (p_device, p_action, p_role, p_idx, coalesce(p_actor, 'manager'), left(p_reason, 200), p_other, p_replacement_id);
end $$;


--
-- Name: _auth_uid_safe(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._auth_uid_safe() RETURNS uuid
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v uuid;
begin
  begin v := auth.uid(); exception when others then v := null; end;
  if v is null then
    begin
      v := nullif(current_setting('request.jwt.claims', true)::json ->> 'sub', '')::uuid;
    exception when others then v := null;
    end;
  end if;
  return v;
end $$;


--
-- Name: _board_business_date(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._board_business_date() RETURNS date
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare tz text := coalesce(nullif(_gt_settings() ->> 'plantTimezone', ''), 'UTC'); d date;
begin
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  select (min(to_timestamp(slaughter_time / 1000.0)) at time zone tz)::date into d
    from animals_pilot where slaughter_time is not null;
  return coalesce(d, (now() at time zone tz)::date);
end $$;


--
-- Name: _board_epoch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._board_epoch() RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
  select nullif(value, '')::bigint from plant_state where key = 'boardEpoch' and value ~ '^\d+$';
$_$;


--
-- Name: _board_unfinished(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._board_unfinished() RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select count(*)::int from animals_pilot
   where slaughter in ('slaughtered', 'notChalak')
     and inner_status is distinct from 'treif' and outer_status is null;
$$;


--
-- Name: _board_write_lock(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._board_write_lock() RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select pg_advisory_xact_lock_shared(hashtext('glatttrack_daily_rollover'));
$$;


--
-- Name: _call_device(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._call_device(p_client text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if _is_api_request() and not _request_is_service_role() then return _acting_device(); end if;
  return coalesce(_current_device_id(), nullif(left(p_client, 80), ''), 'server');
end $$;


--
-- Name: _caller_device_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._caller_device_role() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_dev text; v_role text;
begin
  v_dev := _current_device_id();
  if v_dev is null then return null; end if;
  select assigned_role into v_role from devices_pilot
   where id = v_dev and coalesce(device_status, 'active') <> 'retired';
  if v_role is null then perform _note_revoked_write(v_dev); end if;
  return v_role;
end $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: animals_carry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.animals_carry (
    id integer NOT NULL,
    slaughter text,
    slaughtered_by text,
    slaughter_time bigint,
    legs_stickers boolean,
    head_stickers boolean,
    maw text,
    rumen text,
    inner_status text,
    inner_by text,
    inner_time bigint,
    outer_status text,
    outer_by text,
    outer_time bigint,
    parts_scanned boolean,
    tongue_sticker boolean,
    cheek_sticker boolean,
    weight_right numeric,
    weight_left numeric,
    device_id text,
    updated_at timestamp with time zone DEFAULT now(),
    slaughter_by_device text,
    inner_by_device text,
    outer_by_device text,
    weight_stage2 numeric,
    weight_stage3 numeric,
    stamped boolean,
    weight_right_skipped boolean DEFAULT false,
    weight_left_skipped boolean DEFAULT false,
    weight_stage2_skipped boolean DEFAULT false,
    weight_stage3_skipped boolean DEFAULT false,
    not_chalak_inner boolean DEFAULT false,
    eso_checked boolean DEFAULT false,
    eso_result text,
    legs_sorted boolean DEFAULT false,
    parts_print_count integer DEFAULT 0,
    eso_prev_slaughter text,
    board_epoch bigint,
    outer_open_by_device text,
    outer_open_at bigint,
    parts_printed_as text,
    stamped_as text,
    eso_by_device text,
    not_chalak_outer boolean DEFAULT false NOT NULL,
    board_id bigint NOT NULL,
    slaughter_day date NOT NULL,
    CONSTRAINT animals_pilot_eso_ok CHECK (((eso_result IS NULL) OR (eso_result = ANY (ARRAY['ok'::text, 'nevela'::text])))),
    CONSTRAINT animals_pilot_eso_prev_ok CHECK (((eso_prev_slaughter IS NULL) OR (eso_prev_slaughter = ANY (ARRAY['slaughtered'::text, 'shot'::text, 'nevela'::text, 'notChalak'::text])))),
    CONSTRAINT animals_pilot_id_range CHECK (((id >= 0) AND (id <= 999))),
    CONSTRAINT animals_pilot_inner_ok CHECK (((inner_status IS NULL) OR (inner_status = ANY (ARRAY['in_progress'::text, 'confirmed'::text, 'treif'::text])))),
    CONSTRAINT animals_pilot_maw_ok CHECK (((maw IS NULL) OR (maw = ANY (ARRAY['kosher'::text, 'treif'::text])))),
    CONSTRAINT animals_pilot_outer_ok CHECK (((outer_status IS NULL) OR (outer_status = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text, 'rabChalak'::text])) OR (outer_status ~ '^custom_[A-Za-z0-9_-]{1,40}$'::text))),
    CONSTRAINT animals_pilot_parts_as_ok CHECK (((parts_printed_as IS NULL) OR (parts_printed_as = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text, 'rabChalak'::text, 'kosherRab'::text])) OR (parts_printed_as ~ '^custom_[A-Za-z0-9_-]{1,40}$'::text))),
    CONSTRAINT animals_pilot_print_count_ok CHECK (((parts_print_count IS NULL) OR (parts_print_count >= 0))),
    CONSTRAINT animals_pilot_rumen_ok CHECK (((rumen IS NULL) OR (rumen = ANY (ARRAY['kosher'::text, 'treif'::text])))),
    CONSTRAINT animals_pilot_slaughter_ok CHECK (((slaughter IS NULL) OR (slaughter = ANY (ARRAY['slaughtered'::text, 'shot'::text, 'nevela'::text, 'notChalak'::text])))),
    CONSTRAINT animals_pilot_stamped_as_ok CHECK (((stamped_as IS NULL) OR (stamped_as = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text, 'rabChalak'::text, 'kosherRab'::text])) OR (stamped_as ~ '^custom_[A-Za-z0-9_-]{1,40}$'::text))),
    CONSTRAINT animals_pilot_weights_ok CHECK ((((weight_right IS NULL) OR ((weight_right > (0)::numeric) AND (weight_right < (2000)::numeric))) AND ((weight_left IS NULL) OR ((weight_left > (0)::numeric) AND (weight_left < (2000)::numeric))) AND ((weight_stage2 IS NULL) OR ((weight_stage2 > (0)::numeric) AND (weight_stage2 < (2000)::numeric))) AND ((weight_stage3 IS NULL) OR ((weight_stage3 > (0)::numeric) AND (weight_stage3 < (2000)::numeric)))))
);


--
-- Name: animals_pilot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.animals_pilot (
    id integer NOT NULL,
    slaughter text,
    slaughtered_by text,
    slaughter_time bigint,
    legs_stickers boolean,
    head_stickers boolean,
    maw text,
    rumen text,
    inner_status text,
    inner_by text,
    inner_time bigint,
    outer_status text,
    outer_by text,
    outer_time bigint,
    parts_scanned boolean,
    tongue_sticker boolean,
    cheek_sticker boolean,
    weight_right numeric,
    weight_left numeric,
    device_id text,
    updated_at timestamp with time zone DEFAULT now(),
    slaughter_by_device text,
    inner_by_device text,
    outer_by_device text,
    weight_stage2 numeric,
    weight_stage3 numeric,
    stamped boolean,
    weight_right_skipped boolean DEFAULT false,
    weight_left_skipped boolean DEFAULT false,
    weight_stage2_skipped boolean DEFAULT false,
    weight_stage3_skipped boolean DEFAULT false,
    not_chalak_inner boolean DEFAULT false,
    eso_checked boolean DEFAULT false,
    eso_result text,
    legs_sorted boolean DEFAULT false,
    parts_print_count integer DEFAULT 0,
    eso_prev_slaughter text,
    board_epoch bigint,
    outer_open_by_device text,
    outer_open_at bigint,
    parts_printed_as text,
    stamped_as text,
    eso_by_device text,
    not_chalak_outer boolean DEFAULT false NOT NULL,
    CONSTRAINT animals_pilot_eso_ok CHECK (((eso_result IS NULL) OR (eso_result = ANY (ARRAY['ok'::text, 'nevela'::text])))),
    CONSTRAINT animals_pilot_eso_prev_ok CHECK (((eso_prev_slaughter IS NULL) OR (eso_prev_slaughter = ANY (ARRAY['slaughtered'::text, 'shot'::text, 'nevela'::text, 'notChalak'::text])))),
    CONSTRAINT animals_pilot_id_range CHECK (((id >= 0) AND (id <= 999))),
    CONSTRAINT animals_pilot_inner_ok CHECK (((inner_status IS NULL) OR (inner_status = ANY (ARRAY['in_progress'::text, 'confirmed'::text, 'treif'::text])))),
    CONSTRAINT animals_pilot_maw_ok CHECK (((maw IS NULL) OR (maw = ANY (ARRAY['kosher'::text, 'treif'::text])))),
    CONSTRAINT animals_pilot_outer_ok CHECK (((outer_status IS NULL) OR (outer_status = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text, 'rabChalak'::text])) OR (outer_status ~ '^custom_[A-Za-z0-9_-]{1,40}$'::text))),
    CONSTRAINT animals_pilot_parts_as_ok CHECK (((parts_printed_as IS NULL) OR (parts_printed_as = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text, 'rabChalak'::text, 'kosherRab'::text])) OR (parts_printed_as ~ '^custom_[A-Za-z0-9_-]{1,40}$'::text))),
    CONSTRAINT animals_pilot_print_count_ok CHECK (((parts_print_count IS NULL) OR (parts_print_count >= 0))),
    CONSTRAINT animals_pilot_rumen_ok CHECK (((rumen IS NULL) OR (rumen = ANY (ARRAY['kosher'::text, 'treif'::text])))),
    CONSTRAINT animals_pilot_slaughter_ok CHECK (((slaughter IS NULL) OR (slaughter = ANY (ARRAY['slaughtered'::text, 'shot'::text, 'nevela'::text, 'notChalak'::text])))),
    CONSTRAINT animals_pilot_stamped_as_ok CHECK (((stamped_as IS NULL) OR (stamped_as = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text, 'rabChalak'::text, 'kosherRab'::text])) OR (stamped_as ~ '^custom_[A-Za-z0-9_-]{1,40}$'::text))),
    CONSTRAINT animals_pilot_weights_ok CHECK ((((weight_right IS NULL) OR ((weight_right > (0)::numeric) AND (weight_right < (2000)::numeric))) AND ((weight_left IS NULL) OR ((weight_left > (0)::numeric) AND (weight_left < (2000)::numeric))) AND ((weight_stage2 IS NULL) OR ((weight_stage2 > (0)::numeric) AND (weight_stage2 < (2000)::numeric))) AND ((weight_stage3 IS NULL) OR ((weight_stage3 > (0)::numeric) AND (weight_stage3 < (2000)::numeric)))))
);

ALTER TABLE ONLY public.animals_pilot REPLICA IDENTITY FULL;


--
-- Name: _carry_row(public.animals_carry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._carry_row(c public.animals_carry) RETURNS public.animals_pilot
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select jsonb_populate_record(null::animals_pilot, to_jsonb(c));
$$;


--
-- Name: _cmd_get(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._cmd_get(p_cmd uuid, p_dev text, p_fn text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare c processed_commands%rowtype;
begin
  if p_cmd is null then return null; end if;
  perform pg_advisory_xact_lock(hashtext('gtcmd:' || p_cmd::text));   -- a parallel copy waits for the first
  select * into c from processed_commands where command_id = p_cmd;
  if c.command_id is null then return null; end if;
  if c.device_id is distinct from p_dev or c.fn is distinct from p_fn then
    return jsonb_build_object('ok', false, 'claimed', false, 'error', 'command_id_conflict');
  end if;
  return c.result || jsonb_build_object('replayed', true);
end $$;


--
-- Name: _cmd_put(uuid, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._cmd_put(p_cmd uuid, p_dev text, p_fn text, p_result jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if p_cmd is null or p_result is null then return; end if;
  if coalesce(p_result ->> 'error', '') in ('rate_limited', 'command_id_conflict', 'server_error') then return; end if;
  delete from processed_commands where at < now() - interval '3 days';
  insert into processed_commands (command_id, device_id, fn, result) values (p_cmd, coalesce(p_dev, '?'), p_fn, p_result)
    on conflict (command_id) do nothing;
end $$;


--
-- Name: _code_in_use(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._code_in_use(p_code text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select exists(select 1 from plant_managers where active and code_hash = crypt(p_code, code_hash));
$$;


--
-- Name: _correction_braked(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._correction_braked(p_dev text) RETURNS integer
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_n int; v_last timestamptz;
begin
  if p_dev is null or not _is_api_request() or _request_is_service_role() then return null; end if;
  select count(*), max(at) into v_n, v_last from rate_events
   where kind = 'correction_rejected' and key = p_dev and at > now() - interval '10 minutes';
  if v_n >= 10 then
    return greatest(1, ceil(extract(epoch from (v_last + interval '10 minutes' - now())))::int);
  end if;
  return null;
end $$;


--
-- Name: _correction_check(text, public.animals_pilot, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._correction_check(p_stage text, a public.animals_pilot, p_dev text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_by text; v_later boolean; v_cur integer;
begin
  if p_dev is null then return 'correction_not_allowed'; end if;
  case p_stage
    when 'slaughter' then
      v_by := a.slaughter_by_device;
      v_later := coalesce(a.eso_checked, false) or a.inner_status is not null or a.outer_status is not null;
    when 'eso' then
      v_by := a.eso_by_device;
      v_later := a.inner_status is not null;
    when 'inner' then
      v_by := a.inner_by_device;
      v_later := a.outer_status is not null;
    when 'outer' then
      v_by := a.outer_by_device;
      v_later := coalesce(a.parts_print_count, 0) > 0 or coalesce(a.stamped, false) or coalesce(a.legs_sorted, false)
                 or coalesce(a.parts_scanned, false) or coalesce(a.tongue_sticker, false) or coalesce(a.cheek_sticker, false);
    else
      return 'correction_not_allowed';
  end case;
  if v_by is distinct from p_dev then return 'correction_not_allowed'; end if;     -- only the device that made it
  if v_later then return 'correction_not_allowed'; end if;                          -- a later stage already acted
  select animal_id into v_cur from device_stage_cursor where device_id = p_dev and stage = p_stage;
  if v_cur is distinct from a.id then return 'moved_on'; end if;                    -- it ruled another animal since
  return null;
end $$;


--
-- Name: _credential_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._credential_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare d devices_pilot%rowtype;
begin
  if new.revoked and not coalesce(old.revoked, false) then
    select * into d from devices_pilot where id = new.device_id;
    perform _audit_device_event(new.device_id, 'KEY_REVOKED', d.assigned_role, d.assigned_index,
                                coalesce(nullif(current_setting('gt.audit_reason', true), ''), 'device key revoked'), null,
                                nullif(current_setting('gt.replacement_id', true), '')::uuid,
                                coalesce(nullif(current_setting('gt.audit_actor', true), ''),
                                         case when _is_api_request() then 'manager' else 'server' end));
  end if;
  return null;
end $$;


--
-- Name: _credential_revoked_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._credential_revoked_at() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if new.revoked and not coalesce(old.revoked, false) then new.revoked_at := now(); end if;
  if not new.revoked then new.revoked_at := null; end if;
  return new;
end $$;


--
-- Name: _current_device_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._current_device_id() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_tok text; v_id text;
begin
  v_tok := _request_headers() ->> 'x-device-token';
  if v_tok is null or v_tok = '' then return null; end if;
  select device_id into v_id from device_credentials
   where token_hash = encode(digest(v_tok, 'sha256'), 'hex') and not revoked;
  return v_id;
end $$;


--
-- Name: _current_worker(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._current_worker() RETURNS TABLE(name text, role text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_tok text; v_dev text; v_mt text;
begin
  v_tok := _request_headers() ->> 'x-worker-token';
  if v_tok is null or v_tok = '' then return; end if;
  v_dev := _current_device_id();
  if v_dev is not null then
    return query
      select s.name, s.role from worker_sessions s join devices_pilot d on d.id = s.device_id
       where s.token_hash = encode(digest(v_tok, 'sha256'), 'hex') and not s.revoked and s.expires_at > now()
         and s.device_id = v_dev and coalesce(d.device_status, 'active') <> 'retired' and d.assigned_role is not null
         and ((s.test_mode and _test_mode_on()) or _worker_role_norm(d.assigned_role) = s.role)
       limit 1;
    return;
  end if;
  v_mt := _request_headers() ->> 'x-manager-token';
  if v_mt is not null and v_mt <> '' and _request_has_manager() and _test_mode_on() then
    return query
      select s.name, s.role from worker_sessions s
       where s.token_hash = encode(digest(v_tok, 'sha256'), 'hex') and not s.revoked and s.expires_at > now()
         and s.device_id is null and s.mgr_session_hash = encode(digest(v_mt, 'sha256'), 'hex')
       limit 1;
  end if;
end $$;


--
-- Name: _derive_actor(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._derive_actor(p_stage text, p_client text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare
  w record; v_role text; v_mode text; v_def text; c text; s jsonb;
  defaults text[] := array['שוחט', 'בודק פנים', 'בודק חוץ', 'בודק', 'משגיח'];
begin
  if not _is_api_request() or _request_is_service_role() then return p_client; end if;   -- the server itself
  c := left(nullif(trim(regexp_replace(coalesce(p_client, ''), '\s*\(\?\)\s*$', '')), ''), 60);
  v_role := _stage_worker_role(p_stage);
  v_def := case p_stage when 'slaughter' then 'שוחט' when 'inner' then 'בודק פנים' when 'inner_start' then 'בודק פנים'
                        when 'outer' then 'בודק חוץ' else 'משגיח' end;
  select * into w from _current_worker() limit 1;
  if w.name is not null and w.role = v_role and (c is null or c = w.name or c = any(defaults)) then
    return w.name;
  end if;
  select settings into s from settings_pilot where id = 1;
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
end $_$;


--
-- Name: _device_auth_required(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._device_auth_required() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select true;
$$;


--
-- Name: _device_write_allowed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._device_write_allowed() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _device_write_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._device_write_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if _device_write_allowed() then return null; end if;
  if tg_table_name = 'events_pilot' and tg_op = 'INSERT' and _request_has_manufacturer() then
    return null;   -- each row is checked by _events_maker_guard below
  end if;
  raise exception 'GT:DEVICE_NOT_PAIRED המכשיר אינו מצומד לתחנה — יש לצמד אותו במסך ראש הצוות (device_not_paired)'
    using errcode = '42501';
end $$;


--
-- Name: _devices_assignment_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._devices_assignment_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not _is_api_request()
     or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'GT:ASSIGNMENT_LOCKED מחיקת מכשיר אפשרית רק ממסך המנהל (assignment_locked)' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    new.assigned_role := null; new.assigned_index := null; new.paired_at := null;
    new.device_status := 'active';
    return new;
  end if;
  if new.id             is distinct from old.id
  or new.assigned_role  is distinct from old.assigned_role
  or new.assigned_index is distinct from old.assigned_index
  or new.device_status  is distinct from old.device_status
  or new.paired_at      is distinct from old.paired_at then
    raise exception 'GT:ASSIGNMENT_LOCKED שיוך מכשיר לתחנה אפשרי רק דרך צימוד במסך המנהל (assignment_locked)'
      using errcode = '42501';
  end if;
  return new;
end $$;


--
-- Name: _do_board_reset(text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._do_board_reset(p_reason text, p_business_date date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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
    insert into animals_carry
    select a.*, v_board, v_day from animals_pilot a where a.slaughter is not null;
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
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
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


--
-- Name: _eso_required(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._eso_required(p_id integer) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare s jsonb := _gt_settings(); v_from int := 0;
begin
  if not _gt_flag(s, 'esophagusEnabled', false) then return false; end if;
  if jsonb_typeof(s -> 'esoFromIdx') = 'number' and (s ->> 'esoFromIdx')::numeric > 0
     and coalesce(s ->> 'esoFromReset', '') = coalesce(s ->> 'lastServerResetAt', '') then
    v_from := floor((s ->> 'esoFromIdx')::numeric)::int;
  end if;
  return p_id >= v_from;
end $$;


--
-- Name: _event_canonical(uuid, integer, text, text, jsonb, text, text, text, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._event_canonical(p_event_id uuid, p_animal_no integer, p_stage text, p_action text, p_payload jsonb, p_actor text, p_device_id text, p_occurred_at text, p_prev_hash text, p_chain_pos bigint) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select concat_ws('|', p_chain_pos::text, p_event_id::text, coalesce(p_animal_no::text, ''), p_stage, p_action,
                   coalesce(p_payload::text, ''), coalesce(p_actor, ''), coalesce(p_device_id, ''),
                   coalesce(p_occurred_at, ''), coalesce(p_prev_hash, ''));
$$;


--
-- Name: _event_chain_recent(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._event_chain_recent(p_limit integer DEFAULT 500) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _events_actor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._events_actor() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_dev text; v_role text; v_key text; v_tok text;
begin
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  v_dev := _acting_device();
  v_tok := _request_headers() ->> 'x-manager-token';
  new.device_id := coalesce(v_dev,
                            case when _request_has_manager() then 'team-leader'
                                 when _request_has_manufacturer() then 'manufacturer' end,
                            'unknown');
  v_role := _caller_device_role();
  v_key := case new.stage
             when 'slaughter' then 'slaughter' when 'esophagus' then 'eso' when 'eso' then 'eso'
             when 'inner' then 'inner' when 'outer' then 'outer'
             when 'legs' then 'legs' when 'parts' then 'parts' when 'stamps' then 'stamped' when 'weight' then 'stamped'
             else case v_role when 'slaughter' then 'slaughter' when 'esophagus' then 'eso' when 'inner' then 'inner'
                              when 'outer' then 'outer' when 'legs' then 'legs' when 'parts' then 'parts'
                              when 'stamps' then 'stamped' end
           end;
  if v_key is not null and (v_role is not null or v_dev is not null) then
    new.actor := _derive_actor(v_key, new.actor);                     -- a station (or test mode): its verified worker
  elsif v_tok is not null and v_tok <> '' and _session_name(v_tok) is not null then
    new.actor := _session_name(v_tok);                                -- team leader / owner / manufacturer
  else
    new.actor := null;
  end if;
  if jsonb_typeof(new.payload) = 'object' and new.payload ? 'actor' then
    new.payload := jsonb_set(new.payload, '{actor}', coalesce(to_jsonb(new.actor), 'null'::jsonb));
  end if;
  return new;
end $$;


--
-- Name: _events_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._events_append_only() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if current_setting('request.headers', true) is null then  -- SQL editor / maintenance
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  raise exception 'GT:APPEND_ONLY יומן האירועים הוא לקריאה ולהוספה בלבד (append_only)' using errcode = '42501';
end $$;


--
-- Name: _events_chain_link(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._events_chain_link() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare h events_chain_head%rowtype;
begin
  select * into h from events_chain_head where id = 1 for update;   -- one writer at a time
  if h.id is null then
    insert into events_chain_head (id, pos, hash) values (1, 0, null) on conflict do nothing;
    select * into h from events_chain_head where id = 1 for update;
  end if;
  new.server_chained := true;
  new.chain_pos := h.pos + 1;
  new.prev_hash := h.hash;
  new.event_hash := encode(digest(_event_canonical(new.event_id, new.animal_no, new.stage, new.action,
                              new.payload, new.actor, new.device_id, new.occurred_at,
                              new.prev_hash, new.chain_pos), 'sha256'), 'hex');
  update events_chain_head set pos = new.chain_pos, hash = new.event_hash where id = 1;
  return new;
end $$;


--
-- Name: _events_maker_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._events_maker_guard() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if _device_write_allowed() then return new; end if;
  if _request_has_manufacturer() then
    if not _support_access_open() then
      raise exception 'GT:MANUFACTURER_NO_ACCESS אין גישת יצרן פתוחה (manufacturer_no_access)' using errcode = '42501';
    end if;
    if new.animal_no is not null then
      raise exception 'GT:MANUFACTURER_NO_KASHRUT היצרן לא רושם אירועים על בהמות (manufacturer_no_kashrut)' using errcode = '42501';
    end if;
    return new;
  end if;
  return new;
end $$;


--
-- Name: _extend_maker_sessions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._extend_maker_sessions() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if new.key = 'supportAccessUntil' then
    update manager_sessions set expires_at = _maker_session_end()
     where manager_id in (select id from plant_managers where role = 'manufacturer')
       and expires_at > now();
  end if;
  return new;
end $$;


--
-- Name: _gt_flag(jsonb, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._gt_flag(s jsonb, p_key text, p_default boolean) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select case when jsonb_typeof(s -> p_key) = 'boolean' then (s ->> p_key)::boolean else p_default end;
$$;


--
-- Name: _gt_settings(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._gt_settings() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select coalesce((select settings from settings_pilot where id = 1), '{}'::jsonb);
$$;


--
-- Name: _gt_value_ok(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._gt_value_ok(p_kind text, v text) RETURNS boolean
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
    when 'device_role' then v in ('slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps', 'display')
    else false end;
$_$;


--
-- Name: _is_api_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._is_api_request() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select session_user = 'authenticator' or coalesce(current_setting('gt.as_api', true), '') = 'on';
$$;


--
-- Name: _is_app_caller(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._is_app_caller() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select _is_api_request() or coalesce(current_setting('role', true), '') in ('anon', 'authenticated');
$$;


--
-- Name: _is_nc(public.animals_pilot); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._is_nc(a public.animals_pilot) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select a.slaughter = 'notChalak' or coalesce(a.not_chalak_inner, false) or coalesce(a.not_chalak_outer, false);
$$;


--
-- Name: _is_real_manager(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._is_real_manager(p_token text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select coalesce(_session_role(p_token), '') = 'manager';
$$;


--
-- Name: _jint_ok(jsonb, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._jint_ok(v jsonb, lo numeric, hi numeric) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare n numeric;
begin
  if jsonb_typeof(v) = 'number' then n := (v #>> '{}')::numeric;
  elsif jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^-?\d{1,12}$' then n := (v #>> '{}')::numeric;
  else return false; end if;
  return n = trunc(n) and n between lo and hi;
end $_$;


--
-- Name: _jnum_ok(jsonb, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._jnum_ok(v jsonb, lo numeric, hi numeric) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare n numeric;
begin
  if jsonb_typeof(v) = 'number' then n := (v #>> '{}')::numeric;
  elsif jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^-?\d{1,12}(\.\d{1,6})?$' then n := (v #>> '{}')::numeric;
  else return false; end if;
  return n between lo and hi;
end $_$;


--
-- Name: _jstr_ok(jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._jstr_ok(v jsonb, maxlen integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and length(v #>> '{}') <= maxlen);
$$;


--
-- Name: _kosher_ready(public.animals_pilot); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._kosher_ready(a public.animals_pilot) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select coalesce(a.outer_status is not null
                  and (not _is_nc(a) or a.outer_status = 'kosher')
                  and a.outer_status = any(_kosher_statuses())
                  and coalesce(a.slaughter, '') not in ('nevela', 'shot')
                  and a.inner_status = 'confirmed', false);
$$;


--
-- Name: _kosher_statuses(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._kosher_statuses() RETURNS text[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select array['glatt', 'beit', 'kosher', 'mk', 'rabChalak']
         || coalesce((select array_agg(x ->> 'key') from jsonb_array_elements(
                        case when jsonb_typeof(_gt_settings() -> 'customStatuses') = 'array'
                             then _gt_settings() -> 'customStatuses' else '[]'::jsonb end) x
                       where jsonb_typeof(x) = 'object' and x -> 'kosher' = 'true'::jsonb
                         and coalesce(x ->> 'key', '') not in ('', 'treif')), '{}'::text[]);
$$;


--
-- Name: _log_correction_rejected(text, integer, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._log_correction_rejected(p_dev text, p_id integer, p_stage text, p_reason text, p_detail jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  perform _rate_hit('correction_rejected', coalesce(p_dev, 'unknown'));
  perform _security_event(case when p_id is null then null else p_id + 1 end, 'correction_rejected',
                          jsonb_build_object('stage', p_stage, 'reason', p_reason) || coalesce(p_detail, '{}'::jsonb),
                          null, coalesce(p_dev, 'unknown'));
end $$;


--
-- Name: _log_device_event(text, text, text, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  perform _audit_device_event(p_device, p_action, p_role, p_idx, p_reason, p_other,
                              nullif(current_setting('gt.replacement_id', true), '')::uuid,
                              coalesce(nullif(current_setting('gt.audit_actor', true), ''), 'manager'));
end $$;


--
-- Name: _maker_session_end(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._maker_session_end() RETURNS timestamp with time zone
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select case when _support_access_open()
              then least((select value::timestamptz from plant_state where key = 'supportAccessUntil'), now() + interval '24 hours')
              else now() + interval '10 minutes' end;
$$;


--
-- Name: _manager_session_valid(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._manager_session_valid(p_token text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_role text := coalesce(_session_role(p_token), '');
begin
  if v_role = 'manager' then return true; end if;
  if v_role = 'manufacturer' and _support_access_open() then return true; end if;
  return false;
end $$;


--
-- Name: _manager_sessions_cleanup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._manager_sessions_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  delete from manager_sessions where expires_at < now() - interval '1 day';
  return null;
end $$;


--
-- Name: _manufacturer_session_valid(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._manufacturer_session_valid(p_token text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select coalesce(_session_role(p_token), '') = 'manufacturer';
$$;


--
-- Name: _merge_list(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._merge_list(a jsonb, b jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
  -- union of two lists; items with the same "id" (or identical items) appear once, newest list order kept
  select coalesce(jsonb_agg(x order by ord), '[]'::jsonb) from (
    select distinct on (coalesce(x ->> 'id', x::text)) x, ord from (
      select x, 1000000 + o as ord from jsonb_array_elements(case when jsonb_typeof(b) = 'array' then b else '[]'::jsonb end) with ordinality t(x, o)
      union all
      select x, o from jsonb_array_elements(case when jsonb_typeof(a) = 'array' then a else '[]'::jsonb end) with ordinality t(x, o)
    ) u order by coalesce(x ->> 'id', x::text), ord desc
  ) d;
$$;


--
-- Name: _mgr_session_bound(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._mgr_session_bound(p_dev text, p_uid uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not _is_api_request() or _request_is_service_role() then return true; end if;
  if p_dev is distinct from _current_device_id() then return false; end if;       -- another (or no) paired device
  if p_uid is not null and p_uid is distinct from _auth_uid_safe() then return false; end if;   -- another app session
  return true;
end $$;


--
-- Name: _my_plant(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._my_plant() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
                            select plant_id from profiles where id = auth.uid()
                            $$;


--
-- Name: _my_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._my_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
                              select role from profiles where id = auth.uid()
                              $$;


--
-- Name: _nc_outer_allowed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._nc_outer_allowed() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _no_device_error(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._no_device_error() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if _request_has_manager() then return 'wrong_station'; end if;
  perform _note_revoked_write();
  return 'device_not_paired';
end $$;


--
-- Name: _note_revoked_write(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._note_revoked_write(p_dev text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _plant_state_test_mode_trg(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._plant_state_test_mode_trg() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _printed_as_key(public.animals_pilot); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._printed_as_key(a public.animals_pilot) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select case when a.outer_status is null then null
              when a.outer_status = 'kosher' and _is_nc(a) then 'kosherRab'
              else a.outer_status end;
$$;


--
-- Name: _proc_board_json(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_board_json(p_board bigint) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select case when p_board is null then null else jsonb_build_object(
    'id', p_board,
    'day', (select slaughter_day from animals_carry where board_id = p_board limit 1),
    'pending', (select coalesce(jsonb_object_agg(st, _proc_board_pending(st, p_board)), '{}'::jsonb)
                  from unnest(_proc_stations()) st)) end;            -- the stations this plant uses
$$;


--
-- Name: _proc_board_lock(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_board_lock(p_board bigint) RETURNS void
    LANGUAGE sql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select pg_advisory_xact_lock(hashtext('gt_proc_board:' || p_board::text));
$$;


--
-- Name: _proc_board_pending(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_board_pending(p_station text, p_board bigint) RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select count(*)::int from animals_carry c
   where c.board_id = p_board and _proc_pending(p_station, _carry_row(c), false)
     and not exists (select 1 from processing_day_closed z where z.board_id = p_board and z.station = p_station);
$$;


--
-- Name: _proc_caller_station(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_caller_station(p_station text) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _proc_finalize(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_finalize(p_board bigint DEFAULT NULL::bigint) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _proc_open_board(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_open_board(p_station text) RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select b.board_id from (select distinct board_id, slaughter_day from animals_carry) b
   where p_station = any(_proc_stations())
     and _proc_board_pending(p_station, b.board_id) > 0
   order by b.slaughter_day, b.board_id
   limit 1;
$$;


--
-- Name: _proc_pending(text, public.animals_pilot, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_pending(p_station text, a public.animals_pilot, p_today boolean DEFAULT false) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _proc_station_of_group(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_station_of_group(p_group text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select case p_group
           when 'legs' then 'legs'
           when 'parts' then 'parts'
           when 'weights' then 'stamps'
           when 'stamped' then case when _caller_device_role() = 'parts' then 'parts' else 'stamps' end
         end;
$$;


--
-- Name: _proc_stations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._proc_stations() RETURNS text[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select array_remove(array[
           case when _gt_flag(_gt_settings(), 'legsEnabled', true)   then 'legs' end,
           case when _gt_flag(_gt_settings(), 'partsEnabled', true)  then 'parts' end,
           case when _gt_flag(_gt_settings(), 'stampsEnabled', true) then 'stamps' end], null);
$$;


--
-- Name: _push_is_correction(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._push_is_correction(p_rows jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare r jsonb; a animals_pilot%rowtype;
begin
  for r in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(r) <> 'object' or coalesce(r ->> 'id', '') !~ '^\d{1,3}$' then continue; end if;
    select * into a from animals_pilot where id = (r ->> 'id')::int;
    if a.id is null then continue; end if;
    if (r ? 'slaughter' and a.slaughter is not null and (r ->> 'slaughter') is distinct from a.slaughter)
       or (r ? 'inner_status' and a.inner_status in ('confirmed', 'treif') and (r ->> 'inner_status') is distinct from a.inner_status)
       or (r ? 'outer_status' and a.outer_status is not null and (r ->> 'outer_status') is distinct from a.outer_status)
       or (r ? 'eso_result' and coalesce(a.eso_checked, false) and (r ->> 'eso_result') is distinct from a.eso_result) then
      return true;
    end if;
  end loop;
  return false;
end $_$;


--
-- Name: _raise_correction(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._raise_correction(p_err text, p_stage text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if p_err is null then return; end if;
  if p_err = 'moved_on' then
    raise exception 'GT:MOVED_ON correction-blocked: already moved on — % status is locked', p_stage using errcode = 'P0001';
  end if;
  raise exception 'GT:CORRECTION_NOT_ALLOWED correction-blocked: only the station that made this % ruling can change it, right away, before the next stage', p_stage
    using errcode = 'P0001';
end $$;


--
-- Name: _rate_count(text, text, interval); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._rate_count(p_kind text, p_key text, p_window interval) RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select count(*)::int from rate_events
   where kind = p_kind and (p_key is null or key = p_key) and at > now() - p_window;
$$;


--
-- Name: _rate_hit(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._rate_hit(p_kind text, p_key text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if random() < 0.05 then delete from rate_events where at < now() - interval '2 days'; end if;
  insert into rate_events (kind, key) values (p_kind, coalesce(p_key, '?'));
end $$;


--
-- Name: _reader_ok(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._reader_ok() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_uid uuid;
begin
  if not _is_api_request() then return true; end if;               -- plant server / SQL editor
  if _request_is_service_role() then return true; end if;
  if _current_device_id() is not null then return true; end if;    -- paired station (device key)
  if coalesce(_session_role(_request_headers() ->> 'x-manager-token'), '') <> '' then return true; end if;
  v_uid := _auth_uid_safe();
  if v_uid is null then return false; end if;
  return exists(select 1 from devices_pilot d join device_credentials c on c.device_id = d.id
                 where d.auth_uid = v_uid and not c.revoked
                   and d.assigned_role is not null and coalesce(d.device_status, 'active') <> 'retired')
      or exists(select 1 from manager_sessions s join plant_managers m on m.id = s.manager_id
                 where s.auth_uid = v_uid and s.expires_at > now() and m.active);
end $$;


--
-- Name: _reason_ok(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._reason_ok(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select nullif(trim(coalesce(p, '')), '') is not null;
$$;


--
-- Name: _request_has_manager(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._request_has_manager() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_tok text;
begin
  v_tok := _request_headers() ->> 'x-manager-token';
  if v_tok is null or v_tok = '' then return false; end if;
  return coalesce(_session_role(v_tok), '') = 'manager';
end $$;


--
-- Name: _request_has_manufacturer(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._request_has_manufacturer() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_tok text;
begin
  v_tok := _request_headers() ->> 'x-manager-token';
  if v_tok is null or v_tok = '' then return false; end if;
  return coalesce(_session_role(v_tok), '') = 'manufacturer';
end $$;


--
-- Name: _request_headers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._request_headers() RETURNS json
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare h text;
begin
  h := current_setting('request.headers', true);
  if h is null or h = '' then return null; end if;
  return h::json;
exception when others then return null;  -- unreadable = no key (callers fail closed)
end $$;


--
-- Name: _request_ip(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._request_ip() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare h json; v text;
begin
  h := _request_headers();
  if h is null then return 'local'; end if;
  -- cloud edge (Cloudflare replaces any value a client sends), then the plant's nginx
  v := coalesce(nullif(h ->> 'cf-connecting-ip', ''), nullif(h ->> 'x-gt-client-ip', ''));
  if v is null then return 'unknown'; end if;     -- X-Forwarded-For is NOT trusted: the client can write it
  return left(trim(v), 64);
end $$;


--
-- Name: _request_is_service_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._request_is_service_role() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  return coalesce(current_setting('request.jwt.claims', true)::json ->> 'role', '') = 'service_role';
exception when others then return false;
end $$;


--
-- Name: _request_privileged(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._request_privileged() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not _is_api_request() then return true; end if;
  if _request_is_service_role() then return true; end if;
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  return false;
end $$;


--
-- Name: _security_event(integer, text, jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._security_event(p_animal_no integer, p_action text, p_payload jsonb, p_actor text, p_device text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_prev text := coalesce(current_setting('app.device_admin', true), '');
begin
  perform set_config('app.device_admin', 'on', true);
  insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
  values (gen_random_uuid(), p_animal_no, 'security', p_action, coalesce(p_payload, '{}'::jsonb), p_actor,
          coalesce(p_device, 'server'), now()::text);
  perform set_config('app.device_admin', v_prev, true);
end $$;


--
-- Name: _session_name(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._session_name(p_token text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select m.name from manager_sessions s join plant_managers m on m.id = s.manager_id
   where p_token is not null and s.token = p_token and s.expires_at > now() and m.active
     and _mgr_session_bound(s.device_id, s.auth_uid)
   limit 1;
$$;


--
-- Name: _session_role(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._session_role(p_token text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select m.role from manager_sessions s join plant_managers m on m.id = s.manager_id
   where p_token is not null and s.token = p_token and s.expires_at > now() and m.active
     and _mgr_session_bound(s.device_id, s.auth_uid)
   limit 1;
$$;


--
-- Name: _set_setup_code(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._set_setup_code(p_code text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if p_code is null or length(p_code) < 8 then raise exception 'setup code too short'; end if;
  insert into plant_state (key, value) values ('setupCodeHash', crypt(upper(p_code), gen_salt('bf')))
    on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;


--
-- Name: _settings_hash_worker_codes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._settings_hash_worker_codes() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare u jsonb; out_users jsonb := '[]'::jsonb; changed boolean := false; c text;
begin
  if new.settings is null or jsonb_typeof(new.settings -> 'users') is distinct from 'array' then return new; end if;
  for u in select value from jsonb_array_elements(new.settings -> 'users') loop
    if jsonb_typeof(u) = 'object' and u ? 'code' then
      c := nullif(trim(u ->> 'code'), '');
      if c is not null then
        u := jsonb_set(u - 'code', '{codeHash}', to_jsonb(_worker_code_hash(c)));
      else
        u := u - 'code';
      end if;
      changed := true;
    end if;
    out_users := out_users || jsonb_build_array(u);
  end loop;
  if changed then new.settings := jsonb_set(new.settings, '{users}', out_users); end if;
  return new;
end $$;


--
-- Name: _settings_value_error(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._settings_value_error(p_key text, v jsonb) RETURNS text
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


--
-- Name: _stage_allowed(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._stage_allowed(p_stage text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _stage_order_error(text, public.animals_pilot, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._stage_order_error(p_stage text, a public.animals_pilot, p_today boolean DEFAULT true) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _stage_worker_role(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._stage_worker_role(p_stage text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select case p_stage when 'slaughter' then 'slaughter'
                      when 'inner' then 'inspector' when 'inner_start' then 'inspector' when 'outer' then 'inspector'
                      else 'supervisor' end;
$$;


--
-- Name: _status_change_error(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._status_change_error(p_old jsonb, p_new jsonb) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: _statuses_in_use(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._statuses_in_use() RETURNS text[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select coalesce(array_agg(distinct s), '{}'::text[]) from (
    select outer_status as s from animals_pilot where outer_status is not null
    union all select parts_printed_as from animals_pilot where parts_printed_as is not null
    union all select stamped_as from animals_pilot where stamped_as is not null
    union all select outer_status from animals_carry where outer_status is not null) x;
$$;


--
-- Name: _support_access_open(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._support_access_open() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select coalesce((select value::timestamptz > now() from plant_state where key = 'supportAccessUntil'), false);
$$;


--
-- Name: _test_mode_active(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_mode_active() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select _test_mode_flag() and coalesce(_test_mode_on_at() > now() - _test_mode_max(), false);
$$;


--
-- Name: _test_mode_autooff(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_mode_autooff() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if coalesce(current_setting('transaction_read_only', true), 'off') = 'on' then return; end if;
  if coalesce(current_setting('gt.tm_autooff', true), '') = 'done' then return; end if;
  perform set_config('gt.tm_autooff', 'done', true);
  perform set_config('gt.test_mode_why', 'auto_expired', true);
  update plant_state set value = 'off', updated_at = now() where key = 'testMode' and lower(trim(value)) = 'on';
  perform set_config('gt.test_mode_why', '', true);
end $$;


--
-- Name: _test_mode_flag(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_mode_flag() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select coalesce((select lower(trim(value)) from plant_state where key = 'testMode'), 'off') = 'on';
$$;


--
-- Name: _test_mode_max(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_mode_max() RETURNS interval
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$ select interval '8 hours' $$;


--
-- Name: _test_mode_on(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_mode_on() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not _test_mode_flag() then return false; end if;
  if _test_mode_active() then return true; end if;
  perform _test_mode_autooff();          -- on, but switched on more than 8 hours ago
  return false;
end $$;


--
-- Name: _test_mode_on_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._test_mode_on_at() RETURNS timestamp with time zone
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select _ts_or_null((select value from plant_state where key = 'testModeOnAt'));
$$;


--
-- Name: _ts_or_null(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._ts_or_null(p text) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}' then return null; end if;
  return p::timestamptz;
exception when others then return null;
end $$;


--
-- Name: _worker_code_hash(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._worker_code_hash(p_code text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select encode(extensions.digest('gt-worker:' || p_code, 'sha256'), 'hex');
$$;


--
-- Name: _worker_role_norm(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._worker_role_norm(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select case lower(trim(coalesce(p, '')))
    when 'slaughter'  then 'slaughter'  when 'שוחט'     then 'slaughter'  when 'שוחטים'   then 'slaughter'
    when 'inspector'  then 'inspector'  when 'בודק'     then 'inspector'  when 'בודקים'   then 'inspector'
    when 'inner'      then 'inspector'  when 'outer'    then 'inspector'
    when 'בודק פנים'  then 'inspector'  when 'בודק חוץ' then 'inspector'
    when 'supervisor' then 'supervisor' when 'משגיח'    then 'supervisor' when 'משגיחים' then 'supervisor'
    when 'esophagus'  then 'supervisor' when 'legs'     then 'supervisor'
    when 'parts'      then 'supervisor' when 'stamps'   then 'supervisor'
    else null end;
$$;


--
-- Name: _worker_sessions_revoke_on_credential(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._worker_sessions_revoke_on_credential() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if (new.revoked and not coalesce(old.revoked, false)) or new.token_hash is distinct from old.token_hash then
    update worker_sessions set revoked = true, revoked_at = now() where device_id = new.device_id and not revoked;
  end if;
  return null;
end $$;


--
-- Name: _worker_sessions_revoke_on_device(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._worker_sessions_revoke_on_device() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if tg_op = 'DELETE' then
    update worker_sessions set revoked = true, revoked_at = now() where device_id = old.id and not revoked;
    return null;
  end if;
  if new.assigned_role is distinct from old.assigned_role or new.assigned_index is distinct from old.assigned_index
     or new.device_status is distinct from old.device_status or new.paired_at is distinct from old.paired_at then
    update worker_sessions set revoked = true, revoked_at = now() where device_id = new.id and not revoked;
  end if;
  return null;
end $$;


--
-- Name: animal_push(jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.animal_push(p_rows jsonb, p_command_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
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
    'not_chalak_inner','parts_print_count','parts_printed_as'];
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
    if v_err in ('moved_on', 'correction_not_allowed', 'eso_locked') then
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


--
-- Name: animals_pilot_advance_cursor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.animals_pilot_advance_cursor() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_eso_change boolean;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  v_eso_change := tg_op = 'UPDATE'
                  and (new.eso_result is distinct from old.eso_result
                       or coalesce(new.eso_checked, false) is distinct from coalesce(old.eso_checked, false)
                       or new.eso_by_device is distinct from old.eso_by_device);
  -- slaughter (an esophagus "nevela" is an esophagus ruling, not a slaughter one)
  if new.slaughter is not null and new.slaughter_by_device is not null and not v_eso_change
     and (tg_op = 'INSERT'
          or (new.slaughter, new.slaughter_time, new.slaughter_by_device) is distinct from (old.slaughter, old.slaughter_time, old.slaughter_by_device)) then
    insert into device_stage_cursor (device_id, stage, animal_id, at) values (new.slaughter_by_device, 'slaughter', new.id, now())
      on conflict (device_id, stage) do update set animal_id = excluded.animal_id, at = excluded.at;
  end if;
  if new.inner_status is not null and new.inner_by_device is not null
     and (tg_op = 'INSERT'
          or (new.inner_status, new.inner_time, new.inner_by_device) is distinct from (old.inner_status, old.inner_time, old.inner_by_device)) then
    insert into device_stage_cursor (device_id, stage, animal_id, at) values (new.inner_by_device, 'inner', new.id, now())
      on conflict (device_id, stage) do update set animal_id = excluded.animal_id, at = excluded.at;
  end if;
  if new.outer_status is not null and new.outer_by_device is not null
     and (tg_op = 'INSERT'
          or (new.outer_status, new.outer_time, new.outer_by_device) is distinct from (old.outer_status, old.outer_time, old.outer_by_device)) then
    insert into device_stage_cursor (device_id, stage, animal_id, at) values (new.outer_by_device, 'outer', new.id, now())
      on conflict (device_id, stage) do update set animal_id = excluded.animal_id, at = excluded.at;
  end if;
  if coalesce(new.eso_checked, false) and new.eso_by_device is not null
     and (tg_op = 'INSERT' or v_eso_change) then
    insert into device_stage_cursor (device_id, stage, animal_id, at) values (new.eso_by_device, 'eso', new.id, now())
      on conflict (device_id, stage) do update set animal_id = excluded.animal_id, at = excluded.at;
  end if;
  return new;
end $$;


--
-- Name: animals_pilot_guard_corrections(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.animals_pilot_guard_corrections() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: archive_days(text, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_days(p_token text, p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: carry_claim(bigint, integer, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carry_claim(p_board bigint, p_id integer, p_stage text, p_command_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: carry_push(bigint, jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.carry_push(p_board bigint, p_rows jsonb, p_command_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
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
end $_$;


--
-- Name: claim_animal_stage(integer, text, text, text, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint DEFAULT NULL::bigint) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select claim_animal_stage(p_id, p_stage, p_value, p_actor, p_device_id, p_epoch, null::uuid);
$$;


--
-- Name: claim_animal_stage(integer, text, text, text, text, bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint, p_command_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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
     or (p_stage = 'outer' and (p_value is null or not _gt_value_ok('outer', p_value)))
     or (p_stage = 'eso' and coalesce(p_value, '') not in ('ok', 'nevela')) then
    return jsonb_build_object('claimed', false, 'error', 'bad_value');
  end if;
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

  -- a "not chalak" animal: only kosher (rabbinate) or treif
  if p_stage = 'outer' and a.outer_status is null and p_value not in ('kosher', 'treif')
     and (a.slaughter = 'notChalak' or coalesce(a.not_chalak_inner, false) or coalesce(a.not_chalak_outer, false)) then
    v_res := jsonb_build_object('claimed', false, 'error', 'bad_value', 'reason', 'nc_kosher_or_treif_only',
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


--
-- Name: create_first_manager(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_first_manager(p_name text, p_code text, p_setup_code text DEFAULT NULL::text) RETURNS jsonb
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
    if crypt(upper(regexp_replace(p_setup_code, '[^A-Za-z0-9]', '', 'g')), v_hash) <> v_hash then
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


--
-- Name: device_auth_set(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_auth_set(p_token text, p_on boolean) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_on is distinct from true then
    return jsonb_build_object('ok', false, 'error', 'locked',
      'message', 'Device protection can only be switched off on the server itself (SQL Editor), for maintenance.');
  end if;
  update system_flags set value = true where key = 'device_auth_required';
  return jsonb_build_object('ok', true, 'enforced', true);
end $$;


--
-- Name: device_heartbeat(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_heartbeat(p_device_id text, p_device_name text, p_info jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare v_info jsonb; v_dev text := _current_device_id(); v_mt text; v_uid uuid := _auth_uid_safe();
begin
  -- a team-leader session made before the app session existed is bound to it once (never re-bound)
  v_mt := _request_headers() ->> 'x-manager-token';
  if v_mt is not null and v_mt <> '' and v_uid is not null then
    update manager_sessions set auth_uid = v_uid
     where token = v_mt and expires_at > now() and auth_uid is null and device_id is not distinct from v_dev;
  end if;

  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then return jsonb_build_object('ok', false); end if;
  if v_dev is not null and v_dev <> p_device_id then return jsonb_build_object('ok', false, 'error', 'not_this_device'); end if;

  if v_dev is null then
    if not exists(select 1 from devices_pilot where id = p_device_id
                   and assigned_role is null and coalesce(device_status, 'active') <> 'retired') then
      return jsonb_build_object('ok', false, 'error', 'device_auth_required');
    end if;
    update devices_pilot set last_seen = now() where id = p_device_id;
    return jsonb_build_object('ok', true);
  end if;

  if jsonb_typeof(p_info) = 'object' then
    select jsonb_object_agg(key, to_jsonb(left(value #>> '{}', 40)))
      into v_info
      from jsonb_each(p_info)
     where key in ('v', 'screen', 'lang', 'local') and jsonb_typeof(value) in ('string', 'number', 'boolean');
  end if;
  update devices_pilot set last_seen = now(), app_info = coalesce(v_info, app_info),
         auth_uid = coalesce(v_uid, auth_uid)
   where id = p_device_id;
  return jsonb_build_object('ok', true);
end $_$;


--
-- Name: device_manage(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_manage(p_token text, p_device_id text, p_action text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: device_pair(text, text, text, integer, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer DEFAULT 0, p_replace boolean DEFAULT false, p_device_name text DEFAULT NULL::text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: device_paired_list(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_paired_list(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'devices',
    coalesce((select jsonb_agg(device_id) from device_credentials where not revoked), '[]'::jsonb),
    'enforced', true);
end $$;


--
-- Name: device_pairing_status(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_pairing_status(p_device_id text, p_code text, p_secret text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare r device_pairing%rowtype; d devices_pilot%rowtype;
begin
  select * into r from device_pairing
   where code = p_code and device_id = p_device_id
     and secret_hash = encode(digest(coalesce(p_secret, ''), 'sha256'), 'hex');
  if r.code is null then return jsonb_build_object('status', 'unknown'); end if;
  if r.paired_at is null then
    if r.expires_at < now() then return jsonb_build_object('status', 'expired'); end if;
    return jsonb_build_object('status', 'waiting', 'expires_at', r.expires_at);
  end if;
  if r.token_plain is null or r.paired_at < now() - interval '10 minutes' then
    return jsonb_build_object('status', 'collected');
  end if;
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set auth_uid = coalesce(_auth_uid_safe(), auth_uid) where id = p_device_id;
  perform set_config('app.device_admin', '', true);
  select * into d from devices_pilot where id = p_device_id;
  return jsonb_build_object('status', 'paired', 'token', r.token_plain,
                            'role', d.assigned_role, 'index', d.assigned_index,
                            'device_name', d.device_name);
end $$;


--
-- Name: device_request_pairing(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_request_pairing(p_device_id text, p_secret text, p_device_name text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare v_code text; v_exp timestamptz; i int := 0;
begin
  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then
    return jsonb_build_object('ok', false, 'error', 'bad device id');
  end if;
  if p_secret is null or length(p_secret) < 16 then
    return jsonb_build_object('ok', false, 'error', 'bad secret');
  end if;
  -- one request at a time, so the limits below can't be raced past
  perform pg_advisory_xact_lock(hashtext('glatttrack_pairing_request'));
  -- one address can ask for at most 20 codes in 10 minutes (a flood = abuse)
  delete from pairing_requests where at < now() - interval '1 hour';
  if (select count(*) from pairing_requests where ip = _request_ip() and at > now() - interval '10 minutes') >= 20 then
    return jsonb_build_object('ok', false, 'error', 'too_many_requests');
  end if;
  insert into pairing_requests (ip) values (_request_ip());
  -- housekeeping: unused codes that ran out, old history, keys nobody collected
  delete from device_pairing where paired_at is null and expires_at < now();
  delete from device_pairing where created_at < now() - interval '1 day';
  update device_pairing set token_plain = null
   where token_plain is not null and paired_at < now() - interval '10 minutes';
  -- this device's previous unused codes are replaced
  delete from device_pairing where device_id = p_device_id and paired_at is null;
  -- a plant has a handful of devices; a flood of open codes means abuse
  if (select count(*) from device_pairing where paired_at is null) >= 100 then
    return jsonb_build_object('ok', false, 'error', 'too_many_pending');
  end if;

  loop
    i := i + 1;
    v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
    begin
      insert into device_pairing (code, device_id, device_name, secret_hash)
      values (v_code, p_device_id, left(p_device_name, 60), encode(digest(p_secret, 'sha256'), 'hex'))
      returning expires_at into v_exp;
      exit;
    exception when unique_violation then
      if i > 50 then return jsonb_build_object('ok', false, 'error', 'could not allocate code'); end if;
    end;
  end loop;

  -- make sure the device shows up in the list
  perform set_config('app.device_admin', 'on', true);
  insert into devices_pilot (id, device_name, last_seen) values (p_device_id, left(p_device_name, 60), now())
    on conflict (id) do update set last_seen = now();
  perform set_config('app.device_admin', '', true);

  return jsonb_build_object('ok', true, 'code', v_code, 'expires_at', v_exp);
end $_$;


--
-- Name: device_unpair(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_unpair(p_token text, p_device_id text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: device_whoami(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.device_whoami() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_id text; d devices_pilot%rowtype; v_sent boolean;
begin
  v_sent := coalesce(_request_headers() ->> 'x-device-token', '') <> '';
  v_id := _current_device_id();
  if v_id is not null then select * into d from devices_pilot where id = v_id; end if;
  return jsonb_build_object('key_sent', v_sent, 'device_id', v_id,
                            'role', d.assigned_role, 'index', d.assigned_index,
                            'enforced', true);
end $$;


--
-- Name: eso_change(integer, text, text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint DEFAULT NULL::bigint) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select eso_change(p_id, p_result, p_device_id, p_epoch, null::uuid);
$$;


--
-- Name: eso_change(integer, text, text, bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid) RETURNS jsonb
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


--
-- Name: event_append(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.event_append(p_event jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
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
end $_$;


--
-- Name: lung_drawing_get(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lung_drawing_get(p_id integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare r record;
begin
  if not _reader_ok() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select drawing, extract(epoch from updated_at) * 1000 as t into r
    from lung_drawings where id = p_id and board_epoch is not distinct from _board_epoch();
  if not found then return jsonb_build_object('ok', true, 'drawing', null); end if;
  return jsonb_build_object('ok', true, 'drawing', r.drawing, 't', r.t::bigint);
end $$;


--
-- Name: lung_drawing_set(integer, bigint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text) RETURNS jsonb
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


--
-- Name: manager_add(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_add(p_token text, p_name text, p_code text) RETURNS jsonb
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


--
-- Name: manager_add_owner(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_add_owner(p_token text, p_name text, p_code text) RETURNS jsonb
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


--
-- Name: manager_deactivate(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_deactivate(p_token text, p_manager_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_role text;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select role into v_role from plant_managers where id = p_manager_id;
  if v_role is null or v_role = 'manufacturer' then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_role = 'manager' and (select count(*) from plant_managers where active and role = 'manager') <= 1 then
    return jsonb_build_object('ok', false, 'error', 'last_manager');
  end if;
  update plant_managers set active = false where id = p_manager_id;
  delete from manager_sessions where manager_id = p_manager_id;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: manager_list(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_list(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'accounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', role, 'active', active, 'created_at', created_at)
                     order by role, created_at)
    from plant_managers where active and role <> 'manufacturer'), '[]'::jsonb));
end $$;


--
-- Name: manager_login(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_login(p_code text) RETURNS jsonb
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
                            'repairAccess', _support_access_open());
end $$;


--
-- Name: manager_logout(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_logout(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  delete from manager_sessions where token = p_token;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: manager_session_check(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_session_check(p_token text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_role text; v_exp timestamptz;
begin
  select m.role, s.expires_at into v_role, v_exp
    from manager_sessions s join plant_managers m on m.id = s.manager_id
   where p_token is not null and s.token = p_token and s.expires_at > now() and m.active
     and _mgr_session_bound(s.device_id, s.auth_uid);
  return jsonb_build_object('ok', v_role is not null, 'role', v_role, 'expires_at', v_exp);
end $$;


--
-- Name: manufacturer_set_billing(text, boolean, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text, p_reason text DEFAULT NULL::text) RETURNS jsonb
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
end $_$;


--
-- Name: manufacturer_set_code(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manufacturer_set_code(p_name text, p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_id uuid;
begin
  if p_code is null or length(p_code) < 6 then
    raise exception 'manufacturer code must be at least 6 characters';
  end if;
  if exists(select 1 from plant_managers where active and role <> 'manufacturer'
                                        and code_hash = crypt(p_code, code_hash)) then
    raise exception 'this code is already used by a plant account — choose another';
  end if;
  delete from manager_sessions where manager_id in (select id from plant_managers where role = 'manufacturer');
  update plant_managers set active = false where role = 'manufacturer' and active;
  insert into plant_managers (name, code_hash, role)
  values (coalesce(nullif(trim(p_name), ''), 'Manufacturer'), crypt(p_code, gen_salt('bf')), 'manufacturer')
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;


--
-- Name: outer_open(integer, bigint, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select outer_open(p_id, p_epoch, p_open, p_device_id, null::uuid);
$$;


--
-- Name: outer_open(integer, bigint, boolean, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text, p_command_id uuid) RETURNS jsonb
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


--
-- Name: plant_status_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.plant_status_snapshot() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare s jsonb; tz text; v_cron text := 'not available'; v_intake int;
begin
  if _is_api_request() and not _request_is_service_role()
     and _current_device_id() is null
     and coalesce(_session_role(_request_headers() ->> 'x-manager-token'), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select settings into s from settings_pilot where id = 1;
  tz := coalesce(nullif(s ->> 'plantTimezone', ''), 'UTC');
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  if to_regclass('cron.job') is not null then
    execute $q$select case when exists(select 1 from cron.job where jobname = 'glatttrack-daily-rollover')
                          then 'scheduled' else 'not scheduled' end$q$ into v_cron;
  end if;
  select coalesce(sum((x->>'qty')::int), 0) into v_intake
    from jsonb_array_elements(coalesce(s -> 'dailyIntake', '[]'::jsonb)) x
   where (x->>'qty') ~ '^\d+$';
  return jsonb_build_object(
    'at', now(),
    'plantTime', to_char(now() at time zone tz, 'YYYY-MM-DD HH24:MI'),
    'plantDate', to_char(now() at time zone tz, 'YYYY-MM-DD'),
    'timezone', tz,
    'schemaStep', (select value from plant_state where key = 'schemaStep'),
    'lastRolloverDate', (select value from plant_state where key = 'lastRolloverDate'),
    'rolloverJob', v_cron,
    'eventChain', (select jsonb_build_object('ok', true, 'checked', pos) from events_chain_head where id = 1),
    'supportAccessUntil', (select value from plant_state where key = 'supportAccessUntil'),
    'target', case when v_intake > 0 then v_intake else nullif(s ->> 'dailyTarget', '')::numeric end,
    'counts', (select jsonb_build_object(
        'slaughtered', count(*) filter (where slaughter in ('slaughtered','notChalak')),
        'nevela',      count(*) filter (where slaughter in ('nevela','shot')),
        'innerTreif',  count(*) filter (where inner_status = 'treif'),
        'outerKosher', count(*) filter (where outer_status is not null and outer_status <> 'treif'),
        'outerTreif',  count(*) filter (where outer_status = 'treif'),
        'parts',       count(*) filter (where parts_scanned),
        'stamped',     count(*) filter (where stamped),
        'weightKg',    coalesce(sum(coalesce(weight_right,0) + coalesce(weight_left,0)), 0),
        'weighed',     count(*) filter (where weight_right is not null or weight_left is not null),
        'lastSlaughterAt', max(slaughter_time)) from animals_pilot),
    'devices', coalesce((select jsonb_agg(jsonb_build_object(
        'role', assigned_role, 'index', assigned_index,
        'online', last_seen > now() - interval '3 minutes', 'lastSeen', last_seen,
        'version', app_info ->> 'v', 'screen', app_info ->> 'screen') order by assigned_role nulls last)
      from devices_pilot where coalesce(device_status, 'active') <> 'retired' and assigned_role is not null), '[]'::jsonb),
    'billing', s -> 'billing',
    'problems', coalesce(jsonb_array_length(s -> 'problemReports'), 0)
  );
end $_$;


--
-- Name: processing_board(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.processing_board(p_station text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: processing_day_close(text, bigint, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.processing_day_close(p_token text, p_board bigint, p_station text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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
  perform _admin_audit(p_token, 'processing_day_close', p_station,
                       jsonb_build_object('board', p_board, 'pendingLeft', v_left, 'reason', left(trim(p_reason), 200)));
  perform _proc_finalize(p_board);
  return jsonb_build_object('ok', true, 'pendingLeft', v_left);
end $$;


--
-- Name: processing_status(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.processing_status(p_token text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: push_settings(jsonb, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_settings(p_settings jsonb, p_device_id text, p_token text DEFAULT NULL::text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: request_daily_rollover(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_daily_rollover() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: reset_daily_board(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_daily_board(p_token text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: security_summary(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.security_summary(p_token text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if coalesce(_session_role(p_token), '') not in ('manager', 'owner', 'manufacturer') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object(
    'ok', true,
    'failedLogins24h', (select count(*) from login_attempts where not ok and at > now() - interval '1 day'),
    'lockedAddresses', coalesce((select jsonb_agg(ip) from (select ip from login_attempts
                                  where not ok and at > now() - interval '15 minutes' group by ip having count(*) >= 8) x), '[]'::jsonb),
    'pairingRequestsLastHour', (select count(*) from pairing_requests where at > now() - interval '1 hour'),
    'pendingPairingCodes', (select count(*) from device_pairing where paired_at is null and expires_at > now()),
    'activeDeviceKeys', (select count(*) from device_credentials where not revoked),
    'revokedDeviceKeys', (select count(*) from device_credentials where revoked),
    'openSessions', (select jsonb_object_agg(role, n) from (select m.role, count(*) n from manager_sessions s
                       join plant_managers m on m.id = s.manager_id where s.expires_at > now() group by m.role) y),
    'rejectedCorrections24h', (select count(*) from rate_events where kind = 'correction_rejected' and at > now() - interval '1 day'),
    'manufacturerLogins24h', (select count(*) from rate_events where kind = 'maker_login' and at > now() - interval '1 day'),
    'deviceProtection', true,
    'testMode', _test_mode_on(),
    'schemaStep', (select value from plant_state where key = 'schemaStep')
  );
end $$;


--
-- Name: server_now_ms(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.server_now_ms() RETURNS bigint
    LANGUAGE sql STABLE
    AS $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;


--
-- Name: server_schema_step(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.server_schema_step() RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
  select nullif(value, '')::integer from plant_state where key = 'schemaStep' and value ~ '^\d+$';
$_$;


--
-- Name: server_test_mode(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.server_test_mode() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
  select _test_mode_active();
$$;


--
-- Name: server_test_mode_info(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.server_test_mode_info() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare v_on boolean := _test_mode_active(); v_at timestamptz := _test_mode_on_at();
begin
  return jsonb_build_object(
    'on', v_on,
    'on_at', case when v_on then v_at end,
    'expires_at', case when v_on then v_at + _test_mode_max() end,
    'remaining_s', case when v_on then greatest(0, floor(extract(epoch from (v_at + _test_mode_max() - now()))))::bigint end,
    'serverTime', now());
end $$;


--
-- Name: set_not_chalak_outer(integer, bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_not_chalak_outer(p_id integer, p_epoch bigint, p_command_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: support_access_set(text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.support_access_set(p_token text, p_hours integer, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: support_diagnostics(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.support_diagnostics(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $_$
declare
  s jsonb; tz text; v_cron text := 'not available'; v_chain jsonb; v_role text := coalesce(_session_role(p_token), '');
begin
  if not (_manager_session_valid(p_token) or v_role = 'manufacturer') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if v_role = 'manufacturer' then
    perform _admin_audit(p_token, 'diagnostics', 'plant', '{}'::jsonb);
  end if;
  select settings into s from settings_pilot where id = 1;
  tz := coalesce(nullif(s ->> 'plantTimezone', ''), 'UTC');
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  if to_regclass('cron.job') is not null then
    execute $q$select case when exists(select 1 from cron.job where jobname = 'glatttrack-daily-rollover')
                          then 'scheduled' else 'not scheduled' end$q$ into v_cron;
  end if;
  begin v_chain := verify_event_chain(); exception when others then v_chain := jsonb_build_object('ok', false, 'reason', sqlerrm); end;
  return jsonb_build_object(
    'ok', true,
    'serverTime', now(),
    'plantTimezone', tz,
    'plantTime', to_char(now() at time zone tz, 'YYYY-MM-DD HH24:MI'),
    'autoResetTime', coalesce(s ->> 'autoResetTime', '00:00'),
    'lastRolloverDate', (select value from plant_state where key = 'lastRolloverDate'),
    'lastServerResetAt', s ->> 'lastServerResetAt',
    'rolloverJob', v_cron,
    'animalsToday', (select count(*) from animals_pilot where slaughter is not null),
    'events', (select count(*) from events_pilot),
    'lastEventAt', (select max(created_at) from events_pilot),
    'eventChain', v_chain,
    'archiveDays', (select count(*) from daily_board_archive),
    'devices', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'name', device_name, 'role', assigned_role, 'index', assigned_index,
        'status', device_status, 'lastSeen', last_seen,
        'online', last_seen > now() - interval '3 minutes', 'info', app_info) order by assigned_role nulls last, device_name)
      from devices_pilot where coalesce(device_status, 'active') <> 'retired'), '[]'::jsonb),
    'sessions', (select jsonb_object_agg(role, n) from (
        select m.role, count(*) n from manager_sessions ss join plant_managers m on m.id = ss.manager_id
         where ss.expires_at > now() group by m.role) x),
    'flags', (select jsonb_object_agg(key, value) from system_flags),
    'testMode', _test_mode_on(),
    'dbSize', pg_size_pretty(pg_database_size(current_database())),
    'schemaStep', (select value from plant_state where key = 'schemaStep'),
    'lastForceReloadAt', s ->> 'forceReloadAt',
    'supportAccessUntil', (select value from plant_state where key = 'supportAccessUntil')
  );
end $_$;


--
-- Name: support_force_reload(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.support_force_reload(p_token text, p_reason text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: system_health(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.system_health(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare
  v_role text := coalesce(_session_role(p_token), '');
  v_tm boolean; v_on_at timestamptz; v_devs jsonb; v_chain jsonb; v_sec jsonb;
  v_ver timestamptz; v_fail timestamptz; v_plant boolean; v_backup text; v_age numeric;
  v_attn text[] := '{}'; v_info text[] := '{}';
  v_offline int; v_failed int; v_revoked int; v_brakes int; v_locks int;
  v_boards int; v_oldest date; v_wait timestamptz; v_mismatch int; v_order int;
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
    'processing', jsonb_build_object('openBoards', v_boards, 'oldestDay', v_oldest,
                                     'rolloverWaitingSince', v_wait, 'unfinishedOnBoard', _board_unfinished()),
    'attention', to_jsonb(v_attn),
    'info', to_jsonb(v_info));
end $$;


--
-- Name: verify_event_chain(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.verify_event_chain() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare r events_pilot%rowtype; v_prev text := null; n bigint := 0; v_legacy bigint;
begin
  -- only the plant's own accounts and the server may run the full check (it reads the whole log)
  if _is_api_request() and not _request_is_service_role()
     and coalesce(_session_role(_request_headers() ->> 'x-manager-token'), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select count(*) into v_legacy from events_pilot where not server_chained;
  for r in select * from events_pilot where server_chained order by chain_pos loop
    if r.chain_pos <> n + 1 then
      return jsonb_build_object('ok', false, 'checked', n, 'brokenAt', n + 1, 'reason', 'missing-event', 'legacy', v_legacy);
    end if;
    if r.prev_hash is distinct from v_prev then
      return jsonb_build_object('ok', false, 'checked', n, 'brokenAt', r.chain_pos, 'reason', 'prev-hash-mismatch', 'legacy', v_legacy);
    end if;
    if encode(digest(_event_canonical(r.event_id, r.animal_no, r.stage, r.action, r.payload, r.actor,
                                      r.device_id, r.occurred_at, r.prev_hash, r.chain_pos), 'sha256'), 'hex') <> r.event_hash then
      return jsonb_build_object('ok', false, 'checked', n, 'brokenAt', r.chain_pos, 'reason', 'hash-mismatch', 'legacy', v_legacy);
    end if;
    v_prev := r.event_hash;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'checked', n, 'legacy', v_legacy, 'head', v_prev);
end $$;


--
-- Name: worker_login(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.worker_login(p_role text, p_code text, p_name text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
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


--
-- Name: worker_logout(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.worker_logout(p_token text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
begin
  if p_token is not null and p_token <> '' then
    update worker_sessions set revoked = true, revoked_at = now()
     where token_hash = encode(digest(p_token, 'sha256'), 'hex') and not revoked;
  end if;
  return jsonb_build_object('ok', true);
end $$;


--
-- Name: worker_session_check(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.worker_session_check() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions', 'pg_temp'
    AS $$
declare w record; v_exp timestamptz;
begin
  select * into w from _current_worker() limit 1;
  if w.name is null then return jsonb_build_object('ok', false, 'error', 'session_invalid'); end if;
  select expires_at into v_exp from worker_sessions
   where token_hash = encode(digest(_request_headers() ->> 'x-worker-token', 'sha256'), 'hex');
  return jsonb_build_object('ok', true, 'name', w.name, 'role', w.role, 'expires_at', v_exp);
end $$;


--
-- Name: admin_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_audit (
    id bigint NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL,
    who text,
    role text,
    action text NOT NULL,
    target text,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: admin_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_audit_id_seq OWNED BY public.admin_audit.id;


--
-- Name: animals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.animals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plant_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    seq_number integer NOT NULL,
    farm_id uuid,
    slaughter text,
    slaughtered_by uuid,
    slaughter_time timestamp with time zone,
    legs_stickers boolean DEFAULT false NOT NULL,
    head_stickers boolean DEFAULT false NOT NULL,
    maw text,
    rumen text,
    lung_drawing_url text,
    inner_status text,
    inner_by uuid,
    inner_time timestamp with time zone,
    outer_status text,
    outer_by uuid,
    outer_time timestamp with time zone,
    parts_scanned boolean DEFAULT false NOT NULL,
    tongue_sticker boolean DEFAULT false NOT NULL,
    cheek_sticker boolean DEFAULT false NOT NULL,
    weight_right numeric(6,2),
    weight_left numeric(6,2),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT animals_inner_status_check CHECK ((inner_status = ANY (ARRAY['in_progress'::text, 'treif'::text, 'confirmed'::text]))),
    CONSTRAINT animals_maw_check CHECK ((maw = ANY (ARRAY['kosher'::text, 'treif'::text]))),
    CONSTRAINT animals_outer_status_check CHECK ((outer_status = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text]))),
    CONSTRAINT animals_rumen_check CHECK ((rumen = ANY (ARRAY['kosher'::text, 'treif'::text]))),
    CONSTRAINT animals_slaughter_check CHECK ((slaughter = ANY (ARRAY['slaughtered'::text, 'nevela'::text, 'shot'::text])))
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    plant_id uuid NOT NULL,
    batch_id uuid,
    animal_id uuid,
    event_type text NOT NULL,
    from_value text,
    to_value text,
    user_id uuid,
    user_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plant_id uuid NOT NULL,
    business_date date DEFAULT CURRENT_DATE NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    animal_type text,
    opened_at timestamp with time zone DEFAULT now() NOT NULL,
    opened_by uuid,
    closed_at timestamp with time zone,
    closed_by uuid,
    CONSTRAINT batches_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])))
);


--
-- Name: custom_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_statuses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plant_id uuid NOT NULL,
    key text NOT NULL,
    label_he text NOT NULL,
    label_en text,
    label_es text,
    color text,
    sort_order integer DEFAULT 0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL
);


--
-- Name: daily_board_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_board_archive (
    id bigint NOT NULL,
    business_date date,
    reason text NOT NULL,
    archived_at timestamp with time zone DEFAULT now() NOT NULL,
    animals_count integer,
    board jsonb NOT NULL,
    intake jsonb,
    statuses jsonb
);


--
-- Name: daily_board_archive_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.daily_board_archive ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.daily_board_archive_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: device_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_credentials (
    device_id text NOT NULL,
    token_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    revoked_at timestamp with time zone
);


--
-- Name: device_lifecycle_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_lifecycle_events (
    event_id uuid DEFAULT gen_random_uuid() NOT NULL,
    device_id text NOT NULL,
    action text NOT NULL,
    station_id text,
    station_slot integer,
    actor text,
    reason text,
    replacement_device_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    replacement_id uuid
);

ALTER TABLE ONLY public.device_lifecycle_events REPLICA IDENTITY FULL;


--
-- Name: device_pairing; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_pairing (
    code text NOT NULL,
    device_id text NOT NULL,
    device_name text,
    secret_hash text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:15:00'::interval) NOT NULL,
    paired_at timestamp with time zone,
    token_plain text
);


--
-- Name: device_stage_cursor; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_stage_cursor (
    device_id text NOT NULL,
    stage text NOT NULL,
    animal_id integer NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: devices_pilot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices_pilot (
    id text NOT NULL,
    device_name text,
    assigned_role text,
    assigned_index integer,
    last_seen timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now(),
    device_status text DEFAULT 'active'::text NOT NULL,
    retired_at timestamp with time zone,
    retired_by text,
    retired_reason text,
    cursor_slaughter integer,
    cursor_inner integer,
    cursor_outer integer,
    paired_at timestamp with time zone,
    app_info jsonb,
    auth_uid uuid,
    cursor_eso integer,
    CONSTRAINT devices_pilot_device_status_check CHECK ((device_status = ANY (ARRAY['active'::text, 'retired'::text]))),
    CONSTRAINT devices_pilot_role_ok CHECK (((assigned_role IS NULL) OR (assigned_role = ANY (ARRAY['slaughter'::text, 'esophagus'::text, 'legs'::text, 'inner'::text, 'outer'::text, 'parts'::text, 'stamps'::text, 'display'::text]))))
);

ALTER TABLE ONLY public.devices_pilot REPLICA IDENTITY FULL;


--
-- Name: events_chain_head; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events_chain_head (
    id integer DEFAULT 1 NOT NULL,
    pos bigint DEFAULT 0 NOT NULL,
    hash text,
    CONSTRAINT events_chain_head_id_check CHECK ((id = 1))
);


--
-- Name: events_pilot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events_pilot (
    event_id uuid NOT NULL,
    animal_no integer,
    stage text NOT NULL,
    action text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    actor text,
    device_id text,
    occurred_at text NOT NULL,
    prev_hash text,
    event_hash text NOT NULL,
    server_seq bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    server_chained boolean DEFAULT false NOT NULL,
    chain_pos bigint
);

ALTER TABLE ONLY public.events_pilot REPLICA IDENTITY FULL;


--
-- Name: events_pilot_server_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.events_pilot ALTER COLUMN server_seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.events_pilot_server_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: login_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_attempts (
    id bigint NOT NULL,
    ip text NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL,
    ok boolean NOT NULL
);


--
-- Name: login_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.login_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: login_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.login_attempts_id_seq OWNED BY public.login_attempts.id;


--
-- Name: lung_drawings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lung_drawings (
    id integer NOT NULL,
    board_epoch bigint,
    drawing text NOT NULL,
    device_id text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lung_drawings_id_check CHECK (((id >= 0) AND (id <= 999)))
);


--
-- Name: manager_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.manager_sessions (
    token text DEFAULT encode(extensions.gen_random_bytes(24), 'hex'::text) NOT NULL,
    manager_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '10:00:00'::interval) NOT NULL,
    auth_uid uuid,
    device_id text
);


--
-- Name: outer_status_pilot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outer_status_pilot (
    id integer NOT NULL,
    outer_status text,
    outer_by text,
    outer_time bigint,
    device_id text,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.outer_status_pilot REPLICA IDENTITY FULL;


--
-- Name: pairing_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pairing_requests (
    ip text NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: plant_managers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plant_managers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    code_hash text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    role text DEFAULT 'manager'::text NOT NULL,
    CONSTRAINT plant_managers_role_check CHECK ((role = ANY (ARRAY['manager'::text, 'owner'::text, 'manufacturer'::text])))
);


--
-- Name: plant_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plant_state (
    key text NOT NULL,
    value text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: plants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    license_status text DEFAULT 'trial'::text NOT NULL,
    license_expiry date,
    daily_target integer DEFAULT 500,
    animal_type text DEFAULT 'cattle'::text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plants_animal_type_check CHECK ((animal_type = ANY (ARRAY['cattle'::text, 'sheep'::text, 'mixed'::text]))),
    CONSTRAINT plants_license_status_check CHECK ((license_status = ANY (ARRAY['trial'::text, 'active'::text, 'expired'::text, 'suspended'::text])))
);


--
-- Name: problem_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.problem_reports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plant_id uuid NOT NULL,
    batch_id uuid,
    animal_seq integer,
    description text NOT NULL,
    reported_by uuid,
    resolved boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: processed_commands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_commands (
    command_id uuid NOT NULL,
    device_id text NOT NULL,
    fn text NOT NULL,
    result jsonb NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: processing_day_closed; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processing_day_closed (
    board_id bigint NOT NULL,
    station text NOT NULL,
    closed_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_by text,
    reason text,
    pending_left integer,
    CONSTRAINT processing_day_closed_station_check CHECK ((station = ANY (ARRAY['legs'::text, 'parts'::text, 'stamps'::text])))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    plant_id uuid NOT NULL,
    name text NOT NULL,
    role text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['slaughter'::text, 'inspector'::text, 'supervisor'::text, 'manager'::text])))
);


--
-- Name: rate_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_events (
    id bigint NOT NULL,
    kind text NOT NULL,
    key text NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: rate_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rate_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rate_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rate_events_id_seq OWNED BY public.rate_events.id;


--
-- Name: reprint_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reprint_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plant_id uuid NOT NULL,
    batch_id uuid,
    animal_seq integer NOT NULL,
    station text NOT NULL,
    user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: revoked_device_writes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.revoked_device_writes (
    device_id text NOT NULL,
    minute timestamp with time zone NOT NULL,
    n integer DEFAULT 1 NOT NULL
);


--
-- Name: settings_pilot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings_pilot (
    id integer NOT NULL,
    settings jsonb,
    device_id text,
    updated_at timestamp with time zone DEFAULT now()
);

ALTER TABLE ONLY public.settings_pilot REPLICA IDENTITY FULL;


--
-- Name: source_farms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_farms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plant_id uuid NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: system_flags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_flags (
    key text NOT NULL,
    value boolean DEFAULT false NOT NULL
);


--
-- Name: worker_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.worker_sessions (
    token_hash text NOT NULL,
    device_id text,
    mgr_session_hash text,
    test_mode boolean DEFAULT false NOT NULL,
    name text NOT NULL,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '14:00:00'::interval) NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT worker_sessions_role_check CHECK ((role = ANY (ARRAY['slaughter'::text, 'inspector'::text, 'supervisor'::text])))
);


--
-- Name: admin_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_audit ALTER COLUMN id SET DEFAULT nextval('public.admin_audit_id_seq'::regclass);


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: login_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_attempts ALTER COLUMN id SET DEFAULT nextval('public.login_attempts_id_seq'::regclass);


--
-- Name: rate_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_events ALTER COLUMN id SET DEFAULT nextval('public.rate_events_id_seq'::regclass);


--
-- Name: admin_audit admin_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_audit
    ADD CONSTRAINT admin_audit_pkey PRIMARY KEY (id);


--
-- Name: animals animals_batch_id_seq_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_batch_id_seq_number_key UNIQUE (batch_id, seq_number);


--
-- Name: animals_carry animals_carry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals_carry
    ADD CONSTRAINT animals_carry_pkey PRIMARY KEY (board_id, id);


--
-- Name: animals_pilot animals_pilot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals_pilot
    ADD CONSTRAINT animals_pilot_pkey PRIMARY KEY (id);


--
-- Name: animals animals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: batches batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batches
    ADD CONSTRAINT batches_pkey PRIMARY KEY (id);


--
-- Name: custom_statuses custom_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_statuses
    ADD CONSTRAINT custom_statuses_pkey PRIMARY KEY (id);


--
-- Name: custom_statuses custom_statuses_plant_id_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_statuses
    ADD CONSTRAINT custom_statuses_plant_id_key_key UNIQUE (plant_id, key);


--
-- Name: daily_board_archive daily_board_archive_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_board_archive
    ADD CONSTRAINT daily_board_archive_pkey PRIMARY KEY (id);


--
-- Name: device_credentials device_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_credentials
    ADD CONSTRAINT device_credentials_pkey PRIMARY KEY (device_id);


--
-- Name: device_credentials device_credentials_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_credentials
    ADD CONSTRAINT device_credentials_token_hash_key UNIQUE (token_hash);


--
-- Name: device_lifecycle_events device_lifecycle_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_lifecycle_events
    ADD CONSTRAINT device_lifecycle_events_pkey PRIMARY KEY (event_id);


--
-- Name: device_pairing device_pairing_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_pairing
    ADD CONSTRAINT device_pairing_pkey PRIMARY KEY (code);


--
-- Name: device_stage_cursor device_stage_cursor_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_stage_cursor
    ADD CONSTRAINT device_stage_cursor_pkey PRIMARY KEY (device_id, stage);


--
-- Name: devices_pilot devices_pilot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices_pilot
    ADD CONSTRAINT devices_pilot_pkey PRIMARY KEY (id);


--
-- Name: devices_pilot devices_pilot_safe_id; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.devices_pilot
    ADD CONSTRAINT devices_pilot_safe_id CHECK ((id ~ '^[A-Za-z0-9_-]{6,64}$'::text)) NOT VALID;


--
-- Name: events_chain_head events_chain_head_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events_chain_head
    ADD CONSTRAINT events_chain_head_pkey PRIMARY KEY (id);


--
-- Name: events_pilot events_pilot_event_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events_pilot
    ADD CONSTRAINT events_pilot_event_hash_key UNIQUE (event_hash);


--
-- Name: events_pilot events_pilot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events_pilot
    ADD CONSTRAINT events_pilot_pkey PRIMARY KEY (event_id);


--
-- Name: events_pilot events_pilot_server_seq_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events_pilot
    ADD CONSTRAINT events_pilot_server_seq_key UNIQUE (server_seq);


--
-- Name: login_attempts login_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_attempts
    ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (id);


--
-- Name: lung_drawings lung_drawings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lung_drawings
    ADD CONSTRAINT lung_drawings_pkey PRIMARY KEY (id);


--
-- Name: manager_sessions manager_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manager_sessions
    ADD CONSTRAINT manager_sessions_pkey PRIMARY KEY (token);


--
-- Name: outer_status_pilot outer_status_pilot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outer_status_pilot
    ADD CONSTRAINT outer_status_pilot_pkey PRIMARY KEY (id);


--
-- Name: plant_managers plant_managers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plant_managers
    ADD CONSTRAINT plant_managers_pkey PRIMARY KEY (id);


--
-- Name: plant_state plant_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plant_state
    ADD CONSTRAINT plant_state_pkey PRIMARY KEY (key);


--
-- Name: plants plants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plants
    ADD CONSTRAINT plants_pkey PRIMARY KEY (id);


--
-- Name: problem_reports problem_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problem_reports
    ADD CONSTRAINT problem_reports_pkey PRIMARY KEY (id);


--
-- Name: processed_commands processed_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_commands
    ADD CONSTRAINT processed_commands_pkey PRIMARY KEY (command_id);


--
-- Name: processing_day_closed processing_day_closed_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processing_day_closed
    ADD CONSTRAINT processing_day_closed_pkey PRIMARY KEY (board_id, station);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: rate_events rate_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rate_events
    ADD CONSTRAINT rate_events_pkey PRIMARY KEY (id);


--
-- Name: reprint_log reprint_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reprint_log
    ADD CONSTRAINT reprint_log_pkey PRIMARY KEY (id);


--
-- Name: revoked_device_writes revoked_device_writes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revoked_device_writes
    ADD CONSTRAINT revoked_device_writes_pkey PRIMARY KEY (device_id, minute);


--
-- Name: settings_pilot settings_pilot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings_pilot
    ADD CONSTRAINT settings_pilot_pkey PRIMARY KEY (id);


--
-- Name: source_farms source_farms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_farms
    ADD CONSTRAINT source_farms_pkey PRIMARY KEY (id);


--
-- Name: system_flags system_flags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_flags
    ADD CONSTRAINT system_flags_pkey PRIMARY KEY (key);


--
-- Name: worker_sessions worker_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.worker_sessions
    ADD CONSTRAINT worker_sessions_pkey PRIMARY KEY (token_hash);


--
-- Name: admin_audit_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX admin_audit_at ON public.admin_audit USING btree (at DESC);


--
-- Name: animals_batch_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX animals_batch_id_idx ON public.animals USING btree (batch_id);


--
-- Name: animals_carry_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX animals_carry_day_idx ON public.animals_carry USING btree (slaughter_day, board_id);


--
-- Name: animals_plant_id_batch_id_seq_number_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX animals_plant_id_batch_id_seq_number_idx ON public.animals USING btree (plant_id, batch_id, seq_number);


--
-- Name: audit_log_plant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_plant_id_created_at_idx ON public.audit_log USING btree (plant_id, created_at DESC);


--
-- Name: batches_plant_id_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX batches_plant_id_status_idx ON public.batches USING btree (plant_id, status);


--
-- Name: device_credentials_hash_live; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX device_credentials_hash_live ON public.device_credentials USING btree (token_hash) WHERE (NOT revoked);


--
-- Name: devices_pilot_auth_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX devices_pilot_auth_uid ON public.devices_pilot USING btree (auth_uid);


--
-- Name: devices_pilot_one_per_slot; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX devices_pilot_one_per_slot ON public.devices_pilot USING btree (assigned_role, assigned_index) WHERE ((assigned_role IS NOT NULL) AND (device_status = 'active'::text));


--
-- Name: events_pilot_chain_head_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX events_pilot_chain_head_idx ON public.events_pilot USING btree (chain_pos DESC) WHERE server_chained;


--
-- Name: events_pilot_chain_pos_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX events_pilot_chain_pos_key ON public.events_pilot USING btree (chain_pos) WHERE (chain_pos IS NOT NULL);


--
-- Name: events_pilot_event_id_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX events_pilot_event_id_uq ON public.events_pilot USING btree (event_id);


--
-- Name: idx_device_lifecycle_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_device_lifecycle_device ON public.device_lifecycle_events USING btree (device_id, created_at DESC);


--
-- Name: login_attempts_ip_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX login_attempts_ip_at ON public.login_attempts USING btree (ip, at DESC);


--
-- Name: manager_sessions_auth_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX manager_sessions_auth_uid ON public.manager_sessions USING btree (auth_uid);


--
-- Name: pairing_requests_ip_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pairing_requests_ip_at ON public.pairing_requests USING btree (ip, at DESC);


--
-- Name: processed_commands_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX processed_commands_at ON public.processed_commands USING btree (at);


--
-- Name: rate_events_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rate_events_at ON public.rate_events USING btree (at);


--
-- Name: rate_events_kind_key_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rate_events_kind_key_at ON public.rate_events USING btree (kind, key, at DESC);


--
-- Name: worker_sessions_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX worker_sessions_device ON public.worker_sessions USING btree (device_id) WHERE (NOT revoked);


--
-- Name: events_pilot a0_events_maker_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER a0_events_maker_guard BEFORE INSERT ON public.events_pilot FOR EACH ROW EXECUTE FUNCTION public._events_maker_guard();


--
-- Name: events_pilot a1_events_actor; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER a1_events_actor BEFORE INSERT ON public.events_pilot FOR EACH ROW EXECUTE FUNCTION public._events_actor();


--
-- Name: animals_pilot a_animals_merge; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER a_animals_merge BEFORE UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public._animals_merge();


--
-- Name: animals_pilot a_animals_merge_ins; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER a_animals_merge_ins BEFORE INSERT ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public._animals_merge();


--
-- Name: daily_board_archive a_archive_keep_intake; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER a_archive_keep_intake BEFORE INSERT ON public.daily_board_archive FOR EACH ROW EXECUTE FUNCTION public._archive_keep_intake();


--
-- Name: events_pilot aa_events_chain_link; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER aa_events_chain_link BEFORE INSERT ON public.events_pilot FOR EACH ROW EXECUTE FUNCTION public._events_chain_link();


--
-- Name: events_pilot ab_events_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ab_events_append_only BEFORE DELETE OR UPDATE ON public.events_pilot FOR EACH ROW EXECUTE FUNCTION public._events_append_only();


--
-- Name: animals_pilot b_animals_stage_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER b_animals_stage_guard BEFORE UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public._animals_stage_guard();


--
-- Name: device_credentials credential_revoked_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER credential_revoked_at BEFORE UPDATE ON public.device_credentials FOR EACH ROW EXECUTE FUNCTION public._credential_revoked_at();


--
-- Name: plant_state extend_maker_sessions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER extend_maker_sessions AFTER INSERT OR UPDATE ON public.plant_state FOR EACH ROW EXECUTE FUNCTION public._extend_maker_sessions();


--
-- Name: animals_pilot trg_animals_pilot_advance_cursor; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_animals_pilot_advance_cursor AFTER INSERT OR UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public.animals_pilot_advance_cursor();


--
-- Name: animals_pilot trg_animals_pilot_guard_corrections; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_animals_pilot_guard_corrections BEFORE UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public.animals_pilot_guard_corrections();


--
-- Name: device_credentials zz_credential_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_credential_audit AFTER UPDATE ON public.device_credentials FOR EACH ROW EXECUTE FUNCTION public._credential_audit();


--
-- Name: animals_pilot zz_device_write_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_device_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.animals_pilot FOR EACH STATEMENT EXECUTE FUNCTION public._device_write_guard();


--
-- Name: events_pilot zz_device_write_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_device_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.events_pilot FOR EACH STATEMENT EXECUTE FUNCTION public._device_write_guard();


--
-- Name: devices_pilot zz_devices_assignment_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_devices_assignment_guard BEFORE INSERT OR DELETE OR UPDATE ON public.devices_pilot FOR EACH ROW EXECUTE FUNCTION public._devices_assignment_guard();


--
-- Name: manager_sessions zz_manager_sessions_cleanup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_manager_sessions_cleanup AFTER INSERT ON public.manager_sessions FOR EACH STATEMENT EXECUTE FUNCTION public._manager_sessions_cleanup();


--
-- Name: settings_pilot zz_settings_hash_worker_codes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_settings_hash_worker_codes BEFORE INSERT OR UPDATE ON public.settings_pilot FOR EACH ROW EXECUTE FUNCTION public._settings_hash_worker_codes();


--
-- Name: plant_state zz_test_mode_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_test_mode_audit AFTER INSERT OR UPDATE ON public.plant_state FOR EACH ROW WHEN ((new.key = 'testMode'::text)) EXECUTE FUNCTION public._plant_state_test_mode_trg();


--
-- Name: device_credentials zz_worker_sessions_revoke; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_worker_sessions_revoke AFTER UPDATE ON public.device_credentials FOR EACH ROW EXECUTE FUNCTION public._worker_sessions_revoke_on_credential();


--
-- Name: devices_pilot zz_worker_sessions_revoke; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zz_worker_sessions_revoke AFTER DELETE OR UPDATE ON public.devices_pilot FOR EACH ROW EXECUTE FUNCTION public._worker_sessions_revoke_on_device();


--
-- Name: animals_pilot zzz_nc_outer_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zzz_nc_outer_guard BEFORE INSERT OR UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public._animals_nc_outer_guard();


--
-- Name: animals_pilot zzz_outer_open_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zzz_outer_open_guard BEFORE INSERT OR UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public._animals_outer_open_guard();


--
-- Name: animals_pilot zzzz_nc_outer_value; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER zzzz_nc_outer_value BEFORE INSERT OR UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION public._animals_nc_outer_value();


--
-- Name: animals animals_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(id);


--
-- Name: animals animals_farm_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_farm_id_fkey FOREIGN KEY (farm_id) REFERENCES public.source_farms(id);


--
-- Name: animals animals_inner_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_inner_by_fkey FOREIGN KEY (inner_by) REFERENCES public.profiles(id);


--
-- Name: animals animals_outer_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_outer_by_fkey FOREIGN KEY (outer_by) REFERENCES public.profiles(id);


--
-- Name: animals animals_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: animals animals_slaughtered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.animals
    ADD CONSTRAINT animals_slaughtered_by_fkey FOREIGN KEY (slaughtered_by) REFERENCES public.profiles(id);


--
-- Name: audit_log audit_log_animal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_animal_id_fkey FOREIGN KEY (animal_id) REFERENCES public.animals(id);


--
-- Name: audit_log audit_log_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(id);


--
-- Name: audit_log audit_log_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: audit_log audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id);


--
-- Name: batches batches_closed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batches
    ADD CONSTRAINT batches_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.profiles(id);


--
-- Name: batches batches_opened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batches
    ADD CONSTRAINT batches_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES public.profiles(id);


--
-- Name: batches batches_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.batches
    ADD CONSTRAINT batches_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: custom_statuses custom_statuses_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_statuses
    ADD CONSTRAINT custom_statuses_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: manager_sessions manager_sessions_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manager_sessions
    ADD CONSTRAINT manager_sessions_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.plant_managers(id) ON DELETE CASCADE;


--
-- Name: problem_reports problem_reports_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problem_reports
    ADD CONSTRAINT problem_reports_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(id);


--
-- Name: problem_reports problem_reports_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problem_reports
    ADD CONSTRAINT problem_reports_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: problem_reports problem_reports_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.problem_reports
    ADD CONSTRAINT problem_reports_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES public.profiles(id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: reprint_log reprint_log_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reprint_log
    ADD CONSTRAINT reprint_log_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(id);


--
-- Name: reprint_log reprint_log_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reprint_log
    ADD CONSTRAINT reprint_log_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: reprint_log reprint_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reprint_log
    ADD CONSTRAINT reprint_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id);


--
-- Name: source_farms source_farms_plant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_farms
    ADD CONSTRAINT source_farms_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: admin_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: animals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.animals ENABLE ROW LEVEL SECURITY;

--
-- Name: animals_carry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.animals_carry ENABLE ROW LEVEL SECURITY;

--
-- Name: animals_pilot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.animals_pilot ENABLE ROW LEVEL SECURITY;

--
-- Name: animals animals_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY animals_select ON public.animals FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: animals animals_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY animals_write ON public.animals USING ((plant_id = public._my_plant())) WITH CHECK ((plant_id = public._my_plant()));


--
-- Name: audit_log audit_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_insert ON public.audit_log FOR INSERT WITH CHECK ((plant_id = public._my_plant()));


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_select ON public.audit_log FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.batches ENABLE ROW LEVEL SECURITY;

--
-- Name: batches batches_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY batches_insert ON public.batches FOR INSERT WITH CHECK ((plant_id = public._my_plant()));


--
-- Name: batches batches_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY batches_select ON public.batches FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: batches batches_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY batches_update ON public.batches FOR UPDATE USING (((plant_id = public._my_plant()) AND ((public._my_role() = 'manager'::text) OR (status = 'open'::text))));


--
-- Name: custom_statuses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.custom_statuses ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_board_archive; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_board_archive ENABLE ROW LEVEL SECURITY;

--
-- Name: device_credentials; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_credentials ENABLE ROW LEVEL SECURITY;

--
-- Name: device_lifecycle_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_lifecycle_events ENABLE ROW LEVEL SECURITY;

--
-- Name: device_pairing; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_pairing ENABLE ROW LEVEL SECURITY;

--
-- Name: device_stage_cursor; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_stage_cursor ENABLE ROW LEVEL SECURITY;

--
-- Name: devices_pilot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.devices_pilot ENABLE ROW LEVEL SECURITY;

--
-- Name: events_chain_head; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events_chain_head ENABLE ROW LEVEL SECURITY;

--
-- Name: events_pilot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events_pilot ENABLE ROW LEVEL SECURITY;

--
-- Name: source_farms farms_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY farms_select ON public.source_farms FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: source_farms farms_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY farms_write ON public.source_farms USING (((plant_id = public._my_plant()) AND (public._my_role() = 'manager'::text))) WITH CHECK (((plant_id = public._my_plant()) AND (public._my_role() = 'manager'::text)));


--
-- Name: login_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: lung_drawings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lung_drawings ENABLE ROW LEVEL SECURITY;

--
-- Name: manager_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.manager_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: outer_status_pilot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.outer_status_pilot ENABLE ROW LEVEL SECURITY;

--
-- Name: pairing_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pairing_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: plant_managers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.plant_managers ENABLE ROW LEVEL SECURITY;

--
-- Name: plant_state; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.plant_state ENABLE ROW LEVEL SECURITY;

--
-- Name: plants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.plants ENABLE ROW LEVEL SECURITY;

--
-- Name: plants plants probe: no rows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "plants probe: no rows" ON public.plants FOR SELECT TO anon, authenticated USING (false);


--
-- Name: problem_reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.problem_reports ENABLE ROW LEVEL SECURITY;

--
-- Name: problem_reports problems_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY problems_select ON public.problem_reports FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: problem_reports problems_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY problems_write ON public.problem_reports USING ((plant_id = public._my_plant())) WITH CHECK ((plant_id = public._my_plant()));


--
-- Name: processed_commands; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.processed_commands ENABLE ROW LEVEL SECURITY;

--
-- Name: processing_day_closed; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.processing_day_closed ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_manager_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_manager_write ON public.profiles FOR INSERT WITH CHECK (((public._my_role() = 'manager'::text) AND (plant_id = public._my_plant())));


--
-- Name: profiles profiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select ON public.profiles FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: profiles profiles_update_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update_self ON public.profiles FOR UPDATE USING ((id = auth.uid()));


--
-- Name: rate_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_events ENABLE ROW LEVEL SECURITY;

--
-- Name: animals_pilot read animals_pilot; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read animals_pilot" ON public.animals_pilot FOR SELECT TO anon, authenticated USING (( SELECT public._reader_ok() AS _reader_ok));


--
-- Name: daily_board_archive read daily_board_archive; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read daily_board_archive" ON public.daily_board_archive FOR SELECT TO anon, authenticated USING (( SELECT public._reader_ok() AS _reader_ok));


--
-- Name: device_lifecycle_events read device_lifecycle_events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read device_lifecycle_events" ON public.device_lifecycle_events FOR SELECT TO anon, authenticated USING (( SELECT gt_rls.events_reader_ok() AS events_reader_ok));


--
-- Name: devices_pilot read devices_pilot; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read devices_pilot" ON public.devices_pilot FOR SELECT TO anon, authenticated USING ((( SELECT gt_rls.devices_read_all() AS devices_read_all) OR (id = ANY (( SELECT gt_rls.devices_read_own_ids() AS devices_read_own_ids)::text[]))));


--
-- Name: events_pilot read events_pilot; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read events_pilot" ON public.events_pilot FOR SELECT TO anon, authenticated USING (( SELECT gt_rls.events_reader_ok() AS events_reader_ok));


--
-- Name: settings_pilot read settings_pilot; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read settings_pilot" ON public.settings_pilot FOR SELECT TO anon, authenticated USING (( SELECT public._reader_ok() AS _reader_ok));


--
-- Name: reprint_log reprint_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reprint_insert ON public.reprint_log FOR INSERT WITH CHECK ((plant_id = public._my_plant()));


--
-- Name: reprint_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reprint_log ENABLE ROW LEVEL SECURITY;

--
-- Name: reprint_log reprint_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reprint_select ON public.reprint_log FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: revoked_device_writes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.revoked_device_writes ENABLE ROW LEVEL SECURITY;

--
-- Name: settings_pilot; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.settings_pilot ENABLE ROW LEVEL SECURITY;

--
-- Name: source_farms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.source_farms ENABLE ROW LEVEL SECURITY;

--
-- Name: custom_statuses statuses_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statuses_select ON public.custom_statuses FOR SELECT USING ((plant_id = public._my_plant()));


--
-- Name: custom_statuses statuses_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY statuses_write ON public.custom_statuses USING (((plant_id = public._my_plant()) AND (public._my_role() = 'manager'::text))) WITH CHECK (((plant_id = public._my_plant()) AND (public._my_role() = 'manager'::text)));


--
-- Name: system_flags; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.system_flags ENABLE ROW LEVEL SECURITY;

--
-- Name: worker_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.worker_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA gt_rls; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA gt_rls TO anon;
GRANT USAGE ON SCHEMA gt_rls TO authenticated;
GRANT USAGE ON SCHEMA gt_rls TO service_role;


--
-- Name: FUNCTION devices_read_all(); Type: ACL; Schema: gt_rls; Owner: -
--

REVOKE ALL ON FUNCTION gt_rls.devices_read_all() FROM PUBLIC;
GRANT ALL ON FUNCTION gt_rls.devices_read_all() TO anon;
GRANT ALL ON FUNCTION gt_rls.devices_read_all() TO authenticated;
GRANT ALL ON FUNCTION gt_rls.devices_read_all() TO service_role;


--
-- Name: FUNCTION devices_read_own_ids(); Type: ACL; Schema: gt_rls; Owner: -
--

REVOKE ALL ON FUNCTION gt_rls.devices_read_own_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION gt_rls.devices_read_own_ids() TO anon;
GRANT ALL ON FUNCTION gt_rls.devices_read_own_ids() TO authenticated;
GRANT ALL ON FUNCTION gt_rls.devices_read_own_ids() TO service_role;


--
-- Name: FUNCTION events_reader_ok(); Type: ACL; Schema: gt_rls; Owner: -
--

REVOKE ALL ON FUNCTION gt_rls.events_reader_ok() FROM PUBLIC;
GRANT ALL ON FUNCTION gt_rls.events_reader_ok() TO anon;
GRANT ALL ON FUNCTION gt_rls.events_reader_ok() TO authenticated;
GRANT ALL ON FUNCTION gt_rls.events_reader_ok() TO service_role;


--
-- Name: FUNCTION _acting_device(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._acting_device() FROM PUBLIC;


--
-- Name: FUNCTION _admin_audit(p_token text, p_action text, p_target text, p_detail jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._admin_audit(p_token text, p_action text, p_target text, p_detail jsonb) FROM PUBLIC;


--
-- Name: FUNCTION _animals_merge(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._animals_merge() FROM PUBLIC;


--
-- Name: FUNCTION _animals_nc_outer_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._animals_nc_outer_guard() FROM PUBLIC;


--
-- Name: FUNCTION _animals_nc_outer_value(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._animals_nc_outer_value() FROM PUBLIC;


--
-- Name: FUNCTION _animals_outer_open_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._animals_outer_open_guard() FROM PUBLIC;


--
-- Name: FUNCTION _animals_stage_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._animals_stage_guard() FROM PUBLIC;


--
-- Name: FUNCTION _archive_keep_intake(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._archive_keep_intake() FROM PUBLIC;


--
-- Name: FUNCTION _audit_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text, p_replacement_id uuid, p_actor text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._audit_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text, p_replacement_id uuid, p_actor text) FROM PUBLIC;


--
-- Name: FUNCTION _auth_uid_safe(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._auth_uid_safe() FROM PUBLIC;


--
-- Name: FUNCTION _board_business_date(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._board_business_date() FROM PUBLIC;


--
-- Name: FUNCTION _board_epoch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._board_epoch() FROM PUBLIC;


--
-- Name: FUNCTION _board_unfinished(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._board_unfinished() FROM PUBLIC;


--
-- Name: FUNCTION _board_write_lock(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._board_write_lock() FROM PUBLIC;


--
-- Name: FUNCTION _call_device(p_client text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._call_device(p_client text) FROM PUBLIC;


--
-- Name: FUNCTION _caller_device_role(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._caller_device_role() FROM PUBLIC;


--
-- Name: TABLE animals_pilot; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.animals_pilot TO anon;
GRANT SELECT ON TABLE public.animals_pilot TO authenticated;
GRANT ALL ON TABLE public.animals_pilot TO service_role;


--
-- Name: FUNCTION _carry_row(c public.animals_carry); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._carry_row(c public.animals_carry) FROM PUBLIC;


--
-- Name: FUNCTION _cmd_get(p_cmd uuid, p_dev text, p_fn text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._cmd_get(p_cmd uuid, p_dev text, p_fn text) FROM PUBLIC;


--
-- Name: FUNCTION _cmd_put(p_cmd uuid, p_dev text, p_fn text, p_result jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._cmd_put(p_cmd uuid, p_dev text, p_fn text, p_result jsonb) FROM PUBLIC;


--
-- Name: FUNCTION _code_in_use(p_code text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._code_in_use(p_code text) FROM PUBLIC;


--
-- Name: FUNCTION _correction_braked(p_dev text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._correction_braked(p_dev text) FROM PUBLIC;


--
-- Name: FUNCTION _correction_check(p_stage text, a public.animals_pilot, p_dev text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._correction_check(p_stage text, a public.animals_pilot, p_dev text) FROM PUBLIC;


--
-- Name: FUNCTION _credential_audit(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._credential_audit() FROM PUBLIC;


--
-- Name: FUNCTION _credential_revoked_at(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._credential_revoked_at() FROM PUBLIC;


--
-- Name: FUNCTION _current_device_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._current_device_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public._current_device_id() TO service_role;


--
-- Name: FUNCTION _current_worker(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._current_worker() FROM PUBLIC;


--
-- Name: FUNCTION _derive_actor(p_stage text, p_client text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._derive_actor(p_stage text, p_client text) FROM PUBLIC;


--
-- Name: FUNCTION _device_auth_required(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._device_auth_required() FROM PUBLIC;
GRANT ALL ON FUNCTION public._device_auth_required() TO service_role;


--
-- Name: FUNCTION _device_write_allowed(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._device_write_allowed() FROM PUBLIC;
GRANT ALL ON FUNCTION public._device_write_allowed() TO service_role;


--
-- Name: FUNCTION _device_write_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._device_write_guard() FROM PUBLIC;
GRANT ALL ON FUNCTION public._device_write_guard() TO service_role;


--
-- Name: FUNCTION _devices_assignment_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._devices_assignment_guard() FROM PUBLIC;
GRANT ALL ON FUNCTION public._devices_assignment_guard() TO service_role;


--
-- Name: FUNCTION _do_board_reset(p_reason text, p_business_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._do_board_reset(p_reason text, p_business_date date) FROM PUBLIC;


--
-- Name: FUNCTION _eso_required(p_id integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._eso_required(p_id integer) FROM PUBLIC;


--
-- Name: FUNCTION _event_canonical(p_event_id uuid, p_animal_no integer, p_stage text, p_action text, p_payload jsonb, p_actor text, p_device_id text, p_occurred_at text, p_prev_hash text, p_chain_pos bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._event_canonical(p_event_id uuid, p_animal_no integer, p_stage text, p_action text, p_payload jsonb, p_actor text, p_device_id text, p_occurred_at text, p_prev_hash text, p_chain_pos bigint) FROM PUBLIC;


--
-- Name: FUNCTION _event_chain_recent(p_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._event_chain_recent(p_limit integer) FROM PUBLIC;


--
-- Name: FUNCTION _events_actor(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._events_actor() FROM PUBLIC;


--
-- Name: FUNCTION _events_append_only(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._events_append_only() FROM PUBLIC;


--
-- Name: FUNCTION _events_chain_link(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._events_chain_link() FROM PUBLIC;


--
-- Name: FUNCTION _events_maker_guard(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._events_maker_guard() FROM PUBLIC;


--
-- Name: FUNCTION _extend_maker_sessions(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._extend_maker_sessions() FROM PUBLIC;


--
-- Name: FUNCTION _gt_flag(s jsonb, p_key text, p_default boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._gt_flag(s jsonb, p_key text, p_default boolean) FROM PUBLIC;


--
-- Name: FUNCTION _gt_settings(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._gt_settings() FROM PUBLIC;


--
-- Name: FUNCTION _gt_value_ok(p_kind text, v text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._gt_value_ok(p_kind text, v text) FROM PUBLIC;


--
-- Name: FUNCTION _is_api_request(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._is_api_request() FROM PUBLIC;
GRANT ALL ON FUNCTION public._is_api_request() TO service_role;


--
-- Name: FUNCTION _is_app_caller(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._is_app_caller() FROM PUBLIC;


--
-- Name: FUNCTION _is_nc(a public.animals_pilot); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._is_nc(a public.animals_pilot) FROM PUBLIC;


--
-- Name: FUNCTION _is_real_manager(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._is_real_manager(p_token text) FROM PUBLIC;


--
-- Name: FUNCTION _jint_ok(v jsonb, lo numeric, hi numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._jint_ok(v jsonb, lo numeric, hi numeric) FROM PUBLIC;


--
-- Name: FUNCTION _jnum_ok(v jsonb, lo numeric, hi numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._jnum_ok(v jsonb, lo numeric, hi numeric) FROM PUBLIC;


--
-- Name: FUNCTION _jstr_ok(v jsonb, maxlen integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._jstr_ok(v jsonb, maxlen integer) FROM PUBLIC;


--
-- Name: FUNCTION _kosher_ready(a public.animals_pilot); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._kosher_ready(a public.animals_pilot) FROM PUBLIC;


--
-- Name: FUNCTION _kosher_statuses(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._kosher_statuses() FROM PUBLIC;


--
-- Name: FUNCTION _log_correction_rejected(p_dev text, p_id integer, p_stage text, p_reason text, p_detail jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._log_correction_rejected(p_dev text, p_id integer, p_stage text, p_reason text, p_detail jsonb) FROM PUBLIC;


--
-- Name: FUNCTION _log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text) FROM PUBLIC;
GRANT ALL ON FUNCTION public._log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text) TO service_role;


--
-- Name: FUNCTION _maker_session_end(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._maker_session_end() FROM PUBLIC;


--
-- Name: FUNCTION _manager_session_valid(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._manager_session_valid(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public._manager_session_valid(p_token text) TO service_role;


--
-- Name: FUNCTION _manager_sessions_cleanup(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._manager_sessions_cleanup() FROM PUBLIC;


--
-- Name: FUNCTION _manufacturer_session_valid(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._manufacturer_session_valid(p_token text) FROM PUBLIC;


--
-- Name: FUNCTION _merge_list(a jsonb, b jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._merge_list(a jsonb, b jsonb) FROM PUBLIC;


--
-- Name: FUNCTION _mgr_session_bound(p_dev text, p_uid uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._mgr_session_bound(p_dev text, p_uid uuid) FROM PUBLIC;


--
-- Name: FUNCTION _my_plant(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._my_plant() FROM PUBLIC;
GRANT ALL ON FUNCTION public._my_plant() TO service_role;


--
-- Name: FUNCTION _my_role(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._my_role() FROM PUBLIC;
GRANT ALL ON FUNCTION public._my_role() TO service_role;


--
-- Name: FUNCTION _nc_outer_allowed(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._nc_outer_allowed() FROM PUBLIC;


--
-- Name: FUNCTION _no_device_error(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._no_device_error() FROM PUBLIC;


--
-- Name: FUNCTION _note_revoked_write(p_dev text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._note_revoked_write(p_dev text) FROM PUBLIC;


--
-- Name: FUNCTION _plant_state_test_mode_trg(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._plant_state_test_mode_trg() FROM PUBLIC;


--
-- Name: FUNCTION _printed_as_key(a public.animals_pilot); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._printed_as_key(a public.animals_pilot) FROM PUBLIC;


--
-- Name: FUNCTION _proc_board_json(p_board bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_board_json(p_board bigint) FROM PUBLIC;


--
-- Name: FUNCTION _proc_board_lock(p_board bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_board_lock(p_board bigint) FROM PUBLIC;


--
-- Name: FUNCTION _proc_board_pending(p_station text, p_board bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_board_pending(p_station text, p_board bigint) FROM PUBLIC;


--
-- Name: FUNCTION _proc_caller_station(p_station text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_caller_station(p_station text) FROM PUBLIC;


--
-- Name: FUNCTION _proc_finalize(p_board bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_finalize(p_board bigint) FROM PUBLIC;


--
-- Name: FUNCTION _proc_open_board(p_station text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_open_board(p_station text) FROM PUBLIC;


--
-- Name: FUNCTION _proc_pending(p_station text, a public.animals_pilot, p_today boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_pending(p_station text, a public.animals_pilot, p_today boolean) FROM PUBLIC;


--
-- Name: FUNCTION _proc_station_of_group(p_group text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_station_of_group(p_group text) FROM PUBLIC;


--
-- Name: FUNCTION _proc_stations(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._proc_stations() FROM PUBLIC;


--
-- Name: FUNCTION _push_is_correction(p_rows jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._push_is_correction(p_rows jsonb) FROM PUBLIC;


--
-- Name: FUNCTION _raise_correction(p_err text, p_stage text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._raise_correction(p_err text, p_stage text) FROM PUBLIC;


--
-- Name: FUNCTION _rate_count(p_kind text, p_key text, p_window interval); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._rate_count(p_kind text, p_key text, p_window interval) FROM PUBLIC;


--
-- Name: FUNCTION _rate_hit(p_kind text, p_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._rate_hit(p_kind text, p_key text) FROM PUBLIC;


--
-- Name: FUNCTION _reader_ok(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public._reader_ok() TO anon;
GRANT ALL ON FUNCTION public._reader_ok() TO authenticated;


--
-- Name: FUNCTION _reason_ok(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._reason_ok(p text) FROM PUBLIC;


--
-- Name: FUNCTION _request_has_manager(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._request_has_manager() FROM PUBLIC;
GRANT ALL ON FUNCTION public._request_has_manager() TO service_role;


--
-- Name: FUNCTION _request_has_manufacturer(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._request_has_manufacturer() FROM PUBLIC;


--
-- Name: FUNCTION _request_headers(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._request_headers() FROM PUBLIC;
GRANT ALL ON FUNCTION public._request_headers() TO service_role;


--
-- Name: FUNCTION _request_ip(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._request_ip() FROM PUBLIC;


--
-- Name: FUNCTION _request_is_service_role(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._request_is_service_role() FROM PUBLIC;
GRANT ALL ON FUNCTION public._request_is_service_role() TO service_role;


--
-- Name: FUNCTION _request_privileged(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._request_privileged() FROM PUBLIC;


--
-- Name: FUNCTION _security_event(p_animal_no integer, p_action text, p_payload jsonb, p_actor text, p_device text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._security_event(p_animal_no integer, p_action text, p_payload jsonb, p_actor text, p_device text) FROM PUBLIC;


--
-- Name: FUNCTION _session_name(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._session_name(p_token text) FROM PUBLIC;


--
-- Name: FUNCTION _session_role(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._session_role(p_token text) FROM PUBLIC;


--
-- Name: FUNCTION _set_setup_code(p_code text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._set_setup_code(p_code text) FROM PUBLIC;


--
-- Name: FUNCTION _settings_hash_worker_codes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._settings_hash_worker_codes() FROM PUBLIC;


--
-- Name: FUNCTION _settings_value_error(p_key text, v jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._settings_value_error(p_key text, v jsonb) FROM PUBLIC;


--
-- Name: FUNCTION _stage_allowed(p_stage text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._stage_allowed(p_stage text) FROM PUBLIC;


--
-- Name: FUNCTION _stage_order_error(p_stage text, a public.animals_pilot, p_today boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._stage_order_error(p_stage text, a public.animals_pilot, p_today boolean) FROM PUBLIC;


--
-- Name: FUNCTION _stage_worker_role(p_stage text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._stage_worker_role(p_stage text) FROM PUBLIC;


--
-- Name: FUNCTION _status_change_error(p_old jsonb, p_new jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._status_change_error(p_old jsonb, p_new jsonb) FROM PUBLIC;


--
-- Name: FUNCTION _statuses_in_use(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._statuses_in_use() FROM PUBLIC;


--
-- Name: FUNCTION _support_access_open(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._support_access_open() FROM PUBLIC;


--
-- Name: FUNCTION _test_mode_active(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._test_mode_active() FROM PUBLIC;


--
-- Name: FUNCTION _test_mode_autooff(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._test_mode_autooff() FROM PUBLIC;


--
-- Name: FUNCTION _test_mode_flag(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._test_mode_flag() FROM PUBLIC;


--
-- Name: FUNCTION _test_mode_max(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._test_mode_max() FROM PUBLIC;


--
-- Name: FUNCTION _test_mode_on(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._test_mode_on() FROM PUBLIC;


--
-- Name: FUNCTION _test_mode_on_at(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._test_mode_on_at() FROM PUBLIC;


--
-- Name: FUNCTION _ts_or_null(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._ts_or_null(p text) FROM PUBLIC;


--
-- Name: FUNCTION _worker_code_hash(p_code text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._worker_code_hash(p_code text) FROM PUBLIC;


--
-- Name: FUNCTION _worker_role_norm(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._worker_role_norm(p text) FROM PUBLIC;


--
-- Name: FUNCTION _worker_sessions_revoke_on_credential(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._worker_sessions_revoke_on_credential() FROM PUBLIC;


--
-- Name: FUNCTION _worker_sessions_revoke_on_device(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._worker_sessions_revoke_on_device() FROM PUBLIC;


--
-- Name: FUNCTION animal_push(p_rows jsonb, p_command_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.animal_push(p_rows jsonb, p_command_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.animal_push(p_rows jsonb, p_command_id uuid) TO anon;
GRANT ALL ON FUNCTION public.animal_push(p_rows jsonb, p_command_id uuid) TO authenticated;


--
-- Name: FUNCTION animals_pilot_advance_cursor(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.animals_pilot_advance_cursor() FROM PUBLIC;
GRANT ALL ON FUNCTION public.animals_pilot_advance_cursor() TO service_role;


--
-- Name: FUNCTION animals_pilot_guard_corrections(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.animals_pilot_guard_corrections() FROM PUBLIC;
GRANT ALL ON FUNCTION public.animals_pilot_guard_corrections() TO service_role;


--
-- Name: FUNCTION archive_days(p_token text, p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.archive_days(p_token text, p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.archive_days(p_token text, p_from date, p_to date) TO anon;
GRANT ALL ON FUNCTION public.archive_days(p_token text, p_from date, p_to date) TO authenticated;


--
-- Name: FUNCTION carry_claim(p_board bigint, p_id integer, p_stage text, p_command_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.carry_claim(p_board bigint, p_id integer, p_stage text, p_command_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.carry_claim(p_board bigint, p_id integer, p_stage text, p_command_id uuid) TO anon;
GRANT ALL ON FUNCTION public.carry_claim(p_board bigint, p_id integer, p_stage text, p_command_id uuid) TO authenticated;


--
-- Name: FUNCTION carry_push(p_board bigint, p_rows jsonb, p_command_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.carry_push(p_board bigint, p_rows jsonb, p_command_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.carry_push(p_board bigint, p_rows jsonb, p_command_id uuid) TO anon;
GRANT ALL ON FUNCTION public.carry_push(p_board bigint, p_rows jsonb, p_command_id uuid) TO authenticated;


--
-- Name: FUNCTION claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint) TO anon;
GRANT ALL ON FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint) TO authenticated;


--
-- Name: FUNCTION claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint, p_command_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint, p_command_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint, p_command_id uuid) TO anon;
GRANT ALL ON FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint, p_command_id uuid) TO authenticated;


--
-- Name: FUNCTION create_first_manager(p_name text, p_code text, p_setup_code text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.create_first_manager(p_name text, p_code text, p_setup_code text) TO anon;
GRANT ALL ON FUNCTION public.create_first_manager(p_name text, p_code text, p_setup_code text) TO authenticated;


--
-- Name: FUNCTION device_auth_set(p_token text, p_on boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.device_auth_set(p_token text, p_on boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.device_auth_set(p_token text, p_on boolean) TO service_role;
GRANT ALL ON FUNCTION public.device_auth_set(p_token text, p_on boolean) TO anon;
GRANT ALL ON FUNCTION public.device_auth_set(p_token text, p_on boolean) TO authenticated;


--
-- Name: FUNCTION device_heartbeat(p_device_id text, p_device_name text, p_info jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.device_heartbeat(p_device_id text, p_device_name text, p_info jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.device_heartbeat(p_device_id text, p_device_name text, p_info jsonb) TO anon;
GRANT ALL ON FUNCTION public.device_heartbeat(p_device_id text, p_device_name text, p_info jsonb) TO authenticated;


--
-- Name: FUNCTION device_manage(p_token text, p_device_id text, p_action text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) TO service_role;


--
-- Name: FUNCTION device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text, p_reason text) TO service_role;


--
-- Name: FUNCTION device_paired_list(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.device_paired_list(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.device_paired_list(p_token text) TO authenticated;
GRANT ALL ON FUNCTION public.device_paired_list(p_token text) TO anon;
GRANT ALL ON FUNCTION public.device_paired_list(p_token text) TO service_role;


--
-- Name: FUNCTION device_pairing_status(p_device_id text, p_code text, p_secret text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.device_pairing_status(p_device_id text, p_code text, p_secret text) TO authenticated;
GRANT ALL ON FUNCTION public.device_pairing_status(p_device_id text, p_code text, p_secret text) TO anon;
GRANT ALL ON FUNCTION public.device_pairing_status(p_device_id text, p_code text, p_secret text) TO service_role;


--
-- Name: FUNCTION device_request_pairing(p_device_id text, p_secret text, p_device_name text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) TO authenticated;
GRANT ALL ON FUNCTION public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) TO anon;
GRANT ALL ON FUNCTION public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) TO service_role;


--
-- Name: FUNCTION device_unpair(p_token text, p_device_id text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.device_unpair(p_token text, p_device_id text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.device_unpair(p_token text, p_device_id text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.device_unpair(p_token text, p_device_id text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.device_unpair(p_token text, p_device_id text, p_reason text) TO service_role;


--
-- Name: FUNCTION device_whoami(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.device_whoami() FROM PUBLIC;
GRANT ALL ON FUNCTION public.device_whoami() TO authenticated;
GRANT ALL ON FUNCTION public.device_whoami() TO anon;
GRANT ALL ON FUNCTION public.device_whoami() TO service_role;


--
-- Name: FUNCTION eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint) TO anon;
GRANT ALL ON FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint) TO authenticated;


--
-- Name: FUNCTION eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid) TO anon;
GRANT ALL ON FUNCTION public.eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid) TO authenticated;


--
-- Name: FUNCTION event_append(p_event jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.event_append(p_event jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.event_append(p_event jsonb) TO anon;
GRANT ALL ON FUNCTION public.event_append(p_event jsonb) TO authenticated;


--
-- Name: FUNCTION lung_drawing_get(p_id integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lung_drawing_get(p_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lung_drawing_get(p_id integer) TO anon;
GRANT ALL ON FUNCTION public.lung_drawing_get(p_id integer) TO authenticated;


--
-- Name: FUNCTION lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text) TO anon;
GRANT ALL ON FUNCTION public.lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text) TO authenticated;


--
-- Name: FUNCTION manager_add(p_token text, p_name text, p_code text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.manager_add(p_token text, p_name text, p_code text) TO authenticated;
GRANT ALL ON FUNCTION public.manager_add(p_token text, p_name text, p_code text) TO anon;
GRANT ALL ON FUNCTION public.manager_add(p_token text, p_name text, p_code text) TO service_role;


--
-- Name: FUNCTION manager_add_owner(p_token text, p_name text, p_code text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.manager_add_owner(p_token text, p_name text, p_code text) TO anon;
GRANT ALL ON FUNCTION public.manager_add_owner(p_token text, p_name text, p_code text) TO authenticated;


--
-- Name: FUNCTION manager_deactivate(p_token text, p_manager_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.manager_deactivate(p_token text, p_manager_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.manager_deactivate(p_token text, p_manager_id uuid) TO anon;
GRANT ALL ON FUNCTION public.manager_deactivate(p_token text, p_manager_id uuid) TO service_role;


--
-- Name: FUNCTION manager_list(p_token text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.manager_list(p_token text) TO anon;
GRANT ALL ON FUNCTION public.manager_list(p_token text) TO authenticated;


--
-- Name: FUNCTION manager_login(p_code text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.manager_login(p_code text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.manager_login(p_code text) TO authenticated;
GRANT ALL ON FUNCTION public.manager_login(p_code text) TO anon;
GRANT ALL ON FUNCTION public.manager_login(p_code text) TO service_role;


--
-- Name: FUNCTION manager_logout(p_token text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.manager_logout(p_token text) TO anon;
GRANT ALL ON FUNCTION public.manager_logout(p_token text) TO authenticated;


--
-- Name: FUNCTION manager_session_check(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.manager_session_check(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.manager_session_check(p_token text) TO anon;
GRANT ALL ON FUNCTION public.manager_session_check(p_token text) TO authenticated;


--
-- Name: FUNCTION manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text, p_reason text) TO authenticated;


--
-- Name: FUNCTION manufacturer_set_code(p_name text, p_code text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.manufacturer_set_code(p_name text, p_code text) FROM PUBLIC;


--
-- Name: FUNCTION outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text) TO anon;
GRANT ALL ON FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text) TO authenticated;


--
-- Name: FUNCTION outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text, p_command_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text, p_command_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text, p_command_id uuid) TO anon;
GRANT ALL ON FUNCTION public.outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text, p_command_id uuid) TO authenticated;


--
-- Name: FUNCTION plant_status_snapshot(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.plant_status_snapshot() TO anon;
GRANT ALL ON FUNCTION public.plant_status_snapshot() TO authenticated;


--
-- Name: FUNCTION processing_board(p_station text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.processing_board(p_station text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.processing_board(p_station text) TO anon;
GRANT ALL ON FUNCTION public.processing_board(p_station text) TO authenticated;


--
-- Name: FUNCTION processing_day_close(p_token text, p_board bigint, p_station text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.processing_day_close(p_token text, p_board bigint, p_station text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.processing_day_close(p_token text, p_board bigint, p_station text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.processing_day_close(p_token text, p_board bigint, p_station text, p_reason text) TO authenticated;


--
-- Name: FUNCTION processing_status(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.processing_status(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.processing_status(p_token text) TO anon;
GRANT ALL ON FUNCTION public.processing_status(p_token text) TO authenticated;


--
-- Name: FUNCTION push_settings(p_settings jsonb, p_device_id text, p_token text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.push_settings(p_settings jsonb, p_device_id text, p_token text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.push_settings(p_settings jsonb, p_device_id text, p_token text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.push_settings(p_settings jsonb, p_device_id text, p_token text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.push_settings(p_settings jsonb, p_device_id text, p_token text, p_reason text) TO service_role;


--
-- Name: FUNCTION request_daily_rollover(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.request_daily_rollover() FROM PUBLIC;
GRANT ALL ON FUNCTION public.request_daily_rollover() TO anon;
GRANT ALL ON FUNCTION public.request_daily_rollover() TO authenticated;


--
-- Name: FUNCTION reset_daily_board(p_token text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reset_daily_board(p_token text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reset_daily_board(p_token text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.reset_daily_board(p_token text, p_reason text) TO authenticated;


--
-- Name: FUNCTION security_summary(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.security_summary(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.security_summary(p_token text) TO anon;
GRANT ALL ON FUNCTION public.security_summary(p_token text) TO authenticated;


--
-- Name: FUNCTION server_now_ms(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.server_now_ms() TO anon;
GRANT ALL ON FUNCTION public.server_now_ms() TO authenticated;


--
-- Name: FUNCTION server_schema_step(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.server_schema_step() TO anon;
GRANT ALL ON FUNCTION public.server_schema_step() TO authenticated;


--
-- Name: FUNCTION server_test_mode(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.server_test_mode() FROM PUBLIC;
GRANT ALL ON FUNCTION public.server_test_mode() TO anon;
GRANT ALL ON FUNCTION public.server_test_mode() TO authenticated;


--
-- Name: FUNCTION server_test_mode_info(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.server_test_mode_info() FROM PUBLIC;
GRANT ALL ON FUNCTION public.server_test_mode_info() TO anon;
GRANT ALL ON FUNCTION public.server_test_mode_info() TO authenticated;


--
-- Name: FUNCTION set_not_chalak_outer(p_id integer, p_epoch bigint, p_command_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_not_chalak_outer(p_id integer, p_epoch bigint, p_command_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_not_chalak_outer(p_id integer, p_epoch bigint, p_command_id uuid) TO anon;
GRANT ALL ON FUNCTION public.set_not_chalak_outer(p_id integer, p_epoch bigint, p_command_id uuid) TO authenticated;


--
-- Name: FUNCTION support_access_set(p_token text, p_hours integer, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.support_access_set(p_token text, p_hours integer, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.support_access_set(p_token text, p_hours integer, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.support_access_set(p_token text, p_hours integer, p_reason text) TO authenticated;


--
-- Name: FUNCTION support_diagnostics(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.support_diagnostics(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.support_diagnostics(p_token text) TO anon;
GRANT ALL ON FUNCTION public.support_diagnostics(p_token text) TO authenticated;


--
-- Name: FUNCTION support_force_reload(p_token text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.support_force_reload(p_token text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.support_force_reload(p_token text, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.support_force_reload(p_token text, p_reason text) TO authenticated;


--
-- Name: FUNCTION system_health(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.system_health(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.system_health(p_token text) TO anon;
GRANT ALL ON FUNCTION public.system_health(p_token text) TO authenticated;


--
-- Name: FUNCTION verify_event_chain(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.verify_event_chain() TO anon;
GRANT ALL ON FUNCTION public.verify_event_chain() TO authenticated;


--
-- Name: FUNCTION worker_login(p_role text, p_code text, p_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.worker_login(p_role text, p_code text, p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.worker_login(p_role text, p_code text, p_name text) TO anon;
GRANT ALL ON FUNCTION public.worker_login(p_role text, p_code text, p_name text) TO authenticated;


--
-- Name: FUNCTION worker_logout(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.worker_logout(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.worker_logout(p_token text) TO anon;
GRANT ALL ON FUNCTION public.worker_logout(p_token text) TO authenticated;


--
-- Name: FUNCTION worker_session_check(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.worker_session_check() FROM PUBLIC;
GRANT ALL ON FUNCTION public.worker_session_check() TO anon;
GRANT ALL ON FUNCTION public.worker_session_check() TO authenticated;


--
-- Name: TABLE animals; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.animals TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.audit_log TO service_role;


--
-- Name: SEQUENCE audit_log_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.audit_log_id_seq TO service_role;


--
-- Name: TABLE batches; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.batches TO service_role;


--
-- Name: TABLE custom_statuses; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.custom_statuses TO service_role;


--
-- Name: TABLE daily_board_archive; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.daily_board_archive TO anon;
GRANT SELECT ON TABLE public.daily_board_archive TO authenticated;


--
-- Name: TABLE device_credentials; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.device_credentials TO service_role;


--
-- Name: TABLE device_lifecycle_events; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.device_lifecycle_events TO anon;
GRANT SELECT ON TABLE public.device_lifecycle_events TO authenticated;
GRANT ALL ON TABLE public.device_lifecycle_events TO service_role;


--
-- Name: TABLE device_pairing; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.device_pairing TO service_role;


--
-- Name: TABLE devices_pilot; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.devices_pilot TO anon;
GRANT SELECT ON TABLE public.devices_pilot TO authenticated;
GRANT ALL ON TABLE public.devices_pilot TO service_role;


--
-- Name: TABLE events_pilot; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.events_pilot TO anon;
GRANT SELECT ON TABLE public.events_pilot TO authenticated;
GRANT ALL ON TABLE public.events_pilot TO service_role;


--
-- Name: SEQUENCE events_pilot_server_seq_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.events_pilot_server_seq_seq TO service_role;


--
-- Name: TABLE manager_sessions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.manager_sessions TO service_role;


--
-- Name: TABLE outer_status_pilot; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.outer_status_pilot TO service_role;


--
-- Name: TABLE plant_managers; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.plant_managers TO service_role;


--
-- Name: TABLE plants; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.plants TO service_role;
GRANT SELECT ON TABLE public.plants TO anon;
GRANT SELECT ON TABLE public.plants TO authenticated;


--
-- Name: TABLE problem_reports; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.problem_reports TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profiles TO service_role;


--
-- Name: TABLE reprint_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reprint_log TO service_role;


--
-- Name: TABLE settings_pilot; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.settings_pilot TO anon;
GRANT SELECT ON TABLE public.settings_pilot TO authenticated;
GRANT ALL ON TABLE public.settings_pilot TO service_role;


--
-- Name: TABLE source_farms; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.source_farms TO service_role;


--
-- Name: TABLE system_flags; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.system_flags TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict hTvBLK3WHyccmIUz1chRGp0lp11GLTZSjcn8d6uhDvh4NKlvxF14WM0JxnFjiHX

