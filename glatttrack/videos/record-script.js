// GlattTrack — live recording, Hebrew or English (LANG=he|en), in the plant's working order:
// first installation → team leader picks the screens → slaughter → esophagus → legs & head (stickers)
// → inner → outer → legs sorting → small parts (stickers) → stamps + weighing → team leader.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const { execSync } = require('child_process');
const LANG = process.env.LANG_V || 'he';
const APP = process.env.APP;
const OUT = __dirname + '/raw7-' + LANG; fs.mkdirSync(OUT, { recursive: true });
const MAIN = 'http://localhost:8083/', INST = 'http://localhost:8084/';
const C = require('./caps7.js');
const DUR = JSON.parse(fs.readFileSync(__dirname + '/voice-' + LANG + '7/durations.json'));
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
const VP = { width: 800, height: 560 };   // small CSS screen, recorded at 2x: big and sharp on a phone
const VS = { width: 1600, height: 1120 };
const LOG = {};          // clip → [{t, key}]
const SCR = ['Slaughter','Esophagus','Legs','Inner','Outer','Parts','Stamps'];

const OVERLAY = () => {
  const css = document.createElement('style');
  css.textContent = `#gtCap{position:fixed;left:50%;bottom:14px;transform:translateX(-50%);z-index:2147483647;max-width:64%;
    background:rgba(10,14,24,.93);color:#fff;border:2px solid #E8B84A;border-radius:14px;padding:8px 18px;
    font:700 27px/1.35 Arial,sans-serif;text-align:center;pointer-events:none;box-shadow:0 6px 24px rgba(0,0,0,.5)}
    #gtCap:empty{display:none}
    #gtStep{position:fixed;bottom:16px;inset-inline-end:10px;z-index:2147483647;pointer-events:none;background:linear-gradient(135deg,#E8B84A,#B8862A);
      color:#0B0F18;font:800 15px/1 Arial,sans-serif;padding:7px 12px;border-radius:999px;box-shadow:0 4px 16px rgba(0,0,0,.45)}
    #gtStep:empty{display:none}
    #gtRing{position:fixed;z-index:2147483645;pointer-events:none;border:4px solid #FFD54A;border-radius:12px;box-shadow:0 0 0 6px rgba(255,213,74,.25),0 0 28px 6px rgba(255,213,74,.55);display:none;transition:all .25s ease}
    #gtFinger{position:fixed;width:46px;height:46px;margin:-23px 0 0 -23px;border-radius:50%;z-index:2147483646;pointer-events:none;
    background:rgba(255,215,0,.35);border:3px solid #FFD700;transition:left .45s ease,top .45s ease,transform .15s;display:none}
    #gtFinger.tap{transform:scale(.6);background:rgba(255,215,0,.75)}`;
  const add = () => { if (!document.head || !document.body) return setTimeout(add, 50);
    document.head.appendChild(css);
    const c = document.createElement('div'); c.id = 'gtCap'; c.setAttribute('data-no-i18n', ''); document.body.appendChild(c);
    const f = document.createElement('div'); f.id = 'gtFinger'; document.body.appendChild(f);
    const s = document.createElement('div'); s.id = 'gtStep'; s.setAttribute('data-no-i18n', ''); document.body.appendChild(s);
    const r = document.createElement('div'); r.id = 'gtRing'; document.body.appendChild(r); };
  add();
  window._gtLicShown = true;   // the one-time license request window is not part of this film
  const t = setInterval(() => { if (window.gtStatusSet && !window.gtStatusSet.__v) { const o = window.gtStatusSet; window.gtStatusSet = function (k, txt) { if (/Realtime/i.test(String(txt || '')) || k === 'health') return; return o.apply(this, arguments); }; window.gtStatusSet.__v = 1; clearInterval(t); } }, 20);
};
async function useApp(ctx) {
  await ctx.route(u => { const x = new URL(u); return x.pathname === '/' || x.pathname.startsWith('/index'); },
    r => r.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: fs.readFileSync(APP) }));
}
// v2 timing: a caption waits only for the voice before it to end; the taps after it run while it is spoken
const LEAD = 900;
async function hold(p) { const w = (p.__end || 0) - Date.now(); if (w > 0) await p.waitForTimeout(w); }
async function cap(p, key, minMs = 2200) {
  await hold(p);
  const txt = C[key][LANG === 'en' ? 1 : LANG === 'es' ? 2 : 0];
  (LOG[p.__clip] = LOG[p.__clip] || []).push({ t: Date.now() - p.__t0, key });
  await p.evaluate(([t, dir]) => { const c = document.getElementById('gtCap'); if (c) { c.textContent = t; c.style.direction = dir; c.parentNode.appendChild(c); } }, [txt, LANG === 'he' ? 'rtl' : 'ltr']);
  p.__end = Date.now() + Math.max(minMs, Math.round((DUR[key] || 2) * 1000) + 700);
  await p.waitForTimeout(LEAD);
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
  await p.evaluate(([x, y, w, h]) => { const r = document.getElementById('gtRing'); if (!r) return; r.parentNode.appendChild(r);
    r.style.left = (x - 6) + 'px'; r.style.top = (y - 6) + 'px'; r.style.width = (w + 12) + 'px'; r.style.height = (h + 12) + 'px'; r.style.display = 'block';
    clearTimeout(window._gtRingT); window._gtRingT = setTimeout(() => { r.style.display = 'none'; }, 1400); }, [b.x, b.y, b.width, b.height]);
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
    if (!b) { b = document.createElement('div'); b.id = 'gtStk'; b.setAttribute('data-no-i18n', ''); b.style.cssText = 'position:fixed;inset:0;z-index:2147483600;background:rgba(0,0,0,.8);display:flex;align-items:center;justify-content:center;gap:20px;padding-bottom:110px'; document.body.appendChild(b); }
    b.innerHTML = '<div style="width:330px;height:330px;display:flex;align-items:center;justify-content:center"><div id="gtStkIn" style="transform:scale(1.35)"></div></div><div id="gtStkQr" style="background:#fff;color:#111;border-radius:12px;padding:10px 14px;font:15px/1.6 Arial;min-width:230px;max-width:290px"></div>';
    b.style.display = 'flex';
    renderSticker('gtStkIn', idx, kind, false);
    const pay = buildStickerPayload(idx) || '';
    const lab = en === 'es' ? { N: 'Número', D: 'Fecha', HD: 'Fecha hebrea', W: 'Día', TM: 'Hora', SH: 'Shojet', S: 'Estado al imprimir' }
              : en ? { N: 'Number', D: 'Date', HD: 'Hebrew date', W: 'Day', TM: 'Time', SH: 'Shochet', S: 'Status at printing' }
                   : { N: 'מספר', D: 'תאריך', HD: 'תאריך עברי', W: 'יום', TM: 'שעה', SH: 'שוחט', S: 'מצב בזמן ההדפסה' };
    const sw = { slaughtered: en === 'es' ? 'faenado' : en ? 'slaughtered' : 'נשחט', notChalak: 'לא חלק', nevela: 'נבלה', shot: 'ירוי' };
    const rows = pay.split('|').slice(1).map(x => { const i = x.indexOf(':'); const k = x.slice(0, i), v = x.slice(i + 1); if (k === 'T' || !v) return ''; return `<div><b>${lab[k] || k}:</b> <span dir="auto">${(k === 'S' ? (sw[v] || statusDisplayName(v, KS.getAnimal(idx)) || v) : v).replace(/</g, '&lt;')}</span></div>`; }).join('');
    document.getElementById('gtStkQr').innerHTML = `<div style="font-weight:800;font-size:17px;margin-bottom:6px;direction:${en ? 'ltr' : 'rtl'}">${en === 'es' ? 'Dentro del código QR' : en ? 'Inside the QR code' : 'מה יש בתוך ה-QR'}</div><div style="direction:${en ? 'ltr' : 'rtl'}">${rows}</div>`;
  }, [idx, kind, LANG === 'es' ? 'es' : LANG === 'en']);
  await cap(p, key, 4800); await hold(p);
  await p.evaluate(() => { const b = document.getElementById('gtStk'); if (b) b.style.display = 'none'; });
}

