// v10.24: upload pictures with several marks (Beit Yosef 4 marks, MK 2 marks) and print stickers
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs'); const { execSync } = require('child_process');
const Q=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${q}"`).toString().trim();
const APP=process.env.APP||'/home/user/empower-design-studio/glatttrack/kosher-app-v10.24.html';
const M='/home/user/empower-design-studio/glatttrack/kashrut-marks/';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const c=await b.newContext({viewport:{width:1000,height:900}});
 await c.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 await c.addInitScript(()=>{ window._gtLicShown=true; if(localStorage.getItem('i'))return; localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'})); localStorage.setItem('i','1'); });
 const p=await c.newPage(); p.on('dialog',d=>d.accept()); p.on('pageerror',e=>console.log('pageerror',e.message)); await p.goto('http://localhost:8083/'); await p.waitForTimeout(5000);
 await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrEnter(); }); await p.waitForTimeout(1000);
 await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await p.waitForTimeout(9000);
 for (const [k,f] of [['beit','beit-yosef-4-marks-blue.png'],['mk','mk-2-marks-red.png']]) {
   await p.evaluate(k=>{ const i=document.createElement('input'); i.type='file'; i.id='up_'+k; document.body.appendChild(i); i.onchange=()=>mgrUploadSeal(k,i); }, k);
   await p.setInputFiles('#up_'+k, M+f); await p.waitForTimeout(2500);
 }
 console.log('local:', await p.evaluate(()=>{const s=KS.getSettings().customSeals||{};return Object.keys(s).map(k=>k+'='+s[k].length).join(' ');}));
 await p.waitForTimeout(3000);
 console.log('server:', Q("select string_agg(key||'='||length(image),' ' order by key) from kashrut_seals"));
 const sizes = await p.evaluate(async()=>{ const s=KS.getSettings().customSeals; const o={}; for(const k of ['beit','mk']){ const im=new Image(); im.src=s[k]; await im.decode(); o[k]=im.width+'x'+im.height; } return o; });
 console.log('picture size:', JSON.stringify(sizes));
 await p.evaluate(()=>{ const d=document.createElement('div'); d.id='tst'; d.style.cssText='position:fixed;top:0;left:0;z-index:99999;background:#ddd;padding:20px;display:flex;gap:20px;direction:rtl'; d.innerHTML='<div id="sa"></div><div id="sb"></div><div id="sc"></div>'; document.body.appendChild(d);
   renderSticker('sa',0,'kosher',{status:'beit'}); renderSticker('sb',1,'kosher',{status:'mk'}); renderSticker('sc',2,'kosher',{status:'glatt'}); });
 await p.waitForTimeout(1500); await (await p.$('#tst')).screenshot({path:__dirname+'/stickers1024.png'});
 await b.close(); })();
