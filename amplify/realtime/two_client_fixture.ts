/** Local acceptance ONLY. SDK-double storage + synthetic auth; never deployed. */
import { createServer } from 'node:http';
import { TestDynamo } from '../sharing/test_dynamo';
import { DynamoSyncStore } from '../sync/dynamo_sync_store';
import { DynamoNoteAcl } from '../sharing/dynamo_note_acl';
import { DynamoShareStore } from '../sharing/dynamo_share_store';
import { ShareUseCases } from '../sharing/share_use_cases';
import { ProtectionUseCases } from '../protection/use_cases';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { TestPasswordHasher } from '../protection/test_support';
import { NoteSecurityError } from '../protection/protection_store';
import { securityErrorResponse } from '../protection/handler';
import { handleShares } from '../sharing/share_handler';
import { parseMutationBody } from '../sync/request_parser';
import { appliedMutationResponse, changesResponse, conflictResponse, jsonResponse } from '../sync/sync_response';
import { DynamoRelayStore } from './dynamo_relay_store';
import { RevisionRelay } from './relay';

const OWNER = 'm06-owner-20261002', EDITOR = 'm06-editor-20261002';
const db = new TestDynamo(); const time = new Date().toISOString();
db.put({ ownerId: `OWNER#${OWNER}`, noteId: 'NOTE#fixture-note', id: 'fixture-note',
  title: 'Initial fixture', content: 'Initial synthetic content', revision: 1,
  createdAt: time, serverUpdatedAt: time, deletedAt: null, protected: false, protectionRevision: 0 });
const acl = new DynamoNoteAcl('test', db.client);
const security = new ProtectionUseCases(new DynamoProtectionStore('test', db.client, true),
  new TestPasswordHasher(), acl, { async sendCode() {} });
const shares = new ShareUseCases(new DynamoShareStore('test', db.client), {
  async resolve(email) { if (email !== 'editor@example.invalid') throw Error('Unknown synthetic actor'); return EDITOR; },
}, security);
const sync = new DynamoSyncStore({ tableName: 'test', documentClient: db.client, security, sharing: true });
const flags: Record<string, boolean> = {};
let loseNextAck = false;
let eventPublishes = 0;
let recovering = false;
const relay = new RevisionRelay(new DynamoRelayStore('test', db.client), {
  async read(actor, owner, note, signal) { const s = await acl.read(actor, owner, note, signal); return s?.status === 'active' ? s.accessRevision : null; },
}, { async publish(actor, signal, requestSignal) {
  const reply = await fetch('http://127.0.0.1:8788/publish', { method:'POST',
    headers:{'content-type':'application/json'}, body:JSON.stringify({actor,signal}), signal: requestSignal });
  if (!reply.ok) throw Error('Fixture socket unavailable');
  eventPublishes++;
  if (loseNextAck) { loseNextAck=false; throw Error('Synthetic lost ACK'); }
} });
const ready = shares.apply(OWNER, OWNER, 'fixture-note', { requestId:'initial-share', action:'create',
  email:'editor@example.invalid', role:'editor', expectedAccessRevision:0 });

setInterval(async () => {
  if (recovering) return;
  recovering=true;
  try { await ready; await relay.recover(); } catch { /* retried by next recovery tick */ }
  finally { recovering=false; }
}, 250);

createServer(async (req, res) => {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-headers', 'authorization,content-type');
  res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
  if (req.method==='OPTIONS') { res.writeHead(204); res.end(); return; }
  try {
    await ready;
    const url = new URL(req.url!, 'http://127.0.0.1:8786');
    const actor = req.headers.authorization?.replace(/^Bearer /, '');
    if (![OWNER,EDITOR].includes(actor!)) { res.writeHead(401); res.end(); return; }
    let body = ''; for await(const part of req) { body += part; if(body.length>65536) throw Error('Too large'); }
    let reply;
    if (url.pathname==='/fixture/status') reply=jsonResponse(200,{...flags,eventPublishes});
    else if (url.pathname==='/fixture/mark') {
      const row=JSON.parse(body); flags[`${actor}-${row.phase}`]=true; reply=jsonResponse(200,{ok:true});
    } else if (url.pathname==='/fixture/lost-ack') { loseNextAck=true; reply=jsonResponse(200,{ok:true}); }
    else if (url.pathname==='/fixture/disconnect') {
      const row=JSON.parse(body);
      await fetch('http://127.0.0.1:8788/disconnect',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({actor:row.actor})});
      reply=jsonResponse(200,{ok:true});
    } else if (url.pathname==='/sync/changes') {
      reply=changesResponse(await sync.listChanges(actor!,url.searchParams.get('cursor')??undefined,50));
    } else if (url.pathname==='/sync/mutations' || url.pathname==='/sync/shared-mutations') {
      const parsed=parseMutationBody(body,false,url.pathname==='/sync/shared-mutations');
      if(!parsed.ok) reply=jsonResponse(422,{code:'INVALID_REQUEST',retryable:false});
      else {
        const result=await sync.applyMutation(parsed.mutation.ownerId ?? actor!, parsed.mutation,
          { actorId: actor! });
        reply=result.status==='applied' ? appliedMutationResponse(result) : conflictResponse(result);
      }
    } else if (url.pathname==='/notes/fixture-note/shares') {
      reply=await handleShares({rawPath:url.pathname,body,headers:{},queryStringParameters:Object.fromEntries(url.searchParams),
        requestContext:{http:{method:req.method}}} as any,actor!,shares);
    } else reply=jsonResponse(404,{code:'NOT_FOUND',retryable:false});
    res.writeHead(reply.statusCode!,{'content-type':'application/json'}); res.end(reply.body);
  } catch(error) {
    const reply = error instanceof NoteSecurityError ? securityErrorResponse(error) :
      jsonResponse(503,{code:'INTERNAL_ERROR',retryable:true});
    res.writeHead(reply.statusCode!,{'content-type':'application/json'}); res.end(reply.body);
  }
}).listen(8786,'127.0.0.1',()=>console.log('M06 synthetic production-store HTTP fixture ready: 8786'));
