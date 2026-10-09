const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms);
const lab=(p,n)=>p.evaluate(n=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);return c.className.replace('num-cell','').trim()+':'+c.innerText.replace(/\n/g,' ');},n);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x=await open(b,'esophagus'), p=x.p;
 await p.evaluate(()=>{ gtUsdaStart('eso'); document.getElementById('gtHoldNum').value='2'; }); await W(p,300); await p.click('#gtUsdaOk'); await W(p,2000);
 console.log('esophagus #2:', await lab(p,2)); await x.ctx.close();
 for(const r of ['slaughter','legs']){ x=await open(b,r); p=x.p; await W(p,2500); console.log(r+' #2:', await lab(p,2)); await x.ctx.close(); }
 await b.close(); })();
