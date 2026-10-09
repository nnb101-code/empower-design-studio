// "?" on the maw on one inner tablet; a second inner tablet (nothing stored on it) shows and opens the maw
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execFileSync}=require('child_process');
const Q=q=>execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc',q]).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x=await open(b,'inner'), p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 await p.click(cell(1)); await W(p,1000); if(await p.locator('#rumenModal.open').count()){ await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900); }
 await p.click('#gtQMaw'); await W(p,2500); await x.ctx.close();
 console.log('server:', Q("select part||':'||coalesce(resolution,'OPEN') from animal_holds where animal_id=0 and station='inner'"));
 x=await open(b,'inner'); p=x.p; await W(p,6000);
 console.log('tablet 2 cell #1:', await p.evaluate(()=>document.querySelector('.screen.active .num-cell[data-idx="0"]').innerText.replace(/\n/g,' ')));
 await p.click(cell(1)); await W(p,1300);
 console.log('tablet 2 tap #1 → open:', await p.evaluate(()=>[...document.querySelectorAll('#rumenModal.open,#mawModal.open,#lungModal.open')].map(o=>o.id).join(',')||'-'));
 await p.click('#tMawK'); await W(p,3500);
 console.log('tablet 2 maw kosher → server:', Q("select part||':'||coalesce(resolution,'OPEN') from animal_holds where animal_id=0 and station='inner'"), '| cell:', await p.evaluate(()=>document.querySelector('.screen.active .num-cell[data-idx="0"]').className));
 await x.ctx.close(); await b.close(); })();
