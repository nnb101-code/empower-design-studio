const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs=require('fs');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await browser.newContext({viewport:{width:430,height:900}, deviceScaleFactor:2, acceptDownloads:true});
  await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'})); localStorage.setItem('i','1'); } });
  const p=await ctx.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); p.on('dialog',d=>d.accept());
  await p.goto('http://localhost:8080/'); await p.waitForTimeout(8000);
  await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrEnter(); }); await p.waitForTimeout(1200);
  await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click());
  for(let i=0;i<20;i++){ await p.waitForTimeout(1000); const ok=await p.evaluate(async()=>{ try{ const b=await window.sb.rpc('system_health',{p_token:KS.getManagerToken()}); return !!(b.data&&b.data.ok); }catch(e){ return false; } }); if(ok) break; }
  await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); try{gtWizardClose(true);}catch(e){} });
  console.log('tok:', await p.evaluate(()=>[!!KS.getManagerToken(), (document.getElementById('loginError')||{}).textContent, (document.querySelector('.screen.active')||{}).id].join(' / ')));
  console.log('dbg:', await p.evaluate(async()=>{ const a=await window.sb.rpc('animal_card',{p_token:KS.getManagerToken(),p_date:'2026-10-02',p_n:11}); const b=await window.sb.rpc('system_health',{p_token:KS.getManagerToken()}); return JSON.stringify([a.error, a.data && a.data.error, b.error, b.data && b.data.ok]); }));
  // the card of animal #12 on 2.10.2026
  await p.evaluate(()=>gtAnimalCard('2026-10-02', 11)); await p.waitForTimeout(3000);
  console.log('card:', await p.evaluate(()=>document.querySelector('#gtCardModal .gt-box').innerText.replace(/\s+/g,' ').slice(0,420)));
  await p.screenshot({path:'first/card.png'});
  await p.evaluate(()=>gtAnimalCard(null, 990)); await p.waitForTimeout(2500);
  console.log('today card:', await p.evaluate(()=>document.querySelector('#gtCardModal .gt-box').innerText.replace(/\s+/g,' ').slice(0,200)));
  await p.evaluate(()=>document.getElementById('gtCardModal').classList.remove('open'));
  // summaries + Excel
  await p.evaluate(()=>{ mgrTab('summaries'); document.getElementById('anFrom').value='2026-09-20'; document.getElementById('anTo').value='2026-10-07'; gtAnSetPeriod('custom'); });
  await p.waitForTimeout(9000);
  console.log('export buttons:', await p.evaluate(()=>[...document.querySelectorAll('#anBody button')].filter(b=>/אקסל/.test(b.textContent)).length));
  await p.evaluate(()=>{ const d=document.querySelector('#anBody details[data-k="farm"]'); d.open=true; d.scrollIntoView(); window.scrollBy(0,-60); }); await p.waitForTimeout(500);
  await p.screenshot({path:'first/excel-btn.png'});
  const [dl] = await Promise.all([ p.waitForEvent('download'), p.evaluate(()=>{ [...document.querySelectorAll('#anBody details[data-k="farm"] button')].find(b=>/אקסל/.test(b.textContent)).click(); }) ]);
  const fp='first/'+dl.suggestedFilename(); await dl.saveAs(fp);
  console.log('file:', dl.suggestedFilename()); console.log(fs.readFileSync(fp,'utf8').slice(0,300));
  console.log('errors:', errs.join(' | ')||'none');
  await browser.close();
})();
