#!/usr/bin/env python3
"""Local-only timing probe using copies of the synthetic review executable.
Not a deterministic CI test and not proof against arbitrary malicious ABA.
Usage: artifact_race.py BINARY PLAN_DIR NEW_OUTPUT_ROOT
"""
import json, os, pathlib, shutil, subprocess, sys, threading, time
binary=pathlib.Path(sys.argv[1]).resolve(); plan=pathlib.Path(sys.argv[2]).resolve()
root=pathlib.Path(sys.argv[3]).resolve(); root.mkdir(exist_ok=False)
digest=(plan/'plan.sha256').read_text().strip()
a=root/'source-a'; b=root/'source-b'; target=root/'artifact'
for output in [a,b,target]: shutil.copy2(binary,output)
stop=threading.Event(); swaps=[0]
def replace():
    while not stop.is_set():
        source=a if swaps[0]%2==0 else b
        link=root/'next'; os.link(source,link); os.replace(link,target); swaps[0]+=1
p=subprocess.Popen([str(binary),'preflight',str(plan),digest,str(target),str(root/'report')],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
time.sleep(.005)
t=threading.Thread(target=replace); t.start()
out,err=p.communicate(); stop.set(); t.join()
report=json.loads((root/'report/report.json').read_bytes())
result={'exit':p.returncode,'swaps':swaps[0],'report':report,'stdout':out.decode(),'stderr':err.decode()}
(root/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
assert p.returncode==2 and report['signatureVerified'] is False and 'ARTIFACT_CHANGED' in report['rejectionCodes']
