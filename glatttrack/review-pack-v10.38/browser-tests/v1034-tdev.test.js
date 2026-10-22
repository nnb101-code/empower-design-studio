const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'legs'), p=x.p; await p.waitForTimeout(2000);
 console.log(await p.evaluate(()=>{ const g=KS.getSettings; const extra={legsHeadSplit:true,legsMode:true,printers:[{id:'p1',name:'Zebra רגליים',conn:'wifi'},{id:'p2',name:'Zebra ראש',conn:'wifi'}],scanners:[{id:'s1',name:'סורק ראש',conn:'bt'}],screenDevices:{legs:{printer:'p1',scanner:''},head:{printer:'p2',scanner:'s1'}}};
   KS.getSettings=()=>Object.assign({},g(),extra);
   const out=[]; lgInstance=0; renderScreenDeviceStatus(); out.push('legs: '+document.getElementById('devStatus-legs').innerText.replace(/\s+/g,' '));
   lgInstance=1; renderScreenDeviceStatus(); out.push('head: '+document.getElementById('devStatus-legs').innerText.replace(/\s+/g,' '));
   mgrRenderDevices(); const d=document.getElementById('mgrScreenAssign'); out.push('TL rows: '+[...d.children].map(c=>c.firstElementChild.textContent).join(', '));
   return out.join('\n'); }));
 await x.ctx.close(); await b.close(); })();
