const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js');
const W=(p,ms)=>p.waitForTimeout(ms);
const scr=p=>p.evaluate(()=>(document.querySelector('.screen.active')||{}).id);
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const L=await open(b,'legs'); await W(L.p,1500);
 console.log('A0) working on:', await scr(L.p));
 await L.p.evaluate(()=>{ window.__mark=1; _gtLastTouch=Date.now(); window.gtUpdateOffer('v10.99'); }); await W(L.p,500);
 console.log('A1) in use → window shown:', await L.p.evaluate(()=>!!document.getElementById('gtUpdModal')), '| still same page:', await L.p.evaluate(()=>window.__mark===1));
 await L.p.click('#gtUpdLater'); await W(L.p,300);
 console.log('A2) "later" → window gone:', await L.p.evaluate(()=>!document.getElementById('gtUpdModal')));
 await L.p.evaluate(()=>{ _gtLastTouch=Date.now()-11*60*1000; }); await W(L.p,33000);
 console.log('A3) 10 min without a touch → updated (reloaded):', await L.p.evaluate(()=>window.__mark===undefined), '| back on:', await scr(L.p));
 // B) the tablet sitting on its login screen → at once
 await L.p.evaluate(()=>{ goTo('scLegsLogin'); window.__mark=2; window.gtUpdateOffer('v10.99'); }); await W(L.p,4000);
 console.log('B) not in use → updated at once:', await L.p.evaluate(()=>window.__mark===undefined), '| on:', await scr(L.p));
 // C) "update now" with something waiting to be sent → sent first, then reload, back to work
 await L.p.evaluate(()=>{ lgLogin(); }); await W(L.p,800);
 await L.p.evaluate(()=>{ window.__mark=3; _gtLastTouch=Date.now(); KS.setLegsStickers(4); window.gtUpdateOffer('v10.99'); }); await W(L.p,300);
 await L.p.click('#gtUpdNow'); await W(L.p,8000);
 console.log('C) "update now" → reloaded:', await L.p.evaluate(()=>window.__mark===undefined), '| on:', await scr(L.p), '| #5 legs on the tablet:', await L.p.evaluate(()=>KS.getAnimal(4).legsStickers));
 await b.close(); })();
