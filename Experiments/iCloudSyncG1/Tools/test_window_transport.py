import copy,json,http.client,tempfile,threading,unittest,uuid
from pathlib import Path
from window_transport import Receiver,canonical,sha

class ReceiverTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
  self.command={'id':'probe-crash','action':'crashOnFetch'}
  self.plan={'version':1,'id':'probe-plan','dataset':'synthetic-g1-transport','runID':'probe-run','commands':[self.command]}
  self.raw=canonical(self.plan);self.stage={'plan':self.plan,'expectedExit':75}
  self.server=Receiver(self.root,self.stage,self.raw)
  self.thread=threading.Thread(target=self.server.serve_forever,kwargs={'poll_interval':.01});self.thread.start()
  self.value={'commandID':'probe-crash','commandDigest':sha(canonical(self.command)),'planID':'probe-plan','dataset':self.plan['dataset'],'runID':'probe-run','point':'afterFetchedInstall','processNonce':str(uuid.uuid4()),'processID':123,'sourceAccountHash':'a'*64,'provenance':'actualCloudKitCallback'}
 def tearDown(self):self.server.shutdown();self.thread.join();self.server.server_close();self.tmp.cleanup()
 def post(self,path,data,token=None,launch=None):
  c=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=2)
  c.request('POST',path,body=data,headers={'Authorization':'Bearer '+(token or self.server.token),'X-SyncLab-Launch':launch or self.server.launch})
  response=c.getresponse();status=response.status;body=response.read();c.close();return status,body
 def test_durable_ack_idempotence_and_no_replacement(self):
  raw=canonical(self.value);status,body=self.post('/observation',raw)
  self.assertEqual(status,200);self.assertEqual(json.loads(body)['acceptedSHA256'],sha(raw));self.assertEqual((self.root/'boundary.json').read_bytes(),raw)
  self.assertEqual(self.post('/observation',raw)[0],200)
  changed={**self.value,'pendingKeys':['changed']}
  self.assertEqual(self.post('/observation',canonical(changed))[0],400);self.assertEqual((self.root/'boundary.json').read_bytes(),raw)
 def test_wrong_token_launch_route_and_nested_identity_rejected(self):
  raw=canonical(self.value)
  for kwargs in [{'token':'bad'},{'launch':str(uuid.uuid4())}]:self.assertEqual(self.post('/observation',raw,**kwargs)[0],400)
  self.assertEqual(self.post('/other',raw)[0],400)
  for key,value in [('dataset','wrong'),('commandDigest','b'*64),('point','../escape'),('provenance','LOCAL_CALLBACK_SEAM'),('processID',True)]:
   changed={**self.value,key:value};self.assertEqual(self.post('/observation',canonical(changed))[0],400)
  self.assertFalse((self.root/'boundary.json').exists())
 def test_duplicate_keys_and_wrong_process_cannot_replace(self):
  raw=canonical(self.value);self.assertEqual(self.post('/observation',raw)[0],200)
  changed={**self.value,'processNonce':str(uuid.uuid4())};self.assertEqual(self.post('/observation',canonical(changed))[0],400)
  self.assertEqual(self.post('/failure',b'{"code":"WINDOW_FAILED","code":"WINDOW_FAILED"}')[0],400)
 def test_valid_report_and_failure_are_retained(self):
  result={'id':'probe-crash','commandDigest':sha(canonical(self.command)),'planID':self.plan['id'],'dataset':self.plan['dataset'],'runID':self.plan['runID'],'processNonce':self.value['processNonce'],'processID':123,'platform':'macOS','status':'FAIL','halted':True}
  report={'planID':self.plan['id'],'dataset':self.plan['dataset'],'runID':self.plan['runID'],'planDigest':sha(self.raw),'completedAllCommands':False,'results':[result]}
  self.assertEqual(self.post('/report',canonical(report))[0],200)
  self.assertEqual(self.post('/failure',b'{"code":"WINDOW_FAILED"}')[0],200)
  self.assertTrue((self.root/'report.json').exists());self.assertTrue((self.root/'failure.json').exists())

if __name__=='__main__':unittest.main()
