import { LIVE_QUESTION_SET, LIVE_RECORDING_PROVENANCE } from '../../amplify/rag/question_set';
/** IAM-only synthetic calibration runner. Never reads a key, retries a provider or retunes confirmation. */
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {parseArgs} from 'node:util';
import {readFixtureFile,selectThresholds,evaluateConfirmation,fixturesForSplit,RECORDING_VERSION,type RecordingFile,type CalibrationPolicy} from '../../amplify/rag/calibration';
import {contentHash} from '../../amplify/rag/calibration/hash';
import {policy} from '../../amplify/rag/types';
const {values}=parseArgs({options:{function:{type:'string'},output:{type:'string',default:'output/rag/phase4/live'},mode:{type:'string',default:'development'},table:{type:'string'}},strict:true});
if(!values.function)throw Error('Pass --function <private Lambda name>');
const output=resolve(values.output!);mkdirSync(output,{recursive:true});
const set=readFixtureFile('test/fixtures/rag/phase4/fixtures.json');
if(values.mode!=='budget'&&set.confirmationPurpose!=='heldout')throw Error('Current fixtures are regression-only; use offline recalibrate_hanh, never spend calls or publish seen confirmation');
// Checkpoints cannot be resumed against a different corpus or question set.
if(values.mode!=='budget'){
 const bindings={fixtureHash:set.fixtureHash,developmentHash:set.developmentHash,confirmationHash:set.confirmationHash,questionSetHash:contentHash(LIVE_QUESTION_SET)};
 const bindingFile=resolve(output,'fixture-bindings.json');
 if(existsSync(bindingFile)&&JSON.stringify(JSON.parse(readFileSync(bindingFile,'utf8')))!==JSON.stringify(bindings))throw Error('Fixture/question bindings changed; do not reuse unrelated checkpoints');
 if(!existsSync(bindingFile)&&['development-recording.json','confirmation-recording.json'].some(name=>existsSync(resolve(output,name))))throw Error('Existing recordings have no input binding');
 writeFileSync(bindingFile,JSON.stringify(bindings,null,2)+'\n');
}
const flags=['--profile','noteflow-dev','--region','ap-southeast-1'];
const aws=(args:string[])=>execFileSync('aws',[...args,...flags],{encoding:'utf8',env:{...process.env,AWS_MAX_ATTEMPTS:'1'},timeout:40_000});
function invoke(event:unknown,id:string){
 const input=resolve(output,id+'-input.json'),file=resolve(output,id+'-response.json');
 writeFileSync(input,JSON.stringify(event));
 const meta=JSON.parse(aws(['lambda','invoke','--function-name',values.function!,'--cli-binary-format','raw-in-base64-out','--payload','fileb://'+input,file]));
 const result=JSON.parse(readFileSync(file,'utf8'));
 if(meta.FunctionError)throw Error('Private Lambda function error; inspect metadata, never dump keys');
 return result;
}
function runSplit(split:'development'|'confirmation'){
 const file=resolve(output,split+'-recording.json');
 const recording:RecordingFile=existsSync(file)?JSON.parse(readFileSync(file,'utf8')):{recordingVersion:RECORDING_VERSION,provenance:LIVE_RECORDING_PROVENANCE,results:[]};
 const results=[...recording.results];
 for(const fixture of fixturesForSplit(set,split)){
  if(results.some(r=>r.fixtureId===fixture.id))continue;
  const response=invoke({operation:'jev-fixture',fixtureId:fixture.id},fixture.id);
  if(response.status==='EVALUATED')results.push({fixtureId:fixture.id,status:'recorded',envelope:response.jev});
  else results.push({fixtureId:fixture.id,status:'provider_error',detail:response.code??'INVALID_PROVIDER_OUTPUT'});
  writeFileSync(file,JSON.stringify({...recording,results},null,2)+'\n');
  console.log(JSON.stringify({split,fixtureId:fixture.id,status:response.status,code:response.code,elapsedMs:response.elapsedMs,completed:results.length}));
  if(response.status!=='EVALUATED')throw Error('Stop after provider failure; no hidden retry or invented probability');
 }
 return {...recording,results} as RecordingFile;
}
function deepFreeze<T>(value:T):T{if(value&&typeof value==='object'){Object.freeze(value);for(const child of Object.values(value))deepFreeze(child);}return value;}
if(values.mode==='development'){
 const recording=runSplit('development');
 const frozen=selectThresholds({fixtureSet:set,recording,model:'jev-1.13.0'});
 writeFileSync(resolve(output,'frozen-policy.json'),JSON.stringify(frozen,null,2)+'\n');
 console.log(JSON.stringify({status:'DEVELOPMENT_FROZEN',thresholds:frozen.thresholds,selection:frozen.selection,policyHash:frozen.policyHash}));
}else if(values.mode==='confirmation'){
 const frozen=deepFreeze(JSON.parse(readFileSync(resolve(output,'frozen-policy.json'),'utf8'))) as CalibrationPolicy;
 const recording=runSplit('confirmation');
 const report=evaluateConfirmation({fixtureSet:set,recording,policy:frozen});
 writeFileSync(resolve(output,'confirmation-report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({status:report.gates.passed?'PASS_SYNTHETIC_CALIBRATION':'FAILED_CONFIRMATION',thresholds:report.thresholds,totals:report.totals,byLanguage:report.byLanguage,gates:report.gates}));
 if(report.gates.passed&&values.table){
  const entry={ownerId:{S:'CONFIG#PHASE4'},noteId:{S:'CALIBRATION'},questionSetHash:{S:contentHash(LIVE_QUESTION_SET)},policy:{S:JSON.stringify(frozen)},recording:{S:JSON.stringify(recording)}};
  // DocumentClient expects map attributes: encode JSON structures recursively using a local codec.
  const av=(v:any):any=>v===null?{NULL:true}:typeof v==='string'?{S:v}:typeof v==='number'?{N:String(v)}:typeof v==='boolean'?{BOOL:v}:Array.isArray(v)?{L:v.map(av)}:{M:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,av(x)]))};
  const item={ownerId:entry.ownerId,noteId:entry.noteId,questionSetHash:entry.questionSetHash,policy:av(frozen),recording:av(recording)};
  const path=resolve(output,'calibration-row.json');writeFileSync(path,JSON.stringify(item));
  aws(['dynamodb','put-item','--table-name',values.table,'--item','file://'+path,'--condition-expression','attribute_not_exists(ownerId)']);
  console.log('Published frozen passing calibration row; query remains private/synthetic.');
 }
}else if(values.mode==='answers'){
 const report=JSON.parse(readFileSync(resolve(output,'confirmation-report.json'),'utf8'));
 if(!report.gates?.passed)throw Error('No passing frozen confirmation receipt');
 const candidates=report.outcomes.filter((o:any)=>o.verdict==='ALLOW').slice(0,8);
 for(const candidate of candidates){
  const file=resolve(output,candidate.fixtureId+'-answer-response.json');if(existsSync(file))continue;
  const response=invoke({operation:'answer-fixture',fixtureId:candidate.fixtureId},candidate.fixtureId+'-answer');
  console.log(JSON.stringify({fixtureId:candidate.fixtureId,status:response.status,usage:response.usage,elapsedMs:response.elapsedMs}));
  if(response.status==='ERROR')throw Error('Stop after generation failure; retain receipt and diagnose, no retry');
 }
}else if(values.mode==='budget')console.log(JSON.stringify(invoke({operation:'budget'},'budget'),null,2));
else throw Error('Unknown mode');
