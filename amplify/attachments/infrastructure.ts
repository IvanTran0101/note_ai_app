import { RemovalPolicy, Duration } from 'aws-cdk-lib';
import { Bucket, BlockPublicAccess, BucketEncryption, ObjectOwnership, HttpMethods } from 'aws-cdk-lib/aws-s3';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import type { IFunction } from 'aws-cdk-lib/aws-lambda';
import type { Construct } from 'constructs';

/** Private/versioned retained storage. Clients receive PUT-only staging capabilities. */
export function createAttachmentStorage(scope: Construct, handler: IFunction, origins: string[]) {
  if (origins.some(o => !/^https:\/\/[^/*]+$/.test(o))) throw Error('Exact HTTPS attachment upload origins required');
  const bucket = new Bucket(scope, 'Attachments', {
    blockPublicAccess: BlockPublicAccess.BLOCK_ALL, encryption: BucketEncryption.S3_MANAGED,
    enforceSSL: true, versioned: true, objectOwnership: ObjectOwnership.BUCKET_OWNER_ENFORCED,
    removalPolicy: RemovalPolicy.RETAIN,
    cors: origins.length ? [{allowedOrigins: origins, allowedMethods: [HttpMethods.PUT],
      allowedHeaders: ['content-type', 'x-amz-checksum-sha256', 'x-amz-server-side-encryption'],
      exposedHeaders: ['ETag', 'x-amz-version-id'], maxAge: 300}] : [],
    // Expiry only affects staging/incomplete uploads. Final versions stay until
    // separately authorized reference-safe GC; no lifecycle deletion of Note bytes.
    lifecycleRules: [{prefix: 'staging/', expiration: Duration.days(7),
      noncurrentVersionExpiration: Duration.days(7), abortIncompleteMultipartUploadAfter: Duration.days(1)},
      {prefix: 'final/', abortIncompleteMultipartUploadAfter: Duration.days(1)}],
  });
  handler.addToRolePolicy(new PolicyStatement({actions: ['s3:PutObject', 's3:GetObject', 's3:GetObjectVersion',
    's3:AbortMultipartUpload'], resources: [bucket.arnForObjects('staging/*'), bucket.arnForObjects('final/*')]}));
  handler.addToRolePolicy(new PolicyStatement({actions: ['s3:DeleteObject', 's3:DeleteObjectVersion'],
    resources: [bucket.arnForObjects('staging/*')]}));
  handler.addToRolePolicy(new PolicyStatement({actions: ['s3:ListBucketVersions'], resources: [bucket.bucketArn],
    conditions: {StringLike: {'s3:prefix': ['staging/*']}}}));
  return bucket;
}
