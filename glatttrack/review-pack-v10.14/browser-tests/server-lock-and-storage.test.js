const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const sql=(q)=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -tA -c "${q}"`).toString().trim();
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const mk=async()=>{ const ctx=await browser.newContext({viewport:{width:1000,height:800}}); await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_device_token','tok-outer-e2e-00000000000000001'); localStorage.setItem('ks_kiosk_role','outer'); localStorage.setItem('ks_kiosk_index','0'); localStorage.setItem('ks_device_id','e2e_outer_0001'); localStorage.setItem('ks_lang_by_screen',JSON.stringify({scOuter:'he',scOuterLogin:'he'})); localStorage.setItem('i','1'); } });
    const p=await ctx.newPage(); p.errs=[]; p.on('pageerror',e=>p.errs.push(e.message)); await p.goto('http://localhost:8080/'); await p.waitForTimeout(7000);
    await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); outLogin(); }); await p.waitForTimeout(2000); return p; };
  const st=(p)=>p.evaluate(()=>({locked:!!window._gtNetLocked, storageBad:!!window._gtStorageBad, text:(document.getElementById('gtNetLock')||{}).innerText?document.getElementById('gtNetLock').innerText.split('\n').filter(Boolean).slice(0,2).join(' / '):null}));
  // A1: black hole
  let p=await mk();
  await p.route('**/rest/v1/**', ()=>{});
  for(const t of [10,20,30]){ await p.waitForTimeout(10000); console.log('A1 black hole '+t+' s:', JSON.stringify(await st(p))); }
  await p.unroute('**/rest/v1/**'); await p.waitForTimeout(10000); console.log('A1 server answers again:', JSON.stringify(await st(p)));
  console.log('A1 errors:', p.errs.join(' | ')||'none');
  await p.context().close();
  // B1: storage full, a ruling is pressed
  p=await mk();
  await p.evaluate(()=>{ window.__origSet=Storage.prototype.setItem; Storage.prototype.setItem=function(){ const e=new Error('QuotaExceededError (simulated)'); e.name='QuotaExceededError'; throw e; }; });
  await p.evaluate(()=>KS.setOuterStatus(34,'glatt','E2E storage test'));
  await p.waitForTimeout(5000);
  console.log('B1 storage full, after the press:', JSON.stringify(await st(p)), '| server row 34:', sql("select coalesce(outer_status,'-') from animals_pilot where id=34"));
  await p.evaluate(()=>{ Storage.prototype.setItem=window.__origSet; });
  await p.waitForTimeout(5000);
  console.log('B1 storage works again:', JSON.stringify(await st(p)));
  await p.screenshot({path:'first/b1-after.png'});
  console.log('B1 errors:', p.errs.join(' | ')||'none');
  await browser.close();
})();