async function ctxFor(b, clip, init) {
  const ctx = await b.newContext({ viewport: VP, deviceScaleFactor: 2, recordVideo: { dir: OUT, size: VS } });
  await ctx.addInitScript(init.fn, init.arg); await ctx.addInitScript(OVERLAY); await useApp(ctx);
  const p = await ctx.newPage(); p.__clip = clip; p.__t0 = Date.now();
  p.on('dialog', d => d.accept()); p.on('pageerror', e => console.log('  pageerror', clip, e.message));
  return { ctx, p };
}
async function done(x, clip) { await hold(x.p); await x.p.waitForTimeout(400); const v = x.p.video(); await x.ctx.close(); if (v) fs.renameSync(await v.path(), `${OUT}/${clip}.webm`); }
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

function boardAsBefore() {
  execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -qc "begin; select set_config('gt.reset_in_progress','true',true); update animals_pilot set slaughter='slaughtered', slaughter_time=(extract(epoch from now())*1000)::bigint-3600000+id*60000, eso_checked=true, eso_result='ok', legs_stickers=true, head_stickers=true where id between 0 and 6; update animals_pilot set slaughter='nevela' where id=5; update animals_pilot set inner_status='confirmed', inner_time=(extract(epoch from now())*1000)::bigint-2000000 where id in (0,1,3,4,6); update animals_pilot set inner_status='treif' where id=2; update animals_pilot set outer_status=v.s, outer_time=(extract(epoch from now())*1000)::bigint-1000000 from (values (0,'mk'),(1,'beit'),(3,'glatt'),(4,'kosher'),(6,'glatt')) v(i,s) where id=v.i; commit;"`);
}
const scenesOld = {
  async install(b, clipName) {
    execSync('bash ' + __dirname + '/../mkinst.sh');
    execSync(`psql -h /tmp -p 5433 -U postgres -d gtinst -c "select _set_setup_code('ABCD-1234-XY')"`);
    const x = await ctxFor(b, clipName || '01-install', langInit); const p = x.p;
    await p.setContent('<html><body style="margin:0;background:#06080d"></body></html>');
    await p.evaluate(OVERLAY); await p.waitForTimeout(800);
    await cap(p, 'i1', 3000);
    await p.goto(INST); await p.waitForTimeout(1500);
    await cap(p, 'i2', 4500);
    await tap(p, '[onclick="gtStartFirstSetup()"]', 900);
    await cap(p, 'i4', 1500);
    await finger(p, 512, 290, false); await p.type('#gtFfName', LANG === 'he' ? 'משה כהן' : 'Moshe Cohen', { delay: 90 });
    await p.type('#gtFfCode', 'moshe-2026', { delay: 90 });
    await finger(p, 512, 430, false); await p.type('#gtFfSetup', 'ABCD-1234-XY', { delay: 110 });
    await p.waitForTimeout(500);
    await tap(p, '#gtFfOk', 200);
    await cap(p, 'i5', 3000);
    await p.waitForTimeout(6000);
    await cap(p, 'i6', 3500); await hold(p);
    await tap(p, '#gtWizard [onclick="gtWizGo(1)"]', 1200);
    await cap(p, 'i7', 2600); await hold(p);
    await tap(p, '#gtWizard button[onclick="gtWizGo(1)"] >> nth=0', 1500);
    await cap(p, 'i8', 2500);
    for (const r of ['slaughter', 'esophagus', 'inner', 'outer', 'legs', 'parts', 'stamps']) {
      const on = await p.evaluate(r => { try { return !!(_gtPlanDraft && _gtPlanDraft.screens.has(r)); } catch (e) { return false; } }, r);
      if (!on) await tap(p, `#gtWizard [onclick="gtPlanToggle('${r}')"]`, 500);
    }
    await p.waitForTimeout(800);
    await tap(p, '#gtWizard [onclick="gtPlanSave()"]', 2500);
    console.log('  plan', execSync(`psql -h /tmp -p 5433 -U postgres -d gtinst -Atc "select settings->'screensPlan'->'screens' from settings_pilot"`).toString().trim());
    await cap(p, 'i9', 2800); await hold(p);
    await tap(p, '#gtWizard [onclick="gtWizardClose(true)"] >> nth=0', 2500);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    await cap(p, 'i10', 3500);
    await done(x, clipName || '01-install');
  },
};
// ── v10.36 film: chapter cards, a station badge, and the new chapters ─────────
const LI = LANG === 'en' ? 1 : LANG === 'es' ? 2 : 0;
const BADGE = { install: ['⚙️ התקנה', '⚙️ Installation', '⚙️ Instalación'], statuses: ['✡️ סטטוסי כשרות', '✡️ Kashrut statuses', '✡️ Estados kosher'],
  slaughter: ['🔪 שחיטה', '🔪 Slaughter', '🔪 Faena'], esophagus: ['🩺 וושט', '🩺 Esophagus', '🩺 Esófago'], legs: ['🏷️ רגליים וראש', '🏷️ Legs and head', '🏷️ Patas y cabeza'],
  inner: ['🫁 בודק פנים', '🫁 Inner inspector', '🫁 Inspector interno'], outer: ['✅ בודק חוץ', '✅ Outer inspector', '✅ Inspector externo'],
  sort: ['🦵 מיון רגליים', '🦵 Leg sorting', '🦵 Clasificación de patas'], parts: ['👅 חלקים קטנים', '👅 Small parts', '👅 Partes pequeñas'],
  stamps: ['🔖 חותמות ושקילה', '🔖 Stamps and weighing', '🔖 Sellos y pesaje'], leader: ['👤 ראש הצוות', '👤 Team leader', '👤 Jefe de equipo'] };
