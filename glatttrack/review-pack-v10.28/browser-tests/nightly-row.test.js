const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await browser.newContext({viewport:{width:430,height:900}, deviceScaleFactor:2});
  await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'})); localStorage.setItem('i','1'); } });
  const p=await ctx.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); p.on('dialog',d=>d.accept());
  await p.goto('http://localhost:8080/'); await p.waitForTimeout(8000);
  await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrEnter(); }); await p.waitForTimeout(1200);
  await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click());
  await p.waitForTimeout(7000);
  await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); try{gtWizardClose(true);}catch(e){} gtOpenHealth(); }); await p.waitForTimeout(3500);
  await p.evaluate(()=>{ const r=[...document.querySelectorAll('#mgrHealth .gt-hrow')].find(e=>/בדיקת לילה/.test(e.textContent)); r&&r.scrollIntoView({block:'center'}); });
  await p.screenshot({path:'first/nightly-row.png'});
  console.log('row:', await p.evaluate(()=>{ const r=[...document.querySelectorAll('#mgrHealth .gt-hrow')].find(e=>/בדיקת לילה/.test(e.textContent)); return r? r.innerText.replace(/\s+/g,' '):'none'; }));
  await p.evaluate(()=>gtNightlyExplain()); await p.waitForTimeout(3000);
  console.log('explain:', await p.evaluate(()=>document.getElementById('gtAiModal').innerText.replace(/\s+/g,' ').slice(0,200)));
  console.log('errors:', errs.join(' | ')||'none');
  await browser.close();
})();
