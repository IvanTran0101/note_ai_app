import { AdminGetUserCommand, CognitoIdentityProviderClient } from '@aws-sdk/client-cognito-identity-provider';
import type { AdminGetUserCommandOutput } from '@aws-sdk/client-cognito-identity-provider';
import { RagFailure } from '../types';
import type { ConsentGrant } from './consent_store';
import { isCognitoSub } from './pilot_policy';
import { RUNTIME_ELIGIBLE_OWN_NOTES_KIND, type RuntimeConfig } from './runtime_config';

export type AccountAccess = Readonly<{
  verifyOwner: (ownerId: string, signal: AbortSignal) => Promise<boolean>;
  readConsent: (ownerId: string, signal: AbortSignal) => Promise<ConsentGrant>;
}>;

export const acceptsVerifiedAccounts = (config: RuntimeConfig): boolean =>
  config.verifiedAccountsEnabled === true && config.policy.enabled &&
  config.corpus.kind === RUNTIME_ELIGIBLE_OWN_NOTES_KIND;

type CognitoPort = {
  send(command: AdminGetUserCommand, options: { abortSignal: AbortSignal }): Promise<AdminGetUserCommandOutput>;
};

/** Reuse the live account lookup in HTTP and in stream jobs, which have no access token. */
export function createVerifiedOwnerReader(
  poolId: string,
  client: CognitoPort = new CognitoIdentityProviderClient({ maxAttempts: 1 }),
): AccountAccess['verifyOwner'] {
  return async (ownerId, signal) => {
    if (!isCognitoSub(ownerId)) return false;
    if (signal.aborted) throw new RagFailure('TIMEOUT');
    let user: AdminGetUserCommandOutput;
    try {
      user = await client.send(new AdminGetUserCommand({ UserPoolId: poolId, Username: ownerId }), {
        abortSignal: signal,
      });
    } catch (error) {
      if (signal.aborted) throw new RagFailure('TIMEOUT');
      if (error instanceof Error && error.name === 'UserNotFoundException') return false;
      throw new RagFailure('PROVIDER_UNAVAILABLE');
    }
    if (signal.aborted) throw new RagFailure('TIMEOUT');
    const attributes = user.UserAttributes ?? [];
    return user.Enabled === true &&
      attributes.find(({ Name }) => Name === 'sub')?.Value === ownerId &&
      attributes.find(({ Name }) => Name === 'email_verified')?.Value === 'true';
  };
}
