const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const sql=q=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtinst -tA -c "${q}"`).toString().trim();
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await b.newContext({viewport:{width:1024,height:700}});
  await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'})); localStorage.setItem('i','1'); }
    window.__answers=[]; window.prompt=(m)=>{ const a=window.__answers.shift(); console.log('PROMPT:'+m+' => '+a); return a; }; });
  await ctx.route(u=>{const x=new URL(u); return x.pathname==='/'||x.pathname.startsWith('/index');}, r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:require('fs').readFileSync((process.env.APP||'kosher-app-v10.20.html'))}));
  await ctx.route('**/rest/v1/rpc/device_pair', async r=>{ const resp=await r.fetch(); globalThis.__paired=true; await new Promise(z=>setTimeout(z,5000)); r.fulfill({response:resp}); });
  const p=await ctx.newPage(); p.on('console',m=>{ if(m.text().startsWith('PROMPT')) console.log(m.text()); }); p.on('dialog',d=>{console.log('DIALOG',d.type(),d.message().slice(0,80)); d.accept();}); p.on('response',async r=>{ const u=r.url(); if(u.includes('/rest/v1/rpc/')){ let t=''; try{t=(await r.text()).slice(0,160);}catch(e){} if(/manager|leader|session|device_pair|whoami|health|first/.test(u)) console.log('RPC',u.split('/rpc/')[1].split('?')[0],r.status(),t.replace(/\s+/g,' ')); } }); p.on('pageerror',e=>console.log('pageerror',e.message));
  await p.goto(''+(process.env.GT_URL||'http://localhost:8084/')+''); await p.waitForTimeout(6000);
  sql("select _set_setup_code('ABCD-1234-XY')");
  await p.evaluate(()=>pairEnsureCode(true)); await p.waitForTimeout(2500);
  await p.screenshot({path:__dirname+'/inst/1.png'});
  console.log('pair body:', (await p.innerText('#pairBody')).replace(/\s+/g,' ').slice(0,300));
  await p.evaluate(()=>{ window.__answers=['משה כהן','moshe-2026','ABCD-1234-XY']; });
  await p.click('text=יצירת ראש הצוות הראשון');
  for(let k=0;k<40 && !globalThis.__paired;k++) await p.waitForTimeout(250);
  await p.waitForTimeout(500); await p.evaluate(()=>{ _gtHealthBusy=false; gtHealthRefresh(); });
  await p.waitForTimeout(14000);
  await p.screenshot({path:__dirname+'/inst/2.png'});
  console.log('screen', await p.evaluate(()=>document.querySelector('.screen.active').id), 'wizard', await p.evaluate(()=>{const w=document.getElementById('gtWizard'); return w&&w.style.display;}));
  for(let i=0;i<4;i++){ const t=await p.evaluate(()=>{const w=document.getElementById('gtWizard'); return w? w.innerText.slice(0,500):''}); console.log('--- step',i,t.replace(/\n+/g,' | ')); 
    console.log('buttons:', await p.evaluate(()=>[...document.querySelectorAll('#gtWizard button, #gtWizard input, #gtWizard [onclick]')].map(x=>(x.innerText||x.placeholder||'').trim().slice(0,30)+'=>'+(x.getAttribute('onclick')||'').slice(0,60)).join(' ;; ')));
    await p.screenshot({path:__dirname+'/inst/w'+i+'.png'});
    if(i===2) break;
    await p.evaluate(()=>gtWizGo(1)); await p.waitForTimeout(1500); }
  await b.close();
})();
