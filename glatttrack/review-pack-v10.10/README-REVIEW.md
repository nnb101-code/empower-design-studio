# GlattTrack — review pack (app v10.10, server schema step 46)

This pack is the CURRENT state. Review these files only.

## Files

| File | What it is |
|---|---|
| `active-schema-snapshot.sql` | **Audit this first.** `pg_dump --schema-only` (public + gt_rls) of a clean database built from `glatttrack-schema-full.sql`. Exactly one ACTIVE definition of each function, trigger, RLS policy and grant. |
| `setup-supabase-step46-order-and-processing-days.sql` | The new migration (run after step 45). |
| `STEP46-CHANGES.md` | What step 46 / app v10.6 changed (Hebrew). |
| `security-selftest.sql` + `security-selftest-result.txt` | Release gate, rolled-back transaction: **115 / 115** (90 earlier checks, adapted where step 46 changed the rules, + 25 step-46 checks). |
| `SECURITY-MANIFEST.md` | Permission map (step 45 observed table) + a step-46 section. |
| `active-security-manifest.sql` + `-result.txt` | Prints the active security surface. |
| `kosher-app-v10.10.html` | The app (UI, offline store, sync client). `GT_MIN_SCHEMA = 46`. |
| `setup-supabase-step44/45/46-*.sql` | The last three migrations. |
| `glatttrack-schema-full.sql` | Full install script (base + steps 1–46, history included; last definition wins). |
| `test-mode-on.sql` / `test-mode-off.sql` | The owner's SQL-only test switch. |

## Changed in v10.10 (same step 46): the team leader only from a paired team-leader device

Owner's decision: the team leader must work from a paired device.

- New pairing role `'leader'` (`devices_pilot.assigned_role`, constraint `devices_pilot_role_ok`, `_gt_value_ok('device_role')`), slots 0..3 in `device_pair`. A team-leader device is NOT a station: `_stage_allowed` gives it no stage, and `_device_write_allowed` excludes it (like `'display'`) — it writes only through a team-leader session.
- `manager_login`: a code of role `manager`, through the API (not the service key), once the plant has at least one team-leader device (`_leader_devices_exist()`: active, role leader, a non-revoked credential), is accepted only when the calling device is one (`_is_leader_device(_current_device_id())`). Otherwise: `{ok:false, reason:'leader_device_required'}`, counted as a failed attempt (same brake as wrong codes), security event `leader_device_required`. Owner (`role='owner'`) and manufacturer logins are unchanged (open question to the owner).
- Bootstrap: while the plant has no team-leader device, any device may log in as team leader, and the result says `registerLeaderDevice: true`. The app then pairs THAT device as `'leader'` slot 0 (`device_request_pairing` → `device_pair(token, code, 'leader', 0)` → `device_pairing_status`). `device_pair` with `p_role='leader'` moves the calling session (bound to no device, i.e. made before any team-leader device existed) onto the new device. The first team leader can only be created with the one-time setup code (`create_first_manager`), so the first team-leader device is the device used at installation.
- More team-leader devices: an existing team leader pairs them from Settings → Screens → "Team-leader devices" (`device_pair(..., 'leader', idx)`). Unpairing one revokes its key and ends the sessions made on it (existing step-43 behaviour, now tested for leader devices).
- App: `leader_device_required` → a clear message; a device paired as `'leader'` stores no station (`ks_kiosk_role` stays empty) and opens the team-leader login / screen.
- Tests: 4 new self-test checks (bootstrap + session move, refusal from unpaired / station devices with counting + event, no ruling / station writes / worker login on a leader device, second device + unpair ends sessions). Browser-tested end to end.
- Note on the earlier B4 ("manager session from an unpaired device", answered "by design" in v10.9): superseded by this change.

## Fixed after the v10.8 review (same step 46, app v10.9)

