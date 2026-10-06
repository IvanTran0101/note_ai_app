# M03 attachment contract

## Settled policy

JPG/PNG/WebP10MiB, MP4 50MiB, PDF/TXT/CSV20MiB. Max10/100MiB per Note;
encrypted binary cache250MiB per actor; chunks256KiB. Filename is metadata,
never a path/object key/AI input. Owner writes/exports; currently authorized
Viewer/Editor reads. Note unlock must include the exact attachment operation.

## State and authority

Stage locally encrypted before transport. Canonical owner/note, actor/session,
protection/access epochs are independently guarded. Note create must be ACKed.
Stable attempt id equals local cache id; server owns attempt and object identity.
Queued -> uploading -> verified -> local manifest pending -> server association
ACK (Ready). Lost responses reconcile the same attempt, never create duplicates.
Cancel and finalize use CAS; cancellation after association uses Note removal.

Only the existing Note writer/outbox/cursor changes manifests. Inner schema6,
outer envelope/AAD3, exact attempted payloads, pin/labels/text/protection/sharing/
drafts survive. Feature-aware v2 manifests are validated and fingerprinted;
legacy text writes preserve existing manifests. New-id conflict copies must
remain explicit Pending copies until bytes are rebound, never reuse old objects.

## Bounded transport

Upload chunks are separate versioned private staging objects (256KiB), not S3
multipart parts. Attempt-limited signed PUT permits only its fixed chunk key;
URL/credentials stay transient. Server pins staging versions, validates bytes,
type, size and full SHA256, then streams them into a private final object using
S3 multipart parts >=5MiB (except last). Final descriptor pins its version.
Mutable staging/latest URLs never become read capabilities or descriptors.

Authenticated Range proxy returns <=256KiB per request with fresh JWT, current
ACL and its own M05 attachmentRead grant. Each response checks authority again
before release. No signed GET. Range CORS/content headers are explicit. Current
response bytes may finish after its final authorization check; a subsequent
request rechecks current authority. Media adapters must stream ranges rather
than materialize a complete large video; no plaintext persistent private cache.

Unlink/tombstone ACK precedes reference-safe cleanup. Cleanup may retain an
orphan conservatively; it must never delete a referenced object. Expiry/TTL is
not immediate cleanup proof. Source/local fixture acceptance and live S3/IAM/
Cognito/Range acceptance remain separate.

## Binary key compatibility and password administration

Each actor/canonical Note has a stable random binary DEK. The existing encrypted
account packet accepts its original4 inner fields or an optional fifth binaryKeys
map; Note schema6 and envelope/AAD3 stay unchanged. The binary DEK is wrapped by
the current M05 Note key when protected, otherwise by the account device key.
Enable/change/disable rewraps it in the same M05 account CAS. Protected reads
always require the opened current Note key, even if the DEK was previously opened.
Old clients reject the extended envelope rather than erase key records; downgrade
is unsupported. No cleartext keys/passwords/grants enter Note metadata or outbox.

Chunk AADv2 binds actor, canonical Note, access epoch, cache ID and chunk. Mutable
protection epochs are enforced by the current DEK wrap and live guards. Old AADv1
packets are converted one chunk at a time before password administration while
their original M05 root is still available. Both versions are readable during a
crash-interrupted conversion. Remote reset with an unavailable retired key keeps
the old wrap/ciphertext blocked for explicit recovery; no device-key substitution.

After a different device changes protection, a retired local DEK wrap can remain
unrecoverable. A fresh authorized online read of an associated immutable object
may stream without caching when the local cache seal reports staleRevision. Each
remote request and Application chunk still recheck current authority/binding;
checksum validation remains. No old wrap/draft/chunk is replaced and no plaintext
is persisted. Those retired encrypted bytes remain unavailable offline; a current
unlock alone cannot recreate a missing retired key. Local administration with a
valid current DEK continues to rewrap/carry its encrypted cache normally.

A cancel ACK before begin persists a conditional tombstone, so a late begin is
refused without reserving quota. Begin under fresh owner authority can renew an
unlinked pending attempt to the current protection epoch while preserving its
immutable metadata/chunks/final key. Old protected grants cannot authorize this.
Cancellation uses fresh current authority; linked attempts require canonical
remove, never cancellation or speculative final deletion.

Retry inspects pinned staging versions in batches of at most10. Proven absence
restarts the same stable immutable attempt from local ciphertext without another
quota reservation. A transient storage lookup failure keeps prior ACKs intact.
HTTP adapters use abortable requests for timeout/cancel/access loss, including
while waiting for headers. Each cached read checks current Note association and
scope; full reads verify SHA-256 before a collected preview is released. Note
quota counts pending reservations once; associated sparse cache is not counted
again as another attachment.

## Technical sources

- S3 part minimum5MiB, last part exemption:
  https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html
- Signed PUT can replace an existing key:
  https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html
- Lambda synchronous6MB limit:
  https://docs.aws.amazon.com/lambda/latest/api/API_Invoke.html
- HTTP API binary base64 responses:
  https://aws.amazon.com/blogs/compute/handling-binary-data-using-amazon-api-gateway-http-apis/
- Web video requires Range for seeking:
  https://pub.dev/documentation/video_player_web/latest/
