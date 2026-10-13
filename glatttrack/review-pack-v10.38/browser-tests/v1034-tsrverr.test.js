const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process'); const q=s=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -At`,{input:s}).toString().trim();
const W=(p,ms)=>p.waitForTimeout(ms);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'inner'), p=x.p; await W(p,2500);
 await p.evaluate(()=>{ const orig=window.sb.rpc.bind(window.sb); window._errs=0;
   window.sb.rpc=(fn,args)=>{ if(fn==='animal_push' && (args.p_rows||[]).some(r=>r.id===1)){ window._errs++; return Promise.resolve({data:{ok:false,error:'server_error',id:1,message:'boom'},error:null}); } return orig(fn,args); };
   window.confirm=()=>true; KS.setInnerTreif(1,'x'); KS.setInnerTreif(2,'x'); });
 for(let k=0;k<12;k++){ await W(p,3000); await p.evaluate(()=>{ try{ KS._resaveQueue(); }catch(e){} }); if(q("select inner_status from animals_pilot where id=2")==='treif') break; }
 console.log('server errors seen:', await p.evaluate(()=>window._errs), '| #2 server:', q("select inner_status from animals_pilot where id=1"), '| #3 server:', q("select inner_status from animals_pilot where id=2"), '| pending:', await p.evaluate(()=>KS.pendingCount()));
 console.log('local #2:', await p.evaluate(()=>KS.getAnimal(1).innerStatus), '|', await p.evaluate(()=>[...document.querySelectorAll('#gtStatusBar .gt-srow')].map(r=>r.textContent).filter(t=>/#2/.test(t)).join(' / ')));
 await x.ctx.close(); await b.close(); })();
