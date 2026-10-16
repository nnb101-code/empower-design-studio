const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'inner'), p=x.p; await p.waitForTimeout(2500);
 console.log('inner cells 1-4:', await p.evaluate(()=>[0,1,2,3].map(i=>(i+1)+':'+(document.querySelector(`.screen.active .num-cell[data-idx="${i}"]`).innerText.replace(/\s+/g,' ').replace(/^\d+ ?/,'')||'—')).join(' | ')));
 await x.ctx.close(); await b.close(); })();
