#!/usr/bin/env python3
"""Read-only bounded Mac runtime evidence checks. Never prints account fingerprints."""
import argparse,base64,copy,hashlib,json,re
from pathlib import Path
IDS=['probe-001-mac-connect','probe-002-mac-save-base','probe-003-mac-sync-base','probe-004-mac-reopen','probe-005-mac-sync-after-reopen']
ACTIONS=['connect','save','sync','reopen','sync']
PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
IMAGE_HASH='6b1048f8a6d40bac0b2954c18fefa40c4ea7a96120fc2e54b7317c0e43c2bbec'
MUTATION=dict(deleted=False,id='probe-base-mac-001',imageBytes=68,imageHash=IMAGE_HASH,object='probe-entry',parents=[],requires=[],text='SYNTHETIC G1 Mac initial text and original PNG',version=1)
ENVELOPE=dict(mutations=[MUTATION],object='probe-entry',version=1)
PROJECTION=dict(candidates=['probe-base-mac-001'],complete=True,preview=MUTATION,state='ready')
EVENTS={'ENGINE_STARTED_DEVELOPMENT_OPT_IN','STATE_DURABLE','SAME_ACCOUNT_QUEUE_REBUILT','ACK_EXACT_AND_RESCHEDULED','FETCH_CONTENT_DURABLE'}
def require(value,label):
 if not value: raise AssertionError(label)
def verify(requests,results):
 require(len(PNG)==68 and hashlib.sha256(PNG).hexdigest()==IMAGE_HASH,'reference PNG integrity')
 fingerprints=[]
 for i,(raw,result) in enumerate(zip(requests,results)):
  command=json.loads(raw)
  expected={'action':ACTIONS[i],'id':IDS[i]}
  if i==1:expected['mutation']=MUTATION
  require(command==expected,'fixed request identity/content')
  require(result['id']==IDS[i] and result['commandDigest']==hashlib.sha256(raw).hexdigest(),'raw command digest binding')
  require(result['dataset']=='synthetic-g1-20261107-r4' and result['runID']=='probe-run-20261107-r4','dataset/run binding')
  require(result['scope']=='Command execution only; not a cloud convergence or G1 acceptance verdict','scope disclaimer')
  require(result['status']=='PASS' and result['platform']=='macOS' and result['halted'] is False and not result.get('errorCode'),'command success/nonhalted')
  fp=result.get('accountFingerprint');require(isinstance(fp,str) and re.fullmatch('[0-9a-f]{64}',fp),'fingerprint present/shape');fingerprints.append(fp)
  require(isinstance(result['events'],list) and set(result['events'])<=EVENTS,'no failure/unknown events')
  require('ENGINE_STARTED_DEVELOPMENT_OPT_IN' in result['events'],'real engine entry event')
  if i==0:
   require(result['snapshot']=={'envelopes':[],'images':{}} and result['pendingKeys']==[] and result['projections']=={},'initial empty state')
  else:
   require(result['snapshot']['envelopes']==[ENVELOPE],'exact mutation set and fields')
   require(set(result['snapshot']['images'])=={IMAGE_HASH},'exact image set')
   data=base64.b64decode(result['snapshot']['images'][IMAGE_HASH],validate=True)
   require(data==PNG and len(data)==MUTATION['imageBytes'] and hashlib.sha256(data).hexdigest()==IMAGE_HASH,'original PNG bytes/hash/size')
   require(result['projections']=={'probe-entry':PROJECTION},'complete ready projection')
   require(re.fullmatch('[0-9a-f]{64}',result.get('checkpointHash','')) is not None,'checkpoint present/shape')
  pending=['image-'+IMAGE_HASH,'object-probe-entry'] if i==1 else []
  require(sorted(result['pendingKeys'])==pending,'pending transition')
 require(len(set(fingerprints))==1,'same account fingerprint across commands')
 require({'ACK_EXACT_AND_RESCHEDULED','FETCH_CONTENT_DURABLE','STATE_DURABLE'}<=set(results[2]['events']),'sync ACK/fetch/persistence evidence')
 require(results[2]['checkpointHash']==results[3]['checkpointHash'],'checkpoint retained on store/engine reopen')
 require(results[3]['events']==['ENGINE_STARTED_DEVELOPMENT_OPT_IN'],'reopened engine fresh event history')
 require('STATE_DURABLE' in results[4]['events'],'sync after reopen persisted SDK state')
 require(all(r['snapshot']==results[1]['snapshot'] for r in results[2:]),'no content loss or duplication through sync/reopen')
 return True

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path('/private/tmp/g1-bridge-20261107-r4'));parser.add_argument('--self-test',action='store_true');args=parser.parse_args()
 raws=[(args.root/'requests'/(i+'.json')).read_bytes() for i in IDS]
 result_raws=[(args.root/'results'/(i+'.json')).read_bytes() for i in IDS]
 results=[json.loads(r) for r in result_raws];verify(raws,results)
 print('PASS: 5 Mac command/result pairs; exact request digest, dataset/run, same account fingerprint (redacted).')
 print('PASS: one exact mutation and original 68-byte PNG retained across sync, store/engine reopen and subsequent sync.')
 print('PASS: pending 0 -> 2 -> 0 -> 0 -> 0; ACK/fetch/state events, equal pre/post-reopen checkpoint, no halted/error results.')
 if args.self_test:
  changes=[('digest',lambda r:r[2].update(commandDigest='0'*64)),('dataset',lambda r:r[2].update(dataset='synthetic-g1-wrong')),('run',lambda r:r[2].update(runID='probe-wrong')),('fingerprint',lambda r:r[3].update(accountFingerprint='0'*64)),('mutation',lambda r:r[3]['snapshot']['envelopes'][0]['mutations'][0].update(text='SYNTHETIC wrong')),('image',lambda r:r[3]['snapshot']['images'].update({IMAGE_HASH:base64.b64encode(b'wrong').decode()})),('pending',lambda r:r[2].update(pendingKeys=['object-probe-entry'])),('checkpoint',lambda r:r[3].update(checkpointHash='0'*64)),('ACK',lambda r:r[2].update(events=['ENGINE_STARTED_DEVELOPMENT_OPT_IN','STATE_DURABLE','FETCH_CONTENT_DURABLE'])),('projection',lambda r:r[3]['projections']['probe-entry'].update(complete=False)),('duplicate mutation',lambda r:r[3]['snapshot']['envelopes'][0]['mutations'].append(copy.deepcopy(MUTATION))),('halted',lambda r:r[4].update(halted=True))]
  for name,change in changes:
   altered=copy.deepcopy(results);change(altered)
   try:verify(raws,altered)
   except AssertionError:pass
   else:raise AssertionError('negative control accepted: '+name)
  print('PASS: 12 in-memory tampering negative controls rejected; no original input modified.')
 print('NOT_RUN: second client, process/device restart, cloud-only reconstruction, conflict/multi-client/offline acceptance.')
 print(json.dumps({'inputs':[{'id':i,'requestSHA256':hashlib.sha256(q).hexdigest(),'resultSHA256':hashlib.sha256(r).hexdigest()} for i,q,r in zip(IDS,raws,result_raws)]},indent=2))
if __name__=='__main__':main()
