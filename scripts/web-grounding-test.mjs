import assert from "node:assert/strict";
import { parseGroundedCandidate,searchGroundedAnswer } from "../lib/web-grounding.ts";
import { answerQuestion } from "../lib/retrieval.ts";
import { seedKnowledge } from "../lib/seed.ts";
const docs=seedKnowledge.map(s=>({...s,checkedAt:"2026-10-25"}));
assert.equal((await answerQuestion("what is the area of UMD campus?",docs,{})).sources[0].id,"campus-size");
assert.equal((await answerQuestion("what are housing options near UMD collegepark",docs,{})).sources[0].id,"off-campus-housing");
const text="The main campus covers 1,347 acres.";
const fixture={content:{parts:[{text}]},groundingMetadata:{groundingChunks:[{web:{uri:"https://facilities.umd.edu/info-resources/facility-quick-facts-2023",title:"UMD Facilities"}},{web:{uri:"javascript:alert(1)",title:"Unsafe"}}],groundingSupports:[{segment:{endIndex:text.length},groundingChunkIndices:[0,1]}],webSearchQueries:["UMD main campus acreage"],searchEntryPoint:{renderedContent:'<a href="https://www.google.com/search?q=UMD" target="_blank">Search UMD</a>'}}};
const parsed=parseGroundedCandidate(fixture);assert.equal(parsed.sources.length,1);assert.ok(parsed.answer.endsWith("[1]"));assert.ok(parsed.grounding.suggestionsHtml.includes("Search UMD"));
assert.throws(()=>parseGroundedCandidate({content:{parts:[{text:"A fact without any grounding metadata."}]}}));
const original=globalThis.fetch;
try{
 let sent;
 globalThis.fetch=async(url,options)=>{sent=JSON.parse(options.body);return Response.json({candidates:[fixture]});};
 const found=await searchGroundedAnswer("Campus acreage?",[],{GEMINI_API_KEY:"test-only"});
 assert.ok(sent.tools[0].google_search);assert.equal(sent.generationConfig.responseMimeType,undefined);assert.equal(found.sources.length,1);
 let calls=0;
 globalThis.fetch=async(url,options)=>{calls++;const body=JSON.parse(options.body);if(body.tools)return Response.json({error:{status:"RESOURCE_EXHAUSTED"}},{status:429});return Response.json({candidates:[{content:{parts:[{text:JSON.stringify({supported:true,kind:"general",answer:"DNS translates domain names into the addresses computers use to locate services. This is general networking guidance."})}]}}]});};
 const general=await answerQuestion("What does DNS mean?",[],{GEMINI_API_KEY:"test-only"});
 assert.equal(calls,2);assert.equal(general.mode,"gemini-general");assert.equal(general.status,"private");assert.deepEqual(general.sources,[]);assert.ok(general.notice.includes("quota"));
 globalThis.fetch=async()=>Response.json({error:{status:"RESOURCE_EXHAUSTED"}},{status:429});
 const unavailable=await answerQuestion("What does DNS mean?",[],{GEMINI_API_KEY:"test-only"});
 assert.equal(unavailable.status,"private");assert.equal(unavailable.mode,"ai-unavailable:quota");
}finally{globalThis.fetch=original;}
console.log("Web-grounding, safe-citation, housing/acreage retrieval, and private general-answer regressions passed.");
