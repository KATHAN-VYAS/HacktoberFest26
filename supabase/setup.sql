-- TerpCommons: server-only data API. Browser keys can use Auth but cannot read tables.
begin;
create table if not exists public.tc_profiles (
 id text primary key, username text not null, stage text not null default 'Current student', bio text not null default '', onboarding jsonb not null default '{}'::jsonb,
 created_at bigint not null default (extract(epoch from clock_timestamp())*1000)::bigint,
 check (username ~ '^[a-zA-Z0-9_]{3,24}$'),
 check (stage in ('Incoming student','Current student','Senior','Graduate student','Alum'))
);
alter table public.tc_profiles add column if not exists bio text not null default '';
alter table public.tc_profiles add column if not exists onboarding jsonb not null default '{}'::jsonb;
create unique index if not exists tc_username_unique on public.tc_profiles(lower(username));
create table if not exists public.tc_groups (
 id text primary key, name text not null, description text not null, color text not null default 'sage',
 icon text not null default 'users', owner_id text references public.tc_profiles(id),
 created_at bigint not null default (extract(epoch from clock_timestamp())*1000)::bigint
);
create unique index if not exists tc_group_name_unique on public.tc_groups(lower(name));
create table if not exists public.tc_memberships (
 user_id text references public.tc_profiles(id) on delete cascade,
 group_id text references public.tc_groups(id) on delete cascade, primary key(user_id,group_id)
);
create table if not exists public.tc_posts (
 id text primary key, author_id text not null references public.tc_profiles(id),
 group_id text not null references public.tc_groups(id), type text not null,
 title text not null check (length(title) between 8 and 220), body text not null default '' check(length(body)<=8000),
 anonymous boolean not null default false, status text not null default 'community',
 ai_answer text, ai_mode text, sources jsonb not null default '[]', sample boolean not null default false,
 created_at bigint not null default (extract(epoch from clock_timestamp())*1000)::bigint,
 check(type in ('Discussion','Question','Campus update','Event')), check(status in ('community','private','resolved'))
);
create table if not exists public.tc_replies (
 id text primary key, post_id text not null references public.tc_posts(id) on delete cascade,
 author_id text not null references public.tc_profiles(id), parent_id text references public.tc_replies(id) on delete cascade,
 body text not null check(length(body) between 2 and 4000), anonymous boolean not null default false,
 created_at bigint not null default (extract(epoch from clock_timestamp())*1000)::bigint
);
create table if not exists public.tc_votes (
 user_id text references public.tc_profiles(id) on delete cascade, post_id text references public.tc_posts(id) on delete cascade,
 primary key(user_id,post_id)
);
create table if not exists public.tc_bookmarks (
 user_id text references public.tc_profiles(id) on delete cascade, post_id text references public.tc_posts(id) on delete cascade,
 primary key(user_id,post_id)
);
create table if not exists public.tc_reports (
 id text primary key, user_id text not null references public.tc_profiles(id), post_id text not null references public.tc_posts(id) on delete cascade,
 reason text not null check(length(reason) between 4 and 500),
 created_at bigint not null default (extract(epoch from clock_timestamp())*1000)::bigint
);
create table if not exists public.tc_knowledge (
 id text primary key, title text not null, url text not null, content text not null, keywords text not null, checked_at text not null
);
create table if not exists public.tc_rate_limits (
 user_id text not null, category text not null, window_start bigint not null, hits int not null,
 primary key(user_id,category,window_start)
);
create index if not exists tc_posts_created on public.tc_posts(created_at desc);
create index if not exists tc_posts_author on public.tc_posts(author_id,created_at desc);
create index if not exists tc_replies_post on public.tc_replies(post_id,created_at);

-- No browser policies: all reads/writes go through our server after auth.getUser().
do $$ declare t text; begin
 foreach t in array array['profiles','groups','memberships','posts','replies','votes','bookmarks','reports','knowledge','rate_limits'] loop
  execute format('alter table public.tc_%I enable row level security',t);
  execute format('revoke all on public.tc_%I from anon, authenticated',t);
  execute format('grant all on public.tc_%I to service_role',t);
 end loop;
