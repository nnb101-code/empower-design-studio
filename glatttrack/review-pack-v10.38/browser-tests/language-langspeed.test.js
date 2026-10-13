const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const ctx=await b.newContext({viewport:{width:1024,height:900}});
  await ctx.route(u=>new URL(u).pathname==='/',r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(process.env.APP)}));
  await ctx.addInitScript(()=>{window._gtLicShown=true;if(localStorage.getItem('i'))return;localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'}));localStorage.setItem('i','1');});
  const p=await ctx.newPage(); p.on('dialog',d=>d.accept()); await p.goto('http://localhost:8083/'); await W(p,6000);
  await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));mgrEnter();}); await W(p,1000);
  await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await W(p,9000);
  await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));try{gtWizardClose(true);}catch(e){}}); await W(p,1500);
  for(const tab of ['monitor','analysis','settings']){
    await p.evaluate(t=>mgrTab(t), tab); await W(p,1200);
    const ms=await p.evaluate(()=>{ const t=[]; for(let i=0;i<3;i++){ const a=performance.now(); cycleLang(); t.push(Math.round(performance.now()-a)); } return t; });
    console.log('TL', tab, 'switch ms:', ms.join(' / '));
  }
  await ctx.close();
  for(const r of ['slaughter','inner','parts']){ const x=await open(b,r); const ms=await x.p.evaluate(()=>{ const t=[]; for(let i=0;i<3;i++){ const a=performance.now(); cycleLang(); t.push(Math.round(performance.now()-a)); } return t; }); console.log(r,'switch ms:', ms.join(' / ')); await x.ctx.close(); }
  await b.close(); })();
