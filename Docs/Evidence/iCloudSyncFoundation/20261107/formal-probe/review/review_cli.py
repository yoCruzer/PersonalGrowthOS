#!/usr/bin/env python3
"""Independent black-box checks, synthetic inputs only; never invokes network."""
import hashlib, json, pathlib, shutil, struct, subprocess, sys, zlib

binary = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(sys.argv[2]).resolve()
root.mkdir(exist_ok=False)
results = []
def sha(data): return hashlib.sha256(data).hexdigest()
def call(name, args, expected):
    p = subprocess.run([str(binary), *map(str, args)], capture_output=True)
    (root/(name+'.stdout')).write_bytes(p.stdout)
    (root/(name+'.stderr')).write_bytes(p.stderr)
    assert p.returncode == expected, (name, p.returncode, p.stdout, p.stderr)
    results.append({'name':name, 'exit':p.returncode})
    return p
def digest(directory): return (directory/'plan.sha256').read_text().strip()
def snapshot(directory):
    return {str(p.relative_to(directory)): sha(p.read_bytes()) for p in directory.rglob('*') if p.is_file()}

plan = root/'plan'
call('plan', ['plan', plan], 0)
before = snapshot(plan)
p = json.loads((plan/'plan.json').read_bytes())
assert p['container'] == 'iCloud.com.yocruzer.PersonalGrowthOS'
assert p['environment'] == 'Development'
assert p['schemaSHA256'] == '6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003'
assert len(p['records']) == 6 and len({r['recordName'] for r in p['records']}) == 6
assert {r['recordType'] for r in p['records']} == {'PGMutationV2','PGPayloadChunkV2','PGOriginalV2'}
assert sha((plan/'plan.json').read_bytes()) == digest(plan)
for r in p['records']:
    b=(plan/r['file']).read_bytes()
    assert len(b)==r['byteCount'] and sha(b)==r['sha256']
manifests=[json.loads((plan/f'{x}.manifest').read_bytes()) for x in ['create','edit','tombstone']]
assert manifests[1]['parents']==[manifests[0]['mutation']]
assert manifests[2]['parents']==[manifests[1]['mutation']]
assert manifests[2]['deleted'] and not manifests[2]['originals']
assert json.loads((plan/'create.payload').read_bytes()) == {'synthetic':True,'text':'Formal Development create 原始文字'}
assert json.loads((plan/'edit.payload').read_bytes()) == {'synthetic':True,'text':'Formal Development edit 后续修改'}

second=root/'plan2'
call('fresh-plan', ['plan',second],0)
p2=json.loads((second/'plan.json').read_bytes())
assert p['run']!=p2['run'] and p['dataset']!=p2['dataset'] and digest(plan)!=digest(second)
call('replay',['replay',plan,digest(plan),root/'replay'],0)
report=json.loads((root/'replay/report.json').read_bytes())
assert report['mode']=='OFFLINE_ONLY' and report['status']=='OFFLINE_PASS'
assert report['networkOperations']==0 and report['serverSchemaChecked'] is False and report['p0Passed'] is False
assert report['planSHA256']==digest(plan) and len(report['commands'])==6
assert all(x['status']=='OFFLINE_PASS' for x in report['commands'])
assert snapshot(plan)==before
call('existing-plan',['plan',plan],2)
assert snapshot(plan)==before
replay_before=snapshot(root/'replay')
call('existing-report',['replay',plan,digest(plan),root/'replay'],2)
assert snapshot(root/'replay')==replay_before
call('wrong-expected',['replay',plan,'0'*64,root/'bad-expected'],2)

def changed(name, mutation, rehash=False):
    d=root/name; shutil.copytree(plan,d); mutation(d)
    if rehash: (d/'plan.sha256').write_text(sha((d/'plan.json').read_bytes())+'\n')
    call(name,['replay',d,digest(d),root/(name+'-report')],2)
    r=json.loads((root/(name+'-report/report.json')).read_bytes())
    assert r['status']=='OFFLINE_FAIL' and r['p0Passed'] is False and r['networkOperations']==0
