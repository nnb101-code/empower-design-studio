const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs'); const { execSync } = require('child_process');
const Q=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${q}"`).toString().trim();
const APP=process.env.APP||'/home/user/empower-design-studio/glatttrack/kosher-app-v10.22.html';
async function ctxOf(b, init){ const c=await b.newContext({viewport:{width:1024,height:700}}); await c.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)})); if(init) await c.addInitScript(init); return c; }
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 // 1) a parts tablet (never saw the team leader's device) gets the marks from the server
 const c1=await ctxOf(b,()=>{ if(localStorage.getItem('i'))return; localStorage.setItem('ks_device_token','tok-demo-parts-0000000000000000'); localStorage.setItem('ks_kiosk_role','parts'); localStorage.setItem('ks_kiosk_index','0'); localStorage.setItem('ks_device_id','e2e_parts_0001'); localStorage.setItem('i','1'); });
 const p=await c1.newPage(); p.on('pageerror',e=>console.log('pageerror',e.message)); await p.goto('http://localhost:8083/'); await p.waitForTimeout(8000);
 console.log('1) parts tablet marks:', await p.evaluate(()=>Object.keys(KS.getSettings().customSeals||{}).sort().join(',')));
 console.log('   sticker has mark image:', await p.evaluate(()=>{ const d=document.createElement('div'); d.id='x'; document.body.appendChild(d); renderSticker('x',0,'kosher',{status:'glatt',num:1}); return !!d.querySelector('img'); }));
 // 2) no mark for a status → the sticker says so
 Q("delete from kashrut_seals where key='mk'; update plant_state set value=(value::bigint+1)::text where key='sealsVersion'");
 await p.evaluate(()=>_gtSealsPull()); await p.waitForTimeout(1500);
 console.log('2) without MK mark:', await p.evaluate(()=>{ const d=document.createElement('div'); d.id='y'; document.body.appendChild(d); renderSticker('y',0,'kosher',{status:'mk',num:1}); return d.innerText.replace(/\n/g,' | '); }));
 // 3) the team leader uploads a mark → it reaches the server
 const c2=await ctxOf(b,()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'})); localStorage.setItem('i','1'); } window._gtLicShown=true; });
 const t=await c2.newPage(); t.on('dialog',d=>d.accept()); await t.goto('http://localhost:8083/'); await t.waitForTimeout(7000);
 await t.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrEnter(); }); await t.waitForTimeout(1000);
 await t.fill('#loginCodeInput','e2e-tl-code-7731'); await t.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await t.waitForTimeout(9000);
 console.log('3) health row:', await t.evaluate(()=>{ const r=[...document.querySelectorAll('#mgrHealth .gt-hrow')].find(x=>/סימני כשרות/.test(x.innerText)); return r&&r.innerText.replace(/\n/g,' '); }));
 const mk=JSON.parse(fs.readFileSync(__dirname+'/demo-seals.json')).mk;
 await t.evaluate(mk=>{ const s=KS.getSettings(); const seals=Object.assign({}, s.customSeals||{}); seals.mk=mk; KS.updateSettings({customSeals:seals}); }, mk); await t.waitForTimeout(2500);
 console.log('   server mk after upload:', Q("select coalesce((select length(image)::text from kashrut_seals where key='mk'),'none')"));
 await t.evaluate(()=>{ _gtHealthBusy=false; gtHealthRefresh(); }); await t.waitForTimeout(2500);
 console.log('   health row now:', await t.evaluate(()=>{ const r=[...document.querySelectorAll('#mgrHealth .gt-hrow')].find(x=>/סימני כשרות/.test(x.innerText)); return r&&r.innerText.replace(/\n/g,' '); }));
 await p.evaluate(()=>_gtSealsPull()); await p.waitForTimeout(1500);
 console.log('4) parts tablet has MK again:', await p.evaluate(()=>!!(KS.getSettings().customSeals||{}).mk));
 await b.close(); })();
