import { authClient } from '@/lib/supabase/server';
import type { EmailOtpType } from '@supabase/supabase-js';
export async function GET(request:Request) {
  const url=new URL(request.url), token=url.searchParams.get('token_hash'),type=url.searchParams.get('type'),code=url.searchParams.get('code');
  try {
    const client=await authClient();
    if(code) {
      const {error}=await client.auth.exchangeCodeForSession(code);
      if(!error) return Response.redirect(new URL('/',url));
    } else if(token && (type==='signup'||type==='email')) {
      const {error}=await client.auth.verifyOtp({token_hash:token,type:type as EmailOtpType});
      if(!error) return Response.redirect(new URL('/',url));
    }
  } catch { /* Keep provider details private. */ }
  return Response.redirect(new URL('/login?confirmation=failed',url));
}
