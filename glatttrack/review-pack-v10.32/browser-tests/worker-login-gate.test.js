const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const Q = s => execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${s}"`).toString().trim();
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await browser.newContext({viewport:{width:1000,height:800}}); await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_device_token','tok-outer-e2e-00000000000000001'); localStorage.setItem('ks_kiosk_role','outer'); localStorage.setItem('ks_kiosk_index','0'); localStorage.setItem('ks_device_id','e2e_outer_0001'); localStorage.setItem('ks_lang_by_screen',JSON.stringify({scOuter:'he',scOuterLogin:'he'})); localStorage.setItem('i','1'); } });
  const p=await ctx.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); p.on('dialog',d=>d.accept());
  await p.goto('http://localhost:8080/'); await p.waitForTimeout(7000);
  const login=async()=>{ await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); outLogin(0); }); await p.waitForTimeout(800);
    await p.fill('#loginCodeInput','482915'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await p.waitForTimeout(3000); };
  const rule=async(id)=>{ await p.evaluate(i=>{ outOpenDec(i); }, id); await p.waitForTimeout(1500); await p.evaluate(()=>outDecide('glatt')); await p.waitForTimeout(400);
    await p.evaluate(()=>{ const b=[...document.querySelectorAll('button')].find(x=>x.offsetParent && /אישור|אשר/.test(x.textContent) && /dec|confirm/i.test(x.getAttribute('onclick')||'')); }); };
  await login();
  console.log('1) logged in — worker sessions on the server:', Q("select count(*) from worker_sessions where not revoked and device_id='e2e_outer_0001'"));
  await rule(990); await p.waitForTimeout(4000);
  console.log('2) ruling #991 (index 990) with the login → server:', Q("select coalesce(outer_status,'-')||' by '||coalesce(outer_by,'-') from animals_pilot where id=990"));
  Q("update worker_sessions set revoked=true where device_id='e2e_outer_0001'");
  console.log('3) the login ended on the server (session revoked)');
  await rule(991); await p.waitForTimeout(6000);
  console.log('4) ruling #992 without a valid login → server:', Q("select coalesce(outer_status,'-') from animals_pilot where id=991"),
              '| tablet shows:', await p.evaluate(()=>document.querySelector('.screen.active').id),
              '| kept on tablet:', await p.evaluate(()=>KS.getAnimals()[991].outerStatus));
  await login();
  let v='-'; for(let i=0;i<20 && v==='-';i++){ await p.waitForTimeout(2000); v=Q("select coalesce(outer_status,'-')||' by '||coalesce(outer_by,'-') from animals_pilot where id=991"); if(v.startsWith('-')) v='-'; }
  console.log('5) after logging in again → server:', v);
  console.log('errors:', errs.join(' | ')||'none');
  await browser.close();
})();
