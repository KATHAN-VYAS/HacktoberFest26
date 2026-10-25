// Uses two disposable, pre-confirmed accounts; no confirmation emails are sent.
// Run only against your own configured project and a running local Next.js app.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';
process.loadEnvFile('.env.local');
const base=process.env.TEST_APP_URL||'http://localhost:3000';
if(!['localhost','127.0.0.1'].includes(new URL(base).hostname)) throw new Error('This check is restricted to a local app.');
const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY||process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!url||!secret) throw new Error('Fill the project URL and server key in .env.local first.');
const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
const users=[],posts=[];let checks=0;
const check=(condition,message)=>{assert.ok(condition,message);checks++;};
function session() {
 const jar=new Map();
 return async(path='/api/community',payload,headers={})=>{
  const response=await fetch(base+path,{method:payload?'POST':'GET',headers:{Origin:base,...(payload?{'Content-Type':'application/json'}:{}),Cookie:[...jar].map(([k,v])=>`${k}=${v}`).join('; '),...headers},body:payload?JSON.stringify(payload):undefined});
  for(const cookie of response.headers.getSetCookie()) {const pair=cookie.split(';')[0],split=pair.indexOf('=');jar.set(pair.slice(0,split),pair.slice(split+1));}
  const result=await response.json();
  return {status:response.status,...result};
 };
}
try {
 const ready=await session()();
 if(ready.status!==200) throw new Error('App is not ready: '+ready.error);
 const sessions=[];
 for(const label of ['a','b']) {
  const password=randomUUID()+randomUUID(), email=`tc-qa-${label}-${randomUUID()}@example.com`;
  const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true});
  if(error) throw new Error('Could not create a disposable test account: '+error.message);
  users.push(data.user.id);
  const request=session(),signed=await request('/api/auth',{action:'signin',email,password});
  check(signed.status===200,'Email/password sign-in through app succeeds');sessions.push(request);
 }
 const [a,b]=sessions;
 const profileA=await a('/api/community',{action:'profile',username:'qa_a_'+randomUUID().slice(0,8),stage:'Graduate student'});
 check(profileA.status===200,'Profile saved');
 const publicPost=await a('/api/community',{action:'post',type:'Discussion',title:'Temporary multi-user verification',body:'Disposable verification content',groupId:'campus',anonymous:true});
 check(publicPost.status===200,'A creates a post');posts.push(publicPost.id);
 const thread=await b(`/api/community?post=${publicPost.id}`);
 check(thread.status===200&&thread.post.author==='Anonymous Terp'&&!thread.post.mine,'B sees redacted A post');
 check(!JSON.stringify(thread).includes(users[0]),'Anonymous author ID absent from API');
 const reply=await b('/api/community',{action:'reply',postId:publicPost.id,body:'Temporary cross-account reply',anonymous:true});
 check(reply.status===200,'B can answer A');
 const updated=await a(`/api/community?post=${publicPost.id}`);
 check(updated.replies.some(r=>r.id===reply.id&&r.author==='Anonymous Terp'),'A sees B anonymous answer');
 check((await b('/api/community',{action:'delete',postId:publicPost.id})).status===403,'B cannot delete A post');
 // Insert a draft fixture via the admin client, avoiding a billable AI request.
 const draftId=randomUUID();
 const {error}=await admin.from('tc_posts').insert({id:draftId,author_id:users[0],group_id:'campus',type:'Question',title:'Temporary private question fixture',status:'private',ai_answer:'Test fixture',ai_mode:'retrieval'});
 if(error) throw new Error('Could not create private fixture: '+error.message);posts.push(draftId);
 check((await a(`/api/community?post=${draftId}`)).status===200,'Owner can read private draft');
 check((await b(`/api/community?post=${draftId}`)).status===404,'Other account cannot read private draft');
 check(!(await b()).posts.some(p=>p.id===draftId),'Private draft absent from other feed');
 check((await a('/api/community',{action:'escalate',postId:draftId})).status===200,'Owner can share draft');
 check((await b(`/api/community?post=${draftId}`)).status===200,'Shared question visible to B');
 const guest=session();
 check((await guest('/api/community',{action:'post',type:'Discussion',title:'Forged identity attempt'},{'oai-authenticated-user-id':users[0]})).status===401,'Legacy headers cannot impersonate an account');
 check((await a('/api/auth',{action:'signout'})).status===200,'Sign-out succeeds');
 check((await a()).profile===null,'Signed-out request has no account');
 console.log(`${checks} hosted checks passed with two real Supabase accounts. Temporary records will be removed.`);
} finally {
 let failed=false;
 if(posts.length) {const {error}=await admin.from('tc_posts').delete().in('id',posts);if(error){failed=true;console.error('Temporary post cleanup failed.');}}
 for(const id of users) {
  const {error:profileError}=await admin.from('tc_profiles').delete().eq('id',id);
  const {error:authError}=await admin.auth.admin.deleteUser(id);
  if(profileError||authError) {failed=true;console.error('Temporary account cleanup failed.');}
  await admin.from('tc_rate_limits').delete().eq('user_id',id);
 }
 if(failed) process.exitCode=1;
}
