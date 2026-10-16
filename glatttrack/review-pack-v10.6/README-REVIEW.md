# GlattTrack — review pack (app v10.6, server schema step 46)

This pack is the CURRENT state. Review these files only.

## Files

| File | What it is |
|---|---|
| `active-schema-snapshot.sql` | **Audit this first.** `pg_dump --schema-only` (public + gt_rls) of a clean database built from `glatttrack-schema-full.sql`. Exactly one ACTIVE definition of each function, trigger, RLS policy and grant. |
| `setup-supabase-step46-order-and-processing-days.sql` | The new migration (run after step 45). |
| `STEP46-CHANGES.md` | What step 46 / app v10.6 changed (Hebrew). |
| `security-selftest.sql` + `security-selftest-result.txt` | Release gate, rolled-back transaction: **101 / 101** (90 earlier checks, adapted where step 46 changed the rules, + 11 step-46 checks). |
| `SECURITY-MANIFEST.md` | Permission map (step 45 observed table) + a step-46 section. |
| `active-security-manifest.sql` + `-result.txt` | Prints the active security surface. |
| `kosher-app-v10.6.html` | The app (UI, offline store, sync client). `GT_MIN_SCHEMA = 46`. |
| `setup-supabase-step44/45/46-*.sql` | The last three migrations. |
| `glatttrack-schema-full.sql` | Full install script (base + steps 1–46, history included; last definition wins). |
| `test-mode-on.sql` / `test-mode-off.sql` | The owner's SQL-only test switch. |

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
2. The order of work is fixed: slaughter → esophagus (if used) → inner (lungs) → outer (last ruling). A number never appears at a station before it passed the earlier ones. Each station rules only its own stage; no override by anyone.
3. Correction: same device only, immediately (before that device ruled the same stage on another animal — by time), and before a later stage acted.
4. Nevela / shot are decided only at slaughter (the esophagus check is part of the slaughter stage). A not-chalak / rabbinate animal may only be ruled Rabbinate Kosher or Treif; only an outer device can send it to the rabbinate screen, after the inner check and before any outer ruling; irreversible for the day.
5. The manufacturer never touches kashrut data or kashrut configuration; price per kg is set only by the manufacturer. Status definitions / screens are the team leader's decision, but never a ruling already made.
6. Slaughter through the outer check is one day. Processing (legs, parts, stamps, weights, later: nikur, salting, packing) may continue on later days, strictly in slaughter-day order — no skipping; the screen always shows which slaughter day is being worked on.

## Architecture

One server + database per plant (self-hosted Supabase). Tablets authenticate with a device key (`x-device-token`, stored hashed). Team-leader sessions (`x-manager-token`) are bound to the device and app session (10 h). Workers log in with a code (`worker_login`, `x-worker-token`). All writes go through server functions with optional command ids; direct table writes are revoked; triggers on `animals_pilot` are a second layer. Append-only event log with a server-computed hash chain.

## Known open items

- Central licensing server.
- `create_first_manager` without a setup code when none was set at install; per-IP login limits trust `cf-connecting-ip` (depends on the plant's nginx); manager codes may be 4 characters.
- Team-leader screen for the kept processing days (the server functions exist).
- Nikur / salting / packing stations; a tablet paired as inner + outer together.
