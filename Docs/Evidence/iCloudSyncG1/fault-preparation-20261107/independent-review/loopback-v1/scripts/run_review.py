#!/usr/bin/env python3
"""Independent synthetic local HTTP tests. No SyncLab App, cloud or device access."""
import argparse,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=False);out=a.output.resolve();repo=a.repo.resolve();env={**os.environ,'G1_LOOPBACK_OUT':str(out),'G1_LOOPBACK_REPO':str(repo)}
for s in Path(__file__).parent.iterdir():
 if s.is_file():shutil.copyfile(s,out/s.name)
src=repo/'Experiments/iCloudSyncG1/Sources/SyncLab/ProbeWindowTransport.swift';shutil.copyfile(src,out/src.name)
(out/'SYNTHETIC_ONLY.txt').write_text('Only local 127.0.0.1 sockets, synthetic payloads, mocked App launch. Never CloudKit or devices.\n')
subprocess.run(['swiftc','-DDEBUG','-module-cache-path',str(out/'swift-cache'),str(out/'TransportHarness.swift'),str(out/'ProbeWindowTransport.swift'),'-o',str(out/'transport-harness')],check=True)
for name in ['test_receiver.py','test_network.py','test_swift_transport.py']:
 with (out/(name+'.log')).open('w') as log:result=subprocess.run([sys.executable,str(out/name)],env=env,stdout=log,stderr=subprocess.STDOUT)
 print(name+': '+('PASS' if result.returncode==0 else 'FAIL'))
 if result.returncode:raise SystemExit(result.returncode)
print('23 independent synthetic tests passed. Not a real App/CloudKit/G1 verdict.')
