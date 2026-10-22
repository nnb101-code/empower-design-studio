// GlattTrack — live screen recordings, one clip per tablet, against the local test server.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const OUT = __dirname + '/raw';
const DRY = process.env.DRY === '1';
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
fs.mkdirSync(OUT, { recursive: true });
const VP = { width: 1024, height: 700 };

const DEV = {
  slaughter: ['demo_slaughter', 'tok-demo-slaughter-000000000000000'],
  esophagus: ['demo_esophagus', 'tok-demo-esophagus-000000000000000'],
  inner: ['demo_inner', 'tok-demo-inner-000000000000000'],
  outer: ['e2e_outer_0001', 'tok-outer-e2e-00000000000000001'],
  legs: ['demo_legs', 'tok-demo-legs-000000000000000'],
  parts: ['e2e_parts_0001', 'tok-demo-parts-0000000000000000'],
  stamps: ['e2e_stamps_001', 'tok-demo-stamps-000000000000000'],
  display: ['demo_display', 'tok-demo-display-000000000000000'],
};

// on-screen caption + finger mark (drawn inside the page, so they are in the recording)
const OVERLAY = () => {
  const css = document.createElement('style');
  css.textContent = `#gtCap{position:fixed;left:50%;bottom:14px;transform:translateX(-50%);z-index:2147483647;max-width:92%;
    background:rgba(10,14,24,.92);color:#fff;border:2px solid #E8B84A;border-radius:14px;padding:10px 22px;
    font:600 24px/1.35 Arial,sans-serif;text-align:center;direction:rtl;pointer-events:none;box-shadow:0 6px 24px rgba(0,0,0,.5);transition:opacity .25s}
    #gtCap:empty{opacity:0}
    #gtFinger{position:fixed;width:46px;height:46px;margin:-23px 0 0 -23px;border-radius:50%;z-index:2147483646;pointer-events:none;
    background:rgba(255,215,0,.35);border:3px solid #FFD700;transition:left .45s ease,top .45s ease,transform .15s;display:none}
    #gtFinger.tap{transform:scale(.6);background:rgba(255,215,0,.75)}`;
  const add = () => {
    if (!document.head || !document.body) return setTimeout(add, 50);
    document.head.appendChild(css);
    const c = document.createElement('div'); c.id = 'gtCap'; document.body.appendChild(c);
    const f = document.createElement('div'); f.id = 'gtFinger'; document.body.appendChild(f);
  };
  add();
};

async function cap(p, text, ms = 2600) {
  await p.evaluate(t => { const c = document.getElementById('gtCap'); if (c) { c.textContent = t; c.parentNode.appendChild(c); } }, text);
  if (ms) await p.waitForTimeout(DRY ? 200 : ms);
}
async function finger(p, x, y, press = true) {
  await p.evaluate(([x, y]) => { const f = document.getElementById('gtFinger'); if (!f) return; f.parentNode.appendChild(f); f.style.display = 'block'; f.style.left = x + 'px'; f.style.top = y + 'px'; }, [x, y]);
  await p.waitForTimeout(DRY ? 50 : 550);
  if (press) { await p.evaluate(() => document.getElementById('gtFinger').classList.add('tap')); await p.waitForTimeout(140); await p.evaluate(() => document.getElementById('gtFinger').classList.remove('tap')); }
}
async function tap(p, sel, wait = 1100) {
  const el = p.locator(sel).filter({ visible: true }).first();
  await el.waitFor({ state: 'visible', timeout: 15000 });
  const b = await el.boundingBox();
  await finger(p, b.x + b.width / 2, b.y + b.height / 2);
  await el.click();
  await p.waitForTimeout(DRY ? Math.min(wait, 900) : wait);
}
async function inOpen(p, n, say) {
  await tap(p, cell(n), 1000);
  if (await p.locator('#rumenModal.open').count()) { if (say) await cap(p, 'בדיקת כרס: כשר', 900); await tap(p, '#rumenModal button:has-text("כשר")', 1000); }
}
const cell = n => `.screen.active .num-cell[data-idx="${n - 1}"]`;
async function state(p) {
  return p.evaluate(() => ({ screen: (document.querySelector('.screen.active') || {}).id, open: [...document.querySelectorAll('.overlay.open')].map(o => o.id) }));
}

