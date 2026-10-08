const {Client}=require('pg');
(async()=>{ const mk=async()=>{const c=new Client({host:'/tmp',port:5433,user:'postgres',database:'gtapp'}); await c.connect(); return c;};
 const a=await mk(), b=await mk(), z=await mk();
 // a recovery code made the normal way (as the team leader)
 const tok=(await z.query("select manager_login('e2e-tl-code-7731')->>'token' t")).rows[0].t;
 const rec=(await z.query("select leader_recovery_code_new($1) r",[tok])).rows[0].r;
 const code=rec.code; console.log('recovery code made:', !!code);
 await z.query("delete from login_attempts");
 await a.query('begin'); await b.query('begin');
 const ra=await a.query("select leader_device_replace('e2e-tl-code-7731',$1) r",[code]);
 const pb=b.query("select leader_device_replace('e2e-tl-code-7731',$1) r",[code]);   // waits for a
 await new Promise(r=>setTimeout(r,800));
 await a.query('commit');
 const rb=await pb; await b.query('commit');
 const s=x=>{const r=x.rows[0].r; return r.ok? 'ok (replaced='+r.replaced+')' : 'refused: '+(r.reason||r.error);};
 console.log('request A:', s(ra)); console.log('request B (same codes, at the same time):', s(rb));
 for(const c of [a,b,z]) await c.end(); })().catch(e=>{console.error(e.message);process.exit(1);});
