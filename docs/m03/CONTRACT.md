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
