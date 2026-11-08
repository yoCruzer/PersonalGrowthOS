#!/usr/bin/env python3
"""Independent checks using an original synthetic schema, never an Owner export."""
import hashlib, importlib.util, json, os, pathlib, subprocess, sys

audit=pathlib.Path(sys.argv[1]).resolve(); candidate=pathlib.Path(sys.argv[2]).resolve()
root=pathlib.Path(sys.argv[3]).resolve();root.mkdir(exist_ok=False)
base='''DEFINE SCHEMA
    RECORD TYPE ReviewFixture (
        displayLabel STRING,
        sampleValue DOUBLE,
        syntheticTags LIST<STRING>,
        GRANT READ TO "ReviewObservers",
        GRANT WRITE TO "ReviewEditors"
    );
'''
sha=lambda b:hashlib.sha256(b).hexdigest()
candidate_sha=sha(candidate.read_bytes()); results=[]
def run(name, text=base, expected=0, devhash=None, candidate_file=candidate, candidate_hash=candidate_sha):
    d=root/name;d.mkdir();dev=d/'development.ckdb';prod=d/'production.ckdb'
    dev.write_bytes(text.encode());prod.write_bytes(base.encode())
    args=[sys.executable,str(audit),'--development',str(dev),'--development-sha256',devhash or sha(dev.read_bytes()),'--production',str(prod),'--production-sha256',sha(prod.read_bytes()),'--candidate',str(candidate_file),'--candidate-sha256',candidate_hash,'--output',str(d/'report.json')]
    p=subprocess.run(args,capture_output=True);(d/'stdout.txt').write_bytes(p.stdout);(d/'stderr.txt').write_bytes(p.stderr)
    assert p.returncode==expected,(name,p.returncode,p.stderr)
    results.append({'case':name,'exit':p.returncode})
    assert dev.read_bytes()==text.encode() and prod.read_bytes()==base.encode()
    if expected: assert not (d/'report.json').exists();return
    report=json.loads((d/'report.json').read_bytes())
    assert report['status']=='REVIEW_ONLY_NOT_DEPLOYABLE' and report['deployable'] is False
    assert report['gatesPassed']=={'P0':False,'P1':False,'P2':False} and report['networkOperations']==0
    assert report['candidate']['permissionsCopiedFromUsers'] is False
    assert report['candidate']['customPermissions']=='NOT_SPECIFIED'
    assert report['sourceBinding']['team'] is None and report['sourceBinding']['container'] is None
    return report,args

r,args=run('baseline')
assert r['developmentProduction']=={'byteIdentical':True,'structureIdentical':True}
assert r['development']['diff']['counts']['missingRecordTypes']==3
assert r['development']['diff']['counts']['missingFields']==11
assert r['development']['observedSchema']['ReviewFixture']['fields']=={'displayLabel':'STRING','sampleValue':'DOUBLE','syntheticTags':'LIST<STRING>'}
assert r['development']['diff']['users'] is None
assert r['development']['diff']['observedGrantsByType']['ReviewFixture']==[{'permission':'READ','role':'ReviewObservers'},{'permission':'WRITE','role':'ReviewEditors'}]
original=(root/'baseline/report.json').read_bytes()
p=subprocess.run(args,capture_output=True);assert p.returncode==2 and (root/'baseline/report.json').read_bytes()==original
results.append({'case':'existing-output-unchanged','exit':p.returncode})
run('wrong-source-hash',devhash='0'*64,expected=2)
for name,text in {
 'unknown-type':base.replace('LIST<STRING>','FUTURE_TYPE'),
 'unknown-system-field':base.replace('displayLabel STRING','"___syntheticUnknown" STRING'),
 'unknown-permission':base.replace('GRANT WRITE','GRANT DELETE'),
 'duplicate-grant':base.replace('GRANT READ TO "ReviewObservers"','GRANT READ TO "ReviewObservers", GRANT READ TO "ReviewObservers"'),
 'duplicate-field':base.replace('displayLabel STRING','displayLabel STRING, displayLabel DOUBLE'),
 'duplicate-record':base+' RECORD TYPE ReviewFixture (otherLabel STRING);',
 'second-schema':base+' DEFINE SCHEMA RECORD TYPE New (text STRING);',
 'trailing-token':base+' IGNORED',
 'unknown-index':base.replace('sampleValue DOUBLE','sampleValue DOUBLE QUERYABLE'),
 'comment-injection':base+' /* hidden */',
}.items():run(name,text,2)
r,_=run('extra-type-preserved',base+' RECORD TYPE ExtraSynthetic (value STRING, GRANT READ TO "ExtraReviewRole");')
assert r['development']['diff']['extraRecordTypes']==['ExtraSynthetic','ReviewFixture']
assert r['development']['observedSchema']['ExtraSynthetic']['fields']=={'value':'STRING'}
assert r['development']['diff']['observedGrantsByType']['ExtraSynthetic']==[{'permission':'READ','role':'ExtraReviewRole'}]
r,_=run('candidate-conflict-preserved',base+' RECORD TYPE PGMutationV2 (manifest STRING, sha256 STRING, wireVersion INT64, extra INT64, GRANT READ TO "CandidateReviewRole");')
assert r['development']['diff']['fieldTypeMismatches']==[{'recordType':'PGMutationV2','field':'manifest','candidateType':'BYTES','observedType':'STRING'}]
assert r['development']['diff']['extraFieldsOnCandidateTypes']==[{'recordType':'PGMutationV2','field':'extra','observedType':'INT64'}]
assert r['development']['diff']['observedGrantsByType']['PGMutationV2']==[{'permission':'READ','role':'CandidateReviewRole'}]
r,_=run('changed-grants-preserved',base.replace('GRANT READ TO "ReviewObservers"','GRANT READ TO "ReviewEditors"'))
assert r['developmentProduction']['structureIdentical'] is False
r,_=run('wrong-system-type-reported',base+' RECORD TYPE SystemTypeProbe ("___etag" INT64);')
assert r['development']['diff']['systemFieldTypeMismatches']==[{'recordType':'SystemTypeProbe','field':'___etag','observedType':'INT64','knownSystemType':'STRING'}]
altered=root/'changed-candidate.json';q=json.loads(candidate.read_bytes());q['wireVersion']=99;altered.write_text(json.dumps(q))
run('changed-candidate',candidate_file=altered,candidate_hash=sha(altered.read_bytes()),expected=2)
link=root/'candidate-link';link.symlink_to(candidate)
run('candidate-symlink',candidate_file=link,expected=2)

# Deterministic independent reproduction of output-ancestor replacement at fsync.
spec=importlib.util.spec_from_file_location('reviewed_audit',audit);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
parent=root/'output-parent';parent.mkdir();output=parent/'report.json';original_fsync=module.os.fsync;swapped=[False]
def swap(fd):
    original_fsync(fd)
    if not swapped[0]:swapped[0]=True;parent.rename(root/'renamed-parent');parent.mkdir()
module.os.fsync=swap
error=None
try:module.write_new(str(output),{'synthetic':'only'})
except Exception as exc:error=type(exc).__name__+': '+str(exc)
finally:module.os.fsync=original_fsync
assert error is not None and not output.exists() and (root/'renamed-parent/report.json').exists()
results.append({'case':'output-ancestor-replacement','rejected':True,'error':error})
summary={'fixtureOrigin':'ORIGINAL_SYNTHETIC_REVIEW_FIXTURE_NOT_OWNER_EXPORT','status':'PASS','checks':results,'count':len(results),'audit_sha256':sha(audit.read_bytes()),'candidate_sha256':candidate_sha,'networkOperations':0,'p0Passed':False}
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
