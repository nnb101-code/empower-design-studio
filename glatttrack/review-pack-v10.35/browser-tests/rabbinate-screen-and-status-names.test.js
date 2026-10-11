// v10.17 checks: fixed status names, rabbinate send + rulings, settings, stickers
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const OUT = __dirname + '/shots17'; require('fs').mkdirSync(OUT, { recursive: true });
const Q = sql => execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${sql}"`).toString().trim();
const URL = 'process.env.GT_URL || 'http://localhost:8081/'';
const scr = ['Slaughter','Esophagus','Legs','Inner','Outer','Parts','Stamps'];
async function dev(b, id, tok, role, idx, langv) {
  const ctx = await b.newContext({ viewport: { width: 1024, height: 700 } });
  await ctx.addInitScript(([id, tok, role, idx, langv, scr]) => {
    if (localStorage.getItem('i')) return;
    localStorage.setItem('ks_device_token', tok); localStorage.setItem('ks_kiosk_role', role);
    localStorage.setItem('ks_kiosk_index', String(idx)); localStorage.setItem('ks_device_id', id); localStorage.setItem('i', '1');
    const m = {}; scr.forEach(s => { m['sc' + s] = langv; m['sc' + s + 'Login'] = langv; }); localStorage.setItem('ks_lang_by_screen', JSON.stringify(m));
  }, [id, tok, role, idx, langv, scr]);
  const p = await ctx.newPage(); p.on('dialog', d => d.accept()); p.on('pageerror', e => console.log('  pageerror', e.message));
  await p.goto(URL); await p.waitForTimeout(6500);
  return p;
}
const btns = p => p.evaluate(() => [...document.querySelectorAll('#decModal .dec-btns button')].map(b => b.innerText.trim()));
const cell = n => `.screen.active .num-cell[data-idx="${n - 1}"]`;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  // glatt screen (outer #1)
  const A = await dev(b, 'e2e_outer_0001', 'tok-outer-e2e-00000000000000001', 'outer', 0, 'he');
  await A.click('[onclick="outLogin()"]'); await A.waitForTimeout(1500);
  console.log('A title:', await A.evaluate(() => (document.getElementById('outRoleTitle') || {}).textContent));
  await A.click(cell(1)); await A.waitForTimeout(1500);
  console.log('A #1 buttons:', JSON.stringify(await btns(A)));
  await A.screenshot({ path: OUT + '/1-glatt-screen-send.png' });
  // send → the app's own confirm modal
  await A.click('#decModal [data-tonc="1"]'); await A.waitForTimeout(800);
  await A.screenshot({ path: OUT + '/2-send-confirm.png' });
  const conf = await A.evaluate(() => { const o = [...document.querySelectorAll('.overlay.open, [id*=confirm]')].map(x => x.innerText).join(' || '); return o.slice(0, 300); });
  console.log('confirm text:', conf.replace(/\n/g, ' '));
  await A.evaluate(() => { const bs = [...document.querySelectorAll('button')].filter(b => b.offsetParent && /אישור|כן|OK|לשלוח|שלח/.test(b.innerText)); const last = bs.pop(); if (last) last.click(); });
  await A.waitForTimeout(2500);
  console.log('server #1 after send:', Q("select coalesce(outer_status,'-')||' nco='||not_chalak_outer from animals_pilot where id=0"));
  // rabbinate screen (outer #2), English UI
  const B = await dev(b, 'demo_outer2', 'tok-demo-outer2-0000000000000000', 'outer', 1, 'en');
  await B.click('[onclick="outLogin()"]').catch(() => B.evaluate(() => outLogin(1))); await B.waitForTimeout(1500);
  console.log('B title:', await B.evaluate(() => (document.getElementById('outRoleTitle') || {}).textContent));
  await B.click(cell(1)); await B.waitForTimeout(1500);
  console.log('B #1 (sent) buttons:', JSON.stringify(await btns(B)));
  await B.screenshot({ path: OUT + '/3-rabbinate-sent-en.png' });
  await B.click('#decModal .dec-btns button:has-text("רבנות חלק")'); await B.waitForTimeout(2500);
  console.log('server #1:', Q("select coalesce(outer_status,'-') from animals_pilot where id=0"));
  await B.click(cell(3)); await B.waitForTimeout(1500);
  console.log('B #3 (shochet NC) buttons:', JSON.stringify(await btns(B)));
  await B.screenshot({ path: OUT + '/4-rabbinate-nc-en.png' });
  await B.click('#decModal .dec-btns button:has-text("רבנות כשר")'); await B.waitForTimeout(2500);
  console.log('server #3:', Q("select coalesce(outer_status,'-') from animals_pilot where id=2"));
  // glatt screen rules #2 glatt, #4 MK → English grid
  await A.evaluate(() => { cycleLang(); }); await A.waitForTimeout(500);
  await A.click(cell(2)); await A.waitForTimeout(1200); await A.click('#decModal .dec-btns button:has-text("גלאט")'); await A.waitForTimeout(1500);
  await A.click(cell(4)); await A.waitForTimeout(1200); await A.click('#decModal .dec-btns button:has-text("MK")'); await A.waitForTimeout(2000);
  console.log('A grid (en):', await A.evaluate(() => [...document.querySelectorAll('.screen.active .num-cell')].slice(0, 4).map(c => c.innerText.replace(/\n/g, ':')).join(' | ')));
  console.log('A lang:', await A.evaluate(() => lang));
  await A.screenshot({ path: OUT + '/5-glatt-grid-en.png' });
  await b.close();
})();
