import type { PreSignUpTriggerHandler } from 'aws-lambda';

/**
 * Cognito PreSignUp trigger for NoteFlow.
 *
 * Every sign-up is auto-confirmed so the account can sign in immediately after
 * registration, without an email verification step.
 *
 * `autoVerifyEmail` is left `false` on purpose: NoteFlow does not prove mailbox
 * ownership in this scaffold, and marking the address verified without a code
 * would make Cognito report `email_verified: true` for an unproven address.
 *
 * Nothing here is logged: the incoming event carries the user's email and the
 * password-based sign-up payload, and both are out of scope for logs.
 */
export const handler: PreSignUpTriggerHandler = async (event) => {
  event.response.autoConfirmUser = true;
  event.response.autoVerifyEmail = false;

  return event;
};
