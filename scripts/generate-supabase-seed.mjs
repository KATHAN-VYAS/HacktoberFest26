import fs from 'node:fs';
import {seedGroups,seedPeople,seedPosts,seedReplies,seedKnowledge} from '../lib/seed.ts';
const q=v=>v===null?'null':typeof v==='boolean'?String(v):"'"+String(v).replaceAll("'","''")+"'";
const rows=['-- Curated sources and clearly labeled synthetic sample conversations only.','begin;'];
function insert(table,columns,values,conflict='do nothing') {
 rows.push(`insert into public.tc_${table} (${columns.join(',')}) values (${values.map(q).join(',')}) on conflict(id) ${conflict};`);
}
for(const p of seedPeople) insert('profiles',['id','username','stage'],[p.id,p.username,p.stage]);
for(const g of seedGroups) insert('groups',['id','name','description','color','icon'],[g.id,g.name,g.description,g.color,g.icon]);
for(const p of seedPosts) insert('posts',['id','author_id','group_id','type','title','body','anonymous','status','sample'],[p.id,p.authorId,p.groupId,p.type,p.title,p.body,p.anonymous,'community',true]);
for(const r of seedReplies) insert('replies',['id','post_id','author_id','body','parent_id'],[r.id,r.postId,r.authorId,r.body,r.parentId]);
for(const k of seedKnowledge) insert('knowledge',['id','title','url','content','keywords','checked_at'],[k.id,k.title,k.url,k.content,k.keywords,'2026-10-25'], 'do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at');
rows.push('commit;');
fs.writeFileSync('supabase/migrations/202610250002_seed.sql',rows.join('\n')+'\n');
const schema=fs.readFileSync('supabase/migrations/202610250001_community.sql','utf8');
fs.writeFileSync('supabase/setup.sql',schema+'\n'+rows.join('\n')+'\n');
console.log('Generated Supabase seed and combined setup.sql. No local user data included.');
