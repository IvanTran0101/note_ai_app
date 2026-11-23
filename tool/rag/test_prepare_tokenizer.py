import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('prepare_tokenizer',Path(__file__).with_name('prepare_tokenizer.py'))
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class PrepareTokenizerTest(unittest.TestCase):
    def test_pinned_hash_cache_and_tampering(self):
        data=b'{"model":"synthetic"}'
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'docs/rag').mkdir(parents=True)
            (root/'docs/rag/tokenizer_manifest.json').write_text(json.dumps({
                'repository':'synthetic','revision':'pinned','files':{'tokenizer.json':hashlib.sha256(data).hexdigest()}}))
            destination=root/'output'
            with patch.object(module,'ROOT',root),patch.object(module.urllib.request,'urlopen',return_value=io.BytesIO(data)) as request:
                module.prepare(destination)
                module.prepare(destination)
                self.assertEqual(request.call_count,1)
            (destination/'tokenizer.json').write_bytes(b'tampered')
            with patch.object(module,'ROOT',root),patch.object(module.urllib.request,'urlopen',return_value=io.BytesIO(b'bad')):
                with self.assertRaisesRegex(ValueError,'HASH_MISMATCH'):module.prepare(destination)
            self.assertEqual((destination/'tokenizer.json').read_bytes(),b'tampered')
if __name__=='__main__':unittest.main()
