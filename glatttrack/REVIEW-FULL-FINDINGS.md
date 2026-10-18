# Full review — findings (18.10)

Scope: the active server schema (review-pack-v10.38/active-schema-snapshot.sql, every function / table /
trigger / policy / grant), the app (kosher-app-v10.38.html), the support center (central-setup.sql,
index.html, notify.sh), the plant-server scripts.

Severity: HIGH = wrong kashrut / security result possible · MED = a real malfunction · LOW = edge case /
display · INFO = cleanup.

## FIXED (18.10) — every finding below

| | what was done | checked |
|---|---|---|
| S1–S6 | 02 §41: safe reads (`_ts_or_null`, seals version), the nikur "today" = the plant's day, part number checked, printers / scanners must be a device list, dead code removed, usage by the plant's day | 03: 171 / 171 (+3 new checks) |
| A1 | the "nothing was printed" note only when there is no printer at all | browser |
| A2 | stamps without the cuts list: the server allows the stamps set (stampsCount) on the stamps screen | 03 + browser (printed through the fake printer) |
| A3 | station "Connect": no test print from a station; the scanner opens the scan check | — |
| A4–A5 | the dead AI button / duplicate id / dead login code / stale comment removed | browser: no errors |
| A6–A7 | pounds / kilos labels; the parts set size from the plant's list (not 3) | — |
| A8 | the manufacturer keeps his session on the home screen | — |
| A9–A10 | station names right (head / small-parts nikur / counter); the small-parts nikur can be paired (choose screens → nikur: two screens) | browser |
| A11–A12 | the old licensing window only when a licensing server is set; messages in 3 languages; dead code removed | — |
| C1–C4 | alerts: each recipient once; login limit by the platform's address, no lock-out of the whole team; a plant that never reported → alert; "on" checked; hold one plant out of the automatic update | center test 27 / 27 + notify dry run |
| P1 | the tools run as the `postgres` system user (Ubuntu peer authentication) | VERIFIED on a stock Ubuntu Postgres 16 |
| P2 | the app file is kept in the database; the standby writes it to its web folder | tested |
| P3 | the backup disk must be mounted | tested |
| P4 | the printer search sends nothing to the devices (GT_PRINTER_ASK_MODEL=1 to ask the model) | — |
| P5 | 02 + 03 in ONE transaction (a failed test undoes 02); a failed release waits 6 h | tested (forced failure rolled back) |
| P6 | gt_state with psql variables; the nightly test deletes only its own attempt | tested |

## Server (02 / active schema) — DONE

- Grants: anon/authenticated reach only the RPC list + SELECT on 7 tables (RLS guarded). Server-only
  functions (leader_account_*, manufacturer_set_code, _set_setup_code, leader_device_recovery) are
  revoked. OK.

S1 LOW — `_support_access_open()` / `_maker_session_end()` cast plant_state.supportAccessUntil with
  `::timestamptz` directly. A bad value (only possible from the SQL editor) makes every session check
  throw → nobody can log in. Fix: `_ts_or_null(value)`.
S2 LOW — `seals_get`: `plant_state.sealsVersion::bigint` direct cast (same class). Fix: regex guard.
S3 LOW — nikur "today" counters (`nikur_scan.today`, `nikur_board.todayIn`) use `date_trunc('day', now())`
  = the server's time zone (UTC on Supabase), not plantTimezone → in Israel the counter restarts at
  02:00/03:00, in the US in the afternoon. Display only. Fix: the plant day.
S4 LOW — `print_job_add`: `nullif(x->>'i','')::int` — a non-number throws (server_error) instead of
  bad_value. Fix: regex check first.
S5 LOW — `push_settings`: 'scanners' (station key) and 'printers' have no shape check in
  `_settings_value_error` — a station can write any JSON there. (Check how the app reads them → see app.)
S6 INFO — dead code: `_do_board_reset` v_carry block; duplicate 'loginModeByRole' branch in
  `_settings_value_error`; `_plant_usage` uses current_date (server tz).

