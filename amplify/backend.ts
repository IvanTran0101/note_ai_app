import { defineBackend } from '@aws-amplify/backend';
import { auth } from './auth/resource';

/**
 * NoteFlow Amplify Gen 2 backend.
 *
 * Auth only: this scaffold deliberately defines no data, storage, or function
 * resource yet, so the generated outputs stay limited to the Cognito user pool.
 *
 * @see https://docs.amplify.aws/react/build-a-backend/
 */
const backend = defineBackend({
  auth,
});

/**
 * The Amplify auth construct always creates a Cognito Identity Pool, and its CDK
 * default enables unauthenticated (guest) identities with a real IAM role.
 * NoteFlow is a signed-in app, so guest access is turned off explicitly.
 *
 * Remove this block only when a feature genuinely needs unauthenticated AWS
 * credentials; the pool itself cannot be removed through `defineAuth`.
 */
const { cfnIdentityPool } = backend.auth.resources.cfnResources;
cfnIdentityPool.allowUnauthenticatedIdentities = false;
