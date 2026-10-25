import { AppError, readCommunity, mutateCommunity } from "@/lib/community";
export const dynamic="force-dynamic";
function json(data: unknown,status=200) { return Response.json(data,{status,headers:{"Cache-Control":"no-store","X-Content-Type-Options":"nosniff"}}); }
function failure(error: unknown) {
  if(error instanceof AppError) return json({error:error.message},error.status);
  console.error("Community request failed", error instanceof Error ? error.message : "Unknown error");
  return json({error:"Something went wrong. Your changes may not have saved. Please refresh and try again."},500);
}
export async function GET(request: Request) { try{return json(await readCommunity(request));}catch(e){return failure(e);} }
export async function POST(request: Request) {
  try {
    const origin=request.headers.get("origin");
    if(origin && origin!==new URL(request.url).origin) return json({error:"This request must come from TerpCommons."},403);
    if(!request.headers.get("content-type")?.startsWith("application/json")) return json({error:"Expected JSON."},415);
    const text=await request.text();
    if(text.length>16000) return json({error:"That request is too large."},413);
    let data;try{data=JSON.parse(text);}catch{return json({error:"Invalid request."},400);}
    if(!data || typeof data!=="object" || Array.isArray(data)) return json({error:"Invalid request."},400);
    return json(await mutateCommunity(request,data));
  }catch(e){return failure(e);}
}
