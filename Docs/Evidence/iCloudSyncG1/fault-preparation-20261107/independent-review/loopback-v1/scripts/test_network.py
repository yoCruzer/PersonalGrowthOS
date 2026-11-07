import os
"""Actual loopback sockets, mocked App launch only; synthetic data."""
from pathlib import Path
import base64,copy,http.client,json,os,subprocess,sys,tempfile,threading,unittest,uuid
from unittest.mock import patch
sys.path.insert(0,str(Path(os.environ['G1_LOOPBACK_REPO'])/'Experiments/iCloudSyncG1/Tools'))
import window_transport as w
class Tests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);(self.root/'results').mkdir();self.output=self.root/'results/test';self.output.mkdir();self.plan={'version':1,'id':'probe-plan','dataset':'synthetic-g1-test','runID':'probe-run','commands':[{'id':'probe-command','action':'snapshot'}]};self.stage={'name':'01-test','device':'macOS','plan':self.plan};self.raw=w.canonical(self.plan);self.server=w.Receiver(self.output,self.stage,self.raw);self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
 def tearDown(self):self.server.shutdown();self.server.server_close();self.tmp.cleanup()
 def report(self):
  r=dict(id='probe-command',commandDigest=w.sha(w.canonical(self.plan['commands'][0])),planID=self.plan['id'],dataset=self.plan['dataset'],runID=self.plan['runID'],platform='macOS',processID=101,processNonce=str(uuid.uuid4()),status='PASS',halted=False)
  return dict(planID=self.plan['id'],dataset=self.plan['dataset'],runID=self.plan['runID'],planDigest=w.sha(self.raw),results=[r],completedAllCommands=True)
 def post(self,data=None,headers=None,path='/report'):
  raw=w.canonical(data or self.report());h={'Authorization':'Bearer '+self.server.token,'X-SyncLab-Launch':self.server.launch};h.update(headers or {});c=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=4);c.request('POST',path,raw,h);r=c.getresponse();result=(r.status,r.read());c.close();return result
 def test_correct_token_launch_and_raw_ack(self):
  report=self.report();status,data=self.post(report);self.assertEqual(status,200);self.assertEqual(json.loads(data)['acceptedSHA256'],w.sha(w.canonical(report)))
 def test_wrong_token(self):self.assertEqual(self.post(headers={'Authorization':'Bearer '+'0'*64})[0],400);self.assertFalse((self.output/'report.json').exists())
 def test_wrong_launch(self):self.assertEqual(self.post(headers={'X-SyncLab-Launch':str(uuid.uuid4())})[0],400)
 def test_unknown_route(self):self.assertEqual(self.post(path='/../report')[0],400)
 def test_transfer_encoding(self):self.assertEqual(self.post(headers={'Transfer-Encoding':'chunked'})[0],400)
 def test_declared_too_big(self):self.assertEqual(self.post(headers={'Content-Length':'32000001'})[0],400)
 def test_mock_full_launcher_no_container_touch(self):
  binary=self.root/'SyncLab.app/Contents/MacOS/SyncLab';binary.parent.mkdir(parents=True);binary.write_bytes(b'synthetic executable');config={'testUID':901,'executableSHA256':w.sha(binary.read_bytes())};calls=[]
  def command(argv,**kw):
   calls.append(argv)
   if argv[0]=='/usr/bin/open':
    self.assertEqual(argv,['/usr/bin/open','-n','-W','-a',str(self.root/'SyncLab.app')]);env=kw['env'];self.assertEqual(base64.b64decode(env['SYNCLAB_PROBE_WINDOW_PLAN']),self.raw)
    self.assertNotIn('SYNCLAB_PROBE_TOKEN',env);self.assertNotIn('SYNCLAB_PROBE_BRIDGE',env);self.assertNotIn('SYNCLAB_PROBE_IMPORTED_PLAN',env)
    c=http.client.HTTPConnection('127.0.0.1',int(env['SYNCLAB_PROBE_WINDOW_URL'].rsplit(':',1)[1]),timeout=4)
    c.request('POST','/report',w.canonical(self.report()),{'Authorization':'Bearer '+env['SYNCLAB_PROBE_WINDOW_TOKEN'],'X-SyncLab-Launch':env['SYNCLAB_PROBE_WINDOW_LAUNCH']});response=c.getresponse();self.assertEqual(response.status,200);response.read();c.close()
   else:self.assertEqual(argv[0],'/usr/bin/codesign')
   return subprocess.CompletedProcess(argv,0)
  with patch.object(w.os,'getuid',return_value=901),patch.object(w.subprocess,'run',side_effect=command),patch.object(Path,'home',side_effect=AssertionError('No App-container access')),patch.dict(os.environ,{'SYNCLAB_PROBE_BRIDGE':'forbidden','SYNCLAB_PROBE_TOKEN':'forbidden','SYNCLAB_PROBE_IMPORTED_PLAN':'YES'}):
   w.run_network(self.root,'01-test',config,self.stage,self.raw)
   with self.assertRaises(FileExistsError):w.run_network(self.root,'01-test',config,self.stage,self.raw)
  self.assertEqual(len(calls),2);self.assertTrue((self.root/'results/01-test/report.json').exists());self.assertNotIn('token', (self.root/'results/01-test/transport.json').read_text().lower())
if __name__=='__main__':unittest.main()