const badge = (p, k) => p.evaluate(t => { const s = document.getElementById('gtStep'); if (s) { s.textContent = t; s.parentNode.appendChild(s); } }, k ? BADGE[k][LI] : '');
async function st(b, role, clip, bk, fn) { await station(b, role, clip, async p => { await badge(p, bk); await fn(p); }); }
const BY = LANG === 'he' ? 'בית יוסף' : 'Beit Yosef';     // the status the plant adds itself in this film (neutral: no kashrut body's name)

// a designed full-screen card, narrated (chapter / intro / outro / behind the scenes)
async function card(b, clip, key, o = {}) {
  const x = await ctxFor(b, clip, langInit); const p = x.p;
  const txt = C[key][LI], dir = LANG === 'he' ? 'rtl' : 'ltr';
  const title = o.title || txt.replace(/^[^:]*:\s*/, ''), num = o.num || '';
  await p.setContent(`<html><body style="margin:0"></body></html>`);
  await p.evaluate(OVERLAY);
  await p.evaluate(([title, num, dir, icon, small, big]) => {
    document.body.style.cssText = 'margin:0;height:100vh;overflow:hidden;font-family:Arial,sans-serif;background:radial-gradient(1200px 700px at 30% 20%,#1d2a44 0%,#0b1120 55%,#05070d 100%);color:#fff;display:flex;align-items:center;justify-content:center;direction:' + dir;
    const d = document.createElement('div'); d.style.cssText = 'text-align:center;max-width:90%;animation:gtIn .8s ease both';
    const st = document.createElement('style'); st.textContent = '@keyframes gtIn{from{opacity:0;transform:translateY(24px) scale(.97)}to{opacity:1;transform:none}} @keyframes gtBar{from{width:0}to{width:220px}}';
    document.head.appendChild(st);
    d.innerHTML = (icon ? `<div style="font-size:${big ? 92 : 70}px;margin-bottom:10px">${icon}</div>` : '')
      + (num ? `<div style="display:inline-block;font:800 20px/1 Arial;color:#0b1120;background:linear-gradient(135deg,#E8B84A,#B8862A);padding:9px 18px;border-radius:999px;margin-bottom:18px">${num}</div>` : '')
      + `<div style="font:800 ${big ? 64 : 46}px/1.15 'Frank Ruhl Libre',Georgia,serif;color:#F3D27A;text-shadow:0 4px 24px rgba(232,184,74,.35)">${title}</div>`
      + `<div style="height:4px;background:linear-gradient(90deg,#E8B84A,transparent);margin:22px auto 0;animation:gtBar 1.1s .3s ease both;border-radius:4px"></div>`
      + (small ? `<div style="font:500 24px/1.45 Arial;color:#C9D3E6;margin-top:22px;max-width:760px;margin-inline:auto">${small}</div>` : '')
    ;
    document.body.appendChild(d);
    const br = document.createElement('div'); br.style.cssText = 'position:fixed;bottom:18px;inset-inline-end:24px;font:700 16px Arial;color:#6B7D99;letter-spacing:.5px'; br.textContent = 'GlattTrack · v10.36'; document.body.appendChild(br);
  }, [title, num, dir, o.icon || '', o.small || '', !!o.big]);
  await p.waitForTimeout(700);
  if (o.small && !o.big) await p.evaluate(() => { const c = document.getElementById('gtCap'); if (c) c.style.visibility = 'hidden'; });
  await cap(p, key, o.min || 2600); await hold(p);
  await p.evaluate(() => { const c = document.getElementById('gtCap'); if (c) c.textContent = ''; });
  await p.waitForTimeout(500);
  await done(x, clip);
}
const CH = (n) => ({ num: (['פרק', 'Chapter', 'Capítulo'][LI]) + ' ' + n });

