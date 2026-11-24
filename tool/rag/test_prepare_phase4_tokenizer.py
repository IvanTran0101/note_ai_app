import hashlib,json,tempfile,unittest
from pathlib import Path
from prepare_phase4_tokenizer import prepare

class PreparePhase4Test(unittest.TestCase):
 def test_verified_local_assets_need_no_network_and_only_copy_pinned_data(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);(root/'docs/rag').mkdir(parents=True)
   for directory,filename in [('tokenizer','tokenizer_manifest.json'),('deepseek-tokenizer','deepseek_tokenizer_manifest.json')]:
    origin=root/'output/rag'/directory;origin.mkdir(parents=True)
    data=b'{"synthetic":true}';(origin/'tokenizer.json').write_bytes(data)
    spec={'files':{'tokenizer.json':hashlib.sha256(data).hexdigest()},'source':'invalid','archiveSha256':'invalid'}
    (root/'docs/rag'/filename).write_text(json.dumps(spec))
   out=prepare(root)
   self.assertEqual((out/'tokenizer/tokenizer.json').read_bytes(),data)
   self.assertEqual((out/'deepseek-tokenizer/tokenizer.json').read_bytes(),data)
   (root/'output/rag/tokenizer/tokenizer.json').write_text('{}')
   with self.assertRaisesRegex(ValueError,'pinned file'):prepare(root)

if __name__=='__main__':unittest.main()
