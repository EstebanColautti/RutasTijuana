import { readFile, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
const env=Object.fromEntries((await readFile('local-data/supabase.env','utf8')).split(/\r?\n/).filter(v=>v.includes('=')).map(v=>{const i=v.indexOf('=');return [v.slice(0,i),v.slice(i+1).replace(/^"|"$/g,'')];}));
const url='http://127.0.0.1:54321';
const key=env.PUBLISHABLE_KEY||env.ANON_KEY;
if(!key||!env.SERVICE_ROLE_KEY)throw Error('Inicia primero los servicios locales.');
await writeFile('admin/.env.local',`VITE_SUPABASE_URL=${url}\nVITE_SUPABASE_PUBLISHABLE_KEY=${key}\n`);
await writeFile('local-data/functions.env','ADMIN_ORIGIN=http://127.0.0.1:5173\nCATALOG_PUBLIC_BASE_URL=http://127.0.0.1:54321\n');
const service=createClient(url,env.SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const email=process.env.CATALOG_ADMIN_EMAIL||'admin@rutastijuana.local';
let access;
try { access=JSON.parse(await readFile('local-data/access.json','utf8')); }catch{}
if(!access){
 const password=randomBytes(24).toString('base64url');
 const {data,error}=await service.auth.admin.createUser({email,password,email_confirm:true});
 if(error)throw Error('No se pudo crear el acceso local.');
 const {error:memberError}=await service.from('catalog_members').insert({user_id:data.user.id,role:'admin'});
 if(memberError)throw Error('No se pudo asignar el acceso local.');
 access={email,password,url:'http://127.0.0.1:5173',userID:data.user.id};
 await writeFile('local-data/access.json',JSON.stringify(access,null,2),{mode:0o600});
}
console.log('Conexión preparada. Acceso guardado en local-data/access.json.');
