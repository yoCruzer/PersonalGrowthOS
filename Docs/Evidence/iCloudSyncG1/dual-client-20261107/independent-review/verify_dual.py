#!/usr/bin/env python3
"""Independent read-only oracle for the fixed r5 dual-client experiment.
Prints only synthetic identities and checks; never prints account fingerprints or device paths.
"""
import argparse,base64,copy,hashlib,json,re
from pathlib import Path
DATASET='synthetic-g1-20261107-r4';RUN='probe-run-20261107-r5'
PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
IH='6b1048f8a6d40bac0b2954c18fefa40c4ea7a96120fc2e54b7317c0e43c2bbec'
PLAN_DIRS=['plan-connect','plan-connect-retry','plan-003-fetch','plan-004-phone-write','plan-005-conflict','plan-006-resolve']
PIDS=['probe-ios-plan-001-connect','probe-ios-plan-002-connect','probe-ios-plan-003-fetch','probe-ios-plan-004-phone-write','probe-ios-plan-005-conflict','probe-ios-plan-006-resolve']
MACTIONS=['connect','snapshot','sync','sync','snapshot','save','sync','sync','snapshot','sync','sync','reopen','snapshot','stop']
MIDS=['probe-mac-r5-%03d-%s'%(n,a if n!=6 else 'save-conflict') for n,a in enumerate(MACTIONS,1)]
PACTIONS=[['connect'],['connect'],['connect','sync','sync','snapshot'],['connect','save','sync','sync','reopen','sync','snapshot'],['connect','save','sync','sync','snapshot'],['connect','sync','snapshot','save','sync','sync','reopen','snapshot']]
def digest(b):return hashlib.sha256(b).hexdigest()
def canonical(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def check(ok,label):
 if not ok:raise AssertionError(label)
def scrub(x):
 if isinstance(x,dict):return {k:scrub(v) for k,v in x.items() if k!='accountFingerprint'}
 if isinstance(x,list):return [scrub(v) for v in x]
 return x

def mutation(id,obj,text,parents=(),deleted=False,image=False):
 m=dict(deleted=deleted,id=id,object=obj,parents=list(parents),requires=[],text=text,version=1)
 if image:m.update(imageHash=IH,imageBytes=68)
 return m
BASE=mutation('probe-base-mac-001','probe-entry','SYNTHETIC G1 Mac initial text and original PNG',image=True)
LC=mutation('probe-lifecycle-create','probe-mac-lifecycle','SYNTHETIC lifecycle initial')
LE=mutation('probe-lifecycle-edit','probe-mac-lifecycle','SYNTHETIC lifecycle edited',[LC['id']])
LD=mutation('probe-lifecycle-delete','probe-mac-lifecycle','SYNTHETIC lifecycle deleted intent',[LE['id']],True)
IC=mutation('probe-ios-create-001','probe-ios-roundtrip','SYNTHETIC iPhone reverse roundtrip with original PNG',image=True)
IB=mutation('probe-conflict-ios-001','probe-ios-roundtrip','SYNTHETIC concurrent iPhone edit',[IC['id']],image=True)
MB=mutation('probe-conflict-mac-001','probe-ios-roundtrip','SYNTHETIC concurrent Mac edit',[IC['id']],image=True)
RES=mutation('probe-conflict-resolve-001','probe-ios-roundtrip','SYNTHETIC resolution retains both concurrent edits in history',[IB['id'],MB['id']],image=True)
STAGES={'empty':[],'base':[BASE,LC,LE,LD],'roundtrip':[BASE,LC,LE,LD,IC],'iosbranch':[BASE,LC,LE,LD,IC,IB],'macbranch':[BASE,LC,LE,LD,IC,MB],'both':[BASE,LC,LE,LD,IC,IB,MB],'resolved':[BASE,LC,LE,LD,IC,IB,MB,RES]}
PSTAGES=[['fail'],['empty'],['empty','base','base','base'],['base']+['roundtrip']*6,['roundtrip']+['iosbranch']*4,['iosbranch','both','both']+['resolved']*5]
MSTAGES=['base','base','roundtrip','roundtrip','roundtrip','macbranch','fail','both','both']+['resolved']*5

def oracle(stage):
 rows=STAGES[stage];objects=sorted({m['object'] for m in rows})
 envs=[dict(object=o,version=1,mutations=sorted([m for m in rows if m['object']==o],key=lambda m:m['id'])) for o in objects]
 images={IH:base64.b64encode(PNG).decode()} if rows else {}
 projections={}
 for o in objects:
  ms=[m for m in rows if m['object']==o];parents={v for m in ms for v in m['parents']};heads=sorted([m for m in ms if m['id'] not in parents],key=lambda m:m['id'])
  if len(heads)==2:
   check(heads==[IB,MB],'oracle conflict heads');projections[o]=dict(state='conflict',candidates=[IB['id'],MB['id']],preview=IC,complete=False)
  else:
   check(len(heads)==1,'oracle single head');h=heads[0];p=dict(state='deleted' if h['deleted'] else 'ready',candidates=[h['id']],complete=True)
   if not h['deleted']:p['preview']=h
   projections[o]=p
 return dict(envelopes=envs,images=images),projections

def load_bundle(root):
 source=Path('/private/tmp/g1-ios-export-r5-all');plans=Path('/private/tmp/g1-manual-install-20261107');mac=Path('/private/tmp/g1-bridge-20261107-r5')
 b={'planraw':[],'iosraw':[],'ios':[],'macraw':[],'mac':[],'publicios':[],'publicmac':[],'publicplanraw':[],'publicmacraw':[],'baseline':json.loads(Path('/private/tmp/g1-bridge-20261107-r4/results/probe-013-mac-lifecycle-sync-after-reopen.json').read_bytes())}
 for directory,id in zip(PLAN_DIRS,PIDS):
  matches=list(source.rglob('SyncLab-Manual-'+id+'.json'));check(len(matches)==1,'unique exported report')
  raw=matches[0].read_bytes();b['iosraw'].append(raw);b['ios'].append(json.loads(raw));b['planraw'].append((plans/directory/'SyncLab-Probe-Plan.json').read_bytes())
  b['publicios'].append(json.loads((root/('SyncLab-Manual-'+id+'.json')).read_bytes()));b['publicplanraw'].append((root/(id+'.request.json')).read_bytes())
 for id in MIDS:
  raw=(mac/'results'/(id+'.json')).read_bytes();b['mac'].append(json.loads(raw));b['macraw'].append((mac/'requests'/(id+'.json')).read_bytes())
  b['publicmac'].append(json.loads((root/(id+'.json')).read_bytes()));b['publicmacraw'].append((root/(id+'.request.json')).read_bytes())
 return b

def verify(b):
 check(len(PNG)==68 and digest(PNG)==IH,'reference PNG')
 check((b['baseline']['snapshot'],b['baseline']['projections'])==oracle('base'),'prior r4 exact baseline')
 fingerprints=[];allresults=[]
 for i,(raw,report) in enumerate(zip(b['planraw'],b['ios'])):
  plan=json.loads(raw);check(raw==b['publicplanraw'][i],'public plan raw bytes unchanged');check(scrub(report)==b['publicios'][i],'public iOS copy removes fingerprints only')
  check(plan['id']==PIDS[i] and plan['version']==1 and plan['dataset']==DATASET and plan['runID']==RUN,'plan identity')
  check(report['planID']==PIDS[i] and report['dataset']==DATASET and report['runID']==RUN and report['planDigest']==digest(raw),'plan digest/result binding')
  check(report['scope']=='Command execution only; not cloud convergence or G1 acceptance','plan completion scope')
  check(len(report['results'])==len(PACTIONS[i])==len(plan['commands']),'exact command sequence length')
  check(report['completedAllCommands'] is (i!=0),'preserve first iOS failure')
  check(report.get('errorCode')==('CK_3' if i==0 else None),'iOS plan error preservation')
  for j,(cmd,result) in enumerate(zip(plan['commands'],report['results'])):
   expectedid='probe-ios-%03d-connect'%(i+1) if i<2 else 'probe-ios-%03d-%d-%s'%(i+1,j+1,PACTIONS[i][j])
   expected=dict(id=expectedid,action=PACTIONS[i][j])
   if expected['action']=='save':expected['mutation']={3:IC,4:IB,5:RES}[i]
   check(cmd==expected,'fixed iOS command contents')
   check(result['id']==cmd['id'] and result.get('planID')==PIDS[i] and result['commandDigest']==digest(canonical(cmd)),'iOS command canonical digest/plan/order')
   allresults.append((result,PSTAGES[i][j],'iOS',i==0))
 for i,(raw,result) in enumerate(zip(b['macraw'],b['mac'])):
  check(raw==b['publicmacraw'][i],'public Mac request raw bytes unchanged');check(scrub(result)==b['publicmac'][i],'public Mac copy removes fingerprints only')
  expected=dict(id=MIDS[i],action=MACTIONS[i]);
  if i==5:expected['mutation']=MB
  check(json.loads(raw)==expected,'fixed Mac command contents')
  check(result['id']==MIDS[i] and result['commandDigest']==digest(raw) and result.get('planID') is None,'Mac raw digest binding')
  allresults.append((result,MSTAGES[i],'macOS',i==6))
 for result,stage,platform,failure in allresults:
  check(result['dataset']==DATASET and result['runID']==RUN and result['platform']==platform,'result run/dataset/platform')
  check(result['scope']=='Command execution only; not a cloud convergence or G1 acceptance verdict','command completion scope')
  check(result['halted'] is False,'no fenced runtime')
  check(result['status']==('FAIL' if failure else 'PASS'),'preserved command status')
  check(result.get('errorCode')==(('CK_3' if platform=='iOS' else 'CK_2') if failure else None),'preserved command error')
  fp=result.get('accountFingerprint')
  if platform=='iOS' and failure:check(fp is None,'first iOS failure has no asserted account')
  else:check(isinstance(fp,str) and re.fullmatch('[0-9a-f]{64}',fp),'account fingerprint shape');fingerprints.append(fp)
  if failure:
   check(all(result.get(k) is None for k in ['snapshot','projections','pendingKeys','checkpointHash']),'failure does not invent snapshot/queue/checkpoint')
   continue
  check((result['snapshot'],result['projections'])==oracle(stage),'exact facts/projection stage '+result['id'])
  for key,image in result['snapshot']['images'].items():
   data=base64.b64decode(image,validate=True);check(data==PNG and digest(data)==key and len(data)==68,'original image bytes/hash/size')
  shouldpending=[]
  if result['id'] in ['probe-ios-004-2-save','probe-ios-005-2-save','probe-ios-006-4-save','probe-mac-r5-006-save-conflict']:shouldpending=['object-probe-ios-roundtrip']
  check(result['pendingKeys']==shouldpending,'exact pending transition')
 check(len(fingerprints)==39 and len(set(fingerprints))==1,'39 same-run account fingerprints equal, values withheld')
 ios=b['ios'];mac=b['mac']
 check(ios[0]['results'][0]['events']==[],'first iOS failure precedes engine')
 check(ios[2]['results'][0]['snapshot']==oracle('empty')[0],'iOS empty prefetch snapshot')
 check('FETCH_CONTENT_DURABLE' in ios[2]['results'][1]['events'],'actual SDK fetch event after empty snapshot')
 check(ios[2]['results'][-1]['snapshot']==b['baseline']['snapshot'],'empty-store fetch recovers exact r4 baseline')
 check(ios[3]['results'][-1]['snapshot']==mac[4]['snapshot'],'reverse roundtrip exact convergence')
 for p,save,sync in [(ios[3],1,2),(ios[4],1,2),(ios[5],3,4)]:
  prev=p['results'][save]['events'];current=p['results'][sync]['events'];check(current[:len(prev)]==prev,'event prefix')
  check({'ACK_EXACT_AND_RESCHEDULED','STATE_DURABLE'}<=set(current[len(prev):]),'fresh iOS ACK/state after save')
 prior=mac[5]['events'];failed=mac[6]['events'];retried=mac[7]['events']
 check(failed[:len(prior)]==prior and 'SERVER_RECORD_CHANGED_MERGED' in failed[len(prior):],'fresh actual serverRecordChanged during preserved FAIL')
 check(retried[:len(failed)]==failed and {'ACK_EXACT_AND_RESCHEDULED','FETCH_CONTENT_DURABLE','STATE_DURABLE'}<=set(retried[len(failed):]),'successful retry fresh ACK/fetch/state')
 check((ios[5]['results'][2]['snapshot'],ios[5]['results'][2]['projections'])==(mac[8]['snapshot'],mac[8]['projections']),'both clients same two-head conflict and common ancestor preview')
 check((ios[5]['results'][-1]['snapshot'],ios[5]['results'][-1]['projections'])==(mac[12]['snapshot'],mac[12]['projections']),'final phone006 equals Mac013 full history and projection')
 for before,after in [(ios[3]['results'][3],ios[3]['results'][4]),(ios[5]['results'][5],ios[5]['results'][6]),(mac[10],mac[11])]:
  check(before['checkpointHash']==after['checkpointHash'] and before['snapshot']==after['snapshot'] and before['projections']==after['projections'],'same-process store/engine reopen retains checkpoint and content')
  check(after['events']==['ENGINE_STARTED_DEVELOPMENT_OPT_IN'],'reopen has fresh driver event history')
 check(mac[13]['snapshot']==mac[12]['snapshot'] and mac[13]['projections']==mac[12]['projections'] and mac[13]['events']==[],'Mac stop preserves data and drops driver events')
 return len(allresults)

def main():
 p=argparse.ArgumentParser();p.add_argument('--public-root',type=Path,default=Path('/private/tmp/PersonalGrowthOS-icloud-g1/Docs/Evidence/iCloudSyncG1/dual-client-20261107'));p.add_argument('--self-test',action='store_true');args=p.parse_args();b=load_bundle(args.public_root);n=verify(b)
 print('PASS: 6 raw iOS plans/reports, 26 iOS results, 14 Mac request/results; all digests/identities/order and public redactions exact.')
 print('PASS: 39 available same-run account fingerprints agree; first iOS CK_3 has none. No fingerprint printed or persisted.')
 print('PASS: empty-store iOS fetch equals r4 baseline; reverse creation; sibling conflict, common ancestor preview, explicit resolution, full history/PNG equality; final iOS006 = Mac013.')
 print('PASS: iOS001 FAIL CK_3 and Mac007 FAIL CK_2 preserved; Mac008 retry adds fresh ACK/fetch; same-process checkpoint reopen and Mac014 stop retain content.')
 if args.self_test:
  negatives=[('plan digest',lambda x:x['ios'][2].update(planDigest='0'*64)),('command digest',lambda x:x['ios'][3]['results'][1].update(commandDigest='0'*64)),('Mac digest',lambda x:x['mac'][5].update(commandDigest='0'*64)),('account mismatch',lambda x:x['mac'][12].update(accountFingerprint='0'*64)),('plan result identity',lambda x:x['ios'][5]['results'][0].update(planID=PIDS[4])),('result order',lambda x:x['ios'][5]['results'].reverse()),('empty store claim',lambda x:x['ios'][2]['results'][0].update(snapshot=oracle('base')[0])),('baseline lost',lambda x:x['ios'][2]['results'][1]['snapshot']['envelopes'].pop()),('reverse creation lost',lambda x:x['mac'][4]['snapshot']['envelopes'].pop(1)),('Mac failure rewritten',lambda x:x['mac'][6].update(status='PASS',errorCode=None)),('phone failure rewritten',lambda x:x['ios'][0].update(completedAllCommands=True,errorCode=None)),('missing real conflict',lambda x:x['mac'][6].update(events=[e for e in x['mac'][6]['events'] if e!='SERVER_RECORD_CHANGED_MERGED'])),('stale retry ACK',lambda x:x['mac'][7].update(events=x['mac'][6]['events'])),('lost conflict branch',lambda x:x['mac'][8]['snapshot']['envelopes'][1]['mutations'].pop()),('wrong common ancestor',lambda x:x['mac'][8]['projections']['probe-ios-roundtrip'].update(preview=IB)),('conflict marked complete',lambda x:x['mac'][8]['projections']['probe-ios-roundtrip'].update(complete=True)),('resolution parent lost',lambda x:x['ios'][5]['results'][-1]['snapshot']['envelopes'][1]['mutations'][2]['parents'].pop()),('final PNG changed',lambda x:x['mac'][12]['snapshot']['images'].update({IH:base64.b64encode(b'wrong').decode()})),('final duplicate',lambda x:x['mac'][12]['snapshot']['envelopes'][1]['mutations'].append(RES)),('pending remaining',lambda x:x['mac'][7].update(pendingKeys=['object-probe-ios-roundtrip'])),('reopen checkpoint changed',lambda x:x['mac'][11].update(checkpointHash='0'*64)),('stop data loss',lambda x:x['mac'][13]['snapshot']['envelopes'].pop())]
  for label,change in negatives:
   altered=copy.deepcopy(b);change(altered);altered['publicios']=[scrub(r) for r in altered['ios']];altered['publicmac']=[scrub(r) for r in altered['mac']]
   try:verify(altered)
   except AssertionError:pass
   else:raise AssertionError('negative accepted: '+label)
  altered=copy.deepcopy(b);altered['publicmac'][12]['status']='FAIL'
  try:verify(altered)
  except AssertionError:pass
  else:raise AssertionError('public copy corruption accepted')
  print('PASS: 23 in-memory tampering negative controls rejected (public-copy consistency bypassed for substantive controls).')
 manifest={'ios':[dict(planID=id,requestSHA256=digest(q),resultSHA256=digest(r)) for id,q,r in zip(PIDS,b['planraw'],b['iosraw'])], 'mac':[dict(id=id,requestSHA256=digest(q),resultSHA256=digest((Path('/private/tmp/g1-bridge-20261107-r5/results')/(id+'.json')).read_bytes())) for id,q in zip(MIDS,b['macraw'])]}
 print(json.dumps(manifest,indent=2))
 print('LIMIT: bounded real dual-client scenario; not complete G1, process crash/restart, offline-reconnect, production environment, restore race or actual account switching. Bridge shutdown status is parent-reported, not proven by stop JSON.')
if __name__=='__main__':main()
