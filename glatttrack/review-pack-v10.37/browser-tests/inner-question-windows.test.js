const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execSync}=require('child_process');
const Q=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${q}"`).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`; const OUT=__dirname+'/t26/';
const openNow=p=>p.evaluate(()=>[...document.querySelectorAll('#rumenModal.open,#mawModal.open,#lungModal.open')].map(o=>o.id).join(',')||'-');
const cls=(p,n)=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return c?c.className+' | '+c.innerText.replace(/\n/g,' '):'-';},n);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x=await open(b,'slaughter'); let p=x.p; for(let i=0;i<5;i++){await p.click('#tSlBtnS');await W(p,900);} await W(p,1500); await x.ctx.close();
 x=await open(b,'esophagus'); p=x.p; for(const n of [1,2,3,4]){await p.click(cell(n));await W(p,700);await p.click(`[onclick="esoDecide('ok')"]`);await W(p,900);}
 await p.click(cell(5)); await W(p,700); console.log('eso window ? button:', await p.isVisible('#gtQEso')); await p.click('#gtQEso'); await W(p,2500);
 console.log('eso cell5:', await cls(p,5)); await x.ctx.close();
 x=await open(b,'inner'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 console.log('inner top-bar ?:', await p.evaluate(()=>!!document.querySelector('#scInner .gt-tbq')));
 // #1: ? in the rumen window
 await p.click(cell(1)); await W(p,1000); console.log('#1 opened:', await openNow(p));
 await p.screenshot({path:OUT+'w-1-rumen.png'});
 await p.click('#gtQRumen'); await W(p,2500); console.log('#1 after ?:', await cls(p,1), '| next:', await p.evaluate(()=>document.querySelector('#inGrid .num-cell.next')?.dataset.idx));
 // #2: rumen kosher → ? in the maw window
 await p.click(cell(2)); await W(p,1000); await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900); console.log('#2 at:', await openNow(p));
 await p.click('#gtQMaw'); await W(p,2500);
 // #3: rumen k, maw k → lungs, draw, ?
 await p.click(cell(3)); await W(p,1000); await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900); await p.click('#tMawK'); await W(p,1200);
 await p.click(cell(3)); await W(p,1300); console.log('#3 at:', await openNow(p));
 const c=await p.locator('#lungDraw').boundingBox(); await p.mouse.move(c.x+60,c.y+80); await p.mouse.down(); for(let i=0;i<15;i++) await p.mouse.move(c.x+60+i*8,c.y+80+i*3); await p.mouse.up();
 await p.screenshot({path:OUT+'w-3-lung.png'});
 await p.click('#gtQLung'); await W(p,2500);
 console.log('cells 1,2,3,4:', await cls(p,1),' || ',await cls(p,2),' || ',await cls(p,3),' || ',await cls(p,4));
 console.log('server:', Q("select string_agg(id||':'||coalesce(inner_status,'-')||'/r='||coalesce(rumen,'-')||'/m='||coalesce(maw,'-'),' ' order by id) from animals_pilot where id<4"), '| holds:', Q("select string_agg(animal_id||':'||station||':'||coalesce(resolution,'OPEN'),' ' order by animal_id) from animal_holds"));
 // back: each continues from where it stopped
 await p.click(cell(1)); await W(p,1000); console.log('resume #1 →', await openNow(p)); await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900); console.log('   then →', await openNow(p)); await p.click('#tMawK'); await W(p,1200);
 await p.click(cell(2)); await W(p,1000); console.log('resume #2 →', await openNow(p)); await p.click('#tMawK'); await W(p,1200);
 await p.click(cell(3)); await W(p,1300); console.log('resume #3 →', await openNow(p), '| drawing kept:', await p.evaluate(()=>!!KS.getLungDrawing(2)));
 await p.screenshot({path:OUT+'w-4-lung-resumed.png'});
 await p.click('#tLConfirm'); await W(p,2500);
 console.log('server after:', Q("select string_agg(id||':'||coalesce(inner_status,'-'),' ' order by id) from animals_pilot where id<4"), '| holds:', Q("select string_agg(animal_id||':'||station||':'||coalesce(resolution,'OPEN'),' ' order by animal_id) from animal_holds"));
 await b.close(); })();
