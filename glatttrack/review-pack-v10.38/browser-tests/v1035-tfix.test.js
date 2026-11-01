const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -At`,{input:s}).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
const loc=(p,i)=>p.evaluate(i=>{const a=KS.getAnimal(i);return (a.legsStickers?'L':'-')+(a.headStickers?'H':'-');},i);
const srv=i=>q(`select (case when legs_stickers then 'L' else '-' end)||(case when head_stickers then 'H' else '-' end) from animals_pilot where id=${i}`);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const L=await open(b,'legs'); await W(L.p,1500);
 // A) "held": a USDA hold the tablet does not know about yet → the server refuses → the tablet puts it back
 q(`insert into animal_holds (board_epoch, animal_id, station, kind, part, created_by_device) select _board_epoch(), 0, 'outer', 'usda', 'whole', 'e2e_outer_0001'`);
 await L.p.evaluate(()=>{ window.gtHeldAt=()=>null; lgTap(0); }); await W(L.p,5000);
 console.log('A) held   → tablet:', await loc(L.p,0), '| server:', srv(0), '(expect -- / --)');
 q(`delete from animal_holds`);
 // B) worker login ran out → the change is KEPT (not reverted) until the login
 q(`update settings_pilot set settings = settings || '{"loginModeByRole":{"legs":"code"}}'::jsonb, updated_at=now(), device_id='server' where id=1`);
 await W(L.p,1000);
 await L.p.evaluate(()=>{ KS.setLegsStickers(1); KS.setHeadStickers(1); }); await W(L.p,5000);
 console.log('B) login  → tablet:', await loc(L.p,1), '| server:', srv(1), '(expect LH / --, kept)');
 q(`update settings_pilot set settings = settings || '{"loginModeByRole":{"legs":"none"}}'::jsonb, updated_at=now(), device_id='server' where id=1`);
 // C) head tablet (slot 1) while legs / head are ONE screen → not in use
 await L.p.evaluate(()=>{ lgInstance=1; lgRenderGrid(); }); await W(L.p,300);
 console.log('C) slot 1, one screen → role:', await L.p.evaluate(()=>_lgRole()), '|', await L.p.evaluate(()=>document.getElementById('lgRoleLbl').textContent));
 await L.ctx.close();
 // D) cooler tablet: the login does not send settings
 q(`update devices_pilot set assigned_role='cooler', assigned_index=0 where id='demo_legs'`);
 q(`update settings_pilot set settings = jsonb_set(settings,'{screensPlan,screens}', (settings #> '{screensPlan,screens}') || '["cooler"]'::jsonb), updated_at=now(), device_id='server' where id=1`);
 const before=q(`select device_id||' '||updated_at from settings_pilot`);
 const C=await open(b,'legs','cooler'); await W(C.p,5000);
 await C.p.evaluate(()=>supLogin()); await W(C.p,4000);
 console.log('D) cooler → screen:', await C.p.evaluate(()=>document.querySelector('.screen.active').id), '| settings row unchanged:', q(`select device_id||' '||updated_at from settings_pilot`)===before);
 await C.ctx.close();
 q(`update devices_pilot set assigned_role='legs', assigned_index=0 where id='demo_legs'`);
 q(`update settings_pilot set settings = jsonb_set(settings,'{screensPlan,screens}', (settings #> '{screensPlan,screens}') - 'cooler'), updated_at=now() where id=1`);
 await b.close(); })();
