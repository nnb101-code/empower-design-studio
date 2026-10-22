const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execFileSync}=require('child_process');
const Q=q=>execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc',q]).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
const sheet=p=>p.evaluate(()=>[...document.querySelectorAll('#gtSheet button')].map(b=>b.innerText.trim()+(b.classList.contains('on')?'[✓]':'')+(b.id==='gtUsdaOk'?'(op '+b.style.opacity+')':'')).join(' | '));
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 for(const [role,sc] of [['esophagus','scEsophagus'],['stamps','scStamps'],['parts','scParts']]){
   const x=await open(b,role), p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
   await p.click(`#${sc} .gt-tbu`); await W(p,700); await p.fill('#gtHoldNum','3');
   console.log(role,'sheet:', await sheet(p));
   if(role==='stamps'){ await p.click('#gtUsdaOk'); await W(p,600); console.log('  confirm before choosing → sheet still open:', await p.evaluate(()=>getComputedStyle(document.getElementById('gtSheet')).display)); await p.click('#gtSheet .gt-up[data-part="right"]'); }
   if(role==='parts') await p.click('#gtSheet .gt-up[data-part="tongue"]');
   await W(p,300); console.log('  after choosing:', await sheet(p));
   await p.click('#gtUsdaOk'); await W(p,2500);
   console.log('  server:', Q(`select string_agg((animal_id+1)||':'||station||':'||part,',') from animal_holds where resolved_at is null and kind='usda'`));
   await x.ctx.close(); }
 await b.close(); })();
