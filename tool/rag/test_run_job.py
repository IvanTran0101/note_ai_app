import unittest
from unittest.mock import patch
from run_job import invoke, payload

class JobToolTest(unittest.TestCase):
    def test_foreign_owner_and_worker_refused_before_aws(self):
        with patch('run_job.subprocess.run') as run:
            for owner in ['real-user', 'rag-smoke-', 'rag-smoke-../other', 'rag-smoke-a\n']:
                with self.assertRaises(ValueError):
                    invoke('RagWorker-test', owner)
            with self.assertRaises(ValueError):
                invoke('SummaryFunction', 'rag-smoke-alice')
            run.assert_not_called()
    def test_backfill_metadata_only_and_recovery_no_stale_payload(self):
        body=payload('rag-smoke-alice')
        self.assertEqual(body['job']['kind'],'RECONCILE_ACCOUNT')
        self.assertIsNone(body['job']['sourceRevisionHint'])
        self.assertEqual(set(body['job']),{'jobVersion','kind','ownerId','noteId',
            'sourceRevisionHint','policyVersion','eventId'})
        self.assertEqual(payload('rag-smoke-alice',True),{'operation':'recover','ownerId':'rag-smoke-alice'})
if __name__=='__main__':unittest.main()
