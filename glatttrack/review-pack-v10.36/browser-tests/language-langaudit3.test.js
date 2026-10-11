const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs');
const APP=process.env.APP; const W=(p,ms)=>p.waitForTimeout(ms);
const SCAN=()=>{ const out=new Set(); const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT); let n;
  while(n=w.nextNode()){ const t=n.nodeValue.trim(); if(!/[֐-׿]/.test(t)) continue; const p=n.parentElement; if(!p||p.closest('[data-no-i18n],script,style')) continue;
    const r=p.getBoundingClientRect(); if(!r.width||!r.height) continue; let e=p,vis=true; while(e){ if(getComputedStyle(e).display==='none'){vis=false;break;} e=e.parentElement; } if(!vis) continue; out.add(t); }
  return [...out]; };
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await b.newContext({viewport:{width:1024,height:900}});
  await ctx.route(u=>new URL(u).pathname==='/',r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
  await ctx.addInitScript(()=>{window._gtLicShown=true;if(localStorage.getItem('i'))return;localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'}));localStorage.setItem('i','1');});
  const p=await ctx.newPage(); p.on('dialog',d=>d.accept()); await p.goto('http://localhost:8083/'); await W(p,6000);
  await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));mgrEnter();}); await W(p,1000);
  await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await W(p,9000);
  await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));try{gtWizardClose(true);}catch(e){}}); await W(p,1500);
  const all={};
  for(const tab of (process.env.TABS||'monitor,analysis,search,settings,issues').split(',')){
    await p.evaluate(()=>{ while(lang!=='he') cycleLang(); });
    await p.evaluate(t=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrTab(t); if(t==='settings') document.querySelectorAll('#mgr-settings details').forEach(d=>d.open=true); }, tab); await W(p,1500);
    await p.evaluate(()=>{ while(lang!=='en') cycleLang(); }); await W(p,500);
    const t0=Date.now(); const a=await p.evaluate(SCAN);
    await p.evaluate(t=>{ mgrTab(t); if(t==='settings') document.querySelectorAll('#mgr-settings details').forEach(d=>d.open=true); }, tab); await W(p,1500);
    const b2=await p.evaluate(SCAN);
    console.log(`=== ${tab}: after switch ${a.length} · after re-open of the tab ${b2.length}`);
    all[tab]={afterSwitch:a, afterReopen:b2};
  }
  fs.writeFileSync(__dirname+'/langaudit3.json', JSON.stringify(all,null,1));
  await b.close(); })();
