-- GlattTrack: turn the owner's test mode ON — for testing without printers (switches itself off after 8 hours)
-- While it is on: a screen with no printer marks without printing, and every screen shows a red "test mode" row.
insert into plant_state (key, value) values ('testMode', 'on')
  on conflict (key) do update set value = 'on', updated_at = now();
select case when server_test_mode() then 'TEST MODE IS ON — it switches off by itself after 8 hours'
            else 'NOT ON — check that 02 was run' end as "GlattTrack test mode";