async function station(browser, role, fn) {
  const [id, tok] = DEV[role];
  const ctx = await browser.newContext({ viewport: VP, deviceScaleFactor: 1, ...(DRY ? {} : { recordVideo: { dir: OUT, size: VP } }) });
  await ctx.addInitScript(([id, tok, role]) => {
    if (!localStorage.getItem('i')) {
      localStorage.setItem('ks_device_token', tok); localStorage.setItem('ks_kiosk_role', role);
      localStorage.setItem('ks_kiosk_index', '0'); localStorage.setItem('ks_device_id', id); localStorage.setItem('i', '1');
      const m = {}; ['Slaughter','Esophagus','Legs','Inner','Outer','Parts','Stamps'].forEach(s => { m['sc'+s] = 'he'; m['sc'+s+'Login'] = 'he'; }); m.scCounter = 'he'; m.scPair = 'he'; m.scNav = 'he';
      localStorage.setItem('ks_lang_by_screen', JSON.stringify(m));
    }
  }, [id, tok, role]);
  await ctx.addInitScript(OVERLAY);
  const p = await ctx.newPage(); p.on('dialog', d => d.accept());
  p.on('pageerror', e => console.log('  pageerror', role, e.message));
  await p.goto('http://localhost:8080/');
  await p.waitForTimeout(6500);
  console.log(role, 'start', JSON.stringify(await state(p)));
  try { await fn(p); } catch (e) { console.log('  FAIL', role, e.message.split('\n')[0], JSON.stringify(await state(p))); }
  console.log(role, 'end', JSON.stringify(await state(p)));
  const v = p.video();
  await ctx.close();
  if (v) fs.renameSync(await v.path(), `${OUT}/${role}.webm`);
}

