import { defineBackend } from '@aws-amplify/backend';
import { auth } from './auth/resource';
import { summary } from './ai/resource';
import { createSummaryInfrastructure } from './ai/infrastructure';
import { createSyncHttpApi } from './sync/http_api';
import { createNotesTable } from './sync/notes_table';
import { createSyncFunction } from './sync/sync_function';

/**
 * NoteFlow Amplify Gen 2 backend.
 *
 * Auth, note synchronization, and JWT-protected Summary Cloud resources.
 * Summary provider credentials remain server-side; no deployment occurs here.
 *
 * @see https://docs.amplify.aws/react/build-a-backend/
 */
const backend = defineBackend({
  auth,
  summary,
});

const syncStack = backend.createStack('SyncStack');
const notesTable = createNotesTable(syncStack);
const syncFunction = createSyncFunction(syncStack, notesTable, backend.auth.resources.userPool.userPoolId);
const syncHttpApi = createSyncHttpApi({
  scope: syncStack,
  handler: syncFunction.lambda,
  issuerUrl: `https://cognito-idp.${syncStack.region}.amazonaws.com/${backend.auth.resources.userPool.userPoolId}`,
  audience: [backend.auth.resources.userPoolClient.userPoolClientId],
});

const summaryInfrastructure = createSummaryInfrastructure({
  handler: backend.summary.resources.lambda,
  notesTable,
  issuerUrl: `https://cognito-idp.${syncStack.region}.amazonaws.com/${backend.auth.resources.userPool.userPoolId}`,
  audience: [backend.auth.resources.userPoolClient.userPoolClientId],
});

backend.addOutput({
  custom: {
    syncApiEndpoint: syncHttpApi.api.apiEndpoint,
    aiApiEndpoint: summaryInfrastructure.api.apiEndpoint,
  },
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
