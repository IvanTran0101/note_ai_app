import { CognitoIdentityProviderClient, GetUserCommand } from '@aws-sdk/client-cognito-identity-provider';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { NoteSecurityError } from './protection_store';

/** Access JWTs omit email; GetUser supplies the authenticated account mailbox.
 * The OTP itself proves mailbox control even where autoVerifyEmail is disabled.
 */
export class CognitoRecoveryMailbox {
  constructor(private readonly client = new CognitoIdentityProviderClient({ maxAttempts: 1 })) {}
  async resolve(event: Event, actorId: string): Promise<string> {
    const claims = event.requestContext.authorizer.jwt.claims;
    if (claims['token_use'] === 'id' && typeof claims['email'] === 'string') return claims['email'];
    const authorization = Object.entries(event.headers ?? {}).find(([k]) => k.toLowerCase() === 'authorization')?.[1];
    if (claims['token_use'] !== 'access' || !authorization?.startsWith('Bearer ')) throw new NoteSecurityError('denied');
    try {
      const result = await this.client.send(new GetUserCommand({ AccessToken: authorization.slice(7) }),
        { abortSignal: AbortSignal.timeout(5000) });
      const attributes = new Map((result.UserAttributes ?? []).map(a => [a.Name, a.Value]));
      const email = attributes.get('email');
      if (attributes.get('sub') !== actorId || typeof email !== 'string' || email.length > 254) {
        throw new NoteSecurityError('denied');
      }
      return email;
    } catch { throw new NoteSecurityError('unavailable'); }
  }
}
