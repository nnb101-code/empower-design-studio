# GlattTrack — security manifest (who may do what)

Generated 2026-09-28 from a database at **schema step 45**: the guard helpers each API function calls were read from the ACTIVE definitions (`pg_get_functiondef`), and every cell below was **observed** by calling that function (or reading that table) as that role through the API path (`authenticator` → `anon` + request headers), each call rolled back. The automated checks of the same rules: `tools/security-selftest.sql`; the raw active surface: `tools/active-security-manifest.sql`.

## Roles — how the server recognises each one

| Role | Identified by | Notes |
|---|---|---|
| Anonymous / unpaired | nothing valid in the request | may only ask for a pairing code, read server time / step / test flag, and ask for the daily rollover |
| Station (paired tablet) | `x-device-token` header → `device_credentials` (not revoked) → `devices_pilot.assigned_role` (`_current_device_id`, `_caller_device_role`) | one role per tablet: slaughter, esophagus, inner, outer, legs, parts, stamps, display |
| Retired / revoked tablet | a revoked key (unknown to `_current_device_id`) or `device_status = retired` | every write refused; write attempts are counted (`revoked_device_writes`, step 45) |
| Team leader (TL) | `manager_sessions` token, role `manager`, bound to the device + app session it was made on (`_session_role` → `_mgr_session_bound`), 10 h | manages; **never rules** |
| TL in test mode | as TL, while `plant_state.testMode = on` (SQL only) and switched on < 8 h ago (`_test_mode_on`) | acts as any station (own rulings only); auto-off after 8 h |
| Owner | session role `owner` | view only |
| Manufacturer (Mfr) | session role `manufacturer` | view only; with support access open (`_support_access_open`, opened by the TL with a reason) also repairs settings/devices; never kashrut |
| Server (SQL editor, plant jobs, service key) | not an API request, or the service role (`_request_privileged`) | everything; test mode is switched here only |

## Guard helpers (active definitions)

| Helper | Passes for |
|---|---|
| `_stage_allowed(stage)` | a station whose role may rule that stage (slaughter→slaughter; eso→esophagus, slaughter; inner/outer→inner, outer; legs→legs; stamped→stamps, parts; parts→parts; weights→stamps); TL only in test mode; server |
| `_nc_outer_allowed()` | an active `outer` station (sending to the rabbinate screen); TL only in test mode; server |
| `_device_write_allowed()` | a paired, non-retired, non-display station; any TL session; server |
| `_call_device / _acting_device` | the identity used for a ruling: the device key; in test mode a TL gets a pseudo device `mgr-…`; the client's p_device_id is ignored |
| `_is_real_manager(token)` | TL session only |
| `_manager_session_valid(token)` | TL session, or manufacturer with support access open |
| `_manufacturer_session_valid(token)` | manufacturer session |
| `_session_role(token) in (…)` | the listed session roles (bound session, not expired, active account) |
| `_reader_ok()` | any paired station, any session (TL/owner/Mfr), server; live updates: an app session that belongs to one of those |
| `gt_rls.events_reader_ok()` | TL, owner, manufacturer with access open, server |
| `gt_rls.devices_read_all() / devices_read_own_ids()` | TL/owner/Mfr see all devices; a station sees only its own row |
| `_test_mode_on()` | flag on AND switched on < 8 h ago; an expired flag is set back off (+ admin_audit) by the first read-write request |
| `_reason_ok(p_reason)` | a non-blank reason (step 45 exceptional actions → `reason_required`) |

## API functions × roles (observed)

✓ allowed · ✗ refused · ✓ᴿ allowed with a reason (refused `reason_required` without) · ∅ nothing to see. Columns: Anon = anonymous/unpaired; SL ESO IN OUT LEGS PARTS STMP DISP = paired stations; TL = team leader; Mfr = manufacturer (support access closed / open).

