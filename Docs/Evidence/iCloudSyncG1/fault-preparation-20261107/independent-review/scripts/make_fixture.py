import os
"""Pure synthetic evidence generator for oracle tests. NO REAL CLOUD RESULTS."""
from pathlib import Path
import base64,copy,hashlib,json,uuid
ROOT=Path(os.environ['G1_REVIEW_OUT']);PLANS=Path(os.environ['G1_REVIEW_PLANS'])
PNG='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQT7z8HwAEKQJLn6egIAAAAABJRU5ErkJggg=='
def canon(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def sha(x):return hashlib.sha256(x if isinstance(x,bytes) else x.encode()).hexdigest()
IH=sha(base64.b64decode(PNG));FP={'A':sha('SYNTHETIC FP A'),'B':sha('SYNTHETIC FP B')};AH={'A':sha('SYNTHETIC ACCOUNT A'),'B':sha('SYNTHETIC ACCOUNT B')}
class State:
 def __init__(self):self.facts={};self.images={};self.pending=set();self.cp=None
 def save(self,m):
  self.facts[m['id']]=copy.deepcopy(m);self.pending.add('object-'+m['object'])
  if m.get('imageHash') and m['imageHash'] not in self.images:self.images[m['imageHash']]=PNG;self.pending.add('image-'+m['imageHash'])
 def snap(self,missing=False):
  groups={}
  for m in self.facts.values():groups.setdefault(m['object'],[]).append(m)
  envs=[{'version':1,'object':o,'mutations':sorted(ms,key=lambda m:m['id'])} for o,ms in sorted(groups.items())]
  refs={m['imageHash'] for m in self.facts.values() if 'imageHash' in m}
  return {'envelopes':copy.deepcopy(envs),'images':{} if missing else {h:self.images[h] for h in sorted(refs) if h in self.images}}
 def projections(self):
  out={}
  for e in self.snap()['envelopes']:
   ps={p for m in e['mutations'] for p in m['parents']};heads=[m for m in e['mutations'] if m['id'] not in ps]
   assert len(heads)==1
   out[e['object']]={'state':'ready','candidates':[heads[0]['id']],'preview':copy.deepcopy(heads[0]),'complete':True}
  return out

def generate(dest):
 dest.mkdir(parents=True,exist_ok=False);(dest/'SYNTHETIC_ONLY.txt').write_text('Every report here is fabricated only to test the verifier. No application/CloudKit/device ran. Never use as G1 evidence.\n')
 stages=[s for s in json.loads((PLANS/'manifest.json').read_bytes()) if not s['name'].startswith('00-')];cloud={};locals_={};boundary_by_plan={};allrecords={}
 for number,stage in enumerate(stages,1):
  plan=stage['plan'];device=stage['device'];ds=plan['dataset'];account='B' if stage['name'].startswith('22-') else 'A'
  key=(device,ds,account);state=locals_.setdefault(key,State());server=cloud.setdefault((ds,account),State());nonce=str(uuid.uuid5(uuid.NAMESPACE_DNS,'SYNTHETIC-stage-'+stage['name']));pid=10000+number
  events=['ENGINE_STARTED_DEVELOPMENT_OPT_IN'];source='liveCloudKit';values=[];boundary=None
  def obs(point,command,s=None,missing=False,digests=None):
   s=state if s is None else s;action=command['action'];provenance='actualCloudKitCallback' if action in ['crashOnFetch','crashOnState','editDuringSend','crashWithImageLease','restoreIsolation'] else 'localTransactionOrFileFault'
   value=dict(commandID=command['id'],planID=plan['id'],commandDigest=sha(canon(command)),runID=plan['runID'],dataset=ds,point=point,networkStopped=point in ['restoreTargetGated','oldReceiverFencedBeforeInstall','restoreGateSurvivedReopen','accountChangeFenced'],processNonce=nonce,processID=pid,sourceAccountHash=AH[account],provenance=provenance,snapshot=s.snap(missing),unavailableImages=[IH] if missing else [],pendingKeys=sorted(s.pending),recordDigests=digests or {})
   if s.cp is not None:value['checkpointHash']=s.cp
   if missing:value['snapshotError']='expectedOriginalUnavailable'
   return value
  def sync(command):
   had=bool(state.pending);new=server.facts!=state.facts
   server.facts.update(copy.deepcopy(state.facts));server.images.update(state.images);state.facts.update(copy.deepcopy(server.facts));state.images.update(server.images);state.pending.clear();state.cp=sha(stage['name']+command['id']);events.append('STATE_DURABLE')
   if had:events.append('ACK_EXACT_AND_RESCHEDULED')
   if new:events.append('FETCH_CONTENT_DURABLE')
   events.append('STATE_DURABLE')
  for command in plan['commands']:
   a=command['action'];observations=None
   if a=='openCached':source='cachedPartitionNotCurrentAccount';events=[]
   elif a=='connect':source='liveCloudKit';events=['ENGINE_STARTED_DEVELOPMENT_OPT_IN']
   elif a=='save':state.save(command['mutation'])
   elif a=='sync':sync(command)
   elif a=='crashOnFetch':
    state.facts.update(copy.deepcopy(server.facts));state.images.update(server.images)
    digests={'object-'+e['object']:sha(canon(e)) for e in state.snap()['envelopes']}
    boundary=obs('afterFetchedInstall',command,digests=digests);break
   elif a=='crashOnState':sync(command);boundary=obs('afterFetchedState',command);break
   elif a=='crashBeforeSave':
    boundary=obs('beforeSaveCommit',command);boundary['pendingKeys']=sorted(state.pending|{'object-'+command['mutation']['object']});break
   elif a=='crashAfterSave':state.save(command['mutation']);boundary=obs('afterSaveCommit',command);break
   elif a=='crashWithImageLease':boundary=obs('assetLeaseBeforeACK',command,digests={'image-'+IH:sha(canon(70))});break
   elif a=='inspectFaults':
    observations=[copy.deepcopy(boundary_by_plan[command['faultSource']['planID']])]
    if observations[0]['point']=='assetLeaseBeforeACK':
     prepared=copy.deepcopy(observations[0]);prepared['point']='assetBatchPrepared';observations.insert(0,prepared)
   elif a=='editDuringSend':
    m=command['mutation'];oldenv=next(e for e in state.snap()['envelopes'] if e['object']==m['object']);digests={'object-'+m['object']:sha(canon(oldenv))}
    before=obs('oldBatchPrepared',command,digests=digests);state.save(m);edited=obs('newEditBeforeACK',command);ack=obs('oldACKBeforeCommit',command,digests=digests);state.pending={'object-'+m['object']};after=obs('newVersionStillPending',command)
    observations=[before,edited,ack,after];events+=['STATE_DURABLE','ACK_EXACT_AND_RESCHEDULED']
   elif a=='imageFaults':
    observations=[obs('imageBaseline-0',command),obs('imageMissing-0',command,missing=True),obs('imageMissingRepaired-0',command),obs('imageTruncated-0',command,missing=True),obs('imageTruncatedRepaired-0',command)];events=[];source='cachedPartitionNotCurrentAccount'
   elif a=='reopenLocal':events=[];source='cachedPartitionNotCurrentAccount'
   elif a=='restoreIsolation':
    target=State();target.save(command['mutation']);digests={'object-'+e['object']:sha(canon(e)) for e in server.snap()['envelopes']}
    observations=[obs('restoreTargetGated',command,target),obs('oldReceiverFencedBeforeInstall',command,digests=digests),obs('restoreGateSurvivedReopen',command,target)];events=['ACCOUNT_FENCE_SYNTHETIC','EXPECTED_RESTORE_FENCE_OBSERVED']
   elif a=='waitForAccountChange':
    observations=[obs('beforeAccountChange',command),obs('accountChangeFenced',command)];events=['ACCOUNT_CHANGED_REOPEN_REQUIRED','EXPECTED_ACCOUNT_FENCE_OBSERVED'];source='cachedPartitionNotCurrentAccount'
   elif a=='closePartition':events=[]
   elif a!='snapshot':raise ValueError('Unimplemented synthetic action '+a)
   v=dict(scope='Command execution only; not a cloud convergence or G1 acceptance verdict',id=command['id'],planID=plan['id'],dataset=ds,runID=plan['runID'],commandDigest=sha(canon(command)),status='PASS',events=copy.deepcopy(events),halted=False,platform=device,processNonce=nonce,processID=pid,accountSource=source,accountFingerprint=FP[account],snapshot=state.snap(),projections=state.projections(),snapshotComplete=True,unavailableImages=[],pendingKeys=sorted(state.pending))
   if state.cp is not None:v['checkpointHash']=state.cp
   if observations is not None:v['faultObservations']=observations
   values.append(v)
  if boundary is not None:
   boundary_by_plan[plan['id']]=boundary;file='boundary.json';record=boundary
  else:
   file='report.json';record=dict(scope='Command execution only; not cloud convergence or G1 acceptance',planID=plan['id'],dataset=ds,runID=plan['runID'],planDigest=sha((PLANS/stage['name']/'SyncLab-Probe-Plan.json').read_bytes()),results=values,completedAllCommands=True)
  directory=dest/stage['name'];directory.mkdir();(directory/file).write_bytes(canon(record));allrecords[stage['name']]=(file,record)
 return allrecords
if __name__=='__main__':generate(ROOT/'synthetic-results')
