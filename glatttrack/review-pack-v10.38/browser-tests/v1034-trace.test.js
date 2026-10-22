const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -At`,{input:s}).toString().trim();
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const A=await open(b,'inner'), B=await open(b,'esophagus'); await A.p.waitForTimeout(2000);
 const call=(p,st,n)=>p.evaluate(([st,n])=>window.sb.rpc('hold_set',{p_id:n,p_station:st,p_kind:'usda',p_part:'whole',p_board:null,p_command_id:crypto.randomUUID()}).then(r=>r.data&&(r.data.ok?'ok':r.data.error)),[st,n]);
 let both=0, res=[];
 for(let n=0;n<15;n++){ const [x,y]=await Promise.all([call(A.p,'inner',n), call(B.p,'eso',n)]); res.push(x+'/'+y); if(x==='ok'&&y==='ok') both++; }
 console.log(res.join(' '));
 console.log('both succeeded:', both, '| numbers with 2 open whole holds:', q("select count(*) from (select animal_id from animal_holds where kind='usda' and part='whole' and resolved_at is null group by animal_id having count(*)>1) z"));
 await A.ctx.close(); await B.ctx.close(); await b.close(); })();
