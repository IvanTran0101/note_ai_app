# M06.4 realtime contract and deployment gate

## Signal and single writer

AppSync Events delivers version-1 invalidation metadata (eventId, canonical
owner/note identity and authorized revision/epochs). It carries no title, body,
password, email or unlock grant. AccountRealtimeService deduplicates bounded
event IDs and requests the existing HTTP cursor coordinator. Signals during a
running pass cause another pass; HTTP failures retry even if WS stays alive.
The additive catchUpPending feed flag checks the committed actor counter against
the contiguous GSI prefix. The coordinator persists that prefix, then reports a
retryable server-unavailable result; realtime retries the saved cursor until
visibility catches up. Empty-but-committed feeds cannot silently lose an event.
No socket callback writes local content/cursor/outbox.

The adapter implements ID-token/subprotocol authentication, own-sub subscription,
ack/data framing, keepalive deadline, token-expiry refresh, jittered reconnect and
unsubscribe/disposal. Generation fences invalidate delayed token/ready/message
callbacks. The root stops subscriptions on account changes, pause and disposal;
resume starts a fresh subscription/cursor catch-up.

## Durable publication

Each note/ACL transaction includes the existing private EVENT intent. New intents
have a sparse PendingRelays index; only INSERT events wake the stream Lambda.
A conditional lease protects concurrent delivery and survives process crashes.
Completion/retry require the same lease ID. The scheduled minute recovery queries
due keys, then conditionally claims the current item (no Scan). Publication uses
SDK SigV4 and namespace-scoped IAM. Current recipient ACL is read before each
publication; revoked/missing access gets identity/invalidate only. An ACL outage
retries and never becomes permission. Duplicate deliveries after lost ACK retain
the same event ID. Retries stop at 20; dead intents remain durable for operator
inspection/requeue. Completed event rows expire after seven days, never note data.

## Deployment review

Source changes create one AppSync Events API/notes namespace, enable the existing
table stream, add PendingRelays GSI, stream Lambda and minute recovery rule.
Cognito can connect/subscribe only; the handler rejects wildcard/foreign paths.
Client publication is IAM-only and the signed-in client has no such IAM grant.
Generated custom outputs add eventHttpEndpoint/eventSocketEndpoint. Alternatively
the root accepts NOTEFLOW_EVENT_HTTP and NOTEFLOW_EVENT_SOCKET build defines.
Missing endpoints leave the durable HTTP sync behavior active.

No AWS deployment is part of local acceptance. Before live acceptance, review
the exact account/region/stack diff and deploy these resources plus the M06.2
backend routes together. If a previously deployed table already has EVENT rows
without relayQueue/relayDueAt, a bounded backfill of those EVENT rows is required;
do not scan/backfill automatically or reset any note/feed data. After deployment
test real Cognito own/foreign/wildcard channels, denied client publish, JWT expiry,
two-client edit/reconnect/revoke and protected-note grants. SDK doubles, CDK
assertions and synthetic local tokens do not prove that live gate.

## Protocol references

- [AWS WebSocket protocol](https://docs.aws.amazon.com/appsync/latest/eventapi/event-api-websocket-protocol.html)
- [AWS channel handlers](https://docs.aws.amazon.com/appsync/latest/eventapi/channel-namespace-handlers.html)
- [AWS HTTP publication](https://docs.aws.amazon.com/appsync/latest/eventapi/publish-http.html)

Runtime receipts and any excluded setup attempts are recorded in PROGRESS.md.
