import { Aspects, AspectPriority, CfnResource, RemovalPolicy, Stack } from 'aws-cdk-lib';
import { Table } from 'aws-cdk-lib/aws-dynamodb';
import { Function as LambdaFunction, LayerVersion, Code, Runtime, type IFunction } from 'aws-cdk-lib/aws-lambda';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { createRagInfrastructure } from './infrastructure';
import deepSeekManifest from '../../docs/rag/deepseek_tokenizer_manifest.json';
import cohereManifest from '../../docs/rag/tokenizer_manifest.json';

export function createPrivateRagInfrastructure(handler: IFunction, notes: Table, rag: ReturnType<typeof createRagInfrastructure>) {
  if (!(handler instanceof LambdaFunction)) throw new Error('Managed RAG handler must support environment/layers');
  const scope = Stack.of(handler);
  const assetDirectory = fileURLToPath(new URL('../../output/rag/phase4-tokenizer-layer/', import.meta.url));
  for (const [directory, manifest] of [['tokenizer', cohereManifest], ['deepseek-tokenizer', deepSeekManifest]] as const) {
    for (const [name, digest] of Object.entries(manifest.files)) {
      if (createHash('sha256').update(readFileSync(resolve(assetDirectory, directory, name))).digest('hex') !== digest) {
        throw new Error('Run python3 tool/rag/prepare_phase4_tokenizer.py before synth');
      }
    }
  }
  const layer = new LayerVersion(scope, 'RagQueryTokenizers', {
    code: Code.fromAsset(assetDirectory), compatibleRuntimes: [Runtime.NODEJS_22_X], removalPolicy: RemovalPolicy.RETAIN,
  });
  const retained = layer.node.defaultChild;
  Aspects.of(scope).add({ visit(node) {
    if (node === retained && CfnResource.isCfnResource(node)) node.applyRemovalPolicy(RemovalPolicy.RETAIN);
  } }, { priority: AspectPriority.DEFAULT + 1 });
  handler.addLayers(layer);
  for (const [name, value] of Object.entries({
    RAG_REGION: scope.region, RAG_NOTES_TABLE: notes.tableName, RAG_STATE_TABLE: rag.state.tableName,
    RAG_SNAPSHOT_BUCKET: rag.snapshots.bucketName, RAG_VECTOR_INDEX_ARN: rag.index.attrIndexArn,
    RAG_TOKENIZER_DIR: '/opt/tokenizer', RAG_DEEPSEEK_TOKENIZER_DIR: '/opt/deepseek-tokenizer',
    RAG_PRIVATE_PHASE4: 'synthetic-only',
  })) handler.addEnvironment(name, value);
  handler.addToRolePolicy(new PolicyStatement({ actions: ['dynamodb:GetItem', 'dynamodb:Query'], resources: [notes.tableArn, rag.state.tableArn] }));
  handler.addToRolePolicy(new PolicyStatement({ actions: ['dynamodb:UpdateItem'], resources: [rag.state.tableArn],
    conditions: { 'ForAllValues:StringEquals': { 'dynamodb:LeadingKeys': ['BUDGET#SMOKE', 'BUDGET#PHASE4'] },
      Null: { 'dynamodb:LeadingKeys': 'false' } } }));
  handler.addToRolePolicy(new PolicyStatement({ actions: ['s3:GetObject'], resources: [rag.snapshots.arnForObjects('rag/snapshots/*')] }));
  handler.addToRolePolicy(new PolicyStatement({ actions: ['s3vectors:GetVectors', 's3vectors:QueryVectors'], resources: [rag.index.attrIndexArn] }));
  handler.addToRolePolicy(new PolicyStatement({ actions: ['bedrock:InvokeModel'], resources: [scope.formatArn({ service: 'bedrock', account: '',
    resource: 'foundation-model', resourceName: 'cohere.embed-multilingual-v3' })] }));
  const resource = handler.node.defaultChild as import('aws-cdk-lib/aws-lambda').CfnFunction;
  resource.reservedConcurrentExecutions = 1;
  return { layer };
}
