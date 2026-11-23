/** Local synth only: fictional account/pool, no AWS API or deployment. */
import { App, Stack } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { mkdirSync, writeFileSync } from 'node:fs';
import { isAbsolute, relative, resolve } from 'node:path';
import { createNotesTable } from '../amplify/sync/notes_table';
import { createRealtimeInfrastructure } from '../amplify/realtime/infrastructure';

const root = resolve(process.cwd());
const output = resolve(root, 'output/m06-cloud-review');
const within = relative(root, output);
if (within.startsWith('..') || isAbsolute(within)) throw Error('Output escaped checkout');
const app = new App({ outdir: resolve(output, 'assembly') });
const stack = new Stack(app, 'M06RealtimeReview', {
  env: { account: '123456789012', region: 'ap-southeast-1' },
});
const table = createNotesTable(stack);
createRealtimeInfrastructure(stack, table, 'ap-southeast-1_review', 'reviewclient');
const template = Template.fromStack(stack).toJSON();
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, 'realtime.template.json'), JSON.stringify(template, null, 2));
writeFileSync(resolve(output, 'review.json'), JSON.stringify({
  scope: 'local synth; fictional identity; not a deployed-stack diff',
  resources: Object.values(template.Resources).map((value: any) => value.Type),
  liveGate: 'docs/m06/LIVE_GATE.md',
}, null, 2));
console.log('M06 local resource review saved: output/m06-cloud-review');