## App (kosher-app-v10.38.html)

(read: every line 1–18859, except the data blobs — fonts / images / OCR templates; + static checks of every id / handler)

A1 MED — printing popup says "⚠ printer not connected — nothing was printed" AFTER a successful print:
  `_gtPrintNotice` (≈17680) still reads the old `p.status==='connected'` from the settings; since round 23
  the status is kept on the tablet (`gtPrinterStatusOf`). A printer added from the new add-box has
  status 'disconnected' forever → the red note shows on every legs / parts / stamps print. Workers may print
  again (double stickers). Fix: use gtPrinterStatusOf(p).  CONFIRMED in the code (17682).
A2 MED — stamps on a plant WITHOUT the cuts list, network printer: `gtAreaPieces('stamps')` gives
  stampsCount (default 5) pieces with pid '' → print_job_add gets 5 labels and p_parts=[] → the server
  refuses 'too_many' (labels > greatest(1, parts)) → nothing marked, the stamps station cannot work.
  Fix: send one part entry per label (pid null allowed → whole-animal check) or let the server allow
  labels ≤ stampsCount when parts=[].  CONFIRMED in the code on both sides (_gtStampsJobs 8608 → parts [] ; print_job_add: labels > greatest(1, parts) → too_many).
A3 LOW — the station's "Connect" button (renderScreenDeviceStatus → connectScreenDevices) sends a TEST
  print; the server allows a test only with a team-leader token → on a network printer it always fails
  at a station ("only the team leader prints a test sticker") and marks the printer "did not print".
  Fix: no test print from a station (or just re-check status).
A4 LOW — manufacturer-only "AI — analyze and fix problems" button: `mgrAiAnalyzeProblems` writes to
  #mgrAiInput which no longer exists → TypeError, nothing happens. Fix: remove the button (or the AI tab).
A5 INFO — duplicate id attribute on the pen button (`id="tPen" … id="tPen"`, line 1962); dead code in
  `_workerLoginVerify` (unused `local`, `if(false)`), stale comment on the browser hash chain (≈2866).

A6 LOW — pounds / kilos mixed in the summaries: the rank-table header 'סה״כ ק״ג' and the focus headers stay "kg"
  while the values are converted with gtW (pounds plant); the "average per animal" row is not converted. Display only.
A7 LOW — hard-coded "/3" and ">=3" in the parts grid labels and the reprint log, while the plant's set size varies
  (completion itself uses partsScanned — display only).
A8 LOW — the manufacturer is logged out when he comes back to the home screen: `_gtLeaderSessionOk` accepts only
  role manager / owner, the server answers 'manufacturer' → the token is cleared (and the stashed team-leader
  session too). Reached by back / reload on a non-station tablet. (PLAUSIBLE — verify in the browser.)
A9 LOW — wrong station names: the devices list and the pairing window build the label key with "-index" only for
  inner / outer / leader → the head screen (legs-1) shows "Legs / Head", the small-parts nikur shows "Nikur",
  a counter screen shows the raw word "display"; the pairing window puts that wrong name as the device name.
A10 MED — the SMALL-PARTS NIKUR screen cannot be paired from the app: it is nikur station index 1, but
  gtPlanSlots() gives only [nikur, 0]; the stations panel hides index 1 ("a second slot the plant does not use")
  and the installation page lists only index 0. Fix: add [nikur,1] when nikur is chosen (or a "small-parts nikur"
  choice). The server already allows it (device_pair: nikur slot 1 = the small-parts nikur).
A11 INFO — the old licensing block (activation code, license request window, hourly usage / heartbeat / status
  to "central") calls RPCs that do not exist in the support center (activate_installation, report_usage,
  report_plant_heartbeat, report_plant_status, report_support_issue, submit_license_request) and
  GT_SERVER.central is never set → the license card always says "not configured"; the license request window
  opens once on the team leader's first login and can only fail. Billing really goes through report-to-center.sh.
  Fix: remove the block (or point it at the center).
