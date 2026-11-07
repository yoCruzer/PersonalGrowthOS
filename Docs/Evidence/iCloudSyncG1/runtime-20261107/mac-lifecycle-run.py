import sys,json,time,hashlib,base64
from pathlib import Path
sys.path.insert(0,'/private/tmp/PersonalGrowthOS-icloud-g1/Experiments/iCloudSyncG1/Tools')
from probe_bridge import enqueue
root=Path('/private/tmp/g1-bridge-20261107-r4')
files=Path('/private/tmp/g1-resume-20261107')
first=json.loads((root/'results/probe-003-mac-sync-base.json').read_text())
def result(cid):
 p=root/'results'/(cid+'.json'); deadline=time.monotonic()+45
 while not p.exists() and time.monotonic()<deadline: time.sleep(.5)
 assert p.exists(), 'command result timeout; do not replay: '+cid
 d=json.loads(p.read_text());raw=(root/'requests'/p.name).read_bytes()
 assert d['commandDigest']==hashlib.sha256(raw).hexdigest()
 assert d['runID']==first['runID'] and d['dataset']==first['dataset']
 assert d['accountFingerprint']==first['accountFingerprint']
 assert d['status']=='PASS' and not d['halted'], (cid,d.get('errorCode'))
 assert not any('ERROR' in x or 'FAILED' in x or 'HALTED' in x for x in d['events']),d['events']
 assert d['snapshot']['images']==first['snapshot']['images']
 assert next(e for e in d['snapshot']['envelopes'] if e['object']=='probe-entry')==first['snapshot']['envelopes'][0]
 return d

def run(cid,action,mutation=None):
 c={'id':cid,'action':action}
 if mutation is not None:c['mutation']=mutation
 raw=json.dumps(c,sort_keys=True,separators=(',',':')).encode()
 p=files/(cid+'-command.json')
 with p.open('xb') as f:f.write(raw)
 enqueue(root,p)
 return result(cid)

def verify(d,mutations,state,synced=False):
 e=next(e for e in d['snapshot']['envelopes'] if e['object']=='probe-mac-lifecycle')
 assert {x['id']:x for x in e['mutations']}=={x['id']:x for x in mutations}
 p=d['projections']['probe-mac-lifecycle']
 assert p['state']==state and p['complete'] and p['candidates']==[mutations[-1]['id']]
 if synced:assert not d['pendingKeys']
 else:assert d['pendingKeys']==['object-probe-mac-lifecycle']
 print(d['id']+': exact mutations, preserved PNG, '+state+', pending='+str(len(d['pendingKeys'])),flush=True)

create={'id':'probe-lifecycle-create','object':'probe-mac-lifecycle','parents':[],'requires':[],'text':'SYNTHETIC lifecycle initial','deleted':False,'version':1}
verify(result('probe-006-mac-lifecycle-create'),[create],'ready')
verify(run('probe-007-mac-lifecycle-sync-create','sync'),[create],'ready',True)
edit={**create,'id':'probe-lifecycle-edit','parents':[create['id']],'text':'SYNTHETIC lifecycle edited'}
verify(run('probe-008-mac-lifecycle-edit','save',edit),[create,edit],'ready')
verify(run('probe-009-mac-lifecycle-sync-edit','sync'),[create,edit],'ready',True)
deleted={**edit,'id':'probe-lifecycle-delete','parents':[edit['id']],'text':'SYNTHETIC lifecycle deleted intent','deleted':True}
verify(run('probe-010-mac-lifecycle-delete','save',deleted),[create,edit,deleted],'deleted')
verify(run('probe-011-mac-lifecycle-sync-delete','sync'),[create,edit,deleted],'deleted',True)
verify(run('probe-012-mac-lifecycle-reopen','reopen'),[create,edit,deleted],'deleted',True)
verify(run('probe-013-mac-lifecycle-sync-after-reopen','sync'),[create,edit,deleted],'deleted',True)
print('Single-Mac cloud lifecycle only; no two-device acceptance claimed.',flush=True)