def json_change(d,key,value):
    q=json.loads((d/'plan.json').read_bytes()); q[key]=value
    (d/'plan.json').write_text(json.dumps(q,ensure_ascii=False,separators=(',',':'),sort_keys=True))
changed('changed-payload',lambda d:(d/'create.payload').write_bytes(b'not the synthetic fixture'))
changed('missing-original',lambda d:(d/'original.png').unlink())
changed('extra-file',lambda d:(d/'extra.txt').write_text('synthetic'))
changed('production-plan',lambda d:json_change(d,'environment','Production'),True)
changed('container-plan',lambda d:json_change(d,'container','iCloud.synthetic.wrong'),True)
changed('schema-plan',lambda d:json_change(d,'schemaSHA256','0'*64),True)
changed('version-plan',lambda d:json_change(d,'version',999),True)
def link_file(d):
    (d/'original.png').unlink(); (d/'original.png').symlink_to(plan/'original.png')
changed('leaf-symlink',link_file)
def escape(d):
    q=json.loads((d/'plan.json').read_bytes()); q['records'][0]['file']='../plan/original.png'
    (d/'plan.json').write_text(json.dumps(q,ensure_ascii=False,separators=(',',':'),sort_keys=True))
changed('escape-plan',escape,True)
def records_change(d, variant):
    q=json.loads((d/'plan.json').read_bytes())
    if variant=='duplicate': q['records'].append(q['records'][0])
    if variant=='missing': q['records'].pop()
    if variant=='reorder': q['records'][0],q['records'][1]=q['records'][1],q['records'][0]
    (d/'plan.json').write_text(json.dumps(q,ensure_ascii=False,separators=(',',':'),sort_keys=True))
for variant in ['duplicate','missing','reorder']:
    changed(variant+'-record',lambda d,v=variant:records_change(d,v),True)
linked=root/'linked'; linked.symlink_to(plan,target_is_directory=True)
call('root-symlink',['replay',linked,digest(plan),root/'linked-report'],2)
ancestor=root/'ancestor'; ancestor.symlink_to(root,target_is_directory=True)
call('ancestor-symlink',['replay',ancestor/'plan',digest(plan),root/'ancestor-report'],2)
call('output-symlink-ancestor',['plan',ancestor/'must-not-create'],2)
assert not (root/'must-not-create').exists()

call('preflight-actual-unqualified',['preflight',plan,digest(plan),binary,root/'preflight'],2)
preflight=json.loads((root/'preflight/report.json').read_bytes())
assert preflight['status']=='NOT_READY' and preflight['rejectionCodes']
assert preflight['networkOperations']==0 and preflight['p0Passed'] is False and preflight['readyForCloudRun'] is False
assert preflight['networkAuthorized'] is False and preflight['actualServiceAccess']=='NOT_RUN'
assert preflight['certificateProfileDeviceEligibility']=='NOT_VERIFIED'
assert preflight['mode']=='OFFLINE_ONLY' and preflight['operation']=='READ_ONLY_PREFLIGHT'

png=(plan/'original.png').read_bytes()
assert png[:8]==b'\x89PNG\r\n\x1a\n'
offset=8; chunks=[]; idat=b''
while offset<len(png):
    size=struct.unpack('>I',png[offset:offset+4])[0]
    kind=png[offset+4:offset+8]; data=png[offset+8:offset+8+size]
    crc=struct.unpack('>I',png[offset+8+size:offset+12+size])[0]
    assert zlib.crc32(kind+data)&0xffffffff==crc
    chunks.append(kind)
    if kind==b'IDAT': idat+=data
    if kind==b'IHDR': assert struct.unpack('>II',data[:8])==(1,1)
    offset+=12+size
assert offset==len(png) and chunks[0]==b'IHDR' and chunks[-1]==b'IEND' and zlib.decompress(idat)
assert snapshot(plan)==before
summary={'status':'PASS','binary_sha256':sha(binary.read_bytes()),'commands':results,'command_count':len(results),'original_png_sha256':sha(png),'plan_sha256':digest(plan),'source_unchanged':True,'networkOperations':0,'p0Passed':False}
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
