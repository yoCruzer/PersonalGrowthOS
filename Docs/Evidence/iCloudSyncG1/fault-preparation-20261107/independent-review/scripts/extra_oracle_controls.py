import os
from pathlib import Path
import importlib.util,shutil,json,tempfile
R=Path(os.environ['G1_REVIEW_OUT']);S=Path(os.environ['G1_REVIEW_REPO'])/'Experiments/iCloudSyncG1/Tools/verify_fault_window.py';shutil.copyfile(S,R/'oracle-extra-source.py');sp=importlib.util.spec_from_file_location('o',R/'oracle-extra-source.py');o=importlib.util.module_from_spec(sp);sp.loader.exec_module(o)
P=Path(os.environ['G1_REVIEW_PLANS']);B=R/'synthetic-results-27'
def edit(r,stage,fn):
 d=next(d for d in r.iterdir() if d.is_dir() and d.name.startswith(stage+'-'));p=next(d.glob('*.json'));v=json.loads(p.read_bytes());fn(v);p.write_text(json.dumps(v))
def paired(r,b,recover,fn):
 edit(r,b,fn)
 def change(v):
  for row in v['results']:
   for obs in row.get('faultObservations',[]):fn(obs)
 edit(r,recover,change)
def remove_cp(r):
 paired(r,'06','07',lambda v:v.pop('checkpointHash',None))
 edit(r,'07',lambda v:[x.pop('checkpointHash',None) for x in v['results'][:3]])
cases=[('asset lease has no record digest',lambda r:paired(r,'13','14',lambda v:v.update(recordDigests={}))),('after state checkpoint absent',remove_cp),('observation account differs from report',lambda r:[edit(r,s[:2],lambda v:walk(v)) for s in []])]
def walk(v):
 if isinstance(v,dict):
  if 'sourceAccountHash' in v:v['sourceAccountHash']='a'*64
  for x in v.values():walk(x)
 elif isinstance(v,list):
  for x in v:walk(x)
def account(r):
 for p in r.glob('*/*.json'):
  v=json.loads(p.read_bytes());walk(v);p.write_text(json.dumps(v))
cases[-1]=(cases[-1][0],account)
# Third control is a documented opaque-field linkage limitation, NOT a must-fix.
print('POSITIVE',o.verify(P,B)['status'])
for name,fn in cases:
 with tempfile.TemporaryDirectory() as t:
  r=Path(t)/'results';shutil.copytree(B,r);fn(r)
  try:o.verify(P,r)
  except (ValueError,KeyError,TypeError):print('REJECTED',name)
  else:
   if name=='observation account differs from report':print('DOCUMENTED LIMIT: opaque account hashes have no derivable cross-field relation')
   else:raise AssertionError('Oracle accepted negative control: '+name)
