const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await browser.newContext({viewport:{width:1000,height:800}});
  await ctx.addInitScript(()=>{ if(!localStorage.getItem('i')){ localStorage.setItem('gt_plant_bound','1'); localStorage.setItem('ks_device_token','tok-outer-e2e-00000000000000001'); localStorage.setItem('ks_kiosk_role','outer'); localStorage.setItem('ks_kiosk_index','0'); localStorage.setItem('ks_device_id','e2e_outer_0001'); localStorage.setItem('i','1'); } });
  const p=await ctx.newPage(); await p.route('**/gt-config.js', r=>r.abort()); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); p.on('console',m=>{ if(/error|fail/i.test(m.text())) errs.push('console: '+m.text().slice(0,120)); });
  await p.goto('http://localhost:8080/'); 
  for(const t of [8,16,24]){ await p.waitForTimeout(8000); console.log(t+'s', JSON.stringify(await p.evaluate(()=>({missing:window._gtPlantConfigMissing, sb:!!window.sb, ok:window._gtNetOkAt||0, fail:window._gtNetFailAt||0, locked:!!window._gtNetLocked, txt:((document.getElementById("gtNetLock")||{}).innerText||"").slice(0,200), scr:(document.querySelector('.screen.active')||{}).id, boot:window._gtBootAt})))); }
  console.log(errs.slice(0,6).join('\n'));
  await browser.close();
})();
