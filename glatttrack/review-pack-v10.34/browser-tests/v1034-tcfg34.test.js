const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs');
const APP='/home/user/empower-design-studio/glatttrack/kosher-app-v10.34.html';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const p=await b.newPage();
 await p.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 p.on('pageerror',e=>console.log('ERR',e.message)); await p.goto('http://localhost:8083/'); await p.waitForTimeout(5000);
 for(const c of ['1both','1in1out','1in2out','2in2out']){
  console.log(c, await p.evaluate(c=>{ const g=KS.getSettings; KS.getSettings=()=>Object.assign({},g(),{screenConfig:c}); _gtSyncCfgViews(); KS.getSettings=g;
    const row=document.getElementById('mgrNcRouteBT').closest('.mgr-toggle-row');
    return document.getElementById('mgrCfgNow').textContent+' | routing switch '+(row.style.display==='none'?'hidden':'shown'); },c)); }
 console.log('old buttons gone:', await p.evaluate(()=>!document.getElementById('sc0')&&!document.getElementById('sc4')));
 console.log('loaded label:', await p.evaluate(()=>document.getElementById('mgrCfgNow').textContent));
 await b.close(); })();
