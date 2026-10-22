// Real app screens + the proposed "?" question and USDA HOLD drawn into them (design only, not working yet)
const { chromium } = require('/opt/node22/lib/node_modules/playwright'); const {open}=require('./explore.js'); const fs=require('fs');
const OUT=__dirname+'/out2/'; require('fs').mkdirSync(OUT,{recursive:true}); const W=(p,ms)=>p.waitForTimeout(ms);
const KIT=()=>{ if(window.MK)return;
 const css=document.createElement('style'); css.textContent=`
 .mkQ{background:#FFC400!important;border-color:#FFE57F!important;color:#000!important;position:relative}
 .mkQ .cn,.mkQ .cl{color:#000!important}
 .mkU{background:#6A3FB5!important;border-color:#C5B3FF!important;color:#fff!important;position:relative}
 .mkU .cn,.mkU .cl{color:#fff!important}
 .mkBadge{position:absolute;top:4px;left:6px;font:900 22px Arial;line-height:1}
 .mkCur{animation:none!important;background:#fff!important;color:#000!important;border:4px solid #fff!important;box-shadow:0 0 0 4px #D000FF,0 0 30px 8px rgba(208,0,255,.7)!important}
 .mkCur .cn,.mkCur .cl{color:#000!important}
 .mkNew{outline:3px dashed #00E5FF!important;outline-offset:5px}
 .mkPill{position:fixed;z-index:2147483640;background:#00E5FF;color:#000;font:800 13px Arial;border-radius:10px;padding:2px 8px;pointer-events:none}
 #mkCap{position:fixed;left:50%;bottom:12px;transform:translateX(-50%);z-index:2147483647;max-width:94%;background:rgba(10,14,24,.95);color:#fff;border:2px solid #E8B84A;border-radius:14px;padding:8px 18px;font:700 19px/1.4 Arial;text-align:center;direction:rtl}
 #mkTitle{position:fixed;right:12px;top:-2px;z-index:2147483647;background:#00E5FF;color:#000;font:800 14px Arial;border-radius:0 0 10px 10px;padding:3px 12px;direction:rtl}
 .mkSheetBg{position:fixed;inset:0;background:rgba(0,0,0,.66);z-index:2147483000;display:flex;align-items:center;justify-content:center}
 .mkSheet{background:#111827;border:3px solid #D4A843;border-radius:18px;padding:22px 26px;min-width:440px;max-width:760px;text-align:center;direction:rtl;color:#fff;font-family:Arial}
 .mkSheet h3{margin:0;color:#E8B84A;font-size:30px}.mkSheet .sub{font-size:20px;margin:6px 0 16px}
 .mkB{display:inline-block;min-width:150px;margin:6px;padding:14px 16px;border-radius:12px;border:2px solid;font:700 19px Arial;background:transparent}
 .mkRow{display:flex;justify-content:space-between;align-items:center;background:#1c2433;border-radius:10px;padding:8px 12px;margin:6px 0;font-size:18px;gap:14px}
 `; document.head.appendChild(css);
 const MK=window.MK={};
 MK.cell=(n)=>document.querySelector(`.screen.active .num-cell[data-idx="${n-1}"]`);
 MK.q=(n,label)=>{const c=MK.cell(n);c.className='num-cell mkQ';c.innerHTML=`<span class="mkBadge">?</span><span class="cn">${n}</span><span class="cl">${label}</span>`;};
 MK.u=(n,label)=>{const c=MK.cell(n);c.className='num-cell mkU';c.innerHTML=`<span class="mkBadge" style="font-size:12px;top:5px">USDA</span><span class="cn">${n}</span><span class="cl">${label}</span>`;};
 MK.next=(n)=>{document.querySelectorAll('.screen.active .num-cell.next').forEach(c=>c.classList.remove('next'));const c=MK.cell(n);c.className='num-cell next';};
 MK.label=(n,t)=>{const c=MK.cell(n);let l=c.querySelector('.cl');if(!l){l=document.createElement('span');l.className='cl';c.appendChild(l);}l.textContent=t;};
 MK.newEl=(el,txt)=>{el.classList.add('mkNew');const r=el.getBoundingClientRect();const p=document.createElement('div');p.className='mkPill';p.textContent=txt||'חדש';p.style.top=Math.max(2,r.top-24)+'px';p.style.left=(r.left)+'px';document.body.appendChild(p);};
 MK.cap=(t,title)=>{let c=document.getElementById('mkCap');if(!c){c=document.createElement('div');c.id='mkCap';document.body.appendChild(c);}c.innerHTML=t;
   let h=document.getElementById('mkTitle');if(!h){h=document.createElement('div');h.id='mkTitle';document.body.appendChild(h);}h.textContent=title||'הצעה — עוד לא נבנה';};
 MK.sheet=(title,sub,body)=>{const bg=document.createElement('div');bg.className='mkSheetBg';bg.innerHTML=`<div class="mkSheet"><h3>${title}</h3><div class="sub">${sub}</div>${body}</div>`;document.body.appendChild(bg);return bg.firstChild;};
 MK.b=(t,col,fill)=>`<span class="mkB" style="border-color:${col};color:${fill?'#000':col};${fill?'background:'+col:''}">${t}</span>`;
 MK.usdaBtn=(q)=>{const t=document.querySelector('.screen.active .topbar');const m=t.querySelector('.tb-mid');
   const mk=(txt,bg,bd,fg)=>{const b=document.createElement('button');b.style.cssText=`background:${bg};color:${fg};border:2px solid ${bd};border-radius:12px;padding:10px 14px;font:800 18px Arial;margin:0 6px;box-shadow:0 0 14px ${bg}99`;b.textContent=txt;t.insertBefore(b,m);return b;};
   const u=mk('USDA HOLD','#6A3FB5','#C5B3FF','#fff'); if(q!==false){const qq=mk('? שאלה','#FFC400','#FFE57F','#000'); MK.newEl(qq);} return u;};
};
async function shot(p,name){ await p.evaluate(()=>{document.querySelectorAll('.screen.active .num-cell').forEach(c=>{if(c.classList.contains('mkQ')||c.classList.contains('mkU'))return;if(getComputedStyle(c).animationName!=='none'||c.classList.contains('next'))c.classList.add('mkCur');});}); await W(p,500); await p.screenshot({path:OUT+name+'.png'}); console.log('shot',name); }
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 let x,p;

 const WARN=(n,title,done,effect)=>`<div style="text-align:right;font-size:17px;line-height:1.6;background:#1c2433;border-radius:10px;padding:10px 14px;margin-bottom:10px"><b>כבר נעשה בבהמה ${n}:</b><br>${done}</div><div style="text-align:right;font-size:17px;line-height:1.6;color:#ffb4a8;margin-bottom:12px">⚠ ${effect}</div>`;
 // ── slaughter
 x=await open(b,'slaughter'); p=x.p; await p.evaluate(KIT);
 await p.evaluate(()=>{ const sh=document.getElementById('tSlBtnSh'); const q=sh.cloneNode(true); q.id='mkQBtn'; q.removeAttribute('onclick'); q.style.background='#FFC400'; q.style.color='#000'; q.style.boxShadow='0 0 24px rgba(255,196,0,.55)'; q.innerHTML='<div style="font:900 40px Arial;line-height:1">?</div><div style="font:800 17px Arial">שאלה</div>'; sh.parentNode.appendChild(q);
   MK.q(5,'שאלה'); MK.newEl(q); MK.newEl(MK.cell(5),'חדש: ?'); const u=MK.usdaBtn(false); MK.newEl(u);
   MK.cap('① שחיטה: שאלה על הסכין בבהמה 5 ← <b>"? שאלה"</b>. 5 מקבל "?", והשוחט ממשיך (6, 7, ועכשיו 8). גם כאן יש <b>USDA HOLD</b>.','שחיטה — הצעה, עוד לא נבנה'); });
 await shot(p,'01-slaughter');
 await p.evaluate(()=>{ MK.sheet('#5','שאלה פתוחה — מה הפסק?', MK.b('נשחט (כשר)','#2E86FF')+MK.b('נבלה','#E53935')+MK.b('ירוי','#E08A00')+'<br>'+MK.b('עדיין שאלה — לסגור','#9aa4b5'));
   MK.cap('② כשיש תשובה: לוחצים על 5 (גם אחרי הרבה בהמות) ופוסקים. רק מסך השחיטה פוסק את ה-"?" שלו. נרשם: מי, מתי.','שחיטה — הצעה, עוד לא נבנה'); });
 await shot(p,'02-slaughter-rule-question');
 await p.evaluate(()=>{ document.querySelectorAll('.mkSheetBg').forEach(e=>e.remove());
   MK.sheet('⚠ שינוי פסיקה — #2','הבהמה כבר עברה הלאה. אפשר לשנות — אחרי אישור.',
     `<div>${''}</div>`+'%W2%'+MK.b('כן, לשנות','#E53935',true)+MK.b('ביטול','#9aa4b5'));
   MK.cap('③ <b>שינוי סטטוס תמיד אפשרי</b> — בכל מסך. לפני השינוי: אזהרה שמראה מה כבר נעשה ומה ייפגע. השינוי נרשם, וראש הצוות מקבל התראה.','שחיטה — הצעה, עוד לא נבנה'); });
 await p.evaluate(h=>{ const sh=document.querySelector('.mkSheet'); sh.innerHTML=sh.innerHTML.replace('%W2%',h); }, await p.evaluate(()=>0) || `<div style="text-align:right;font-size:17px;line-height:1.6;background:#1c2433;border-radius:10px;padding:10px 14px;margin-bottom:10px"><b>כבר נעשה בבהמה 2:</b><br>✔ וושט: תקין · ✔ פנים: כשר · ✔ חוץ: <b>בית יוסף</b><br>🖨 הודפסו: רגליים + ראש, 3 מדבקות חלקים (עם סימן בית יוסף)</div><div style="text-align:right;font-size:17px;line-height:1.6;color:#ffb4a8;margin-bottom:12px">⚠ אם תשנה ל"נבלה": המדבקות שהודפסו כבר לא נכונות — <b>צריך לאסוף אותן</b>. בכל המסכים בהמה 2 תסומן "⚠ הפסיקה השתנתה".</div>`);
 await shot(p,'03-slaughter-change-warning'); await x.ctx.close();
 // ── esophagus
 x=await open(b,'esophagus'); p=x.p; await p.evaluate(KIT);
 await p.evaluate(()=>{ MK.q(5,'שאלה בשחיטה'); MK.next(6); MK.label(6,'נשחט'); MK.newEl(MK.cell(5),'חדש: ?'); const u=MK.usdaBtn(); MK.newEl(u);
   MK.cap('④ וושט: 5 מחכה לשחיטה ("?"). מותר לדלג — 6 הבא. למעלה בכל מסך: <b>"? שאלה"</b> ו-<b>USDA HOLD</b> — על המספר הנוכחי, או בוחרים מספר.','וושט — הצעה, עוד לא נבנה'); });
 await shot(p,'04-esophagus');
 await p.click('.screen.active .num-cell[data-idx="4"]'); await W(p,1200);
 await p.evaluate(()=>{ const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT); let n; while(n=w.nextNode()){ if(n.nodeValue.trim()==='#5' && n.parentElement.offsetParent) n.nodeValue=n.nodeValue.replace('#5','#6'); } });
 await p.evaluate(()=>{ const ok=document.querySelector(`[onclick="esoDecide('ok')"]`); const q=ok.cloneNode(true); q.removeAttribute('onclick'); q.textContent='? שאלה'; q.style.borderColor='#FFC400'; q.style.color='#FFC400'; ok.parentNode.appendChild(q); MK.newEl(q);
   MK.cap('⑤ גם בחלון של כל בהמה: <b>"? שאלה"</b>. שאלה של הוושט נפסקת רק במסך הוושט.','וושט — הצעה, עוד לא נבנה'); });
 await shot(p,'05-esophagus-window'); await x.ctx.close();
 // ── legs
 x=await open(b,'legs'); p=x.p; await p.evaluate(KIT);
 await p.evaluate(()=>{ MK.q(5,'הודפס · ?'); MK.next(6); MK.newEl(MK.cell(5),'חדש: ?'); const u=MK.usdaBtn(); MK.newEl(u);
   MK.cap('⑥ רגליים וראש: גם ל-5 מדפיסים כרגיל; בסריקה במיון — "?" עד הפסיקה. גם כאן "? שאלה" ו-USDA HOLD.','רגליים וראש — הצעה, עוד לא נבנה'); });
 await shot(p,'06-legs'); await x.ctx.close();
 // ── inner
 x=await open(b,'inner'); p=x.p; await p.evaluate(KIT);
 await p.evaluate(()=>{ MK.q(5,'שאלה בשחיטה'); const u=MK.usdaBtn(); MK.newEl(u); MK.newEl(MK.cell(5),'חדש: ?');
   MK.cap('⑦ פנים: "? שאלה" — למשל שאלה על הריאה: הבהמה מחכה, וממשיכים לבאה. רק מסך הפנים פוסק אותה.','פנים — הצעה, עוד לא נבנה'); });
 await shot(p,'07-inner'); await x.ctx.close();
 // ── outer
 x=await open(b,'outer'); p=x.p; await p.evaluate(KIT);
 await p.evaluate(()=>{ MK.u(3,'כל הבהמה'); MK.q(5,'שאלה בשחיטה'); const u=MK.usdaBtn(); MK.newEl(u); MK.newEl(MK.cell(3),'חדש: USDA');
   MK.cap('⑧ חוץ: 3 מעוכב USDA (סגול) — הפסיקה הכשרותית לא משתנה. 5 עם "?". גם לבודק החוץ יש "? שאלה".','חוץ — הצעה, עוד לא נבנה'); });
 await shot(p,'08-outer');
 await p.evaluate(()=>{ MK.sheet('⚠ שינוי פסיקה — #1','גלאט ← טרף',
   `<div style="text-align:right;font-size:17px;line-height:1.6;background:#1c2433;border-radius:10px;padding:10px 14px;margin-bottom:10px"><b>כבר נעשה בבהמה 1:</b><br>🖨 הודפסו 3 מדבקות חלקים (עם סימן גלאט) · 🖨 5 חותמות · ⚖ נשקלה</div><div style="text-align:right;font-size:17px;line-height:1.6;color:#ffb4a8;margin-bottom:12px">⚠ המדבקות והחותמות כבר לא נכונות — <b>צריך לאסוף ולהוריד אותן</b>. ראש הצוות יקבל התראה.</div>`+MK.b('כן, לשנות לטרף','#E53935',true)+MK.b('ביטול','#9aa4b5'));
   MK.cap('⑨ גם בחוץ (ובכל מסך): שינוי אחרי שהודפס — תמיד אפשרי, עם אזהרה ברורה מה צריך לתקן בפועל.','חוץ — הצעה, עוד לא נבנה'); });
 await shot(p,'09-outer-change-warning'); await x.ctx.close();
 // ── parts
 x=await open(b,'parts'); p=x.p; await p.evaluate(KIT);
 await p.evaluate(()=>{ const u=MK.usdaBtn(); MK.newEl(u);
   MK.sheet('USDA HOLD — #3','מה מעוכב?', MK.b('כל הבהמה','#B39DFF')+MK.b('לחי 1','#B39DFF')+MK.b('לחי 2','#B39DFF')+MK.b('לשון','#B39DFF',true)+'<br>'+MK.b('ביטול','#9aa4b5'));
   MK.cap('⑩ חלקים: לשון של 3 נפלה ← <b>USDA HOLD</b> ← "לשון". בלי סיבה. רק הלשון מעוכבת — הלחיים ממשיכות.','חלקים — הצעה, עוד לא נבנה'); });
 await shot(p,'10-parts-usda-choose');
 await p.evaluate(()=>{ document.querySelectorAll('.mkSheetBg').forEach(e=>e.remove()); MK.u(3,'לשון'); MK.next(4); MK.label(4,'');
   const c=MK.cell(1); c.style.outline='4px solid #FF5252'; c.style.outlineOffset='-4px'; const l=c.querySelector('.cl'); if(l){l.textContent='⚠ השתנה'; l.style.color='#FF8A80';} MK.newEl(c,'חדש: ⚠');
   MK.cap('⑪ 3 מסומן <b>USDA · לשון</b>. 1 מסומן <b>⚠ השתנה</b> — הפסיקה שונתה אחרי שהודפס כאן: לאסוף את המדבקות.','חלקים — הצעה, עוד לא נבנה'); });
 await shot(p,'11-parts-held');
 await p.evaluate(()=>{ MK.sheet('מעוכבים USDA — חלקים','רק התחנה שעיכבה משחררת או פוסלת',
   `<div class="mkRow"><span><b>#3</b> · לשון · 09:42 · דוד</span><span>${MK.b('שחרור','#28C76F')}${MK.b('נפסל USDA','#E53935')}</span></div>
    <div class="mkRow"><span><b>#11</b> · לחי 2 · 10:05 · דוד</span><span>${MK.b('שחרור','#28C76F')}${MK.b('נפסל USDA','#E53935')}</span></div>`);
   MK.cap('⑫ שחרור ← חוזר לתור, ראשון. נפסל USDA ← לא ממשיך; בדוחות בנפרד מטרף; הפסיקה הכשרותית לא משתנה.','חלקים — הצעה, עוד לא נבנה'); });
 await shot(p,'12-parts-held-list'); await x.ctx.close();
 // ── stamps
 x=await open(b,'stamps'); p=x.p; await p.evaluate(KIT);
 await p.evaluate(()=>{ const u=MK.usdaBtn(); MK.newEl(u);
   MK.sheet('USDA HOLD — #2','מה מעוכב?', MK.b('כל הבהמה','#B39DFF')+MK.b('חצי ימין','#B39DFF')+MK.b('חצי שמאל','#B39DFF',true)+'<br>'+MK.b('ביטול','#9aa4b5'));
   MK.cap('⑬ חותמות ושקילה: חצי שמאל של 2 נפל ← USDA HOLD ← "חצי שמאל". חצי ימין ממשיך.','חותמות — הצעה, עוד לא נבנה'); });
 await shot(p,'13-stamps-usda-half'); await x.ctx.close();
 // ── team leader
 { const ctx=await b.newContext({viewport:{width:1024,height:700},deviceScaleFactor:1.5});
   await ctx.route(u=>new URL(u).pathname==='/',r=>r.fulfill({status:200,contentType:'text/html; charset=utf-8',body:fs.readFileSync('/home/user/empower-design-studio/glatttrack/kosher-app-v10.25.html')}));
   await ctx.addInitScript(()=>{window._gtLicShown=true;if(localStorage.getItem('i'))return;localStorage.setItem('ks_lang_by_screen',JSON.stringify({scPair:'he',scNav:'he',scManager:'he'}));localStorage.setItem('i','1');});
   p=await ctx.newPage(); p.on('dialog',d=>d.accept()); await p.goto('http://localhost:8083/'); await W(p,6000);
   await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));mgrEnter();}); await W(p,1000);
   await p.fill('#loginCodeInput','e2e-tl-code-7731'); await p.evaluate(()=>[...document.querySelectorAll('#loginModal button')].pop().click()); await W(p,10000);
   await p.evaluate(()=>{document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open'));try{gtWizardClose(true);}catch(e){}}); await W(p,1500);
   await p.evaluate(()=>document.querySelectorAll('.overlay.open').forEach(o=>o.classList.remove('open')));
   await p.evaluate(KIT);
   await p.evaluate(()=>{ const c=document.createElement('div'); c.style.cssText='position:fixed;top:120px;left:50%;transform:translateX(-50%);width:640px;z-index:2147483000;background:#111827;border:3px solid #E8B84A;border-radius:16px;padding:14px 18px;direction:rtl;color:#fff;font-family:Arial;box-shadow:0 10px 40px rgba(0,0,0,.7)';
     const row=(tag,col,txt,wait)=>`<div class="mkRow"><span><span style="background:${col};color:${col==='#FFC400'?'#000':'#fff'};border-radius:6px;padding:1px 8px;font-weight:800;margin-left:8px">${tag}</span>${txt}</span><span style="color:#9aa4b5">${wait}</span></div>`;
     c.innerHTML='<div style="font:800 22px Arial;color:#E8B84A;margin-bottom:6px">⏳ פתוחים עכשיו (3)</div>'+row('?','#FFC400','<b>#5</b> · שחיטה · 08:31 · השוחט','מחכה 12 דק׳')+row('USDA','#6A3FB5','<b>#3</b> · חלקים · לשון · דוד','מחכה 40 דק׳')+row('USDA','#6A3FB5','<b>#2</b> · חותמות · חצי שמאל · משה','מחכה 8 דק׳')+'<div style="color:#ff8a80;font-weight:700;margin-top:8px">🔒 סגירת יום חסומה — יש "?" פתוח</div>';
     document.body.appendChild(c); MK.newEl(c);
     MK.cap('⑭ ראש הצוות רואה את השינויים אחרי הדפסה, כל ה"?" ועיכובי ה-USDA הפתוחים: מה, איפה, מי וכמה זמן. ראש הצוות רק רואה — מי שסימן הוא שפוסק/משחרר.','ראש צוות — הצעה, עוד לא נבנה'); });
   await shot(p,'14-team-leader-open'); await ctx.close(); }
 await b.close(); })();
