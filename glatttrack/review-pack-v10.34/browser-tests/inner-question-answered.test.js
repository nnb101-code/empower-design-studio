const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execFileSync}=require('child_process');
const Q=q=>execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc',q]).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const x=await open(b,'inner'), p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 const lab=n=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return c.className+' | '+c.innerText.replace(/\n/g,' ');},n);
 await p.click(cell(1)); await W(p,1000); if(await p.locator('#rumenModal.open').count()){ await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900); }
 await p.click('#gtQMaw'); await W(p,2500);
 console.log('after "?" on maw:', await lab(1), '| server:', Q("select resolution is null from animal_holds where animal_id=0 and station='inner'"));
 await p.click(cell(1)); await W(p,1200);
 console.log('tap #1 → open:', await p.evaluate(()=>[...document.querySelectorAll('#rumenModal.open,#mawModal.open,#lungModal.open')].map(o=>o.id).join(',')||'-'));
 await p.click('#tMawK'); await W(p,3500);
 console.log('maw kosher →', await lab(1), '| server hold:', Q("select coalesce(resolution,'OPEN') from animal_holds where animal_id=0 and station='inner'"), '| inner_status:', Q("select coalesce(inner_status,'-') from animals_pilot where id=0"));
 await x.ctx.close(); await b.close(); })();
