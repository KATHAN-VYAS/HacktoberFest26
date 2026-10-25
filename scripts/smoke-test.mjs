import assert from "node:assert/strict";
const base=process.env.TEST_URL||"http://localhost:5173";
const cookie="__sites_local_auth=1";
let checks=0;
function ok(condition,message){assert.ok(condition,message);checks++;console.log(`PASS ${message}`);}
async function call(payload,auth=true,query="",extra={}) {
  const response=await fetch(base+"/api/community"+query,{method:payload?"POST":"GET",headers:{...(auth?{Cookie:cookie}:{}),...(payload?{"Content-Type":"application/json",Origin:base}:{}),...extra},...(payload?{body:JSON.stringify(payload)}:{})});
  const raw=await response.text();let data;try{data=JSON.parse(raw);}catch{data={error:raw};}
  return {status:response.status,data};
}
const created=[];
try{
  const guest=await call(null,false);
  ok(guest.status===200&&guest.data.posts.length>=6,"Guest can read clearly marked sample conversations");
  ok(["welcome","research-collab","housing-question","campus-pantry","coffee-walk","study-buddies"].every(id=>guest.data.posts.some(p=>p.id===id&&p.sample)),"Starter discussions are labeled as examples");
  ok((await call({action:"post",title:"Unauthorized post",body:"test",groupId:"campus",type:"Discussion"},false)).status===401,"Unauthenticated writes are rejected");
  const me=await call(null);
  ok(!!me.data.profile,"Loopback development sign-in creates a private profile");
  const cross=await call({action:"profile",username:"csrf_test",stage:"Senior"},true,"",{Origin:"https://unrelated.example"});
  ok(cross.status===403,"Cross-origin writes are rejected");
  const anonymous=await call({action:"post",title:"Smoke test: anonymous campus question",body:"A test of public identity separation.",groupId:"campus",type:"Discussion",anonymous:true});
  ok(anonymous.status===200,"A signed-in member can post anonymously");created.push(anonymous.data.id);
  const anonPublic=await call(null,false,`?post=${anonymous.data.id}`);
  ok(anonPublic.data.post.author==="Anonymous Terp"&&anonPublic.data.post.stage==="","Anonymous username and stage are hidden");
  ok(!JSON.stringify(anonPublic.data).includes("local_seedy")&&!JSON.stringify(anonPublic.data).includes(me.data.profile.username),"Public anonymous payload excludes private account identifiers");
  const q=await call({action:"ask",title:"How can I use the UMD Campus Pantry?",groupId:"campus",anonymous:true});
  ok(q.status===200&&q.data.answer.sources.some(s=>s.id==="pantry"),"Known question retrieves the correct official UMD source");created.push(q.data.id);
  ok(q.data.answer.status==="private"&&["retrieval","gemini"].includes(q.data.answer.mode)||q.data.answer.status==="private"&&q.data.answer.mode.startsWith("retrieval-fallback"),"Source-backed answer stays private and correctly labels its provider mode");
  ok((await call(null,false,`?post=${q.data.id}`)).status===404,"Private question cannot be opened by a guest");
  ok(!(await call(null,false)).data.posts.some(p=>p.id===q.data.id),"Private questions are excluded from the public feed");
  const privateReply=await call({action:"reply",postId:q.data.id,body:"Must be refused"});
  ok(privateReply.status===400,"Replies to an unshared private question are rejected");
  ok((await call({action:"escalate",postId:q.data.id})).status===200,"Author can hand the same question to the community");
  ok((await call(null,false,`?post=${q.data.id}`)).data.post.status==="community","Escalated question is visible in the community");
  const reply=await call({action:"reply",postId:q.data.id,body:"Here is a helpful peer perspective.",anonymous:true});
  ok(reply.status===200,"Threaded community reply persists");
  const nested=await call({action:"reply",postId:q.data.id,parentId:reply.data.id,body:"Thanks for the extra context."});
  ok(nested.status===200,"A reply can have a parent within its thread");
  const comments=await call(null,false,`?post=${q.data.id}`);
  ok(comments.data.replies.length===2&&comments.data.replies[0].author==="Anonymous Terp","Thread returns replies while preserving anonymous identity");
  const badParent=await call({action:"reply",postId:q.data.id,parentId:"welcome-reply-1",body:"Wrong thread"});
  ok(badParent.status===400,"Cross-thread reply parents are rejected");
  for(let n=0;n<2;n++)await call({action:"vote",postId:q.data.id,enabled:true});
  ok((await call(null,true,`?post=${q.data.id}`)).data.post.votes===1,"Retrying an upvote cannot inflate the vote count");
  await call({action:"bookmark",postId:q.data.id,enabled:true});
  ok((await call(null)).data.posts.find(p=>p.id===q.data.id).saved,"Saved posts survive a fresh request");
  ok(!(await call(null,false)).data.posts.find(p=>p.id===q.data.id).saved,"Saved state is private to its member");
  const unknown=await call({action:"ask",title:"Where can I buy a unicorn submarine?",groupId:"academics"});
  ok(unknown.status===200&&unknown.data.answer.status==="private","An empty local match still gets an AI attempt and does not automatically publish");created.push(unknown.data.id);
  const denied=await call({action:"escalate",postId:"welcome"});
  ok(denied.status===403,"A member cannot change another author's question state");
  const invalid=await call({action:"profile",username:"<script>alert(1)</script>",stage:"Senior"});
  ok(invalid.status===400,"Unsafe or invalid public usernames are rejected");
  const joined=await call({action:"join",groupId:"research",joined:true});
  ok(joined.status===200&&(await call(null)).data.groups.find(g=>g.id==="research").joined,"Community membership persists");
  await call({action:"join",groupId:"research",joined:false});
  const preview=await call({action:"post",type:"Question",title:"What is the current weather at the UMD campus?",groupId:"campus"});
  ok(preview.status===200&&preview.data.answer?.status==="private"&&preview.data.answer?.mode.startsWith("live-weather"),"Question posted through the regular composer still gets a private live-data preview");created.push(preview.data.id);
  const retried=await call({action:"retry-ai",postId:preview.data.id});
  ok(retried.status===200&&retried.data.id===preview.data.id&&retried.data.answer.status==="private","Retry refreshes the same private question without publishing a duplicate");
  ok((await call({action:"retry-ai",postId:"housing-question"})).status===403,"A member cannot retry another author's question");
  console.log(`\n${checks} integration checks passed.`);
} finally {
  for(const postId of created)await call({action:"delete",postId});
}
