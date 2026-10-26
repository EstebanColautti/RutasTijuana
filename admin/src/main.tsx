import { useEffect, useState, type FormEvent } from 'react';
import { createRoot } from 'react-dom/client';
import { api, client, type Session } from './api';
import { Editor } from './Editor';
import './style.css';
function Login() {
  const [email,setEmail]=useState(''),[password,setPassword]=useState(''),[message,setMessage]=useState(''),[busy,setBusy]=useState(false);
  async function submit(e:FormEvent) { e.preventDefault();setBusy(true);setMessage(''); const {error}=await client!.auth.signInWithPassword({email,password}); if(error)setMessage('No se pudo iniciar sesión.');setBusy(false); }
  return <main className="access"><p className="eyebrow">RUTAS TIJUANA</p><h1>Administración</h1><p>Acceso del equipo</p><form onSubmit={submit}><label>Correo<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="username"/></label><label>Contraseña<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="current-password"/></label><button disabled={busy}>Entrar</button></form><p role="alert">{message}</p></main>;
}
function SecondFactor({onReady,invited}:{onReady:()=>void; invited:boolean}) {
  const [factor,setFactor]=useState(''),[secret,setSecret]=useState(''),[qr,setQr]=useState(''),[code,setCode]=useState(''),[password,setPassword]=useState(''),[message,setMessage]=useState(''),[busy,setBusy]=useState(false);
  async function prepare() { setBusy(true);setMessage('');try { const {data,error}=await client!.auth.mfa.listFactors();if(error)throw error;const existing=data.totp.find(f=>f.status==='verified');if(existing){setFactor(existing.id);}else{for(const f of data.all.filter(f=>f.factor_type==='totp'&&f.status==='unverified'))await client!.auth.mfa.unenroll({factorId:f.id});const {data:enrolled,error}=await client!.auth.mfa.enroll({factorType:'totp',friendlyName:'Administración'});if(error)throw error;setFactor(enrolled.id);setSecret(enrolled.totp.secret);setQr(enrolled.totp.qr_code);}}catch{setMessage('No se pudo preparar el acceso. Vuelve a intentarlo.');}finally{setBusy(false);} }
  async function verify(e:FormEvent){e.preventDefault();setBusy(true);setMessage('');try{if(invited){if(password.length<12)throw Error();const {error}=await client!.auth.updateUser({password});if(error)throw error;}const {error}=await client!.auth.mfa.challengeAndVerify({factorId:factor,code});if(error)throw error;setSecret('');setQr('');onReady();}catch{setMessage('Revisa el código y vuelve a intentarlo.');}finally{setBusy(false);} }
  return <main className="access"><p className="eyebrow">RUTAS TIJUANA</p><h1>Doble factor</h1><p>Usa tu aplicación de autenticación.</p>{!factor?<button onClick={prepare} disabled={busy}>Continuar</button>:<form onSubmit={verify}>{qr&&<img className="qr" alt="Código de configuración del autenticador" src={'data:image/svg+xml;base64,'+btoa(qr)}/>} {secret&&<label>Clave de configuración<code>{secret}</code></label>}{invited&&<label>Nueva contraseña<input type="password" minLength={12} value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="new-password"/></label>}<label>Código<input inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={code} onChange={e=>setCode(e.target.value)} autoComplete="one-time-code" required/></label><button disabled={busy}>Verificar</button></form>}<p role="alert">{message}</p><button className="secondary" onClick={()=>client!.auth.signOut()}>Salir</button></main>;
}
function App(){
 const [session,setSession]=useState<Session|null>(null),[ready,setReady]=useState(false),[loading,setLoading]=useState(true);
 const [invited]=useState(()=>new URLSearchParams(location.hash.slice(1)).get('type')==='invite');
 useEffect(()=>{if(!client){setLoading(false);return;}const {data}=client.auth.onAuthStateChange((_event,s)=>{setSession(s);setReady(false);setLoading(false);if(s)queueMicrotask(()=>client!.auth.mfa.getAuthenticatorAssuranceLevel().then(r=>setReady(r.data?.currentLevel==='aal2')));});client.auth.getSession().then(r=>{setSession(r.data.session);setLoading(false);if(r.data.session)client!.auth.mfa.getAuthenticatorAssuranceLevel().then(r=>setReady(r.data?.currentLevel==='aal2'));});return()=>data.subscription.unsubscribe();},[]);
 useEffect(()=>{if(!session)return;let last=Date.now();const touch=()=>{last=Date.now();};window.addEventListener('pointerdown',touch);window.addEventListener('keydown',touch);const timer=setInterval(()=>{if(Date.now()-last>15*60*1000)void client!.auth.signOut();},30000);return()=>{clearInterval(timer);window.removeEventListener('pointerdown',touch);window.removeEventListener('keydown',touch);};},[session?.user.id]);
 if(!client)return <main className="access"><p className="eyebrow">RUTAS TIJUANA</p><h1>Administración local</h1><p>Inicia los servicios locales y configura la conexión para abrir el panel.</p></main>;
 if(loading)return <main className="access">Abriendo…</main>;
 if(!session)return <Login/>;
 if(!ready)return <SecondFactor invited={invited} onReady={()=>setReady(true)}/>;
 return <Editor service={api()} onSignOut={()=>client!.auth.signOut()}/>;
}
createRoot(document.getElementById('root')!).render(<App/>);
