/** Offline only: relabel Hanh, prove identical inputs, select on development, replay seen regression. */
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { readFixtureFile, hashFixtures } from '../../amplify/rag/calibration/fixtures';
import { selectThresholds, evaluateRegression } from '../../amplify/rag/calibration/evaluate';
import { hashRecording, loadRecordingFile } from '../../amplify/rag/calibration/recordings';
import { reuseUnchangedInputs } from '../../amplify/rag/calibration/reuse_recordings';
import type { Fixture } from '../../amplify/rag/calibration/types';
const directory='output/rag/phase4/recalibration-hanh';
const read=(name:string)=>JSON.parse(readFileSync(`${directory}/${name}`,'utf8'));
const write=(name:string,value:unknown)=>writeFileSync(`${directory}/${name}`,JSON.stringify(value,null,2)+'\n');
const previous=read('fixtures-before.json');
const oldPolicy=read('policy-before.json');
const current=readFixtureFile('test/fixtures/rag/phase4/fixtures.json');
const oldDev=(previous.fixtures as Fixture[]).filter(f=>f.split==='development');
const oldConf=(previous.fixtures as Fixture[]).filter(f=>f.split==='confirmation');
if(hashFixtures(oldDev)!==oldPolicy.developmentFixtureHash||hashFixtures(oldConf)!==oldPolicy.confirmationFixtureHash)throw Error('Archived fixtures do not match the frozen v2 run');
const rawDev=loadRecordingFile(read('development-recording.json'));
if(hashRecording(rawDev)!==oldPolicy.developmentResultsHash)throw Error('Original development responses changed');
const receipt=JSON.parse(readFileSync('docs/rag/phase4_receipt.json','utf8'));
for(const name of ['amplify/rag/question_set.ts','amplify/rag/providers/jev.ts','amplify/rag/private_handler.ts']) {
 const digest=createHash('sha256').update(readFileSync(name)).digest('hex');
 if(receipt.sourceHashes[name]!==digest)throw Error('Original request builder/instructions changed: '+name);
}
const confirmationBytes=readFileSync(`${directory}/confirmation-recording.json`);
const confirmationHash=createHash('sha256').update(confirmationBytes).digest('hex');
if(receipt.evidenceHashes['output/rag/phase4/live-v2/confirmation-recording.json']!==confirmationHash)throw Error('Original confirmation responses changed');
const renamed={'fx-dev-vi-ins-03':'fx-dev-vi-ans-05'};
const development=reuseUnchangedInputs(rawDev,oldDev,current.fixtures.filter(f=>f.split==='development'),renamed);
const regression=reuseUnchangedInputs(loadRecordingFile(read('confirmation-recording.json')),oldConf,current.fixtures.filter(f=>f.split==='confirmation'),{});
write('development-reused.json',development.recording);write('regression-reused.json',regression.recording);
write('input-reuse-proof.json',{model:'jev-1.13.0',questionSetVersion:'rag-evidence.v2',newProviderCalls:0,renamedFixture:renamed,development:development.proofs,regression:regression.proofs});
const candidate=selectThresholds({fixtureSet:current,recording:development.recording,model:'jev-1.13.0'});
write('candidate-policy.json',candidate);
const report=evaluateRegression({fixtureSet:current,recording:regression.recording,policy:candidate});
write('seen-regression-report.json',report);
const summary={status:'OFFLINE_CANDIDATE_REQUIRES_FRESH_CONFIRMATION',fixtureVersion:current.fixtureVersion,calibrationVersion:candidate.calibrationVersion,thresholds:candidate.thresholds,development:candidate.selection,regression:{totals:report.totals,byLanguage:report.byLanguage,gates:report.gates},newProviderCalls:0,livePolicyUpdated:false,approvalPublished:false};
write('summary.json',summary);console.log(JSON.stringify(summary,null,2));
