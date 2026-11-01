const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const L=await open(b,'legs'); await W(L.p,1500);
 await L.ctx.unrouteAll({behavior:'ignoreErrors'});
 const got=await L.p.evaluate(async()=>{ const r=await fetch(location.pathname+'?gtv='+Date.now(),{cache:'no-store'}); const t=await r.text(); return (t.match(new RegExp("var GT_APP_VERSION='([a-z][0-9][^']*)';"))||[])[1]; });
 console.log('the server now serves:', got);
 await L.p.evaluate(()=>{ _gtLastTouch=Date.now(); }); await L.p.evaluate(()=>_gtUpdCheck()); await W(L.p,1500);
 console.log('in use → window:', await L.p.evaluate(()=>!!document.getElementById('gtUpdModal')), '| offered:', await L.p.evaluate(()=>_gtUpd.ver), '| running:', await L.p.evaluate(()=>GT_APP_VERSION));
 // and the same version → nothing
 await L.p.evaluate(()=>{ document.getElementById('gtUpdModal')?.remove(); _gtUpd.offered=false; _gtUpd.ver=null; GT_APP_VERSION='v10.99'; }); await L.p.evaluate(()=>_gtUpdCheck()); await W(L.p,1000);
 console.log('same version → no window:', await L.p.evaluate(()=>!document.getElementById('gtUpdModal') && !_gtUpd.offered));
 await b.close(); })();
