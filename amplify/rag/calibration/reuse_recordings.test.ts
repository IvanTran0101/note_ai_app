import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFixtureFile } from './fixtures';
import { reuseUnchangedInputs } from './reuse_recordings';
import { LIVE_RECORDING_PROVENANCE } from '../question_set';
import { RECORDING_VERSION, type Fixture, type RecordingFile } from './types';
const h=readFixtureFile('test/fixtures/rag/phase4/fixtures.json').fixtures.find(f=>f.id==='fx-dev-vi-ans-05')!;
const before:Fixture={...h,id:'fx-dev-vi-ins-03',category:'insufficient',gold:{answerable:false,conflict:false,expectedFacts:[],citationLabels:[],semanticChecks:['legacy incorrect label']}};
const recording:RecordingFile={recordingVersion:RECORDING_VERSION,provenance:LIVE_RECORDING_PROVENANCE,results:[{fixtureId:before.id,status:'recorded',envelope:{model:'jev-1.13.0',answers:{answerable_from_evidence:{type:'noul',noul:.93},has_unresolved_conflict:{type:'noul',noul:.08}},usage:{input_tokens:100,output_tokens:20}}}]};
const rename={[before.id]:h.id};
test('gold-only correction reuses the exact recorded envelope after full provider-input hashes match',()=>{
 const r=reuseUnchangedInputs(recording,[before],[h],rename);
 assert.equal(r.proofs[0].beforeHash,r.proofs[0].afterHash);
 assert.equal(r.recording.results[0].fixtureId,h.id);
 assert.equal(r.recording.results[0].status,'recorded');
 assert.equal('envelope' in r.recording.results[0]?r.recording.results[0].envelope:null,'envelope' in recording.results[0]?recording.results[0].envelope:null);
});
test('changed question/evidence, other model/version, duplicate rename or crossing split cannot reuse probabilities',()=>{
 const denied=(next:Fixture)=>assert.throws(()=>reuseUnchangedInputs(recording,[before],[next],rename),{code:'RECORDING_REUSE_DENIED'});
 denied({...h,question:h.question+' Different question'});
 denied({...h,evidence:{...h.evidence,text:h.evidence.text+' changed'}});
 denied({...h,split:'confirmation'});
 assert.throws(()=>reuseUnchangedInputs({...recording,provenance:'older-question-set'},[before],[h],rename),{code:'RECORDING_REUSE_DENIED'});
 const mixed={...recording,results:[{fixtureId:before.id,status:'recorded' as const,envelope:{model:'other'}}]};
 assert.throws(()=>reuseUnchangedInputs(mixed,[before],[h],rename),{code:'EVIDENCE_VALIDATION_UNAVAILABLE'});
});
