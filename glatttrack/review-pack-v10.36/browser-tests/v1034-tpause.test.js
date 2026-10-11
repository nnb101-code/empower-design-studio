const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -At`,{input:s}).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
const cells=(p,n)=>p.evaluate(n=>[...Array(n).keys()].map(i=>{const c=document.querySelector(`.screen.active .num-cell[data-idx="${i}"]`);return (i+1)+':'+(c.innerText.replace(/\s+/g,' ').replace(/^\d+ ?/,'')||'—')+(c.className.includes('next')?'*':'');}).join(' | '),n);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const L=await open(b,'legs'); await W(L.p,2500);
 console.log('one screen, legs off → role:', await L.p.evaluate(()=>_lgRole()), '| title:', await L.p.evaluate(()=>(document.getElementById('lgRoleLbl')||{}).textContent));
 console.log('grid:', await cells(L.p,3));
 await L.p.evaluate(()=>lgTap(0)); await W(L.p,2500);
 console.log('server #1:', q("select legs_stickers||'/'||head_stickers from animals_pilot where id=0"));
 // split + legs off: the legs tablet shows "off"
 q(`update settings_pilot set settings = settings || '{"legsHeadSplit":true}'::jsonb where id=1`);
 await L.p.evaluate(()=>{ const g=KS.getSettings; KS.getSettings=()=>Object.assign({},g(),{legsHeadSplit:true}); lgInstance=0; lgRenderGrid(); }); await W(L.p,1500);
 console.log('split, legs tablet:', await L.p.evaluate(()=>_lgRole()), '| overlay:', await L.p.evaluate(()=>{const o=document.getElementById('gtPausedOv');return o&&o.style.display!=='none'?o.innerText.split('\n')[1]:'none';}));
 // switch legs on again (as the team leader does) → from the first number without head stickers
 await L.p.evaluate(()=>{ KS.getSettings=KS.getSettings; });
 await L.ctx.close();
 q(`update settings_pilot set settings = (settings - 'legsHeadSplit') || '{"legsPaused":false,"legsFromIdx":1}'::jsonb || jsonb_build_object('legsFromReset', settings->>'lastServerResetAt') where id=1`);
 const L2=await open(b,'legs'); await W(L2.p,2500);
 console.log('legs on again (from #2), one screen:', await L2.p.evaluate(()=>_lgRole()), '| grid:', await cells(L2.p,3));
 await L2.p.evaluate(()=>lgTap(1)); await W(L2.p,2500);
 console.log('#2 after one tap (needs legs):', q("select legs_stickers||'/'||head_stickers from animals_pilot where id=1"));
 await L2.ctx.close(); await b.close(); })();
