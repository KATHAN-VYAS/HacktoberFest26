import {createClient} from '@supabase/supabase-js';
process.loadEnvFile('.env.local');
const names=['NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY','SUPABASE_SECRET_KEY'];
const missing=names.filter(n=>!process.env[n]?.trim());
if(missing.length) {console.log('Still needed in .env.local: '+missing.join(', '));process.exit(1);}
const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,secret=process.env.SUPABASE_SECRET_KEY;
try {
 const options={auth:{persistSession:false,autoRefreshToken:false}};
 const db=createClient(url,secret,options),publicClient=createClient(url,key,options);
 const {data,error}=await db.rpc('tc_community_read',{p_user_id:null,p_post_id:null});
 if(error) {
  console.log(['PGRST202','42P01'].includes(error.code)?'Project reached. Run supabase/setup.sql in its SQL Editor.':'Connection failed. Check that the URL and keys belong to the same project. Error code: '+error.code);
  process.exitCode=1;
 } else {
  const direct=await publicClient.from('tc_profiles').select('id').limit(1);
  if(!direct.error||direct.error.code!=='42501') throw new Error('Browser table access did not match the expected permissions. Run the setup SQL again.');
  console.log(`Shared database connected: ${data.groups.length} communities and ${data.knowledge.length} sources. Browser table access blocked as expected.`);
  console.log('Next: configure email URLs/templates in SUPABASE_SETUP.md, start the app, then run npm run test:hosted.');
 }
} catch(e) {console.log(e instanceof Error?e.message:'Connection failed.');process.exitCode=1;}
