const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const fs=require('fs');
const APP='/home/user/empower-design-studio/glatttrack/'+process.env.APP; const NOCFG=process.env.NOCFG==='1';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const ctx=await b.newContext({viewport:{width:1024,height:700}}); const ext=new Set();
 await ctx.route(u=>!/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\//.test(u.toString()), r=>{ ext.add(new URL(r.request().url()).host); /* no internet: hang */ });
 await ctx.route(u=>new URL(u).pathname==='/', r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync(APP)}));
 if(NOCFG) await ctx.route(u=>new URL(u).pathname==='/gt-config.js', r=>r.fulfill({status:404,body:'nf'}));
 await ctx.addInitScript(()=>{ window._gtLicShown=true; if(localStorage.getItem('i'))return; localStorage.setItem('ks_device_token','tok-demo-slaughter-000000000000000');localStorage.setItem('ks_kiosk_role','slaughter');localStorage.setItem('ks_kiosk_index','0');localStorage.setItem('ks_device_id','demo_slaughter');localStorage.setItem('i','1'); });
 const p=await ctx.newPage(); p.on('pageerror',e=>console.log('pageerror',e.message));
 await p.goto('http://localhost:8083/',{waitUntil:'commit'}); await p.waitForTimeout(+(process.env.WAIT||12000)); await p.screenshot({path:__dirname+"/shots/plant-"+process.env.NOCFG+".png"});
 const st=await p.evaluate(()=>({build:window.GT_BUILD, missing:!!window._gtPlantConfigMissing, sb:!!window.sb, screen:(document.querySelector('.screen.active')||{}).id,
   stop:(document.body.innerText.match(/[^\n]*gt-config[^\n]*/)||[''])[0].slice(0,120)}));
 let write='-'; if(!NOCFG){ await p.click('[onclick="slLogin()"]'); await p.waitForTimeout(1500); await p.click('#tSlBtnS'); await p.waitForTimeout(2500);
   write=require('child_process').execFileSync('psql',['-h','/tmp','-p','5433','-U','postgres','-d','gtapp','-Atc','select count(slaughter) from animals_pilot']).toString().trim(); }
 console.log(JSON.stringify(st), '| slaughtered on server:', write, '| outside hosts asked:', [...ext].join(', ')||'none');
 await b.close(); })();
