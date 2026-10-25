import 'server-only';
import { createServerClient } from '@supabase/ssr';
import { createClient } from '@supabase/supabase-js';
import { cookies } from 'next/headers';

export function publicConfig() {
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if(!url || !key) throw new Error('Supabase is not connected. Fill in .env.local and restart the app.');
  return {url,key};
}
export async function authClient() {
  const {url,key}=publicConfig(), jar=await cookies();
  return createServerClient(url,key,{cookies:{getAll:()=>jar.getAll(),setAll:values=>{for(const {name,value,options} of values) jar.set(name,value,options);}}});
}
export function databaseClient() {
  const {url}=publicConfig();
  const secret=process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!secret) throw new Error('The shared database server key is missing from .env.local.');
  return createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
}
export async function currentUser() {
  const client=await authClient();
  // Verify with Supabase Auth. Never trust an ID in a cookie, body, or header.
  const {data:{user},error}=await client.auth.getUser();
  if(error && error.name!=='AuthSessionMissingError') {
    if(error.status && error.status>=500) throw new Error('Sign-in is temporarily unavailable. Please try again.');
    if(!error.status) throw new Error('Could not verify your sign-in. Please try again.');
  }
  return user;
}
