import { defineFunction } from '@aws-amplify/backend';

/**
 * Cognito PreSignUp trigger Lambda, wired into the auth resource through
 * `triggers.preSignUp`.
 *
 * The runtime is left at the Amplify default on purpose; Amplify picks the
 * supported Node.js LTS version at synthesis time.
 */
export const preSignUp = defineFunction({
  name: 'pre-sign-up',
  entry: './handler.ts',
});
