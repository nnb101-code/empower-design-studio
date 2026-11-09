const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync('psql -h /tmp -p 5433 -U postgres -d gtapp -At',{input:s}).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const L=await open(b,'legs'); await W(L.p,2000);
 // go offline for a moment so the tap waits in the queue, then "update now"
 await L.ctx.setOffline(true);
 await L.p.evaluate(()=>{ window.__mark=3; _gtLastTouch=Date.now(); lgTap(0); });
 console.log('waiting in the queue:', await L.p.evaluate(()=>KS.pendingCount()));
 await L.p.evaluate(()=>window.gtUpdateOffer('v10.99')); await W(L.p,300);
 await L.p.click('#gtUpdNow'); await W(L.p,3000);
 console.log('offline → not reloaded yet (waits for the queue):', await L.p.evaluate(()=>window.__mark===3));
 await L.ctx.setOffline(false); await W(L.p,25000);
 console.log('online → reloaded:', await L.p.evaluate(()=>window.__mark===undefined), '| on:', await L.p.evaluate(()=>(document.querySelector('.screen.active')||{}).id), '| server #1 legs/head:', q("select legs_stickers||'/'||head_stickers from animals_pilot where id=0"));
 await b.close(); })();
