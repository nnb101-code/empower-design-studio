-- GlattTrack database structure, exported 2026-09-22 23:29
set check_function_bodies = off;
create extension if not exists pgcrypto;

-- re-run guard (step 45): step 45 gave these functions a last p_reason argument.
-- When this whole file runs again, the older steps below re-create the old
-- signatures first; the step-45 ones are dropped here and re-created (with the
-- same grants) by step 45 at the end, so no call below is ambiguous.
drop function if exists public.device_pair(text, text, text, integer, boolean, text, text);
drop function if exists public.support_access_set(text, integer, text);
drop function if exists public.manufacturer_set_billing(text, boolean, numeric, text, text);
drop function if exists public.support_force_reload(text, text);
drop function if exists public.push_settings(jsonb, text, text, text);

create sequence if not exists public.audit_log_id_seq;

create table if not exists public.animals (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  batch_id uuid not null,
  seq_number integer not null,
  farm_id uuid,
  slaughter text,
  slaughtered_by uuid,
  slaughter_time timestamp with time zone,
  legs_stickers boolean default false not null,
  head_stickers boolean default false not null,
  maw text,
  rumen text,
  lung_drawing_url text,
  inner_status text,
  inner_by uuid,
  inner_time timestamp with time zone,
  outer_status text,
  outer_by uuid,
  outer_time timestamp with time zone,
  parts_scanned boolean default false not null,
  tongue_sticker boolean default false not null,
  cheek_sticker boolean default false not null,
  weight_right numeric(6,2),
  weight_left numeric(6,2),
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.animals_pilot (
  id integer not null,
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
  updated_at timestamp with time zone default now(),
  slaughter_by_device text,
  inner_by_device text,
  outer_by_device text,
  weight_stage2 numeric,
  weight_stage3 numeric,
  stamped boolean,
  weight_right_skipped boolean default false,
  weight_left_skipped boolean default false,
  weight_stage2_skipped boolean default false,
  weight_stage3_skipped boolean default false
);

create table if not exists public.audit_log (
  id bigint default nextval('audit_log_id_seq'::regclass) not null,
  plant_id uuid not null,
  batch_id uuid,
  animal_id uuid,
  event_type text not null,
  from_value text,
  to_value text,
  user_id uuid,
  user_name text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.batches (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  business_date date default CURRENT_DATE not null,
  status text default 'open'::text not null,
  animal_type text,
  opened_at timestamp with time zone default now() not null,
  opened_by uuid,
  closed_at timestamp with time zone,
  closed_by uuid
);

create table if not exists public.custom_statuses (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  key text not null,
  label_he text not null,
  label_en text,
  label_es text,
  color text,
  sort_order integer default 0 not null,
  enabled boolean default true not null
);

create table if not exists public.device_credentials (
  device_id text not null,
  token_hash text not null,
  created_at timestamp with time zone default now() not null,
  revoked boolean default false not null
);

create table if not exists public.device_lifecycle_events (
  event_id uuid default gen_random_uuid() not null,
  device_id text not null,
  action text not null,
  station_id text,
  station_slot integer,
  actor text,
  reason text,
  replacement_device_id text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.device_pairing (
  code text not null,
  device_id text not null,
  device_name text,
  secret_hash text,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone default (now() + '00:15:00'::interval) not null,
  paired_at timestamp with time zone,
  token_plain text
);

create table if not exists public.devices_pilot (
  id text not null,
  device_name text,
  assigned_role text,
  assigned_index integer,
  last_seen timestamp with time zone,
  updated_at timestamp with time zone default now(),
  device_status text default 'active'::text not null,
  retired_at timestamp with time zone,
  retired_by text,
  retired_reason text,
  cursor_slaughter integer,
  cursor_inner integer,
  cursor_outer integer,
  paired_at timestamp with time zone
);

create table if not exists public.events_pilot (
  event_id uuid not null,
  animal_no integer,
  stage text not null,
  action text not null,
  payload jsonb default '{}'::jsonb not null,
  actor text,
  device_id text,
  occurred_at text not null,
  prev_hash text,
  event_hash text not null,
  server_seq bigint generated always as identity not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.manager_sessions (
  token text default encode(gen_random_bytes(24), 'hex'::text) not null,
  manager_id uuid not null,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone default (now() + '12:00:00'::interval) not null
);

create table if not exists public.outer_status_pilot (
  id integer not null,
  outer_status text,
  outer_by text,
  outer_time bigint,
  device_id text,
  updated_at timestamp with time zone default now()
);

create table if not exists public.plant_managers (
  id uuid default gen_random_uuid() not null,
  name text not null,
  code_hash text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.plants (
  id uuid default gen_random_uuid() not null,
  name text not null,
  license_status text default 'trial'::text not null,
  license_expiry date,
  daily_target integer default 500,
  animal_type text default 'cattle'::text,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.problem_reports (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  batch_id uuid,
  animal_seq integer,
  description text not null,
  reported_by uuid,
  resolved boolean default false not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.profiles (
  id uuid not null,
  plant_id uuid not null,
  name text not null,
  role text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.reprint_log (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  batch_id uuid,
  animal_seq integer not null,
  station text not null,
  user_id uuid,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.settings_pilot (
  id integer not null,
  settings jsonb,
  device_id text,
  updated_at timestamp with time zone default now()
);

create table if not exists public.source_farms (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  name text not null,
  active boolean default true not null
);

create table if not exists public.system_flags (
  key text not null,
  value boolean default false not null
);

alter sequence public.audit_log_id_seq owned by public.audit_log.id;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_pilot_pkey' and conrelid = 'public.animals_pilot'::regclass) then
    alter table public.animals_pilot add constraint animals_pilot_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_pkey' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'audit_log_pkey' and conrelid = 'public.audit_log'::regclass) then
    alter table public.audit_log add constraint audit_log_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'batches_pkey' and conrelid = 'public.batches'::regclass) then
    alter table public.batches add constraint batches_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'custom_statuses_pkey' and conrelid = 'public.custom_statuses'::regclass) then
    alter table public.custom_statuses add constraint custom_statuses_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'device_credentials_pkey' and conrelid = 'public.device_credentials'::regclass) then
    alter table public.device_credentials add constraint device_credentials_pkey PRIMARY KEY (device_id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'device_lifecycle_events_pkey' and conrelid = 'public.device_lifecycle_events'::regclass) then
    alter table public.device_lifecycle_events add constraint device_lifecycle_events_pkey PRIMARY KEY (event_id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'device_pairing_pkey' and conrelid = 'public.device_pairing'::regclass) then
    alter table public.device_pairing add constraint device_pairing_pkey PRIMARY KEY (code);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'devices_pilot_pkey' and conrelid = 'public.devices_pilot'::regclass) then
    alter table public.devices_pilot add constraint devices_pilot_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'events_pilot_pkey' and conrelid = 'public.events_pilot'::regclass) then
    alter table public.events_pilot add constraint events_pilot_pkey PRIMARY KEY (event_id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'manager_sessions_pkey' and conrelid = 'public.manager_sessions'::regclass) then
    alter table public.manager_sessions add constraint manager_sessions_pkey PRIMARY KEY (token);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'outer_status_pilot_pkey' and conrelid = 'public.outer_status_pilot'::regclass) then
    alter table public.outer_status_pilot add constraint outer_status_pilot_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'plant_managers_pkey' and conrelid = 'public.plant_managers'::regclass) then
    alter table public.plant_managers add constraint plant_managers_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'plants_pkey' and conrelid = 'public.plants'::regclass) then
    alter table public.plants add constraint plants_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'problem_reports_pkey' and conrelid = 'public.problem_reports'::regclass) then
    alter table public.problem_reports add constraint problem_reports_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_pkey' and conrelid = 'public.profiles'::regclass) then
    alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'reprint_log_pkey' and conrelid = 'public.reprint_log'::regclass) then
    alter table public.reprint_log add constraint reprint_log_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'settings_pilot_pkey' and conrelid = 'public.settings_pilot'::regclass) then
    alter table public.settings_pilot add constraint settings_pilot_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'source_farms_pkey' and conrelid = 'public.source_farms'::regclass) then
    alter table public.source_farms add constraint source_farms_pkey PRIMARY KEY (id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'system_flags_pkey' and conrelid = 'public.system_flags'::regclass) then
    alter table public.system_flags add constraint system_flags_pkey PRIMARY KEY (key);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_batch_id_seq_number_key' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_batch_id_seq_number_key UNIQUE (batch_id, seq_number);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_inner_status_check' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_inner_status_check CHECK ((inner_status = ANY (ARRAY['in_progress'::text, 'treif'::text, 'confirmed'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_maw_check' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_maw_check CHECK ((maw = ANY (ARRAY['kosher'::text, 'treif'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_outer_status_check' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_outer_status_check CHECK ((outer_status = ANY (ARRAY['glatt'::text, 'beit'::text, 'kosher'::text, 'mk'::text, 'treif'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_rumen_check' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_rumen_check CHECK ((rumen = ANY (ARRAY['kosher'::text, 'treif'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_slaughter_check' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_slaughter_check CHECK ((slaughter = ANY (ARRAY['slaughtered'::text, 'nevela'::text, 'shot'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'batches_status_check' and conrelid = 'public.batches'::regclass) then
    alter table public.batches add constraint batches_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'custom_statuses_plant_id_key_key' and conrelid = 'public.custom_statuses'::regclass) then
    alter table public.custom_statuses add constraint custom_statuses_plant_id_key_key UNIQUE (plant_id, key);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'device_credentials_token_hash_key' and conrelid = 'public.device_credentials'::regclass) then
    alter table public.device_credentials add constraint device_credentials_token_hash_key UNIQUE (token_hash);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'devices_pilot_device_status_check' and conrelid = 'public.devices_pilot'::regclass) then
    alter table public.devices_pilot add constraint devices_pilot_device_status_check CHECK ((device_status = ANY (ARRAY['active'::text, 'retired'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'devices_pilot_safe_id' and conrelid = 'public.devices_pilot'::regclass) then
    alter table public.devices_pilot add constraint devices_pilot_safe_id CHECK ((id ~ '^[A-Za-z0-9_-]{6,64}$'::text)) NOT VALID;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'events_pilot_event_hash_key' and conrelid = 'public.events_pilot'::regclass) then
    alter table public.events_pilot add constraint events_pilot_event_hash_key UNIQUE (event_hash);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'events_pilot_server_seq_key' and conrelid = 'public.events_pilot'::regclass) then
    alter table public.events_pilot add constraint events_pilot_server_seq_key UNIQUE (server_seq);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'plants_animal_type_check' and conrelid = 'public.plants'::regclass) then
    alter table public.plants add constraint plants_animal_type_check CHECK ((animal_type = ANY (ARRAY['cattle'::text, 'sheep'::text, 'mixed'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'plants_license_status_check' and conrelid = 'public.plants'::regclass) then
    alter table public.plants add constraint plants_license_status_check CHECK ((license_status = ANY (ARRAY['trial'::text, 'active'::text, 'expired'::text, 'suspended'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_role_check' and conrelid = 'public.profiles'::regclass) then
    alter table public.profiles add constraint profiles_role_check CHECK ((role = ANY (ARRAY['slaughter'::text, 'inspector'::text, 'supervisor'::text, 'manager'::text])));
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_batch_id_fkey' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_farm_id_fkey' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_farm_id_fkey FOREIGN KEY (farm_id) REFERENCES source_farms(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_inner_by_fkey' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_inner_by_fkey FOREIGN KEY (inner_by) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_outer_by_fkey' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_outer_by_fkey FOREIGN KEY (outer_by) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_plant_id_fkey' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'animals_slaughtered_by_fkey' and conrelid = 'public.animals'::regclass) then
    alter table public.animals add constraint animals_slaughtered_by_fkey FOREIGN KEY (slaughtered_by) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'audit_log_animal_id_fkey' and conrelid = 'public.audit_log'::regclass) then
    alter table public.audit_log add constraint audit_log_animal_id_fkey FOREIGN KEY (animal_id) REFERENCES animals(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'audit_log_batch_id_fkey' and conrelid = 'public.audit_log'::regclass) then
    alter table public.audit_log add constraint audit_log_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'audit_log_plant_id_fkey' and conrelid = 'public.audit_log'::regclass) then
    alter table public.audit_log add constraint audit_log_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'audit_log_user_id_fkey' and conrelid = 'public.audit_log'::regclass) then
    alter table public.audit_log add constraint audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'batches_closed_by_fkey' and conrelid = 'public.batches'::regclass) then
    alter table public.batches add constraint batches_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'batches_opened_by_fkey' and conrelid = 'public.batches'::regclass) then
    alter table public.batches add constraint batches_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'batches_plant_id_fkey' and conrelid = 'public.batches'::regclass) then
    alter table public.batches add constraint batches_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'custom_statuses_plant_id_fkey' and conrelid = 'public.custom_statuses'::regclass) then
    alter table public.custom_statuses add constraint custom_statuses_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'manager_sessions_manager_id_fkey' and conrelid = 'public.manager_sessions'::regclass) then
    alter table public.manager_sessions add constraint manager_sessions_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES plant_managers(id) ON DELETE CASCADE;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'problem_reports_batch_id_fkey' and conrelid = 'public.problem_reports'::regclass) then
    alter table public.problem_reports add constraint problem_reports_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'problem_reports_plant_id_fkey' and conrelid = 'public.problem_reports'::regclass) then
    alter table public.problem_reports add constraint problem_reports_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'problem_reports_reported_by_fkey' and conrelid = 'public.problem_reports'::regclass) then
    alter table public.problem_reports add constraint problem_reports_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_id_fkey' and conrelid = 'public.profiles'::regclass) then
    alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_plant_id_fkey' and conrelid = 'public.profiles'::regclass) then
    alter table public.profiles add constraint profiles_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'reprint_log_batch_id_fkey' and conrelid = 'public.reprint_log'::regclass) then
    alter table public.reprint_log add constraint reprint_log_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES batches(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'reprint_log_plant_id_fkey' and conrelid = 'public.reprint_log'::regclass) then
    alter table public.reprint_log add constraint reprint_log_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'reprint_log_user_id_fkey' and conrelid = 'public.reprint_log'::regclass) then
    alter table public.reprint_log add constraint reprint_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id);
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_constraint where conname = 'source_farms_plant_id_fkey' and conrelid = 'public.source_farms'::regclass) then
    alter table public.source_farms add constraint source_farms_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
  end if;
end $x$;

CREATE INDEX IF NOT EXISTS animals_batch_id_idx ON public.animals USING btree (batch_id);

CREATE INDEX IF NOT EXISTS animals_plant_id_batch_id_seq_number_idx ON public.animals USING btree (plant_id, batch_id, seq_number);

CREATE INDEX IF NOT EXISTS audit_log_plant_id_created_at_idx ON public.audit_log USING btree (plant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS batches_plant_id_status_idx ON public.batches USING btree (plant_id, status);

CREATE INDEX IF NOT EXISTS idx_device_lifecycle_device ON public.device_lifecycle_events USING btree (device_id, created_at DESC);

CREATE OR REPLACE FUNCTION public._current_device_id()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_tok text; v_id text;
begin
  v_tok := _request_headers() ->> 'x-device-token';
  if v_tok is null or v_tok = '' then return null; end if;
  select device_id into v_id from device_credentials
   where token_hash = encode(digest(v_tok, 'sha256'), 'hex') and not revoked;
  return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public._device_auth_required()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select coalesce((select value from system_flags where key = 'device_auth_required'), false);
$function$
;

CREATE OR REPLACE FUNCTION public._device_write_allowed()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_dev text;
begin
  if not _device_auth_required() then return true; end if;             -- enforcement OFF
  if not _is_api_request() then return true; end if;                    -- SQL editor / server jobs
  if _request_is_service_role() then return true; end if;                -- server-side code with the service key
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  if _request_has_manager() then return true; end if;                    -- logged-in manager
  v_dev := _current_device_id();
  if v_dev is null then return false; end if;
  return exists(select 1 from devices_pilot
                 where id = v_dev and assigned_role is not null
                   and coalesce(device_status, 'active') <> 'retired');
end $function$
;

CREATE OR REPLACE FUNCTION public._device_write_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if not _device_write_allowed() then
    raise exception 'המכשיר אינו מצומד לתחנה — יש לצמד אותו במסך המנהל (device_not_paired)'
      using errcode = '42501';
  end if;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public._devices_assignment_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if not _device_auth_required()
     or not _is_api_request()
     or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'מחיקת מכשיר אפשרית רק ממסך המנהל (assignment_locked)' using errcode = '42501';
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
    raise exception 'שיוך מכשיר לתחנה אפשרי רק דרך צימוד במסך המנהל (assignment_locked)'
      using errcode = '42501';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public._is_api_request()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select session_user = 'authenticator';
$function$
;

CREATE OR REPLACE FUNCTION public._log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  insert into device_lifecycle_events (device_id, action, station_id, station_slot, actor, reason, replacement_device_id)
  values (p_device, p_action, p_role, p_idx, 'manager', p_reason, p_other);
exception when others then null;  -- logging must never block pairing
end $function$
;

CREATE OR REPLACE FUNCTION public._manager_session_valid(p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
        declare
          v_required boolean;
          begin
            select value into v_required from system_flags where key = 'manager_auth_required';
              if coalesce(v_required, false) = false then
                  return true;
                    end if;
                      return exists(
                          select 1 from manager_sessions s
                              join plant_managers m on m.id = s.manager_id
                                  where s.token = p_token and s.expires_at > now() and m.active
                                    );
                                    end;
                                    $function$
;

CREATE OR REPLACE FUNCTION public._my_plant()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
                            select plant_id from profiles where id = auth.uid()
                            $function$
;

CREATE OR REPLACE FUNCTION public._my_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
                              select role from profiles where id = auth.uid()
                              $function$
;

CREATE OR REPLACE FUNCTION public._request_has_manager()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_tok text;
begin
  v_tok := _request_headers() ->> 'x-manager-token';
  if v_tok is null or v_tok = '' then return false; end if;
  return exists(
    select 1 from manager_sessions s join plant_managers m on m.id = s.manager_id
     where s.token = v_tok and s.expires_at > now() and m.active
  );
end $function$
;

CREATE OR REPLACE FUNCTION public._request_headers()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare h text;
begin
  h := current_setting('request.headers', true);
  if h is null or h = '' then return null; end if;
  return h::json;
exception when others then return null;  -- unreadable = no key (callers fail closed)
end $function$
;

CREATE OR REPLACE FUNCTION public._request_is_service_role()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  return coalesce(current_setting('request.jwt.claims', true)::json ->> 'role', '') = 'service_role';
exception when others then return false;
end $function$
;

CREATE OR REPLACE FUNCTION public.animals_pilot_advance_cursor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if old.slaughter is null and new.slaughter is not null and new.device_id is not null then
      update public.devices_pilot set cursor_slaughter = new.id where id = new.device_id;
        end if;
          if old.inner_status is null and new.inner_status is not null and new.device_id is not null then
              update public.devices_pilot set cursor_inner = new.id where id = new.device_id;
                end if;
                  if old.outer_status is null and new.outer_status is not null and new.device_id is not null then
                      update public.devices_pilot set cursor_outer = new.id where id = new.device_id;
                        end if;
                          return new;
                          end;
                          $function$
;

CREATE OR REPLACE FUNCTION public.animals_pilot_guard_corrections()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
                              declare
                                d record;
                                begin
                                  if current_setting('gt.reset_in_progress', true) = 'true' then
                                      return new;
                                        end if;

                                          if old.slaughter is not null and new.slaughter is distinct from old.slaughter then
                                              select cursor_slaughter into d from public.devices_pilot where id = new.device_id;
                                                  if d.cursor_slaughter is distinct from new.id then
                                                        raise exception 'correction-blocked: already moved on — slaughter status is locked';
                                                            end if;
                                                              end if;

                                                                if old.inner_status is not null and old.inner_status is distinct from 'in_progress' and new.inner_status is distinct from old.inner_status then
                                                                    select cursor_inner into d from public.devices_pilot where id = new.device_id;
                                                                        if d.cursor_inner is distinct from new.id then
                                                                              raise exception 'correction-blocked: already moved on — inner status is locked';
                                                                                  end if;
                                                                                    end if;

                                                                                      if old.outer_status is not null and new.outer_status is distinct from old.outer_status then
                                                                                          select cursor_outer into d from public.devices_pilot where id = new.device_id;
                                                                                              if d.cursor_outer is distinct from new.id then
                                                                                                    raise exception 'correction-blocked: already moved on — outer status is locked';
                                                                                                        end if;
                                                                                                          end if;

                                                                                                            return new;
                                                                                                            end;
                                                                                                            $function$
;

CREATE OR REPLACE FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
          declare
            v_rows integer;
              v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
                v_row jsonb;
                begin
                  if p_stage = 'slaughter' then
                      update animals_pilot
                            set slaughter = p_value,
                                      slaughtered_by = p_actor,
                                                slaughter_time = v_now_ms,
                                                          slaughter_by_device = p_device_id,
                                                                    updated_at = now()
                                                                          where id = p_id and slaughter is null;

                                                                            elsif p_stage = 'inner' then
                                                                                update animals_pilot
                                                                                      set inner_status = p_value,
                                                                                                inner_by = p_actor,
                                                                                                          inner_time = v_now_ms,
                                                                                                                    inner_by_device = p_device_id,
                                                                                                                              updated_at = now()
                                                                                                                                    where id = p_id and (inner_status is null or inner_status = 'in_progress');

                                                                                                                                      elsif p_stage = 'outer' then
                                                                                                                                          update animals_pilot
                                                                                                                                                set outer_status = p_value,
                                                                                                                                                          outer_by = p_actor,
                                                                                                                                                                    outer_time = v_now_ms,
                                                                                                                                                                              outer_by_device = p_device_id,
                                                                                                                                                                                        updated_at = now()
                                                                                                                                                                                              where id = p_id and outer_status is null;

                                                                                                                                                                                                elsif p_stage = 'eso' then
                                                                                                                                                                                                    -- Mirrors the client's own side-effect: a nevela result at the esophagus
                                                                                                                                                                                                        -- check also sets the final slaughter status, atomically, in the same
                                                                                                                                                                                                            -- claim (a null slaughter is the normal case here since eso happens
                                                                                                                                                                                                                -- right after slaughter and before it's usually corrected).
                                                                                                                                                                                                                    update animals_pilot
                                                                                                                                                                                                                          set eso_checked = true,
                                                                                                                                                                                                                                    eso_result = p_value,
                                                                                                                                                                                                                                              slaughter = case when p_value = 'nevela' and slaughter is null then 'nevela' else slaughter end,
                                                                                                                                                                                                                                                        updated_at = now()
                                                                                                                                                                                                                                                              where id = p_id and (eso_checked is distinct from true);

                                                                                                                                                                                                                                                                elsif p_stage = 'legs' then
                                                                                                                                                                                                                                                                    update animals_pilot
                                                                                                                                                                                                                                                                          set legs_sorted = true,
                                                                                                                                                                                                                                                                                    updated_at = now()
                                                                                                                                                                                                                                                                                          where id = p_id and (legs_sorted is distinct from true);

                                                                                                                                                                                                                                                                                            elsif p_stage = 'stamped' then
                                                                                                                                                                                                                                                                                                update animals_pilot
                                                                                                                                                                                                                                                                                                      set stamped = true,
                                                                                                                                                                                                                                                                                                                updated_at = now()
                                                                                                                                                                                                                                                                                                                      where id = p_id and (stamped is distinct from true);

                                                                                                                                                                                                                                                                                                                        else
                                                                                                                                                                                                                                                                                                                            raise exception 'claim_animal_stage: unknown stage %', p_stage;
                                                                                                                                                                                                                                                                                                                              end if;

                                                                                                                                                                                                                                                                                                                                get diagnostics v_rows = row_count;

                                                                                                                                                                                                                                                                                                                                  select to_jsonb(a.*) into v_row from animals_pilot a where a.id = p_id;

                                                                                                                                                                                                                                                                                                                                    if v_rows = 1 then
                                                                                                                                                                                                                                                                                                                                        return jsonb_build_object('claimed', true, 'row', v_row);
                                                                                                                                                                                                                                                                                                                                          else
                                                                                                                                                                                                                                                                                                                                              return jsonb_build_object('claimed', false, 'row', v_row);
                                                                                                                                                                                                                                                                                                                                                end if;
                                                                                                                                                                                                                                                                                                                                                end;
                                                                                                                                                                                                                                                                                                                                                $function$
;

CREATE OR REPLACE FUNCTION public.create_first_manager(p_name text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
                                  declare
                                    v_id uuid;
                                    begin
                                      if exists(select 1 from plant_managers) then
                                          return jsonb_build_object('ok', false, 'error', 'a manager already exists — use manager_add instead');
                                            end if;
                                              if p_code is null or length(p_code) < 4 then
                                                  return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
                                                    end if;
                                                      insert into plant_managers (name, code_hash) values (p_name, crypt(p_code, gen_salt('bf')))
                                                          returning id into v_id;
                                                            return jsonb_build_object('ok', true, 'id', v_id);
                                                            end;
                                                            $function$
;

CREATE OR REPLACE FUNCTION public.device_auth_set(p_token text, p_on boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  update system_flags set value = p_on where key = 'device_auth_required';
  return jsonb_build_object('ok', true, 'enforced', p_on);
end $function$
;

CREATE OR REPLACE FUNCTION public.device_heartbeat(p_device_id text, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then return jsonb_build_object('ok', false); end if;
  insert into devices_pilot (id, device_name, last_seen) values (p_device_id, left(p_device_name, 60), now())
    on conflict (id) do update set last_seen = now(),
      device_name = coalesce(devices_pilot.device_name, excluded.device_name);
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.device_manage(p_token text, p_device_id text, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare d devices_pilot%rowtype;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into d from devices_pilot where id = p_device_id;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform set_config('app.device_admin', 'on', true);
  if p_action = 'retire' then
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null,
           device_status = 'retired', retired_at = now(), retired_by = 'manager',
           retired_reason = coalesce(left(p_reason, 200), 'מסך תקול'), updated_at = now()
     where id = p_device_id;
    update device_credentials set revoked = true where device_id = p_device_id;
    perform _log_device_event(p_device_id, 'DEVICE_RETIRED', d.assigned_role, d.assigned_index, p_reason, null);
  elsif p_action = 'reactivate' then
    update devices_pilot set device_status = 'active', retired_at = null, retired_by = null,
           retired_reason = null, updated_at = now()
     where id = p_device_id;
    perform _log_device_event(p_device_id, 'DEVICE_REACTIVATED', null, null, p_reason, null);
  elsif p_action = 'rename' then
    update devices_pilot set device_name = coalesce(nullif(left(trim(p_reason), 60), ''), device_name), updated_at = now()
     where id = p_device_id;
  else
    perform set_config('app.device_admin', '', true);
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;
  perform set_config('app.device_admin', '', true);
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer DEFAULT 0, p_replace boolean DEFAULT false, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare r device_pairing%rowtype; v_idx int; v_tok text; v_old record;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_role not in ('slaughter','esophagus','legs','inner','outer','parts','stamps') then
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;
  v_idx := case when p_role in ('inner','outer') then coalesce(p_index, 0) else 0 end;
  if v_idx not in (0, 1) then return jsonb_build_object('ok', false, 'error', 'bad_slot'); end if;

  -- one pairing per station slot at a time (two managers can't both win)
  perform pg_advisory_xact_lock(hashtext('device_slot:' || p_role || ':' || v_idx));

  select * into r from device_pairing
   where code = trim(p_code) and paired_at is null and expires_at > now()
   for update;
  if r.code is null then return jsonb_build_object('ok', false, 'error', 'code_invalid'); end if;

  perform set_config('app.device_admin', 'on', true);

  -- someone else already on this station slot?
  for v_old in select id, device_name from devices_pilot
                where assigned_role = p_role and coalesce(assigned_index, 0) = v_idx
                  and id <> r.device_id and coalesce(device_status, 'active') <> 'retired'
  loop
    if not p_replace then
      perform set_config('app.device_admin', '', true);
      return jsonb_build_object('ok', false, 'error', 'slot_taken',
                                'device_name', coalesce(v_old.device_name, v_old.id));
    end if;
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
     where id = v_old.id;
    update device_credentials set revoked = true where device_id = v_old.id;
    perform _log_device_event(v_old.id, 'UNASSIGNED', p_role, v_idx, 'replaced by pairing', r.device_id);
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
  perform _log_device_event(r.device_id, 'ASSIGNED', p_role, v_idx, 'paired with code', null);
  return jsonb_build_object('ok', true, 'device_id', r.device_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.device_paired_list(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'devices',
    coalesce((select jsonb_agg(device_id) from device_credentials where not revoked), '[]'::jsonb),
    'enforced', _device_auth_required());
end $function$
;

CREATE OR REPLACE FUNCTION public.device_pairing_status(p_device_id text, p_code text, p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
  select * into d from devices_pilot where id = p_device_id;
  return jsonb_build_object('status', 'paired', 'token', r.token_plain,
                            'role', d.assigned_role, 'index', d.assigned_index,
                            'device_name', d.device_name);
end $function$
;

CREATE OR REPLACE FUNCTION public.device_request_pairing(p_device_id text, p_secret text, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_code text; v_exp timestamptz; i int := 0;
begin
  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then
    return jsonb_build_object('ok', false, 'error', 'bad device id');
  end if;
  if p_secret is null or length(p_secret) < 16 then
    return jsonb_build_object('ok', false, 'error', 'bad secret');
  end if;
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
end $function$
;

CREATE OR REPLACE FUNCTION public.device_unpair(p_token text, p_device_id text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare d devices_pilot%rowtype;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into d from devices_pilot where id = p_device_id;
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
   where id = p_device_id;
  update device_credentials set revoked = true where device_id = p_device_id;
  perform set_config('app.device_admin', '', true);
  perform _log_device_event(p_device_id, 'UNASSIGNED', d.assigned_role, d.assigned_index, coalesce(p_reason, 'unpaired'), null);
  return jsonb_build_object('ok', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.device_whoami()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_id text; d devices_pilot%rowtype; v_sent boolean;
begin
  v_sent := coalesce(_request_headers() ->> 'x-device-token', '') <> '';
  v_id := _current_device_id();
  if v_id is not null then select * into d from devices_pilot where id = v_id; end if;
  return jsonb_build_object('key_sent', v_sent, 'device_id', v_id,
                            'role', d.assigned_role, 'index', d.assigned_index,
                            'enforced', _device_auth_required());
end $function$
;

CREATE OR REPLACE FUNCTION public.manager_add(p_token text, p_name text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
                                                                                                    declare
                                                                                                      v_id uuid;
                                                                                                      begin
                                                                                                        if not _manager_session_valid(p_token) then
                                                                                                            return jsonb_build_object('ok', false, 'error', 'unauthorized');
                                                                                                              end if;
                                                                                                                if p_code is null or length(p_code) < 4 then
                                                                                                                    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
                                                                                                                      end if;
                                                                                                                        insert into plant_managers (name, code_hash) values (p_name, crypt(p_code, gen_salt('bf')))
                                                                                                                            returning id into v_id;
                                                                                                                              return jsonb_build_object('ok', true, 'id', v_id);
                                                                                                                              end;
                                                                                                                              $function$
;

CREATE OR REPLACE FUNCTION public.manager_deactivate(p_token text, p_manager_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
                                                                                                                              begin
                                                                                                                                if not _manager_session_valid(p_token) then
                                                                                                                                    return jsonb_build_object('ok', false, 'error', 'unauthorized');
                                                                                                                                      end if;
                                                                                                                                        update plant_managers set active = false where id = p_manager_id;
                                                                                                                                          delete from manager_sessions where manager_id = p_manager_id;
                                                                                                                                            return jsonb_build_object('ok', true);
                                                                                                                                            end;
                                                                                                                                            $function$
;

CREATE OR REPLACE FUNCTION public.manager_login(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
                                                            declare
                                                              v_manager plant_managers%rowtype;
                                                                v_token text;
                                                                  v_expires timestamptz;
                                                                  begin
                                                                    if not exists(select 1 from plant_managers) then
                                                                        return jsonb_build_object('ok', false, 'reason', 'no_managers');
                                                                          end if;
                                                                            select * into v_manager from plant_managers
                                                                                where active and code_hash = crypt(p_code, code_hash)
                                                                                    limit 1;
                                                                                      if v_manager.id is null then
                                                                                          return jsonb_build_object('ok', false, 'reason', 'wrong_code');
                                                                                            end if;
                                                                                              insert into manager_sessions (manager_id) values (v_manager.id)
                                                                                                  returning token, expires_at into v_token, v_expires;
                                                                                                    return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name, 'expires_at', v_expires);
                                                                                                    end;
                                                                                                    $function$
;

CREATE OR REPLACE FUNCTION public.push_settings(p_settings jsonb, p_device_id text, p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
                                                                                                                                            declare
                                                                                                                                              admin_keys text[] := array[
                                                                                                                                                  'weightControl','customStatuses','disabledStatuses','autoResetTime',
                                                                                                                                                      'users','license','loginModeByRole','stickerSize','customSeals',
                                                                                                                                                          'notChalakEnabled','legsSortEnabled','weightMethods','dailyTarget',
                                                                                                                                                              'installationCode'
                                                                                                                                                                ];
                                                                                                                                                                  cur jsonb;
                                                                                                                                                                    k text;
                                                                                                                                                                      is_manager boolean := false;
                                                                                                                                                                      begin
                                                                                                                                                                        if p_token is not null then
                                                                                                                                                                            is_manager := _manager_session_valid(p_token);
                                                                                                                                                                              end if;

                                                                                                                                                                                select settings into cur from settings_pilot where id = 1;

                                                                                                                                                                                  if not is_manager then
                                                                                                                                                                                      foreach k in array admin_keys loop
                                                                                                                                                                                            if (cur -> k) is distinct from (p_settings -> k) then
                                                                                                                                                                                                    return jsonb_build_object('ok', false, 'error', 'unauthorized: this setting requires manager login', 'key', k);
                                                                                                                                                                                                          end if;
                                                                                                                                                                                                              end loop;
                                                                                                                                                                                                                end if;

                                                                                                                                                                                                                  insert into settings_pilot (id, settings, device_id, updated_at)
                                                                                                                                                                                                                    values (1, p_settings, p_device_id, now())
                                                                                                                                                                                                                      on conflict (id) do update
                                                                                                                                                                                                                          set settings = excluded.settings, device_id = excluded.device_id, updated_at = excluded.updated_at;

                                                                                                                                                                                                                            return jsonb_build_object('ok', true);
                                                                                                                                                                                                                            end;
                                                                                                                                                                                                                            $function$
;

CREATE OR REPLACE FUNCTION public.reset_daily_board(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
                                                                                                                                                                                                                            begin
                                                                                                                                                                                                                              if not _manager_session_valid(p_token) then
                                                                                                                                                                                                                                  return jsonb_build_object('ok', false, 'error', 'unauthorized');
                                                                                                                                                                                                                                    end if;

                                                                                                                                                                                                                                      update animals_pilot set
                                                                                                                                                                                                                                          slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
                                                                                                                                                                                                                                              legs_stickers = false, head_stickers = false,
                                                                                                                                                                                                                                                  maw = null, rumen = null,
                                                                                                                                                                                                                                                      inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
                                                                                                                                                                                                                                                          not_chalak_inner = false,
                                                                                                                                                                                                                                                              outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
                                                                                                                                                                                                                                                                  parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
                                                                                                                                                                                                                                                                      weight_right = null, weight_left = null,
                                                                                                                                                                                                                                                                          weight_stage2 = null, weight_stage3 = null,
                                                                                                                                                                                                                                                                              weight_right_skipped = false, weight_left_skipped = false,
                                                                                                                                                                                                                                                                                  weight_stage2_skipped = false, weight_stage3_skipped = false,
                                                                                                                                                                                                                                                                                      eso_checked = false, eso_result = null,
                                                                                                                                                                                                                                                                                          legs_sorted = false,
                                                                                                                                                                                                                                                                                              stamped = false,
                                                                                                                                                                                                                                                                                                  parts_print_count = 0,
                                                                                                                                                                                                                                                                                                      updated_at = now();

                                                                                                                                                                                                                                                                                                        update devices_pilot set
                                                                                                                                                                                                                                                                                                            cursor_slaughter = null, cursor_inner = null, cursor_outer = null;

                                                                                                                                                                                                                                                                                                              insert into settings_pilot (id, settings, device_id, updated_at)
                                                                                                                                                                                                                                                                                                                values (1, jsonb_build_object('lastServerResetAt', now()::text), 'server', now())
                                                                                                                                                                                                                                                                                                                  on conflict (id) do update
                                                                                                                                                                                                                                                                                                                      set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('lastServerResetAt', now()::text),
                                                                                                                                                                                                                                                                                                                              updated_at = now();

                                                                                                                                                                                                                                                                                                                                return jsonb_build_object('ok', true);
                                                                                                                                                                                                                                                                                                                                end;
                                                                                                                                                                                                                                                                                                                                $function$
;

drop trigger if exists trg_animals_pilot_advance_cursor on public.animals_pilot; CREATE TRIGGER trg_animals_pilot_advance_cursor AFTER INSERT OR UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION animals_pilot_advance_cursor();

drop trigger if exists trg_animals_pilot_guard_corrections on public.animals_pilot; CREATE TRIGGER trg_animals_pilot_guard_corrections BEFORE UPDATE ON public.animals_pilot FOR EACH ROW EXECUTE FUNCTION animals_pilot_guard_corrections();

drop trigger if exists zz_device_write_guard on public.animals_pilot; CREATE TRIGGER zz_device_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.animals_pilot FOR EACH STATEMENT EXECUTE FUNCTION _device_write_guard();

drop trigger if exists zz_devices_assignment_guard on public.devices_pilot; CREATE TRIGGER zz_devices_assignment_guard BEFORE INSERT OR DELETE OR UPDATE ON public.devices_pilot FOR EACH ROW EXECUTE FUNCTION _devices_assignment_guard();

drop trigger if exists zz_device_write_guard on public.events_pilot; CREATE TRIGGER zz_device_write_guard BEFORE INSERT OR DELETE OR UPDATE ON public.events_pilot FOR EACH STATEMENT EXECUTE FUNCTION _device_write_guard();

alter table public.animals enable row level security;

alter table public.animals_pilot enable row level security;

alter table public.audit_log enable row level security;

alter table public.batches enable row level security;

alter table public.custom_statuses enable row level security;

alter table public.device_credentials enable row level security;

alter table public.device_lifecycle_events enable row level security;

alter table public.device_pairing enable row level security;

alter table public.devices_pilot enable row level security;

alter table public.events_pilot enable row level security;

alter table public.manager_sessions enable row level security;

alter table public.outer_status_pilot enable row level security;

alter table public.plant_managers enable row level security;

alter table public.plants enable row level security;

alter table public.problem_reports enable row level security;

alter table public.profiles enable row level security;

alter table public.reprint_log enable row level security;

alter table public.settings_pilot enable row level security;

alter table public.source_farms enable row level security;

alter table public.system_flags enable row level security;

drop policy if exists "anon insert animals_pilot" on public.animals_pilot; create policy "anon insert animals_pilot" on public.animals_pilot as permissive for insert to public with check (true);

drop policy if exists "anon select animals_pilot" on public.animals_pilot; create policy "anon select animals_pilot" on public.animals_pilot as permissive for select to public using (true);

drop policy if exists "anon update animals_pilot" on public.animals_pilot; create policy "anon update animals_pilot" on public.animals_pilot as permissive for update to public using (true);

drop policy if exists animals_select on public.animals; create policy animals_select on public.animals as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists animals_write on public.animals; create policy animals_write on public.animals as permissive for all to public using ((plant_id = _my_plant())) with check ((plant_id = _my_plant()));

drop policy if exists audit_insert on public.audit_log; create policy audit_insert on public.audit_log as permissive for insert to public with check ((plant_id = _my_plant()));

drop policy if exists audit_select on public.audit_log; create policy audit_select on public.audit_log as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists batches_insert on public.batches; create policy batches_insert on public.batches as permissive for insert to public with check ((plant_id = _my_plant()));

drop policy if exists batches_select on public.batches; create policy batches_select on public.batches as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists batches_update on public.batches; create policy batches_update on public.batches as permissive for update to public using (((plant_id = _my_plant()) AND ((_my_role() = 'manager'::text) OR (status = 'open'::text))));

drop policy if exists statuses_select on public.custom_statuses; create policy statuses_select on public.custom_statuses as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists statuses_write on public.custom_statuses; create policy statuses_write on public.custom_statuses as permissive for all to public using (((plant_id = _my_plant()) AND (_my_role() = 'manager'::text))) with check (((plant_id = _my_plant()) AND (_my_role() = 'manager'::text)));

drop policy if exists "anon insert device_lifecycle_events" on public.device_lifecycle_events; create policy "anon insert device_lifecycle_events" on public.device_lifecycle_events as permissive for insert to public with check (true);

drop policy if exists "anon select device_lifecycle_events" on public.device_lifecycle_events; create policy "anon select device_lifecycle_events" on public.device_lifecycle_events as permissive for select to public using (true);

drop policy if exists "anon insert devices_pilot" on public.devices_pilot; create policy "anon insert devices_pilot" on public.devices_pilot as permissive for insert to public with check (true);

drop policy if exists "anon select devices_pilot" on public.devices_pilot; create policy "anon select devices_pilot" on public.devices_pilot as permissive for select to public using (true);

drop policy if exists "anon update devices_pilot" on public.devices_pilot; create policy "anon update devices_pilot" on public.devices_pilot as permissive for update to public using (true);

drop policy if exists "anon insert events_pilot" on public.events_pilot; create policy "anon insert events_pilot" on public.events_pilot as permissive for insert to public with check (true);

drop policy if exists "anon select events_pilot" on public.events_pilot; create policy "anon select events_pilot" on public.events_pilot as permissive for select to public using (true);

drop policy if exists "anon insert pilot" on public.outer_status_pilot; create policy "anon insert pilot" on public.outer_status_pilot as permissive for insert to public with check (true);

drop policy if exists "anon select pilot" on public.outer_status_pilot; create policy "anon select pilot" on public.outer_status_pilot as permissive for select to public using (true);

drop policy if exists "anon update pilot" on public.outer_status_pilot; create policy "anon update pilot" on public.outer_status_pilot as permissive for update to public using (true);

drop policy if exists plants_select on public.plants; create policy plants_select on public.plants as permissive for select to public using ((id = _my_plant()));

drop policy if exists problems_select on public.problem_reports; create policy problems_select on public.problem_reports as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists problems_write on public.problem_reports; create policy problems_write on public.problem_reports as permissive for all to public using ((plant_id = _my_plant())) with check ((plant_id = _my_plant()));

drop policy if exists profiles_manager_write on public.profiles; create policy profiles_manager_write on public.profiles as permissive for insert to public with check (((_my_role() = 'manager'::text) AND (plant_id = _my_plant())));

drop policy if exists profiles_select on public.profiles; create policy profiles_select on public.profiles as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists profiles_update_self on public.profiles; create policy profiles_update_self on public.profiles as permissive for update to public using ((id = auth.uid()));

drop policy if exists reprint_insert on public.reprint_log; create policy reprint_insert on public.reprint_log as permissive for insert to public with check ((plant_id = _my_plant()));

drop policy if exists reprint_select on public.reprint_log; create policy reprint_select on public.reprint_log as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists "anon insert settings_pilot" on public.settings_pilot; create policy "anon insert settings_pilot" on public.settings_pilot as permissive for insert to public with check (true);

drop policy if exists "anon select settings_pilot" on public.settings_pilot; create policy "anon select settings_pilot" on public.settings_pilot as permissive for select to public using (true);

drop policy if exists "anon update settings_pilot" on public.settings_pilot; create policy "anon update settings_pilot" on public.settings_pilot as permissive for update to public using (true);

drop policy if exists farms_select on public.source_farms; create policy farms_select on public.source_farms as permissive for select to public using ((plant_id = _my_plant()));

drop policy if exists farms_write on public.source_farms; create policy farms_write on public.source_farms as permissive for all to public using (((plant_id = _my_plant()) AND (_my_role() = 'manager'::text))) with check (((plant_id = _my_plant()) AND (_my_role() = 'manager'::text)));

revoke all on public.animals_pilot from anon, authenticated;

revoke all on public.animals from anon, authenticated;

revoke all on public.audit_log from anon, authenticated;

revoke all on public.batches from anon, authenticated;

revoke all on public.custom_statuses from anon, authenticated;

revoke all on public.device_credentials from anon, authenticated;

revoke all on public.device_lifecycle_events from anon, authenticated;

revoke all on public.device_pairing from anon, authenticated;

revoke all on public.devices_pilot from anon, authenticated;

revoke all on public.events_pilot from anon, authenticated;

revoke all on public.manager_sessions from anon, authenticated;

revoke all on public.outer_status_pilot from anon, authenticated;

revoke all on public.plant_managers from anon, authenticated;

revoke all on public.plants from anon, authenticated;

revoke all on public.problem_reports from anon, authenticated;

revoke all on public.profiles from anon, authenticated;

revoke all on public.reprint_log from anon, authenticated;

revoke all on public.settings_pilot from anon, authenticated;

revoke all on public.source_farms from anon, authenticated;

revoke all on public.system_flags from anon, authenticated;

grant SELECT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, INSERT on public.animals_pilot to anon;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.animals_pilot to authenticated;

grant INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.animals_pilot to service_role;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.animals to anon;

grant REFERENCES, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, TRIGGER on public.animals to authenticated;

grant REFERENCES, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, TRIGGER on public.animals to service_role;

grant SELECT, UPDATE, USAGE on sequence public.audit_log_id_seq to anon;

grant SELECT, UPDATE, USAGE on sequence public.audit_log_id_seq to authenticated;

grant SELECT, UPDATE, USAGE on sequence public.audit_log_id_seq to service_role;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.audit_log to anon;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.audit_log to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.audit_log to service_role;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.batches to anon;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.batches to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.batches to service_role;

grant REFERENCES, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, TRIGGER on public.custom_statuses to anon;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.custom_statuses to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.custom_statuses to service_role;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.device_credentials to anon;

grant INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.device_credentials to authenticated;

grant SELECT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, INSERT on public.device_credentials to service_role;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.device_lifecycle_events to anon;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.device_lifecycle_events to authenticated;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.device_lifecycle_events to service_role;

grant INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.device_pairing to anon;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.device_pairing to authenticated;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.device_pairing to service_role;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.devices_pilot to anon;

grant TRUNCATE, INSERT, SELECT, UPDATE, DELETE, REFERENCES, TRIGGER on public.devices_pilot to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.devices_pilot to service_role;

grant SELECT, UPDATE, USAGE on sequence public.events_pilot_server_seq_seq to anon;

grant SELECT, UPDATE, USAGE on sequence public.events_pilot_server_seq_seq to authenticated;

grant SELECT, UPDATE, USAGE on sequence public.events_pilot_server_seq_seq to service_role;

grant TRIGGER, SELECT, UPDATE, DELETE, TRUNCATE, INSERT, REFERENCES on public.events_pilot to anon;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.events_pilot to authenticated;

grant UPDATE, TRIGGER, REFERENCES, TRUNCATE, DELETE, SELECT, INSERT on public.events_pilot to service_role;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.manager_sessions to anon;

grant INSERT, SELECT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE on public.manager_sessions to authenticated;

grant SELECT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, INSERT on public.manager_sessions to service_role;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.outer_status_pilot to anon;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.outer_status_pilot to authenticated;

grant REFERENCES, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, TRIGGER on public.outer_status_pilot to service_role;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.plant_managers to anon;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.plant_managers to authenticated;

grant SELECT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, INSERT on public.plant_managers to service_role;

grant UPDATE, TRIGGER, REFERENCES, TRUNCATE, DELETE, SELECT, INSERT on public.plants to anon;

grant TRIGGER, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, INSERT on public.plants to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.plants to service_role;

grant SELECT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, INSERT on public.problem_reports to anon;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.problem_reports to authenticated;

grant REFERENCES, TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE on public.problem_reports to service_role;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.profiles to anon;

grant INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.profiles to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.profiles to service_role;

grant SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.reprint_log to anon;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.reprint_log to authenticated;

grant REFERENCES, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, TRIGGER on public.reprint_log to service_role;

grant TRUNCATE, TRIGGER, REFERENCES, SELECT on public.settings_pilot to anon;

grant REFERENCES, TRUNCATE, TRIGGER, SELECT on public.settings_pilot to authenticated;

grant DELETE, REFERENCES, TRIGGER, INSERT, SELECT, UPDATE, TRUNCATE on public.settings_pilot to service_role;

grant SELECT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, INSERT on public.source_farms to anon;

grant TRUNCATE, INSERT, SELECT, UPDATE, DELETE, REFERENCES, TRIGGER on public.source_farms to authenticated;

grant TRIGGER, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, INSERT on public.source_farms to service_role;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.system_flags to anon;

grant SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, INSERT, TRIGGER on public.system_flags to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.system_flags to service_role;

revoke all on function public._current_device_id() from public, anon, authenticated; grant execute on function public._current_device_id() to service_role;

revoke all on function public._device_auth_required() from public, anon, authenticated; grant execute on function public._device_auth_required() to service_role;

revoke all on function public._device_write_allowed() from public, anon, authenticated; grant execute on function public._device_write_allowed() to service_role;

revoke all on function public._device_write_guard() from public, anon, authenticated; grant execute on function public._device_write_guard() to authenticated; grant execute on function public._device_write_guard() to anon; grant execute on function public._device_write_guard() to service_role; grant execute on function public._device_write_guard() to public;

revoke all on function public._devices_assignment_guard() from public, anon, authenticated; grant execute on function public._devices_assignment_guard() to authenticated; grant execute on function public._devices_assignment_guard() to anon; grant execute on function public._devices_assignment_guard() to service_role; grant execute on function public._devices_assignment_guard() to public;

revoke all on function public._is_api_request() from public, anon, authenticated; grant execute on function public._is_api_request() to service_role;

revoke all on function public._log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text) from public, anon, authenticated; grant execute on function public._log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text) to service_role;

revoke all on function public._manager_session_valid(p_token text) from public, anon, authenticated; grant execute on function public._manager_session_valid(p_token text) to service_role;

revoke all on function public._my_plant() from public, anon, authenticated; grant execute on function public._my_plant() to authenticated; grant execute on function public._my_plant() to anon; grant execute on function public._my_plant() to service_role; grant execute on function public._my_plant() to public;

revoke all on function public._my_role() from public, anon, authenticated; grant execute on function public._my_role() to authenticated; grant execute on function public._my_role() to anon; grant execute on function public._my_role() to service_role; grant execute on function public._my_role() to public;

revoke all on function public._request_has_manager() from public, anon, authenticated; grant execute on function public._request_has_manager() to service_role;

revoke all on function public._request_headers() from public, anon, authenticated; grant execute on function public._request_headers() to service_role;

revoke all on function public._request_is_service_role() from public, anon, authenticated; grant execute on function public._request_is_service_role() to service_role;

revoke all on function public.animals_pilot_advance_cursor() from public, anon, authenticated; grant execute on function public.animals_pilot_advance_cursor() to authenticated; grant execute on function public.animals_pilot_advance_cursor() to anon; grant execute on function public.animals_pilot_advance_cursor() to service_role; grant execute on function public.animals_pilot_advance_cursor() to public;

revoke all on function public.animals_pilot_guard_corrections() from public, anon, authenticated; grant execute on function public.animals_pilot_guard_corrections() to authenticated; grant execute on function public.animals_pilot_guard_corrections() to anon; grant execute on function public.animals_pilot_guard_corrections() to service_role; grant execute on function public.animals_pilot_guard_corrections() to public;

revoke all on function public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text) from public, anon, authenticated; grant execute on function public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text) to authenticated; grant execute on function public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text) to anon; grant execute on function public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text) to service_role; grant execute on function public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text) to public;

revoke all on function public.create_first_manager(p_name text, p_code text) from public, anon, authenticated; grant execute on function public.create_first_manager(p_name text, p_code text) to authenticated; grant execute on function public.create_first_manager(p_name text, p_code text) to anon; grant execute on function public.create_first_manager(p_name text, p_code text) to service_role; grant execute on function public.create_first_manager(p_name text, p_code text) to public;

revoke all on function public.device_auth_set(p_token text, p_on boolean) from public, anon, authenticated; grant execute on function public.device_auth_set(p_token text, p_on boolean) to authenticated; grant execute on function public.device_auth_set(p_token text, p_on boolean) to anon; grant execute on function public.device_auth_set(p_token text, p_on boolean) to service_role; grant execute on function public.device_auth_set(p_token text, p_on boolean) to public;

revoke all on function public.device_heartbeat(p_device_id text, p_device_name text) from public, anon, authenticated; grant execute on function public.device_heartbeat(p_device_id text, p_device_name text) to authenticated; grant execute on function public.device_heartbeat(p_device_id text, p_device_name text) to anon; grant execute on function public.device_heartbeat(p_device_id text, p_device_name text) to service_role; grant execute on function public.device_heartbeat(p_device_id text, p_device_name text) to public;

revoke all on function public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) from public, anon, authenticated; grant execute on function public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) to authenticated; grant execute on function public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) to anon; grant execute on function public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) to service_role; grant execute on function public.device_manage(p_token text, p_device_id text, p_action text, p_reason text) to public;

revoke all on function public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text) from public, anon, authenticated; grant execute on function public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text) to authenticated; grant execute on function public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text) to anon; grant execute on function public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text) to service_role; grant execute on function public.device_pair(p_token text, p_code text, p_role text, p_index integer, p_replace boolean, p_device_name text) to public;

revoke all on function public.device_paired_list(p_token text) from public, anon, authenticated; grant execute on function public.device_paired_list(p_token text) to authenticated; grant execute on function public.device_paired_list(p_token text) to anon; grant execute on function public.device_paired_list(p_token text) to service_role; grant execute on function public.device_paired_list(p_token text) to public;

revoke all on function public.device_pairing_status(p_device_id text, p_code text, p_secret text) from public, anon, authenticated; grant execute on function public.device_pairing_status(p_device_id text, p_code text, p_secret text) to authenticated; grant execute on function public.device_pairing_status(p_device_id text, p_code text, p_secret text) to anon; grant execute on function public.device_pairing_status(p_device_id text, p_code text, p_secret text) to service_role; grant execute on function public.device_pairing_status(p_device_id text, p_code text, p_secret text) to public;

revoke all on function public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) from public, anon, authenticated; grant execute on function public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) to authenticated; grant execute on function public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) to anon; grant execute on function public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) to service_role; grant execute on function public.device_request_pairing(p_device_id text, p_secret text, p_device_name text) to public;

revoke all on function public.device_unpair(p_token text, p_device_id text, p_reason text) from public, anon, authenticated; grant execute on function public.device_unpair(p_token text, p_device_id text, p_reason text) to authenticated; grant execute on function public.device_unpair(p_token text, p_device_id text, p_reason text) to anon; grant execute on function public.device_unpair(p_token text, p_device_id text, p_reason text) to service_role; grant execute on function public.device_unpair(p_token text, p_device_id text, p_reason text) to public;

revoke all on function public.device_whoami() from public, anon, authenticated; grant execute on function public.device_whoami() to authenticated; grant execute on function public.device_whoami() to anon; grant execute on function public.device_whoami() to service_role; grant execute on function public.device_whoami() to public;

revoke all on function public.manager_add(p_token text, p_name text, p_code text) from public, anon, authenticated; grant execute on function public.manager_add(p_token text, p_name text, p_code text) to authenticated; grant execute on function public.manager_add(p_token text, p_name text, p_code text) to anon; grant execute on function public.manager_add(p_token text, p_name text, p_code text) to service_role; grant execute on function public.manager_add(p_token text, p_name text, p_code text) to public;

revoke all on function public.manager_deactivate(p_token text, p_manager_id uuid) from public, anon, authenticated; grant execute on function public.manager_deactivate(p_token text, p_manager_id uuid) to authenticated; grant execute on function public.manager_deactivate(p_token text, p_manager_id uuid) to anon; grant execute on function public.manager_deactivate(p_token text, p_manager_id uuid) to service_role; grant execute on function public.manager_deactivate(p_token text, p_manager_id uuid) to public;

revoke all on function public.manager_login(p_code text) from public, anon, authenticated; grant execute on function public.manager_login(p_code text) to authenticated; grant execute on function public.manager_login(p_code text) to anon; grant execute on function public.manager_login(p_code text) to service_role; grant execute on function public.manager_login(p_code text) to public;

revoke all on function public.push_settings(p_settings jsonb, p_device_id text, p_token text) from public, anon, authenticated; grant execute on function public.push_settings(p_settings jsonb, p_device_id text, p_token text) to authenticated; grant execute on function public.push_settings(p_settings jsonb, p_device_id text, p_token text) to anon; grant execute on function public.push_settings(p_settings jsonb, p_device_id text, p_token text) to service_role; grant execute on function public.push_settings(p_settings jsonb, p_device_id text, p_token text) to public;

revoke all on function public.reset_daily_board(p_token text) from public, anon, authenticated; grant execute on function public.reset_daily_board(p_token text) to authenticated; grant execute on function public.reset_daily_board(p_token text) to anon; grant execute on function public.reset_daily_board(p_token text) to service_role; grant execute on function public.reset_daily_board(p_token text) to public;

alter table public.animals_pilot replica identity full;

alter table public.device_lifecycle_events replica identity full;

alter table public.devices_pilot replica identity full;

alter table public.events_pilot replica identity full;

alter table public.outer_status_pilot replica identity full;

alter table public.settings_pilot replica identity full;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'animals') then
    alter publication supabase_realtime add table public.animals;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'animals_pilot') then
    alter publication supabase_realtime add table public.animals_pilot;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'audit_log') then
    alter publication supabase_realtime add table public.audit_log;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'batches') then
    alter publication supabase_realtime add table public.batches;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'device_lifecycle_events') then
    alter publication supabase_realtime add table public.device_lifecycle_events;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'devices_pilot') then
    alter publication supabase_realtime add table public.devices_pilot;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'events_pilot') then
    alter publication supabase_realtime add table public.events_pilot;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'outer_status_pilot') then
    alter publication supabase_realtime add table public.outer_status_pilot;
  end if;
end $x$;

do $x$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'settings_pilot') then
    alter publication supabase_realtime add table public.settings_pilot;
  end if;
end $x$;

-- === step16 (applied on top of the cloud export) ===
-- ============================================================================
-- STEP 16: fix animal sync + daily reset
-- ============================================================================
-- 1. Five columns the app sends with every animal were never added to the
--    cloud database. Every animal update sent with them was refused
--    ("Could not find the 'eso_checked' column..."), so animal changes were
--    not reaching the server or the other devices.
-- 2. reset_daily_board (step11) lost the line that tells the "no corrections
--    after moving on" rule that this is a reset, not a correction — so the
--    reset was blocked as soon as any station had worked.
-- Safe to run more than once.
-- ============================================================================

alter table animals_pilot add column if not exists not_chalak_inner boolean default false;
alter table animals_pilot add column if not exists eso_checked boolean default false;
alter table animals_pilot add column if not exists eso_result text;
alter table animals_pilot add column if not exists legs_sorted boolean default false;
alter table animals_pilot add column if not exists parts_print_count integer default 0;

create or replace function reset_daily_board(p_token text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  -- this is the daily reset, not a correction: let the iron-rule trigger through
  perform set_config('gt.reset_in_progress', 'true', true);

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null,
    legs_sorted = false,
    stamped = false,
    parts_print_count = 0,
    updated_at = now();

  update devices_pilot set
    cursor_slaughter = null, cursor_inner = null, cursor_outer = null;

  perform set_config('gt.reset_in_progress', 'false', true);

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('lastServerResetAt', now()::text), 'server', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('lastServerResetAt', now()::text),
        updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function reset_daily_board(text) to authenticated, anon;


-- === step17 + required settings rows (the export carries structure only, not these values) ===
-- ============================================================================
-- STEP 17: only paired devices (or a logged-in manager) may record data — always
-- ============================================================================
-- Removes the "on/off" idea: from now on a device that isn't paired to a
-- station can't write animal data or events, full stop. (In the app such a
-- device only ever shows its pairing code anyway; this also blocks anyone who
-- tries to bypass the app.)
-- Safe to run more than once.
-- ============================================================================

insert into system_flags (key, value) values ('manager_auth_required', true)
  on conflict (key) do update set value = true;
insert into system_flags (key, value) values ('device_auth_required', true)
  on conflict (key) do update set value = true;

-- the manager can no longer switch it off from the app
revoke execute on function device_auth_set(text, boolean) from public, anon, authenticated;


-- === step18 (owner accounts) ===
-- ============================================================================
-- STEP 18: "Owner" accounts — see everything, change nothing
-- ============================================================================
-- An owner logs in from anywhere (another country too) with their own code
-- and sees the manager screen's monitor, summaries, reports and log live.
-- The server itself refuses every change from an owner session: settings,
-- daily reset, pairing, and writing animal data. Only real managers can.
-- Safe to run more than once.
-- ============================================================================

alter table plant_managers add column if not exists role text not null default 'manager';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'plant_managers_role_check') then
    alter table plant_managers add constraint plant_managers_role_check check (role in ('manager','owner'));
  end if;
end $$;

-- A session only counts as "manager" (allowed to change things) for role = manager.
create or replace function _manager_session_valid(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_required boolean;
begin
  select value into v_required from system_flags where key = 'manager_auth_required';
  if coalesce(v_required, false) = false then
    return true;
  end if;
  return exists(
    select 1 from manager_sessions s
    join plant_managers m on m.id = s.manager_id
    where s.token = p_token and s.expires_at > now() and m.active and m.role = 'manager'
  );
end;
$$;

-- same rule for the "manager header" that lets a manager's device write data
create or replace function _request_has_manager() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_tok text;
begin
  v_tok := _request_headers() ->> 'x-manager-token';
  if v_tok is null or v_tok = '' then return false; end if;
  return exists(
    select 1 from manager_sessions s join plant_managers m on m.id = s.manager_id
     where s.token = v_tok and s.expires_at > now() and m.active and m.role = 'manager'
  );
end $$;

-- login now also says whether this is a manager or an owner
create or replace function manager_login(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_manager plant_managers%rowtype;
  v_token text;
  v_expires timestamptz;
begin
  if not exists(select 1 from plant_managers) then
    return jsonb_build_object('ok', false, 'reason', 'no_managers');
  end if;
  select * into v_manager from plant_managers
    where active and code_hash = crypt(p_code, code_hash)
    order by (role = 'manager') desc
    limit 1;
  if v_manager.id is null then
    return jsonb_build_object('ok', false, 'reason', 'wrong_code');
  end if;
  insert into manager_sessions (manager_id) values (v_manager.id)
    returning token, expires_at into v_token, v_expires;
  return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name,
                            'role', v_manager.role, 'expires_at', v_expires);
end;
$$;

create or replace function _code_in_use(p_code text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists(select 1 from plant_managers where active and code_hash = crypt(p_code, code_hash));
$$;

-- Manager → add an owner (view-only) account
create or replace function manager_add_owner(p_token text, p_name text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if coalesce(trim(p_name), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'name required');
  end if;
  if p_code is null or length(p_code) < 4 then
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'owner')
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Manager → list of manager and owner accounts (never the codes)
create or replace function manager_list(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'accounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', role, 'active', active, 'created_at', created_at)
                     order by role, created_at)
    from plant_managers where active), '[]'::jsonb));
end $$;

-- Manager → remove an account (never the last manager)
create or replace function manager_deactivate(p_token text, p_manager_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_role text;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select role into v_role from plant_managers where id = p_manager_id;
  if v_role = 'manager' and (select count(*) from plant_managers where active and role = 'manager') <= 1 then
    return jsonb_build_object('ok', false, 'error', 'last_manager');
  end if;
  update plant_managers set active = false where id = p_manager_id;
  delete from manager_sessions where manager_id = p_manager_id;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function _manager_session_valid(text) from public, anon, authenticated;
revoke execute on function _request_has_manager()       from public, anon, authenticated;
revoke execute on function _code_in_use(text)           from public, anon, authenticated;
grant execute on function manager_login(text)                    to anon, authenticated;
grant execute on function manager_add_owner(text, text, text)    to anon, authenticated;
grant execute on function manager_list(text)                     to anon, authenticated;
grant execute on function manager_deactivate(text, uuid)         to anon, authenticated;


-- === step19 (server-side event chain) ===
-- ============================================================================
-- STEP 19: the event log is chained by the SERVER, not by each device
-- ============================================================================
-- Until now every device linked each new event to the last event IT had
-- written (kept in that device's own memory). With more than one device the
-- log was therefore several separate chains mixed together, and the health
-- check — which expects one chain — reported "broken" the moment a second
-- device wrote anything. That was a false alarm, not tampering.
--
-- From now on the server links every event, in order, to the event before it
-- (one chain for the whole plant), computes the fingerprint itself, and checks
-- the chain itself (verify_event_chain). A device can no longer supply its own
-- fingerprint. Deleting, changing or removing an event from the middle breaks
-- the chain and is reported with the exact event number.
--
-- Events written before this step stay as they are and are reported as
-- "older, not verified". Safe to run more than once.
-- ============================================================================

alter table events_pilot add column if not exists server_chained boolean not null default false;
alter table events_pilot add column if not exists chain_pos bigint;
create unique index if not exists events_pilot_chain_pos_key on events_pilot(chain_pos) where chain_pos is not null;

-- the exact text that gets fingerprinted (same function writes and verifies)
create or replace function _event_canonical(p_event_id uuid, p_animal_no integer, p_stage text, p_action text,
                                            p_payload jsonb, p_actor text, p_device_id text, p_occurred_at text,
                                            p_prev_hash text, p_chain_pos bigint)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select concat_ws('|', p_chain_pos::text, p_event_id::text, coalesce(p_animal_no::text, ''), p_stage, p_action,
                   coalesce(p_payload::text, ''), coalesce(p_actor, ''), coalesce(p_device_id, ''),
                   coalesce(p_occurred_at, ''), coalesce(p_prev_hash, ''));
$$;

create or replace function _events_chain_link() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_prev text; v_pos bigint;
begin
  -- one writer at a time, so the chain has exactly one order
  perform pg_advisory_xact_lock(hashtext('glatttrack_events_chain'));
  select event_hash, chain_pos into v_prev, v_pos
    from events_pilot where server_chained order by chain_pos desc limit 1;
  new.server_chained := true;
  new.chain_pos := coalesce(v_pos, 0) + 1;
  new.prev_hash := v_prev;                       -- whatever the device sent is ignored
  new.event_hash := encode(digest(_event_canonical(new.event_id, new.animal_no, new.stage, new.action,
                              new.payload, new.actor, new.device_id, new.occurred_at,
                              new.prev_hash, new.chain_pos), 'sha256'), 'hex');
  return new;
end $$;

drop trigger if exists aa_events_chain_link on events_pilot;
create trigger aa_events_chain_link before insert on events_pilot
  for each row execute function _events_chain_link();

-- events can never be changed or removed once written (even by a manager)
create or replace function _events_append_only() returns trigger
language plpgsql as $$
begin
  if current_setting('request.headers', true) is null then  -- SQL editor / maintenance
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  raise exception 'יומן האירועים הוא לקריאה ולהוספה בלבד (append_only)' using errcode = '42501';
end $$;
drop trigger if exists ab_events_append_only on events_pilot;
create trigger ab_events_append_only before update or delete on events_pilot
  for each row execute function _events_append_only();

-- Anyone may check the chain (read-only).
create or replace function verify_event_chain()
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare r events_pilot%rowtype; v_prev text := null; n bigint := 0; v_legacy bigint;
begin
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

revoke execute on function _events_chain_link() from public, anon, authenticated;
grant execute on function verify_event_chain() to anon, authenticated;


-- === step20 ===
-- ============================================================================
-- STEP 20: fix "UPDATE requires a WHERE clause" in the daily reset
-- ============================================================================
-- The Supabase cloud refuses any UPDATE that has no WHERE at all (a safety
-- guard against wiping a whole table by mistake). The daily reset clears the
-- whole board on purpose, so it now says so explicitly with "where true".
-- Safe to run more than once.
-- ============================================================================

create or replace function reset_daily_board(p_token text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  -- this is the daily reset, not a correction: let the iron-rule trigger through
  perform set_config('gt.reset_in_progress', 'true', true);

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null,
    legs_sorted = false,
    stamped = false,
    parts_print_count = 0,
    updated_at = now()
  where true;   -- Supabase refuses an UPDATE with no WHERE at all

  update devices_pilot set
    cursor_slaughter = null, cursor_inner = null, cursor_outer = null
  where true;

  perform set_config('gt.reset_in_progress', 'false', true);

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('lastServerResetAt', now()::text), 'server', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('lastServerResetAt', now()::text),
        updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function reset_daily_board(text) to authenticated, anon;


-- === step21 ===
-- ============================================================================
-- STEP 21: logging out really ends the session on the server
-- ============================================================================
-- Until now "log out" only forgot the session on the device; the session
-- itself stayed valid on the server until it expired (12 hours). Now logout
-- deletes it, so that token can never be used again.
-- Safe to run more than once.
-- ============================================================================

create or replace function manager_logout(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  delete from manager_sessions where token = p_token;
  return jsonb_build_object('ok', true);
end $$;

-- expired sessions are cleaned up whenever someone logs in
create or replace function _manager_sessions_cleanup() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  delete from manager_sessions where expires_at < now() - interval '1 day';
  return null;
end $$;
drop trigger if exists zz_manager_sessions_cleanup on manager_sessions;
create trigger zz_manager_sessions_cleanup after insert on manager_sessions
  for each statement execute function _manager_sessions_cleanup();

-- the daily reset checks the team leader itself, so it never depends on the device header
create or replace function reset_daily_board(p_token text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  -- this is the daily reset, not a correction: let the iron-rule trigger through
  perform set_config('gt.reset_in_progress', 'true', true);
  -- the team leader was verified just above; don't also demand the device header
  perform set_config('app.device_admin', 'on', true);

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null,
    legs_sorted = false,
    stamped = false,
    parts_print_count = 0,
    updated_at = now()
  where true;   -- Supabase refuses an UPDATE with no WHERE at all

  update devices_pilot set
    cursor_slaughter = null, cursor_inner = null, cursor_outer = null
  where true;

  perform set_config('gt.reset_in_progress', 'false', true);
  perform set_config('app.device_admin', '', true);

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('lastServerResetAt', now()::text), 'server', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('lastServerResetAt', now()::text),
        updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function reset_daily_board(text) to authenticated, anon;
grant execute on function manager_logout(text) to anon, authenticated;
revoke execute on function _manager_sessions_cleanup() from public, anon, authenticated;


-- === step22 (server-side daily rollover) ===
-- ============================================================================
-- STEP 22: the SERVER changes the day — one decision for the whole plant
-- ============================================================================
-- Before: every device decided on its own, at the reset hour, to start a new
-- day. A station tablet could clear its board while the server (and other
-- stations) still had yesterday — two different "days" at once.
--
-- Now:
--  • request_daily_rollover() — any device may ask; the SERVER checks the
--    plant's reset time in the plant's time zone and clears the board exactly
--    once per day. The first request does it, the rest get "already done".
--    Every device then clears its own screen only when the server tells it to.
--  • If pg_cron is available, the server also runs it by itself every minute,
--    so the day changes even if no device happens to be switched on.
--  • Before clearing, the whole board is archived IN THE SERVER
--    (daily_board_archive) — a server-side copy of every day, for any device.
--  • The first time this runs it only records "today" — it never clears a
--    board in the middle of a working day.
--  • push_settings can no longer overwrite the server's own reset markers with
--    an old copy from a device, and plantTimezone is a team-leader setting.
-- Safe to run more than once.
-- ============================================================================

-- ── server-owned state (not part of the settings devices send back) ──
create table if not exists plant_state (
  key text primary key,
  value text,
  updated_at timestamptz not null default now()
);
alter table plant_state enable row level security;          -- no policies: only the functions below
revoke all on plant_state from anon, authenticated;

-- ── server-side archive of each day's board ──
create table if not exists daily_board_archive (
  id bigint generated always as identity primary key,
  business_date date,
  reason text not null,
  archived_at timestamptz not null default now(),
  animals_count integer,
  board jsonb not null
);
alter table daily_board_archive enable row level security;
drop policy if exists "read daily_board_archive" on daily_board_archive;
create policy "read daily_board_archive" on daily_board_archive for select to anon, authenticated using (true);
revoke all on daily_board_archive from anon, authenticated;
grant select on daily_board_archive to anon, authenticated;

-- ── the one place that clears the board ──
create or replace function _do_board_reset(p_reason text, p_business_date date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  -- 1. keep a copy on the server
  insert into daily_board_archive (business_date, reason, animals_count, board)
  select p_business_date, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb)
    from animals_pilot a;

  -- 2. clear (this is the reset, not a correction; verified by the caller)
  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null,
    legs_sorted = false,
    stamped = false,
    parts_print_count = 0,
    updated_at = now()
  where true;   -- Supabase refuses an UPDATE with no WHERE at all

  update devices_pilot set cursor_slaughter = null, cursor_inner = null, cursor_outer = null
  where true;

  perform set_config('gt.reset_in_progress', 'false', true);
  perform set_config('app.device_admin', '', true);

  -- 3. tell every device (they clear their screens when they see this)
  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason), 'server', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb)
                   || jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason),
        updated_at = now();
end $$;

-- ── manual reset by a team leader ──
create or replace function reset_daily_board(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('glatttrack_daily_rollover'));
  perform _do_board_reset('manual', null);
  return jsonb_build_object('ok', true);
end $$;

-- ── automatic day change, decided by the server ──
create or replace function request_daily_rollover()
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s jsonb; tz text; rt time; local_now timestamp; today date; last_date text;
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
    -- first run ever: just remember today, never clear a board mid-day
    insert into plant_state (key, value) values ('lastRolloverDate', today::text)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    return jsonb_build_object('ok', true, 'done', false, 'status', 'initialized', 'plantDate', today, 'timezone', tz);
  end if;
  if last_date = today::text then
    return jsonb_build_object('ok', true, 'done', false, 'status', 'already', 'plantDate', today, 'timezone', tz);
  end if;
  if local_now::time < rt then
    return jsonb_build_object('ok', true, 'done', false, 'status', 'not_yet', 'plantDate', today, 'timezone', tz, 'resetTime', rt);
  end if;

  perform _do_board_reset('daily-rollover', today - 1);
  update plant_state set value = today::text, updated_at = now() where key = 'lastRolloverDate';
  return jsonb_build_object('ok', true, 'done', true, 'status', 'rolled_over', 'plantDate', today, 'timezone', tz);
end $$;

-- ── push_settings: plantTimezone is a team-leader setting, and the server's
--    own markers are never taken from a device's (possibly old) copy ──
create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  admin_keys text[] := array[
    'weightControl','customStatuses','disabledStatuses','autoResetTime',
    'users','license','loginModeByRole','stickerSize','customSeals',
    'notChalakEnabled','legsSortEnabled','weightMethods','dailyTarget',
    'installationCode','plantTimezone'
  ];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason'];
  cur jsonb;
  k text;
  is_manager boolean := false;
begin
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
  end if;

  select settings into cur from settings_pilot where id = 1;

  if not is_manager then
    foreach k in array admin_keys loop
      if (cur -> k) is distinct from (p_settings -> k) then
        return jsonb_build_object('ok', false, 'error', 'unauthorized: this setting requires manager login', 'key', k);
      end if;
    end loop;
  end if;

  -- keep the server's values for the server-owned keys
  foreach k in array server_keys loop
    if cur ? k then
      p_settings := p_settings || jsonb_build_object(k, cur -> k);
    else
      p_settings := p_settings - k;
    end if;
  end loop;

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, p_settings, p_device_id, now())
  on conflict (id) do update
    set settings = excluded.settings, device_id = excluded.device_id, updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true);
end $$;

revoke execute on function _do_board_reset(text, date) from public, anon, authenticated;
grant execute on function reset_daily_board(text)            to anon, authenticated;
grant execute on function request_daily_rollover()           to anon, authenticated;
grant execute on function push_settings(jsonb, text, text)   to anon, authenticated;

-- ── let the server run the day change by itself (if pg_cron exists) ──
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron is not available here (%). Devices will trigger the day change instead.', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'glatttrack-daily-rollover';
    perform cron.schedule('glatttrack-daily-rollover', '* * * * *', 'select public.request_daily_rollover()');
    raise notice 'Server day-change job scheduled (every minute).';
  end if;
exception when others then
  raise notice 'Could not schedule the server job (%). Devices will trigger the day change instead.', sqlerrm;
end $$;

-- ============================================================================
-- STEP 23: plant settings — a station can change only what a station needs
-- ============================================================================
-- Before: push_settings protected a fixed list of "manager" settings
-- (users, license, weightControl, ...). Everything NOT on that list — price per
-- kg (billing), which screens are on, cattle/part types, farm names, archive,
-- daily intake, beeps — could be changed by any paired station tablet, or by
-- anyone holding a station's key who called the server directly.
--
-- Now it is the other way round (deny by default):
--  • A station (no team-leader login) may change ONLY: who is logged in,
--    reprint log, problem reports, printer/scanner connection state, and
--    dismissing the licence reminder. Anything else it sends is IGNORED —
--    the server keeps its own value and tells the device which keys it
--    ignored, so the device re-syncs. An old copy on a tablet can therefore
--    no longer overwrite a team leader's newer change either.
--  • A team leader (role = manager) may change everything, except the
--    server's own reset markers.
--  • An owner session counts as a station here: view only.
--  • Settings are MERGED, never replaced: a device running an older app that
--    doesn't know a key (e.g. plantTimezone) can't wipe it.
--  • The server's daily reset now also clears the day's intake list and the
--    list of logged-in workers, in the server copy.
-- Safe to run more than once.
-- ============================================================================

create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason'];
  cur jsonb;
  incoming jsonb;
  k text;
  ignored text[] := '{}';
  is_manager boolean := false;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
  end if;

  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  select coalesce(settings, '{}'::jsonb) into cur from settings_pilot where id = 1;
  cur := coalesce(cur, '{}'::jsonb);

  incoming := p_settings;
  -- the server's own keys are never taken from a device
  foreach k in array server_keys loop
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

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, p_device_id, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;

-- the server's reset also starts the day's lists fresh (server copy)
create or replace function _do_board_reset(p_reason text, p_business_date date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  insert into daily_board_archive (business_date, reason, animals_count, board)
  select p_business_date, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb)
    from animals_pilot a;

  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null,
    legs_sorted = false,
    stamped = false,
    parts_print_count = 0,
    updated_at = now()
  where true;

  update devices_pilot set cursor_slaughter = null, cursor_inner = null, cursor_outer = null
  where true;

  perform set_config('gt.reset_in_progress', 'false', true);
  perform set_config('app.device_admin', '', true);

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason,
                                'dailyIntake', '[]'::jsonb, 'activeUserByRole', '{}'::jsonb), 'server', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb)
                   || jsonb_build_object('lastServerResetAt', now()::text, 'lastServerResetReason', p_reason,
                                         'dailyIntake', '[]'::jsonb, 'activeUserByRole', '{}'::jsonb),
        device_id = 'server',
        updated_at = now();
end $$;

revoke execute on function _do_board_reset(text, date) from public, anon, authenticated;
grant execute on function push_settings(jsonb, text, text) to anon, authenticated;

-- ============================================================================
-- STEP 24: price per weight — set by the MANUFACTURER only
-- ============================================================================
--  • New account type "manufacturer". It is created ONLY from here (the SQL
--    Editor), never from the app, so nobody at the plant can create one.
--  • Only a manufacturer session can change billing (on/off, price per kg,
--    currency) — through manufacturer_set_billing(). Nobody else can: not a
--    station, not an owner, not a team leader, and not by sending settings
--    directly (push_settings now always keeps the server's billing).
--  • A manufacturer session is NOT a team leader: it can't change plant
--    settings, pair devices, reset the day or write animal data.
--  • Team leaders can't see, remove or reuse the manufacturer's code.
--  • The first-team-leader setup still works when a manufacturer account
--    already exists.
-- Safe to run more than once.
--
-- ▶ After running this file, set YOUR manufacturer code (keep it private):
--      select manufacturer_set_code('Manufacturer', 'YOUR-SECRET-CODE');
--   Running it again replaces the code (the old one stops working at once).
-- ============================================================================

alter table plant_managers drop constraint if exists plant_managers_role_check;
alter table plant_managers add constraint plant_managers_role_check
  check (role in ('manager','owner','manufacturer'));

-- ── create / replace the manufacturer account (SQL Editor only) ──
create or replace function manufacturer_set_code(p_name text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
revoke execute on function manufacturer_set_code(text, text) from public, anon, authenticated;

create or replace function _manufacturer_session_valid(p_token text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select exists(select 1 from manager_sessions s join plant_managers m on m.id = s.manager_id
                 where s.token = p_token and s.expires_at > now() and m.active and m.role = 'manufacturer');
$$;
revoke execute on function _manufacturer_session_valid(text) from public, anon, authenticated;

-- ── the only way to change billing ──
create or replace function manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
  v_billing := jsonb_build_object('enabled', coalesce(p_enabled, false), 'price', round(p_price, 4),
                                  'currency', p_currency, 'updatedAt', now()::text);
  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('billing', v_billing), 'manufacturer', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('billing', v_billing),
        device_id = 'manufacturer', updated_at = now();
  return jsonb_build_object('ok', true, 'billing', v_billing);
end $$;
grant execute on function manufacturer_set_billing(text, boolean, numeric, text) to anon, authenticated;

-- ── push_settings: billing is never taken from any device (see step23) ──
create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason','billing'];
  cur jsonb;
  incoming jsonb;
  k text;
  ignored text[] := '{}';
  is_manager boolean := false;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
  end if;

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

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, p_device_id, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;

-- ── first team leader: a manufacturer account doesn't count ──
create or replace function create_first_manager(p_name text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('glatttrack_first_manager'));
  if exists(select 1 from plant_managers where role = 'manager' and active) then
    return jsonb_build_object('ok', false, 'error', 'a manager already exists — use manager_add instead');
  end if;
  if p_code is null or length(p_code) < 4 then
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'manager')
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function manager_login(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_manager plant_managers%rowtype;
  v_token text;
  v_expires timestamptz;
begin
  select * into v_manager from plant_managers
    where active and code_hash = crypt(p_code, code_hash)
    order by (role = 'manager') desc
    limit 1;
  if v_manager.id is null then
    if not exists(select 1 from plant_managers where role = 'manager' and active) then
      return jsonb_build_object('ok', false, 'reason', 'no_managers');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'wrong_code');
  end if;
  insert into manager_sessions (manager_id) values (v_manager.id)
    returning token, expires_at into v_token, v_expires;
  return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name,
                            'role', v_manager.role, 'expires_at', v_expires);
end $$;

-- adding another team leader: code must be unique too
create or replace function manager_add(p_token text, p_name text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_code is null or length(p_code) < 4 then
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'manager')
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- the plant's account list never shows the manufacturer
create or replace function manager_list(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'accounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', role, 'active', active, 'created_at', created_at)
                     order by role, created_at)
    from plant_managers where active and role <> 'manufacturer'), '[]'::jsonb));
end $$;

-- ...and a team leader can't remove it
create or replace function manager_deactivate(p_token text, p_manager_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_role text;
begin
  if not _manager_session_valid(p_token) then
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

grant execute on function push_settings(jsonb, text, text)   to anon, authenticated;
grant execute on function create_first_manager(text, text)   to anon, authenticated;
grant execute on function manager_login(text)                to anon, authenticated;
grant execute on function manager_add(text, text, text)      to anon, authenticated;
grant execute on function manager_list(text)                 to anon, authenticated;
grant execute on function manager_deactivate(text, uuid)     to anon, authenticated;

-- ============================================================================
-- STEP 25: the manufacturer can do everything a team leader can — from anywhere
-- ============================================================================
-- A manufacturer session now counts as a team leader on the server:
-- settings, pairing/unpairing devices, owners, day reset, corrections,
-- everything. On top of that it is still the ONLY one who can change billing
-- (manufacturer_set_billing, step24). It stays hidden from the plant's
-- account list and a team leader can't remove it.
-- Safe to run more than once.
-- ============================================================================

create or replace function _manager_session_valid(p_token text)
returns boolean language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_required boolean;
begin
  select value into v_required from system_flags where key = 'manager_auth_required';
  if coalesce(v_required, false) = false then
    return true;
  end if;
  return exists(
    select 1 from manager_sessions s
    join plant_managers m on m.id = s.manager_id
    where s.token = p_token and s.expires_at > now() and m.active
      and m.role in ('manager','manufacturer')
  );
end $$;

create or replace function _request_has_manager() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_tok text;
begin
  v_tok := _request_headers() ->> 'x-manager-token';
  if v_tok is null or v_tok = '' then return false; end if;
  return exists(
    select 1 from manager_sessions s join plant_managers m on m.id = s.manager_id
     where s.token = v_tok and s.expires_at > now() and m.active
       and m.role in ('manager','manufacturer')
  );
end $$;

revoke execute on function _manager_session_valid(text) from public, anon, authenticated;
revoke execute on function _request_has_manager()       from public, anon, authenticated;

-- ============================================================================
-- STEP 26: the manufacturer never touches kashrut records
-- ============================================================================
-- The manufacturer keeps everything from step25 (settings, devices, owners,
-- reports, billing) but can NOT:
--   • record or change any animal data (slaughter, inspections, statuses,
--     weights, stickers, stamps) — not from any screen and not by calling
--     the server directly;
--   • write events about an animal into the event log;
--   • clear the day's board by hand (the automatic day change still runs).
-- Only people at the plant (paired stations and team leaders) can.
-- Safe to run more than once.
-- ============================================================================

-- role of a session token (null if not valid)
create or replace function _session_role(p_token text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select m.role from manager_sessions s join plant_managers m on m.id = s.manager_id
   where s.token = p_token and s.expires_at > now() and m.active limit 1;
$$;
revoke execute on function _session_role(text) from public, anon, authenticated;

-- the "team leader header" that lets a device write animal data: team leaders only
create or replace function _request_has_manager() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_tok text;
begin
  v_tok := _request_headers() ->> 'x-manager-token';
  if v_tok is null or v_tok = '' then return false; end if;
  return coalesce(_session_role(v_tok), '') = 'manager';
end $$;

create or replace function _request_has_manufacturer() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_tok text;
begin
  v_tok := _request_headers() ->> 'x-manager-token';
  if v_tok is null or v_tok = '' then return false; end if;
  return coalesce(_session_role(v_tok), '') = 'manufacturer';
end $$;
revoke execute on function _request_has_manager()      from public, anon, authenticated;
revoke execute on function _request_has_manufacturer() from public, anon, authenticated;

-- statement guard: the manufacturer may add to the event log (its own
-- actions: settings, devices, ...), never write animal data
create or replace function _device_write_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if _device_write_allowed() then return null; end if;
  if tg_table_name = 'events_pilot' and tg_op = 'INSERT' and _request_has_manufacturer() then
    return null;   -- each row is checked by _events_maker_guard below
  end if;
  raise exception 'המכשיר אינו מצומד לתחנה — יש לצמד אותו במסך ראש הצוות (device_not_paired)'
    using errcode = '42501';
end $$;

create or replace function _events_maker_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if _device_write_allowed() then return new; end if;        -- station / team leader / server
  if _request_has_manufacturer() then
    if new.animal_no is not null then
      raise exception 'היצרן לא רושם אירועים על בהמות (manufacturer_no_kashrut)' using errcode = '42501';
    end if;
    return new;
  end if;
  return new;   -- anything else was already stopped by the statement guard
end $$;
drop trigger if exists a0_events_maker_guard on events_pilot;
create trigger a0_events_maker_guard before insert on events_pilot
  for each row execute function _events_maker_guard();

-- manual board reset: team leaders at the plant only
create or replace function reset_daily_board(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) or coalesce(_session_role(p_token), 'manager') = 'manufacturer' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('glatttrack_daily_rollover'));
  perform _do_board_reset('manual', null);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function reset_daily_board(text) to anon, authenticated;

-- ============================================================================
-- STEP 27: technical support tools (for the manufacturer, also from afar)
-- ============================================================================
--  • support_diagnostics(token): one read-only snapshot of the plant's health —
--    server time and plant time zone, day change status, automatic job,
--    every device (last seen, app version, which screen it is on), event log
--    check, sessions, database size, schema step.
--  • support_force_reload(token): every tablet reloads the app within seconds
--    (after an update, or when a screen is stuck). Nothing is lost — each
--    tablet keeps its data locally and syncs after reloading.
--  • device_heartbeat now also reports the app version and current screen.
-- Only a team leader or the manufacturer can use these. They never touch
-- animal data.
-- Safe to run more than once.
-- ============================================================================

alter table devices_pilot add column if not exists app_info jsonb;

create or replace function device_heartbeat(p_device_id text, p_device_name text, p_info jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_info jsonb;
begin
  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then return jsonb_build_object('ok', false); end if;
  v_info := case when jsonb_typeof(p_info) = 'object' and length(p_info::text) < 2000 then p_info else null end;
  insert into devices_pilot (id, device_name, last_seen, app_info) values (p_device_id, left(p_device_name, 60), now(), v_info)
    on conflict (id) do update set last_seen = now(), app_info = coalesce(excluded.app_info, devices_pilot.app_info),
      device_name = coalesce(devices_pilot.device_name, excluded.device_name);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function device_heartbeat(text, text, jsonb) to anon, authenticated;

create or replace function support_diagnostics(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s jsonb; tz text; v_cron text := 'not available'; v_chain jsonb;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
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
    'dbSize', pg_size_pretty(pg_database_size(current_database())),
    'schemaStep', (select value from plant_state where key = 'schemaStep'),
    'lastForceReloadAt', s ->> 'forceReloadAt'
  );
end $$;
grant execute on function support_diagnostics(text) to anon, authenticated;

create or replace function support_force_reload(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  update settings_pilot
     set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('forceReloadAt', now()::text),
         device_id = 'support', updated_at = now()
   where id = 1;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function support_force_reload(text) to anon, authenticated;

-- push_settings: forceReloadAt is a server marker too (same as step24 otherwise)
create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason','billing','forceReloadAt'];
  cur jsonb;
  incoming jsonb;
  k text;
  ignored text[] := '{}';
  is_manager boolean := false;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
  end if;

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

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, p_device_id, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;
grant execute on function push_settings(jsonb, text, text) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '27')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ============================================================================
-- STEP 28: an esophagus "nevela" really becomes nevela — on the server too
-- ============================================================================
-- Found in the full workday test:
--  • The server only turned slaughter into "nevela" when slaughter was empty,
--    which never happens (the animal is always slaughtered first). So an
--    esophagus failure stayed "slaughtered" on the server and on every other
--    device — the animal could continue as kosher elsewhere.
--  • A correction from the esophagus screen was blocked by the "already moved
--    on" rule and never reached the server.
-- Now:
--  • claim_animal_stage('eso', 'nevela') sets slaughter = nevela (with a new
--    time, so every device takes it) and remembers what it was before.
--  • eso_change(): the esophagus screen can correct its own result
--    (ok → nevela, or back to ok restoring the previous slaughter status).
--    Only the esophagus check can undo an esophagus nevela.
--  • The slaughter screen can't overwrite an esophagus nevela.
-- Safe to run more than once.
-- ============================================================================

alter table animals_pilot add column if not exists eso_prev_slaughter text;

-- the "already moved on" rule lets the esophagus ruling through (and only it)
create or replace function animals_pilot_guard_corrections() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d record;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;

  -- an esophagus nevela can only be changed by the esophagus ruling itself
  if old.eso_result = 'nevela' and new.slaughter is distinct from old.slaughter
     and coalesce(current_setting('gt.eso_ruling', true), '') <> 'true' then
    raise exception 'correction-blocked: failed the esophagus check — only the esophagus screen can change it';
  end if;

  if old.slaughter is not null and new.slaughter is distinct from old.slaughter
     and coalesce(current_setting('gt.eso_ruling', true), '') <> 'true' then
    select cursor_slaughter into d from public.devices_pilot where id = new.device_id;
    if d.cursor_slaughter is distinct from new.id then
      raise exception 'correction-blocked: already moved on — slaughter status is locked';
    end if;
  end if;

  if old.inner_status is not null and old.inner_status is distinct from 'in_progress' and new.inner_status is distinct from old.inner_status then
    select cursor_inner into d from public.devices_pilot where id = new.device_id;
    if d.cursor_inner is distinct from new.id then
      raise exception 'correction-blocked: already moved on — inner status is locked';
    end if;
  end if;

  if old.outer_status is not null and new.outer_status is distinct from old.outer_status then
    select cursor_outer into d from public.devices_pilot where id = new.device_id;
    if d.cursor_outer is distinct from new.id then
      raise exception 'correction-blocked: already moved on — outer status is locked';
    end if;
  end if;

  return new;
end $$;

create or replace function claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_rows integer;
  v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_row jsonb;
begin
  if p_stage = 'slaughter' then
    update animals_pilot
       set slaughter = p_value, slaughtered_by = p_actor, slaughter_time = v_now_ms,
           slaughter_by_device = p_device_id, updated_at = now()
     where id = p_id and slaughter is null;

  elsif p_stage = 'inner' then
    update animals_pilot
       set inner_status = p_value, inner_by = p_actor, inner_time = v_now_ms,
           inner_by_device = p_device_id, updated_at = now()
     where id = p_id and (inner_status is null or inner_status = 'in_progress');

  elsif p_stage = 'outer' then
    update animals_pilot
       set outer_status = p_value, outer_by = p_actor, outer_time = v_now_ms,
           outer_by_device = p_device_id, updated_at = now()
     where id = p_id and outer_status is null;

  elsif p_stage = 'eso' then
    if p_value not in ('ok','nevela') then
      raise exception 'claim_animal_stage: bad esophagus result %', p_value;
    end if;
    perform set_config('gt.eso_ruling', 'true', true);
    update animals_pilot
       set eso_checked = true,
           eso_result = p_value,
           eso_prev_slaughter = case when p_value = 'nevela' then slaughter else eso_prev_slaughter end,
           slaughter = case when p_value = 'nevela' then 'nevela' else slaughter end,
           slaughter_time = case when p_value = 'nevela' then v_now_ms else slaughter_time end,
           slaughter_by_device = case when p_value = 'nevela' then p_device_id else slaughter_by_device end,
           updated_at = now()
     where id = p_id and (eso_checked is distinct from true);
    perform set_config('gt.eso_ruling', '', true);

  elsif p_stage = 'legs' then
    update animals_pilot set legs_sorted = true, updated_at = now()
     where id = p_id and (legs_sorted is distinct from true);

  elsif p_stage = 'stamped' then
    update animals_pilot set stamped = true, updated_at = now()
     where id = p_id and (stamped is distinct from true);

  else
    raise exception 'claim_animal_stage: unknown stage %', p_stage;
  end if;

  get diagnostics v_rows = row_count;
  select to_jsonb(a.*) into v_row from animals_pilot a where a.id = p_id;
  return jsonb_build_object('claimed', v_rows = 1, 'row', v_row);
end $$;
grant execute on function claim_animal_stage(integer, text, text, text, text) to anon, authenticated;

-- correction from the esophagus screen
create or replace function eso_change(p_id integer, p_result text, p_device_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  a animals_pilot%rowtype;
  v_row jsonb;
begin
  if p_result not in ('ok','nevela') then
    return jsonb_build_object('ok', false, 'error', 'bad_result');
  end if;
  select * into a from animals_pilot where id = p_id for update;
  if a.id is null or a.eso_checked is distinct from true then
    return jsonb_build_object('ok', false, 'error', 'not_checked');
  end if;
  if a.eso_result = p_result then
    select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
    return jsonb_build_object('ok', true, 'row', v_row);
  end if;
  perform set_config('gt.eso_ruling', 'true', true);
  if p_result = 'nevela' then
    update animals_pilot
       set eso_result = 'nevela', eso_prev_slaughter = slaughter, slaughter = 'nevela',
           slaughter_time = v_now_ms, slaughter_by_device = p_device_id, updated_at = now()
     where id = p_id;
  else
    update animals_pilot
       set eso_result = 'ok', slaughter = coalesce(eso_prev_slaughter, 'slaughtered'),
           slaughter_time = v_now_ms, slaughter_by_device = p_device_id, updated_at = now()
     where id = p_id;
  end if;
  perform set_config('gt.eso_ruling', '', true);
  select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
  return jsonb_build_object('ok', true, 'row', v_row);
end $$;
grant execute on function eso_change(integer, text, text) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '28')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ============================================================================
-- STEP 29: a device with an old copy can never erase newer data on the server
-- ============================================================================
-- Each device sends the WHOLE animal record when it changes something. If
-- that device had not yet received the latest changes from other stations
-- (slow Wi-Fi, just came back online), its record still had empty or older
-- values for the other stations' fields — and sending it could erase a
-- weight, a maw/rumen result, stickers or the esophagus result another
-- station had already recorded, or be rejected as a "correction" so the
-- device's own new work was lost.
--
-- Now the server merges every incoming record field by field, with the same
-- rules the devices use:
--   • slaughter / inner / outer status: the NEWER time wins (an older copy
--     can't overwrite, a deliberate newer change can);
--   • yes/no marks (stickers, stamped, weighed-skipped…): once yes, stays yes;
--   • recorded values (weights, maw, rumen): an empty value never erases one;
--   • printed-sticker count: the highest wins;
--   • esophagus result follows the slaughter time.
-- The daily reset (and only it) still clears everything.
-- Safe to run more than once.
-- ============================================================================

create or replace function _animals_merge() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;

  -- timed groups: keep the server's values when the incoming copy is older
  if old.slaughter_time is not null and (new.slaughter_time is null or new.slaughter_time < old.slaughter_time) then
    new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
    new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
    new.eso_result := coalesce(old.eso_result, new.eso_result);
    new.eso_prev_slaughter := coalesce(old.eso_prev_slaughter, new.eso_prev_slaughter);
  end if;
  if old.inner_time is not null and (new.inner_time is null or new.inner_time < old.inner_time) then
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
  end if;
  if old.outer_time is not null and (new.outer_time is null or new.outer_time < old.outer_time) then
    new.outer_status := old.outer_status; new.outer_time := old.outer_time;
    new.outer_by := old.outer_by; new.outer_by_device := old.outer_by_device;
  end if;
  -- a status without a time (older app) never erases a timed one
  if new.slaughter is null and old.slaughter is not null and new.slaughter_time is null then new.slaughter := old.slaughter; end if;
  if new.outer_status is null and old.outer_status is not null and new.outer_time is null then new.outer_status := old.outer_status; end if;

  -- once yes, stays yes
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
  new.not_chalak_inner      := coalesce(old.not_chalak_inner, false)      or coalesce(new.not_chalak_inner, false);
  new.eso_checked           := coalesce(old.eso_checked, false)           or coalesce(new.eso_checked, false);
  new.legs_sorted           := coalesce(old.legs_sorted, false)           or coalesce(new.legs_sorted, false);

  -- an empty value never erases a recorded one
  new.maw           := coalesce(new.maw, old.maw);
  new.rumen         := coalesce(new.rumen, old.rumen);
  new.weight_right  := coalesce(new.weight_right, old.weight_right);
  new.weight_left   := coalesce(new.weight_left, old.weight_left);
  new.weight_stage2 := coalesce(new.weight_stage2, old.weight_stage2);
  new.weight_stage3 := coalesce(new.weight_stage3, old.weight_stage3);
  new.eso_result    := coalesce(new.eso_result, old.eso_result);

  -- printed count: highest wins
  new.parts_print_count := greatest(coalesce(old.parts_print_count, 0), coalesce(new.parts_print_count, 0));

  return new;
end $$;

-- runs BEFORE the "already moved on" rule (triggers fire in name order), so
-- that rule only ever sees real changes, not an old copy's empty fields
drop trigger if exists a_animals_merge on animals_pilot;
create trigger a_animals_merge before update on animals_pilot
  for each row execute function _animals_merge();

insert into plant_state (key, value) values ('schemaStep', '29')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ============================================================================
-- STEP 30: counter display screens (a big monitor / TV that shows the count)
-- ============================================================================
--  • A device can be paired as "display" (up to 4 of them). It shows the
--    live animal count in big numbers and nothing else.
--  • A display device can only READ — it can never record animal data or
--    events, even though it is paired.
-- Safe to run more than once.
-- ============================================================================

create or replace function _device_write_allowed() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text;
begin
  if not _device_auth_required() then return true; end if;             -- enforcement OFF
  if not _is_api_request() then return true; end if;                    -- SQL editor / server jobs
  if _request_is_service_role() then return true; end if;                -- server-side code with the service key
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  if _request_has_manager() then return true; end if;                    -- logged-in team leader
  v_dev := _current_device_id();
  if v_dev is null then return false; end if;
  return exists(select 1 from devices_pilot
                 where id = v_dev and assigned_role is not null
                   and assigned_role <> 'display'                        -- a counter screen only reads
                   and coalesce(device_status, 'active') <> 'retired');
end $$;

create or replace function device_pair(p_token text, p_code text, p_role text, p_index integer default 0,
                                       p_replace boolean default false, p_device_name text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r device_pairing%rowtype; v_idx int; v_tok text; v_old record;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_role not in ('slaughter','esophagus','legs','inner','outer','parts','stamps','display') then
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;
  v_idx := case when p_role in ('inner','outer','display') then coalesce(p_index, 0) else 0 end;
  if (p_role = 'display' and v_idx not between 0 and 3) or (p_role <> 'display' and v_idx not in (0, 1)) then
    return jsonb_build_object('ok', false, 'error', 'bad_slot');
  end if;

  perform pg_advisory_xact_lock(hashtext('device_slot:' || p_role || ':' || v_idx));

  select * into r from device_pairing
   where code = trim(p_code) and paired_at is null and expires_at > now()
   for update;
  if r.code is null then return jsonb_build_object('ok', false, 'error', 'code_invalid'); end if;

  perform set_config('app.device_admin', 'on', true);

  for v_old in select id, device_name from devices_pilot
                where assigned_role = p_role and coalesce(assigned_index, 0) = v_idx
                  and id <> r.device_id and coalesce(device_status, 'active') <> 'retired'
  loop
    if not p_replace then
      perform set_config('app.device_admin', '', true);
      return jsonb_build_object('ok', false, 'error', 'slot_taken',
                                'device_name', coalesce(v_old.device_name, v_old.id));
    end if;
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
     where id = v_old.id;
    update device_credentials set revoked = true where device_id = v_old.id;
    perform _log_device_event(v_old.id, 'UNASSIGNED', p_role, v_idx, 'replaced by pairing', r.device_id);
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
  perform _log_device_event(r.device_id, 'ASSIGNED', p_role, v_idx, 'paired with code', null);
  return jsonb_build_object('ok', true, 'device_id', r.device_id);
end $$;
grant execute on function device_pair(text, text, text, integer, boolean, text) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '30')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ============================================================================
-- STEP 31: manufacturer repair access needs the PLANT's permission
--          + a status snapshot for the manufacturer's central console
-- ============================================================================
--  • The manufacturer's code alone now gives VIEW access (monitor, reports,
--    diagnostics) and billing. Full access for repairs (settings, devices,
--    owners…) needs the plant's permission: a team leader turns on
--    "manufacturer repair access" for a number of hours. It turns itself off
--    when the time is up, and the team leader can turn it off at any moment.
--    Every grant / revoke is written to the event log.
--  • plant_status_snapshot(): a read-only summary of the plant (no names, no
--    codes) that is sent to the manufacturer's central console every minute —
--    so the manufacturer sees every plant live, without any code.
-- Safe to run more than once.
-- ============================================================================

create or replace function _support_access_open() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select value::timestamptz > now() from plant_state where key = 'supportAccessUntil'), false);
$$;
revoke execute on function _support_access_open() from public, anon, authenticated;

-- a manufacturer session counts as a team leader only while the plant allows it
create or replace function _manager_session_valid(p_token text)
returns boolean language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_required boolean; v_role text;
begin
  select value into v_required from system_flags where key = 'manager_auth_required';
  if coalesce(v_required, false) = false then
    return true;
  end if;
  v_role := _session_role(p_token);
  if v_role = 'manager' then return true; end if;
  if v_role = 'manufacturer' and _support_access_open() then return true; end if;
  return false;
end $$;
revoke execute on function _manager_session_valid(text) from public, anon, authenticated;

-- team leader (only a real team leader) opens / closes repair access
create or replace function support_access_set(p_token text, p_hours integer)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_until timestamptz; v_name text;
begin
  if coalesce(_session_role(p_token), '') <> 'manager' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_hours is null or p_hours < 0 or p_hours > 168 then
    return jsonb_build_object('ok', false, 'error', 'bad_hours');
  end if;
  select m.name into v_name from manager_sessions s join plant_managers m on m.id = s.manager_id where s.token = p_token;
  v_until := case when p_hours = 0 then now() else now() + make_interval(hours => p_hours) end;
  insert into plant_state (key, value) values ('supportAccessUntil', v_until::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  if p_hours = 0 then
    -- closing: end the manufacturer's open sessions right away
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
          jsonb_build_object('hours', p_hours, 'until', v_until), v_name, 'server', now()::text);
  perform set_config('app.device_admin', '', true);
  return jsonb_build_object('ok', true, 'until', v_until);
end $$;
grant execute on function support_access_set(text, integer) to anon, authenticated;

create or replace function support_diagnostics(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s jsonb; tz text; v_cron text := 'not available'; v_chain jsonb;
begin
  -- read-only: a team leader, or the manufacturer (even without repair access)
  if not (_manager_session_valid(p_token) or coalesce(_session_role(p_token), '') = 'manufacturer') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
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
    'dbSize', pg_size_pretty(pg_database_size(current_database())),
    'schemaStep', (select value from plant_state where key = 'schemaStep'),
    'lastForceReloadAt', s ->> 'forceReloadAt',
    'supportAccessUntil', (select value from plant_state where key = 'supportAccessUntil')
  );
end $$;
grant execute on function support_diagnostics(text) to anon, authenticated;

create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason','billing','forceReloadAt','supportAccessUntil'];
  cur jsonb;
  incoming jsonb;
  k text;
  ignored text[] := '{}';
  is_manager boolean := false;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
  end if;

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

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, p_device_id, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;
grant execute on function push_settings(jsonb, text, text) to anon, authenticated;

-- ── status for the manufacturer's central console (read-only, no names/codes) ──
create or replace function plant_status_snapshot()
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare s jsonb; tz text; v_cron text := 'not available'; v_chain jsonb; v_intake int;
begin
  select settings into s from settings_pilot where id = 1;
  tz := coalesce(nullif(s ->> 'plantTimezone', ''), 'UTC');
  if not exists (select 1 from pg_timezone_names where name = tz) then tz := 'UTC'; end if;
  if to_regclass('cron.job') is not null then
    execute $q$select case when exists(select 1 from cron.job where jobname = 'glatttrack-daily-rollover')
                          then 'scheduled' else 'not scheduled' end$q$ into v_cron;
  end if;
  begin v_chain := verify_event_chain() - 'head'; exception when others then v_chain := jsonb_build_object('ok', false); end;
  select coalesce(sum((x->>'qty')::int), 0) into v_intake
    from jsonb_array_elements(coalesce(s -> 'dailyIntake', '[]'::jsonb)) x
   where (x->>'qty') ~ '^\d+$';
  return jsonb_build_object(
    'at', now(),
    'plantTime', to_char(now() at time zone tz, 'YYYY-MM-DD HH24:MI'),
    'timezone', tz,
    'schemaStep', (select value from plant_state where key = 'schemaStep'),
    'lastRolloverDate', (select value from plant_state where key = 'lastRolloverDate'),
    'rolloverJob', v_cron,
    'eventChain', v_chain,
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
        'lastSlaughterAt', max(slaughter_time)) from animals_pilot),
    'devices', coalesce((select jsonb_agg(jsonb_build_object(
        'role', assigned_role, 'index', assigned_index, 'name', device_name,
        'online', last_seen > now() - interval '3 minutes', 'lastSeen', last_seen,
        'version', app_info ->> 'v', 'screen', app_info ->> 'screen') order by assigned_role nulls last)
      from devices_pilot where coalesce(device_status, 'active') <> 'retired' and assigned_role is not null), '[]'::jsonb),
    'billing', s -> 'billing',
    'problems', coalesce(jsonb_array_length(s -> 'problemReports'), 0)
  );
end $$;
grant execute on function plant_status_snapshot() to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '31')
  on conflict (key) do update set value = excluded.value, updated_at = now();

set check_function_bodies = on;
notify pgrst, 'reload schema';


-- ============================================================================
-- STEP 32: a manufacturer session ends by itself
-- ============================================================================
--  • Without the plant's repair permission, a manufacturer login lasts
--    10 minutes (view only) and then ends on its own — the server itself
--    rejects the session after that, not only the screen.
--  • While the plant has "manufacturer repair access" open, the session
--    lasts until that access ends. Opening access extends a session that is
--    already logged in; closing access ends it at once (step31).
-- Safe to run more than once.
-- ============================================================================

create or replace function _maker_session_end() returns timestamptz
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when _support_access_open()
              then least((select value::timestamptz from plant_state where key = 'supportAccessUntil'), now() + interval '24 hours')
              else now() + interval '10 minutes' end;
$$;
revoke execute on function _maker_session_end() from public, anon, authenticated;

create or replace function manager_login(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_manager plant_managers%rowtype;
  v_token text;
  v_expires timestamptz;
begin
  select * into v_manager from plant_managers
    where active and code_hash = crypt(p_code, code_hash)
    order by (role = 'manager') desc
    limit 1;
  if v_manager.id is null then
    if not exists(select 1 from plant_managers where role = 'manager' and active) then
      return jsonb_build_object('ok', false, 'reason', 'no_managers');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'wrong_code');
  end if;
  insert into manager_sessions (manager_id) values (v_manager.id)
    returning token, expires_at into v_token, v_expires;
  if v_manager.role = 'manufacturer' then
    v_expires := _maker_session_end();
    update manager_sessions set expires_at = v_expires where token = v_token;
  end if;
  return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name,
                            'role', v_manager.role, 'expires_at', v_expires,
                            'repairAccess', _support_access_open());
end $$;
grant execute on function manager_login(text) to anon, authenticated;

-- opening repair access extends a manufacturer session that is already in
create or replace function _extend_maker_sessions() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if new.key = 'supportAccessUntil' then
    update manager_sessions set expires_at = _maker_session_end()
     where manager_id in (select id from plant_managers where role = 'manufacturer')
       and expires_at > now();
  end if;
  return new;
end $$;
drop trigger if exists extend_maker_sessions on plant_state;
create trigger extend_maker_sessions after insert or update on plant_state
  for each row execute function _extend_maker_sessions();

-- shorten sessions that were opened before this step
update manager_sessions set expires_at = least(expires_at, now() + interval '10 minutes')
 where manager_id in (select id from plant_managers where role = 'manufacturer')
   and not _support_access_open();

insert into plant_state (key, value) values ('schemaStep', '32')
  on conflict (key) do update set value = excluded.value, updated_at = now();

notify pgrst, 'reload schema';


-- ============================================================================
-- STEP 33: kashrut data integrity + security hardening (full review, 23/09)
-- ============================================================================
--  Data integrity
--  • A first ruling now always lands on the server — also on a brand-new
--    install (the animal row is created if it doesn't exist yet), and the
--    board has room for 1000 animals a day.
--  • A ruling is always stamped with the SERVER's clock (never older than the
--    value it replaces), so a tablet whose clock is wrong can't lose a ruling.
--  • The first ruling also moves that device's "worked on" cursor, so the
--    inspector can still correct the animal he is standing at.
--  • Day number ("board epoch"): every daily reset starts a new epoch. A
--    tablet that was offline over the reset and still holds yesterday's
--    board can never write yesterday's animals into today's board.
--  • Each station may only rule its own stage (slaughter / esophagus /
--    inner / outer / legs / stamps). Other stations' copies can never change
--    another station's ruling.
--  • Inner inspection: a second inner screen can't open an animal another
--    inner screen is already checking (atomic "start" claim).
--  • Daily rollover: never in the middle of work (waits while the board is
--    active, max 3 hours), and the archive gets the real date of the board.
--  • Event log: adding an event stays fast forever (chain head kept aside);
--    the heavy full-chain check is no longer run every 2 minutes.
--  Security
--  • Code guessing: after 8 wrong codes from one address → locked 15 min.
--  • Only a real team leader can add / remove team leaders or owners, pair
--    devices or turn the device lock on/off (not the manufacturer, even with
--    repair access; not an owner).
--  • The manufacturer can't write to the event log without repair access.
--  • Station settings (worker on duty, reprints, problem reports…) can only
--    be sent by a paired station or a team leader; lists are MERGED, so two
--    stations reporting at the same moment never erase each other.
--  • Nobody can write the device table directly any more (only through the
--    server's own functions); pairing-code flooding is limited per address.
--  • The plant summary for the manufacturer's console can only be read by a
--    paired device, a logged-in account, or the plant server itself.
-- Safe to run more than once.
-- ============================================================================

-- ─────────────────────────── helpers ───────────────────────────
create or replace function _request_ip() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare h json; v text;
begin
  h := _request_headers();
  if h is null then return 'local'; end if;
  v := coalesce(h ->> 'x-forwarded-for', h ->> 'x-real-ip', h ->> 'cf-connecting-ip', 'unknown');
  return left(trim(split_part(v, ',', 1)), 64);
end $$;
revoke execute on function _request_ip() from public, anon, authenticated;

-- which station the calling device is paired to (null = not a device call)
create or replace function _caller_device_role() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text; v_role text;
begin
  v_dev := _current_device_id();
  if v_dev is null then return null; end if;
  select assigned_role into v_role from devices_pilot
   where id = v_dev and coalesce(device_status, 'active') <> 'retired';
  return v_role;
end $$;
revoke execute on function _caller_device_role() from public, anon, authenticated;

-- may the current caller write this stage? (true for team leader / server / enforcement off)
create or replace function _stage_allowed(p_stage text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text;
begin
  if not _device_auth_required() then return true; end if;
  if not _is_api_request() then return true; end if;
  if _request_is_service_role() then return true; end if;
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  if _request_has_manager() then return true; end if;
  v_role := _caller_device_role();
  if v_role is null then return false; end if;
  return case p_stage
    when 'slaughter' then v_role in ('slaughter')
    when 'eso'       then v_role in ('esophagus','slaughter')
    when 'inner'     then v_role in ('inner','outer')
    when 'outer'     then v_role in ('outer','inner')
    when 'legs'      then v_role in ('legs')
    when 'stamped'   then v_role in ('stamps','parts')
    else false end;
end $$;
revoke execute on function _stage_allowed(text) from public, anon, authenticated;

create or replace function _board_epoch() returns bigint
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select nullif(value, '')::bigint from plant_state where key = 'boardEpoch' and value ~ '^\d+$';
$$;
revoke execute on function _board_epoch() from public, anon, authenticated;

create or replace function server_now_ms() returns bigint
language sql stable as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;
grant execute on function server_now_ms() to anon, authenticated;

-- ─────────────────────────── board: 1000 rows, epoch ───────────────────────────
alter table animals_pilot add column if not exists board_epoch bigint;
alter table animals_pilot add column if not exists eso_prev_slaughter text;

-- every animal row exists (0..999), so first rulings and merges always find it
insert into animals_pilot (id) select g from generate_series(0, 999) g
  on conflict (id) do nothing;

-- ─────────────────────────── merge trigger (replaces step29) ───────────────────────────
create or replace function _animals_merge() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := _board_epoch();
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;

  -- yesterday's board may never come back (a tablet offline over the reset)
  if v_epoch is not null and new.board_epoch is not null and new.board_epoch < v_epoch then
    raise exception 'stale-board: this device still has the previous day''s board' using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    new.board_epoch := coalesce(v_epoch, new.board_epoch);
    return new;
  end if;
  new.board_epoch := coalesce(v_epoch, new.board_epoch, old.board_epoch);

  -- timed groups: keep the server's values when the incoming copy is older
  if old.slaughter_time is not null and (new.slaughter_time is null or new.slaughter_time < old.slaughter_time) then
    new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
    new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
    new.eso_result := coalesce(old.eso_result, new.eso_result);
    new.eso_prev_slaughter := coalesce(old.eso_prev_slaughter, new.eso_prev_slaughter);
  end if;
  if old.inner_time is not null and (new.inner_time is null or new.inner_time < old.inner_time) then
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
  end if;
  if old.outer_time is not null and (new.outer_time is null or new.outer_time < old.outer_time) then
    new.outer_status := old.outer_status; new.outer_time := old.outer_time;
    new.outer_by := old.outer_by; new.outer_by_device := old.outer_by_device;
  end if;
  if new.slaughter is null and old.slaughter is not null and new.slaughter_time is null then new.slaughter := old.slaughter; end if;
  if new.outer_status is null and old.outer_status is not null and new.outer_time is null then new.outer_status := old.outer_status; end if;

  -- each station rules only its own stage: another station's copy can't change it
  if coalesce(current_setting('gt.eso_ruling', true), '') <> 'true' then
    if new.slaughter is distinct from old.slaughter and not _stage_allowed('slaughter') then
      new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
      new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
    end if;
    if new.eso_result is distinct from old.eso_result and not _stage_allowed('eso') then
      new.eso_result := old.eso_result;
    end if;
  end if;
  if new.inner_status is distinct from old.inner_status and not _stage_allowed('inner') then
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
  end if;
  if new.outer_status is distinct from old.outer_status and not _stage_allowed('outer') then
    new.outer_status := old.outer_status; new.outer_time := old.outer_time;
    new.outer_by := old.outer_by; new.outer_by_device := old.outer_by_device;
  end if;

  -- once yes, stays yes
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
  new.not_chalak_inner      := coalesce(old.not_chalak_inner, false)      or coalesce(new.not_chalak_inner, false);
  new.eso_checked           := coalesce(old.eso_checked, false)           or coalesce(new.eso_checked, false);
  new.legs_sorted           := coalesce(old.legs_sorted, false)           or coalesce(new.legs_sorted, false);

  -- an empty value never erases a recorded one
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

drop trigger if exists a_animals_merge on animals_pilot;
create trigger a_animals_merge before update on animals_pilot
  for each row execute function _animals_merge();
drop trigger if exists a_animals_merge_ins on animals_pilot;
create trigger a_animals_merge_ins before insert on animals_pilot
  for each row execute function _animals_merge();

-- the "moved on" cursor follows whoever made the first ruling of each stage
create or replace function animals_pilot_advance_cursor() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if tg_op = 'UPDATE' and current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if (tg_op = 'INSERT' or old.slaughter is null) and new.slaughter is not null then
    update devices_pilot set cursor_slaughter = new.id where id = coalesce(new.slaughter_by_device, new.device_id);
  end if;
  if (tg_op = 'INSERT' or old.inner_status is null) and new.inner_status is not null then
    update devices_pilot set cursor_inner = new.id where id = coalesce(new.inner_by_device, new.device_id);
  end if;
  if (tg_op = 'INSERT' or old.outer_status is null) and new.outer_status is not null then
    update devices_pilot set cursor_outer = new.id where id = coalesce(new.outer_by_device, new.device_id);
  end if;
  return new;
end $$;

-- ─────────────────────────── first-claim (replaces step28) ───────────────────────────
drop function if exists claim_animal_stage(integer, text, text, text, text);
create or replace function claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text,
                                              p_device_id text, p_epoch bigint default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_rows integer;
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_row jsonb;
  v_dev text;
  v_epoch bigint := _board_epoch();
  v_stage text := case when p_stage = 'inner_start' then 'inner' else p_stage end;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('claimed', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and p_epoch is not null and p_epoch < v_epoch then
    return jsonb_build_object('claimed', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed(v_stage) then
    return jsonb_build_object('claimed', false, 'error', 'wrong_station');
  end if;
  -- a paired device is always recorded as itself, whatever it claims to be
  v_dev := coalesce(_current_device_id(), p_device_id);

  insert into animals_pilot (id) values (p_id) on conflict (id) do nothing;

  if p_stage = 'slaughter' then
    update animals_pilot
       set slaughter = p_value, slaughtered_by = p_actor, slaughter_by_device = v_dev, device_id = v_dev,
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), updated_at = now()
     where id = p_id and slaughter is null;

  elsif p_stage = 'inner_start' then
    -- open the lung check: only if nobody else has this animal
    update animals_pilot
       set inner_status = 'in_progress', inner_by = p_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id and (inner_status is null
                          or (inner_status = 'in_progress'
                              and (inner_by_device is null or inner_by_device = v_dev
                                   or inner_time < v_now - 600000)));   -- a check left open 10+ min can be taken over

  elsif p_stage = 'inner' then
    if p_value not in ('confirmed','treif') then
      raise exception 'claim_animal_stage: bad inner result %', p_value;
    end if;
    update animals_pilot
       set inner_status = p_value, inner_by = p_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id
       and (inner_status is null
            or (inner_status = 'in_progress' and (inner_by_device is null or inner_by_device = v_dev
                                                  or inner_time < v_now - 600000)));

  elsif p_stage = 'outer' then
    update animals_pilot
       set outer_status = p_value, outer_by = p_actor, outer_by_device = v_dev, device_id = v_dev,
           outer_time = greatest(v_now, coalesce(outer_time, 0) + 1), updated_at = now()
     where id = p_id and outer_status is null;

  elsif p_stage = 'eso' then
    if p_value not in ('ok','nevela') then
      raise exception 'claim_animal_stage: bad esophagus result %', p_value;
    end if;
    perform set_config('gt.eso_ruling', 'true', true);
    update animals_pilot
       set eso_checked = true,
           eso_result = p_value,
           eso_prev_slaughter = case when p_value = 'nevela' then slaughter else eso_prev_slaughter end,
           slaughter = case when p_value = 'nevela' then 'nevela' else slaughter end,
           slaughter_time = case when p_value = 'nevela' then greatest(v_now, coalesce(slaughter_time, 0) + 1) else slaughter_time end,
           slaughter_by_device = case when p_value = 'nevela' then v_dev else slaughter_by_device end,
           updated_at = now()
     where id = p_id and (eso_checked is distinct from true);
    perform set_config('gt.eso_ruling', '', true);

  elsif p_stage = 'legs' then
    update animals_pilot set legs_sorted = true, updated_at = now()
     where id = p_id and (legs_sorted is distinct from true);

  elsif p_stage = 'stamped' then
    update animals_pilot set stamped = true, updated_at = now()
     where id = p_id and (stamped is distinct from true);

  else
    raise exception 'claim_animal_stage: unknown stage %', p_stage;
  end if;

  get diagnostics v_rows = row_count;
  select to_jsonb(a.*) into v_row from animals_pilot a where a.id = p_id;
  return jsonb_build_object('claimed', v_rows = 1, 'row', v_row, 'serverNow', v_now);
end $$;
grant execute on function claim_animal_stage(integer, text, text, text, text, bigint) to anon, authenticated;

-- esophagus correction: only the esophagus station (or a team leader)
create or replace function eso_change(p_id integer, p_result text, p_device_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  a animals_pilot%rowtype;
  v_row jsonb;
  v_dev text := coalesce(_current_device_id(), p_device_id);
begin
  if p_result not in ('ok','nevela') then
    return jsonb_build_object('ok', false, 'error', 'bad_result');
  end if;
  if not _stage_allowed('eso') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  select * into a from animals_pilot where id = p_id for update;
  if a.id is null or a.eso_checked is distinct from true then
    return jsonb_build_object('ok', false, 'error', 'not_checked');
  end if;
  if a.eso_result = p_result then
    select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
    return jsonb_build_object('ok', true, 'row', v_row);
  end if;
  perform set_config('gt.eso_ruling', 'true', true);
  if p_result = 'nevela' then
    update animals_pilot
       set eso_result = 'nevela', eso_prev_slaughter = slaughter, slaughter = 'nevela',
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev, updated_at = now()
     where id = p_id;
  else
    update animals_pilot
       set eso_result = 'ok', slaughter = coalesce(eso_prev_slaughter, 'slaughtered'),
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev, updated_at = now()
     where id = p_id;
  end if;
  perform set_config('gt.eso_ruling', '', true);
  select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
  return jsonb_build_object('ok', true, 'row', v_row);
end $$;
grant execute on function eso_change(integer, text, text) to anon, authenticated;

-- ─────────────────────────── daily reset: new epoch ───────────────────────────
create or replace function _do_board_reset(p_reason text, p_business_date date)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  insert into daily_board_archive (business_date, reason, animals_count, board)
  select p_business_date, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb)
    from animals_pilot a
   where a.slaughter is not null or a.inner_status is not null or a.outer_status is not null;

  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);

  insert into plant_state (key, value) values ('boardEpoch', v_epoch::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null, eso_prev_slaughter = null,
    legs_sorted = false,
    stamped = false,
    parts_print_count = 0,
    board_epoch = v_epoch,
    updated_at = now()
  where true;

  update devices_pilot set cursor_slaughter = null, cursor_inner = null, cursor_outer = null
  where true;

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

-- first epoch for an existing plant (current board = current epoch)
insert into plant_state (key, value)
values ('boardEpoch', ((extract(epoch from clock_timestamp()) * 1000)::bigint)::text)
on conflict (key) do nothing;
update animals_pilot set board_epoch = _board_epoch() where board_epoch is null;
insert into settings_pilot (id, settings, device_id, updated_at)
values (1, jsonb_build_object('boardEpoch', _board_epoch()), 'server', now())
on conflict (id) do update
  set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('boardEpoch', _board_epoch()),
      updated_at = now()
  where (settings_pilot.settings -> 'boardEpoch') is null;

-- rollover: not in the middle of work, and archive under the board's real date
create or replace function request_daily_rollover()
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s jsonb; tz text; rt time; local_now timestamp; today date; last_date text;
  v_last_activity timestamptz; v_board_date date;
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
    return jsonb_build_object('ok', true, 'done', false, 'status', 'already', 'plantDate', today, 'timezone', tz);
  end if;
  if local_now::time < rt then
    return jsonb_build_object('ok', true, 'done', false, 'status', 'not_yet', 'plantDate', today, 'timezone', tz, 'resetTime', rt);
  end if;

  -- work still going on (a ruling in the last 20 minutes)? wait — at most 3 hours
  select max(to_timestamp(greatest(coalesce(slaughter_time,0), coalesce(inner_time,0), coalesce(outer_time,0)) / 1000.0))
    into v_last_activity from animals_pilot
   where slaughter_time is not null or inner_time is not null or outer_time is not null;
  if v_last_activity is not null and v_last_activity > now() - interval '20 minutes'
     and local_now < (today + rt) + interval '3 hours' then
    return jsonb_build_object('ok', true, 'done', false, 'status', 'busy', 'plantDate', today, 'timezone', tz);
  end if;

  -- the board belongs to the day its work was done on
  select (min(to_timestamp(slaughter_time / 1000.0)) at time zone tz)::date into v_board_date
    from animals_pilot where slaughter_time is not null;
  perform _do_board_reset('daily-rollover', coalesce(v_board_date, today - 1));
  update plant_state set value = today::text, updated_at = now() where key = 'lastRolloverDate';
  return jsonb_build_object('ok', true, 'done', true, 'status', 'rolled_over', 'plantDate', today, 'timezone', tz);
end $$;

-- ─────────────────────────── event log: fast head ───────────────────────────
create table if not exists events_chain_head (
  id int primary key default 1 check (id = 1),
  pos bigint not null default 0,
  hash text
);
alter table events_chain_head enable row level security;
revoke all on events_chain_head from anon, authenticated;
insert into events_chain_head (id, pos, hash)
select 1, coalesce(max(chain_pos), 0),
       (select event_hash from events_pilot where server_chained order by chain_pos desc limit 1)
  from events_pilot where server_chained
on conflict (id) do nothing;
create index if not exists events_pilot_chain_head_idx on events_pilot (chain_pos desc) where server_chained;

create or replace function _events_chain_link() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

-- the same event sent twice (offline outbox retry) is stored once
create unique index if not exists events_pilot_event_id_uq on events_pilot (event_id);

-- manufacturer: event log only with the plant's repair permission
create or replace function _events_maker_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if _device_write_allowed() then return new; end if;
  if _request_has_manufacturer() then
    if not _support_access_open() then
      raise exception 'אין גישת יצרן פתוחה (manufacturer_no_access)' using errcode = '42501';
    end if;
    if new.animal_no is not null then
      raise exception 'היצרן לא רושם אירועים על בהמות (manufacturer_no_kashrut)' using errcode = '42501';
    end if;
    return new;
  end if;
  return new;
end $$;

-- ─────────────────────────── login: stop code guessing ───────────────────────────
create table if not exists login_attempts (
  id bigserial primary key,
  ip text not null,
  at timestamptz not null default now(),
  ok boolean not null
);
create index if not exists login_attempts_ip_at on login_attempts (ip, at desc);
alter table login_attempts enable row level security;
revoke all on login_attempts from anon, authenticated;

create or replace function manager_login(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_manager plant_managers%rowtype;
  v_token text;
  v_expires timestamptz;
  v_ip text := _request_ip();
  v_fails int;
  v_last timestamptz;
begin
  delete from login_attempts where at < now() - interval '1 day';
  select count(*), max(at) into v_fails, v_last from login_attempts
   where ip = v_ip and not ok and at > now() - interval '15 minutes';
  if v_fails >= 8 then
    return jsonb_build_object('ok', false, 'reason', 'locked',
                              'retry_after', ceil(extract(epoch from (v_last + interval '15 minutes' - now()))));
  end if;

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
  delete from login_attempts where ip = v_ip;
  insert into manager_sessions (manager_id) values (v_manager.id)
    returning token, expires_at into v_token, v_expires;
  if v_manager.role = 'manufacturer' then
    v_expires := _maker_session_end();
    update manager_sessions set expires_at = v_expires where token = v_token;
  end if;
  return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name,
                            'role', v_manager.role, 'expires_at', v_expires,
                            'repairAccess', _support_access_open());
end $$;
grant execute on function manager_login(text) to anon, authenticated;

-- session check without logging in again (used when the app returns to a saved team-leader session)
create or replace function manager_session_check(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text; v_exp timestamptz;
begin
  select m.role, s.expires_at into v_role, v_exp
    from manager_sessions s join plant_managers m on m.id = s.manager_id
   where s.token = p_token and s.expires_at > now() and m.active;
  return jsonb_build_object('ok', v_role is not null, 'role', v_role, 'expires_at', v_exp);
end $$;
grant execute on function manager_session_check(text) to anon, authenticated;

-- ─────────────────────────── only a real team leader ───────────────────────────
create or replace function _is_real_manager(p_token text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_required boolean;
begin
  select value into v_required from system_flags where key = 'manager_auth_required';
  if coalesce(v_required, false) = false then return true; end if;
  return coalesce(_session_role(p_token), '') = 'manager';
end $$;
revoke execute on function _is_real_manager(text) from public, anon, authenticated;

create or replace function manager_add(p_token text, p_name text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_code is null or length(p_code) < 4 then
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'manager')
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function manager_add_owner(p_token text, p_name text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if coalesce(trim(p_name), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'name required');
  end if;
  if p_code is null or length(p_code) < 4 then
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
  end if;
  if _code_in_use(p_code) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;
  insert into plant_managers (name, code_hash, role) values (left(trim(p_name), 60), crypt(p_code, gen_salt('bf')), 'owner')
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function manager_deactivate(p_token text, p_manager_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function device_auth_set(p_token text, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _is_real_manager(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  update system_flags set value = p_on where key = 'device_auth_required';
  return jsonb_build_object('ok', true, 'enforced', p_on);
end $$;
grant execute on function device_auth_set(text, boolean) to anon, authenticated;

-- pairing a station = giving a device the right to record kashrut → team leader only
do $$
declare v_src text;
begin
  select pg_get_functiondef('device_pair(text,text,text,integer,boolean,text)'::regprocedure) into v_src;
  if position('_manager_session_valid(p_token)' in v_src) > 0 then
    v_src := replace(v_src, 'if not _manager_session_valid(p_token) then', 'if not _is_real_manager(p_token) then');
    execute v_src;
  end if;
end $$;

-- ─────────────────────────── station settings: paired + merged ───────────────────────────
create or replace function _merge_list(a jsonb, b jsonb) returns jsonb
language sql immutable as $$
  -- union of two lists; items with the same "id" (or identical items) appear once, newest list order kept
  select coalesce(jsonb_agg(x order by ord), '[]'::jsonb) from (
    select distinct on (coalesce(x ->> 'id', x::text)) x, ord from (
      select x, 1000000 + o as ord from jsonb_array_elements(case when jsonb_typeof(b) = 'array' then b else '[]'::jsonb end) with ordinality t(x, o)
      union all
      select x, o from jsonb_array_elements(case when jsonb_typeof(a) = 'array' then a else '[]'::jsonb end) with ordinality t(x, o)
    ) u order by coalesce(x ->> 'id', x::text), ord desc
  ) d;
$$;

create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  list_keys text[] := array['reprintLog','problemReports'];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason','billing','forceReloadAt','supportAccessUntil','boardEpoch'];
  cur jsonb;
  incoming jsonb;
  k text;
  ignored text[] := '{}';
  is_manager boolean := false;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
  end if;
  -- station keys: a paired station (or team leader); nobody anonymous
  if not is_manager and not _device_write_allowed() then
    return jsonb_build_object('ok', false, 'error', 'device_not_paired');
  end if;

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

  -- append-style lists: merge with what other stations already sent
  -- (a team leader's edit — e.g. closing a report — replaces the list as is)
  foreach k in array list_keys loop
    if not is_manager and incoming ? k then
      incoming := jsonb_set(incoming, array[k], _merge_list(cur -> k, incoming -> k));
    end if;
  end loop;

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, p_device_id, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;
grant execute on function push_settings(jsonb, text, text) to anon, authenticated;

-- ─────────────────────────── device table: server functions only ───────────────────────────
drop policy if exists "anon insert devices_pilot" on public.devices_pilot;
drop policy if exists "anon update devices_pilot" on public.devices_pilot;
revoke insert, update, delete, truncate on public.devices_pilot from anon, authenticated;
drop policy if exists "anon insert settings_pilot" on public.settings_pilot;
drop policy if exists "anon update settings_pilot" on public.settings_pilot;
revoke insert, update, delete, truncate on public.settings_pilot from anon, authenticated;
revoke truncate on public.animals_pilot, public.events_pilot from anon, authenticated;
revoke delete on public.animals_pilot from anon, authenticated;

create table if not exists pairing_requests (ip text not null, at timestamptz not null default now());
create index if not exists pairing_requests_ip_at on pairing_requests (ip, at desc);
alter table pairing_requests enable row level security;
revoke all on pairing_requests from anon, authenticated;

do $$
declare v_src text;
begin
  select pg_get_functiondef('device_request_pairing(text,text,text)'::regprocedure) into v_src;
  if position('pairing_requests' in v_src) = 0 then
    v_src := replace(v_src,
      '  -- housekeeping: unused codes that ran out, old history, keys nobody collected',
      '  -- one address can ask for at most 20 codes in 10 minutes (a flood = abuse)
  delete from pairing_requests where at < now() - interval ''1 hour'';
  if (select count(*) from pairing_requests where ip = _request_ip() and at > now() - interval ''10 minutes'') >= 20 then
    return jsonb_build_object(''ok'', false, ''error'', ''too_many_requests'');
  end if;
  insert into pairing_requests (ip) values (_request_ip());
  -- housekeeping: unused codes that ran out, old history, keys nobody collected');
    execute v_src;
  end if;
end $$;

-- heartbeat: only a paired device (or a device that is waiting for pairing) keeps its row alive
create or replace function device_heartbeat(p_device_id text, p_device_name text, p_info jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_info jsonb; v_dev text := _current_device_id();
begin
  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then return jsonb_build_object('ok', false); end if;
  if v_dev is not null and v_dev <> p_device_id then return jsonb_build_object('ok', false, 'error', 'not_this_device'); end if;
  v_info := case when jsonb_typeof(p_info) = 'object' and length(p_info::text) < 2000 then p_info else null end;
  if v_dev is null and not exists(select 1 from devices_pilot where id = p_device_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_device');   -- new devices appear through pairing only
  end if;
  update devices_pilot set last_seen = now(), app_info = coalesce(v_info, app_info)
   where id = p_device_id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function device_heartbeat(text, text, jsonb) to anon, authenticated;

-- ─────────────────────────── console summary: no chain scan, no anonymous reads ───────────────────────────
create or replace function plant_status_snapshot()
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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
        'role', assigned_role, 'index', assigned_index, 'name', device_name,
        'online', last_seen > now() - interval '3 minutes', 'lastSeen', last_seen,
        'version', app_info ->> 'v', 'screen', app_info ->> 'screen') order by assigned_role nulls last)
      from devices_pilot where coalesce(device_status, 'active') <> 'retired' and assigned_role is not null), '[]'::jsonb),
    'billing', s -> 'billing',
    'problems', coalesce(jsonb_array_length(s -> 'problemReports'), 0)
  );
end $$;
grant execute on function plant_status_snapshot() to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '33')
  on conflict (key) do update set value = excluded.value, updated_at = now();

notify pgrst, 'reload schema';


-- ============================================================================
-- STEP 34: data protection — nobody outside the plant's own devices can read
-- ============================================================================
--  Until now anyone holding the public app key (it is inside the web page)
--  could READ the board, the event log, the archive and the settings.
--  From this step on, the plant's data can be read only by:
--    • a paired station (its device key), or the app session of a paired
--      station (for live updates),
--    • a logged-in team leader / owner / manufacturer session,
--    • the plant server itself.
--  An unpaired phone or a stranger on the network gets nothing.
--  Also:
--    • the plant summary sent to the manufacturer carries no device names;
--    • old pilot tables are closed;
--    • device keys of devices that were replaced are wiped.
-- Safe to run more than once.
-- ============================================================================

alter table devices_pilot add column if not exists auth_uid uuid;
alter table manager_sessions add column if not exists auth_uid uuid;
create index if not exists devices_pilot_auth_uid on devices_pilot (auth_uid);
create index if not exists manager_sessions_auth_uid on manager_sessions (auth_uid);

create or replace function _auth_uid_safe() returns uuid
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  return auth.uid();
exception when others then return null;
end $$;
revoke execute on function _auth_uid_safe() from public, anon, authenticated;

-- may the current caller READ plant data?
create or replace function _reader_ok() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_uid uuid;
begin
  if not _device_auth_required() then return true; end if;         -- protection switched off by the team leader
  if not _is_api_request() then return true; end if;               -- plant server / SQL editor
  if _request_is_service_role() then return true; end if;
  if _current_device_id() is not null then return true; end if;    -- paired station (device key)
  if coalesce(_session_role(_request_headers() ->> 'x-manager-token'), '') <> '' then return true; end if;
  -- live updates carry only the app session: accept it when it belongs to a paired station or a live account session
  v_uid := _auth_uid_safe();
  if v_uid is null then return false; end if;
  return exists(select 1 from devices_pilot d join device_credentials c on c.device_id = d.id
                 where d.auth_uid = v_uid and not c.revoked
                   and d.assigned_role is not null and coalesce(d.device_status, 'active') <> 'retired')
      or exists(select 1 from manager_sessions s join plant_managers m on m.id = s.manager_id
                 where s.auth_uid = v_uid and s.expires_at > now() and m.active);
end $$;
grant execute on function _reader_ok() to anon, authenticated;   -- used inside the read policies

-- remember which app session belongs to which station / account
do $$
declare v_src text;
begin
  -- device_pairing_status: when the device collects its key, record its app session
  select pg_get_functiondef('device_pairing_status(text,text,text)'::regprocedure) into v_src;
  if position('auth_uid' in v_src) = 0 then
    v_src := replace(v_src,
      '  select * into d from devices_pilot where id = p_device_id;',
      '  perform set_config(''app.device_admin'', ''on'', true);
  update devices_pilot set auth_uid = coalesce(_auth_uid_safe(), auth_uid) where id = p_device_id;
  perform set_config(''app.device_admin'', '''', true);
  select * into d from devices_pilot where id = p_device_id;');
    execute v_src;
  end if;
  -- manager_login: record the app session of the account
  select pg_get_functiondef('manager_login(text)'::regprocedure) into v_src;
  if position('auth_uid' in v_src) = 0 then
    v_src := replace(v_src,
      '  insert into manager_sessions (manager_id) values (v_manager.id)',
      '  insert into manager_sessions (manager_id, auth_uid) values (v_manager.id, _auth_uid_safe())');
    execute v_src;
  end if;
end $$;

-- a paired device refreshes its app session on every heartbeat (app sessions renew themselves)
create or replace function device_heartbeat(p_device_id text, p_device_name text, p_info jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_info jsonb; v_dev text := _current_device_id();
begin
  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then return jsonb_build_object('ok', false); end if;
  if v_dev is not null and v_dev <> p_device_id then return jsonb_build_object('ok', false, 'error', 'not_this_device'); end if;
  v_info := case when jsonb_typeof(p_info) = 'object' and length(p_info::text) < 2000 then p_info else null end;
  if v_dev is null and not exists(select 1 from devices_pilot where id = p_device_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_device');
  end if;
  update devices_pilot set last_seen = now(), app_info = coalesce(v_info, app_info),
         auth_uid = case when v_dev is not null then coalesce(_auth_uid_safe(), auth_uid) else auth_uid end
   where id = p_device_id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function device_heartbeat(text, text, jsonb) to anon, authenticated;

-- ── read policies ──
drop policy if exists "anon select animals_pilot" on public.animals_pilot;
drop policy if exists "read animals_pilot" on public.animals_pilot;
create policy "read animals_pilot" on public.animals_pilot for select to anon, authenticated using ((select _reader_ok()));

drop policy if exists "anon select settings_pilot" on public.settings_pilot;
drop policy if exists "read settings_pilot" on public.settings_pilot;
create policy "read settings_pilot" on public.settings_pilot for select to anon, authenticated using ((select _reader_ok()));

drop policy if exists "anon select events_pilot" on public.events_pilot;
drop policy if exists "read events_pilot" on public.events_pilot;
create policy "read events_pilot" on public.events_pilot for select to anon, authenticated using ((select _reader_ok()));

drop policy if exists "read daily_board_archive" on daily_board_archive;
create policy "read daily_board_archive" on daily_board_archive for select to anon, authenticated using ((select _reader_ok()));

drop policy if exists "anon select devices_pilot" on public.devices_pilot;
drop policy if exists "read devices_pilot" on public.devices_pilot;
create policy "read devices_pilot" on public.devices_pilot for select to anon, authenticated using ((select _reader_ok()));

-- old tables from the first pilot: closed
do $$ begin
  if to_regclass('public.outer_status_pilot') is not null then
    execute 'drop policy if exists "anon insert pilot" on public.outer_status_pilot';
    execute 'drop policy if exists "anon update pilot" on public.outer_status_pilot';
    execute 'drop policy if exists "anon select pilot" on public.outer_status_pilot';
    execute 'revoke insert, update, delete, truncate on public.outer_status_pilot from anon, authenticated';
  end if;
  if to_regclass('public.device_lifecycle_events') is not null then
    execute 'drop policy if exists "anon insert device_lifecycle_events" on public.device_lifecycle_events';
    execute 'drop policy if exists "anon select device_lifecycle_events" on public.device_lifecycle_events';
    execute 'drop policy if exists "read device_lifecycle_events" on public.device_lifecycle_events';
    execute 'create policy "read device_lifecycle_events" on public.device_lifecycle_events for select to anon, authenticated using ((select _reader_ok()))';
    execute 'revoke insert, update, delete, truncate on public.device_lifecycle_events from anon, authenticated';
  end if;
end $$;

-- keys of replaced / retired devices stay revoked (kept for history — see step 36)

-- the manufacturer's summary: counts and health only — no device names
do $$
declare v_src text;
begin
  select pg_get_functiondef('plant_status_snapshot()'::regprocedure) into v_src;
  if position('''name'', device_name,' in v_src) > 0 then
    v_src := replace(v_src, '''role'', assigned_role, ''index'', assigned_index, ''name'', device_name,', '''role'', assigned_role, ''index'', assigned_index,');
    execute v_src;
  end if;
end $$;

insert into plant_state (key, value) values ('schemaStep', '34')
  on conflict (key) do update set value = excluded.value, updated_at = now();

notify pgrst, 'reload schema';


-- ============================================================================
-- STEP 35: security review follow-up (24/09)
-- ============================================================================
--  An outside review of step 34 asked for these; all are done here:
--  • Every function that steps 33–34 changed by "patching" the previous
--    version in place is now written out IN FULL (no silent no-op if a
--    patch did not match): device_pairing_status, device_pair,
--    device_request_pairing, plant_status_snapshot, manager_login.
--  • device_heartbeat: without a device key, only a device that is still
--    WAITING to be paired may report in — never a paired or retired one.
--    A logged-in team leader's app session is also bound here (live updates).
--  • Device protection is always ON and cannot be switched off from the app
--    (only from the SQL Editor on the server, for maintenance).
--  • No TRUNCATE / TRIGGER / REFERENCES rights for app users on any table.
--  • server_schema_step(): the app checks the server is up to date and warns
--    loudly if it is not.
--  • A self-check at the end: if anything above is not in place, this file
--    fails with an error instead of finishing quietly.
-- Safe to run more than once. Run after step 34.
-- ============================================================================

-- ── written out in full (were patched in steps 33/34) ──
CREATE OR REPLACE FUNCTION public.device_pairing_status(p_device_id text, p_code text, p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.device_pair(p_token text, p_code text, p_role text, p_index integer DEFAULT 0, p_replace boolean DEFAULT false, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare r device_pairing%rowtype; v_idx int; v_tok text; v_old record;
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

  perform pg_advisory_xact_lock(hashtext('device_slot:' || p_role || ':' || v_idx));

  select * into r from device_pairing
   where code = trim(p_code) and paired_at is null and expires_at > now()
   for update;
  if r.code is null then return jsonb_build_object('ok', false, 'error', 'code_invalid'); end if;

  perform set_config('app.device_admin', 'on', true);

  for v_old in select id, device_name from devices_pilot
                where assigned_role = p_role and coalesce(assigned_index, 0) = v_idx
                  and id <> r.device_id and coalesce(device_status, 'active') <> 'retired'
  loop
    if not p_replace then
      perform set_config('app.device_admin', '', true);
      return jsonb_build_object('ok', false, 'error', 'slot_taken',
                                'device_name', coalesce(v_old.device_name, v_old.id));
    end if;
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
     where id = v_old.id;
    update device_credentials set revoked = true where device_id = v_old.id;
    perform _log_device_event(v_old.id, 'UNASSIGNED', p_role, v_idx, 'replaced by pairing', r.device_id);
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
  perform _log_device_event(r.device_id, 'ASSIGNED', p_role, v_idx, 'paired with code', null);
  return jsonb_build_object('ok', true, 'device_id', r.device_id);
end $function$;

CREATE OR REPLACE FUNCTION public.device_request_pairing(p_device_id text, p_secret text, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_code text; v_exp timestamptz; i int := 0;
begin
  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then
    return jsonb_build_object('ok', false, 'error', 'bad device id');
  end if;
  if p_secret is null or length(p_secret) < 16 then
    return jsonb_build_object('ok', false, 'error', 'bad secret');
  end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.plant_status_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
end $function$;

-- ── manager_login in full: code-guessing lock + the app session of the account ──
create or replace function manager_login(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_manager plant_managers%rowtype;
  v_token text;
  v_expires timestamptz;
  v_ip text := _request_ip();
  v_fails int;
  v_last timestamptz;
begin
  delete from login_attempts where at < now() - interval '1 day';
  select count(*), max(at) into v_fails, v_last from login_attempts
   where ip = v_ip and not ok and at > now() - interval '15 minutes';
  if v_fails >= 8 then
    return jsonb_build_object('ok', false, 'reason', 'locked',
                              'retry_after', ceil(extract(epoch from (v_last + interval '15 minutes' - now()))));
  end if;

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
  delete from login_attempts where ip = v_ip;
  insert into manager_sessions (manager_id, auth_uid) values (v_manager.id, _auth_uid_safe())
    returning token, expires_at into v_token, v_expires;
  if v_manager.role = 'manufacturer' then
    v_expires := _maker_session_end();
    update manager_sessions set expires_at = v_expires where token = v_token;
  end if;
  return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name,
                            'role', v_manager.role, 'expires_at', v_expires,
                            'repairAccess', _support_access_open());
end $$;
grant execute on function manager_login(text) to anon, authenticated;

-- ── heartbeat: a device key is required, except for a device still waiting to be paired ──
create or replace function device_heartbeat(p_device_id text, p_device_name text, p_info jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_info jsonb; v_dev text := _current_device_id(); v_mt text;
begin
  -- a logged-in account on this app session: remember the session (live updates need it)
  v_mt := _request_headers() ->> 'x-manager-token';
  if v_mt is not null and v_mt <> '' and _auth_uid_safe() is not null then
    update manager_sessions set auth_uid = _auth_uid_safe()
     where token = v_mt and expires_at > now() and auth_uid is distinct from _auth_uid_safe();
  end if;

  if p_device_id is null or p_device_id !~ '^[A-Za-z0-9_-]{6,64}$' then return jsonb_build_object('ok', false); end if;
  if v_dev is not null and v_dev <> p_device_id then return jsonb_build_object('ok', false, 'error', 'not_this_device'); end if;

  if v_dev is null then
    -- no device key: only an unpaired, non-retired device may say it is alive (nothing else changes)
    if not exists(select 1 from devices_pilot where id = p_device_id
                   and assigned_role is null and coalesce(device_status, 'active') <> 'retired') then
      return jsonb_build_object('ok', false, 'error', 'device_auth_required');
    end if;
    update devices_pilot set last_seen = now() where id = p_device_id;
    return jsonb_build_object('ok', true);
  end if;

  v_info := case when jsonb_typeof(p_info) = 'object' and length(p_info::text) < 2000 then p_info else null end;
  update devices_pilot set last_seen = now(), app_info = coalesce(v_info, app_info),
         auth_uid = coalesce(_auth_uid_safe(), auth_uid)
   where id = p_device_id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function device_heartbeat(text, text, jsonb) to anon, authenticated;

-- ── device protection: always on; the app can only switch it ON ──
create or replace function device_auth_set(p_token text, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
grant execute on function device_auth_set(text, boolean) to anon, authenticated;

insert into system_flags (key, value) values ('device_auth_required', true)
  on conflict (key) do update set value = true;
insert into system_flags (key, value) values ('manager_auth_required', true)
  on conflict (key) do update set value = true;

-- ── no table-level rights beyond what the app uses (TRUNCATE ignores row security) ──
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' loop
    execute format('revoke truncate, trigger, references on public.%I from anon, authenticated', t);
    execute format('alter table public.%I no force row level security', t);   -- owner-run checks never recurse
  end loop;
end $$;

-- ── the app checks the server is up to date ──
create or replace function server_schema_step() returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select nullif(value, '')::integer from plant_state where key = 'schemaStep' and value ~ '^\d+$';
$$;
grant execute on function server_schema_step() to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '35')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ── self-check: stop with an error if any protection is missing ──
do $$
declare
  problems text[] := '{}';
  f text;
begin
  if position('auth_uid' in pg_get_functiondef('manager_login(text)'::regprocedure)) = 0
     or position('login_attempts' in pg_get_functiondef('manager_login(text)'::regprocedure)) = 0 then
    problems := array_append(problems, ('manager_login')::text); end if;
  if position('_is_real_manager' in pg_get_functiondef('device_pair(text,text,text,integer,boolean,text)'::regprocedure)) = 0 then
    problems := array_append(problems, ('device_pair')::text); end if;
  if position('pairing_requests' in pg_get_functiondef('device_request_pairing(text,text,text)'::regprocedure)) = 0 then
    problems := array_append(problems, ('device_request_pairing')::text); end if;
  if position('auth_uid' in pg_get_functiondef('device_pairing_status(text,text,text)'::regprocedure)) = 0 then
    problems := array_append(problems, ('device_pairing_status')::text); end if;
  if position('device_name' in pg_get_functiondef('plant_status_snapshot()'::regprocedure)) > 0 then
    problems := array_append(problems, ('plant_status_snapshot (device names)')::text); end if;
  if position('device_auth_required' in pg_get_functiondef('device_heartbeat(text,text,jsonb)'::regprocedure)) = 0 then
    problems := array_append(problems, ('device_heartbeat')::text); end if;
  if position('token_hash' in pg_get_functiondef('_current_device_id()'::regprocedure)) = 0 then
    problems := array_append(problems, ('_current_device_id (must check the device key)')::text); end if;
  foreach f in array array['animals_pilot','settings_pilot','events_pilot','daily_board_archive','devices_pilot'] loop
    if not exists(select 1 from pg_policies where schemaname = 'public' and tablename = f and policyname = 'read ' || f) then
      problems := array_append(problems, (('read policy ' || f))::text); end if;
    if exists(select 1 from pg_policies where schemaname = 'public' and tablename = f and cmd = 'SELECT'
                 and policyname <> 'read ' || f) then
      problems := array_append(problems, (('extra read policy on ' || f))::text); end if;
  end loop;
  if exists(select 1 from pg_policies where schemaname = 'public'
              and tablename in ('devices_pilot','settings_pilot','device_credentials','manager_sessions','plant_managers','system_flags')
              and cmd in ('INSERT','UPDATE','DELETE','ALL')) then
    problems := array_append(problems, ('write policy on a protected table')::text); end if;
  if not coalesce((select value from system_flags where key = 'device_auth_required'), false) then
    problems := array_append(problems, ('device protection is off')::text); end if;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack security self-check FAILED: %', array_to_string(problems, ', ');
  end if;
  raise notice 'GlattTrack security self-check: OK';
end $$;

notify pgrst, 'reload schema';


-- ============================================================================
-- STEP 36: second security review follow-up (24/09)
-- ============================================================================
--  • Code-guessing lock can't be dodged by faking the address: the address
--    now comes only from the plant's own web server (X-GT-Client-IP, set by
--    nginx, which also strips anything the tablet sends), or from the cloud's
--    edge (CF-Connecting-IP). Anything else counts as one shared address.
--    Plus an overall brake: many wrong codes from everywhere slow every try.
--  • The old 2-value device_heartbeat (from step 15) is removed — it could
--    still register or refresh a device without any key.
--  • The first team leader of a new plant needs the plant's one-time SETUP
--    CODE (printed by the installer), not just an empty server.
--  • A tablet must always say which day its board is from; a board with no
--    day (or an older day) is refused.
--  • Pairing requests are handled one at a time (the pending-code limit
--    can't be raced past).
--  • Heartbeat keeps only known fields of the app info (v, screen, lang, local).
--  • Device keys are never deleted: a revoked key keeps its revoke time
--    (history for audits).
--  • The full event-log check can be run only by the plant's accounts.
--  • Row security helpers used by old tables get a fixed search_path.
--  • App users have NO table rights on any internal table, and can't run
--    internal helper functions.
--  • security_summary(): failed logins, locked addresses, pairing floods,
--    revoked keys — for the team leader / manufacturer.
--  • The self-check now TESTS behaviour (fake keys, revoked keys, expired
--    sessions, owner vs team leader, faked addresses) and privileges,
--    not just the text of the functions.
-- Safe to run more than once. Run after step 35.
-- ============================================================================

-- ── the caller's address: only from sources the caller can't forge ──
create or replace function _request_ip() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare h json; v text;
begin
  h := _request_headers();
  if h is null then return 'local'; end if;
  -- cloud edge (Cloudflare replaces any value a client sends), then the plant's nginx
  v := coalesce(nullif(h ->> 'cf-connecting-ip', ''), nullif(h ->> 'x-gt-client-ip', ''));
  if v is null then return 'unknown'; end if;     -- X-Forwarded-For is NOT trusted: the client can write it
  return left(trim(v), 64);
end $$;
revoke execute on function _request_ip() from public, anon, authenticated;

-- ── remove the old heartbeat that needed no key ──
drop function if exists device_heartbeat(text, text);

-- ── heartbeat: known app-info fields only ──
create or replace function device_heartbeat(p_device_id text, p_device_name text, p_info jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_info jsonb; v_dev text := _current_device_id(); v_mt text;
begin
  v_mt := _request_headers() ->> 'x-manager-token';
  if v_mt is not null and v_mt <> '' and _auth_uid_safe() is not null then
    update manager_sessions set auth_uid = _auth_uid_safe()
     where token = v_mt and expires_at > now() and auth_uid is distinct from _auth_uid_safe();
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
         auth_uid = coalesce(_auth_uid_safe(), auth_uid)
   where id = p_device_id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function device_heartbeat(text, text, jsonb) to anon, authenticated;

-- ── first team leader: needs the plant's one-time setup code ──
create or replace function _set_setup_code(p_code text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_code is null or length(p_code) < 8 then raise exception 'setup code too short'; end if;
  insert into plant_state (key, value) values ('setupCodeHash', crypt(upper(p_code), gen_salt('bf')))
    on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;
revoke execute on function _set_setup_code(text) from public, anon, authenticated;

drop function if exists create_first_manager(text, text);
create or replace function create_first_manager(p_name text, p_code text, p_setup_code text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid; v_hash text; v_ip text := _request_ip(); v_fails int;
begin
  perform pg_advisory_xact_lock(hashtext('glatttrack_first_manager'));
  if exists(select 1 from plant_managers where role = 'manager' and active) then
    return jsonb_build_object('ok', false, 'error', 'a manager already exists — use manager_add instead');
  end if;
  select value into v_hash from plant_state where key = 'setupCodeHash';
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
  if p_code is null or length(p_code) < 4 then
    return jsonb_build_object('ok', false, 'error', 'code too short (minimum 4 characters)');
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
grant execute on function create_first_manager(text, text, text) to anon, authenticated;

-- ── manager_login: an overall brake on top of the per-address lock ──
create or replace function manager_login(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
  -- many wrong codes from everywhere: every attempt waits longer (slows a spread-out attack)
  select count(*) into v_all from login_attempts where not ok and at > now() - interval '15 minutes';
  if v_all >= 30 then perform pg_sleep(least(3.0, v_all / 30.0)); end if;

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
  delete from login_attempts where ip = v_ip;
  insert into manager_sessions (manager_id, auth_uid) values (v_manager.id, _auth_uid_safe())
    returning token, expires_at into v_token, v_expires;
  if v_manager.role = 'manufacturer' then
    v_expires := _maker_session_end();
    update manager_sessions set expires_at = v_expires where token = v_token;
  end if;
  return jsonb_build_object('ok', true, 'token', v_token, 'name', v_manager.name,
                            'role', v_manager.role, 'expires_at', v_expires,
                            'repairAccess', _support_access_open());
end $$;
grant execute on function manager_login(text) to anon, authenticated;

-- ── device keys: revoked, never deleted (with the time) ──
alter table device_credentials add column if not exists revoked_at timestamptz;
create or replace function _credential_revoked_at() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if new.revoked and not coalesce(old.revoked, false) then new.revoked_at := now(); end if;
  if not new.revoked then new.revoked_at := null; end if;
  return new;
end $$;
drop trigger if exists credential_revoked_at on device_credentials;
create trigger credential_revoked_at before update on device_credentials
  for each row execute function _credential_revoked_at();
update device_credentials set revoked_at = coalesce(revoked_at, created_at) where revoked and revoked_at is null;
create index if not exists device_credentials_hash_live on device_credentials (token_hash) where not revoked;

-- ── row-security helpers of the older tables: fixed search_path ──
alter function _my_plant() set search_path = public, extensions, pg_temp;
alter function _my_role() set search_path = public, extensions, pg_temp;

CREATE OR REPLACE FUNCTION public.device_request_pairing(p_device_id text, p_secret text, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.verify_event_chain()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
end $function$;


-- ── the day of the board: always announced, always required ──
CREATE OR REPLACE FUNCTION public._animals_merge()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_epoch bigint := _board_epoch();
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;

  -- yesterday's board may never come back (a tablet offline over the reset)
  if v_epoch is not null and _is_api_request() and (new.board_epoch is null or new.board_epoch < v_epoch) then
    raise exception 'stale-board: this device still has the previous day''s board' using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    new.board_epoch := coalesce(v_epoch, new.board_epoch);
    return new;
  end if;
  new.board_epoch := coalesce(v_epoch, new.board_epoch, old.board_epoch);

  -- timed groups: keep the server's values when the incoming copy is older
  if old.slaughter_time is not null and (new.slaughter_time is null or new.slaughter_time < old.slaughter_time) then
    new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
    new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
    new.eso_result := coalesce(old.eso_result, new.eso_result);
    new.eso_prev_slaughter := coalesce(old.eso_prev_slaughter, new.eso_prev_slaughter);
  end if;
  if old.inner_time is not null and (new.inner_time is null or new.inner_time < old.inner_time) then
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
  end if;
  if old.outer_time is not null and (new.outer_time is null or new.outer_time < old.outer_time) then
    new.outer_status := old.outer_status; new.outer_time := old.outer_time;
    new.outer_by := old.outer_by; new.outer_by_device := old.outer_by_device;
  end if;
  if new.slaughter is null and old.slaughter is not null and new.slaughter_time is null then new.slaughter := old.slaughter; end if;
  if new.outer_status is null and old.outer_status is not null and new.outer_time is null then new.outer_status := old.outer_status; end if;

  -- each station rules only its own stage: another station's copy can't change it
  if coalesce(current_setting('gt.eso_ruling', true), '') <> 'true' then
    if new.slaughter is distinct from old.slaughter and not _stage_allowed('slaughter') then
      new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
      new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
    end if;
    if new.eso_result is distinct from old.eso_result and not _stage_allowed('eso') then
      new.eso_result := old.eso_result;
    end if;
  end if;
  if new.inner_status is distinct from old.inner_status and not _stage_allowed('inner') then
    new.inner_status := old.inner_status; new.inner_time := old.inner_time;
    new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
  end if;
  if new.outer_status is distinct from old.outer_status and not _stage_allowed('outer') then
    new.outer_status := old.outer_status; new.outer_time := old.outer_time;
    new.outer_by := old.outer_by; new.outer_by_device := old.outer_by_device;
  end if;

  -- once yes, stays yes
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
  new.not_chalak_inner      := coalesce(old.not_chalak_inner, false)      or coalesce(new.not_chalak_inner, false);
  new.eso_checked           := coalesce(old.eso_checked, false)           or coalesce(new.eso_checked, false);
  new.legs_sorted           := coalesce(old.legs_sorted, false)           or coalesce(new.legs_sorted, false);

  -- an empty value never erases a recorded one
  new.maw           := coalesce(new.maw, old.maw);
  new.rumen         := coalesce(new.rumen, old.rumen);
  new.weight_right  := coalesce(new.weight_right, old.weight_right);
  new.weight_left   := coalesce(new.weight_left, old.weight_left);
  new.weight_stage2 := coalesce(new.weight_stage2, old.weight_stage2);
  new.weight_stage3 := coalesce(new.weight_stage3, old.weight_stage3);
  new.eso_result    := coalesce(new.eso_result, old.eso_result);

  new.parts_print_count := greatest(coalesce(old.parts_print_count, 0), coalesce(new.parts_print_count, 0));
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_rows integer;
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_row jsonb;
  v_dev text;
  v_epoch bigint := _board_epoch();
  v_stage text := case when p_stage = 'inner_start' then 'inner' else p_stage end;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('claimed', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then   -- a device must say which day its board is from
    return jsonb_build_object('claimed', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed(v_stage) then
    return jsonb_build_object('claimed', false, 'error', 'wrong_station');
  end if;
  -- a paired device is always recorded as itself, whatever it claims to be
  v_dev := coalesce(_current_device_id(), p_device_id);

  insert into animals_pilot (id, board_epoch) values (p_id, v_epoch) on conflict (id) do nothing;

  if p_stage = 'slaughter' then
    update animals_pilot
       set slaughter = p_value, slaughtered_by = p_actor, slaughter_by_device = v_dev, device_id = v_dev,
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), updated_at = now()
     where id = p_id and slaughter is null;

  elsif p_stage = 'inner_start' then
    -- open the lung check: only if nobody else has this animal
    update animals_pilot
       set inner_status = 'in_progress', inner_by = p_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id and (inner_status is null
                          or (inner_status = 'in_progress'
                              and (inner_by_device is null or inner_by_device = v_dev
                                   or inner_time < v_now - 600000)));   -- a check left open 10+ min can be taken over

  elsif p_stage = 'inner' then
    if p_value not in ('confirmed','treif') then
      raise exception 'claim_animal_stage: bad inner result %', p_value;
    end if;
    update animals_pilot
       set inner_status = p_value, inner_by = p_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id
       and (inner_status is null
            or (inner_status = 'in_progress' and (inner_by_device is null or inner_by_device = v_dev
                                                  or inner_time < v_now - 600000)));

  elsif p_stage = 'outer' then
    update animals_pilot
       set outer_status = p_value, outer_by = p_actor, outer_by_device = v_dev, device_id = v_dev,
           outer_time = greatest(v_now, coalesce(outer_time, 0) + 1), updated_at = now()
     where id = p_id and outer_status is null;

  elsif p_stage = 'eso' then
    if p_value not in ('ok','nevela') then
      raise exception 'claim_animal_stage: bad esophagus result %', p_value;
    end if;
    perform set_config('gt.eso_ruling', 'true', true);
    update animals_pilot
       set eso_checked = true,
           eso_result = p_value,
           eso_prev_slaughter = case when p_value = 'nevela' then slaughter else eso_prev_slaughter end,
           slaughter = case when p_value = 'nevela' then 'nevela' else slaughter end,
           slaughter_time = case when p_value = 'nevela' then greatest(v_now, coalesce(slaughter_time, 0) + 1) else slaughter_time end,
           slaughter_by_device = case when p_value = 'nevela' then v_dev else slaughter_by_device end,
           updated_at = now()
     where id = p_id and (eso_checked is distinct from true);
    perform set_config('gt.eso_ruling', '', true);

  elsif p_stage = 'legs' then
    update animals_pilot set legs_sorted = true, updated_at = now()
     where id = p_id and (legs_sorted is distinct from true);

  elsif p_stage = 'stamped' then
    update animals_pilot set stamped = true, updated_at = now()
     where id = p_id and (stamped is distinct from true);

  else
    raise exception 'claim_animal_stage: unknown stage %', p_stage;
  end if;

  get diagnostics v_rows = row_count;
  select to_jsonb(a.*) into v_row from animals_pilot a where a.id = p_id;
  return jsonb_build_object('claimed', v_rows = 1, 'row', v_row, 'serverNow', v_now);
end $function$;
grant execute on function claim_animal_stage(integer, text, text, text, text, bigint) to anon, authenticated;

-- every plant has a board day from the start (the tablets adopt it before sending anything)
insert into plant_state (key, value)
values ('boardEpoch', ((extract(epoch from clock_timestamp()) * 1000)::bigint)::text)
on conflict (key) do nothing;
insert into settings_pilot (id, settings, device_id, updated_at)
values (1, jsonb_build_object('boardEpoch', (select value::bigint from plant_state where key = 'boardEpoch')), 'server', now())
on conflict (id) do update
  set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('boardEpoch', (select value::bigint from plant_state where key = 'boardEpoch'))
  where (settings_pilot.settings -> 'boardEpoch') is null;
update animals_pilot set board_epoch = (select value::bigint from plant_state where key = 'boardEpoch') where board_epoch is null;

-- ── table rights: app users get only what the app really uses ──
do $$
declare t text;
begin
  -- internal tables: nothing at all (they are used only by the server's own functions)
  foreach t in array array['device_credentials','device_pairing','manager_sessions','plant_managers','system_flags',
                           'plant_state','login_attempts','pairing_requests','events_chain_head','outer_status_pilot'] loop
    if to_regclass('public.' || t) is not null then
      execute format('revoke all on public.%I from anon, authenticated', t);
    end if;
  end loop;
  -- read-only (row security decides which rows)
  foreach t in array array['settings_pilot','devices_pilot','daily_board_archive','device_lifecycle_events'] loop
    if to_regclass('public.' || t) is not null then
      execute format('revoke insert, update, delete, truncate, trigger, references on public.%I from anon, authenticated', t);
    end if;
  end loop;
  -- the board: add / change rows (guarded by triggers), never delete
  revoke delete, truncate, trigger, references on public.animals_pilot from anon, authenticated;
  -- the event log: add only
  revoke update, delete, truncate, trigger, references on public.events_pilot from anon, authenticated;
end $$;

-- ── internal helper functions: not callable by app users ──
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like '\_%'
              and p.proname not in ('_reader_ok', '_my_plant', '_my_role') loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- ── security summary for the team leader / manufacturer ──
create or replace function security_summary(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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
    'deviceProtection', _device_auth_required(),
    'schemaStep', (select value from plant_state where key = 'schemaStep')
  );
end $$;
grant execute on function security_summary(text) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '36')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ============================================================================
-- SELF-CHECK — behaviour, rights and rules. Any failure stops this file.
-- (the test rows it creates are rolled back)
-- ============================================================================
do $$
declare
  problems text[] := '{}';
  tok text := 'gtselftest' || encode(gen_random_bytes(16), 'hex');
  dev text := 'gtselftest_' || substr(md5(random()::text), 1, 10);
  mid uuid; mtok text;
  t text; p text; f record; r record;
  anon_roles text[] := array['anon', 'authenticated'];
  ro text;
begin
  -- 1. behaviour, inside a block that is rolled back at its end
  begin
    perform set_config('app.device_admin', 'on', true);
    insert into devices_pilot (id, device_name) values (dev, 'self-test');
    insert into device_credentials (device_id, token_hash) values (dev, encode(digest(tok, 'sha256'), 'hex'));
    perform set_config('app.device_admin', '', true);

    perform set_config('request.headers', json_build_object('x-device-token', tok)::text, true);
    if _current_device_id() is distinct from dev then problems := array_append(problems, 'a valid device key is not recognised'); end if;
    perform set_config('request.headers', '{"x-device-token":"not-a-real-key"}', true);
    if _current_device_id() is not null then problems := array_append(problems, 'a FAKE device key is accepted'); end if;
    perform set_config('request.headers', json_build_object('x-device-id', dev, 'x-device', dev)::text, true);
    if _current_device_id() is not null then problems := array_append(problems, 'a device ID without a key is accepted'); end if;
    update device_credentials set revoked = true where device_id = dev;
    perform set_config('request.headers', json_build_object('x-device-token', tok)::text, true);
    if _current_device_id() is not null then problems := array_append(problems, 'a REVOKED device key is accepted'); end if;
    if (select revoked_at from device_credentials where device_id = dev) is null then problems := array_append(problems, 'revoke time not recorded'); end if;

    insert into plant_managers (name, code_hash, role) values ('self-test', crypt(encode(gen_random_bytes(16), 'hex'), gen_salt('bf')), 'manager')
      returning id into mid;
    insert into manager_sessions (manager_id) values (mid) returning token into mtok;
    if not _is_real_manager(mtok) then problems := array_append(problems, 'a valid team-leader session is refused'); end if;
    if _is_real_manager('not-a-real-token') then problems := array_append(problems, 'a FAKE team-leader token is accepted'); end if;
    update manager_sessions set expires_at = now() - interval '1 minute' where token = mtok;
    if _is_real_manager(mtok) then problems := array_append(problems, 'an EXPIRED session is accepted'); end if;
    update manager_sessions set expires_at = now() + interval '1 hour' where token = mtok;
    update plant_managers set active = false where id = mid;
    if _is_real_manager(mtok) then problems := array_append(problems, 'a REMOVED account''s session is accepted'); end if;
    update plant_managers set active = true, role = 'owner' where id = mid;
    if _is_real_manager(mtok) then problems := array_append(problems, 'an OWNER is treated as a team leader'); end if;
    update plant_managers set role = 'manufacturer' where id = mid;
    if _is_real_manager(mtok) then problems := array_append(problems, 'the MANUFACTURER is treated as a team leader'); end if;

    perform set_config('request.headers', '{"x-forwarded-for":"6.6.6.6"}', true);
    if _request_ip() <> 'unknown' then problems := array_append(problems, 'the login lock trusts X-Forwarded-For'); end if;
    perform set_config('request.headers', '{"x-forwarded-for":"6.6.6.6","x-gt-client-ip":"10.1.2.3"}', true);
    if _request_ip() <> '10.1.2.3' then problems := array_append(problems, 'the login lock does not use the plant web server''s address'); end if;

    raise exception 'gt_selftest_rollback';
  exception when others then
    if sqlerrm <> 'gt_selftest_rollback' then problems := array_append(problems, 'self-test error: ' || sqlerrm); end if;
  end;
  perform set_config('request.headers', '', true);
  perform set_config('app.device_admin', '', true);

  -- 2. table rights of app users
  foreach ro in array anon_roles loop
    foreach t in array array['device_credentials','device_pairing','manager_sessions','plant_managers','system_flags',
                             'plant_state','login_attempts','pairing_requests','events_chain_head'] loop
      foreach p in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] loop
        if has_table_privilege(ro, 'public.' || t, p) then problems := array_append(problems, ro || ' can ' || p || ' ' || t); end if;
      end loop;
    end loop;
    foreach t in array array['settings_pilot','devices_pilot','daily_board_archive'] loop
      foreach p in array array['INSERT','UPDATE','DELETE','TRUNCATE'] loop
        if has_table_privilege(ro, 'public.' || t, p) then problems := array_append(problems, ro || ' can ' || p || ' ' || t); end if;
      end loop;
    end loop;
    foreach p in array array['DELETE','TRUNCATE'] loop
      if has_table_privilege(ro, 'public.animals_pilot', p) then problems := array_append(problems, ro || ' can ' || p || ' animals_pilot'); end if;
    end loop;
    foreach p in array array['UPDATE','DELETE','TRUNCATE'] loop
      if has_table_privilege(ro, 'public.events_pilot', p) then problems := array_append(problems, ro || ' can ' || p || ' events_pilot'); end if;
    end loop;
  end loop;

  -- 3. function rights and definitions
  for f in select p.oid, p.oid::regprocedure::text as sig, p.proname, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) as owner
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' loop
    if f.proname like '\_%' and f.proname not in ('_reader_ok', '_my_plant', '_my_role')
       and (has_function_privilege('anon', f.oid, 'EXECUTE') or has_function_privilege('authenticated', f.oid, 'EXECUTE')) then
      problems := array_append(problems, 'app users can run internal ' || f.sig);
    end if;
    if f.prosecdef and not coalesce(array_to_string(f.proconfig, ',') like '%search_path=%', false) then
      problems := array_append(problems, 'no fixed search_path: ' || f.sig);
    end if;
    if f.owner in ('anon', 'authenticated', 'authenticator') then
      problems := array_append(problems, 'owned by an app role: ' || f.sig);
    end if;
  end loop;
  if to_regprocedure('device_heartbeat(text,text)') is not null then problems := array_append(problems, 'old keyless heartbeat still exists'); end if;
  if to_regprocedure('create_first_manager(text,text)') is not null then problems := array_append(problems, 'old first-manager setup still exists'); end if;

  -- 4. row-security rules
  foreach t in array array['animals_pilot','settings_pilot','events_pilot','daily_board_archive','devices_pilot'] loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      problems := array_append(problems, 'row security OFF on ' || t); end if;
    for r in select * from pg_policies where schemaname = 'public' and tablename = t loop
      if r.cmd = 'SELECT' then
        if r.policyname <> 'read ' || t or r.permissive <> 'PERMISSIVE'
           or r.qual <> '( SELECT _reader_ok() AS _reader_ok)' or r.roles::text <> '{anon,authenticated}' then
          problems := array_append(problems, 'unexpected read rule on ' || t || ': ' || r.policyname);
        end if;
      elsif not ((t = 'animals_pilot' and r.cmd in ('INSERT','UPDATE')) or (t = 'events_pilot' and r.cmd = 'INSERT')) then
        problems := array_append(problems, 'unexpected ' || r.cmd || ' rule on ' || t || ': ' || r.policyname);
      end if;
    end loop;
  end loop;
  -- writes to the board and the log are allowed by the rules ONLY because these guards check every write
  foreach t in array array['animals_pilot','events_pilot'] loop
    if not exists(select 1 from pg_trigger tg join pg_proc pr on pr.oid = tg.tgfoid
                   where tg.tgrelid = ('public.' || t)::regclass and pr.proname = '_device_write_guard' and tg.tgenabled <> 'D') then
      problems := array_append(problems, 'write guard missing/disabled on ' || t); end if;
  end loop;
  foreach p in array array['a_animals_merge','animals_pilot_guard_corrections'] loop
    if not exists(select 1 from pg_trigger tg join pg_proc pr on pr.oid = tg.tgfoid
                   where tg.tgrelid = 'public.animals_pilot'::regclass and (tg.tgname = p or pr.proname = p) and tg.tgenabled <> 'D') then
      problems := array_append(problems, 'board guard missing/disabled: ' || p); end if;
  end loop;

  -- 5. live updates: every table sent live must be protected by row security
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime') then
    for r in select c.relname, c.relrowsecurity from pg_publication_tables pt
               join pg_class c on c.relname = pt.tablename join pg_namespace n on n.oid = c.relnamespace and n.nspname = pt.schemaname
              where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public' loop
      if not r.relrowsecurity then problems := array_append(problems, 'live table without row security: ' || r.relname); end if;
    end loop;
  end if;

  -- 6. switches
  if not coalesce((select value from system_flags where key = 'device_auth_required'), false) then
    problems := array_append(problems, 'device protection is OFF'); end if;
  if not coalesce((select value from system_flags where key = 'manager_auth_required'), false) then
    problems := array_append(problems, 'team-leader login check is OFF'); end if;

  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack security self-check FAILED: %', array_to_string(problems, ' | ');
  end if;
  raise notice 'GlattTrack security self-check (behaviour + rights + rules): OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 37 ============================
-- ============================================================================
-- GlattTrack — step 37: the inner inspector's lung drawing reaches the outer inspector
-- ============================================================================
-- Until now the lung drawing stayed only on the tablet that drew it, so an
-- outer inspector on another tablet saw an empty lung. This step keeps one
-- small compressed picture per animal on the server:
--   • lung_drawing_set(id, epoch, picture) — inner / outer station or team leader only,
--     current day only, picture must be a small jpeg/png/webp image (max ~450 KB text)
--   • lung_drawing_get(id)                  — any paired station / signed-in account
-- The table itself is closed: no direct reads or writes, only these two functions.
-- Old days' pictures are removed automatically when a new day starts drawing.
-- Safe to run more than once. Run after step 36.
-- ============================================================================

create table if not exists lung_drawings (
  id          integer primary key check (id >= 0 and id <= 999),
  board_epoch bigint,
  drawing     text not null,
  device_id   text,
  updated_at  timestamptz not null default now()
);
alter table lung_drawings enable row level security;
revoke all on table lung_drawings from public, anon, authenticated;

create or replace function lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := _board_epoch();
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
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
       values (p_id, v_epoch, p_drawing, _current_device_id(), now())
  on conflict (id) do update
     set board_epoch = excluded.board_epoch, drawing = excluded.drawing,
         device_id = excluded.device_id, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function lung_drawing_set(integer, bigint, text) from public;
grant  execute on function lung_drawing_set(integer, bigint, text) to anon, authenticated;

create or replace function lung_drawing_get(p_id integer) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare r record;
begin
  if not _reader_ok() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select drawing, extract(epoch from updated_at) * 1000 as t into r
    from lung_drawings where id = p_id and board_epoch is not distinct from _board_epoch();
  if not found then return jsonb_build_object('ok', true, 'drawing', null); end if;
  return jsonb_build_object('ok', true, 'drawing', r.drawing, 't', r.t::bigint);
end $$;
revoke execute on function lung_drawing_get(integer) from public;
grant  execute on function lung_drawing_get(integer) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '37')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ── self-check ──
do $$
declare problems text[] := '{}';
begin
  if has_table_privilege('anon', 'public.lung_drawings', 'select')
     or has_table_privilege('anon', 'public.lung_drawings', 'insert')
     or has_table_privilege('authenticated', 'public.lung_drawings', 'select') then
    problems := array_append(problems, 'lung_drawings is readable/writable directly');
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.lung_drawings'::regclass) then
    problems := array_append(problems, 'lung_drawings has no row security');
  end if;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 37 self-check FAILED: %', array_to_string(problems, '; ');
  end if;
  raise notice 'GlattTrack step 37 self-check OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 38 ============================
-- ============================================================================
-- GlattTrack — step 38: one animal is open on ONE outer screen at a time
-- ============================================================================
-- Opening an animal on an outer inspector screen now takes it on the server.
-- A second outer screen can't open the same animal: it shows it as
-- "open on another screen" and its blinking "next" moves to the following one.
--   • outer_open(id, epoch, open, device) — take (open=true) / let go (open=false)
--   • a screen that took an animal keeps it while its window is open (renewed
--     every 40 s); a screen that died loses it after 2 minutes
--   • the ruling itself (or the daily reset) always lets go
--   • nobody can set these two fields directly — only through outer_open
-- Safe to run more than once. Run after step 36 (37 is independent).
-- ============================================================================

alter table animals_pilot add column if not exists outer_open_by_device text;
alter table animals_pilot add column if not exists outer_open_at bigint;

-- the two lock fields change only through outer_open(); a ruling or a reset clears them
create or replace function _animals_outer_open_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
revoke execute on function _animals_outer_open_guard() from public, anon, authenticated;
drop trigger if exists zzz_outer_open_guard on animals_pilot;
create trigger zzz_outer_open_guard before insert or update on animals_pilot
  for each row execute function _animals_outer_open_guard();

drop function if exists outer_open(integer, bigint, boolean, text);
create or replace function outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_epoch bigint := _board_epoch();
  v_dev text;
  v_rows integer;
  r record;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed('outer') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  v_dev := coalesce(_current_device_id(), nullif(left(p_device_id, 80), ''));
  if v_dev is null then return jsonb_build_object('ok', false, 'error', 'no_device'); end if;

  perform set_config('gt.outer_open', 'true', true);
  if p_open then
    update animals_pilot
       set outer_open_by_device = v_dev, outer_open_at = v_now, updated_at = now()
     where id = p_id
       and (outer_open_by_device is null or outer_open_by_device = v_dev
            or outer_open_at is null or outer_open_at < v_now - 120000);
  else
    update animals_pilot
       set outer_open_by_device = null, outer_open_at = null, updated_at = now()
     where id = p_id and outer_open_by_device = v_dev;
  end if;
  get diagnostics v_rows = row_count;
  perform set_config('gt.outer_open', '', true);

  select outer_open_by_device, outer_open_at into r from animals_pilot where id = p_id;
  return jsonb_build_object('ok', true, 'claimed', (p_open and v_rows = 1),
                            'by', r.outer_open_by_device, 'at', r.outer_open_at, 'serverNow', v_now);
end $$;
revoke execute on function outer_open(integer, bigint, boolean, text) from public;
grant  execute on function outer_open(integer, bigint, boolean, text) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '38')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ── self-check ──
do $$
declare problems text[] := '{}'; v_old text; v_old_at bigint;
begin
  if not exists(select 1 from pg_trigger where tgname = 'zzz_outer_open_guard' and tgrelid = 'public.animals_pilot'::regclass) then
    problems := array_append(problems, 'outer-open guard trigger missing');
  end if;
  -- a direct write must not be able to set the lock
  begin
    insert into animals_pilot (id) values (0) on conflict (id) do nothing;
    select outer_open_by_device, outer_open_at into v_old, v_old_at from animals_pilot where id = 0;
    update animals_pilot set outer_open_by_device = 'gtselftest', outer_open_at = 1 where id = 0;
    if exists(select 1 from animals_pilot where id = 0 and outer_open_by_device = 'gtselftest') then
      problems := array_append(problems, 'the lock can be set by a direct write');
    end if;
    raise exception 'gt_rollback';
  exception when others then
    if sqlerrm <> 'gt_rollback' then problems := array_append(problems, 'lock test: ' || sqlerrm); end if;
  end;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 38 self-check FAILED: %', array_to_string(problems, '; ');
  end if;
  raise notice 'GlattTrack step 38 self-check OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 39 ============================
-- ============================================================================
-- GlattTrack — step 39: week / month / year reports come from the server
-- ============================================================================
-- The server already keeps a copy of every day's board (daily_board_archive),
-- but the reports only read the copy kept on the tablet that happened to be
-- open when the day changed. Now:
--   • each archived day also keeps that day's farm intake (farm / cattle type)
--   • archive_days(token, from, to) — the team leader or owner reads the days
--     of a period, reduced to what the reports need (no pictures, no device data)
-- Safe to run more than once. Run after step 38.
-- ============================================================================

alter table daily_board_archive add column if not exists intake jsonb;

-- keep the day's intake with the archived board (the reset clears it right after)
create or replace function _archive_keep_intake() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if new.intake is null then
    select coalesce(settings -> 'dailyIntake', '[]'::jsonb) into new.intake from settings_pilot where id = 1;
  end if;
  return new;
end $$;
revoke execute on function _archive_keep_intake() from public, anon, authenticated;
drop trigger if exists a_archive_keep_intake on daily_board_archive;
create trigger a_archive_keep_intake before insert on daily_board_archive
  for each row execute function _archive_keep_intake();

drop function if exists archive_days(text, date, date);
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
             'animals', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'n',  (x ->> 'id')::int,
                        's',  x ->> 'slaughter',
                        'i',  x ->> 'inner_status',
                        'o',  x ->> 'outer_status',
                        'sb', x ->> 'slaughtered_by',
                        'ib', x ->> 'inner_by',
                        'ob', x ->> 'outer_by',
                        'st', (x ->> 'slaughter_time'),
                        'nc', coalesce((x ->> 'not_chalak_inner')::boolean, false)
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
grant  execute on function archive_days(text, date, date) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '39')
  on conflict (key) do update set value = excluded.value, updated_at = now();

do $$
begin
  if (archive_days('no-such-token', current_date - 7, current_date) ->> 'ok')::boolean then
    raise exception 'GlattTrack step 39 self-check FAILED: archive_days answers without a team-leader session';
  end if;
  raise notice 'GlattTrack step 39 self-check OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 40 ============================
-- ============================================================================
-- GlattTrack — step 40: second integrity review (sync + server rules)
-- ============================================================================
--  • "Who did it" comes from the server: a paired tablet is always recorded as
--    itself (its key), whatever device name it sends. The "already moved on"
--    lock and the per-station "last animal" use that server-known device.
--  • Each station can change only its own part of an animal:
--      slaughter group (status, time, by, device) — slaughter station
--      inner group + maw + rumen + "not chalak" — inner (and outer) inspectors
--      outer group — outer (and inner) inspectors
--      esophagus result — only through the esophagus ruling (claim / change);
--        an esophagus "nevela" sent by an offline tablet is applied whole
--        (slaughter = nevela, previous status kept) or not at all
--      legs sorted / legs + head stickers — legs station
--      stamped + stamped_as — stamps (and parts) station
--      parts scanned / tongue + cheek stickers / print count / parts_printed_as
--        — small parts station
--      weights and "skipped" flags — the stamps station (it hosts the scale)
--    A signed-in team leader and the server itself may change anything.
--  • A tablet's clock can't put a ruling in the future (times capped at
--    server time + 60 s).
--  • A late "close lung check" can't wipe a final inner ruling, and only the
--    tablet that opened a lung check (or a team leader) can abandon it.
--  • "Not chalak" (inner) travels WITH the inner group: it can be cleared
--    again, and the newer inner group wins (no separate time column).
--  • The server stamps updated_at itself (so the 20 s catch-up never misses).
--  • First claims / esophagus change / outer screen lock can't land on a board
--    that was reset a moment ago (board day checked inside the update).
--  • claim_animal_stage('eso') answers claimed:false when nothing changed.
--  • eso_change checks the board day (p_epoch), like the claims.
--  • Animal numbers are 0..999 only; a new row sent by a tablet starts empty.
--  • New label fields: parts_printed_as, stamped_as.
--  • archive_days also returns each animal's weights (wr / wl).
--  • push_settings records the paired device's own id.
-- Safe to run more than once. Run after step 39.
-- ============================================================================

-- ── new label-tracking columns ──────────────────────────────────────────────
alter table animals_pilot add column if not exists parts_printed_as text;
alter table animals_pilot add column if not exists stamped_as text;

-- ── animal number range 0..999 ──────────────────────────────────────────────
do $$
begin
  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);
  delete from animals_pilot where id < 0 or id > 999;
  perform set_config('gt.reset_in_progress', 'false', true);
  perform set_config('app.device_admin', '', true);
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.animals_pilot'::regclass and conname = 'animals_pilot_id_range') then
    alter table animals_pilot add constraint animals_pilot_id_range check (id between 0 and 999) not valid;
  end if;
  alter table animals_pilot validate constraint animals_pilot_id_range;
end $$;
-- every animal row of the board exists (claims insert with "on conflict do nothing")
insert into animals_pilot (id, board_epoch)
select g, (select nullif(value, '')::bigint from plant_state where key = 'boardEpoch' and value ~ '^\d+$')
  from generate_series(0, 999) g
on conflict (id) do nothing;

-- ── is this call from the team leader / the server itself? ──────────────────
create or replace function _request_privileged() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _device_auth_required() then return true; end if;
  if not _is_api_request() then return true; end if;
  if _request_is_service_role() then return true; end if;
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  if _request_has_manager() then return true; end if;
  return false;
end $$;
revoke execute on function _request_privileged() from public, anon, authenticated;

-- ── which station may change which part ─────────────────────────────────────
create or replace function _stage_allowed(p_stage text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text;
begin
  if _request_privileged() then return true; end if;
  v_role := _caller_device_role();
  if v_role is null then return false; end if;
  return case p_stage
    when 'slaughter' then v_role in ('slaughter')
    when 'eso'       then v_role in ('esophagus','slaughter')
    when 'inner'     then v_role in ('inner','outer')
    when 'outer'     then v_role in ('outer','inner')
    when 'legs'      then v_role in ('legs')
    when 'stamped'   then v_role in ('stamps','parts')
    when 'parts'     then v_role in ('parts')
    when 'weights'   then v_role in ('stamps')        -- the scale is on the stamps screen
    else false end;
end $$;
revoke execute on function _stage_allowed(text) from public, anon, authenticated;

-- ── the merge: every write to an animal passes here ─────────────────────────
create or replace function _animals_merge() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_epoch bigint := _board_epoch();
  v_api   boolean := _is_api_request();
  v_dev   text := _current_device_id();
  v_priv  boolean;
  v_now   bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_cap   bigint;
  v_eso   boolean := coalesce(current_setting('gt.eso_ruling', true), '') = 'true';
  v_eso_upsert boolean := false;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;

  -- yesterday's board may never come back (a tablet offline over the reset)
  if v_epoch is not null and v_api and (new.board_epoch is null or new.board_epoch < v_epoch) then
    raise exception 'stale-board: this device still has the previous day''s board' using errcode = 'P0001';
  end if;

  new.updated_at := clock_timestamp();                       -- the server's clock, never the tablet's
  if v_api and v_dev is not null then new.device_id := v_dev; end if;   -- a paired tablet is always itself

  if tg_op = 'INSERT' then
    new.board_epoch := coalesce(v_epoch, new.board_epoch);
    -- a tablet can't create an animal with values in it (rows 0..999 always
    -- exist; an upsert of an existing row goes on to the UPDATE rules below)
    if v_api and not exists (select 1 from animals_pilot x where x.id = new.id) then
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
      new.eso_checked := false; new.eso_result := null; new.eso_prev_slaughter := null;
    end if;
    return new;
  end if;
  new.board_epoch := coalesce(v_epoch, new.board_epoch, old.board_epoch);
  v_priv := _request_privileged();

  -- a tablet's clock can't put a ruling in the future
  if v_api then
    v_cap := v_now + 60000;
    if new.slaughter_time is distinct from old.slaughter_time and new.slaughter_time > v_cap then new.slaughter_time := v_cap; end if;
    if new.inner_time     is distinct from old.inner_time     and new.inner_time     > v_cap then new.inner_time     := v_cap; end if;
    if new.outer_time     is distinct from old.outer_time     and new.outer_time     > v_cap then new.outer_time     := v_cap; end if;
  end if;

  -- esophagus: only through the ruling itself — except a "nevela" sent by an
  -- esophagus tablet that was offline, which is applied whole
  if not v_eso then
    if new.eso_result = 'nevela' and old.eso_result is distinct from 'nevela' and _stage_allowed('eso') then
      v_eso_upsert := true;
      new.eso_checked := true;
      new.eso_prev_slaughter := case when old.slaughter = 'nevela' then coalesce(old.eso_prev_slaughter, 'slaughtered')
                                     else old.slaughter end;
      new.slaughter := 'nevela';
      new.slaughtered_by := old.slaughtered_by;
      new.slaughter_time := greatest(v_now, coalesce(old.slaughter_time, 0) + 1);
      new.slaughter_by_device := coalesce(v_dev, new.device_id);
      perform set_config('gt.eso_upsert_row', new.id::text, true);   -- for the "moved on" check below
    else
      new.eso_result := old.eso_result;
      new.eso_checked := old.eso_checked;
      new.eso_prev_slaughter := old.eso_prev_slaughter;
    end if;
  end if;

  -- timed groups: keep the server's values when the incoming copy is older
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
     and (not v_priv or new.slaughter_time is null) then              -- a slaughter status is never cleared by a tablet
    new.slaughter := old.slaughter; new.slaughter_time := old.slaughter_time;
    new.slaughtered_by := old.slaughtered_by; new.slaughter_by_device := old.slaughter_by_device;
  end if;
  if new.outer_status is null and old.outer_status is not null and new.outer_time is null then new.outer_status := old.outer_status; end if;

  -- a late "close the lung check" never wipes a final inner ruling, and only
  -- the tablet that opened the check (or the team leader) can abandon it
  if new.inner_status is null and old.inner_status is not null then
    if old.inner_status in ('confirmed', 'treif')
       or (old.inner_status = 'in_progress' and not v_priv
           and old.inner_by_device is distinct from coalesce(v_dev, new.device_id)) then
      new.inner_status := old.inner_status; new.inner_time := old.inner_time;
      new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
      new.not_chalak_inner := old.not_chalak_inner;
    end if;
  end if;

  -- each station rules only its own stage: another station's copy can't
  -- change any part of it (status, time, who, which tablet)
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

  -- a group that changed is recorded as done by the tablet that sent it
  if v_api and v_dev is not null then
    if (new.slaughter, new.slaughter_time) is distinct from (old.slaughter, old.slaughter_time) then new.slaughter_by_device := v_dev; end if;
    if (new.inner_status, new.inner_time) is distinct from (old.inner_status, old.inner_time) then new.inner_by_device := v_dev; end if;
    if (new.outer_status, new.outer_time) is distinct from (old.outer_status, old.outer_time) then new.outer_by_device := v_dev; end if;
  end if;

  -- the other parts of the animal, per station
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

  -- once yes, stays yes
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
  new.not_chalak_inner      := coalesce(new.not_chalak_inner, false);      -- follows the inner group (can be cleared)

  -- an empty value never erases a recorded one
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
revoke execute on function _animals_merge() from public, anon, authenticated;

-- ── "already moved on" lock: uses the server-known device ───────────────────
create or replace function animals_pilot_guard_corrections() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d record; v_dev text; v_eso boolean;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;
  v_eso := coalesce(current_setting('gt.eso_ruling', true), '') = 'true'
           or coalesce(current_setting('gt.eso_upsert_row', true), '') = new.id::text;
  if coalesce(current_setting('gt.eso_upsert_row', true), '') <> '' then
    perform set_config('gt.eso_upsert_row', '', true);
  end if;
  v_dev := case when _is_api_request()
                then coalesce(_current_device_id(), case when _request_privileged() then new.device_id end)
                else new.device_id end;

  -- an esophagus nevela can only be changed by the esophagus ruling itself
  if old.eso_result = 'nevela' and new.slaughter is distinct from old.slaughter and not v_eso then
    raise exception 'correction-blocked: failed the esophagus check — only the esophagus screen can change it';
  end if;

  if old.slaughter is not null and new.slaughter is distinct from old.slaughter and not v_eso then
    select cursor_slaughter into d from public.devices_pilot where id = v_dev;
    if d.cursor_slaughter is distinct from new.id then
      raise exception 'correction-blocked: already moved on — slaughter status is locked';
    end if;
  end if;

  if old.inner_status is not null and old.inner_status is distinct from 'in_progress' and new.inner_status is distinct from old.inner_status then
    select cursor_inner into d from public.devices_pilot where id = v_dev;
    if d.cursor_inner is distinct from new.id then
      raise exception 'correction-blocked: already moved on — inner status is locked';
    end if;
  end if;

  if old.outer_status is not null and new.outer_status is distinct from old.outer_status then
    select cursor_outer into d from public.devices_pilot where id = v_dev;
    if d.cursor_outer is distinct from new.id then
      raise exception 'correction-blocked: already moved on — outer status is locked';
    end if;
  end if;

  return new;
end $$;

create or replace function animals_pilot_advance_cursor() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if tg_op = 'UPDATE' and current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if new.device_id is null then return new; end if;
  -- new.device_id is the server-known tablet (set by _animals_merge)
  if (tg_op = 'INSERT' or old.slaughter is null) and new.slaughter is not null then
    update devices_pilot set cursor_slaughter = new.id where id = new.device_id;
  end if;
  if (tg_op = 'INSERT' or old.inner_status is null) and new.inner_status is not null then
    update devices_pilot set cursor_inner = new.id where id = new.device_id;
  end if;
  if (tg_op = 'INSERT' or old.outer_status is null) and new.outer_status is not null then
    update devices_pilot set cursor_outer = new.id where id = new.device_id;
  end if;
  return new;
end $$;

-- ── first claims: the right answer, and never onto a board reset meanwhile ──
-- (a row's board day moves only forward: "board_epoch <= the day read at the
--  start" is false exactly when a reset landed in between)
create or replace function claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_rows integer := 0;
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_row jsonb;
  v_dev text;
  v_epoch bigint := _board_epoch();
  v_stage text := case when p_stage = 'inner_start' then 'inner' else p_stage end;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('claimed', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then   -- a device must say which day its board is from
    return jsonb_build_object('claimed', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed(v_stage) then
    return jsonb_build_object('claimed', false, 'error', 'wrong_station');
  end if;
  -- a paired device is always recorded as itself, whatever it claims to be
  v_dev := coalesce(_current_device_id(), p_device_id);

  insert into animals_pilot (id, board_epoch) values (p_id, v_epoch) on conflict (id) do nothing;

  if p_stage = 'slaughter' then
    update animals_pilot
       set slaughter = p_value, slaughtered_by = p_actor, slaughter_by_device = v_dev, device_id = v_dev,
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), updated_at = now()
     where id = p_id and slaughter is null
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;

  elsif p_stage = 'inner_start' then
    -- open the lung check: only if nobody else has this animal
    update animals_pilot
       set inner_status = 'in_progress', inner_by = p_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id and (inner_status is null
                          or (inner_status = 'in_progress'
                              and (inner_by_device is null or inner_by_device = v_dev
                                   or inner_time < v_now - 600000)))   -- a check left open 10+ min can be taken over
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;

  elsif p_stage = 'inner' then
    if p_value not in ('confirmed','treif') then
      raise exception 'claim_animal_stage: bad inner result %', p_value;
    end if;
    update animals_pilot
       set inner_status = p_value, inner_by = p_actor, inner_by_device = v_dev, device_id = v_dev,
           inner_time = greatest(v_now, coalesce(inner_time, 0) + 1), updated_at = now()
     where id = p_id
       and (inner_status is null
            or (inner_status = 'in_progress' and (inner_by_device is null or inner_by_device = v_dev
                                                  or inner_time < v_now - 600000)))
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;

  elsif p_stage = 'outer' then
    update animals_pilot
       set outer_status = p_value, outer_by = p_actor, outer_by_device = v_dev, device_id = v_dev,
           outer_time = greatest(v_now, coalesce(outer_time, 0) + 1), updated_at = now()
     where id = p_id and outer_status is null
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;

  elsif p_stage = 'eso' then
    if p_value not in ('ok','nevela') then
      raise exception 'claim_animal_stage: bad esophagus result %', p_value;
    end if;
    perform set_config('gt.eso_ruling', 'true', true);
    update animals_pilot
       set eso_checked = true,
           eso_result = p_value,
           eso_prev_slaughter = case when p_value = 'nevela' then slaughter else eso_prev_slaughter end,
           slaughter = case when p_value = 'nevela' then 'nevela' else slaughter end,
           slaughter_time = case when p_value = 'nevela' then greatest(v_now, coalesce(slaughter_time, 0) + 1) else slaughter_time end,
           slaughter_by_device = case when p_value = 'nevela' then v_dev else slaughter_by_device end,
           device_id = v_dev,
           updated_at = now()
     where id = p_id and (eso_checked is distinct from true)
       and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
    get diagnostics v_rows = row_count;          -- before anything else runs
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

  else
    raise exception 'claim_animal_stage: unknown stage %', p_stage;
  end if;

  select to_jsonb(a.*) into v_row from animals_pilot a where a.id = p_id;
  return jsonb_build_object('claimed', v_rows = 1, 'row', v_row, 'serverNow', v_now);
end $$;
revoke execute on function claim_animal_stage(integer, text, text, text, text, bigint) from public;
grant  execute on function claim_animal_stage(integer, text, text, text, text, bigint) to anon, authenticated;

-- ── esophagus change: board day checked like the claims ─────────────────────
drop function if exists eso_change(integer, text, text);
create or replace function eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  a animals_pilot%rowtype;
  v_row jsonb;
  v_rows integer := 0;
  v_epoch bigint := _board_epoch();
  v_dev text := coalesce(_current_device_id(), p_device_id);
begin
  if p_result is null or p_result not in ('ok','nevela') then
    return jsonb_build_object('ok', false, 'error', 'bad_result');
  end if;
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed('eso') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  select * into a from animals_pilot where id = p_id for update;
  if a.id is null or a.eso_checked is distinct from true then
    return jsonb_build_object('ok', false, 'error', 'not_checked');
  end if;
  if coalesce(a.board_epoch, 0) > coalesce(v_epoch, 0) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', a.board_epoch);
  end if;
  if a.eso_result = p_result then
    select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
    return jsonb_build_object('ok', true, 'row', v_row);
  end if;
  perform set_config('gt.eso_ruling', 'true', true);
  if p_result = 'nevela' then
    update animals_pilot
       set eso_result = 'nevela', eso_prev_slaughter = slaughter, slaughter = 'nevela',
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev,
           device_id = v_dev, updated_at = now()
     where id = p_id and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  else
    update animals_pilot
       set eso_result = 'ok', slaughter = coalesce(eso_prev_slaughter, 'slaughtered'),
           slaughter_time = greatest(v_now, coalesce(slaughter_time, 0) + 1), slaughter_by_device = v_dev,
           device_id = v_dev, updated_at = now()
     where id = p_id and coalesce(board_epoch, 0) <= coalesce(v_epoch, 0);
  end if;
  get diagnostics v_rows = row_count;
  perform set_config('gt.eso_ruling', '', true);
  select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
  return jsonb_build_object('ok', v_rows = 1, 'row', v_row);
end $$;
revoke execute on function eso_change(integer, text, text, bigint) from public;
grant  execute on function eso_change(integer, text, text, bigint) to anon, authenticated;

-- ── outer screen lock: never onto a board reset meanwhile ───────────────────
create or replace function outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_epoch bigint := _board_epoch();
  v_dev text;
  v_rows integer;
  r record;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed('outer') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  v_dev := coalesce(_current_device_id(), nullif(left(p_device_id, 80), ''));
  if v_dev is null then return jsonb_build_object('ok', false, 'error', 'no_device'); end if;

  perform set_config('gt.outer_open', 'true', true);
  if p_open then
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
  return jsonb_build_object('ok', true, 'claimed', (p_open and v_rows = 1),
                            'by', r.outer_open_by_device, 'at', r.outer_open_at, 'serverNow', v_now);
end $$;
revoke execute on function outer_open(integer, bigint, boolean, text) from public;
grant  execute on function outer_open(integer, bigint, boolean, text) to anon, authenticated;

-- ── daily reset also clears the new label fields ────────────────────────────
create or replace function _do_board_reset(p_reason text, p_business_date date) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  insert into daily_board_archive (business_date, reason, animals_count, board)
  select p_business_date, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb)
    from animals_pilot a
   where a.slaughter is not null or a.inner_status is not null or a.outer_status is not null;

  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);

  insert into plant_state (key, value) values ('boardEpoch', v_epoch::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
    outer_status = null, outer_by = null, outer_time = null, outer_by_device = null,
    parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
    weight_right = null, weight_left = null,
    weight_stage2 = null, weight_stage3 = null,
    weight_right_skipped = false, weight_left_skipped = false,
    weight_stage2_skipped = false, weight_stage3_skipped = false,
    eso_checked = false, eso_result = null, eso_prev_slaughter = null,
    legs_sorted = false,
    stamped = false, stamped_as = null,
    parts_print_count = 0, parts_printed_as = null,
    board_epoch = v_epoch,
    updated_at = clock_timestamp()
  where true;

  update devices_pilot set cursor_slaughter = null, cursor_inner = null, cursor_outer = null
  where true;

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

-- ── settings: record the paired device's own id ─────────────────────────────
create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  station_keys text[] := array[
    'currentUser','activeUserByRole','reprintLog','problemReports',
    'printers','scanners','licenseRequestDismissed'
  ];
  list_keys text[] := array['reprintLog','problemReports'];
  server_keys text[] := array['lastServerResetAt','lastServerResetReason','billing','forceReloadAt','supportAccessUntil','boardEpoch'];
  cur jsonb;
  incoming jsonb;
  k text;
  ignored text[] := '{}';
  is_manager boolean := false;
  v_dev text := coalesce(_current_device_id(), left(p_device_id, 80));
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
  end if;
  -- station keys: a paired station (or team leader); nobody anonymous
  if not is_manager and not _device_write_allowed() then
    return jsonb_build_object('ok', false, 'error', 'device_not_paired');
  end if;

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

  -- append-style lists: merge with what other stations already sent
  -- (a team leader's edit — e.g. closing a report — replaces the list as is)
  foreach k in array list_keys loop
    if not is_manager and incoming ? k then
      incoming := jsonb_set(incoming, array[k], _merge_list(cur -> k, incoming -> k));
    end if;
  end loop;

  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, cur || incoming, v_dev, now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || incoming,
        device_id = excluded.device_id,
        updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;

-- ── period reports: weights per animal too ──────────────────────────────────
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
             'animals', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'n',  (x ->> 'id')::int,
                        's',  x ->> 'slaughter',
                        'i',  x ->> 'inner_status',
                        'o',  x ->> 'outer_status',
                        'sb', x ->> 'slaughtered_by',
                        'ib', x ->> 'inner_by',
                        'ob', x ->> 'outer_by',
                        'st', (x ->> 'slaughter_time'),
                        'nc', coalesce((x ->> 'not_chalak_inner')::boolean, false),
                        'wr', coalesce(x -> 'weight_right', 'null'::jsonb),
                        'wl', coalesce(x -> 'weight_left', 'null'::jsonb)
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
grant  execute on function archive_days(text, date, date) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '40')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ── self-check (behaviour, inside a rolled-back sub-block) ──────────────────
do $$
declare
  v_ep bigint; r jsonb; a record; v_fail text := null;
begin
  if not exists (select 1 from information_schema.columns where table_name = 'animals_pilot' and column_name = 'parts_printed_as')
     or not exists (select 1 from information_schema.columns where table_name = 'animals_pilot' and column_name = 'stamped_as') then
    raise exception 'GlattTrack step 40 self-check FAILED: label columns missing';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.animals_pilot'::regclass
                  and conname = 'animals_pilot_id_range' and convalidated) then
    raise exception 'GlattTrack step 40 self-check FAILED: id range check missing';
  end if;
  if exists (select 1 from pg_proc where proname = 'eso_change' and pronargs = 3) then
    raise exception 'GlattTrack step 40 self-check FAILED: old eso_change still present';
  end if;
  if not has_function_privilege('anon', 'eso_change(integer, text, text, bigint)', 'execute')
     or not has_function_privilege('anon', 'claim_animal_stage(integer, text, text, text, text, bigint)', 'execute')
     or has_function_privilege('anon', '_request_privileged()', 'execute') then
    raise exception 'GlattTrack step 40 self-check FAILED: function rights';
  end if;
  if position('wr' in pg_get_functiondef('archive_days(text,date,date)'::regprocedure)) = 0 then
    raise exception 'GlattTrack step 40 self-check FAILED: archive_days has no weights';
  end if;

  -- behaviour (as the server; rolled back)
  begin
    v_ep := _board_epoch();
    update animals_pilot set updated_at = '2000-01-01' where id = 998;
    if (select updated_at from animals_pilot where id = 998) < now() - interval '1 minute' then
      v_fail := 'updated_at is not set by the server';
    end if;
    -- eso claim: second claim on the same animal must say claimed:false
    r := claim_animal_stage(998, 'slaughter', 'slaughtered', 'x', 'selfcheck', v_ep);
    r := claim_animal_stage(998, 'eso', 'ok', 'x', 'selfcheck', v_ep);
    if v_fail is null and not (r ->> 'claimed')::boolean then v_fail := 'first eso claim not claimed'; end if;
    r := claim_animal_stage(998, 'eso', 'nevela', 'x', 'selfcheck', v_ep);
    if v_fail is null and (r ->> 'claimed')::boolean then v_fail := 'second eso claim answered claimed:true'; end if;
    -- eso_change needs the board day
    r := eso_change(998, 'nevela', 'selfcheck', null);
    if v_fail is null and v_ep is not null and coalesce(r ->> 'error', '') <> 'stale_board' then v_fail := 'eso_change without board day accepted'; end if;
    r := eso_change(998, 'nevela', 'selfcheck', v_ep);
    select * into a from animals_pilot where id = 998;
    if v_fail is null and (a.slaughter <> 'nevela' or a.eso_prev_slaughter <> 'slaughtered') then v_fail := 'eso_change nevela not applied'; end if;
    -- a claim made with the day read before a reset doesn't land
    perform set_config('gt.reset_in_progress', 'true', true);
    update animals_pilot set board_epoch = coalesce(v_ep, 0) + 1 where id = 997;
    perform set_config('gt.reset_in_progress', 'false', true);
    r := claim_animal_stage(997, 'slaughter', 'slaughtered', 'x', 'selfcheck', v_ep);
    if v_fail is null and (r ->> 'claimed')::boolean then v_fail := 'claim landed on a newer board'; end if;
    -- a stale "close lung check" keeps a final inner ruling
    update animals_pilot set inner_status = 'confirmed', inner_time = 1000 where id = 996;
    update animals_pilot set inner_status = null, inner_time = 2000 where id = 996;
    if v_fail is null and (select inner_status from animals_pilot where id = 996) is distinct from 'confirmed' then
      v_fail := 'a final inner ruling was cleared';
    end if;
    -- not chalak can be cleared with the inner group
    update animals_pilot set inner_status = 'in_progress', inner_time = 3000, not_chalak_inner = true where id = 995;
    update animals_pilot set not_chalak_inner = false where id = 995;
    if v_fail is null and (select not_chalak_inner from animals_pilot where id = 995) then
      v_fail := 'not chalak can not be cleared';
    end if;
    raise exception 'selfcheck-rollback';
  exception when others then
    if sqlerrm <> 'selfcheck-rollback' then v_fail := coalesce(v_fail, sqlerrm); end if;
  end;
  if v_fail is not null then
    raise exception 'GlattTrack step 40 self-check FAILED: %', v_fail;
  end if;
  raise notice 'GlattTrack step 40 self-check OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 41 ============================
-- ============================================================================
-- GlattTrack — step 41: correction authority, value rules, stable error codes,
--                        server-verified worker identity
-- ============================================================================
--  A. Who may change a ruling (the plant owner's rule): "each station can
--     change only the ruling it made, and only immediately; after the outer
--     inspector's ruling nothing can change — not even by the team leader".
--     An existing slaughter / esophagus / inner / outer ruling may be changed
--     (or cleared) through the app ONLY when ALL of these hold:
--       1. the tablet asking is the tablet that made it (server-known key);
--       2. that tablet has not moved on (no later animal ruled by it for that
--          stage, and its "last animal" for that stage is this one);
--       3. no later stage has acted on the animal:
--            slaughter  — until the esophagus check / inner / outer
--            esophagus  — until the inner check starts
--            inner      — until the outer ruling
--            outer      — until parts stickers printed / parts scanned /
--                         stamped / legs sorted (all done only on an animal
--                         that already has its outer ruling). Legs + head
--                         stickers are printed right after slaughter, so they
--                         do NOT lock the outer ruling.
--       4. no team-leader override (a team leader may still make FIRST
--          rulings, reset the day, pair tablets …). The plant server itself
--          (SQL editor, server jobs, service key) is not restricted.
--     Refusals: trigger → 'GT:MOVED_ON …' / 'GT:CORRECTION_NOT_ALLOWED …'
--     (P0001); RPC → {ok:false, error:'moved_on'|'correction_not_allowed'}.
--     Kept: opening / abandoning a lung check, the 10-minute takeover, reopen
--     of an inner ruling by the same tablet before the outer ruling, the outer
--     screen lock, the daily reset.
--  B. Value rules (CHECK constraints) for every status / result / weight /
--     station role.
--  C. Every exception the app must react to starts with 'GT:<CODE>' (the old
--     words stay after it, so older tablets keep matching them).
--  D. Workers: codes are stored only as hashes (sha256 of 'gt-worker:'+code);
--     worker_login / worker_logout / worker_session_check; the header
--     x-worker-token; the name written on a ruling comes from the server.
-- Safe to run more than once. Run after step 40.
-- ============================================================================

-- ── new columns ──────────────────────────────────────────────────────────────
alter table animals_pilot add column if not exists eso_by_device text;
alter table devices_pilot add column if not exists cursor_eso integer;

-- the tablet of an esophagus "nevela" is already known (it wrote the slaughter group)
do $$
begin
  perform set_config('gt.reset_in_progress', 'true', true);
  update animals_pilot set eso_by_device = slaughter_by_device
   where eso_by_device is null and eso_result = 'nevela' and slaughter_by_device is not null;
  perform set_config('gt.reset_in_progress', 'false', true);
end $$;

-- ============================================================================
-- D. WORKER SESSIONS
-- ============================================================================
create table if not exists worker_sessions (
  token_hash       text primary key,
  device_id        text,
  mgr_session_hash text,                    -- test mode: a team leader without a paired tablet
  test_mode        boolean not null default false,
  name             text not null,
  role             text not null,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default now() + interval '14 hours',
  revoked          boolean not null default false,
  revoked_at       timestamptz
);
create index if not exists worker_sessions_device on worker_sessions (device_id) where not revoked;
alter table worker_sessions enable row level security;
revoke all on worker_sessions from public, anon, authenticated;
do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.worker_sessions'::regclass
                  and conname = 'worker_sessions_role_check') then
    alter table worker_sessions add constraint worker_sessions_role_check
      check (role in ('slaughter', 'inspector', 'supervisor'));
  end if;
end $$;

-- worker role of a login screen / station / legacy Hebrew label
create or replace function _worker_role_norm(p text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
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
revoke execute on function _worker_role_norm(text) from public, anon, authenticated;

create or replace function _stage_worker_role(p_stage text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case p_stage when 'slaughter' then 'slaughter'
                      when 'inner' then 'inspector' when 'inner_start' then 'inspector' when 'outer' then 'inspector'
                      else 'supervisor' end;
$$;
revoke execute on function _stage_worker_role(text) from public, anon, authenticated;

-- the stored form of a worker code: sha256 hex of 'gt-worker:' || code
create or replace function _worker_code_hash(p_code text) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select encode(extensions.digest('gt-worker:' || p_code, 'sha256'), 'hex');
$$;
revoke execute on function _worker_code_hash(text) from public, anon, authenticated;

-- settings never keep a worker code in plain text (whatever path writes them)
create or replace function _settings_hash_worker_codes() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
revoke execute on function _settings_hash_worker_codes() from public, anon, authenticated;
drop trigger if exists zz_settings_hash_worker_codes on settings_pilot;
create trigger zz_settings_hash_worker_codes before insert or update on settings_pilot
  for each row execute function _settings_hash_worker_codes();
-- migrate what is stored now
update settings_pilot set settings = settings
 where jsonb_typeof(settings -> 'users') = 'array'
   and exists (select 1 from jsonb_array_elements(settings -> 'users') u where jsonb_typeof(u) = 'object' and u ? 'code');

-- the verified worker of this request (header x-worker-token), bound to the calling tablet
create or replace function _current_worker() returns table (name text, role text)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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
         and (s.test_mode or _worker_role_norm(d.assigned_role) = s.role)
       limit 1;
    return;
  end if;
  v_mt := _request_headers() ->> 'x-manager-token';
  if v_mt is not null and v_mt <> '' and _request_has_manager() then
    return query
      select s.name, s.role from worker_sessions s
       where s.token_hash = encode(digest(v_tok, 'sha256'), 'hex') and not s.revoked and s.expires_at > now()
         and s.device_id is null and s.mgr_session_hash = encode(digest(v_mt, 'sha256'), 'hex')
       limit 1;
  end if;
end $$;
revoke execute on function _current_worker() from public, anon, authenticated;

-- the name written on a ruling (never the tablet's word alone):
--   verified worker of this tablet → its name;
--   login mode 'none' (or not set) for that worker role → the app's default name;
--   mode 'name' → a name from the plant's worker list (else marked);
--   otherwise (a code is required but no verified session, e.g. an offline
--   login or a queued ruling sent later) → the tablet's name + ' (?)'.
create or replace function _derive_actor(p_stage text, p_client text) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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
end $$;
revoke execute on function _derive_actor(text, text) from public, anon, authenticated;

-- worker_login(p_role, p_code [, p_name]) — see the contract in the header of worker_login below
drop function if exists worker_login(text, text);
create or replace function worker_login(p_role text, p_code text, p_name text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_role text := _worker_role_norm(p_role);
  v_dev text := _current_device_id();
  v_mgr boolean := _request_has_manager();
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

  -- code-guessing brake: per address and per tablet, 8 wrong codes → 15 minutes
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
    v_h2 := case when coalesce(s ->> 'codeSalt', '') <> ''                            -- hashes made by older tablets
                 then encode(digest('gt1:' || (s ->> 'codeSalt') || ':' || trim(p_code), 'sha256'), 'hex') end;
    select x into u from jsonb_array_elements(s -> 'users') x
     where jsonb_typeof(x) = 'object'
       and _worker_role_norm(x ->> 'role') = v_role
       and (p_name is null or x ->> 'name' = p_name)
       and coalesce(x ->> 'name', '') <> ''
       and (x ->> 'codeHash' = v_h1 or (v_h2 is not null and x ->> 'codeHash' = v_h2)
            or (x ? 'code' and x ->> 'code' = trim(p_code)))
     limit 1;
  end if;
  if u is null then
    insert into login_attempts (ip, ok) values (v_ip, false), (v_key2, false);
    perform pg_sleep(0.3);
    return jsonb_build_object('ok', false, 'error', 'code_invalid', 'attempts_left', greatest(0, 7 - v_fails));
  end if;
  delete from login_attempts where ip in (v_ip, v_key2);

  -- one worker per tablet at a time
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

  perform set_config('app.device_admin', 'on', true);
  insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
  values (gen_random_uuid(), null, 'security', 'worker_login',
          jsonb_build_object('role', v_role, 'testMode', v_dev is null or v_mgr), left(u ->> 'name', 60),
          coalesce(v_dev, 'team-leader'), now()::text);
  perform set_config('app.device_admin', '', true);

  return jsonb_build_object('ok', true, 'token', v_tok, 'name', left(u ->> 'name', 60), 'role', v_role, 'expires_at', v_exp);
end $$;
revoke execute on function worker_login(text, text, text) from public;
grant  execute on function worker_login(text, text, text) to anon, authenticated;

create or replace function worker_logout(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_token is not null and p_token <> '' then
    update worker_sessions set revoked = true, revoked_at = now()
     where token_hash = encode(digest(p_token, 'sha256'), 'hex') and not revoked;
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function worker_logout(text) from public;
grant  execute on function worker_logout(text) to anon, authenticated;

-- is this worker token still good on this tablet? (uses the x-worker-token header)
create or replace function worker_session_check() returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare w record; v_exp timestamptz;
begin
  select * into w from _current_worker() limit 1;
  if w.name is null then return jsonb_build_object('ok', false, 'error', 'session_invalid'); end if;
  select expires_at into v_exp from worker_sessions
   where token_hash = encode(digest(_request_headers() ->> 'x-worker-token', 'sha256'), 'hex');
  return jsonb_build_object('ok', true, 'name', w.name, 'role', w.role, 'expires_at', v_exp);
end $$;
revoke execute on function worker_session_check() from public;
grant  execute on function worker_session_check() to anon, authenticated;

-- a tablet that is unpaired / retired / replaced / re-paired loses its worker sessions
create or replace function _worker_sessions_revoke_on_credential() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if (new.revoked and not coalesce(old.revoked, false)) or new.token_hash is distinct from old.token_hash then
    update worker_sessions set revoked = true, revoked_at = now() where device_id = new.device_id and not revoked;
  end if;
  return null;
end $$;
revoke execute on function _worker_sessions_revoke_on_credential() from public, anon, authenticated;
drop trigger if exists zz_worker_sessions_revoke on device_credentials;
create trigger zz_worker_sessions_revoke after update on device_credentials
  for each row execute function _worker_sessions_revoke_on_credential();

create or replace function _worker_sessions_revoke_on_device() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
revoke execute on function _worker_sessions_revoke_on_device() from public, anon, authenticated;
drop trigger if exists zz_worker_sessions_revoke on devices_pilot;
create trigger zz_worker_sessions_revoke after update or delete on devices_pilot
  for each row execute function _worker_sessions_revoke_on_device();

-- ============================================================================
-- B. VALUE RULES
-- ============================================================================
create or replace function _gt_value_ok(p_kind text, v text) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select v is null or case p_kind
    when 'slaughter' then v in ('slaughtered', 'shot', 'nevela', 'notChalak')
    when 'inner'     then v in ('in_progress', 'confirmed', 'treif')
    when 'outer'     then v in ('glatt', 'beit', 'kosher', 'mk', 'treif', 'rabChalak') or v ~ '^custom_[A-Za-z0-9_-]{1,40}$'
    when 'printed'   then v in ('glatt', 'beit', 'kosher', 'mk', 'treif', 'rabChalak', 'kosherRab') or v ~ '^custom_[A-Za-z0-9_-]{1,40}$'
    when 'eso'       then v in ('ok', 'nevela')
    when 'maw'       then v in ('kosher', 'treif')
    when 'device_role' then v in ('slaughter', 'esophagus', 'legs', 'inner', 'outer', 'parts', 'stamps', 'display')
    else false end;
$$;
revoke execute on function _gt_value_ok(text, text) from public, anon, authenticated;

do $$
declare
  c record; v_bad jsonb := '[]'::jsonb; n int;
  cons constant text[][] := array[
    array['animals_pilot', 'animals_pilot_slaughter_ok',   $c$slaughter is null or slaughter in ('slaughtered','shot','nevela','notChalak')$c$],
    array['animals_pilot', 'animals_pilot_eso_prev_ok',    $c$eso_prev_slaughter is null or eso_prev_slaughter in ('slaughtered','shot','nevela','notChalak')$c$],
    array['animals_pilot', 'animals_pilot_inner_ok',       $c$inner_status is null or inner_status in ('in_progress','confirmed','treif')$c$],
    array['animals_pilot', 'animals_pilot_outer_ok',       $c$outer_status is null or outer_status in ('glatt','beit','kosher','mk','treif','rabChalak') or outer_status ~ '^custom_[A-Za-z0-9_-]{1,40}$'$c$],
    array['animals_pilot', 'animals_pilot_parts_as_ok',    $c$parts_printed_as is null or parts_printed_as in ('glatt','beit','kosher','mk','treif','rabChalak','kosherRab') or parts_printed_as ~ '^custom_[A-Za-z0-9_-]{1,40}$'$c$],
    array['animals_pilot', 'animals_pilot_stamped_as_ok',  $c$stamped_as is null or stamped_as in ('glatt','beit','kosher','mk','treif','rabChalak','kosherRab') or stamped_as ~ '^custom_[A-Za-z0-9_-]{1,40}$'$c$],
    array['animals_pilot', 'animals_pilot_eso_ok',         $c$eso_result is null or eso_result in ('ok','nevela')$c$],
    array['animals_pilot', 'animals_pilot_maw_ok',         $c$maw is null or maw in ('kosher','treif')$c$],
    array['animals_pilot', 'animals_pilot_rumen_ok',       $c$rumen is null or rumen in ('kosher','treif')$c$],
    array['animals_pilot', 'animals_pilot_weights_ok',     $c$(weight_right is null or (weight_right > 0 and weight_right < 2000)) and (weight_left is null or (weight_left > 0 and weight_left < 2000)) and (weight_stage2 is null or (weight_stage2 > 0 and weight_stage2 < 2000)) and (weight_stage3 is null or (weight_stage3 > 0 and weight_stage3 < 2000))$c$],
    array['animals_pilot', 'animals_pilot_print_count_ok', $c$parts_print_count is null or parts_print_count >= 0$c$],
    array['devices_pilot', 'devices_pilot_role_ok',        $c$assigned_role is null or assigned_role in ('slaughter','esophagus','legs','inner','outer','parts','stamps','display')$c$]
  ];
  i int;
begin
  -- 1. add (not yet checking old rows)
  for i in 1 .. array_length(cons, 1) loop
    if not exists (select 1 from pg_constraint where conrelid = ('public.' || cons[i][1])::regclass and conname = cons[i][2]) then
      execute format('alter table %I add constraint %I check (%s) not valid', cons[i][1], cons[i][2], cons[i][3]);
    end if;
  end loop;

  -- 2. clean rows that break them (kept in plant_state 'step41CleanedValues' for the audit)
  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);
  for c in
    select id, 'slaughter' col, slaughter v from animals_pilot where not _gt_value_ok('slaughter', slaughter)
    union all select id, 'eso_prev_slaughter', eso_prev_slaughter from animals_pilot where not _gt_value_ok('slaughter', eso_prev_slaughter)
    union all select id, 'inner_status', inner_status from animals_pilot where not _gt_value_ok('inner', inner_status)
    union all select id, 'outer_status', outer_status from animals_pilot where not _gt_value_ok('outer', outer_status)
    union all select id, 'parts_printed_as', parts_printed_as from animals_pilot where not _gt_value_ok('printed', parts_printed_as)
    union all select id, 'stamped_as', stamped_as from animals_pilot where not _gt_value_ok('printed', stamped_as)
    union all select id, 'eso_result', eso_result from animals_pilot where not _gt_value_ok('eso', eso_result)
    union all select id, 'maw', maw from animals_pilot where not _gt_value_ok('maw', maw)
    union all select id, 'rumen', rumen from animals_pilot where not _gt_value_ok('maw', rumen)
    union all select id, 'weight_right', weight_right::text from animals_pilot where not (weight_right is null or (weight_right > 0 and weight_right < 2000))
    union all select id, 'weight_left', weight_left::text from animals_pilot where not (weight_left is null or (weight_left > 0 and weight_left < 2000))
    union all select id, 'weight_stage2', weight_stage2::text from animals_pilot where not (weight_stage2 is null or (weight_stage2 > 0 and weight_stage2 < 2000))
    union all select id, 'weight_stage3', weight_stage3::text from animals_pilot where not (weight_stage3 is null or (weight_stage3 > 0 and weight_stage3 < 2000))
    union all select id, 'parts_print_count', parts_print_count::text from animals_pilot where parts_print_count < 0
  loop
    v_bad := v_bad || jsonb_build_array(jsonb_build_object('table', 'animals_pilot', 'id', c.id, 'column', c.col, 'value', c.v));
    if c.col = 'parts_print_count' then
      update animals_pilot set parts_print_count = 0 where id = c.id;
    else
      execute format('update animals_pilot set %I = null where id = $1', c.col) using c.id;
    end if;
  end loop;
  for c in select id, assigned_role from devices_pilot where not _gt_value_ok('device_role', assigned_role) loop
    v_bad := v_bad || jsonb_build_array(jsonb_build_object('table', 'devices_pilot', 'id', c.id, 'column', 'assigned_role', 'value', c.assigned_role));
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null where id = c.id;
  end loop;
  perform set_config('gt.reset_in_progress', 'false', true);
  perform set_config('app.device_admin', '', true);
  n := jsonb_array_length(v_bad);
  if n > 0 then
    insert into plant_state (key, value) values ('step41CleanedValues', v_bad::text)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    raise notice 'GlattTrack step 41: % invalid value(s) were cleared (kept in plant_state step41CleanedValues)', n;
  end if;

  -- 3. now check every row
  for i in 1 .. array_length(cons, 1) loop
    execute format('alter table %I validate constraint %I', cons[i][1], cons[i][2]);
  end loop;
end $$;

-- ============================================================================
-- C. STABLE ERROR CODES in the guards (old words kept after the code)
-- ============================================================================
create or replace function _device_write_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if _device_write_allowed() then return null; end if;
  if tg_table_name = 'events_pilot' and tg_op = 'INSERT' and _request_has_manufacturer() then
    return null;   -- each row is checked by _events_maker_guard below
  end if;
  raise exception 'GT:DEVICE_NOT_PAIRED המכשיר אינו מצומד לתחנה — יש לצמד אותו במסך ראש הצוות (device_not_paired)'
    using errcode = '42501';
end $$;
revoke execute on function _device_write_guard() from public, anon, authenticated;

create or replace function _devices_assignment_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _device_auth_required()
     or not _is_api_request()
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
revoke execute on function _devices_assignment_guard() from public, anon, authenticated;

create or replace function _events_append_only() returns trigger
language plpgsql set search_path = public, extensions, pg_temp as $$
begin
  if current_setting('request.headers', true) is null then  -- SQL editor / maintenance
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  raise exception 'GT:APPEND_ONLY יומן האירועים הוא לקריאה ולהוספה בלבד (append_only)' using errcode = '42501';
end $$;
revoke execute on function _events_append_only() from public, anon, authenticated;

create or replace function _events_maker_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
revoke execute on function _events_maker_guard() from public, anon, authenticated;

-- the name on a ruling event comes from the server too (same rules as the board)
create or replace function _events_actor() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  if new.stage in ('slaughter', 'inner', 'outer', 'esophagus') then
    new.actor := _derive_actor(case new.stage when 'esophagus' then 'eso' else new.stage end, new.actor);
  end if;
  return new;
end $$;
revoke execute on function _events_actor() from public, anon, authenticated;
drop trigger if exists a1_events_actor on events_pilot;
create trigger a1_events_actor before insert on events_pilot
  for each row execute function _events_actor();

-- ============================================================================
-- A. CORRECTION AUTHORITY
-- ============================================================================
-- May tablet p_dev change the existing <stage> ruling of animal a (the row as
-- it is BEFORE the change)? null = yes, else 'correction_not_allowed' / 'moved_on'.
create or replace function _correction_check(p_stage text, a animals_pilot, p_dev text) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_by text; v_later boolean; v_cur integer; v_moved boolean;
begin
  if p_dev is null then return 'correction_not_allowed'; end if;           -- only a paired tablet, never an override
  case p_stage
    when 'slaughter' then
      v_by := a.slaughter_by_device;
      v_later := coalesce(a.eso_checked, false) or a.inner_status is not null or a.outer_status is not null;
      select cursor_slaughter into v_cur from devices_pilot where id = p_dev;
      v_moved := exists (select 1 from animals_pilot x where x.id > a.id and x.slaughter is not null and x.slaughter_by_device = p_dev);
    when 'eso' then
      v_by := a.eso_by_device;
      v_later := a.inner_status is not null;
      select cursor_eso into v_cur from devices_pilot where id = p_dev;
      v_moved := exists (select 1 from animals_pilot x where x.id > a.id and coalesce(x.eso_checked, false) and x.eso_by_device = p_dev);
    when 'inner' then
      v_by := a.inner_by_device;
      v_later := a.outer_status is not null;
      select cursor_inner into v_cur from devices_pilot where id = p_dev;
      v_moved := exists (select 1 from animals_pilot x where x.id > a.id and x.inner_status is not null and x.inner_by_device = p_dev);
    when 'outer' then
      v_by := a.outer_by_device;
      v_later := coalesce(a.parts_print_count, 0) > 0 or coalesce(a.stamped, false) or coalesce(a.legs_sorted, false)
                 or coalesce(a.parts_scanned, false) or coalesce(a.tongue_sticker, false) or coalesce(a.cheek_sticker, false);
      select cursor_outer into v_cur from devices_pilot where id = p_dev;
      v_moved := exists (select 1 from animals_pilot x where x.id > a.id and x.outer_status is not null and x.outer_by_device = p_dev);
    else
      return 'correction_not_allowed';
  end case;
  if v_by is distinct from p_dev then return 'correction_not_allowed'; end if;     -- 1. only the tablet that made it
  if v_later then return 'correction_not_allowed'; end if;                          -- 3. a later stage already acted
  if v_moved or v_cur is distinct from a.id then return 'moved_on'; end if;         -- 2. only right away
  return null;
end $$;
revoke execute on function _correction_check(text, animals_pilot, text) from public, anon, authenticated;

create or replace function _raise_correction(p_err text, p_stage text) returns void
language plpgsql set search_path = public, extensions, pg_temp as $$
begin
  if p_err is null then return; end if;
  if p_err = 'moved_on' then
    raise exception 'GT:MOVED_ON correction-blocked: already moved on — % status is locked', p_stage using errcode = 'P0001';
  end if;
  raise exception 'GT:CORRECTION_NOT_ALLOWED correction-blocked: only the station that made this % ruling can change it, right away, before the next stage', p_stage
    using errcode = 'P0001';
end $$;
revoke execute on function _raise_correction(text, text) from public, anon, authenticated;

-- ── the merge (step 40) + esophagus tablet + names from the server ──────────
create or replace function _animals_merge() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_epoch bigint := _board_epoch();
  v_api   boolean := _is_api_request();
  v_dev   text := _current_device_id();
  v_priv  boolean;
  v_now   bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_cap   bigint;
  v_eso   boolean := coalesce(current_setting('gt.eso_ruling', true), '') = 'true';
  v_claim boolean := coalesce(current_setting('gt.claim', true), '') = 'true';
  v_eso_upsert boolean := false;
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    return new;
  end if;

  -- yesterday's board may never come back (a tablet offline over the reset)
  if v_epoch is not null and v_api and (new.board_epoch is null or new.board_epoch < v_epoch) then
    raise exception 'GT:STALE_BOARD stale-board: this device still has the previous day''s board' using errcode = 'P0001';
  end if;

  new.updated_at := clock_timestamp();                       -- the server's clock, never the tablet's
  if v_api and v_dev is not null then new.device_id := v_dev; end if;   -- a paired tablet is always itself

  if tg_op = 'INSERT' then
    new.board_epoch := coalesce(v_epoch, new.board_epoch);
    if v_api and not exists (select 1 from animals_pilot x where x.id = new.id) then
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

  if v_api then
    v_cap := v_now + 60000;
    if new.slaughter_time is distinct from old.slaughter_time and new.slaughter_time > v_cap then new.slaughter_time := v_cap; end if;
    if new.inner_time     is distinct from old.inner_time     and new.inner_time     > v_cap then new.inner_time     := v_cap; end if;
    if new.outer_time     is distinct from old.outer_time     and new.outer_time     > v_cap then new.outer_time     := v_cap; end if;
  end if;

  -- esophagus: only through the ruling itself — except a "nevela" sent by an
  -- esophagus tablet that was offline, which is applied whole
  if not v_eso then
    if new.eso_result = 'nevela' and old.eso_result is distinct from 'nevela' and _stage_allowed('eso') then
      v_eso_upsert := true;
      new.eso_checked := true;
      new.eso_by_device := coalesce(v_dev, new.device_id);
      new.eso_prev_slaughter := case when old.slaughter = 'nevela' then coalesce(old.eso_prev_slaughter, 'slaughtered')
                                     else old.slaughter end;
      new.slaughter := 'nevela';
      new.slaughtered_by := old.slaughtered_by;
      new.slaughter_time := greatest(v_now, coalesce(old.slaughter_time, 0) + 1);
      new.slaughter_by_device := coalesce(v_dev, new.device_id);
      perform set_config('gt.eso_upsert_row', new.id::text, true);   -- for the correction rules below
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
       or (old.inner_status = 'in_progress' and not v_priv
           and old.inner_by_device is distinct from coalesce(v_dev, new.device_id)) then
      new.inner_status := old.inner_status; new.inner_time := old.inner_time;
      new.inner_by := old.inner_by; new.inner_by_device := old.inner_by_device;
      new.not_chalak_inner := old.not_chalak_inner;
    end if;
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

  if v_api and v_dev is not null then
    if (new.slaughter, new.slaughter_time) is distinct from (old.slaughter, old.slaughter_time) then new.slaughter_by_device := v_dev; end if;
    if (new.inner_status, new.inner_time) is distinct from (old.inner_status, old.inner_time) then new.inner_by_device := v_dev; end if;
    if (new.outer_status, new.outer_time) is distinct from (old.outer_status, old.outer_time) then new.outer_by_device := v_dev; end if;
  end if;

  -- the name on a ruling: from the server (claims already decided it)
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
revoke execute on function _animals_merge() from public, anon, authenticated;

-- ── the correction rule (runs after the merge: triggers fire in name order) ──
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

  -- the plant server itself (SQL editor, server jobs, service key) is not restricted
  if not _is_api_request() or _request_is_service_role()
     or coalesce(current_setting('app.device_admin', true), '') = 'on' then
    return new;
  end if;
  v_dev := _current_device_id();

  -- an esophagus nevela can only be changed by the esophagus ruling itself
  if old.eso_result = 'nevela' and new.slaughter is distinct from old.slaughter and not v_eso then
    raise exception 'GT:ESO_LOCKED correction-blocked: failed the esophagus check — only the esophagus screen can change it'
      using errcode = 'P0001';
  end if;

  -- slaughter
  if not v_eso and old.slaughter is not null
     and (new.slaughter, new.slaughtered_by, new.slaughter_by_device)
         is distinct from (old.slaughter, old.slaughtered_by, old.slaughter_by_device) then
    perform _raise_correction(_correction_check('slaughter', old, v_dev), 'slaughter');
  end if;

  -- esophagus (only its own ruling can change it; the first ruling is not a correction)
  if coalesce(old.eso_checked, false)
     and (new.eso_result is distinct from old.eso_result or new.eso_by_device is distinct from old.eso_by_device) then
    perform _raise_correction(_correction_check('eso', old, v_dev), 'esophagus');
  end if;

  -- inner (a final ruling; its maw / rumen / "not chalak" travel with it)
  v_inner_final := old.inner_status in ('confirmed', 'treif');
  if v_inner_final
     and ((new.inner_status, new.inner_by, new.inner_by_device) is distinct from (old.inner_status, old.inner_by, old.inner_by_device)
          or coalesce(new.not_chalak_inner, false) is distinct from coalesce(old.not_chalak_inner, false)
          or (old.maw is not null and new.maw is distinct from old.maw)
          or (old.rumen is not null and new.rumen is distinct from old.rumen)) then
    perform _raise_correction(_correction_check('inner', old, v_dev), 'inner');
  end if;

  -- outer
  if old.outer_status is not null
     and (new.outer_status, new.outer_by, new.outer_by_device) is distinct from (old.outer_status, old.outer_by, old.outer_by_device) then
    perform _raise_correction(_correction_check('outer', old, v_dev), 'outer');
  end if;

  return new;
end $$;
revoke execute on function animals_pilot_guard_corrections() from public, anon, authenticated;

-- ── "last animal" per tablet and stage (follows who made the ruling) ─────────
create or replace function animals_pilot_advance_cursor() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if tg_op = 'UPDATE' and current_setting('gt.reset_in_progress', true) = 'true' then return new; end if;
  if new.slaughter is not null and new.slaughter_by_device is not null
     and (tg_op = 'INSERT' or old.slaughter is null or old.slaughter_by_device is distinct from new.slaughter_by_device) then
    update devices_pilot set cursor_slaughter = new.id where id = new.slaughter_by_device and cursor_slaughter is distinct from new.id;
  end if;
  if new.inner_status is not null and new.inner_by_device is not null
     and (tg_op = 'INSERT' or old.inner_status is null or old.inner_by_device is distinct from new.inner_by_device) then
    update devices_pilot set cursor_inner = new.id where id = new.inner_by_device and cursor_inner is distinct from new.id;
  end if;
  if new.outer_status is not null and new.outer_by_device is not null
     and (tg_op = 'INSERT' or old.outer_status is null or old.outer_by_device is distinct from new.outer_by_device) then
    update devices_pilot set cursor_outer = new.id where id = new.outer_by_device and cursor_outer is distinct from new.id;
  end if;
  if coalesce(new.eso_checked, false) and new.eso_by_device is not null
     and (tg_op = 'INSERT' or not coalesce(old.eso_checked, false) or old.eso_by_device is distinct from new.eso_by_device) then
    update devices_pilot set cursor_eso = new.id where id = new.eso_by_device and cursor_eso is distinct from new.id;
  end if;
  return new;
end $$;
revoke execute on function animals_pilot_advance_cursor() from public, anon, authenticated;

-- ── first claims: value check, name from the server, esophagus tablet ───────
create or replace function claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_rows integer := 0;
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_row jsonb;
  v_dev text;
  v_epoch bigint := _board_epoch();
  v_stage text := case when p_stage = 'inner_start' then 'inner' else p_stage end;
  v_actor text;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('claimed', false, 'error', 'bad_id');
  end if;
  if p_stage is null or p_stage not in ('slaughter', 'inner_start', 'inner', 'outer', 'eso', 'legs', 'stamped') then
    return jsonb_build_object('claimed', false, 'error', 'bad_stage');
  end if;
  if (p_stage = 'slaughter' and not _gt_value_ok('slaughter', p_value))
     or (p_stage = 'inner' and coalesce(p_value, '') not in ('confirmed', 'treif'))
     or (p_stage = 'outer' and (p_value is null or not _gt_value_ok('outer', p_value)))
     or (p_stage = 'eso' and coalesce(p_value, '') not in ('ok', 'nevela'))
     or (p_stage = 'slaughter' and p_value is null) then
    return jsonb_build_object('claimed', false, 'error', 'bad_value');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('claimed', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed(v_stage) then
    return jsonb_build_object('claimed', false, 'error', 'wrong_station');
  end if;
  v_dev := coalesce(_current_device_id(), p_device_id);
  v_actor := case when p_stage in ('slaughter', 'inner_start', 'inner', 'outer') then _derive_actor(p_stage, p_actor) else p_actor end;

  insert into animals_pilot (id, board_epoch) values (p_id, v_epoch) on conflict (id) do nothing;
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

  select to_jsonb(a.*) into v_row from animals_pilot a where a.id = p_id;
  return jsonb_build_object('claimed', v_rows = 1, 'row', v_row, 'serverNow', v_now);
end $$;
revoke execute on function claim_animal_stage(integer, text, text, text, text, bigint) from public;
grant  execute on function claim_animal_stage(integer, text, text, text, text, bigint) to anon, authenticated;

-- ── esophagus change: only the tablet that ruled, right away, before inner ──
create or replace function eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  a animals_pilot%rowtype;
  v_row jsonb;
  v_rows integer := 0;
  v_epoch bigint := _board_epoch();
  v_dev text := coalesce(_current_device_id(), p_device_id);
  v_err text;
begin
  if p_result is null or p_result not in ('ok','nevela') then
    return jsonb_build_object('ok', false, 'error', 'bad_result');
  end if;
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
  if v_epoch is not null and (p_epoch is null or p_epoch < v_epoch) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', v_epoch);
  end if;
  if not _stage_allowed('eso') then
    return jsonb_build_object('ok', false, 'error', 'wrong_station');
  end if;
  select * into a from animals_pilot where id = p_id for update;
  if a.id is null or a.eso_checked is distinct from true then
    return jsonb_build_object('ok', false, 'error', 'not_checked');
  end if;
  if coalesce(a.board_epoch, 0) > coalesce(v_epoch, 0) then
    return jsonb_build_object('ok', false, 'error', 'stale_board', 'boardEpoch', a.board_epoch);
  end if;
  if a.eso_result = p_result then
    select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
    return jsonb_build_object('ok', true, 'row', v_row);
  end if;
  if _is_api_request() and not _request_is_service_role() then
    v_err := _correction_check('eso', a, _current_device_id());
    if v_err is not null then
      perform set_config('app.device_admin', 'on', true);
      insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
      values (gen_random_uuid(), p_id + 1, 'security', 'correction_rejected',
              jsonb_build_object('stage', 'esophagus', 'from', a.eso_result, 'to', p_result, 'reason', v_err),
              null, coalesce(_current_device_id(), 'unknown'), now()::text);
      perform set_config('app.device_admin', '', true);
      select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
      return jsonb_build_object('ok', false, 'error', v_err, 'row', v_row);
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
  select to_jsonb(x.*) into v_row from animals_pilot x where x.id = p_id;
  return jsonb_build_object('ok', v_rows = 1, 'row', v_row);
end $$;
revoke execute on function eso_change(integer, text, text, bigint) from public;
grant  execute on function eso_change(integer, text, text, bigint) to anon, authenticated;

-- ── daily reset also clears the esophagus tablet and its "last animal" ───────
create or replace function _do_board_reset(p_reason text, p_business_date date) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  insert into daily_board_archive (business_date, reason, animals_count, board)
  select p_business_date, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb)
    from animals_pilot a
   where a.slaughter is not null or a.inner_status is not null or a.outer_status is not null;

  perform set_config('gt.reset_in_progress', 'true', true);
  perform set_config('app.device_admin', 'on', true);

  insert into plant_state (key, value) values ('boardEpoch', v_epoch::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();

  update animals_pilot set
    slaughter = null, slaughtered_by = null, slaughter_time = null, slaughter_by_device = null,
    legs_stickers = false, head_stickers = false,
    maw = null, rumen = null,
    inner_status = null, inner_by = null, inner_time = null, inner_by_device = null,
    not_chalak_inner = false,
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

  update devices_pilot set cursor_slaughter = null, cursor_inner = null, cursor_outer = null, cursor_eso = null
  where true;

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

-- (anything created above that starts with "_" is internal)
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like '\_%'
              and p.proname not in ('_reader_ok', '_my_plant', '_my_role') loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

insert into plant_state (key, value) values ('schemaStep', '41')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ============================================================================
-- SELF-CHECK (structure, rights, and behaviour inside a rolled-back block).
-- The full API-level test is tools/security-selftest.sql.
-- ============================================================================
do $$
declare
  problems text[] := '{}';
  t text; r jsonb; a animals_pilot%rowtype; v_ep bigint;
  dA text := 'gtst41A_' || substr(md5(random()::text), 1, 8);
  dB text := 'gtst41B_' || substr(md5(random()::text), 1, 8);
  tokA text := encode(gen_random_bytes(16), 'hex');
  n int;
begin
  -- structure
  if not exists (select 1 from information_schema.columns where table_name = 'animals_pilot' and column_name = 'eso_by_device') then
    problems := array_append(problems, 'eso_by_device missing'); end if;
  if not exists (select 1 from information_schema.columns where table_name = 'devices_pilot' and column_name = 'cursor_eso') then
    problems := array_append(problems, 'cursor_eso missing'); end if;
  foreach t in array array['animals_pilot_slaughter_ok','animals_pilot_eso_prev_ok','animals_pilot_inner_ok','animals_pilot_outer_ok',
                           'animals_pilot_parts_as_ok','animals_pilot_stamped_as_ok','animals_pilot_eso_ok','animals_pilot_maw_ok',
                           'animals_pilot_rumen_ok','animals_pilot_weights_ok','animals_pilot_print_count_ok'] loop
    if not exists (select 1 from pg_constraint where conrelid = 'public.animals_pilot'::regclass and conname = t and convalidated) then
      problems := array_append(problems, ('value rule missing / not validated: ' || t)); end if;
  end loop;
  if not exists (select 1 from pg_constraint where conrelid = 'public.devices_pilot'::regclass and conname = 'devices_pilot_role_ok' and convalidated) then
    problems := array_append(problems, 'device role rule missing'); end if;
  if exists (select 1 from settings_pilot s, jsonb_array_elements(case when jsonb_typeof(s.settings -> 'users') = 'array' then s.settings -> 'users' else '[]'::jsonb end) u
              where jsonb_typeof(u) = 'object' and u ? 'code') then
    problems := array_append(problems, 'a worker code is still stored in plain text'); end if;

  -- rights
  foreach t in array array['SELECT','INSERT','UPDATE','DELETE'] loop
    if has_table_privilege('anon', 'public.worker_sessions', t) or has_table_privilege('authenticated', 'public.worker_sessions', t) then
      problems := array_append(problems, ('app users can ' || t || ' worker_sessions')); end if;
  end loop;
  if not has_function_privilege('anon', 'worker_login(text,text,text)', 'execute')
     or not has_function_privilege('anon', 'worker_logout(text)', 'execute')
     or not has_function_privilege('anon', 'worker_session_check()', 'execute') then
    problems := array_append(problems, 'worker login functions not callable by the app'); end if;
  if has_function_privilege('anon', '_current_worker()', 'execute')
     or has_function_privilege('anon', '_derive_actor(text,text)', 'execute')
     or has_function_privilege('anon', '_correction_check(text,animals_pilot,text)', 'execute') then
    problems := array_append(problems, 'internal step-41 helpers callable by the app'); end if;
  if _worker_code_hash('1234') <> encode(digest('gt-worker:1234', 'sha256'), 'hex') then
    problems := array_append(problems, 'worker code hash format'); end if;

  -- behaviour (rolled back)
  begin
    v_ep := _board_epoch();
    perform set_config('app.device_admin', 'on', true);
    insert into devices_pilot (id, device_name, assigned_role, device_status) values (dA, 'st41 A', 'outer', 'active'), (dB, 'st41 B', 'outer', 'active');
    insert into device_credentials (device_id, token_hash) values (dA, encode(digest(tokA, 'sha256'), 'hex'));
    perform set_config('app.device_admin', '', true);
    perform set_config('gt.reset_in_progress', 'true', true);
    update animals_pilot set slaughter = 'slaughtered', inner_status = 'confirmed', outer_status = null, outer_by_device = null, outer_time = null,
                             parts_print_count = 0, stamped = false, legs_sorted = false, parts_scanned = false
     where id in (990, 991);
    perform set_config('gt.reset_in_progress', 'false', true);
    update animals_pilot set outer_status = 'glatt', outer_by_device = dA, outer_time = 1 where id = 990;
    select * into a from animals_pilot where id = 990;
    if (select cursor_outer from devices_pilot where id = dA) is distinct from 990 then problems := array_append(problems, 'cursor not advanced'); end if;
    if _correction_check('outer', a, dA) is not null then problems := array_append(problems, 'same tablet, right away: refused'); end if;
    if _correction_check('outer', a, dB) is distinct from 'correction_not_allowed' then problems := array_append(problems, 'another tablet may correct'); end if;
    if _correction_check('outer', a, null) is distinct from 'correction_not_allowed' then problems := array_append(problems, 'no tablet (team leader) may correct'); end if;
    update animals_pilot set outer_status = 'glatt', outer_by_device = dA, outer_time = 2 where id = 991;
    if _correction_check('outer', a, dA) is distinct from 'moved_on' then problems := array_append(problems, 'moved-on tablet may correct'); end if;
    perform set_config('gt.reset_in_progress', 'true', true);
    update animals_pilot set parts_print_count = 1 where id = 991;
    perform set_config('gt.reset_in_progress', 'false', true);
    select * into a from animals_pilot where id = 991;
    if _correction_check('outer', a, dA) is distinct from 'correction_not_allowed' then problems := array_append(problems, 'outer may change after labels'); end if;
    -- value rules
    begin
      update animals_pilot set slaughter = 'bogus' where id = 989;
      problems := array_append(problems, 'bad slaughter value accepted');
    exception when check_violation then null;
    end;
    r := claim_animal_stage(989, 'outer', 'bogus', 'x', 'selftest', v_ep);
    if coalesce(r ->> 'error', '') <> 'bad_value' then problems := array_append(problems, 'claim with a bad value not refused'); end if;
    -- worker codes: stored hashed, login checks the tablet and the code
    update settings_pilot set settings = coalesce(settings, '{}'::jsonb)
         || jsonb_build_object('users', jsonb_build_array(jsonb_build_object('name', 'st41 worker', 'role', 'inspector', 'code', '4321')))
     where id = 1;
    if (select settings -> 'users' -> 0 ->> 'codeHash' from settings_pilot where id = 1) is distinct from _worker_code_hash('4321')
       or (select settings -> 'users' -> 0 ? 'code' from settings_pilot where id = 1) then
      problems := array_append(problems, 'worker code not hashed on save'); end if;
    perform set_config('request.headers', json_build_object('x-device-token', tokA)::text, true);
    r := worker_login('inspector', '0000');
    if coalesce(r ->> 'error', '') <> 'code_invalid' then problems := array_append(problems, 'wrong worker code accepted'); end if;
    r := worker_login('slaughter', '4321');
    if coalesce(r ->> 'error', '') <> 'wrong_station' then problems := array_append(problems, 'worker login on another station accepted'); end if;
    r := worker_login('inspector', '4321');
    if not coalesce((r ->> 'ok')::boolean, false) or r ->> 'name' <> 'st41 worker' then problems := array_append(problems, 'right worker code refused: ' || r::text); end if;
    perform set_config('request.headers', json_build_object('x-device-token', tokA, 'x-worker-token', r ->> 'token')::text, true);
    select count(*) into n from _current_worker() w where w.name = 'st41 worker';
    if n <> 1 then problems := array_append(problems, 'worker session not recognised'); end if;
    update device_credentials set revoked = true where device_id = dA;
    perform set_config('app.device_admin', 'on', true);
    if exists (select 1 from worker_sessions where device_id = dA and not revoked) then problems := array_append(problems, 'worker session survives an unpaired tablet'); end if;
    raise exception 'gt_selftest_rollback';
  exception when others then
    if sqlerrm <> 'gt_selftest_rollback' then problems := array_append(problems, ('self-test error: ' || sqlerrm)); end if;
  end;
  perform set_config('request.headers', '', true);
  perform set_config('app.device_admin', '', true);
  perform set_config('gt.reset_in_progress', 'false', true);

  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 41 self-check FAILED: %', array_to_string(problems, ' | ');
  end if;
  raise notice 'GlattTrack step 41 self-check OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 42 ============================
-- ============================================================================
-- GlattTrack — step 42: the glatt outer screen can send an animal to the
--                       rabbinate (לא חלק רבנות) outer screen
-- ============================================================================
-- With "לא חלק רבנות" on and two outer screens (glatt / rabbinate), the glatt
-- outer inspector may decide an animal is not glatt but fit for the rabbinate
-- ruling. He marks it "to the rabbinate screen": the animal leaves his queue
-- and shows on the second screen, where it can only be ruled כשר רבנות or טרף.
--   • new column not_chalak_outer (once set it stays set for the day)
--   • only an outer station (or the team leader in test mode) may set it,
--     and only while the animal has no outer ruling yet
--   • nobody can clear it; the daily reset clears it
-- Safe to run more than once. Run after step 41.
-- ============================================================================

alter table animals_pilot add column if not exists not_chalak_outer boolean not null default false;

create or replace function _animals_nc_outer_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if current_setting('gt.reset_in_progress', true) = 'true' then
    new.not_chalak_outer := false; return new;
  end if;
  if not _is_api_request() then return new; end if;              -- plant server / SQL editor
  if tg_op = 'INSERT' then
    -- an upsert of an existing row arrives here first: its value is checked on the UPDATE that follows
    if not exists(select 1 from animals_pilot where id = new.id) then new.not_chalak_outer := false; end if;
    return new;
  end if;
  if new.not_chalak_outer is distinct from old.not_chalak_outer then
    if not (coalesce(new.not_chalak_outer, false) = true
            and coalesce(old.not_chalak_outer, false) = false
            and old.outer_status is null
            and _stage_allowed('outer')) then
      new.not_chalak_outer := old.not_chalak_outer;               -- set once, by an outer station, before the ruling
    end if;
  end if;
  return new;
end $$;
revoke execute on function _animals_nc_outer_guard() from public, anon, authenticated;
drop trigger if exists zzz_nc_outer_guard on animals_pilot;
create trigger zzz_nc_outer_guard before insert or update on animals_pilot
  for each row execute function _animals_nc_outer_guard();

-- the week / month / year reports count it as a rabbinate animal too
do $$
declare v_src text;
begin
  select pg_get_functiondef('archive_days(text,date,date)'::regprocedure) into v_src;
  if position('not_chalak_outer' in v_src) = 0 then
    v_src := replace(v_src,
      '''nc'', coalesce((x ->> ''not_chalak_inner'')::boolean, false)',
      '''nc'', (coalesce((x ->> ''not_chalak_inner'')::boolean, false) or coalesce((x ->> ''not_chalak_outer'')::boolean, false))');
    if position('not_chalak_outer' in v_src) = 0 then
      raise exception 'step42: could not update archive_days (unexpected definition)';
    end if;
    execute v_src;
  end if;
end $$;

insert into plant_state (key, value) values ('schemaStep', '42')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ── self-check ──
do $$
declare problems text[] := '{}';
begin
  if not exists(select 1 from pg_trigger where tgname = 'zzz_nc_outer_guard' and tgrelid = 'public.animals_pilot'::regclass) then
    problems := array_append(problems, 'guard trigger missing');
  end if;
  if position('not_chalak_outer' in pg_get_functiondef('archive_days(text,date,date)'::regprocedure)) = 0 then
    problems := array_append(problems, 'archive_days not updated');
  end if;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 42 self-check FAILED: %', array_to_string(problems, '; ');
  end if;
  raise notice 'GlattTrack step 42 self-check OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 43 ============================
-- ============================================================================
-- GlattTrack — step 43: final hardening
-- ============================================================================
-- The plant owner's rules, enforced by the server:
--   • The team leader (manager session) never rules on animals. He manages
--     (settings, pairing, reset, reports) only. Each station rules only its own
--     stage; the outer inspector's ruling is final; nobody overrides.
--   • A station may correct only its own ruling, only from the same tablet,
--     only right away (before THAT tablet ruled the same stage on another
--     animal — judged by time, not by animal number) and only before a later
--     stage acted. A late animal (e.g. #16 sent to the rabbinate screen after
--     that screen ruled #17/#18) may be ruled and corrected right away.
--   • Test mode (owner's single-phone testing on the cloud project only):
--     plant_state 'testMode' = 'on' (default 'off'; settable ONLY with SQL /
--     the service key — no API path writes plant_state) lets a team-leader
--     session act as any station. With it off a team-leader session has no
--     ruling rights anywhere.
--
-- What changes (see the CLIENT CONTRACT block below for the app):
--   1. _stage_allowed: no rights for team-leader sessions (unless testMode).
--   2. set_not_chalak_outer(): the ONLY way to send an animal to the
--      rabbinate outer screen — an 'outer' station only; trigger = 2nd layer.
--      A "not chalak" animal can only be ruled kosher / treif.
--   3. "Moved on" by time: device_stage_cursor (device, stage) = the last
--      animal this device ruled for that stage (any number, every ruling).
--   4. Identity from the server only (_acting_device); p_device_id ignored.
--   5. Idempotent retries: same value by the same device → claimed:true;
--      optional command ids (processed_commands, kept 3 days).
--   6. Audit: device lifecycle writes can no longer be swallowed (the
--      operation fails if the audit row cannot be written); replacement_id;
--      admin_audit for manufacturer / support actions.
--   7. animal_push() / event_append(): direct table writes are revoked.
--   8. Reads: a station sees only its own devices_pilot row; events_pilot and
--      device_lifecycle_events only for team leader / owner (manufacturer with
--      open support access).
--   9. push_settings validates value shapes (bad_settings + key).
--  10. Fail closed: protection switches in system_flags are ignored.
--  11. archive_days: 'nci' / 'nco' (and 'nc' = nci or nco).
--  12. One device per station slot (unique index).
--  13. Team-leader session bound to the device + app session it was made on;
--      10 hours.
--  14. Brakes: rejected corrections per device, manufacturer logins.
--  15. Legacy multi-plant tables: no app access.
--  16. Inner check takeover: the tablet that lost the check can't overwrite it.
-- Safe to run more than once. Run after step 42.
-- ============================================================================
--
-- ── CLIENT CONTRACT (all RPCs: POST /rest/v1/rpc/<name>, JSON named args) ───
--
-- animal_push(p_rows jsonb, p_command_id uuid default null) → jsonb
--   p_rows: one row object or an array (≤ 50) of row objects, exactly what
--   _sbPushAnimal sends today to the table: {id, device_id, board_epoch, …}.
--   Accepted columns: id, device_id (ignored: the server sets it),
--   board_epoch, slaughter, slaughter_time, slaughtered_by,
--   slaughter_by_device, legs_stickers, head_stickers, maw, rumen,
--   inner_status, inner_time, inner_by, inner_by_device, outer_status,
--   outer_time, outer_by, outer_by_device, parts_scanned, tongue_sticker,
--   cheek_sticker, weight_right, weight_left, weight_stage2, weight_stage3,
--   weight_*_skipped (4), eso_checked, eso_result, legs_sorted, stamped,
--   stamped_as, not_chalak_inner, parts_print_count, parts_printed_as.
--   Other keys are ignored and listed in "ignored" (not_chalak_outer: use
--   set_not_chalak_outer). Same upsert + merge semantics as the table
--   upsert (only the columns sent are written, every guard trigger runs).
--   ok:    {"ok":true, "rows":[<server row after merge>, …], "ignored":[…]?}
--   error: {"ok":false, "error":<code>, "id":<row id>?, "row":<server row>?}
--     codes: bad_rows, bad_id, device_not_paired, wrong_station, stale_board,
--            moved_on, correction_not_allowed, eso_locked, invalid_value,
--            rate_limited (+ retry_after s), command_id_conflict, server_error
--   All rows of one call are applied or none. A replayed p_command_id from the
--   same device answers the stored result with "replayed":true.
--
-- event_append(p_event jsonb) → jsonb
--   p_event: the row the app inserts today: {event_id (uuid, required),
--   animal_no, stage, action, payload, actor, device_id, occurred_at,
--   prev_hash, event_hash}. actor / device_id / chain are set by the server.
--   ok:    {"ok":true, "event_id":…, "chain_pos":…}  or  {"ok":true,"duplicate":true}
--   error: {"ok":false, "error":<code>}   codes: bad_event, device_not_paired,
--          manufacturer_no_access, manufacturer_no_kashrut, server_error
--
-- set_not_chalak_outer(p_id int, p_epoch bigint, p_command_id uuid default null)
--   ok: {"ok":true, "row":…}  (already set: also "already":true)
--   error codes: bad_id, stale_board, device_not_paired, wrong_station
--   (only an 'outer' station), already_ruled (+ row), command_id_conflict
--
-- claim_animal_stage(p_id, p_stage, p_value, p_actor, p_device_id, p_epoch
--                    [, p_command_id uuid])   (7-arg form: all 7 names sent)
-- eso_change(p_id, p_result, p_device_id, p_epoch [, p_command_id uuid])
-- outer_open(p_id, p_epoch, p_open, p_device_id [, p_command_id uuid])
--   p_device_id is IGNORED (identity = the device key / test-mode session).
--   New answers: error 'device_not_paired' (no paired device), claim of the
--   same value by the same device → {"claimed":true,"duplicate":true,…},
--   claim/eso error 'rate_limited', outer claim of a "not chalak" animal with
--   another value than kosher/treif → {"claimed":false,"error":"bad_value",
--   "reason":"nc_kosher_or_treif_only"}, eso_change 'rate_limited'.
--
-- manager_login(p_code) — unchanged call; the session is bound to the device
--   key (x-device-token, if any) and the app session (JWT sub) it was made
--   with, and lasts 10 hours. The same token sent from another paired device
--   or another app session is not valid there. Manufacturer logins: extra
--   brake → {"ok":false,"reason":"locked","retry_after":…}.
-- push_settings → new {"ok":false,"error":"bad_settings","key":<k>,"reason":…}
--
-- Reads: devices_pilot → a station sees only its own row (live updates: the
--   row whose auth_uid is the app session); events_pilot and
--   device_lifecycle_events → team leader / owner (manufacturer only with
--   open support access). animals_pilot / settings_pilot / archive: as before.
-- Writes: INSERT/UPDATE on animals_pilot and INSERT on events_pilot are
--   revoked for anon/authenticated — use animal_push / event_append.
-- ============================================================================

-- ============================================================================
-- 0. TABLES / COLUMNS
-- ============================================================================
insert into plant_state (key, value) values ('testMode', 'off') on conflict (key) do nothing;

create table if not exists processed_commands (
  command_id uuid primary key,
  device_id  text not null,
  fn         text not null,
  result     jsonb not null,
  at         timestamptz not null default now()
);
create index if not exists processed_commands_at on processed_commands (at);

create table if not exists device_stage_cursor (
  device_id text not null,
  stage     text not null,
  animal_id integer not null,
  at        timestamptz not null default now(),
  primary key (device_id, stage)
);

create table if not exists rate_events (
  id   bigserial primary key,
  kind text not null,
  key  text not null,
  at   timestamptz not null default now()
);
create index if not exists rate_events_kind_key_at on rate_events (kind, key, at desc);
create index if not exists rate_events_at on rate_events (at);

create table if not exists admin_audit (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  who     text,
  role    text,
  action  text not null,
  target  text,
  detail  jsonb not null default '{}'::jsonb
);
create index if not exists admin_audit_at on admin_audit (at desc);

alter table manager_sessions add column if not exists device_id text;
alter table manager_sessions alter column expires_at set default now() + interval '10 hours';
alter table device_lifecycle_events add column if not exists replacement_id uuid;

do $$
declare t text;
begin
  foreach t in array array['processed_commands','device_stage_cursor','rate_events','admin_audit'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
  end loop;
end $$;

-- existing team-leader sessions: at most 10 hours
update manager_sessions s set expires_at = least(s.expires_at, s.created_at + interval '10 hours')
 where s.expires_at > s.created_at + interval '10 hours'
   and exists (select 1 from plant_managers m where m.id = s.manager_id and m.role <> 'manufacturer');

-- the "last animal" of each tablet now lives in device_stage_cursor (seeded from the old columns)
insert into device_stage_cursor (device_id, stage, animal_id)
select id, 'slaughter', cursor_slaughter from devices_pilot where cursor_slaughter is not null
union all select id, 'inner', cursor_inner from devices_pilot where cursor_inner is not null
union all select id, 'outer', cursor_outer from devices_pilot where cursor_outer is not null
union all select id, 'eso', cursor_eso from devices_pilot where cursor_eso is not null
on conflict (device_id, stage) do nothing;

-- private schema for row-security helpers (not exposed by the API)
create schema if not exists gt_rls;
revoke all on schema gt_rls from public;
grant usage on schema gt_rls to anon, authenticated, service_role;

-- ============================================================================
-- 1. CORE HELPERS
-- ============================================================================
-- protection is always on (maintenance only through SQL, which is not the API)
create or replace function _device_auth_required() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select true;
$$;

-- a request that came through the API (PostgREST login). gt.as_api lets the
-- step self-check run the API rules from SQL (it can only make things stricter).
create or replace function _is_api_request() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select session_user = 'authenticator' or coalesce(current_setting('gt.as_api', true), '') = 'on';
$$;

-- any app caller: the API, or live updates (which run with the app's role)
create or replace function _is_app_caller() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select _is_api_request() or coalesce(current_setting('role', true), '') in ('anon', 'authenticated');
$$;

create or replace function _test_mode_on() returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select lower(trim(value)) from plant_state where key = 'testMode'), 'off') = 'on';
$$;

-- the app session (JWT "sub"), also when auth.uid() is not available
create or replace function _auth_uid_safe() returns uuid
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

-- is a team-leader / owner / manufacturer session presented from where it was made?
create or replace function _mgr_session_bound(p_dev text, p_uid uuid) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _is_api_request() or _request_is_service_role() then return true; end if;
  if p_dev is distinct from _current_device_id() then return false; end if;       -- another (or no) paired device
  if p_uid is not null and p_uid is distinct from _auth_uid_safe() then return false; end if;   -- another app session
  return true;
end $$;

create or replace function _session_role(p_token text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select m.role from manager_sessions s join plant_managers m on m.id = s.manager_id
   where p_token is not null and s.token = p_token and s.expires_at > now() and m.active
     and _mgr_session_bound(s.device_id, s.auth_uid)
   limit 1;
$$;

create or replace function _session_name(p_token text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select m.name from manager_sessions s join plant_managers m on m.id = s.manager_id
   where p_token is not null and s.token = p_token and s.expires_at > now() and m.active
     and _mgr_session_bound(s.device_id, s.auth_uid)
   limit 1;
$$;

create or replace function _manufacturer_session_valid(p_token text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(_session_role(p_token), '') = 'manufacturer';
$$;

-- the team-leader login check can no longer be switched off
create or replace function _is_real_manager(p_token text) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(_session_role(p_token), '') = 'manager';
$$;

create or replace function _manager_session_valid(p_token text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text := coalesce(_session_role(p_token), '');
begin
  if v_role = 'manager' then return true; end if;
  if v_role = 'manufacturer' and _support_access_open() then return true; end if;
  return false;
end $$;

-- the device this request acts as: the paired device key; in test mode a
-- team-leader session without a device acts as its own pseudo device
create or replace function _acting_device() returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

-- only the server itself (SQL editor, server jobs, service key, internal admin
-- code) is privileged — never a team-leader session
create or replace function _request_privileged() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _is_api_request() then return true; end if;
  if _request_is_service_role() then return true; end if;
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  return false;
end $$;

-- may this request rule / write this stage?
create or replace function _stage_allowed(p_stage text) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text; v_ok boolean := false;
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
  -- the team leader has NO ruling rights — except in test mode (SQL-only switch)
  return _test_mode_on() and _request_has_manager();
end $$;

-- sending an animal to the rabbinate outer screen: an 'outer' station only
create or replace function _nc_outer_allowed() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _is_api_request() or _request_is_service_role() then return true; end if;
  if exists (select 1 from devices_pilot d
              where d.id = _current_device_id() and d.assigned_role = 'outer' and d.device_status = 'active') then
    return true;
  end if;
  return _test_mode_on() and _request_has_manager();
end $$;

create or replace function _device_write_allowed() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_dev text;
begin
  if not _is_api_request() then return true; end if;                    -- SQL editor / server jobs
  if _request_is_service_role() then return true; end if;                -- server-side code with the service key
  if coalesce(current_setting('app.device_admin', true), '') = 'on' then return true; end if;
  if _request_has_manager() then return true; end if;                    -- team leader (events / settings only; rulings: _stage_allowed)
  v_dev := _current_device_id();
  if v_dev is null then return false; end if;
  return exists(select 1 from devices_pilot
                 where id = v_dev and assigned_role is not null
                   and assigned_role <> 'display'                        -- a counter screen only reads
                   and coalesce(device_status, 'active') <> 'retired');
end $$;

-- board / settings / archive reads (unchanged rules, but always on)
create or replace function _reader_ok() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function _devices_assignment_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

-- ── row-security helpers (schema gt_rls: callable by the app roles, not an API endpoint) ──
create or replace function gt_rls.devices_read_all() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function gt_rls.devices_read_own_ids() returns text[]
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function gt_rls.events_reader_ok() returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text;
begin
  if not _is_app_caller() or _request_is_service_role() then return true; end if;
  v_role := coalesce(_session_role(_request_headers() ->> 'x-manager-token'), '');
  if v_role in ('manager', 'owner') then return true; end if;
  if v_role = 'manufacturer' and _support_access_open() then return true; end if;
  return false;
end $$;

revoke all on function gt_rls.devices_read_all() from public;
revoke all on function gt_rls.devices_read_own_ids() from public;
revoke all on function gt_rls.events_reader_ok() from public;
grant execute on function gt_rls.devices_read_all() to anon, authenticated, service_role;
grant execute on function gt_rls.devices_read_own_ids() to anon, authenticated, service_role;
grant execute on function gt_rls.events_reader_ok() to anon, authenticated, service_role;

-- ============================================================================
-- 2. AUDIT, BRAKES, COMMAND IDS
-- ============================================================================
-- a security event in the plant's event log (keeps an outer app.device_admin as it was)
create or replace function _security_event(p_animal_no integer, p_action text, p_payload jsonb, p_actor text, p_device text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_prev text := coalesce(current_setting('app.device_admin', true), '');
begin
  perform set_config('app.device_admin', 'on', true);
  insert into events_pilot (event_id, animal_no, stage, action, payload, actor, device_id, occurred_at)
  values (gen_random_uuid(), p_animal_no, 'security', p_action, coalesce(p_payload, '{}'::jsonb), p_actor,
          coalesce(p_device, 'server'), now()::text);
  perform set_config('app.device_admin', v_prev, true);
end $$;

create or replace function _rate_hit(p_kind text, p_key text) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if random() < 0.05 then delete from rate_events where at < now() - interval '2 days'; end if;
  insert into rate_events (kind, key) values (p_kind, coalesce(p_key, '?'));
end $$;

create or replace function _rate_count(p_kind text, p_key text, p_window interval) returns integer
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select count(*)::int from rate_events
   where kind = p_kind and (p_key is null or key = p_key) and at > now() - p_window;
$$;

-- a tablet with many refused corrections in a short time is braked (10 in 10 minutes)
create or replace function _correction_braked(p_dev text) returns integer
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function _log_correction_rejected(p_dev text, p_id integer, p_stage text, p_reason text, p_detail jsonb)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform _rate_hit('correction_rejected', coalesce(p_dev, 'unknown'));
  perform _security_event(case when p_id is null then null else p_id + 1 end, 'correction_rejected',
                          jsonb_build_object('stage', p_stage, 'reason', p_reason) || coalesce(p_detail, '{}'::jsonb),
                          null, coalesce(p_dev, 'unknown'));
end $$;

-- command ids: a repeated command from the same device answers the stored result
create or replace function _cmd_get(p_cmd uuid, p_dev text, p_fn text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function _cmd_put(p_cmd uuid, p_dev text, p_fn text, p_result jsonb) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_cmd is null or p_result is null then return; end if;
  if coalesce(p_result ->> 'error', '') in ('rate_limited', 'command_id_conflict', 'server_error') then return; end if;
  delete from processed_commands where at < now() - interval '3 days';
  insert into processed_commands (command_id, device_id, fn, result) values (p_cmd, coalesce(p_dev, '?'), p_fn, p_result)
    on conflict (command_id) do nothing;
end $$;

-- device lifecycle audit: NEVER swallowed — if it can't be written, the operation fails
create or replace function _audit_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text,
                                               p_other text, p_replacement_id uuid, p_actor text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  insert into device_lifecycle_events (device_id, action, station_id, station_slot, actor, reason, replacement_device_id, replacement_id)
  values (p_device, p_action, p_role, p_idx, coalesce(p_actor, 'manager'), left(p_reason, 200), p_other, p_replacement_id);
end $$;

create or replace function _log_device_event(p_device text, p_action text, p_role text, p_idx integer, p_reason text, p_other text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform _audit_device_event(p_device, p_action, p_role, p_idx, p_reason, p_other,
                              nullif(current_setting('gt.replacement_id', true), '')::uuid,
                              coalesce(nullif(current_setting('gt.audit_actor', true), ''), 'manager'));
end $$;

-- every device key revoke is audited, whatever path revoked it
create or replace function _credential_audit() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
drop trigger if exists zz_credential_audit on device_credentials;
create trigger zz_credential_audit after update on device_credentials
  for each row execute function _credential_audit();

-- manufacturer / support actions: who, what, on what, when
create or replace function _admin_audit(p_token text, p_action text, p_target text, p_detail jsonb)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  insert into admin_audit (who, role, action, target, detail)
  values (_session_name(p_token), _session_role(p_token), p_action, p_target, coalesce(p_detail, '{}'::jsonb));
end $$;

-- ============================================================================
-- 3. "MOVED ON" BY TIME + CORRECTION AUTHORITY
-- ============================================================================
-- the last animal each device ruled, per stage (any number: a late animal counts)
create or replace function animals_pilot_advance_cursor() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
drop trigger if exists trg_animals_pilot_advance_cursor on animals_pilot;
create trigger trg_animals_pilot_advance_cursor after insert or update on animals_pilot
  for each row execute function animals_pilot_advance_cursor();

-- May device p_dev change the existing <stage> ruling of animal a (the row
-- BEFORE the change)? null = yes, else 'correction_not_allowed' / 'moved_on'.
--   yes iff: the ruling was made by p_dev, no later stage acted, and the last
--   animal p_dev ruled for that stage (by time) is this animal.
create or replace function _correction_check(p_stage text, a animals_pilot, p_dev text) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

-- ============================================================================
-- 4. THE MERGE (identity from the server, the inner-check takeover rule)
-- ============================================================================
create or replace function _animals_merge() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

-- ============================================================================
-- 5. "NOT CHALAK" (rabbinate) OUTER RULES
-- ============================================================================
-- second layer: not_chalak_outer changes only through set_not_chalak_outer()
create or replace function _animals_nc_outer_guard() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
drop trigger if exists zzz_nc_outer_guard on animals_pilot;
create trigger zzz_nc_outer_guard before insert or update on animals_pilot
  for each row execute function _animals_nc_outer_guard();

-- a "not chalak" animal (slaughter notChalak, inner or outer "not chalak") can
-- only be ruled kosher (כשר רבנות) or treif at the outer check
create or replace function _animals_nc_outer_value() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
drop trigger if exists zzzz_nc_outer_value on animals_pilot;
create trigger zzzz_nc_outer_value before insert or update on animals_pilot
  for each row execute function _animals_nc_outer_value();

-- ============================================================================
-- 6. DAILY RESET (also the per-device cursors, rabbinate flag)
-- ============================================================================
create or replace function _do_board_reset(p_reason text, p_business_date date) returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  insert into daily_board_archive (business_date, reason, animals_count, board)
  select p_business_date, p_reason, count(*), coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]'::jsonb)
    from animals_pilot a
   where a.slaughter is not null or a.inner_status is not null or a.outer_status is not null;

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

-- ============================================================================
-- 7. EVENTS: the server names the device and the worker on every event
-- ============================================================================
create or replace function _events_actor() returns trigger
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
drop trigger if exists a1_events_actor on events_pilot;
create trigger a1_events_actor before insert on events_pilot
  for each row execute function _events_actor();

-- ============================================================================
-- 8. RULING RPCs — identity from the server, idempotent retries, command ids
-- ============================================================================
-- the device a call acts as: API → the server's identity only (the p_device_id
-- a tablet sends is ignored); the plant server itself (SQL / service key) may
-- name one.
create or replace function _call_device(p_client text) returns text
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if _is_api_request() and not _request_is_service_role() then return _acting_device(); end if;
  return coalesce(_current_device_id(), nullif(left(p_client, 80), ''), 'server');
end $$;


-- why a call without an acting device is refused: a team-leader session has no
-- ruling rights (wrong_station); anything else is not a paired device
create or replace function _no_device_error() returns text
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select case when _request_has_manager() then 'wrong_station' else 'device_not_paired' end;
$$;

create or replace function claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text,
                                              p_epoch bigint, p_command_id uuid)
returns jsonb
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
  a animals_pilot%rowtype;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('claimed', false, 'error', 'bad_id');
  end if;
  if p_stage is null or p_stage not in ('slaughter', 'inner_start', 'inner', 'outer', 'eso', 'legs', 'stamped') then
    return jsonb_build_object('claimed', false, 'error', 'bad_stage');
  end if;
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

-- the call the app makes today (6 named arguments): same function, no command id
create or replace function claim_animal_stage(p_id integer, p_stage text, p_value text, p_actor text, p_device_id text, p_epoch bigint default null)
returns jsonb
language sql security definer set search_path = public, extensions, pg_temp as $$
  select claim_animal_stage(p_id, p_stage, p_value, p_actor, p_device_id, p_epoch, null::uuid);
$$;

-- ── esophagus change: only the tablet that ruled, right away, before inner ──
create or replace function eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint, p_command_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function eso_change(p_id integer, p_result text, p_device_id text, p_epoch bigint default null)
returns jsonb
language sql security definer set search_path = public, extensions, pg_temp as $$
  select eso_change(p_id, p_result, p_device_id, p_epoch, null::uuid);
$$;

-- ── one animal open on ONE outer screen at a time ──
create or replace function outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text, p_command_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function outer_open(p_id integer, p_epoch bigint, p_open boolean, p_device_id text default null)
returns jsonb
language sql security definer set search_path = public, extensions, pg_temp as $$
  select outer_open(p_id, p_epoch, p_open, p_device_id, null::uuid);
$$;

-- ── the inner inspector's lung drawing ──
create or replace function lung_drawing_set(p_id integer, p_epoch bigint, p_drawing text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := _board_epoch(); v_dev text;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
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
end $$;

-- ── the glatt outer screen sends an animal to the rabbinate outer screen ──
-- the ONLY way to set not_chalak_outer
create or replace function set_not_chalak_outer(p_id integer, p_epoch bigint, p_command_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_epoch bigint := _board_epoch(); v_dev text; a animals_pilot%rowtype; v_res jsonb;
begin
  if p_id is null or p_id < 0 or p_id > 999 then
    return jsonb_build_object('ok', false, 'error', 'bad_id');
  end if;
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
  if coalesce(a.not_chalak_outer, false) then
    v_res := jsonb_build_object('ok', true, 'already', true, 'row', to_jsonb(a));
  elsif a.outer_status is not null then
    v_res := jsonb_build_object('ok', false, 'error', 'already_ruled', 'row', to_jsonb(a));
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

-- ============================================================================
-- 9. animal_push — the ONLY write path for a board row (replaces the table upsert)
-- ============================================================================
create or replace function _push_is_correction(p_rows jsonb) returns boolean
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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
end $$;

create or replace function animal_push(p_rows jsonb, p_command_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
    v_res := jsonb_build_object('ok', false, 'error', v_err)
             || case when v_cur is not null then jsonb_build_object('id', v_cur,
                     'row', (select to_jsonb(a) from animals_pilot a where a.id = v_cur)) else '{}'::jsonb end
             || case when v_err = 'server_error' then jsonb_build_object('message', left(v_msg, 200)) else '{}'::jsonb end;
  else
    v_res := jsonb_build_object('ok', true, 'rows', v_out)
             || case when array_length(v_ignored, 1) > 0 then jsonb_build_object('ignored', to_jsonb(v_ignored)) else '{}'::jsonb end;
  end if;
  perform _cmd_put(p_command_id, v_dev, 'animal_push', v_res);
  return v_res;
end $$;

-- ============================================================================
-- 10. event_append — the ONLY write path into the event log
-- ============================================================================
create or replace function event_append(p_event jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
end $$;

-- ============================================================================
-- 11. SETTINGS: value shapes are checked (push_settings)
-- ============================================================================
create or replace function _jint_ok(v jsonb, lo numeric, hi numeric) returns boolean
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare n numeric;
begin
  if jsonb_typeof(v) = 'number' then n := (v #>> '{}')::numeric;
  elsif jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^-?\d{1,12}$' then n := (v #>> '{}')::numeric;
  else return false; end if;
  return n = trunc(n) and n between lo and hi;
end $$;

create or replace function _jnum_ok(v jsonb, lo numeric, hi numeric) returns boolean
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare n numeric;
begin
  if jsonb_typeof(v) = 'number' then n := (v #>> '{}')::numeric;
  elsif jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^-?\d{1,12}(\.\d{1,6})?$' then n := (v #>> '{}')::numeric;
  else return false; end if;
  return n between lo and hi;
end $$;

create or replace function _jstr_ok(v jsonb, maxlen int) returns boolean
language sql immutable set search_path = public, extensions, pg_temp as $$
  select jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and length(v #>> '{}') <= maxlen);
$$;

-- null = fine, else why the value of setting p_key is refused.
-- Only keys whose shape is known are checked; null always clears a key.
create or replace function _settings_value_error(p_key text, v jsonb) returns text
language plpgsql stable set search_path = public, extensions, pg_temp as $$
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
end $$;

create or replace function push_settings(p_settings jsonb, p_device_id text, p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
  v_label text;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'bad_settings');
  end if;
  if p_token is not null then
    is_manager := _manager_session_valid(p_token);
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
                         jsonb_build_object('keys', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_object_keys(incoming) x)));
  end if;
  return jsonb_build_object('ok', true, 'ignored', to_jsonb(ignored));
end $$;

-- ============================================================================
-- 12. TEAM-LEADER SESSIONS: bound to device + app session, 10 hours;
--     manufacturer logins braked and audited
-- ============================================================================
create or replace function manager_login(p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function manager_session_check(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_role text; v_exp timestamptz;
begin
  select m.role, s.expires_at into v_role, v_exp
    from manager_sessions s join plant_managers m on m.id = s.manager_id
   where p_token is not null and s.token = p_token and s.expires_at > now() and m.active
     and _mgr_session_bound(s.device_id, s.auth_uid);
  return jsonb_build_object('ok', v_role is not null, 'role', v_role, 'expires_at', v_exp);
end $$;

create or replace function device_heartbeat(p_device_id text, p_device_name text, p_info jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
end $$;

-- worker sessions of a team leader exist only in test mode
create or replace function _current_worker() returns table (name text, role text)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function worker_login(p_role text, p_code text, p_name text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
       and (x ->> 'codeHash' = v_h1 or (v_h2 is not null and x ->> 'codeHash' = v_h2)
            or (x ? 'code' and x ->> 'code' = trim(p_code)))
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

-- ============================================================================
-- 13. DEVICE LIFECYCLE (audited, never silently)
-- ============================================================================
create or replace function device_pair(p_token text, p_code text, p_role text, p_index integer default 0,
                                       p_replace boolean default false, p_device_name text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r device_pairing%rowtype; v_idx int; v_tok text; v_old record; v_repl uuid; v_actor text; v_prev text;
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
    perform set_config('gt.audit_reason', 'replaced by pairing', true);
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
     where id = v_old.id;
    update device_credentials set revoked = true where device_id = v_old.id;   -- audited as KEY_REVOKED
    perform _audit_device_event(v_old.id, 'UNASSIGNED', p_role, v_idx, 'replaced by pairing', r.device_id, v_repl, v_actor);
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
                              case when v_repl is not null then 'paired with code (replacement)' else 'paired with code' end,
                              null, v_repl, v_actor);
  perform set_config('gt.replacement_id', '', true);
  perform set_config('gt.audit_reason', '', true);
  perform set_config('gt.audit_actor', '', true);
  return jsonb_build_object('ok', true, 'device_id', r.device_id)
         || case when v_repl is not null then jsonb_build_object('replacement_id', v_repl) else '{}'::jsonb end;
end $$;

create or replace function device_unpair(p_token text, p_device_id text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d devices_pilot%rowtype; v_actor text;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into d from devices_pilot where id = p_device_id;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  v_actor := coalesce(_session_name(p_token), 'manager');
  perform set_config('gt.audit_actor', v_actor, true);
  perform set_config('gt.audit_reason', coalesce(left(p_reason, 200), 'unpaired'), true);
  perform set_config('app.device_admin', 'on', true);
  update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now()
   where id = p_device_id;
  update device_credentials set revoked = true where device_id = p_device_id;
  perform set_config('app.device_admin', '', true);
  perform _audit_device_event(p_device_id, 'UNASSIGNED', d.assigned_role, d.assigned_index, coalesce(p_reason, 'unpaired'), null, null, v_actor);
  if coalesce(_session_role(p_token), '') = 'manufacturer' then
    perform _admin_audit(p_token, 'device_unpair', p_device_id, jsonb_build_object('reason', p_reason));
  end if;
  perform set_config('gt.audit_actor', '', true);
  perform set_config('gt.audit_reason', '', true);
  return jsonb_build_object('ok', true);
end $$;

create or replace function device_manage(p_token text, p_device_id text, p_action text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare d devices_pilot%rowtype; v_actor text; v_name text;
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into d from devices_pilot where id = p_device_id;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_action not in ('retire', 'reactivate', 'rename') then
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;
  v_actor := coalesce(_session_name(p_token), 'manager');
  perform set_config('gt.audit_actor', v_actor, true);
  perform set_config('app.device_admin', 'on', true);
  if p_action = 'retire' then
    perform set_config('gt.audit_reason', coalesce(left(p_reason, 200), 'retired'), true);
    update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null,
           device_status = 'retired', retired_at = now(), retired_by = 'manager',
           retired_reason = coalesce(left(p_reason, 200), 'מסך תקול'), updated_at = now()
     where id = p_device_id;
    update device_credentials set revoked = true where device_id = p_device_id;
    perform _audit_device_event(p_device_id, 'DEVICE_RETIRED', d.assigned_role, d.assigned_index, p_reason, null, null, v_actor);
  elsif p_action = 'reactivate' then
    update devices_pilot set device_status = 'active', retired_at = null, retired_by = null,
           retired_reason = null, updated_at = now()
     where id = p_device_id;
    perform _audit_device_event(p_device_id, 'DEVICE_REACTIVATED', null, null, p_reason, null, null, v_actor);
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
    perform _admin_audit(p_token, 'device_' || p_action, p_device_id, jsonb_build_object('reason', p_reason));
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================================
-- 14. MANUFACTURER / SUPPORT ACTIONS — each one written to admin_audit
-- ============================================================================
create or replace function manufacturer_set_billing(p_token text, p_enabled boolean, p_price numeric, p_currency text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
  v_billing := jsonb_build_object('enabled', coalesce(p_enabled, false), 'price', round(p_price, 4),
                                  'currency', p_currency, 'updatedAt', now()::text);
  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  insert into settings_pilot (id, settings, device_id, updated_at)
  values (1, jsonb_build_object('billing', v_billing), 'manufacturer', now())
  on conflict (id) do update
    set settings = coalesce(settings_pilot.settings, '{}'::jsonb) || jsonb_build_object('billing', v_billing),
        device_id = 'manufacturer', updated_at = now();
  perform _admin_audit(p_token, 'billing', 'settings_pilot.billing', v_billing);
  return jsonb_build_object('ok', true, 'billing', v_billing);
end $$;

create or replace function support_force_reload(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('glatttrack_settings'));
  update settings_pilot
     set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('forceReloadAt', now()::text),
         device_id = 'support', updated_at = now()
   where id = 1;
  perform _admin_audit(p_token, 'force_reload', 'all devices', '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

create or replace function support_access_set(p_token text, p_hours integer)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_until timestamptz; v_name text;
begin
  if coalesce(_session_role(p_token), '') <> 'manager' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_hours is null or p_hours < 0 or p_hours > 168 then
    return jsonb_build_object('ok', false, 'error', 'bad_hours');
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
          jsonb_build_object('hours', p_hours, 'until', v_until), v_name, 'server', now()::text);
  perform set_config('app.device_admin', '', true);
  perform _admin_audit(p_token, case when p_hours = 0 then 'support_access_closed' else 'support_access_opened' end,
                       'manufacturer', jsonb_build_object('hours', p_hours, 'until', v_until));
  return jsonb_build_object('ok', true, 'until', v_until);
end $$;

create or replace function support_diagnostics(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
end $$;

create or replace function security_summary(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

create or replace function device_whoami() returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id text; d devices_pilot%rowtype; v_sent boolean;
begin
  v_sent := coalesce(_request_headers() ->> 'x-device-token', '') <> '';
  v_id := _current_device_id();
  if v_id is not null then select * into d from devices_pilot where id = v_id; end if;
  return jsonb_build_object('key_sent', v_sent, 'device_id', v_id,
                            'role', d.assigned_role, 'index', d.assigned_index,
                            'enforced', true);
end $$;

create or replace function device_paired_list(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not _manager_session_valid(p_token) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'devices',
    coalesce((select jsonb_agg(device_id) from device_credentials where not revoked), '[]'::jsonb),
    'enforced', true);
end $$;

-- ============================================================================
-- 15. REPORTS: "not chalak" inner and outer kept apart (nc = either)
-- ============================================================================
create or replace function archive_days(p_token text, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
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

-- ============================================================================
-- 16. ONE DEVICE PER STATION SLOT
-- ============================================================================
do $$
declare g record; d record; n int := 0;
begin
  perform set_config('app.device_admin', 'on', true);
  perform set_config('gt.audit_actor', 'server (step 43)', true);
  perform set_config('gt.audit_reason', 'slot conflict cleanup (step 43)', true);
  -- a station without a slot number is slot 0
  update devices_pilot x set assigned_index = 0
   where x.assigned_role is not null and x.assigned_index is null and x.device_status = 'active';
  -- two devices on one slot: the most recently paired one keeps it
  for g in select assigned_role, assigned_index from devices_pilot
            where assigned_role is not null and device_status = 'active'
            group by 1, 2 having count(*) > 1 loop
    for d in select id, assigned_role, assigned_index from devices_pilot
              where assigned_role = g.assigned_role and assigned_index = g.assigned_index and device_status = 'active'
              order by paired_at desc nulls last, last_seen desc nulls last, updated_at desc nulls last, id
              offset 1 loop
      update devices_pilot set assigned_role = null, assigned_index = null, paired_at = null, updated_at = now() where id = d.id;
      update device_credentials set revoked = true where device_id = d.id and not revoked;
      perform _audit_device_event(d.id, 'UNASSIGNED', d.assigned_role, d.assigned_index, 'slot conflict cleanup (step 43)',
                                  null, null, 'server (step 43)');
      n := n + 1;
    end loop;
  end loop;
  perform set_config('app.device_admin', '', true);
  perform set_config('gt.audit_actor', '', true);
  perform set_config('gt.audit_reason', '', true);
  if n > 0 then raise notice 'GlattTrack step 43: % device(s) sharing a station slot were unpaired (most recent kept)', n; end if;
end $$;
create unique index if not exists devices_pilot_one_per_slot on devices_pilot (assigned_role, assigned_index)
  where assigned_role is not null and device_status = 'active';

-- ============================================================================
-- 17. RIGHTS: no direct writes, narrowed reads, legacy tables closed
-- ============================================================================
drop policy if exists "anon insert animals_pilot" on animals_pilot;
drop policy if exists "anon update animals_pilot" on animals_pilot;
drop policy if exists "anon insert events_pilot" on events_pilot;
revoke insert, update, delete, truncate, references, trigger on animals_pilot from public, anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on events_pilot from public, anon, authenticated;
grant select on animals_pilot, events_pilot to anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['settings_pilot','devices_pilot','daily_board_archive','device_lifecycle_events'] loop
    execute format('revoke insert, update, delete, truncate, references, trigger on %I from public, anon, authenticated', t);
    execute format('grant select on %I to anon, authenticated', t);
  end loop;
  foreach t in array array['device_credentials','device_pairing','manager_sessions','plant_managers','system_flags',
                           'plant_state','login_attempts','pairing_requests','events_chain_head','worker_sessions',
                           'lung_drawings','processed_commands','device_stage_cursor','rate_events','admin_audit'] loop
    if to_regclass('public.' || t) is not null then
      execute format('revoke all on %I from public, anon, authenticated', t);
    end if;
  end loop;
end $$;
revoke all on all sequences in schema public from public, anon, authenticated;

-- a station reads only its own device row; the team leader / owner / manufacturer read all
drop policy if exists "read devices_pilot" on devices_pilot;
create policy "read devices_pilot" on devices_pilot for select to anon, authenticated
  using ((select gt_rls.devices_read_all()) or id = any ((select gt_rls.devices_read_own_ids())::text[]));
-- the event log: team leader / owner (manufacturer only with open support access)
drop policy if exists "read events_pilot" on events_pilot;
create policy "read events_pilot" on events_pilot for select to anon, authenticated
  using ((select gt_rls.events_reader_ok()));
drop policy if exists "read device_lifecycle_events" on device_lifecycle_events;
create policy "read device_lifecycle_events" on device_lifecycle_events for select to anon, authenticated
  using ((select gt_rls.events_reader_ok()));

-- legacy multi-plant tables (not used by the app): no access. "plants" keeps a
-- SELECT that returns no rows — the app's start-up connection probe reads it.
do $$
declare t text; p record;
begin
  foreach t in array array['animals','audit_log','batches','custom_statuses','problem_reports','profiles',
                           'reprint_log','source_farms','outer_status_pilot','plants'] loop
    if to_regclass('public.' || t) is not null then
      execute format('revoke all on %I from public, anon, authenticated', t);
      execute format('alter table %I enable row level security', t);
    end if;
  end loop;
  if to_regclass('public.plants') is not null then
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'plants' loop
      execute format('drop policy %I on plants', p.policyname);
    end loop;
    execute 'create policy "plants probe: no rows" on plants for select to anon, authenticated using (false)';
    execute 'grant select on plants to anon, authenticated';
  end if;
end $$;

-- functions: the app's API only; everything internal (and every trigger function) closed
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname, p.prorettype = 'trigger'::regtype as trg
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' loop
    if f.trg or (f.proname like '\_%' and f.proname <> '_reader_ok') then
      execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
grant execute on function _reader_ok() to anon, authenticated;

do $$
declare s text;
begin
  foreach s in array array[
    'claim_animal_stage(integer,text,text,text,text,bigint)',
    'claim_animal_stage(integer,text,text,text,text,bigint,uuid)',
    'eso_change(integer,text,text,bigint)',
    'eso_change(integer,text,text,bigint,uuid)',
    'outer_open(integer,bigint,boolean,text)',
    'outer_open(integer,bigint,boolean,text,uuid)',
    'lung_drawing_set(integer,bigint,text)',
    'set_not_chalak_outer(integer,bigint,uuid)',
    'animal_push(jsonb,uuid)',
    'event_append(jsonb)',
    'push_settings(jsonb,text,text)',
    'manager_login(text)',
    'manager_session_check(text)',
    'device_heartbeat(text,text,jsonb)',
    'worker_login(text,text,text)',
    'device_pair(text,text,text,integer,boolean,text)',
    'device_unpair(text,text,text)',
    'device_manage(text,text,text,text)',
    'manufacturer_set_billing(text,boolean,numeric,text)',
    'support_force_reload(text)',
    'support_access_set(text,integer)',
    'support_diagnostics(text)',
    'security_summary(text)',
    'device_whoami()',
    'device_paired_list(text)',
    'archive_days(text,date,date)'] loop
    execute format('revoke execute on function %s from public', s);
    execute format('grant execute on function %s to anon, authenticated', s);
  end loop;
end $$;

insert into plant_state (key, value) values ('schemaStep', '43')
  on conflict (key) do update set value = excluded.value, updated_at = now();

-- ============================================================================
-- SELF-CHECK — structure, rights, and behaviour (the API rules, run from SQL
-- with gt.as_api inside a block that is rolled back). Full API-level test:
-- tools/security-selftest.sql.
-- ============================================================================
do $$
declare
  problems text[] := '{}';
  t text; r jsonb; r2 jsonb; a animals_pilot%rowtype; v_ep bigint; n int;
  sfx text := substr(md5(random()::text), 1, 8);
  devO text := 'gtst43O_' || sfx; devO2 text := 'gtst43Q_' || sfx; devI text := 'gtst43I_' || sfx;
  devS text := 'gtst43S_' || sfx; devX text := 'gtst43X_' || sfx;
  kO text := encode(gen_random_bytes(16), 'hex'); kO2 text := encode(gen_random_bytes(16), 'hex');
  kI text := encode(gen_random_bytes(16), 'hex'); kS text := encode(gen_random_bytes(16), 'hex');
  kX text := encode(gen_random_bytes(16), 'hex');
  mid uuid; mtok text; v_cmd uuid := gen_random_uuid();
begin
  -- structure
  foreach t in array array['processed_commands','device_stage_cursor','rate_events','admin_audit'] loop
    if to_regclass('public.' || t) is null then problems := array_append(problems, 'missing table ' || t); end if;
  end loop;
  if not exists (select 1 from pg_indexes where indexname = 'devices_pilot_one_per_slot') then
    problems := array_append(problems, 'slot unique index missing'); end if;
  foreach t in array array['zzz_nc_outer_guard','zzzz_nc_outer_value','a_animals_merge','trg_animals_pilot_guard_corrections',
                           'trg_animals_pilot_advance_cursor','zz_device_write_guard'] loop
    if not exists (select 1 from pg_trigger where tgrelid = 'public.animals_pilot'::regclass and tgname = t and tgenabled <> 'D') then
      problems := array_append(problems, 'animals_pilot trigger missing: ' || t); end if;
  end loop;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.device_credentials'::regclass and tgname = 'zz_credential_audit') then
    problems := array_append(problems, 'key revoke audit trigger missing'); end if;
  if position('exception when others' in lower(pg_get_functiondef('_log_device_event(text,text,text,integer,text,text)'::regprocedure))) > 0 then
    problems := array_append(problems, 'device audit still swallows errors'); end if;
  if position('nco' in pg_get_functiondef('archive_days(text,date,date)'::regprocedure)) = 0 then
    problems := array_append(problems, 'archive_days: no nci/nco'); end if;
  if coalesce((select value from plant_state where key = 'testMode'), '') not in ('on', 'off') then
    problems := array_append(problems, 'testMode key missing'); end if;
  -- rights
  foreach t in array array['anon','authenticated'] loop
    if has_table_privilege(t, 'public.animals_pilot', 'INSERT') or has_table_privilege(t, 'public.animals_pilot', 'UPDATE') then
      problems := array_append(problems, t || ' can write animals_pilot directly'); end if;
    if has_table_privilege(t, 'public.events_pilot', 'INSERT') then
      problems := array_append(problems, t || ' can insert into events_pilot directly'); end if;
    if not has_function_privilege(t, 'animal_push(jsonb,uuid)', 'execute') or not has_function_privilege(t, 'event_append(jsonb)', 'execute')
       or not has_function_privilege(t, 'set_not_chalak_outer(integer,bigint,uuid)', 'execute') then
      problems := array_append(problems, t || ' cannot call the new write functions'); end if;
    if has_function_privilege(t, '_acting_device()', 'execute') or has_function_privilege(t, '_cmd_get(uuid,text,text)', 'execute') then
      problems := array_append(problems, t || ' can call internal step-43 helpers'); end if;
  end loop;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('animals_pilot','events_pilot') and pg_policies.cmd <> 'SELECT') then
    problems := array_append(problems, 'a write policy is left on animals_pilot / events_pilot'); end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'devices_pilot'
                  and policyname = 'read devices_pilot' and qual like '%devices_read_own_ids%') then
    problems := array_append(problems, 'devices_pilot read not narrowed'); end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'events_pilot'
                  and policyname = 'read events_pilot' and qual like '%events_reader_ok%') then
    problems := array_append(problems, 'events_pilot read not narrowed'); end if;
  foreach t in array array['animals','audit_log','batches','profiles','source_farms'] loop
    if to_regclass('public.' || t) is not null and (has_table_privilege('anon', 'public.' || t, 'SELECT')
       or has_table_privilege('anon', 'public.' || t, 'INSERT')) then
      problems := array_append(problems, 'legacy table open: ' || t); end if;
  end loop;

  -- behaviour (API rules from SQL; rolled back)
  begin
    v_ep := _board_epoch();
    perform set_config('app.device_admin', 'on', true);
    insert into devices_pilot (id, device_name, assigned_role, assigned_index, device_status, paired_at) values
      (devO, 'st43 outer', 'outer', 97, 'active', now()), (devO2, 'st43 outer 2', 'outer', 98, 'active', now()),
      (devI, 'st43 inner', 'inner', 97, 'active', now()), (devS, 'st43 slaughter', 'slaughter', 97, 'active', now()),
      (devX, 'st43 unpaired', null, null, 'active', null);
    insert into device_credentials (device_id, token_hash) values
      (devO, encode(digest(kO, 'sha256'), 'hex')), (devO2, encode(digest(kO2, 'sha256'), 'hex')), (devI, encode(digest(kI, 'sha256'), 'hex')),
      (devS, encode(digest(kS, 'sha256'), 'hex')), (devX, encode(digest(kX, 'sha256'), 'hex'));
    perform set_config('app.device_admin', '', true);
    insert into plant_managers (name, code_hash, role) values ('st43 leader', crypt(encode(gen_random_bytes(12), 'hex'), gen_salt('bf')), 'manager')
      returning id into mid;
    insert into manager_sessions (manager_id) values (mid) returning token into mtok;
    update plant_state set value = 'off' where key = 'testMode';
    perform set_config('gt.reset_in_progress', 'true', true);
    update animals_pilot set slaughter = 'slaughtered', slaughter_time = 1, inner_status = 'confirmed', inner_time = 1,
           outer_status = null, outer_time = null, outer_by_device = null, not_chalak_inner = false, not_chalak_outer = false,
           parts_print_count = 0, stamped = false, legs_sorted = false, parts_scanned = false, tongue_sticker = false, cheek_sticker = false,
           board_epoch = v_ep
     where id between 980 and 989;
    update animals_pilot set slaughter = null, slaughter_time = null, inner_status = null, inner_time = null where id = 989;
    perform set_config('gt.reset_in_progress', 'false', true);

    perform set_config('gt.as_api', 'on', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);

    -- 1. the team leader never rules (test mode off); test mode on: he may
    perform set_config('request.headers', json_build_object('x-manager-token', mtok)::text, true);
    r := claim_animal_stage(989, 'slaughter', 'slaughtered', 'x', 'fake', v_ep);
    if coalesce(r ->> 'error', '') <> 'wrong_station' then problems := array_append(problems, 'team leader ruled with test mode off: ' || r::text); end if;
    r := animal_push(jsonb_build_object('id', 989, 'board_epoch', v_ep, 'slaughter', 'shot', 'slaughter_time', 5));
    if coalesce(r ->> 'error', '') <> 'wrong_station' then problems := array_append(problems, 'team leader pushed a ruling: ' || r::text); end if;
    update plant_state set value = 'on' where key = 'testMode';
    r := claim_animal_stage(989, 'slaughter', 'slaughtered', 'x', 'fake', v_ep);
    if not coalesce((r ->> 'claimed')::boolean, false) or (r -> 'row' ->> 'slaughter_by_device') not like 'mgr-%' then
      problems := array_append(problems, 'test mode: team leader cannot act as a station: ' || r::text); end if;
    update plant_state set value = 'off' where key = 'testMode';

    -- 2. rabbinate screen: only an 'outer' station; then only kosher / treif
    perform set_config('request.headers', json_build_object('x-device-token', kI)::text, true);
    r := set_not_chalak_outer(980, v_ep);
    if coalesce(r ->> 'error', '') <> 'wrong_station' then problems := array_append(problems, 'inner station sent to rabbinate: ' || r::text); end if;
    r := animal_push(jsonb_build_object('id', 980, 'board_epoch', v_ep, 'not_chalak_outer', true));
    if (select not_chalak_outer from animals_pilot where id = 980) then problems := array_append(problems, 'not_chalak_outer set by a push'); end if;
    perform set_config('request.headers', json_build_object('x-device-token', kO)::text, true);
    r := set_not_chalak_outer(980, v_ep);
    if not coalesce((r ->> 'ok')::boolean, false) then problems := array_append(problems, 'outer station cannot send to rabbinate: ' || r::text); end if;
    r := claim_animal_stage(980, 'outer', 'glatt', 'x', 'x', v_ep);
    if coalesce(r ->> 'error', '') <> 'bad_value' then problems := array_append(problems, 'NC animal ruled glatt: ' || r::text); end if;
    r := claim_animal_stage(980, 'outer', 'kosher', 'x', 'x', v_ep);
    if not coalesce((r ->> 'claimed')::boolean, false) then problems := array_append(problems, 'NC animal cannot be ruled kosher: ' || r::text); end if;
    r := set_not_chalak_outer(980, v_ep);
    if (r ->> 'ok')::boolean and not coalesce((r ->> 'already')::boolean, false) then problems := array_append(problems, 'rabbinate after ruling'); end if;
    r := animal_push(jsonb_build_object('id', 980, 'board_epoch', v_ep, 'outer_status', 'glatt', 'outer_time', 99999999999999));
    if coalesce(r ->> 'error', '') <> 'invalid_value' then problems := array_append(problems, 'NC animal corrected to glatt: ' || r::text); end if;

    -- 3. moved on by TIME: rules 983 then (late) 982 → 982 correctable, 983 not
    r := claim_animal_stage(983, 'outer', 'glatt', 'x', 'x', v_ep);
    r := claim_animal_stage(982, 'outer', 'glatt', 'x', 'x', v_ep);
    r := animal_push(jsonb_build_object('id', 982, 'board_epoch', v_ep, 'outer_status', 'beit', 'outer_time', (r -> 'row' ->> 'outer_time')::bigint + 5));
    if not coalesce((r ->> 'ok')::boolean, false) or (select outer_status from animals_pilot where id = 982) <> 'beit' then
      problems := array_append(problems, 'late animal cannot be corrected right away: ' || r::text); end if;
    r := animal_push(jsonb_build_object('id', 983, 'board_epoch', v_ep, 'outer_status', 'beit', 'outer_time', 99999999999999));
    if coalesce(r ->> 'error', '') <> 'moved_on' then problems := array_append(problems, 'higher animal correctable after moving on: ' || r::text); end if;
    perform set_config('request.headers', json_build_object('x-device-token', kO2)::text, true);
    r := animal_push(jsonb_build_object('id', 982, 'board_epoch', v_ep, 'outer_status', 'treif', 'outer_time', 99999999999999));
    if coalesce(r ->> 'error', '') <> 'correction_not_allowed' then problems := array_append(problems, 'other device corrected: ' || r::text); end if;

    -- 4. retries: same value by the same device; command ids
    perform set_config('request.headers', json_build_object('x-device-token', kO)::text, true);
    r := claim_animal_stage(984, 'outer', 'glatt', 'x', 'x', v_ep, v_cmd);
    r2 := claim_animal_stage(984, 'outer', 'glatt', 'x', 'x', v_ep);
    if not coalesce((r2 ->> 'claimed')::boolean, false) or not coalesce((r2 ->> 'duplicate')::boolean, false) then
      problems := array_append(problems, 'same-value retry is a conflict: ' || r2::text); end if;
    r2 := claim_animal_stage(984, 'outer', 'glatt', 'x', 'x', v_ep, v_cmd);
    if not coalesce((r2 ->> 'replayed')::boolean, false) then problems := array_append(problems, 'command id not replayed: ' || r2::text); end if;
    perform set_config('request.headers', json_build_object('x-device-token', kO2)::text, true);
    r2 := claim_animal_stage(984, 'outer', 'glatt', 'x', 'x', v_ep, v_cmd);
    if coalesce(r2 ->> 'error', '') <> 'command_id_conflict' then problems := array_append(problems, 'command id of another device accepted'); end if;
    r2 := claim_animal_stage(984, 'outer', 'treif', 'x', 'x', v_ep);
    if coalesce((r2 ->> 'claimed')::boolean, true) then problems := array_append(problems, 'conflicting claim won'); end if;

    -- 5. identity: no key → refused; unpaired key → refused
    perform set_config('request.headers', json_build_object('x-device-id', devO)::text, true);
    r := claim_animal_stage(985, 'outer', 'glatt', 'x', devO, v_ep);
    if coalesce(r ->> 'error', '') <> 'device_not_paired' then problems := array_append(problems, 'claim without a key: ' || r::text); end if;
    r := event_append(jsonb_build_object('event_id', gen_random_uuid(), 'stage', 'outer', 'action', 'glatt', 'occurred_at', now()::text));
    if coalesce(r ->> 'error', '') <> 'device_not_paired' then problems := array_append(problems, 'event without a key: ' || r::text); end if;
    perform set_config('request.headers', json_build_object('x-device-token', kO, 'x-device-id', devI)::text, true);
    r := event_append(jsonb_build_object('event_id', gen_random_uuid(), 'stage', 'outer', 'action', 'glatt', 'animal_no', 985,
                                         'device_id', devI, 'actor', 'Somebody', 'occurred_at', now()::text, 'payload', '{}'::jsonb));
    if not coalesce((r ->> 'ok')::boolean, false)
       or (select device_id from events_pilot where event_id = (r ->> 'event_id')::uuid) is distinct from devO then
      problems := array_append(problems, 'event device not the server''s: ' || r::text); end if;

    -- 6. settings shapes
    perform set_config('request.headers', json_build_object('x-manager-token', mtok)::text, true);
    r := push_settings('{"autoResetTime":"25:99"}'::jsonb, 'x', mtok);
    if coalesce(r ->> 'error', '') <> 'bad_settings' or r ->> 'key' <> 'autoResetTime' then problems := array_append(problems, 'bad time accepted: ' || r::text); end if;
    r := push_settings('{"autoResetTime":"05:30","activeLangs":["he","en"],"beepSeconds":25}'::jsonb, 'x', mtok);
    if not coalesce((r ->> 'ok')::boolean, false) then problems := array_append(problems, 'good settings refused: ' || r::text); end if;

    -- 7. the device audit can't be skipped: if it fails, the unpair fails
    perform set_config('gt.as_api', '', true);
    execute 'create function pg_temp.gt_st43_fail() returns trigger language plpgsql as $f$ begin raise exception ''audit down''; end $f$';
    execute 'create trigger gt_st43_fail before insert on device_lifecycle_events for each row execute function pg_temp.gt_st43_fail()';
    begin
      r := device_unpair(mtok, devS, 'st43');
      problems := array_append(problems, 'unpair succeeded without its audit row');
    exception when others then null;
    end;
    execute 'drop trigger gt_st43_fail on device_lifecycle_events';
    if (select assigned_role from devices_pilot where id = devS) is distinct from 'slaughter' then
      problems := array_append(problems, 'unpair without audit changed the device'); end if;

    raise exception 'gt_selftest43_rollback';
  exception when others then
    if sqlerrm <> 'gt_selftest43_rollback' then problems := array_append(problems, 'self-test error: ' || sqlerrm); end if;
  end;
  perform set_config('gt.as_api', '', true);
  perform set_config('request.headers', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('app.device_admin', '', true);
  perform set_config('gt.reset_in_progress', 'false', true);

  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 43 self-check FAILED: %', array_to_string(problems, ' | ');
  end if;
  raise notice 'GlattTrack step 43 self-check OK';
end $$;

notify pgrst, 'reload schema';

-- ============================ step 44 ============================
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

-- ============================ step 45 ============================
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


-- ═══════════════════════════ step 46 ═══════════════════════════
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
-- Safe to run more than once. Run after step 45.
-- ============================================================================

-- ── helpers: settings, kosher statuses, the esophagus rule ──────────────────
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
create or replace function _kosher_ready(a animals_pilot) returns boolean
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(a.outer_status is not null
                  and (not _is_nc(a) or a.outer_status = 'kosher')
                  and a.outer_status = any(_kosher_statuses())
                  and coalesce(a.slaughter, '') not in ('nevela', 'shot')
                  and a.inner_status = 'confirmed', false);
$$;
revoke execute on function _kosher_ready(animals_pilot) from public, anon, authenticated;

-- what a parts sticker / stamp must say for this ruling (the app's _printedAsKey)
create or replace function _printed_as_key(a animals_pilot) returns text
language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when a.outer_status is null then null
              when a.outer_status = 'kosher' and _is_nc(a) then 'kosherRab'
              else a.outer_status end;
$$;
revoke execute on function _printed_as_key(animals_pilot) from public, anon, authenticated;

-- ── 1. stage order ───────────────────────────────────────────────────────────
-- Why a stage may NOT act on this animal yet (null = it may). p_stage:
-- 'eso', 'inner', 'outer', 'legs_stickers', 'legs', 'parts', 'stamped', 'weights'.
-- p_today: the row is on today's board (the esophagus rule of today applies).
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
revoke execute on function _do_board_reset(text, date) from public, anon, authenticated;

-- ── 5. daily rollover: never in the middle of work ──────────────────────────
-- slaughtered animals that have not reached their last ruling (lungs treif, or outer)
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

-- ── system_health: processing boards waiting, rollover waiting, label mismatches ──
create or replace function system_health(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
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
revoke execute on function system_health(text) from public;
grant execute on function system_health(text) to anon, authenticated;

insert into plant_state (key, value) values ('schemaStep', '46')
  on conflict (key) do update
    set value = case when plant_state.value ~ '^\d+$' and plant_state.value::int > 46 then plant_state.value else '46' end,
        updated_at = now();

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
  if (select value from plant_state where key = 'schemaStep')::int < 46 then
    problems := problems || 'schemaStep not 46'::text; end if;
  if array_length(problems, 1) > 0 then
    raise exception 'GlattTrack step 46 self-check FAILED: %', array_to_string(problems, ' | ');
  end if;
  raise notice 'GlattTrack step 46 self-check OK';
end $$;

notify pgrst, 'reload schema';
