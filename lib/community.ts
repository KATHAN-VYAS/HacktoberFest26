import { env } from "cloudflare:workers";
import { seedGroups, seedKnowledge, seedPeople, seedPosts, seedReplies } from "./seed";
import { answerQuestion, type Source, type AnswerResult } from "./retrieval";

type Row = Record<string, any>;
export class AppError extends Error { constructor(message: string, public status = 400) { super(message); } }
function database() { if (!env.DB) throw new AppError("The community database is not connected yet.", 503); return env.DB; }
async function all(sql: string, ...args: any[]) { return (await database().prepare(sql).bind(...args).all<Row>()).results || []; }
async function first(sql: string, ...args: any[]) { return database().prepare(sql).bind(...args).first<Row>(); }
async function run(sql: string, ...args: any[]) { return database().prepare(sql).bind(...args).run(); }
function str(value: unknown, name: string, min: number, max: number) {
  if (typeof value !== "string" || value.trim().length < min || value.trim().length > max) throw new AppError(`${name} must be ${min}–${max} characters.`);
  return value.trim();
}
function uid() { return crypto.randomUUID(); }
const stages = ["Incoming student", "Current student", "Senior", "Graduate student", "Alum"];
const postTypes = ["Discussion", "Question", "Campus update", "Event"];

let knowledgeSynced=false;
export async function initialize() {
  if (await first("SELECT id FROM knowledge LIMIT 1")) {
    if(!knowledgeSynced) {
      await database().batch(seedKnowledge.map(k=>database().prepare("INSERT INTO knowledge (id,title,url,content,keywords,checked_at) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at").bind(k.id,k.title,k.url,k.content,k.keywords,"2026-10-25")));
      knowledgeSynced=true;
    }
    return;
  }
  const db = database(), now = Date.now();
  const batch: D1PreparedStatement[] = [];
  for (const p of seedPeople) batch.push(db.prepare("INSERT OR IGNORE INTO profiles (id,username,stage,created_at) VALUES (?,?,?,?)").bind(p.id, p.username, p.stage, now));
  for (const g of seedGroups) batch.push(db.prepare("INSERT OR IGNORE INTO groups (id,name,description,color,icon,created_at) VALUES (?,?,?,?,?,?)").bind(g.id, g.name, g.description, g.color, g.icon, now));
  for (const [i, p] of seedPosts.entries()) batch.push(db.prepare("INSERT OR IGNORE INTO posts (id,author_id,group_id,type,title,body,anonymous,status,sample,created_at) VALUES (?,?,?,?,?,?,?,'community',1,?)").bind(p.id,p.authorId,p.groupId,p.type,p.title,p.body,p.anonymous ? 1 : 0, now - (i + 1) * 2400000));
  for (const r of seedReplies) batch.push(db.prepare("INSERT OR IGNORE INTO replies (id,post_id,author_id,body,parent_id,created_at) VALUES (?,?,?,?,?,?)").bind(r.id,r.postId,r.authorId,r.body,r.parentId,now - 600000));
  for (const k of seedKnowledge) batch.push(db.prepare("INSERT OR IGNORE INTO knowledge (id,title,url,content,keywords,checked_at) VALUES (?,?,?,?,?,?)").bind(k.id,k.title,k.url,k.content,k.keywords,"2026-10-25"));
  await db.batch(batch);
  knowledgeSynced=true;
}

function identity(request: Request) { return request.headers.get("oai-authenticated-user-id"); }
async function ensureProfile(id: string) {
  let p = await first("SELECT * FROM profiles WHERE id=?", id);
  if (!p) {
    // Never derive a public username from a private email or full name.
    const username = `terp_${uid().slice(0, 8)}`;
    await run("INSERT OR IGNORE INTO profiles (id,username,stage,created_at) VALUES (?,?,'Current student',?)",id,username,Date.now());
    p = await first("SELECT * FROM profiles WHERE id=?", id);
  }
  return p!;
}
const publicPostSelect = `SELECT p.*, u.username, u.stage, g.name AS group_name, g.color AS group_color, g.icon AS group_icon,
  (SELECT COUNT(*) FROM replies r WHERE r.post_id=p.id) AS reply_count,
  (SELECT COUNT(*) FROM votes v WHERE v.post_id=p.id) AS vote_count,
  EXISTS(SELECT 1 FROM votes v WHERE v.post_id=p.id AND v.user_id=?) AS voted,
  EXISTS(SELECT 1 FROM bookmarks b WHERE b.post_id=p.id AND b.user_id=?) AS saved
  FROM posts p JOIN profiles u ON u.id=p.author_id JOIN groups g ON g.id=p.group_id`;
