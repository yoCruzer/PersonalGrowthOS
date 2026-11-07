#!/usr/bin/env python3
"""Read-only exact lifecycle verification, independent of controller assertions."""
import argparse,base64,copy,hashlib,json,re
from pathlib import Path
import verify_runtime as base
IDS=['probe-006-mac-lifecycle-create','probe-007-mac-lifecycle-sync-create','probe-008-mac-lifecycle-edit','probe-009-mac-lifecycle-sync-edit','probe-010-mac-lifecycle-delete','probe-011-mac-lifecycle-sync-delete','probe-012-mac-lifecycle-reopen','probe-013-mac-lifecycle-sync-after-reopen']
ACTIONS=['save','sync','save','sync','save','sync','reopen','sync']
CREATE=dict(deleted=False,id='probe-lifecycle-create',object='probe-mac-lifecycle',parents=[],requires=[],text='SYNTHETIC lifecycle initial',version=1)
EDIT=dict(deleted=False,id='probe-lifecycle-edit',object='probe-mac-lifecycle',parents=['probe-lifecycle-create'],requires=[],text='SYNTHETIC lifecycle edited',version=1)
DELETE=dict(deleted=True,id='probe-lifecycle-delete',object='probe-mac-lifecycle',parents=['probe-lifecycle-edit'],requires=[],text='SYNTHETIC lifecycle deleted intent',version=1)
require=base.require

def verify(raws,results,prior):
 for i,(raw,result) in enumerate(zip(raws,results)):
  expected=dict(id=IDS[i],action=ACTIONS[i])
  if i in (0,2,4):expected['mutation']=[CREATE,EDIT,DELETE][i//2]
  require(json.loads(raw)==expected,'lifecycle exact request')
  require(result['id']==IDS[i] and result['commandDigest']==hashlib.sha256(raw).hexdigest(),'lifecycle digest/id')
  for key in ['dataset','runID','platform','scope','accountFingerprint']: require(result[key]==prior[key],'lifecycle binding '+key)
  require(result['status']=='PASS' and result['halted'] is False and not result.get('errorCode'),'lifecycle status')
  require(set(result['events'])<=base.EVENTS,'lifecycle event allowlist')
  require(re.fullmatch('[0-9a-f]{64}',result['checkpointHash']) is not None,'lifecycle checkpoint')
  mutations=[CREATE] if i<2 else [CREATE,EDIT] if i<4 else [CREATE,DELETE,EDIT]
  envelope=dict(mutations=mutations,object='probe-mac-lifecycle',version=1)
  require(result['snapshot']['envelopes']==[base.ENVELOPE,envelope],'exact mutation history including tombstone')
  require(set(result['snapshot']['images'])=={base.IMAGE_HASH},'unchanged image set')
  require(base64.b64decode(result['snapshot']['images'][base.IMAGE_HASH],validate=True)==base.PNG,'unchanged original PNG')
  head=mutations[-1] if i<4 else DELETE
  projection=dict(candidates=[head['id']],complete=True,state='ready' if i<4 else 'deleted')
  if i<4:projection['preview']=head
  require(result['projections']=={'probe-entry':base.PROJECTION,'probe-mac-lifecycle':projection},'lifecycle exact projection')
  require(result['pendingKeys']==(['object-probe-mac-lifecycle'] if i in (0,2,4) else []),'lifecycle pending')
  if i in (1,3,5):
   previous=results[i-1]['events'];require(result['events'][:len(previous)]==previous,'event prefix retained')
   new=result['events'][len(previous):]
   require({'ACK_EXACT_AND_RESCHEDULED','FETCH_CONTENT_DURABLE','STATE_DURABLE'}<=set(new),'fresh ACK/fetch/state for each sync')
   require(result['snapshot']==results[i-1]['snapshot'],'sync retains exact saved history')
 require(results[5]['checkpointHash']==results[6]['checkpointHash'],'delete checkpoint retained through reopen')
 require(results[6]['events']==['ENGINE_STARTED_DEVELOPMENT_OPT_IN'],'fresh engine after lifecycle reopen')
 require('STATE_DURABLE' in results[7]['events'],'sync state after lifecycle reopen')
 require(results[4]['snapshot']==results[5]['snapshot']==results[6]['snapshot']==results[7]['snapshot'],'deleted history retained through sync/reopen')

def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path('/private/tmp/g1-bridge-20261107-r4'));p.add_argument('--self-test',action='store_true');args=p.parse_args()
 read=lambda kind,ids:[(args.root/kind/(i+'.json')).read_bytes() for i in ids]
 prior_raw=read('results',base.IDS);prior=[json.loads(r) for r in prior_raw];base.verify(read('requests',base.IDS),prior)
 raws=read('requests',IDS);result_raw=read('results',IDS);results=[json.loads(r) for r in result_raw];verify(raws,results,prior[-1])
 print('PASS: all 13 identities/digests/account equality (redacted); eight lifecycle steps preserve original object and PNG.')
 print('PASS: exact create -> edit -> logical-delete ancestry retained; fresh ACK/fetch/state after each save; pending 1,0,1,0,1,0,0,0.')
 print('PASS: deletion remains complete/deleted with original history through Store/Engine reopen and sync; checkpoint retained at reopen.')
 if args.self_test:
  negatives=[('stale ACK',lambda r:r[3].update(events=r[2]['events'])),('lost create',lambda r:r[5]['snapshot']['envelopes'][1]['mutations'].pop(0)),('broken ancestry',lambda r:r[5]['snapshot']['envelopes'][1]['mutations'][1].update(parents=[])),('resurrect projection',lambda r:r[6]['projections']['probe-mac-lifecycle'].update(state='ready')),('changed original PNG',lambda r:r[7]['snapshot']['images'].update({base.IMAGE_HASH:''})),('account mismatch',lambda r:r[7].update(accountFingerprint='0'*64)),('pending retained',lambda r:r[5].update(pendingKeys=['object-probe-mac-lifecycle'])),('reopen checkpoint',lambda r:r[6].update(checkpointHash='0'*64))]
  for name,change in negatives:
   r=copy.deepcopy(results);change(r)
   try:verify(raws,r,prior[-1])
   except AssertionError:pass
   else:raise AssertionError('accepted negative: '+name)
  print('PASS: 8 additional in-memory tampering negative controls rejected.')
 print('LIMIT: one Mac; Store/Engine reopen only; no second client, crash/restart, or cloud-only reconstruction.')
 print(json.dumps({'inputs':[{'id':i,'requestSHA256':hashlib.sha256(q).hexdigest(),'resultSHA256':hashlib.sha256(r).hexdigest()} for i,q,r in zip(IDS,raws,result_raw)]},indent=2))
if __name__=='__main__':main()
