const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execSync}=require('child_process');
const Q=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${q}"`).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`; const OUT=__dirname+'/t26/';
const at=p=>p.evaluate(()=>[...document.querySelectorAll('#rumenModal.open,#mawModal.open,#lungModal.open')].map(o=>o.id).join(',')||'-');
const cls=(p,n)=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return c?c.className+' | '+c.innerText.replace(/\n/g,' '):'-';},n);
const draw=async p=>{const c=await p.locator('#lungDraw').boundingBox(); await p.mouse.move(c.x+60,c.y+80); await p.mouse.down(); for(let i=0;i<12;i++) await p.mouse.move(c.x+60+i*8,c.y+80+i*3); await p.mouse.up();};
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x=await open(b,'slaughter'); let p=x.p; for(let i=0;i<3;i++){await p.click('#tSlBtnS');await W(p,900);} await W(p,1500); await x.ctx.close();
 x=await open(b,'esophagus'); p=x.p; for(const n of [1,2,3]){await p.click(cell(n));await W(p,700);await p.click(`[onclick="esoDecide('ok')"]`);await W(p,900);} await x.ctx.close();
 x=await open(b,'inner'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 await p.click(cell(1)); await W(p,1000); console.log('#1 opened:', await at(p));
 await p.click('#gtQRumen'); await W(p,1200); console.log('#1 after ? on rumen →', await at(p));
 await p.click('#tMawK'); await W(p,1200); console.log('#1 after maw kosher →', await at(p));
 if((await at(p))!=='lungModal'){ await p.click(cell(1)); await W(p,1200); console.log('   (float) →', await at(p)); }
 await draw(p); await p.click('#tLConfirm'); await W(p,2500); console.log('#1 after lung confirm:', await at(p), '|', await cls(p,1));
 await p.click(cell(2)); await W(p,1000); await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900);
 await p.click('#gtQMaw'); await W(p,1500); console.log('#2 after ? on maw →', await at(p));
 await draw(p); await p.click('#gtQLung'); await W(p,2500); console.log('#2 after ? on lung:', await at(p), '|', await cls(p,2));
 await p.screenshot({path:OUT+'w29-grid.png'});
 console.log('server:', Q("select string_agg(id||':'||coalesce(inner_status,'-')||'/r='||coalesce(rumen,'-')||'/m='||coalesce(maw,'-'),' ' order by id) from animals_pilot where id<3"), '| holds:', Q("select string_agg(animal_id||':'||coalesce(resolution,'OPEN'),' ' order by animal_id) from animal_holds"));
 await p.click(cell(1)); await W(p,1200); console.log('resume #1 →', await at(p)); await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,1300); console.log('   then →', await at(p), '| drawing:', await p.evaluate(()=>!!KS.getLungDrawing(0)));
 await p.click('#tLConfirm'); await W(p,2500);
 await p.click(cell(2)); await W(p,1200); console.log('resume #2 →', await at(p)); await p.click('#tMawK'); await W(p,1300); console.log('   then →', await at(p));
 if((await at(p))!=='lungModal'){ await p.click(cell(2)); await W(p,1200); console.log('   (float) →', await at(p)); }
 await p.click('#tLConfirm'); await W(p,2500);
 console.log('server after:', Q("select string_agg(id||':'||coalesce(inner_status,'-')||'/r='||coalesce(rumen,'-')||'/m='||coalesce(maw,'-'),' ' order by id) from animals_pilot where id<3"), '| holds:', Q("select string_agg(animal_id||':'||coalesce(resolution,'OPEN'),' ' order by animal_id) from animal_holds"));
 await b.close(); })();
