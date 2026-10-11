const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms);
const bars=p=>p.evaluate(()=>[...document.querySelectorAll('#gtStatusBar .gt-srow')].map(r=>r.textContent).filter(t=>!/📅/.test(t)).join(' / '));
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'}); const x=await open(b,'outer'), p=x.p; await W(p,3000);
 console.log('scan setting:', await p.evaluate(()=>KS.getSettings().scanInOut), '| button:', await p.evaluate(()=>{const b=document.querySelector('.screen.active [data-gt-scan]');return b?b.textContent+' '+b.style.display:'none';}));
 // hand scanner types the code of #4 (out of order: #1 is next)
 await p.keyboard.type('BH|N:4|D:2026-10-09|S:'); await p.keyboard.press('Enter'); await W(p,800);
 console.log('after hand scan:', await p.evaluate(()=>document.getElementById('decModal').classList.contains('open')+' #'+(outPendingDec+1)));
 await p.evaluate(()=>{ try{ outCancelDec(); }catch(e){} });
 // the camera sheet → type 7 (not through inner) 
 await p.evaluate(()=>gtScanOpen('outer')); await W(p,500);
 await p.fill('#gtHoldNum','8'); await p.click('#gtSheet button:has-text("פתח")'); await W(p,500);
 console.log('typed 8:', await bars(p));
 await x.ctx.close(); await b.close(); })();
