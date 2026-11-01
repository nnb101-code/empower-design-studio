-- The plant's side of the manufacturer's support center (from 02 — the plant server's schema, step 46).
-- §32: the first _plant_report; §39 replaces it (the last definition is the active one).

-- ── §32 the plant's report to the manufacturer's support center (v10.35, owner) ──
-- Read only by the plant server itself (plant-server/report-to-center.sh, as the database owner) —
-- never by the app. The health of the plant + its app version + whether anyone works now + each
-- tablet (connected, version). No kashrut data, no worker names, no codes.
create or replace function _plant_report() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select _system_health_data() || jsonb_build_object(
    'appVersion', (select value from plant_state where key = 'appVersion'),
    'appUpdatedAt', (select value from plant_state where key = 'appUpdatedAt'),
    'working', exists (select 1 from animals_pilot where updated_at > now() - interval '10 minutes'),
    'tablets', coalesce((select jsonb_agg(jsonb_build_object(
                  'role', d.assigned_role, 'index', coalesce(d.assigned_index, 0), 'name', left(coalesce(d.device_name, ''), 40),
                  'online', d.last_seen > now() - interval '3 minutes', 'lastSeen', d.last_seen,
                  'version', d.app_info ->> 'v', 'screen', d.app_info ->> 'screen')
                  order by d.assigned_role, d.assigned_index)
                from devices_pilot d where d.assigned_role is not null and coalesce(d.device_status, 'active') <> 'retired'), '[]'::jsonb));
$$;
revoke execute on function _plant_report() from public, anon, authenticated;


-- ── 39. the manufacturer's support center: problem reports, daily totals, what the maker changed (v10.38, owner) ──
-- The plant's report (§32) now also carries: (1) the problem reports of the last 14 days — from the stations
-- ("report a problem" events) and from the team leader (support_issue_add); each becomes a ticket at the
-- support center once; (2) the daily totals of the last 40 days (animals slaughtered, kg) — the center bills
-- by them when the plant pays by kg / by animal. Still no kashrut rulings, no worker names, no codes.
-- The center's answer (each ticket's status + the last reply) is kept in plant_state 'supportTickets'
-- by plant-server/report-to-center.sh; the team leader reads it with support_tickets().
create table if not exists support_issues (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  who text, message text not null check (length(message) between 1 and 1000));
alter table support_issues enable row level security;
revoke all on table support_issues from public, anon, authenticated;
revoke all on sequence support_issues_id_seq from public, anon, authenticated;   -- Supabase opens new sequences to the app by default

create index if not exists events_pilot_problem_reports on events_pilot (created_at) where action = 'problem_report';   -- (review)

create or replace function support_issue_add(p_token text, p_message text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id bigint;
begin
  if not _manager_session_valid(p_token) or coalesce(_session_role(p_token), 'manager') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if coalesce(trim(p_message), '') = '' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if (select count(*) from support_issues where at > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('ok', false, 'error', 'too_many');
  end if;
  insert into support_issues (who, message) values (left(coalesce(_session_name(p_token), ''), 60), left(trim(p_message), 1000))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'key', 'L' || v_id);
end $$;
revoke execute on function support_issue_add(text, text) from public;
grant execute on function support_issue_add(text, text) to anon, authenticated;

-- the tickets as the support center last answered (status new / working / closed + its last reply)
create or replace function support_tickets(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare t jsonb;
begin
  if not _manager_session_valid(p_token) or coalesce(_session_role(p_token), 'manager') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  begin t := (select value from plant_state where key = 'supportTickets')::jsonb; exception when others then t := null; end;
  return jsonb_build_object('ok', true,
    'at', (select updated_at from plant_state where key = 'supportTickets'),
    'issues', coalesce((select jsonb_agg(x order by x ->> 'at' desc) from (
        select jsonb_build_object('key', 'L' || i.id, 'at', i.at, 'source', 'leader', 'message', i.message,
                                  'status', tk ->> 'status', 'reply', tk ->> 'reply') x
          from support_issues i
          left join lateral (select e from jsonb_array_elements(case when jsonb_typeof(t) = 'array' then t else '[]'::jsonb end) e
                              where e ->> 'key' = 'L' || i.id limit 1) z(tk) on true
         where i.at > now() - interval '30 days'
        union all
        select jsonb_build_object('key', 'E' || e.server_seq, 'at', e.created_at, 'source', 'station', 'screen', e.payload ->> 'screen',
                                  'message', left(concat_ws(' · ', nullif(e.payload ->> 'note', ''), e.payload ->> 'summary'), 1000),
                                  'status', tk ->> 'status', 'reply', tk ->> 'reply')
          from events_pilot e
          left join lateral (select x from jsonb_array_elements(case when jsonb_typeof(t) = 'array' then t else '[]'::jsonb end) x
                              where x ->> 'key' = 'E' || e.server_seq limit 1) z(tk) on true
         where e.action = 'problem_report' and e.created_at > now() - interval '30 days') q), '[]'::jsonb));
end $$;
revoke execute on function support_tickets(text) from public;
grant execute on function support_tickets(text) to anon, authenticated;

-- what the manufacturer changed at this plant (its own audit rows) — the owner and the team leader see them
create or replace function maker_changes(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) or coalesce(_session_role(p_token), 'manager') not in ('manager', 'owner') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object('at', a.at, 'who', a.who, 'action', a.action,
            'target', a.target, 'detail', left(a.detail::text, 400)) order by a.at desc)
     from (select * from admin_audit where role = 'manufacturer' order by at desc limit 200) a), '[]'::jsonb));
