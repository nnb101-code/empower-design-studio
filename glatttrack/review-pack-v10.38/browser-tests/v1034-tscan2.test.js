const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'inner'), p=x.p; await W(p,3000);
 await p.keyboard.type('BH|N:5|D:2026-10-09'); await p.keyboard.press('Enter'); await W(p,1500);
 console.log('inner after scan #5:', await p.evaluate(()=>[...document.querySelectorAll('.overlay.open,[id$=Modal].open')].map(e=>e.id).join(',')), await p.evaluate(()=>JSON.stringify(inFloats.map(f=>f.idx+1))));
 await x.ctx.close(); await b.close(); })();
