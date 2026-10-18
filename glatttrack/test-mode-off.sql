-- GlattTrack: turn the owner's test mode OFF now
insert into plant_state (key, value) values ('testMode', 'off')
  on conflict (key) do update set value = 'off', updated_at = now();
select case when server_test_mode() then 'still on?' else 'TEST MODE IS OFF' end as "GlattTrack test mode";
