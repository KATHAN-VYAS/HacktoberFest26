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