- A1 (reset vs. a write to today's board): every function that writes animals_pilot (`animal_push`, `claim_animal_stage`, `eso_change`, `set_not_chalak_outer`, `outer_open`, `lung_drawing_set`) first takes `_board_write_lock()` = `pg_advisory_xact_lock_shared(hashtext('glatttrack_daily_rollover'))`; `request_daily_rollover` / `reset_daily_board` take the same key exclusively (as before). Taken at the start of the RPC, before any row is locked (a lock inside the trigger would deadlock with the reset's UPDATE of the same row). The board epoch is read after the lock. Writers don't wait for each other. Tested with two real concurrent connections in both orders: write-then-reset → the reset waits, the write is in the archive and the kept day; reset-then-write → the write waits and gets `stale_board`.
- A2: `create_first_manager` through the API needs the setup code: none configured → `setup_code_not_configured` (fail closed). From the server (SQL, not an API request) it still works. Installation: `select _set_setup_code('…8+ chars…');` once, before tablets connect.
- B1: new team-leader / owner codes ≥ 6 characters (`create_first_manager`, `manager_add`, `manager_add_owner`; app prompts too). Existing codes keep working.
- B3: `customStatuses` with two entries of the same key → `bad_settings` (`_settings_value_error`).
- B5 (app): `carry_push` answering `board_closed` / `earlier_day_open` → the unsent rows are written to the event log (`unsent_processing`, with board + slaughter day + the row), not dropped. Browser-tested.
- B6 (app): offline work of an ended day is kept 14 days (was 3), then written to the event log, never dropped silently.
- B4 (manager session from an unpaired device): by design — a paired device is a STATION device (ruling rights); the team leader never rules, so his phone / office PC is deliberately not a station. His session is bound to the browser (app session) it was made in, 10 h.
- Device reactivated after retirement: the app now says it must be paired again (its key was revoked when retired).

## Fixed after the v10.7 review (same step 46, app v10.8)

- A (time-only correction): `animals_pilot_guard_corrections` — a write that changes only `slaughter_time`, a final `inner_time` or `outer_time` (the ruling, its worker and its device unchanged) keeps the recorded time. Such a write used to move the device's `device_stage_cursor` back (trigger `animals_pilot_advance_cursor`) and so reopened a correction the "moved on" rule had closed. Two new self-tests; with the v10.7 guard they fail (the bypass worked), with the fix they pass.
- B3: SECURITY-MANIFEST.md header now says what it is (step-45 observed base + step-46 section from the active definitions).
- B4: each archived day keeps the status definitions it was ruled with (`daily_board_archive.statuses`, returned by `archive_days`).

## Fixed after the v10.6 review (same step 46, app v10.7)

