// v10.26 part 2: inner/outer through, USDA at parts (tongue) + release print, stamps (left half), a change after printing, team leader card + handled
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execSync}=require('child_process'); const fs=require('fs');
const Q=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${q}"`).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
const cls=(p,n)=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return c?c.className+' | '+c.innerText.replace(/\n/g,' '):'-';},n);
const OUT=__dirname+'/t26/';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x=await open(b,'inner'); let p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 for(const n of [1,2,3,4,5]){ await p.click(cell(n)); await W(p,900); if(await p.locator('#rumenModal.open').count()){await p.click(`[onclick="rumenDecide('k')"]`);await W(p,900);} await p.click('#tMawK'); await W(p,1000); await p.click(cell(n)); await W(p,1100); await p.click('#tLConfirm'); await W(p,1200); }
 await x.ctx.close();
 x=await open(b,'outer'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 // outer "?" on #2 from the top bar: the screen goes on to 3
 await p.click('#scOuter .gt-tbq'); await W(p,600); await p.fill('#gtHoldNum','2'); await p.click('#gtSheet button:has-text("סמן")'); await W(p,2500);
 console.log('outer after ? on 2: cell2', await cls(p,2), '| cell3', await cls(p,3));
 for(const [n,s] of [[1,'גלאט'],[3,'גלאט'],[4,'MK'],[5,'בית יוסף']]){await p.click(cell(n));await W(p,1300);await p.click(`#decModal .dec-btns button:has-text("${s}")`);await W(p,1300);}
 await p.click(cell(2)); await W(p,1300); await p.click(`#decModal .dec-btns button:has-text("בית יוסף")`); await W(p,2500);
 console.log('server outer:', Q("select string_agg(id||':'||coalesce(outer_status,'-'),' ' order by id) from animals_pilot where id between 0 and 4"), '| hold 2:', Q("select coalesce(resolution,'OPEN') from animal_holds where animal_id=1 and station='outer'"));
 await x.ctx.close();
 // parts: USDA hold on the tongue of #1 → #1 prints cheeks only; release → the tongue prints
 x=await open(b,'parts'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,1500);
 await p.click('#scParts .gt-tbu'); await W(p,600); await p.fill('#gtHoldNum','1'); await p.click('#gtSheet button:has-text("לשון")'); await W(p,2500);
 console.log('parts cell1', await cls(p,1));
 await p.click(cell(1)); await W(p,1500);
 console.log('print popup:', await p.evaluate(()=>document.getElementById('ppPartsInfo')?.textContent));
 await p.screenshot({path:OUT+'7-parts-tongue-held.png'});
 await W(p,3500);
 console.log('server parts 1:', Q("select parts_print_count from animals_pilot where id=0"));
 // USDA whole on #3 → the station goes on to #4
 await p.click('#scParts .gt-tbu'); await W(p,600); await p.fill('#gtHoldNum','3'); await p.click('#gtSheet button:has-text("כל הבהמה")'); await W(p,2500);
 console.log('parts cells 2,3,4:', await cls(p,2),' || ', await cls(p,3),' || ', await cls(p,4));
 await p.click('#scParts .gt-tbl'); await W(p,800); console.log('held list:', await p.evaluate(()=>document.getElementById('gtSheet')?.innerText.replace(/\n/g,' | ')));
 await p.screenshot({path:OUT+'8-parts-held-list.png'});
 await p.click('#gtSheet .gt-hrow:has-text("לשון") button:has-text("שחרור")'); await W(p,2500);
 console.log('after release tongue popup:', await p.evaluate(()=>document.getElementById('ppPartsInfo')?.textContent), '| hold:', Q("select string_agg(animal_id||':'||part||':'||coalesce(resolution,'OPEN'),' ') from animal_holds where station='parts'"));
 await W(p,3500); await x.ctx.close();
 // stamps: USDA hold on the left half of #1; stamp #1, right weight goes in, left waits
 x=await open(b,'stamps'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,1500);
 await p.click('#scStamps .gt-tbu'); await W(p,600); await p.fill('#gtHoldNum','1'); await p.click('#gtSheet button:has-text("חצי שמאל")'); await W(p,2500);
 const code=await p.evaluate(()=>buildStickerPayload(0)); await p.evaluate(()=>{try{stampsFocusScan()}catch(e){}}); await p.keyboard.type(code,{delay:5}); await p.keyboard.press('Enter'); await W(p,3500);
 await p.evaluate(()=>{try{stampsFocusScan()}catch(e){}}); await p.keyboard.type('245.5 kg',{delay:30}); await p.keyboard.press('Enter'); await W(p,2500);
 console.log('stamps 1:', Q("select stamped||' R='||coalesce(weight_right::text,'-')||' L='||coalesce(weight_left::text,'-') from animals_pilot where id=0"), '| weight pending idx:', await p.evaluate(()=>_stampsWeightPendingIdx()));
 await x.ctx.close();
 // a change after printing: the shochet changes #1 to nevela → the warning says what was done
 x=await open(b,'slaughter'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,1500);
 await p.click(cell(1)); await W(p,1000);
 console.log('warning:', await p.evaluate(()=>document.getElementById('wDesc')?.innerText.replace(/\n/g,' | ')));
 await p.screenshot({path:OUT+'9-change-warning.png'});
 await p.click('#warnModal button:has-text("נבלה")'); await W(p,3000);
 console.log('server 1 slaughter:', Q("select slaughter from animals_pilot where id=0"), '| changes:', Q("select string_agg(animal_id||':'||stage||':'||old_value||'>'||new_value||':'||done::text,' ') from animal_changes"));
 await W(p,6000); console.log('slaughter cell1 now:', await cls(p,1));
 await x.ctx.close();
 // the team leader
 execSync('bash '+__dirname+'/../vid/rl.sh');
 const ctx=await b.newContext({viewport:{width:1024,height:900},deviceScaleFactor:1});
 await ctx.route(u=>new URL(u).pathname==='/',r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync('/home/user/empower-design-studio/glatttrack/kosher-app-v10.26.html')}));
 await ctx.addInitScript(()=>{window._gtLicShown=true;if(localStorage.getItem('i'))return;localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'}));localStorage.setItem('i','1');});
 p=await ctx.newPage(); p.on('dialog',d=>d.accept()); p.on('pageerror',e=>console.log('ERR',e.message)); await p.goto('http://localhost:8083/'); await W(p,6000);
 await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));mgrEnter();}); await W(p,1000);
 await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await W(p,9000);
 await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));try{gtWizardClose(true);}catch(e){}}); await W(p,6000);
 await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); gtFlagsPull(); }); await W(p,3000);
 console.log('TL card:', await p.evaluate(()=>document.getElementById('gtOpenCard')?.innerText.replace(/\n/g,' | ')));
 await p.screenshot({path:OUT+'10-team-leader.png'});
 await p.click('#gtOpenCard button:has-text("טופל")'); await W(p,3000);
 console.log('acked:', Q("select count(*) from animal_changes where ack_at is not null"));
 await b.close(); })();
