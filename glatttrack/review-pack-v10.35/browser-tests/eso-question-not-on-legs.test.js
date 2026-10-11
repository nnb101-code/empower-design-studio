// the legs tablet still thinks #4 passed the esophagus (esoChecked true on the tablet), the server has an open esophagus "?"
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x=await open(b,'esophagus'), p=x.p;
 for(const n of [1,2,3]){ await p.click(cell(n)); await W(p,700); await p.click(`[onclick="esoDecide('ok')"]`); await W(p,900); }
 await p.click('#scEsophagus .gt-tbq'); await W(p,2500); await x.ctx.close();
 x=await open(b,'legs'); p=x.p; p.on('pageerror',e=>console.log('ERR',e.message)); await W(p,2500);
 await p.evaluate(()=>{ const a=KS.getAnimal(3); a.esoChecked=true; a.esoResult='ok'; lgRenderGrid(); });   // the stale state
 const show=()=>p.evaluate(()=>[0,1,2,3,4].map(i=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${i}"]`);return c.className.replace('num-cell','').trim()+':'+c.innerText.replace(/\n/g,' ');}).join(' | '));
 console.log('legs:', await show());
 for(const n of [1,2,3]){ await p.click(cell(n)); await W(p,600); await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'))); await p.click(cell(n)); await W(p,600); await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'))); }
 await p.click(cell(4)); await W(p,800);
 console.log('after 1-3 printed, tap #4 → head/legs printed?', await p.evaluate(()=>{const a=KS.getAnimal(3);return !!(a.legsStickers||a.headStickers);}), '| next blinking:', await p.evaluate(()=>{const c=document.querySelector('.screen.active .num-cell.next');return c?+c.dataset.idx+1:'none';}));
 console.log('legs now:', await show());
 await x.ctx.close(); await b.close(); })();
