#!/usr/bin/env python3
"""Offline independent oracle + mocked launcher review. NEVER runs an app or cloud."""
import argparse,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--repo',type=Path,required=True);p.add_argument('--plans',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
repo=a.repo.resolve();plans=a.plans.resolve();out=a.output.resolve()
env={**os.environ,'G1_REVIEW_REPO':str(repo),'G1_REVIEW_PLANS':str(plans),'G1_REVIEW_OUT':str(out)}
for file in Path(__file__).parent.glob('*.py'):shutil.copyfile(file,out/file.name)
(out/'SYNTHETIC_ONLY.txt').write_text('Fabricated oracle inputs and mocked launch only. NOT device or cloud evidence.\n')
paths=[repo/'Experiments/iCloudSyncG1/Tools'/name for name in ['fault_window.py','verify_fault_window.py']]
(out/'tested-source-sha256.json').write_text(json.dumps({str(p.relative_to(repo)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2)+'\n')
for name in ['make_fixture.py','check_oracle_controls.py','dependency_controls.py','extra_oracle_controls.py','test_window_current.py']:
 with (out/(name+'.log')).open('w') as log:
  result=subprocess.run([sys.executable,str(out/name)],env=env,stdout=log,stderr=subprocess.STDOUT)
 print(name+': '+('PASS' if result.returncode==0 else 'FAIL'))
 if result.returncode:raise SystemExit(result.returncode)
print('Synthetic only: full 27-stage positive, 24 rejection controls, 8 mocked launcher tests. No G1/cloud verdict.')
