# GlattTrack — the manufacturer's support center (v10.38) — review pack

A separate Supabase project of the manufacturer (not a plant's database). Every plant server reports to it every
5 minutes; the manufacturer's staff watch all plants, answer problem reports and bill the plants.

## Files
- `central-setup.sql` — the whole central database (tables, RLS, RPCs). Re-runnable; the LAST definition of a function is the active one.
- `central-selftest.sql` + `central-selftest-result.txt` — the self-test (24/24), one DO block, everything undone.
- `index.html` — the staff page (vanilla JS, calls the RPCs with the public anon / publishable key).
- `notify.sh` — sends the alerts (e-mail / SMS / WhatsApp), runs on the manufacturer's machine.
- `report-to-center.sh`, `update-app.sh`, `gt-lib.sh` — on each PLANT server (as root, timer every 5 min): sends `_plant_report()`, runs the center's commands, installs a released app version (sha256 checked, then 02 + the plant's security self-test).
- `plant-side-functions.sql` — the plant's database functions that feed the report (`_plant_report`, `_plant_issues`, `_plant_usage`, `support_issue_add`, `support_tickets`, `maker_changes`).

## Model
- **Plants:** `sc_plants` (code + bcrypt secret, given once). A plant authenticates with code + secret on `sc_report` / `sc_command_done` only.
- **Staff:** `sc_staff` (bcrypt code ≥ 10 chars, role `admin` / `support` / `finance` / `viewer`), sessions 12 h. `_sc_can(token, what)`:
  plants (see) admin/support/viewer · plants_write (commands, release, alerts, tickets) admin/support · plant_add admin · billing (see) admin/finance/viewer · billing_write admin/finance · staff admin. The last active admin cannot be demoted or disabled.
- **Report:** health only — servers, backup, nightly check, event chain ok, failed logins, tablets online / version; since v10.38 also the problem reports' text (→ `sc_tickets`, once per key) and the daily totals (animals, kg → `sc_usage`, for billing). Never rulings, animal numbers or codes.
- **Back to the plant:** pending commands (only 4 known: restart_standby, reload_tablets, run_nightly_check, update_now), the current release (https URL + sha256), each ticket's status + last reply.
- **Billing:** per plant `sc_billing` (by kg / by animal / fixed monthly, monthly minimum, currency), `sc_paid` per month; `_sc_bill(code, month)`.
- **Login lock:** per address (x-forwarded-for, first value) 10 wrong / 15 min, plus 500 for everyone together.

## Fixed in our own review (16.10)
A month that does not exist (2026-13) crashed `_sc_bill` → refused. The login lock was global (anyone could lock the whole team out) → per address. Old sessions, closed tickets (> 1 year), daily totals (> 3 years) are cleaned.

## Please check especially
1. Can a role do more than `_sc_can` allows (finance seeing plants, viewer writing, support touching billing / staff)? Any RPC without a role check?
2. Can a plant (with its own code + secret) write into another plant (tickets, usage, commands, status)? Can it make the center store something huge / slow (report size, issues, usage)?
3. `sc_release_set` → every plant downloads and installs it (`report-to-center.sh` / `update-app.sh`): can a wrong / hostile release get installed (URL, sha256, the shell scripts' quoting of values from the center's answer)?
4. `report-to-center.sh` reads the center's JSON answer and runs commands — any shell injection from the answer (command names, ids, release fields, ticket text)?
5. `index.html`: XSS from plant data (plant names, problem texts, notes, tablet names) — is everything escaped?
6. Billing math (`_sc_bill`): rounding, the minimum, a month with no data, a plant with no billing row.
7. The plant side (`plant-side-functions.sql`): does the report leak anything it must not (codes, worker names, rulings)? Who can call `support_issue_add` / `support_tickets` / `maker_changes`?
