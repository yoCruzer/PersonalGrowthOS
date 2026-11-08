import json,pathlib,subprocess,hashlib
r=pathlib.Path(__file__).parent;b=r/'build/out/Products/Debug/FormalDevelopmentHost';results=[];reports=[]
for label,args,expected in [('fixture-a',['inspect-fixture'],2),('fixture-b',['inspect-fixture'],2),('extra-path',['inspect-fixture','/private/tmp/synthetic-forbidden'],64),('live',['inspect-fixture','--live'],64),('production',['inspect-fixture','Production'],64),('missing',[],64),('cloud',['run'],64)]:
 p=subprocess.run([str(b),*args],capture_output=True);(r/(label+'.stdout')).write_bytes(p.stdout);(r/(label+'.stderr')).write_bytes(p.stderr)
 ok=p.returncode==expected
 if expected==2:
  d=json.loads(p.stdout);ok=ok and d['mode']=='OFFLINE_ONLY' and d['status']=='NOT_READY' and d['networkOperations']==0 and d['networkAuthorized'] is False and d['p0Passed'] is False and d['environment']=='Development';reports.append(d)
 results.append({'case':label,'exit':p.returncode,'expected':expected,'pass':ok})
results.append({'case':'fresh-identities','pass':all(reports[0][k]!=reports[1][k] for k in ['run','dataset','planSHA256'])})
d={'status':'PASS' if all(x['pass'] for x in results) else 'FAIL','checks':results,'binarySHA256':hashlib.sha256(b.read_bytes()).hexdigest(),'artifactKind':'Independent compiled executable, not provisioned App Sandbox app','cloudOperations':0,'p0Passed':False};(r/'cli-summary.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d))
assert all(x['pass'] for x in results)
