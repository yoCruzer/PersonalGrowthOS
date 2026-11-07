import os
import contextlib,copy,hashlib,importlib.util,io,json,pathlib,subprocess,tempfile,unittest,uuid
from unittest.mock import patch
TOOL=pathlib.Path(os.environ['G1_REVIEW_REPO'])/'Experiments/iCloudSyncG1/Tools/fault_window.py'
spec=importlib.util.spec_from_file_location('window_current',TOOL);w=importlib.util.module_from_spec(spec);spec.loader.exec_module(w)
def canon(x):return json.dumps(x,sort_keys=True,separators=(',',':')).encode()
def sha(x):return hashlib.sha256(x).hexdigest()
class WindowIndependentTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name)/'package';self.root.mkdir();(self.root/'results').mkdir();self.home=pathlib.Path(self.tmp.name)/'home';self.home.mkdir();self.container=self.home/'Library/Containers/com.yocruzer.PersonalGrowthOS.SyncLab/Data';self.docs=self.container/'Documents';self.docs.mkdir(parents=True)
  self.binary=self.root/'SyncLab.app/Contents/MacOS/SyncLab';self.binary.parent.mkdir(parents=True);self.binary.write_bytes(b'SYNTHETIC BINARY');self.name='03-mac-fetch-crash';self.opens=0;self.prepare()
 def tearDown(self):self.tmp.cleanup()
 def prepare(self,exit=None):
  self.plan={'version':1,'id':'probe-plan-synthetic','dataset':'synthetic-g1-review','runID':'probe-review','commands':[{'id':'probe-final','action':'crashOnFetch' if exit else 'snapshot'}]};self.raw=canon(self.plan);stage={'name':self.name,'device':'macOS','instruction':'SYNTHETIC','expectedExit':exit,'plan':self.plan};directory=self.root/'plans'/self.name;directory.mkdir(parents=True,exist_ok=True);(directory/'SyncLab-Probe-Plan.json').write_bytes(self.raw);manifest=canon([stage]);(self.root/'plans/manifest.json').write_bytes(manifest);(self.root/'window.json').write_bytes(canon({'testUID':901,'manifestSHA256':sha(manifest),'executableSHA256':sha(self.binary.read_bytes())}))
  self.reportpath=self.docs/('SyncLab-Manual-'+self.plan['id']+'.json');self.claim=self.container/'Library/Application Support/PersonalGrowthOS-SyncLab/manual-plan-journals/SyncLab-Manual-Results'/self.plan['runID']/self.plan['dataset']/(self.plan['id']+'.request.json')
  self.marker=self.container/'Library/Application Support/PersonalGrowthOS-SyncLab/fault-journals'/self.plan['runID']/self.plan['dataset']/self.plan['id']/'probe-final/afterFetchedInstall.json'
 def report(self):
  result={'id':'probe-final','planID':self.plan['id'],'dataset':self.plan['dataset'],'runID':self.plan['runID'],'commandDigest':sha(canon(self.plan['commands'][0])),'processNonce':str(uuid.uuid4()),'processID':19901,'platform':'macOS','status':'PASS','halted':False,'accountFingerprint':'a'*64}
  return {'planID':self.plan['id'],'dataset':self.plan['dataset'],'runID':self.plan['runID'],'planDigest':sha(self.raw),'completedAllCommands':True,'results':[result]}
 def boundary(self):return dict(commandID='probe-final',planID=self.plan['id'],dataset=self.plan['dataset'],runID=self.plan['runID'],commandDigest=sha(canon(self.plan['commands'][0])),processNonce=str(uuid.uuid4()),processID=19901,sourceAccountHash='a'*64,provenance='actualCloudKitCallback',point='afterFetchedInstall')
 def run_window(self,onopen=None):
  def command(args,**kw):
   if args[0]=='/usr/bin/open':
    self.opens+=1
    self.assertNotIn('SYNCLAB_PROBE_TOKEN',kw['env']);self.assertNotIn('SYNCLAB_PROBE_BRIDGE',kw['env']);self.assertNotIn('SYNCLAB_PROBE_COMMAND',kw['env'])
    self.claim.parent.mkdir(parents=True,exist_ok=True);self.claim.write_bytes(self.raw)
    if onopen:onopen()
   return subprocess.CompletedProcess(args,0)
  with patch('os.getuid',return_value=901),patch.object(pathlib.Path,'home',return_value=self.home),patch('subprocess.run',side_effect=command),contextlib.redirect_stdout(io.StringIO()):w.run(self.root,self.name)
 def test_good_report_and_no_shell_or_ambient_token(self):
  expected=self.report();self.run_window(lambda:self.reportpath.write_bytes(canon(expected)));self.assertEqual(json.loads((self.root/'results'/self.name/'report.json').read_bytes()),expected);self.assertEqual(self.opens,1)
 def test_imported_symlink_never_copies_target(self):
  private=self.home/'synthetic-private';private.write_bytes(b'SYNTHETIC PRIVATE');(self.docs/'SyncLab-Probe-Plan.json').symlink_to(private)
  with self.assertRaises((ValueError,OSError)):self.run_window()
  self.assertEqual(self.opens,0);self.assertEqual(list(self.docs.glob('SyncLab-Imported-*')),[])
 def test_preexisting_report_not_replayed(self):
  self.reportpath.write_bytes(canon(self.report()))
  with self.assertRaises((ValueError,OSError)):self.run_window()
  self.assertEqual(self.opens,0)
 def test_imported_fifo_rejected(self):
  import os;os.mkfifo(self.docs/'SyncLab-Probe-Plan.json')
  with self.assertRaises((ValueError,OSError)):self.run_window()
  self.assertEqual(self.opens,0)
 def test_bad_nested_result_context_rejected(self):
  report=self.report();report['results'][0]['dataset']='synthetic-g1-WRONG';report['results'][0]['planID']='probe-WRONG'
  with self.assertRaises((ValueError,OSError)):self.run_window(lambda:self.reportpath.write_bytes(canon(report)))
 def test_preexisting_wellformed_boundary_rejected_before_launch(self):
  self.prepare(exit=75);self.marker.parent.mkdir(parents=True);self.marker.write_bytes(canon(self.boundary()))
  with self.assertRaises((ValueError,OSError)):self.run_window()
  self.assertEqual(self.opens,0)
 def test_bad_digest_or_local_seam_boundary_rejected(self):
  self.prepare(exit=75)
  def onopen():
   boundary=self.boundary();boundary['commandDigest']='0'*64;boundary['provenance']='LOCAL_CALLBACK_SEAM';self.marker.parent.mkdir(parents=True);self.marker.write_bytes(canon(boundary))
  with self.assertRaises((ValueError,OSError)):self.run_window(onopen)
 def test_collector_never_replaces_prior_result(self):
  target=self.root/'results'/self.name/'report.json'
  def onopen():target.write_bytes(b'SYNTHETIC PRIOR');self.reportpath.write_bytes(canon(self.report()))
  with self.assertRaises((ValueError,OSError)):self.run_window(onopen)
  self.assertEqual(target.read_bytes(),b'SYNTHETIC PRIOR')
if __name__=='__main__':unittest.main()
