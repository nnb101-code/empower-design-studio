const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execFileSync}=require('child_process');
const Q=q=>execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc',q]).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
const lab=(p,n)=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return (c.className.includes('gt-usda')?'USDA':'—')+'('+c.innerText.replace(/\n/g,' ')+')';},n);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 for(const [r,st,n] of [['stamps','stamps',1],['legs','legs',2],['inner','inner',3]]){ const x=await open(b,r), p=x.p;
   await p.evaluate(([st,n])=>{ gtUsdaStart(st); document.getElementById('gtHoldNum').value=String(n); },[st,n]); await W(p,300); if(await p.locator('#gtSheet .gt-up[data-part="whole"]').count()) await p.click('#gtSheet .gt-up[data-part="whole"]'); await p.click('#gtUsdaOk'); await W(p,1500); await x.ctx.close(); }
 console.log('holds on server:', Q("select string_agg((animal_id+1)||':'||station,', ' order by id) from animal_holds where resolved_at is null"));
 for(const r of ['slaughter','esophagus','legs','inner','outer','stamps']){ const x=await open(b,r), p=x.p; await W(p,2500);
   console.log(r.padEnd(10), '#1', await lab(p,1), ' #2', await lab(p,2), ' #3', await lab(p,3)); await x.ctx.close(); }
 await b.close(); })();