- A1: `reset_daily_board` (the team leader's manual reset — an emergency tool, the app has no button for it) stops while slaughtered animals lack their last ruling: `{ok:false, error:'unfinished_animals', unfinished, numbers}`; it goes on only with a written `p_reason`, recorded in admin_audit with the numbers.
- A2: one transaction at a time on a kept processing board — `_proc_board_lock(p_board)` (advisory, per board) in `carry_push`, `carry_claim`, `processing_day_close` and `_proc_finalize`. Tested with two real concurrent connections in both orders.
- A3: by design — legs / head stickers are identification stickers put on every animal right after slaughter (also nevela / shot); legs SORTING is after the outer ruling (enforced). Rule 2 below says so now.
- B2: `worker_login` accepts hashed codes only.
- B3: SECURITY-MANIFEST.md step-46 section completed.
- B4: team-leader screen → Monitor: "Slaughter days in processing" (each open day, what is left per station, the station's current day in bold, a Close button with a required reason — `processing_status` / `processing_day_close`).

## What changed since v10.5 (server step 45 → 46, app v10.5 → v10.6)

1. **Stage order on the server** (every write path: `claim_animal_stage`, `animal_push`, the offline esophagus path, `set_not_chalak_outer`, `carry_push`, `carry_claim`; trigger `b_animals_stage_guard`, helper `_stage_order_error`): slaughter → esophagus (when the plant uses it, `_eso_required`) → inner → outer → legs sort / parts / stamps / weights. A number that has not reached a station cannot be ruled there (`out_of_order` + reason). A "nevela" from the esophagus after the inner check started is refused.
2. **Each station only its own stage**: `_stage_allowed('inner')` = inner station only, `('outer')` = outer station only.
3. **Kashrut configuration**: manufacturer = technical settings only; the team leader cannot change the kosher mark of / delete a custom status carried by an animal on an open board (`status_in_use`).
4. **Processing over several days, no skipping**: the daily reset keeps every slaughter day whose processing (legs / parts / stamps) is unfinished (`animals_carry`, one board per reset, linked to its archive row). Each processing station works strictly on its oldest unfinished board (`_proc_open_board`); writes to a newer board or today's board are refused (`earlier_day_open`). A board done for every station is written back into its archive row. App: the processing tablet switches its board by itself and always shows which slaughter day it works on; offline work of a day that ended is sent to that kept day.
5. **Daily rollover**: never during work (the 3-hour forced reset is gone) and never while a slaughtered animal has no last ruling (`waiting_unfinished`, health attention `rollover_waiting`). The manual reset is audited.
6. **Label mismatch**: a parts sticker / stamp that does not say the ruling is kept but recorded (`label_mismatch`, health attention).

Please check in particular:
- can any write path still rule a stage before the previous one (including INSERT … ON CONFLICT through `animal_push`, test mode, the offline esophagus path)?
- can a processing station skip an older slaughter day (live board, `carry_push`, `carry_claim`, two kept boards)?
- the trigger order on `animals_pilot` (`a_animals_merge` → `b_animals_stage_guard` → `trg_animals_pilot_guard_corrections` → `zzz_*`).
- `_do_board_reset` / `_proc_finalize`: is unfinished processing ever lost?
- the app's carry mode (`_carry`, `_carryRefresh`, `_carryPump`, `_carryKeepUnsent` in the KS module).

## Business rules the code must enforce

1. The team leader never rules on animals (only manages). Only exception: the owner's single-phone test flag, SQL-only, auto-off after 8 h.
2. The order of work is fixed: slaughter → esophagus (if used) → inner (lungs) → outer (last ruling) → processing (legs sorting, parts, stamps, weights). A number never appears at a station before it passed the earlier ones. Exception by design: legs / head identification stickers are put on every slaughtered animal right after slaughter (and the esophagus check when it applies), before inner / outer. Each station rules only its own stage; no override by anyone.
3. Correction: same device only, immediately (before that device ruled the same stage on another animal — by time), and before a later stage acted. A ruling's time never changes without the ruling itself.
4. Nevela / shot are decided only at slaughter (the esophagus check is part of the slaughter stage). A not-chalak / rabbinate animal may only be ruled Rabbinate Kosher or Treif; only an outer device can send it to the rabbinate screen, after the inner check and before any outer ruling; irreversible for the day.
5. The manufacturer never touches kashrut data or kashrut configuration; price per kg is set only by the manufacturer. Status definitions / screens are the team leader's decision, but never a ruling already made.
6. Slaughter through the outer check is one day. Processing (legs, parts, stamps, weights, later: nikur, salting, packing) may continue on later days, strictly in slaughter-day order — no skipping; the screen always shows which slaughter day is being worked on.

## Architecture

One server + database per plant (self-hosted Supabase). Tablets authenticate with a device key (`x-device-token`, stored hashed). Team-leader sessions (`x-manager-token`) are bound to the device and app session (10 h). Workers log in with a code (`worker_login`, `x-worker-token`). All writes go through server functions with optional command ids; direct table writes are revoked; triggers on `animals_pilot` are a second layer. Append-only event log with a server-computed hash chain.

## Known open items

- Central licensing server.
- Per-IP login limits trust `cf-connecting-ip` / `x-gt-client-ip` (depends on the plant's nginx overwriting them).
- Nikur / salting / packing stations; a tablet paired as inner + outer together.
