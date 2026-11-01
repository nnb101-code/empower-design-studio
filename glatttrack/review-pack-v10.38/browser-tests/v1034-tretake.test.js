const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -At`,{input:s}).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'outer'), p=x.p; await W(p,2500);
 await p.evaluate(()=>outOpenDec(0)); await W(p,2000);
 console.log('held by:', q("select outer_open_by_device from animals_pilot where id=0"));
 q("select set_config('gt.reset_in_progress','true',false); update animals_pilot set outer_open_by_device=null, outer_open_at=null where id=0");   // as if it lapsed
 await p.evaluate(()=>window.dispatchEvent(new Event('online'))); await W(p,2000);
 console.log('after back online:', q("select outer_open_by_device from animals_pilot where id=0"), '| window open:', await p.evaluate(()=>document.getElementById('decModal').classList.contains('open')));
 q("select set_config('gt.reset_in_progress','true',false), set_config('gt.outer_open','true',false); update animals_pilot set outer_open_by_device='other_dev', outer_open_at=(extract(epoch from now())*1000)::bigint where id=0");   // A took it
 console.log('before:', q("select outer_open_by_device from animals_pilot where id=0")); console.log('direct:', await p.evaluate(async()=>JSON.stringify(await KS.outerOpen(0,true))), q("select outer_open_by_device from animals_pilot where id=0"));
 await p.evaluate(()=>window.dispatchEvent(new Event('online'))); await W(p,2000);
 console.log('A took it, B back:', await p.evaluate(()=>document.getElementById('decModal').classList.contains('open')), await p.evaluate(()=>[...document.querySelectorAll('#gtStatusBar .gt-srow')].map(r=>r.textContent).filter(t=>!/📅/.test(t)).join(' / ')));
 await x.ctx.close(); await b.close(); })();
