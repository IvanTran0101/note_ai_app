import { CognitoIdentityProviderClient, ListUsersCommand } from '@aws-sdk/client-cognito-identity-provider';
import { ShareError } from './share_models';
import type { RecipientResolver } from './share_models';

export const normalizedEmail = (input: string): string => {
  const email = input.trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@"\\\x00-\x1f]+@[^\s@"\\\x00-\x1f]+\.[^\s@"\\\x00-\x1f]+$/.test(email)) {
    throw new ShareError('invalidInput');
  }
  return email;
};

/** Private server lookup: never confirms/verifies a mailbox or returns a directory. */
export class CognitoRecipientResolver implements RecipientResolver {
  constructor(private readonly userPoolId: string,
    private readonly client = new CognitoIdentityProviderClient({ maxAttempts: 1 })) {}
  async resolve(input: string): Promise<string> {
    const email = normalizedEmail(input);
    if (!this.userPoolId) throw new ShareError('unavailable');
    try {
      const r = await this.client.send(new ListUsersCommand({ UserPoolId: this.userPoolId,
        Filter: `email = "${email}"`, Limit: 2 }), { abortSignal: AbortSignal.timeout(5000) });
      if (r.PaginationToken || r.Users?.length !== 1) throw new ShareError('recipientUnavailable');
      const user = r.Users[0];
      const a = new Map((user.Attributes ?? []).map(v => [v.Name, v.Value]));
      const sub = a.get('sub');
      if (!user.Enabled || user.UserStatus !== 'CONFIRMED' || a.get('email_verified') !== 'true' ||
          a.get('email')?.toLowerCase() !== email || !sub?.trim() || sub.length > 128) {
        throw new ShareError('recipientUnavailable');
      }
      return sub;
    } catch (error) {
      if (error instanceof ShareError) throw error;
      throw new ShareError('unavailable');
    }
  }
}
