const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = __dirname + '/shots17';
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await b.newContext({viewport:{width:1000,height:900}});
  await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'})); localStorage.setItem('i','1'); } });
  const p=await ctx.newPage(); p.on('dialog',d=>d.accept()); p.on('pageerror',e=>console.log('pageerror',e.message));
  await p.goto('http://localhost:8081/'); await p.waitForTimeout(7000);
  await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrEnter(); }); await p.waitForTimeout(1200);
  await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click());
  for(let i=0;i<20;i++){ await p.waitForTimeout(800); const ok=await p.evaluate(async()=>{ try{ const r=await window.sb.rpc('system_health',{p_token:KS.getManagerToken()}); return !!(r.data&&r.data.ok);}catch(e){return false;} }); if(ok) break; }
  await p.evaluate(()=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); try{gtWizardClose(true);}catch(e){} });
  await p.evaluate(()=>mgrTab('settings')); await p.waitForTimeout(1500);
  const shot=async(sel,name)=>{ await p.evaluate(sel=>{ const e=document.querySelector(sel); let d=e; while(d){ if(d.tagName==='DETAILS') d.open=true; d=d.parentElement; } e.scrollIntoView({block:'start'}); },sel); await p.waitForTimeout(1200); await p.screenshot({path:OUT+'/'+name}); };
  await p.evaluate(()=>{ KS.updateSettings({removedDefaults:['mk']}); mgrUpdateStatusToggles(); });
  await shot('#mgrStatusToggles','6-settings-statuses.png');
  console.log('optin seen by TL:', await p.evaluate(()=>JSON.stringify(KS.getSettings().statusOptIn)));
  console.log('restore btn rect:', await p.evaluate(()=>{ const x=[...document.querySelectorAll('#mgrStatusToggles button')].find(x=>/↩/.test(x.innerText)); let d=x; const ch=[]; while(d){ if(d.tagName==='DETAILS'){ ch.push((d.open?'open':'CLOSED')+':'+(d.getAttribute('data-g')||d.className)); d.open=true;} d=d.parentElement; } x.scrollIntoView({block:'center'}); const r=x.getBoundingClientRect(); return JSON.stringify({ch, r:[r.x,r.y,r.width,r.height]}); }));
  await p.waitForTimeout(800); await p.screenshot({path:OUT+'/6c-restore.png'});
  console.log('restore buttons:', await p.evaluate(()=>[...document.querySelectorAll('#mgrStatusToggles button')].filter(x=>/↩/.test(x.innerText)).map(x=>x.innerText)));
  await p.evaluate(()=>{ [...document.querySelectorAll('#mgrStatusToggles button')].find(x=>/↩/.test(x.innerText)).click(); });
  await p.waitForTimeout(800);
  console.log('after restore removedDefaults:', await p.evaluate(()=>JSON.stringify(KS.getSettings().removedDefaults)));
  await p.evaluate(()=>{ mgrAddStatus(); document.getElementById('newStatusHe').value='שחיטה מיוחדת'; document.getElementById('newStatusEn').value='Special'; });
  await shot('#mgrAddStatusForm','7-add-status.png');
  await p.evaluate(()=>{ document.getElementById('newStatusKosherYes').checked=true; mgrConfirmAddStatus(); });
  await p.waitForTimeout(1000);
  await p.evaluate(()=>{ try{mgrRenderPrintPreview();}catch(e){} });
  await shot('#previewKosherSticker','8-sticker-preview.png');
  // the sticker viewer: every status
  const html=await p.evaluate(()=>{ const out=[]; const keys=['glatt','beit','kosher','kosherRab','mk','rabChalak',(KS.getSettings().customStatuses||[]).slice(-1)[0].key]; const box=document.createElement('div'); box.id='stkTest'; box.style.cssText='position:fixed;inset:0;z-index:999999;background:#222;display:flex;flex-wrap:wrap;gap:12px;padding:16px;overflow:auto'; document.body.appendChild(box);
    keys.forEach((k,i)=>{ const d=document.createElement('div'); d.id='stk'+i; box.appendChild(d); renderSticker('stk'+i,0,'kosher',{status:k,num:7}); });
    const d=document.createElement('div'); d.id='stkL'; box.appendChild(d); renderSticker('stkL',0,'legs',{status:'slaughtered',num:7}); return box.innerText.replace(/\n/g,' ');});
  console.log('stickers text:', html);
  await p.waitForTimeout(800); await p.screenshot({path:OUT+'/9-stickers.png'});
  await b.close();
})();
