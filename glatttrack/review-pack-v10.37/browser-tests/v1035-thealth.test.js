const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const L=await open(b,'legs','x'); await L.p.waitForTimeout(4000);
 const run=role=>L.p.evaluate(role=>{ lang='he';
   KS.getManagerToken=()=>'t'; KS.getManagerRole=()=>role;
   window._gtHealth={ok:true, attention:['devices_offline','rollover_waiting','standby_down','nightly_check_problems'], devices:{active:7,offline:1}, testMode:{on:false}, eventChain:{ok:true,checked:5,total:5}, security:{}, backup:{status:'ok',ageHours:3}, server:{name:'A'}, nightly:{at:new Date().toISOString(),problems:['שרת הגיבוי לא עונה'],fixed:[]}};
   let d=document.getElementById('mgrHealth'); if(!d){ d=document.createElement('div'); d.id='mgrHealth'; document.body.appendChild(d); }
   mgrRenderHealth(); return d.innerText.replace(/\n+/g,' | '); }, role);
 console.log('TEAM LEADER :', await run('manager'));
 console.log('');
 console.log('MANUFACTURER:', await run('manufacturer'));
 await b.close(); })();