end $$;

create or replace function public.tc_ensure_profile(p_user_id text) returns void
language plpgsql set search_path=public as $$ begin
 if p_user_id is not null then
  insert into tc_profiles(id,username) values(p_user_id,'terp_'||substr(replace(gen_random_uuid()::text,'-',''),1,12)) on conflict(id) do nothing;
 end if;
end $$;

create or replace function public.tc_badge_count(p_user_id text) returns int
language sql stable set search_path=public as $$
 select (case when (select count(*) from tc_replies where author_id=p_user_id)>=1 then 1 else 0 end)
      + (case when (select count(*) from tc_replies where author_id=p_user_id)>=3 then 1 else 0 end)
      + (case when exists(select 1 from tc_groups where owner_id=p_user_id) then 1 else 0 end)
      + (case when (select count(*) from tc_replies where author_id=p_user_id)>=5 then 1 else 0 end)
$$;

create or replace function public.tc_profile_json(p_user_id text) returns jsonb
language sql stable set search_path=public as $$
 select jsonb_build_object(
  'username',p.username,'stage',p.stage,'bio',p.bio,'helpedCount',(select count(*) from tc_replies where author_id=p.id),
  'onboarding',p.onboarding,
  'badges',jsonb_build_array(
   jsonb_build_object('id','first-reply','label','First Reply','description','Shared your first helpful answer','earned',(select count(*) from tc_replies where author_id=p.id)>=1),
   jsonb_build_object('id','helpful-terp','label','Helpful Terp','description','Helped three fellow Terps','earned',(select count(*) from tc_replies where author_id=p.id)>=3),
   jsonb_build_object('id','community-builder','label','Community Builder','description','Started a space for shared interests','earned',exists(select 1 from tc_groups where owner_id=p.id)),
   jsonb_build_object('id','welcome-guide','label','Welcome Guide','description','Helped five fellow Terps','earned',(select count(*) from tc_replies where author_id=p.id)>=5)
  ))
 from tc_profiles p where p.id=p_user_id
$$;

create or replace function public.tc_limit(p_user_id text,p_category text,p_max int) returns void
language plpgsql set search_path=public as $$
declare n int; w bigint := floor(extract(epoch from clock_timestamp())/60); begin
 insert into tc_rate_limits values(p_user_id,p_category,w,1)
 on conflict(user_id,category,window_start) do update set hits=tc_rate_limits.hits+1 returning hits into n;
 if n>p_max then raise exception using errcode='P0429',message='Please wait a minute before trying again.'; end if;
 delete from tc_rate_limits where window_start<w-10;
end $$;

create or replace function public.tc_post_json(p tc_posts,p_user_id text) returns jsonb
language sql stable set search_path=public as $$
 select jsonb_build_object(
 'id',p.id,'groupId',p.group_id,'groupName',g.name,'groupColor',g.color,'groupIcon',g.icon,
 'type',p.type,'title',p.title,'body',p.body,'anonymous',p.anonymous,
 'author',case when p.anonymous then 'Anonymous Terp' else u.username end,
 'stage',case when p.anonymous then '' else u.stage end,'authorBadgeCount',case when p.anonymous then 0 else tc_badge_count(p.author_id) end,'mine',coalesce(p.author_id=p_user_id,false),
 'status',p.status,'aiAnswer',p.ai_answer,'aiMode',p.ai_mode,
 'sources',case when jsonb_typeof(p.sources)='array' then p.sources else coalesce(p.sources->'items','[]') end,
 'grounding',p.sources->'grounding','aiNotice',p.sources->'notice','sample',p.sample,'createdAt',p.created_at,
 'replies',(select count(*) from tc_replies where post_id=p.id),'votes',(select count(*) from tc_votes where post_id=p.id),
 'voted',exists(select 1 from tc_votes where post_id=p.id and user_id=p_user_id),
 'saved',exists(select 1 from tc_bookmarks where post_id=p.id and user_id=p_user_id))
 from tc_profiles u,tc_groups g where u.id=p.author_id and g.id=p.group_id