async function leader(browser, name, fn) {
  const ctx = await browser.newContext({ viewport: VP, ...(DRY ? {} : { recordVideo: { dir: OUT, size: VP } }) });
  await ctx.addInitScript(() => { if (!localStorage.getItem('i')) { localStorage.setItem('ks_lang_by_screen', JSON.stringify({ scPair: 'he', scNav: 'he', scManager: 'he' })); localStorage.setItem('i', '1'); } });
  await ctx.addInitScript(OVERLAY);
  const p = await ctx.newPage(); p.on('dialog', d => d.accept());
  p.on('pageerror', e => console.log('  pageerror', name, e.message));
  await p.goto('http://localhost:8080/'); await p.waitForTimeout(7000);
  console.log(name, 'start', JSON.stringify(await state(p)));
  try { await fn(p); } catch (e) { console.log('  FAIL', name, e.message.split('\n')[0], JSON.stringify(await state(p))); }
  const v = p.video(); await ctx.close();
  if (v) fs.renameSync(await v.path(), `${OUT}/${name}.webm`);
}
async function tlLogin(p) {
  await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
  await cap(p, 'טאבלט ראש הצוות — נכנסים עם קוד אישי', 2200);
  await p.evaluate(() => mgrEnter()); await p.waitForTimeout(1200);
  await finger(p, 512, 330, false);
  await p.type('#loginCodeInput', 'e2e-tl-code-7731', { delay: DRY ? 0 : 60 });
  await tap(p, '#loginModal button >> nth=-1', 300);
  for (let i = 0; i < 20; i++) { await p.waitForTimeout(800); const ok = await p.evaluate(async () => { try { const b = await window.sb.rpc('system_health', { p_token: KS.getManagerToken() }); return !!(b.data && b.data.ok); } catch (e) { return false; } }); if (ok) break; }
  await p.evaluate(() => { document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')); try { gtWizardClose(true); } catch (e) { } });
  await p.waitForTimeout(1500);
}
async function tab(p, t, text) {
  await tap(p, `[onclick*="mgrTab('${t}')"]`, 600);
  await cap(p, text, 3200);
}

const scenes = {
  async leader1(b) {
    await leader(b, '01-leader-start', async p => {
      await tlLogin(p);
      await cap(p, 'לשונית "היום": מצב כל התחנות, הכמויות, והתראות', 4000);
      await p.mouse.wheel(0, 500); await p.waitForTimeout(1500); await p.mouse.wheel(0, -500);
      await tab(p, 'search', 'לשונית "חיפוש": מוצאים בהמה לפי מספר ותאריך');
      await tab(p, 'analysis', 'לשונית "ניתוח": סיכומים, משקל, השוואות, משקים ועובדים');
      await p.mouse.wheel(0, 600); await p.waitForTimeout(1800); await p.mouse.wheel(0, -600);
      await tab(p, 'log', 'לשונית "תקלות": דיווחים מהתחנות ובריאות המערכת');
      await tab(p, 'settings', 'לשונית "הגדרות": כל ההגדרות בקבוצות. עכשיו — יום עבודה, תחנה אחרי תחנה');
    });
  },
  async slaughter(b) {
    await station(b, 'slaughter', async p => {
      await cap(p, 'טאבלט השחיטה. נכנסים לעבודה', 2000);
      await tap(p, '[onclick="slLogin()"]', 1500);
      await cap(p, 'לוחצים "נשחט" — המספר הבא מסומן, והתור מתקדם לבד', 1800);
      for (let i = 0; i < 4; i++) await tap(p, '#tSlBtnS', 1300);
      await cap(p, 'בהמה 5 — "נבלה"', 1200);
      await tap(p, '#tSlBtnN', 1300);
      await cap(p, 'בהמה 6 — "נשחט"', 1000);
      await tap(p, '#tSlBtnS', 1300);
      await cap(p, 'לחיצה על מספר שכבר סומן — חלון תיקון (רק לפני שהשלב הבא נגע בו)', 1500);
      await tap(p, cell(6), 2500);
      console.log('  after cell tap', JSON.stringify(await state(p)));
      await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
      await cap(p, 'הבהמות עוברות עכשיו לבדיקת הוושט', 2500);
    });
  },
  async esophagus(b) {
    await station(b, 'esophagus', async p => {
      await cap(p, 'טאבלט בדיקת הוושט', 1800);
      await tap(p, '[onclick="esoLogin()"]', 1500).catch(() => {});
      await cap(p, 'ניסיון לדלג לבהמה 3 — המערכת לא מאפשרת', 1500);
      await tap(p, cell(3), 2400);
      await cap(p, 'לוחצים על הבהמה המהבהבת, ובוחרים "תקין"', 1500);
      for (const n of [1, 2, 3, 4, 6]) {
        await tap(p, cell(n), 900);
        await tap(p, '#esoModal button:has-text("תקין")', 1100);
      }
      await cap(p, 'בהמה 5 (נבלה) לא מגיעה לוושט. כל השאר עוברות לבודק הפנים', 3000);
    });
  },
  async inner(b) {
    await station(b, 'inner', async p => {
      await cap(p, 'טאבלט בודק הפנים', 1800);
      await tap(p, '[onclick="inLogin()"]', 1500);
      await cap(p, 'לוחצים על הבהמה הבאה בתור (מהבהבת)', 1500);
      await inOpen(p, 1, true);
      await cap(p, 'בית הכוסות: כשר', 900);
      await tap(p, '#tMawK', 1200);
      await cap(p, 'עכשיו ציור הריאה: מסמנים באצבע', 1200);
      await tap(p, cell(1), 1500);
      const c = await p.locator('#lungDraw').boundingBox();
      if (c) {
        const sx = c.x + c.width * 0.35, sy = c.y + c.height * 0.4;
        await finger(p, sx, sy, false); await p.mouse.move(sx, sy); await p.mouse.down();
        for (let i = 1; i <= 20; i++) { await p.mouse.move(sx + i * 6, sy + Math.sin(i / 3) * 30); await p.evaluate(([x, y]) => { const f = document.getElementById('gtFinger'); f.style.left = x + 'px'; f.style.top = y + 'px'; }, [sx + i * 6, sy + Math.sin(i / 3) * 30]); await p.waitForTimeout(40); }
        await p.mouse.up();
      }
      await cap(p, '"אישור לבודק חוץ" — הבהמה עוברת לחוץ יחד עם הציור', 1500);
      await tap(p, '#tLConfirm', 1500);
      await cap(p, 'בהמה 2 — כשר, ואישור', 900);
      await inOpen(p, 2); await tap(p, '#tMawK', 900); await tap(p, cell(2), 1200); await tap(p, '#tLConfirm', 1300);
      await cap(p, 'בהמה 3 — טרף: לחיצה ראשונה שואלת "לאשר טרף?", השנייה פוסקת', 1600);
      await inOpen(p, 3); await tap(p, '#tMawT', 1600); await tap(p, '#tMawT', 1600);
      await cap(p, 'בהמות 4 ו-6 — כשר ואישור', 900);
      for (const n of [4, 6]) { await inOpen(p, n); await tap(p, '#tMawK', 900); await tap(p, cell(n), 1200); await tap(p, '#tLConfirm', 1200); }
      await cap(p, 'בהמה 3 טרף — לא ממשיכה. השאר מחכות לבודק החוץ', 3000);
    });
  },
  async outer(b) {
    await station(b, 'outer', async p => {
      await cap(p, 'טאבלט בודק החוץ', 1800);
      await tap(p, '[onclick="outLogin()"]', 1500);
      await cap(p, 'לוחצים על הבהמה הבאה — רואים את ציור הריאה מבודק הפנים, ופוסקים', 1500);
      await tap(p, cell(1), 2600);
      await tap(p, '#decModal .dec-btns button:has-text("גלאט")', 1300);
      await cap(p, 'בהמה 2 — בית יוסף', 900);
      await tap(p, cell(2), 1300); await tap(p, '#decModal .dec-btns button:has-text("בית יוסף")', 1300);
      await cap(p, 'בהמה 4 — גלאט, בהמה 6 — כשר', 900);
      await tap(p, cell(4), 1300); await tap(p, '#decModal .dec-btns button:has-text("גלאט")', 1300);
      await tap(p, cell(6), 1300); await tap(p, '#decModal .dec-btns button:has-text("כשר")', 1300);
      await cap(p, 'הפסיקה הסופית נקבעה. עכשיו אפשר להדפיס מדבקות כשרות', 3000);
    });
  },
  async legs(b) {
    await station(b, 'legs', async p => {
      await cap(p, 'טאבלט רגליים / ראש', 1800);
      await tap(p, '[onclick="lgLogin()"]', 1500);
      await cap(p, 'לחיצה ראשונה — מדבקות רגליים. לחיצה שנייה — מדבקת ראש', 1600);
      for (const n of [1, 2, 3, 4, 5, 6]) { if (n === 5) await cap(p, 'גם בהמה 5 (נבלה) מקבלת מדבקת מספר — כולן לפי הסדר', 600); await tap(p, cell(n), 2200); await tap(p, cell(n), 2200); }
      await cap(p, 'מצב "מיון": סורקים מדבקת רגל ורואים בגדול לאן למיין', 1600);
      await tap(p, '#lgModeSort', 1500);
      for (const code of ['1', '2', '3']) {
        await p.evaluate(() => { const i = document.getElementById('lgScanInput'); if (i) i.focus(); });
        await p.keyboard.type(code, { delay: 80 }); await p.keyboard.press('Enter');
        await p.waitForTimeout(DRY ? 300 : 2800);
        await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
      }
      await cap(p, 'רגל 3 — "טרף!" באדום. המיון רק מציג, לא משנה דבר', 3000);
    });
  },
  async parts(b) {
    await station(b, 'parts', async p => {
      await cap(p, 'טאבלט חלקים (לחיים ולשון)', 1800);
      await tap(p, '[onclick="partsLogin()"]', 1500);
      await cap(p, 'ניסיון על בהמה 3 (טרף) — המסך מסרב', 1300);
      await tap(p, cell(3), 2600);
      await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
      await cap(p, 'בהמה 1 — לחיצה אחת מדפיסה 3 מדבקות: לחי 1, לחי 2, לשון', 1500);
      await tap(p, cell(1), 3000);
      await tap(p, cell(2), 3000);
      await cap(p, 'הבהמות הבאות מחכות בתור, לפי הסדר', 2500);
    });
  },
  async stamps(b) {
    await station(b, 'stamps', async p => {
      await cap(p, 'טאבלט חותמות ומשקל', 1800);
      await tap(p, '[onclick="stampsLogin()"]', 1500);
      await cap(p, 'סורקים את מדבקת הבהמה — יוצאות 5 חותמות לפי הפסיקה', 1500);
      await p.evaluate(() => { try { stampsFocusScan(); } catch (e) { } });
      await p.keyboard.type('1', { delay: 80 }); await p.keyboard.press('Enter');
      await p.waitForTimeout(DRY ? 3300 : 3600);
      console.log('  after scan', JSON.stringify(await state(p)));
      await cap(p, 'אם השקילה מופעלת: סורקים מדבקת משקל — צד ימין ואז צד שמאל', 1500);
      await p.keyboard.type('245.5 kg', { delay: 60 }); await p.keyboard.press('Enter'); await p.waitForTimeout(DRY ? 300 : 2200);
      await p.keyboard.type('238.0 kg', { delay: 60 }); await p.keyboard.press('Enter'); await p.waitForTimeout(DRY ? 300 : 2500);
      console.log('  after weight', JSON.stringify(await state(p)));
      await cap(p, 'בהמה 1 הוחתמה. ממשיכים לבאה', 2500);
    });
  },
  async display(b) {
    await station(b, 'display', async p => {
      await cap(p, 'מסך הספירה לקיר — מתעדכן לבד, רק לצפייה', 5000);
    });
  },
  async leader2(b) {
    await leader(b, '99-leader-end', async p => {
      await tlLogin(p);
      await cap(p, 'בחזרה אצל ראש הצוות: רואים את כל מה שקרה', 3500);
      await p.mouse.wheel(0, 500); await p.waitForTimeout(2000); await p.mouse.wheel(0, -500);
      await tab(p, 'search', 'חיפוש בהמה 1 — כרטיס בהמה עם כל ההיסטוריה');
      await p.evaluate(() => { try { gtAnimalCard(null, 0); } catch (e) { console.log(e); } });
      await p.waitForTimeout(DRY ? 300 : 4500);
      await p.mouse.wheel(0, 400); await p.waitForTimeout(2000);
      await cap(p, 'כל פעולה: מי, מתי, ומאיזה טאבלט', 3500);
    });
  },
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  for (const [k, fn] of Object.entries(scenes)) {
    if (ONLY && !ONLY.includes(k)) continue;
    await fn(browser);
  }
  await browser.close();
})();
