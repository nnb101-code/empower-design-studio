-- GlattTrack: turn the owner's test mode ON (switches itself off after 8 hours)
update plant_state set value='on' where key='testMode';
