const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs');
const APP='/home/user/empower-design-studio/glatttrack/kosher-app-v10.34.html';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const p=await b.newPage({viewport:{width:820,height:1000}});
 await p.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 p.on('pageerror',e=>console.log('ERR',e.message)); await p.goto('http://localhost:8083/'); await p.waitForTimeout(5000);
 await p.evaluate(()=>{ lang='he'; applyLang(); gtSettingsBuild(); gtSettingsLabels(); });
 for(const q of ['איפוס','מדפסת','לא חלק','USDA']){
   await p.evaluate(q=>gtSetSearch(q),q);
   console.log(q+':', await p.evaluate(()=>[...document.querySelectorAll('#gtSetSearchRes button')].slice(0,4).map(b=>b.innerText.replace(/\n/g,' — ')).join(' | ')||document.getElementById('gtSetSearchRes').innerText));
 }
 await p.evaluate(()=>gtSetSearch('איפוס')); await p.evaluate(()=>gtSetSearchGo(0)); await p.waitForTimeout(800);
 console.log('opened:', await p.evaluate(()=>[...document.querySelectorAll('#gtSetGroups details[open]')].map(d=>(d.querySelector('summary').innerText||'').slice(0,30)).join(' / ')));
 await b.close(); })();