$$;

create or replace function public.tc_community_read(p_user_id text default null,p_post_id text default null) returns jsonb
language plpgsql set search_path=public as $$
declare v_post tc_posts; result jsonb; begin
 perform tc_ensure_profile(p_user_id);
 if p_post_id is not null then
  select * into v_post from tc_posts where id=p_post_id and (status='community' or author_id=p_user_id);
  if not found then raise exception using errcode='P0002',message='This thread is unavailable or private.'; end if;
  return jsonb_build_object('post',tc_post_json(v_post,p_user_id),'replies',coalesce((
   select jsonb_agg(jsonb_build_object('id',r.id,'postId',r.post_id,'parentId',r.parent_id,'body',r.body,
   'author',case when r.anonymous then 'Anonymous Terp' else u.username end,
   'stage',case when r.anonymous then '' else u.stage end,'authorBadgeCount',case when r.anonymous then 0 else tc_badge_count(r.author_id) end,'anonymous',r.anonymous,'mine',coalesce(r.author_id=p_user_id,false),'createdAt',r.created_at) order by r.created_at)
   from tc_replies r join tc_profiles u on u.id=r.author_id where r.post_id=v_post.id),'[]'));
 end if;
 select jsonb_build_object(
 'profile',tc_profile_json(p_user_id),
 'posts',coalesce((select jsonb_agg(tc_post_json(q,p_user_id) order by q.created_at desc) from (
  select * from tc_posts where status='community' or author_id=p_user_id order by created_at desc limit 200) q),'[]'),
 'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'color',g.color,'icon',g.icon,
  'members',(select count(*) from tc_memberships where group_id=g.id),'joined',exists(select 1 from tc_memberships where group_id=g.id and user_id=p_user_id))
  order by case g.id when 'campus' then 0 when 'housing' then 1 when 'research' then 2 when 'newterps' then 3 when 'events' then 4 when 'academics' then 5 else 6 end,g.created_at) from tc_groups g),'[]'),
 'knowledge',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'url',url,'checkedAt',checked_at) order by title) from tc_knowledge),'[]'),
 'stats',jsonb_build_object('members',(select count(*) from tc_profiles where id not like 'sample-%'),'posts',(select count(*) from tc_posts where status='community' and not sample)),
 'notifications',case when p_user_id is null then '[]'::jsonb else coalesce((select jsonb_agg(n.item order by n.created_at desc) from (
  select jsonb_build_object('id',r.id,'kind','reply','body',r.body,'created_at',r.created_at,'post_id',p.id,'title',p.title,
   'author',case when r.anonymous then 'Anonymous Terp' else u.username end) item,r.created_at
  from tc_replies r join tc_posts p on p.id=r.post_id join tc_profiles u on u.id=r.author_id where p.author_id=p_user_id and r.author_id<>p_user_id
  union all select jsonb_build_object('id','question-'||p.id,'kind','question','body',p.body,'created_at',p.created_at,'post_id',p.id,'title',p.title,
   'author',case when p.anonymous then 'Anonymous Terp' else u.username end),p.created_at
  from tc_posts p join tc_profiles u on u.id=p.author_id where p.status='community' and p.type='Question' and not p.sample and p.author_id<>p_user_id
  order by created_at desc limit 12) n),'[]') end,
 'requiresSignIn',p_user_id is null) into result;
 return result;
end $$;

-- Atomic, validated writes. p_user_id is passed ONLY by our authenticated server.
create or replace function public.tc_community_mutate(p_user_id text,p_data jsonb,p_ai jsonb default null) returns jsonb
language plpgsql set search_path=public as $$
declare a text:=p_data->>'action'; p tc_posts; new_id text:=gen_random_uuid()::text;
 v_title text:=trim(p_data->>'title'); v_body text:=trim(coalesce(p_data->>'body',''));
 v_group text:=coalesce(nullif(p_data->>'groupId',''),'campus'); v_type text:=p_data->>'type';
 v_name text:=trim(p_data->>'name'); v_username text:=trim(p_data->>'username');
 v_parent text:=nullif(p_data->>'parentId',''); ask boolean;
