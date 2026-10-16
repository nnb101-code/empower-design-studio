const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const {execSync}=require('child_process');
const W=(p,ms)=>p.waitForTimeout(ms); const cell=n=>`.screen.active .num-cell[data-idx="${n-1}"]`;
const q=s=>execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -At`,{input:s}).toString().trim();
const btns=p=>p.evaluate(()=>[...document.querySelectorAll('#decModal .dec-btns button')].map(b=>b.innerText.trim()+(b.dataset.decide?'['+b.dataset.decide+']':'')).join(' | '));
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'outer'), p=x.p; await W(p,1500);
 await p.evaluate(()=>outOpenDec(1)); await W(p,1000);
 console.log('#2 NC buttons:', await btns(p));
 await p.click('#decModal [data-decide="kosherPlain"]'); await W(p,3500);
 console.log('server #2:', q("select outer_status||' plain='||nc_plain||' printed_as='||_printed_as_key(a) from animals_pilot a where id=1"));
 console.log('label on outer:', await p.evaluate(()=>statusLabel(KS.getAnimal(1),'outer')), '| sticker key:', await p.evaluate(()=>_printedAsKey(KS.getAnimal(1))));
 await p.screenshot({path:'shots/nc33-after-plain.png'});
 // change to רבנות כשר
 await p.evaluate(()=>{ outPendingDec=1; rebuildOuterButtons(); document.getElementById('decModal').classList.add('open'); }); await W(p,500);
 console.log('change window buttons:', await btns(p));
 await p.click('#decModal [data-decide="kosher"]'); await W(p,3500);
 console.log('server #2 after change:', q("select outer_status||' plain='||nc_plain||' printed_as='||_printed_as_key(a) from animals_pilot a where id=1"));
 console.log('label:', await p.evaluate(()=>statusLabel(KS.getAnimal(1),'outer')));
 // routing switch (screen choice is the team leader's: set on the server)
 for(const v of [true,false]){ q(`update settings_pilot set settings = settings || '{"screenConfig":"1in2out","ncRouteB":${v}}'::jsonb, updated_at=now() where id=1`);
   await p.evaluate(()=>{try{_sbFetchSettingsSnapshot(true)}catch(e){}}); await W(p,4000);
   console.log('2 outer screens, ncRouteB='+v+': roles', await p.evaluate(()=>{const s=KS.getSettings();return [outRole(0),outRole(1),s.screenConfig,s.ncRouteB].join('/')})); }
 q(`update settings_pilot set settings = (settings - 'ncRouteB') || '{"screenConfig":"1in1out"}'::jsonb where id=1`);
 await x.ctx.close(); await b.close(); })();
