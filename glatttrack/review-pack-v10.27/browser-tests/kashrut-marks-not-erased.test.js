// the team-leader's PAIRED device opens the app (not logged in yet); the server never had marks
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs'); const { execSync } = require('child_process');
const Q=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${q}"`).toString().trim();
const APP=process.env.APP; const seals=JSON.parse(fs.readFileSync(__dirname+'/demo-seals.json'));
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const c=await b.newContext();
 await c.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 await c.addInitScript(()=>{ window._gtLicShown=true; });
 const p=await c.newPage(); p.on('dialog',d=>d.accept()); await p.goto('http://localhost:8083/'); await p.waitForTimeout(5000);
 await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrEnter(); }); await p.waitForTimeout(800);
 await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await p.waitForTimeout(8000);
 // now a paired team-leader device; log out; marks only on this device; server has never had any
 await p.evaluate(()=>{ try{ mgrLogout(); }catch(e){ KS.setManagerToken(null,null); } });
 Q("delete from kashrut_seals; delete from plant_state where key='sealsVersion'");
 await p.evaluate(sl=>{ localStorage.setItem('kosher_state_v1_imgs', JSON.stringify({customSeals:{glatt:sl.glatt, mk:sl.mk}})); localStorage.removeItem('gt_seals_ver'); }, seals);
 await p.reload(); await p.waitForTimeout(1500);
 console.log('has device key:', await p.evaluate(()=>!!_devToken()), '| logged in:', await p.evaluate(()=>!!KS.getManagerToken()));
 console.log('marks right after opening:', await p.evaluate(()=>Object.keys(KS.getSettings().customSeals||{}).join(',')||'none'));
 await p.waitForTimeout(6000);
 console.log('marks 6 s later:', await p.evaluate(()=>Object.keys(KS.getSettings().customSeals||{}).join(',')||'none'));
 await b.close(); })();