begin
 if p_user_id is null or p_user_id='' then raise exception using errcode='28000',message='Sign in to join the conversation.'; end if;
 perform tc_ensure_profile(p_user_id);
 -- Serialize writes by this user, including group creation limits.
 perform 1 from tc_profiles where id=p_user_id for update;
 if a='profile' then
  if v_username is null or v_username !~ '^[a-zA-Z0-9_]{3,24}$' then raise exception 'Use 3–24 letters, numbers, or underscores in your username.'; end if;
  update tc_profiles set username=v_username,stage=p_data->>'stage',bio=left(coalesce(p_data->>'bio',''),280) where id=p_user_id;
 elsif a='onboarding' then
  if jsonb_typeof(p_data->'onboarding')<>'object' then raise exception 'Onboarding progress must be an object.'; end if;
  update tc_profiles set onboarding=onboarding || p_data->'onboarding' where id=p_user_id;
 elsif a in ('post','ask') then
  ask:=a='ask' or coalesce(v_type='Question',false);
  if v_title is null or length(v_title) not between 8 and 220 then raise exception 'Title must be 8–220 characters.'; end if;
  if length(v_body)>8000 then raise exception 'Keep the post under 8,000 characters.'; end if;
  if not exists(select 1 from tc_groups where id=v_group) then raise exception 'Choose an existing community.'; end if;
  perform tc_limit(p_user_id,'posts',8);
  if ask and p_ai is null then raise exception 'The AI preview is missing. Please try again.'; end if;
  insert into tc_posts(id,author_id,group_id,type,title,body,anonymous,status,ai_answer,ai_mode,sources)
  values(new_id,p_user_id,v_group,case when ask then 'Question' else v_type end,v_title,v_body,
   coalesce(p_data->'anonymous'='true',false),case when ask then 'private' else 'community' end,p_ai->>'answer',p_ai->>'mode',
   jsonb_strip_nulls(jsonb_build_object('items',coalesce(p_ai->'sources','[]'),'grounding',p_ai->'grounding','notice',p_ai->'notice')));
  return jsonb_build_object('ok',true,'id',new_id,'answer',p_ai);
 elsif a='group' then
  if v_name is null or length(v_name) not between 3 and 40 or length(trim(coalesce(p_data->>'description',''))) not between 12 and 240 then raise exception 'Use a 3–40 character community name and a 12–240 character description.'; end if;
  if (select count(*) from tc_groups where owner_id=p_user_id)>=8 then raise exception 'You can create up to eight communities.'; end if;
  insert into tc_groups(id,name,description,owner_id) values(new_id,v_name,trim(p_data->>'description'),p_user_id);
  insert into tc_memberships values(p_user_id,new_id);
  return jsonb_build_object('ok',true,'id',new_id);
 elsif a='join' then
  if not exists(select 1 from tc_groups where id=v_group) then raise exception using errcode='P0002',message='Community not found.'; end if;
  if p_data->'joined'='true' then insert into tc_memberships values(p_user_id,v_group) on conflict do nothing;
  else delete from tc_memberships where user_id=p_user_id and group_id=v_group; end if;
 else
  select * into p from tc_posts where id=p_data->>'postId' and (status='community' or author_id=p_user_id) for update;
  if not found then raise exception using errcode='P0002',message='This thread is unavailable or private.'; end if;
  if a in ('retry-ai','escalate','resolve','delete') and p.author_id<>p_user_id then raise exception using errcode='42501',message='Only the author can change this post.'; end if;
  if a='retry-ai' then
   if p.type<>'Question' or p_ai is null then raise exception 'Only questions can receive an AI preview.'; end if;
   update tc_posts set ai_answer=p_ai->>'answer',ai_mode=p_ai->>'mode',
    sources=jsonb_strip_nulls(jsonb_build_object('items',p_ai->'sources','grounding',p_ai->'grounding','notice',p_ai->'notice')),
    status=case when status='community' then 'community' else 'private' end where id=p.id;
   return jsonb_build_object('ok',true,'id',p.id,'answer',p_ai);
  elsif a in ('escalate','resolve') then
   if p.type<>'Question' then raise exception 'Only questions have an AI sharing status.'; end if;
   if a='resolve' and p.status='community' then raise exception 'This thread is already shared with the community.'; end if;
   update tc_posts set status=case when a='escalate' then 'community' else 'resolved' end where id=p.id;
  elsif a='reply' then
   if p.status<>'community' then raise exception 'Share this question before adding replies.'; end if;
   if length(v_body) not between 2 and 4000 then raise exception 'Reply must be 2–4,000 characters.'; end if;
   if v_parent is not null and not exists(select 1 from tc_replies where id=v_parent and post_id=p.id and parent_id is null) then raise exception 'Reply to a top-level comment in this thread.'; end if;
   perform tc_limit(p_user_id,'replies',15);
   insert into tc_replies(id,post_id,author_id,parent_id,body,anonymous) values(new_id,p.id,p_user_id,v_parent,v_body,coalesce(p_data->'anonymous'='true',false));
   return jsonb_build_object('ok',true,'id',new_id);
  elsif a='vote' then
   if p_data->'enabled'='true' then insert into tc_votes values(p_user_id,p.id) on conflict do nothing;
   else delete from tc_votes where user_id=p_user_id and post_id=p.id; end if;
  elsif a='bookmark' then
   if p_data->'enabled'='true' then insert into tc_bookmarks values(p_user_id,p.id) on conflict do nothing;
   else delete from tc_bookmarks where user_id=p_user_id and post_id=p.id; end if;
  elsif a='report' then
   if length(trim(coalesce(p_data->>'reason',''))) not between 4 and 500 then raise exception 'Reason must be 4–500 characters.'; end if;
   perform tc_limit(p_user_id,'reports',10);
   insert into tc_reports(id,user_id,post_id,reason) values(new_id,p_user_id,p.id,trim(p_data->>'reason'));
  elsif a='delete' then delete from tc_posts where id=p.id;
  else raise exception 'Unknown action.';
  end if;
 end if;
 return jsonb_build_object('ok',true);
