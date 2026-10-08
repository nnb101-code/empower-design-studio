// GlattTrack — live recording, Hebrew or English (LANG=he|en), in the plant's working order:
// first installation → team leader picks the screens → slaughter → esophagus → legs & head (stickers)
// → inner → outer → legs sorting → small parts (stickers) → stamps + weighing → team leader.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const { execSync } = require('child_process');
const LANG = process.env.LANG_V || 'he';
const APP = process.env.APP;
const OUT = __dirname + '/raw3-' + LANG; fs.mkdirSync(OUT, { recursive: true });
const MAIN = 'http://localhost:8083/', INST = 'http://localhost:8084/';
const C = require('./caps3.js');
const DUR = JSON.parse(fs.readFileSync(__dirname + '/voice-en/durations.json'));
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
const VP = { width: 1024, height: 700 };
const LOG = {};          // clip → [{t, key}]
const SCR = ['Slaughter','Esophagus','Legs','Inner','Outer','Parts','Stamps'];

const OVERLAY = () => {
  const css = document.createElement('style');
  css.textContent = `#gtCap{position:fixed;left:50%;bottom:14px;transform:translateX(-50%);z-index:2147483647;max-width:92%;
    background:rgba(10,14,24,.93);color:#fff;border:2px solid #E8B84A;border-radius:14px;padding:10px 22px;
    font:600 23px/1.35 Arial,sans-serif;text-align:center;pointer-events:none;box-shadow:0 6px 24px rgba(0,0,0,.5)}
    #gtCap:empty{display:none}
    #gtFinger{position:fixed;width:46px;height:46px;margin:-23px 0 0 -23px;border-radius:50%;z-index:2147483646;pointer-events:none;
    background:rgba(255,215,0,.35);border:3px solid #FFD700;transition:left .45s ease,top .45s ease,transform .15s;display:none}
    #gtFinger.tap{transform:scale(.6);background:rgba(255,215,0,.75)}`;
  const add = () => { if (!document.head || !document.body) return setTimeout(add, 50);
    document.head.appendChild(css);
    const c = document.createElement('div'); c.id = 'gtCap'; c.setAttribute('data-no-i18n', ''); document.body.appendChild(c);
    const f = document.createElement('div'); f.id = 'gtFinger'; document.body.appendChild(f); };
  add();
};
async function useApp(ctx) {
  await ctx.route(u => { const x = new URL(u); return x.pathname === '/' || x.pathname.startsWith('/index'); },
    r => r.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: fs.readFileSync(APP) }));
}
async function cap(p, key, minMs = 2200) {
  const txt = C[key][LANG === 'en' ? 1 : 0];
  (LOG[p.__clip] = LOG[p.__clip] || []).push({ t: Date.now() - p.__t0, key });
  await p.evaluate(([t, dir]) => { const c = document.getElementById('gtCap'); if (c) { c.textContent = t; c.style.direction = dir; c.parentNode.appendChild(c); } }, [txt, LANG === 'en' ? 'ltr' : 'rtl']);
  await p.waitForTimeout(Math.max(minMs, Math.round((DUR[key] || 2) * 1000) + 500));
}
async function finger(p, x, y, press = true) {
  await p.evaluate(([x, y]) => { const f = document.getElementById('gtFinger'); if (!f) return; f.parentNode.appendChild(f); f.style.display = 'block'; f.style.left = x + 'px'; f.style.top = y + 'px'; }, [x, y]);
  await p.waitForTimeout(550);
  if (press) { await p.evaluate(() => document.getElementById('gtFinger').classList.add('tap')); await p.waitForTimeout(140); await p.evaluate(() => document.getElementById('gtFinger').classList.remove('tap')); }
}
async function tap(p, sel, wait = 1100) {
  const el = p.locator(sel).filter({ visible: true }).first();
  await el.waitFor({ state: 'visible', timeout: 15000 });
  const b = await el.boundingBox();
  await finger(p, b.x + b.width / 2, b.y + b.height / 2);
  await el.click();
  await p.waitForTimeout(wait);
}
const cell = n => `.screen.active .num-cell[data-idx="${n - 1}"]`;
const state = p => p.evaluate(() => ({ screen: (document.querySelector('.screen.active') || {}).id, open: [...document.querySelectorAll('.overlay.open')].map(o => o.id) }));

