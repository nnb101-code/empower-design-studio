-- ============================================================================
-- GlattTrack — ACTIVE security manifest (read-only; changes nothing)
-- ============================================================================
-- Prints what is really in force in THIS database right now:
--   1. schema step / test mode (+ when switched on; 8-hour limit, step 45) /
--      support access / backup verification
--   2. every function in public + gt_rls: security definer, fixed search_path,
--      owner, who may run it (anon / authenticated / PUBLIC)
--   3. triggers on the key tables (enabled?)
--   4. row security + policies on every table the app roles can touch
--   5. table and sequence rights of anon / authenticated
--   6. schema rights
-- The expected manifest is embedded in tools/security-selftest.sql (section
-- "the ACTIVE security surface against the expected manifest"), which FAILS if
-- a guard trigger / policy / revoke is missing or an unexpected grant appears.
--
--   psql -U postgres -d <db> -f active-security-manifest.sql
-- ============================================================================
\pset pager off
\pset null '·'

\echo '== 1. plant state ======================================================='
select key, value, updated_at from plant_state
 where key in ('schemaStep', 'testMode', 'testModeOnAt', 'supportAccessUntil', 'boardEpoch', 'lastRolloverDate',
               'plantServer', 'lastBackupVerifiedAt', 'lastBackupFailedAt', 'lastBackupFailReason')
 order by key;

\echo '== 2. functions (public, gt_rls) ========================================'
select n.nspname                                              as schema,
       p.oid::regprocedure::text                              as function,
       case when p.prorettype = 'trigger'::regtype then 'trigger' else 'function' end as kind,
       p.prosecdef                                            as security_definer,
       coalesce((select substring(c from 'search_path=(.*)') from unnest(p.proconfig) c where c like 'search_path=%'), '— NONE —')
                                                              as search_path,
       pg_get_userbyid(p.proowner)                            as owner,
       has_function_privilege('anon', p.oid, 'execute')          as anon,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated,
       exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where a.grantee = 0 and a.privilege_type = 'EXECUTE') as public_role,
       exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') as from_extension
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('public', 'gt_rls')
 order by (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')) desc,
          n.nspname, p.proname, p.oid::regprocedure::text;

\echo '== 2b. API surface: functions the app roles can run ======================'
select p.oid::regprocedure::text as callable_by_app,
       p.prosecdef as security_definer
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('public', 'gt_rls')
   and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
 order by 1;

\echo '== 3. triggers on the key tables ========================================'
select c.relname as "table", t.tgname as trigger, p.proname as function,
       case when t.tgtype & 2 = 2 then 'BEFORE' when t.tgtype & 64 = 64 then 'INSTEAD OF' else 'AFTER' end
       || ' ' || concat_ws('/', case when t.tgtype & 4 = 4 then 'INSERT' end, case when t.tgtype & 16 = 16 then 'UPDATE' end,
                              case when t.tgtype & 8 = 8 then 'DELETE' end, case when t.tgtype & 32 = 32 then 'TRUNCATE' end)
       || case when t.tgtype & 1 = 1 then ' ROW' else ' STATEMENT' end as fires,
       case t.tgenabled when 'O' then 'enabled' when 'D' then '*** DISABLED ***' when 'R' then 'replica only' when 'A' then 'always' end as state,
       p.prosecdef as security_definer
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_proc p on p.oid = t.tgfoid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and not t.tgisinternal
   and c.relname in ('animals_pilot', 'events_pilot', 'devices_pilot', 'device_credentials', 'settings_pilot',
                     'manager_sessions', 'plant_state', 'daily_board_archive', 'device_lifecycle_events')
 order by c.relname, t.tgname;

\echo '== 4. row security and policies ========================================='
select c.relname as "table", c.relrowsecurity as rls_on, c.relforcerowsecurity as rls_forced,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as policies
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p')
 order by c.relrowsecurity, c.relname;
select tablename as "table", policyname as policy, cmd, permissive, roles::text as roles,
       coalesce(qual, '') as using_expr, coalesce(with_check, '') as check_expr
  from pg_policies where schemaname = 'public'
 order by tablename, policyname;

\echo '== 5. table rights of the app roles (anything but these SELECTs is unexpected) =='
select c.relname as "table", ro.r as role,
       string_agg(pv.p, ', ' order by pv.p) as privileges
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  cross join (values ('anon'), ('authenticated')) ro(r)
  cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) pv(p)
 where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
   and has_table_privilege(ro.r, c.oid, pv.p)
 group by c.relname, ro.r
 order by c.relname, ro.r;
select c.relname as "sequence", has_sequence_privilege('anon', c.oid, 'USAGE') as anon_usage,
       has_sequence_privilege('authenticated', c.oid, 'USAGE') as authenticated_usage
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'S'
 order by 1;

\echo '== 6. schema rights ====================================================='
select s.nspname as schema,
       has_schema_privilege('anon', s.oid, 'USAGE') as anon_usage,
       has_schema_privilege('anon', s.oid, 'CREATE') as anon_create,
       has_schema_privilege('authenticated', s.oid, 'CREATE') as authenticated_create
  from pg_namespace s where s.nspname in ('public', 'gt_rls', 'extensions', 'auth')
 order by 1;

\echo '== 7. quick verdict (the full comparison: tools/security-selftest.sql) =='
select 'direct board writes closed' as rule,
       not (has_table_privilege('anon', 'public.animals_pilot', 'INSERT') or has_table_privilege('anon', 'public.animals_pilot', 'UPDATE')
            or has_table_privilege('authenticated', 'public.animals_pilot', 'INSERT') or has_table_privilege('authenticated', 'public.animals_pilot', 'UPDATE')) as ok
union all select 'direct event inserts closed',
       not (has_table_privilege('anon', 'public.events_pilot', 'INSERT') or has_table_privilege('authenticated', 'public.events_pilot', 'INSERT'))
union all select 'device reads narrowed', exists (select 1 from pg_policies where tablename = 'devices_pilot' and qual like '%devices_read_own_ids%')
union all select 'event reads narrowed', exists (select 1 from pg_policies where tablename = 'events_pilot' and qual like '%events_reader_ok%')
union all select 'one device per slot', exists (select 1 from pg_indexes where indexname = 'devices_pilot_one_per_slot')
union all select 'test mode OFF', coalesce((select value from plant_state where key = 'testMode'), 'off') = 'off'
union all select 'every security definer has a search_path',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname in ('public', 'gt_rls') and p.prosecdef
                      and not coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false))
union all select 'no internal (_*) function callable by the app (except _reader_ok)',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname like '\_%' and p.proname <> '_reader_ok'
                      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')));
