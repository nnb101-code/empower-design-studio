const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync('psql -h /tmp -p 5433 -U postgres -d gtapp -At',{input:s}).toString().trim();
const MT=process.env.MT;
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const L=await open(b,'legs'); await L.p.waitForTimeout(1500);
 // the team leader's call (as the app makes it) — first a new worker with a code, then the same code for another → refused
 const r1=await L.p.evaluate(async(t)=>{ const r=await window.sb.rpc('worker_code_set',{p_token:t,p_role:'legs',p_name:'רגליים בדיקה',p_code:'4321'}); return JSON.stringify(r.data||r.error); }, MT);
 const r2=await L.p.evaluate(async(t)=>{ const r=await window.sb.rpc('worker_code_set',{p_token:t,p_role:'legs',p_name:'רגליים שני',p_code:'4321'}); return JSON.stringify(r.data||r.error); }, MT);
 console.log('1) set code:', r1, '| same code for another:', r2);
 // what a tablet can read
 await L.p.waitForTimeout(500);
 const rd=await L.p.evaluate(async()=>{ const r=await window.sb.from('settings_pilot').select('settings').eq('id',1).maybeSingle(); const u=(r.data.settings.users||[]); return JSON.stringify(u.filter(x=>x.role==='legs')); });
 console.log('2) the tablet reads:', rd, '| worker_codes direct read:', await L.p.evaluate(async()=>{ const r=await window.sb.from('worker_codes').select('*'); return r.error? 'refused ('+(r.error.code||'')+')' : 'ROWS '+JSON.stringify(r.data); }));
 // the worker logs in with the code
 q("update settings_pilot set settings = settings || '{\"loginModeByRole\":{\"legs\":\"code\"}}'::jsonb, updated_at=now(), device_id='server' where id=1");
 const lg=await L.p.evaluate(async()=>{ const r=await window.sb.rpc('worker_login',{p_role:'legs',p_code:'4321'}); const w=await window.sb.rpc('worker_login',{p_role:'legs',p_code:'9999'}); return JSON.stringify({ok:r.data&&r.data.ok, name:r.data&&r.data.name, wrong:w.data&&w.data.error}); });
 console.log('3) worker login:', lg);
 q("update settings_pilot set settings = settings || '{\"loginModeByRole\":{\"legs\":\"none\"}}'::jsonb, updated_at=now() where id=1");
 await b.close(); })();