| Action | Anon | SL | ESO | IN | OUT | LEGS | PARTS | STMP | DISP | Retired | TL | TL+test | Owner | Mfr | Mfr+access | Refused with | Enforced by (active definition) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `claim_animal_stage slaughter` | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_stage_allowed`, `_call_device` |
| `claim_animal_stage eso` | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_stage_allowed`, `_call_device` |
| `claim_animal_stage inner_start` | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_stage_allowed`, `_call_device` |
| `claim_animal_stage outer` | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_stage_allowed`, `_call_device` |
| `animal_push (legs stickers)` | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, column not applied, wrong_station | `_request_has_manager`, `_call_device`, `_caller_device_role`, `_test_mode_on` |
| `eso_change` | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_stage_allowed`, `_call_device`, `_correction_check` |
| `outer_open` | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_stage_allowed`, `_call_device` |
| `set_not_chalak_outer` | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_nc_outer_allowed`, `_call_device` |
| `lung_drawing_set` | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_stage_allowed`, `_call_device` |
| `lung_drawing_get` | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | not_allowed | `_reader_ok` |
| `event_append` | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | device_not_paired, manufacturer_no_access | `_request_has_manufacturer`, `_device_write_allowed` |
| `push_settings (station keys)` | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ᴿ | device_not_paired | `_manager_session_valid`, `_session_role`, `_request_has_manager`, `_device_write_allowed`, `_current_device_id`, `_reason_ok` · roles manufacturer |
| `push_settings (admin key)` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | device_not_paired, key ignored | `_manager_session_valid`, `_session_role`, `_request_has_manager`, `_device_write_allowed`, `_current_device_id`, `_reason_ok` · roles manufacturer |
| `worker_login` | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | device_not_paired, wrong_station | `_request_has_manager`, `_current_device_id`, `_test_mode_on`, `_worker_role_norm` |
| `reset_daily_board` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | unauthorized | `_manager_session_valid`, `_session_role` · roles manufacturer |
| `request_daily_rollover` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — |  |
| `device_pair` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | unauthorized | `_is_real_manager`, `_reason_ok` |
| `device_manage retire` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | unauthorized | `_manager_session_valid`, `_session_role`, `_reason_ok` · roles manufacturer |
| `device_unpair` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | unauthorized | `_manager_session_valid`, `_session_role`, `_reason_ok` · roles manufacturer |
| `device_paired_list` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | unauthorized | `_manager_session_valid` |
| `device_auth_set` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | unauthorized | `_is_real_manager` |
| `manager_add` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | unauthorized | `_is_real_manager` |
| `manager_add_owner` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | unauthorized | `_is_real_manager` |
| `manager_list` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | unauthorized | `_manager_session_valid` |
| `support_access_set (open)` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | unauthorized | `_session_role`, `_reason_ok` |
| `support_diagnostics` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | unauthorized | `_manager_session_valid`, `_session_role`, `_test_mode_on` |
| `support_force_reload` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✓ | unauthorized | `_manager_session_valid`, `_reason_ok` |
| `manufacturer_set_billing` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | unauthorized | `_manufacturer_session_valid`, `_reason_ok` |
| `security_summary` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | unauthorized | `_session_role`, `_test_mode_on` · roles manager/manufacturer/owner |
| `system_health` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | unauthorized | `_session_role`, `_test_mode_on` |
| `archive_days` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | unauthorized | `_session_role` |
| `plant_status_snapshot` | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | unauthorized | `_session_role`, `_current_device_id` |
| `verify_event_chain` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | unauthorized | `_session_role` |
| `server_test_mode / _info` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | `_test_mode_active` |
| `device_whoami` | ∅ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ∅ | ∅ | ∅ | ∅ | ∅ | — | `_current_device_id` |

Notes: a ✓ for a ruling means the server accepted the call from that role (value, board day, "moved on" and correction rules still apply — see security-selftest.sql). `animal_push` checks each column against `_stage_allowed` too: the legs-sticker column is applied only for the legs station (others: the call succeeds, the column is not applied). push_settings: stations may change only their own keys (problem reports, reprint log, printers …); other keys are ignored. `request_daily_rollover` is open to all but runs at most once per plant day and only after the reset time. `archive_days`, `system_health`: TL + owner. `security_summary`, `verify_event_chain`: any session.

## Tables × roles (observed reads; no role may write any table directly)

