const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -At`,{input:s}).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'esophagus'), p=x.p; await W(p,1500);
 for(const n of [14,13]){
  await p.click(`.screen.active .num-cell[data-idx="${n-1}"]`); await W(p,700);
  const warn=await p.evaluate(()=>document.getElementById('esoWarnModal').classList.contains('open'));
  if(warn){ await p.click('#esoWarnModal button:has-text("אשר שינוי")'); await W(p,500);
    await p.click('#esoModal button:has-text("? שאלה")'); await W(p,3500); }
  console.log('#'+n, 'warn window:', warn, '| notice:', await p.evaluate(()=>[...document.querySelectorAll('#gtStatusBar .gt-srow')].map(r=>r.textContent).join(' / ')));
  console.log('   server:', q(`select eso_checked||' '||coalesce(eso_result,'-')||' open?='||exists(select 1 from animal_holds h where h.animal_id=${n-1} and h.station='eso' and h.resolved_at is null) from animals_pilot where id=${n-1}`));
  console.log('   cell:', await p.evaluate(n=>document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`).innerText.replace(/\s+/g,' '),n));
  await p.evaluate(()=>{ try{ gtStatusClear('rule'); }catch(e){} });
 }
 await p.screenshot({path:'shots/eso-q14.png'});
 await x.ctx.close(); await b.close(); })();
