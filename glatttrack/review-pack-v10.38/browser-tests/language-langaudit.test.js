// switch every screen to English: what is still Hebrew right away, and what changes later by itself
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const fs=require('fs');
const APP=process.env.APP; const W=(p,ms)=>p.waitForTimeout(ms);
const SCAN=()=>{ const out=new Set(); const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT); let n;
  while(n=w.nextNode()){ const t=n.nodeValue.trim(); if(!/[֐-׿]/.test(t)) continue; const p=n.parentElement; if(!p||p.closest('[data-no-i18n],script,style')) continue;
    const r=p.getBoundingClientRect(); if(!r.width||!r.height) continue; const cs=getComputedStyle(p); if(cs.visibility==='hidden'||cs.display==='none') continue;
    let e=p,vis=true; while(e){ if(getComputedStyle(e).display==='none'){vis=false;break;} e=e.parentElement; } if(!vis) continue;
    out.add(t.slice(0,80)); }
  return [...out]; };
async function toEn(p){ for(let k=0;k<4;k++){ const l=await p.evaluate(()=>lang); if(l==='en') return; await p.evaluate(()=>cycleLang()); await W(p,150);} }
async function audit(p, name){
  await toEn(p); await W(p,400); const a=await p.evaluate(SCAN);
  await W(p,70000); const b=await p.evaluate(SCAN);
  const late=a.filter(x=>!b.includes(x)), stay=b;
  console.log(`\n=== ${name}: right away ${a.length} Hebrew · fixed by itself later ${late.length} · still Hebrew ${stay.length}`);
  if(late.length) console.log('  LATE:', JSON.stringify(late));
  if(stay.length) console.log('  STAY:', JSON.stringify(stay));
}
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const which=(process.env.ONLY||'tl,slaughter,esophagus,legs,inner,outer,parts,stamps').split(',');
 if(which.includes('tl')){
  const ctx=await b.newContext({viewport:{width:1024,height:900}});
  await ctx.route(u=>new URL(u).pathname==='/',r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
  await ctx.addInitScript(()=>{window._gtLicShown=true;if(localStorage.getItem('i'))return;localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'}));localStorage.setItem('i','1');});
  const p=await ctx.newPage(); p.on('dialog',d=>d.accept()); await p.goto('http://localhost:8083/'); await W(p,6000);
  await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));mgrEnter();}); await W(p,1000);
  await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await W(p,9000);
  await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));try{gtWizardClose(true);}catch(e){}}); await W(p,1500);
  for(const tab of ['monitor','analysis','search','settings','issues']){
    await p.evaluate(()=>{ if(lang!=='he'){ while(lang!=='he') cycleLang(); } });
    await p.evaluate(t=>{ document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')); mgrTab(t); if(t==='settings') document.querySelectorAll('#mgr-settings details').forEach(d=>d.open=true); }, tab); await W(p,1500);
    await audit(p,'TL '+tab);
  }
  await ctx.close();
 }
 for(const r of ['slaughter','esophagus','legs','inner','outer','parts','stamps']){ if(!which.includes(r)) continue;
   const x=await open(b,r); await audit(x.p,r); await x.ctx.close(); }
 await b.close(); })();
