import os
"""Purely fabricated 27-stage verifier fixtures; not device/cloud evidence."""
from pathlib import Path
import importlib.util,copy,json,shutil,tempfile,uuid,hashlib
R=Path(os.environ['G1_REVIEW_OUT']);P=Path(os.environ['G1_REVIEW_PLANS'])
spec=importlib.util.spec_from_file_location('fixture',R/'make_fixture.py');f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
source=Path(os.environ['G1_REVIEW_REPO'])/'Experiments/iCloudSyncG1/Tools/verify_fault_window.py';shutil.copyfile(source,R/'oracle-full-source.py')
spec=importlib.util.spec_from_file_location('oracle',R/'oracle-full-source.py');o=importlib.util.module_from_spec(spec);spec.loader.exec_module(o)
stages=json.loads((P/'manifest.json').read_bytes())[:3]
def project(s):
 out={};allm=s.facts
 for e in s.snap()['envelopes']:
  mids={m['id'] for m in e['mutations']};parents={p for m in e['mutations'] for p in m['parents']};heads=sorted(mids-parents)
  complete=all(p in mids for p in parents) and bool(heads)
  h=allm[heads[0]] if len(heads)==1 else None
  def ready(obj,trail=()):
   if obj in trail:return False
   ms=[m for m in allm.values() if m['object']==obj]
   ids={m['id'] for m in ms};ps={p for m in ms for p in m['parents']};hs=ids-ps
   if len(hs)!=1 or not ps<=ids:return False
   m=allm[next(iter(hs))]
   return not m['deleted'] and all(ready(d,(*trail,obj)) for d in m['requires'])
  state='deleted' if complete and h and h['deleted'] else 'ready' if ready(e['object']) else 'staged'
  out[e['object']]={'state':state,'candidates':heads if heads else sorted(mids),'complete':state in ('ready','deleted'),'preview':h if state=='ready' else None}
 return out
D=R/'synthetic-results-27'
if D.exists():shutil.rmtree(D)
shutil.copytree(R/'synthetic-results',D)
server=f.State();states={}
for ix,stage in enumerate(stages):
 plan=stage['plan'];s=states.setdefault(stage['device'],f.State());rows=[]
 for c in plan['commands']:
  events=['ENGINE_STARTED_DEVELOPMENT_OPT_IN']
  if c['action']=='save':s.save(c['mutation'])
  if c['action']=='sync':server.facts.update(copy.deepcopy(s.facts));server.images.update(s.images);s.facts.update(copy.deepcopy(server.facts));s.images.update(server.images);s.pending.clear();events=['ACK_EXACT_AND_RESCHEDULED','FETCH_CONTENT_DURABLE','STATE_DURABLE']
  rows.append(dict(id=c['id'],commandDigest=f.sha(f.canon(c)),planID=plan['id'],dataset=plan['dataset'],runID=plan['runID'],status='PASS',halted=False,platform=stage['device'],processID=11000+ix,processNonce=str(uuid.uuid5(uuid.NAMESPACE_DNS,stage['name'])),accountSource='liveCloudKit',accountFingerprint=f.FP['A'],snapshot=s.snap(),projections=project(s),snapshotComplete=True,unavailableImages=[],pendingKeys=sorted(s.pending),events=events))
 dest=D/stage['name'];dest.mkdir();(dest/'report.json').write_bytes(f.canon(dict(planID=plan['id'],dataset=plan['dataset'],runID=plan['runID'],planDigest=f.sha((P/stage['name']/'SyncLab-Probe-Plan.json').read_bytes()),completedAllCommands=True,results=rows)))
print('SYNTHETIC ONLY full 27-stage positive:',o.verify(P,D))
def edit(root,stage,fn):
 path=root/stages[stage]['name']/'report.json';v=json.loads(path.read_bytes());fn(v);path.write_bytes(f.canon(v))
cases=[('nested dependency identity wrong',lambda root:edit(root,1,lambda v:v['results'][0].update(dataset='wrong',runID='wrong',planID='wrong'))),('dependency process missing',lambda root:edit(root,1,lambda v:[x.update(processNonce=None,processID=None) for x in v['results']])),('dependency ready preview wrong old head',lambda root:edit(root,1,lambda v:v['results'][-1]['projections']['probe-batch-head'].update(preview=next(m for e in v['results'][-1]['snapshot']['envelopes'] for m in e['mutations'] if m['id']=='probe-batch-head-old')))),('dependency preview/candidates/complete cleared',lambda root:edit(root,1,lambda v:[p.update(preview=None,candidates=[],complete=False) for p in v['results'][-1]['projections'].values()])),('dependency extra projection',lambda root:edit(root,1,lambda v:v['results'][-1]['projections'].update({'private-unexpected-object':{'state':'ready'}}))),('dependency cached account claimed live connect',lambda root:edit(root,1,lambda v:v['results'][0].update(accountSource='cachedPartitionNotCurrentAccount'))),('dependency new image ACK absent',lambda root:edit(root,1,lambda v:[x.update(events=[]) for x in v['results']])),('dependency mutation tamper MUST reject',lambda root:edit(root,1,lambda v:v['results'][-1]['snapshot']['envelopes'][0]['mutations'][0].update(text='TAMPER')))]
accepted=[]
for name,change in cases:
 with tempfile.TemporaryDirectory(prefix='g1-dependency-negative-') as tmp:
  dest=Path(tmp)/'results';shutil.copytree(D,dest);change(dest)
  try:o.verify(P,dest)
  except (ValueError,KeyError,TypeError):print('REJECTED',name)
  else:print('ACCEPTED BAD INPUT',name);accepted.append(name)
print(json.dumps({'badInputsAccepted':accepted,'tested':len(cases),'scope':'Synthetic only, all 27 stages'}))

assert not accepted, "Oracle accepted negative controls"
