import base64,copy,hashlib,json,os,pathlib,stat,struct,subprocess,tempfile,zlib
ROOT=pathlib.Path('/private/tmp/g1-next-batch-review');BIN=ROOT/'build-fixed/debug/LabReplay'
PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQT7z8HwAEKQJLn6egIAAAAABJRU5ErkJggg==')
OLD=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
HASH=hashlib.sha256(PNG).hexdigest();D='synthetic-g1-independent-cli';R='probe-independent-cli'
STAGES=['01-mac-seed','02-ios-repair','03-mac-fetch']
MUTS=[('deleted-live','deleted',[],[],False),('deleted-tombstone','deleted',['deleted-live'],[],True),('deleted-child','deleted-child',[],['deleted'],False),('missing-new','missing',['missing-parent'],[],False),('trans-mid','trans-mid',[],['trans-leaf'],False),('trans-root','trans-root',[],['trans-mid'],False),('dep-a','dep-a',[],['dep-b'],False),('dep-b','dep-b',[],['dep-a'],False),('head-old','head',[],[],False),('head-new','head',['head-old'],['head-dependency'],False),('cause-a','cause',['cause-b'],[],False),('cause-b','cause',['cause-a'],[],False),('missing-parent','missing',[],[],False),('trans-leaf','trans-leaf',[],[],False),('head-dependency','head-dependency',[],[],False),('new-image','new-image',[],[],False)]
def pngcheck(p):
 assert p[:8]==b'\x89PNG\r\n\x1a\n';pos=8;chunks=[]
 while pos<len(p):
  n=struct.unpack('>I',p[pos:pos+4])[0];kind=p[pos+4:pos+8];data=p[pos+8:pos+8+n];crc=struct.unpack('>I',p[pos+8+n:pos+12+n])[0];assert zlib.crc32(kind+data)&0xffffffff==crc
  chunks.append((kind,data));pos+=n+12
 assert pos==len(p) and chunks[-1]==(b'IEND',b'')
 assert struct.unpack('>IIBBBBB',chunks[0][1])==(1,1,8,6,0,0,0)
 assert len(zlib.decompress(b''.join(data for kind,data in chunks if kind==b'IDAT')))==5

def plan_id(stage):return 'probe-'+stage[:2]+'-'+hashlib.sha256((D+'|'+R+'|'+stage).encode()).hexdigest()

def validate(plans):
 assert len(plans)==3
 assert [len(p['commands']) for p in plans]==[16,10,4]
 ids=[];seen=[]
 actions=[['connect']+['save']*12+['sync','sync','snapshot'],['connect','sync','snapshot']+['save']*4+['sync','sync','snapshot'],['connect','sync','sync','snapshot']]
 for stage,plan,action in zip(STAGES,plans,actions):
  assert plan['id']==plan_id(stage) and plan['version']==1 and plan['dataset']==D and plan['runID']==R
  assert [c['action'] for c in plan['commands']]==action
  ids.extend(c['id'] for c in plan['commands']);seen.extend(c['mutation'] for c in plan['commands'] if c['action']=='save')
 assert len(set(ids))==30
 for actual,(id,obj,parents,requires,deleted) in zip(seen,MUTS):
  expected=dict(id='probe-batch-'+id,object='probe-batch-'+obj,parents=['probe-batch-'+v for v in parents],requires=['probe-batch-'+v for v in requires],deleted=deleted,text='SYNTHETIC batch '+id,version=1)
  if id=='new-image':expected.update(imageHash=HASH,imageBytes=len(PNG))
  assert actual==expected
 assert HASH!=hashlib.sha256(OLD).hexdigest()
 pngcheck(PNG)

with tempfile.TemporaryDirectory(prefix='g1-batch-cli-review-') as tmp:
 output=pathlib.Path(tmp)/'new';cmd=[str(BIN),'prepare-batch',str(output),D,R]
 previous=os.umask(0)
 try:result=subprocess.run(cmd,capture_output=True,check=True)
 finally:os.umask(previous)
 assert 'no app launch or cloud operations' in result.stdout.decode()
 assert stat.S_IMODE(output.stat().st_mode)==0o700
 files=sorted(output.rglob('*'));assert len(files)==6 and all(p.is_dir() or p.name=='SyncLab-Probe-Plan.json' for p in files)
 raw=[(output/plan_id(s)/'SyncLab-Probe-Plan.json').read_bytes() for s in STAGES];plans=[json.loads(x) for x in raw];validate(plans)
 assert subprocess.run(cmd,capture_output=True).returncode!=0
 assert [(output/plan_id(s)/'SyncLab-Probe-Plan.json').read_bytes() for s in STAGES]==raw
 negatives=[lambda p:p[1]['commands'].pop(2),lambda p:p[1]['commands'].reverse(),lambda p:p[0]['commands'][4]['mutation'].update(parents=[]),lambda p:p[0]['commands'][10]['mutation'].update(parents=[]),lambda p:p[0]['commands'][3]['mutation'].update(requires=[]),lambda p:p[0]['commands'][2]['mutation'].update(deleted=False),lambda p:p[0]['commands'][6]['mutation'].update(requires=[]),lambda p:p[0]['commands'][12]['mutation'].update(parents=[]),lambda p:p[1]['commands'][6]['mutation'].update(imageHash=hashlib.sha256(OLD).hexdigest()),lambda p:p[1]['commands'][6]['mutation'].update(imageBytes=999),lambda p:p[0]['commands'][1]['mutation'].update(imageHash=HASH,imageBytes=len(PNG)),lambda p:p[2].update(runID='probe-wrong'),lambda p:p[2]['commands'][0].update(id=p[0]['commands'][0]['id'])]
 for modify in negatives:
  changed=copy.deepcopy(plans);modify(changed)
  try:validate(changed)
  except AssertionError:pass
  else:raise AssertionError('mutated plan accepted')
 bad=bytearray(PNG);bad[40]^=1
 try:pngcheck(bytes(bad))
 except AssertionError:pass
 else:raise AssertionError('corrupted PNG accepted')
 print('PASS: actual Debug CLI creates only three fixed plans, root700 even umask000; existing output refused without changing bytes.')
 print('PASS: independent exact action/edge/deletion/image oracle; second PNG all chunk CRCs, IHDR and decompression valid; 14 tampering controls rejected.')
 print('SECOND_PNG',len(PNG),HASH)
 print(json.dumps({s:hashlib.sha256(r).hexdigest() for s,r in zip(STAGES,raw)},indent=2))
