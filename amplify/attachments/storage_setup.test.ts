import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const template = JSON.parse(readFileSync(new URL('./storage.template.json', import.meta.url), 'utf8'));
const resources = template.Resources;
test('M03 bucket is private, encrypted, versioned and retained without expiry', () => {
  const bucket = resources.AttachmentBucket;
  assert.equal(bucket.DeletionPolicy, 'Retain');
  assert.equal(bucket.UpdateReplacePolicy, 'Retain');
  assert.ok(Object.values(bucket.Properties.PublicAccessBlockConfiguration).every(v => v === true));
  assert.equal(bucket.Properties.OwnershipControls.Rules[0].ObjectOwnership, 'BucketOwnerEnforced');
  assert.equal(bucket.Properties.VersioningConfiguration.Status, 'Enabled');
  assert.equal(bucket.Properties.BucketEncryption.ServerSideEncryptionConfiguration[0].ServerSideEncryptionByDefault.SSEAlgorithm, 'AES256');
  assert.equal(bucket.Properties.LifecycleConfiguration, undefined);
  const cors = bucket.Properties.CorsConfiguration.CorsRules[0];
  assert.deepEqual(cors.AllowedOrigins, [{ Ref: 'UploadOrigin' }]);
  assert.deepEqual(cors.AllowedMethods, ['PUT']);
  assert.equal(resources.TlsOnly.Properties.PolicyDocument.Statement[0].Condition.Bool['aws:SecureTransport'], 'false');
});
test('M03 IAM separates staging signer/verifier/read/cleanup and forbids final deletes', () => {
  const statements = (role: string) => resources[role].Properties.Policies[0].PolicyDocument.Statement;
  assert.deepEqual(statements('UploadSignerRole')[0].Action, ['s3:PutObject']);
  assert.equal(statements('UploadSignerRole')[0].Resource['Fn::Sub'], '${AttachmentBucket.Arn}/staging/*');
  assert.deepEqual(statements('ReadGatewayRole')[0].Action, ['s3:GetObjectVersion']);
  assert.equal(statements('ReadGatewayRole')[0].Resource['Fn::Sub'], '${AttachmentBucket.Arn}/final/*');
  assert.equal(statements('StagingCleanupRole')[0].Resource['Fn::Sub'], '${AttachmentBucket.Arn}/staging/*');
  assert.ok(statements('VerifierRole').every((s: {Action: string[]}) => s.Action.every(a => !a.includes('Delete') && !a.includes('*'))));
  for (const role of ['UploadSignerRole', 'VerifierRole', 'ReadGatewayRole', 'StagingCleanupRole']) {
    assert.deepEqual(resources[role].Properties.AssumeRolePolicyDocument.Statement[0].Principal, { Service: 'lambda.amazonaws.com' });
  }
});
