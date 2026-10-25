import { currentUser, databaseClient, publicConfig } from './supabase/server';
import { answerQuestion, type AnswerResult, type Source } from './retrieval';
export class AppError extends Error { constructor(message:string,public status=400){super(message);} }
async function rpc(name:string,args:Record<string,unknown>) {
 const {data,error}=await databaseClient().rpc(name,args);
 if(error) {
  const statuses:Record<string,number>={'28000':401,'42501':403,'P0002':404,'23505':409,'P0429':429};
  if(error.code==='23505') throw new AppError('That username or community name is already taken.',409);
  if(error.code==='PGRST202'||error.code==='42P01') throw new AppError('The shared database needs its setup SQL. See SUPABASE_SETUP.md.',503);
  const status=statuses[error.code] || (error.code==='P0001'||error.code.startsWith('22')||error.code.startsWith('23')?400:503);
  if(status===503) {console.error('Database request failed',error.code);throw new AppError('The shared database could not be reached. Check the project settings and try again.',503);}
  throw new AppError(error.code==='P0001'||statuses[error.code]?error.message:'Please check the fields and try again.',status);
 }
 return data;
}
function configured() {try{publicConfig();databaseClient();}catch(e){throw new AppError((e as Error).message,503);}}
export async function readCommunity(request:Request) {
 configured();const user=await currentUser();
 const result=await rpc('tc_community_read',{p_user_id:user?.id||null,p_post_id:new URL(request.url).searchParams.get('post')});
 return {...result,aiConfigured:!!process.env.GEMINI_API_KEY};
}
export async function mutateCommunity(_request:Request,data:Record<string,unknown>) {
 configured();const user=await currentUser();
 if(!user) throw new AppError('Sign in to join the conversation.',401);
 let answer:AnswerResult|null=null;
 const ask=data.action==='ask'||data.action==='post'&&data.type==='Question';
 if(ask||data.action==='retry-ai') {
  if(ask && (typeof data.title!=='string'||data.title.trim().length<8||data.title.trim().length>220)) throw new AppError('Question must be 8–220 characters.');
  if(data.body!==undefined && (typeof data.body!=='string'||data.body.length>8000)) throw new AppError('Keep the post under 8,000 characters.');
  if(data.action==='retry-ai' && (typeof data.postId!=='string'||!data.postId)) throw new AppError('Choose a question to retry.');
  const context=await rpc('tc_ai_context',{p_user_id:user.id,p_post_id:data.action==='retry-ai'?data.postId:null});
  answer=await answerQuestion(ask?`${String(data.title).trim()}\n${data.body||''}`:context.question,context.documents as Source[],{
   GEMINI_API_KEY:process.env.GEMINI_API_KEY,GEMINI_MODEL:process.env.GEMINI_MODEL,GEMINI_WEB_SEARCH:process.env.GEMINI_WEB_SEARCH,
  });
  answer.status='private';
 }
 return rpc('tc_community_mutate',{p_user_id:user.id,p_data:data,p_ai:answer});
}
