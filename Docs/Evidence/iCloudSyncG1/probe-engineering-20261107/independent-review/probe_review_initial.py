import contextlib, http.client, importlib.util, io, json, os, pathlib, runpy, subprocess, sys, tempfile, threading, types
from unittest.mock import patch
TOOLS=pathlib.Path('/private/tmp/PersonalGrowthOS-icloud-g1/Experiments/iCloudSyncG1/Tools')
spec=importlib.util.spec_from_file_location('bridge',TOOLS/'probe_bridge.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
with tempfile.TemporaryDirectory(prefix='g1-review-') as tmp:
 root=pathlib.Path(tmp)/'bridge';server=mod.Bridge(root);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 source=pathlib.Path(tmp)/'command.json';source.write_text(json.dumps({'id':'probe-current','action':'snapshot'}));mod.enqueue(root,source)
 conn=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=3)
 data=json.dumps({'id':'probe-current','dataset':'synthetic-g1-WRONG','runID':'probe-OLD','status':'PASS'})
 conn.request('POST','/result',data,headers={'Authorization':'Bearer '+server.token});response=conn.getresponse();code=response.status;response.read();conn.close()
 print(json.dumps({'case':'wrong-result-identity','httpStatus':code,'resultPublished':(root/'results/probe-current.json').exists()}))
 server.shutdown();server.server_close();thread.join()
with tempfile.TemporaryDirectory(prefix='g1-package-review-') as tmp:
 root=pathlib.Path(tmp);app=root/'Synthetic.app';(app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/MacOS/SyncLab').write_bytes(b'SYNTHETIC-EXECUTABLE')
 conn=root/'connection.json';conn.write_text(json.dumps({'address':'http://127.0.0.1:23456','token':'a'*64}));out=root/'package'
 def command(args,**kwargs):
  if args[0]=='/usr/bin/ditto':
   import shutil;shutil.copytree(args[1],args[2])
  return subprocess.CompletedProcess(args,0)
 argv=['prepare_probe_package.py','--app',str(app),'--output',str(out),'--connection',str(conn),'--test-user','synthetic-test-user','--dataset','synthetic-g1-review','--run-id','probe-review']
 old=os.umask(0o077)
 try:
  with patch.object(sys,'argv',argv),patch('pwd.getpwnam',return_value=types.SimpleNamespace(pw_uid=os.getuid()+100)),patch('subprocess.run',command),contextlib.redirect_stdout(io.StringIO()):
   runpy.run_path(str(TOOLS/'prepare_probe_package.py'),run_name='__main__')
 finally:os.umask(old)
 print(json.dumps({'case':'package-under-umask077','outputMode':oct(out.stat().st_mode&0o777),'pythonLauncherMode':oct((out/'launch_probe.py').stat().st_mode&0o777),'verifierMode':oct((out/'verify_signing.py').stat().st_mode&0o777),'tokenMode':oct((out/'connection-private.json').stat().st_mode&0o777)}))
