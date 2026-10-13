const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execSync}=require('child_process');
const Q=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${q}"`).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
const cls=(p,n)=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return c?c.className+' | '+c.innerText.replace(/\n/g,' '):'-';},n);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const OUT=__dirname+'/t26/'; require('fs').mkdirSync(OUT,{recursive:true});
 let x=await open(b,'slaughter'); let p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 console.log('round ? button:', await p.evaluate(()=>!!document.getElementById('tSlBtnQ')), '| top bar:', await p.evaluate(()=>document.querySelector('#scSlaughter .gt-tb')?.innerText));
 for(let i=0;i<4;i++){await p.click('#tSlBtnS');await W(p,900);}
 await p.click('#tSlBtnQ'); await W(p,2500);
 console.log('after ?: cell5', await cls(p,5));
 await p.click('#tSlBtnS'); await W(p,900); await p.click('#tSlBtnS'); await W(p,2500);
 console.log('server 4..6:', Q("select string_agg(id||':'||coalesce(slaughter,'-'),' ' order by id) from animals_pilot where id between 3 and 6"));
 console.log('holds:', Q("select string_agg(animal_id||':'||station||':'||kind||':'||coalesce(resolution,'OPEN'),' ') from animal_holds"));
 console.log('cells 5,6,7,8:', await cls(p,5),' || ',await cls(p,6),' || ',await cls(p,8));
 await p.screenshot({path:OUT+'1-slaughter.png'}); await x.ctx.close();
 x=await open(b,'esophagus'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,1500);
 console.log('eso cell5', await cls(p,5));
 for(const n of [1,2,3,4,5]){ await p.click(cell(n)); await W(p,700); const open=await p.evaluate(()=>document.getElementById('esoModal').style.display); if(open!=='flex'){console.log('eso modal not open for',n, await cls(p,n)); continue;} await p.click(`[onclick="esoDecide('ok')"]`); await W(p,1000); }
 await W(p,2000); console.log('server eso:', Q("select string_agg(id||':'||coalesce(eso_result,'-'),' ' order by id) from animals_pilot where id between 0 and 6"));
 await p.screenshot({path:OUT+'2-eso.png'}); await x.ctx.close();
 x=await open(b,'legs'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,1500);
 console.log('legs cell5', await cls(p,5));
 for(const n of [1,2,3,4,5]){ await p.click(cell(n)); await W(p,1300); await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'))); await p.click(cell(n)); await W(p,1300); await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'))); }
 await W(p,2000); console.log('server legs:', Q("select string_agg(id||':'||head_stickers,' ' order by id) from animals_pilot where id between 0 and 5"));
 await p.screenshot({path:OUT+'3-legs.png'}); await x.ctx.close();
 x=await open(b,'inner'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,1500);
 console.log('inner cells 4,5,6:', await cls(p,4),' || ', await cls(p,5),' || ', await cls(p,6));
 await p.screenshot({path:OUT+'4-inner.png'}); await x.ctx.close();
 x=await open(b,'slaughter'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,1500);
 await p.click(cell(5)); await W(p,800); console.log('sheet:', await p.evaluate(()=>document.getElementById('gtSheet')?.innerText.replace(/\n/g,' | ')));
 await p.screenshot({path:OUT+'5-slaughter-rule.png'});
 await p.click('#gtSheet button:has-text("נשחט")'); await W(p,3000);
 console.log('server 5:', Q("select coalesce(slaughter,'-') from animals_pilot where id=4"), '| hold:', Q("select coalesce(resolution,'OPEN')||':'||coalesce(note,'') from animal_holds where animal_id=4"));
 await x.ctx.close();
 x=await open(b,'inner'); p=x.p; await W(p,6000);
 console.log('inner cell5 now:', await cls(p,5));
 await p.screenshot({path:OUT+'6-inner-after.png'}); await x.ctx.close();
 await b.close(); })();
