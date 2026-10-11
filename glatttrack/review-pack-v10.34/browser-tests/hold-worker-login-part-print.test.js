const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execFileSync}=require('child_process');
const Q=q=>execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc',q]).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
const srv=n=>Q(`select coalesce(parts_print_count,0)||' tongue='||coalesce(tongue_sticker,false)||' cheeks='||coalesce(cheek_sticker,false) from animals_pilot where id=${n-1}`);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x=await open(b,'parts'), p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 console.log('version', await p.evaluate(()=>GT_APP_VERSION));
 // USDA on the tongue of #1
 await p.click('#scParts .gt-tbu'); await W(p,700); await p.fill('#gtHoldNum','1'); await W(p,300);
 await p.click('#gtSheet .gt-row .gt-sb >> nth=3'); await W(p,2500);
 await p.click(cell(1)); await W(p,3500);
 console.log('print popup:', await p.evaluate(()=>document.getElementById('ppPartsInfo').textContent+' | '+document.getElementById('ppTotalN').textContent));
 await W(p,4000); console.log('server #1 after print (tongue held):', srv(1));
 await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')));
 await p.click(cell(1)); await W(p,1200);
 console.log('tap #1 again →', await p.evaluate(()=>[...document.querySelectorAll('.overlay.open')].map(o=>o.id).join(',')), '| server', srv(1));
 await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')));
 // release
 await p.click('#scParts .gt-tbl'); await W(p,1200); await p.click('#gtSheet .gt-hrow .gt-sb >> nth=0'); await W(p,5000);
 console.log('after release popup:', await p.evaluate(()=>document.getElementById('ppPartsInfo').textContent), '| server', srv(1));
 await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')));
 // #2 normal print
 await p.click(cell(2)); await W(p,5000); console.log('server #2 (no hold):', srv(2));
 await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')));
 // worker login required: the parts screen now logs in with a code
 Q(`update settings_pilot set settings = settings || '{"loginModeByRole":{"parts":"code"}}'::jsonb`);
 const r=await p.evaluate(async()=>{ const ok=await gtHoldPut(2,'parts','usda','whole'); await new Promise(r=>setTimeout(r,800));
   return ok+' | screen='+document.querySelector('.screen.active').id+' | status='+(document.querySelector('[data-gt-status="worker"]')?.innerText||document.body.innerText.match(/[^\n]*USDA[^\n]*קוד[^\n]*|[^\n]*קוד[^\n]*USDA[^\n]*/)?.[0]||'?'); });
 console.log('USDA without worker login →', r, '| holds on #3:', Q(`select count(*) from animal_holds where animal_id=2 and resolved_at is null`));
 Q(`update settings_pilot set settings = settings || '{"loginModeByRole":{"parts":"none"}}'::jsonb`);
 await x.ctx.close(); await b.close(); })();
