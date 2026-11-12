import { ragQuery } from './rag/resource';
import { createPrivateRagInfrastructure } from './rag/private_infrastructure';
import { createRagInfrastructure, readRagPilotScope, resolveRagSecrets } from './rag/infrastructure';
import { createPhase5Infrastructure, RAG_ALLOWED_ORIGINS } from './rag/phase5/infrastructure';
import { RUNTIME_ELIGIBLE_OWN_NOTES_KIND } from './rag/phase5/runtime_config';
import { defineBackend } from '@aws-amplify/backend';
import { auth } from './auth/resource';
import { summary } from './ai/resource';
import { createSummaryInfrastructure } from './ai/infrastructure';
import { createSyncHttpApi } from './sync/http_api';
import { createNotesTable } from './sync/notes_table';
import { createSyncFunction } from './sync/sync_function';
import { createRealtimeInfrastructure } from './realtime/infrastructure';
import { createAttachmentStorage } from './attachments/infrastructure';

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
  ragQuery,
});

/**
 * The explicitly approved pilot actors use the `eligible-own-notes.v1` corpus
 * (docs/rag/phase5_runtime_contract.md). Only actor IDs are compiled; `noteIds` is deliberately
 * empty and there is no case hash or digest in this scope. Canonical `isEligibleNote` plus the
 * live consent/freshness guard decide which of each actor's own notes may be embedded. The ESM
 * filter remains exact per owner and the explicit dynamic stream flag stays false for the first
 * deploy; root flips it only after the controlled worker READY proof.
 */
const ragPilotScope = readRagPilotScope({
  kind: RUNTIME_ELIGIBLE_OWN_NOTES_KIND,
  owners: [
    { ownerId: '293a65cc-20f1-70e3-16e8-5317be9e95a6', noteIds: [] },
    { ownerId: '89fa153c-5031-704f-6d8c-7fe77abd1cca', noteIds: [] },
    { ownerId: 'a9cad54c-5071-709a-6c23-e90dd410f6ae', noteIds: [] },
  ],
  streamEnabled: true,
});

const syncStack = backend.createStack('SyncStack');
const notesTable = createNotesTable(syncStack);
// Keep RAG resources declared on every deploy; its reviewed pilot stream mapping defaults disabled.
// The worker/probe get the same Amplify-resolved Cloudflare Access secrets as the managed Lambda;
// the values are deploy-time references, never literals in this file or the synthesized template.
const rag = createRagInfrastructure(syncStack, notesTable, ragPilotScope, resolveRagSecrets(syncStack));
createPrivateRagInfrastructure(backend.ragQuery.resources.lambda, notesTable, rag);
const ragPhase5 = createPhase5Infrastructure({
  handler: backend.ragQuery.resources.lambda,
  notesTable,
  stateTable: rag.state,
  ownerIds: ragPilotScope.owners.map((owner) => owner.ownerId),
  issuerUrl: `https://cognito-idp.${syncStack.region}.amazonaws.com/${backend.auth.resources.userPool.userPoolId}`,
  audience: [backend.auth.resources.userPoolClient.userPoolClientId],
});
const realtime = createRealtimeInfrastructure(syncStack, notesTable,
  backend.auth.resources.userPool.userPoolId, backend.auth.resources.userPoolClient.userPoolClientId);
const syncFunction = createSyncFunction(syncStack, notesTable, backend.auth.resources.userPool.userPoolId);
// Phase 5.4 hosting wiring: the hosted web origin plus the authorized local
// dev origin are exactly the two origins the RAG HTTP API already exports.
// Reuse that reviewed list rather than introducing new configuration, and hand
// each factory its own mutable copy.
const allowedOrigins: string[] = [...RAG_ALLOWED_ORIGINS];
// Merge the reviewed browser origins into the attachment upload origins
// without dropping any teammate-provided origin and without a wildcard. The
// existing exact-HTTPS validator in `createAttachmentStorage` still checks the
// result, so a wildcard or malformed explicit origin is refused at synth.
const explicitAttachmentOrigins = String(process.env.NOTEFLOW_ATTACHMENT_UPLOAD_ORIGINS ?? syncStack.node.tryGetContext('attachmentUploadOrigins') ?? '').split(',').map(x => x.trim()).filter(Boolean);
const attachmentOrigins = [...new Set([...explicitAttachmentOrigins, ...allowedOrigins])];
const attachments = createAttachmentStorage(syncStack, syncFunction.lambda, attachmentOrigins);
syncFunction.lambda.addEnvironment('ATTACHMENT_BUCKET', attachments.bucketName);
const syncHttpApi = createSyncHttpApi({
  scope: syncStack,
  handler: syncFunction.lambda,
  issuerUrl: `https://cognito-idp.${syncStack.region}.amazonaws.com/${backend.auth.resources.userPool.userPoolId}`,
  audience: [backend.auth.resources.userPoolClient.userPoolClientId],
  allowedOrigins: [...allowedOrigins],
});

const summaryInfrastructure = createSummaryInfrastructure({
  handler: backend.summary.resources.lambda,
  notesTable,
  issuerUrl: `https://cognito-idp.${syncStack.region}.amazonaws.com/${backend.auth.resources.userPool.userPoolId}`,
  audience: [backend.auth.resources.userPoolClient.userPoolClientId],
  allowedOrigins: [...allowedOrigins],
});

backend.addOutput({
  custom: {
    syncApiEndpoint: syncHttpApi.api.apiEndpoint,
    attachmentApiEndpoint: syncHttpApi.api.apiEndpoint,
    attachmentProtocolVersion: 1,
    aiApiEndpoint: summaryInfrastructure.api.apiEndpoint,
    ragApiEndpoint: ragPhase5.api.apiEndpoint,
    eventHttpEndpoint: realtime.httpEndpoint,
    eventSocketEndpoint: realtime.socketEndpoint,
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
