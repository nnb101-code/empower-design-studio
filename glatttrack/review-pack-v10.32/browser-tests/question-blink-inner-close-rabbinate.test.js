const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const {execFileSync}=require('child_process');
const Q=q=>execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc',q]).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
const at=p=>p.evaluate(()=>[...document.querySelectorAll('#rumenModal.open,#mawModal.open,#lungModal.open')].map(o=>o.id).join(',')||'-');
const blink=(p,n)=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return c?c.className+' anim='+getComputedStyle(c).animationName:'none'},n);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 Q(`update settings_pilot set settings = settings || '{"rumenCheck":true,"floatsEnabled":true,"lungEnabled":true}'::jsonb`);
 let x=await open(b,'slaughter'), p=x.p;
 console.log('slaughter top bar:', JSON.stringify(await p.evaluate(()=>document.querySelector('#scSlaughter .gt-tb')?.innerText)));
 for(let i=0;i<6;i++){await p.click('#tSlBtnS');await W(p,900);} await x.ctx.close();
 x=await open(b,'esophagus'); p=x.p; for(const n of [1,2,3,4,5,6]){await p.click(cell(n));await W(p,700);await p.click(`[onclick="esoDecide('ok')"]`);await W(p,900);} await x.ctx.close();
 x=await open(b,'inner'); p=x.p;
 for(const w of ['rumen','maw','lung']){
   const n=await p.evaluate(()=>+document.querySelector('#inGrid .num-cell.next')?.dataset.idx+1);
   await p.click(cell(n)); await W(p,1000);
   if(w!=='rumen' && (await at(p))==='rumenModal'){ await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900); }
   if(w==='lung'){ if((await at(p))==='mawModal'){ await p.click(`#mawModal [onclick*="mawDecide"]`).catch(()=>{}); await W(p,900);} 
      if((await at(p))!=='lungModal'){ await p.evaluate(n=>inOpenLung(n-1),n); await W(p,900);} }
   const before=await at(p); const id={rumen:'#gtQRumen',maw:'#gtQMaw',lung:'#gtQLung'}[w];
   await p.click(id); await W(p,2500);
   console.log(`#${n} ? on ${w} (was in ${before}) → open now: ${await at(p)} | floats: ${await p.evaluate(()=>inFloats.map(f=>f.idx+1).join(','))} | ${await blink(p,n)}`);
 }
 // resume: tap #1 (rumen "?") → rumen window opens
 await p.click(cell(1)); await W(p,1200); console.log('tap #1 again →', await at(p));
 await p.screenshot({path:__dirname+'/shots/v1031-inner.png'}); await x.ctx.close();
 // rabbinate screen: 2 outer screens + not-chalak
 Q(`update settings_pilot set settings = settings || '{"screenConfig":"1in2out","notChalakEnabled":true}'::jsonb`);
 x=await open(b,'outer'); p=x.p;
 await p.evaluate(()=>{goTo('scNav');}); await W(p,500); await p.evaluate(()=>outLogin(1)); await W(p,2000);
 console.log('outer instance', await p.evaluate(()=>outInstance+' role='+outRole(outInstance)+' title='+document.getElementById('outRoleTitle').innerText));
 console.log('rabbinate top bar:', JSON.stringify(await p.evaluate(()=>document.querySelector('#scOuter .gt-tb')?.innerText)));
 console.log('decision window has ?:', await p.evaluate(()=>!!document.getElementById('gtQOuter')));
 console.log('blink on outer grid for "?" numbers:', await p.evaluate(()=>[...document.querySelectorAll('#scOuter .num-cell.gt-q,#scOuter .num-cell.gt-qb')].map(c=>c.dataset.idx*1+1+':'+getComputedStyle(c).animationName).join(' ')));
 await p.screenshot({path:__dirname+'/shots/v1031-rabbinate.png'});
 Q(`update settings_pilot set settings = settings || '{"screenConfig":"1in1out","notChalakEnabled":false}'::jsonb`);
 await b.close(); })();
