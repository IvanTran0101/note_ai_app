import { defineAuth } from '@aws-amplify/backend';
import { preSignUp } from './pre-sign-up/resource';

/**
 * NoteFlow auth resource: email/password sign-in only.
 *
 * Intentionally omitted, matching the backend policy:
 * - external/social providers (`loginWith.externalProviders`)
 * - phone login (`loginWith.phone`)
 * - MFA (`mfa`)
 * - `userAttributes.displayName`: the display name is owned by the app's
 *   UserProfile, not by Cognito.
 *
 * @see https://docs.amplify.aws/react/build-a-backend/auth/
 */
export const auth = defineAuth({
  loginWith: {
    email: true,
  },
  triggers: {
    preSignUp,
  },
});
