const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const x=await open(b,'inner'), p=x.p; p.on('pageerror',e=>console.log('ERR',e.message));
 // a list left by an older version on number 2: rumen, maw, lung
 await p.evaluate(()=>{ const m=JSON.parse(localStorage.getItem('gt_inner_qsteps')||'{}'); m[String(_gtFlags.epoch||'')+':1']=['rumen','maw','lung']; localStorage.setItem('gt_inner_qsteps',JSON.stringify(m)); });
 // number 1: rumen kosher, then "?" in the maw window
 await p.click(cell(1)); await W(p,1000); if(await p.locator('#rumenModal.open').count()){ await p.click(`#rumenModal [onclick="rumenDecide('k')"]`); await W(p,900); }
 await p.click('#gtQMaw'); await W(p,2500);
 // number 2 gets a hold so its label shows
 await p.evaluate(()=>gtHoldPut(1,'inner','question','whole')); await W(p,2500);
 const lab=n=>p.evaluate(n=>document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`)?.innerText.replace(/\n/g,' '),n);
 console.log('#1:', await lab(1)); console.log('#2 (old list):', await lab(2));
 await x.ctx.close(); await b.close(); })();
