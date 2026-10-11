const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const fs=require('fs');
const W=(p,ms)=>p.waitForTimeout(ms);
const SCAN=()=>{ const out=new Set(); const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT); let n;
  while(n=w.nextNode()){ const t=n.nodeValue.trim(); if(!/[֐-׿]/.test(t)) continue; const p=n.parentElement; if(!p||p.closest('[data-no-i18n],script,style')) continue;
    const r=p.getBoundingClientRect(); if(!r.width||!r.height) continue; let e=p,vis=true; while(e){ const cs=getComputedStyle(e); if(cs.display==='none'||cs.visibility==='hidden'){vis=false;break;} e=e.parentElement; } if(!vis) continue; out.add(t); }
  return [...out].filter(x=>!['גלאט','בית יוסף','כשר','טרף','רבנות חלק','רבנות כשר','לא חלק','MK','כ״ז בתשרי תשפ״ז'].includes(x)); };
const en=async p=>{ for(let k=0;k<4;k++){ if(await p.evaluate(()=>lang)==='en') return; await p.evaluate(()=>cycleLang()); await W(p,100);} };
const LOGIN={slaughter:'scSlaughterLogin',esophagus:'scEsophagusLogin',legs:'scLegsLogin',inner:'scInnerLogin',outer:'scOuterLogin',parts:'scPartsLogin',stamps:'scStampsLogin'};
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const res={};
 for(const r of Object.keys(LOGIN)){
   const x=await open(b,r); const p=x.p;
   await p.evaluate(id=>goTo(id), LOGIN[r]); await W(p,800); await en(p); await W(p,300); res[r+' login']=await p.evaluate(SCAN);
   await p.evaluate(()=>{ while(lang!=='he') cycleLang(); });
   await p.evaluate(r=>({slaughter:slLogin,esophagus:esoLogin,legs:lgLogin,inner:()=>inLogin(),outer:()=>outLogin(),parts:partsLogin,stamps:stampsLogin})[r](), r); await W(p,1200);
   await en(p); await W(p,300);
   // windows of the station
   const st={slaughter:'slaughter',esophagus:'eso',legs:'legs',inner:'inner',outer:'outer',parts:'parts',stamps:'stamps'}[r];
   await p.evaluate(st=>gtUsdaStart(st), st); await W(p,400); res[r+' USDA window']=await p.evaluate(SCAN); await p.evaluate(()=>gtSheetClose());
   await p.evaluate(st=>gtHeldList(st), st); await W(p,400); res[r+' held list']=await p.evaluate(SCAN); await p.evaluate(()=>gtSheetClose());
   if(r==='esophagus'){ await p.evaluate(()=>esoOpenDec(0)); await W(p,400); res['eso decision']=await p.evaluate(SCAN); await p.evaluate(()=>{document.getElementById('esoModal').style.display='none';}); }
   if(r==='inner'){ for(const m of ['rumenModal','mawModal','lungModal']){ await p.evaluate(m=>{ try{ if(m==='mawModal') openMawWindow(0); else if(m==='lungModal') inOpenLung(0); else { document.getElementById('rumenNum').textContent='#1'; document.getElementById('rumenModal').classList.add('open'); } }catch(e){} }, m); await W(p,500); res['inner '+m]=await p.evaluate(SCAN); await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'))); } }
   if(r==='outer'){ await p.evaluate(()=>{ try{ outPendingDec=0; rebuildOuterButtons(); document.getElementById('decModal').classList.add('open'); }catch(e){} }); await W(p,400); res['outer decision']=await p.evaluate(SCAN); await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'))); }
   res[r+' screen']=await p.evaluate(SCAN);
   await x.ctx.close();
 }
 for(const [k,v] of Object.entries(res)) console.log(k.padEnd(22), v.length, v.length?JSON.stringify(v).slice(0,600):'');
 await b.close(); })();
