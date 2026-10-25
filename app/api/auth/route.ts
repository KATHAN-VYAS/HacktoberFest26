import { authClient } from '@/lib/supabase/server';
export const dynamic='force-dynamic';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
export async function POST(request:Request) {
  if(request.headers.get('origin')!==new URL(request.url).origin) return json({error:'Open this form from TerpCommons.'},403);
  if(!request.headers.get('content-type')?.startsWith('application/json')) return json({error:'Expected JSON.'},415);
  try {
    const body=await request.text();
    if(body.length>4000) return json({error:'That request is too large.'},413);
    const input=JSON.parse(body),client=await authClient();
    if(!input||typeof input!=='object'||Array.isArray(input)) return json({error:'Invalid request.'},400);
    if(input.action==='signout') {
      const {error}=await client.auth.signOut();
      if(error) return json({error:'Could not sign out. Please try again.'},503);
      return json({ok:true});
    }
    if(typeof input.email!=='string'||input.email.length>254||!/^\S+@\S+\.\S+$/.test(input.email)) return json({error:'Enter a valid email address.'},400);
    if(typeof input.password!=='string'||input.password.length<8||input.password.length>128) return json({error:'Use a password with 8–128 characters.'},400);
    if(input.action==='signup') {
      const {data,error}=await client.auth.signUp({email:input.email.trim(),password:input.password,options:{emailRedirectTo:`${new URL(request.url).origin}/auth/confirm`}});
      if(error) return json({error:error.status===429?'Too many attempts. Wait a moment and try again.':'Could not create the account. Check the details and Supabase email settings.'},error.status===429?429:400);
      return json({ok:true,confirmationRequired:!data.session});
    }
    if(input.action!=='signin') return json({error:'Unknown account action.'},400);
    const {error}=await client.auth.signInWithPassword({email:input.email.trim(),password:input.password});
    if(error) return json({error:error.status===429?'Too many attempts. Wait a moment and try again.':'Could not sign in. Check your email and password, and confirm your email first.'},error.status===429?429:400);
    return json({ok:true});
  } catch(e) {
    if(e instanceof SyntaxError) return json({error:'Invalid request.'},400);
    return json({error:'Account services are not connected yet. Check .env.local and restart the app.'},503);
  }
}
