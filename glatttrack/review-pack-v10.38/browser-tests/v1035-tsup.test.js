const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const fs=require('fs');
const W=(p,ms)=>p.waitForTimeout(ms); const APP='/home/user/empower-design-studio/glatttrack/kosher-app-v10.34.html';
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 // 1) a tablet paired as "cooler" opens the cooler supervisor screen
 const C=await open(b,'legs','cooler'); await W(C.p,6000);
 console.log('1) active screen:', await C.p.evaluate(()=>document.querySelector('.screen.active').id), '| title:', await C.p.evaluate(()=>document.getElementById('supLTitle').textContent));
 await C.p.evaluate(()=>supLogin()); await W(C.p,800);
 console.log('2) after login:', await C.p.evaluate(()=>document.querySelector('.screen.active').id), '|', await C.p.evaluate(()=>document.getElementById('supTitle').textContent+' · '+document.getElementById('supBody').innerText.replace(/\s+/g,' ').slice(0,200)));
 await C.p.screenshot({path:__dirname+'/shots/sup-cooler.png'});
 await C.p.evaluate(()=>{ lang='en'; supRender(); supTitles(); }); console.log('3) EN title:', await C.p.evaluate(()=>document.getElementById('supTitle').textContent));
 console.log('4) plan slots:', await C.p.evaluate(()=>JSON.stringify(gtPlanSlots().filter(([r])=>GT_SUP_SCREENS[r]))));
 console.log('5) plan card:', await C.p.evaluate(async()=>{ lang='he'; let d=document.getElementById('mgrPlanCard'); if(!d){d=document.createElement('div');d.id='mgrPlanCard';document.body.appendChild(d);} _gtPlanDraft=null; await mgrRenderPlan(); return (d.textContent.match(/משגיח קולר.{0,30}|משגיח שיפינג.{0,10}/g)||[]).join(' | '); }));
 console.log('6) devices assign list:', await C.p.evaluate(()=>{ let d=document.getElementById('mgrScreenAssign'); if(!d){d=document.createElement('div');d.id='mgrScreenAssign';document.body.appendChild(d);} mgrRenderDevices(); return d.textContent.replace(/—[^—]*—/g,'').replace(/\s+/g,' ').trim(); }));
 await C.ctx.close();
 await b.close(); })();
