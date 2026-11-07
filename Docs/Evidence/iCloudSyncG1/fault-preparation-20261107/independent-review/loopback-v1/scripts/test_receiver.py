import os
"""Independent synthetic server tests; no App/CloudKit/device/container access."""
from pathlib import Path
import sys,tempfile,json,uuid,copy,unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(os.environ['G1_LOOPBACK_REPO'])/'Experiments/iCloudSyncG1/Tools'))
import window_transport as w
class Tests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.output=self.root/'stage';self.output.mkdir()
  self.plan={'version':1,'id':'probe-plan','dataset':'synthetic-g1-test','runID':'probe-run','commands':[{'id':'probe-command','action':'crashOnFetch'}]}
  self.stage={'plan':self.plan,'expectedExit':75};self.raw=w.canonical(self.plan)
  with patch.object(w.HTTPServer,'__init__',return_value=None):self.server=w.Receiver(self.output,self.stage,self.raw)
  self.obs=dict(planID=self.plan['id'],dataset=self.plan['dataset'],runID=self.plan['runID'],commandID='probe-command',commandDigest=w.sha(w.canonical(self.plan['commands'][0])),processNonce=str(uuid.uuid4()),processID=1,point='afterFetchedInstall',sourceAccountHash='a'*64,provenance='actualCloudKitCallback')
 def tearDown(self):self.tmp.cleanup()
 def test_exact_ack_after_both_files(self):
  raw=w.canonical(self.obs);ack=json.loads(self.server.accept('observation',raw));self.assertEqual(ack['acceptedSHA256'],w.sha(raw));self.assertEqual((self.output/'boundary.json').read_bytes(),raw);self.assertEqual((self.output/'observations/probe-command-afterFetchedInstall.json').read_bytes(),raw)
 def test_duplicate_identical_is_idempotent(self):
  raw=w.canonical(self.obs);self.assertEqual(self.server.accept('observation',raw),self.server.accept('observation',raw))
 def test_changed_duplicate_never_overwrites(self):
  raw=w.canonical(self.obs);self.server.accept('observation',raw);self.obs['extra']='TAMPER'
  with self.assertRaises(ValueError):self.server.accept('observation',w.canonical(self.obs))
  self.assertEqual((self.output/'boundary.json').read_bytes(),raw)
 def test_wrong_nested_context(self):
  self.obs['dataset']='synthetic-g1-wrong'
  with self.assertRaises(ValueError):self.server.accept('observation',w.canonical(self.obs))
 def test_local_seam_cannot_cloud_boundary(self):
  self.obs['provenance']='LOCAL_CALLBACK_SEAM'
  with self.assertRaises(ValueError):self.server.accept('observation',w.canonical(self.obs))
 def test_duplicate_json_key(self):
  raw=w.canonical(self.obs)[:-1]+b',"planID":"probe-plan"}'
  with self.assertRaises(ValueError):self.server.accept('observation',raw)
 def test_mixed_process(self):
  self.server.accept('observation',w.canonical(self.obs));self.obs['processNonce']=str(uuid.uuid4());self.obs['point']='other'
  with self.assertRaises(ValueError):self.server.accept('observation',w.canonical(self.obs))
 def test_publish_failure_cannot_ack(self):
  with patch.object(w,'publish',side_effect=OSError('synthetic fsync failure')):
   with self.assertRaises(OSError):self.server.accept('observation',w.canonical(self.obs))
 def test_unsafe_command_path_rejected(self):
  self.plan['commands'][0]['id']='../../escaped';self.obs['commandID']='../../escaped';self.obs['commandDigest']=w.sha(w.canonical(self.plan['commands'][0]));self.obs['point']='test'
  with patch.object(w.HTTPServer,'__init__',return_value=None):
   with self.assertRaises(ValueError):w.Receiver(self.output,self.stage,w.canonical(self.plan))
  self.assertFalse((self.root/'escaped-test.json').exists())
if __name__=='__main__':unittest.main()
