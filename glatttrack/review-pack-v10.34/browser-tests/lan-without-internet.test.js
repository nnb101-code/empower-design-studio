// A tablet at the plant: the plant server answers, the internet does not (mode: abort = no route, hang = no answer)
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs'); const {execFileSync}=require('child_process');
const Q=q=>execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc',q]).toString().trim();
const APP='/home/user/empower-design-studio/glatttrack/'+(process.env.APP||'kosher-app-v10.32.html'); const MODE=process.env.MODE||'abort';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const ctx=await b.newContext({viewport:{width:1024,height:700}}); const ext=new Set();
 await ctx.route(u=>!/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\//.test(u.toString()), r=>{ ext.add(new URL(r.request().url()).host); if(MODE==='abort') return r.abort('internetdisconnected'); /* hang: never answer */ });
 await ctx.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 await ctx.addInitScript(()=>{ window._gtLicShown=true; if(localStorage.getItem('i'))return; localStorage.setItem('ks_device_token','tok-demo-slaughter-000000000000000');localStorage.setItem('ks_kiosk_role','slaughter');localStorage.setItem('ks_kiosk_index','0');localStorage.setItem('ks_device_id','demo_slaughter');localStorage.setItem('i','1'); });
 const p=await ctx.newPage(); p.on('pageerror',e=>console.log('pageerror',e.message));
 const t0=Date.now(); await p.goto('http://localhost:8083/',{waitUntil:'commit'});
 // ready = the slaughter login button is on screen
 await p.waitForSelector('[onclick="slLogin()"]',{state:'visible',timeout:120000}); const tReady=Date.now()-t0;
 await p.waitForTimeout(3000);
 await p.click('[onclick="slLogin()"]'); await p.waitForTimeout(1500);
 const before=Q("select count(slaughter) from animals_pilot");
 for(let i=0;i<3;i++){ await p.click('#tSlBtnS'); await p.waitForTimeout(900); }
 await p.waitForTimeout(3000);
 const after=Q("select count(slaughter) from animals_pilot");
 const ok=await p.evaluate(async()=>{ const r=await window.sb.rpc('board_flags',{}); return !!(r.data); });
 const lock=await p.evaluate(()=>{ const e=[...document.querySelectorAll('.overlay.open,[id*=Lock]')].filter(x=>x.offsetParent).map(x=>x.id); return e.join(',')||'none'; });
 const font=await p.evaluate(()=>getComputedStyle(document.body).fontFamily);
 console.log(`MODE=${MODE} | app ready in ${(tReady/1000).toFixed(1)} s | slaughtered on server ${before}→${after} | board_flags ok=${ok} | lock overlays: ${lock} | font: ${font.slice(0,40)} | blocked hosts: ${[...ext].join(', ')}`);
 await b.close(); })();
