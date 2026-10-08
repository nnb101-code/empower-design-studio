const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const mk=async(extra)=>{ const ctx=await browser.newContext({viewport:{width:1000,height:800}}); await ctx.addInitScript(extra||(()=>{}));
    await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('ks_device_token','tok-outer-e2e-00000000000000001'); localStorage.setItem('ks_kiosk_role','outer'); localStorage.setItem('ks_kiosk_index','0'); localStorage.setItem('ks_device_id','e2e_outer_0001'); localStorage.setItem('ks_lang_by_screen',JSON.stringify({scOuter:'he',scOuterLogin:'he'})); localStorage.setItem('i','1'); } });
    const p=await ctx.newPage(); p.errs=[]; p.on('pageerror',e=>p.errs.push(e.message)); await p.goto('http://localhost:8080/'); await p.waitForTimeout(7000); return p; };
  const st=(p)=>p.evaluate(()=>({locked:!!window._gtNetLocked, text:(document.getElementById('gtNetLock')||{}).innerText?document.getElementById('gtNetLock').innerText.split('\n').filter(Boolean).slice(0,4).join(' / '):null}));
  // B4: the browser says "offline" (a plant LAN without internet) but the plant server answers
  let p=await mk(()=>{ Object.defineProperty(Navigator.prototype,'onLine',{get(){return false;}}); });
  for(const t of [10,25]){ await p.waitForTimeout(t===10?10000:15000); console.log('B4 browser says offline, server answers — '+t+' s:', JSON.stringify(await st(p))); }
  console.log('B4 errors:', p.errs.join(' | ')||'none'); await p.context().close();
  // A7: this tablet worked with a plant server before; now gt-config.js is missing → no cloud, stopped
  p=await mk(()=>{ try{ localStorage.setItem('gt_plant_bound','1'); }catch(e){} });
  await p.waitForTimeout(15000);
  console.log('A7 bound tablet, no plant config — 22 s:', JSON.stringify(await st(p)), '| asks the cloud:', await p.evaluate(()=>performance.getEntriesByType('resource').some(e=>/supabase\.co\/rest/.test(e.name))));
  console.log('A7 errors:', p.errs.join(' | ')||'none'); await p.context().close();
  await browser.close();
})();
