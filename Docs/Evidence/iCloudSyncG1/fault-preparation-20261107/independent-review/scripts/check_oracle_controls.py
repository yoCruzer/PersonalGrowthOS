import os
"""All inputs fabricated; 24-scenario sub-oracle only, never runtime evidence."""
from pathlib import Path
import copy,importlib.util,json,shutil,tempfile
ROOT=Path(os.environ['G1_REVIEW_OUT']);SOURCE=Path(os.environ['G1_REVIEW_REPO'])/'Experiments/iCloudSyncG1/Tools/verify_fault_window.py'
snapshot=ROOT/'oracle-controls-source.py';shutil.copyfile(SOURCE,snapshot)
spec=importlib.util.spec_from_file_location('oracle_under_test',snapshot);oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
oracle.verify_dependencies=lambda *a,**kw:None  # Explicit parent-authorized boundary: 3 new dependency fixtures excluded here.
PLANS=Path(os.environ['G1_REVIEW_PLANS']);baseline=ROOT/'synthetic-results'
def load(root,prefix):
 directory=next(p for p in root.iterdir() if p.is_dir() and p.name.startswith(prefix+'-'));path=next(directory.glob('*.json'));return path,json.loads(path.read_bytes())
def edit(root,prefix,fn):
 p,v=load(root,prefix);fn(v);p.write_text(json.dumps(v))
def remove_fact(value,id):
 snap=value['snapshot'];snap['envelopes']=[dict(e,mutations=[m for m in e['mutations'] if m['id']!=id]) for e in snap['envelopes']];snap['envelopes']=[e for e in snap['envelopes'] if e['mutations']]
 if 'projections' in value:
  value['projections']={k:v for k,v in value['projections'].items() if k in {e['object'] for e in snap['envelopes']}}
def drop_recovery_fact(root,crash,recover,id):
 edit(root,crash,lambda b:remove_fact(b,id))
 def alter(report):
  for value in report['results'][:3]:
   remove_fact(value,id)
   for o in value.get('faultObservations',[]):remove_fact(o,id)
 edit(root,recover,alter)
def before_ack(root):
 def change(r):
  for v in r['results']:
   for o in v.get('faultObservations',[]):
    if o['point'] in ['newEditBeforeACK','oldACKBeforeCommit']:remove_fact(o,'probe-inflight-new')
 edit(root,'12',change)
def restore_empty(root):
 def change(r):
  for o in r['results'][-1]['faultObservations']:
   if o['point']=='restoreGateSurvivedReopen':o['snapshot']={'envelopes':[],'images':{}};o['pendingKeys']=[]
 edit(root,'20',change)
cases=[('missing image fault phases',lambda r:edit(r,'15',lambda v:v['results'][-1].pop('faultObservations'))),('missing account change phases',lambda r:edit(r,'21',lambda v:v['results'][-2].pop('faultObservations'))),('empty restored target accepted',restore_empty),('ready projection marked incomplete',lambda r:edit(r,'14',lambda v:next(iter(v['results'][-1]['projections'].values())).update(complete=False))),('new edit absent before old ACK',before_ack),('fetched fact lost across crash and silently fetched later',lambda r:drop_recovery_fact(r,'03','04','probe-remote-seed')),('post-state fetched fact lost',lambda r:drop_recovery_fact(r,'06','07','probe-remote-next')),('duplicate fault point',lambda r:edit(r,'12',lambda v:v['results'][2]['faultObservations'].append(copy.deepcopy(v['results'][2]['faultObservations'][0])))),('invalid process ID type',lambda r:edit(r,'01',lambda v:v['results'][0].update(processID='not-a-pid'))),('account B changes within same plan',lambda r:edit(r,'22',lambda v:v['results'][1].update(accountFingerprint='f'*64))),('invalid completion boolean',lambda r:edit(r,'01',lambda v:v.update(completedAllCommands='false'))),('wrong command digest MUST reject',lambda r:edit(r,'01',lambda v:v['results'][0].update(commandDigest='0'*64))),('wrong snapshot text MUST reject',lambda r:edit(r,'14',lambda v:v['results'][-1]['snapshot']['envelopes'][0]['mutations'][0].update(text='SYNTHETIC TAMPER'))),('empty account MUST reject',lambda r:edit(r,'01',lambda v:v['results'][0].update(accountFingerprint=None)))]
print('SYNTHETIC ONLY positive accepted:',bool(oracle.verify(PLANS,baseline)))
accepted=[]
for name,change in cases:
 with tempfile.TemporaryDirectory(prefix='g1-oracle-negative-') as tmp:
  target=Path(tmp)/'results';shutil.copytree(baseline,target);change(target)
  try:oracle.verify(PLANS,target)
  except (ValueError,KeyError,TypeError):print('REJECTED',name)
  else:print('ACCEPTED BAD INPUT',name);accepted.append(name)
print('SUMMARY',json.dumps({'badInputsAccepted':accepted,'tested':len(cases),'scope':'24-scenario oracle; dependency verifier explicitly stubbed, no cloud/device/runtime'}))

assert not accepted, "Oracle accepted negative controls"