function serializePost(p: Row, userId: string | null) {
  const stored=JSON.parse(p.sources||"[]");
  const sources=Array.isArray(stored)?stored:stored.items||[];
  return { id: p.id, groupId: p.group_id, groupName: p.group_name, groupColor: p.group_color, groupIcon: p.group_icon,
    type: p.type, title: p.title, body: p.body, anonymous: !!p.anonymous,
    author: p.anonymous ? "Anonymous Terp" : p.username, stage: p.anonymous ? "" : p.stage,
    mine: p.author_id === userId, status: p.status, aiAnswer: p.ai_answer, aiMode: p.ai_mode,
    sources, grounding:Array.isArray(stored)?undefined:stored.grounding, aiNotice:Array.isArray(stored)?undefined:stored.notice, sample: !!p.sample, createdAt: p.created_at,
    replies: p.reply_count, votes: p.vote_count, voted: !!p.voted, saved: !!p.saved };
}
async function getPost(id: string, userId: string | null) {
  const row = await first(`${publicPostSelect} WHERE p.id=? AND (p.status='community' OR p.author_id=?)`,userId,userId,id,userId);
  if (!row) throw new AppError("This thread is unavailable or private.",404);
  return row;
}
export async function readCommunity(request: Request) {
  await initialize();
  const userId = identity(request), profile = userId ? await ensureProfile(userId) : null;
  const postId = new URL(request.url).searchParams.get("post");
  if (postId) {
    const p = await getPost(postId,userId);
    const comments = await all("SELECT r.*,u.username,u.stage FROM replies r JOIN profiles u ON u.id=r.author_id WHERE r.post_id=? ORDER BY r.created_at ASC LIMIT 300",postId);
    return { post: serializePost(p,userId), replies: comments.map(r => ({ id:r.id,postId:r.post_id,parentId:r.parent_id,body:r.body,
      author:r.anonymous ? "Anonymous Terp" : r.username,stage:r.anonymous ? "" : r.stage,anonymous:!!r.anonymous,mine:r.author_id===userId,createdAt:r.created_at })) };
  }
  const [postRows,groupRows,docs,stats,notifications] = await Promise.all([
    all(`${publicPostSelect} WHERE p.status='community' OR p.author_id=? ORDER BY p.created_at DESC LIMIT 200`,userId,userId,userId),
    all("SELECT g.*,(SELECT COUNT(*) FROM memberships m WHERE m.group_id=g.id) AS members, EXISTS(SELECT 1 FROM memberships m WHERE m.group_id=g.id AND m.user_id=?) AS joined FROM groups g ORDER BY CASE g.id WHEN 'campus' THEN 0 WHEN 'housing' THEN 1 WHEN 'research' THEN 2 WHEN 'newterps' THEN 3 WHEN 'events' THEN 4 WHEN 'academics' THEN 5 ELSE 6 END,g.created_at ASC",userId),
    all("SELECT id,title,url,checked_at FROM knowledge ORDER BY title"),
    first("SELECT (SELECT COUNT(*) FROM profiles WHERE id NOT LIKE 'sample-%') AS members,(SELECT COUNT(*) FROM posts WHERE status='community' AND sample=0) AS posts"),
    userId ? all("SELECT r.id,r.body,r.created_at,p.id AS post_id,p.title,CASE WHEN r.anonymous=1 THEN 'Anonymous Terp' ELSE u.username END AS author FROM replies r JOIN posts p ON p.id=r.post_id JOIN profiles u ON u.id=r.author_id WHERE p.author_id=? AND r.author_id<>? ORDER BY r.created_at DESC LIMIT 12",userId,userId) : Promise.resolve([]),
  ]);
  return { profile:profile ? { username:profile.username,stage:profile.stage } : null,
    posts:postRows.map(p=>serializePost(p,userId)),groups:groupRows.map(g=>({id:g.id,name:g.name,description:g.description,color:g.color,icon:g.icon,members:g.members,joined:!!g.joined})),
    knowledge:docs.map(d=>({id:d.id,title:d.title,url:d.url,checkedAt:d.checked_at})),stats,
    notifications:userId ? [...notifications.map(n=>({...n,kind:"reply"})),...postRows.filter(p=>p.status==="community"&&p.type==="Question"&&p.author_id!==userId&&!p.sample).map(p=>({id:`question-${p.id}`,kind:"question",body:p.body,created_at:p.created_at,post_id:p.id,title:p.title,author:p.anonymous?"Anonymous Terp":p.username}))].sort((a:Row,b:Row)=>b.created_at-a.created_at).slice(0,12):[],
    aiConfigured:!!env.GEMINI_API_KEY,requiresSignIn:!userId };
}