end $$;

-- Reserve a provider call before contacting Gemini; failed calls also consume the slot.
create or replace function public.tc_ai_context(p_user_id text,p_post_id text default null) returns jsonb
language plpgsql set search_path=public as $$ declare p tc_posts; begin
 if p_user_id is null then raise exception using errcode='28000',message='Sign in to ask AI.'; end if;
 perform tc_limit(p_user_id,'ai',8);
 if p_post_id is not null then
  select * into p from tc_posts where id=p_post_id and author_id=p_user_id and type='Question';
  if not found then raise exception using errcode='42501',message='Only the author can retry their question.'; end if;
 end if;
 return jsonb_build_object('question',case when p.id is null then null else p.title||E'\n'||p.body end,
  'documents',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'url',url,'content',content,'keywords',keywords,'checkedAt',checked_at)) from tc_knowledge),'[]'));
end $$;

-- Functions are invoker-rights, never callable by browser roles, including helpers.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'tc\_%' escape '\' loop
  execute format('revoke all on function %s from public, anon, authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;
commit;

-- Curated sources and clearly labeled synthetic sample conversations only.
begin;
insert into public.tc_profiles (id,username,stage) values ('sample-maya','mayaonthemall','Senior') on conflict(id) do nothing;
insert into public.tc_profiles (id,username,stage) values ('sample-alex','alexbuilds','Current student') on conflict(id) do nothing;
insert into public.tc_profiles (id,username,stage) values ('sample-sam','samtheterp','Graduate student') on conflict(id) do nothing;
insert into public.tc_profiles (id,username,stage) values ('sample-riley','riley_reads','Incoming student') on conflict(id) do nothing;
insert into public.tc_groups (id,name,description,color,icon) values ('campus','Campus life','The everyday, the unexpected, and everything between classes.','coral','coffee') on conflict(id) do nothing;
insert into public.tc_groups (id,name,description,color,icon) values ('housing','Housing & roommates','Find your place and the people who make it home.','sage','home') on conflict(id) do nothing;
insert into public.tc_groups (id,name,description,color,icon) values ('research','Research & ideas','Big questions, side projects, and your next collaborator.','lavender','flask') on conflict(id) do nothing;
insert into public.tc_groups (id,name,description,color,icon) values ('newterps','New to UMD','No question is too small. Start your Maryland story here.','gold','sprout') on conflict(id) do nothing;
insert into public.tc_groups (id,name,description,color,icon) values ('events','What''s happening','Make plans, share events, and find a reason to get out.','blue','calendar') on conflict(id) do nothing;
insert into public.tc_groups (id,name,description,color,icon) values ('academics','Academics & careers','Study buddies, course experiences, and the next chapter.','peach','book') on conflict(id) do nothing;
insert into public.tc_posts (id,author_id,group_id,type,title,body,anonymous,status,sample) values ('welcome','sample-maya','newterps','Discussion','What''s one thing you wish you knew before your first semester?','The little things count. A favorite study corner, a way to meet people, or something that made campus feel like home. Let''s leave a little wisdom for the next wave of Terps.',false,'community',true) on conflict(id) do nothing;
insert into public.tc_posts (id,author_id,group_id,type,title,body,anonymous,status,sample) values ('research-collab','sample-alex','research','Discussion','Building something for good? Find your next collaborator here.','Sample project thread: imagine a small team exploring how AI can make campus resources easier to find. What would you build, and what skills would you bring? Share an idea and find someone whose strengths complement yours.',false,'community',true) on conflict(id) do nothing;
insert into public.tc_posts (id,author_id,group_id,type,title,body,anonymous,status,sample) values ('housing-question','sample-riley','housing','Question','How do you start a roommate conversation without making it awkward?','Incoming Terp here. Beyond budget and location, what should we talk about before deciding to live together? I''d love to hear what worked for you.',true,'community',true) on conflict(id) do nothing;
insert into public.tc_posts (id,author_id,group_id,type,title,body,anonymous,status,sample) values ('campus-pantry','sample-sam','campus','Campus update','A campus resource worth knowing about: the UMD Pantry','The Campus Pantry supports current UMD students, faculty, and staff facing food insecurity. Check the official Dining Services page for current hours and details. Asking for support is part of looking after yourself, and sharing resources is part of looking after each other.',false,'community',true) on conflict(id) do nothing;
insert into public.tc_posts (id,author_id,group_id,type,title,body,anonymous,status,sample) values ('coffee-walk','sample-maya','events','Event','Your next low-key campus meetup starts here','Sample event idea: bring a coffee, walk around McKeldin Mall, and meet someone outside your major. No networking pitch required. This is an example post, not a scheduled campus event—create your own with a real time and meeting point!',false,'community',true) on conflict(id) do nothing;
insert into public.tc_posts (id,author_id,group_id,type,title,body,anonymous,status,sample) values ('study-buddies','sample-sam','academics','Discussion','Different majors. Same need to finally finish that assignment.','Sample study-group thread: tell us what you''re working on and whether you''re a silent-study or explain-it-on-a-whiteboard person. Sometimes all it takes is a little company to get started.',false,'community',true) on conflict(id) do nothing;
insert into public.tc_replies (id,post_id,author_id,body,parent_id) values ('welcome-reply-1','welcome','sample-sam','Go to something outside your department. It''s easy to stay in your own bubble, but some of the best conversations happen when you step out of it.',null) on conflict(id) do nothing;
insert into public.tc_replies (id,post_id,author_id,body,parent_id) values ('welcome-reply-2','welcome','sample-alex','Ask the question! You aren''t the only one wondering, and another Terp usually has a useful starting point.',null) on conflict(id) do nothing;
insert into public.tc_replies (id,post_id,author_id,body,parent_id) values ('housing-reply','housing-question','sample-maya','Talk about quiet hours, cleaning, guests, and how you want to handle disagreements. Be specific about what a normal week looks like for you. This is personal experience, not housing advice.',null) on conflict(id) do nothing;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('off-campus-housing','Off-campus housing options near UMD','https://ochdatabase.umd.edu/housing','Near UMD, you can compare private apartments, rooms in shared houses, and sublets using UMD''s Off-Campus Housing Database. Examples listed in its College Park results include University View on Baltimore Avenue, Domain College Park on Campus Drive, and The Standard on Hartwick Road. These are examples to investigate, not endorsements or promises of a vacancy. Use filters for budget, move-in date, room versus whole unit, walking distance, and campus shuttle access. Check whether a displayed price is per bedroom or per unit and whether fees and utilities are included. Confirm current rent and availability directly with the listing. What is your monthly budget, move-in date, and preference for a private room or shared housing?','housing house homes apartment apartments room rooms roommate roommates rent rental lease sublet accommodation options near nearby offcampus off campus college park university view domain standard','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('graduate-housing','UMD graduate and affiliated housing resources','https://networth.rhsmith.umd.edu/admits/housing-resources-college-park-students','UMD''s Smith School housing resource page points graduate students to university-affiliated options including Discovery House and Graduate Hills and Garden Apartments. It also recommends UMD''s Off-Campus Housing Database for housing listings and roommate connections. Compare these options with private apartments or a room in a shared house. Eligibility, leases, prices, and openings must be checked with each provider. The page does not guarantee housing or match a student with a roommate.','housing graduate masters phd incoming international hills gardens discovery house university affiliated options living roommate apartment apartments','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('campus-size','UMD campus area · Facilities Quick Facts','https://facilities.umd.edu/info-resources/facility-quick-facts-2023','UMD Facilities Management''s Facility Quick Facts 2023 reports that the College Park main campus covers 1,347 acres, approximately 5.45 square kilometers. The same table lists 4,813 off-campus acres and 6,160 total acres, so the main-campus figure should not be confused with total university land. State that this is the figure reported in the 2023 facilities snapshot rather than claiming it is a newly measured 2026 boundary.','campus area size acreage acre acres land square kilometer kilometres kilometers km how big large main grounds footprint','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('cs-ai-faculty','CS faculty working in AI and machine learning','https://www.cs.umd.edu/people/faculty','UMD''s Computer Science faculty directory lists AI-related research areas. Examples include Hal Daume III (AI, machine learning, and natural language processing), Furong Huang (AI, machine learning, NLP, and computer vision), Tom Goldstein (AI, computer vision, and machine learning), Rachel Rudinger (NLP, machine learning, and AI), and Han Shao (machine learning, algorithms, and AI). These are starting points, not a complete list. Use each directory profile to read current projects and recent papers before contacting a faculty member. The directory does not establish who is currently taking students or hiring.','cs computer science department professor professors faculty research researcher artificial intelligence ai machine learning ml nlp natural language processing vision robotics lab advisor supervisor','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('clark-directions','A. James Clark Hall: location and directions','https://ceee.umd.edu/about/directions','A. James Clark Hall is at 8278 Paint Branch Drive, College Park, MD. For a trip from Tulane Drive, use a live map or transit planner with that destination; choose walking, driving, or public transit for your trip. The UMD directions page places Clark Hall on Paint Branch Drive after Engineering Drive when approaching from the main campus entrance. The saved sources do not contain a verified turn-by-turn route from Tulane Drive, current construction detours, or live travel times. Use the linked official directions and current campus map rather than relying on guessed turns.','clark james hall building paint branch drive tulane directions reach navigate navigation route address location walk walking trip travel','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('campus-map','UMD campus map and building finder','https://maps.umd.edu/','The official UMD campus map lets you look up buildings and use the Directions tab. Search for the building''s full name, then enter your starting point and destination. A. James Clark Hall appears as building 429. For routes that avoid stairs, choose Accessible Pathways; this option does not account for sidewalk grade. The map is a better place to check a campus route than an AI-generated set of unverified turns.','map maps building buildings directions navigate navigation route reach location destination walk walking travel trip clark mckeldin stamp iribe hall library','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('pantry','UMD Campus Pantry','https://dining.umd.edu/md-community/campus-pantry','The Campus Pantry supports current UMD students, faculty, and staff experiencing food insecurity. Bring a current UID and a reusable bag. It is in South Campus Dining at 7093 Preinkert Drive. Check the official page for current hours and eligibility details. Volunteer and donation opportunities are also listed there.','pantry food insecure insecurity hungry groceries volunteer donate donation reusable bag uid meal support','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('access','Accessible campus pathways','https://accessibility.umd.edu/campus-areas/physical-access','On the UMD Campus Map, open Directions and select Accessible Pathways. This routing avoids stairs and undepressed curbs, but does not account for elevation or sidewalk grade. The physical access page links construction updates and elevator outages. It also explains how to report broken elevators and automatic door openers.','accessible accessibility wheelchair stairs stair mobility elevator broken entrance pathways route ramps disability map','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('app','The official UMD app','https://umd.edu/app','The official UMD app brings together a campus map, events, dining menus and traffic information, class schedules, campus safety resources, and Shuttle-UM tracking through TransitApp. Some personalized features depend on your university account and services.','app shuttle bus transit transitapp map dining menu busy meter schedule classes package events campus','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('halls','Explore UMD residence halls','https://reslife.umd.edu/explore-halls','Resident Life describes traditional rooms, semi-suites, suites, and apartment-style campus housing. Its Explore the Halls page links residence communities, room layouts, virtual tours, and living-learning programs. It does not establish current room availability or guarantee housing; confirm your situation with Resident Life.','housing residence halls dorm dorms room roommate accommodation apartment campus living suite north south','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('traditions','Maryland traditions & history','https://umd.edu/about/history','Rubbing the bronze Testudo statue''s nose outside McKeldin Library is a UMD good-luck tradition. Maryland traditions also include graduation photos at the M and the giant Maryland flag unfurling at games. The official history page explains the stories behind these shared campus experiences.','tradition traditions testudo nose luck mascot flag maryland history pride spirit graduation','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('clubs','Campus events & traditions','https://studentaffairs.umd.edu/student-life/events-traditions','The First Look Fair brings together student clubs, organizations, and campus departments to help students explore interests and get involved. Student Affairs also describes Fall Welcome and Terps After Dark as opportunities to connect. Use the linked official programs for current dates and participation information.','club clubs organization organizations join first look fair involvement friends community welcome after dark event events','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('good','Do Good at Maryland','https://www.dogood.umd.edu/research-impact/projects/do-good-campus-fund','UMD''s Do Good learning principles emphasize hands-on experience, inclusion, innovation, social impact, and service to humanity. The Do Good Campus Fund supports eligible UMD-led initiatives. Eligibility, application dates, and funding conditions must be checked on the official program page.','do good service public social impact volunteer philanthropy fund funding community projects nonprofit','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
insert into public.tc_knowledge (id,title,url,content,keywords,checked_at) values ('values','UMD mission & values','https://umd.edu/about/mission','UMD''s mission centers teaching, research, and service. Its community values include unity, respect, safety, inclusion, accountability, and being empowered and open to growth. These values encourage members to support one another and contribute to the public good.','mission values united respectful inclusive accountable empowered growth belonging research teaching service','2026-10-25') on conflict(id) do update set title=excluded.title,url=excluded.url,content=excluded.content,keywords=excluded.keywords,checked_at=excluded.checked_at;
commit;