// the real sticker of an animal, big, with what is inside its QR code
async function showSticker(p, idx, kind, key) {
  await p.evaluate(([idx, kind, en]) => {
    let b = document.getElementById('gtStk');
    if (!b) { b = document.createElement('div'); b.id = 'gtStk'; b.setAttribute('data-no-i18n', ''); b.style.cssText = 'position:fixed;inset:0;z-index:2147483600;background:rgba(0,0,0,.8);display:flex;align-items:center;justify-content:center;gap:34px;padding-bottom:90px'; document.body.appendChild(b); }
    b.innerHTML = '<div style="width:440px;height:440px;display:flex;align-items:center;justify-content:center"><div id="gtStkIn" style="transform:scale(1.75)"></div></div><div id="gtStkQr" style="background:#fff;color:#111;border-radius:12px;padding:14px 18px;font:15px/1.7 Arial;min-width:260px;max-width:330px"></div>';
    b.style.display = 'flex';
    renderSticker('gtStkIn', idx, kind, false);
    const pay = buildStickerPayload(idx) || '';
    const lab = en ? { N: 'Number', D: 'Date', HD: 'Hebrew date', W: 'Day', TM: 'Time', SH: 'Shochet', S: 'Status at printing' }
                   : { N: 'מספר', D: 'תאריך', HD: 'תאריך עברי', W: 'יום', TM: 'שעה', SH: 'שוחט', S: 'מצב בזמן ההדפסה' };
    const sw = { slaughtered: en ? 'slaughtered' : 'נשחט', notChalak: 'לא חלק', nevela: 'נבלה', shot: 'ירוי' };
    const rows = pay.split('|').slice(1).map(x => { const i = x.indexOf(':'); const k = x.slice(0, i), v = x.slice(i + 1); if (k === 'T' || !v) return ''; return `<div><b>${lab[k] || k}:</b> <span dir="auto">${(k === 'S' ? (sw[v] || statusDisplayName(v, KS.getAnimal(idx)) || v) : v).replace(/</g, '&lt;')}</span></div>`; }).join('');
    document.getElementById('gtStkQr').innerHTML = `<div style="font-weight:800;font-size:17px;margin-bottom:6px;direction:${en ? 'ltr' : 'rtl'}">${en ? 'Inside the QR code' : 'מה יש בתוך ה-QR'}</div><div style="direction:${en ? 'ltr' : 'rtl'}">${rows}</div>`;
  }, [idx, kind, LANG === 'en']);
  await cap(p, key, 4800);
  await p.evaluate(() => { const b = document.getElementById('gtStk'); if (b) b.style.display = 'none'; });
}

async function ctxFor(b, clip, init) {
  const ctx = await b.newContext({ viewport: VP, recordVideo: { dir: OUT, size: VP } });
  await ctx.addInitScript(init.fn, init.arg); await ctx.addInitScript(OVERLAY); await useApp(ctx);
  const p = await ctx.newPage(); p.__clip = clip; p.__t0 = Date.now();
  p.on('dialog', d => d.accept()); p.on('pageerror', e => console.log('  pageerror', clip, e.message));
  return { ctx, p };
}
async function done(x, clip) { const v = x.p.video(); await x.ctx.close(); if (v) fs.renameSync(await v.path(), `${OUT}/${clip}.webm`); }
const langInit = { fn: ([L, scr]) => { if (localStorage.getItem('i')) return; const m = { scPair: L, scNav: L, scManager: L, scCounter: L }; scr.forEach(s => { m['sc' + s] = L; m['sc' + s + 'Login'] = L; }); localStorage.setItem('ks_lang_by_screen', JSON.stringify(m)); localStorage.setItem('i', '1'); }, arg: [LANG, SCR] };
const DEV = {
  slaughter: ['demo_slaughter', 'tok-demo-slaughter-000000000000000'], esophagus: ['demo_esophagus', 'tok-demo-esophagus-000000000000000'],
  inner: ['demo_inner', 'tok-demo-inner-000000000000000'], outer: ['e2e_outer_0001', 'tok-outer-e2e-00000000000000001'],
  legs: ['demo_legs', 'tok-demo-legs-000000000000000'], parts: ['e2e_parts_0001', 'tok-demo-parts-0000000000000000'],
  stamps: ['e2e_stamps_001', 'tok-demo-stamps-000000000000000'],
};
async function station(b, role, clip, fn) {
  const [id, tok] = DEV[role];
  const x = await ctxFor(b, clip, { fn: ([id, tok, role, L, scr]) => { if (localStorage.getItem('i')) return;
      localStorage.setItem('ks_device_token', tok); localStorage.setItem('ks_kiosk_role', role); localStorage.setItem('ks_kiosk_index', '0'); localStorage.setItem('ks_device_id', id);
      const m = {}; scr.forEach(s => { m['sc' + s] = L; m['sc' + s + 'Login'] = L; }); localStorage.setItem('ks_lang_by_screen', JSON.stringify(m)); localStorage.setItem('i', '1'); }, arg: [id, tok, role, LANG, SCR] });
  await x.p.goto(MAIN); await x.p.waitForTimeout(6500);
  try { await fn(x.p); } catch (e) { console.log('  FAIL', clip, e.message.split('\n')[0], JSON.stringify(await state(x.p))); }
  await done(x, clip);
}
const login = (p, role) => tap(p, `[onclick="${{ slaughter: 'slLogin', esophagus: 'esoLogin', legs: 'lgLogin', inner: 'inLogin', outer: 'outLogin', parts: 'partsLogin', stamps: 'stampsLogin' }[role]}()"]`, 1500);