end $$;
revoke execute on function maker_changes(text) from public;
grant execute on function maker_changes(text) to anon, authenticated;

-- the daily totals: every archived board of a day + today's board (animals slaughtered / ruled at the knife, kg)
create or replace function _plant_usage() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('day', d, 'animals', n, 'kg', round(kg, 1)) order by d), '[]'::jsonb)
    from (select d, sum(n)::int n, sum(kg) kg from (
            select b.business_date d, count(*) filter (where x ->> 'slaughter' is not null) n,
                   coalesce(sum(coalesce(nullif(x ->> 'weight_right', '')::numeric, 0) + coalesce(nullif(x ->> 'weight_left', '')::numeric, 0)), 0) kg
              from daily_board_archive b, jsonb_array_elements(case when jsonb_typeof(b.board) = 'array' then b.board else '[]'::jsonb end) x
             where b.business_date > current_date - 40
             group by b.business_date
            union all
            select _board_business_date(), count(*) filter (where a.slaughter is not null),
                   coalesce(sum(coalesce(a.weight_right, 0) + coalesce(a.weight_left, 0)), 0)
              from animals_pilot a) u
           where d is not null group by d) t;
$$;
revoke execute on function _plant_usage() from public, anon, authenticated;

create or replace function _plant_issues() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object('key', 'L' || id, 'at', at, 'source', 'leader', 'message', message) x
      from support_issues where at > now() - interval '14 days'
    union all
    select jsonb_build_object('key', 'E' || server_seq, 'at', created_at, 'source', 'station', 'screen', left(payload ->> 'screen', 40),
                              'message', left(concat_ws(' · ', nullif(payload ->> 'note', ''), payload ->> 'summary'), 1000))
      from events_pilot where action = 'problem_report' and created_at > now() - interval '14 days'
     limit 300) q;
$$;
revoke execute on function _plant_issues() from public, anon, authenticated;

create or replace function _plant_report() returns jsonb
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select _system_health_data() || jsonb_build_object(
    'appVersion', (select value from plant_state where key = 'appVersion'),
    'appUpdatedAt', (select value from plant_state where key = 'appUpdatedAt'),
    'working', exists (select 1 from animals_pilot where updated_at > now() - interval '10 minutes'),
    'tablets', coalesce((select jsonb_agg(jsonb_build_object(
                  'role', d.assigned_role, 'index', coalesce(d.assigned_index, 0), 'name', left(coalesce(d.device_name, ''), 40),
                  'online', d.last_seen > now() - interval '3 minutes', 'lastSeen', d.last_seen,
                  'version', d.app_info ->> 'v', 'screen', d.app_info ->> 'screen')
                  order by d.assigned_role, d.assigned_index)
                from devices_pilot d where d.assigned_role is not null and coalesce(d.device_status, 'active') <> 'retired'), '[]'::jsonb),
    'issues', _plant_issues(),
    'usage', _plant_usage());
$$;
revoke execute on function _plant_report() from public, anon, authenticated;

