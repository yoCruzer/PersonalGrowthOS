import contextlib, io, json, os, pathlib, runpy, shutil, subprocess, sys, tempfile, types
from unittest.mock import patch
TOOLS=pathlib.Path('/private/tmp/PersonalGrowthOS-icloud-g1/Experiments/iCloudSyncG1/Tools')
with tempfile.TemporaryDirectory(prefix='g1-launcher-review-') as tmp:
 root=pathlib.Path(tmp); app=root/'Synthetic.app'; (app/'Contents/MacOS').mkdir(parents=True); (app/'Contents/MacOS/SyncLab').write_bytes(b'SYNTHETIC')
 connection=root/'connection.json'; token='a'*64
 connection.write_text(json.dumps(dict(address='http://127.0.0.1:23456',token=token,dataset='synthetic-g1-review',runID='probe-review')))
 output=(root/'package').resolve(); calls=[]
 def fake_run(args,**kwargs):
  calls.append((args,kwargs))
  if args[0]=='/usr/bin/ditto': shutil.copytree(args[1],args[2])
  return subprocess.CompletedProcess(args,0)
 argv=['prepare_probe_package.py','--app',str(app),'--output',str(output),'--connection',str(connection),'--test-user','synthetic-test-user','--dataset','synthetic-g1-review','--run-id','probe-review']
 with patch.object(sys,'argv',argv),patch('pwd.getpwnam',return_value=types.SimpleNamespace(pw_uid=901)),patch('os.getuid',return_value=900),patch('subprocess.run',fake_run),contextlib.redirect_stdout(io.StringIO()):
  runpy.run_path(str(TOOLS/'prepare_probe_package.py'),run_name='__main__')
 assert calls[0][0][1].endswith('verify_signing.py')
 assert any(call[0][:3]==['/bin/chmod','+a','user:synthetic-test-user allow read'] for call in calls)
 calls.clear()
 with patch('os.getuid',return_value=900),patch('subprocess.run',fake_run):
  try: runpy.run_path(str(output/'launch_probe.py'),run_name='__main__')
  except SystemExit: pass
  else: raise AssertionError('wrong user launched')
 assert not calls
 with patch('os.getuid',return_value=901),patch.dict(os.environ,{'PATH':'/usr/bin:/bin'},clear=True),patch('subprocess.run',fake_run),contextlib.redirect_stdout(io.StringIO()):
  runpy.run_path(str(output/'launch_probe.py'),run_name='__main__')
 assert len(calls)==2
 assert calls[0][0][1]==str(output/'verify_signing.py')
 args,kw=calls[1]
 assert args==['/usr/bin/open','-n','-a',str(output/'SyncLab.app')]
 assert token not in str(args)
 assert kw['env']['SYNCLAB_PROBE_TOKEN']==token
 assert kw['env']['SYNCLAB_PROBE_RUN']=='probe-review'
 assert kw['env']['SYNCLAB_DATASET']=='synthetic-g1-review'
 assert kw['env']['SYNCLAB_ENABLE_DEVELOPMENT']=='YES'
 assert kw['check'] is True
 print('PASS: synthetic packaging signature check ordering and designated ACL arguments')
 print('PASS: wrong UID rejects before any subprocess')
 print('PASS: correct UID verifies copy then open; token absent argv, fixed opt-in/run/dataset/token in environment')
 print('LIMIT: signature, ACL command, and application launch mocked; no private inputs used')
