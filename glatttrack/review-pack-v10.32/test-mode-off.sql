-- GlattTrack: turn the owner's test mode OFF
update plant_state set value='off' where key='testMode';
