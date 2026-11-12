import assert from 'node:assert/strict';
import {test} from 'node:test';
import {labelIds, labelName, parseLabelMutation} from './label_models';

test('ORG-FR-05/06: membership is canonical, bounded and rejects duplicate IDs', () => {
  assert.deepEqual(labelIds([]), []);
  assert.deepEqual(labelIds(['study', 'work']), ['study', 'work']);
  assert.deepEqual(labelIds(['work', 'study']), ['study', 'work']);
  assert.throws(() => labelIds(['study', 'study']));
  assert.throws(() => labelIds(Array.from({length: 33}, (_, i) => `id-${i}`)));
});

test('ORG-FR-04/09: rename preserves identity and fingerprints distinguish labels', () => {
  const mutation = {wireVersion: 2, entityType: 'label', mutationId: 'm1',
    labelId: 'a', operation: 'update', baseRevision: 2, payload: {name: '  Học tập  '}};
  const renamed = parseLabelMutation(mutation);
  assert.equal(renamed.labelId, 'a');
  assert.equal(renamed.name, 'Học tập');
  assert.equal(parseLabelMutation({...mutation, mutationId: 'm2'}).fingerprint, renamed.fingerprint);
  assert.notEqual(parseLabelMutation({...mutation, labelId: 'b'}).fingerprint, renamed.fingerprint);
  assert.equal(labelName('😀'.repeat(64)), '😀'.repeat(64));
  assert.throws(() => labelName('😀'.repeat(65)));
});
