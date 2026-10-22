const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const Q = sql => execSync(`psql -h /tmp -p 5433 -U postgres -d gtapp -Atc "${sql}"`).toString().trim();
const OUT=__dirname+'/shots18'; require('fs').mkdirSync(OUT,{recursive:true});
async function dev(b,id,tok,role){ const ctx=await b.newContext({viewport:{width:1024,height:700}});
  await ctx.addInitScript(([id,tok,role])=>{ if(localStorage.getItem('i'))return; localStorage.setItem('ks_device_token',tok); localStorage.setItem('ks_kiosk_role',role); localStorage.setItem('ks_kiosk_index','0'); localStorage.setItem('ks_device_id',id); localStorage.setItem('i','1');
    const m={}; ['Slaughter','Legs','Outer','Inner'].forEach(s=>{m['sc'+s]='he';m['sc'+s+'Login']='he';}); localStorage.setItem('ks_lang_by_screen',JSON.stringify(m)); },[id,tok,role]);
  const p=await ctx.newPage(); p.on('dialog',d=>d.accept()); p.on('pageerror',e=>console.log('pageerror',e.message)); await p.goto(''+(process.env.GT_URL||'http://localhost:8082/')+''); await p.waitForTimeout(6500); return p; }
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const S=await dev(b,'demo_slaughter','tok-demo-slaughter-000000000000000','slaughter');
  await S.click('[onclick="slLogin()"]'); await S.waitForTimeout(1200);
  console.log('NC button:', await S.evaluate(()=>{const x=document.getElementById('tSlBtnNC');return x&&x.innerText+' visible='+!!x.offsetParent;}));
  for(const id of ['#tSlBtnS','#tSlBtnNC','#tSlBtnS']){ await S.click(id); await S.waitForTimeout(1200); }
  await S.screenshot({path:OUT+'/1-slaughter.png'});
  console.log('server:', Q("select string_agg(id||':'||slaughter||':'||coalesce(slaughtered_by,'-'),' ' order by id) from animals_pilot where slaughter is not null"));
  const L=await dev(b,'demo_legs','tok-demo-legs-000000000000000','legs');
  await L.click('[onclick="lgLogin()"]'); await L.waitForTimeout(1500);
  const pay=await L.evaluate(()=>buildStickerPayload(0)); console.log('legs QR payload #1:', pay);
  await L.evaluate(()=>{ const box=document.createElement('div'); box.style.cssText='position:fixed;inset:0;z-index:999999;background:#333;display:flex;gap:14px;padding:20px;flex-wrap:wrap'; document.body.appendChild(box);
    [0,1].forEach(i=>{const d=document.createElement('div'); d.id='lgs'+i; box.appendChild(d); renderSticker('lgs'+i,i,'legs',false);}); });
  await L.waitForTimeout(800); await L.screenshot({path:OUT+'/2-legs-stickers.png'});
  console.log('sticker text:', await L.evaluate(()=>document.getElementById('lgs0').innerText.replace(/\n/g,' | ')));
  // outer rules #1 glatt, then the legs sort scans the PRINTED payload (made before the ruling)
  Q("begin; select set_config('gt.reset_in_progress','true',true); update animals_pilot set inner_status='confirmed', inner_time=1, maw='kosher' where id in (0,1,2); commit;");
  const O=await dev(b,'e2e_outer_0001','tok-outer-e2e-00000000000000001','outer');
  await O.click('[onclick="outLogin()"]'); await O.waitForTimeout(1500);
  await O.click('.screen.active .num-cell[data-idx="0"]'); await O.waitForTimeout(1500);
  await O.click('#decModal .dec-btns button:has-text("גלאט")'); await O.waitForTimeout(2500);
  console.log('server #1 outer:', Q("select outer_status from animals_pilot where id=0"));
  await L.reload(); await L.waitForTimeout(6500); await L.click('[onclick="lgLogin()"]').catch(()=>{}); await L.waitForTimeout(1500);
  await L.evaluate(()=>lgSetMode('sort')); await L.waitForTimeout(800);
  await L.evaluate(p=>lgProcessSort(p), pay); await L.waitForTimeout(1200);
  console.log('sort result for printed payload:', await L.evaluate(()=>{const n=document.getElementById('lgStatusNum'),b=document.getElementById('lgStatusBig');return (n&&n.textContent)+' '+(b&&b.textContent);}));
  await L.screenshot({path:OUT+'/3-sort.png'});
  await b.close();
})();