A12 INFO — Hebrew-only messages in pairing / devices (ATalert / ATconfirm in _mgrDoPair, mgrUnpairDevice,
  rename / retire, enforcement); stale line "Cooler, packaging, salting, nikkur — coming soon" under the stations;
  dead code: _mgrPairPromptOld, _renderScreenDeviceStatusOld, the code after `return` in gtRenderSetupGuide;
  the `unfinished_animals` branch of ksRunProtectedDailyReset; the boot migrations (screenConfig / disabledStatuses
  — checked: harmless, the server's settings load first); the Tesseract whitelist has no "l b" (a pounds label
  is read as pounds only by the plant setting).

## Support center

(read: central-setup.sql 1–698, index.html 1–282, notify.sh 1–49)
- All tables closed to anon; every RPC checks the staff session + role; inputs escaped on the page. OK.

C1 LOW — notify.sh: when ONE recipient fails (a wrong phone number), the alert is not marked sent → next minute it
  is sent again to EVERY recipient → the same SMS / WhatsApp / e-mail every minute until fixed. Fix: mark per
  recipient / per channel.
C2 LOW — sc_login: the per-address limit uses x-forwarded-for, which the caller can set → it can be bypassed, and
  the shared limit (500 wrong codes / 15 min) lets anyone with the public page lock ALL staff out, again and
  again. (Codes are long + bcrypt — guessing is not the risk; the lock-out is.)
C3 INFO — _sc_check_silent never alerts a plant that never reported at all; sc_notify_set: a non-boolean "on"
  throws (server_error, not bad_value); a command is marked "delivered" before the plant ran it — if the plant
  script dies there, it stays "sent" forever.
C4 INFO — one global release for all plants (no step-by-step rollout; only "update this plant now").

## Plant-server scripts

(read: every script + conf + systemd + keepalived + NUT)

P1 HIGH (installation) — every tool runs as root (sudo / systemd without User=) and connects as
  `-U postgres` over the local socket. On a standard Ubuntu / Debian postgresql-16 (the guide installs it with
  apt) that is refused: "Peer authentication failed for user postgres" — VERIFIED here on a stock cluster.
  Result: keepalived's check_pg.sh always fails → NO server takes the floating address → the tablets cannot
  reach the plant server; also the fence, sync watchdog, print relay, backup, nightly check and support-center
  report all fail ("down"). Fix: run them as the postgres user (systemd User=postgres / runuser -u postgres) or a
  pg_ident map root→postgres, set by setup-primary / setup-standby, plus one line in the guide.
P2 MED — the app file is updated only on the main server; the standby keeps the file it had at installation.
  After a takeover the tablets load the standby's file, and the app's update check fires on ANY different version
  (`!==`, not "newer") → every tablet "updates" back to the old app against the newer database.
  Fix: update-app.sh also copies the file to the peer (and the app offers only a newer version).
P3 MED — backup.sh: `mkdir -p /mnt/gt-backup` — when the USB disk is NOT mounted it creates the folder on the
  server's own disk and the backup is made and "verified" there. Health shows green; the backup dies with the
  server's disk. Fix: `mountpoint -q "$GT_BACKUP_DIR"` (or a marker file on the disk).
P4 LOW — the printer search sends "~HI" to every device with port 9100 open; an ordinary office / network printer
  (not ZPL) prints a page with "~HI" on every search. Fix: ask only after the team leader confirms, or send nothing.
P5 LOW — update-app.sh runs 02 BEFORE the self-test: if the test fails, the server was already changed (only
  the app is held back); --rollback returns only the app file. report-to-center.sh retries a failing release
  every 5 minutes (02 + self-test again and again) — no back-off.
P6 INFO — gt_state puts the value inside $v$…$v$ (a value containing "$v$" breaks it); the nightly IP test may
  delete a real tablet's failed login of that same minute.
