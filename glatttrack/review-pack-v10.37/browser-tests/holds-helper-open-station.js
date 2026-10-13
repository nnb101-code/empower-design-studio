const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs');
const APP='/home/user/empower-design-studio/glatttrack/kosher-app-v10.26.html'; const OUT=__dirname+'/shots/';
const SCR=['Slaughter','Esophagus','Legs','Inner','Outer','Parts','Stamps'];
const DEV={slaughter:['demo_slaughter','tok-demo-slaughter-000000000000000','slLogin'],esophagus:['demo_esophagus','tok-demo-esophagus-000000000000000','esoLogin'],
 legs:['demo_legs','tok-demo-legs-000000000000000','lgLogin'],inner:['demo_inner','tok-demo-inner-000000000000000','inLogin'],outer:['e2e_outer_0001','tok-outer-e2e-00000000000000001','outLogin'],
 parts:['e2e_parts_0001','tok-demo-parts-0000000000000000','partsLogin'],stamps:['e2e_stamps_001','tok-demo-stamps-000000000000000','stampsLogin']};
module.exports.open=async function(b,role){ const [id,tok,lg]=DEV[role];
 const ctx=await b.newContext({viewport:{width:1024,height:700},deviceScaleFactor:1.5});
 await ctx.route(u=>new URL(u).pathname==='/',r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 await ctx.addInitScript(([id,tok,role,scr])=>{window._gtLicShown=true; if(localStorage.getItem('i'))return; localStorage.setItem('ks_device_token',tok);localStorage.setItem('ks_kiosk_role',role);localStorage.setItem('ks_kiosk_index','0');localStorage.setItem('ks_device_id',id);
   const m={};scr.forEach(s=>{m['sc'+s]='he';m['sc'+s+'Login']='he';});localStorage.setItem('ks_lang_by_screen',JSON.stringify(m));localStorage.setItem('i','1');},[id,tok,role,SCR]);
 const p=await ctx.newPage(); p.on('dialog',d=>d.accept()); p.on('pageerror',e=>console.log('pageerror',role,e.message));
 await p.goto('http://localhost:8083/'); await p.waitForTimeout(6000);
 await p.click(`[onclick="${lg}()"]`); await p.waitForTimeout(1800); return {ctx,p}; };
if(require.main===module)(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 for(const r of Object.keys(DEV)){ const {ctx,p}=await module.exports.open(b,r); await p.screenshot({path:OUT+r+'.png'});
   console.log(r, await p.evaluate(()=>{const s=document.querySelector('.screen.active');return s.id+' | '+[...s.querySelectorAll('button[id],div[id]')].filter(e=>e.offsetParent).map(e=>e.id).slice(0,40).join(',');})); await ctx.close(); }
 await b.close(); })();
