from pathlib import Path
import subprocess,tempfile,resource
binary=Path('/private/tmp/g1-next-batch-review/release-build/release/LabReplay')
with tempfile.TemporaryDirectory(prefix='g1-release-batch-review-') as temp:
 output=Path(temp)/'must-not-exist'
 def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
 r=subprocess.run([str(binary),'prepare-batch',str(output),'synthetic-g1-review','probe-review'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,preexec_fn=no_core)
 assert r.returncode!=0
 assert not output.exists()
 assert b'Prepared three ordered synthetic plans' not in r.stdout
 symbols=subprocess.run(['/usr/bin/nm',str(binary)],capture_output=True,check=True).stdout
 assert b'RemainingBatch' not in symbols
 print('PASS: actual Release CLI rejects prepare-batch before destination creation; RemainingBatch absent from symbols. Expected nonzero exit:',r.returncode)