| Table | Anon | SL | ESO | IN | OUT | LEGS | PARTS | STMP | DISP | Retired | TL | TL+test | Owner | Mfr | Mfr+access | Policy (active) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `read animals_pilot` | ∅ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | `( SELECT _reader_ok() AS _reader_ok)` |
| `read settings_pilot` | ∅ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | `( SELECT _reader_ok() AS _reader_ok)` |
| `read daily_board_archive` | ∅ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | `( SELECT _reader_ok() AS _reader_ok)` |
| `read events_pilot` | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ✓ | ✓ | ✓ | ∅ | ✓ | `( SELECT gt_rls.events_reader_ok() AS events_reader_ok)` |
| `read device_lifecycle_events` | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ∅ | ✓ | ✓ | ✓ | ∅ | ✓ | `( SELECT gt_rls.events_reader_ok() AS events_reader_ok)` |
| `read devices_pilot` | ∅ | ◐ own | ◐ own | ◐ own | ◐ own | ◐ own | ◐ own | ◐ own | ◐ own | ◐ own | ✓ | ✓ | ✓ | ✓ | ✓ | `(( SELECT gt_rls.devices_read_all() AS devices_read_all) OR (id = ANY (( SELECT gt_rls.devices_read_own_ids() AS devices_read_own_ids)::text[])))` |
| `write animals_pilot directly` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | `no INSERT/UPDATE/DELETE grant` |
| `read plant_state / sessions` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | `no grant to anon/authenticated` |

The "Retired" column is a retired tablet whose key was not revoked (the worst case); retiring through the app also revokes the key, after which the tablet is treated exactly like "Anon".

◐ own = only the tablet's own row. Every other table (plant_state, manager_sessions, device_credentials, rate_events, admin_audit, revoked_device_writes, legacy multi-plant tables …) has **no grant** to the app roles. Direct INSERT/UPDATE/DELETE on `animals_pilot`, `events_pilot`, `devices_pilot`, `settings_pilot` are revoked; the guard triggers `_device_write_guard`, `animals_pilot_guard_corrections`, `_animals_outer_open_guard`, `_animals_nc_outer_guard`, `_events_append_only`, `_events_maker_guard`, `_devices_assignment_guard` are the second layer behind the RPCs.

## Other API functions (self-scoped or public by design)

| Function | Who | Enforced by (active definition) | Errors |
|---|---|---|---|
| `_reader_ok()` | row-security helper (see above) | `_session_role`, `_current_device_id`, `_reader_ok` | — |
| `claim_animal_stage(integer,text,text,text,text,bigint)` | wrapper → the 7-argument version | — | — |
| `create_first_manager(text,text,text)` | anyone, only while no team leader exists, with the one-time setup code | — | code_in_use, locked, setup_code_required, setup_code_wrong |
| `device_heartbeat(text,text,jsonb)` | a tablet about itself only (`not_this_device`); binds a TL session to its app session once | `_current_device_id` | device_auth_required, not_this_device |
| `device_pairing_status(text,text,text)` | the tablet that asked (device id + its secret) | — | — |
| `device_request_pairing(text,text,text)` | anyone (an unpaired tablet asks for a code); 20 per address / 10 min, 100 pending max | — | too_many_pending, too_many_requests |
| `eso_change(integer,text,text,bigint)` | wrapper → the 5-argument version | — | — |
| `gt_rls.devices_read_all()` | row-security helper | `_session_role` · roles manager/manufacturer/owner | — |
| `gt_rls.devices_read_own_ids()` | row-security helper | `_current_device_id` | — |
| `gt_rls.events_reader_ok()` | row-security helper | `_session_role`, `_support_access_open` | — |
| `manager_deactivate(text,uuid)` | TL | `_is_real_manager` | last_manager, not_found, unauthorized |
| `manager_login(text)` | anyone with a valid code; 8 wrong codes / 15 min brake; manufacturer 6 / hour, audited | `_current_device_id`, `_support_access_open` | — |
| `manager_logout(text)` | the session holder | — | — |
| `manager_session_check(text)` | the session holder (bound session) | `_mgr_session_bound` | — |
| `outer_open(integer,bigint,boolean,text)` | wrapper → the 5-argument version | — | — |
| `server_now_ms()` | anyone | — | — |
| `server_schema_step()` | anyone | — | — |
| `server_test_mode()` | anyone (read-only) | `_test_mode_active` | — |
| `server_test_mode_info()` | anyone (read-only) | `_test_mode_active` | — |
| `worker_logout(text)` | the worker session holder | — | — |
| `worker_session_check()` | the worker session on this tablet | — | session_invalid |

## Exceptional actions: a reason is required (step 45)