export async function mutateCommunity(request: Request, data: Row) {
  await initialize();
  const userId=identity(request);
  if (!userId) throw new AppError("Sign in to join the conversation.",401);
  await ensureProfile(userId);
  const now=Date.now(), action=data.action;
  if (action==="profile") {
    const username=str(data.username,"Username",3,24);
    if (!/^[a-zA-Z0-9_]+$/.test(username)) throw new AppError("Use letters, numbers, and underscores in your username.");
    if (!stages.includes(data.stage)) throw new AppError("Choose a student stage.");
    const existing=await first("SELECT id FROM profiles WHERE lower(username)=lower(?) AND id<>?",username,userId);
    if(existing) throw new AppError("That username is taken. Try another.");
    await run("UPDATE profiles SET username=?,stage=? WHERE id=?",username,data.stage,userId);
    return {ok:true};
  }
  if(action==="post" || action==="ask") {
    const ask=action==="ask" || data.type==="Question";
    const title=str(data.title,action==="ask"?"Question":"Title",8,220);
    const body=typeof data.body==="string" ? data.body.trim() : "";
    if(body.length>8000) throw new AppError("Keep the post under 8,000 characters.");
    const groupId=str(data.groupId || "campus","Community",1,80);
    if(!await first("SELECT id FROM groups WHERE id=?",groupId)) throw new AppError("Choose an existing community.");
    const recent=await first("SELECT COUNT(*) AS n FROM posts WHERE author_id=? AND created_at>?",userId,now-60000);
    if((recent?.n||0)>=8) throw new AppError("A lot of good questions! Please wait a minute before posting again.",429);
    const type=ask?"Question":data.type;
    if(!postTypes.includes(type)) throw new AppError("Choose a post type.");
    let answer:AnswerResult|null=null;
    if(ask) {
      const docs=(await all("SELECT id,title,url,content,keywords,checked_at AS checkedAt FROM knowledge")) as Source[];
      answer=await answerQuestion(`${title}${body ? "\n"+body : ""}`,docs,env);
    }
    const id=uid();
    await run("INSERT INTO posts (id,author_id,group_id,type,title,body,anonymous,status,ai_answer,ai_mode,sources,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",id,userId,groupId,type,title,body,data.anonymous===true?1:0,answer?.status||"community",answer?.answer||null,answer?.mode||null,JSON.stringify({items:answer?.sources||[],grounding:answer?.grounding,notice:answer?.notice}),now);
    return {ok:true,id,...(answer?{answer}:{} )};
  }
  if(action==="group") {
    const name=str(data.name,"Community name",3,40),description=str(data.description,"Description",12,240);
    if(await first("SELECT id FROM groups WHERE lower(name)=lower(?)",name)) throw new AppError("That community already exists.");
    const count=await first("SELECT COUNT(*) AS n FROM groups WHERE owner_id=?",userId);
    if((count?.n||0)>=8) throw new AppError("You can create up to eight communities in this prototype.");
    const id=uid();
    await database().batch([
      database().prepare("INSERT INTO groups (id,name,description,color,icon,owner_id,created_at) VALUES (?,?,?,'sage','users',?,?)").bind(id,name,description,userId,now),
      database().prepare("INSERT INTO memberships (user_id,group_id) VALUES (?,?)").bind(userId,id),
    ]);
    return {ok:true,id};
  }
  if(action==="join") {
    const groupId=str(data.groupId,"Community",1,80);
    if(!await first("SELECT id FROM groups WHERE id=?",groupId)) throw new AppError("Community not found.",404);
    // Insert-or-ignore makes retrying a request safe.
    if(data.joined===true) await run("INSERT OR IGNORE INTO memberships (user_id,group_id) VALUES (?,?)",userId,groupId);
    else await run("DELETE FROM memberships WHERE user_id=? AND group_id=?",userId,groupId);
    return {ok:true};
  }
  const postId=str(data.postId,"Thread",1,80), post=await getPost(postId,userId);
  if(action==="retry-ai") {
    if(post.author_id!==userId) throw new AppError("Only the author can retry this question.",403);
    if(post.type!=="Question") throw new AppError("Only questions can receive an AI answer.");
    const docs=(await all("SELECT id,title,url,content,keywords,checked_at AS checkedAt FROM knowledge")) as Source[];
    const answer=await answerQuestion(`${post.title}${post.body ? "\n"+post.body : ""}`,docs,env);
    const status=post.status==="community"?"community":answer.status;
    await run("UPDATE posts SET ai_answer=?,ai_mode=?,sources=?,status=? WHERE id=?",answer.answer,answer.mode,JSON.stringify({items:answer.sources,grounding:answer.grounding,notice:answer.notice}),status,postId);
    return {ok:true,id:postId,answer:{...answer,status}};
  }
  if(action==="escalate" || action==="resolve") {
    if(post.author_id!==userId) throw new AppError("Only the author can change this question.",403);
    if(action==="resolve" && post.status==="community") throw new AppError("This thread is already shared with the community.");
    await run("UPDATE posts SET status=? WHERE id=?",action==="escalate"?"community":"resolved",postId);
    return {ok:true,id:postId};
  }
  if(action==="reply") {
    if(post.status!=="community") throw new AppError("Share this question with the community before adding replies.");
    const body=str(data.body,"Reply",2,4000),parentId=data.parentId||null;
    if(parentId && !await first("SELECT id FROM replies WHERE id=? AND post_id=? AND parent_id IS NULL",parentId,postId)) throw new AppError("Reply to a top-level comment in this thread.");
    const recent=await first("SELECT COUNT(*) AS n FROM replies WHERE author_id=? AND created_at>?",userId,now-60000);
    if((recent?.n||0)>=15) throw new AppError("Please wait a minute before replying again.",429);
    const id=uid();
    await run("INSERT INTO replies (id,post_id,author_id,parent_id,body,anonymous,created_at) VALUES (?,?,?,?,?,?,?)",id,postId,userId,parentId,body,data.anonymous===true?1:0,now);
    return {ok:true,id};
  }
  if(action==="vote" || action==="bookmark") {
    const table=action==="vote"?"votes":"bookmarks";
    if(data.enabled===true) await run(`INSERT OR IGNORE INTO ${table} (user_id,post_id) VALUES (?,?)`,userId,postId);
    else await run(`DELETE FROM ${table} WHERE user_id=? AND post_id=?`,userId,postId);
    return {ok:true};
  }
  if(action==="report") {
    const reason=str(data.reason,"Reason",4,500);
    await run("INSERT INTO reports (id,user_id,post_id,reason,created_at) VALUES (?,?,?,?,?)",uid(),userId,postId,reason,now);
    return {ok:true};
  }
  if(action==="delete") {
    if(post.author_id!==userId) throw new AppError("You can only delete your own posts.",403);
    await database().batch([
      ...["replies","votes","bookmarks","reports"].map(t=>database().prepare(`DELETE FROM ${t} WHERE post_id=?`).bind(postId)),
      database().prepare("DELETE FROM posts WHERE id=? AND author_id=?").bind(postId,userId),
    ]);
    return {ok:true};
  }
  throw new AppError("Unknown action.");
}
