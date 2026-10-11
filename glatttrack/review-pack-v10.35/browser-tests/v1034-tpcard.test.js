const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs');
const APP='/home/user/empower-design-studio/glatttrack/kosher-app-v10.34.html';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const p=await b.newPage();
 await p.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 p.on('pageerror',e=>console.log('ERR',e.message)); p.on('dialog',d=>d.accept());
 await p.goto('http://localhost:8083/'); await p.waitForTimeout(4000);
 console.log(await p.evaluate(()=>{ lang='he'; gtTodayArrange(); gtTodayRender(); const c=document.getElementById('gtPauseCard'); return c?c.textContent.replace(/\s+/g,' ').slice(0,260):'none'; }));
 console.log(await p.evaluate(()=>{ gtPauseToggle('parts'); return 'partsPaused='+KS.getSettings().partsPaused+' | '+document.getElementById('gtPauseCard').textContent.match(/חלקים קטנים.{0,120}/)[0].slice(-12); }));
 await b.close(); })();
