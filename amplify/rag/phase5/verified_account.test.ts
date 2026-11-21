import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createVerifiedOwnerReader } from './verified_account';

const OWNER = '00000001-0000-4000-8000-000000000001';

test('the Cognito reader binds the live attribute to the exact local account in the configured pool', async () => {
  let subject = OWNER;
  let enabled = true;
  let emailVerified = 'true';
  let found = true;
  let calls = 0;
  const signal = new AbortController().signal;
  const verify = createVerifiedOwnerReader('ap-southeast-1_Example', {
    async send(command, options) {
      calls += 1;
      assert.deepEqual(command.input, { UserPoolId: 'ap-southeast-1_Example', Username: OWNER });
      assert.equal(options.abortSignal, signal);
      if (!found) throw Object.assign(new Error('missing'), { name: 'UserNotFoundException' });
      return {
        $metadata: {}, Username: OWNER, Enabled: enabled,
        UserAttributes: [{ Name: 'sub', Value: subject }, { Name: 'email_verified', Value: emailVerified }],
      };
    },
  });
  assert.equal(await verify(OWNER, signal), true);
  emailVerified = 'false';
  assert.equal(await verify(OWNER, signal), false);
  emailVerified = 'true';
  enabled = false;
  assert.equal(await verify(OWNER, signal), false);
  enabled = true;
  subject = '00000002-0000-4000-8000-000000000002';
  assert.equal(await verify(OWNER, signal), false);
  found = false;
  assert.equal(await verify(OWNER, signal), false);
  assert.equal(await verify('invalid', signal), false);
  assert.equal(calls, 5);
});
