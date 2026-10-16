const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'legs'), p=x.p; await W(p,2500);
 console.log(await p.evaluate(()=>['#1 slaughtered','#2 eso ok','#3 legs printed','#4 inner done','#5 outer ruled'].map((t,i)=>t+' → '+_gtUsdaZone(i)).join('\n')));
 // the legs station marks #2 (eso checked, not printed)
 const r=await p.evaluate(()=>gtHoldPut(1,'legs','usda','whole')); await W(p,2000);
 console.log('legs marks #2:', r, await p.evaluate(()=>[...document.querySelectorAll('#gtStatusBar .gt-srow')].map(r=>r.textContent).join(' / ')));
 await x.ctx.close(); await b.close(); })();