const scenes = {
  async install(b) {
    execSync('bash ' + __dirname + '/../mkinst.sh');
    execSync(`psql -h /tmp -p 5433 -U postgres -d gtinst -c "select _set_setup_code('ABCD-1234-XY')"`);
    const x = await ctxFor(b, '01-install', langInit); const p = x.p;
    await p.setContent('<html><body style="margin:0;background:#06080d"></body></html>');
    await p.evaluate(OVERLAY); await p.waitForTimeout(800);
    await cap(p, 'i1', 3000);
    await p.goto(INST); await p.waitForTimeout(1500);
    await cap(p, 'i2', 4500);
    await tap(p, '[onclick="gtStartFirstSetup()"]', 900);
    await cap(p, 'i4', 1500);
    await finger(p, 512, 290, false); await p.type('#gtFfName', LANG === 'en' ? 'Moshe Cohen' : 'משה כהן', { delay: 90 });
    await p.type('#gtFfCode', 'moshe-2026', { delay: 90 });
    await finger(p, 512, 430, false); await p.type('#gtFfSetup', 'ABCD-1234-XY', { delay: 110 });
    await p.waitForTimeout(500);
    await tap(p, '#gtFfOk', 200);
    await cap(p, 'i5', 3000);
    await p.waitForTimeout(6000);
    await cap(p, 'i6', 3500);
    await tap(p, '#gtWizard [onclick="gtWizGo(1)"]', 1200);
    await cap(p, 'i7', 2600);
    await tap(p, '#gtWizard button[onclick="gtWizGo(1)"] >> nth=0', 1500);
    await cap(p, 'i8', 2500);
    for (const r of ['slaughter', 'esophagus', 'inner', 'outer', 'legs', 'parts', 'stamps']) {
      const on = await p.evaluate(r => { try { return !!(_gtPlanDraft && _gtPlanDraft.screens.has(r)); } catch (e) { return false; } }, r);
      if (!on) await tap(p, `#gtWizard [onclick="gtPlanToggle('${r}')"]`, 500);
    }
    await p.waitForTimeout(800);
    await tap(p, '#gtWizard [onclick="gtPlanSave()"]', 2500);
    console.log('  plan', execSync(`psql -h /tmp -p 5433 -U postgres -d gtinst -Atc "select settings->'screensPlan'->'screens' from settings_pilot"`).toString().trim());
    await cap(p, 'i9', 2800);
    await tap(p, '#gtWizard [onclick="gtWizardClose(true)"] >> nth=0', 2500);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    await cap(p, 'i10', 3500);
    await done(x, '01-install');
  },
  async slaughter(b) { await station(b, 'slaughter', '02-slaughter', async p => {
    await login(p, 'slaughter'); await cap(p, 's1');
    for (let i = 0; i < 4; i++) await tap(p, '#tSlBtnS', 1300);
    await cap(p, 's2', 900); await tap(p, '#tSlBtnN', 1300); await tap(p, '#tSlBtnS', 1300);
    await cap(p, 's3', 1200); await tap(p, cell(6), 2400);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
  }); },
  async esophagus(b) { await station(b, 'esophagus', '03-esophagus', async p => {
    await cap(p, 'e1', 1500); await login(p, 'esophagus');
    await cap(p, 'e2', 1000); await tap(p, cell(3), 2400);
    await cap(p, 'e3', 1000);
    for (const n of [1, 2, 3, 4, 6]) { await tap(p, cell(n), 900); await tap(p, `[onclick="esoDecide('ok')"]`, 1000); }
  }); },
  async legs(b) { await station(b, 'legs', '04-legs', async p => {
    await login(p, 'legs'); await cap(p, 'l1', 2000);
    await cap(p, 'l2', 800); await tap(p, cell(1), 1800);
    await showSticker(p, 0, 'legs', 'k_legs');
    await cap(p, 'l3', 800); await tap(p, cell(1), 1800);
    await showSticker(p, 0, 'head', 'k_head');
    await cap(p, 'l4', 800);
    for (const n of [2, 3, 4, 5, 6]) { await tap(p, cell(n), 1900); await tap(p, cell(n), 1900); }
    await showSticker(p, 4, 'legs', 'k_nev');
  }); },
  async inner(b) { await station(b, 'inner', '05-inner', async p => {
    await login(p, 'inner'); await cap(p, 'in1', 1000);
    const open = async (n, say) => { await tap(p, cell(n), 1000); if (await p.locator('#rumenModal.open').count()) { if (say) await cap(p, 'in2', 800); await tap(p, `[onclick="rumenDecide('k')"]`, 1000); } };
    await open(1, true); await cap(p, 'in3', 800); await tap(p, '#tMawK', 1200);
    await cap(p, 'in4', 900); await tap(p, cell(1), 1500);
    const c = await p.locator('#lungDraw').boundingBox();
    if (c) { const sx = c.x + c.width * 0.35, sy = c.y + c.height * 0.4; await finger(p, sx, sy, false); await p.mouse.move(sx, sy); await p.mouse.down();
      for (let i = 1; i <= 20; i++) { const X = sx + i * 6, Y = sy + Math.sin(i / 3) * 30; await p.mouse.move(X, Y); await p.evaluate(([x, y]) => { const f = document.getElementById('gtFinger'); f.style.left = x + 'px'; f.style.top = y + 'px'; }, [X, Y]); await p.waitForTimeout(40); }
      await p.mouse.up(); }
    await cap(p, 'in5', 1000); await tap(p, '#tLConfirm', 1500);
    await open(2); await tap(p, '#tMawK', 900); await tap(p, cell(2), 1200); await tap(p, '#tLConfirm', 1300);
    await cap(p, 'in6', 1000); await open(3); await tap(p, '#tMawT', 1600); await tap(p, '#tMawT', 1600);
    await cap(p, 'in7', 800);
    for (const n of [4, 6]) { await open(n); await tap(p, '#tMawK', 900); await tap(p, cell(n), 1200); await tap(p, '#tLConfirm', 1200); }
  }); },
  async outer(b) { await station(b, 'outer', '06-outer', async p => {
    await login(p, 'outer'); await cap(p, 'o1', 1000);
    await tap(p, cell(1), 2600); await cap(p, 'o2', 800); await tap(p, '#decModal .dec-btns button:has-text("גלאט")', 1300);
    await cap(p, 'o3', 800);
    await tap(p, cell(2), 1300); await tap(p, '#decModal .dec-btns button:has-text("בית יוסף")', 1300);
    await tap(p, cell(4), 1300); await tap(p, '#decModal .dec-btns button:has-text("גלאט")', 1300);
    await tap(p, cell(6), 1300); await tap(p, '#decModal .dec-btns button:has-text("כשר")', 1300);
    await cap(p, 'o4', 2500);
  }); },
  async legsSort(b) { await station(b, 'legs', '07-legs-sort', async p => {
    await login(p, 'legs');
    await tap(p, '#lgModeSort', 1500);
    await cap(p, 'ls1', 1200);
    for (const [n, key] of [[1, 'ls2'], [2, null], [3, 'ls3']]) {
      const code = await p.evaluate(i => buildStickerPayload(i), n - 1);
      await p.evaluate(() => { const i = document.getElementById('lgScanInput'); if (i) i.focus(); });
      await p.keyboard.type(code, { delay: 8 }); await p.keyboard.press('Enter');
      await p.waitForTimeout(600); if (key) await cap(p, key, 2200); else await p.waitForTimeout(2200);
      await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    }
  }); },
  async parts(b) { await station(b, 'parts', '08-parts', async p => {
    await login(p, 'parts'); await cap(p, 'p1', 1000);
    await cap(p, 'p2', 800); await tap(p, cell(3), 2400);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    await cap(p, 'p3', 800); await tap(p, cell(1), 2400);
    await showSticker(p, 0, 'kosher', 'k_parts1');
    await cap(p, 'p4', 600); await tap(p, cell(2), 2400);
    await showSticker(p, 1, 'kosher', 'k_parts2');
  }); },
  async stamps(b) { await station(b, 'stamps', '09-stamps', async p => {
    await login(p, 'stamps'); await cap(p, 'st1', 1000);
    await cap(p, 'st2', 600);
    const code = await p.evaluate(() => buildStickerPayload(0));
    await p.evaluate(() => { try { stampsFocusScan(); } catch (e) { } });
    await p.keyboard.type(code, { delay: 8 }); await p.keyboard.press('Enter');
    await p.waitForTimeout(3600);
    await showSticker(p, 0, 'kosher', 'k_stamp');
    await cap(p, 'st3', 800);
    await p.evaluate(() => { try { stampsFocusScan(); } catch (e) { } });
    await p.keyboard.type('245.5 kg', { delay: 60 }); await p.keyboard.press('Enter'); await p.waitForTimeout(2200);
    await p.keyboard.type('238.0 kg', { delay: 60 }); await p.keyboard.press('Enter'); await p.waitForTimeout(2500);
    console.log('  after weight', JSON.stringify(await state(p)));
    await cap(p, 'st4', 1500);
  }); },
  async leader(b) {
    execSync('bash ' + __dirname + '/rl.sh');
    const x = await ctxFor(b, '10-leader', langInit); const p = x.p;
    await p.goto(MAIN); await p.waitForTimeout(7000);
    await p.evaluate(() => { document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')); mgrEnter(); }); await p.waitForTimeout(1000);
    await p.fill('#loginCodeInput', 'e2e-tl-code-7731'); await p.evaluate(() => [...document.querySelectorAll('#loginModal button')].pop().click());
    for (let i = 0; i < 20; i++) { await p.waitForTimeout(800); const ok = await p.evaluate(async () => { try { const r = await window.sb.rpc('system_health', { p_token: KS.getManagerToken() }); return !!(r.data && r.data.ok); } catch (e) { return false; } }); if (ok) break; }
    await p.evaluate(() => { document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')); try { gtWizardClose(true); } catch (e) { } });
    await p.waitForTimeout(1500);
    await tap(p, `[onclick*="mgrTab('search')"]`, 600);
    await p.evaluate(() => { try { gtAnimalCard(null, 0); } catch (e) { } }); await p.waitForTimeout(3000);
    await cap(p, 't1', 3000);
    await p.mouse.wheel(0, 400); await p.waitForTimeout(1500);
    await cap(p, 't2', 2500);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    await p.evaluate(en => { const b = document.createElement('div'); b.setAttribute('data-no-i18n', ''); b.style.cssText = 'position:fixed;inset:0;z-index:2147483600;background:#2a2f3a;display:flex;flex-wrap:wrap;gap:10px;padding:14px;align-content:flex-start;overflow:hidden'; document.body.appendChild(b);
      const items = [['legs','slaughtered'],['legs','notChalak'],['legs','nevela'],['kosher','glatt'],['kosher','beit'],['kosher','kosher'],['kosher','mk'],['kosher','kosherRab']];
      items.forEach((it, i) => { const d = document.createElement('div'); d.id = 'g' + i; b.appendChild(d); renderSticker('g' + i, i, it[0], { status: it[1], num: i + 1 }); }); }, LANG === 'en');
    await p.waitForTimeout(600);
    await cap(p, 't3', 1500); await cap(p, 't4', 5000);
    await done(x, '10-leader');
  },
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  for (const [k, fn] of Object.entries(scenes)) { if (ONLY && !ONLY.includes(k)) continue; console.log('scene', k); await fn(browser); }
  await browser.close();
  const f = OUT + '/captions.json'; const old = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f)) : {};
  fs.writeFileSync(f, JSON.stringify(Object.assign(old, LOG), null, 1));
})();