function cleanPlant() {
  execSync('bash ' + __dirname + '/reset.sh');
  execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -qc "delete from daily_board_archive"`);   // the summaries show only this film's day
  execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -qc "update settings_pilot set settings = (settings - 'statusNames' - 'legsHeadSplit' - 'legsPaused' - 'partsPaused') || '{\\"customStatuses\\":[],\\"ncStatuses\\":[\\"kosher\\"],\\"removedDefaults\\":[\\"beit\\",\\"mk\\",\\"rabChalak\\"],\\"disabledStatuses\\":[],\\"statusOptIn\\":[],\\"notChalakEnabled\\":true,\\"screenConfig\\":\\"1in1out\\"}'::jsonb, updated_at=now(), device_id='server' where id=1"`);
}
async function leaderIn(b, clip) {
  execSync('bash ' + __dirname + '/rl.sh');
  const x = await ctxFor(b, clip, langInit); const p = x.p;
  await p.goto(MAIN); await p.waitForTimeout(7000);
  await p.evaluate(() => { document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')); mgrEnter(); }); await p.waitForTimeout(1000);
  await p.fill('#loginCodeInput', 'e2e-tl-code-7731'); await p.evaluate(() => [...document.querySelectorAll('#loginModal button')].pop().click());
  for (let i = 0; i < 20; i++) { await p.waitForTimeout(800); const ok = await p.evaluate(async () => { try { const r = await window.sb.rpc('system_health', { p_token: KS.getManagerToken() }); return !!(r.data && r.data.ok); } catch (e) { return false; } }); if (ok) break; }
  await p.evaluate(() => { document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')); try { gtWizardClose(true); } catch (e) { } });
  await p.waitForTimeout(1500);
  await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
  await badge(p, 'leader');
  // the day's animals and the plant's own statuses are here before anything is shown
  for (let i = 0; i < 40; i++) { const ok = await p.evaluate(() => (KS.getAnimals() || []).filter(a => a && a.outerStatus).length >= 6 && getAllStatuses().some(x => /^custom_/.test(x.key))); if (ok) break; await p.waitForTimeout(500); }
  await p.waitForTimeout(2500);
  return x;
}
const openTo = (p, sel) => p.evaluate(sel => { const el = document.querySelector(sel); if (!el) return; let n = el; while (n) { if (n.tagName === 'DETAILS') n.open = true; n = n.parentElement; } el.scrollIntoView({ block: 'start' }); window.scrollBy && window.scrollBy(0, -60); }, sel);

const scenes = {
  async intro(b) { cleanPlant(); await card(b, '00-intro', 'intro', { title: 'GlattTrack', icon: '✡️', big: true, small: ['מעקב כשרות בבית שחיטה', 'Kashrut tracking in the slaughterhouse', 'Control kosher en el matadero'][LI], min: 3500 }); },
  async c1(b) { await card(b, '01a-card', 'c1', Object.assign(CH(1), { icon: '⚙️' })); },
  async install(b) { await scenesOld.install(b, '01b-install'); },
  async c2(b) { await card(b, '02a-card', 'c2', Object.assign(CH(2), { icon: '✡️' })); },
  async statuses(b) {
    const x = await leaderIn(b, '02b-statuses'); const p = x.p; await badge(p, 'statuses');
    try {
      await tap(p, `[onclick*="mgrTab('settings')"]`, 1200);
      await p.evaluate(() => mgrUpdateStatusToggles());
      await openTo(p, '#mgrStatusToggles'); await p.waitForTimeout(1200);
      await cap(p, 'ss1', 2500); await hold(p);
      await tap(p, 'button[onclick="mgrAddStatus()"]', 1500);
      await cap(p, 'ss2', 900);
      await finger(p, 400, 200, false); await p.type('#newStatusHe', BY, { delay: 110 }); await p.waitForTimeout(500);
      await p.selectOption('#newStatusGroup', 'chalak'); await p.waitForTimeout(900);
      await cap(p, 'ss3', 900);
      await p.type('#newStatusStickerHe', 'בית יוסף', { delay: 90 }); await p.type('#newStatusEn', 'Beit Yosef', { delay: 70 });
      await tap(p, '#mgrAddStatusForm button[data-col] >> nth=4', 900);
      await tap(p, '#mgrAddStatusForm button[onclick="mgrConfirmAddStatus()"]', 1800);
      await p.evaluate(() => { const r = [...document.querySelectorAll('[data-status-row]')].pop(); if (r) r.scrollIntoView({ block: 'center' }); }); await p.waitForTimeout(1200);
      await cap(p, 'ss5', 1500); await hold(p);
      await tap(p, '[data-status-row="glatt"] span[onclick]', 1500);
      await cap(p, 'ss4', 1500); await hold(p);
      await tap(p, '#mgrNameEdit button >> nth=0', 1000);
      await openTo(p, '#mgrNcStatusesBox'); await p.waitForTimeout(1200);
      await cap(p, 'ss6', 1500);
    } catch (e) { console.log('  FAIL statuses', e.message.split('\n')[0]); }
    console.log('  statuses', execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "select settings->>'ncStatuses', (select string_agg(x->>'he',',') from jsonb_array_elements(settings->'customStatuses') x) from settings_pilot"`).toString().trim());
    // the sample kashrut mark ("SAMPLE") of Beit Yosef goes with the status the plant added
    execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -qc "insert into kashrut_seals(key,image,updated_by) select c->>'key', (select image from kashrut_seals where key='beit'), 'demo' from settings_pilot, jsonb_array_elements(settings->'customStatuses') c where id=1 on conflict(key) do update set image=excluded.image; insert into plant_state(key,value) values('sealsVersion',(extract(epoch from now())*1000)::bigint::text) on conflict(key) do update set value=excluded.value;"`);
    await done(x, '02b-statuses');
  },
  async c3(b) { await card(b, '03a-card', 'c3', Object.assign(CH(3), { icon: '🔪' })); },
  async slaughter(b) { await st(b, 'slaughter', '03b-slaughter', 'slaughter', async p => {
    await login(p, 'slaughter'); await cap(p, 's1');
    for (let i = 0; i < 4; i++) await tap(p, '#tSlBtnS', 1300);
    await cap(p, 's4q', 900); await tap(p, '#tSlBtnQ', 2600);
    await cap(p, 's5q', 1200);
    await cap(p, 's2', 900); await tap(p, '#tSlBtnN', 1300); await tap(p, '#tSlBtnS', 1300);
    await cap(p, 's8', 900); await tap(p, '#tSlBtnNC', 2200);
    await cap(p, 's6q', 900); await tap(p, cell(5), 1600);
    await tap(p, '#gtSheet .gt-row .gt-sb >> nth=0', 2200);
    await cap(p, 's3', 1200); await tap(p, cell(7), 2400);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
  }); },
  async c4(b) { await card(b, '04a-card', 'c4', Object.assign(CH(4), { icon: '🩺' })); },
  async esophagus(b) { await st(b, 'esophagus', '04b-esophagus', 'esophagus', async p => {
    await cap(p, 'e1', 1500); await login(p, 'esophagus');
    await cap(p, 'e2', 1000); await tap(p, cell(3), 2400);
    await cap(p, 'e3', 1000);
    for (const n of [1, 2, 3, 4, 5, 7, 8]) { await tap(p, cell(n), 900); await tap(p, `[onclick="esoDecide('ok')"]`, 1000); }
  }); },
  async c5(b) { await card(b, '05a-card', 'c5', Object.assign(CH(5), { icon: '🏷️' })); },
  async legs(b) { await st(b, 'legs', '05b-legs', 'legs', async p => {
    await login(p, 'legs'); await cap(p, 'l1', 2000);
    await cap(p, 'l2', 800); await tap(p, cell(1), 1800);
    await showSticker(p, 0, 'legs', 'k_legs');
    await cap(p, 'l3', 800); await tap(p, cell(1), 1800);
    await showSticker(p, 0, 'head', 'k_head');
    await cap(p, 'l4', 800);
    for (const n of [2, 3, 4, 5, 6, 7, 8]) { await tap(p, cell(n), 1700); await tap(p, cell(n), 1700); }
    await showSticker(p, 5, 'legs', 'k_nev');
  }); },
  async c6(b) { await card(b, '06a-card', 'c6', Object.assign(CH(6), { icon: '🫁' })); },
  async inner(b) { await st(b, 'inner', '06b-inner', 'inner', async p => {
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
    await cap(p, 'in8', 1000); await open(4);
    await tap(p, '#gtQMaw', 2200);
    await cap(p, 'in9', 2500);
    await cap(p, 'in7', 800);
    for (const n of [5, 7, 8]) { await open(n); await tap(p, '#tMawK', 900); await tap(p, cell(n), 1200); await tap(p, '#tLConfirm', 1200); }
    await cap(p, 'in10', 900); await tap(p, cell(4), 1500);
    await tap(p, '#tMawK', 1300); await tap(p, cell(4), 1300);
    await tap(p, '#tLConfirm', 2000);
  }); },
  async c7(b) { await card(b, '07a-card', 'c7', Object.assign(CH(7), { icon: '✅' })); },
  async outer(b) { await st(b, 'outer', '07b-outer', 'outer', async p => {
    await login(p, 'outer'); await cap(p, 'o1', 1000);
    await tap(p, cell(1), 2600); await cap(p, 'o2', 800); await tap(p, '#decModal .dec-btns button:has-text("גלאט")', 1300);
    await cap(p, 'o3', 800);
    await tap(p, cell(2), 1300); await tap(p, `#decModal .dec-btns button:has-text("${BY}")`, 1300);
    await tap(p, cell(4), 1300); await tap(p, '#decModal .dec-btns button:has-text("גלאט")', 1300);
    await tap(p, cell(5), 1300); await tap(p, '#decModal .dec-btns button:has-text("כשר")', 1300);
    await tap(p, cell(7), 1300); await tap(p, `#decModal .dec-btns button:has-text("${BY}")`, 1300);
    await tap(p, cell(8), 2400); await cap(p, 'o5', 2500); await hold(p);
    await tap(p, '#decModal .dec-btns button:has-text("כשר")', 1500); await cap(p, 'o6', 1500);
    await cap(p, 'o4', 2500);
  }); },
  async c8(b) { await card(b, '08a-card', 'c8', Object.assign(CH(8), { icon: '🦵' })); },
  async legsSort(b) { await st(b, 'legs', '08b-legs-sort', 'sort', async p => {
    await login(p, 'legs');
    await tap(p, '#lgModeSort', 1500);
    await cap(p, 'ls1', 1200);
    for (const [n, key] of [[1, 'ls2'], [2, null], [3, 'ls3']]) {
      const code = await p.evaluate(i => buildStickerPayload(i), n - 1);
      await p.evaluate(() => { const i = document.getElementById('lgScanInput'); if (i) i.focus(); });
      await p.keyboard.type(code, { delay: 8 }); await p.keyboard.press('Enter');
      await p.waitForTimeout(600); if (key) { await cap(p, key, 2200); await hold(p); } else await p.waitForTimeout(2200);
      await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    }
  }); },
  async c9(b) { await card(b, '09a-card', 'c9', Object.assign(CH(9), { icon: '👅' })); },
  async parts(b) { await st(b, 'parts', '09b-parts', 'parts', async p => {
    await login(p, 'parts'); await cap(p, 'p1', 1000);
    await cap(p, 'p2', 800); await tap(p, cell(3), 2400); await hold(p);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    await cap(p, 'p5', 900); await tap(p, '#scParts .gt-tbu', 1200);
    await p.fill('#gtHoldNum', '1'); await p.waitForTimeout(500);
    await tap(p, '#gtSheet .gt-up[data-part="tongue"]', 1200);
    await tap(p, '#gtUsdaOk', 2400);
    await cap(p, 'p3', 800); await tap(p, cell(1), 2600);
    await showSticker(p, 0, 'kosher', 'k_parts1');
    await cap(p, 'p6', 900); await tap(p, '#scParts .gt-tbl', 1500);
    await tap(p, '#gtSheet .gt-hrow .gt-sb >> nth=0', 3200);
    await cap(p, 'p4', 600); await tap(p, cell(2), 2400);
    await showSticker(p, 1, 'kosher', 'k_parts2');
  }); },
  async c10(b) { await card(b, '10a-card', 'c10', Object.assign(CH(10), { icon: '🔖' })); },
  async stamps(b) { await st(b, 'stamps', '10b-stamps', 'stamps', async p => {
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
    await cap(p, 'st4', 1500);
  }); },
  async c11(b) { await card(b, '11a-card', 'c11', Object.assign(CH(11), { icon: '👤' })); },
  async leader(b) {
    const x = await leaderIn(b, '11b-leader'); const p = x.p;
    await tap(p, `[onclick*="mgrTab('search')"]`, 600);
    await p.evaluate(() => { try { gtAnimalCard(null, 0); } catch (e) { } }); await p.waitForTimeout(3000);
    await cap(p, 't1', 3000); await hold(p);
    await p.mouse.wheel(0, 400); await p.waitForTimeout(1500);
    await cap(p, 't2', 2500); await hold(p);
    await p.evaluate(() => document.querySelectorAll('.overlay.open').forEach(o => o.classList.remove('open')));
    await tap(p, `[onclick*="mgrTab('analysis')"]`, 1500);
    for (let i = 0; i < 20; i++) { await p.evaluate(() => { try { gtAnRender(); } catch (e) { } }); await p.waitForTimeout(1500);
      const ok = await p.evaluate(() => { const t = document.querySelector('details.gt-acc[data-k="kashrut"]'); return !!t && /Beit Yosef|בית יוסף/.test(t.textContent) && !/Deleted status|Estado borrado|סטטוס שנמחק/.test(t.textContent); }); if (ok) break; }
    await p.evaluate(() => { const d = document.querySelector('details.gt-acc[data-k="kashrut"]'); if (d) { d.open = true; d.scrollIntoView({ block: 'start' }); } }); await p.waitForTimeout(1800);
    await cap(p, 't5', 3500); await hold(p);
    await p.evaluate(en => { const b = document.createElement('div'); b.setAttribute('data-no-i18n', ''); b.style.cssText = 'position:fixed;left:0;top:0;width:1000px;z-index:2147483600;background:#2a2f3a;display:flex;flex-wrap:wrap;gap:10px;padding:14px;align-content:flex-start;overflow:hidden;transform:scale(.78);transform-origin:top left;height:715px'; document.body.appendChild(b);
      const by = ((KS.getSettings().customStatuses || [])[0] || {}).key || 'kosher';
      const items = [['legs','slaughtered'],['legs','notChalak'],['legs','nevela'],['kosher','glatt'],['kosher',by]];
      items.forEach((it, i) => { const d = document.createElement('div'); d.id = 'g' + i; b.appendChild(d); renderSticker('g' + i, i, it[0], { status: it[1], num: i + 1 }); }); }, LANG === 'en');
    await p.waitForTimeout(600);
    await cap(p, 't3', 1500); await cap(p, 't4', 5000);
    await done(x, '11b-leader');
  },
  async c12(b) { await card(b, '12a-card', 'c12', Object.assign(CH(12), { icon: '🛡️' })); },
  async behind(b) {
    await card(b, '12b-update', 'b1', { icon: '🔄', title: ['עדכון תוכנה', 'Software updates', 'Actualizaciones'][LI], small: C.b1[LI] });
    await card(b, '12c-offline', 'b2', { icon: '📡', title: ['בלי חיבור לשרת', 'No server connection', 'Sin conexión al servidor'][LI], small: C.b2[LI] });
    await card(b, '12d-backup', 'b3', { icon: '💾', title: ['גיבוי והיצרן', 'Backup and the maker', 'Copia y el fabricante'][LI], small: C.b3[LI] });
  },
  async outro(b) { await card(b, '13-outro', 'outro', { title: 'GlattTrack', icon: '✡️', big: true, small: C.outro[LI].replace(/^GlattTrack\.\s*/, ''), min: 3500 }); },
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--force-device-scale-factor=2'] });
  const f = OUT + '/captions.json';
  for (const [k, fn] of Object.entries(scenes)) { if (ONLY && !ONLY.includes(k)) continue; console.log('scene', k);
    try { await fn(browser); } catch (e) { console.log('  SCENE FAIL', k, e.message.split('\n')[0]); }
    const old = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f)) : {}; fs.writeFileSync(f, JSON.stringify(Object.assign(old, LOG), null, 1)); }
  await browser.close();
})();