| Function | When | Stored in |
|---|---|---|
| `device_pair(…, p_reason)` | `p_replace = true` | device_lifecycle_events.reason (UNASSIGNED / KEY_REVOKED / ASSIGNED, one replacement_id) |
| `device_manage(…, p_reason)` | retire, reactivate (rename: p_reason is the new name) | device_lifecycle_events.reason, devices_pilot.retired_reason |
| `device_unpair(…, p_reason)` | always | device_lifecycle_events.reason |
| `support_access_set(…, p_reason)` | `p_hours > 0` | admin_audit.detail.reason, events_pilot payload |
| `manufacturer_set_billing(…, p_reason)`, `support_force_reload(…, p_reason)` | always | admin_audit.detail.reason |
| `push_settings(…, p_reason)` | a manufacturer session (support access open) | admin_audit.detail.reason |


## Step 46 additions (written by hand from the active definitions — the tables above are from step 45)

Changed rows:
- `claim_animal_stage inner_start / inner`: only an **inner** station (outer refused: wrong_station). `claim_animal_stage outer`, `outer_open`: only an **outer** station (inner refused). `lung_drawing_set`: inner only.
- every first ruling also needs the earlier stages (`_stage_order_error`, trigger `b_animals_stage_guard`) → `out_of_order` + reason.
- `set_not_chalak_outer`: outer station, and the inner check confirmed.
- `push_settings` by a manufacturer (support access open + reason): technical keys only (`printers, scanners, beep*, lang*, activeLangs, weightMethods, errorLog, problemReports, reprintLog, licenseRequestDismissed`); all other keys ignored. Team leader: `status_in_use` when a custom status carried by an animal on an open board would change its kosher mark or disappear.
- `reset_daily_board(p_token, p_reason default null)` (was `(text)`): team leader; while slaughtered animals lack their last ruling → `unfinished_animals` (+ numbers) unless a reason is given; recorded in admin_audit (reason, numbers); sets lastRolloverDate.
- `worker_login`: hashed worker codes only (no plain-text `code`).
- `carry_push`, `carry_claim`, `processing_day_close`, `_proc_finalize`: one transaction at a time per kept board (`_proc_board_lock`, advisory).
- `system_health`: adds `security.labelMismatch24h`, `security.outOfOrder24h`, `processing{openBoards, oldestDay, rolloverWaitingSince, unfinishedOnBoard}`; attention codes `label_mismatch`, `rollover_waiting`; info `processing_days_open`.
- `request_daily_rollover`: never while a ruling happened in the last 20 minutes (no 3-hour limit), never while a slaughtered animal lacks its last ruling (`waiting_unfinished`).

Step-46 helper functions (no grant to anon / authenticated): `_stage_order_error`, `_animals_stage_guard` (trigger `b_animals_stage_guard` BEFORE UPDATE on animals_pilot), `_eso_required`, `_kosher_statuses`, `_kosher_ready`, `_is_nc`, `_printed_as_key`, `_proc_stations`, `_proc_pending`, `_proc_board_pending`, `_proc_open_board`, `_proc_finalize`, `_proc_board_lock`, `_proc_station_of_group`, `_proc_caller_station`, `_proc_board_json`, `_carry_row`, `_statuses_in_use`, `_status_change_error`, `_board_business_date`, `_board_unfinished`, `_gt_settings`, `_gt_flag`.

New API functions:

| Function | Who | Enforced by | Errors |
|---|---|---|---|
| `processing_board(p_station)` | any reader (`_reader_ok`); a legs / parts / stamps station gets its own board | `_reader_ok`, `_proc_caller_station` | not_allowed, bad_station |
| `carry_push(p_board, p_rows, p_command_id)` | legs / parts / stamps stations (TL only in test mode); processing columns of the station only; the board must be the station's oldest unfinished one | `_stage_allowed`, `_stage_order_error`, `_proc_open_board`, `_cmd_get` | wrong_station, device_not_paired, earlier_day_open, board_closed, out_of_order, invalid_value |
| `carry_claim(p_board, p_id, p_stage legs/stamped, p_command_id)` | legs / stamps / parts stations | same | as above |
| `processing_day_close(p_token, p_board, p_station, p_reason)` | team leader only, reason required, oldest board first; admin_audit | `_is_real_manager`, `_reason_ok`, `_proc_board_lock` | unauthorized, reason_required, earlier_day_open, board_closed |
| `processing_status(p_token)` | team leader / owner | `_session_role` | unauthorized |

New tables (no grant to anon / authenticated): `animals_carry` (kept slaughter days, PK board_id + id, board_id = daily_board_archive.id), `processing_day_closed`.
