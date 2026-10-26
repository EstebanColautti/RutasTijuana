import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const origin = Deno.env.get('ADMIN_ORIGIN') || 'http://127.0.0.1:5173';
const headers = {'Content-Type':'application/json','Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
Deno.serve(async(request:Request)=>{
 if(request.headers.get('origin')!==origin)return new Response(null,{status:403});
 if(request.method==='OPTIONS')return new Response(null,{headers});
 if(request.method!=='POST')return new Response(null,{status:405,headers});
 const token=request.headers.get('authorization');if(!token?.startsWith('Bearer '))return new Response(null,{status:401,headers});
 const url=Deno.env.get('SUPABASE_URL')!;
 const publishable=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default||Deno.env.get('SUPABASE_ANON_KEY')!;
 const userClient=createClient(url,publishable,{global:{headers:{Authorization:token}},auth:{persistSession:false}});
 const {data:identity,error:identityError}=await userClient.auth.getUser(token.slice(7));
 const {data:role,error:roleError}=await userClient.rpc('catalog_role');
 if(identityError||!identity.user||roleError||role!=='admin')return new Response(null,{status:403,headers});
 try {
   const reader=request.body?.getReader();if(!reader)return new Response(null,{status:400,headers});let size=0;const parts:Uint8Array[]=[];while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>2048){await reader.cancel();return new Response(null,{status:413,headers});}parts.push(value);}const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}const body=JSON.parse(new TextDecoder().decode(bytes));
   if(typeof body.email!=='string'||body.email.length>254||!/^\S+@\S+\.\S+$/.test(body.email))return new Response(null,{status:400,headers});
   const secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
   const admin=createClient(url,secret,{auth:{persistSession:false}});
   const {data,error}=await admin.auth.admin.inviteUserByEmail(body.email,{redirectTo:origin});
   if(error||!data.user)return new Response(JSON.stringify({error:'No se pudo preparar la invitación.'}),{status:400,headers});
   const {error:memberError}=await admin.from('catalog_members').insert({user_id:data.user.id,role:'editor'});
   if(memberError)return new Response(null,{status:409,headers});
   return new Response(JSON.stringify({ok:true}),{headers});
 }catch{return new Response(null,{status:400,headers});}
});
